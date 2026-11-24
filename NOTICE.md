# PoleSim Gear: credits and licences

PoleSim Gear is free software under the GNU General Public License v3.0 only (LICENSE), like
Polestar, which it requires and reads at runtime.

- **Weights and scoring:** PoleSim (https://github.com/petllama/wowsims-forever, MIT), a leveling
  simulator built on wowsims (https://github.com/wowsims/forever, MIT). `PoleSimGear/Data/Weights.lua`
  is generated from PoleSim's results by `forever/tools/gen_addon_data.py`; `Score.lua` ports the
  scoring rules of PoleSim's `forever/web/armory.py`. MIT notice below.
- **Item facts** (`PoleSimGear/Data/Items.lua`, `Data/Suffixes.lua`): World of Warcraft: Forever client
  tables (build in `ns.DATA.build`) and, for items the Forever table lacks, Classic Era client tables;
  confirmed with Blizzard's Battle.net Game Data API. Only derived facts are stored, never API records
  (no raw API data is shipped). Item and suffix names, numbers and icon names are Blizzard
  Entertainment's game data, used as facts. World of Warcraft and Blizzard Entertainment are
  trademarks or registered trademarks of Blizzard Entertainment, Inc. This addon is not made,
  endorsed or supported by Blizzard Entertainment.
- **Combat rating conversion** (hit 10, crit 14 ... rating per 1%): the client's CombatRatings table
  as wowsims/forever (MIT) extracted it.
- **Where items come from:** read in game from Polestar's Codex and active guide (Polestar, GPL-3.0;
  its data credits are in Polestar_Codex/LICENSE-DATA.txt). Nothing of it is copied into this addon.
- **LibDeflate** 1.0.2 (`PoleSimGear/Libs/LibDeflate/`, unmodified, from
  https://github.com/SafeteeWoW/LibDeflate): (C) 2018-2020 Haoqian He, zlib License (its text is in
  `Libs/LibDeflate/LICENSE.txt`). It compresses the recorder's export.
- **LibStub** (`PoleSimGear/Libs/LibStub/`, unmodified): public domain (Kaelten, Cladhaire, ckknight,
  Mikk, Ammo, Nevcairiel, joshborke).
- Nothing here comes from Forever Leveling BiS or from Polestar_ItemDB's Forever.lua.

## MIT notice (PoleSim and wowsims)

```
MIT License

Copyright (c) 2024 wowsims team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
