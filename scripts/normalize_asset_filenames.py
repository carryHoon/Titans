#!/usr/bin/env python3
"""Normalize Assets.xcassets image filenames to fix Unicode (NFC/NFD) mismatches.

Background
----------
When Korean-named logo images are added on macOS, the on-disk filename may be
stored in NFD form while the imageset's Contents.json references it in NFC form
(or vice versa). The two look identical in Finder/Xcode but differ at the byte
level, so `actool` emits a warning/error for every affected imageset at build
time. This script snaps each Contents.json `filename` to the exact bytes of the
file that actually exists on disk.

It only rewrites the `filename` value bytes; Xcode's JSON formatting is left
untouched, so diffs stay minimal. Run it after adding/renaming any image assets:

    python3 scripts/normalize_asset_filenames.py            # apply fixes
    python3 scripts/normalize_asset_filenames.py --check    # report only (CI-friendly, exits 1 if issues)
"""
import os, sys, json, glob, unicodedata

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "Titans", "Assets.xcassets")
IMG_EXT = {".png", ".jpg", ".jpeg", ".pdf", ".svg", ".gif"}


def process(check_only: bool) -> int:
    issues = 0
    for d in sorted(glob.glob(os.path.join(ROOT, "**", "*.imageset"), recursive=True)):
        cj = os.path.join(d, "Contents.json")
        if not os.path.exists(cj):
            continue
        disk = [f for f in os.listdir(d) if os.path.splitext(f)[1].lower() in IMG_EXT]
        by_nfc = {unicodedata.normalize("NFC", f): f for f in disk}
        raw = open(cj, encoding="utf-8").read()
        data = json.loads(raw)
        new = raw
        for im in data.get("images", []):
            fn = im.get("filename")
            if not fn or fn in disk:
                continue
            cand = by_nfc.get(unicodedata.normalize("NFC", fn))
            if cand and cand != fn:
                issues += 1
                print(f"  {os.path.basename(d)}: '{fn}' -> on-disk bytes")
                new = new.replace('"' + fn + '"', '"' + cand + '"')
        if new != raw and not check_only:
            open(cj, "w", encoding="utf-8").write(new)
    return issues


def main():
    check_only = "--check" in sys.argv
    print(f"Scanning {ROOT} ...")
    n = process(check_only)
    if n == 0:
        print("All imageset filenames match on-disk bytes. Nothing to do.")
        return 0
    print(f"\n{'Found' if check_only else 'Fixed'} {n} filename mismatch(es).")
    return 1 if check_only else 0


if __name__ == "__main__":
    sys.exit(main())
