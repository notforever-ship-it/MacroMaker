-- Macro Maker: minimap button. Click opens the window, Shift-click the help, drag moves it around the minimap.

local MM = MacroMaker

local button

local function UpdatePosition()
  local angle = math.rad(MM.db.minimapAngle or 200)
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end

local function DragUpdate()
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  px, py = px / scale, py / scale
  MM.db.minimapAngle = math.deg(math.atan2(py - my, px - mx))
  UpdatePosition()
end

function MM.UpdateMinimapButton()
  if not button then return end
  if MM.db.minimapHidden then
    button:Hide()
  else
    UpdatePosition()
    button:Show()
  end
end

function MM.InitMinimapButton()
  button = CreateFrame("Button", "MacroMakerMinimapButton", Minimap)
  button:SetWidth(31)
  button:SetHeight(31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local icon = button:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
  icon:SetWidth(20)
  icon:SetHeight(20)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  icon:SetPoint("TOPLEFT", button, "TOPLEFT", 6, -5)

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetWidth(53)
  border:SetHeight(53)
  border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

  button:SetScript("OnClick", function()
    if IsShiftKeyDown() then MM.ToggleHelp() else MM.ToggleWindow() end
  end)
  button:SetScript("OnDragStart", function() this:SetScript("OnUpdate", DragUpdate) end)
  button:SetScript("OnDragStop", function() this:SetScript("OnUpdate", nil) end)
  button:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:SetText("Macro Maker")
    GameTooltip:AddLine("version " .. MM.VERSION, 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Click: build a macro", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Shift-click: how to use", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Drag: move this button", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("/mm minimap hides it", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)

  MM.UpdateMinimapButton()
end
