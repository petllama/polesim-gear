#!/usr/bin/env bash
# Zip PoleSimGear for GitHub and CurseForge: PoleSimGear-<version>.zip with only the PoleSimGear folder at
# the zip's root; README.md (Polestar is required), LICENSE and NOTICE.md are copied into that folder. Only tracked files, as committed (git archive of HEAD): the
# working tree must be clean. The version is the TOC's. The zip is written outside the repository
# (PSG_DIST, default ~/.hermes/cache/scratch/polesim-gear-dist). Nothing is published.
set -euo pipefail
cd "$(dirname "$0")/.."
DIST="${PSG_DIST:-$HOME/.hermes/cache/scratch/polesim-gear-dist}"
case "$(realpath -m "$DIST")/" in "$(pwd -P)/"*) echo "PSG_DIST must be outside the repository" >&2; exit 1 ;; esac
[ -z "$(git status --porcelain -- PoleSimGear README.md LICENSE NOTICE.md)" ] || { echo "uncommitted changes to the addon: commit first" >&2; exit 1; }
git ls-files --error-unmatch README.md LICENSE NOTICE.md PoleSimGear/PoleSimGear.toc > /dev/null
mapfile -t LUA < <(git ls-files 'PoleSimGear/*.lua')
for f in "${LUA[@]}"; do luac5.1 -p "$f"; done
luajit tests/run.lua
lua5.1 tests/run.lua
v=$(sed -n 's/^## Version: //p' PoleSimGear/PoleSimGear.toc | tr -d '\r')
[ -n "$v" ] || { echo "no ## Version in the TOC" >&2; exit 1; }
mkdir -p "$DIST"
out="$DIST/PoleSimGear-$v.zip"
# Only the PoleSimGear folder at the zip's root (CurseForge and its app unpack every top-level entry into
# AddOns): README.md, LICENSE and NOTICE.md go inside it.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git archive --format=tar HEAD PoleSimGear README.md LICENSE NOTICE.md | tar -x -C "$tmp"
mv "$tmp/README.md" "$tmp/LICENSE" "$tmp/NOTICE.md" "$tmp/PoleSimGear/"
rm -f "$out"
(cd "$tmp" && TZ=UTC find PoleSimGear -exec touch -d '1980-01-02 00:00:00' {} + && find PoleSimGear -print | LC_ALL=C sort | zip -X -9 -q "$out" -@)
[ "$(unzip -Z1 "$out" | cut -d/ -f1 | sort -u)" = "PoleSimGear" ] || { echo "zip root is not just PoleSimGear/" >&2; exit 1; }
ls -l "$out"
