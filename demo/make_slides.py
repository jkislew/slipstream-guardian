#!/usr/bin/env python3
"""Render the demo slide deck as PNGs (1920x1080) for build-video.sh."""
import os
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "slides")
os.makedirs(OUT, exist_ok=True)

BG = (13, 17, 23)
FG = (230, 237, 243)
ACCENT = (88, 166, 255)
MUTED = (139, 148, 158)
GREEN = (63, 185, 80)
RED = (248, 81, 73)

SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"


def font(path, size):
    return ImageFont.truetype(path, size)


def wrap(draw, text, fnt, width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if draw.textlength(trial, font=fnt) <= width:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def slide(idx, title, body, accent=ACCENT, mono_lines=None, footer="Slipstream Guardian — Reactive Omni Buildathon"):
    img = Image.new("RGB", (1920, 1080), BG)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 1920, 10], fill=accent)
    d.text((110, 80), title, font=font(BOLD, 64), fill=FG)
    y = 210
    for para in body:
        for line in wrap(d, para, font(SANS, 40), 1700):
            d.text((110, y), line, font=font(SANS, 40), fill=FG)
            y += 56
        y += 28
    if mono_lines:
        y += 10
        d.rectangle([90, y - 14, 1830, y + 58 * len(mono_lines) + 22], fill=(22, 27, 34))
        for line in mono_lines:
            d.text((120, y), line, font=font(MONO, 36), fill=(165, 243, 165))
            y += 58
    d.text((110, 1000), footer, font=font(SANS, 28), fill=MUTED)
    img.save(os.path.join(OUT, f"slide-{idx:02d}.png"))
    print("slide", idx)


slide(1, "Slipstream Guardian",
      ["A stop-loss that fires itself.",
       "Reactive Omni Buildathon — Every Second Counts track.",
       "Base Sepolia ⇄ Reactive Lasna. No keeper bot. No human awake."])
slide(2, "The problem",
      ["A bot can die. A human sleeps.",
       "A stop-loss kept off-chain is a promise, not a guarantee.",
       "So we moved the stop-loss into a contract."])
slide(3, "Architecture", [
    "PriceFeed + GuardianVault live on Base Sepolia.",
    "StopLossReactive lives on Reactive Lasna and watches them.",
    "Events flow up. Decisions flow down as authenticated callbacks.",
], mono_lines=[
    "PriceUpdated ─► react() ─► protectPosition()",
    "  (origin)      (decide)      (execute)",
])
slide(4, "Opening a position", [
    "Deposit 1,000 USDX → buy 10 VOLT at $100.",
    "Stop-loss −10% · take-profit +25%.",
    "The vault's PositionOpened event teaches the reactive",
    "contract the position. Nothing is registered by hand.",
], mono_lines=["PositionOpened(user, entry=100e8, stop=1000, target=2500)"])
slide(5, "The crash", [
    "Price drops to $89 — through the stop.",
    "Lasna evaluates, fires exactly once, and the callback",
    "sells on Base Sepolia: 890 USDX credited to the user.",
], accent=RED, mono_lines=[
    "setPrice($89) ─► react() ─► ProtectionExecuted(890 USDX)",
])
slide(6, "Measured, not asserted", [
    "Full-loop latency is reconstructed from the chains:",
    "origin block timestamp → reactive block → callback block.",
], mono_lines=[
    "$ node scripts/measure-loop.mjs --origin <tx> ...",
    "FULL LOOP (origin -> protection): see RESULTS.md",
])
slide(7, "Under the hood", [
    "Cross-multiplied threshold math — no precision loss.",
    "Positions marked inactive before firing — no double-sell.",
    "Callbacks authenticated twice (proxy + injected sender).",
    "Both contracts self-funded and expose coverDebt().",
    "9/9 Foundry tests simulate the entire loop locally.",
], accent=GREEN)
slide(8, "The stop-loss is the contract",
      ["Slipstream Guardian",
       "github.com/jkislew/slipstream-guardian",
       "Code · tests · deployment runbook · latency harness"])

print("done ->", OUT)
