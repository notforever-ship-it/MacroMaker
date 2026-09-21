-- Macro Maker: saved settings, the spellbook / bag / macro lists the window picks from, and /mm.

MacroMaker = {}
local MM = MacroMaker
MM.VERSION = "1.0.0"

-- The functions macros call. The name is short on purpose: a macro only holds 255 characters.
MMK = {}

local GOLD, GREY, RED, END = "|cffffd100", "|cff9d9d9d", "|cffff4040", "|r"
local BOOK, PETBOOK = "spell", "pet"

local DEFAULTS = {
  minimapAngle = 200,
  minimapHidden = false,
  perCharacter = true,     -- new macros go in the character's own macro tab
  allRanks = false,        -- the spell list shows every rank instead of only the highest
}

MM.spells = {}             -- [lowercase "name" or "name(rank n)"] = { cast, name, index, book, texture }
MM.spellList = {}          -- spellbook order, with a header row for each tab

function MM.Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Macro Maker:|r " .. msg)
  end
end

function MM.Trim(s)
  if type(s) ~= "string" then return "" end
  s = string.gsub(s, "^%s+", "")
  s = string.gsub(s, "%s+$", "")
  return s
end

-- "Flash Heal (Rank 2)" the way the game wants it: no space before the bracket.
function MM.CleanName(s)
  s = MM.Trim(s)
  s = string.gsub(s, "%s+%(", "(")
  return s
end

-- "Flash Heal(Rank 2)" -> "Flash Heal"
function MM.BaseName(s)
  s = string.gsub(s or "", "%s*%(.*%)$", "")
  return s
end

------------------------------------------------------------------------------------------------------
-- Spellbook
------------------------------------------------------------------------------------------------------

local function IsPassive(index, book, rank)
  if rank == "Passive" then return true end
  if IsSpellPassive and IsSpellPassive(index, book) then return true end
  return false
end

local function AddSpell(list, index, book)
  local name, rank = GetSpellName(index, book)
  if not name then return false end
  if IsPassive(index, book, rank) then return true end
  local texture = GetSpellTexture(index, book)
  local lower = string.lower(name)
  -- Ranks are listed lowest first, so the plain name ends up pointing at the highest one.
  MM.spells[lower] = { cast = name, name = name, index = index, book = book, texture = texture }
  local entry = { name = name, cast = name, index = index, book = book, texture = texture }
  if rank and string.find(rank, "^Rank %d+") then
    local ranked = name .. "(" .. rank .. ")"
    MM.spells[string.lower(ranked)] = { cast = ranked, name = name, index = index, book = book, texture = texture }
    entry.rank = rank
    entry.cast = ranked
  end
  table.insert(list, entry)
  return true
end

function MM.ScanSpells()
  MM.spells = {}
  local list = {}
  local tabs = (GetNumSpellTabs and GetNumSpellTabs()) or 0
  for t = 1, tabs do
    local tabName, _, offset, count = GetSpellTabInfo(t)
    table.insert(list, { header = tabName or ("Tab " .. t) })
    for i = (offset or 0) + 1, (offset or 0) + (count or 0) do
      AddSpell(list, i, BOOK)
    end
  end
  local i = 1
  local petHeader = false
  while i < 200 do
    if not GetSpellName(i, PETBOOK) then break end
    if not petHeader then
      table.insert(list, { header = "Pet" })
      petHeader = true
    end
    AddSpell(list, i, PETBOOK)
    i = i + 1
  end
  MM.spellList = list
  MM.lastScan = GetTime()
  MM.dirty = false
end

-- The spellbook entry for a name as typed in a macro, or nil. Learning a spell shifts the spellbook's
-- numbering, so a changed book is read again first; a miss rereads it too, once a second at most.
function MM.FindSpell(name)
  local key = string.lower(name or "")
  if MM.dirty then MM.ScanSpells() end
  local s = MM.spells[key]
  if not s and (not MM.lastScan or GetTime() - MM.lastScan > 1) then
    MM.ScanSpells()
    s = MM.spells[key]
  end
  return s
end

-- What the spell list shows: every rank, or only the highest of each spell.
function MM.SpellRows(allRanks, filter)
  MM.ScanSpells()
  local rows, pendingHeader = {}, nil
  local list = MM.spellList
  local n = table.getn(list)
  for i = 1, n do
    local e = list[i]
    if e.header then
      pendingHeader = e
    else
      local nextEntry = list[i + 1]
      local isHighest = not (nextEntry and nextEntry.name == e.name and nextEntry.book == e.book)
      if (allRanks or isHighest) and (not filter or string.find(string.lower(e.name), filter, 1, true)) then
        if pendingHeader then
          table.insert(rows, pendingHeader)
          pendingHeader = nil
        end
        local label, value = e.name, e.name
        if allRanks and e.rank then
          label = e.name .. GREY .. " (" .. e.rank .. ")" .. END
          value = e.cast
        end
        table.insert(rows, { label = label, value = value, name = e.name, texture = e.texture,
          spellIndex = e.index, book = e.book })
      end
    end
  end
  return rows
end

------------------------------------------------------------------------------------------------------
-- Bags and worn items
------------------------------------------------------------------------------------------------------

function MM.ItemName(link)
  local _, _, name = string.find(link or "", "%[(.-)%]")
  return name
end

function MM.ItemRows(filter)
  local rows, seen = {}, {}
  local worn, carried = {}, {}
  for slot = 0, 19 do
    local name = MM.ItemName(GetInventoryItemLink("player", slot))
    if name and not seen[name] and (not filter or string.find(string.lower(name), filter, 1, true)) then
      seen[name] = true
      table.insert(worn, { label = name, value = name, name = name,
        texture = GetInventoryItemTexture("player", slot), invSlot = slot })
    end
  end
  for bag = 0, 4 do
    for slot = 1, GetContainerNumSlots(bag) or 0 do
      local name = MM.ItemName(GetContainerItemLink(bag, slot))
      if name and not seen[name] and (not filter or string.find(string.lower(name), filter, 1, true)) then
        seen[name] = true
        local texture = GetContainerItemInfo(bag, slot)
        table.insert(carried, { label = name, value = name, name = name, texture = texture, bag = bag, bagSlot = slot })
      end
    end
  end
  table.sort(carried, function(a, b) return a.name < b.name end)
  if table.getn(carried) > 0 then
    table.insert(rows, { header = "In my bags" })
    for i = 1, table.getn(carried) do table.insert(rows, carried[i]) end
  end
  if table.getn(worn) > 0 then
    table.insert(rows, { header = "Wearing" })
    for i = 1, table.getn(worn) do table.insert(rows, worn[i]) end
  end
  return rows
end

------------------------------------------------------------------------------------------------------
-- Macros
------------------------------------------------------------------------------------------------------

MM.MAX_ACCOUNT, MM.MAX_CHARACTER = 18, 18

-- Account macros sit in slots 1-18, the character's own in 19-36.
function MM.MacroRows(filter)
  local rows = {}
  local numAccount, numCharacter = GetNumMacros()
  local function Add(first, count, header)
    local added = false
    for i = first, first + (count or 0) - 1 do
      local name, texture, body = GetMacroInfo(i)
      if name and (not filter or string.find(string.lower(name), filter, 1, true)) then
        if not added then
          table.insert(rows, { header = header })
          added = true
        end
        table.insert(rows, { label = name, value = name, name = name, texture = texture, macroIndex = i, body = body })
      end
    end
  end
  Add(MM.MAX_ACCOUNT + 1, numCharacter, "This character")
  Add(1, numAccount, "All characters")
  return rows
end

function MM.FindMacro(name)
  if not name or name == "" then return nil end
  local numAccount, numCharacter = GetNumMacros()
  for i = MM.MAX_ACCOUNT + 1, MM.MAX_ACCOUNT + (numCharacter or 0) do
    if GetMacroInfo(i) == name then return i end
  end
  for i = 1, numAccount or 0 do
    if GetMacroInfo(i) == name then return i end
  end
  return nil
end

-- The stock 1.12 client saves a macro's icon as a number from its own icon list. Turtle WoW's
-- client (and servers built on it) takes the icon's file name instead, which is how any spell icon
-- can be used there; its macro window keeps those names in MACRO_ICON_FILENAMES.
local iconIndex
local function IconIndex(texture)
  if not texture then return 1 end
  if not iconIndex then
    iconIndex = {}
    for i = 1, GetNumMacroIcons() do
      local path = GetMacroIconInfo(i)
      if path then iconIndex[string.lower(path)] = i end
    end
  end
  return iconIndex[string.lower(texture)] or 1
end

local function IconArgument(texture)
  if MacroFrame_LoadUI then MacroFrame_LoadUI() end
  if not MACRO_ICON_FILENAMES then return IconIndex(texture) end
  local file = string.upper(texture or "")
  file = string.gsub(file, "^INTERFACE\\ICONS\\", "")
  if file == "" or string.find(file, "\\", 1, true) then file = "INV_MISC_QUESTIONMARK" end
  return file
end

-- Creates the macro, or rewrites the one that already has this name (it keeps its place on the bars).
-- Returns the macro's slot and whether it was an update, or nil and the reason.
function MM.SaveMacro(name, texture, body, perCharacter)
  if MacroFrame and MacroFrame:IsVisible() then HideUIPanel(MacroFrame) end
  local icon = IconArgument(texture)
  local index = MM.FindMacro(name)
  if index then
    EditMacro(index, name, icon, body)
    return index, true
  end
  local numAccount, numCharacter = GetNumMacros()
  if perCharacter and (numCharacter or 0) >= MM.MAX_CHARACTER then
    return nil, "this character's 18 macro slots are full. Untick 'Only for this character' or delete one in the game's macro window."
  end
  if not perCharacter and (numAccount or 0) >= MM.MAX_ACCOUNT then
    return nil, "the 18 shared macro slots are full. Tick 'Only for this character' or delete one in the game's macro window."
  end
  index = CreateMacro(name, icon, body, nil, perCharacter and 1 or nil)
  if type(index) ~= "number" or index == 0 then index = MM.FindMacro(name) end
  if not index then return nil, "the game refused to create the macro." end
  return index, false
end

------------------------------------------------------------------------------------------------------
-- Settings, events, /mm
------------------------------------------------------------------------------------------------------

local function InitDB()
  if type(MacroMakerDB) ~= "table" then MacroMakerDB = {} end
  for k, v in pairs(DEFAULTS) do
    if MacroMakerDB[k] == nil then MacroMakerDB[k] = v end
  end
  MM.db = MacroMakerDB
end

local function Slash(msg)
  msg = string.lower(MM.Trim(msg))
  if msg == "minimap" then
    MM.db.minimapHidden = not MM.db.minimapHidden
    if MM.UpdateMinimapButton then MM.UpdateMinimapButton() end
    MM.Print("minimap button " .. (MM.db.minimapHidden and "hidden" or "shown") .. ".")
  elseif msg == "help" or msg == "?" then
    MM.Print(GOLD .. "/mm" .. END .. " opens the window. " .. GOLD .. "/mm minimap" .. END .. " shows or hides the minimap button.")
    if MM.ShowHelp then MM.ShowHelp() end
  else
    if MM.ToggleWindow then MM.ToggleWindow() end
  end
end

SLASH_MACROMAKER1 = "/mm"
SLASH_MACROMAKER2 = "/macromaker"
SlashCmdList["MACROMAKER"] = Slash

local events = CreateFrame("Frame")
events:RegisterEvent("VARIABLES_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("LEARNED_SPELL_IN_TAB")
events:RegisterEvent("UNIT_PET")
events:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then
    InitDB()
  elseif event == "PLAYER_LOGIN" then
    if not MM.db then InitDB() end
    MM.ScanSpells()
    if MM.InitMinimapButton then MM.InitMinimapButton() end
    MM.Print("type " .. GOLD .. "/mm" .. END .. " to build a macro.")
  elseif event == "UNIT_PET" then
    if arg1 == "player" then MM.dirty = true end
  else
    MM.dirty = true
    if MM.SpellsChanged then MM.SpellsChanged() end
  end
end)

MM.RED, MM.GOLD, MM.GREY, MM.END = RED, GOLD, GREY, END
