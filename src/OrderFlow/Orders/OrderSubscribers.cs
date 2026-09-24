using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using OrderFlow.Contracts;

namespace OrderFlow.Orders;

/// <summary>
/// Four subscriptions on one topic. Each gets its own copy of OrderPlaced, its own
/// delivery count and its own dead-letter queue. One slow or failing subscriber does
/// not hold up the others: that is the difference between a topic and a queue.
///
/// Service Bus delivers at least once. Every handler here has to be safe to run twice
/// for the same OrderId; in a real system that means an idempotency key in your store.
/// </summary>
public sealed class OrderSubscribers(ServiceBusClient serviceBus, ILogger<OrderSubscribers> logger)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    /// <summary>
    /// Payment settles messages itself (AutoCompleteMessages = false) so it can dead-letter
    /// a message it knows will never succeed, instead of burning retries on it.
    /// </summary>
    [Function("PaymentHandler")]
    public async Task Payment(
        [ServiceBusTrigger(Names.OrdersTopic, Names.PaymentSubscription,
            Connection = Names.ServiceBusConnection, AutoCompleteMessages = false)]
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions actions)
    {
        var order = message.Body.ToObjectFromJson<OrderPlaced>(Json)!;

        // 1. A message that can never succeed: dead-letter it now, with a reason.
        if (order.Total <= 0)
        {
            logger.LogWarning("PAYMENT rejected {OrderId}: total {Total} is not payable, dead-lettering",
                order.OrderId, order.Total);
            await actions.DeadLetterMessageAsync(message,
                deadLetterReason: "InvalidTotal",
                deadLetterErrorDescription: $"Order total {order.Total} is not payable.");
            return;
        }

        // 2. A transient-looking failure: throw, let the lock expire into a retry.
        //    After maxDeliveryCount (3 on this subscription) the broker dead-letters it
        //    with reason MaxDeliveryCountExceeded. No code of ours decides that.
        if (order.CustomerId.Equals("poison", StringComparison.OrdinalIgnoreCase))
        {
            logger.LogWarning("PAYMENT gateway failure {OrderId}, attempt {DeliveryCount}",
                order.OrderId, message.DeliveryCount);
            throw new InvalidOperationException($"Simulated payment gateway failure for {order.OrderId}.");
        }

        // 3. Happy path: capture, then hand shipping a command.
        logger.LogInformation("PAYMENT captured {OrderId} amount={Total} attempt={DeliveryCount}",
            order.OrderId, order.Total, message.DeliveryCount);

        var command = new ServiceBusMessage(BinaryData.FromObjectAsJson(
            new ShipOrder(order.OrderId, order.CustomerId, DateTimeOffset.UtcNow), Json))
        {
            // Send and complete are two operations, not one transaction. If we crash after
            // the send and before the complete, this message is redelivered and we send
            // again. Duplicate detection on the shipments queue drops the second copy.
            MessageId = $"{order.OrderId}:ship",
            // Sessions: all commands for one customer are handled in order, by one
            // receiver at a time. Different customers still run in parallel.
            SessionId = order.CustomerId,
            Subject = nameof(ShipOrder),
            ContentType = "application/json",
        };

        await using var sender = serviceBus.CreateSender(Names.ShipmentsQueue);
        await sender.SendMessageAsync(command);
        await actions.CompleteMessageAsync(message);
    }

    [Function("InventoryHandler")]
    public void Inventory(
        [ServiceBusTrigger(Names.OrdersTopic, Names.InventorySubscription,
            Connection = Names.ServiceBusConnection)]
        ServiceBusReceivedMessage message)
    {
        var order = message.Body.ToObjectFromJson<OrderPlaced>(Json)!;
        logger.LogInformation("INVENTORY reserved {Lines} line(s) for {OrderId}",
            order.Lines.Count, order.OrderId);
    }

    [Function("NotificationHandler")]
    public void Notification(
        [ServiceBusTrigger(Names.OrdersTopic, Names.NotificationSubscription,
            Connection = Names.ServiceBusConnection)]
        ServiceBusReceivedMessage message)
    {
        var order = message.Body.ToObjectFromJson<OrderPlaced>(Json)!;
        logger.LogInformation("EMAIL order confirmation for {OrderId} to customer {CustomerId}",
            order.OrderId, order.CustomerId);
    }

    /// <summary>Only sees orders with total >= 1000, thanks to the SQL rule on the subscription.</summary>
    [Function("FraudReviewHandler")]
    public void FraudReview(
        [ServiceBusTrigger(Names.OrdersTopic, Names.FraudReviewSubscription,
            Connection = Names.ServiceBusConnection)]
        ServiceBusReceivedMessage message)
    {
        var order = message.Body.ToObjectFromJson<OrderPlaced>(Json)!;
        logger.LogInformation("FRAUD-REVIEW high-value order {OrderId} total={Total}",
            order.OrderId, order.Total);
    }
}
