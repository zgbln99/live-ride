"""Karty Open Graph dla publicznych stron Live Ride.

Obrazek podglądu linku jest STAŁY i celowo nie pokazuje pozycji zawodnika —
miniatura w WhatsAppie trafia do ludzi, którzy linku nie dostali.

Uruchomienie (wymaga Chromium z Playwrighta):

    python3 docs/live-ride/generate_og_cards.py

Wynik ląduje w web/static/imgs/live-ride/. Chromium w nowym trybie headless
odejmuje od `--window-size` wysokość paska okna, więc renderujemy z zapasem
i przycinamy do 1200x630 (png_crop.py).
"""

import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent.parent / 'web' / 'static' / 'imgs' / 'live-ride'
WORK = HERE / '.render'

def esc(t):
    return t.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;')

def card(path, badge, badge_colour, l1, l2, sub1, sub2, foot):
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <defs>
    <radialGradient id="g1" cx="0.82" cy="-0.16" r="0.95">
      <stop offset="0" stop-color="#00bfd8" stop-opacity="0.30"/>
      <stop offset="0.62" stop-color="#00bfd8" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="g2" cx="0.08" cy="1.16" r="0.80">
      <stop offset="0" stop-color="#8b7bff" stop-opacity="0.24"/>
      <stop offset="0.60" stop-color="#8b7bff" stop-opacity="0"/>
    </radialGradient>
    <pattern id="grid" width="60" height="60" patternUnits="userSpaceOnUse">
      <path d="M60 0H0v60" fill="none" stroke="#ffffff" stroke-opacity="0.05" stroke-width="1"/>
    </pattern>
  </defs>

  <rect width="1200" height="630" fill="#07101a"/>
  <rect width="1200" height="630" fill="url(#grid)"/>
  <rect width="1200" height="630" fill="url(#g1)"/>
  <rect width="1200" height="630" fill="url(#g2)"/>

  <path d="M-40 700 C 300 690, 470 646, 660 596 S 880 480, 1030 372 S 1160 236, 1270 196"
        fill="none" stroke="#ffffff" stroke-opacity="0.10" stroke-width="26" stroke-linecap="round"/>
  <path d="M-40 700 C 300 690, 470 646, 660 596 S 880 480, 1030 372 S 1160 236, 1270 196"
        fill="none" stroke="#00bfd8" stroke-opacity="0.85" stroke-width="7" stroke-linecap="round"/>
  <circle cx="1030" cy="372" r="33" fill="none" stroke="#00bfd8" stroke-opacity="0.40" stroke-width="4"/>
  <circle cx="1030" cy="372" r="17" fill="#00bfd8"/>

  <g transform="translate(80,62) scale(0.86)">
    <path d="M10 52 33 9l9 18H23z" fill="#ffffff"/>
    <path d="M30 56 58 12 49 56z" fill="#00bfd8"/>
  </g>
  <text x="148" y="106" font-family="DejaVu Sans, sans-serif" font-size="30" font-weight="700"
        letter-spacing="10" fill="#ffffff">LIVE RIDE</text>

  <g>
    <rect x="884" y="66" width="236" height="52" rx="26"
          fill="{badge_colour}" fill-opacity="0.16" stroke="{badge_colour}" stroke-opacity="0.55"/>
    <circle cx="920" cy="92" r="8" fill="{badge_colour}"/>
    <circle cx="920" cy="92" r="15" fill="{badge_colour}" fill-opacity="0.22"/>
    <text x="944" y="101" font-family="DejaVu Sans, sans-serif" font-size="21" font-weight="700"
          letter-spacing="4" fill="#ffffff">{esc(badge)}</text>
  </g>

  <text x="80" y="268" font-family="DejaVu Sans, sans-serif" font-size="82" font-weight="700"
        fill="#ffffff">{esc(l1)}</text>
  <text x="80" y="356" font-family="DejaVu Sans, sans-serif" font-size="82" font-weight="700"
        fill="#00bfd8">{esc(l2)}</text>

  <text x="80" y="432" font-family="DejaVu Sans, sans-serif" font-size="31"
        fill="#ffffff" fill-opacity="0.66">{esc(sub1)}</text>
  <text x="80" y="476" font-family="DejaVu Sans, sans-serif" font-size="31"
        fill="#ffffff" fill-opacity="0.66">{esc(sub2)}</text>

  <rect x="80" y="528" width="164" height="48" rx="24"
        fill="#ffffff" fill-opacity="0.05" stroke="#ffffff" stroke-opacity="0.16"/>
  <text x="104" y="559" font-family="DejaVu Sans, sans-serif" font-size="23" font-weight="700"
        fill="#ffffff" fill-opacity="0.80">Live Ride</text>
  <text x="266" y="559" font-family="DejaVu Sans, sans-serif" font-size="23"
        fill="#ffffff" fill-opacity="0.50">{esc(foot)}</text>
</svg>'''
    path = str(path)
    WORK.mkdir(exist_ok=True)
    svg_path = str(WORK / (Path(path).stem + '.svg'))
    open(svg_path, 'w').write(svg)
    subprocess.run([
        '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', '--headless', '--disable-gpu',
        '--no-sandbox', '--hide-scrollbars', f'--screenshot={path}',
        '--window-size=1200,715', f'file://{svg_path}',
    ], stderr=subprocess.DEVNULL)

card(WORK / 'live.png', 'NA ŻYWO', '#ff465a',
     'Śledź przejazd', 'na żywo',
     'Mapa, tempo i dystans w czasie rzeczywistym.',
     'Bez aplikacji i bez zakładania konta.',
     'własne śledzenie jazdy na żywo')

card(WORK / 'route.png', 'TRASA', '#00bfd8',
     'Trasa rowerowa', 'w Live Ride',
     'Przebieg, przewyższenie i profil wysokości.',
     'Pobierz GPX albo otwórz w Live Ride.',
     'trasy, nawigacja i jazda na żywo')

from png_crop import crop_top

OUT.mkdir(parents=True, exist_ok=True)
crop_top(str(WORK / 'live.png'), str(OUT / 'og-live.png'), 630)
crop_top(str(WORK / 'route.png'), str(OUT / 'og-route.png'), 630)
print('zapisano', OUT / 'og-live.png', 'i', OUT / 'og-route.png')
