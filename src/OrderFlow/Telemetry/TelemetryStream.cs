using System.Text.Json;
using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Producer;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using OrderFlow.Contracts;

namespace OrderFlow.Telemetry;

/// <summary>
/// POST /api/telemetry?vehicles=5&amp;readings=200 simulates delivery-van telemetry.
///
/// This is an event series, not a set of discrete events: one reading is worthless on
/// its own, the value is in the aggregate. Event Hubs is a partitioned, append-only log.
/// Readers don't remove anything, they move a checkpoint. Retention (1 day here) decides
/// when data disappears, not consumption.
/// </summary>
public sealed class SimulateTelemetry(EventHubProducerClient producer, ILogger<SimulateTelemetry> logger)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    [Function(nameof(SimulateTelemetry))]
    public async Task<IActionResult> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "telemetry")] HttpRequest request)
    {
        var vehicles = Math.Clamp(int.TryParse(request.Query["vehicles"].ToString(), out var v) ? v : 5, 1, 50);
        var readings = Math.Clamp(int.TryParse(request.Query["readings"].ToString(), out var r) ? r : 200, 1, 5000);
        var random = new Random();
        var sent = 0;

        for (var i = 0; i < vehicles; i++)
        {
            var vehicleId = $"van-{i + 1:00}";

            // Partition key = vehicle: all readings for one van land in the same partition,
            // in order. Ordering across vans is not guaranteed, and doesn't need to be.
            var batch = await producer.CreateBatchAsync(new CreateBatchOptions { PartitionKey = vehicleId });

            for (var n = 0; n < readings; n++)
            {
                var reading = new VehicleReading(
                    vehicleId,
                    DateTimeOffset.UtcNow.AddSeconds(n - readings),
                    SpeedKmh: Math.Round(40 + random.NextDouble() * 60, 1),
                    // Roughly 1 in 100 readings is an overheating spike for the alerts reader.
                    EngineTempC: Math.Round(random.NextDouble() < 0.01 ? 115 + random.NextDouble() * 10 : 85 + random.NextDouble() * 10, 1),
                    Latitude: 52.09 + random.NextDouble() / 100,
                    Longitude: 5.12 + random.NextDouble() / 100);

                var eventData = new EventData(BinaryData.FromObjectAsJson(reading, Json));
                if (!batch.TryAdd(eventData))
                {
                    await producer.SendAsync(batch);
                    batch.Dispose();
                    batch = await producer.CreateBatchAsync(new CreateBatchOptions { PartitionKey = vehicleId });
                    if (!batch.TryAdd(eventData))
                    {
                        throw new InvalidOperationException("A single reading does not fit in a batch.");
                    }
                }

                sent++;
            }

            await producer.SendAsync(batch);
            batch.Dispose();
        }

        logger.LogInformation("TELEMETRY sent {Count} readings for {Vehicles} vehicles", sent, vehicles);
        return new OkObjectResult(new { sent, vehicles, hub = Names.TelemetryHub });
    }
}

/// <summary>
/// Reader 1, consumer group "aggregator": rolling averages per vehicle.
/// </summary>
public sealed class AggregateTelemetry(ILogger<AggregateTelemetry> logger)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    [Function(nameof(AggregateTelemetry))]
    public void Run(
        [EventHubTrigger(Names.TelemetryHub, Connection = Names.EventHubsConnection,
            ConsumerGroup = Names.AggregatorConsumerGroup)]
        EventData[] events)
    {
        var readings = events.Select(e => e.EventBody.ToObjectFromJson<VehicleReading>(Json)!).ToList();

        foreach (var group in readings.GroupBy(x => x.VehicleId))
        {
            logger.LogInformation(
                "STREAM-AGGREGATE {VehicleId} readings={Count} avgSpeed={AvgSpeed:F1} maxTemp={MaxTemp:F1}",
                group.Key, group.Count(), group.Average(x => x.SpeedKmh), group.Max(x => x.EngineTempC));
        }
    }
}

/// <summary>
/// Reader 2, consumer group "alerts": reads the very same events, independently, with its
/// own checkpoint. If this function is down for an hour, it catches up from its checkpoint;
/// the aggregator never notices. Try that with a queue.
/// </summary>
public sealed class DetectOverheating(ILogger<DetectOverheating> logger)
{
    private const double Threshold = 110;
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    [Function(nameof(DetectOverheating))]
    public void Run(
        [EventHubTrigger(Names.TelemetryHub, Connection = Names.EventHubsConnection,
            ConsumerGroup = Names.AlertsConsumerGroup)]
        EventData[] events)
    {
        foreach (var e in events)
        {
            var reading = e.EventBody.ToObjectFromJson<VehicleReading>(Json)!;
            if (reading.EngineTempC > Threshold)
            {
                logger.LogWarning("STREAM-ALERT {VehicleId} engine {Temp:F1} C at {Timestamp:O} (partition key {PartitionKey})",
                    reading.VehicleId, reading.EngineTempC, reading.Timestamp, e.PartitionKey);
            }
        }
    }
}
