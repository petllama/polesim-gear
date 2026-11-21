# In-game checklist (one session, on a priest) — PoleSim Gear 0.2.2

**0.2.2 over 0.2.1** (no new files: `tools/install.sh` then `/reload` is enough): green world drops
("... of Magic", "... of the Whale": any mob of their levels drops them) are no longer dungeon loot;
they are under BoE / World only. Dungeons keep boss/dungeon drops and blue+ items. Check: K14.

**0.2.1 over 0.2.0** (no new files: `tools/install.sh` then `/reload` is enough): the window is larger
(980x600) and resizable, nothing in it is cut, worn items show their icon and name, the equipped strip
explains its dots. Checks: K3, K7, K10.

One ordered pass over everything that can only be checked in the game (plan Tasks 24, 26, 28, 30,
31, 32, 34, 36 and 45, and the window v2 plan's Phase 8). Work top to bottom; a check that needs a
place you are not at (a group, the auction house) can be skipped and done later; mark it so in the
results table at the end.

How to use it:

- Paste each `/run` line into chat as it is (every one is under 255 characters; `tests/test_checklist.lua`
  checks that, and that every addon name used here exists).
- "This item" checks: pick the item first with `/run X=[[<item>]]`: type `/run X=[[`, Shift-click
  the item into the chat box, type `]]`, Enter. The next lines read `X`.
- **Report**, per check: what it says to report (copy printed lines), anything that differs from
  "Expected", and any Lua error with its text (BugSack or `/console scriptErrors 1`).
- Fill the **Results** table at the end (ok / differs + note / skipped).

## 0. Before the session (outside the game)

1. `tools/install.sh` (copies the committed addon into the AddOns folder).
2. Bring, if you have them: a worn chest piece and a wand; a green "of the Owl"/"of the Eagle" item;
   an item whose tooltip has "Equip: Increases damage and healing done by magical spells...";
   an upgrade item in your bags (or one to buy); an alt that can mail you an item.
3. Polestar on, with its **Gear module on** (Polestar options: Questing > Rewards & gear > Gear
   advice) and a leveling guide open in its window. Bagnon on, if you use it.
4. **Full game restart** (new .lua files since the last install need it; `/reload` is not enough).

## A. Login

**A1. Lua errors on.** `/console scriptErrors 1` (or BugSack). Report any error from here on.

**A2. Modules loaded.**

```
/run local P=PoleSimGear print(P.Arrows and "arrows ok", P.Rewards and "rewards ok", P.Coexist and "coexist ok", P.Window and "ui ok", BagBrother and BagBrother.Item and BagBrother.Item.Update)
```

Expected: `arrows ok rewards ok coexist ok ui ok function: ...` (the last value is Bagnon's item
update, which arrows hook; `nil` without Bagnon).

**A3. Spec right after login.** As soon as the loading screen is gone, then again ~5 seconds later:

```
/run print(PoleSimGear.Context.Get().specSource)
```

Expected: `talents` the second time at the latest (a `default` right after login is read again every
2 seconds, up to 5 times). Report if it still says `default` after 15 seconds with talent points spent.

**A4. The Polestar question (wording pending).** About 5 seconds after login one question shows:
"Polestar's gear scores are on. Turn them off so you see one score?". *The wording, and what Yes does,
are pending your decision: note here what you would want it to say/do.* **Do not answer yet**; first:

```
/run print(PoleSimGear.Coexist and "coexist ok", Polestar.Gear and Polestar.Gear.IsEnabled(), PoleSimGearDB.askedPolestarGear)
```

Expected: `coexist ok true nil` (`nil` = not answered yet). If no question showed and this prints `yes`
or `no` (answered in an earlier session): `/run PoleSimGearDB.askedPolestarGear=nil`, `/reload`, and
start A4 again.

**A5. No.** Click **No**. Chat: "Both score items: ours is the line that says PoleSim." `/reload`: no
question (remembered); `/run print(PoleSimGearDB.askedPolestarGear)` prints `no`. Polestar's scores stay
on for sections B-D, so both show (ours labelled **PoleSim score**).

## B. Item stats from the client (Task 24, Risk R3)

Wear a chest piece (slot 5) and a wand (slot 18) if you have them.

**B1. What `C_Item.GetItemStats` returns.**

```
/run local function d(l) if not l then return end print(l) for k,v in pairs(C_Item.GetItemStats(l) or {}) do print("  ",k,v) end end d(GetInventoryItemLink("player",5)) d(GetInventoryItemLink("player",18))
/run local l=select(2,C_Item.GetItemInfo(11288)) if l then for k,v in pairs(C_Item.GetItemStats(l) or {}) do print(k,v) end end
```

The second line is Greater Magic Wand (`sp = 2` in our data); run it twice (the first call may only
ask the server). Then with `X` set to a green "of the Owl"/"of the Eagle" item, and again to an item
with an "Equip: Increases damage and healing done by magical spells..." line:

```
/run print(X) for k,v in pairs(C_Item.GetItemStats(X) or {}) do print(k,v) end
```

Report (copy the printed lines) and fill **Probe results** at the end:

- the key for "+spell damage and healing" (expected `ITEM_MOD_SPELL_POWER_SHORT`);
- whether **Equip:** effects appear at all (spell damage, mp5, hit/crit) or are missing;
- armor as `RESISTANCE0_NAME`? DPS as `ITEM_MOD_DAMAGE_PER_SECOND_SHORT`?
- ratings as rating points (e.g. 14 for 1% crit), not percent?
- one bonus under two names? e.g. mp5 as both `ITEM_MOD_MANA_REGENERATION_SHORT` and
  `ITEM_MOD_POWER_REGEN0_SHORT`, or hit/crit as both `..._MELEE_RATING_SHORT` and
  `..._RANGED_RATING_SHORT`. PoleSim Gear counts such a pair once (the larger value): which pairs
  appear, and do two such keys ever carry two different bonuses on one item?
- any key not in this list: `ITEM_MOD_*_SHORT` for strength, agility, stamina, intellect, spirit,
  health, mana, attack power, ranged attack power, spell power, spell damage done, spell healing done,
  each school's spell damage, mana/health regeneration, defense, block value, spell penetration, the
  hit/crit/dodge/parry/block/haste ratings, `RESISTANCE0..6_NAME`. (A new key must go into `Live.lua`.)

**B2. How PoleSim Gear reads the same item** (`X` as above):

```
/run local i=PoleSimGear.Live.Instance(X) if i then print(i.id,i.bonus,i.inv,i.rl,i.armor,i.dps) for k,v in pairs(i.stats) do print(k,v,i.filled[k] and "TABLE" or "") end else print("none/pending") end
```

Expected: the item ID, its suffix id for a random-suffix green (e.g. `12720` for some "of the Owl"),
then one line per stat. If an "of the ..." item prints `nil` for the suffix, report its link. `TABLE`
marks an equip bonus the client did not report, filled from PoleSim's item table (a whole family, e.g.
all spell damage, comes from one or the other). Equip effects missing in B1 should show `TABLE`; if
the client reports them, nothing should say `TABLE`.

## C. Spec, level band and worn scores (Task 26, Risk R4)

**C1.**

```
/run local c=PoleSimGear.Context.Get() print(c.spec,c.specSource,c.level,c.band.upTo,c.ref) for s,e in pairs(c.worn) do print(s,e.inst.id,("%.2f"):format(e.score)) end
/psg spec
```

Expected: your spec with source `talents`, the band end (e.g. `39` at level 34), `spShadow` (Shadow)
or `sp` (Holy/Discipline); one line per worn slot with a score. `/psg spec` prints the talent points
per column (e.g. `0/5/21`). If the points are all 0 while talents are spent, report it with:

```
/run local c=C_ClassTalents.GetActiveConfigID() local t=c and C_Traits.GetConfigInfo(c).treeIDs[1] for _,g in ipairs(t and C_Traits.GetGroupDisplayInfoByTreeID(t) or {}) do print(g.groupID,g.displayName,g.orderIndex) end
```

**C2. Website.** On https://polesim.petllama.com/#armory pick the same spec and level, enter one worn
item (same random suffix): its score equals C1's to 2 decimals for a plain item (enchants are ignored
in both).

## D. The tooltip line (Task 28)

**D1.** Hover: a bag item, a worn item (character sheet), a vendor item, a quest reward in the quest
log, an item link in chat (click it: ItemRefTooltip). On items a priest can wear (up to 5 levels above
yours):

- `PoleSim score x.x` (Polestar's scores are on since A5) and, on the right, `+y.y (+z%)` (green gain,
  red loss); Polestar's own line also shows;
- `Shadow, levels 30-39: points of Shadow spell damage` (your spec and band);
- `requires level N` above your level; rings/trinkets say `against your weaker one`; a two-hander says
  `replaces main and off hand` only when you wear an off hand and no two-hander;
- worn items say `equipped` on the right;
- plate/mail/other-class items and the shopping comparison tooltips show nothing;
- an item missing from PoleSim's table (new on Forever) is judged by armor/weapon type only: report a
  class-restricted item of another class that still shows a score.

**D2. Shift: how?** Holding Shift redraws the tooltip with one line per stat (`Intellect 10 x 0.5   5.00`;
a stat from the item table ends in `(item table)`), then `minus worn` and `gain`. Blizzard's comparison
tooltips open beside it (no PoleSim lines there). A clicked chat link redraws on Shift too. In combat
Shift does nothing until you hover again.

**D3. Website.** One green "of the Owl" item's tooltip score equals the website's (same spec, level,
item and suffix).

## E. The Polestar question: Yes (Task 36; wording pending)

**E1.** `/psg polestar`: the question again (wording pending, see A4). Click **Yes**. Chat: "Polestar's
gear scores are off (Polestar options: Questing > Rewards & gear > Gear advice to turn them back on)."
At once (no `/reload`): Polestar's tooltip line and bag arrows are gone; ours says **Score** (no
"PoleSim" label).

```
/run print(Polestar.Gear.IsEnabled(), Polestar.Get("gear.enabled"), PoleSimGearDB.askedPolestarGear)
```

Expected: `false false yes`. If Yes could not change it, chat says "... set off, but Polestar reported
an error applying it: /reload if they still show." or "Could not turn off Polestar's gear scores: ...":
report which.

**E2.** `/psg polestar` again (Polestar's Gear now off): "Polestar's gear scores are off: nothing to ask."
and no question.

Note: the answer is kept for the account, but Yes changes only the Polestar settings profile of this
character; a character on another Polestar profile can still have Polestar's Gear on and is not
asked again (`/psg polestar` there).

## F. Bag arrows (Task 30, Risk R6)

An arrow means: you can wear the item **now** and it scores above what you wear (green `+x.x` in the
tooltip). Ours is the green bag arrow **top-right**; Polestar's (if its Gear is on) sits top-left.

**F1.** Open the bags (Bagnon). A known upgrade: arrow top-right. A worse item, plate/mail: none.

```
/run for b=0,4 do for s=1,C_Container.GetContainerNumSlots(b) do local l=C_Container.GetContainerItemLink(b,s) if l and PoleSimGear.Arrows.Verdict(l) then print(b,s,l) end end end
```

lists the bag items PoleSim calls upgrades; one item: `/run print(PoleSimGear.Arrows.Verdict(X))`.
If Bagnon shows no arrows while this lists upgrades, report it with A2's output.

**F2.** Equip the upgrade: its arrow goes; the old item (now in the bag) has none. Move an item between
slots/bags: the arrow moves with it.

**F3. Combat.** Fight a mob (or dummy) with the bags open and loot an upgrade: the arrow appears; no
"Interface action failed because of an AddOn"; bag items use/equip normally after combat.

**F4.** The client's own bags (Bagnon's inventory off, or the combined bag): F1-F2 again.

**F5.** Bagnon's character selector, an alt's bags: no arrows. Back to yours: they return. Your own
bank viewed away from the banker keeps its arrows.

**F6.** A PoleSim error on one item appears once per item per session (not on every bag update; at most
50 per session). Report it with the item.

## G. The Polestar question in combat (Task 36)

**G1.** Turn Polestar's Gear back on in its options, `/run PoleSimGearDB.askedPolestarGear=nil`, pull a
mob and `/psg polestar` (or `/reload`) during the fight: no question in combat; it appears when combat
ends (wording pending). Answer as you prefer (No keeps both scores; Yes turns Polestar's off).

## H. Merchant and loot rolls (Task 31)

**H1.** A vendor selling an upgrade (cloth, staff, dagger, mace, wand): arrow top-right of its icon.
Page forward and back: arrows stay on the right items.

**H2.** The **Buyback** tab: no arrows, even on an upgrade you sold; back on the first tab they return.

**H3.** (In a group) a roll on a usable upgrade: arrow on the roll frame's item icon; none on items you
cannot wear.

## I. Mail and the auction house (Task 32, Risk R7)

**I1.** Mail yourself an upgrade from an alt: the inbox row's icon has the arrow (first item only); the
opened letter's attachment has it. A non-upgrade: none.

**I2.** Auction house: search "Robe" / "Staff". Usable upgrades without a random suffix get an arrow
top-right of their **row** (there is no stable item icon to anchor to). "of the ..." items get none in
that list; click one: each auction's row shows the arrow when that auction's suffix is an upgrade.
Scroll: arrows stay with their rows. Report if it overlaps the favourite star / time-left column or
reads unclearly. If no row has an arrow at all, report with:

```
/run local f=AuctionHouseFrame print(f and f.BrowseResultsFrame and f.BrowseResultsFrame.ItemList.ScrollBox, f and f.ItemBuyFrame and f.ItemBuyFrame.ItemList.getEntry)
```

## J. Quest reward pick (Task 34, Risk R2)

Turn in a quest with two or more reward choices.

**J1.** The best choice shows our green arrow at the **left edge** of its icon and green `+x.x` at the
**bottom**. When no choice is an upgrade, the least loss gets a grey `-x.x` and no arrow.

**J2.** Each choice's tooltip gain equals the number on its icon.

**J3.** A choice you cannot wear (mail, plate, shield) or a currency choice is never marked.

**J4.** Only the quest giver's turn-in panel is marked (not the quest log or the accept panel).

**J5.** A choice needing a level above yours (up to 5) can be the pick: no arrow, the gain in **gold**
when it will be an upgrade (grey if not), `lvl N` at the top of the icon.

**J6.** With Polestar's reward marks on, theirs (arrow top-left, coin top-right, ring) and ours do not
overlap. Note whether two highlights on one panel bother you (R2).

**J7.** Close the panel, open another turn-in: no leftover mark, not even for a frame.

On the turn-in panel, what PoleSim read:

```
/run local R=PoleSimGear.Rewards for _,c in ipairs(R.Choices(PoleSimGear.Context.Get())) do print(c.index,c.usable,c.gain,c.score,c.pending,c.rl) end print(R.Pick(R.Choices(PoleSimGear.Context.Get())))
```

Expected: `index true gain score nil nil` for wearable items (last value: the level needed when above
yours), `index nil` for others, then the picked index and `true` when it is an upgrade. A choice still
pending after a second or two: report the quest (after ~1 s it counts as unusable and the best of the
others is marked; redrawn if its data comes later).

## K. The PoleSim Gear window (v2)

New files since 0.1.x: **restart the game once** after installing (`/reload` is not enough). A Polestar
guide open in its window, for the route tags.

**K1. Parts the window reads.**

```
/run local P=PoleSimGear print(P.Window and "ui ok", P.Sources.Codex() and "codex ok", Polestar.Nav and Polestar.Nav.API and Polestar.Nav.API.version)
/run local n=0 for _ in pairs(PoleSimGear.Route.Build(Polestar.Engine.GetGuide())) do n=n+1 end print("route turn-ins",n)
```

Expected: `ui ok codex ok 1` (`nil` or another number instead of 1: no Waypoint buttons in K14), and the
open guide's number of turn-ins.

**K2. Open and close, no stutter.** Each of these opens the window and a second press closes it:
`/psg`; the addon compartment button ("PoleSim Gear"); the **minimap button** (round, cloth-chest icon
on the minimap's edge; hover: "PoleSim Gear", "Left-click: open or close the window", "Drag: move";
right-click does nothing). Escape and the red X close it too. While it scores, the progress card says
"scoring..." (a second at most) **with no stutter**. Drag the window by its title bar and the minimap
button around the edge, `/reload`: both stay where they were left. `/psg minimap` hides the button
(chat says so), `/reload`: still hidden; `/psg minimap` shows it again.

**K3. Look.** Against the template: dark body; white title "PoleSim Gear" with a gold-framed icon; five
tabs right of the title (Gear Plan, Slot Upgrades, Sources, Weights, Settings), the active one teal; a
red X; four header cards; the Sources / Show panel on the left; the equipped strip and the stat
weights card at the bottom. Every kind icon (quest, dungeon skull, crafting hammer, vendor coin, world
bag) and the weights card's pencil render: a green square instead of an icon is a missing texture: name which one.
**Size (0.2.1):** the window opens at about 980x600 (a first open, or after `/run PoleSimGearDB.window=nil`
and `/reload`) and **no text is cut** ("..."): the Gear Plan's `#` column, slot names (Ranged, Main
hand, Off hand, Trinkets), the current item's score ("130.4"), Gain, Gain % ("+1177%"), the source kind
("Dungeon"), item names, and the weights card (two values a line). **Resize** by the grip at the bottom
right corner (the chat frame's grabber): it stops at 780x500 and at the screen; the tables stretch and
their columns move with it (rows already shown too); at 780 wide the current item shows its icon and
score only. `/reload` and reopen: the same size and place.

**K4. Header.** "Level N Priest" with the class icon; spec "Shadow (auto)" (no "(auto)" once you choose
a spec in K15); Gear score = the sum of the "PoleSim score" lines of what you wear (check that two worn
items' tooltip scores are part of it; hover the card: the band's levels and the stat it counts in);
"Gear plan progress" with a bar and "d / 15 (p%)".

**K5. Look ahead.** Header dropdown Now -> "+3 levels (N)": Gear Plan and Slot Upgrades show rows with
"level N" (items you can wear soon); no "scoring..." (it does not rebuild). Back to Now.

**K6. Sources checkboxes.** By default all ticked but **BoE / World**. Tick it: world drops appear in the
lists; untick **Quests**: quest rows go; nothing rebuilds. `/reload` and reopen: the ticks are kept (per
character). Tick Quests again.

**K7. Gear Plan.** One row per slot with an upgrade: priority 1-3 in gold badges (then grey), the slot,
what you wear (**its own icon and name**, with an "of the Owl" style suffix if it has one; no red
question mark, no "?") and its score, the plan item, Gain and Gain %, the source icon and kind. Hover a row: the
"how?" (as D2: Score, its terms, "Gain over what you wear", the sources) and at the bottom "Click: this
slot's upgrades. Right-click: back to suggestion, wishlist.". Click a row: Slot Upgrades opens on that
slot.

**K8. Picks.** Slot Upgrades on a slot with two or more rows: **Set as plan** on the 2nd row. Gear Plan:
that slot shows the item with "Your pick" and "best +N" (the suggestion's gain; hover: "Better: <item>
+N"). Right-click the row -> **Back to suggestion**: the suggestion is back. Pick again, then switch
spec on the Weights tab (Holy): no pick on that slot; back to **Automatic (talents)**: the pick is back
(picks are per spec).

**K9. A pick that goes away.** Pick a quest reward (Slot Upgrades, "Quest" kind), then untick **Quests**:
the Gear Plan row stays, greyed, "its sources are off: Quests". Tick Quests again: normal.

**K10. Equip a pick.** Equip the picked item (or any plan item) from your bags: the slot's pick clears,
the row shows the next suggestion (or goes), progress goes up, and that slot's dot in the equipped
strip turns green or goes. **The strip (0.2.1):** under the icons a legend: a green dot "suggested
upgrade", a gold dot "your pick". Hover a slot: its item's tooltip, then one line: "Suggested upgrade:
<item> +N" (green), "Your pick: <item> +N" (gold) or "No upgrade from the ticked sources" (grey). An
empty slot shows that slot's own empty art (the character frame's), not one shared picture.

**K11. Wishlist.** Star two rows (the star at the row's left, any tab). Show -> **Wishlist** lists both
with their gains. The item's own tooltip (bag or a chat link) shows "On your PoleSim wishlist".
`/reload`: still starred. Unstar one: it leaves the list.

**K12. All gear.** Show -> **All gear**: every slot listed; a slot without an upgrade says "nothing better
now" with what you wear. Back to **Upgrades only**.

**K13. Slot Upgrades.** The slot picker lists every slot; the count line ("N upgrades: Quests 3, Vendors
2, ..."); rows with "lvl N", the source, "(route)" in blue on rewards of your guide's turn-ins, "needs:
<quest> first" in orange; the first row's button says "Suggested". On a crowded slot (chest at 30+),
where the list was trimmed (25 kept per source kind), the last row says "Show all (N)": click it,
"Scoring every upgrade..." briefly, then all N.

**K14. Sources.** Pills with counts: Dungeons, Quests, Crafting, Vendors, BoE / World. Dungeons: places
with level ranges; a dungeon's rows show the boss (or mob) and the chance; drops under 1% are faded and
last (hover: "luck, not a plan"). Quests: a zone's quests as "[level] title" headers (tags elite / on
your route / needs: X first on a second line; hover: the full title); their rewards below. Crafting;
Vendors with prices; BoE / World. **Waypoint** on a quest header: Polestar's arrow points at the quest
giver; on a dungeon header: at the entrance; on a vendor row: at the vendor. Set as plan and the star
work here too. **0.2.2:** a dungeon lists no green "of Magic / of the Whale" items (e.g. Medicine Staff,
Buccaneer's Vest, Zircon Band); tick BoE / World and they are there, their hover starting with "World drop,
levels A-B" and a dungeon drop saying where ("Drop: Gilnid, 1.25%, Deadmines"). Boss loot (Cookie's
Tenderizer, Bloody Apron) and blue BoEs (Skycaller, Witching Stave) stay under Dungeons.

**K15. Weights.** "Levels A-B (your band)" with the weights and bars. ">" steps to the next band, "<"
back; at the first band "<" is faded and does nothing, at the last ">" is. The spec radios: Holy
switches scoring (the header, the bottom weights card and the lists follow; "Now: Holy, your choice");
**Automatic (talents)** goes back.

**K16. Settings.** Each switch works at once, no `/reload`: minimap button (hidden/shown), the score line
in item tooltips, the upgrade arrows (bags, merchant), the best quest reward mark. "Look ahead for a new
character" sets the default for a character that never chose one. **Ask again** shows the Polestar
question (wording pending, see A4) when Polestar's scores are on; the line under it says what you
answered.

**K17. Memory**, window closed, then open (wait for the list), then closed again. (The first visit to
each tab creates its frames, which stay for the session to be reused: compare open/close pairs taken
after K3-K16, not against a reading from before them.)

```
/run collectgarbage() UpdateAddOnMemoryUsage() print(format("PoleSim Gear %.0f KB",GetAddOnMemoryUsage("PoleSimGear")))
```

Expected: open adds a few MB at most, closing gives it back. (Polestar's own number grows ~7 MB the
first time any addon reads its Codex: Polestar's, once per session.) Offline (tools/fullload.lua, real
Codex, lua5.1) closing left +0.5 to +0.9 MB at levels 10, 30, 60.

**K18. Time** (this one hitches once, on purpose):

```
/run local t=debugprofilestop() PoleSimGear.Browser.Build(PoleSimGear.Window.Env()) print(format("build %.0f ms",debugprofilestop()-t))
```

Offline (tools/fullload.lua, lua5.1) the window's build took 109 ms at level 10, 219 ms at 30, 429 ms at
60, spread over frames of at most 11-14 ms. After K18, close and reopen the window once: K18 builds the
item index outside the window, and only a window close releases it.

**K19. Skyborne only.**

```
/run local c=PoleSimGear.Context.Get() print(c.raceBit, PoleSimGear.Sources.RaceOk(2^33+178, c.raceBit))
```

Expected: `4294967296 false` (High Order) or `8589934592 true` (Windshaper); the window lists your
side's and the Skyborne-only quests' rewards.

**K20. Turn-in rebuild.** Note a Quest row (Gear Plan or Slot Upgrades), turn that quest in with the
window open: about a second later "scoring..." and the row is gone.

## L. Later in the session (or another session)

**L1. Arrows follow changes.** Level up, change talents or equip something: within a moment the arrows
in open bags, vendor and mail update (no `/reload`); opening a bag or the vendor does not stutter.

**L2. Another character** of the account: no Polestar question (the answer is account-wide).

**L3.** Group loot roll (H3) and auction house (I2), if skipped above.

## Probe results (B1, fill in)

| Question | Answer |
|---|---|
| Key for spell damage and healing | |
| Equip: effects reported by `GetItemStats`? | |
| Armor key / DPS key | |
| Ratings in rating points? | |
| Same bonus under two keys (which)? Ever two different bonuses? | |
| Unlisted keys | |
| B2: any `TABLE` stats? Suffix id read for "of the ..." items? | |

## Results

| Check | What | Result |
|---|---|---|
| A2 | modules loaded | |
| A3 | spec after login | |
| A4 | question shows; wording (pending) | |
| A5 | No: both scores, remembered | |
| B1 | GetItemStats probe | |
| B2 | Live.Instance | |
| C1 | context, worn scores, /psg spec | |
| C2 | worn score = website | |
| D1 | tooltip line | |
| D2 | Shift: how? | |
| D3 | tooltip = website (suffix item) | |
| E1 | Yes turns Polestar's scores off (pending) | |
| E2 | nothing to ask | |
| F1-F2 | bag arrows (Bagnon) | |
| F3 | combat loot, no taint | |
| F4 | client bags | |
| F5 | alt bags / cached bank | |
| F6 | errors once per item | |
| G1 | question waits for combat end | |
| H1-H2 | merchant, buyback | |
| H3 | loot roll | |
| I1 | mail | |
| I2 | auction house | |
| J1-J7 | quest reward pick | |
| K1 | parts: codex, Nav API, route | |
| K2 | open/close (/psg, compartment, minimap button), positions kept | |
| K3 | look, kind icons, default size, nothing cut, resize grip, size kept | |
| K4 | header | |
| K5 | look ahead | |
| K6 | Sources checkboxes, kept per character | |
| K7 | Gear Plan rows (worn icons and names), hover, click | |
| K8 | picks, back to suggestion, per spec | |
| K9 | a pick whose sources are off | |
| K10 | equipping a pick, strip legend and dot tooltips, empty-slot art | |
| K11 | wishlist | |
| K12 | All gear | |
| K13 | Slot Upgrades, Show all | |
| K14 | Sources tab, waypoints | |
| K15 | Weights: bands, stepper, spec switch | |
| K16 | Settings switches, Ask again | |
| K17 | memory | |
| K18 | time | |
| K19 | Skyborne | |
| K20 | turn-in rebuild | |
| L1 | arrows follow changes | |
| L2 | other character not asked | |

## Known limits (tell me if they bother you)

- A drop of dungeon trash counts as "Dungeon" (as on the website), so some BoE greens show as dungeon
  drops with a small chance.
- Reputation, PvP, raid and "opened from an item" (container) sources are not listed.
- Crafted items are gated by "about level = skill / 5" (the website's rule), not by your profession.
- The tooltip compares one item with what you wear: a one-hander under a worn two-hander says it
  leaves the off hand empty, while the window pairs it with the best off hand (R9).
- With the Quests / Dungeons / Crafted filters on, a one-hander's paired off hand is still the best
  from all sources (the website recomputes per filter).
- No dual wield yet (no priest can); added with the melee classes.
- If the client leaves an item's equip bonuses out of its stats, the tooltip fills that whole group
  from PoleSim's item table (Shift shows "(item table)" on those lines).
- Tooltip (live stats) and window (shipped table) can differ when Forever changes an item before the
  table is regenerated; table weapon DPS is rounded to 2 decimals.
- Polestar's own reward highlight (vendor value, the coin) stays on even after answering Yes.
- If Polestar changes its internals, a part turns off instead of erroring: no route tags (guide),
  "Polestar's Codex is not available" (Codex), no question (settings), or an orange "some sources
  could not be read" line.
- One pick per ring and trinket pair: a pick replaces the weaker (or empty) one of the two.
- Progress counts upgrades available now (look ahead is ignored).
- The Sources tab ignores the Sources checkboxes (it has its own kind pills).
- At most 3 open-world drops per item (the likeliest).
- "elite" on a quest = the Codex lists hostile elites at one of its objectives for your side (it has no
  group-quest flag).
- Columns say "Gain" (the mockup's "Δ" may not be in the game font).
- The Look ahead dropdown uses Blizzard's dropdown art.
