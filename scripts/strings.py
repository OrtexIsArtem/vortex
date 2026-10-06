#!/usr/bin/env python3
"""Adds strings with their Ukrainian translations to a String Catalog.

Usage: scripts/strings.py <Localizable.xcstrings> <entries.json>
entries.json maps an English key to its Ukrainian text, or to {"uk": "...", "comment": "..."}.
An existing key gets the new uk translation; its other languages and fields stay as they are. A uk translation with
plural variations is left alone, with a warning: edit it in Xcode. Keys stay sorted the way Xcode writes them.
"""
import json
import sys

if len(sys.argv) != 3:
    print(__doc__.strip(), file=sys.stderr)
    sys.exit(2)

catalog_path, entries_path = sys.argv[1], sys.argv[2]
with open(catalog_path, encoding="utf-8") as f:
    catalog = json.load(f)
with open(entries_path, encoding="utf-8") as f:
    entries = json.load(f)

strings = catalog.setdefault("strings", {})
for key, value in entries.items():
    if isinstance(value, str):
        value = {"uk": value}
    entry = strings.setdefault(key, {})
    if "comment" in value:
        entry["comment"] = value["comment"]
    localizations = entry.setdefault("localizations", {})
    if "variations" in localizations.get("uk", {}):
        print(f"warning: {key!r} has plural variations in uk, left as it is; edit it in Xcode", file=sys.stderr)
        continue
    localizations["uk"] = {"stringUnit": {"state": "translated", "value": value["uk"]}}
catalog["strings"] = dict(sorted(strings.items(), key=lambda item: item[0].lower()))

with open(catalog_path, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2, separators=(",", " : "))
    f.write("\n")
