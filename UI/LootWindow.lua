local PP  = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")
local Kit = PP.Kit

local function shortItemName(link)
    return (link and link:match("%[(.-)%]")) or link or "Unknown Item"
end

local function truncateToWidth(fontString, text, maxWidth)
    fontString:SetText(text)
    if fontString:GetStringWidth() <= maxWidth then return text end
    local lo, hi = 0, #text
    while lo < hi do
        local mid = math.ceil((lo + hi) / 2)
        fontString:SetText(text:sub(1, mid) .. "...")
        if fontString:GetStringWidth() <= maxWidth then
            lo = mid
        else
            hi = mid - 1
        end
    end
    local result = text:sub(1, lo) .. "..."
    fontString:SetText(result)
    return result
end

local function lootEntrySortLess(a, b)
    local ta, ia = a.key:match(":([%d%.]+):(%d+)$")
    local tb, ib = b.key:match(":([%d%.]+):(%d+)$")
    ta, ia = tonumber(ta) or 0, tonumber(ia) or 0
    tb, ib = tonumber(tb) or 0, tonumber(ib) or 0
    if ta == tb then return ia < ib end
    return ta < tb
end

function PP:AddItemTooltip(frame, itemLink)
    if not frame or not itemLink then return end
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(itemLink)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- Loot-master window
---------------------------------------------------------------------------
function PP:ToggleLootMasterWindow()
    if self.lootMasterWindow then
        self.lootMasterWindow:Hide()
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
    self:DrawLootMasterContent()
end

function PP:CreateLootMasterWindow()
    local f = Kit:Window("Pirates Plunder - Loot Master", 860, 500)
    f:SetOnClose(function()
        f:Hide()
        PP.lootMasterWindow = nil
        PP._lmList = nil
    end)
    self.lootMasterWindow = f
    PP:RegisterEscFrame(f, "PPLootMasterFrame")
    self._lmList = Kit:ScrollList(f.body)
    self._lmList.frame:SetAllPoints(f.body)
    self:DrawLootMasterContent()
end

local function itemBlock(parent, item, index)
    local block = Kit:Panel(parent)
    local titleBar = CreateFrame("Frame", nil, block)
    titleBar:SetPoint("TOPLEFT", block, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", block, "TOPRIGHT")
    titleBar:SetHeight(20)
    Kit:Fill(titleBar, Kit.Palette.panelLight)
    local titleLbl = Kit:Label(titleBar, item.itemLink or "Item", "head")
    titleLbl:SetPoint("LEFT", titleBar, "LEFT", 8, 0)
    PP:AddItemTooltip(titleBar, item.itemLink)
    block._titleBar = titleBar
    block._y = -26
    return block
end

local function blockAdd(block, widget, y, x)
    x = x or 8
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", block, "TOPLEFT", x, block._y)
    widget:SetPoint("TOPRIGHT", block, "TOPRIGHT", -x, block._y)
    block._y = block._y - y
end

function PP:DrawLootMasterContent()
    if not self.lootMasterWindow or not self._lmList then return end
    local list = self._lmList
    local content = list.child
    list:Clear()

    local me      = self:GetPlayerFullName()
    local canPost = self:CanPostLoot()

    if canPost then
        list:Add(Kit:Heading(content, "Loot Queue"), 20)
        local hint = Kit:Label(content, "|cFF888888Alt+right-click bag items, or link an item below, then click Post All.|r", "small")
        list:Add(hint, 16)

        local inputRow = Kit:Row(content, 24)
        local editBox
        editBox = Kit:EditBox(inputRow, 320, function(text)
            if text and text:trim() ~= "" then
                PP:AddToLootQueue(text:trim())
                editBox:SetText("")
            end
        end)
        editBox:SetPoint("LEFT", inputRow, "LEFT", 0, 0)
        local addBtn = Kit:Button(inputRow, "Add", function()
            local text = editBox:GetText()
            if text and text:trim() ~= "" then
                PP:AddToLootQueue(text:trim())
                editBox:SetText("")
            end
        end)
        addBtn:SetSize(60, 22)
        addBtn:SetPoint("LEFT", editBox, "RIGHT", 6, 0)
        list:Add(inputRow, 24)

        local queue = PP.Repo.Loot:GetQueue()
        if #queue > 0 then
            for i, qEntry in ipairs(queue) do
                local qRow = Kit:Row(content, 22)
                local qLbl = Kit:Label(qRow, qEntry.itemLink or "Unknown Item", "body")
                qLbl:SetPoint("LEFT", qRow, "LEFT", 0, 0)
                PP:AddItemTooltip(qRow, qEntry.itemLink)
                local rmBtn = Kit:Button(qRow, "Remove", function() PP:RemoveFromLootQueue(i) end)
                rmBtn:SetSize(80, 20)
                rmBtn:SetPoint("RIGHT", qRow, "RIGHT", 0, 0)
                list:Add(qRow, 22)
            end
            local postAllBtn = Kit:Button(content, "Post All (" .. #queue .. ")", function()
                PP.Loot:PostAll()
            end)
            postAllBtn:SetSize(130, 22)
            list:Add(postAllBtn, 22, 14, false)
        else
            list:Add(Kit:Label(content, "|cFF888888Queue is empty.|r", "small"), 16, 14)
        end
    end

    list:Add(Kit:Heading(content, "Items Being Distributed"), 20)

    local pending = self:GetPendingLootList()
    table.sort(pending, lootEntrySortLess)

    if #pending == 0 then
        list:Add(Kit:Label(content, "No items currently being distributed.", "small"), 20)
    end

    local allowTmogGlobal = PP.db.global.allowTransmogRolls ~= false
    for idx, item in ipairs(pending) do
        local responses = self:GetSortedResponses(item.key)
        local rowCount = math.max(#responses, 1)
        local blockH = 26 + 20 + 4 + (#responses > 0 and 20 or 0) + rowCount * 22 + 24
        local extra = 0
        local raidSet, nonResponders = nil, nil
        if IsInRaid() or PP:IsSandbox() then
            raidSet = PP.Roster:GetRaidMemberSet()
            local lootEntry = PP.Repo.Loot:GetEntry(item.key)
            nonResponders = {}
            if lootEntry then
                for fullName in pairs(raidSet) do
                    if not lootEntry.responses[fullName] then
                        nonResponders[#nonResponders + 1] = self:GetShortName(fullName)
                    end
                end
            end
            if #nonResponders > 0 or next(raidSet) then extra = extra + 18 end
        end
        if item.postedBy == me then extra = extra + 26 end
        blockH = blockH + extra

        local block = itemBlock(content, item, idx)

        local infoLbl = Kit:Label(block, "Responses: " .. item.responseCount .. "  |  By: "
            .. self:GetShortName(item.postedBy) .. "  |  Transmog: "
            .. (allowTmogGlobal and "|cFF00FF00ON|r" or "|cFFFF4400OFF|r"), "small")
        blockAdd(block, infoLbl, 20)

        if #responses > 0 then
            local hdr = Kit:Row(block, 18)
            local cols = { {t="#",w=25}, {t="Player",w=140}, {t="Score",w=50}, {t="Roll",w=45}, {t="Response",w=90}, {t="Equipped",w=130}, {t="Votes",w=55} }
            local x = 0
            for _, c in ipairs(cols) do
                local l = Kit:Label(hdr, c.t, "small")
                l:SetTextColor(Kit.Palette.accent[1], Kit.Palette.accent[2], Kit.Palette.accent[3])
                l:SetPoint("LEFT", hdr, "LEFT", x, 0)
                x = x + c.w
            end
            blockAdd(block, hdr, 20)

            for rIdx, resp in ipairs(responses) do
                local row = Kit:Row(block, 22)
                Kit:Label(row, tostring(rIdx), "small"):SetPoint("LEFT", row, "LEFT", 0, 0)
                Kit:Label(row, resp.name, "small"):SetPoint("LEFT", row, "LEFT", 25, 0)
                Kit:Label(row, "|cFFFFFF00" .. resp.score .. "|r", "small"):SetPoint("LEFT", row, "LEFT", 165, 0)
                Kit:Label(row, tostring(resp.roll), "small"):SetPoint("LEFT", row, "LEFT", 215, 0)
                local respColor = resp.response == PP.RESPONSE.NEED and "|cFF00FF00"
                               or resp.response == PP.RESPONSE.MINOR and "|cFF00CCFF" or "|cFFFF8800"
                Kit:Label(row, respColor .. resp.response .. "|r", "small"):SetPoint("LEFT", row, "LEFT", 260, 0)

                if resp.equippedLinks then
                    local _, _, _, newIlvl = C_Item.GetItemInfo(item.itemLink)
                    local bestDiff = nil
                    local ix = 350
                    for _, eLink in ipairs(resp.equippedLinks) do
                        local _, _, _, eIlvl, _, _, _, _, _, tex = C_Item.GetItemInfo(eLink)
                        if eIlvl and newIlvl then
                            local d = newIlvl - eIlvl
                            if bestDiff == nil or d > bestDiff then bestDiff = d end
                        end
                        local icon = row:CreateTexture(nil, "OVERLAY")
                        icon:SetSize(16, 16)
                        icon:SetPoint("LEFT", row, "LEFT", ix, 0)
                        if tex then icon:SetTexture(tex) end
                        local capturedLink = eLink
                        local hover = CreateFrame("Frame", nil, row)
                        hover:SetAllPoints(icon)
                        PP:AddItemTooltip(hover, capturedLink)
                        ix = ix + 18
                    end
                    local diffLbl
                    if bestDiff ~= nil then
                        local color = bestDiff > 0 and "|cFF00FF00" or bestDiff < 0 and "|cFFFF4444" or "|cFFAAAAAA"
                        diffLbl = Kit:Label(row, color .. (bestDiff > 0 and "+" or "") .. bestDiff .. " ilvl|r", "small")
                    else
                        diffLbl = Kit:Label(row, "|cFFAAAAAA(empty)|r", "small")
                    end
                    diffLbl:SetPoint("LEFT", row, "LEFT", 400, 0)
                end

                local voteCount = resp.voteCount or 0
                Kit:Label(row, voteCount > 0 and ("|cFFFFD100" .. voteCount .. "|r") or "|cFF888888-|r", "small")
                    :SetPoint("LEFT", row, "LEFT", 480, 0)

                local capturedKey, capturedName = item.key, resp.fullName
                if item.postedBy == me then
                    local awardBtn = Kit:Button(row, "Award", function() PP.Loot:Award(capturedKey, capturedName) end)
                    awardBtn:SetSize(60, 20)
                    awardBtn:SetPoint("LEFT", row, "LEFT", 520, 0)
                    local freeBtn = Kit:Button(row, "Free", function() PP.Loot:Award(capturedKey, capturedName, true) end)
                    freeBtn:SetSize(50, 20)
                    freeBtn:SetPoint("LEFT", awardBtn, "RIGHT", 4, 0)
                    local lootEntry = PP.Repo.Loot:GetEntry(item.key)
                    local votedThis = lootEntry and lootEntry.votes and lootEntry.votes[me] == resp.fullName
                    local voteBtn = Kit:Button(row, votedThis and "|cFF00FF00Vote|r" or "Vote", function()
                        PP:CastVote(capturedKey, capturedName)
                    end)
                    voteBtn:SetSize(55, 20)
                    voteBtn:SetPoint("LEFT", freeBtn, "RIGHT", 4, 0)
                else
                    local lootEntry = PP.Repo.Loot:GetEntry(item.key)
                    local votedThis = lootEntry and lootEntry.votes and lootEntry.votes[me] == resp.fullName
                    local voteBtn = Kit:Button(row, votedThis and "|cFF00FF00Vote|r" or "Vote", function()
                        PP:CastVote(capturedKey, capturedName)
                    end)
                    voteBtn:SetSize(55, 20)
                    voteBtn:SetPoint("LEFT", row, "LEFT", 520, 0)
                end

                blockAdd(block, row, 22)
            end
        else
            local waiting = Kit:Label(block, "Waiting for responses...", "small")
            blockAdd(block, waiting, 20)
        end

        if raidSet then
            if #nonResponders > 0 then
                table.sort(nonResponders)
                local w = Kit:Label(block, "|cFFFFAA00Waiting: |r" .. table.concat(nonResponders, ", "), "small")
                blockAdd(block, w, 18)
            elseif next(raidSet) then
                local w = Kit:Label(block, "|cFF00FF00All raid members have responded.|r", "small")
                blockAdd(block, w, 18)
            end
        end

        if item.postedBy == me then
            local cancelBtn = Kit:Button(block, "Cancel", function() PP.Loot:Cancel(item.key) end, "danger")
            cancelBtn:SetSize(80, 20)
            blockAdd(block, cancelBtn, 24)
        end

        block:SetHeight(-block._y + 6)
        list:Add(block, -block._y + 6, 8)
    end

    local pendingTrades = PP.Repo.Loot:GetPendingTrades()
    if canPost and #pendingTrades > 0 then
        list:Add(Kit:Heading(content, "Pending Trades"), 20)
        for tIdx, trade in ipairs(pendingTrades) do
            local tRow = Kit:Row(content, 22)
            local tLbl = Kit:Label(tRow, (trade.itemLink or "Item") .. "  -> " .. self:GetShortName(trade.awardedTo), "body")
            tLbl:SetPoint("LEFT", tRow, "LEFT", 0, 0)
            PP:AddItemTooltip(tRow, trade.itemLink)
            local clearBtn = Kit:Button(tRow, "Clear", function()
                PP.Repo.Loot:RemovePendingTrade(tIdx)
                PP:RefreshLootMasterWindow()
            end)
            clearBtn:SetSize(80, 20)
            clearBtn:SetPoint("RIGHT", tRow, "RIGHT", 0, 0)
            list:Add(tRow, 22)
        end
        local clearAllBtn = Kit:Button(content, "Clear All Trades", function()
            wipe(PP.Repo.Loot:GetPendingTrades())
            PP.Repo.Loot:Save()
            PP:RefreshLootMasterWindow()
        end)
        clearAllBtn:SetSize(140, 22)
        list:Add(clearAllBtn, 22, 6, false)
    end

    list:Layout()
end

---------------------------------------------------------------------------
-- Unified multi-item response popup
---------------------------------------------------------------------------
function PP:ShowLootResponseFrame()
    local hasItems = false
    for _, entry in pairs(PP.Repo.Loot:GetAll()) do
        if not entry.awarded then hasItems = true; break end
    end
    if not hasItems then return end

    self:HideLootBars()

    if self.lootResponseFrame then
        self:RefreshLootResponseFrame()
        self.lootResponseFrame:Show()
        return
    end

    local f = CreateFrame("Frame", "PPLootResponseFrame", UIParent, "BackdropTemplate")
    f:SetSize(370, 80)
    f:SetPoint("TOP", UIParent, "TOP", 0, -100)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Kit:Fill(f, Kit.Palette.backdrop)
    f:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropBorderColor(Kit.Palette.border[1], Kit.Palette.border[2], Kit.Palette.border[3], 1)

    tinsert(UISpecialFrames, "PPLootResponseFrame")

    f:SetScript("OnHide", function()
        if not PP._suppressLootBars then PP:ShowLootBars() end
    end)

    local title = f:CreateFontString(nil, "OVERLAY", "PPFontHead")
    title:SetPoint("TOP", 0, -8)
    title:SetText("Pirates Plunder - Loot")
    title:SetTextColor(Kit.Palette.accent[1], Kit.Palette.accent[2], Kit.Palette.accent[3])

    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY", "PPFontBody")
    closeLbl:SetAllPoints(closeBtn)
    closeLbl:SetText("x")
    closeLbl:SetTextColor(Kit.Palette.textDim[1], Kit.Palette.textDim[2], Kit.Palette.textDim[3])
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    f._itemContainer = CreateFrame("Frame", nil, f)
    f._itemContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -30)
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
    local kids = { container:GetChildren() }
    for _, child in ipairs(kids) do child:Hide(); child:SetParent(nil) end

    local me = self:GetPlayerFullName()
    local yOffset = 0
    local btnWidth, btnHeight = 72, 20
    local iconPad, iconWidth, textGap = 8, 28, 4
    local textX = iconPad + iconWidth + textGap
    local textH, btnGap, rowPadBot = 30, 4, 6
    local rowHeight = textH + btnGap + btnHeight + rowPadBot
    local itemCount = 0

    local anyTmog = false
    for _, entry in pairs(PP.Repo.Loot:GetAll()) do
        if not entry.awarded and entry.allowTransmog ~= false then anyTmog = true; break end
    end
    local numBtns = anyTmog and 4 or 3
    local contentWidth = textX + numBtns * btnWidth + (numBtns - 1) * 6
    f:SetWidth(contentWidth + iconPad + 24)

    local allEntries = {}
    for key, entry in pairs(PP.Repo.Loot:GetAll()) do
        if not entry.awarded then allEntries[#allEntries + 1] = { key = key, entry = entry } end
    end
    table.sort(allEntries, lootEntrySortLess)

    for _, pair in ipairs(allEntries) do
        local key, entry = pair.key, pair.entry
        itemCount = itemCount + 1
        local myResponse = entry.responses[me] and entry.responses[me].response or nil

        local row = CreateFrame("Frame", nil, container)
        row:SetSize(contentWidth, rowHeight)
        row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -yOffset)

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

        local itemText = row:CreateFontString(nil, "OVERLAY", "PPFontBody")
        itemText:SetPoint("TOPLEFT", row, "TOPLEFT", textX, 0)
        itemText:SetWidth(contentWidth - textX)
        itemText:SetHeight(textH)
        itemText:SetJustifyH("LEFT")
        itemText:SetJustifyV("TOP")
        local displayText = entry.itemLink or "Unknown Item"
        if myResponse then
            local color = myResponse == PP.RESPONSE.NEED and "|cFF00FF00"
                       or myResponse == PP.RESPONSE.MINOR and "|cFF00CCFF"
                       or myResponse == PP.RESPONSE.TRANSMOG and "|cFFFF8800" or "|cFF888888"
            displayText = displayText .. "  " .. color .. "[" .. myResponse .. "]|r"
        end
        itemText:SetText(displayText)
        PP:AddItemTooltip(row, entry.itemLink)

        local btnY = -(textH + btnGap)
        local capturedKey = key

        local needBtn = Kit:Button(row, "Need", function() PP.Loot:SubmitResponse(capturedKey, PP.RESPONSE.NEED) end)
        needBtn:SetSize(btnWidth, btnHeight)
        needBtn:SetPoint("TOPLEFT", row, "TOPLEFT", textX, btnY)
        if myResponse == PP.RESPONSE.NEED then needBtn.GetFontString(needBtn):SetTextColor(0, 1, 0) end

        local minorBtn = Kit:Button(row, "Minor", function() PP.Loot:SubmitResponse(capturedKey, PP.RESPONSE.MINOR) end)
        minorBtn:SetSize(btnWidth, btnHeight)
        minorBtn:SetPoint("LEFT", needBtn, "RIGHT", 6, 0)
        if myResponse == PP.RESPONSE.MINOR then minorBtn.GetFontString(minorBtn):SetTextColor(0, 0.8, 1) end

        local showTmog = entry.allowTransmog ~= false
        local tmogBtn = Kit:Button(row, "Transmog", function() PP.Loot:SubmitResponse(capturedKey, PP.RESPONSE.TRANSMOG) end)
        tmogBtn:SetSize(btnWidth, btnHeight)
        tmogBtn:SetPoint("LEFT", minorBtn, "RIGHT", 6, 0)
        if myResponse == PP.RESPONSE.TRANSMOG then tmogBtn.GetFontString(tmogBtn):SetTextColor(1, 0.53, 0) end
        if not showTmog then tmogBtn:Hide() end

        local passBtn = Kit:Button(row, "Pass", function() PP.Loot:SubmitResponse(capturedKey, PP.RESPONSE.PASS) end)
        passBtn:SetSize(btnWidth, btnHeight)
        passBtn:SetPoint("LEFT", showTmog and tmogBtn or minorBtn, "RIGHT", 6, 0)
        if myResponse == PP.RESPONSE.PASS then passBtn.GetFontString(passBtn):SetTextColor(0.5, 0.5, 0.5) end

        row:Show()
        yOffset = yOffset + rowHeight + 4
    end

    if itemCount == 0 then
        f:Hide()
        self:HideLootBars()
        return
    end

    f:SetHeight(math.max(80, 34 + yOffset + 8))
    container:SetHeight(yOffset)

    if self.lootBarsFrame and self.lootBarsFrame:IsShown() then
        self:RefreshLootBars()
    end
end

function PP:ShowLootPopup(key, itemLink)
    self:ShowLootResponseFrame()
end

function PP:CloseLootPopups()
    for key, frame in pairs(self.lootPopups) do
        if frame and frame.Hide then frame:Hide() end
    end
    wipe(self.lootPopups)
    if self.lootResponseFrame then
        self._suppressLootBars = true
        self.lootResponseFrame:Hide()
        self._suppressLootBars = nil
    end
    self:HideLootBars()
end

---------------------------------------------------------------------------
-- Loot bars
---------------------------------------------------------------------------
function PP:CreateLootBarsFrame()
    if self.lootBarsFrame then return end
    local LibWindow = LibStub("LibWindow-1.1")

    local f = CreateFrame("Frame", "PPLootBarsFrame", UIParent, "BackdropTemplate")
    f:SetSize(212, 12)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    Kit:Fill(f, {0.04, 0.04, 0.05, 0.9})
    f:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropBorderColor(Kit.Palette.border[1], Kit.Palette.border[2], Kit.Palette.border[3], 1)

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

    local bars = { f:GetChildren() }
    for _, bar in ipairs(bars) do bar:Hide() end

    local me = self:GetPlayerFullName()
    local barW, barH = 200, 22
    local padX, padTop, padBottom, barGap = 6, 6, 6, 2
    local yOffset = padTop
    local count = 0

    local allEntries = {}
    for key, entry in pairs(PP.Repo.Loot:GetAll()) do
        if not entry.awarded then allEntries[#allEntries + 1] = { key = key, entry = entry } end
    end
    table.sort(allEntries, lootEntrySortLess)

    for _, pair in ipairs(allEntries) do
        local key, entry = pair.key, pair.entry
        count = count + 1
        local myResponse = entry.responses[me] and entry.responses[me].response or nil

        local bar = bars[count]
        if not bar then
            bar = CreateFrame("Button", nil, f)
            bar:SetSize(barW, barH)
            local hoverBg = Kit:Fill(bar, {0, 0, 0, 0})
            local hoverBorder = CreateFrame("Frame", nil, bar, "BackdropTemplate")
            hoverBorder:SetAllPoints(bar)
            hoverBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            hoverBorder:SetBackdropBorderColor(Kit.Palette.accent[1], Kit.Palette.accent[2], Kit.Palette.accent[3], 0.85)
            hoverBorder:Hide()
            bar:SetScript("OnEnter", function() Kit.Tint(hoverBg, Kit.Palette.hover); hoverBorder:Show() end)
            bar:SetScript("OnLeave", function() Kit.Tint(hoverBg, {0, 0, 0, 0}); hoverBorder:Hide() end)
            bar:RegisterForDrag("LeftButton")
            bar:SetScript("OnDragStart", function() f:StartMoving() end)
            bar:SetScript("OnDragStop", function() f:StopMovingOrSizing(); LibWindow.SavePosition(f) end)
            bar:SetScript("OnClick", function() f:Hide(); PP:ShowLootResponseFrame() end)
            local icon = bar:CreateTexture(nil, "OVERLAY")
            icon:SetSize(16, 16)
            icon:SetPoint("LEFT", bar, "LEFT", 2, 0)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            bar._icon = icon
            local nameStr = bar:CreateFontString(nil, "OVERLAY", "PPFontSmall")
            nameStr:SetPoint("LEFT", bar, "LEFT", 22, 0)
            nameStr:SetPoint("RIGHT", bar, "RIGHT", -42, 0)
            nameStr:SetJustifyH("LEFT")
            nameStr:SetWordWrap(false)
            nameStr:SetTextColor(Kit.Palette.text[1], Kit.Palette.text[2], Kit.Palette.text[3])
            bar._nameStr = nameStr
            local respStr = bar:CreateFontString(nil, "OVERLAY", "PPFontSmall")
            respStr:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
            respStr:SetJustifyH("RIGHT")
            bar._respStr = respStr
            bars[count] = bar
        end

        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", f, "TOPLEFT", padX, -yOffset)

        local iconTex = (entry.itemID and C_Item.GetItemIconByID(entry.itemID))
        if not iconTex and entry.itemLink then
            local _, _, _, _, tex = GetItemInfoInstant(entry.itemLink)
            iconTex = tex
        end
        if iconTex then bar._icon:SetTexture(iconTex); bar._icon:Show() else bar._icon:Hide() end

        truncateToWidth(bar._nameStr, shortItemName(entry.itemLink), barW - 22 - 42)
        local quality
        if entry.itemLink then
            local _, _, q = C_Item.GetItemInfo(entry.itemLink)
            quality = q
        end
        if quality then
            local r, g, b = C_Item.GetItemQualityColor(quality)
            bar._nameStr:SetTextColor(r, g, b)
        else
            bar._nameStr:SetTextColor(Kit.Palette.text[1], Kit.Palette.text[2], Kit.Palette.text[3])
        end
        if myResponse == PP.RESPONSE.NEED then bar._respStr:SetText("|cFF00FF00Need|r")
        elseif myResponse == PP.RESPONSE.MINOR then bar._respStr:SetText("|cFF00CCFFMinor|r")
        elseif myResponse == PP.RESPONSE.TRANSMOG then bar._respStr:SetText("|cFFFF8800Tmog|r")
        elseif myResponse == PP.RESPONSE.PASS then bar._respStr:SetText("|cFF888888Pass|r")
        else bar._respStr:SetText("|cFFFFFF00?|r") end

        bar:Show()
        yOffset = yOffset + barH + barGap
    end

    if count == 0 then f:Hide(); return end
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
    if self.lootBarsFrame then self.lootBarsFrame:Hide() end
end
