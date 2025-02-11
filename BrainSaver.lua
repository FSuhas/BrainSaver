local addon_name = "BrainSaver"
local dialogue_alpha = 0.35

--------------------------------------------------
-- Main Frame Setup
--------------------------------------------------
local mainFrame = CreateFrame("Frame", addon_name.."Frame", UIParent)
mainFrame:SetWidth(350)
mainFrame:SetHeight(350)
mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
mainFrame:EnableMouse(true)
mainFrame:SetMovable(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", function () mainFrame:StartMoving() end)
mainFrame:SetScript("OnDragStop", function () mainFrame:StopMovingOrSizing() end )
mainFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
-- mainFrame:SetBackdropColor(0, 0, 0, 1)
-- For testing you can call mainFrame:Show() manually,
-- but now event handling will control its visibility.
mainFrame:Hide()

mainFrame.iconCheckTexture = mainFrame:CreateTexture()

-- Allow the frame to be closed with Escape.
tinsert(UISpecialFrames, addon_name.."Frame")

mainFrame.gossip_slots = {}
mainFrame.gossip_slots.save = {}
mainFrame.gossip_slots.load = {}
mainFrame.gossip_slots.buy = {}
mainFrame.gossip_slots.reset = nil
mainFrame.currentButton = 1


--------------------------------------------------
-- Title and Talent Summary
--------------------------------------------------
mainFrame.titleText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
mainFrame.titleText:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 15, -15)
mainFrame.titleText:SetText(GetAddOnMetadata(addon_name, "title") .. " " .. GetAddOnMetadata(addon_name, "version"))

mainFrame.talentSummaryText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
mainFrame.talentSummaryText:SetPoint("TOP", mainFrame, "TOP", 0, -50)
mainFrame.talentSummaryText:SetText("12/31/9")  -- Update this with real talent info as needed

-- Standard close button.
mainFrame.closeButton = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
mainFrame.closeButton:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -5, -5)
mainFrame.closeButton:SetScript("OnClick", function()
  HideUIPanel(GossipFrame) -- use the specific closing function
end)

local function ColorSpecSummary(t1,t2,t3)
  local largest  = math.max(t1, t2, t3)
  local smallest = math.min(t1, t2, t3)

  -- Function to return the color code based on ranking
  local function getColor(value)
      if value == largest then
          return "|cff00ff00"  -- Green
      elseif value == smallest then
          return "|cff0077ff"  -- Blue
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

local function TalentCounts()
  local _,_,t1 = GetTalentTabInfo(1)
  local _,_,t2 = GetTalentTabInfo(2)
  local _,_,t3 = GetTalentTabInfo(3)
  return t1,t2,t3
end

function FetchTalents()
  local talents = {}
  for tab=1,3 do
    local _,_,tcount = GetTalentTabInfo(tab)
    for talent=1,100 do
      local name,icon,row,col,count,max = GetTalentInfo(tab,talent)
      if not name then break end
      talents[tab] = talents[tab] or {}
      talents[tab][talent] = {
        name = name,
        icon = icon,
        row = row,
        col = col,
        count = count,
        max = max,
      }
    end
  end
  return talents
end

function IsSameSpec(t1, t2)
  for i, tab in ipairs(t1) do
    for j, talent in ipairs(tab) do
      if not (t2[i] and t2[i][j] and talent.count == t2[i][j].count) then
        return false
      end
    end
  end
  return true
end

----------------------------------------------------------------
-- Searches the spellbook for a spell matching the given name.
-- Returns the texture path if found, or nil otherwise.
----------------------------------------------------------------
local function SearchSpellbookForIcon(spellName)
  local lowerSpellName = string.lower(spellName)
  local index = 1
  local foundTexture = nil
  -- In WoW 1.12, iterate until GetSpellName returns nil.
  while true do
    local name, rank = GetSpellName(index, BOOKTYPE_SPELL)
    if not name then
      break
    end
    if string.lower(name) == lowerSpellName then
      foundTexture = GetSpellTexture(index, BOOKTYPE_SPELL)
      break
    end
    index = index + 1
  end
  return foundTexture
end

----------------------------------------------------------------
-- Searches the talent list for a talent matching the given name.
-- Returns the talent’s texture if found, or nil otherwise.
----------------------------------------------------------------
local function SearchTalentsForIcon(talentName)
  local lowerTalentName = string.lower(talentName)
  local foundTexture = nil
  -- In WoW 1.12 there are 3 talent tabs; adjust the max talents per tab if needed.
  for tab = 1, 3 do
    for talent = 1, 100 do
      local name, texture, tier, column, rank, maxRank = GetTalentInfo(tab, talent)
      if not name then
        break
      end
      if string.lower(name) == lowerTalentName then
        foundTexture = texture
        return foundTexture
      end
    end
  end
  return foundTexture
end

function FindTexture(source)
  local icon = "Interface\\Icons\\INV_Misc_QuestionMark"
  local spell_icon = SearchSpellbookForIcon(source)
  local talent_icon = SearchTalentsForIcon(source)
  if spell_icon then
    icon = spell_icon
  elseif talent_icon then
    icon = talent_icon
  else -- check if it's a valid texture path
    mainFrame.iconCheckTexture:SetTexture(source)
    if mainFrame.iconCheckTexture:GetTexture() then
      icon = source
    end
    mainFrame.iconCheckTexture:SetTexture()
  end

  return icon
end

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
local gridTopOffset = -110

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
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        -- Static slot number in the top-left corner.
        btn.slotNumberText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.slotNumberText:SetFont(btn.slotNumberText:GetFont(), 16, "")
        btn.slotNumberText:SetPoint("CENTER", btn, "BOTTOMRIGHT", -8, 9)
        btn.slotNumberText:SetText(index)
        
        -- Editable layout name above the button.
        btn.layoutName = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.layoutName:SetPoint("BOTTOM", btn, "TOP", 0, 16)
        btn.layoutName:SetText("Spec " .. index)

        -- Editable layout name above the button.
        btn.talentSummary = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.talentSummary:SetPoint("BOTTOM", btn, "TOP", 0, 2)
        btn.talentSummary:SetText("? | ? | ?")

        -- Editable layout name above the button.
        btn.activeIndicator = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        local aif,ais = btn.activeIndicator:GetFont()
        btn.activeIndicator:SetFont(aif,ais, "OUTLINE")
        btn.activeIndicator:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn.activeIndicator:SetText("")
        
        -- Active/inactive state.
        btn.isActive = false
        
        -- Variables for simulating double-click.
        btn.clickPending = false
        btn.lastClickTime = 0

        function btn:SetName(name)
          self.layoutName:SetText(name)
        end
        function btn:GetName()
          return self.layoutName:GetText()
        end
        function btn:SetTalentSummary(t1,t2,t3)
          if not t1 then
            self.talentSummary:SetText("? | ? | ?")
          elseif type(t1) == "string" then
            self.talentSummary:SetText(t1)
          else
            self.talentSummary:SetText(ColorSpecSummary(t1,t2,t3))
          end
        end
        function btn:GetTalentSummary()
          return self.talentSummary:GetText()
        end
        function btn:GetIndex()
          return self.index
        end
        function btn:GetIcon()
          return self:GetNormalTexture():GetTexture()
        end
        function btn:SetIcon(source,disabled) -- path or spellname  or talent name
          local icon = FindTexture(source)

          self:SetNormalTexture(icon)
          self:SetPushedTexture(icon)

          if disabled then
            self:GetNormalTexture():SetVertexColor(0.5, 0.5, 0.5)
          else
            self:GetNormalTexture():SetVertexColor(1, 1, 1)
          end

          return icon
        end

        btn:SetIcon("Interface\\Icons\\INV_Misc_QuestionMark")

        -- OnClick handler using 'this' and 'arg1'.
        btn:SetScript("OnClick", function()
          mainFrame.currentButton = this.index

          if this.isActive then
            local button = this
            if arg1 == "RightButton" and IsShiftKeyDown() then
                StaticPopup_Show("EDIT_TALENT_SLOT")
            elseif arg1 == "RightButton"  then
              StaticPopup_Show("SAVE_TALENT_LAYOUT")
            elseif arg1 == "LeftButton" then
              if BrainSaverDB.spec[button.index] then
                StaticPopup_Show("ENABLE_TALENT_LAYOUT")
              end
            end
          else
            StaticPopup_Show("BUY_TALENT_SLOT")
          end
        end)
        btn:SetScript("OnShow", function ()
          if this.isCurrentSpec then
            -- this:GetNormalTexture():SetVertexColor(0.7, 1, 0.7)
            this.activeIndicator:SetText("ACTIVE")
          else
            -- this:GetNormalTexture():SetVertexColor(1, 1, 1)
            this.activeIndicator:SetText("")
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
mainFrame.resetButton = CreateFrame("Button", "ResetTalentButton", mainFrame, "UIPanelButtonTemplate")
mainFrame.resetButton:SetWidth(120)
mainFrame.resetButton:SetHeight(30)
-- Anchor the reset button below the grid.
mainFrame.resetButton:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, 20)
mainFrame.resetButton:SetText("Reset Talents")
mainFrame.resetButton:SetScript("OnClick", function()
    StaticPopup_Show("RESET_TALENTS")
end)

--------------------------------------------------
-- Show Brainwasher Dialogue button
--------------------------------------------------
mainFrame.washerButton = CreateFrame("Button", "WasherDialogueButton", mainFrame, "UIPanelButtonTemplate")
mainFrame.washerButton:SetWidth(60)
mainFrame.washerButton:SetHeight(20)
-- Anchor the reset button below the grid.
mainFrame.washerButton:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -15, 15)
mainFrame.washerButton:SetText("Washer")
mainFrame.washerButton:SetScript("OnClick", function()
  GossipFrame:SetAlpha(1)
end)
mainFrame.washerButton:SetScript("OnEnter", function()
  GameTooltip:SetOwner(this, "ANCHOR_LEFT")
  GameTooltip:SetText("Show original brainwasher dialogue.", 1, 1, 0)  -- Tooltip title
  GameTooltip:Show()
end)
mainFrame.washerButton:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

--------------------------------------------------
-- Static Popup Dialogs
--------------------------------------------------

StaticPopupDialogs["BUY_TALENT_SLOT"] = {
    text = "Do you want to buy a talent slot for 100 gold?",
    button1 = "Yes",
    button2 = "No",
    OnShow = function()
      mainFrame:SetAlpha(dialogue_alpha)
    end,
    OnAccept = function()
      -- local button = this.data
      local button
      local buy_button
      local slot
      for s,btn in mainFrame.gossip_slots.buy do
        -- Send the appropriate gossip option:
        btn:Click() -- this will close the dialogue for us
        break
      end
    end,
    OnHide = function ()
      mainFrame:SetAlpha(1)
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

StaticPopupDialogs["ENABLE_TALENT_LAYOUT"] = {
    text = "Do you want to enable these talents?",
    button1 = "Activate",
    button2 = "Cancel",
    showAlert = 1,
    OnShow = function()
      mainFrame:SetAlpha(dialogue_alpha)
      this:SetBackdropColor(1,1,1,1)
      -- getglobal(this:GetName().."Background"):SetVertexColor(0,0,0,1)
      local button = talentButtons[mainFrame.currentButton]
      local spec = BrainSaverDB.spec[button.index]
      local t1,t2,t3 = TalentCounts()
      getglobal(this:GetName().."Text"):SetText(
        format("|cffff5500LOAD|r TALENTS\n\nSpec Slot %d:\nSpec name: %s\nSpec talents: %s\n\nCurrent talents: %s\nActivate spec talents? (causes brainwasher debuff)",
        -- format("Enable these talents from slot %d?\n\n%s\n\n%s",
                button.index,
                button:GetName(),
                ColorSpecSummary(spec.t1, spec.t2, spec.t3),
                ColorSpecSummary(t1, t2, t3))
      )
      if spec then
        getglobal(this:GetName().."AlertIcon"):SetTexture(spec.icon)
      else
        getglobal(this:GetName().."AlertIcon"):SetTexture(button:GetIcon())
      end
    end,
    OnAccept = function()
      local button = talentButtons[mainFrame.currentButton]
      -- Send the appropriate gossip option:
      mainFrame.gossip_slots.load[mainFrame.currentButton]:Click()
    end,
    OnHide = function ()
      mainFrame:SetAlpha(1)
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

StaticPopupDialogs["EDIT_TALENT_SLOT"] = {
    text = "Change talent spec icon:\n\nEnter an icon path or spell or talent name.",
    button1 = "Save",
    button2 = "Cancel",
    hasEditBox = 1,
    hasWideEditBox = 1,
    OnShow = function()
      mainFrame:SetAlpha(dialogue_alpha)
      local editBox = getglobal(this:GetName().."WideEditBox")
      local spec = BrainSaverDB.spec[mainFrame.currentButton]
      if spec and spec.icon then
        editBox:SetText(spec.icon)
      else
        editBox:SetText("Interface\\Icons\\INV_Misc_QuestionMark")
      end
    end,
    OnAccept = function()
      local button = talentButtons[mainFrame.currentButton]
      local newText = getglobal(this:GetParent():GetName().."WideEditBox"):GetText()
      local icon = button:SetIcon(newText)
      if BrainSaverDB.spec[mainFrame.currentButton] then
        BrainSaverDB.spec[mainFrame.currentButton].icon = icon
      end
    end,
    OnHide = function()
      getglobal(this:GetName().."WideEditBox"):SetText("")
      mainFrame:SetAlpha(1)
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

-- todo, show the spec numbers you're saving, and what exists in the slot
StaticPopupDialogs["SAVE_TALENT_LAYOUT"] = {
    -- text = "Save your current talents to slot %d?\n\n%s\n\n%s\n\nEnter new name:",
    text = "Do you want to save these talents?",
    button1 = "Save",
    button2 = "Cancel",
    hasEditBox = 1,
    showAlert = 1,
    OnShow = function()
      mainFrame:SetAlpha(dialogue_alpha)
      local button = talentButtons[mainFrame.currentButton]
      local spec = BrainSaverDB.spec[mainFrame.currentButton]
      local t1,t2,t3 = TalentCounts()

      getglobal(this:GetName().."Text"):SetText(
        format("|cff00ff55SAVE|r TALENTS\n\nSpec Slot %d:\nSpec name: %s\nSpec talents: %s\n\nCurrent talents: %s\nReplace spec talents with current talents?",
                button.index,
                button.layoutName:GetText(),
                spec and ColorSpecSummary(spec.t1,spec.t2,spec.t3) or "? | ? | ?",
                ColorSpecSummary(t1,t2,t3))
      )
      local editBox = getglobal(this:GetName().."EditBox")
      if spec then
        getglobal(this:GetName().."AlertIcon"):SetTexture(spec.icon)
        editBox:SetText(spec.name)
      else
        getglobal(this:GetName().."AlertIcon"):SetTexture(button:GetIcon())
        editBox:SetText(button:GetName())
      end
    end,
    OnAccept = function()
      local button = talentButtons[mainFrame.currentButton]
      local newName = getglobal(this:GetParent():GetName().."EditBox"):GetText()
      local t1,t2,t3 = TalentCounts()
      local talents = FetchTalents()

      BrainSaverDB.spec[button.index] = {
        name = newName,
        t1 = t1,
        t2 = t2,
        t3 = t3,
        talents = talents,
        icon = (BrainSaverDB.spec[button.index] and BrainSaverDB.spec[button.index].icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
      }

      button.layoutName:SetText(newName)
      button.talentSummary:SetText(ColorSpecSummary(t1,t2,t3))

      -- Send the appropriate gossip option:
      mainFrame.gossip_slots.save[mainFrame.currentButton]:Click()
    end,
    OnHide = function()
      getglobal(this:GetName() .. "EditBox"):SetText("")
      mainFrame:SetAlpha(1)
      getglobal(this:GetName().."AlertIcon"):SetTexture()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

-- can't use the builtin since this doesn't use the CONFIRM_TALENT_WIPE event
-- and can't use CheckTalentMasterDist
StaticPopupDialogs["RESET_TALENTS"] = {
    text = "Reset your current talent points?\n\nThis cost gold to do and causes a 10 minute brainwasher debuff.",
    button1 = "Yes",
    button2 = "No",
    OnShow = function()
      mainFrame:SetAlpha(dialogue_alpha)
      getglobal(this:GetName().."AlertIcon"):SetTexture("Interface\\Icons\\Spell_Nature_AstralRecalGroup")
    end,
    OnAccept = function()
      mainFrame.gossip_slots.reset:Click()
    end,
    OnHide = function()
      mainFrame:SetAlpha(1)
      getglobal(this:GetName().."AlertIcon"):SetTexture()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
    showAlert = 1,
}

--------------------------------------------------
-- Gossip Event Handling
--------------------------------------------------
mainFrame:RegisterEvent("ADDON_LOADED")
mainFrame:RegisterEvent("GOSSIP_SHOW")
mainFrame:RegisterEvent("GOSSIP_CLOSED")
mainFrame:RegisterEvent("UI_ERROR_MESSAGE")
mainFrame:SetScript("OnEvent", function()
  if event == "UI_ERROR_MESSAGE" then
    if string.find(arg1, "^Scrambled brain detected") then
      UIErrorsFrame:Clear()
      for i = 0, 16 do
        local ix = GetPlayerBuff(i, "HARMFUL")
        if ix < 0 then break end
        local texture = GetPlayerBuffTexture(ix)
        if string.lower(texture) == "interface\\icons\\spell_shadow_mindrot" then
          local timeRemaining = GetPlayerBuffTimeLeft(ix)
          if timeRemaining then
            UIErrorsFrame:AddMessage(format("Brainwasher Debuff: %dm %ds", timeRemaining/60,math.mod(timeRemaining,60)),1,0,0)
          end
          break -- stop once we've found the desired debuff
        end
      end
    end
  elseif event == "GOSSIP_SHOW" and (GossipFrameNpcNameText:GetText() == "Goblin Brainwashing Device") then

    local titleButton;
    local t1,t2,t3 = TalentCounts()
    local current_spec = FetchTalents()

    mainFrame.talentSummaryText:SetText("Current talents: " .. ColorSpecSummary(t1,t2,t3))

    mainFrame.gossip_slots = {
      save = {},
      load = {},
      buy = {},
      -- reset = nil,
    }

    for i=1, NUMGOSSIPBUTTONS do
      titleButton = getglobal("GossipTitleButton" .. i)

      
      if titleButton:IsVisible() then
        local text = titleButton:GetText()
        local _,_,save_spec = string.find(text,"Save (%d+)(..) Specialization")
        local _,_,load_spec = string.find(text,"Activate (%d+)(..) Specialization")
        local _,_,buy_spec = string.find(text,"Buy (%d+)(..) Specialization")
        local reset = string.find(text,"Reset my talents")
        save_spec = tonumber(save_spec)
        load_spec = tonumber(load_spec)
        buy_spec  = tonumber(buy_spec)

        
        if save_spec then
          mainFrame.gossip_slots.save[save_spec] = titleButton
          talentButtons[save_spec].canSave = true
          talentButtons[save_spec].isActive = true

        elseif load_spec then
          mainFrame.gossip_slots.load[load_spec] = titleButton
          talentButtons[load_spec].canLoad = true
          talentButtons[load_spec].isActive = true

        elseif buy_spec then
          mainFrame.gossip_slots.buy[buy_spec] = titleButton

          for i=buy_spec,4 do
            talentButtons[i].isActive = false
            talentButtons[i]:SetIcon("Interface\\Icons\\INV_Misc_Coin_01",true)
            talentButtons[i]:SetName("")
            talentButtons[i]:SetTalentSummary("Buy Slot")
          end

        elseif reset then
          mainFrame.gossip_slots.reset = titleButton
        end
      end
    end

    -- for s_ix,spec in ipairs(BrainSaverDB.spec) do
    for i=1,4 do
      local button = talentButtons[i]
      local spec = BrainSaverDB.spec[i]
      button.isCurrentSpec = false
      if button.isActive then
        if button.canLoad and spec then
          -- load spec data
          button:SetIcon(spec.icon)
          button:SetName(spec.name)
          button:SetTalentSummary(spec.t1,spec.t2,spec.t3)
          if spec.talents and IsSameSpec(spec.talents,current_spec) then
            button.isCurrentSpec = true
          end
        elseif button.canSave then -- if save but no load
          button:SetIcon("Interface\\Icons\\INV_Misc_QuestionMark")
          button:SetName("Spec "..button.index)
          button:SetTalentSummary("? | ? | ?")
        end
      end
    end


    -- if no gossip options occur we can't use the washer
    if not mainFrame.gossip_slots.reset then
      mainFrame.talentSummaryText:SetText("\n\n\n\nBrainwasher not available on this character.")
      for _,btn in talentButtons do
        btn:Hide()
      end
      mainFrame.resetButton:Hide()
      mainFrame.washerButton:Hide()
    else
      for _,btn in talentButtons do
        btn:Show()
      end
      mainFrame.resetButton:Show()
      mainFrame.washerButton:Show()
    end

    GossipFrame:SetAlpha(0) -- 'hide' but don't cause a GOSSIP_CLOSED
    mainFrame:Show()

  elseif event == "GOSSIP_CLOSED" then
    mainFrame:Hide()
  elseif event == "ADDON_LOADED" and arg1 == "BrainSaver" then
    BrainSaverDB = BrainSaverDB or {}
    BrainSaverDB.spec = BrainSaverDB.spec or {}
  end
end)
