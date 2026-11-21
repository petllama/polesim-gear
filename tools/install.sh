#!/usr/bin/env bash
# Copy PoleSimGear into the WoW: Forever AddOns folder (the previous copy goes to a backup).
# A new .lua file needs a full game restart; changed files need /reload.
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="${WOW_ADDONS:-/mnt/games/BattleNet/World of Warcraft/_forever_/Interface/AddOns}"
[ -d "$DEST/Polestar" ] || { echo "no Polestar in $DEST" >&2; exit 1; }
for f in PoleSimGear/*.lua PoleSimGear/Data/*.lua; do luac5.1 -p "$f"; done
if [ -d "$DEST/PoleSimGear" ]; then
  mkdir -p "$HOME/.cache/polesim-gear"
  rm -rf "$HOME/.cache/polesim-gear/PoleSimGear.bak"
  mv "$DEST/PoleSimGear" "$HOME/.cache/polesim-gear/PoleSimGear.bak"
fi
cp -r PoleSimGear "$DEST/PoleSimGear"
echo "installed into $DEST/PoleSimGear ($(grep '^## Version' PoleSimGear/PoleSimGear.toc))"
