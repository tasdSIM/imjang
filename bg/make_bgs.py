"""Draw Imjang's extra scenes as SVG (900x738, same frame as pet/room.webp).
The pet stands on the floor around y 560-700, centre x 450, so the middle bottom is kept calm.
usage: python -I make_bgs.py <out_dir>
"""
import math, os, random, sys

W, H = 900, 738
out = sys.argv[1]
os.makedirs(out, exist_ok=True)


def svg(body, defs=''):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">'
            f'<defs>{defs}</defs>{body}</svg>\n')


def cloud(x, y, s, fill='#fff', op=1):
    return (f'<g opacity="{op}" fill="{fill}"><ellipse cx="{x}" cy="{y}" rx="{60*s}" ry="{24*s}"/>'
            f'<circle cx="{x-24*s}" cy="{y-12*s}" r="{24*s}"/><circle cx="{x+14*s}" cy="{y-22*s}" r="{30*s}"/>'
            f'<circle cx="{x+42*s}" cy="{y-6*s}" r="{20*s}"/></g>')


# ---------------- sea ----------------
def sea():
    r = random.Random(7)
    defs = ('<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8FD3F4"/><stop offset="1" stop-color="#DDF3FB"/></linearGradient>'
            '<linearGradient id="water" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3FB4D8"/><stop offset="1" stop-color="#7FD6E6"/></linearGradient>'
            '<linearGradient id="sand" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F8DFAE"/><stop offset="1" stop-color="#EEC98A"/></linearGradient>'
            '<radialGradient id="sun"><stop offset="0" stop-color="#FFF6C9"/><stop offset=".6" stop-color="#FFE27A"/><stop offset="1" stop-color="#FFE27A" stop-opacity="0"/></radialGradient>')
    b = [f'<rect width="{W}" height="{H}" fill="url(#sky)"/>',
         '<circle cx="735" cy="120" r="120" fill="url(#sun)"/><circle cx="735" cy="120" r="54" fill="#FFE27A"/>',
         cloud(170, 110, 1.1, op=.95), cloud(470, 70, .8, op=.9), cloud(610, 200, .6, op=.85),
         # far island
         '<path d="M40 330 Q120 270 210 330 Z" fill="#7CC59A"/><path d="M180 330 Q230 300 280 330 Z" fill="#94D2A8"/>',
         # sea
         f'<rect y="325" width="{W}" height="140" fill="url(#water)"/>']
    for k in range(9):  # wave glints
        y = 345 + k * 13
        for _ in range(4):
            x = r.randint(0, W)
            b.append(f'<path d="M{x} {y} q12 -6 24 0" stroke="#E9FAFF" stroke-width="3" fill="none" stroke-linecap="round" opacity=".8"/>')
    # sailboat
    b.append('<g transform="translate(560 300)"><path d="M0 30 h70 l-12 14 h-46z" fill="#E96B4C"/><path d="M34 28 V-30 L70 24z" fill="#fff"/><path d="M30 28 V-14 L4 24z" fill="#FFF3E6"/></g>')
    # shore foam + sand
    b.append(f'<path d="M0 455 Q150 430 300 452 T600 450 T900 446 V{H} H0Z" fill="#fff" opacity=".9"/>')
    b.append(f'<path d="M0 470 Q160 448 320 466 T640 462 T900 458 V{H} H0Z" fill="url(#sand)"/>')
    for _ in range(70):  # sand speckles
        x, y = r.randint(0, W), r.randint(480, H)
        b.append(f'<circle cx="{x}" cy="{y}" r="{r.choice([1.5,2,2.5])}" fill="#D9AE6A" opacity=".55"/>')
    # palm tree left
    b.append('<path d="M110 640 C120 560 112 470 140 400" stroke="#A9773F" stroke-width="22" fill="none" stroke-linecap="round"/>')
    # fronds arch up and droop down at the tips
    for (ex, ey, qx, qy, c) in ((30, 470, 60, 370, '#3FA66B'), (55, 405, 85, 345, '#4DB577'), (140, 340, 120, 350, '#4DB577'),
                                (235, 400, 205, 340, '#4DB577'), (255, 470, 225, 370, '#3FA66B')):
        b.append(f'<path d="M140 400 Q{qx} {qy} {ex} {ey}" stroke="{c}" stroke-width="20" fill="none" stroke-linecap="round"/>')
        b.append(f'<path d="M140 400 Q{qx} {qy} {ex} {ey}" stroke="#2E8F57" stroke-width="2" fill="none" opacity=".6"/>')
    b.append('<circle cx="132" cy="412" r="11" fill="#7A5230"/><circle cx="152" cy="418" r="11" fill="#7A5230"/>')
    # umbrella + towel right
    b.append('<path d="M760 655 L735 470" stroke="#8C6A4A" stroke-width="7"/><path d="M640 500 Q735 400 830 470 Q735 455 640 500Z" fill="#FF8466"/><path d="M688 474 Q735 420 735 452Z M782 468 Q760 425 735 452Z" fill="#FFF3E6" opacity=".9"/>')
    b.append('<rect x="660" y="640" width="160" height="40" rx="10" fill="#78CDB5" transform="rotate(-4 740 660)"/><rect x="660" y="640" width="160" height="10" rx="5" fill="#FFF3E6" transform="rotate(-4 740 660)" opacity=".8"/>')
    # shells and starfish
    b.append('<g transform="translate(270 640) rotate(12)" fill="#FF9E7A"><path d="M0 -22 L6 -6 L22 -6 L9 4 L14 20 L0 10 L-14 20 L-9 4 L-22 -6 L-6 -6Z"/></g>')
    b.append('<path d="M600 700 q14 -26 28 0 z" fill="#FFD3C2"/><path d="M606 700 l8 -18 M614 700 v-20 M622 700 l-8 -18" stroke="#E9A58C" stroke-width="2"/>')
    b.append('<ellipse cx="200" cy="700" rx="12" ry="8" fill="#F3E3F0"/><circle cx="560" cy="610" r="6" fill="#FFF" opacity=".9"/>')
    return svg(''.join(b), defs)


# ---------------- forest ----------------
def tree(x, base, h, w, c1, c2, trunk='#8A5A35'):
    return (f'<rect x="{x-w*.07}" y="{base-h*.45}" width="{w*.14}" height="{h*.45}" rx="6" fill="{trunk}"/>'
            f'<ellipse cx="{x}" cy="{base-h*.62}" rx="{w*.55}" ry="{h*.32}" fill="{c1}"/>'
            f'<ellipse cx="{x-w*.22}" cy="{base-h*.74}" rx="{w*.32}" ry="{h*.22}" fill="{c2}"/>'
            f'<ellipse cx="{x+w*.2}" cy="{base-h*.8}" rx="{w*.3}" ry="{h*.2}" fill="{c1}"/>')


def forest():
    r = random.Random(11)
    defs = ('<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#BFE8D2"/><stop offset="1" stop-color="#EEF8E6"/></linearGradient>'
            '<linearGradient id="grass" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#9FD67F"/><stop offset="1" stop-color="#7EC266"/></linearGradient>'
            '<radialGradient id="light" cx=".5" cy="0" r=".9"><stop offset="0" stop-color="#FFF8D6" stop-opacity=".8"/><stop offset="1" stop-color="#FFF8D6" stop-opacity="0"/></radialGradient>')
    b = [f'<rect width="{W}" height="{H}" fill="url(#sky)"/>',
         '<path d="M0 360 Q150 250 320 330 T640 300 T900 330 V480 H0Z" fill="#A8D8B0"/>',
         '<path d="M0 410 Q200 320 420 390 T900 380 V500 H0Z" fill="#8CC99B"/>']
    for x in range(30, 900, 95):  # far tree line
        b.append(tree(x + r.randint(-15, 15), 470, 150 + r.randint(-20, 30), 110, '#6DB585', '#7FC394', '#6E5038'))
    b.append(f'<path d="M0 470 Q220 440 450 462 T900 456 V{H} H0Z" fill="url(#grass)"/>')
    b.append('<path d="M380 738 Q420 600 450 470 Q480 600 520 738Z" fill="#E9D7A6" opacity=".7"/>')  # path to the pet
    b.append(f'<rect width="{W}" height="{H}" fill="url(#light)"/>')
    # big trees at both sides, framing the middle
    b.append(tree(70, 700, 520, 300, '#4E9E63', '#63B276', '#7A4E2E'))
    b.append(tree(840, 700, 560, 320, '#4E9E63', '#5FAE72', '#7A4E2E'))
    b.append(tree(230, 660, 330, 190, '#5AAA6C', '#73BE83'))
    b.append(tree(690, 650, 300, 180, '#5AAA6C', '#73BE83'))
    for _ in range(60):  # grass tufts
        x, y = r.randint(0, W), r.randint(490, H)
        b.append(f'<path d="M{x} {y} l-5 -12 M{x} {y} l0 -15 M{x} {y} l5 -12" stroke="#5FA84E" stroke-width="2.5" stroke-linecap="round"/>')
    for _ in range(26):  # flowers
        x, y = r.randint(0, W), r.randint(500, H - 10)
        if 360 < x < 540 and y > 560:
            continue
        c = r.choice(['#FFFFFF', '#FFD36E', '#FF9EB5', '#C9A7FF'])
        b.append(f'<g transform="translate({x} {y})">' + ''.join(f'<circle cx="{6*math.cos(a)}" cy="{6*math.sin(a)}" r="4.5" fill="{c}"/>' for a in (0, 1.26, 2.51, 3.77, 5.03)) + '<circle r="3.5" fill="#F5A623"/></g>')
    # mushrooms
    for x, y, s in ((300, 690, 1), (330, 700, .7), (610, 680, .9)):
        b.append(f'<g transform="translate({x} {y}) scale({s})"><rect x="-8" y="-26" width="16" height="26" rx="6" fill="#FFF3E6"/><path d="M-30 -24 Q0 -62 30 -24Z" fill="#E96B4C"/><circle cx="-10" cy="-36" r="5" fill="#fff"/><circle cx="10" cy="-32" r="4" fill="#fff"/></g>')
    # butterflies + fireflies
    b.append('<g transform="translate(560 300)" fill="#FFB86B"><ellipse cx="-8" cy="0" rx="9" ry="12" transform="rotate(-20)"/><ellipse cx="8" cy="0" rx="9" ry="12" transform="rotate(20)"/></g>')
    b.append('<g transform="translate(330 250) scale(.8)" fill="#9BD3FF"><ellipse cx="-8" cy="0" rx="9" ry="12" transform="rotate(-20)"/><ellipse cx="8" cy="0" rx="9" ry="12" transform="rotate(20)"/></g>')
    for _ in range(14):
        b.append(f'<circle cx="{r.randint(150,750)}" cy="{r.randint(160,440)}" r="3" fill="#FFF7B0" opacity=".85"/>')
    return svg(''.join(b), defs)


# ---------------- stars ----------------
def star(x, y, s, c='#FFF7D6'):
    p = []
    for k in range(10):
        a = math.pi / 5 * k - math.pi / 2
        rad = s if k % 2 == 0 else s * .45
        p.append(f'{x + rad*math.cos(a):.1f},{y + rad*math.sin(a):.1f}')
    return f'<polygon points="{" ".join(p)}" fill="{c}"/>'


def stars():
    r = random.Random(23)
    defs = ('<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#241E52"/><stop offset=".6" stop-color="#4B3D8F"/><stop offset="1" stop-color="#8A6FC4"/></linearGradient>'
            '<linearGradient id="ground" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#C8B6EE"/><stop offset="1" stop-color="#A28CDA"/></linearGradient>'
            '<radialGradient id="glow"><stop offset="0" stop-color="#FFF4C2" stop-opacity=".7"/><stop offset="1" stop-color="#FFF4C2" stop-opacity="0"/></radialGradient>'
            '<radialGradient id="neb" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#FF9EC9" stop-opacity=".35"/><stop offset="1" stop-color="#FF9EC9" stop-opacity="0"/></radialGradient>')
    b = [f'<rect width="{W}" height="{H}" fill="url(#sky)"/>',
         '<ellipse cx="300" cy="200" rx="260" ry="110" fill="url(#neb)" transform="rotate(-18 300 200)"/>']
    for _ in range(140):  # tiny stars
        b.append(f'<circle cx="{r.randint(0,W)}" cy="{r.randint(0,470)}" r="{r.choice([1,1.2,1.6,2])}" fill="#fff" opacity="{r.choice([.5,.7,.9])}"/>')
    for x, y, s in ((120, 90, 9), (420, 60, 7), (560, 170, 10), (230, 300, 6), (820, 330, 8), (60, 380, 6), (700, 60, 6)):
        b.append(star(x, y, s))
    # moon + glow
    b.append('<circle cx="740" cy="150" r="120" fill="url(#glow)"/><circle cx="740" cy="150" r="58" fill="#FFF0B3"/><circle cx="764" cy="134" r="52" fill="#3A3077" opacity=".0"/>')
    b.append('<circle cx="722" cy="136" r="9" fill="#F2DE96"/><circle cx="756" cy="172" r="12" fill="#F2DE96"/><circle cx="760" cy="128" r="6" fill="#F2DE96"/>')
    # ringed planet
    b.append('<g transform="translate(170 210) rotate(-15)"><circle r="42" fill="#FFB58A"/><path d="M-42 -6 Q0 10 42 -6" stroke="#F08A6A" stroke-width="6" fill="none" opacity=".6"/><ellipse rx="78" ry="16" fill="none" stroke="#FFE3A6" stroke-width="7"/><path d="M-42 0 A42 42 0 0 0 42 0" fill="#FFB58A"/></g>')
    # shooting star
    b.append('<path d="M500 110 L610 70" stroke="#fff" stroke-width="3" stroke-linecap="round" opacity=".8"/>' + star(615, 68, 8))
    # small far planet
    b.append('<circle cx="600" cy="360" r="16" fill="#8DE0D0"/><circle cx="595" cy="355" r="5" fill="#B6F0E4"/>')
    # ground: a little planet surface
    b.append(f'<path d="M0 500 Q450 420 900 500 V{H} H0Z" fill="url(#ground)"/>')
    b.append(f'<path d="M0 520 Q450 446 900 520" stroke="#E2D6FA" stroke-width="4" fill="none" opacity=".7"/>')
    for x, y, rx in ((150, 600, 46), (300, 690, 30), (690, 610, 52), (800, 700, 28), (560, 700, 20)):  # craters
        b.append(f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{rx*.38}" fill="#9A84D2"/><ellipse cx="{x}" cy="{y-3}" rx="{rx*.8}" ry="{rx*.26}" fill="#8C75C8"/>')
    for _ in range(40):
        b.append(f'<circle cx="{r.randint(0,W)}" cy="{r.randint(520,H)}" r="2" fill="#E9E0FF" opacity=".6"/>')
    # rocket parked on the right, flag on the left
    b.append('<g transform="translate(780 520)"><path d="M0 -110 Q26 -80 26 -30 V30 H-26 V-30 Q-26 -80 0 -110Z" fill="#FFF3E6"/><circle cy="-50" r="13" fill="#78CDB5" stroke="#3F9E86" stroke-width="4"/>'
             '<path d="M-26 0 L-46 34 H-26Z M26 0 L46 34 H26Z" fill="#FF8466"/><path d="M-14 30 Q0 60 14 30Z" fill="#FFD36E"/></g>')
    b.append('<path d="M110 600 V500" stroke="#E2D6FA" stroke-width="5"/><path d="M110 500 h56 l-12 16 l12 16 h-56z" fill="#FF8466"/>')
    return svg(''.join(b), defs)


for name, fn in (('sea', sea), ('forest', forest), ('stars', stars)):
    with open(os.path.join(out, name + '.svg'), 'w', encoding='utf-8') as f:
        f.write(fn())
print('ok')
