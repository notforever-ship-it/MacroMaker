-- Macro Maker: "How to use" window. Opens with the Help button in the /mm window, /mm help, or
-- Shift-clicking the minimap icon.

local MM = MacroMaker

local GOLD, GREEN, GREY, WHITE, END = "|cffffd100", "|cff40ff40", "|cff9d9d9d", "|cffffffff", "|r"

local function B(s) return WHITE .. s .. END end

local HELP_TEXT = table.concat({
  GOLD .. "Making a macro, step by step" .. END,
  "1. Open the window with " .. B("/mm") .. " or the " .. B("note icon on your minimap") .. ".",
  "2. On the left, click " .. B("what the button should do") .. ", for example 'Cast on mouseover'. The text under 'Fill in the blanks' explains it.",
  "3. On the right, " .. B("click the spell") .. " you want. It drops into the blank that's marked in gold. No typing, no spelling mistakes.",
  "4. Press " .. B("Add to macro") .. ". The macro text appears in the box at the bottom.",
  "5. Give it a " .. B("name") .. " (one is suggested) and press " .. B("Create macro") .. ".",
  "6. The macro is now " .. B("on your cursor") .. ": click an empty action bar slot to drop it there. Done!",
  " ",
  GOLD .. "Several steps on one button" .. END,
  "- After 'Add to macro' you can pick another action and add it too. The steps run " .. B("top to bottom") .. " every time you press the button.",
  "- The game only lets " .. B("one spell go out per press") .. ". Smart steps like 'Keep a buff on me' or 'Keep a debuff on my target' " ..
    "do nothing when they aren't needed, and the press moves on to the next step. So this works as a one-button priority list:",
  GREY .. "     Keep a buff on me: Battle Shout   ->   Cast a spell: Bloodthirst" .. END,
  "- Things that aren't spells (attack, pet attack, trinkets, chat) happen together with your spell in the same press.",
  "- " .. B("Undo") .. " takes back the last change. " .. B("Start over") .. " empties the box. You can also type in the box yourself.",
  " ",
  GOLD .. "The lists on the right" .. END,
  "- " .. B("Spells") .. ": your own spellbook (and your pet's), so it works for every class. Use " .. B("Find") .. " to search.",
  "- " .. B("All ranks") .. ": off = always your highest rank, even after you train new ones. On = pick one exact rank, like a cheap low-rank heal.",
  "- " .. B("Items") .. ": what you carry and wear, for potions, healthstones, trinkets and weapon swaps.",
  "- " .. B("Macros") .. ": click one of your existing macros to load it, change it, and press " .. B("Update macro") .. ".",
  "- " .. B("Right-click") .. " any spell or item to use its picture as the macro's icon.",
  " ",
  GOLD .. "Good to know" .. END,
  "- A macro holds " .. B("255 characters") .. ". The counter turns red when it's too long.",
  "- " .. GREEN .. "Plain macro" .. END .. " = works even without this addon. " .. GOLD .. "Uses helpers" .. END ..
    " = the macro calls Macro Maker (lines with " .. B("MMK.") .. "), so keep the addon turned on.",
  "- Saving under a name that already exists " .. B("updates") .. " that macro, and it stays where it is on your bars.",
  "- You have 18 macro slots per character and 18 shared ones. Delete old macros in the game's macro window (" .. B("/macro") .. ").",
  "- If a macro does nothing, check chat: Macro Maker tells you when a spell or item name in it doesn't match anything you have.",
  "- Hover anything in the window for an explanation.",
  " ",
  GOLD .. "Commands" .. END,
  B("/mm") .. " - open the window      " .. B("/mm help") .. " - this window      " .. B("/mm minimap") .. " - show or hide the minimap button",
}, "\n")

local frame

local function Opaque(f)
  local solid = f:CreateTexture(nil, "BACKGROUND")
  solid:SetTexture(0.05, 0.05, 0.07, 1)
  solid:SetPoint("TOPLEFT", f, "TOPLEFT", 11, -11)
  solid:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -11, 11)
end

local function CreateHelp()
  frame = CreateFrame("Frame", "MacroMakerHelpFrame", UIParent)
  frame:SetWidth(540)
  frame:SetHeight(620)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() this:StartMoving() end)
  frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  Opaque(frame)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  frame:Hide()
  table.insert(UISpecialFrames, "MacroMakerHelpFrame")

  local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOP", frame, "TOP", 0, -20)
  title:SetText("Macro Maker - How to use")
  local version = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  version:SetPoint("TOP", title, "BOTTOM", 0, -2)
  version:SetText(GREY .. "version " .. MM.VERSION .. END)

  local close = CreateFrame("Button", "MacroMakerHelpCloseButton", frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function() frame:Hide() end)

  local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  text:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, -64)
  text:SetWidth(488)
  text:SetHeight(500)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("TOP")
  text:SetText(HELP_TEXT)

  local ok = CreateFrame("Button", "MacroMakerHelpOkButton", frame, "UIPanelButtonTemplate")
  ok:SetWidth(120)
  ok:SetHeight(24)
  ok:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 20)
  ok:SetText("Got it")
  ok:SetScript("OnClick", function() frame:Hide() end)

  local credit = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  credit:SetPoint("BOTTOM", frame, "BOTTOM", 0, 26)
  credit:SetText(GREY .. "Made by " .. END .. "|cffabd473stealthzi" .. END)
end

function MM.ShowHelp()
  if not frame then CreateHelp() end
  frame:Show()
end

function MM.ToggleHelp()
  if frame and frame:IsShown() then
    frame:Hide()
  else
    MM.ShowHelp()
  end
end
