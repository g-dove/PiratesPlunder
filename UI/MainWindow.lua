---------------------------------------------------------------------------
-- Pirates Plunder – Main Window UI (Roster + Raids tabs)
---------------------------------------------------------------------------
local PP  = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")
local AceGUI = PP.AceGUI

---------------------------------------------------------------------------
-- Toggle
---------------------------------------------------------------------------
function PP:ToggleMainWindow()
    if self.mainWindow then
        self.mainWindow:Release()
        self.mainWindow = nil
        return
    end
    self:CreateMainWindow()
end

function PP:RefreshMainWindow()
    if not self.mainWindow then return end
    if self._currentTab == "roster" then
        self:DrawRosterTab(self._tabContainer)
    elseif self._currentTab == "raids" then
        self:DrawRaidsTab(self._tabContainer)
    elseif self._currentTab == "settings" then
        self:DrawSettingsTab(self._tabContainer)
    end
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------
function PP:CreateMainWindow()
    local f = AceGUI:Create("Frame")
    f:SetTitle("Pirates Plunder")
    f:SetLayout("Fill")
    f:SetWidth(740)
    f:SetHeight(580)
    f:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        PP.mainWindow = nil
    end)
    self.mainWindow = f

    -- Make ESC close this window
    local frameName = "PPMainWindowFrame"
    _G[frameName] = f.frame
    tinsert(UISpecialFrames, frameName)

    local tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetLayout("Fill")
    tabGroup:SetTabs({
        { value = "roster",   text = "Roster" },
        { value = "raids",    text = "Raids" },
        { value = "settings", text = "Settings" },
    })
    tabGroup:SetCallback("OnGroupSelected", function(container, _, group)
        container:ReleaseChildren()
        self._currentTab   = group
        self._tabContainer = container
        if group == "roster" then
            self:DrawRosterTab(container)
        elseif group == "raids" then
            self:DrawRaidsTab(container)
        elseif group == "settings" then
            self:DrawSettingsTab(container)
        end
    end)
    f:AddChild(tabGroup)
    tabGroup:SelectTab("roster")
end

---------------------------------------------------------------------------
-- Roster tab
---------------------------------------------------------------------------
function PP:DrawRosterTab(container)
    container:ReleaseChildren()
    -- Always re-check officer status in case guild roster was not ready earlier
    PP:RefreshOfficerStatus()
    local canModify = self:CanModify()

    -- Strips any lingering mouse scripts from a recycled AceGUI SimpleGroup frame.
    local function scrubFrame(sg)
        sg.frame:EnableMouse(false)
        sg.frame:SetScript("OnMouseDown", nil)
        sg.frame:SetScript("OnEnter",    nil)
        sg.frame:SetScript("OnLeave",    nil)
        if sg.frame._ppHlTex then
            sg.frame._ppHlTex:SetColorTexture(0, 0, 0, 0)
        end
    end

    -- Single ScrollFrame as the sole Fill child of the tab container
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    scroll:SetLayout("List")
    container:AddChild(scroll)

    -- ── Roster selector ──────────────────────────────────────────────────
    if not PP:IsSandbox() then
        local ddGroup = AceGUI:Create("SimpleGroup")
        ddGroup:SetFullWidth(true)
        ddGroup:SetLayout("Flow")
        scrubFrame(ddGroup)
        scroll:AddChild(ddGroup)

        local dd = AceGUI:Create("Dropdown")
        dd:SetLabel("Active Roster")
        dd:SetWidth(220)
        local ddItems = {}
        for gk in pairs(self.db.global.guilds) do
            ddItems[gk] = PP:GetRosterDisplayName(gk)
        end
        dd:SetList(ddItems)
        dd:SetValue(PP:GetActiveGuildKey())
        dd:SetCallback("OnValueChanged", function(_, _, val)
            PP._activeGuildKey = val
            PP._selectedRosterPlayer = nil
            PP:DrawRosterTab(container)
        end)
        ddGroup:AddChild(dd)

        if canModify then
            local newBtn = AceGUI:Create("Button")
            newBtn:SetText("New Roster")
            newBtn:SetWidth(110)
            newBtn:SetCallback("OnClick", function()
                StaticPopup_Show("PP_CREATE_ROSTER")
            end)
            ddGroup:AddChild(newBtn)
        end
    end

    -- Top bar: add player + roster management
    local topGroup = AceGUI:Create("SimpleGroup")
    topGroup:SetFullWidth(true)
    topGroup:SetLayout("Flow")
    scrubFrame(topGroup)
    scroll:AddChild(topGroup)

    if canModify then
        local addBox = AceGUI:Create("EditBox")
        addBox:SetLabel("Add Player")
        addBox:SetWidth(200)
        addBox:SetCallback("OnEnterPressed", function(widget, _, text)
            if text and text:trim() ~= "" then
                PP:AddToRoster(text:trim())
                widget:SetText("")
            end
        end)
        topGroup:AddChild(addBox)

        local randBtn = AceGUI:Create("Button")
        randBtn:SetText("Randomize Order")
        randBtn:SetWidth(140)
        randBtn:SetCallback("OnClick", function()
            StaticPopup_Show("PP_CONFIRM_RANDOMIZE")
        end)
        topGroup:AddChild(randBtn)

        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear Roster")
        clearBtn:SetWidth(120)
        clearBtn:SetCallback("OnClick", function()
            StaticPopup_Show("PP_CONFIRM_CLEAR_ROSTER")
        end)
        topGroup:AddChild(clearBtn)
    end

    -- ── Actions section ───────────────────────────────────────────────────
    if canModify then
        local actionsHead = AceGUI:Create("Heading")
        actionsHead:SetFullWidth(true)
        actionsHead:SetText("Actions")
        scroll:AddChild(actionsHead)

        -- ── Selection subsection ──────────────────────────────────────────
        local selSubHead = AceGUI:Create("Label")
        selSubHead:SetFullWidth(true)
        selSubHead:SetText("|cFFFFD100Selection|r")
        scroll:AddChild(selSubHead)

        local sel      = PP._selectedRosterPlayer
        local selEntry = nil
        if sel then
            for _, e in ipairs(self:GetSortedRoster()) do
                if e.fullName == sel then selEntry = e; break end
            end
        end
        local hasSelection = selEntry ~= nil
        
        local selPadTop = AceGUI:Create("Label")
        selPadTop:SetFullWidth(true)
        selPadTop:SetText(" ")
        selPadTop:SetHeight(20)
        scroll:AddChild(selPadTop)

        local selHint = AceGUI:Create("Label")
        selHint:SetFullWidth(true)
        selHint:SetText(hasSelection
            and ("|cFFAAAAAA  Editing: |r|cFFFFD100" .. selEntry.name .. "|r")
            or  "|cFFAAAAAA  Click a row below to select a player.|r")
        scroll:AddChild(selHint)

        local selRow = AceGUI:Create("SimpleGroup")
        selRow:SetFullWidth(true)
        selRow:SetLayout("Flow")
        scrubFrame(selRow)
        scroll:AddChild(selRow)

        local scoreBox = AceGUI:Create("EditBox")
        scoreBox:SetLabel("")
        scoreBox:SetWidth(60)
        scoreBox:SetText(hasSelection and tostring(selEntry.score) or "")
        scoreBox:SetDisabled(not hasSelection)
        scoreBox:SetCallback("OnEnterPressed", function(widget, _, text)
            if not selEntry then return end
            local val = tonumber(text)
            if val then
                PP:SetPlayerScore(sel, val)
            else
                widget:SetText(tostring(selEntry.score))
            end
        end)
        selRow:AddChild(scoreBox)

        local plusBtn = AceGUI:Create("Button")
        plusBtn:SetText("+1")
        plusBtn:SetWidth(50)
        plusBtn:SetDisabled(not hasSelection)
        plusBtn:SetCallback("OnClick", function()
            if selEntry then PP:SetPlayerScore(sel, selEntry.score + 1) end
        end)
        selRow:AddChild(plusBtn)

        local minusBtn = AceGUI:Create("Button")
        minusBtn:SetText("-1")
        minusBtn:SetWidth(50)
        minusBtn:SetDisabled(not hasSelection)
        minusBtn:SetCallback("OnClick", function()
            if selEntry then PP:SetPlayerScore(sel, math.max(0, selEntry.score - 1)) end
        end)
        selRow:AddChild(minusBtn)

        local removeBtn = AceGUI:Create("Button")
        removeBtn:SetText("Remove")
        removeBtn:SetWidth(80)
        removeBtn:SetDisabled(not hasSelection)
        removeBtn:SetCallback("OnClick", function()
            if selEntry then
                PP._pendingRemovePlayer = sel
                StaticPopup_Show("PP_CONFIRM_REMOVE_PLAYER")
            end
        end)
        selRow:AddChild(removeBtn)

        local selPad = AceGUI:Create("Label")
        selPad:SetFullWidth(true)
        selPad:SetText(" ")
        selPad:SetHeight(20)
        scroll:AddChild(selPad)

        -- ── Group Actions subsection ───────────────────────────────────────
        local groupSubHead = AceGUI:Create("Label")
        groupSubHead:SetFullWidth(true)
        groupSubHead:SetText("|cFFFFD100Group Actions|r")
        scroll:AddChild(groupSubHead)

        local groupRow = AceGUI:Create("SimpleGroup")
        groupRow:SetFullWidth(true)
        groupRow:SetLayout("Flow")
        scrubFrame(groupRow)
        scroll:AddChild(groupRow)

        local bulkAmountBox = AceGUI:Create("EditBox")
        bulkAmountBox:SetLabel("Amount")
        bulkAmountBox:SetWidth(100)
        bulkAmountBox:SetText("1")
        groupRow:AddChild(bulkAmountBox)

        local applyBtn = AceGUI:Create("Button")
        applyBtn:SetText("Apply to Group")
        applyBtn:SetWidth(130)
        applyBtn:SetCallback("OnClick", function()
            if not IsInGroup() then
                PP:Print("You must be in a group.")
                return
            end
            local amt = tonumber(bulkAmountBox:GetText())
            if not amt then
                PP:Print("Enter a valid number.")
                return
            end
            PP:AddScoreToRaidMembers(amt)
        end)
        groupRow:AddChild(applyBtn)

        local plusOneBtn = AceGUI:Create("Button")
        plusOneBtn:SetText("+1 to Group")
        plusOneBtn:SetWidth(120)
        plusOneBtn:SetCallback("OnClick", function()
            if not IsInGroup() then
                PP:Print("You must be in a group.")
                return
            end
            PP:AddScoreToRaidMembers(1)
        end)
        groupRow:AddChild(plusOneBtn)

        local bulkDesc = AceGUI:Create("Label")
        bulkDesc:SetFullWidth(true)
        bulkDesc:SetText("|cFFAAAAAA  Group actions adjust score for all roster members currently in your group.\n|r")
        scroll:AddChild(bulkDesc)
    end

    -- Player Roster heading
    local heading = AceGUI:Create("Heading")
    heading:SetFullWidth(true)
    heading:SetText("Player Roster  (sorted by score)")
    scroll:AddChild(heading)

    -- Column headers
    local headerRow = AceGUI:Create("SimpleGroup")
    headerRow:SetFullWidth(true)
    headerRow:SetLayout("Flow")
    scrubFrame(headerRow)
    scroll:AddChild(headerRow)

    local h1 = AceGUI:Create("Label")
    h1:SetText("|cFFFFD100#|r")
    h1:SetWidth(30)
    headerRow:AddChild(h1)

    local h2 = AceGUI:Create("Label")
    h2:SetText("|cFFFFD100Name|r")
    h2:SetWidth(200)
    headerRow:AddChild(h2)

    local h3 = AceGUI:Create("Label")
    h3:SetText("|cFFFFD100Realm|r")
    h3:SetWidth(150)
    headerRow:AddChild(h3)

    local h4 = AceGUI:Create("Label")
    h4:SetText("|cFFFFD100Score|r")
    h4:SetWidth(60)
    headerRow:AddChild(h4)

    -- Player rows
    local sorted  = self:GetSortedRoster()
    local raidSet = self:GetRaidMemberSet()

    local padTop = AceGUI:Create("Label")
    padTop:SetFullWidth(true)
    padTop:SetText(" ")
    padTop:SetHeight(4)
    scroll:AddChild(padTop)

    for idx, entry in ipairs(sorted) do
        local isSelected = canModify and (PP._selectedRosterPlayer == entry.fullName)

        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Flow")

        -- Reuse or create a single highlight texture per frame (frames are recycled by AceGUI,
        -- so CreateTexture must not be called unconditionally or textures accumulate).
        -- The texture bleeds 4px above and below to visually cover the padding spacers.
        if not row.frame._ppHlTex then
            row.frame._ppHlTex = row.frame:CreateTexture(nil, "BACKGROUND")
            row.frame._ppHlTex:SetPoint("TOPLEFT",     row.frame, "TOPLEFT",     0,  4)
            row.frame._ppHlTex:SetPoint("BOTTOMRIGHT", row.frame, "BOTTOMRIGHT", 0, -4)
        end
        local hlTex = row.frame._ppHlTex

        if canModify then
            row.frame:EnableMouse(true)
            row.frame:SetScript("OnMouseDown", function()
                if PP._selectedRosterPlayer == entry.fullName then
                    PP._selectedRosterPlayer = nil
                else
                    PP._selectedRosterPlayer = entry.fullName
                end
                PP:DrawRosterTab(container)
            end)

            if isSelected then
                hlTex:SetColorTexture(1, 0.85, 0, 0.15)
                row.frame:SetScript("OnEnter", nil)
                row.frame:SetScript("OnLeave", nil)
            else
                hlTex:SetColorTexture(0, 0, 0, 0)
                row.frame:SetScript("OnEnter", function() hlTex:SetColorTexture(1, 1, 1, 0.07) end)
                row.frame:SetScript("OnLeave", function() hlTex:SetColorTexture(0, 0, 0, 0) end)
            end
        else
            -- Read-only: no interaction, clear any highlight left on a recycled frame
            hlTex:SetColorTexture(0, 0, 0, 0)
            row.frame:EnableMouse(false)
            row.frame:SetScript("OnMouseDown", nil)
            row.frame:SetScript("OnEnter", nil)
            row.frame:SetScript("OnLeave", nil)
        end

        local nameColor = raidSet[entry.fullName] and "|cFF00FF00" or "|cFFAAAAAA"

        local numLabel = AceGUI:Create("Label")
        numLabel:SetText(tostring(idx))
        numLabel:SetWidth(30)
        row:AddChild(numLabel)

        local nameLabel = AceGUI:Create("Label")
        nameLabel:SetText(nameColor .. entry.name .. "|r")
        nameLabel:SetWidth(200)
        row:AddChild(nameLabel)

        local realmLabel = AceGUI:Create("Label")
        realmLabel:SetText(entry.realm)
        realmLabel:SetWidth(150)
        row:AddChild(realmLabel)

        local scoreLabel = AceGUI:Create("Label")
        scoreLabel:SetText("|cFFFFFF00" .. tostring(entry.score) .. "|r")
        scoreLabel:SetWidth(60)
        row:AddChild(scoreLabel)

        scroll:AddChild(row)

        local padBot = AceGUI:Create("Label")
        padBot:SetFullWidth(true)
        padBot:SetText(" ")
        padBot:SetHeight(4)
        scroll:AddChild(padBot)
    end

    if #sorted == 0 then
        local empty = AceGUI:Create("Label")
        empty:SetFullWidth(true)
        empty:SetText("\n  No players in roster. Join a raid or add players manually.")
        scroll:AddChild(empty)
    end
end

---------------------------------------------------------------------------
-- Raids tab
---------------------------------------------------------------------------
function PP:DrawRaidsTab(container)
    container:ReleaseChildren()
    local canModify = self:CanModify()

    -- Single ScrollFrame as the sole Fill child of the tab container
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    scroll:SetLayout("List")
    container:AddChild(scroll)

    -- ── Roster selector ──────────────────────────────────────────────────
    if not PP:IsSandbox() then
        local ddGroup = AceGUI:Create("SimpleGroup")
        ddGroup:SetFullWidth(true)
        ddGroup:SetLayout("Flow")
        scroll:AddChild(ddGroup)

        local dd = AceGUI:Create("Dropdown")
        dd:SetLabel("Active Roster")
        dd:SetWidth(220)
        local ddItems = {}
        for gk in pairs(self.db.global.guilds) do
            ddItems[gk] = PP:GetRosterDisplayName(gk)
        end
        dd:SetList(ddItems)
        dd:SetValue(PP:GetActiveGuildKey())
        dd:SetCallback("OnValueChanged", function(_, _, val)
            PP._activeGuildKey = val
            PP:DrawRaidsTab(container)
        end)
        ddGroup:AddChild(dd)
    end

    -- Top bar
    local topGroup = AceGUI:Create("SimpleGroup")
    topGroup:SetFullWidth(true)
    topGroup:SetLayout("Flow")
    scroll:AddChild(topGroup)

    if canModify then
        local nameBox = AceGUI:Create("EditBox")
        nameBox:SetLabel("Raid Name")
        nameBox:SetWidth(200)
        nameBox:SetText(date("%Y-%m-%d") .. " Raid")
        topGroup:AddChild(nameBox)
        self._raidNameBox = nameBox

        if self:HasActiveRaid() then
            local closeBtn = AceGUI:Create("Button")
            closeBtn:SetText("Close Raid")
            closeBtn:SetWidth(120)
            closeBtn:SetCallback("OnClick", function()
                PP:EndRaid()
            end)
            topGroup:AddChild(closeBtn)
        else
            local createBtn = AceGUI:Create("Button")
            createBtn:SetText("Create Raid")
            createBtn:SetWidth(120)
            createBtn:SetCallback("OnClick", function()
                local raidName = nameBox:GetText()
                PP:CreateRaid(raidName)
            end)
            topGroup:AddChild(createBtn)
        end
    end

    -- Active raid indicator
    if self:HasActiveRaid() then
        local raid = self:GetActiveRaid()
        local activeLabel = AceGUI:Create("Label")
        activeLabel:SetFullWidth(true)
        activeLabel:SetText("|cFF00FF00Active Raid:|r " .. (raid and raid.name or "Unknown"))
        scroll:AddChild(activeLabel)
    end

    -- Raid history heading
    local heading = AceGUI:Create("Heading")
    heading:SetFullWidth(true)
    heading:SetText("Raid History")
    scroll:AddChild(heading)

    -- Raid rows
    local history = self:GetRaidHistory()

    for _, raid in ipairs(history) do
        local row = AceGUI:Create("InteractiveLabel")
        row:SetFullWidth(true)

        local status = raid.active and "|cFF00FF00[ACTIVE]|r " or "|cFF888888[ENDED]|r "
        local dateStr = date("%Y-%m-%d %H:%M", raid.startTime)
        local text = status .. raid.name .. "  |cFF888888(" .. dateStr .. ")|r"
            .. "  Bosses: " .. raid.bossCount .. "  Items: " .. raid.itemCount

        row:SetText(text)
        row:SetHighlight(1, 1, 1, 0.1)
        row:SetCallback("OnClick", function()
            PP:ShowRaidDetail(raid.id)
        end)
        scroll:AddChild(row)
    end

    if #history == 0 then
        local empty = AceGUI:Create("Label")
        empty:SetFullWidth(true)
        empty:SetText("\n  No raids recorded yet.")
        scroll:AddChild(empty)
    end
end

---------------------------------------------------------------------------
-- Raid detail popup (items + bosses)
---------------------------------------------------------------------------
function PP:ShowRaidDetail(raidID)
    -- Search all guild data blocks since the raid may belong to any guild
    local raid
    for _, gd in pairs(self.db.global.guilds) do
        if gd.raids and gd.raids[raidID] then
            raid = gd.raids[raidID]
            break
        end
    end
    if not raid then return end

    -- If a detail window is already open, close it
    if self._raidDetailWindow then
        self._raidDetailWindow:Release()
        self._raidDetailWindow = nil
    end

    local f = AceGUI:Create("Frame")
    f:SetTitle(raid.name or "Raid Detail")
    f:SetLayout("Fill")
    f:SetWidth(550)
    f:SetHeight(450)
    f:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        PP._raidDetailWindow = nil
    end)
    self._raidDetailWindow = f

    -- Make ESC close this window
    local detailFrameName = "PPRaidDetailFrame"
    _G[detailFrameName] = f.frame
    tinsert(UISpecialFrames, detailFrameName)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    scroll:SetLayout("List")
    f:AddChild(scroll)

    -- Info
    local info = AceGUI:Create("Label")
    info:SetFullWidth(true)
    local startStr = date("%Y-%m-%d %H:%M", raid.startTime)
    local endStr   = raid.endTime and date("%Y-%m-%d %H:%M", raid.endTime) or "In Progress"
    info:SetText("Leader: " .. self:GetShortName(raid.leader)
        .. "\nStarted: " .. startStr
        .. "\nEnded: " .. endStr)
    scroll:AddChild(info)

    -- Bosses
    local bossHead = AceGUI:Create("Heading")
    bossHead:SetFullWidth(true)
    bossHead:SetText("Boss Kills (" .. #raid.bosses .. ")")
    scroll:AddChild(bossHead)

    for _, boss in ipairs(raid.bosses) do
        local bossLabel = AceGUI:Create("Label")
        bossLabel:SetFullWidth(true)
        bossLabel:SetText("  " .. boss.encounterName .. "  |cFF888888" .. date("%H:%M", boss.time) .. "|r")
        scroll:AddChild(bossLabel)
    end
    if #raid.bosses == 0 then
        local nb = AceGUI:Create("Label")
        nb:SetFullWidth(true)
        nb:SetText("  No bosses killed.")
        scroll:AddChild(nb)
    end

    -- Items
    local itemHead = AceGUI:Create("Heading")
    itemHead:SetFullWidth(true)
    itemHead:SetText("Awarded Items (" .. #raid.items .. ")")
    scroll:AddChild(itemHead)

    for _, item in ipairs(raid.items) do
        local ptsStr  = item.pointsSpent and ("  |cFFFFFF00" .. item.pointsSpent .. " pts|r") or ""
        local respStr = item.response    and ("  |cFF888888[" .. item.response .. "]|r")       or ""
        local itemRow = AceGUI:Create("Label")
        itemRow:SetFullWidth(true)
        itemRow:SetText("  " .. (item.itemLink or "Unknown") .. "  →  "
            .. self:GetShortName(item.awardedTo) .. ptsStr .. respStr)
        scroll:AddChild(itemRow)
    end
    if #raid.items == 0 then
        local ni = AceGUI:Create("Label")
        ni:SetFullWidth(true)
        ni:SetText("  No items awarded.")
        scroll:AddChild(ni)
    end
end

---------------------------------------------------------------------------
-- Settings tab
---------------------------------------------------------------------------
function PP:DrawSettingsTab(container)
    container:ReleaseChildren()

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    scroll:SetLayout("List")
    container:AddChild(scroll)

    -- ── Sandbox active banner (command-line toggled, no UI button needed) ────
    if PP:IsSandbox() then
        local banner = AceGUI:Create("Label")
        banner:SetFullWidth(true)
        banner:SetText("|cFFFFD100SANDBOX ACTIVE — simulating raid leader. Roster, raid, and loot changes are NOT saved to disk.\nUse /pp sandbox to disable  ·  /pp sandbox mod to toggle raid leader/officer status.|r\n")
        scroll:AddChild(banner)
    end

    -- ── Sync section ─────────────────────────────────────────────────────
    local syncHead = AceGUI:Create("Heading")
    syncHead:SetFullWidth(true)
    syncHead:SetText("Synchronisation")
    scroll:AddChild(syncHead)

    local syncDesc = AceGUI:Create("Label")
    syncDesc:SetFullWidth(true)
    syncDesc:SetText("Request a full roster and raid sync from any online officer in your current group.\n")
    scroll:AddChild(syncDesc)

    local syncGroup = AceGUI:Create("SimpleGroup")
    syncGroup:SetFullWidth(true)
    syncGroup:SetLayout("Flow")
    scroll:AddChild(syncGroup)

    local syncBtn = AceGUI:Create("Button")
    syncBtn:SetText("Request Sync")
    syncBtn:SetWidth(140)
    syncBtn:SetCallback("OnClick", function()
        if not IsInGroup() then
            PP:Print("You must be in a group to request a sync.")
        else
            PP:RequestSync()
            PP:Print("Sync requested.")
        end
    end)
    syncGroup:AddChild(syncBtn)

    if PP:CanModify() then
        local broadcastBtn = AceGUI:Create("Button")
        broadcastBtn:SetText("Broadcast Roster")
        broadcastBtn:SetWidth(160)
        broadcastBtn:SetCallback("OnClick", function()
            if not IsInGroup() then
                PP:Print("You must be in a group to broadcast.")
            else
                PP:BroadcastRoster()
                PP:Print("Roster broadcast to group.")
            end
        end)
        syncGroup:AddChild(broadcastBtn)
    end

    -- ── Manage Custom Rosters section ───────────────────────────────────────
    local manageHead = AceGUI:Create("Heading")
    manageHead:SetFullWidth(true)
    manageHead:SetText("Manage Custom Rosters")
    scroll:AddChild(manageHead)

    -- Collect only custom (non-guild) roster keys
    local customKeys = {}
    for gk in pairs(PP.db.global.guilds) do
        if PP:IsCustomRoster(gk) then
            customKeys[#customKeys + 1] = gk
        end
    end
    table.sort(customKeys, function(a, b)
        return PP:GetRosterDisplayName(a) < PP:GetRosterDisplayName(b)
    end)

    if #customKeys == 0 then
        local noCustom = AceGUI:Create("Label")
        noCustom:SetFullWidth(true)
        noCustom:SetText("|cFFAAAAAA  No custom rosters yet. Use the 'New Roster' button on the Roster tab to create one.\n|r")
        scroll:AddChild(noCustom)
    else
        local manageRow = AceGUI:Create("SimpleGroup")
        manageRow:SetFullWidth(true)
        manageRow:SetLayout("Flow")
        scroll:AddChild(manageRow)

        local manageDd = AceGUI:Create("Dropdown")
        manageDd:SetLabel("Custom Roster")
        manageDd:SetWidth(180)
        local manageItems = {}
        for _, gk in ipairs(customKeys) do
            manageItems[gk] = PP:GetRosterDisplayName(gk)
        end
        manageDd:SetList(manageItems)
        manageDd:SetValue(customKeys[1])
        manageRow:AddChild(manageDd)

        local renameBox = AceGUI:Create("EditBox")
        renameBox:SetLabel("New Name")
        renameBox:SetWidth(150)
        renameBox:SetText(PP:GetRosterDisplayName(customKeys[1]))
        manageDd:SetCallback("OnValueChanged", function(_, _, val)
            renameBox:SetText(PP:GetRosterDisplayName(val))
        end)
        manageRow:AddChild(renameBox)

        local renameBtn = AceGUI:Create("Button")
        renameBtn:SetText("Rename")
        renameBtn:SetWidth(90)
        renameBtn:SetCallback("OnClick", function()
            local selectedKey = manageDd:GetValue()
            local newName = renameBox:GetText()
            if selectedKey and newName and newName:trim() ~= "" then
                PP:RenameCustomRoster(selectedKey, newName:trim())
            end
        end)
        manageRow:AddChild(renameBtn)
    end

    -- ── Loot Rules section
    local lootRulesHead = AceGUI:Create("Heading")
    lootRulesHead:SetFullWidth(true)
    lootRulesHead:SetText("Loot Rules")
    scroll:AddChild(lootRulesHead)

    local tmogChk = AceGUI:Create("CheckBox")
    tmogChk:SetFullWidth(true)
    tmogChk:SetLabel("Allow Transmog rolls")
    tmogChk:SetValue(PP.db.global.allowTransmogRolls ~= false)
    tmogChk:SetCallback("OnValueChanged", function(_, _, val)
        PP.db.global.allowTransmogRolls = val
    end)
    scroll:AddChild(tmogChk)

    local tmogDesc = AceGUI:Create("Label")
    tmogDesc:SetFullWidth(true)
    tmogDesc:SetText("|cFFAAAAAA  When enabled, raid members see a Transmog button when voting on loot.\n  Takes effect on the next item posted.\n|r")
    scroll:AddChild(tmogDesc)

    -- Auto-pass in-game Epic+ rolls
    local isLeader = PP:IsRaidLeaderOrAssist()
    local autoPassChk = AceGUI:Create("CheckBox")
    autoPassChk:SetFullWidth(true)
    autoPassChk:SetLabel("Auto-pass in-game Epic+ loot rolls for non-leaders")
    autoPassChk:SetValue(PP.db.global.autoPassEpicRolls == true)
    if not isLeader then
        autoPassChk:SetDisabled(true)
    end
    autoPassChk:SetCallback("OnValueChanged", function(_, _, val)
        if not PP:IsRaidLeaderOrAssist() then return end
        PP.db.global.autoPassEpicRolls = val
        PP:BroadcastRaidSettings()
    end)
    scroll:AddChild(autoPassChk)

    local autoPassDesc = AceGUI:Create("Label")
    autoPassDesc:SetFullWidth(true)
    if isLeader then
        autoPassDesc:SetText("|cFFAAAAAA  When enabled, raiders who are not the raid leader or an officer will\n  automatically Pass on in-game loot rolls at Epic quality or higher.\n  Syncs to all group members when toggled.\n|r")
    else
        autoPassDesc:SetText("|cFFAAAAAA  Controlled by the raid leader. When active, you will automatically\n  Pass on in-game rolls for Epic+ items.\n|r")
    end
    scroll:AddChild(autoPassDesc)

    -- Status section
    local statusHead = AceGUI:Create("Heading")
    statusHead:SetFullWidth(true)
    statusHead:SetText("Status")
    scroll:AddChild(statusHead)

    local guildKey  = PP:GetActiveGuildKey()
    local myGuild   = PP:GetPlayerGuild() or "|cFFAAAAAAnone|r"
    local officer   = PP:IsOfficerOrHigher() and "|cFF00FF00Yes|r" or "|cFFFF4400No|r"
    local canMod    = PP:CanModify()          and "|cFF00FF00Yes|r" or "|cFFFF4400No|r"
    local gd        = PP:GetGuildData(guildKey)
    local rVer      = gd and gd.rosterVersion or 0
    local inGroup   = IsInGroup()             and "|cFF00FF00Yes|r" or "|cFFAAAAAA No|r"

    local statusLabel = AceGUI:Create("Label")
    statusLabel:SetFullWidth(true)
    statusLabel:SetText(
        "Active roster:  |cFFFFD100" .. PP:GetRosterDisplayName(guildKey) .. "|r\n"
     .. "My guild:  " .. myGuild .. "\n"
     .. "Officer:  " .. officer .. "\n"
     .. "Can modify:  " .. canMod .. "\n"
     .. "Roster version:  |cFFFFFFFF" .. rVer .. "|r\n"
     .. "In group:  " .. inGroup
    )
    scroll:AddChild(statusLabel)

    -- Reset section
    local resetHead = AceGUI:Create("Heading")
    resetHead:SetFullWidth(true)
    resetHead:SetText("Reset")
    scroll:AddChild(resetHead)

    local resetDesc = AceGUI:Create("Label")
    resetDesc:SetFullWidth(true)
    resetDesc:SetText(
        "Reset clears all saved data for this character only (roster, raids, pending loot).\n"
     .. "|cFFFF4400This cannot be undone.|r\n"
    )
    scroll:AddChild(resetDesc)

    local resetBtn = AceGUI:Create("Button")
    resetBtn:SetText("Reset Addon (Local)")
    resetBtn:SetWidth(180)
    resetBtn:SetCallback("OnClick", function()
        StaticPopup_Show("PP_CONFIRM_RESET_ADDON")
    end)
    scroll:AddChild(resetBtn)
end

---------------------------------------------------------------------------
-- Static popup for clear-roster confirmation
---------------------------------------------------------------------------
StaticPopupDialogs["PP_CONFIRM_REMOVE_PLAYER"] = {
    text = "Remove this player from the roster?",
    button1 = "Remove",
    button2 = "Cancel",
    OnAccept = function()
        if PP._pendingRemovePlayer then
            PP._selectedRosterPlayer = nil
            PP:RemoveFromRoster(PP._pendingRemovePlayer)
            PP._pendingRemovePlayer = nil
        end
    end,
    OnCancel = function()
        PP._pendingRemovePlayer = nil
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["PP_CONFIRM_RANDOMIZE"] = {
    text = "Randomize the roster order?\nThis will reassign all scores and |cFFFF4400cannot be undone|r.",
    button1 = "Randomize",
    button2 = "Cancel",
    OnAccept = function()
        PP:RandomizeRosterOrder()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["PP_CONFIRM_CLEAR_ROSTER"] = {
    text = "Are you sure you want to clear the entire Pirates Plunder roster?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        PP:ClearRoster()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["PP_CREATE_ROSTER"] = {
    text = "Enter a name for the new roster:",
    button1 = "Create",
    button2 = "Cancel",
    hasEditBox = 1,
    OnAccept = function(dialog)
        local name = dialog.editBox:GetText()
        if name and name:trim() ~= "" then
            PP:CreateCustomRoster(name)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["PP_CONFIRM_RESET_ADDON"] = {
    text = "Reset ALL Pirates Plunder saved data for this character?\n|cFFFF4400This cannot be undone.|r",
    button1 = "Reset",
    button2 = "Cancel",
    OnAccept = function()
        PP:ResetAddon()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}
