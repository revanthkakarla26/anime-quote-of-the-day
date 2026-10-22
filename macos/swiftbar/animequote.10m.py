#!/usr/bin/env python3
"""Anime Quote of the Day menu bar plugin for SwiftBar."""

from __future__ import annotations

import json
import random
import sys
import subprocess
from datetime import date
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
PLUGIN = Path(__file__).resolve()
DATA_FILE = REPO / "quotes.json"
STATE_FILE = Path.home() / "Library" / "Application Support" / "Reva Widgets" / "animequote.json"
MASK = 0xFFFFFFFF


def shuffled(count: int, seed: int) -> list[int]:
    state = seed & MASK

    def next_float() -> float:
        nonlocal state
        state = (state + 0x6D2B79F5) & MASK
        value = state
        value = ((value ^ (value >> 15)) * (value | 1)) & MASK
        value ^= (value + (((value ^ (value >> 7)) * (value | 61)) & MASK)) & MASK
        return ((value ^ (value >> 14)) & MASK) / 4294967296

    deck = list(range(count))
    for i in range(count - 1, 0, -1):
        j = int(next_float() * (i + 1))
        deck[i], deck[j] = deck[j], deck[i]
    return deck


def daily_index(day: date, count: int) -> int:
    if count <= 0:
        return -1
    elapsed = (day - date(1970, 1, 1)).days
    round_number = elapsed // count
    deck = shuffled(count, round_number + 1)
    if count > 2 and deck[0] == shuffled(count, round_number)[-1]:
        deck[0], deck[1] = deck[1], deck[0]
    return deck[elapsed % count]


def clean(text: object) -> str:
    return " ".join(str(text).replace("|", "¦").split())


def quoted(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def row_action(label: str, action: str) -> str:
    return f"{label} | bash={quoted(str(PLUGIN))} param1={action} terminal=false refresh=true"


def load_state(day_key: str, count: int) -> dict:
    try:
        value = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        index = int(value.get("index", -1))
        if value.get("day") == day_key and value.get("mode") == "random" and 0 <= index < count:
            return value
    except (OSError, ValueError, TypeError):
        pass
    return {"day": day_key, "mode": "today", "index": -1}


def save_state(value: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    temporary = STATE_FILE.with_suffix(".tmp")
    temporary.write_text(json.dumps(value), encoding="utf-8")
    temporary.replace(STATE_FILE)


def main() -> None:
    data = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    characters = data.get("characters", {})
    quotes = [q for q in data.get("quotes", []) if q.get("text") and q.get("by") in characters]
    if not quotes:
        print("✦ Anime Quote")
        print("---")
        print("No quotes are available.")
        return

    today = date.today()
    day_key = today.isoformat()
    state = load_state(day_key, len(quotes))
    action = sys.argv[1] if len(sys.argv) > 1 else ""

    if action == "today":
        state = {"day": day_key, "mode": "today", "index": -1}
        save_state(state)
    elif action == "random":
        current = state["index"] if state["mode"] == "random" else daily_index(today, len(quotes))
        current_by = quotes[current].get("by") if current >= 0 else None
        choices = [i for i, quote in enumerate(quotes) if i != current and quote.get("by") != current_by]
        if not choices:
            choices = [i for i in range(len(quotes)) if i != current]
        if choices:
            state = {"day": day_key, "mode": "random", "index": random.choice(choices)}
            save_state(state)

    index = state["index"] if state["mode"] == "random" else daily_index(today, len(quotes))
    quote = quotes[index]
    character = characters[quote["by"]]
    name = clean(character.get("name", "Unknown character"))
    anime = clean(character.get("anime", ""))
    text = clean(quote["text"])
    if action == "notify":
        subtitle = f"{name} · {anime}" if anime else name
        notification = "on run argv\n  display notification (item 2 of argv) with title (item 1 of argv) subtitle (item 3 of argv)\nend run"
        subprocess.run(["osascript", "-e", notification, "Anime Quote", f"“{text}”", subtitle], check=False)
    title = f"✦ {name[:18]}"
    print(f"{title} | tooltip={quoted('“' + text + '” — ' + name)}")
    print("---")
    print(f"“{text}”")
    print(f"— {name}" + (f" · {anime}" if anime else ""))
    print("---")
    print(row_action("Random quote", "random"))
    print(row_action("Today's quote", "today"))
    print(row_action("Notify today's quote", "notify"))
    image = character.get("image")
    if image:
        image_path = (REPO / "images" / image)
        if image_path.is_file():
            print(f"View character portrait | href={image_path.as_uri()}")


if __name__ == "__main__":
    main()
