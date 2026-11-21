#!/usr/bin/env bash
# Copy PoleSimGear's tracked files into the WoW: Forever AddOns folder (the previous copy goes to a
# backup, and comes back if the copy fails). A new .lua file needs a full game restart; changed files
# need /reload.
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="${WOW_ADDONS:-/mnt/games/BattleNet/World of Warcraft/_forever_/Interface/AddOns}"
BAK="${POLESIMGEAR_BACKUP:-$HOME/.cache/polesim-gear/PoleSimGear.bak}"
[ -d "$DEST/Polestar" ] || { echo "no Polestar in $DEST" >&2; exit 1; }
mapfile -t FILES < <(git ls-files PoleSimGear)
[ "${#FILES[@]}" -gt 0 ] || { echo "no tracked files under PoleSimGear" >&2; exit 1; }
for f in "${FILES[@]}"; do
  case "$f" in *.lua) luac5.1 -p "$f" ;; esac
done
had_backup=0
if [ -d "$DEST/PoleSimGear" ]; then
  mkdir -p "$(dirname "$BAK")"
  rm -rf "$BAK"
  mv "$DEST/PoleSimGear" "$BAK"
  had_backup=1
fi
restore() {
  rm -rf "$DEST/PoleSimGear"
  if [ "$had_backup" = 1 ]; then
    mv "$BAK" "$DEST/PoleSimGear"
    echo "copy failed: the previous PoleSimGear is back" >&2
  else
    echo "copy failed: nothing installed" >&2
  fi
}
trap restore ERR
for f in "${FILES[@]}"; do
  mkdir -p "$DEST/$(dirname "$f")"
  cp "$f" "$DEST/$f"
done
trap - ERR
echo "installed ${#FILES[@]} files into $DEST/PoleSimGear ($(grep '^## Version' PoleSimGear/PoleSimGear.toc))"
