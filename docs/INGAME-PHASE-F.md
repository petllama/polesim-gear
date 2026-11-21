# In-game checks: Phase F (coexisting with Polestar's Gear module)

For the user, on a priest. Paste each line into chat as it is (every `/run` line is under 255
characters). Turn on Lua errors first: `/console scriptErrors 1` (or use BugSack). Report any error
with its text.

## Before you start

1. `tools/install.sh` (already run once for this phase).
2. **Full game restart** (new file `Coexist.lua`; `/reload` is not enough).
3. Polestar's Gear module on (Polestar options: Gear). Check:

```
/run print(PoleSimGear.Coexist and "coexist ok", Polestar.Gear and Polestar.Gear.IsEnabled(), PoleSimGearDB.askedPolestarGear)
```

Expected: `coexist ok true nil` on the first login after the restart (`nil` = not answered yet).

What it does: on login (after ~5 s), while Polestar's Gear module exists and is on and you have not
answered yet, one question: "Polestar's gear scores are on. Turn them off so you see one score?". It
changes Polestar's setting only on **Yes** (`Polestar.Set("gear.enabled", false)`, which Polestar
applies at once: no `/reload`). The answer is remembered for the whole account; Escape counts as No.
In combat the question waits until combat ends.

To ask again (for these checks, or to change your mind): `/psg polestar` (forgets the answer and asks
now), or `/run PoleSimGearDB.askedPolestarGear=nil` then `/reload`.

## Task 36: the prompt

1. Log in (or `/reload`) with Polestar's Gear on: the question appears after ~5 s.
2. Click **No**. Chat: "Both score items: ours is the line that says PoleSim." Hover an item: Polestar's
   tooltip line and ours both show; ours starts with **PoleSim score**. Bag arrows: Polestar's
   top-left, ours top-right.
3. `/reload`: no question (the answer is remembered). `/run print(PoleSimGearDB.askedPolestarGear)`
   prints `no`.
4. `/psg polestar`: the question again. Click **Yes**. Chat: "Polestar's gear scores are off ...".
   At once (no `/reload`): Polestar's tooltip line and its bag arrows are gone; ours stays and says
   **Score** (no "PoleSim" label). Check:

```
/run print(Polestar.Gear.IsEnabled(), Polestar.Get("gear.enabled"), PoleSimGearDB.askedPolestarGear)
```

   Expected: `false false yes`.
5. Log in on another character of the account: no question.
6. Combat: `/run PoleSimGearDB.askedPolestarGear=nil` with Polestar's Gear turned back on in its
   options, then pull a mob and `/reload` during the fight (or `/psg polestar` in combat): no
   question while in combat; it appears when combat ends.
7. Polestar's Gear off in its options, `/psg polestar`: chat says "Polestar's gear scores are off:
   nothing to ask." and no question.
8. Turn Polestar's Gear back on in its options afterwards if you want it.
