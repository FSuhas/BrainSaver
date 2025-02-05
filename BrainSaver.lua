--[[ 
  Goblin Brainwashing Device Addon for WoW 1.12
  Revised Layout with Event Handling:
  
  - Main frame (350x350) centered on screen.
  - Title ("Goblin Brainwashing Device") at the top.
  - A talent summary line below the title (e.g. "12/31/9").
  - A close button (Escape also closes the frame via UISpecialFrames).
  - Four talent slot buttons arranged in a 2x2 grid.
      • Each button is 64x64.
      • A permanent slot number appears in the top–left of each button.
      • An editable layout name appears just above each button.
      • Inactive slots show a default question–mark icon.
      • For inactive slots a left–click pops up a confirmation to buy the slot for 100 gold.
      • For active slots:
           - A single left–click (if not part of a double–click) prompts a confirmation to enable that layout.
           - A right–click opens a popup to edit the slot’s name/icon.
           - A double–click (simulated via timing) prompts a confirmation to save your current talents.
  - A “Reset Talents” button appears below the grid, which pops up a confirmation dialog.
  
  - Event handling:
      When a gossip window is shown (GOSSIP_SHOW) and the NPC name is "Orgrimmar Grunt,"
      the default GossipFrame is hidden and this custom frame is shown.
      When gossip is closed (GOSSIP_CLOSED), this custom frame is hidden.
      
  Note: In WoW 1.12 script handlers use 'this', 'arg1', and 'event' as globals.
--]]

--------------------------------------------------
-- Main Frame Setup
--------------------------------------------------
local mainFrame = CreateFrame("Frame", "GoblinBrainWashingDeviceFrame", UIParent)
mainFrame:SetWidth(350)
mainFrame:SetHeight(350)
mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
mainFrame:EnableMouse(true)
mainFrame:SetMovable(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
mainFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
mainFrame:SetBackdropColor(0, 0, 0, 1)
-- For testing you can call mainFrame:Show() manually,
-- but now event handling will control its visibility.
mainFrame:Hide()

-- Allow the frame to be closed with Escape.
tinsert(UISpecialFrames, "GoblinBrainWashingDeviceFrame")

mainFrame.gossip_slots = {}
mainFrame.gossip_slots.save = {}
mainFrame.gossip_slots.load = {}
mainFrame.gossip_slots.buy = {}
mainFrame.gossip_slots.reset = nil

--------------------------------------------------
-- Title and Talent Summary
--------------------------------------------------
local titleText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleText:SetPoint("TOP", mainFrame, "TOP", 0, -15)
titleText:SetText("Goblin Brainwashing Device")

local talentSummaryText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
talentSummaryText:SetPoint("TOP", titleText, "BOTTOM", 0, -10)
talentSummaryText:SetText("12/31/9")  -- Update this with real talent info as needed

-- Standard close button.
local closeButton = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -5, -5)

--------------------------------------------------
-- Create 4 Talent Buttons in a 2x2 Grid
--------------------------------------------------
local talentButtons = {}
local numRows, numCols = 2, 2
local btnWidth, btnHeight = 64, 64
local spacing = 40
-- Calculate the grid width.
local gridWidth = numCols * btnWidth + (numCols - 1) * spacing
-- Center the grid horizontally.
local gridXOffset = (mainFrame:GetWidth() - gridWidth) / 2  
-- Position the grid a bit below the talent summary text.
local gridTopOffset = -95  

local index = 1
for row = 1, numRows do
    for col = 1, numCols do
        local btn = CreateFrame("Button", "TalentButton"..index, mainFrame, "ActionButtonTemplate")
        btn:SetWidth(btnWidth)
        btn:SetHeight(btnHeight)
        -- Calculate x and y offsets relative to mainFrame's TOPLEFT.
        local x = gridXOffset + (col - 1) * (btnWidth + spacing)
        local y = gridTopOffset - (row - 1) * (btnHeight + spacing)
        btn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", x, y)
        
        -- Static slot number in the top-left corner.
        btn.slotNumberText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.slotNumberText:SetFont(btn.slotNumberText:GetFont(), 16, "")
        btn.slotNumberText:SetPoint("CENTER", btn, "BOTTOMRIGHT", -8, 9)
        btn.slotNumberText:SetText(index)
        
        -- Editable layout name above the button.
        btn.layoutName = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.layoutName:SetPoint("BOTTOM", btn, "TOP", 0, 14)
        btn.layoutName:SetText("Spec " .. index)

        -- Editable layout name above the button.
        btn.talentSummary = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.talentSummary:SetPoint("BOTTOM", btn, "TOP", 0, 2)
        btn.talentSummary:SetText("? | ? | ?")
        
        -- Active/inactive state.
        btn.isActive = false
        btn:SetNormalTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        
        -- Variables for simulating double-click.
        btn.clickPending = false
        btn.lastClickTime = 0

        btn:SetScript("OnShow", function ()
          if mainFrame.gossip_slots.load[btn.index] or mainFrame.gossip_slots.save[btn.index] then
            btn.isActive = true
          end
        end)
        
        -- OnClick handler using 'this' and 'arg1'.
        btn:SetScript("OnClick", function()
          if arg1 == "RightButton" then
            if this.isActive then
              local edit_layout_dialogue = StaticPopup_Show("EDIT_TALENT_SLOT")
              edit_layout_dialogue.data = this
            end
            return
          end
          
          if arg1 == "LeftButton" then
            local curTime = GetTime()
            if this.clickPending and ((curTime - this.lastClickTime) < 0.3) then
              -- Double-click detected.
              this.clickPending = false
              this:SetScript("OnUpdate", nil)
              if this.isActive then
                local save_layout_dialog = StaticPopup_Show("SAVE_TALENT_LAYOUT", this.index, this.layoutName:GetText())
                save_layout_dialog.data = this
              end
            else
              -- Begin timer to distinguish single vs. double-click.
              this.lastClickTime = curTime
              this.clickPending = true
              this:SetScript("OnUpdate", function(elapsed)
                if ((GetTime() - this.lastClickTime) >= 0.3) and this.clickPending then
                  if this.isActive and BrainsaverDB.spec[button.index] then
                    local enable_talent = StaticPopup_Show("ENABLE_TALENT_LAYOUT", format("Enable these talents from slot %d?\n%s\n%s",
                    this.index,
                    this.layoutName:GetText(),
                    ColorSpecSummary(BrainsaverDB.spec[button.index].t1,BrainsaverDB.spec[button.index].t2,BrainsaverDB.spec[button.index].t3)))
                    enable_talent.data = this
                    -- StaticPopup_Show("ENABLE_TALENT_LAYOUT", this.index, this.layoutName:GetText(), "1 | 2 | 3")
                  elseif not this.isActive then
                    StaticPopup_Show("BUY_TALENT_SLOT")
                  end
                  this.clickPending = false
                  this:SetScript("OnUpdate", nil)
                end
              end)
            end
          end
        end)

        btn.index = index
        talentButtons[index] = btn
        index = index + 1
    end
end

--------------------------------------------------
-- Reset Talents Button (Anchored below the grid)
--------------------------------------------------
local resetButton = CreateFrame("Button", "ResetTalentButton", mainFrame, "UIPanelButtonTemplate")
resetButton:SetWidth(120)
resetButton:SetHeight(30)
-- Anchor the reset button below the grid.
resetButton:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, 20)
resetButton:SetText("Reset Talents")
resetButton:SetScript("OnClick", function()
    StaticPopup_Show("CONFIRM_TALENT_WIPE") -- builtin
end)

local function ColorSpecSummary(t1,t2,t3)
  local largest  = math.max(t1, t2, t3)
  local smallest = math.min(t1, t2, t3)

  -- Function to return the color code based on ranking
  local function getColor(value)
      if value == largest then
          return "|cff00ff00"  -- Green
      elseif value == smallest then
          return "|cff0000ff"  -- Blue
      else
          return "|cffffff00"  -- Yellow
      end
  end

  -- Build the output string with each number colored according to its ranking.
  return string.format("%s%d|r | %s%d|r | %s%d|r",
      getColor(t1), t1,
      getColor(t2), t2,
      getColor(t3), t3)
end

--------------------------------------------------
-- Static Popup Dialogs
--------------------------------------------------

StaticPopupDialogs["BUY_TALENT_SLOT"] = {
    text = "Do you want to buy a talent slot for 100 gold?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        -- local button = this.data
        local button
        local slot
        for s,btn in mainFrame.gossip_slots.buy do
          button = getglobal("TalentButton" .. s)
          slot = s
          break
        end
        -- print("Buying talent slot for 100 gold.")
        -- print(slot)
        button.isActive = true
        button:SetNormalTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        button:GetNormalTexture():SetVertexColor(1,1,1) -- prob not needed
        button.layoutName:SetText("Spec "..button.index)
        button.talentSummary:SetText(" ? | ? | ?")
        -- button:GetNormalTexture():SetVertexColor(1,1,1)
        -- (Update the button's appearance as needed.)
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

StaticPopupDialogs["ENABLE_TALENT_LAYOUT"] = {
    text = "%s",
    button1 = "Enable",
    button2 = "Cancel",
    OnShow = function()
        -- local button = this.data
        -- this.text:SetFormattedText("Do you want to enable these talents?\n%s\n%s", button.layoutName:GetText(), button.talentSummary)
    end,
    OnAccept = function()
        local button = this.data
        print("Enabling talent layout: " .. button.layoutName:GetText())
        -- (Send the appropriate gossip option.)
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

StaticPopupDialogs["EDIT_TALENT_SLOT"] = {
    text = "Enter new name and icon path for this talent slot:",
    button1 = "Save",
    button2 = "Cancel",
    hasEditBox = 1,
    OnShow = function()
        local button = this.data
        local editBox = getglobal(this:GetParent():GetName().."EditBox")
        editBox:SetText(button.layoutName:GetText())
        editBox:SetFocus()
    end,
    OnAccept = function()
        local button = this.data
        local newText = getglobal(this:GetParent():GetName().."EditBox"):GetText()
        button.layoutName:SetText(newText)
        print("Talent slot renamed to: " .. newText)
        -- (Optionally parse input for an icon path.)
    end,
    OnHide = function()
      getglobal(this:GetParent():GetName().."EditBox"):SetText("")
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

StaticPopupDialogs["SAVE_TALENT_LAYOUT"] = {
    text = "Save your current talents to slot %d?\nCurrent name: %s\nEnter new name:",
    button1 = "Save",
    button2 = "Cancel",
    hasEditBox = 1,
    OnShow = function(button)
      local editBox = getglobal(this:GetName().."EditBox")
      editBox:SetText(button.layoutName:GetText())
      editBox:SetFocus()
    end,
    OnAccept = function(button)
      local newName = getglobal(this:GetParent():GetName().."EditBox"):GetText()

      local _,_,t1 = GetTalentTabInfo(1)
      local _,_,t2 = GetTalentTabInfo(2)
      local _,_,t3 = GetTalentTabInfo(3)

      BrainsaverDB.spec[button.index] = {
        name = newName,
        t1 = t1,
        t2 = t2,
        t3 = t3,
        icon = (BrainsaverDB.spec[button.index] and BrainsaverDB.spec[button.index].icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
      }

      button.layoutName:SetText(newName)
      button.talentSummary:SetText(ColorSpecSummary(t1,t2,t3))

      -- (Send the gossip option to save the layout; update talentSummary if needed.)
    end,
    OnHide = function()
      getglobal(this:GetName() .. "EditBox"):SetText("")
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

StaticPopupDialogs["RESET_TALENTS"] = {
    text = "Do you really want to reset your current talent points?",
    button1 = "Yes", -- todo, just call the built in confirm
    button2 = "No",
    OnAccept = function()
      mainFrame.gossip_slots.reset:Click()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

--------------------------------------------------
-- Gossip Event Handling
--------------------------------------------------
mainFrame:RegisterEvent("ADDON_LOADED")
mainFrame:RegisterEvent("GOSSIP_SHOW")
mainFrame:RegisterEvent("GOSSIP_CLOSED")
mainFrame:SetScript("OnEvent", function()
  if event == "GOSSIP_SHOW" and (GossipFrameNpcNameText:GetText() == "Orgrimmar Grunt" or (GossipFrameNpcNameText:GetText() == "Goblin Brainwashing Device")) then

    local titleButton;
    local _,_,t1 = GetTalentTabInfo(1)
    local _,_,t2 = GetTalentTabInfo(2)
    local _,_,t3 = GetTalentTabInfo(3)

    talentSummaryText:SetText(format("%d | %d | %d",t1,t2,t3))

    mainFrame.gossip_slots = {}
    mainFrame.gossip_slots.save = {}
    mainFrame.gossip_slots.load = {}
    mainFrame.gossip_slots.buy = {}
    mainFrame.gossip_slots.reset = nil

    for i=1, NUMGOSSIPBUTTONS do
      titleButton = getglobal("GossipTitleButton" .. i)

      
      if titleButton:IsVisible() then
        local text = titleButton:GetText()
        local _,_,save_spec = string.find(text,"Save (%d+)(..) Specialization")
        local _,_,load_spec = string.find(text,"Activate (%d+)(..) Specialization")
        local _,_,buy_spec = string.find(text,"Buy (%d+)(..) Specialization")
        local reset = string.find(text,"Reset my talents")
        
        if save_spec then
          mainFrame.gossip_slots.save[tonumber(save_spec)] = titleButton
          -- TODO, enable buttons here?
          print("save " ..save_spec)
        elseif load_spec then
          load_spec = tonumber(load_spec)
          mainFrame.gossip_slots.load[load_spec] = titleButton
          talentButtons[load_spec].canLoad = true
          talentButtons[load_spec].isActive = true

          print("load " ..load_spec)
        elseif buy_spec then
          buy_spec = tonumber(buy_spec)
          mainFrame.gossip_slots.buy[buy_spec] = titleButton

          for i=buy_spec,4 do
            talentButtons[i].isActive = false
            talentButtons[i]:SetNormalTexture("Interface\\Icons\\INV_Misc_Coin_01")
            talentButtons[i]:GetNormalTexture():SetVertexColor(0.5, 0.5, 0.5)
            talentButtons[i].layoutName:SetText("")
            talentButtons[i].talentSummary:SetText("Buy Slot")
          end

          -- print("buy " ..buy_spec)
        elseif reset then
          mainFrame.gossip_slots.reset = titleButton
          print("reset")
        end
      end
    end
    GossipFrame:SetAlpha(0) -- 'hide' but don't cause a GOSSIP_CLOSED
    mainFrame:Show()

    -- mainFrame.gossip_slots.reset:Click()
  elseif event == "GOSSIP_CLOSED" then
    mainFrame:Hide()
  elseif event == "ADDON_LOADED" and arg1 == "BrainSaver" then
    BrainsaverDB = BrainsaverDB or {}
    BrainsaverDB.spec = BrainsaverDB.spec or {}
  end
end)

--------------------------------------------------
-- (Optional) Show/Hide Frame Functions
--------------------------------------------------
function ShowGoblinDeviceFrame()
    -- If needed, this function can be called manually.
    mainFrame:Show()
end

function HideGoblinDeviceFrame()
    mainFrame:Hide()
end

-- The event handling code above now controls when the custom frame is shown.
