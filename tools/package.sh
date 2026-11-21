#!/usr/bin/env bash
# Zip PoleSimGear for a manual install: PoleSimGear-<version>.zip with the PoleSimGear folder at the
# zip's root, plus LICENSE and NOTICE.md. Only tracked files, as committed (git archive of HEAD): the
# working tree must be clean. The version is the TOC's. The zip is written outside the repository
# (PSG_DIST, default ~/.hermes/cache/scratch/polesim-gear-dist). Nothing is published.
set -euo pipefail
cd "$(dirname "$0")/.."
DIST="${PSG_DIST:-$HOME/.hermes/cache/scratch/polesim-gear-dist}"
case "$(realpath -m "$DIST")/" in "$(pwd -P)/"*) echo "PSG_DIST must be outside the repository" >&2; exit 1 ;; esac
[ -z "$(git status --porcelain -- PoleSimGear LICENSE NOTICE.md)" ] || { echo "uncommitted changes to the addon: commit first" >&2; exit 1; }
git ls-files --error-unmatch LICENSE NOTICE.md PoleSimGear/PoleSimGear.toc > /dev/null
mapfile -t LUA < <(git ls-files 'PoleSimGear/*.lua')
for f in "${LUA[@]}"; do luac5.1 -p "$f"; done
luajit tests/run.lua
lua5.1 tests/run.lua
v=$(sed -n 's/^## Version: //p' PoleSimGear/PoleSimGear.toc | tr -d '\r')
[ -n "$v" ] || { echo "no ## Version in the TOC" >&2; exit 1; }
mkdir -p "$DIST"
out="$DIST/PoleSimGear-$v.zip"
git archive --format=zip -9 -o "$out" HEAD PoleSimGear LICENSE NOTICE.md
ls -l "$out"
