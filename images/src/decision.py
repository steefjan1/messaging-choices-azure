from lib import *
W, H = 1760, 880
B = []
BLUE, ORANGE, TEAL, GREY = '#0369a1', '#c2410c', '#0f766e', '#475569'
B.append(text(40, 52, 'Azure messaging: start with what you are sending', 28, '700', '#0f172a'))
B.append(text(40, 82, 'Microsoft Learn draws the line between messages, discrete events and event series. The service mostly follows from that.', 15, 'normal', '#475569'))

# top question
qx, qy, qw, qh = 600, 110, 560, 64
B.append(rect(qx, qy, qw, qh, '#f8fafc', '#334155', 12, 2))
B.append(text(880, qy+28, 'After it sends, what does the producer expect?', 18, '700', '#0f172a', 'middle'))
B.append(text(880, qy+50, 'This is the question that decides it. Not the stack, not the volume.', 13, 'normal', '#475569', 'middle'))

cols = [
  (40, 920, BLUE, '#eff6ff', 'A MESSAGE', 'Someone must act on it. A contract exists', 'between publisher and consumer.'),
  (990, 350, ORANGE, '#fff7ed', 'A DISCRETE EVENT', 'Something happened. The publisher has', 'no expectation about how it is handled.'),
  (1370, 350, TEAL, '#f0fdfa', 'AN EVENT SERIES', 'A time-ordered stream. One data point is', 'worthless; the value is in the aggregate.'),
]
top = 220
for (x, w, c, bg, head, l1, l2) in cols:
    B.append(rect(x, top, w, 570, bg, c, 14, 2))
    B.append(text(x+22, top+36, head, 17, '700', c))
    B.append(text(x+22, top+60, l1, 13, 'normal', '#334155'))
    B.append(text(x+22, top+78, l2, 13, 'normal', '#334155'))
    B.append(arrow([(880, qy+qh), (880, 196), (x + w/2, 196), (x + w/2, top-2)], GREY))

# --- message column: sub question
B.append(rect(70, 320, 860, 50, '#ffffff', BLUE, 10, 1.5, '5 4'))
B.append(text(500, 342, 'Is this plain background work, or a business operation that must not get lost?', 13.5, '600', '#0f172a', 'middle'))
B.append(text(500, 360, 'Then: does it have one owner, or several?', 12.5, 'normal', '#475569', 'middle'))

def card(x, y, w, h, ic, title, sub, bullets, c, wrong):
    out = [rect(x, y, w, h, '#ffffff', c, 12, 1.6)]
    out.append(icon(ic, x+16, y+16, 44))
    out.append(text(x+72, y+36, title, 17, '700', '#0f172a'))
    out.append(text(x+72, y+56, sub, 12.5, '600', c))
    yy = y + 88
    for b in bullets:
        if not b.startswith('  '):
            out.append(f'<circle cx="{x+22}" cy="{yy-4}" r="2.6" fill="{c}"/>')
        out.append(text(x+32, yy, b.strip(), 12.5, 'normal', '#334155'))
        yy += 21
    out.append(f'<line x1="{x+16}" y1="{y+h-64}" x2="{x+w-16}" y2="{y+h-64}" stroke="#e2e8f0"/>')
    out.append(text(x+16, y+h-44, 'Wrong answer when', 11.5, '700', '#b91c1c'))
    for i, wline in enumerate(wrong):
        out.append(text(x+16, y+h-27+i*15, wline, 11.5, 'normal', '#7f1d1d'))
    return '\n'.join(out)

cy, ch, cw = 400, 370, 280
B.append(arrow([(500, 370), (500, 384), (62+cw/2, 384), (62+cw/2, cy-2)], BLUE, 'background work', (208, 396), lcolor=BLUE, lanchor='start'))
B.append(arrow([(500, 370), (500, cy-2)], BLUE))
B.append(arrow([(500, 370), (500, 384), (638+cw/2, 384), (638+cw/2, cy-2)], BLUE))
B.append(text(508, 396, 'one owner', 11, '600', BLUE))
B.append(text(786, 396, 'many owners', 11, '600', BLUE))

B.append(card(62, cy, cw, ch, 'sq', 'Storage Queue', '"Get this done, eventually"', [
  'Report, email, resize, file job',
  'Up to 64 KB per message',
  'At least once; no ordering',
  'No dead-letter queue: the',
  '  Functions host fakes one',
  'Backlog can exceed 80 GB',
  'Per-message visibility timeout',
  'Cheapest option, HTTP only',
], BLUE, ['you need DLQ, ordering,', 'dedup or transactions']))

B.append(card(350, cy, cw, ch, 'sb', 'Service Bus Queue', '"Do this, exactly one of you"', [
  'Commands: ShipOrder, Refund',
  'Competing consumers, peek-lock',
  'Broker-owned dead-letter queue',
  'Sessions: FIFO per key',
  'Duplicate detection on MessageId',
  'Transactions within a namespace',
  '256 KB Standard, 100 MB Premium',
  'Basic tier: queues only',
], BLUE, ['nobody cares if it gets', 'lost, or 5 teams subscribe']))

B.append(card(638, cy, cw, ch, 'sb', 'Service Bus Topic', '"It happened; each of you owes"', [
  'Business facts: OrderPlaced',
  'Copy per subscription, own DLQ',
  'SQL and correlation filters',
  '  on application properties',
  'Same dedup, sessions, TTL',
  'Needs Standard or Premium',
  'Adding a consumer = adding',
  '  a subscription, not code',
], BLUE, ['subscribers don\'t owe', 'anything: use Event Grid']))

# event grid
B.append(card(1010, 320, 310, 450, 'eg', 'Event Grid', '"FYI, react if you care"', [
  'BlobCreated, resource changes,',
  '  your own custom events',
  'Push to Functions, Logic Apps,',
  '  webhooks, queues, Event Hubs',
  'Pull delivery on namespace topics',
  'MQTT broker, CloudEvents 1.0',
  'Default retry: 30 attempts',
  '  within 24 hours, backing off',
  'No ordering guarantee',
  'Dead-lettering is OFF by default',
  'Filters on type and subject',
  'Router, not a work queue: hand',
  '  real work to a queue behind it',
], ORANGE, ['the handler must process', 'it or the business breaks']))

# event hubs
B.append(card(1390, 320, 310, 450, 'eh', 'Event Hubs', '"Here is the firehose"', [
  'Telemetry, clickstream, logs',
  'Partitioned append-only log',
  'Order only within a partition',
  'Reading deletes nothing:',
  '  consumers keep checkpoints',
  'Consumer groups = independent',
  '  readers of the same stream',
  'Retention decides deletion',
  '  (Standard: up to 7 days)',
  'Kafka endpoint, Capture to',
  '  Blob / Data Lake',
  'Basic tier: 1 consumer group',
], TEAL, ['you need per-message', 'retry, DLQ or ack']))

B.append(text(40, 830, 'They combine. Event Grid can deliver to a Service Bus or Storage queue; Event Hubs Capture announces files through Event Grid; the sample repo uses all five in one order flow.', 13, 'normal', '#475569'))
B.append(text(1720, 862, 'Sources: Microsoft Learn, "Compare Azure messaging services", "Storage queues and Service Bus queues compared", Event Grid delivery and retry, Event Hubs features', 10, 'normal', '#94a3b8', 'end'))

open('../messaging-decision.svg', 'w').write(doc(W, H, '\n'.join(B), [GREY, BLUE, ORANGE, TEAL]))
print('ok')
