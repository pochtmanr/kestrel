#!/usr/bin/env bash
# Copies a studio export into the folders the upload lanes read:
#   out/<variant>/ios/<locale>/  (iphone_*, ipad_*)  → fastlane/screenshots/<locale>/
#   out/<variant>/duo/<locale>/  (duo_*)             → fastlane/screenshots-duo/<locale>/
# Each target locale folder is emptied first, so a slide removed from the studio does not linger
# (upload_screenshots replaces the whole set of every locale it finds on disk).
#
#   scripts/collect.sh                 # variant A, every exported locale
#   scripts/collect.sh C en-US de-DE   # variant C, only these locales
set -eo pipefail  # no -u: macOS bash 3.2 treats an empty array as unbound

STUDIO="$(cd "$(dirname "$0")/.." && pwd)"
FASTLANE="$(cd "$STUDIO/.." && pwd)"
VARIANT="${1:-A}"
shift || true

SRC="$STUDIO/out/$VARIANT"
[ -d "$SRC" ] || { echo "No export at $SRC. Run: node server.mjs export --variants $VARIANT --devices iphone,ipad,duo --locales en-US" >&2; exit 1; }

copy_set() { # <kind: ios|duo> <dest root>
  local kind="$1" dest="$2" locales=("${@:3}")
  [ -d "$SRC/$kind" ] || { echo "skip $kind: nothing exported"; return; }
  if [ ${#locales[@]} -eq 0 ]; then
    locales=()
    for d in "$SRC/$kind"/*/; do locales+=("$(basename "$d")"); done
  fi
  for loc in "${locales[@]}"; do
    local from="$SRC/$kind/$loc"
    [ -d "$from" ] || { echo "skip $kind/$loc: not exported"; continue; }
    mkdir -p "$dest/$loc"
    find "$dest/$loc" -maxdepth 1 -type f \( -name '*.jpg' -o -name '*.png' \) -delete
    cp "$from"/*.jpg "$dest/$loc/" 2>/dev/null || cp "$from"/*.png "$dest/$loc/"
    echo "$kind/$loc → ${dest#"$FASTLANE"/}/$loc ($(find "$dest/$loc" -maxdepth 1 -type f | wc -l | tr -d ' ') files)"
  done
}

copy_set ios "$FASTLANE/screenshots" "$@"
copy_set duo "$FASTLANE/screenshots-duo" "$@"
