---------------------------------------------------------------------------
-- Pirates Plunder – Per-Player Awarded Loot History Window
--
-- Opened via PP:ShowAwardedLootWindow(fullName) from the Roster tab.
-- Only accessible to players who pass the CanModify() check.
--
-- History is derived live from raid records – nothing extra is stored.
-- Each row shows: Item · Type · Cost · Raid (roster/name) · Date
--
-- Public API:
--   PP:ShowAwardedLootWindow(fullName)
--   PP:HideAwardedLootWindow()
--   PP:RefreshAwardedLootWindow()
---------------------------------------------------------------------------
---@type PPAddon
local PP     = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")
local AceGUI = PP.AceGUI

-- Response type display config: { label, colour }
local RESP_DISPLAY = {
    [PP.RESPONSE.NEED]     = { label = "Need",     color = "|cFFFF4444" },
    [PP.RESPONSE.MINOR]    = { label = "Minor",    color = "|cFFFFAA00" },
    [PP.RESPONSE.TRANSMOG] = { label = "Transmog", color = "|cFF44AAFF" },
}

---------------------------------------------------------------------------
-- Open / close / refresh
---------------------------------------------------------------------------
function PP:ShowAwardedLootWindow(fullName)
    -- If already open for this player, just bring it to focus.
    if self.awardedLootWindow then
        if self._awardedLootTarget == fullName then
            self.awardedLootWindow.frame:Raise()
            return
        end
        -- Different player requested – release and reopen.
        self.awardedLootWindow:Release()
        self.awardedLootWindow = nil
    end

    self._awardedLootTarget = fullName

    local displayName = self:GetShortName(fullName)

    local f = AceGUI:Create("Frame")
    f:SetTitle("Loot History  –  " .. displayName)
    f:SetLayout("Fill")
    f:SetWidth(720)
    f:SetHeight(480)
    f:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        PP.awardedLootWindow  = nil
        PP._awardedLootTarget = nil
        PP._alwContainer      = nil
    end)
    self.awardedLootWindow = f

    -- ESC closes this window
    PP:RegisterEscFrame(f, "PPAwardedLootFrame")

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    scroll:SetLayout("List")
    f:AddChild(scroll)
    self._alwContainer = scroll

    self:DrawAwardedLootContent(scroll, fullName)
end

function PP:HideAwardedLootWindow()
    if self.awardedLootWindow then
        self.awardedLootWindow:Release()
        self.awardedLootWindow  = nil
        self._awardedLootTarget = nil
        self._alwContainer      = nil
    end
end

function PP:RefreshAwardedLootWindow()
    if not self.awardedLootWindow or not self._alwContainer then return end
    self:DrawAwardedLootContent(self._alwContainer, self._awardedLootTarget)
end

---------------------------------------------------------------------------
-- Content renderer
---------------------------------------------------------------------------
function PP:DrawAwardedLootContent(container, fullName)
    if not container or not fullName then return end
    container:ReleaseChildren()

    local shortName = self:GetShortName(fullName)
    local history   = self:GetPlayerAwardedLoot(fullName)
    local count     = #history

    -- ── Summary row ─────────────────────────────────────────────────────
    local summaryRow = AceGUI:Create("SimpleGroup")
    summaryRow:SetFullWidth(true)
    summaryRow:SetLayout("Flow")
    summaryRow.frame:EnableMouse(false)
    container:AddChild(summaryRow)

    local summaryLbl = AceGUI:Create("Label")
    summaryLbl:SetText(
        "|cFFFFD100" .. shortName .. "|r  —  " ..
        count .. " item" .. (count == 1 and "" or "s") .. " awarded"
    )
    summaryLbl:SetFontObject(GameFontNormal)
    summaryLbl:SetFullWidth(true)
    summaryRow:AddChild(summaryLbl)

    local noteLbl = AceGUI:Create("Label")
    noteLbl:SetFullWidth(true)
    noteLbl:SetText("|cFF888888  History is read directly from saved session records.|r")
    container:AddChild(noteLbl)

    local spacer = AceGUI:Create("Label")
    spacer:SetFullWidth(true)
    spacer:SetText(" ")
    spacer:SetHeight(6)
    container:AddChild(spacer)

    -- ── Empty state ──────────────────────────────────────────────────────
    if count == 0 then
        local empty = AceGUI:Create("Label")
        empty:SetFullWidth(true)
        empty:SetText("|cFFAAAAAA  No items recorded for " .. shortName .. " in any session.|r")
        container:AddChild(empty)
        return
    end

    -- ── Column headers ───────────────────────────────────────────────────
    local COL_ITEM   = 260
    local COL_TYPE   = 80
    local COL_COST   = 55
    local COL_RAID   = 190
    local COL_DATE   = 90

    local headerRow = AceGUI:Create("SimpleGroup")
    headerRow:SetFullWidth(true)
    headerRow:SetLayout("Flow")
    headerRow.frame:EnableMouse(false)
    container:AddChild(headerRow)

    local function makeHeader(text, width)
        local lbl = AceGUI:Create("Label")
        lbl:SetText("|cFFFFD100" .. text .. "|r")
        lbl:SetWidth(width)
        headerRow:AddChild(lbl)
    end
    makeHeader("Item",   COL_ITEM)
    makeHeader("Type",   COL_TYPE)
    makeHeader("Cost",   COL_COST)
    makeHeader("Session", COL_RAID)
    makeHeader("Date",   COL_DATE)

    local divider = AceGUI:Create("Label")
    divider:SetFullWidth(true)
    divider:SetText(" ")
    divider:SetHeight(10)
    container:AddChild(divider)

    -- ── Item rows ────────────────────────────────────────────────────────
    for _, item in ipairs(history) do
        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Flow")
        row.frame:EnableMouse(false)
        container:AddChild(row)

        -- Item link (hover = item tooltip)
        local itemLbl = AceGUI:Create("Label")
        itemLbl:SetText(item.itemLink or "|cFFAAAAAA[Unknown Item]|r")
        itemLbl:SetWidth(COL_ITEM)
        row:AddChild(itemLbl)
        if item.itemLink then
            self:AddItemTooltip(itemLbl.frame, item.itemLink)
        end

        -- Response type
        local dispInfo = RESP_DISPLAY[item.response]
        local respText = dispInfo
            and (dispInfo.color .. dispInfo.label .. "|r")
            or  ("|cFFFFFFFF" .. (item.response or "?") .. "|r")
        local respLbl = AceGUI:Create("Label")
        respLbl:SetText(respText)
        respLbl:SetWidth(COL_TYPE)
        row:AddChild(respLbl)

        -- Points spent
        local costLbl = AceGUI:Create("Label")
        costLbl:SetText("|cFFFF8800" .. tostring(item.pointsSpent or 0) .. "|r")
        costLbl:SetWidth(COL_COST)
        row:AddChild(costLbl)

        -- Raid name + roster qualifier
        -- Build a short label; show which roster it came from if it is not
        -- the currently active guild (helps in cross-roster scenarios).
        local activeKey   = self:GetActiveGuildKey()
        local rosterLabel = ""
        if item.guildKey and item.guildKey ~= activeKey then
            rosterLabel = " |cFF888888[" .. self:GetRosterDisplayName(item.guildKey) .. "]|r"
        end
        -- Hyperlink-style colour when the row is clickable
        local raidColor   = item.raidID and "|cFF4DB8FF" or "|cFFFFFFFF"
        local raidNameText = raidColor .. (item.raidName or "—") .. "|r" .. rosterLabel

        local raidLbl = AceGUI:Create("Label")
        raidLbl:SetText(raidNameText)
        raidLbl:SetWidth(COL_RAID)
        row:AddChild(raidLbl)

        -- Tooltip on the raid cell: full date + roster name + click hint
        if item.raidID then
            raidLbl.frame:EnableMouse(true)
            local capturedItem = item
            raidLbl.frame:SetScript("OnEnter", function(f)
                GameTooltip:SetOwner(f, "ANCHOR_CURSOR")
                GameTooltip:AddLine(capturedItem.raidName or "Unknown Session", 1, 0.82, 0)
                GameTooltip:AddLine(
                    "Roster: " .. PP:GetRosterDisplayName(capturedItem.guildKey or ""),
                    0.8, 0.8, 0.8
                )
                if capturedItem.awardedAt and capturedItem.awardedAt > 0 then
                    GameTooltip:AddLine(
                        "Awarded: " .. date("%Y-%m-%d %H:%M", capturedItem.awardedAt),
                        0.8, 0.8, 0.8
                    )
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Click to view session", 0, 1, 0)
                GameTooltip:Show()
            end)
            raidLbl.frame:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            raidLbl.frame:SetScript("OnMouseDown", function()
                PP:ShowRaidDetail(capturedItem.raidID)
            end)
        end

        -- Award date
        local dateLbl = AceGUI:Create("Label")
        dateLbl:SetText(item.awardedAt and date("%Y-%m-%d", item.awardedAt) or "")
        dateLbl:SetWidth(COL_DATE)
        row:AddChild(dateLbl)

        local rowSpacer = AceGUI:Create("Label")
        rowSpacer:SetFullWidth(true)
        rowSpacer:SetText(" ")
        rowSpacer:SetHeight(3)
        container:AddChild(rowSpacer)
    end
end
