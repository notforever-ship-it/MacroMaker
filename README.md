# Macro Maker

Build macros for any class without typing code. For the 1.12 client: Turtle WoW, OctoWoW and other
vanilla servers. No client mods needed (SuperWoW is used for cleaner mouseover casts when present).

Type `/mm` or click the minimap button. The **Help** button in the window (or `/mm help`) has
step-by-step instructions.

## How it works

1. **What should the button do?** Pick from the list on the left: cast on mouseover, keep a buff up,
   attack without toggling off, cast sequence, low health emergency, use trinkets, announce in chat...
2. **Fill in the blanks** by clicking your spells in the list on the right. It reads your own spellbook,
   so it works for every class and for custom spells. The Items tab lists what you carry, the Macros
   tab loads a macro you already have.
3. **Add to macro.** A macro can have several steps; they run top to bottom on each press.
   Steps that only cast when needed (a missing buff, a missing debuff, a cooldown) let you stack a
   priority list on one button: the first step that has something to do uses the key press.
4. **Create macro.** It lands on your cursor: drop it on an action bar. Saving under a name that
   already exists updates that macro where it sits.

The icon comes from the first spell you click; right-click any spell or item to use its icon instead.
Tick "All ranks" to pick an exact rank (downranked heals).

## Plain macros and helper macros

The 1.12 client has no `[conditions]` in `/cast`. Simple recipes are written in the game's own commands
and work without the addon. The smart ones call short helper functions this addon provides, like
`/script MMK.Over("Flash Heal")`, which keeps them far below the 255 character limit. Those macros need
Macro Maker to stay enabled; the window tells you which kind you've built.

| Helper | What it does |
| --- | --- |
| `MMK.Cast("Spell")` | cast a spell, or use an item with that name; only the first cast of a key press goes out |
| `MMK.Self("Spell")` | cast on yourself, target unchanged |
| `MMK.Over("Spell")` | cast on whoever is under the mouse, in the world or on unit frames |
| `MMK.Unit("Spell","targettarget")` | cast on a unit without targeting it |
| `MMK.Friend("Heal","Nuke")` | first on friends, second on enemies |
| `MMK.Mod("shift","Held","Normal")` | another spell while Shift, Ctrl or Alt is held |
| `MMK.First("A","B","C")` | the first one that isn't on cooldown |
| `MMK.Seq(8,"A","B","C")` | cast sequence, starting over after 8 idle seconds |
| `MMK.Buff("Spell")` / `MMK.Debuff("Spell")` | only when you / your target don't have it yet |
| `MMK.HP(30,"Below","Otherwise")` | by your health; `MMK.Mana` by your mana, `MMK.THP` by your target's health |
| `MMK.Combat("In","Out")` | by whether you're in combat |
| `MMK.Attack()` / `MMK.Auto("Auto Shot")` | start attacking or shooting, never toggle it off |
| `MMK.Enemy()` | target the nearest enemy when you have no live target |
| `MMK.Form("Bear Form")` / `MMK.Unform()` | switch stance or form unless already in it / leave form |
| `MMK.Use("Item")` / `MMK.Trinkets()` / `MMK.Equip("Item",16)` | items by name; never "uses" a bag item while a vendor, bank, trade, mail or auction window is open |
| `MMK.Say("Sheeping %t!")` | announce once even when mashing; picks raid, party or say |
| `MMK.Cancel("Buff")` | click a buff off |

## Development

- `node tools/check-lua.js` checks the code against Lua 5.0 and the 1.12 API (no Lua install needed).
- `node tools/install.js [AddOns path]` copies the addon into the game.
