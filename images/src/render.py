import sys, asyncio
from playwright.async_api import async_playwright
async def main(paths):
    async with async_playwright() as p:
        b = await p.chromium.launch()
        for svg in paths:
            import re
            s = open(svg).read()
            w, h = map(float, re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', s).groups())
            pg = await b.new_page(viewport={'width': int(w), 'height': int(h)}, device_scale_factor=2)
            await pg.set_content(f'<html><body style="margin:0">{s}</body></html>')
            await pg.screenshot(path=svg.replace('.svg', '.png'), clip={'x':0,'y':0,'width':w,'height':h})
        await b.close()
asyncio.run(main(sys.argv[1:]))
