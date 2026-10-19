#!/usr/bin/env python3
"""gate-failures.py <annotations.json> — ile razy która bramka Platform zatrzymała konsumentów (N-SHOW-8).

Wejście: lista adnotacji check-runów nieudanych przebiegów konsumentów, każda jako
{"repo": "...", "pin": "1.6.0", "completed_at": "2026-10-19T10:00:00Z", "title": "PLAT-DEP-001", "message": "..."}
— zebrana lokalnie przez gh api, jak opisuje docs/gates.md (konsumenci są prywatni, Decyzja 32).
Wyjście: tabela Markdown liczników na kod, tydzień ISO i pin Platform; tylko agregaty, bez treści komunikatów.
"""
import collections
import datetime
import json
import re
import sys

CODE = re.compile(r"PLAT-[A-Z]+-[0-9]{3}")


def main(path: str) -> int:
    with open(path, encoding="utf-8") as source:
        annotations = json.load(source)
    counts = collections.Counter()
    for annotation in annotations:
        match = CODE.search(annotation.get("title", "")) or CODE.search(annotation.get("message", ""))
        if not match:
            continue
        day = datetime.date.fromisoformat(annotation["completed_at"][:10])
        year, week, _ = day.isocalendar()
        counts[(match.group(0), f"{year}-W{week:02d}", annotation.get("pin", "unknown"))] += 1
    print("| Code | Week | Platform pin | Failures |")
    print("|---|---|---|---|")
    for (code, week, pin), count in sorted(counts.items(), key=lambda item: (item[0][1], -item[1], item[0][0])):
        print(f"| {code} | {week} | {pin} | {count} |")
    if not counts:
        print("| — | — | — | 0 |")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: scripts/gate-failures.py <annotations.json>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
