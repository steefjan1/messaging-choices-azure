using Azure.Core;
using Azure.Identity;
using Azure.Messaging.EventHubs.Producer;
using Azure.Messaging.ServiceBus;
using Azure.Storage.Blobs;
using Azure.Storage.Queues;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using OrderFlow.Contracts;

var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWebApplication();

// Triggers and bindings read their connections from app settings
// (ServiceBus__fullyQualifiedNamespace, EventHubs__fullyQualifiedNamespace, ...).
// The HTTP functions that *send* use SDK clients directly, because the send side
// needs things the output bindings don't expose: MessageId for duplicate detection,
// SessionId for ordering, application properties for subscription filters,
// and partition keys for Event Hubs.
TokenCredential credential = new DefaultAzureCredential();
builder.Services.AddSingleton(credential);

builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var fqns = config[$"{Names.ServiceBusConnection}:fullyQualifiedNamespace"]
        ?? throw new InvalidOperationException("ServiceBus__fullyQualifiedNamespace is not set.");
    return new ServiceBusClient(fqns, credential);
});

builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var fqns = config[$"{Names.EventHubsConnection}:fullyQualifiedNamespace"]
        ?? throw new InvalidOperationException("EventHubs__fullyQualifiedNamespace is not set.");
    return new EventHubProducerClient(fqns, Names.TelemetryHub, credential);
});

builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var queueUri = config[$"{Names.WorkStorageConnection}:queueServiceUri"]
        ?? throw new InvalidOperationException("WorkStorage__queueServiceUri is not set.");
    return new QueueServiceClient(new Uri(queueUri), credential);
});

builder.Services.AddSingleton(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var blobUri = config[$"{Names.WorkStorageConnection}:blobServiceUri"]
        ?? throw new InvalidOperationException("WorkStorage__blobServiceUri is not set.");
    return new BlobServiceClient(new Uri(blobUri), credential);
});

builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

// The Application Insights worker SDK adds a default filter that drops everything below
// Warning. The demo relies on Information traces ("PAYMENT captured ..."), so remove it.
builder.Logging.Services.Configure<LoggerFilterOptions>(options =>
{
    var defaultRule = options.Rules.FirstOrDefault(rule =>
        rule.ProviderName == "Microsoft.Extensions.Logging.ApplicationInsights.ApplicationInsightsLoggerProvider");
    if (defaultRule is not null)
    {
        options.Rules.Remove(defaultRule);
    }
});

builder.Build().Run();
