# In-game checklist (one session, on a priest; section M on a mage; section Q on a warlock, druid, shaman or paladin; section S on a warrior, rogue, hunter, Feral druid, Enhancement shaman or Retribution/Protection paladin) — PoleSim Gear 0.7.4

**0.7.5 over 0.7.4:** the Slot dropdown is greyed out (its tooltip says "Scan first") until a scan has
listed upgrades, and while a scan runs, so it never opens empty. No new files: `/reload` is enough.
Check: N12.

**0.7.4 over 0.7.3:** the auction house upgrades panel has a **Slot** dropdown right of Gain / Value /
Price (our own popup, not Blizzard's menu). **All slots** by default, then only the slots the scan found,
in paper-doll order with their counts ("Main hand (3)", "Rings (12)"). A choice lists that slot only,
still sorted, from the top. It stays while the auction house is open (a new scan keeps it; if that slot
has nothing left it goes back to All slots) and resets to All slots when the auction house closes. The
"Next: <partner>" button still opens the other half when that row is filtered out; it is a bit
narrower now (a long name ends in "..."). No new files: `/reload` is enough. Check: N11.

**0.7.3 over 0.7.2:** auction house weapon sets read as a pair at a glance. A set row (a one-hander
under your two-hander with the best off hand for sale, or the reverse) shows the partner's small icon
on its icon's bottom-right corner, "Main hand + <partner>" (or "Off hand + <one-hander>") in teal under
the name (a long name ends in "..."), and its **Price** is both items' price with "set of 2" under it,
the price its Gain/g uses; sorting by Price uses it too. The tooltip still gives the item's own price
and "Weapon set with X (price): Y together". Other rows are unchanged. No new files: `/reload` is enough.
Check: N10.

**0.7.2 over 0.7.1:** auction house weapon sets. A weapon-set row (a one-hander under your two-hander
paired with the best off hand for sale, or the reverse) now takes you to the other half too:
**right-click** the row opens the partner's listings (its tooltip ends with "Right-click: <partner>'s
listings"), and after you click a set row a **Next: <partner>** button appears next to the sort buttons;
it opens the partner's listings and hides (a new scan, a row without a partner or closing the auction
house hide it too). If the partner's listing is gone, it searches the auction house for it by name and
says so in chat. No new files: `/reload` is enough. Check: N9.

**0.7.1 over 0.7.0:** tanks. Warrior and Paladin **Protection** now get scores, arrows, the quest reward
mark, the equip prompt, the window and the auction house scan, from PoleSim's simulated tank weights
(one-hander + shield; weapon speed against the reference weapon, as for the other melee specs). Tank
weights are less certain (Stamina, armor and avoidance rest on the least validated parts of the model):
the Weights tab says so under the spec choice. Prot Paladin's note there: block is a damage stat from 42
(Holy Shield, Reckoning), faster weapons are better until ~55, and the level-60 weapon speed weight is set
to neutral (PoleSim's sim and wowsims/forever disagree on it). The auction house scan now follows the
spec's weapon style like the Gear Plan and the website (no two-handers for a tank, no one-handers or
shields for Arms/Retribution/Enhancement). No new files: `/reload` is enough. Checks: S1 and S6 on a
Protection warrior or paladin (talents in Protection, or Settings > Spec > Protection).

**0.7.0 over 0.6.0:** melee and hunter weights, and the Recorder. **New files: restart the game** (a
`/reload` does not load them). Warriors (Arms, Fury), Rogues (Assassination, Combat, Subtlety), Hunters
(Beast Mastery, Marksmanship, Survival), Druid Feral, Shaman Enhancement and Paladin Retribution now get
scores, arrows, the quest reward mark, the equip prompt, the window and the auction house scan, from
PoleSim's new simulated weights with **weapon speed**: at the same DPS a slow two-hander is worth more
to Arms, Retribution and Enhancement, a slow main hand to Combat and Subtlety, a fast off hand to most
dual wielders (counted against the weapon PoleSim fought with at your level, at most 0.6 s either way).
Off-hand weapons have their own weights; Assassination and Subtlety need a dagger in the main hand and
hunters a bow, gun or crossbow (other weapons are never an upgrade there; the tooltip says why); rogues
and Fury warriors dual wield (a one-hander compares in its better hand; a set never plans one item in
both hands). Warrior and Paladin Protection are not supported yet (tank weights pending): pick another
spec in Settings. With no talent points yet a druid starts on Balance, a shaman on Elemental and a
paladin on Holy (casters, as in 0.6.0; the website's import starts them on Feral/Enhancement/Retribution).
Quest rewards and items with no level show no level (no more "lvl 0", "(0)" or "[0]"). New
`/psg drift [itemID]`: lists items whose live stats differ from PoleSim's shipped table (shipped -> live),
for Blizzard hotfixes. With Polestar's Gear module on, one chat line per session says our equip prompt
stays quiet. **Recorder:** an opt-in leveling recorder for PoleSim
(asked once; off until you say yes): pulls, casts, kills and XP, meals, deaths and character sheets, never
names, chat or gold; every 4 h of play it offers a copy-paste export for polesim.petllama.com/upload.
Checks: sections S, R and T. Item data about 1.3 MB (weapon speeds added).

**0.6.0 over 0.5.1:** four more classes. Warlock (Affliction, Demonology, Destruction), Druid (Balance,
Restoration), Shaman (Elemental, Restoration) and Paladin (Holy) now get scores, arrows, the quest reward
mark, the equip prompt, the window and the auction house scan, from PoleSim's simulated leveling weights
(scores equal the website's armory). Feral, Enhancement, Retribution and Protection, and all Warriors,
Rogues and Hunters are not supported yet (their melee/hunter weapon rules are not done). A druid, shaman
or paladin whose talents point to such a spec is not scored with another spec's weights: chat and the
window say "<Class> <Spec> isn't supported yet. Pick a supported spec in Settings to use its weights.",
and the new Spec choice in Settings (also the Weights tab and `/psg spec`) lists only the class's specs
with weights. Restoration and Holy weights are leveling weights (killing while questing), not dungeon
healing. Relics (idols, totems, librams) score their stats only (none today: 0). Checks: section Q. No
new files: `/reload` is enough after updating (the item data is larger: about 1.2 MB, 0.5 MB before).

**0.5.1 over 0.5.0:** fixes a "C stack overflow" error when hovering a row in the PoleSim upgrades
list at the Auction House (or any window row) with Auctionator installed. Auctionator's tooltip hook
makes the game report the item as loaded from inside the tooltip draw, and PoleSim Gear redrew the
tooltip on that report, which drew again, without end. The row tooltip now never redraws from inside
its own draw and ignores "item loaded" for an item already shown with its full tooltip. Check: with
Auctionator on, scan at the AH and hover several rows: no error, the tooltip shows the item, its
Auctionator prices and PoleSim's lines. `/reload` is enough.

**0.5.0 over 0.4.4:** an equip prompt. A new upgrade reaching your bags (loot, quest reward, mail, a
purchase, a trade) now asks to be equipped: a small card directly above Polestar's guide window with the
item, its slot and the gain in green (Upgrade +0.5 (+3%)), **Equip** and **Not now**; several upgrades
queue ("1 of 3"). Equip puts it in the slot it replaces (the weaker ring or trinket); a bind-on-equip
item still brings up the game's own confirmation. In combat the button reads "After combat" and comes
back when the fight ends. Right-click the card: Never for this item (account-wide; Settings > Clear).
Settings: "Ask to equip upgrades I pick up" (on) and "Minimum gain to ask to equip" (any/1%/3%/5%). Quiet
while Polestar's own Gear module is on (its "Wear it" banner asks instead). `/psg ask` asks about every
upgrade already in your bags. Checks: section P. **A new file (Prompt.lua): restart the game** (a
`/reload` does not load it).

**0.4.4 over 0.4.3:** a taint fix. Setting a raid marker from the target frame's right-click menu (Target
Marker Icon > Skull) could be blocked ("an action was blocked because of taint from PoleSimGear -
SetRaidTarget()") after you had used one of our dropdowns or the Gear Plan's right-click menu: those were
Blizzard's menus, which the unit menus share, and opening them from an addon tainted them. The look-ahead
dropdowns (header and Settings), the Slot Upgrades slot picker and the Gear Plan right-click menu are now
our own popup (same choices, our colours; a click outside or Escape closes it, Escape without closing the
window). Check (O1): `/console taintLog 1`, `/reload`, open the window, pick a look ahead in the header
dropdown, right-click a Gear Plan row and pick an entry, close the window, target a mob, right-click its
target frame > Target Marker Icon > Skull: the skull is set, no "blocked" message, and after logging out
Logs/taint.log has no PoleSimGear line. `/console taintLog 0` afterwards. `/reload` is enough.

**0.4.3 over 0.4.2:** items Forever's server does not have are gone. The item data included ~4,800
Classic-only items (Season of Discovery ids such as Scout's Blade, Lorekeeper's Staff and Resilient Cloth
Headband from vendors, Scourge Invasion loot such as Abomination Skin Leggings, raid and PvP gear): the
game never loads them, so their tooltip stayed at "Retrieving item information". The data now keeps only
items Forever serves (its own tables, its server's answers, or proof on Wowhead Forever). As a safety net,
an item the game reports it cannot load is remembered (until the next version) and left out of every
list, the AH results and arrows (`/psg missing` lists them, `/psg missing clear` forgets them), and a row
whose item takes over 2 s to load shows its name and a grey "Item data not loaded from the server yet"
under our lines instead of an empty tooltip. `/reload` is enough.

**0.4.2 over 0.4.1:** AH upgrades while you wear a two-hander: off hands are no longer listed one by one
(each rode on the best one-hander's score and flooded the list); only the best one-hander + off hand set
is shown, as its two rows ("with <item> (AH) over your two-hander"). One-handers still pair with that
off hand. `/reload` is enough.

**0.4.1 over 0.4.0:** two fixes to the auction house upgrades. Developer and placeholder items are no
longer in the item data (QATest +1000 Spell Dmg Ring, which topped the list at +1200, the 72
"[PH] ... Dawn" items and 29 more test, "(DNT)"/"(DND)"/"(OLD)" and monster items; the website dropped
them too). Items with no required level now follow the same item-level rule as the Gear Plan's sources:
above your level + the look ahead + 5 they are not upgrades yet (Stormrager, Wand of Biting Cold and
Woestave no longer show at 21). Check: at level ~21 a scan's top rows are items of about your level.

**0.4.0 over 0.3.7:** auction house upgrades. At the auction house a "PoleSim upgrades" button (right
of the auction house's top-right corner) shows a panel docked to its right; **Scan for upgrades** runs
a few browse searches (6 on a priest or mage: cloth; neck, rings, trinkets, off hands and cloaks; one per
weapon type; usable, common to epic, up to your level + the look ahead), one at a time as the auction
house allows (Cancel stops it), and lists the upgrades for sale: name with suffix, slot, "lvl N" for
items above your level, gain, cheapest price and gain per gold, sorted by Gain, Value or Price. Weapons
count as a set (under a staff, a one-hander with the best off hand for sale); rings and trinkets against
the weaker one. Hover: the item's tooltip with PoleSim's lines; click: its listings in the auction house,
cheapest first. Buying stays yours (nothing is bought). While the auction house is open, the Gear Plan
shows "AH: <price>" on plan items for sale and the equipped strip's tooltip names a scanned item that
beats the plan. Two new files: **restart the game** (a `/reload` does not load new files). Check: N1-N8.

**0.3.7 over 0.3.6:** Bagnon bags get arrows and gains: Bagnon keeps its own copy of BagBrother's
classes (`Bagnon.Item`), which is now hooked (0.3.6 and earlier only looked at `BagBrother.Item`, absent
there). Check: an upgrade in Bagnon shows the arrow top-right and "+N" in green. `/reload` is enough.

**0.3.6 over 0.3.5:** bag (and Bagnon, loot roll, merchant, mail) item buttons that are upgrades show
their gain in green at the icon's bottom ("+1.0"), as on quest rewards; nothing for non-upgrades (no
minus numbers); auction house rows keep the arrow only. `/reload` is enough.

**0.3.5 over 0.3.4** (no new files: `tools/install.sh` then `/reload` is enough): main hand and off hand
are **one decision, the weapon set**: a two-hander alone, or a one-hander + an off hand. The Gear Plan
suggests the best set (your picks and the near-quest rule apply per item); an off hand is suggested only
together with a one-hander that is available from the ticked sources or planned ("with <item> (also
planned)"), and only when the pair beats what you wear. Wearing a staff that the best pair does not beat
(or with a two-hander as the plan), the Off hand row says "Uses the two-hander" (All gear only, no gain).
Gains split so the two rows add up: a one-hander replacing a staff shows its score minus the staff's, the
off hand its own score; the tooltip says "Weapon set: +X over <staff>". Slot Upgrades pairs each
one-hander/off hand with the best other hand from the ticked sources (or your pick); under All gear the
pairs that lose to the staff are listed with their negative gain. Progress counts the weapons once
(14 slots). Check: K24.

**0.3.4 over 0.3.3** (no new files: `tools/install.sh` then `/reload` is enough): when a slot has no
pick of yours, the Gear Plan suggests an upgrade from an **upcoming quest of your Polestar guide** (a
turn-in ahead on the active guide, another open tab or the next guide; quest level and the item's level
at most your level + 2) over the best overall (a dungeon drop, a craft); the row says "near quest" and
"BiS +N", the tooltip "Best overall: <item> +N (<source>)". Quests not on your guide never replace the
best. Settings: "Prefer upgrades from upcoming guide quests (within 2 levels)" (on) turns it off. Check:
K23.

**0.3.3 over 0.3.2** (no new files: `tools/install.sh` then `/reload` is enough): a quest reward that one
of your open Polestar guides turns in **ahead of you** says how far: "in 12 steps" (active guide),
"(this step)", "The Barrens, in 30 steps" (another open tab), "next guide: <name>" (the guide yours hands
off to), in blue on Slot Upgrades and Gear Plan rows and on the Sources tab's quest headers; the row
tooltip says "On your Polestar route: <guide>, step 87 (12 steps ahead)"; the game's item tooltip gets
"Polestar: in 12 steps (<quest>)". Passed or turned-in quests show nothing. Check: K22.

**0.3.2 over 0.3.1** (data only, no new files: `tools/install.sh` then `/reload` is enough): caster
weapons (210 caster staves, maces and daggers) carry the spell power the game gives them in the window
and on the website, not only in the live tooltip. Living Root shows "healing 45, spell damage 15" (23.2
for Shadow at 20, the same as its tooltip score) and is listed in Slot Upgrades > Main hand; caster
weapons' damage matches the game (Living Root 34-51). Check: Slot Upgrades > Main hand at 18-24 on a
priest, hover Living Root: window score = tooltip score.

**0.3.1 over 0.3.0:** clicking an icon in the equipped strip opens Slot Upgrades on that slot (both rings: Rings;
both trinkets: Trinkets); the slot's tooltip ends with "Click: this slot's upgrades". `/reload` is enough.

**0.3.0 over 0.2.3** (no new files: `tools/install.sh` then `/reload` is enough on an existing install;
a first install needs the game restarted): Mage support (Frost, Fire, Arcane: weights, spec detection,
swords and mage-only items in the lists). Other classes get one chat line and nothing else. Checks: M1-M4.

**0.2.3 over 0.2.2** (no new files: `tools/install.sh` then `/reload` is enough): hovering an item in
the window shows the game's own item tooltip (stats, with the row's "of the ..." suffix), then
PoleSim's lines below it; Shift compares with what you wear. The Gear Plan's current item has its own
tooltip. Check: K21.

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
slot. (The item tooltip above those lines: K21.)

**K8. Picks.** Slot Upgrades on a slot with two or more rows: **Set as plan** on the 2nd row. Gear Plan:
that slot shows the item with "Your pick" and "BiS +N" (the best overall's gain; hover: "Best overall:
<item> +N (<source>)"). Right-click the row -> **Back to suggestion**: the suggestion is back. Pick again, then switch
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
2, ..."); rows with "lvl N", the source, "in N steps" in blue on rewards of your guide's turn-ins (K22), "needs:
<quest> first" in orange; the Gear Plan's suggestion's button says "Suggested" (the first row, or
a near guide quest: K23). On a crowded slot (chest at 30+),
where the list was trimmed (25 kept per source kind), the last row says "Show all (N)": click it,
"Scoring every upgrade..." briefly, then all N.

**K14. Sources.** Pills with counts: Dungeons, Quests, Crafting, Vendors, BoE / World. Dungeons: places
with level ranges; a dungeon's rows show the boss (or mob) and the chance; drops under 1% are faded and
last (hover: "luck, not a plan"). Quests: a zone's quests as "[level] title" headers (tags elite / in N
steps / needs: X first on a second line; hover: the full title); their rewards below. Crafting;
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
in item tooltips, the upgrade arrows (bags, merchant), the best quest reward mark, "Prefer upgrades from upcoming guide quests (within 2 levels)" (K23). "Look ahead for a new
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

**K21. Item tooltips in the window.** Hover a plan item in the Gear Plan, then a row in Slot Upgrades,
Sources (an item row) and the Wishlist, and a greyed "not available now" pick:
- the top is the game's own item tooltip: name in quality colour, binding, slot, armor, the stats
  (green "Equip:" lines too). For an "of the Owl" style row the name and the stats are that suffix's
  (the same suffix as the row's name);
- below a blank line, PoleSim's lines: Score and its terms, "Gain over what you wear", your pick /
  wishlist marks, the sources (zone, cost, needs, route), the hint at the bottom. **Only one** score
  block: no second "Score"/"PoleSim score" line and no "Shift: how?" line from the bag tooltip;
- an item you have never seen this session may show "Retrieving item information" for a moment: then
  the stats fill in and PoleSim's lines are still there;
- hold **Shift** while hovering: the game's comparison tooltip(s) with what you wear open beside it
  (release: they close); PoleSim's lines stay.
Hover the **current item** (icon or name in the "Current item" column): the worn item's own tooltip
(as the equipped strip's) with the slot's plan line ("Suggested upgrade: ..." or "Your pick: ...");
a click there still opens Slot Upgrades. Hover a bag item afterwards: its usual PoleSim score line is
back. Report: a row whose stats or suffix differ from the row's name, a missing or doubled score block,
lines lost after "Retrieving item information", any Lua error.

**K22. Steps ahead on your Polestar route (0.3.3).** Polestar's guide window open, on a guide with quest
turn-ins ahead. First the turn-ins of the active guide within 15 steps (quest id, then the tag):

```
/run local R,E=PoleSimGear.Route,Polestar.Engine print("live",E.GetLiveStep()) for q in pairs(R.Build(E.GetGuide())) do local r=R.Upcoming(q) if r and r.ahead and r.ahead<15 then print(q,R.Tag(r)) end end
```

Expected: `live 75` (your step) and lines like `1234 in 3 steps`. Then:
- open the window; on Slot Upgrades (the slot of such a reward) its row says "Quest: ... in 3 steps" in
  blue; the Gear Plan row (if it is the plan) has the blue dot and "in 3 steps" under the name; Sources
  -> Quests: the quest's header tags say "in 3 steps"; hover a row: "On your Polestar route: <guide>,
  step N (3 steps ahead)";
- hover the reward anywhere else (quest log, chat link): the item tooltip's last lines include a blue
  "Polestar: in 3 steps (<quest>)" (only once the window has been opened this session: it reads
  Polestar's quest data only while it is loaded);
- finish (or Skip) the current step: with the window open, the counts drop by one without a rebuild
  (no "Scoring items..."); the tooltip line too;
- High Robe of the Adjudicator (Assault on Fenris Isle): tagged only if one of your open tabs, or the
  guide your active one hands off to, turns that quest in ahead of where that tab is; then it names the
  guide ("<guide>, in N steps" / "next guide: <guide>"). Nothing on any guide: no tag (as before).

**K23. Upcoming guide quests over BiS (0.3.4).** Polestar's guide on a stretch with quest turn-ins
ahead (K22), window open (Gear Plan). The slots whose suggestion is a near guide quest:

```
/run local W=PoleSimGear.Window for _,s in ipairs(PoleSimGear.Browser.SLOTS) do local k,n=W.SuggestedKey(s.key) if n then print(s.key,k,"near quest") end end
```

Expected: a line per such slot (`legs 1234:0 near quest`), or none when no reward of a turn-in ahead
beats what you wear. Then:
- the Gear Plan row of that slot shows the quest's item, gold "near quest", blue "in N steps" and "BiS
  +N" (the best overall's gain); hover: "Best overall: <item> +N (<source>)";
- the equipped strip's tooltip of that slot: "Suggested upgrade: <the quest's item> +N";
- Slot Upgrades on that slot: the quest's row says "Suggested", the BiS row is still listed ("Set as
  plan"); Set as plan on the BiS row -> Gear Plan: "Your pick" (a pick always wins);
- a reward of a quest NOT on your guide (or above your level + 2) is never suggested over the best;
- Settings: untick "Prefer upgrades from upcoming guide quests (within 2 levels)": the Gear Plan shows
  the best overall again (no "near quest"); tick it again.

**K24. Weapon set (0.3.5).** Wearing a staff (e.g. Wind Rider Staff), window open (Gear Plan, All gear):

```
/run local W,P=PoleSimGear.Window,PoleSimGear local m,o=P.View.Weapons(W.state.model,P.Context.Get().worn,W.St(),W.St().ahead) print(m.plan and m.plan.c.inst.name,m.plan and m.plan.gain,o.twoHander,o.plan and o.plan.c.inst.name)
```

Expected: one line: the main-hand plan and its gain, then `true nil` when the best set is a two-hander
(or the staff you wear), else `nil <off hand>`. Then:
- best set a two-hander: Main hand row = it (gain over the staff); Off hand row greyed "Uses the
  two-hander", no gain, no number; hover: "Off hand: uses the two-hander"; Upgrades only: no Off hand row;
- best set a one-hander + off hand: both rows planned, each tooltip "with <other> (also planned)" and
  "Weapon set: +X over <staff>"; the two Gain cells add up to X (the main hand may be negative);
- Sources: untick Dungeons: the off hand never pairs with a dungeon one-hander; if no pair beats the
  staff any more, the Off hand row "uses the two-hander";
- Slot Upgrades > Off hand: every row "with <one-hander> in the main hand" (from the ticked sources);
  Set as plan on a one-hander (Main hand list): the off hands now pair with it; Show: All gear also lists
  the off hands whose pair loses (negative gain); the count line counts only upgrades;
- Choose an off hand as your pick: the Main hand row becomes the best one-hander (no staff);
- header progress: "N / 14".

## L. Later in the session (or another session)

**L1. Arrows follow changes.** Level up, change talents or equip something: within a moment the arrows
in open bags, vendor and mail update (no `/reload`); opening a bag or the vendor does not stutter.

**L2. Another character** of the account: no Polestar question (the answer is account-wide).

**L3.** Group loot roll (H3) and auction house (I2), if skipped above.

## M. On a mage (0.3.0)

Log in on a mage (any level; the first tester is a Frost mage).

**M1. Spec auto-detect.**

```
/psg spec
/run local c=PoleSimGear.Context.Get() print(c.cls,c.spec,c.specSource,c.level,c.band.upTo,c.ref,c.classBit)
```

Expected: `spec frost (talents)` with the talent points per column Arcane/Fire/Frost (e.g. `0/0/11`;
no points yet: `frost (default)`); the second line `mage frost talents <level> <band end> spFrost 128`.

**M2. Weights tab.** `/psg`, tab Weights: the header says Frost, the radios are Automatic, Arcane,
Fire, Frost only (no priest specs); the reference line says `in points of Frost spell damage.`;
choosing Fire switches the reference to Fire spell damage; back to Automatic.

**M3. Tooltip.** Hover a cloth item with Frost (or plain spell) damage: the second PoleSim line reads
`Frost, levels X-Y: points of Frost spell damage`. A one-hand sword or a dagger shows a score; a mace,
a shield and a priest-only item show nothing.

**M4. Gear Plan sane.** Gear Plan tab: the top rows carry Frost/spell damage, Stamina and (below 30)
a wand high up (wand DPS weighs a lot at low level); Intellect and Spirit weigh little. No mace,
shield or priest-only item anywhere; swords appear in Main hand. Report the first five rows (item,
gain, source).

## N. Auction house upgrades (0.4.0)

At an auctioneer, on a priest (and once on a mage). Report the numbers and anything that reads wrong.

**N1. Open the auction house.** A "PoleSim upgrades" button sits just right of the auction house's
top-right corner, the panel below it (title, Scan for upgrades, "Gear you can wear up to level N",
Gain / Value / Price, an empty list). Clicking the button hides the panel; close and reopen the auction
house: it stays hidden; click again to show it. Report if it covers your bags or another window.

**N2. Scan.** Click **Scan for upgrades**: it turns into Cancel and the line says "Scanning 1/6...",
"2/6"... then "Scoring N results..." and "Done: N upgrades in M results" (", K not scored" for items
PoleSim has no data for). Time it (about 6 searches, each a few pages). No error, no
"too many requests" message. Run it a second time: same counts.

```
/run print(PoleSimGear.AH.Status(), #PoleSimGear.AH.Rows())
```

**N3. Rows.** Each row: icon, name in its quality colour (with "of the ..." when the auction has one),
the slot below, "lvl N" in gold for an item above your level (set Look ahead to 2-3 in the window
first), "any suffix" when the browse list gives one row for every suffix, the gain in green, the price
in gold/silver/copper and the gain per gold. Nothing you wear, nothing worse than what you wear, no
item another class needs. A star lights for wishlist items, "plan" in gold for your Gear Plan item.

**N4. Sort.** Gain (biggest first), Value (most gain per gold first), Price (cheapest first): the list
reorders at once.

**N5. Hover.** The game's item tooltip (with the row's suffix), PoleSim's score lines, "Auction house:
<price> (cheapest)", "Gain per gold", for a weapon under your staff "Weapon set with <off hand>", for an
"any suffix" row which suffix scored it, and "Click: its listings in the auction house". Shift compares.

**N6. Click and buy manually.** Click a row: the auction house shows that item's listings, cheapest
first (the item buy view). Click another row while there: its listings replace them. Buy one yourself
with Blizzard's Buyout button: it must work as usual (report any "blocked" or "interface action failed"
message). Equip it: the row leaves the list. If a click says "the item's data is not loaded yet", click
again.

**N7. Gear Plan while the auction house is open.** `/psg`: a Gear Plan row whose item is for sale says
"AH: <price>" in its second line; hover the equipped strip's slots: a slot where the scan found a bigger
upgrade than the plan ends with "AH: <item> +N (<price>)". Close the auction house: both are gone.

**N8. Cancel and closing.** Start a scan and click Cancel: "Cancelled (n/6 searched)" and what it had
found is listed. Start another and close the auction house mid-scan: no error; reopen: the panel is
empty ("Gear you can wear..."). Search for something yourself mid-scan: "Stopped: another search
started".

**N9. Weapon set partner (0.7.2).** Wearing a staff, scan; find a one-hander row whose tooltip says
"Weapon set with <off hand>". The tooltip ends with "Right-click: <off hand>'s listings". Right-click the
row: the off hand's listings show. Right-click the off hand's row: the one-hander's. Left-click the
one-hander row: its listings, and a "Next: <off hand>" button right of Gain / Value / Price; click it:
the off hand's listings, the button hides. Left-click a non-weapon row: no Next button; right-click it:
nothing happens. Then buy something with Blizzard's Buyout button: no "blocked" message.

**N10. Weapon set rows (0.7.3).** Same scan: the one-hander and the off hand rows each carry the other's
small teal-framed icon on their icon and "+ <partner>" in teal on the second line; their Price is the
sum of both (the tooltip's "... together" figure) with "set of 2" under it, and Gain/g = gain / that
price in gold. Sort by Price: the set rows sit at the pair's price. A chest or ring row: no small icon,
plain slot line, its own price.

**N11. Slot filter (0.7.4).** After a scan the Slot dropdown (right of Gain / Value / Price) says "All
slots"; open it: All slots, then only slots in the list, head to ranged, each with its count. Pick one:
only that slot's rows, from the top; Price/Gain still sort them. Wearing a staff, pick Main hand, click a
one-hander set row, then "Next: <off hand>": the off hand's listings, though its row is hidden. Scan
again: the choice stays. Close and reopen the auction house: All slots. Then a raid marker from the
target frame's menu: no "blocked" message.

**N12. Slot dropdown waits for a scan (0.7.5).** Open the auction house: the Slot dropdown is faded and
does nothing; its tooltip says "Scan first". Scan: it stays faded while scanning, then turns on. Scan
again: faded during the scan, your choice is back after it.

If the browse rows of "of the ..." items never show their suffix (every such row "any suffix"), paste
this after a normal search for e.g. "of the Owl" and report the lines:

```
/run local r=C_AuctionHouse.GetBrowseResults() for i=1,math.min(8,#r) do local k=r[i].itemKey local n=C_AuctionHouse.GetItemKeyInfo(k) print(k.itemID,k.itemSuffix,k.itemLevel,n and n.itemName) end
```

## O. Our popups, no taint (0.4.4)

**O1. Raid marker after our menus.** As the 0.4.4 paragraph at the top: header Look ahead dropdown (its
popup opens under it with a dot on the current choice; a click picks and closes; Escape closes only the
popup, a second Escape the window), Slot Upgrades slot picker, a Gear Plan right-click (slot name in gold,
Choose another upgrade, Back to suggestion on a pick, Add/Remove wishlist), then a mob's target frame >
Target Marker Icon > Skull: set, no "blocked" popup; with `/console taintLog 1` no PoleSimGear line in
Logs/taint.log.

## P. Equip prompt (0.5.0)

Before: a full game restart (new file), Polestar's guide window shown, Polestar's own Gear module off (as
after "Yes" in A4; with it on our prompt stays quiet: P6).

**P1. Loot an upgrade.** Loot (or buy from a vendor, or take from mail) a piece you can wear now that
shows our green arrow in the bags. A card appears directly above Polestar's guide window: icon with a
quality border, the name, the slot and "Upgrade +N (+N%)" in green, Equip, Not now and X. Hover the icon:
the item's own tooltip with our score line and "Right-click the card: never ask for this item". Move
Polestar's window: the card follows. Hide Polestar's window (its close button or /polestar hide): the card
moves under the minimap; drag it somewhere and show Polestar's window again: back above it. Items already
in the bags at login and moving an item to another bag never ask. Screenshot the card.

**P2. Equip.** Click Equip: the item goes on (a bind-on-equip item first shows the game's "will bind"
confirmation; Okay equips it, Cancel leaves it in the bags and the Equip button comes back after a few
seconds). Chat: "Wearing <item> (Upgrade +N (+N%))." and the card closes. A ring or trinket replaces the
weaker of the two you wear (the one the tooltip compares against).

**P3. In combat.** Pull a mob, then loot an upgrade during the fight (or have one waiting): the Equip button
is greyed and reads "After combat"; clicking it does nothing. When the fight ends it reads Equip again
and works.

**P4. Queue, Not now.** Get two upgrades at once (a quest reward plus a vendor buy, or `/psg ask` with two
upgrades in the bags): "1 of 2" top right; Not now (or X) shows the next; the last one has no counter.
Not now remembers that copy for the session (it does not ask again; `/psg ask` does).

**P5. Never.** Right-click the card > Never for this item: it closes and the same item never asks again (on
any character). Settings shows "1 item never asked" and Clear; Clear empties it.

**P6. Settings and Polestar.** Settings: "Ask to equip upgrades I pick up" off: no card for a new upgrade.
"Minimum gain to ask to equip" +5%: a smaller upgrade does not ask. With Polestar's Gear module on
(Polestar options: Questing > Rewards & gear > Gear advice), the Settings note says Polestar's "Wear it"
asks, and our card does not show (only Polestar's banner offers it): never two prompts for one item.

## Q. Warlock, Druid, Shaman, Paladin (0.6.0)

On an alt of a new class (any level; 40+ shows mail/plate on a shaman/paladin). Report the printed lines.

**Q1. Spec auto-detect.**

```
/psg spec
/run local c=PoleSimGear.Context.Get() if c then print(c.cls,c.spec,c.specSource,c.level,c.band.upTo,c.ref,c.classBit) else print("no context") end
```

Expected: `spec <key> (talents)` with your talent points per column (Warlock Affliction/Demonology/
Destruction, Druid Balance/Feral/Restoration, Shaman Elemental/Enhancement/Restoration, Paladin Holy/
Protection/Retribution), the most points wins; no points yet: `affliction`/`balance`/`elemental`/`holy`
`(default)`. Second line e.g. `warlock affliction talents 21 29 spShadow 256`, `druid balance ... sp 1024`,
`shaman elemental ... sp 64` (Restoration: `str`), `paladin holy ... str 2`.

**Q2. Unsupported spec (since 0.7.1 every spec has weights: skip unless a later release gates one).** With most
points in such a tree (or on a friend's character): at login (or after `/reload`) one chat line
`<Class> <Spec> isn't supported yet. Pick a supported spec in Settings to use its weights.`; no PoleSim
line in item tooltips, no arrows; the minimap button is there; `/psg` opens the window: the header says
`<Spec> (not supported)`, the Gear Plan says the same sentence. Settings > Spec lists only Automatic and
the class's supported specs (Druid: Balance, Restoration; Shaman: Elemental, Restoration; Paladin:
Holy); picking one scores with its weights (tooltips, Gear Plan); Automatic brings the message back.

**Q3. Weights tab and Settings.** Weights tab: the radios are Automatic plus the supported specs only
(no Feral/Enhancement/Retribution/Protection); Settings shows the Spec choice and the line "Healer specs'
weights are for leveling (killing while questing), not dungeon healing."

**Q4. Tooltips by proficiency.** Hover, and report any that differ:
- Warlock: a dagger, a one-hand sword, a staff and a wand show a score; a mace, leather and a shield don't.
- Druid: leather, a mace, a two-hand mace, a staff, a dagger and a fist weapon show a score (an idol
  scores 0: its effect isn't scored); mail, a shield, a wand and a totem don't. **Also report:** at
  20+, is a polearm's "Polearm" line white (usable) or red in the game's tooltip? (The client has a
  druid polearm row; PoleSim follows Classic: no polearms.)
- Shaman: leather, a shield, a totem, a one- or two-hand axe/mace, a staff, a dagger, a fist weapon show
  a score; mail only from 40 (at 39 nothing); a sword, plate and a wand don't. **Also report:** is a two-hand axe's or mace's type line white or red without the
  Enhancement talent? (Classic needed the talent; PoleSim lets shamans use them.)
- Paladin: mail, a shield, a libram, one- and two-hand swords/maces/axes and a polearm show a score;
  plate only from 40; a staff, a dagger and a wand don't.

**Q5. A score equals the website.** Hover one worn item, Shift for "how?"; on
https://polesim.petllama.com/#armory pick the same class, spec and level and the same item: the score
and the parts are the same.

**Q6. Gear Plan sane.** Gear Plan tab: Main hand suggests two-handers for a druid, shaman or paladin
(no off-hand suggestions: PoleSim plays them with a two-hander), one-handers and off hands for a
warlock; no item of an armor type you can't wear yet. Report the first five rows (item, gain, source).
A Holy paladin's or Restoration shaman's top rows may be Strength and weapon DPS: they melee while
leveling.

**Q7. Auction house** (if near one): Scan for upgrades: the scan's steps count the class's armor types
(e.g. a level 40 shaman: cloth, leather, mail, shields, jewelry, 7 weapon types = 12), the rows are items
you can wear.

## S. Warrior, Rogue, Hunter, Feral, Enhancement, Retribution (0.7.0)

On a character of one of these specs (any level; 20+ for dual wield and off-hand checks). After the
game restart. Report the printed lines.

**S1. Spec and reference weapon.**

```
/psg spec
/run local c=PoleSimGear.Context.Get() if c then print(c.cls,c.spec,c.specSource,c.level,c.band.upTo,c.ref,c.w._mhSpeed,c.w.speed,c.w._ohSpeed,c.w.ohSpeed,c.w._rSpeed,c.w.rspeed) else print("no context") end
```

Expected: your spec from the talents (no points yet: `arms`, `combat`, `beastmastery`, and for a druid,
shaman or paladin their caster spec `balance`, `elemental`, `holy` `(default)`); the second line e.g. `warrior arms talents 30 39 str 3 9.8 nil
nil nil nil` (reference main-hand speed and its weight; rogues also the off hand, hunters the ranged
weapon). Feral: `nil` speed (the paw ignores it). Protection (warrior or paladin, 0.7.1): e.g. `paladin
protection talents 45 49 str 2.4 -14 nil nil nil nil`; the Weights tab shows the tank note under the spec
choice (Prot Paladin: also the block / weapon speed note).

**S2. Slow vs fast at the same DPS.** Hover two weapons of about the same DPS and different speed (e.g. a
3.6 s and a 2.7 s two-hander for Arms/Ret/Enhancement, a slow and a fast one-hander in the main hand for
Combat): with Shift, the "how?" has a "Weapon speed (s over the reference weapon, at most ±0.6)" line,
positive for the slower one. Compare one score with https://polesim.petllama.com/#armory (same spec and
level): same score and parts.

**S3. Weapon rules.** Assassination/Subtlety: hover a one-hand sword or mace: it is compared in the off
hand only (grey line "in the off hand"), never as a main hand; a main-hand-only sword or mace: "not for
Assassination" (red) and the red line "Backstab, Ambush and Mutilate need a dagger in the main hand", no
arrow. Hunter: a thrown weapon says "not for <spec>" and "Auto Shot, Aimed Shot and Multi-Shot need a bow,
gun or crossbow"; a bow scores. Report the lines.

**S4. Dual wield.** Rogue (or Fury warrior 20+): hover a one-hander: it is compared in the hand where it
gains most (an off-hand comparison has the grey line "in the off hand"). Gear Plan: Main hand and Off
hand rows suggest different items (never the same one-hander twice). Report both rows.

**S5. Gear Plan sane.** Gear Plan tab: Arms/Ret/Enhancement/Feral/hunter main hand suggests two-handers
(no off-hand list: "Uses the two-hander"); Assassination/Subtlety main hand only daggers; hunter ranged
only bows, guns and crossbows. Report the first five rows (item, gain, source) and anything absurd (an
item far above your level, a weapon type you can't use).

**S6. Weights tab.** The radios list the class's supported specs only (Warrior: Arms, Fury; Paladin: Holy,
Retribution); the weight list shows "Weapon speed ..." (and off-hand/ranged speed) rows; a negative one
(e.g. off-hand speed for Combat) sits at the bottom.

## R. Recording for PoleSim (0.7.0)

Before: a full game restart (new files). Any class, out of a dungeon. `/console scriptErrors 1`.

**R1. The question.** About 8 s after login, out of combat: a PoleSim-styled dialog "Help improve PoleSim's
gear weights?" with what is recorded / never recorded and **Yes, record** / **No thanks**. In combat it
waits until the fight ends. Click Yes: chat "Recording leveling data for PoleSim ...". Screenshot it.
`/reload`: it does not ask again (nor on another character).

**R2. State.** `/psg record` prints "Recording on; 0.0 h of active play recorded; ...". Settings tab, right
column: "Record leveling data for PoleSim" and "Ask me to upload every 4 h of play" ticked, the hours and
an Export now button.

**R3. A pull.** Kill one mob with a few casts, wait 3 s, then:
`/run local b=PoleSimGearCharDB.rec.blocks b=b[#b] local p=b.p[#b.p] print(#b.p,p.n,#p.k,p.k[1] and p.k[1][3],p.e-p.s,p.l)`
prints: pulls so far, mobs engaged (1), kills (1), the XP the kill paid (as in chat), fight seconds, your
level. Then two mobs at once: the second number is 2. Casts of the last pull:
`/run local b=PoleSimGearCharDB.rec.blocks b=b[#b] for id,n in pairs(b.p[#b.p].c) do print(id,C_Spell.GetSpellName(id),n) end`
(the opener cast just before the fight counts).

**R4. The mobs.** `/run local b=PoleSimGearCharDB.rec.blocks b=b[#b] for _,m in ipairs(b.p[#b.p].m) do print(unpack(m)) end`
prints each mob: creature id, level, creature type, 1 if it uses mana. If it prints nothing, report it
(identity secret in combat on this content: the pull then has flag "s").

**R5. Character sheet.** `/run local c=PoleSimGearCharDB.rec.blocks[1].c[1] print(c.l,c.cls,c.hp,c.mp,c.ar,c.mr[1],c.mr[2],#c.it,#c.ta)`
prints level, class, max health and mana, armor, mana regen out of combat and while casting (per second;
both 0 for a warrior/rogue), items worn, talent nodes. After the next level-up (3 s, out of combat) there
is a second sheet: `/run local b=PoleSimGearCharDB.rec.blocks print(#b[#b].c)`.

**R6. A meal.** Eat or drink 10 s, stand up, then
`/run local b=PoleSimGearCharDB.rec.blocks b=b[#b] local m=b.m[#b.m] print(m and m.k,m and m.d,m and m.a,m and m.i)`:
f/d/b, seconds sat, the aura's length, nil (1 when a pull interrupted it).

**R7. AFK.** `/run print(PoleSimGear.Record.ActiveSeconds())`, then `/afk` for 3 minutes, come back, move
for 10 s and run it again: it grew by about 10 s, not 190.

**R8. Export and upload.** `/psg export`: a window with one line of text, already highlighted; Ctrl+C. Open
https://polesim.petllama.com/upload, paste, tick the Cloudflare check, Send: a 6-character code. In game:
**I uploaded it**, type the code, **Confirm** (or Enter): chat "Thanks! ..."; `/psg record` now says 0.0 h
since the last upload. A wrong code says it doesn't match and deletes nothing.

**R9. The reminder.** Force it: `/run PoleSimGearCharDB.rec.askAt=0` and wait 5 s out of combat (not at a
vendor/mailbox/AH, not casting): the card "N h of leveling recorded. Upload it?" with Copy export, Later,
Stop asking. Pull a mob while it shows: it hides and comes back after. Later: gone for an hour of play.
Force again, Stop asking: never again; Settings "Ask me to upload every 4 h of play" back on: it shows.

**R10. No taint.** After the dialogs and the export window, use a unit frame's menu (Target Marker Icon >
Skull) on your target: no "blocked" message.

## T. Small changes (0.7.0)

**T1. No "lvl 0".** Open the window: Gear Plan, Slot Upgrades (a slot with a quest reward that has no
required level), Sources > Quests (a quest with no level) and the AH upgrades panel: a missing level is
blank, never "lvl 0", "(0)", "[0]" or "level 0". Hover such a row: the source line has no "(0)".

**T2. /psg drift.**

```
/psg drift
```

Expected: either "drift: no differences (N items checked)" or one line per item "Name (id): stat
shipped -> live, ..." (at most 15, then "and N more"), plus "N items not loaded yet, run again" if some
were not cached (run it again after a few seconds: the count drops). Running it twice at once prints
"ran a moment ago, try again in N s". `/psg drift 8071` checks one item (Sizzle Stick). Send me the list
if it shows differences.

**T3. Polestar's Gear notice.** With Polestar's Gear module on (and the Polestar question answered
earlier), log in: one chat line "PoleSim Gear: Polestar's Gear is on: PoleSim Gear's equip prompt stays
quiet." once; `/reload` shows it again (a new session), turning Polestar's Gear off: none at the next login.

**T4. Default spec.** A druid, shaman or paladin with no talent points (a new character, or after a
talent reset): `/psg spec` says `balance` / `elemental` / `holy` `(default)`.

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
| K21 | item tooltips in the window (suffix stats, one score block, Shift compare, current item) | |
| K22 | Polestar route: "in N steps", count drops after a step, other tab / next guide | |
| K23 | upcoming guide quests over BiS: "near quest", "BiS +N", Suggested, setting off | |
| L1 | arrows follow changes | |
| L2 | other character not asked | |
| M1 | mage: spec auto-detect, context | |
| M2 | mage: Weights tab (Frost, mage specs only) | |
| M3 | mage: tooltip (Frost spell damage; swords yes, maces no) | |
| M4 | mage: Gear Plan sane (first five rows) | |
| N1 | AH: button, panel, hide kept | |
| N2 | AH: scan, progress, counts, time | |
| N3 | AH: rows (suffix, slot, lvl N, gain, price, gain/g) | |
| N4 | AH: sorts | |
| N5 | AH: hover tooltip | |
| N6 | AH: click -> listings; manual buy works | |
| N7 | AH: Gear Plan "AH:" price and strip line | |
| N8 | AH: cancel, close mid-scan, own search | |
| O1 | our popups; then Skull from the target frame not blocked, taint.log clean | |
| P1 | equip prompt above Polestar; tooltip; follows; fallback place | |
| P2 | Equip: worn, chat line, ring/trinket slot; bind confirmation | |
| P3 | in combat: After combat, then Equip | |
| P4 | queue 1 of 2; Not now | |
| P5 | Never; Settings count and Clear | |
| P6 | switch off, minimum gain, quiet with Polestar's Gear on | |
| Q1 | new class: spec auto-detect, context | |
| Q2 | unsupported spec: message, Settings choice | |
| Q3 | Weights radios, Settings spec + healer line | |
| Q4 | tooltips by proficiency; druid polearm / shaman 2H answer | |
| Q5 | score = website | |
| Q6 | Gear Plan sane (two-handers for druid/shaman/paladin) | |
| Q7 | AH scan steps and rows | |
| S1 | melee/hunter/tank: spec, reference weapon, tank note | |
| S2 | slow vs fast weapon: speed line, score = website | |
| S3 | dagger / bow-gun-crossbow rules in the tooltip | |
| S4 | dual wield: better hand, no item planned twice | |
| S5 | Gear Plan sane (two-handers, daggers, ranged types) | |
| S6 | Weights tab: supported specs, speed rows | |
| R1-R10 | Recorder: question, state, pulls, mobs, sheet, meal, AFK, export/upload, reminder, no taint | |

## Known limits (tell me if they bother you)

- Recorder: Forever closes the combat log to addons, so kills come from UNIT_DIED / PARTY_KILL and the
  XP from the kill's chat line (its number only); a mob's identity can be secret in combat on some
  content (pull flag "s": the mob is counted but not described). Active play = activity (moving,
  casting, fighting, looting, quests) with gaps under 2 minutes and the AFK flag off; standing still
  reading quest text for over 2 minutes counts as a pause. Creature types are the client's words (in its
  language).

- A drop of dungeon trash counts as "Dungeon" (as on the website), so some BoE greens show as dungeon
  drops with a small chance.
- Reputation, PvP, raid and "opened from an item" (container) sources are not listed.
- Crafted items are gated by "about level = skill / 5" (the website's rule), not by your profession.
- The tooltip compares one item with what you wear: a one-hander under a worn two-hander says it
  leaves the off hand empty, while the window pairs it with the best off hand (R9).
- Weapon sets mix bands with look ahead: a level-23 off hand paired with a one-hander you can wear now
  is scored with the weights of its own level, like every "coming up" row.
- Warrior and Paladin Protection (0.7.1): tank weights are less certain (Stamina, armor, avoidance).
  Prot Paladin's level-60 weapon speed weight is set to neutral (PoleSim's sim and wowsims/forever
  disagree on it); below 60 faster weapons score better until ~55.
- Weapon speed counts at most 0.6 s from the reference weapon (the range PoleSim measured): a 3.8 s and a
  3.4 s two-hander score the same speed part when the reference is 2.8 s. Within the range the speed
  weight is a straight line; PoleSim's check found the real gain flattening above the reference at
  higher levels (the line overstates a slower weapon by up to ~3% of its score).
- Hunters' melee weapon is scored as a two-hander (PoleSim plays them with one); dual-wielding hunters
  get no off-hand list.
- Relics (idols, totems, librams) score their stats only; their effects are not modelled, so every relic
  scores 0 today and the auction house scan does not search for them.
- Druid, Shaman and Paladin: the window suggests two-handers only (PoleSim plays them with one, as the
  website does); a shield or off hand gets a tooltip score and AH rows, not a Gear Plan row.
- Restoration and Holy weights are leveling weights (killing while questing), not dungeon healing.
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
- The dropdowns and the right-click menu are our own popup (Blizzard's menus taint the unit menus).
- Auction house: the scan sees what the browse list shows (one row per item, its cheapest price); a
  browse row that stands for every suffix is scored with its best suffix ("any suffix"). Under a staff a
  one-hander is paired with the best off hand for sale (not with a Gear Plan item). After a scan the
  auction house's own list shows the scan's last search. Prices are not kept after the auction house
  closes.
