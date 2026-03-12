---------------------------------------------------------------------------
-- Pirates Plunder – Loot Distribution UI
--   1) Loot-master window  (/pploot, /ppl)  – post items, view responses, award
--   2) Unified multi-item response popup – Need / Transmog / Pass per item
---------------------------------------------------------------------------
local PP  = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")
local AceGUI = PP.AceGUI

-- =========================================================================
--  LOOT-MASTER WINDOW
-- =========================================================================

function PP:ToggleLootMasterWindow()
    if self.lootMasterWindow then
        self.lootMasterWindow:Release()
        self.lootMasterWindow = nil
        return
    end
    self:CreateLootMasterWindow()
end

function PP:RefreshLootMasterWindow()
    if not self.lootMasterWindow then return end
    self:DrawLootMasterContent(self._lmContainer)
end

function PP:CreateLootMasterWindow()
    local f = AceGUI:Create("Frame")
    f:SetTitle("Pirates Plunder – Loot Master")
    f:SetLayout("Fill")
    f:SetWidth(650)
    f:SetHeight(500)
    f:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        PP.lootMasterWindow = nil
        PP._lmContainer = nil
    end)
    self.lootMasterWindow = f

    -- Make ESC close this window
    local frameName = "PPLootMasterFrame"
    _G[frameName] = f.frame
    tinsert(UISpecialFrames, frameName)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    scroll:SetLayout("List")
    f:AddChild(scroll)
    self._lmContainer = scroll

    self:DrawLootMasterContent(scroll)
end

function PP:DrawLootMasterContent(container)
    if not container then return end
    container:ReleaseChildren()

    -- ── Loot Queue ──────────────────────────────────────────────────────────
    local queueHead = AceGUI:Create("Heading")
    queueHead:SetFullWidth(true)
    queueHead:SetText("Loot Queue")
    container:AddChild(queueHead)

    local hintLbl = AceGUI:Create("Label")
    hintLbl:SetFullWidth(true)
    hintLbl:SetText("|cFF888888Alt+right-click bag items, or link an item below, then click Post All.|r")
    container:AddChild(hintLbl)

    local inputGroup = AceGUI:Create("SimpleGroup")
    inputGroup:SetFullWidth(true)
    inputGroup:SetLayout("Flow")
    container:AddChild(inputGroup)

    local editBox = AceGUI:Create("EditBox")
    editBox:SetLabel("Link Item (shift-click)")
    editBox:SetWidth(310)
    editBox:SetCallback("OnEnterPressed", function(widget, _, text)
        if text and text:trim() ~= "" then
            PP:AddToLootQueue(text:trim())
            widget:SetText("")
        end
    end)
    inputGroup:AddChild(editBox)

    local addBtn = AceGUI:Create("Button")
    addBtn:SetText("Add")
    addBtn:SetWidth(60)
    addBtn:SetCallback("OnClick", function()
        local text = editBox:GetText()
        if text and text:trim() ~= "" then
            PP:AddToLootQueue(text:trim())
            editBox:SetText("")
        end
    end)
    inputGroup:AddChild(addBtn)

    if #self.lootQueue > 0 then
        for i, qEntry in ipairs(self.lootQueue) do
            local qRow = AceGUI:Create("SimpleGroup")
            qRow:SetFullWidth(true)
            qRow:SetLayout("Flow")
            container:AddChild(qRow)

            local qLabel = AceGUI:Create("Label")
            qLabel:SetText("  " .. (qEntry.itemLink or "Unknown Item"))
            qLabel:SetWidth(420)
            qRow:AddChild(qLabel)
            self:AddItemTooltip(qLabel.frame, qEntry.itemLink)

            local removeBtn = AceGUI:Create("Button")
            removeBtn:SetText("Remove")
            removeBtn:SetWidth(80)
            local capturedIdx = i
            removeBtn:SetCallback("OnClick", function()
                PP:RemoveFromLootQueue(capturedIdx)
            end)
            qRow:AddChild(removeBtn)
        end

        local postAllBtn = AceGUI:Create("Button")
        postAllBtn:SetText("Post All (" .. #self.lootQueue .. ")")
        postAllBtn:SetWidth(130)
        postAllBtn:SetCallback("OnClick", function()
            PP:PostLootQueue()
        end)
        container:AddChild(postAllBtn)
    else
        local emptyQ = AceGUI:Create("Label")
        emptyQ:SetFullWidth(true)
        emptyQ:SetText("|cFF888888  Queue is empty.|r")
        container:AddChild(emptyQ)
    end

    -- ── Items Being Distributed ─────────────────────────────────────────────
    local heading = AceGUI:Create("Heading")
    heading:SetFullWidth(true)
    heading:SetText("Items Being Distributed")
    container:AddChild(heading)

    local pending = self:GetPendingLootList()

    if #pending == 0 then
        local empty = AceGUI:Create("Label")
        empty:SetFullWidth(true)
        empty:SetText("\n  No items currently being distributed.")
        container:AddChild(empty)
    end

    for _, item in ipairs(pending) do
        -- Item header with tooltip support
        local itemGroup = AceGUI:Create("InlineGroup")
        itemGroup:SetFullWidth(true)
        itemGroup:SetTitle(item.itemLink or "Item")
        itemGroup:SetLayout("List")
        container:AddChild(itemGroup)

        -- Tooltip on the item group title area
        self:AddItemTooltip(itemGroup.frame, item.itemLink)

        -- Response count info
        local infoRow = AceGUI:Create("SimpleGroup")
        infoRow:SetFullWidth(true)
        infoRow:SetLayout("Flow")
        itemGroup:AddChild(infoRow)

        local allowTmogGlobal = PP.db.global.allowTransmogRolls ~= false
        local countLabel = AceGUI:Create("Label")
        countLabel:SetText("Responses: " .. item.responseCount .. "  |  By: " .. self:GetShortName(item.postedBy)
            .. "  |  Transmog: " .. (allowTmogGlobal and "|cFF00FF00ON|r" or "|cFFFF4400OFF|r"))
        countLabel:SetFullWidth(true)
        infoRow:AddChild(countLabel)

        -- Response list (sorted)
        local responses = self:GetSortedResponses(item.key)

        if #responses > 0 then
            -- Column headers
            local hdrRow = AceGUI:Create("SimpleGroup")
            hdrRow:SetFullWidth(true)
            hdrRow:SetLayout("Flow")
            itemGroup:AddChild(hdrRow)

            local rh1 = AceGUI:Create("Label")
            rh1:SetText("|cFFFFD100#|r")
            rh1:SetWidth(25)
            hdrRow:AddChild(rh1)

            local rh2 = AceGUI:Create("Label")
            rh2:SetText("|cFFFFD100Player|r")
            rh2:SetWidth(140)
            hdrRow:AddChild(rh2)

            local rh3 = AceGUI:Create("Label")
            rh3:SetText("|cFFFFD100Score|r")
            rh3:SetWidth(50)
            hdrRow:AddChild(rh3)

            local rh4 = AceGUI:Create("Label")
            rh4:SetText("|cFFFFD100Roll|r")
            rh4:SetWidth(45)
            hdrRow:AddChild(rh4)

            local rh5 = AceGUI:Create("Label")
            rh5:SetText("|cFFFFD100Response|r")
            rh5:SetWidth(90)
            hdrRow:AddChild(rh5)

            for rIdx, resp in ipairs(responses) do
                local rRow = AceGUI:Create("SimpleGroup")
                rRow:SetFullWidth(true)
                rRow:SetLayout("Flow")
                itemGroup:AddChild(rRow)

                local rl1 = AceGUI:Create("Label")
                rl1:SetText(tostring(rIdx))
                rl1:SetWidth(25)
                rRow:AddChild(rl1)

                local rl2 = AceGUI:Create("Label")
                rl2:SetText(resp.name)
                rl2:SetWidth(140)
                rRow:AddChild(rl2)

                local rl3 = AceGUI:Create("Label")
                rl3:SetText("|cFFFFFF00" .. tostring(resp.score) .. "|r")
                rl3:SetWidth(50)
                rRow:AddChild(rl3)

                local rl4 = AceGUI:Create("Label")
                rl4:SetText(tostring(resp.roll))
                rl4:SetWidth(45)
                rRow:AddChild(rl4)

                local respColor = resp.response == PP.RESPONSE.NEED    and "|cFF00FF00"
                               or resp.response == PP.RESPONSE.MINOR   and "|cFF00CCFF"
                               or "|cFFFF8800"
                local rl5 = AceGUI:Create("Label")
                rl5:SetText(respColor .. resp.response .. "|r")
                rl5:SetWidth(90)
                rRow:AddChild(rl5)

                local awardBtn = AceGUI:Create("Button")
                awardBtn:SetText("Award")
                awardBtn:SetWidth(70)
                local capturedKey  = item.key
                local capturedName = resp.fullName
                awardBtn:SetCallback("OnClick", function()
                    PP:AwardItem(capturedKey, capturedName)
                end)
                rRow:AddChild(awardBtn)
            end
        else
            local noResp = AceGUI:Create("Label")
            noResp:SetFullWidth(true)
            noResp:SetText("  Waiting for responses...")
            itemGroup:AddChild(noResp)
        end

        -- Who in the raid hasn't responded yet (also works in sandbox)
        if IsInRaid() or PP:IsSandbox() then
            local raidSet = self:GetRaidMemberSet()
            local lootEntry = self.pendingLoot[item.key]
            local nonResponders = {}
            if lootEntry then
                for fullName in pairs(raidSet) do
                    if not lootEntry.responses[fullName] then
                        nonResponders[#nonResponders + 1] = self:GetShortName(fullName)
                    end
                end
            end
            if #nonResponders > 0 then
                table.sort(nonResponders)
                local waitLabel = AceGUI:Create("Label")
                waitLabel:SetFullWidth(true)
                waitLabel:SetText("|cFFFFAA00Waiting: |r" .. table.concat(nonResponders, ", "))
                itemGroup:AddChild(waitLabel)
            elseif lootEntry and next(raidSet) then
                local allLabel = AceGUI:Create("Label")
                allLabel:SetFullWidth(true)
                allLabel:SetText("|cFF00FF00All raid members have responded.|r")
                itemGroup:AddChild(allLabel)
            end
        end

        -- Cancel button
        local cancelBtn = AceGUI:Create("Button")
        cancelBtn:SetText("Cancel")
        cancelBtn:SetWidth(80)
        local capturedItemKey = item.key
        cancelBtn:SetCallback("OnClick", function()
            PP:CancelLoot(capturedItemKey)
        end)
        itemGroup:AddChild(cancelBtn)
    end

    -- Pending trades section with clear buttons
    if #self.pendingTrades > 0 then
        local tradeHead = AceGUI:Create("Heading")
        tradeHead:SetFullWidth(true)
        tradeHead:SetText("Pending Trades")
        container:AddChild(tradeHead)

        for tIdx, trade in ipairs(self.pendingTrades) do
            local tRow = AceGUI:Create("SimpleGroup")
            tRow:SetFullWidth(true)
            tRow:SetLayout("Flow")
            container:AddChild(tRow)

            local tLabel = AceGUI:Create("Label")
            tLabel:SetText("  " .. (trade.itemLink or "Item") .. "  →  " .. self:GetShortName(trade.awardedTo))
            tLabel:SetWidth(450)
            tRow:AddChild(tLabel)

            -- Tooltip on trade label
            self:AddItemTooltip(tLabel.frame, trade.itemLink)

            local clearBtn = AceGUI:Create("Button")
            clearBtn:SetText("Clear")
            clearBtn:SetWidth(60)
            local capturedIdx = tIdx
            clearBtn:SetCallback("OnClick", function()
                table.remove(PP.pendingTrades, capturedIdx)
                PP:RefreshLootMasterWindow()
            end)
            tRow:AddChild(clearBtn)
        end

        local clearAllBtn = AceGUI:Create("Button")
        clearAllBtn:SetText("Clear All Trades")
        clearAllBtn:SetWidth(140)
        clearAllBtn:SetCallback("OnClick", function()
            wipe(PP.pendingTrades)
            PP:RefreshLootMasterWindow()
        end)
        container:AddChild(clearAllBtn)
    end

    -- Force the ScrollFrame to recalculate its scroll height after all
    -- children (including nested InlineGroups) have been laid out.
    container:DoLayout()
end

-- =========================================================================
--  ITEM TOOLTIP HELPER
-- =========================================================================
function PP:AddItemTooltip(frame, itemLink)
    if not frame or not itemLink then return end
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(itemLink)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- =========================================================================
--  UNIFIED MULTI-ITEM RESPONSE FRAME
--  Shows ALL pending loot items. Players can respond or change their
--  response. New items are added dynamically. NOT dismissed by ESC.
-- =========================================================================

function PP:ShowLootResponseFrame()
    if self.lootResponseFrame then
        self:RefreshLootResponseFrame()
        self.lootResponseFrame:Show()
        return
    end

    local f = CreateFrame("Frame", "PPLootResponseFrame", UIParent, "BackdropTemplate")
    f:SetSize(370, 80) -- grows dynamically
    f:SetPoint("TOP", UIParent, "TOP", 0, -100)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 24,
        insets   = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    f:SetBackdropColor(0, 0, 0, 0.92)

    -- DO NOT add to UISpecialFrames — ESC should NOT close this

    -- Hide reopen btn whenever the full response frame is visible
    self:HideLootReopenButton()

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cFF33CCFF[Pirates Plunder]|r Loot")
    f._title = title

    -- Close / minimize button (top right X)
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        f:Hide()
        PP:ShowLootReopenButton()
    end)

    -- Scroll-child container for item rows
    f._itemContainer = CreateFrame("Frame", nil, f)
    f._itemContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -32)
    f._itemContainer:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f._itemContainer:SetHeight(1)

    self.lootResponseFrame = f
    self:RefreshLootResponseFrame()
    f:Show()
end

function PP:RefreshLootResponseFrame()
    local f = self.lootResponseFrame
    if not f then return end

    local container = f._itemContainer
    -- Clear old children
    local kids = { container:GetChildren() }
    for _, child in ipairs(kids) do
        child:Hide()
        child:SetParent(nil)
    end

    local me = self:GetPlayerFullName()
    local yOffset = 0
    local btnWidth, btnHeight = 72, 20
    local iconPad    = 8     -- left padding before the icon
    local iconWidth  = 28
    local textGap    = 4     -- gap between icon right edge and text start
    local textX      = iconPad + iconWidth + textGap  -- 40
    local textH      = 30    -- fixed text zone height (fits ~2 wrapped lines)
    local btnGap     = 4     -- vertical gap between text zone and buttons
    local rowPadBot  = 6     -- bottom padding per row
    local rowHeight  = textH + btnGap + btnHeight + rowPadBot  -- 60
    local itemCount  = 0

    -- Frame width depends on whether transmog is globally enabled.
    -- textX + N buttons * btnWidth + (N-1) gaps * 6 + outer margins
    local tmogGlobal = PP.db.global.allowTransmogRolls ~= false
    local numBtns = tmogGlobal and 4 or 3
    local contentWidth = textX + numBtns * btnWidth + (numBtns - 1) * 6
    local frameWidth   = contentWidth + iconPad + 24   -- matching right margin
    f:SetWidth(frameWidth)

    for key, entry in pairs(self.pendingLoot) do
        if not entry.awarded then
            itemCount = itemCount + 1
            local myResponse = entry.responses[me] and entry.responses[me].response or nil

            -- Row frame for this item
            local row = CreateFrame("Frame", nil, container)
            row:SetSize(contentWidth, rowHeight)
            row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -yOffset)

            -- Item icon (with left padding)
            local iconTex = (entry.itemID and C_Item.GetItemIconByID(entry.itemID))
            if not iconTex and entry.itemLink then
                local _, _, _, _, tex = GetItemInfoInstant(entry.itemLink)
                iconTex = tex
            end
            if iconTex then
                local icon = row:CreateTexture(nil, "OVERLAY")
                icon:SetSize(iconWidth, iconWidth)
                icon:SetPoint("TOPLEFT", row, "TOPLEFT", iconPad, -1)
                icon:SetTexture(iconTex)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end

            -- Item text: fixed height so buttons always sit below it
            local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            itemText:SetPoint("TOPLEFT", row, "TOPLEFT", textX, 0)
            itemText:SetWidth(contentWidth - textX)
            itemText:SetHeight(textH)
            itemText:SetJustifyH("LEFT")
            itemText:SetJustifyV("TOP")
            local displayText = entry.itemLink or "Unknown Item"
            if myResponse then
                local color = myResponse == PP.RESPONSE.NEED     and "|cFF00FF00"
                           or myResponse == PP.RESPONSE.MINOR    and "|cFF00CCFF"
                           or myResponse == PP.RESPONSE.TRANSMOG and "|cFFFF8800"
                           or "|cFF888888"
                displayText = displayText .. "  " .. color .. "[" .. myResponse .. "]|r"
            end
            itemText:SetText(displayText)

            -- Tooltip on the item row
            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self)
                if entry.itemLink then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(entry.itemLink)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Response buttons: anchored below the fixed text zone, never overlap it
            local btnY = -(textH + btnGap)
            local capturedKey = key

            local needBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            needBtn:SetSize(btnWidth, btnHeight)
            needBtn:SetPoint("TOPLEFT", row, "TOPLEFT", textX, btnY)
            needBtn:SetText("Need")
            if myResponse == PP.RESPONSE.NEED then
                needBtn:GetFontString():SetTextColor(0, 1, 0)
            end
            needBtn:SetScript("OnClick", function()
                PP:ExpressInterest(capturedKey, PP.RESPONSE.NEED)
            end)

            local minorBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            minorBtn:SetSize(btnWidth, btnHeight)
            minorBtn:SetPoint("LEFT", needBtn, "RIGHT", 6, 0)
            minorBtn:SetText("Minor")
            if myResponse == PP.RESPONSE.MINOR then
                minorBtn:GetFontString():SetTextColor(0, 0.8, 1)
            end
            minorBtn:SetScript("OnClick", function()
                PP:ExpressInterest(capturedKey, PP.RESPONSE.MINOR)
            end)

            local showTmog = entry.allowTransmog ~= false

            local tmogBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            tmogBtn:SetSize(btnWidth, btnHeight)
            tmogBtn:SetPoint("LEFT", minorBtn, "RIGHT", 6, 0)
            tmogBtn:SetText("Transmog")
            if myResponse == PP.RESPONSE.TRANSMOG then
                tmogBtn:GetFontString():SetTextColor(1, 0.53, 0)
            end
            if not showTmog then
                tmogBtn:Hide()
            end
            tmogBtn:SetScript("OnClick", function()
                PP:ExpressInterest(capturedKey, PP.RESPONSE.TRANSMOG)
            end)

            local passBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            passBtn:SetSize(btnWidth, btnHeight)
            if showTmog then
                passBtn:SetPoint("LEFT", tmogBtn, "RIGHT", 6, 0)
            else
                passBtn:SetPoint("LEFT", minorBtn, "RIGHT", 6, 0)
            end
            passBtn:SetText("Pass")
            if myResponse == PP.RESPONSE.PASS then
                passBtn:GetFontString():SetTextColor(0.5, 0.5, 0.5)
            end
            passBtn:SetScript("OnClick", function()
                PP:ExpressInterest(capturedKey, PP.RESPONSE.PASS)
            end)

            row:Show()
            yOffset = yOffset + rowHeight + 4
        end
    end

    if itemCount == 0 then
        f:Hide()
        self:HideLootReopenButton()
        return
    end

    -- Resize frame to fit all items
    local totalHeight = 40 + yOffset + 8
    f:SetHeight(math.max(80, totalHeight))
    container:SetHeight(yOffset)
    f:Show()
end

-- Legacy redirect — still called from Sync.lua HandleLootPost
function PP:ShowLootPopup(key, itemLink)
    self:ShowLootResponseFrame()
end

-- Close all popups (called during raid end)
function PP:CloseLootPopups()
    for key, frame in pairs(self.lootPopups) do
        if frame and frame.Hide then frame:Hide() end
    end
    wipe(self.lootPopups)
    if self.lootResponseFrame then
        self.lootResponseFrame:Hide()
    end
    self:HideLootReopenButton()
end

-- =========================================================================
--  REOPEN BUTTON  – tiny floating button shown when response frame is hidden
--  but items are still pending distribution
-- =========================================================================

function PP:CreateLootReopenButton()
    if self.lootReopenBtn then return end
    local f = CreateFrame("Frame", "PPLootReopenFrame", UIParent, "BackdropTemplate")
    f:SetSize(164, 46)  -- larger than the button so there's a draggable border
    f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -230, 100)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 18,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.9)

    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetSize(128, 22)
    btn:SetPoint("CENTER")
    btn:SetText("|cFF33CCFF▸|r PP Loot")
    btn:SetScript("OnClick", function()
        f:Hide()
        PP:ShowLootResponseFrame()
    end)

    f:Hide()
    self.lootReopenBtn = f
end

function PP:ShowLootReopenButton()
    -- Only show if unawarded items are still pending
    local hasItems = false
    for _, entry in pairs(self.pendingLoot) do
        if not entry.awarded then hasItems = true; break end
    end
    if not hasItems then return end
    self:CreateLootReopenButton()
    self.lootReopenBtn:Show()
end

function PP:HideLootReopenButton()
    if self.lootReopenBtn then
        self.lootReopenBtn:Hide()
    end
end
