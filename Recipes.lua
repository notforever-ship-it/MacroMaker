-- Macro Maker: the recipes. Each one is a sentence with blanks, and knows how to write its macro lines.
--
-- fields: kind "name" is a spell or item (clickable from the lists), "list" is several of them,
-- "text" and "number" are typed, "choice" is a button that cycles. optional = may stay empty.
-- build(v, plain) returns the macro lines. plain is true while the macro has no MMK helper in it yet:
-- recipes that can be written in the game's own commands do so then, and the macro works without
-- this addon. Once a helper is in, casts go through MMK.Cast so only the first one of a press fires.

local MM = MacroMaker

local function Q(s)
  return '"' .. string.gsub(s, '(["\\])', "\\%1") .. '"'
end

local function Script(code)
  return "/script " .. code
end

local function CastLine(spell, plain)
  if plain then return "/cast " .. spell end
  return Script("MMK.Cast(" .. Q(spell) .. ")")
end

-- Q(a), Q(b), ... skipping empty ones at the end
local function Args(...)
  local last = 0
  for i = 1, arg.n do
    if arg[i] ~= nil and arg[i] ~= "" then last = i end
  end
  local out = ""
  for i = 1, last do
    local a = arg[i]
    if i > 1 then out = out .. "," end
    if type(a) == "number" then out = out .. a else out = out .. Q(a or "") end
  end
  return out
end

local function HasText(s)
  return s ~= nil and s ~= ""
end

local KEYS = {
  { label = "Shift", value = "shift", test = "IsShiftKeyDown()" },
  { label = "Ctrl", value = "ctrl", test = "IsControlKeyDown()" },
  { label = "Alt", value = "alt", test = "IsAltKeyDown()" },
}

local UNITS = {
  { label = "My target's target", value = "targettarget" },
  { label = "My pet", value = "pet" },
  { label = "Party member 1", value = "party1" },
  { label = "Party member 2", value = "party2" },
  { label = "Party member 3", value = "party3" },
  { label = "Party member 4", value = "party4" },
}

local CHANNELS = {
  { label = "Automatic: raid, party or say", value = "" },
  { label = "Say", value = "SAY" },
  { label = "Party", value = "PARTY" },
  { label = "Raid", value = "RAID" },
  { label = "Yell", value = "YELL" },
}

local TRINKETS = {
  { label = "Both trinkets", value = "" },
  { label = "Top trinket only", value = 13 },
  { label = "Bottom trinket only", value = 14 },
}

local EQUIP_SLOTS = {
  { label = "Wherever it fits", value = "" },
  { label = "Main hand", value = 16 },
  { label = "Off hand", value = 17 },
}

local function RangedDefault()
  local _, class = UnitClass("player")
  if class == "HUNTER" then return "Auto Shot" end
  return "Shoot"
end

MM.RECIPES = {
  { header = "Casting" },
  {
    id = "cast",
    title = "Cast a spell",
    desc = "The simplest button. Click a spell on the right. To always use one rank (healers saving mana), tick 'All ranks' first.",
    fields = { { key = "spell", label = "Spell", kind = "name" } },
    build = function(v, plain) return { CastLine(v.spell, plain) } end,
  },
  {
    title = "Cast on myself",
    desc = "Always lands on you, whoever you have targeted, and your target stays. Good for shields, heals and buffs.",
    fields = { { key = "spell", label = "Spell", kind = "name" } },
    build = function(v, plain)
      if plain then return { Script("CastSpellByName(" .. Q(v.spell) .. ",1)") } end
      return { Script("MMK.Self(" .. Q(v.spell) .. ")") }
    end,
  },
  {
    title = "Cast on mouseover",
    desc = "Lands on whoever your mouse is pointing at, in the world or on party and raid frames, without changing your target. Nobody under the mouse: your target.",
    fields = { { key = "spell", label = "Spell", kind = "name" } },
    build = function(v) return { Script("MMK.Over(" .. Q(v.spell) .. ")") } end,
  },
  {
    title = "Cast on target's target / pet",
    desc = "Lands on someone specific without targeting them. Target the boss and heal whoever it is hitting, or heal your pet.",
    fields = {
      { key = "unit", label = "Who", kind = "choice", choices = UNITS },
      { key = "spell", label = "Spell", kind = "name" },
    },
    build = function(v) return { Script("MMK.Unit(" .. Q(v.spell) .. "," .. Q(v.unit) .. ")") } end,
  },
  {
    title = "Heal friend or hurt enemy",
    desc = "One button, two jobs: the first spell when your target is friendly (or you have none: it goes on you), the second when it's an enemy.",
    fields = {
      { key = "helpful", label = "On friends", kind = "name" },
      { key = "harmful", label = "On enemies", kind = "name" },
    },
    build = function(v, plain)
      if plain then
        return { Script('if UnitCanAttack("player","target") then CastSpellByName(' .. Q(v.harmful) ..
          ") else CastSpellByName(" .. Q(v.helpful) .. ") end") }
      end
      return { Script("MMK.Friend(" .. Args(v.helpful, v.harmful) .. ")") }
    end,
  },
  {
    title = "Shift / Ctrl / Alt = other spell",
    desc = "Two spells on one button: press it normally for the first, hold the key while pressing for the second.",
    fields = {
      { key = "normal", label = "Normally", kind = "name" },
      { key = "key", label = "While holding", kind = "choice", choices = KEYS },
      { key = "held", label = "cast this instead", kind = "name" },
    },
    build = function(v, plain)
      if plain then
        local test = KEYS[1].test
        for i = 1, table.getn(KEYS) do
          if KEYS[i].value == v.key then test = KEYS[i].test end
        end
        return { Script("if " .. test .. " then CastSpellByName(" .. Q(v.held) .. ") else CastSpellByName(" ..
          Q(v.normal) .. ") end") }
      end
      return { Script("MMK.Mod(" .. Args(v.key, v.held, v.normal) .. ")") }
    end,
  },
  {
    title = "Stop casting, then cast",
    desc = "Cuts off whatever you're casting and casts this right away. For interrupts and emergency spells that can't wait.",
    fields = { { key = "spell", label = "Spell", kind = "name" } },
    build = function(v, plain) return { Script("SpellStopCasting()"), CastLine(v.spell, plain) } end,
  },
  {
    title = "Cast sequence",
    desc = "One button that works down a list, one spell per press: click the spells in order. It starts over after the list ends, or after a pause.",
    fields = {
      { key = "spells", label = "Spells, in order", kind = "list" },
      { key = "reset", label = "Start over after this many seconds idle", kind = "number", default = 8 },
    },
    build = function(v)
      if table.getn(v.spells) < 2 then return nil, "A sequence needs at least two spells." end
      local names = ""
      for i = 1, table.getn(v.spells) do names = names .. "," .. Q(v.spells[i]) end
      return { Script("MMK.Seq(" .. v.reset .. names .. ")") }
    end,
  },

  { header = "Smart casting" },
  {
    title = "First spell that's ready",
    desc = "Casts the first spell on the list that isn't on cooldown. Put the big cooldown first and your filler last.",
    fields = {
      { key = "first", label = "First choice", kind = "name" },
      { key = "second", label = "Otherwise", kind = "name" },
      { key = "third", label = "Otherwise", kind = "name", optional = true },
    },
    build = function(v) return { Script("MMK.First(" .. Args(v.first, v.second, v.third) .. ")") } end,
  },
  {
    title = "Keep a buff on me",
    desc = "Casts only when you don't have the buff, so you can put it above your main attack: add this step first, then 'Cast a spell'.",
    fields = {
      { key = "spell", label = "Spell", kind = "name" },
      { key = "buff", label = "Buff's name, if it differs from the spell", kind = "text", optional = true },
    },
    build = function(v) return { Script("MMK.Buff(" .. Args(v.spell, v.buff) .. ")") } end,
  },
  {
    title = "Keep a debuff on my target",
    desc = "Casts only when the target doesn't have it yet. Add your filler as a second step ('Cast a spell') and mash one button.",
    fields = {
      { key = "spell", label = "Spell", kind = "name" },
      { key = "debuff", label = "Debuff's name, if it differs from the spell", kind = "text", optional = true },
    },
    build = function(v) return { Script("MMK.Debuff(" .. Args(v.spell, v.debuff) .. ")") } end,
  },
  {
    title = "Low health emergency",
    desc = "Below the health you set, the first one (a spell, potion or healthstone: try the Items tab). Above it, the second, if you want one.",
    fields = {
      { key = "percent", label = "When my health is under (%)", kind = "number", default = 30 },
      { key = "below", label = "Use", kind = "name" },
      { key = "otherwise", label = "Otherwise", kind = "name", optional = true },
    },
    build = function(v) return { Script("MMK.HP(" .. Args(v.percent, v.below, v.otherwise) .. ")") } end,
  },
  {
    title = "Low mana / rage / energy",
    desc = "Below the amount you set, the first one (Evocation, a mana potion, Bloodrage...). Above it, the second, if you want one.",
    fields = {
      { key = "percent", label = "When it's under (%)", kind = "number", default = 20 },
      { key = "below", label = "Use", kind = "name" },
      { key = "otherwise", label = "Otherwise", kind = "name", optional = true },
    },
    build = function(v) return { Script("MMK.Mana(" .. Args(v.percent, v.below, v.otherwise) .. ")") } end,
  },
  {
    title = "Finisher (target low health)",
    desc = "When the target drops under the health you set, the finisher (Execute, Hammer of Wrath...). Until then, your normal spell.",
    fields = {
      { key = "percent", label = "When my target is under (%)", kind = "number", default = 20 },
      { key = "below", label = "Finisher", kind = "name" },
      { key = "otherwise", label = "Until then", kind = "name", optional = true },
    },
    build = function(v) return { Script("MMK.THP(" .. Args(v.percent, v.below, v.otherwise) .. ")") } end,
  },
  {
    title = "In combat / out of combat",
    desc = "A different spell or item depending on whether you're fighting. Fill in one or both.",
    fields = {
      { key = "fighting", label = "In combat", kind = "name", optional = true },
      { key = "resting", label = "Out of combat", kind = "name", optional = true },
    },
    build = function(v)
      if not HasText(v.fighting) and not HasText(v.resting) then return nil, "Fill in at least one of the two." end
      return { Script("MMK.Combat(" .. Q(v.fighting or "") .. "," .. Q(v.resting or "") .. ")") }
    end,
  },

  { header = "Fighting" },
  {
    title = "Attack (never turns off)",
    desc = "Starts your auto attack and never stops it, however often you press. Picks the nearest enemy if you have no target. Add a spell to do both.",
    fields = { { key = "spell", label = "Then cast (optional)", kind = "name", optional = true } },
    build = function(v)
      local lines = { Script("MMK.Attack()") }
      if HasText(v.spell) then table.insert(lines, CastLine(v.spell, false)) end
      return lines
    end,
  },
  {
    title = "Auto Shot / wand (stays on)",
    desc = "Starts shooting and keeps shooting: pressing again doesn't switch it off. Hunters use Auto Shot, wand users Shoot.",
    fields = { { key = "spell", label = "Shooting spell", kind = "name", default = RangedDefault } },
    build = function(v) return { Script("MMK.Auto(" .. Q(v.spell) .. ")") } end,
  },
  {
    title = "Target nearest enemy",
    desc = "Picks the nearest enemy, but only when you have no target or a dead one. Put it first, then add your attack.",
    fields = {},
    build = function(v, plain)
      if plain then
        return { Script('if not UnitExists("target") or UnitIsDead("target") then TargetNearestEnemy() end') }
      end
      return { Script("MMK.Enemy()") }
    end,
  },
  {
    title = "Stance or form, then cast",
    desc = "Not in the stance or form yet: the first press switches, the next one casts. Already in it: casts right away.",
    fields = {
      { key = "form", label = "Stance or form", kind = "name" },
      { key = "spell", label = "Then cast (optional)", kind = "name", optional = true },
    },
    build = function(v)
      local lines = { Script("MMK.Form(" .. Q(MM.BaseName(v.form)) .. ")") }
      if HasText(v.spell) then table.insert(lines, CastLine(v.spell, false)) end
      return lines
    end,
  },
  {
    title = "Leave form, then cast",
    desc = "For druids and shadow priests: the first press drops your form, the next one casts. Not in a form: casts right away.",
    fields = { { key = "spell", label = "Then cast (optional)", kind = "name", optional = true } },
    build = function(v)
      local lines = { Script("MMK.Unform()") }
      if HasText(v.spell) then table.insert(lines, CastLine(v.spell, false)) end
      return lines
    end,
  },

  { header = "Pet" },
  {
    title = "Pet attack",
    desc = "Sends your pet at your target. Add a spell to send the pet and open the fight with one press.",
    fields = { { key = "spell", label = "Then cast (optional)", kind = "name", optional = true } },
    build = function(v, plain)
      local lines = { Script("PetAttack()") }
      if HasText(v.spell) then table.insert(lines, CastLine(v.spell, plain)) end
      return lines
    end,
  },
  {
    title = "Pet come back",
    desc = "Calls your pet off and back to your side.",
    fields = {},
    build = function() return { Script("PetFollow()") } end,
  },

  { header = "Items" },
  {
    title = "Use an item",
    desc = "A potion, bandage, healthstone, trinket, anything you can right-click. Open the Items tab on the right and click it.",
    fields = { { key = "item", label = "Item", kind = "name" } },
    build = function(v) return { Script("MMK.Use(" .. Q(v.item) .. ")") } end,
  },
  {
    title = "Use trinkets",
    desc = "Fires your on-use trinkets when they're ready and stays quiet when they aren't. Add a spell to do both with one press.",
    fields = {
      { key = "which", label = "Which", kind = "choice", choices = TRINKETS },
      { key = "spell", label = "Then cast (optional)", kind = "name", optional = true },
    },
    build = function(v)
      local lines = { Script("MMK.Trinkets(" .. v.which .. ")") }
      if HasText(v.spell) then table.insert(lines, CastLine(v.spell, false)) end
      return lines
    end,
  },
  {
    title = "Equip an item",
    desc = "Puts on an item from your bags. For a weapon swap add this step twice: once for the main hand, once for the off hand or shield.",
    fields = {
      { key = "item", label = "Item", kind = "name" },
      { key = "slot", label = "Where", kind = "choice", choices = EQUIP_SLOTS },
    },
    build = function(v)
      if v.slot == "" then return { Script("MMK.Equip(" .. Q(v.item) .. ")") } end
      return { Script("MMK.Equip(" .. Q(v.item) .. "," .. v.slot .. ")") }
    end,
  },

  { header = "Chat and targeting" },
  {
    title = "Announce in chat",
    desc = "Tells your group what you're doing, once, even if you mash the button. Write %t where the target's name should go.",
    fields = {
      { key = "message", label = "Message", kind = "text", default = "Casting on %t!" },
      { key = "channel", label = "Where", kind = "choice", choices = CHANNELS },
      { key = "spell", label = "Then cast (optional)", kind = "name", optional = true },
    },
    build = function(v)
      local lines = { Script("MMK.Say(" .. Args(v.message, v.channel) .. ")") }
      if HasText(v.spell) then table.insert(lines, CastLine(v.spell, false)) end
      return lines
    end,
  },
  {
    title = "Target by name",
    desc = "Targets a player or creature by name. The start of the name is enough.",
    fields = { { key = "who", label = "Name", kind = "text" } },
    build = function(v) return { "/target " .. v.who } end,
  },
  {
    title = "Assist a player",
    desc = "Targets whatever that player is targeting. Assist your tank or main assist, then add your attack as a second step.",
    fields = { { key = "who", label = "Player's name", kind = "text" } },
    build = function(v) return { "/assist " .. v.who } end,
  },
  {
    title = "Remove a buff from me",
    desc = "Clicks a buff off you: a tank removing Blessing of Protection or Salvation, for example.",
    fields = { { key = "buff", label = "Buff's name", kind = "text" } },
    build = function(v) return { Script("MMK.Cancel(" .. Q(v.buff) .. ")") } end,
  },
}

function MM.DefaultRecipe()
  for i = 1, table.getn(MM.RECIPES) do
    if MM.RECIPES[i].id == "cast" then return MM.RECIPES[i] end
  end
end
