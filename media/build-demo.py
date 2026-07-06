#!/usr/bin/env python3
"""Render the small-model-skills demo as a terminal animation -> media/demo.gif (+ poster).

No screen recording: frames are drawn with Pillow; the typing/streaming is synthesized.
The content is a REAL capture on the author's workstation (2026-07-06): a local model
(qwen3-coder-cc) ran the read-only `router-status` skill, which reads the WAN links off a
SonicWall over SNMP + REST — offline. The interface table + verdict are that wrapper's
verbatim output; the closing two lines are the model's own verbatim verdict (the gateway IP
it mentioned is omitted). Nothing is invented. Regenerate with:  python3 media/build-demo.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
MONO  = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
MONOB = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
W, H = 960, 600
BG   = (13, 17, 23)
CARD = (22, 27, 34); EDGE = (48, 54, 61)
TXT  = (230, 237, 243); MUT = (139, 148, 158)
GRN  = (63, 185, 80); BLUE = (88, 166, 255); CYAN = (57, 197, 187); AMBER = (240, 180, 60)
FS = 19
mono  = ImageFont.truetype(MONO, FS)
monob = ImageFont.truetype(MONOB, FS)
chip  = ImageFont.truetype(MONOB, 16)
LH = int(FS * 1.34); PAD = 34
CARD_XY = (26, 22, W-26, H-22)

def base():
    img = Image.new("RGB", (W, H), BG); d = ImageDraw.Draw(img)
    d.rounded_rectangle(CARD_XY, radius=14, fill=CARD, outline=EDGE, width=2)
    for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        x = CARD_XY[0] + PAD + i*26
        d.ellipse([x, CARD_XY[1]+22, x+13, CARD_XY[1]+35], fill=c)
    d.text((CARD_XY[0]+PAD+104, CARD_XY[1]+21),
           "small-model-skills  —  a local model reads your firewall, offline", font=chip, fill=MUT)
    d.line([CARD_XY[0]+PAD, CARD_XY[1]+56, CARD_XY[2]-PAD, CARD_XY[1]+56], fill=(33, 38, 45), width=2)
    return img, d

def put(d, lines):
    x = CARD_XY[0]+PAD; y = CARD_XY[1]+76
    for segs in lines:
        cx = x
        for t, c, *b in segs:
            f = monob if (b and b[0]) else mono
            d.text((cx, y), t, font=f, fill=c)
            cx += d.textlength(t, font=mono)
        y += LH

frames = []
def emit(lines, n=1):
    img, d = base(); put(d, lines)
    for _ in range(n): frames.append(img.copy())

PROMPT = [("you@laptop", GRN), (":", MUT), ("~", BLUE), ("$ ", MUT)]
launch = [PROMPT + [("freeclaude", TXT), ("   # Claude Code -> a local model, offline", MUT)]]

# type the plain-English question
q = "is my internet flaky? check the firewall's WAN links."
head = launch + [[("", TXT)]]
for i in range(len(q)+1):
    emit(head + [[("> ", CYAN), (q[:i], TXT), ("_" if i < len(q) else "", MUT)]], 2)
ask = head + [[("> ", CYAN), (q, TXT)]]
emit(ask, 4)

# the skill runs router-status (real, verbatim output), then the model's verbatim verdict
ans = [
    [("  . ran ", MUT), ("router-status", CYAN), ("   (read-only: SNMP + REST to the router)", MUT)],
    [("", TXT)],
    [("  IFACE  LINK  IN/s        OUT/s", MUT)],
    [("  X0     ", TXT), ("UP", GRN), ("    18 KB/s     11 KB/s", TXT)],
    [("  X1     ", TXT), ("UP", GRN), ("    32 KB/s     35 KB/s", TXT)],
    [("  X2     ", TXT), ("UP", GRN), ("    32 B/s      58 B/s", TXT)],
    [("  verdict: ", MUT), ("X1 (primary ISP) link UP and carrying traffic", GRN), (" -> normal path", MUT)],
    [("  detail:  SonicWall TZ 370  |  LB group: preempt=true, final_backup=X2", MUT)],
    [("", TXT)],
    [("  ", TXT), ("->", CYAN), (" You're using the primary ISP; there's no indication of failover to", TXT)],
    [("     a backup link. Your internet connection is active and stable.", TXT)],
]
shown = []
for line in ans:
    shown.append(line)
    emit(ask + shown, 3)
emit(ask + shown, 34)   # hold

FPS = 12
gif = os.path.join(HERE, "demo.gif")
frames[0].save(gif, save_all=True, append_images=frames[1:], duration=int(1000/FPS), loop=0, optimize=True)
frames[-1].save(os.path.join(HERE, "demo-poster.png"))
print(f"frames: {len(frames)}  ->  {gif} ({os.path.getsize(gif)//1024} KB), demo-poster.png")
