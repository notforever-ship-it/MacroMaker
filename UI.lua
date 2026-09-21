-- Macro Maker: the /mm window. Left: what the button should do. Middle: the blanks. Right: your
-- spells, items and macros to click instead of typing. Bottom: the macro being built.

local MM = MacroMaker

local GOLD, GREY, WHITE, RED, GREEN, END = "|cffffd100", "|cff9d9d9d", "|cffffffff", "|cffff4040", "|cff40ff40", "|r"
local WIDTH, HEIGHT = 724, 560
local MAX_BODY, MAX_NAME = 255, 16
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local LEFT_X, MID_X, RIGHT_X = 20, 256, 486
local LEFT_W, MID_W, RIGHT_W = 200, 216, 192
local RECIPE_ROWS, RECIPE_ROW_H = 15, 18
local PICK_ROWS, PICK_ROW_H = 11, 20
local MAX_FIELDS = 3

local frame
local recipeScroll, pickScroll
local recipeRows, pickRows, tabButtons, fieldWidgets = {}, {}, {}, {}
local descText, stepText, searchBox, ranksCheck
local nameBox, iconButton, perCharCheck, macroEdit, countText, noteText, statusText, createButton

local selected                 -- the recipe being filled in
local activeField              -- which blank the next clicked spell goes into
local choiceIndex = {}         -- [field number] = position in its choices
local pickTab = "spells"
local pickData = {}
local undo = {}
local iconTexture, iconManual = nil, false
local nameTyped = false        -- the player typed a name, so picks stop suggesting one
local quiet = false            -- the window itself is changing a box; ignore its OnTextChanged

local TABS = {
  { key = "spells", label = "Spells", hint = "Click a spell to fill in the blank. Right-click to use its icon for the macro." },
  { key = "items", label = "Items", hint = "What you carry and wear. Click one to fill in the blank. Right-click to use its icon." },
  { key = "macros", label = "Macros", hint = "The macros you already have. Click one to load it, change it, and save it again." },
}

------------------------------------------------------------------------------------------------------
-- Small pieces
------------------------------------------------------------------------------------------------------

-- The 1.12 dialog background art is partly see-through; a solid layer underneath keeps text readable.
local function Opaque(f)
  local solid = f:CreateTexture(nil, "BACKGROUND")
  solid:SetTexture(0.05, 0.05, 0.07, 1)
  solid:SetPoint("TOPLEFT", f, "TOPLEFT", 11, -11)
  solid:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -11, 11)
end

local function Explain(widget, title, text)
  widget:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    GameTooltip:AddLine(text, 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Button(name, parent, width, text)
  local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
  b:SetWidth(width)
  b:SetHeight(22)
  b:SetText(text)
  return b
end

local function Label(parent, font, x, y, width, text)
  local s = parent:CreateFontString(nil, "ARTWORK", font)
  s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  if width then
    s:SetWidth(width)
    s:SetJustifyH("LEFT")
  end
  if text then s:SetText(text) end
  return s
end

local function InputBox(name, parent, x, y, width)
  local box = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
  box:SetWidth(width)
  box:SetHeight(20)
  box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  box:SetAutoFocus(false)
  box:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  box:SetScript("OnEnterPressed", function() this:ClearFocus() end)
  return box
end

local function SetBox(box, text)
  quiet = true
  box:SetText(text or "")
  quiet = false
end

local function Status(msg, colour)
  if statusText then statusText:SetText((colour or WHITE) .. (msg or "") .. END) end
end

-- A list row: optional icon, one line of text, a highlight under the mouse.
local function ListRow(name, parent, x, y, width, height, scroll)
  local b = CreateFrame("Button", name, parent)
  b:SetWidth(width)
  b:SetHeight(height)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:SetFrameLevel(scroll:GetFrameLevel() + 2)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetWidth(height - 4)
  b.icon:SetHeight(height - 4)
  b.icon:SetPoint("LEFT", b, "LEFT", 2, 0)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  b.text:SetJustifyH("LEFT")
  b.text:SetHeight(12)

  b.chosen = b:CreateTexture(nil, "BACKGROUND")
  b.chosen:SetTexture(1, 0.82, 0, 0.22)
  b.chosen:SetAllPoints(b)
  b.chosen:Hide()

  local glow = b:CreateTexture(nil, "HIGHLIGHT")
  glow:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  glow:SetBlendMode("ADD")
  glow:SetAllPoints(b)

  -- The rows cover the scroll frame, so they pass the mouse wheel on to its scroll bar.
  b:EnableMouseWheel(true)
  b:SetScript("OnMouseWheel", function()
    local bar = getglobal(scroll:GetName() .. "ScrollBar")
    if bar and scroll:IsShown() then bar:SetValue(bar:GetValue() - arg1 * height * 3) end
  end)
  return b
end

local function RowText(row, text, withIcon)
  row.text:ClearAllPoints()
  if withIcon then
    row.text:SetPoint("LEFT", row, "LEFT", row:GetHeight() + 2, 0)
    row.text:SetWidth(row:GetWidth() - row:GetHeight() - 4)
  else
    row.text:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.text:SetWidth(row:GetWidth() - 4)
  end
  row.text:SetText(text)
end

local function ScrollToTop(scroll)
  local bar = getglobal(scroll:GetName() .. "ScrollBar")
  if bar then bar:SetValue(0) end
  scroll.offset = 0
end

------------------------------------------------------------------------------------------------------
-- The blanks of the chosen recipe
------------------------------------------------------------------------------------------------------

local function Pickable(def)
  return def and (def.kind == "name" or def.kind == "list")
end

local function FieldDefault(def)
  local d = def.default
  if type(d) == "function" then d = d() end
  if d == nil then return "" end
  return tostring(d)
end

local function SplitNames(text)
  local names = {}
  for part in string.gfind(text or "", "[^,]+") do
    local name = MM.CleanName(part)
    if name ~= "" then table.insert(names, name) end
  end
  return names
end

-- The values of the blanks keyed by field, or nil and the label of the first required one left empty.
local function GetValues()
  local v = {}
  for i = 1, table.getn(selected.fields) do
    local def, w = selected.fields[i], fieldWidgets[i]
    local value
    if def.kind == "choice" then
      value = def.choices[choiceIndex[i] or 1].value
    elseif def.kind == "list" then
      value = SplitNames(w.box:GetText())
      if table.getn(value) == 0 and not def.optional then return nil, def.label end
    elseif def.kind == "number" then
      value = tonumber(MM.Trim(w.box:GetText())) or tonumber(FieldDefault(def)) or 0
    elseif def.kind == "name" then
      value = MM.CleanName(w.box:GetText())
    else
      value = MM.Trim(w.box:GetText())
    end
    if value == "" and not def.optional and def.kind ~= "choice" then return nil, def.label end
    v[def.key] = value
  end
  return v
end

local function BuildStep()
  if not selected then return nil, "Pick what the button should do first." end
  local v, missing = GetValues()
  if not v then return nil, "Fill in: " .. missing end
  local plain = not string.find(macroEdit:GetText() or "", "MMK%.")
  return selected.build(v, plain)
end

local function UpdateStep()
  if not stepText or not selected then return end
  local lines, problem = BuildStep()
  if lines then
    stepText:SetText(GREY .. "This step adds:" .. END .. "\n" .. table.concat(lines, "\n"))
  else
    stepText:SetText(GREY .. (problem or "") .. END)
  end
end

local function UpdateFieldLabels()
  if not selected then return end
  for i = 1, MAX_FIELDS do
    local def, w = selected.fields[i], fieldWidgets[i]
    if def then
      if i == activeField and Pickable(def) then
        w.label:SetText(GOLD .. def.label .. END .. GREY .. "  - click one on the right" .. END)
      else
        w.label:SetText(WHITE .. def.label .. END)
      end
    end
  end
end

local function SetActive(i)
  activeField = i
  UpdateFieldLabels()
end

local function FirstPickable(recipe, after, onlyEmpty)
  for i = (after or 0) + 1, table.getn(recipe.fields) do
    if Pickable(recipe.fields[i]) then
      if not onlyEmpty or MM.Trim(fieldWidgets[i].box:GetText()) == "" then return i end
    end
  end
  return nil
end

local function ResetFields()
  for i = 1, MAX_FIELDS do
    local def, w = selected.fields[i], fieldWidgets[i]
    if def then
      w.label:Show()
      if def.kind == "choice" then
        choiceIndex[i] = 1
        w.box:Hide()
        w.cycle:SetText(def.choices[1].label)
        w.cycle:Show()
      else
        w.cycle:Hide()
        SetBox(w.box, FieldDefault(def))
        w.box:Show()
      end
    else
      w.label:Hide()
      w.box:Hide()
      w.cycle:Hide()
    end
  end
  SetActive(FirstPickable(selected))
  UpdateStep()
end

local UpdateRecipes

local function SelectRecipe(recipe)
  selected = recipe
  descText:SetText(recipe.desc or "")
  ResetFields()
  UpdateRecipes()
end

------------------------------------------------------------------------------------------------------
-- The macro being built
------------------------------------------------------------------------------------------------------

local function SetIcon(texture, manual)
  iconTexture = texture
  if manual then iconManual = true end
  iconButton.icon:SetTexture(texture or QUESTION_MARK)
end

local function SetBody(text)
  table.insert(undo, macroEdit:GetText() or "")
  if table.getn(undo) > 30 then table.remove(undo, 1) end
  macroEdit:SetText(text)
end

local function UpdateCreateButton()
  if not createButton then return end
  if MM.FindMacro(MM.Trim(nameBox:GetText())) then
    createButton:SetText("Update macro")
  else
    createButton:SetText("Create macro")
  end
end

local function BodyChanged()
  if not countText or not noteText then return end
  local text = macroEdit:GetText() or ""
  local length = string.len(text)
  if length > MAX_BODY then
    countText:SetText(RED .. length .. " / " .. MAX_BODY .. " characters: too long" .. END)
  else
    countText:SetText(GREY .. length .. " / " .. MAX_BODY .. " characters" .. END)
  end
  if text == "" then
    noteText:SetText(GREY .. "Steps you add show up here. You can also type in the box." .. END)
  elseif string.find(text, "MMK%.") then
    noteText:SetText(GOLD .. "Uses Macro Maker's helpers:" .. END .. WHITE .. " keep this addon turned on or the macro stops working." .. END)
  else
    noteText:SetText(GREEN .. "Plain macro:" .. END .. WHITE .. " works even without this addon." .. END)
  end
  UpdateStep()
end

local function AddStep()
  local lines, problem = BuildStep()
  if not lines then
    Status(problem, RED)
    return
  end
  local text = macroEdit:GetText() or ""
  if text ~= "" and string.sub(text, -1) ~= "\n" then text = text .. "\n" end
  text = text .. table.concat(lines, "\n")
  SetBody(text)
  ResetFields()
  if string.len(text) > MAX_BODY then
    Status("That makes the macro longer than " .. MAX_BODY .. " characters. Press Undo, or shorten it.", RED)
  else
    Status("Added. Add another step, or give it a name and press Create macro.", GREEN)
  end
end

local function Undo()
  local n = table.getn(undo)
  if n == 0 then
    Status("Nothing to undo.", GREY)
    return
  end
  local text = table.remove(undo, n)
  macroEdit:SetText(text)
  Status("Undone.", GREY)
end

local function ClearAll()
  SetBody("")
  SetBox(nameBox, "")
  nameTyped = false
  iconManual = false
  SetIcon(nil)
  UpdateCreateButton()
  Status("Cleared. Undo brings the text back.", GREY)
end

local RefreshPicks

local function CreateIt()
  local body = macroEdit:GetText() or ""
  if MM.Trim(body) == "" then
    Status("The macro is empty: fill in the blanks and press Add to macro first.", RED)
    return
  end
  if string.len(body) > MAX_BODY then
    Status("Too long: a macro holds " .. MAX_BODY .. " characters. Remove a step.", RED)
    return
  end
  local name = MM.Trim(nameBox:GetText())
  if name == "" then
    Status("Give the macro a name first.", RED)
    nameBox:SetFocus()
    return
  end
  local index, updated = MM.SaveMacro(name, iconTexture, body, perCharCheck:GetChecked())
  if not index then
    Status("Couldn't save: " .. (updated or "unknown reason"), RED)
    return
  end
  if updated then
    Status("'" .. name .. "' updated. It's still wherever you put it on your bars.", GREEN)
  else
    PickupMacro(index)
    Status("'" .. name .. "' created and on your cursor: drop it on an action bar. (It's also in the game's macro window.)", GREEN)
    MM.Print("'" .. name .. "' created. Drop it on an action bar.")
  end
  UpdateCreateButton()
  if pickTab == "macros" then RefreshPicks() end
end

local function LoadMacro(entry)
  local name, texture, body = GetMacroInfo(entry.macroIndex)
  if not name then return end
  SetBody(body or "")
  SetBox(nameBox, name)
  nameTyped = true
  SetIcon(texture, true)
  perCharCheck:SetChecked((entry.macroIndex > MM.MAX_ACCOUNT) and 1 or nil)
  UpdateCreateButton()
  Status("Loaded '" .. name .. "'. Change it and press Update macro, or rename it to save a copy.", GREEN)
end

------------------------------------------------------------------------------------------------------
-- Lists
------------------------------------------------------------------------------------------------------

UpdateRecipes = function()
  if not frame then return end
  local total = table.getn(MM.RECIPES)
  FauxScrollFrame_Update(recipeScroll, total, RECIPE_ROWS, RECIPE_ROW_H)
  local offset = FauxScrollFrame_GetOffset(recipeScroll)
  for i = 1, RECIPE_ROWS do
    local row, recipe = recipeRows[i], MM.RECIPES[i + offset]
    if recipe then
      row.recipe = recipe
      row.icon:Hide()
      if recipe.header then
        RowText(row, GOLD .. recipe.header .. END, false)
        row.chosen:Hide()
      else
        RowText(row, "   " .. recipe.title, false)
        if recipe == selected then row.chosen:Show() else row.chosen:Hide() end
      end
      row:Show()
    else
      row:Hide()
    end
  end
end

local function UpdatePicks()
  if not frame then return end
  local total = table.getn(pickData)
  FauxScrollFrame_Update(pickScroll, total, PICK_ROWS, PICK_ROW_H)
  local offset = FauxScrollFrame_GetOffset(pickScroll)
  for i = 1, PICK_ROWS do
    local row, entry = pickRows[i], pickData[i + offset]
    if entry then
      row.entry = entry
      if entry.header then
        row.icon:Hide()
        RowText(row, GOLD .. entry.header .. END, false)
      else
        row.icon:SetTexture(entry.texture or QUESTION_MARK)
        row.icon:Show()
        RowText(row, entry.label, true)
      end
      row:Show()
    else
      row.entry = nil
      row:Hide()
    end
  end
end

RefreshPicks = function()
  if not frame or not frame:IsShown() then return end
  local filter = string.lower(MM.Trim(searchBox:GetText()))
  if filter == "" then filter = nil end
  if pickTab == "spells" then
    pickData = MM.SpellRows(ranksCheck:GetChecked(), filter)
  elseif pickTab == "items" then
    pickData = MM.ItemRows(filter)
  else
    pickData = MM.MacroRows(filter)
  end
  UpdatePicks()
end

local function SelectTab(key)
  pickTab = key
  for i = 1, table.getn(TABS) do
    if TABS[i].key == key then tabButtons[i]:LockHighlight() else tabButtons[i]:UnlockHighlight() end
  end
  if key == "spells" then ranksCheck:Show() else ranksCheck:Hide() end
  ScrollToTop(pickScroll)
  RefreshPicks()
end

-- A spell or item was clicked: it goes into the blank that's waiting for one.
local function PickEntry(entry)
  local index = activeField
  if not (selected and index and Pickable(selected.fields[index])) then
    index = selected and FirstPickable(selected)
  end
  if not index then
    -- This recipe has no blank for it; "Cast a spell" is what a click on a spell most likely means.
    SelectRecipe(MM.DefaultRecipe())
    index = FirstPickable(selected)
  end
  local def, box = selected.fields[index], fieldWidgets[index].box
  if def.kind == "list" then
    local have = MM.Trim(box:GetText())
    if have ~= "" then SetBox(box, have .. ", " .. entry.value) else SetBox(box, entry.value) end
  else
    SetBox(box, entry.value)
  end

  if not iconManual and not iconTexture then SetIcon(entry.texture) end
  if not nameTyped and MM.Trim(nameBox:GetText()) == "" then
    SetBox(nameBox, string.sub(entry.name, 1, MAX_NAME))
    UpdateCreateButton()
  end

  if def.kind == "name" then
    SetActive(FirstPickable(selected, index, true) or index)
  else
    SetActive(index)
  end
  UpdateStep()
  Status("")
end

local function PickTooltip(row)
  local entry = row.entry
  if not entry or entry.header then return end
  GameTooltip:SetOwner(row, "ANCHOR_LEFT")
  if entry.spellIndex then
    GameTooltip:SetSpell(entry.spellIndex, entry.book)
  elseif entry.bag then
    GameTooltip:SetBagItem(entry.bag, entry.bagSlot)
  elseif entry.invSlot then
    GameTooltip:SetInventoryItem("player", entry.invSlot)
  else
    GameTooltip:SetText(entry.name)
    GameTooltip:AddLine(entry.body or "", 1, 1, 1, 1)
  end
  if entry.macroIndex then
    GameTooltip:AddLine("Click: load it into the box below", 0.4, 1, 0.4)
  else
    GameTooltip:AddLine("Click: fill in the blank", 0.4, 1, 0.4)
    GameTooltip:AddLine("Right-click: use this icon for the macro", 0.4, 1, 0.4)
  end
  GameTooltip:Show()
end

------------------------------------------------------------------------------------------------------
-- Building the window
------------------------------------------------------------------------------------------------------

local function BuildRecipeColumn(f)
  Label(f, "GameFontNormal", LEFT_X, -58, LEFT_W + 20, "1. What should the button do?")

  recipeScroll = CreateFrame("ScrollFrame", "MacroMakerRecipeScroll", f, "FauxScrollFrameTemplate")
  recipeScroll:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT_X, -78)
  recipeScroll:SetWidth(LEFT_W)
  recipeScroll:SetHeight(RECIPE_ROWS * RECIPE_ROW_H)
  recipeScroll:SetScript("OnVerticalScroll", function()
    FauxScrollFrame_OnVerticalScroll(RECIPE_ROW_H, UpdateRecipes)
  end)

  for i = 1, RECIPE_ROWS do
    local row = ListRow("MacroMakerRecipe" .. i, f, LEFT_X, -78 - (i - 1) * RECIPE_ROW_H, LEFT_W, RECIPE_ROW_H, recipeScroll)
    row:SetScript("OnClick", function()
      if this.recipe and not this.recipe.header then
        SelectRecipe(this.recipe)
        Status("")
      end
    end)
    recipeRows[i] = row
  end
end

local function BuildFieldColumn(f)
  Label(f, "GameFontNormal", MID_X, -58, MID_W, "2. Fill in the blanks")

  descText = Label(f, "GameFontHighlightSmall", MID_X, -78, MID_W)
  descText:SetHeight(54)
  descText:SetJustifyV("TOP")

  for i = 1, MAX_FIELDS do
    local y = -138 - (i - 1) * 40
    local w = {}
    w.label = Label(f, "GameFontHighlightSmall", MID_X, y, MID_W)
    w.label:SetHeight(12)

    w.box = InputBox("MacroMakerField" .. i, f, MID_X + 6, y - 14, MID_W - 8)
    w.box.fieldIndex = i
    w.box:SetScript("OnEditFocusGained", function()
      this:HighlightText()
      if selected and Pickable(selected.fields[this.fieldIndex]) then SetActive(this.fieldIndex) end
    end)
    w.box:SetScript("OnEditFocusLost", function() this:HighlightText(0, 0) end)
    w.box:SetScript("OnTextChanged", function()
      if not quiet then UpdateStep() end
    end)
    w.box:SetScript("OnEnterPressed", function()
      this:ClearFocus()
      AddStep()
    end)
    w.box:SetScript("OnTabPressed", function()
      local nextWidget = fieldWidgets[this.fieldIndex + 1]
      if nextWidget and nextWidget.box:IsShown() then nextWidget.box:SetFocus() end
    end)

    w.cycle = Button("MacroMakerChoice" .. i, f, MID_W, "")
    w.cycle:SetPoint("TOPLEFT", f, "TOPLEFT", MID_X, y - 13)
    w.cycle.fieldIndex = i
    w.cycle:SetScript("OnClick", function()
      local def = selected and selected.fields[this.fieldIndex]
      if not def or not def.choices then return end
      local n = (choiceIndex[this.fieldIndex] or 1) + 1
      if n > table.getn(def.choices) then n = 1 end
      choiceIndex[this.fieldIndex] = n
      this:SetText(def.choices[n].label)
      UpdateStep()
    end)
    Explain(w.cycle, "Click to change", "Each click moves to the next choice.")
    fieldWidgets[i] = w
  end

  stepText = Label(f, "GameFontHighlightSmall", MID_X, -260, MID_W)
  stepText:SetHeight(66)
  stepText:SetJustifyV("TOP")

  local add = Button("MacroMakerAdd", f, 138, "Add to macro")
  add:SetPoint("TOPLEFT", f, "TOPLEFT", MID_X, -330)
  add:SetScript("OnClick", AddStep)
  Explain(add, "Add to macro", "Writes this step into the macro at the bottom. A macro can have several steps: they run top to bottom each time you press the button.")

  local undoButton = Button("MacroMakerUndo", f, 72, "Undo")
  undoButton:SetPoint("LEFT", add, "RIGHT", 6, 0)
  undoButton:SetScript("OnClick", Undo)
  Explain(undoButton, "Undo", "Takes back the last change to the macro text.")
end

local function BuildPickColumn(f)
  Label(f, "GameFontNormal", RIGHT_X, -58, RIGHT_W + 24, "Click instead of typing")

  for i = 1, table.getn(TABS) do
    local tab = Button("MacroMakerTab" .. i, f, 70, TABS[i].label)
    tab:SetHeight(20)
    tab:SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_X + (i - 1) * 72, -76)
    tab.key = TABS[i].key
    tab:SetScript("OnClick", function() SelectTab(this.key) end)
    Explain(tab, TABS[i].label, TABS[i].hint)
    tabButtons[i] = tab
  end

  Label(f, "GameFontHighlightSmall", RIGHT_X, -106, nil, GREY .. "Find" .. END)
  searchBox = InputBox("MacroMakerSearch", f, RIGHT_X + 34, -101, 84)
  searchBox:SetScript("OnTextChanged", function()
    if quiet then return end
    ScrollToTop(pickScroll)
    RefreshPicks()
  end)

  ranksCheck = CreateFrame("CheckButton", "MacroMakerRanks", f, "UICheckButtonTemplate")
  ranksCheck:SetWidth(22)
  ranksCheck:SetHeight(22)
  ranksCheck:SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_X + 126, -100)
  local ranksLabel = getglobal("MacroMakerRanksText")
  if ranksLabel then ranksLabel:SetText("All ranks") end
  ranksCheck:SetScript("OnClick", function()
    MM.db.allRanks = this:GetChecked() and true or false
    ScrollToTop(pickScroll)
    RefreshPicks()
  end)
  Explain(ranksCheck, "All ranks", "Off: the macro always casts your highest rank, and keeps doing so as you level.\n\nOn: pick one exact rank, like a cheap low-rank heal.")

  pickScroll = CreateFrame("ScrollFrame", "MacroMakerPickScroll", f, "FauxScrollFrameTemplate")
  pickScroll:SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_X, -128)
  pickScroll:SetWidth(RIGHT_W)
  pickScroll:SetHeight(PICK_ROWS * PICK_ROW_H)
  pickScroll:SetScript("OnVerticalScroll", function()
    FauxScrollFrame_OnVerticalScroll(PICK_ROW_H, UpdatePicks)
  end)

  for i = 1, PICK_ROWS do
    local row = ListRow("MacroMakerPick" .. i, f, RIGHT_X, -128 - (i - 1) * PICK_ROW_H, RIGHT_W, PICK_ROW_H, pickScroll)
    row:SetScript("OnClick", function()
      local entry = this.entry
      if not entry or entry.header then return end
      if entry.macroIndex then
        LoadMacro(entry)
      elseif arg1 == "RightButton" then
        SetIcon(entry.texture, true)
        Status("Icon set.", GREY)
      else
        PickEntry(entry)
      end
    end)
    row:SetScript("OnEnter", function() PickTooltip(this) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pickRows[i] = row
  end
end

local function BuildMacroSection(f)
  local line = f:CreateTexture(nil, "ARTWORK")
  line:SetTexture(1, 1, 1, 0.12)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -362)
  line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -20, -362)

  Label(f, "GameFontNormal", LEFT_X, -370, 300, "3. Your macro")

  iconButton = CreateFrame("Button", "MacroMakerIcon", f)
  iconButton:SetWidth(32)
  iconButton:SetHeight(32)
  iconButton:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT_X, -390)
  iconButton.icon = iconButton:CreateTexture(nil, "ARTWORK")
  iconButton.icon:SetAllPoints(iconButton)
  iconButton.icon:SetTexture(QUESTION_MARK)
  Explain(iconButton, "Macro icon", "Taken from the first spell or item you click. To choose another, right-click any spell or item in the list on the right.")

  Label(f, "GameFontHighlightSmall", LEFT_X + 42, -390, nil, "Name")
  nameBox = InputBox("MacroMakerName", f, LEFT_X + 48, -403, 124)
  nameBox:SetMaxLetters(MAX_NAME)
  nameBox:SetScript("OnTextChanged", function()
    if quiet then return end
    nameTyped = MM.Trim(this:GetText()) ~= ""
    UpdateCreateButton()
  end)

  perCharCheck = CreateFrame("CheckButton", "MacroMakerPerChar", f, "UICheckButtonTemplate")
  perCharCheck:SetWidth(24)
  perCharCheck:SetHeight(24)
  perCharCheck:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT_X + 190, -400)
  local perCharLabel = getglobal("MacroMakerPerCharText")
  if perCharLabel then perCharLabel:SetText("Only for this character") end
  perCharCheck:SetScript("OnClick", function()
    MM.db.perCharacter = this:GetChecked() and true or false
  end)
  Explain(perCharCheck, "Only for this character", "On: the macro goes in this character's own macro tab (18 slots).\n\nOff: every character on the account sees it (18 shared slots).")

  local holder = CreateFrame("Frame", "MacroMakerBodyHolder", f)
  holder:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT_X, -430)
  holder:SetWidth(452)
  holder:SetHeight(100)
  holder:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  holder:SetBackdropColor(0, 0, 0, 0.9)
  holder:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
  holder:EnableMouse(true)
  holder:SetScript("OnMouseDown", function() macroEdit:SetFocus() end)

  macroEdit = CreateFrame("EditBox", "MacroMakerBody", holder)
  macroEdit:SetMultiLine(true)
  macroEdit:SetAutoFocus(false)
  macroEdit:SetFontObject(ChatFontNormal)
  macroEdit:SetWidth(436)
  macroEdit:SetHeight(84)
  macroEdit:SetPoint("TOPLEFT", holder, "TOPLEFT", 8, -8)
  macroEdit:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  macroEdit:SetScript("OnTextChanged", BodyChanged)

  countText = Label(f, "GameFontHighlightSmall", RIGHT_X, -392, RIGHT_W + 24)
  noteText = Label(f, "GameFontHighlightSmall", RIGHT_X, -408, RIGHT_W + 24)
  noteText:SetHeight(40)
  noteText:SetJustifyV("TOP")

  createButton = Button("MacroMakerCreate", f, 128, "Create macro")
  createButton:SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_X, -456)
  createButton:SetScript("OnClick", CreateIt)
  Explain(createButton, "Create macro", "Saves the macro and puts it on your cursor, ready to drop on an action bar. A macro with the same name is updated instead and stays where it is on your bars.")

  local clear = Button("MacroMakerClear", f, 84, "Start over")
  clear:SetPoint("LEFT", createButton, "RIGHT", 6, 0)
  clear:SetScript("OnClick", ClearAll)
  Explain(clear, "Start over", "Empties the macro text, name and icon. Your saved macros aren't touched.")

  local game = Button("MacroMakerGame", f, 218, "Open the game's macro window")
  game:SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_X, -482)
  game:SetScript("OnClick", function()
    if ShowMacroFrame then ShowMacroFrame() end
  end)
  Explain(game, "The game's macro window", "Where every macro lives (also /macro). Drag macros to your bars from there, change their icon, or delete ones you no longer need.")

  statusText = Label(f, "GameFontHighlightSmall", LEFT_X, -536, WIDTH - 40)
  statusText:SetHeight(12)
end

local function BuildWindow()
  local f = CreateFrame("Frame", "MacroMakerFrame", UIParent)
  f:SetWidth(WIDTH)
  f:SetHeight(HEIGHT)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  Opaque(f)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  f:Hide()
  table.insert(UISpecialFrames, "MacroMakerFrame")

  local close = CreateFrame("Button", "MacroMakerFrameClose", f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOP", f, "TOP", 0, -18)
  title:SetText("Macro Maker")
  local sub = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOP", f, "TOP", 0, -38)
  sub:SetText(GREY .. "Pick what the button should do, click your spells, press Add to macro, then Create macro." .. END)

  local help = Button("MacroMakerHelpButton", f, 110, "Help: how to use")
  help:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -14)
  help:SetScript("OnClick", function() MM.ToggleHelp() end)
  Explain(help, "Help", "Step-by-step instructions for making your first macro, and what everything in this window does.")

  frame = f
  BuildRecipeColumn(f)
  BuildFieldColumn(f)
  BuildPickColumn(f)
  BuildMacroSection(f)

  f:SetScript("OnShow", function()
    UpdateCreateButton()
    RefreshPicks()
  end)

  ranksCheck:SetChecked(MM.db.allRanks and 1 or nil)
  perCharCheck:SetChecked(MM.db.perCharacter and 1 or nil)
  SelectRecipe(MM.DefaultRecipe())
  BodyChanged()
  Status("New here? Press Help in the top left corner. Hover anything for an explanation.", GREY)
end

function MM.ToggleWindow()
  if not frame then BuildWindow() end
  if frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
    SelectTab(pickTab)
    -- The very first time, open the instructions next to it.
    if not MM.db.seenHelp then
      MM.db.seenHelp = true
      MM.ShowHelp()
    end
  end
end

-- A spell was learned or the pet changed while the window is open.
function MM.SpellsChanged()
  if frame and frame:IsShown() and pickTab == "spells" then RefreshPicks() end
end
