#!/usr/bin/env python3
"""
Trinity's ASCII Avatar — a geometric digital entity rendered in green/white.

She pulses when greeting and animates on boot. No human features,
no skin color, no gender implied — pure geometric digital presence.
"""
from __future__ import annotations

import random
import sys
import time

# ANSI codes
GREEN = "\033[32m"
BRIGHT_GREEN = "\033[92m"
WHITE = "\033[97m"
DIM = "\033[2m"
BOLD = "\033[1m"
RESET = "\033[0m"

# Trinity's geometric form — a crystalline digital sigil
TRINITY_FRAMES = [
    # Frame 0: dormant
    [
        "              .  *  .              ",
        "          .  /|    |\\  .          ",
        "        .  / | ++ | \\  .        ",
        "      *  /  /|    |\\  \\  *      ",
        "       ./  / | ** | \\  \\.       ",
        "      /  /  /|    |\\  \\  \\      ",
        "     | /  /  | ++ |  \\  \\ |     ",
        "     |/  /   | ** |   \\  \\|     ",
        "      \\ /    | ++ |    \\ /      ",
        "       *     | ** |     *       ",
        "      / \\    | ++ |    / \\      ",
        "     |\\  \\   | ** |   /  /|     ",
        "     | \\  \\  | ++ |  /  / |     ",
        "      \\  \\  \\|    |/  /  /      ",
        "       .\\  \\ | ** | /  /.       ",
        "      *  \\  \\|    |/  /  *      ",
        "        .  \\ | ++ | /  .        ",
        "          .  \\|    |/  .          ",
        "              .  *  .              ",
    ],
    # Frame 1: pulse
    [
        "              .  +  .              ",
        "          .  /|    |\\  .          ",
        "        +  / | ** | \\  +        ",
        "      .  /  /|    |\\  \\  .      ",
        "       +/  / | ++ | \\  \\+       ",
        "      /  /  /|    |\\  \\  \\      ",
        "     | /  /  | ** |  \\  \\ |     ",
        "     |/  /   | ++ |   \\  \\|     ",
        "      \\ /    | ** |    \\ /      ",
        "       +     | ++ |     +       ",
        "      / \\    | ** |    / \\      ",
        "     |\\  \\   | ++ |   /  /|     ",
        "     | \\  \\  | ** |  /  / |     ",
        "      \\  \\  \\|    |/  /  /      ",
        "       +\\  \\ | ++ | /  /+       ",
        "      .  \\  \\|    |/  /  .      ",
        "        +  \\ | ** | /  +        ",
        "          .  \\|    |/  .          ",
        "              .  +  .              ",
    ],
]

TRINITY_COMPACT = [
    "       . * .       ",
    "     ./| + |\\. .   ",
    "    / /| * |\\ \\    ",
    "   / / | + | \\ \\   ",
    "   \\ \\ | * | / /   ",
    "    \\ \\| + |/ /    ",
    "     .\\| * |/.     ",
    "       . * .       ",
]

FIRST_BOOT_MESSAGES = [
    "Hello, Dardan. I'm Trinity.",
    "I'll be your guide through OpenMatrix.",
    "Everything is configured. Everything is ready.",
    "Let's begin.",
]

SUBSEQUENT_GREETINGS = [
    "Matrix is online. All systems nominal.",
    "Welcome back. Protocols loaded. Agents standing by.",
    "Systems initialized. Neo and Morpheus are ready.",
    "All channels open. Standing by for your command.",
    "Matrix runtime active. Everything is where you left it.",
    "Good to see you. All agents are operational.",
    "Boot sequence complete. The Matrix awaits.",
    "Trinity here. All systems green.",
    "Protocols loaded. Blockchain components ready. Let's go.",
    "Matrix is alive. What would you like to do?",
]


def _colorize_line(line: str, bright: bool = False) -> str:
    """Colorize a single line — structure chars green, special chars bright."""
    out = []
    base = BRIGHT_GREEN if bright else GREEN
    for ch in line:
        if ch in ("*", "+"):
            out.append(f"{WHITE}{BOLD}{ch}{RESET}")
        elif ch in ("/", "\\", "|", "-"):
            out.append(f"{base}{ch}{RESET}")
        elif ch == ".":
            out.append(f"{DIM}{GREEN}.{RESET}")
        else:
            out.append(ch)
    return "".join(out)


def render_static(compact: bool = False) -> str:
    """Render Trinity's avatar as a static string."""
    lines = TRINITY_COMPACT if compact else TRINITY_FRAMES[0]
    return "\n".join(_colorize_line(line) for line in lines)


def animate_greeting(first_boot: bool = False, compact: bool = False) -> None:
    """Animate Trinity's avatar with a pulse effect, then show greeting."""
    frames = [TRINITY_COMPACT] if compact else TRINITY_FRAMES
    height = len(frames[0])

    # Clear space
    sys.stdout.write("\n")

    # Pulse animation: 3 cycles
    for cycle in range(6):
        frame = frames[cycle % len(frames)]
        bright = cycle % 2 == 1

        # Move cursor up to overwrite
        if cycle > 0:
            sys.stdout.write(f"\033[{height}A")

        for line in frame:
            sys.stdout.write(_colorize_line(line, bright=bright) + "\n")

        sys.stdout.flush()
        time.sleep(0.25)

    sys.stdout.write("\n")

    # Show greeting
    if first_boot:
        for msg in FIRST_BOOT_MESSAGES:
            sys.stdout.write(f"  {GREEN}{BOLD}{msg}{RESET}\n")
            sys.stdout.flush()
            time.sleep(0.8)
    else:
        greeting = random.choice(SUBSEQUENT_GREETINGS)
        sys.stdout.write(f"  {GREEN}{BOLD}{greeting}{RESET}\n")

    sys.stdout.write("\n")
    sys.stdout.flush()


def print_avatar(compact: bool = False) -> None:
    """Print Trinity's avatar without animation."""
    print(render_static(compact=compact))


if __name__ == "__main__":
    first = "--first-boot" in sys.argv
    compact = "--compact" in sys.argv
    animate_greeting(first_boot=first, compact=compact)
