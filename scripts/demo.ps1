<#
.SYNOPSIS
  Drives the order flow end to end against the deployed function app.

.DESCRIPTION
  Runs in Windows PowerShell 5.1 and pwsh 7. Needs: azd (env provisioned + deployed), az (logged in).
  Each step prints what to look for in Application Insights.

  1. Service Bus topic: a normal order fans out to payment, inventory, notification.
  2. Duplicate detection: the same orderId again is dropped by the broker.
  3. Subscription filter: a high-value order also reaches fraud-review.
  4. Explicit dead-letter: a zero-total order is dead-lettered by the payment handler.
  5. Max delivery count: a "poison" customer fails 3 times, the broker dead-letters it.
  6. Event Grid + Storage queue: two image uploads, one of which ends in the poison queue.
  7. Event Hubs: a telemetry burst read by two consumer groups.
#>
[CmdletBinding()]
param(
    [int] $Vehicles = 5,
    [int] $Readings = 200,
    [int] $SettleSeconds = 60
)

# 'Continue', not 'Stop': in Windows PowerShell 5.1 a native command's stderr (az warnings)
# becomes a terminating error under 'Stop'. Every native call checks $LASTEXITCODE instead.
$ErrorActionPreference = 'Continue'

# Windows PowerShell 5.1 on .NET Framework may not offer TLS 1.2 by default; the function app requires it.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Get-AzdValues {
    $values = @{}
    $lines = azd env get-values
    if ($LASTEXITCODE -ne 0) { throw 'azd env get-values failed. Run azd up first.' }
    foreach ($line in $lines) {
        if ($line -match '^\s*([A-Za-z0-9_]+)\s*=\s*"?(.*?)"?\s*$') {
            $values[$Matches[1]] = $Matches[2]
        }
    }
    return $values
}

function Write-Step([string] $title) {
    Write-Host ''
    Write-Host "=== $title" -ForegroundColor Cyan
}

function Send-Order($body) {
    $json = $body | ConvertTo-Json -Depth 5
    return Invoke-RestMethod -ErrorAction Stop -Method Post -Uri "$baseUrl/orders?code=$key" -ContentType 'application/json' -Body $json
}

$envValues = Get-AzdValues
$rg      = $envValues['AZURE_RESOURCE_GROUP']
$app     = $envValues['AZURE_FUNCTION_APP_NAME']
$baseUrl = $envValues['FUNCTION_BASE_URL']
$work    = $envValues['WORK_STORAGE_ACCOUNT_NAME']
$sub     = $envValues['AZURE_SUBSCRIPTION_ID']

# azd and az keep separate logins; pin az to azd's subscription.
az account show --subscription $sub --output none
if ($LASTEXITCODE -ne 0) { throw "The az CLI cannot reach subscription $sub. Run 'az login' first." }

$key = az functionapp keys list --subscription $sub --resource-group $rg --name $app --query 'functionKeys.default' --output tsv
if ($LASTEXITCODE -ne 0 -or -not $key) { throw "Could not read the default function key for $app." }

$runId = (Get-Date).ToString('HHmmss')

Write-Step '1. Service Bus topic: one OrderPlaced, three subscribers'
$order1 = @{
    orderId    = "ord-$runId-a"
    customerId = 'cust-001'
    lines      = @(@{ sku = 'MUG-01'; quantity = 2; unitPrice = 12.50 })
}
Send-Order $order1 | Format-List

Write-Step '2. Duplicate detection: same orderId again (broker drops it, handlers run once)'
Send-Order $order1 | Format-List

Write-Step '3. Subscription filter: total >= 1000 also lands on fraud-review'
Send-Order @{
    orderId    = "ord-$runId-b"
    customerId = 'cust-002'
    lines      = @(@{ sku = 'LAPTOP-15'; quantity = 1; unitPrice = 1499.00 })
} | Format-List

Write-Step '4. Explicit dead-letter: zero total, payment handler dead-letters with reason InvalidTotal'
Send-Order @{
    orderId    = "ord-$runId-c"
    customerId = 'cust-003'
    lines      = @(@{ sku = 'FREEBIE'; quantity = 1; unitPrice = 0 })
} | Format-List

Write-Step '5. Max delivery count: customer "poison" fails 3 times, broker dead-letters it'
Send-Order @{
    orderId    = "ord-$runId-d"
    customerId = 'poison'
    lines      = @(@{ sku = 'MUG-01'; quantity = 1; unitPrice = 12.50 })
} | Format-List

Write-Step '6. Event Grid -> Storage queue: two uploads, one corrupt'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "msg-demo-$runId.png"
[System.IO.File]::WriteAllBytes($tmp, [byte[]]((0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A) + (1..64)))
foreach ($name in @("mug-$runId.png", "corrupt-$runId.png")) {
    az storage blob upload --subscription $sub --account-name $work --container-name product-images --name $name --file $tmp --auth-mode login --overwrite --only-show-errors --output none
    if ($LASTEXITCODE -ne 0) {
        throw "Blob upload failed. If this is a fresh deployment, your Storage Blob Data Contributor role may still be propagating; wait a minute and rerun."
    }
    Write-Host "  uploaded product-images/$name (the uploader knows nothing about the pipeline)"
}
Remove-Item $tmp -ErrorAction SilentlyContinue

Write-Step "7. Event Hubs: $($Vehicles * $Readings) readings, two consumer groups read them all"
Invoke-RestMethod -ErrorAction Stop -Method Post -Uri "$baseUrl/telemetry?vehicles=$Vehicles&readings=$Readings&code=$key" | Format-List

Write-Step "Waiting $SettleSeconds s for retries and dead-lettering to settle..."
Start-Sleep -Seconds $SettleSeconds

Write-Step 'Dead letters (peeked, not received)'
$dl = Invoke-RestMethod -ErrorAction Stop -Method Get -Uri "$baseUrl/deadletters?code=$key"
$dl | ConvertTo-Json -Depth 6

Write-Step 'Application Insights: paste this into Logs'
@"
traces
| where timestamp > ago(30m)
| where message has_any ('ORDER', 'PAYMENT', 'INVENTORY', 'EMAIL', 'FRAUD-REVIEW', 'SHIPPING',
                         'EVENTGRID', 'IMAGE-WORKER', 'TELEMETRY', 'STREAM-')
| where message has '$runId' or message has_any ('STREAM-', 'TELEMETRY')
| project timestamp, operation_Name, severityLevel, message
| order by timestamp asc
"@ | Write-Host

Write-Host ''
Write-Host "Expect: ord-$runId-a once per handler despite two POSTs; ord-$runId-b on FRAUD-REVIEW;"
Write-Host "        ord-$runId-c dead-lettered as InvalidTotal; ord-$runId-d dead-lettered as MaxDeliveryCountExceeded;"
Write-Host "        corrupt-$runId.png in image-jobs-poison after 3 dequeues; STREAM-AGGREGATE and STREAM-ALERT both see the burst."
