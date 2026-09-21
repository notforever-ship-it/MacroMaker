-- Macro Maker: the functions the generated macros call, as /script MMK.Something("Spell").
--
-- The 1.12 client has no [conditions] in /cast, so anything smarter than "cast this" is done here.
-- Every function that casts returns true when it used the key press and false when it had nothing to
-- do, and only the first cast of a key press goes out: the lines of a macro run top to bottom, so a
-- macro reads as a priority list without the game shouting "Another action is in progress".

local MM = MacroMaker
local K = MMK

local BOOK = "spell"
local GCD = 1.5                 -- cooldowns this short are the global cooldown, not the spell's own

local attacking = false         -- auto attack is swinging
local autoRepeat = false        -- Auto Shot or a wand is firing
local pressTime = -1            -- when a key press last cast something
local warned = {}
local sequences = {}
local lastSeq, lastSeqStop
local lastSaid = {}
local scanTip

-- All lines of a macro run within the same instant, so "a cast went out a moment ago" means "this
-- key press already cast". Nobody presses a key twice in a twentieth of a second.
local function Busy() return GetTime() - pressTime < 0.05 end
local function Mark() pressTime = GetTime() end

local function Warn(name)
  if warned[name] then return end
  warned[name] = true
  MM.Print("you don't have a spell or item called '" .. name .. "'. Check the spelling in your macro.")
end

local function OnCooldown(start, duration)
  return start and start > 0 and duration and duration > GCD
end

------------------------------------------------------------------------------------------------------
-- Units
------------------------------------------------------------------------------------------------------

-- The unit under the mouse. In 1.12 "mouseover" only knows about characters in the world, so unit
-- frames (Blizzard's, pfUI's and most others) are asked directly.
local function FrameUnit(f)
  if not f then return nil end
  local unit = f.unit
  if not unit and f.label and f.id then unit = f.label .. f.id end
  if type(unit) == "string" and UnitExists(unit) then return unit end
  return nil
end

local function MouseUnit()
  local f = GetMouseFocus()
  if f and f ~= WorldFrame then
    local unit = FrameUnit(f)
    if not unit and f.GetParent then unit = FrameUnit(f:GetParent()) end
    if unit then return unit end
  end
  if UnitExists("mouseover") then return "mouseover" end
  return nil
end

local function Fire(s, unit)
  if s.book ~= BOOK then
    CastSpell(s.index, s.book)
  elseif not unit or unit == "target" then
    CastSpellByName(s.cast)
  elseif unit == "player" then
    CastSpellByName(s.cast, 1)
  elseif SUPERWOW_VERSION then
    CastSpellByName(s.cast, unit)
  elseif UnitIsUnit("target", unit) then
    CastSpellByName(s.cast)
  else
    -- Plain 1.12: swap targets for the length of the cast call, then put everything back.
    local hadTarget = UnitExists("target")
    TargetUnit(unit)
    CastSpellByName(s.cast)
    if SpellIsTargeting() then SpellStopTargeting() end
    if hadTarget then TargetLastTarget() else ClearTarget() end
  end
end

------------------------------------------------------------------------------------------------------
-- Items
------------------------------------------------------------------------------------------------------

local function FindItem(name, bagsOnly)
  local want = string.lower(name)
  if not bagsOnly then
    for slot = 0, 19 do
      local worn = MM.ItemName(GetInventoryItemLink("player", slot))
      if worn and string.lower(worn) == want then return "worn", slot end
    end
  end
  for bag = 0, 4 do
    for slot = 1, GetContainerNumSlots(bag) or 0 do
      local carried = MM.ItemName(GetContainerItemLink(bag, slot))
      if carried and string.lower(carried) == want then return "bag", bag, slot end
    end
  end
  return nil
end

-- With one of these windows open, "using" a bag item sells, banks, trades or mails it instead.
local function BagClickIsDangerous()
  return (MerchantFrame and MerchantFrame:IsVisible()) or (BankFrame and BankFrame:IsVisible())
    or (TradeFrame and TradeFrame:IsVisible()) or (MailFrame and MailFrame:IsVisible())
    or (AuctionFrame and AuctionFrame:IsVisible())
end

-- Use a potion, bandage, healthstone, trinket... by name. False when it's missing or on cooldown.
function K.Use(name)
  name = MM.CleanName(name)
  if name == "" then return false end
  local where, a, b = FindItem(name)
  if not where then
    Warn(name)
    return false
  end
  if where == "worn" then
    if OnCooldown(GetInventoryItemCooldown("player", a)) then return false end
    UseInventoryItem(a)
    return true
  end
  if BagClickIsDangerous() then return false end
  if OnCooldown(GetContainerItemCooldown(a, b)) then return false end
  UseContainerItem(a, b)
  return true
end

-- Both trinkets, or just slot 13 (top) or 14 (bottom). Ones on cooldown are left alone.
function K.Trinkets(slot)
  for s = 13, 14 do
    if not slot or slot == s then
      local start = GetInventoryItemCooldown("player", s)
      if GetInventoryItemLink("player", s) and (not start or start == 0) then UseInventoryItem(s) end
    end
  end
end

-- Put on an item from the bags. slot 16 is the main hand, 17 the off hand; leave it out for anything else.
function K.Equip(name, slot)
  name = MM.CleanName(name)
  if name == "" or CursorHasItem() then return false end
  local where, bag, bagSlot = FindItem(name, true)
  if not where then return false end
  PickupContainerItem(bag, bagSlot)
  if slot then PickupInventoryItem(slot) else AutoEquipCursorItem() end
  return true
end

------------------------------------------------------------------------------------------------------
-- Casting
------------------------------------------------------------------------------------------------------

-- Cast a spell (or use an item with that name). unit is optional: "player", "mouseover", "party2"...
function K.Cast(name, unit)
  if Busy() then return true end
  name = MM.CleanName(name)
  if name == "" then return false end
  local s = MM.FindSpell(name)
  if not s then
    if FindItem(name) then return K.Use(name) end
    Warn(name)
    return false
  end
  if OnCooldown(GetSpellCooldown(s.index, s.book)) then return false end
  Fire(s, unit)
  Mark()
  return true
end

function K.Self(name)
  return K.Cast(name, "player")
end

-- On whoever is under the mouse, in the world or on a unit frame; on the target when nobody is.
function K.Over(name)
  return K.Cast(name, MouseUnit())
end

-- On a given unit, and nothing at all when that unit isn't there ("targettarget", "pet", "party1"...).
function K.Unit(name, unit)
  if not unit or not UnitExists(unit) then return false end
  return K.Cast(name, unit)
end

-- The first of these that isn't on cooldown.
function K.First(...)
  for i = 1, arg.n do
    if K.Cast(arg[i]) then return true end
  end
  return false
end

-- held is "shift", "ctrl" or "alt".
function K.Mod(held, withKey, without)
  local down
  if held == "ctrl" then down = IsControlKeyDown()
  elseif held == "alt" then down = IsAltKeyDown()
  else down = IsShiftKeyDown() end
  if down then return K.Cast(withKey) end
  if without then return K.Cast(without) end
  return false
end

-- One for friends, another for enemies. With no target the friendly spell goes on yourself.
function K.Friend(helpful, harmful)
  if UnitExists("target") and UnitCanAttack("player", "target") then
    if harmful then return K.Cast(harmful) end
    return false
  end
  if UnitExists("target") then return K.Cast(helpful) end
  return K.Cast(helpful, "player")
end

function K.Combat(inCombat, outOfCombat)
  if UnitAffectingCombat("player") then
    if inCombat and inCombat ~= "" then return K.Cast(inCombat) end
    return false
  end
  if outOfCombat and outOfCombat ~= "" then return K.Cast(outOfCombat) end
  return false
end

local function Percent(unit, mana)
  local now, max
  if mana then now, max = UnitMana(unit), UnitManaMax(unit) else now, max = UnitHealth(unit), UnitHealthMax(unit) end
  if not max or max == 0 then return 100 end
  return now / max * 100
end

-- below: when under the percentage (if it's on cooldown the other one is tried); otherwise: optional.
local function Threshold(value, percent, below, otherwise)
  if value < (tonumber(percent) or 0) and K.Cast(below) then return true end
  if otherwise and otherwise ~= "" then return K.Cast(otherwise) end
  return false
end

function K.HP(percent, below, otherwise)
  return Threshold(Percent("player"), percent, below, otherwise)
end

-- Mana, rage or energy, whichever the character uses.
function K.Mana(percent, below, otherwise)
  return Threshold(Percent("player", true), percent, below, otherwise)
end

function K.THP(percent, below, otherwise)
  if not UnitExists("target") or UnitIsDead("target") then
    if otherwise and otherwise ~= "" then return K.Cast(otherwise) end
    return false
  end
  return Threshold(Percent("target"), percent, below, otherwise)
end

------------------------------------------------------------------------------------------------------
-- Buffs and debuffs: 1.12 only gives an icon, the name has to be read off a tooltip
------------------------------------------------------------------------------------------------------

local function TipName()
  local line = getglobal("MacroMakerScanTipTextLeft1")
  return line and line:GetText()
end

local function ScanTip()
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "MacroMakerScanTip", nil, "GameTooltipTemplate")
  end
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  return scanTip
end

local function HasAura(unit, name, harmful)
  local want = string.lower(name)
  for i = 1, 40 do
    local texture
    if harmful then texture = UnitDebuff(unit, i) else texture = UnitBuff(unit, i) end
    if not texture then break end
    local tip = ScanTip()
    if harmful then tip:SetUnitDebuff(unit, i) else tip:SetUnitBuff(unit, i) end
    local found = TipName()
    tip:Hide()
    if found and string.lower(found) == want then return true end
  end
  return false
end

-- Cast on yourself only when the buff is missing. buff: its name when it differs from the spell's.
function K.Buff(name, buff)
  if Busy() then return true end
  name = MM.CleanName(name)
  if name == "" then return false end
  buff = MM.Trim(buff)
  if buff == "" then buff = MM.BaseName(name) end
  if HasAura("player", buff, false) then return false end
  return K.Cast(name, "player")
end

-- Cast on the target only when it doesn't have the debuff yet (anyone's: 1.12 can't tell whose it is).
function K.Debuff(name, debuff)
  if Busy() then return true end
  name = MM.CleanName(name)
  if name == "" or not UnitExists("target") or not UnitCanAttack("player", "target") then return false end
  debuff = MM.Trim(debuff)
  if debuff == "" then debuff = MM.BaseName(name) end
  if HasAura("target", debuff, true) then return false end
  return K.Cast(name)
end

-- Click a buff off, like Blessing of Protection on a tank.
function K.Cancel(name)
  local want = string.lower(MM.Trim(name))
  if want == "" then return false end
  for i = 0, 31 do
    local buffIndex = GetPlayerBuff(i, "HELPFUL")
    if not buffIndex or buffIndex < 0 then break end
    local tip = ScanTip()
    tip:SetPlayerBuff(buffIndex)
    local found = TipName()
    tip:Hide()
    if found and string.lower(found) == want then
      CancelPlayerBuff(buffIndex)
      return true
    end
  end
  return false
end

------------------------------------------------------------------------------------------------------
-- Stances, forms, stealth
------------------------------------------------------------------------------------------------------

-- Switch to a stance or form unless already in it. "Bear Form" also finds "Dire Bear Form".
function K.Form(name)
  if Busy() then return true end
  local want = string.lower(MM.Trim(name))
  if want == "" then return false end
  for i = 1, GetNumShapeshiftForms() do
    local _, formName, active = GetShapeshiftFormInfo(i)
    if formName and string.find(string.lower(formName), want, 1, true) then
      if active then return false end
      CastShapeshiftForm(i)
      Mark()
      return true
    end
  end
  return false
end

-- Leave whatever form is active. False when already in caster form.
function K.Unform()
  if Busy() then return true end
  for i = 1, GetNumShapeshiftForms() do
    local _, _, active = GetShapeshiftFormInfo(i)
    if active then
      CastShapeshiftForm(i)
      Mark()
      return true
    end
  end
  return false
end

------------------------------------------------------------------------------------------------------
-- Attacking: /cast Attack and /cast Auto Shot toggle, so pressing twice stops. These only ever start.
------------------------------------------------------------------------------------------------------

local function NeedsEnemy()
  return not UnitExists("target") or UnitIsDead("target")
end

-- Pick the nearest enemy when there is no target, or a dead one.
function K.Enemy()
  if NeedsEnemy() then TargetNearestEnemy() end
end

function K.Attack()
  K.Enemy()
  if not attacking and UnitExists("target") and UnitCanAttack("player", "target") then AttackTarget() end
end

-- name: "Auto Shot" for hunters, "Shoot" for wands, "Shoot Bow" and the like for everyone else.
function K.Auto(name)
  K.Enemy()
  if autoRepeat then return end
  local s = MM.FindSpell(MM.CleanName(name))
  if s then CastSpellByName(s.cast) else Warn(name) end
end

------------------------------------------------------------------------------------------------------
-- Cast sequence: the next spell of the list on each press
------------------------------------------------------------------------------------------------------

-- reset: seconds without a press before it starts over (0 = never). A press while a spell is cooling
-- down waits instead of skipping, and a cast that fails is tried again on the next press.
function K.Seq(reset, ...)
  if Busy() then return true end
  if arg.n == 0 then return false end
  local key = table.concat(arg, "|")
  local seq = sequences[key]
  if not seq then
    seq = { step = 1, pressed = 0 }
    sequences[key] = seq
  end
  local now = GetTime()
  reset = tonumber(reset) or 0
  if reset > 0 and now - seq.pressed > reset then seq.step = 1 end
  if seq.step > arg.n then seq.step = 1 end

  local name = MM.CleanName(arg[seq.step])
  local s = MM.FindSpell(name)
  if not s and not FindItem(name) then
    -- A typo, or a spell not learned yet: move past it instead of getting stuck on it.
    Warn(name)
    seq.step = seq.step + 1
    return false
  end
  if s then
    local start = GetSpellCooldown(s.index, s.book)
    if start and start > 0 then return false end
  end
  seq.pressed = now
  if K.Cast(name) then
    seq.step = seq.step + 1
    lastSeq, lastSeqStop = seq, nil
    return true
  end
  return false
end

------------------------------------------------------------------------------------------------------
-- Chat
------------------------------------------------------------------------------------------------------

-- Says it once even when the button is mashed. %t becomes the target's name.
-- channel: "SAY", "PARTY", "RAID", "YELL"; left out, it picks raid, party or say by the group you're in.
function K.Say(message, channel)
  message = MM.Trim(message)
  if message == "" then return end
  local now = GetTime()
  if lastSaid[message] and now - lastSaid[message] < 5 then return end
  lastSaid[message] = now
  local text = string.gsub(message, "%%t", UnitName("target") or "my target")
  if not channel or channel == "" then
    if GetNumRaidMembers() > 0 then channel = "RAID"
    elseif GetNumPartyMembers() > 0 then channel = "PARTY"
    else channel = "SAY" end
  end
  SendChatMessage(text, channel)
end

------------------------------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTER_COMBAT")
events:RegisterEvent("PLAYER_LEAVE_COMBAT")
events:RegisterEvent("START_AUTOREPEAT_SPELL")
events:RegisterEvent("STOP_AUTOREPEAT_SPELL")
events:RegisterEvent("SPELLCAST_STOP")
events:RegisterEvent("SPELLCAST_FAILED")
events:RegisterEvent("SPELLCAST_INTERRUPTED")
events:SetScript("OnEvent", function()
  if event == "PLAYER_ENTER_COMBAT" then
    attacking = true
  elseif event == "PLAYER_LEAVE_COMBAT" then
    attacking = false
  elseif event == "START_AUTOREPEAT_SPELL" then
    autoRepeat = true
  elseif event == "STOP_AUTOREPEAT_SPELL" then
    autoRepeat = false
  elseif event == "SPELLCAST_STOP" then
    if lastSeq and not lastSeqStop then lastSeqStop = GetTime() end
  elseif lastSeq then
    -- Failed or interrupted: give the sequence its step back, unless that cast finished a while ago
    -- and this failure belongs to some other button.
    if not lastSeqStop or GetTime() - lastSeqStop < 0.3 then
      lastSeq.step = lastSeq.step - 1
      if lastSeq.step < 1 then lastSeq.step = 1 end
    end
    lastSeq = nil
  end
end)
