# To do (after the first in-game test of 0.1.0)

Start these once the planned features (docs/CHECKLIST.md) have been tested in game.

## Replace what Polestar's gear switch turns off

Polestar's `gear.enabled` (the switch our "turn off Polestar's gear scores?" prompt flips) also
drives these Polestar features, and they all run on its Gear module, which Fitz is removing:

- [ ] **"Wear it" banner** (Polestar `QoL/Wear.lua`): a new upgrade reaching the bags from loot or a
      merchant is offered with "Wear it" / "Not this one"; equips only on the press, out of combat
      (the client's bind-on-equip confirmation still shows); "Not this one" remembered per item per
      character; only new copies (not what the bags held at login, not a piece just taken off); the
      offer goes when the item leaves the bags or stops being an upgrade. Our own movable banner,
      placed above Polestar's guide window when it can be found (its banner is internal).
- [ ] **Reward auto-equip** (Polestar `QoL/Equip.lua`): put on a quest reward that is an upgrade
      after turn-in.
- [ ] **Reward auto-pick** (Polestar `QoL/Rewards.lua`): choose the best reward at turn-in
      automatically (ours only marks it today).
- [ ] **Guide's reward pick** (Polestar `UI/GearPick.lua`): the guide window's turn-in step shows which
      reward to take.
- [ ] **"when upgrade" guide steps** (Polestar `Core/Engine.lua`): steps shown only when an item is an
      upgrade. Without Polestar's Gear they always show; only Polestar can gate its own steps, so this
      one needs the upstream API below.
- [ ] Then settle the coexistence prompt wording (design decision pending: (a) keep the prompt and
      list everything Yes turns off, (b) no prompt and always label our line, (c) hide only
      Polestar's score line). With the replacements above in place, Yes loses nothing.

## Guides (Polestar API v1 only)

- [ ] **"Upgrades" guide** in its own Polestar tab, built from the browser's list
      (`Polestar.Lookup.RegisterPlanner`, `RegisterGuide`, `Engine.SetGuide`, `API.ReplaceSteps`):
      pick up quest X (reward Y, +gain), run dungeon Z, craft W; updated as items are gained.
      `ReplaceSteps` refuses Polestar's own guides, so nothing is inserted into the leveling route.

## Ask Fitz (upstream)

- [ ] A small API for another addon to supply gear scores (e.g. `Polestar.API.SetGearProvider`), so
      Polestar's own wear banner, reward auto-equip/auto-pick, guide reward pick and "when upgrade"
      steps keep working on PoleSim's weights after the Gear module is removed. Pitch it together with
      the Recorder sim-telemetry change. Also ask to list the internals we read (Codex item/quest/
      object, `Engine.GetGuide`, `Get`/`Set`) in docs/API.md.

## Data

- [ ] Drop GM/test items from the shipped table in `forever/tools/gen_addon_data.py` (e.g. 24358
      "QATest +1000 Spell Dmg Ring"); regenerate.
