#!/usr/bin/env bash
# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
# Builds the Asset Library zip: <repo>-<version>/addons/<folder>/..., the tracked files without tests/, .release/ and
# the icon scripts (*.py). The version is plugin.cfg's. Output: .release/dist/<repo>-<version>.zip.
#   .release/make_zip.sh
set -euo pipefail
REPO=godot-waailand
ADDON=$(cd "$(dirname "$0")/.." && pwd)
FOLDER=$(basename "$ADDON")
VERSION=$(sed -n 's/^version="\(.*\)"$/\1/p' "$ADDON/plugin.cfg")
OUT="$ADDON/.release/dist/$REPO-$VERSION.zip"
mkdir -p "$ADDON/.release/dist"
rm -f "$OUT"
cd "$ADDON"
git ls-files | grep -vE '^(tests/|\.release/|\.gitignore$)|\.py$' | python3 -c '
import sys, zipfile
out, prefix = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in sys.stdin.read().splitlines():
        z.write(f, prefix + f)
' "$OUT" "$REPO-$VERSION/addons/$FOLDER/"
echo "$OUT"
