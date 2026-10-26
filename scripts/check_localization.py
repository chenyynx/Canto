#!/usr/bin/env python3
"""Check the three iOS Localizable.strings tables for structural drift.

The app ships plain UTF-8 .strings files (one entry per line), so a small
line parser is enough here and avoids depending on macOS-only plutil.
"""
from collections import Counter
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "apple/ClashClient/Sources/AppArchitecture/AppLocalization"
LANGUAGES = ("en", "zh-Hans", "zh-Hant")
ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')


def read_table(language: str) -> tuple[dict[str, str], list[int]]:
    path = BASE / f"{language}.lproj/Localizable.strings"
    entries: dict[str, str] = {}
    duplicates: list[int] = []
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("//") or line.startswith("/*"):
            continue
        match = ENTRY.match(line)
        if not match:
            continue
        key, value = match.groups()
        if key in entries:
            duplicates.append(number)
        entries[key] = value
    return entries, duplicates


def main() -> int:
    tables = {language: read_table(language) for language in LANGUAGES}
    failed = False

    for language, (entries, duplicates) in tables.items():
        if duplicates:
            failed = True
            print(f"{language}: duplicate keys at lines {duplicates[:10]}")
        print(f"{language}: {len(entries)} keys")

    reference = set(tables["en"][0])
    for language in LANGUAGES[1:]:
        keys = set(tables[language][0])
        missing = sorted(reference - keys)
        extra = sorted(keys - reference)
        if missing:
            failed = True
            print(f"{language}: missing {len(missing)} keys, first {missing[:10]}")
        if extra:
            failed = True
            print(f"{language}: extra {len(extra)} keys, first {extra[:10]}")

    # Placeholder drift would crash or print a literal %@ at runtime.
    # Positional forms (%1$@) are equivalent to repeated %@ for counting.
    placeholders = re.compile(r"%(?:\d+\$)?([@d])")
    for key in sorted(reference):
        expected = Counter(placeholders.findall(key))
        for language in LANGUAGES:
            value = tables[language][0].get(key, "")
            found = Counter(placeholders.findall(value))
            if expected != found:
                failed = True
                print(
                    f"{language}: placeholder mismatch for {key!r}: "
                    f"key={dict(expected)} value={dict(found)}"
                )

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
