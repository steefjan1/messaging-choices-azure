# Creates the Event Grid subscription (BlobCreated -> OnImageUploaded) after azd deploy.
# Works in Windows PowerShell 5.1 and pwsh 7. azd passes its env values as environment variables.

# 'Continue', not 'Stop': in Windows PowerShell 5.1 a native command's stderr (az warnings)
# becomes a terminating error under 'Stop'. Every native call checks $LASTEXITCODE instead.
$ErrorActionPreference = 'Continue'

# Windows PowerShell 5.1 on .NET Framework may not offer TLS 1.2 by default; the function app requires it.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$rg    = $env:AZURE_RESOURCE_GROUP
$app   = $env:AZURE_FUNCTION_APP_NAME
$topic = $env:EVENTGRID_SYSTEM_TOPIC_NAME
$work  = $env:WORK_STORAGE_ACCOUNT_NAME
$sb    = $env:SERVICEBUS_NAMESPACE

$sub   = $env:AZURE_SUBSCRIPTION_ID

if (-not $rg -or -not $app -or -not $topic -or -not $work -or -not $sb -or -not $sub -or -not $env:FUNCTION_BASE_URL) {
    throw 'Missing azd env values. Run `azd provision` first (AZURE_RESOURCE_GROUP, AZURE_FUNCTION_APP_NAME, EVENTGRID_SYSTEM_TOPIC_NAME, WORK_STORAGE_ACCOUNT_NAME, SERVICEBUS_NAMESPACE, FUNCTION_BASE_URL).'
}

# azd and az keep separate logins, and az may default to another subscription.
# Check up front and pin every az call to azd's subscription.
az account show --subscription $sub --output none
if ($LASTEXITCODE -ne 0) {
    throw "The az CLI cannot reach subscription $sub. azd's login is separate from az's: run 'az login', then 'azd hooks run postdeploy'."
}

# Take the hostname from the Bicep output (Flex Consumption apps can get a unique
# default hostname, so don't guess <app>.azurewebsites.net).
$hostName = ([Uri]$env:FUNCTION_BASE_URL).Host

Write-Host "Warming up $hostName so the host creates its eventgrid_extension key..."
try {
    Invoke-WebRequest -ErrorAction Stop -Uri "https://$hostName" -UseBasicParsing -TimeoutSec 60 | Out-Null
} catch {
    Write-Host "  (warm-up request returned: $($_.Exception.Message))"
}

$key = $null
for ($i = 1; $i -le 18; $i++) {
    $key = az functionapp keys list --subscription $sub --resource-group $rg --name $app --query 'systemKeys.eventgrid_extension' --output tsv 2>$null
    if ($LASTEXITCODE -eq 0 -and $key) { break }
    Write-Host "  eventgrid_extension key not there yet (attempt $i/18), waiting 10s..."
    Start-Sleep -Seconds 10
}
if (-not $key) {
    # Run once more without swallowing stderr so the real az error is visible.
    az functionapp keys list --subscription $sub --resource-group $rg --name $app --output none
    throw "Could not read the eventgrid_extension system key from $app. Check that OnImageUploaded deployed, then rerun: azd hooks run postdeploy"
}

Write-Host "Creating Event Grid subscription image-uploaded on $topic..."
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$template = Join-Path (Split-Path -Parent $scriptDir) 'infra/eventgrid-subscription.bicep'

az deployment group create `
    --subscription $sub `
    --resource-group $rg `
    --name eventgrid-subscription `
    --template-file $template `
    --parameters functionAppName=$app systemTopicName=$topic workStorageName=$work eventGridExtensionKey=$key `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Event Grid subscription deployment failed.'
}

Write-Host 'Event Grid subscription created: product-images BlobCreated -> OnImageUploaded'

# fraud-review must only carry the high-value rule. Service Bus adds a '$Default'
# TrueFilter to every new subscription, and rules are OR-ed: while it exists, the
# subscription silently receives every order. Remove anything that isn't high-value.
$ruleArgs = @('--subscription', $sub, '--resource-group', $rg, '--namespace-name', $sb, '--topic-name', 'orders', '--subscription-name', 'fraud-review')
$rules = az servicebus topic subscription rule list @ruleArgs --query '[].name' --output tsv
if ($LASTEXITCODE -ne 0) { throw 'Could not list the rules on fraud-review.' }
$rules = @($rules | Where-Object { $_ })

if ($rules -notcontains 'high-value') {
    az servicebus topic subscription rule create @ruleArgs --name high-value --filter-sql-expression 'total >= 1000' --output none
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the high-value rule on fraud-review.' }
    Write-Host 'fraud-review: created rule high-value (total >= 1000)'
}
foreach ($rule in $rules | Where-Object { $_ -ne 'high-value' }) {
    az servicebus topic subscription rule delete @ruleArgs --name $rule --output none
    if ($LASTEXITCODE -ne 0) { throw "Could not delete rule $rule on fraud-review." }
    Write-Host "fraud-review: deleted rule $rule (it would let every order through)"
}
Write-Host 'fraud-review: only rule is high-value (total >= 1000)'
