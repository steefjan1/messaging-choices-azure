namespace OrderFlow.Contracts;

// Names shared by producers, consumers and infra/resources.bicep.
// If you rename something here, rename it in the Bicep too.
public static class Names
{
    // Service Bus: a topic for the business fact, a queue for the command.
    public const string OrdersTopic = "orders";
    public const string PaymentSubscription = "payment";
    public const string InventorySubscription = "inventory";
    public const string NotificationSubscription = "notification";
    public const string FraudReviewSubscription = "fraud-review"; // SQL filter: total >= 1000
    public const string ShipmentsQueue = "shipments";            // sessions + duplicate detection

    // Storage: the blob container Event Grid watches and the cheap work queue behind it.
    public const string ImagesContainer = "product-images";
    public const string ThumbnailsContainer = "thumbnails";
    public const string ImageJobsQueue = "image-jobs";
    public const string ImageJobsPoisonQueue = "image-jobs-poison"; // filled by the Functions host, not by Storage

    // Event Hubs: one stream, two independent readers.
    public const string TelemetryHub = "telemetry";
    public const string AggregatorConsumerGroup = "aggregator";
    public const string AlertsConsumerGroup = "alerts";

    // Connection prefixes. Each maps to <prefix>__fullyQualifiedNamespace or
    // <prefix>__queueServiceUri / __blobServiceUri app settings (managed identity, no keys).
    public const string ServiceBusConnection = "ServiceBus";
    public const string EventHubsConnection = "EventHubs";
    public const string WorkStorageConnection = "WorkStorage";
}

/// <summary>A business fact with a contract: the publisher expects payment, stock and email to happen.</summary>
public sealed record OrderPlaced(
    string OrderId,
    string CustomerId,
    decimal Total,
    IReadOnlyList<OrderLine> Lines,
    DateTimeOffset PlacedAt);

public sealed record OrderLine(string Sku, int Quantity, decimal UnitPrice);

/// <summary>A command with exactly one owner: shipping.</summary>
public sealed record ShipOrder(string OrderId, string CustomerId, DateTimeOffset RequestedAt);

/// <summary>Background work: cheap, retryable, nobody waits for it.</summary>
public sealed record ImageJob(string BlobName, string BlobUrl, long ContentLength);

/// <summary>One data point in a stream. Worthless alone, useful in aggregate.</summary>
public sealed record VehicleReading(
    string VehicleId,
    DateTimeOffset Timestamp,
    double SpeedKmh,
    double EngineTempC,
    double Latitude,
    double Longitude);

/// <summary>Request body for POST /api/orders.</summary>
public sealed record PlaceOrderRequest(
    string? OrderId,
    string CustomerId,
    IReadOnlyList<OrderLine> Lines);
