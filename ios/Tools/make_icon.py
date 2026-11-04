"""Draws Canary's app icon: light, dark and tinted 1024 px PNGs for the asset catalog.

    pip install cairosvg pillow
    python3 ios/Tools/make_icon.py ios/Canary/Assets.xcassets/AppIcon.appiconset
"""
import os
import sys

import cairosvg

def bird(body, wing, beak, eye, highlight=True):
    # A canary in profile, perched and alert, facing right. One silhouette path
    # (beak to crown, back, tail, belly, throat), a wing and an eye.
    return f'''
  <g transform="translate(512,512) scale(1.1) translate(-500,-496)">
    <path d="M806 382 L742 362
             C728 300 640 278 590 330
             C540 382 470 470 352 548
             L196 676 C204 694 222 704 240 700
             L362 632
             C440 690 610 690 688 572
             C722 520 742 462 744 408 Z" fill="{body}"/>
    <path d="M396 556 C470 470 590 468 650 522 C580 588 470 606 396 556 Z" fill="{wing}"/>
    <path d="M806 382 L744 408 L742 362 Z" fill="{beak}"/>
    <circle cx="680" cy="356" r="17" fill="{eye}"/>
    {'<circle cx="686" cy="350" r="5.5" fill="#FFFFFF"/>' if highlight else ''}
  </g>'''

def rings(color, opacity):
    return ''.join(f'<circle cx="520" cy="512" r="{r}" fill="none" stroke="{color}" stroke-opacity="{o}" stroke-width="9"/>'
                   for r, o in [(250, opacity), (350, opacity * 0.7), (450, opacity * 0.45)])

grad = '''<linearGradient id="body" x1="0.2" y1="0" x2="0.5" y2="1">
      <stop offset="0" stop-color="#FFE45C"/><stop offset="1" stop-color="#FFB300"/></linearGradient>'''
light = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#1D3F73"/><stop offset="1" stop-color="#0A1631"/></linearGradient>{grad}</defs>
  <rect width="1024" height="1024" fill="url(#bg)"/>{rings('#FFFFFF', 0.11)}
  {bird('url(#body)', '#EBA200', '#FF8A00', '#0A1631')}</svg>'''
dark = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>{grad}</defs>{rings('#FFFFFF', 0.12)}
  {bird('url(#body)', '#D99600', '#FF8A00', '#111111')}</svg>'''
tinted = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <rect width="1024" height="1024" fill="#000000"/>{rings('#FFFFFF', 0.2)}
  {bird('#FFFFFF', '#B8B8B8', '#DADADA', '#000000', highlight=False)}</svg>'''
out = sys.argv[1] if len(sys.argv) > 1 else '.'
for name, svg in [('AppIcon.png', light), ('AppIcon-Dark.png', dark), ('AppIcon-Tinted.png', tinted)]:
    cairosvg.svg2png(bytestring=svg.encode(), write_to=os.path.join(out, name), output_width=1024, output_height=1024)

print("Wrote icons to", out)
