local PP  = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")
local Kit = PP.Kit

local RESP_DISPLAY = {
    [PP.RESPONSE.NEED]     = { label = "Need",     color = "|cFFFF4444" },
    [PP.RESPONSE.MINOR]    = { label = "Minor",    color = "|cFFFFAA00" },
    [PP.RESPONSE.TRANSMOG] = { label = "Transmog", color = "|cFF44AAFF" },
}

function PP:ShowAwardedLootWindow(fullName)
    self._awardedLootTarget = fullName
    local displayName = self:GetShortName(fullName)

    local f = self.awardedLootWindow
    if not f then
        f = Kit:Window("Loot History - " .. displayName, 720, 480)
        f:SetOnClose(function() f:Hide() end)
        self.awardedLootWindow = f
        PP:RegisterEscFrame(f, "PPAwardedLootFrame")
        self._alwList = Kit:ScrollList(f.body)
        self._alwList.frame:SetAllPoints(f.body)
    else
        f:SetTitle("Loot History - " .. displayName)
    end

    self:DrawAwardedLootContent(fullName)
    f:Show()
    f:Raise()
end

function PP:HideAwardedLootWindow()
    if self.awardedLootWindow then
        self.awardedLootWindow:Hide()
        self._awardedLootTarget = nil
    end
end

function PP:RefreshAwardedLootWindow()
    if not self.awardedLootWindow or not self._alwList then return end
    self:DrawAwardedLootContent(self._awardedLootTarget)
end

local COL_ITEM, COL_TYPE, COL_COST, COL_RAID, COL_DATE = 260, 80, 55, 190, 90

function PP:DrawAwardedLootContent(fullName)
    local list = self._alwList
    if not list or not fullName then return end
    list:Clear()

    local shortName = self:GetShortName(fullName)
    local history    = self:GetPlayerAwardedLoot(fullName)
    local count      = #history

    local summary = Kit:Label(list.child, "|cFFFFD100" .. shortName .. "|r  -  "
        .. count .. " item" .. (count == 1 and "" or "s") .. " awarded", "head")
    list:Add(summary, 20)

    local note = Kit:Label(list.child, "History is read directly from saved session records.", "small")
    list:Add(note, 16, 12)

    if count == 0 then
        list:Add(Kit:Label(list.child, "No items recorded for " .. shortName .. " in any session.", "small"), 20)
        list:Layout()
        return
    end

    local header = Kit:Row(list.child, 18)
    local function col(text, x)
        local l = Kit:Label(header, text, "small")
        l:SetTextColor(Kit.Palette.accent[1], Kit.Palette.accent[2], Kit.Palette.accent[3])
        l:SetPoint("LEFT", header, "LEFT", x, 0)
    end
    col("Item", 0)
    col("Type", COL_ITEM)
    col("Cost", COL_ITEM + COL_TYPE)
    col("Session", COL_ITEM + COL_TYPE + COL_COST)
    col("Date", COL_ITEM + COL_TYPE + COL_COST + COL_RAID)
    list:Add(header, 18, 10)

    local activeKey = self:GetActiveGuildKey()
    for _, item in ipairs(history) do
        local row = Kit:Row(list.child, 20)

        local itemLbl = Kit:Label(row, item.itemLink or "|cFFAAAAAA[Unknown Item]|r", "small")
        itemLbl:SetPoint("LEFT", row, "LEFT", 0, 0)
        itemLbl:SetWidth(COL_ITEM - 4)
        if item.itemLink then PP:AddItemTooltip(row, item.itemLink) end

        local dispInfo = RESP_DISPLAY[item.response]
        local respText = dispInfo and (dispInfo.color .. dispInfo.label .. "|r")
            or ("|cFFFFFFFF" .. (item.response or "?") .. "|r")
        Kit:Label(row, respText, "small"):SetPoint("LEFT", row, "LEFT", COL_ITEM, 0)

        Kit:Label(row, "|cFFFF8800" .. tostring(item.pointsSpent or 0) .. "|r", "small")
            :SetPoint("LEFT", row, "LEFT", COL_ITEM + COL_TYPE, 0)

        local rosterLabel = ""
        if item.guildKey and item.guildKey ~= activeKey then
            rosterLabel = " |cFF888888[" .. self:GetRosterDisplayName(item.guildKey) .. "]|r"
        end
        local raidColor = item.raidID and "|cFF4DB8FF" or "|cFFFFFFFF"
        local raidLbl = Kit:Label(row, raidColor .. (item.raidName or "-") .. "|r" .. rosterLabel, "small")
        raidLbl:SetPoint("LEFT", row, "LEFT", COL_ITEM + COL_TYPE + COL_COST, 0)
        raidLbl:SetWidth(COL_RAID - 4)

        if item.raidID then
            local capturedItem = item
            row:EnableMouse(true)
            row:SetScript("OnEnter", function(fr)
                GameTooltip:SetOwner(fr, "ANCHOR_CURSOR")
                GameTooltip:AddLine(capturedItem.raidName or "Unknown Session", 1, 0.82, 0)
                GameTooltip:AddLine("Roster: " .. PP:GetRosterDisplayName(capturedItem.guildKey or ""), 0.8, 0.8, 0.8)
                if capturedItem.awardedAt and capturedItem.awardedAt > 0 then
                    GameTooltip:AddLine("Awarded: " .. date("%Y-%m-%d %H:%M", capturedItem.awardedAt), 0.8, 0.8, 0.8)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Click to view session", 0, 1, 0)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row:SetScript("OnMouseDown", function() PP:ShowRaidDetail(capturedItem.raidID) end)
        end

        Kit:Label(row, item.awardedAt and date("%Y-%m-%d", item.awardedAt) or "", "small")
            :SetPoint("LEFT", row, "LEFT", COL_ITEM + COL_TYPE + COL_COST + COL_RAID, 0)

        list:Add(row, 20, 3)
    end

    list:Layout()
end
