#!/usr/bin/env python3
"""Adds strings with their Ukrainian translations to a String Catalog.

Usage: scripts/strings.py <Localizable.xcstrings> <entries.json>
entries.json maps an English key to its Ukrainian text, or to {"uk": "...", "comment": "..."}.
An existing key gets the new translation. Keys stay sorted the way Xcode writes them.
"""
import json
import sys

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
    entry["localizations"] = {"uk": {"stringUnit": {"state": "translated", "value": value["uk"]}}}
catalog["strings"] = dict(sorted(strings.items(), key=lambda item: item[0].lower()))

with open(catalog_path, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2, separators=(",", " : "))
    f.write("\n")
