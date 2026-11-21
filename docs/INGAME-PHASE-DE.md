# In-game checks: Phases D and E (upgrade arrows, quest reward pick)

For the user, on a priest. Paste each line into chat as it is (every `/run` line is under 255
characters). For "this item" checks, first pick the item with `/run X=[[<item>]]`: type `/run X=[[`,
Shift-click the item into the chat box, type `]]`, Enter. The next lines read `X`.
Turn on Lua errors first: `/console scriptErrors 1` (or use BugSack). Report any error with its text.

## Before you start

1. `tools/install.sh` (already run once for these phases).
2. **Full game restart** (new files `Arrows.lua` and `Rewards.lua`; `/reload` is not enough).

What an arrow means: the character can wear the item **now** (armor/weapon type, required level at or
below yours) and it scores above what you wear (the tooltip's gain is green, `+x.x`). Items up to 5
levels above you get a tooltip line but no arrow. Our arrow is the client's green bag arrow in the
**top-right** corner; Polestar's own (if its Gear module is still on) sits top-left.

```
/run print(PoleSimGear.Arrows and "arrows ok", PoleSimGear.Rewards and "rewards ok", BagBrother and BagBrother.Item and BagBrother.Item.Update)
```

Expected: `arrows ok rewards ok function: ...` (the third value is Bagnon's item update, which we hook).

## Task 30: bags (Bagnon and the client's bags)

1. Open the bags (Bagnon). Put a known upgrade in a bag (an item whose tooltip shows a green `+`):
   a green arrow top-right of its icon. A worse item: none. A plate/mail item: none.
2. Equip the upgrade: its arrow goes, and the old item (now in the bag) has none.
3. Move an item between slots/bags: the arrow moves with it (no stale arrow on the old slot).
4. In combat (a training dummy or a mob), loot an upgrade with the bags open: the arrow appears; no
   "Interface action failed because of an AddOn" message, and bag items still use/equip normally after
   combat.
5. If you also use the client's own bags (Bagnon's inventory off, or the combined bag): same checks.

Which bag items PoleSim calls upgrades (compare with what you see):

```
/run for b=0,4 do for s=1,C_Container.GetContainerNumSlots(b) do local l=C_Container.GetContainerItemLink(b,s) if l and PoleSimGear.Arrows.Verdict(l) then print(b,s,l) end end end
```

For one item: `/run print(PoleSimGear.Arrows.Verdict(X))` (`true` = arrow).

If Bagnon shows no arrows at all while the line above lists upgrades, report it with the output of
the first `/run` line (Risk R6).

## Task 31: merchant and loot rolls

1. A vendor selling a cloth item, staff, dagger, mace or wand that is an upgrade: the arrow top-right
   of that item's icon. Page forward and back: arrows stay on the right items.
2. The vendor's **Buyback** tab: no arrows, even on an upgrade you sold; back on the first tab they
   return.
3. In a group (dungeon), a roll on a usable upgrade: the arrow on the roll frame's item icon; no
   arrow on items you cannot wear.

## Task 32: mail and the auction house

1. Mail yourself (from an alt) an upgrade: the inbox row's icon has the arrow; open the letter: the
   attachment has it. A letter with a non-upgrade: none. (An inbox row shows the arrow for its
   first item only.)
2. Auction house: search "Robe" / "Staff". Usable upgrades without a random suffix get an arrow at the
   top-right of their row in the result list. Items "of the ..." (random suffix) get none in that list;
   click one: in its auctions list each auction's row shows the arrow when that auction's suffix is an
   upgrade. Scroll the lists: arrows stay with their rows.
3. Report if rows show no arrow at all (Risk R7) with:

```
/run local f=AuctionHouseFrame print(f and f.BrowseResultsFrame and f.BrowseResultsFrame.ItemList.ScrollBox, f and f.ItemBuyFrame and f.ItemBuyFrame.ItemList.getEntry)
```

## Arrows follow score changes

Level up, change talents (spec) or equip something: within a moment the arrows in the open bags,
vendor and mail update (no `/reload`). Opening a bag or the vendor must not stutter.

## Task 34: the quest reward pick

Turn in a quest with two or more reward choices (e.g. one with a cloth item and a weapon):

1. The best choice for you shows our green arrow at the **left edge** of its icon and the gain at the
   **bottom** of the icon, green `+x.x`. When no choice is an upgrade, the least loss is marked with a
   grey `-x.x` and no arrow.
2. Hover each choice: the tooltip's gain (right side of the PoleSim line) equals the number on the
   icon.
3. A choice the priest cannot wear (mail, plate, a shield) or a currency choice is never marked.
4. Only the quest giver's turn-in panel is marked: the quest log and the quest's accept panel show
   no marks (tooltips only).
5. With Polestar's reward marks on, theirs (an arrow top-left, a coin top-right, a ring around the
   icon) and ours do not overlap.
6. Close the panel and open another quest's turn-in: no leftover mark.

On the turn-in panel, what PoleSim read (one line per choice, then the pick):

```
/run local R=PoleSimGear.Rewards for _,c in ipairs(R.Choices(PoleSimGear.Context.Get())) do print(c.index,c.usable,c.gain,c.score,c.pending) end print(R.Pick(R.Choices(PoleSimGear.Context.Get())))
```

Expected: `index true gain score nil` for wearable items, `index nil` for others, then the picked
index and `true` when it is an upgrade. A choice still `true` in the last column (pending) after a
second or two means its item data never came: report the quest.
