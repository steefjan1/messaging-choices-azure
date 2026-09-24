from lib import *
W, H = 1790, 1110
B = []
BLUE, ORANGE, TEAL, GREY, RED = '#0369a1', '#c2410c', '#0f766e', '#475569', '#b91c1c'
B.append(text(40, 50, 'messaging-choices-azure: one order flow, five services', 26, '700', '#0f172a'))
B.append(text(40, 78, 'All functions run in one Flex Consumption app (.NET 8 isolated). Every connection uses the app\'s managed identity; local auth is disabled on Service Bus, Event Hubs and Storage.', 14, 'normal', '#475569'))

def lane(y, h, c, bg, title, sub):
    B.append(rect(20, y, W-40, h, bg, c, 14, 1.5))
    B.append(text(40, y+28, title, 15, '700', c))
    B.append(text(40, y+47, sub, 12, 'normal', '#475569'))

lane(100, 420, BLUE, '#f0f7ff', '1  ORDERS: messages', 'Service Bus topic for the business fact, Service Bus queue for the command')
lane(540, 250, ORANGE, '#fff8f1', '2  PRODUCT IMAGES: an event that starts work', 'Event Grid routes the notification; a Storage queue holds the work')
lane(810, 250, TEAL, '#f0fdfa', '3  VEHICLE TELEMETRY: a stream', 'Event Hubs log, two consumer groups reading the same events independently')

F = '#ffffff'
# ---- lane 1
B.append(node(40, 270, 150, 64, 'browser', 'Client', ['POST /api/orders']))
B.append(node(215, 270, 170, 64, 'func', 'PlaceOrder', ['HTTP trigger']))
B.append(node(470, 237, 220, 130, 'sb', 'orders', ['Service Bus topic', 'duplicate detection 10 min', 'MessageId = orderId', 'app property: total'], accent=BLUE))
subs = [('payment', 'maxDeliveryCount 3'), ('inventory', 'all orders'), ('notification', 'all orders'), ('fraud-review', 'SQL rule: total >= 1000')]
hand = [('PaymentHandler', 'settles the message itself'), ('InventoryHandler', 'auto-complete'), ('NotificationHandler', 'auto-complete'), ('FraudReviewHandler', 'high-value only')]
ys = [150, 234, 318, 402]
for (sn, sd), (hn, hd), y in zip(subs, hand, ys):
    B.append(node(740, y, 200, 60, None, sn, ['subscription: ' + sd] if sn != 'fraud-review' else [sd], accent=BLUE))
    B.append(node(990, y, 205, 60, 'func', hn, [hd], isz=30))
    B.append(arrow([(690, 302), (715, 302), (715, y+30), (738, y+30)], BLUE))
    B.append(arrow([(940, y+30), (988, y+30)], BLUE))
B.append(text(706, 142, 'a copy each', 11, '600', BLUE, 'middle'))
B.append(arrow([(190, 302), (213, 302)], BLUE))
B.append(arrow([(385, 302), (468, 302)], BLUE, 'OrderPlaced', (426, 292)))

B.append(node(1275, 130, 220, 100, 'sb', 'shipments', ['Service Bus queue', 'sessions: one per customer', 'duplicate detection'], accent=BLUE))
B.append(arrow([(1195, 170), (1273, 170)], BLUE, 'ShipOrder', (1234, 162)))
B.append(node(1540, 150, 220, 60, 'func', 'ShippingHandler', ['session trigger, FIFO'], isz=30))
B.append(arrow([(1495, 180), (1538, 180)], BLUE))

B.append(node(1275, 290, 220, 100, None, 'Dead-letter queues', ['broker-owned, one per entity', 'InvalidTotal (explicit)', 'MaxDeliveryCountExceeded'], fill='#fef2f2', stroke=RED))
B.append(arrow([(1195, 196), (1235, 196), (1235, 330), (1273, 330)], RED, dash='5 4'))
B.append(text(1242, 262, 'dead-letter', 11, '600', RED, 'start'))
B.append(node(1540, 310, 220, 60, 'func', 'DeadLetters', ['GET /api/deadletters (peek)'], isz=30))
B.append(arrow([(1495, 340), (1538, 340)], RED, dash='5 4'))

# ---- lane 2
r2 = 610
B.append(node(40, r2, 150, 64, 'users', 'Uploader', ['az storage blob', 'upload']))
B.append(node(215, r2, 170, 64, 'blob', 'product-images', ['blob container']))
B.append(node(470, r2-16, 220, 96, 'eg', 'Event Grid', ['system topic, BlobCreated', 'subject filter on container', '30 attempts / 24 h'], accent=ORANGE))
B.append(node(740, r2, 200, 64, 'func', 'OnImageUploaded', ['Event Grid trigger'], isz=30))
B.append(node(990, r2, 220, 64, 'sq', 'image-jobs', ['Storage queue'], accent=ORANGE))
B.append(node(1260, r2, 230, 64, 'func', 'ImageWorker', ['queue trigger'], isz=30))
B.append(node(1540, r2, 220, 64, 'blob', 'thumbnails', ['blob container']))
for x1, x2 in [(190, 213), (385, 468), (690, 738), (940, 988), (1210, 1258), (1490, 1538)]:
    B.append(arrow([(x1, r2+32), (x2, r2+32)], ORANGE))
B.append(text(426, r2+22, 'event', 11, '600', ORANGE, 'middle'))
B.append(text(714, r2+22, 'push', 11, '600', ORANGE, 'middle'))
B.append(text(964, r2+22, 'job', 11, '600', ORANGE, 'middle'))
B.append(node(470, 708, 220, 56, 'blob', 'eventgrid-deadletter', ['off unless you configure it'], fill='#fef2f2', stroke=RED, isz=28))
B.append(arrow([(580, r2+80), (580, 706)], RED, dash='5 4'))
B.append(node(1260, 708, 230, 56, 'sq', 'image-jobs-poison', ['moved there by Functions host'], fill='#fef2f2', stroke=RED, isz=28))
B.append(arrow([(1375, r2+64), (1375, 706)], RED, dash='5 4'))
B.append(text(1383, 694, 'after 3 dequeues', 11, '600', RED))

# ---- lane 3
r3 = 880
B.append(node(40, r3+30, 170, 64, 'code', 'Van simulator', ['POST /api/telemetry']))
B.append(node(232, r3+30, 190, 64, 'func', 'SimulateTelemetry', ['batches per van'], isz=30))
B.append(node(470, r3+12, 220, 100, 'eh', 'telemetry', ['event hub, 4 partitions', 'partition key = van id', 'retention 1 day'], accent=TEAL))
B.append(node(740, r3, 200, 56, None, 'aggregator', ['consumer group'], accent=TEAL))
B.append(node(740, r3+78, 200, 56, None, 'alerts', ['consumer group'], accent=TEAL))
B.append(node(990, r3, 220, 56, 'func', 'AggregateTelemetry', ['avg speed per van'], isz=28))
B.append(node(990, r3+78, 220, 56, 'func', 'DetectOverheating', ['engine > 110 C'], isz=28))
B.append(arrow([(210, r3+62), (230, r3+62)], TEAL))
B.append(arrow([(422, r3+62), (468, r3+62)], TEAL, 'readings', (445, r3+52)))
B.append(arrow([(690, r3+62), (715, r3+62), (715, r3+28), (738, r3+28)], TEAL))
B.append(arrow([(715, r3+62), (715, r3+106), (738, r3+106)], TEAL))
B.append(arrow([(940, r3+28), (988, r3+28)], TEAL))
B.append(arrow([(940, r3+106), (988, r3+106)], TEAL))
B.append(node(1260, r3+30, 230, 64, 'st', 'Host storage', ['a checkpoint per consumer group']))
B.append(arrow([(1210, r3+28), (1235, r3+28), (1235, r3+52), (1258, r3+52)], GREY, dash='4 4'))
B.append(arrow([(1210, r3+106), (1235, r3+106), (1235, r3+74), (1258, r3+74)], GREY, dash='4 4'))
B.append(node(1540, r3+30, 220, 64, 'appi', 'Application Insights', ['traces from every handler']))

B.append(text(40, 1090, 'Blue: Service Bus.  Orange: Event Grid + Storage queue.  Teal: Event Hubs.  Red dashed: where failed work goes; notice that only Service Bus owns its dead letters.', 13, 'normal', '#475569'))
open('../messaging-order-flow.svg', 'w').write(doc(W, H, '\n'.join(B), [GREY, BLUE, ORANGE, TEAL, RED]))
print('ok')
