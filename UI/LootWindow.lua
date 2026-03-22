---------------------------------------------------------------------------
-- Pirates Plunder – Loot Distribution UI
--   1) Loot-master window  (/pploot, /ppl)  – post items, view responses, award
--   2) Unified multi-item response popup – Need / Transmog / Pass per item
---------------------------------------------------------------------------
---@type PPAddon
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
    if not self:CanViewLootMaster() then
        self:Print("Only officers and the raid leader can access the loot master window.")
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
    f:SetWidth(800)
    f:SetHeight(500)
    f:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        PP.lootMasterWindow = nil
        PP._lmContainer = nil
    end)
    self.lootMasterWindow = f

    -- Make ESC close this window
    PP:RegisterEscFrame(f, "PPLootMasterFrame")

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
    -- Save scroll position before releasing (ReleaseChildren wipes it synchronously)
    local lmSt = container.status or container.localstatus
    local savedLmScroll = lmSt and lmSt.scrollvalue or 0
    container:ReleaseChildren()

    local me      = self:GetPlayerFullName()
    local canPost = self:CanPostLoot()

    -- ── Loot Queue ──────────────────────────────────────────────────────────
    if canPost then
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

    local lootQueue = PP.Repo.Loot:GetQueue()
    if #lootQueue > 0 then
        for i, qEntry in ipairs(lootQueue) do
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
        postAllBtn:SetText("Post All (" .. #lootQueue .. ")")
        postAllBtn:SetWidth(130)
        postAllBtn:SetCallback("OnClick", function()
            PP.Loot:PostAll()
        end)
        container:AddChild(postAllBtn)
    else
        local emptyQ = AceGUI:Create("Label")
        emptyQ:SetFullWidth(true)
        emptyQ:SetText("|cFF888888  Queue is empty.|r")
        container:AddChild(emptyQ)
    end
    end -- canPost: loot queue section

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

        -- Tooltip only when hovering the item name in the title bar
        local titleOverlay = CreateFrame("Frame", nil, itemGroup.frame)
        titleOverlay:SetPoint("TOPLEFT",  itemGroup.frame, "TOPLEFT",  14, -1)
        titleOverlay:SetPoint("TOPRIGHT", itemGroup.frame, "TOPRIGHT", -14, -1)
        titleOverlay:SetHeight(18)
        titleOverlay:EnableMouse(true)
        self:AddItemTooltip(titleOverlay, item.itemLink)

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

            local rh6 = AceGUI:Create("Label")
            rh6:SetText("|cFFFFD100Equipped|r")
            rh6:SetWidth(130)
            hdrRow:AddChild(rh6)

            local rh7 = AceGUI:Create("Label")
            rh7:SetText("|cFFFFD100Votes|r")
            rh7:SetWidth(55)
            hdrRow:AddChild(rh7)

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

                -- Equipped item comparison (NEED / MINOR only)
                -- Icons for each equipped item with individual tooltips.
                -- ilvl diff is computed here from the item being distributed
                -- vs each equipped link, so it never travels in messages.
                local hasComp = resp.equippedLinks ~= nil
                if hasComp then
                    local compGroup = AceGUI:Create("SimpleGroup")
                    compGroup:SetLayout("Flow")
                    compGroup:SetWidth(130)
                    compGroup.frame:EnableMouse(false)
                    rRow:AddChild(compGroup)

                    -- Compute best ilvl diff locally from the distributed item
                    local _, _, _, newIlvl = C_Item.GetItemInfo(item.itemLink)
                    local bestDiff = nil
                    if newIlvl and #resp.equippedLinks > 0 then
                        for _, eLink in ipairs(resp.equippedLinks) do
                            local _, _, _, eIlvl = C_Item.GetItemInfo(eLink)
                            if eIlvl then
                                local d = newIlvl - eIlvl
                                if bestDiff == nil or d > bestDiff then bestDiff = d end
                            end
                        end
                    end

                    -- One icon per equipped item, each with its own tooltip
                    for _, eLink in ipairs(resp.equippedLinks) do
                        local _, _, _, _, _, _, _, _, _, tex = C_Item.GetItemInfo(eLink)
                        local iconLbl = AceGUI:Create("Label")
                        iconLbl:SetWidth(20)
                        iconLbl:SetText(tex and ("|T" .. tex .. ":16:16|t") or "")
                        local capturedLink = eLink
                        iconLbl.frame:EnableMouse(true)
                        iconLbl.frame:SetScript("OnEnter", function(f)
                            GameTooltip:SetOwner(f, "ANCHOR_CURSOR")
                            GameTooltip:SetHyperlink(capturedLink)
                            GameTooltip:Show()
                        end)
                        iconLbl.frame:SetScript("OnLeave", function()
                            GameTooltip:Hide()
                        end)
                        compGroup:AddChild(iconLbl)
                    end

                    local diffLbl = AceGUI:Create("Label")
                    if bestDiff ~= nil then
                        local color = bestDiff > 0 and "|cFF00FF00"
                                   or bestDiff < 0 and "|cFFFF4444"
                                   or "|cFFAAAAAA"
                        local sign = bestDiff > 0 and "+" or ""
                        diffLbl:SetText(color .. sign .. bestDiff .. " ilvl|r")
                    else
                        diffLbl:SetText("|cFFAAAAAA(empty)|r")
                    end
                    diffLbl:SetWidth(70)
                    compGroup:AddChild(diffLbl)
                else
                    -- No comparison data: add a fixed-width spacer label so columns stay aligned
                    local spacer = AceGUI:Create("Label")
                    spacer:SetWidth(130)
                    spacer:SetText("")
                    rRow:AddChild(spacer)
                end

                -- Vote tally for this responder
                local voteCount = resp.voteCount or 0
                local voteCountLbl = AceGUI:Create("Label")
                voteCountLbl:SetText(voteCount > 0
                    and "|cFFFFD100" .. voteCount .. "|r"
                    or  "|cFF888888-|r")
                voteCountLbl:SetWidth(55)
                rRow:AddChild(voteCountLbl)

                -- Action buttons: poster gets Award / Free; observers get Vote
                local capturedKey  = item.key
                local capturedName = resp.fullName
                if item.postedBy == me then
                    local awardBtn = AceGUI:Create("Button")
                    awardBtn:SetText("Award")
                    awardBtn:SetWidth(70)
                    awardBtn:SetCallback("OnClick", function()
                        PP.Loot:Award(capturedKey, capturedName)
                    end)
                    rRow:AddChild(awardBtn)

                    local freeBtn = AceGUI:Create("Button")
                    freeBtn:SetText("|cFF00FF00Free|r")
                    freeBtn:SetWidth(60)
                    freeBtn:SetCallback("OnClick", function()
                        PP.Loot:Award(capturedKey, capturedName, true)
                    end)
                    rRow:AddChild(freeBtn)

                    local lootEntry = PP.Repo.Loot:GetEntry(item.key)
                    local myVote    = lootEntry and lootEntry.votes and lootEntry.votes[me]
                    local votedThis = myVote == resp.fullName
                    local voteBtn = AceGUI:Create("Button")
                    voteBtn:SetWidth(65)
                    voteBtn:SetText(votedThis and "|cFF00FF00Vote|r" or "Vote")
                    voteBtn:SetCallback("OnClick", function()
                        PP:CastVote(capturedKey, capturedName)
                    end)
                    rRow:AddChild(voteBtn)
                else
                    -- Observer (officer / RL who didn't post this item): one vote per item
                    local lootEntry = PP.Repo.Loot:GetEntry(item.key)
                    local myVote    = lootEntry and lootEntry.votes and lootEntry.votes[me]
                    local votedThis = myVote == resp.fullName
                    local voteBtn = AceGUI:Create("Button")
                    voteBtn:SetWidth(65)
                    voteBtn:SetText(votedThis and "|cFF00FF00Vote|r" or "Vote")
                    voteBtn:SetCallback("OnClick", function()
                        PP:CastVote(capturedKey, capturedName)
                    end)
                    rRow:AddChild(voteBtn)
                end
            end
        else
            local noResp = AceGUI:Create("Label")
            noResp:SetFullWidth(true)
            noResp:SetText("  Waiting for responses...")
            itemGroup:AddChild(noResp)
        end

        -- Who in the raid hasn't responded yet (also works in sandbox)
        if IsInRaid() or PP:IsSandbox() then
            local raidSet = PP.Roster:GetRaidMemberSet()
            local lootEntry = PP.Repo.Loot:GetEntry(item.key)
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

        -- Cancel button (poster only)
        if item.postedBy == me then
            local cancelBtn = AceGUI:Create("Button")
            cancelBtn:SetText("Cancel")
            cancelBtn:SetWidth(80)
            local capturedItemKey = item.key
            cancelBtn:SetCallback("OnClick", function()
                PP.Loot:Cancel(capturedItemKey)
            end)
            itemGroup:AddChild(cancelBtn)
        end
    end

    -- Pending trades section with clear buttons (poster's view only)
    local pendingTrades = PP.Repo.Loot:GetPendingTrades()
    if canPost and #pendingTrades > 0 then
        local tradeHead = AceGUI:Create("Heading")
        tradeHead:SetFullWidth(true)
        tradeHead:SetText("Pending Trades")
        container:AddChild(tradeHead)

        for tIdx, trade in ipairs(pendingTrades) do
            local tRow = AceGUI:Create("SimpleGroup")
            tRow:SetFullWidth(true)
            tRow:SetLayout("Flow")
            container:AddChild(tRow)

            local tLabel = AceGUI:Create("Label")
            tLabel:SetText("  " .. (trade.itemLink or "Item") .. "  ->  " .. self:GetShortName(trade.awardedTo))
            tLabel:SetWidth(450)
            tRow:AddChild(tLabel)

            -- Tooltip on trade label
            self:AddItemTooltip(tLabel.frame, trade.itemLink)

            local clearBtn = AceGUI:Create("Button")
            clearBtn:SetText("Clear")
            clearBtn:SetWidth(80)
            local capturedIdx = tIdx
            clearBtn:SetCallback("OnClick", function()
                PP.Repo.Loot:RemovePendingTrade(capturedIdx)
                PP:RefreshLootMasterWindow()
            end)
            tRow:AddChild(clearBtn)
        end

        local clearAllBtn = AceGUI:Create("Button")
        clearAllBtn:SetText("Clear All Trades")
        clearAllBtn:SetWidth(140)
        clearAllBtn:SetCallback("OnClick", function()
            wipe(PP.Repo.Loot:GetPendingTrades())
            PP.Repo.Loot:Save()
            PP:RefreshLootMasterWindow()
        end)
        container:AddChild(clearAllBtn)
    end

    -- Force the ScrollFrame to recalculate its scroll height after all
    -- children (including nested InlineGroups) have been laid out.
    container:DoLayout()
    -- Restore scroll position after layout settles
    if savedLmScroll > 0 then
        C_Timer.After(0, function() if container.SetScroll then container:SetScroll(savedLmScroll) end end)
    end
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

    -- Add to UISpecialFrames so ESC hides the frame
    tinsert(UISpecialFrames, "PPLootResponseFrame")

    -- When the frame is hidden (by ESC or the X button), show the loot bars
    f:SetScript("OnHide", function()
        PP:ShowLootBars()
    end)

    -- Hide bars whenever the full response frame is visible
    self:HideLootBars()

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
        -- OnHide script fires on Hide() and calls ShowLootReopenButton()
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

    -- Frame width depends on whether any pending item has transmog enabled.
    -- We check the individual entry flags (synced from the poster) rather than
    -- the local setting, which may differ from the raid leader's.
    local anyTmog = false
    for _, entry in pairs(PP.Repo.Loot:GetAll()) do
        if not entry.awarded and entry.allowTransmog ~= false then
            anyTmog = true
            break
        end
    end
    local numBtns = anyTmog and 4 or 3
    local contentWidth = textX + numBtns * btnWidth + (numBtns - 1) * 6
    local frameWidth   = contentWidth + iconPad + 24   -- matching right margin
    f:SetWidth(frameWidth)

    for key, entry in pairs(PP.Repo.Loot:GetAll()) do
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
                PP.Loot:SubmitResponse(capturedKey, PP.RESPONSE.NEED)
            end)

            local minorBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            minorBtn:SetSize(btnWidth, btnHeight)
            minorBtn:SetPoint("LEFT", needBtn, "RIGHT", 6, 0)
            minorBtn:SetText("Minor")
            if myResponse == PP.RESPONSE.MINOR then
                minorBtn:GetFontString():SetTextColor(0, 0.8, 1)
            end
            minorBtn:SetScript("OnClick", function()
                PP.Loot:SubmitResponse(capturedKey, PP.RESPONSE.MINOR)
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
                PP.Loot:SubmitResponse(capturedKey, PP.RESPONSE.TRANSMOG)
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
                PP.Loot:SubmitResponse(capturedKey, PP.RESPONSE.PASS)
            end)

            row:Show()
            yOffset = yOffset + rowHeight + 4
        end
    end

    if itemCount == 0 then
        f:Hide()
        self:HideLootBars()
        return
    end

    -- Resize frame to fit all items
    local totalHeight = 40 + yOffset + 8
    f:SetHeight(math.max(80, totalHeight))
    container:SetHeight(yOffset)
    -- Do NOT call f:Show() here — only ShowLootResponseFrame() should open the frame.
    -- Refreshing should never reopen a frame the player has minimised.

    -- Keep bars in sync when visible but response frame is not
    if self.lootBarsFrame and self.lootBarsFrame:IsShown() then
        self:RefreshLootBars()
    end
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
    self:HideLootBars()
end

-- =========================================================================
--  LOOT BARS  – per-item floating bars shown when response frame is hidden
--  but items are still pending distribution. All bars share one draggable
--  anchor; position is persisted via LibWindow-1.1.
-- =========================================================================

function PP:CreateLootBarsFrame()
    if self.lootBarsFrame then return end
    local LibWindow = LibStub("LibWindow-1.1")

    local f = CreateFrame("Frame", "PPLootBarsFrame", UIParent, "BackdropTemplate")
    f:SetSize(212, 12)  -- height grows dynamically in RefreshLootBars
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.85)

    LibWindow.RegisterConfig(f, PP.db.global.lootBarsAnchor)
    LibWindow.MakeDraggable(f)
    LibWindow.RestorePosition(f)

    f:Hide()
    self.lootBarsFrame = f
end

function PP:RefreshLootBars()
    local f = self.lootBarsFrame
    if not f then return end

    local LibWindow = LibStub("LibWindow-1.1")

    -- Collect and hide all existing bars without unparenting (preserves the pool)
    local bars = { f:GetChildren() }
    for _, bar in ipairs(bars) do bar:Hide() end

    local me = self:GetPlayerFullName()
    local barW, barH = 200, 22
    local padX, padTop, padBottom = 6, 6, 6
    local barGap = 2
    local yOffset = padTop
    local count = 0

    for key, entry in pairs(PP.Repo.Loot:GetAll()) do
        if not entry.awarded then
            count = count + 1
            local myResponse = entry.responses[me] and entry.responses[me].response or nil

            -- Reuse existing bar or create a new one
            local bar = bars[count]
            if not bar then
                bar = CreateFrame("Button", nil, f)
                bar:SetSize(barW, barH)
                bar:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight")
                bar:RegisterForDrag("LeftButton")
                bar:SetScript("OnDragStart", function() f:StartMoving() end)
                bar:SetScript("OnDragStop", function()
                    f:StopMovingOrSizing()
                    LibWindow.SavePosition(f)
                end)
                bar:SetScript("OnClick", function()
                    f:Hide()
                    PP:ShowLootResponseFrame()
                end)
                local icon = bar:CreateTexture(nil, "OVERLAY")
                icon:SetSize(16, 16)
                icon:SetPoint("LEFT", bar, "LEFT", 2, 0)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                bar._icon = icon
                local nameStr = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                nameStr:SetPoint("LEFT", bar, "LEFT", 22, 0)
                nameStr:SetPoint("RIGHT", bar, "RIGHT", -42, 0)
                nameStr:SetJustifyH("LEFT")
                nameStr:SetJustifyV("MIDDLE")
                bar._nameStr = nameStr
                local respStr = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                respStr:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
                respStr:SetJustifyH("RIGHT")
                respStr:SetJustifyV("MIDDLE")
                bar._respStr = respStr
                bars[count] = bar
            end

            -- Update position
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", f, "TOPLEFT", padX, -yOffset)

            -- Update icon
            local iconTex = (entry.itemID and C_Item.GetItemIconByID(entry.itemID))
            if not iconTex and entry.itemLink then
                local _, _, _, _, tex = GetItemInfoInstant(entry.itemLink)
                iconTex = tex
            end
            if iconTex then
                bar._icon:SetTexture(iconTex)
                bar._icon:Show()
            else
                bar._icon:Hide()
            end

            -- Update name and response label
            bar._nameStr:SetText(entry.itemLink or "Unknown")

            if myResponse == PP.RESPONSE.NEED then
                bar._respStr:SetText("|cFF00FF00Need|r")
            elseif myResponse == PP.RESPONSE.MINOR then
                bar._respStr:SetText("|cFF00CCFFMinor|r")
            elseif myResponse == PP.RESPONSE.TRANSMOG then
                bar._respStr:SetText("|cFFFF8800Tmog|r")
            elseif myResponse == PP.RESPONSE.PASS then
                bar._respStr:SetText("|cFF888888Pass|r")
            else
                bar._respStr:SetText("|cFFFFFF00?|r")
            end

            bar:Show()
            yOffset = yOffset + barH + barGap
        end
    end

    if count == 0 then
        f:Hide()
        return
    end

    f:SetSize(212, yOffset - barGap + padBottom)
end

function PP:ShowLootBars()
    local hasItems = false
    for _, entry in pairs(PP.Repo.Loot:GetAll()) do
        if not entry.awarded then hasItems = true; break end
    end
    if not hasItems then return end
    self:CreateLootBarsFrame()
    self:RefreshLootBars()
    self.lootBarsFrame:Show()
end

function PP:HideLootBars()
    if self.lootBarsFrame then
        self.lootBarsFrame:Hide()
    end
end
