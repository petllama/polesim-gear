# In-game checks: Phase G (the upgrade browser, layout B)

For the user, on a priest. Paste each line into chat as it is (every `/run` line is under 255
characters). Turn on Lua errors first: `/console scriptErrors 1` (or use BugSack). Report any error
with its text, and the numbers the `/run` lines print.

## Before you start

1. `tools/install.sh` (already run once for this phase).
2. **Full game restart** (new files `Sources.lua`, `Route.lua`, `Browser.lua`, `BrowserUI.lua` and a
   new TOC line; `/reload` is not enough).
3. Polestar on, with a leveling guide open in its window (for the "route" checks).
4. Check the modules and Polestar's parts the browser reads:

```
/run local P=PoleSimGear print(P.BrowserUI and "ui ok", P.Sources.Codex() and "codex ok", Polestar.Engine and Polestar.Engine.GetGuide() and "guide ok")
```

Expected: `ui ok codex ok guide ok` (`nil` for the guide when no guide is open: then no route tags).

How the route tag finds the guide: `Polestar.Engine.GetGuide()` is the guide of Polestar's active
tab; each step's goals with `t == "turnin"` give quest -> step. It is rebuilt when Polestar fires
`GUIDE_CHANGED` (switching guide or tab). How many turn-ins the open guide has:

```
/run local n=0 for _ in pairs(PoleSimGear.Route.Build(Polestar.Engine.GetGuide())) do n=n+1 end print("route turn-ins",n)
```

## Task 45: the window

1. `/psg` (or the addon compartment button under the minimap: "PoleSim Gear") opens the window.
   "Scoring items..." shows briefly (about a second at most), **with no stutter** (the build is spread
   over frames, 8 ms each), then the list. `/psg` again (or Escape, or the X) closes it.
2. Header: spec, level, the band's levels ("weights of levels 20-29"), "Gains in points of Shadow
   spell damage" (Shadow) or "Spell damage and healing" (Holy/Discipline).
3. "Best per slot right now": one row per slot that has an upgrade, biggest gain first; the tag says
   Quest / Dungeon / Crafted; "(route)" in blue on rewards of quests the open Polestar guide turns in.
   Names include the best random suffix for the spec ("... of the Owl").
4. Chips: Quests / Dungeons / Crafted change the list to that kind; All brings it back.
5. Click a row: that slot's every upgrade (up to 25 of each kind), each with "level N" (its required
   level) and its first source. Hover a row: the item, "scored with its best suffix" (suffix items),
   Score and its terms (the same terms as the item tooltip's Shift "how?"), "Gain over what you wear",
   a note for weapons/rings when it applies, then every source: quest (zone), dungeon drop (dungeon,
   boss, drop chance), a container inside a dungeon ("Container: Food Crate, 2%", the dungeon; as on
   the website), crafted (profession and skill); "needs: <quest> first" in orange when an
   earlier quest of the chain is not done; "on your route (Polestar guide step N)" in blue. **Back**
   returns to the list.
6. "Coming up (levels L+1 to L+5)": up to 10 upgrades whose required level is in the next five
   levels, "level N" in the slot column; hover says "level N item: scored with the weights of levels
   A-B" (the band it would be worn in). Not shown at 60. Wearing a two-hander, a coming one-hander
   says "with <off hand> in the off hand", the best off hand you can have by that level (any level up
   to it, as on the website), and the reverse for an off hand ("with <one-hander> in the main hand").
7. Gating, check each:
   - no Alliance-only quest rewards on a Horde priest (and the reverse);
   - no rewards of quests you already turned in: note a Quest row, turn that quest in, close and
     reopen the window: it is gone;
   - no raid drops (Molten Core, Zul'Gurub, ...), no leather or mail, no other classes' quests;
   - no items Polestar marks retired (Polestar's own item search shows them as retired).
8. The **Spec** button cycles auto / discipline / holy / shadow; the list scores again each time
   ("Scoring items..." then the new list) and the header follows.
9. Website cross-check: pick one "now" row. On polesim.petllama.com/#armory with the same spec, level
   and worn gear (macro import), the same item has the same score and the same best suffix.
10. Equip an upgrade from the list while the window is open: the list scores again by itself.

## Skyborne

Skyborne's race bits in quest and item race masks are 2^32 (High Order, Alliance, ChrRaces 95) and
2^33 (Windshaper, Horde, 96), as Polestar's Codex stores them (the whole-side masks are 2^32 + 77
and 2^33 + 178). The addon tests them with arithmetic, not `bit.band` (32 bits). On a Skyborne:

```
/run local c=PoleSimGear.Context.Get() print(c.raceBit, PoleSimGear.Sources.RaceOk(2^33+178, c.raceBit))
```

Expected: `4294967296 false` (High Order) or `8589934592 true` (Windshaper). The window then lists
your side's quest rewards and the Skyborne-only quests' rewards. A mask with no bit above 2^32 (a
Classic mask) never locks Skyborne out; a race with no known bit is never excluded (Polestar's rule).

## Time and memory

The build's total time when done in one go (this one hitches once, on purpose):

```
/run local t=debugprofilestop() PoleSimGear.Browser.Build(PoleSimGear.BrowserUI.Env()) print(format("build %.0f ms",debugprofilestop()-t))
```

Offline (`lua5.1`, real item table and Polestar's real Codex, empty worn slots) it took about 200 ms
at level 20, 360 ms at 40 and 610 ms at 60; the window spreads that over frames.

Memory, with the window closed, then open (wait for the list), then closed again:

```
/run collectgarbage() UpdateAddOnMemoryUsage() print(format("PoleSim Gear %.0f KB",GetAddOnMemoryUsage("PoleSimGear")))
```

Expected: open adds a few MB at most (the list's rows), and closing gives it back (the window lets
go of its rows and its item index; nothing decoded is kept). Polestar's own number grows by about 7
MB the first time any addon reads its Codex (its load-on-demand pack Polestar_Codex); that is
Polestar's, once per session.

## Known limits (tell me if they bother you)

- A drop of dungeon trash counts as "Dungeon" (as on the website), so some BoE greens show as dungeon
  drops with a small chance.
- Vendors, world drops, reputation and raids are not goals of the browser.
- Crafted items are gated by "about level = skill / 5" (the website's rule), not by your profession.
- If Polestar changes its internals, a part turns off instead of erroring: no route tags (guide),
  "Polestar's Codex is not available" (Codex), or an orange "some sources could not be read" line.
