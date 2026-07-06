#!/usr/bin/env python3
"""Render the small-model-skills demo as a terminal animation -> media/demo.gif (+ poster).

No screen recording: frames are drawn with Pillow; the typing/streaming is synthesized.
The TEXT is a REAL capture — a local model (qwen3-coder-cc) that actually ran the read-only
`sys-diag` skill on the author's workstation (2026-07-06) and reported back, verbatim. One
middle paragraph is omitted for length and the shell prompt is genericized; the wording of
the model's answer is unchanged. Regenerate with:  python3 media/build-demo.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
MONO  = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
MONOB = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
W, H = 940, 520
BG   = (13, 17, 23)          # generic dark terminal
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
           "small-model-skills  —  Claude Code driving a local model, offline", font=chip, fill=MUT)
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

PROMPT = [("you@laptop", GRN), (":", MUT), ("~/project", BLUE), ("$ ", MUT)]

# 1) launch line (already typed) + comment
launch = [PROMPT + [("freeclaude", TXT), ("   # Claude Code -> a local model, offline", MUT)]]
# 2) type the plain-English question
q = "why is my computer slow?"
head = launch + [[("", TXT)]]
for i in range(len(q)+1):
    cur = [("> ", CYAN), (q[:i], TXT), ("_" if i < len(q) else "", MUT)]
    emit(head + [cur], 2)
ask = head + [[("> ", CYAN), (q, TXT)]]
emit(ask, 4)

# 3) the skill runs (read-only), then the answer streams in — real, genericized output
ans = [
    [("  . ran ", MUT), ("sys-diag", CYAN), ("  (read-only)", MUT)],
    [("", TXT)],
    [("  Based on the system diagnostics, your computer is slow primarily", TXT)],
    [("  because the llama-server process (PID 2906245) is consuming 93.9% of", TXT)],
    [("  CPU resources. This high CPU usage is causing the load average to be", TXT)],
    [("  very high (7.67, 12.84, 8.58) compared to your 24-core system.", TXT)],
    [("", TXT)],
    [("  I recommend considering whether you can stop or reduce the resource", TXT)],
    [("  usage of this llama-server process if it's not actively needed.", TXT)],
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
