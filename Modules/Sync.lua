---------------------------------------------------------------------------
-- Pirates Plunder – Sync (AceComm messaging)
---------------------------------------------------------------------------
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

---------------------------------------------------------------------------
-- Send a structured message to the raid / party
---------------------------------------------------------------------------
function PP:SendAddonMessage(msgType, data, target)
    -- Never broadcast real messages while in sandbox mode
    if self._sandbox then return end
    local payload = self:Serialize(msgType, data)
    if target then
        self:SendCommMessage(PP.COMM_PREFIX, payload, "WHISPER", target)
    elseif IsInRaid() then
        self:SendCommMessage(PP.COMM_PREFIX, payload, "RAID")
    elseif IsInGroup() then
        self:SendCommMessage(PP.COMM_PREFIX, payload, "PARTY")
    end
end

---------------------------------------------------------------------------
-- Incoming message handler  (called by AceComm)
---------------------------------------------------------------------------
function PP:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= PP.COMM_PREFIX then return end

    local success, msgType, data = self:Deserialize(message)
    if not success then return end

    -- Ignore our own messages
    local me = self:GetPlayerFullName()
    sender = self:GetFullName(sender)
    if sender == me then return end

    -- Dispatch
    if msgType == PP.MSG.SYNC_REQUEST then
        self:HandleSyncRequest(sender, data)

    elseif msgType == PP.MSG.SYNC_FULL then
        self:HandleSyncFull(data, sender)

    elseif msgType == PP.MSG.ROSTER_UPDATE then
        self:HandleRosterUpdate(data, sender)

    elseif msgType == PP.MSG.RAID_CREATE then
        self:HandleRaidCreate(data, sender)

    elseif msgType == PP.MSG.RAID_CLOSE then
        self:HandleRaidClose(data, sender)

    elseif msgType == PP.MSG.SCORE_UPDATE then
        self:HandleScoreUpdate(data, sender)

    elseif msgType == PP.MSG.LOOT_POST then
        self:HandleLootPost(data, sender)

    elseif msgType == PP.MSG.LOOT_INTEREST then
        self:HandleLootInterest(data, sender)

    elseif msgType == PP.MSG.LOOT_AWARD then
        self:HandleLootAward(data, sender)

    elseif msgType == PP.MSG.LOOT_CANCEL then
        self:HandleLootCancel(data, sender)

    elseif msgType == PP.MSG.LOOT_UPDATE then
        self:HandleLootUpdate(data)

    elseif msgType == PP.MSG.RAID_SETTINGS then
        self:HandleRaidSettings(data, sender)

    elseif msgType == PP.MSG.RAID_DELETE then
        self:HandleRaidDelete(data, sender)

    elseif msgType == PP.MSG.VERSION_REQUEST then
        self:HandleVersionRequest(sender)

    elseif msgType == PP.MSG.VERSION_REPLY then
        self:HandleVersionReply(data, sender)
    end
end

---------------------------------------------------------------------------
-- Version check handlers
---------------------------------------------------------------------------

-- Received a version-check broadcast: reply with our own version via whisper.
function PP:HandleVersionRequest(sender)
    self:SendAddonMessage(PP.MSG.VERSION_REPLY, { version = PP.VERSION }, self:GetShortName(sender))
end

-- Received a version reply: update the open version-check window if any.
function PP:HandleVersionReply(data, sender)
    if not data or not data.version then return end
    self:UpdateVersionCheckWindow(sender, tostring(data.version))
end

function PP:BroadcastRaidSettings()
    if not IsInGroup() then return end
    self:SendAddonMessage(PP.MSG.RAID_SETTINGS, {
        autoPassEpicRolls = self.db.global.autoPassEpicRolls,
    })
end

function PP:HandleRaidSettings(data, sender)
    -- Only accept from the current raid leader
    if not data then return end
    local isLeader = false
    for i = 1, GetNumGroupMembers() do
        local name, rank = GetRaidRosterInfo(i)
        if rank == 2 and self:GetFullName(name) == sender then
            isLeader = true
            break
        end
    end
    if not isLeader then return end
    if data.autoPassEpicRolls ~= nil then
        self.db.global.autoPassEpicRolls = data.autoPassEpicRolls
        self:RefreshMainWindow()
    end
end

function PP:BroadcastRoster()
    if not IsInGroup() then return end
    local gk = self:GetActiveGuildKey()
    local gd = self:GetGuildData(gk)
    self:SendAddonMessage(PP.MSG.ROSTER_UPDATE, {
        roster   = gd.roster,
        version  = gd.rosterVersion,
        guildKey = gk,
    })
end

function PP:BroadcastRaidCreate(raidID)
    if not IsInGroup() then return end
    local gk = self:GetActiveGuildKey()
    local gd = self:GetGuildData(gk)
    self:SendAddonMessage(PP.MSG.RAID_CREATE, {
        raidID   = raidID,
        raid     = gd.raids[raidID],
        guildKey = gk,
    })
end

function PP:BroadcastRaidClose(raidID)
    if not IsInGroup() then return end
    self:SendAddonMessage(PP.MSG.RAID_CLOSE, {
        raidID   = raidID,
        guildKey = self:GetActiveGuildKey(),
    })
end

function PP:BroadcastRaidDelete(raidID, guildKey, newVersion)
    if not IsInGroup() then return end
    self:SendAddonMessage(PP.MSG.RAID_DELETE, {
        raidID      = raidID,
        guildKey    = guildKey,
        version     = newVersion,
    })
end

function PP:RequestSync()
    if not IsInGroup() then return end
    local gk = self:GetActiveGuildKey()
    local gd = self:GetGuildData(gk)
    -- Count raid award records we have so peers can detect a gap
    local raidItemCount = 0
    for _, raid in pairs(gd.raids or {}) do
        raidItemCount = raidItemCount + #(raid.items or {})
    end
    self:SendAddonMessage(PP.MSG.SYNC_REQUEST, {
        guildKey      = gk,
        rosterVersion = gd.rosterVersion,
        raidItemCount = raidItemCount,
    })
end

function PP:SendFullSync(target)
    -- Send all known guild data so the recipient can merge everything
    local guilds = {}
    for gk, gd in pairs(self.db.global.guilds) do
        guilds[gk] = gd
    end
    self:SendAddonMessage(PP.MSG.SYNC_FULL, { guilds = guilds }, target)
end

---------------------------------------------------------------------------
-- Handlers
---------------------------------------------------------------------------

-- Someone requests a full sync – only officers respond, and only if they
-- have a higher version than the requester. A small random jitter prevents
-- all online officers from whispering back simultaneously.
function PP:HandleSyncRequest(sender, data)
    if not self:CanModify() then return end
    local gk = (data and data.guildKey) or self:GetActiveGuildKey()
    -- Only respond if the requester's guild matches ours
    local myGuild = self:GetPlayerGuild()
    if not myGuild or gk ~= myGuild then return end
    local gd = self:GetGuildData(gk)
    local requesterVersion   = data and data.rosterVersion   or -1
    local requesterRaidItems = data and data.raidItemCount   or -1
    -- Count our own awarded items across all raids
    local myRaidItems = 0
    for _, raid in pairs(gd.raids or {}) do
        myRaidItems = myRaidItems + #(raid.items or {})
    end
    -- Respond if roster OR raid-award records are behind
    if requesterVersion >= gd.rosterVersion and requesterRaidItems >= myRaidItems then return end
    -- Random jitter 0.3-1.5 s so multiple officers don't reply simultaneously
    local delay = 0.3 + math.random() * 1.2
    self:ScheduleTimer(function()
        self:SendFullSync(sender)
    end, delay)
end

-- Receive full sync data
function PP:HandleSyncFull(data, sender)
    if not data or not data.guilds then return end
    for gk, incoming in pairs(data.guilds) do
        local local_gd = self:GetGuildData(gk)
        -- Roster: take higher version
        if incoming.rosterVersion and incoming.rosterVersion > local_gd.rosterVersion then
            local_gd.roster        = incoming.roster or local_gd.roster
            local_gd.rosterVersion = incoming.rosterVersion
        end
        -- Raids: merge (add unknown, update known if incoming has more data)
        if incoming.raids then
            for id, raid in pairs(incoming.raids) do
                local local_raid = local_gd.raids[id]
                if not local_raid then
                    local_gd.raids[id] = raid
                else
                    if raid.items and #raid.items > #(local_raid.items or {}) then
                        local_raid.items = raid.items
                    end
                    if raid.bosses and #raid.bosses > #(local_raid.bosses or {}) then
                        local_raid.bosses = raid.bosses
                    end
                    if raid.endTime and not local_raid.endTime then
                        local_raid.endTime = raid.endTime
                        local_raid.active  = false
                    end
                end
            end
        end
        if incoming.activeRaidID then
            local_gd.activeRaidID = incoming.activeRaidID
        end
    end
    self:RefreshMainWindow()
end

-- Roster update from an officer
function PP:HandleRosterUpdate(data, sender)
    if not data or not data.guildKey then return end
    local gd = self:GetGuildData(data.guildKey)
    if not gd then return end
    if data.version and data.version > gd.rosterVersion then
        gd.roster        = data.roster or gd.roster
        gd.rosterVersion = data.version
        self:RefreshMainWindow()
    end
end

-- Raid created by an officer
function PP:HandleRaidCreate(data, sender)
    if not data or not data.raidID or not data.raid then return end
    local gk = data.guildKey or self:GetActiveGuildKey()
    local gd = self:GetGuildData(gk)
    gd.raids[data.raidID] = data.raid
    gd.activeRaidID = data.raidID
    -- Adopt this guild key as active if we don't have one set
    if not self._activeGuildKey then
        self._activeGuildKey = gk
    end
    self:Print("Raid started: " .. (data.raid.name or data.raidID))
    self:RefreshMainWindow()
end

-- Raid deleted by an officer
function PP:HandleRaidDelete(data, sender)
    if not data or not data.raidID or not data.guildKey then return end
    local gd = self:GetGuildData(data.guildKey)
    if not gd then return end

    -- Only apply if the incoming version is newer than ours (same guard as roster updates)
    if data.version and data.version <= gd.rosterVersion then return end

    gd.raids[data.raidID] = nil
    gd.rosterVersion = data.version

    if gd.activeRaidID == data.raidID then
        gd.activeRaidID = nil
        wipe(self.pendingLoot)
        self:CloseLootPopups()
        self:RefreshLootMasterWindow()
        self:RefreshLootResponseFrame()
    end

    -- Close the detail window if it was showing the deleted raid
    if self._raidDetailWindow then
        self._raidDetailWindow:Release()
        self._raidDetailWindow = nil
    end

    self:Print("A raid record was deleted by an officer.")
    self:RefreshMainWindow()
end

-- Raid closed
function PP:HandleRaidClose(data, sender)
    if not data or not data.raidID then return end
    local gk = data.guildKey or self:GetActiveGuildKey()
    local gd = self:GetGuildData(gk)
    local raid = gd.raids[data.raidID]
    if raid then
        raid.active  = false
        raid.endTime = time()
    end
    if gd.activeRaidID == data.raidID then
        gd.activeRaidID = nil
    end
    wipe(self.pendingLoot)
    self:CloseLootPopups()
    self:Print("Raid ended.")
    self:RefreshMainWindow()
    self:RefreshLootMasterWindow()
end

-- Score update
function PP:HandleScoreUpdate(data, sender)
    if not data or not data.guildKey then return end
    local gd = self:GetGuildData(data.guildKey)
    if not gd then return end
    if data.version and data.version > gd.rosterVersion then
        gd.roster        = data.roster or gd.roster
        gd.rosterVersion = data.version
        self:RefreshMainWindow()
    end
end

-- Loot posted for distribution
function PP:HandleLootPost(data, sender)
    if not data or not data.key then return end
    -- Store locally so we can respond
    self.pendingLoot[data.key] = {
        itemLink      = data.itemLink,
        itemID        = data.itemID,
        postedBy      = data.postedBy or sender,
        postedAt      = GetTime(),
        responses     = {},
        awarded       = false,
        awardedTo     = nil,
        allowTransmog = data.allowTransmog ~= false,  -- default true
    }
    -- Show popup for non-poster
    if sender ~= self:GetPlayerFullName() then
        self:ShowLootPopup(data.key, data.itemLink)
    end
    self:RefreshLootMasterWindow()
end

-- Loot interest received
function PP:HandleLootInterest(data, sender)
    if not data or not data.key then return end
    local comp = data.equippedLinks and { equippedLinks = data.equippedLinks } or nil
    self:ReceiveLootInterest(data.key, data.player or sender, data.response, data.score, comp)
end

-- Loot awarded
function PP:HandleLootAward(data, sender)
    if not data or not data.key then return end
    -- Record item in raid history for all clients
    if data.itemLink and data.awardedTo then
        self:RecordItemAward(data.itemLink, data.itemID, data.awardedTo, data.pointsSpent, data.response)
    end
    -- Apply score deduction to the winner
    if data.awardedTo then
        local roster = self:GetRoster()
        if roster[data.awardedTo] then
            if data.newScore ~= nil then
                roster[data.awardedTo].score = data.newScore
            elseif data.response == PP.RESPONSE.TRANSMOG then
                roster[data.awardedTo].score = math.max(0, (roster[data.awardedTo].score or 0) - 1)
            elseif data.response == PP.RESPONSE.MINOR then
                -- Recompute minor-upgrade target from local roster view
                roster[data.awardedTo].score = PP:GetMinorUpgradeScore(data.awardedTo)
            else
                roster[data.awardedTo].score = 0
            end
        end
    end
    -- If we were awarded, notify
    local me = self:GetPlayerFullName()
    if data.awardedTo == me then
        self:Print("You have been awarded " .. (data.itemLink or "an item") .. "!")
    end
    -- Close popup for this item
    if self.lootPopups[data.key] then
        self.lootPopups[data.key]:Hide()
        self.lootPopups[data.key] = nil
    end
    self.pendingLoot[data.key] = nil
    self:RefreshLootMasterWindow()
    self:RefreshLootResponseFrame()
    self:RefreshMainWindow()
end

-- Loot item flag updated (e.g. allowTransmog toggled by loot master)
function PP:HandleLootUpdate(data)
    if not data or not data.key then return end
    if self.pendingLoot[data.key] then
        if data.allowTransmog ~= nil then
            self.pendingLoot[data.key].allowTransmog = data.allowTransmog
        end
        self:RefreshLootResponseFrame()
        self:RefreshLootMasterWindow()
    end
end

-- Loot posting cancelled
function PP:HandleLootCancel(data, sender)
    if not data or not data.key then return end
    self.pendingLoot[data.key] = nil
    if self.lootPopups[data.key] then
        self.lootPopups[data.key]:Hide()
        self.lootPopups[data.key] = nil
    end
    self:RefreshLootMasterWindow()
    self:RefreshLootResponseFrame()
end
