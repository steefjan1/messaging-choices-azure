using System.Text;
using Azure.Messaging.ServiceBus;
using Azure.Storage.Queues;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using OrderFlow.Contracts;

namespace OrderFlow.Orders;

/// <summary>
/// GET /api/deadletters peeks (never receives) the places failed work ends up.
/// Note the asymmetry the post talks about: Service Bus has a dead-letter queue per
/// entity, owned by the broker, with a reason on every message. Storage queues have no
/// such thing; the Functions host moves failed messages to "image-jobs-poison" itself.
/// </summary>
public sealed class DeadLetters(ServiceBusClient serviceBus, QueueServiceClient queues)
{
    [Function(nameof(DeadLetters))]
    public async Task<IActionResult> Run(
        [HttpTrigger(AuthorizationLevel.Function, "get", Route = "deadletters")] HttpRequest request)
    {
        var payment = await PeekServiceBus(serviceBus.CreateReceiver(
            Names.OrdersTopic, Names.PaymentSubscription,
            new ServiceBusReceiverOptions { SubQueue = SubQueue.DeadLetter }));

        var shipments = await PeekServiceBus(serviceBus.CreateReceiver(
            Names.ShipmentsQueue,
            new ServiceBusReceiverOptions { SubQueue = SubQueue.DeadLetter }));

        var poison = new List<object>();
        var poisonQueue = queues.GetQueueClient(Names.ImageJobsPoisonQueue);
        if (await poisonQueue.ExistsAsync())
        {
            var peeked = await poisonQueue.PeekMessagesAsync(maxMessages: 20);
            foreach (var m in peeked.Value)
            {
                poison.Add(new { m.MessageId, body = DecodeQueueBody(m.Body.ToString()), m.DequeueCount });
            }
        }

        return new OkObjectResult(new
        {
            serviceBus = new
            {
                ordersPaymentDeadLetter = payment,
                shipmentsDeadLetter = shipments,
            },
            storageQueue = new
            {
                imageJobsPoison = poison,
                note = "Filled by the Functions host after maxDequeueCount (host.json), not by Azure Storage.",
            },
        });
    }

    private static async Task<List<object>> PeekServiceBus(ServiceBusReceiver receiver)
    {
        await using (receiver)
        {
            var messages = await receiver.PeekMessagesAsync(maxMessages: 20);
            return messages.Select(m => (object)new
            {
                m.MessageId,
                m.DeadLetterReason,
                m.DeadLetterErrorDescription,
                m.DeliveryCount,
                m.EnqueuedTime,
            }).ToList();
        }
    }

    // The Functions queue extension base64-encodes messages by default.
    private static string DecodeQueueBody(string body)
    {
        try
        {
            return Encoding.UTF8.GetString(Convert.FromBase64String(body));
        }
        catch (FormatException)
        {
            return body;
        }
    }
}
