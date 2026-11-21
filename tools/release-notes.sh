#!/usr/bin/env bash
# Print the release notes of one version: its "**<version> over <previous>:**" paragraph in
# docs/CHECKLIST.md (the in-game changes and what to check), with the bold label dropped.
# Usage: tools/release-notes.sh <version>
set -euo pipefail
cd "$(dirname "$0")/.."
v="${1:?usage: tools/release-notes.sh <version>}"
notes=$(awk -v v="$v" '
	index($0, "**" v " over ") == 1 { on = 1 }
	on && /^$/ { exit }
	on { print }
' docs/CHECKLIST.md | sed -E 's/^\*\*[0-9.]+ over [0-9.]+:\*\* ?//')
if [ -z "$notes" ]; then
	notes="PoleSim Gear $v."
fi
printf '%s\n\nInstall: unzip into `World of Warcraft/_forever_/Interface/AddOns/` (a new install needs a game restart; an update needs `/reload`). Requires Polestar.\n' "$notes"
