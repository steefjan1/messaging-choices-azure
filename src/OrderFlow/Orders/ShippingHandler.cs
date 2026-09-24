using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using OrderFlow.Contracts;

namespace OrderFlow.Orders;

/// <summary>
/// The shipments queue carries commands, and a command has exactly one owner.
/// Competing consumers: however many instances Flex Consumption scales out to, each
/// ShipOrder is locked by one of them. Sessions add FIFO per customer on top of that.
/// </summary>
public sealed class ShippingHandler(ILogger<ShippingHandler> logger)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    [Function(nameof(ShippingHandler))]
    public void Run(
        [ServiceBusTrigger(Names.ShipmentsQueue, Connection = Names.ServiceBusConnection,
            IsSessionsEnabled = true)]
        ServiceBusReceivedMessage message)
    {
        var command = message.Body.ToObjectFromJson<ShipOrder>(Json)!;
        logger.LogInformation(
            "SHIPPING order {OrderId} session={SessionId} sequence={SequenceNumber}",
            command.OrderId, message.SessionId, message.SequenceNumber);
    }
}
