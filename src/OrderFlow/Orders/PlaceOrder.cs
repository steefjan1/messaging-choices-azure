using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using OrderFlow.Contracts;

namespace OrderFlow.Orders;

/// <summary>
/// POST /api/orders publishes OrderPlaced to the Service Bus topic.
///
/// Why a Service Bus topic and not Event Grid? By Microsoft Learn's definition this is a
/// message, not an event: the publisher has an expectation (someone must take the money,
/// reserve stock and send the email). It needs durability, dead-lettering, duplicate
/// detection and subscription filters. It fans out, so it's a topic, not a queue.
/// </summary>
public sealed class PlaceOrder(ServiceBusClient serviceBus, ILogger<PlaceOrder> logger)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    [Function(nameof(PlaceOrder))]
    public async Task<IActionResult> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "orders")] HttpRequest request)
    {
        var body = await JsonSerializer.DeserializeAsync<PlaceOrderRequest>(request.Body, Json);
        if (body is null || string.IsNullOrWhiteSpace(body.CustomerId) || body.Lines is null)
        {
            return new BadRequestObjectResult(new { error = "customerId and lines are required" });
        }

        // Deliberately no business validation of the total here: the demo sends a
        // zero-total order so you can watch the payment handler dead-letter it explicitly.
        var order = new OrderPlaced(
            OrderId: string.IsNullOrWhiteSpace(body.OrderId) ? "ord-" + Guid.NewGuid().ToString("N")[..12] : body.OrderId,
            CustomerId: body.CustomerId,
            Total: body.Lines.Sum(l => l.Quantity * l.UnitPrice),
            Lines: body.Lines,
            PlacedAt: DateTimeOffset.UtcNow);

        var message = new ServiceBusMessage(BinaryData.FromObjectAsJson(order, Json))
        {
            // Duplicate detection on the topic keys on MessageId. A client that retries
            // the POST with the same orderId inside the 10-minute window is dropped by the
            // broker, and every subscriber still sees the order exactly once.
            MessageId = order.OrderId,
            Subject = nameof(OrderPlaced),
            ContentType = "application/json",
        };

        // Subscription rules filter on application properties, never on the body.
        // The fraud-review subscription's rule is: total >= 1000
        message.ApplicationProperties["total"] = (double)order.Total;
        message.ApplicationProperties["customerId"] = order.CustomerId;

        await using var sender = serviceBus.CreateSender(Names.OrdersTopic);
        await sender.SendMessageAsync(message);

        logger.LogInformation("ORDER published {OrderId} customer={CustomerId} total={Total}",
            order.OrderId, order.CustomerId, order.Total);

        return new AcceptedResult(location: null, value: new
        {
            order.OrderId,
            order.Total,
            publishedTo = $"{Names.OrdersTopic} (Service Bus topic)",
        });
    }
}
