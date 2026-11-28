# The CurseForge listing

Project: **PoleSim Gear**, id `1838141`, slug `polesim-gear`
(https://www.curseforge.com/wow/addons/polesim-gear once approved; edit at
https://authors.curseforge.com/#/projects/1838141).

## Updating the addon

Nothing by hand. Bump `## Version` in `PoleSimGear/PoleSimGear.toc` (+ README line 3, the CHECKLIST header and
its "**X over Y:**" paragraph) and push to `main`. `.github/workflows/release.yml` then:

1. runs both test suites and `tools/package.sh` (zip with only the `PoleSimGear/` folder at its root),
2. publishes GitHub release `v<version>`,
3. uploads the same zip to CurseForge with `tools/publish_curseforge.py`: display name `PoleSim Gear <version>`,
   release type Release, game version Forever 1.60.1 (from the TOC's `## Interface`), changelog = the CHECKLIST
   paragraph, Polestar as a required dependency.

Retry or re-upload the current version to CurseForge only: Actions > "test and release" > Run workflow, tick
"curseforge" (`gh workflow run release.yml -f curseforge=true`).

Settings: repo secret `CF_API_TOKEN` (CurseForge token "polesim-gear CI", authors.curseforge.com > API tokens),
repo variable `CF_PROJECT_ID=1838141`. Unset the variable to pause CurseForge uploads. Local check without
uploading: `CF_API_TOKEN=... CF_PROJECT_ID=1838141 tools/publish_curseforge.py <zip> <version> release --dry-run`.

When the Interface number changes for a new Forever patch, the upload picks the matching CurseForge game
version by itself; if CurseForge doesn't list it yet the upload fails with a clear error: set the repo variable
`CF_GAME_VERSIONS` to a version name it does list (e.g. `1.60.1`) and rerun, or wait for CurseForge to add it.

## Listing assets

| File | Use |
|---|---|
| `description.md` | Project description (Markdown editor). Images are 836 px wide: CurseForge rejects description images 850 px or wider |
| `media/*.png` | The description's images (836 px), loaded from `main` on GitHub (repo must stay public) |
| `gallery/*.png` | The gallery, uploaded by hand, in file order (crops of in-game screenshots from 0.2-0.4; no player names) |
| `images/logo-400.png` | Project logo (original art, no game assets); `logo-1024.png` the large copy |

Summary (147 chars): "Leveling gear scores for WoW: Forever from a combat sim: stat weights by level, upgrade arrows,
quest reward picks, a gear planner and AH upgrades."

Settings: main category Quests & Leveling; also Tooltip, Bags & Inventory, Auction & Economy, Plugins; comments
on; GPLv3; third-party distribution allowed; source = GitHub petllama/polesim-gear.

CurseForge does not allow links to downloads hosted elsewhere in the description: link the source and the
issues, never the GitHub releases page.
