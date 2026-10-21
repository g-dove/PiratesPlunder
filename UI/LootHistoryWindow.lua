---------------------------------------------------------------------------
-- Pirates Plunder – Session Loot History
-- /pp history: items awarded this session, the responses captured for each,
-- and (raid leader only) reassigning an item to another responder.
---------------------------------------------------------------------------
---@type PPAddon
local PP  = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")
local Kit = PP.Kit

local RESP_DISPLAY = {
    [PP.RESPONSE.NEED]     = "|cFF00FF00NEED|r",
    [PP.RESPONSE.MINOR]    = "|cFF00CCFFMINOR|r",
    [PP.RESPONSE.TRANSMOG] = "|cFFFF8800TRANSMOG|r",
}

local COL_ITEM, COL_WINNER, COL_RESP, COL_COST = 250, 170, 85, 55

function PP:CanViewLootHistory()
    return self:CanModify() or self:IsRaidLeader()
end

-- History entries belonging to the active session, oldest first.
local function activeHistory()
    local gk = PP:GetActiveGuildKey()
    local gd = PP.Repo.Roster:GetData(gk)
    local sessionID = gd and gd.activeSessionID
    local list = {}
    if not sessionID then return list end
    for _, h in pairs(PP.Repo.Loot:GetHistory()) do
        if h.guildKey == gk and h.sessionID == sessionID then
            list[#list + 1] = h
        end
    end
    table.sort(list, function(a, b) return (a.time or 0) < (b.time or 0) end)
    return list
end

local function costText(h)
    if h.free then return "|cFF00FF00Free|r" end
    return "|cFFFF8800" .. tostring(h.pointsSpent or 0) .. "|r"
end

---------------------------------------------------------------------------
-- List window
---------------------------------------------------------------------------
function PP:ToggleLootHistoryWindow()
    if self.lootHistoryWindow and self.lootHistoryWindow:IsShown() then
        self.lootHistoryWindow:Hide()
        return
    end
    if not self:CanViewLootHistory() then
        self:Print("Only officers and the raid leader can view loot history.")
        return
    end
    if not PP.Repo.Roster:HasActiveSession() then
        self:Print("No active session.")
        return
    end

    local f = self.lootHistoryWindow
    if not f then
        f = Kit:Window("Pirates Plunder - Session Loot History", 680, 420)
        f:SetOnClose(function() f:Hide() end)
        self.lootHistoryWindow = f
        PP:RegisterEscFrame(f, "PPLootHistoryFrame")
        self._lhList = Kit:ScrollList(f.body)
        self._lhList.frame:SetAllPoints(f.body)
    end
    self:DrawLootHistoryContent()
    f:Show()
    f:Raise()
end

function PP:RefreshLootHistoryWindow()
    if self.lootHistoryWindow and self.lootHistoryWindow:IsShown() then
        self:DrawLootHistoryContent()
    end
    if self.lootHistoryDetail and self.lootHistoryDetail:IsShown() then
        self:DrawLootHistoryDetail()
    end
end

function PP:DrawLootHistoryContent()
    local list = self._lhList
    if not list then return end
    list:Clear()
    local content = list.child

    if not PP.Repo.Roster:HasActiveSession() then
        list:Add(Kit:Label(content, "No active session.", "small"), 20)
        list:Layout()
        return
    end

    local session = PP.Repo.Roster:GetActiveSession()
    list:Add(Kit:Heading(content, "Awarded This Session - " .. (session and session.name or "")), 20)

    local history = activeHistory()
    if #history == 0 then
        list:Add(Kit:Label(content, "No items have been awarded yet.", "small"), 20)
        list:Layout()
        return
    end

    local header = Kit:Row(content, 18)
    local function col(text, x)
        local l = Kit:Label(header, text, "small")
        l:SetTextColor(Kit.Palette.accent[1], Kit.Palette.accent[2], Kit.Palette.accent[3])
        l:SetPoint("LEFT", header, "LEFT", x, 0)
    end
    col("Item", 0)
    col("Awarded To", COL_ITEM)
    col("Response", COL_ITEM + COL_WINNER)
    col("Cost", COL_ITEM + COL_WINNER + COL_RESP)
    list:Add(header, 18, 6)

    for _, h in ipairs(history) do
        local row = Kit:Row(content, 22)

        local itemLbl = Kit:Label(row, h.itemLink or "|cFFAAAAAA[Unknown Item]|r", "small")
        itemLbl:SetPoint("LEFT", row, "LEFT", 0, 0)
        itemLbl:SetWidth(COL_ITEM - 4)
        itemLbl:SetJustifyH("LEFT")
        local itemHover = CreateFrame("Frame", nil, row)
        itemHover:SetAllPoints(itemLbl)
        PP:AddItemTooltip(itemHover, h.itemLink)

        local winner = self:GetShortName(h.awardedTo)
        if h.reassignedFrom then
            winner = winner .. " |cFF888888(was " .. self:GetShortName(h.reassignedFrom) .. ")|r"
        end
        local winLbl = Kit:Label(row, winner, "small")
        winLbl:SetPoint("LEFT", row, "LEFT", COL_ITEM, 0)
        winLbl:SetWidth(COL_WINNER - 4)
        winLbl:SetJustifyH("LEFT")

        Kit:Label(row, RESP_DISPLAY[h.response] or tostring(h.response or "?"), "small")
            :SetPoint("LEFT", row, "LEFT", COL_ITEM + COL_WINNER, 0)
        Kit:Label(row, costText(h), "small")
            :SetPoint("LEFT", row, "LEFT", COL_ITEM + COL_WINNER + COL_RESP, 0)

        local capturedKey = h.key
        local viewBtn = Kit:Button(row, "View", function() PP:ShowLootHistoryDetail(capturedKey) end)
        viewBtn:SetSize(60, 20)
        viewBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)

        list:Add(row, 22, 2)
    end

    list:Layout()
end

---------------------------------------------------------------------------
-- Detail window – responses for one awarded item
---------------------------------------------------------------------------
function PP:ShowLootHistoryDetail(key)
    self._lootHistoryDetailKey = key
    local f = self.lootHistoryDetail
    if not f then
        f = Kit:Window("Pirates Plunder - Loot Responses", 860, 420)
        f:SetOnClose(function() f:Hide() end)
        self.lootHistoryDetail = f
        PP:RegisterEscFrame(f, "PPLootHistoryDetailFrame")
        self._lhdList = Kit:ScrollList(f.body)
        self._lhdList.frame:SetAllPoints(f.body)
    end
    self:DrawLootHistoryDetail()
    f:Show()
    f:Raise()
end

function PP:DrawLootHistoryDetail()
    local list = self._lhdList
    if not list then return end
    list:Clear()
    local content = list.child
    local UI = PP.LootUI

    local h = self._lootHistoryDetailKey and PP.Repo.Loot:GetHistoryEntry(self._lootHistoryDetailKey)
    if not h then
        list:Add(Kit:Label(content, "This item is no longer in the session history.", "small"), 20)
        list:Layout()
        return
    end

    local isLeader = self:IsRaidLeader()
    local block = UI.ItemBlock(content, h, 1)

    local info = "Awarded to: |cFFFFD100" .. self:GetShortName(h.awardedTo) .. "|r  |  "
        .. (RESP_DISPLAY[h.response] or tostring(h.response or "?")) .. "  |  Cost: " .. costText(h)
    if h.reassignedFrom then
        info = info .. "  |  Reassigned from " .. self:GetShortName(h.reassignedFrom)
    end
    UI.BlockAdd(block, Kit:Label(block, info, "small"), 20)

    local responses = self:SortResponses(h)
    if #responses > 0 then
        UI.DrawResponseRows(block, h.itemLink, responses, function(row, resp)
            if resp.fullName == h.awardedTo then
                Kit:Label(row, "|cFF00FF00Winner|r", "small"):SetPoint("LEFT", row, "LEFT", 520, 0)
            elseif isLeader then
                local capturedKey, capturedName = h.key, resp.fullName
                local awardBtn = Kit:Button(row, "Award", function() PP.Loot:Reassign(capturedKey, capturedName) end)
                awardBtn:SetSize(60, 20)
                awardBtn:SetPoint("LEFT", row, "LEFT", 520, 0)
                local freeBtn = Kit:Button(row, "Free", function() PP.Loot:Reassign(capturedKey, capturedName, true) end)
                freeBtn:SetSize(50, 20)
                freeBtn:SetPoint("LEFT", awardBtn, "RIGHT", 4, 0)
            end
        end)
    else
        UI.BlockAdd(block, Kit:Label(block, "No responses were captured on this client for this item.", "small"), 20)
    end

    if not isLeader then
        UI.BlockAdd(block, Kit:Label(block, "|cFF888888Only the raid leader can reassign this item.|r", "small"), 18)
    end

    block:SetHeight(-block._y + 6)
    list:Add(block, -block._y + 6, 8)
    list:Layout()
end

---------------------------------------------------------------------------
-- Confirm reassigning an item that has left pending trades
---------------------------------------------------------------------------
StaticPopupDialogs["PP_CONFIRM_REASSIGN_TRADED"] = {
    text = "%s is no longer in pending trades and may already have been traded to %s.\n\nPoints will still be refunded and charged. Continue with the reassign?",
    button1 = "Reassign", button2 = "Cancel",
    OnAccept = function()
        local p = PP._pendingReassign
        PP._pendingReassign = nil
        if p then PP.Loot:Reassign(p.key, p.newName, p.free, true) end
    end,
    OnCancel = function() PP._pendingReassign = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
