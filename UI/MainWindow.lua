local PP  = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")
local Kit = PP.Kit

local ROW_H = 22

function PP:ToggleMainWindow()
    if self.mainWindow then
        self.mainWindow:Hide()
        self.mainWindow = nil
        return
    end
    self:CreateMainWindow()
end

function PP:RefreshMainWindow()
    if not self.mainWindow then return end
    local tab = self._mwActiveTab or "roster"
    if tab == "roster" then
        self:DrawRosterTab()
    elseif tab == "sessions" then
        self:DrawSessionsTab()
    elseif tab == "settings" then
        self:DrawSettingsTab()
    end
end

function PP:CreateMainWindow()
    local f = Kit:Window("Pirates Plunder", 760, 580)
    f:SetOnClose(function()
        f:Hide()
        PP.mainWindow = nil
    end)
    self.mainWindow = f
    self._rosterList = nil
    self._sessionsList = nil
    self._settingsList = nil
    PP:RegisterEscFrame(f, "PPMainWindowFrame")

    local tabArea = CreateFrame("Frame", nil, f.body)
    tabArea:SetPoint("TOPLEFT", f.body, "TOPLEFT")
    tabArea:SetPoint("TOPRIGHT", f.body, "TOPRIGHT")
    tabArea:SetHeight(24)

    local content = CreateFrame("Frame", nil, f.body)
    content:SetPoint("TOPLEFT", tabArea, "BOTTOMLEFT", 0, -8)
    content:SetPoint("BOTTOMRIGHT", f.body, "BOTTOMRIGHT")
    self._mwContent = content

    local strip = Kit:TabStrip(tabArea, {
        { value = "roster",   text = "Roster" },
        { value = "sessions", text = "Sessions" },
        { value = "settings", text = "Settings" },
    }, function(value)
        self._mwActiveTab = value
        self:RefreshMainWindow()
    end)
    strip:SetPoint("TOPLEFT", tabArea, "TOPLEFT")
    strip:SetPoint("BOTTOMLEFT", tabArea, "BOTTOMLEFT")

    self._mwActiveTab = "roster"
    self:DrawRosterTab()
end

-- Each tab keeps its own persistent ScrollList so switching tabs (or just
-- redrawing the active one, e.g. after selecting a row) never tears down and
-- rebuilds the scroll frame -- that was resetting scroll position to the top
-- on every redraw and leaking an orphaned ScrollFrame/Slider each time.
local function hideOtherTabLists(exceptList)
    if PP._rosterList   and PP._rosterList   ~= exceptList then PP._rosterList:SetShown(false) end
    if PP._sessionsList and PP._sessionsList ~= exceptList then PP._sessionsList:SetShown(false) end
    if PP._settingsList and PP._settingsList ~= exceptList then PP._settingsList:SetShown(false) end
end

local function headerRow(parent, cols)
    local row = Kit:Row(parent, ROW_H)
    local x = 0
    for _, col in ipairs(cols) do
        local lbl = Kit:Label(row, col.text, "small")
        lbl:SetPoint("LEFT", row, "LEFT", x, 0)
        lbl:SetTextColor(Kit.Palette.accent[1], Kit.Palette.accent[2], Kit.Palette.accent[3])
        x = x + col.w
    end
    return row
end

---------------------------------------------------------------------------
-- Roster tab
---------------------------------------------------------------------------
function PP:DrawRosterTab()
    PP:RefreshOfficerStatus()
    local canModify = self:CanModify()

    local list = self._rosterList
    if not list then
        list = Kit:ScrollList(self._mwContent)
        list.frame:SetAllPoints(self._mwContent)
        self._rosterList = list
    end
    hideOtherTabLists(list)
    list:SetShown(true)
    list:Clear()
    local content = list.child

    if not PP:IsSandbox() then
        local row = Kit:Row(content, 24)
        local dd = Kit:Dropdown(row, 220, function(val)
            PP._activeGuildKey = val
            PP._selectedRosterPlayer = nil
            PP:DrawRosterTab()
        end)
        local items = {}
        for _, gk in ipairs(PP.Repo.Roster:GetAllGuildKeys()) do
            items[#items + 1] = { value = gk, label = PP:GetRosterDisplayName(gk) }
        end
        dd:SetItems(items)
        dd:SetLabel(PP:GetRosterDisplayName(PP:GetActiveGuildKey()))
        dd:SetPoint("LEFT", row, "LEFT", 0, 0)
        list:Add(row, 24)
    end

    if canModify then
        local topRow = Kit:Row(content, 24)
        local randBtn = Kit:Button(topRow, "Randomize Order", function()
            StaticPopup_Show("PP_CONFIRM_RANDOMIZE")
        end)
        randBtn:SetSize(140, 22)
        randBtn:SetPoint("LEFT", topRow, "LEFT", 0, 0)

        local clearBtn = Kit:Button(topRow, "Clear Roster", function()
            StaticPopup_Show("PP_CONFIRM_CLEAR_ROSTER")
        end)
        clearBtn:SetSize(120, 22)
        clearBtn:SetPoint("LEFT", randBtn, "RIGHT", 8, 0)
        list:Add(topRow, 24)

        list:Add(Kit:Heading(content, "Actions"), 20)

        local sel      = PP._selectedRosterPlayer
        local selEntry = nil
        if sel then
            for _, e in ipairs(PP.Roster:GetSorted()) do
                if e.fullName == sel then selEntry = e; break end
            end
        end
        local hasSelection = selEntry ~= nil

        local hintLbl = Kit:Label(content, hasSelection
            and ("Editing: |cFFFFD100" .. selEntry.name .. "|r")
            or  "|cFFAAAAAAClick a row below to select a player.|r", "small")
        list:Add(hintLbl, 16)

        local selRow = Kit:Row(content, 24)
        local scoreBox = Kit:EditBox(selRow, 60)
        scoreBox:SetText(hasSelection and tostring(selEntry.score) or "")
        scoreBox._eb:SetScript("OnEnterPressed", function(eb)
            if selEntry then
                local val = tonumber(eb:GetText())
                if val then PP.Roster:SetScore(sel, val) else eb:SetText(tostring(selEntry.score)) end
            end
            eb:ClearFocus()
        end)
        scoreBox:SetPoint("LEFT", selRow, "LEFT", 0, 0)

        local minusBtn = Kit:Button(selRow, "-1", function()
            if selEntry then PP.Roster:SetScore(sel, math.max(0, selEntry.score - 1)) end
        end)
        minusBtn:SetSize(40, 22)
        minusBtn:SetPoint("LEFT", scoreBox, "RIGHT", 6, 0)

        local plusBtn = Kit:Button(selRow, "+1", function()
            if selEntry then PP.Roster:SetScore(sel, selEntry.score + 1) end
        end)
        plusBtn:SetSize(40, 22)
        plusBtn:SetPoint("LEFT", minusBtn, "RIGHT", 6, 0)

        local removeBtn = Kit:Button(selRow, "Remove", function()
            if selEntry then
                PP._pendingRemovePlayer = sel
                StaticPopup_Show("PP_CONFIRM_REMOVE_PLAYER")
            end
        end)
        removeBtn:SetSize(80, 22)
        removeBtn:SetPoint("LEFT", plusBtn, "RIGHT", 6, 0)

        for _, w in ipairs({ scoreBox, minusBtn, plusBtn, removeBtn }) do
            if w.SetDisabled then w:SetDisabled(not hasSelection) end
        end
        list:Add(selRow, 24)

        list:Add(Kit:Label(content, "|cFFFFD100Group Actions|r", "small"), 16)

        local groupRow = Kit:Row(content, 24)
        local amountBox = Kit:EditBox(groupRow, 90)
        amountBox:SetText(PP._groupAmountValue or "1")
        amountBox._eb:SetScript("OnTextChanged", function(eb) PP._groupAmountValue = eb:GetText() end)
        amountBox:SetPoint("LEFT", groupRow, "LEFT", 0, 0)

        local applyBtn = Kit:Button(groupRow, "Apply to Group", function()
            if not IsInGroup() then PP:Print("You must be in a group."); return end
            local amt = tonumber(amountBox:GetText())
            if not amt then PP:Print("Enter a valid number."); return end
            PP.Roster:AddScoreToRaidMembers(amt)
        end)
        applyBtn:SetSize(130, 22)
        applyBtn:SetPoint("LEFT", amountBox, "RIGHT", 8, 0)

        local plusOneBtn = Kit:Button(groupRow, "+1 to Group", function()
            if not IsInGroup() then PP:Print("You must be in a group."); return end
            PP.Roster:AddScoreToRaidMembers(1)
        end)
        plusOneBtn:SetSize(110, 22)
        plusOneBtn:SetPoint("LEFT", applyBtn, "RIGHT", 8, 0)
        list:Add(groupRow, 24, 14)
    end

    list:Add(Kit:Heading(content, "Player Roster (sorted by score)"), 20)

    local cols = { {text="#",w=30}, {text="Name",w=200}, {text="Realm",w=150}, {text="Score",w=60} }
    if canModify then cols[#cols+1] = {text="Actions", w=105} end
    list:Add(headerRow(content, cols), ROW_H)

    local sorted  = PP.Roster:GetSorted()
    local raidSet = PP.Roster:GetRaidMemberSet()

    for idx, entry in ipairs(sorted) do
        local isSelected = canModify and (PP._selectedRosterPlayer == entry.fullName)
        local row = CreateFrame("Button", nil, content)
        row:SetHeight(ROW_H)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        Kit.Tint(bg, isSelected and Kit.Palette.accentDim or (idx % 2 == 0 and Kit.Palette.rowA or Kit.Palette.rowB))

        if canModify then
            row:SetScript("OnClick", function()
                PP._selectedRosterPlayer = (PP._selectedRosterPlayer == entry.fullName) and nil or entry.fullName
                PP:DrawRosterTab()
            end)
            row:SetScript("OnEnter", function() if not isSelected then Kit.Tint(bg, Kit.Palette.hover) end end)
            row:SetScript("OnLeave", function() if not isSelected then Kit.Tint(bg, idx % 2 == 0 and Kit.Palette.rowA or Kit.Palette.rowB) end end)
        end

        local nameColor = raidSet[entry.fullName] and "|cFF00FF00" or "|cFFAAAAAA"
        Kit:Label(row, tostring(idx), "body"):SetPoint("LEFT", row, "LEFT", 0, 0)
        Kit:Label(row, nameColor .. entry.name .. "|r", "body"):SetPoint("LEFT", row, "LEFT", 30, 0)
        Kit:Label(row, entry.realm, "body"):SetPoint("LEFT", row, "LEFT", 230, 0)
        Kit:Label(row, "|cFFFFFF00" .. entry.score .. "|r", "body"):SetPoint("LEFT", row, "LEFT", 380, 0)

        if canModify then
            local histBtn = Kit:Button(row, "Loot History", function()
                PP:ShowAwardedLootWindow(entry.fullName)
            end)
            histBtn:SetSize(100, 20)
            histBtn:SetPoint("LEFT", row, "LEFT", 440, 0)
        end

        list:Add(row, ROW_H, 2)
    end

    if #sorted == 0 then
        list:Add(Kit:Label(content, "No players in roster. Join a raid or add players manually.", "small"), 20)
    end

    list:Layout()
end

---------------------------------------------------------------------------
-- Sessions tab
---------------------------------------------------------------------------
function PP:DrawSessionsTab()
    local canModify = self:CanModify()

    local list = self._sessionsList
    if not list then
        list = Kit:ScrollList(self._mwContent)
        list.frame:SetAllPoints(self._mwContent)
        self._sessionsList = list
    end
    hideOtherTabLists(list)
    list:SetShown(true)
    list:Clear()
    local content = list.child

    if not PP:IsSandbox() then
        local row = Kit:Row(content, 24)
        local dd = Kit:Dropdown(row, 220, function(val)
            PP._activeGuildKey = val
            PP:DrawSessionsTab()
        end)
        local items = {}
        for _, gk in ipairs(PP.Repo.Roster:GetAllGuildKeys()) do
            items[#items + 1] = { value = gk, label = PP:GetRosterDisplayName(gk) }
        end
        dd:SetItems(items)
        dd:SetLabel(PP:GetRosterDisplayName(PP:GetActiveGuildKey()))
        dd:SetPoint("LEFT", row, "LEFT", 0, 0)
        list:Add(row, 24)
    end

    local nameBox
    if canModify then
        local topRow = Kit:Row(content, 24)
        nameBox = Kit:EditBox(topRow, 220)
        nameBox:SetText(date("%Y-%m-%d") .. " Session")
        nameBox:SetPoint("LEFT", topRow, "LEFT", 0, 0)

        if PP.Repo.Roster:HasActiveSession() then
            local closeBtn = Kit:Button(topRow, "Close Session", function()
                PP.Session:End(PP.SESSION_END.OFFICER_ACTION)
            end, "danger")
            closeBtn:SetSize(130, 22)
            closeBtn:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
        else
            local createBtn = Kit:Button(topRow, "Create Session", function()
                PP.Session:Create(nameBox:GetText())
            end)
            createBtn:SetSize(130, 22)
            createBtn:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
        end
        list:Add(topRow, 24)
    end

    if PP.Repo.Roster:HasActiveSession() then
        local session = PP.Repo.Roster:GetActiveSession()
        list:Add(Kit:Label(content, "|cFF00FF00Active Session:|r " .. (session and session.name or "Unknown"), "body"), 18)
    end

    list:Add(Kit:Heading(content, "Session History"), 20)

    local history = self:GetRaidHistory()
    for _, raid in ipairs(history) do
        local row = CreateFrame("Button", nil, content)
        row:SetHeight(ROW_H)
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        Kit.Tint(bg, Kit.Palette.rowA)
        row:SetScript("OnEnter", function() Kit.Tint(bg, Kit.Palette.hover) end)
        row:SetScript("OnLeave", function() Kit.Tint(bg, Kit.Palette.rowA) end)
        row:SetScript("OnClick", function() PP:ShowRaidDetail(raid.id) end)

        local status = raid.active and "|cFF00FF00[ACTIVE]|r " or "|cFF888888[ENDED]|r "
        local dateStr = date("%Y-%m-%d %H:%M", raid.startTime)
        local text = status .. raid.name .. "  |cFF888888(" .. dateStr .. ")|r  Bosses: "
            .. raid.bossCount .. "  Items: " .. raid.itemCount
        local lbl = Kit:Label(row, text, "body")
        lbl:SetPoint("LEFT", row, "LEFT", 4, 0)
        list:Add(row, ROW_H, 2)
    end

    if #history == 0 then
        list:Add(Kit:Label(content, "No sessions recorded yet.", "small"), 20)
    end

    list:Layout()
end

---------------------------------------------------------------------------
-- Raid detail popup
---------------------------------------------------------------------------
function PP:ShowRaidDetail(raidID)
    local raid, raidGuildKey
    for _, gk in ipairs(PP.Repo.Roster:GetAllGuildKeys()) do
        local gd = PP.Repo.Roster:GetData(gk)
        if gd and gd.sessions and gd.sessions[raidID] then
            raid = gd.sessions[raidID]
            raidGuildKey = gk
            break
        end
    end
    if not raid then return end

    local f = self._raidDetailWindow
    if not f then
        f = Kit:Window(raid.name or "Session Detail", 560, 460)
        f:SetOnClose(function() f:Hide() end)
        self._raidDetailWindow = f
        PP:RegisterEscFrame(f, "PPRaidDetailFrame")
        self._rdList = Kit:ScrollList(f.body)
        self._rdList.frame:SetAllPoints(f.body)
    end
    f:SetTitle(raid.name or "Session Detail")
    local list = self._rdList
    list:Clear()

    local startStr = date("%Y-%m-%d %H:%M", raid.startTime)
    local endStr   = raid.endTime and date("%Y-%m-%d %H:%M", raid.endTime) or "In Progress"
    local infoLbl = Kit:Label(list.child, "Leader: " .. self:GetShortName(raid.leader)
        .. "    Started: " .. startStr .. "    Ended: " .. endStr, "body")
    infoLbl:SetWordWrap(true)
    list:Add(infoLbl, 34)

    if not raid.active then
        local snapshot = PP.Repo.Roster:GetSessionSnapshot(raidGuildKey, raidID)
        if snapshot then
            local snapBtn = Kit:Button(list.child, "View Roster Snapshot", function()
                PP:ShowRosterSnapshot(raidGuildKey, raidID)
            end)
            snapBtn:SetSize(180, 22)
            list:Add(snapBtn, 22, 6, false)
        end
    end

    if self:IsOfficerOrHigher() and not self:IsSandbox() then
        local warn = Kit:Label(list.child, "|cFFFF4400Deleting a session permanently removes its loot and boss records. This syncs to all online raid members.|r", "small")
        warn:SetWordWrap(true)
        list:Add(warn, 30)

        local delBtn = Kit:Button(list.child, "Delete Session", function()
            PP._pendingDeleteRaidID = raidID
            StaticPopup_Show("PP_CONFIRM_DELETE_RAID")
        end, "danger")
        delBtn:SetSize(130, 22)
        list:Add(delBtn, 22, 6, false)
    end

    list:Add(Kit:Heading(list.child, "Boss Kills (" .. #raid.bosses .. ")"), 20)
    for _, boss in ipairs(raid.bosses) do
        list:Add(Kit:Label(list.child, boss.encounterName .. "  |cFF888888" .. date("%H:%M", boss.time) .. "|r", "small"), 16)
    end
    if #raid.bosses == 0 then
        list:Add(Kit:Label(list.child, "No bosses killed.", "small"), 16)
    end

    list:Add(Kit:Heading(list.child, "Awarded Items (" .. #raid.items .. ")"), 20)
    for _, item in ipairs(raid.items) do
        local ptsStr  = item.pointsSpent and ("  |cFFFFFF00" .. item.pointsSpent .. " pts|r") or ""
        local respStr = item.response and ("  |cFF888888[" .. item.response .. "]|r") or ""
        list:Add(Kit:Label(list.child, (item.itemLink or "Unknown") .. "  -> " .. self:GetShortName(item.awardedTo) .. ptsStr .. respStr, "small"), 16)
    end
    if #raid.items == 0 then
        list:Add(Kit:Label(list.child, "No items awarded.", "small"), 16)
    end

    list:Layout()
    f:Show()
    f:Raise()
end

---------------------------------------------------------------------------
-- Roster snapshot popup
---------------------------------------------------------------------------
function PP:ShowRosterSnapshot(guildKey, sessionID)
    local snapshot = PP.Repo.Roster:GetSessionSnapshot(guildKey, sessionID)
    if not snapshot then return end

    local gd = PP.Repo.Roster:GetData(guildKey)
    local sessionName = (gd and gd.sessions and gd.sessions[sessionID] and gd.sessions[sessionID].name) or sessionID

    local f = self._snapshotWindow
    if not f then
        f = Kit:Window("Roster Snapshot - " .. sessionName, 420, 480)
        f:SetOnClose(function() f:Hide() end)
        self._snapshotWindow = f
        PP:RegisterEscFrame(f, "PPSnapshotFrame")
        self._snapList = Kit:ScrollList(f.body)
        self._snapList.frame:SetAllPoints(f.body)
    end
    f:SetTitle("Roster Snapshot - " .. sessionName)
    local list = self._snapList
    list:Clear()

    local capturedStr = snapshot.capturedAt and date("%Y-%m-%d %H:%M:%S", snapshot.capturedAt) or "unknown"
    list:Add(Kit:Label(list.child, "Captured: " .. capturedStr .. "    Roster version: " .. tostring(snapshot.rosterVersion or "?"), "small"), 16)
    list:Add(Kit:Heading(list.child, "Standings (sorted by score)"), 20)
    list:Add(headerRow(list.child, { {text="#",w=30}, {text="Name",w=170}, {text="Realm",w=130}, {text="Score",w=60} }), ROW_H)

    local sorted = {}
    for fullName, entry in pairs(snapshot.entries or {}) do
        sorted[#sorted + 1] = {
            name  = entry.name or PP:GetShortName(fullName),
            realm = entry.realm or "",
            score = entry.score or 0,
        }
    end
    table.sort(sorted, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.name < b.name
    end)

    for idx, entry in ipairs(sorted) do
        local row = Kit:Row(list.child, ROW_H)
        Kit:Label(row, tostring(idx), "body"):SetPoint("LEFT", row, "LEFT", 0, 0)
        Kit:Label(row, "|cFFAAAAAA" .. entry.name .. "|r", "body"):SetPoint("LEFT", row, "LEFT", 30, 0)
        Kit:Label(row, entry.realm, "body"):SetPoint("LEFT", row, "LEFT", 200, 0)
        Kit:Label(row, "|cFFFFFF00" .. entry.score .. "|r", "body"):SetPoint("LEFT", row, "LEFT", 330, 0)
        list:Add(row, ROW_H, 2)
    end

    if #sorted == 0 then
        list:Add(Kit:Label(list.child, "Snapshot has no roster entries.", "small"), 20)
    end

    list:Layout()
    f:Show()
    f:Raise()
end

---------------------------------------------------------------------------
-- Settings tab
---------------------------------------------------------------------------
function PP:DrawSettingsTab()
    local list = self._settingsList
    if not list then
        list = Kit:ScrollList(self._mwContent)
        list.frame:SetAllPoints(self._mwContent)
        self._settingsList = list
    end
    hideOtherTabLists(list)
    list:SetShown(true)
    list:Clear()
    local content = list.child

    if PP:IsSandbox() then
        local banner = Kit:Label(content, "|cFFFFD100SANDBOX ACTIVE - simulating raid leader. Nothing is saved to disk.\nUse /pp sandbox to disable, /pp sandbox mod to toggle status.|r", "small")
        banner:SetWordWrap(true)
        list:Add(banner, 32)
    end

    list:Add(Kit:Heading(content, "Synchronisation"), 20)
    local syncDesc = Kit:Label(content, "Request a full roster and session sync from any online officer in your current group.", "small")
    syncDesc:SetWordWrap(true)
    list:Add(syncDesc, 28)

    local syncRow = Kit:Row(content, 24)
    local syncBtn = Kit:Button(syncRow, "Request Sync", function()
        if not IsInGroup() then PP:Print("You must be in a group to request a sync.")
        else PP:RequestSync(); PP:Print("Sync requested.") end
    end)
    syncBtn:SetSize(140, 22)
    syncBtn:SetPoint("LEFT", syncRow, "LEFT", 0, 0)

    local lastAnchor = syncBtn
    if PP:CanModify() then
        local bcBtn = Kit:Button(syncRow, "Broadcast Roster", function()
            if not IsInGroup() then PP:Print("You must be in a group to broadcast.")
            else PP:BroadcastRoster(); PP:Print("Roster broadcast to group.") end
        end)
        bcBtn:SetSize(150, 22)
        bcBtn:SetPoint("LEFT", lastAnchor, "RIGHT", 8, 0)
        lastAnchor = bcBtn
    end

    local snapBtn = Kit:Button(syncRow, "Fetch Session Snapshots", function()
        PP:RequestSessionSnapshots()
    end)
    snapBtn:SetSize(190, 22)
    snapBtn:SetPoint("LEFT", lastAnchor, "RIGHT", 8, 0)
    list:Add(syncRow, 24, 14)

    list:Add(Kit:Heading(content, "Loot"), 20)
    local lootDesc = Kit:Label(content, "Clear any loot items stuck on your response frame. Local only - does not affect other players.", "small")
    lootDesc:SetWordWrap(true)
    list:Add(lootDesc, 28)
    local clearLootBtn = Kit:Button(content, "Clear My Loot Display", function()
        PP:LocalClearLoot()
        PP:Print("Loot display cleared.")
    end)
    clearLootBtn:SetSize(190, 22)
    list:Add(clearLootBtn, 22, 14, false)

    list:Add(Kit:Heading(content, "Manage Guild Rosters"), 20)
    local guildDesc = Kit:Label(content, "Locally remove a guild roster record from your client. This does not sync to other players.", "small")
    guildDesc:SetWordWrap(true)
    list:Add(guildDesc, 28)

    local guildKeys = {}
    for _, gk in ipairs(PP.Repo.Roster:GetAllGuildKeys()) do
        if gk ~= "__sandbox__" then guildKeys[#guildKeys + 1] = gk end
    end
    table.sort(guildKeys)

    if #guildKeys == 0 then
        list:Add(Kit:Label(content, "No guild rosters on record.", "small"), 16, 14)
    else
        local guildRow = Kit:Row(content, 24)
        local selectedGuildKey = guildKeys[1]
        local gdd = Kit:Dropdown(guildRow, 220, function(val) selectedGuildKey = val end)
        local gItems = {}
        for _, gk in ipairs(guildKeys) do gItems[#gItems+1] = { value = gk, label = gk } end
        gdd:SetItems(gItems)
        gdd:SetLabel(guildKeys[1])
        gdd:SetPoint("LEFT", guildRow, "LEFT", 0, 0)

        local delBtn = Kit:Button(guildRow, "Delete Locally", function()
            if selectedGuildKey then
                PP._pendingDeleteGuildRoster = selectedGuildKey
                StaticPopup_Show("PP_CONFIRM_DELETE_GUILD_ROSTER")
            end
        end, "danger")
        delBtn:SetSize(130, 22)
        delBtn:SetPoint("LEFT", gdd, "RIGHT", 8, 0)
        list:Add(guildRow, 24, 14)
    end

    list:Add(Kit:Heading(content, "Loot Rules"), 20)
    local tmogChk = Kit:Checkbox(content, "Allow Transmog rolls", function(val)
        PP.db.global.allowTransmogRolls = val
    end)
    tmogChk:SetValue(PP.db.global.allowTransmogRolls ~= false)
    list:Add(tmogChk, 20)

    local isLeader = PP:IsRaidLeaderOrAssist()
    local autoPassChk = Kit:Checkbox(content, "Auto-pass in-game Epic+ loot rolls for non-leaders", function(val)
        if not PP:IsRaidLeaderOrAssist() then return end
        PP.db.global.autoPassEpicRolls = val
        PP:BroadcastRaidSettings()
    end)
    autoPassChk:SetValue(PP.db.global.autoPassEpicRolls == true)
    if not isLeader then autoPassChk:SetDisabled(true) end
    list:Add(autoPassChk, 20, 14)

    list:Add(Kit:Heading(content, "Display"), 20)
    local minimapChk = Kit:Checkbox(content, "Show minimap icon", function(val)
        if val then PP:ShowMinimapIcon() else PP:HideMinimapIcon() end
    end)
    minimapChk:SetValue(not PP.db.global.minimapIcon.hide)
    list:Add(minimapChk, 20, 14)

    list:Add(Kit:Heading(content, "Status"), 20)
    local guildKey = PP:GetActiveGuildKey()
    local myGuild  = PP:GetPlayerGuild() or "|cFFAAAAAAnone|r"
    local officer  = PP:IsOfficerOrHigher() and "|cFF00FF00Yes|r" or "|cFFFF4400No|r"
    local canMod   = PP:CanModify() and "|cFF00FF00Yes|r" or "|cFFFF4400No|r"
    local gd       = PP.Repo.Roster:GetData(guildKey)
    local rVer     = gd and gd.rosterVersion or 0
    local inGroup  = IsInGroup() and "|cFF00FF00Yes|r" or "|cFFAAAAAANo|r"
    local statusLbl = Kit:Label(content,
        "Active roster: |cFFFFD100" .. PP:GetRosterDisplayName(guildKey) .. "|r\n"
        .. "My guild: " .. myGuild .. "    Officer: " .. officer .. "    Can modify: " .. canMod .. "\n"
        .. "Roster version: |cFFFFFFFF" .. rVer .. "|r    In group: " .. inGroup, "small")
    statusLbl:SetWordWrap(true)
    list:Add(statusLbl, 46)

    list:Add(Kit:Heading(content, "Reset"), 20)
    local resetDesc = Kit:Label(content, "Reset clears all saved data for this character only. |cFFFF4400This cannot be undone.|r", "small")
    resetDesc:SetWordWrap(true)
    list:Add(resetDesc, 28)
    local resetBtn = Kit:Button(content, "Reset Addon (Local)", function()
        StaticPopup_Show("PP_CONFIRM_RESET_ADDON")
    end, "danger")
    resetBtn:SetSize(180, 22)
    list:Add(resetBtn, 22, 6, false)

    list:Layout()
end

---------------------------------------------------------------------------
-- Static popups
---------------------------------------------------------------------------
StaticPopupDialogs["PP_CONFIRM_REMOVE_PLAYER"] = {
    text = "Remove this player from the roster?",
    button1 = "Remove",
    button2 = "Cancel",
    OnAccept = function()
        if PP._pendingRemovePlayer then
            PP._selectedRosterPlayer = nil
            PP.Roster:Remove(PP._pendingRemovePlayer)
            PP._pendingRemovePlayer = nil
        end
    end,
    OnCancel = function() PP._pendingRemovePlayer = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["PP_CONFIRM_RANDOMIZE"] = {
    text = "Randomize the roster order?\nThis will reassign all scores and |cFFFF4400cannot be undone|r.",
    button1 = "Randomize", button2 = "Cancel",
    OnAccept = function() PP.Roster:Randomize() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["PP_CONFIRM_CLEAR_ROSTER"] = {
    text = "Are you sure you want to clear the entire roster?",
    button1 = "Yes", button2 = "No",
    OnAccept = function() PP.Roster:Clear() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["PP_CONFIRM_RESET_ADDON"] = {
    text = "Reset ALL Pirates Plunder saved data for this character?\n|cFFFF4400This cannot be undone.|r",
    button1 = "Reset", button2 = "Cancel",
    OnAccept = function() PP:ResetAddon() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["PP_CONFIRM_DELETE_GUILD_ROSTER"] = {
    text = "Delete this guild roster from your client?\n|cFFFF4400This only affects your local data.|r",
    button1 = "Delete Locally", button2 = "Cancel",
    OnAccept = function()
        if PP._pendingDeleteGuildRoster then
            PP:DeleteGuildRoster(PP._pendingDeleteGuildRoster)
            PP._pendingDeleteGuildRoster = nil
        end
    end,
    OnCancel = function() PP._pendingDeleteGuildRoster = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["PP_CONTINUE_RAID"] = {
    text = "Pirates Plunder\n\nWould you like to continue the active session?",
    button1 = "Continue Session", button2 = "End Session",
    OnAccept = function()
        local id = PP._pendingContinueRaidID
        if id then
            local gk = PP:GetActiveGuildKey()
            local gd = PP.Repo.Roster:GetData(gk)
            if gd and gd.sessions and gd.sessions[id] then
                gd.sessions[id].leader = PP:GetPlayerFullName()
                PP:Print("You are now leading the session: " .. (gd.sessions[id].name or id))
            end
            PP._pendingContinueRaidID = nil
        end
    end,
    OnCancel = function()
        PP._pendingContinueRaidID = nil
        PP.Session:End(PP.SESSION_END.OFFICER_ACTION)
    end,
    timeout = 0, whileDead = true, hideOnEscape = false,
}

StaticPopupDialogs["PP_CONFIRM_DELETE_RAID"] = {
    text = "Permanently delete this session?\n\n|cFFFF4400All loot and boss records will be erased for you and all online raid members.|r",
    button1 = "Delete", button2 = "Cancel",
    OnAccept = function()
        if PP._pendingDeleteRaidID then
            PP.Session:Delete(PP._pendingDeleteRaidID)
            PP._pendingDeleteRaidID = nil
        end
    end,
    OnCancel = function() PP._pendingDeleteRaidID = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
