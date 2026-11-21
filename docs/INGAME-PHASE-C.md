# In-game checks: Phase C (live item stats, tooltip line)

For the user, on a priest. Paste each line into chat as it is (every `/run` line is under 255
characters). For "this item" checks, first pick the item with `/run X=[[<item>]]`: type
`/run X=[[`, Shift-click the item into the chat box, type `]]`, Enter. The next lines read `X`.

## Before you start

1. `tools/install.sh` (already run once for this phase).
2. **Full game restart** (new files `Live.lua` and `Tooltip.lua`; `/reload` is not enough).

## Task 24: what `C_Item.GetItemStats` returns on Forever

Wear a chest piece (slot 5) and a wand (slot 18) if you have them.

```
/run local function d(l) if not l then return end print(l) for k,v in pairs(C_Item.GetItemStats(l) or {}) do print("  ",k,v) end end d(GetInventoryItemLink("player",5)) d(GetInventoryItemLink("player",18))
/run local l=select(2,C_Item.GetItemInfo(11288)) if l then for k,v in pairs(C_Item.GetItemStats(l) or {}) do print(k,v) end end
/run X=[[<item>]]
/run print(X) for k,v in pairs(C_Item.GetItemStats(X) or {}) do print(k,v) end
```

- The second line is Greater Magic Wand (`sp = 2` in our data). Run it twice: the first call may only
  ask the server.
- Run the last two lines with a green "of the Owl"/"of the Eagle" item, and with an item whose tooltip has
  an "Equip: Increases damage and healing done by magical spells..." line.

Report (copy the printed lines):

- the key for "+spell damage and healing" (expected `ITEM_MOD_SPELL_POWER_SHORT`);
- whether **Equip:** effects appear at all (spell damage, mp5, hit/crit) or are missing;
- armor as `RESISTANCE0_NAME`? DPS as `ITEM_MOD_DAMAGE_PER_SECOND_SHORT`?
- ratings as rating points (e.g. 14 for 1% crit), not percent?
- one bonus under two names? e.g. mp5 as both `ITEM_MOD_MANA_REGENERATION_SHORT` and
  `ITEM_MOD_POWER_REGEN0_SHORT`, or a hit/crit bonus as both the `..._MELEE_RATING_SHORT` and
  `..._RANGED_RATING_SHORT` keys. PoleSim Gear counts such a pair once (the larger value); report
  which pairs appear, and whether two such keys ever carry two different bonuses on one item;
- any key not in this list: `ITEM_MOD_*_SHORT` for strength, agility, stamina, intellect, spirit,
  health, mana, attack power, ranged attack power, spell power, spell damage done, spell healing done,
  each school's spell damage, mana/health regeneration, defense, block value, spell penetration, the
  hit/crit/dodge/parry/block/haste ratings, `RESISTANCE0..6_NAME`. A new key must be added to
  `Live.lua` (`PLAIN`/`RATED`) before Phase D.

### How PoleSim Gear reads the same item

With `X` set as above:

```
/run local i=PoleSimGear.Live.Instance(X) if i then print(i.id,i.bonus,i.inv,i.rl,i.armor,i.dps) for k,v in pairs(i.stats) do print(k,v,i.filled[k] and "TABLE" or "") end else print("none/pending") end
```

Expected: the item ID, its suffix id for a random-suffix green (e.g. `12720` for some "of the Owl"),
then one line per stat. A stat marked `TABLE` is an equip bonus the client did not report, filled
from PoleSim's item table (the whole family, e.g. all spell damage, comes either from the client or
from the table, never both). If equip effects are missing from `GetItemStats` (above), those stats
should show `TABLE`; if the client reports them, nothing should say `TABLE`.

## Task 26: context and worn scores

```
/run local c=PoleSimGear.Context.Get() print(c.spec,c.specSource,c.level,c.band.upTo,c.ref) for s,e in pairs(c.worn) do print(s,e.inst.id,("%.2f"):format(e.score)) end
/psg spec
```

Expected: the priest's spec with source `talents`, the band end (e.g. `39` at level 34), `spShadow`
(Shadow) or `sp` (Holy/Discipline); one line per worn slot with a score. `/psg spec` prints the talent
points per column (e.g. `0/5/21`).

- If the points are all 0 while talents are spent, report it (the column mapping failed) together with:

```
/run local c=C_ClassTalents.GetActiveConfigID() local t=c and C_Traits.GetConfigInfo(c).treeIDs[1] for _,g in ipairs(t and C_Traits.GetGroupDisplayInfoByTreeID(t) or {}) do print(g.groupID,g.displayName,g.orderIndex) end
```

### Spec right after login (new)

Right after a full restart, as soon as the loading screen is gone:

```
/run print(PoleSimGear.Context.Get().specSource)
```

then the same line again about 5 seconds later. Expected: `talents` the second time at the latest
(a `default` right after login is read again every 2 seconds, up to 5 times). If it still says
`default` after 15 seconds while you have talent points spent, report it.

### Compare with the website

On https://polesim.petllama.com/#armory pick the same spec and level, enter one worn item (search,
the same random suffix) and compare its score with the `/run` line above: equal to 2 decimals for a
plain item (enchants are ignored in both).

## Task 28: the tooltip line

`/reload` is enough after this restart. Hover:

1. a bag item, 2. a worn item (character sheet), 3. a vendor item, 4. a quest reward in the quest
log, 5. an item link in chat (click it: ItemRefTooltip).

Expected on items a priest can wear (up to 5 levels above yours):

- `Score x.x` and, on the right, `+y.y (+z%)` (green for a gain, red for a loss);
- `Shadow, levels 30-39: points of Shadow spell damage` (your spec and band);
- `requires level N` when the item is above your level; a note for rings/trinkets
  (`against your weaker one`) and two-handers (`replaces main and off hand`);
- `Shift: how?`. Holding Shift (while the tooltip is shown) redraws it with one line per stat
  (`Intellect 10 x 0.5   5.00`; a stat filled from the item table ends in `(item table)`), then
  `minus worn` and `gain`;
- worn items say `equipped` on the right;
- plate/mail/other-class items show nothing; the shopping comparison tooltips show nothing.
- With Polestar's Gear scores also on, both show (the "PoleSim score" label comes with Phase F's
  coexist prompt).

Compare one green "of the Owl" item's tooltip score with the website (same spec, level, item and
suffix). Report any Lua error (BugSack/`/console scriptErrors 1`).
