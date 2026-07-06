#!/usr/bin/env python3
"""Render the small-model-skills demo as a terminal animation -> media/demo.gif (+ poster).

No screen recording: frames are drawn with Pillow; a scrolling terminal viewport is synthesized.
One offline session, two REAL captures on the author's workstation (2026-07-06) with a local model
(qwen3-coder-cc):
  1. router-status reading a SonicWall's WAN links + failover over SNMP + REST (wrapper output +
     the model's verbatim verdict);
  2. sys-diag finding why the box is slow (the model's verbatim answer).
Wrapper tables/verdicts are verbatim; the model's replies are verbatim (one gateway IP omitted).
Nothing is invented. Regenerate with:  python3 media/build-demo.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
MONO  = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
MONOB = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
W, H = 960, 560
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
TOP = CARD_XY[1] + 76
MAX_LINES = (CARD_XY[3] - TOP - 12) // LH

def base():
    img = Image.new("RGB", (W, H), BG); d = ImageDraw.Draw(img)
    d.rounded_rectangle(CARD_XY, radius=14, fill=CARD, outline=EDGE, width=2)
    for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        x = CARD_XY[0] + PAD + i*26
        d.ellipse([x, CARD_XY[1]+22, x+13, CARD_XY[1]+35], fill=c)
    d.text((CARD_XY[0]+PAD+104, CARD_XY[1]+21),
           "small-model-skills  —  a small local model, offline", font=chip, fill=MUT)
    d.line([CARD_XY[0]+PAD, CARD_XY[1]+56, CARD_XY[2]-PAD, CARD_XY[1]+56], fill=(33, 38, 45), width=2)
    return img, d

history = []                       # every line printed so far (scrolling viewport shows the tail)
frames = []
def render(hold=1):
    img, d = base()
    x = CARD_XY[0]+PAD; y = TOP
    for segs in history[-MAX_LINES:]:
        cx = x
        for t, c, *b in segs:
            d.text((cx, y), t, font=(monob if (b and b[0]) else mono), fill=c)
            cx += d.textlength(t, font=mono)
        y += LH
    for _ in range(hold): frames.append(img.copy())

PROMPT = [("you@laptop", GRN), (":", MUT), ("~", BLUE), ("$ ", MUT)]

def ask(q, answer, read_hold):
    history.append([("> ", CYAN), ("", TXT)])          # a fresh Claude Code prompt
    for i in range(1, len(q)+1):                       # type the question
        history[-1] = [("> ", CYAN), (q[:i], TXT), ("_" if i < len(q) else "", MUT)]
        render(2)
    history[-1] = [("> ", CYAN), (q, TXT)]; render(6)
    for line in answer:                                # stream the answer
        history.append(line); render(3)
    render(read_hold)                                  # PAUSE so it can be read
    history.append([("", TXT)])                        # spacer before the next prompt

# one session
history.append(PROMPT + [("freeclaude", TXT), ("   # Claude Code -> a local model, offline", MUT)])
history.append([("", TXT)]); render(6)

Q1 = "is my internet flaky? check the firewall's WAN links."
A1 = [
    [("  . ran ", MUT), ("router-status", CYAN), ("   (read-only: SNMP + REST to the router)", MUT)],
    [("", TXT)],
    [("  IFACE  LINK  IN/s        OUT/s", MUT)],
    [("  X0     ", TXT), ("UP", GRN), ("    18 KB/s     11 KB/s", TXT)],
    [("  X1     ", TXT), ("UP", GRN), ("    32 KB/s     35 KB/s", TXT)],
    [("  X2     ", TXT), ("UP", GRN), ("    32 B/s      58 B/s", TXT)],
    [("  verdict: ", MUT), ("X1 (primary ISP) link UP and carrying traffic", GRN), (" -> normal path", MUT)],
    [("  detail:  SonicWall TZ 370  |  LB group: preempt=true, final_backup=X2", MUT)],
    [("", TXT)],
    [("  ", TXT), ("->", CYAN), (" You're using the primary ISP; there's no indication of failover", TXT)],
    [("     to a backup link. Your internet connection is active and stable.", TXT)],
]

Q2 = "why is my computer slow?"
A2 = [
    [("  . ran ", MUT), ("sys-diag", CYAN), ("   (read-only)", MUT)],
    [("", TXT)],
    [("  ", TXT), ("->", CYAN), (" Based on the system diagnostics, your computer is slow primarily", TXT)],
    [("     because the llama-server process (PID 2906245) is consuming 93.9%", TXT)],
    [("     of CPU resources. This high CPU usage is causing the load average", TXT)],
    [("     to be very high (7.67, 12.84, 8.58) compared to your 24-core system.", TXT)],
    [("", TXT)],
    [("     I recommend considering whether you can stop or reduce the resource", TXT)],
    [("     usage of this llama-server process if it's not actively needed.", TXT)],
]

ask(Q1, A1, read_hold=54)   # ~4.5s to read the firewall output
ask(Q2, A2, read_hold=72)   # ~6s to read + hold at the end

FPS = 12
gif = os.path.join(HERE, "demo.gif")
frames[0].save(gif, save_all=True, append_images=frames[1:], duration=int(1000/FPS), loop=0, optimize=True)
frames[-1].save(os.path.join(HERE, "demo-poster.png"))
print(f"frames: {len(frames)}  ->  {gif} ({os.path.getsize(gif)//1024} KB), demo-poster.png (MAX_LINES={MAX_LINES})")
