# To do (after the first in-game test of 0.2.0)

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

- [ ] **"Upgrades" guide** in its own Polestar tab, built from the window's Gear Plan
      (`Polestar.Lookup.RegisterPlanner`, `RegisterGuide`, `Engine.SetGuide`, `API.ReplaceSteps`):
      pick up quest X (reward Y, +gain), run dungeon Z, craft W; updated as items are gained.
      `ReplaceSteps` refuses Polestar's own guides, so nothing is inserted into the leveling route.

## Ask Fitz (upstream)

- [ ] A small API for another addon to supply gear scores (e.g. `Polestar.API.SetGearProvider`), so
      Polestar's own wear banner, reward auto-equip/auto-pick, guide reward pick and "when upgrade"
      steps keep working on PoleSim's weights after the Gear module is removed. Pitch it together with
      the Recorder sim-telemetry change. Also ask to list the internals we read (Codex item/quest/
      object, `Engine.GetGuide`, `Get`/`Set`) in docs/API.md.

## Melee and hunter classes (after 0.6.0)

- [ ] **Melee/hunter support**: Warriors, Rogues, Hunters and Druid Feral, Shaman Enhancement, Paladin
      Retribution/Protection. Needs the weapon rules first, in the website's armory and the addon alike:
      weapon speed (slow main hands for instant strikes, fast off hands), daggers for Backstab/Ambush,
      dual wield (the off hand at half damage, the level it is learned: Rogue 10, Warrior/Hunter 20;
      main/off-hand-only items, hit cap with two weapons), two-handers vs one-hander + shield for tanks,
      and a hunter's ranged weapon (bow/gun/crossbow DPS and speed, ammo) with the pet (stats it gets from
      the hunter). Then ship their band files in gen_addon_data `CLASSES`, add the parity cases (dual
      wield sets in SET_CASES), and drop the "not supported yet" spec message for them.
- [ ] Relic effects (idols, totems, librams: "Increases the damage of your Moonfire spell by up to 33")
      score 0 today: model them in the sim, or as spell power equivalents, website and addon alike.
- [ ] Verify in game (CHECKLIST Q4) whether Forever druids can use polearms (the client has a druid
      polearm skill row from 20; PoleSim follows Classic: no) and whether shamans need the Enhancement
      talent for two-hand axes/maces (Classic did; PoleSim and Polestar allow them).

## Data

- [ ] Drop GM/test items from the shipped table in `forever/tools/gen_addon_data.py` (e.g. 24358
      "QATest +1000 Spell Dmg Ring"); regenerate.

## From the 0.2.0 review

- [ ] Slots with no upgrade: show the best option anyway (e.g. "Best quest option: Sizzle Stick, -1.3, a sidegrade").
- [x] Drift check: `/psg drift [itemID]` lists items whose live stats differ from the shipped table (0.7.0).
