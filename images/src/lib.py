import re, html
import os
ICON_ROOT = os.environ.get('AZURE_ICONS', 'Icons') + '/'
ICONS = {
 'sb': 'integration/10836-icon-service-Azure-Service-Bus.svg',
 'eg': 'integration/10206-icon-service-Event-Grid-Topics.svg',
 'egsub': 'integration/10221-icon-service-Event-Grid-Subscriptions.svg',
 'eh': 'analytics/00039-icon-service-Event-Hubs.svg',
 'sq': 'general/10840-icon-service-Storage-Queue.svg',
 'st': 'storage/10086-icon-service-Storage-Accounts.svg',
 'blob': 'general/10780-icon-service-Blob-Block.svg',
 'func': 'compute/10029-icon-service-Function-Apps.svg',
 'appi': 'monitor/00012-icon-service-Application-Insights.svg',
 'browser': 'general/10783-icon-service-Browser.svg',
 'users': 'identity/10230-icon-service-Users.svg',
 'code': 'general/10787-icon-service-Code.svg',
 'image': 'general/10812-icon-service-Image.svg',
 'mi': 'identity/10227-icon-service-Managed-Identities.svg',
}
_cache = {}
_n = [0]
def icon(key, x, y, size):
    if key not in _cache:
        s = open(ICON_ROOT + ICONS[key]).read()
        s = re.sub(r'<\?xml[^>]*\?>', '', s)
        s = re.sub(r'<title>.*?</title>', '', s, flags=re.S)
        m = re.search(r'viewBox="([^"]+)"', s)
        vb = m.group(1)
        inner = re.sub(r'^.*?<svg[^>]*>', '', s, count=1, flags=re.S)
        inner = inner[:inner.rfind('</svg>')]
        _cache[key] = (vb, inner)
    vb, inner = _cache[key]
    _n[0] += 1
    # make ids unique per use
    ids = set(re.findall(r'id="([^"]+)"', inner))
    for i in ids:
        new = f'{i}-u{_n[0]}'
        inner2 = inner
    out = inner
    for i in ids:
        new = f'{i}-u{_n[0]}'
        out = out.replace(f'id="{i}"', f'id="{new}"').replace(f'url(#{i})', f'url(#{new})').replace(f'href="#{i}"', f'href="#{new}"')
    return f'<svg x="{x}" y="{y}" width="{size}" height="{size}" viewBox="{vb}">{out}</svg>'

FONT = "Segoe UI, Helvetica Neue, Arial, sans-serif"
def esc(t): return html.escape(t, quote=False)

def text(x, y, s, size=14, weight='normal', fill='#1f2937', anchor='start', style=''):
    return f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" font-weight="{weight}" fill="{fill}" text-anchor="{anchor}" {style}>{esc(s)}</text>'

def rect(x, y, w, h, fill='#ffffff', stroke='#cbd5e1', rx=10, sw=1.5, dash=None):
    d = f' stroke-dasharray="{dash}"' if dash else ''
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}/>'

def node(x, y, w, h, ic, title, lines=(), fill='#ffffff', stroke='#94a3b8', isz=36, tsize=14, lsize=11.5, accent=None):
    out = [rect(x, y, w, h, fill, stroke)]
    if accent:
        out.append(f'<rect x="{x}" y="{y}" width="5" height="{h}" rx="2" fill="{accent}"/>')
    ix = x + 12
    iy = y + (h - isz) / 2 if not lines or h < 70 else y + 12
    if ic:
        out.append(icon(ic, ix, iy, isz))
        tx = ix + isz + 10
    else:
        tx = x + 14
    n = len(lines)
    total = tsize + n * (lsize + 4)
    ty = y + (h - total) / 2 + tsize - 2
    out.append(text(tx, ty, title, tsize, '600'))
    for i, l in enumerate(lines):
        out.append(text(tx, ty + (i + 1) * (lsize + 4) + 1, l, lsize, 'normal', '#475569'))
    return '\n'.join(out)

def arrow(points, color='#475569', label=None, lpos=None, dash=None, sw=1.8, lcolor=None, lanchor='middle'):
    d = 'M ' + ' L '.join(f'{px} {py}' for px, py in points)
    da = f' stroke-dasharray="{dash}"' if dash else ''
    mid = f'arr{abs(hash(color))%10000}'
    out = [f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{sw}" marker-end="url(#{mid})"{da}/>']
    if label:
        lx, ly = lpos if lpos else ((points[0][0]+points[-1][0])/2, (points[0][1]+points[-1][1])/2 - 6)
        out.append(text(lx, ly, label, 11, '600', lcolor or color, lanchor))
    return '\n'.join(out)

def markers(colors):
    ms = []
    for c in colors:
        mid = f'arr{abs(hash(c))%10000}'
        ms.append(f'<marker id="{mid}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="{c}"/></marker>')
    return '<defs>' + ''.join(ms) + '</defs>'

def doc(w, h, body, colors):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">\n<rect width="{w}" height="{h}" fill="#ffffff"/>\n{markers(colors)}\n{body}\n</svg>\n'
