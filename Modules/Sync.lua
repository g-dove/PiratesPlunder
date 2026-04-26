---------------------------------------------------------------------------
-- Pirates Plunder – Sync (AceComm messaging)
---------------------------------------------------------------------------
---@type PPAddon
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

---------------------------------------------------------------------------
-- Reliable broadcast state
---------------------------------------------------------------------------
local FULL_SYNC_COOLDOWN = 10 -- seconds before another full sync can broadcast

PP._seenAckIds       = {}
PP._completedLootKeys = {}

local _ackCounter = 0
local function newAckId()
    _ackCounter = _ackCounter + 1
    return string.format("%x-%x-%x", time(), math.floor(GetTime() * 1000) % 0x10000, _ackCounter)
end

local function ComputeRosterHash(roster)
    local keys = {}
    for k in pairs(roster) do keys[#keys + 1] = k end
    table.sort(keys)
    local h = 0
    for _, k in ipairs(keys) do
        local score = roster[k] and roster[k].score or 0
        for i = 1, #k do
            h = (h * 31 + string.byte(k, i)) % 0x7FFFFFFF
        end
        h = (h * 31 + score) % 0x7FFFFFFF
    end
    return h
end

PP.ComputeRosterHash = ComputeRosterHash

local MSG_PRIORITY = {
    -- Loot lifecycle: players respond to posts, awards update scores
    [PP.MSG.LOOT_POST]        = "NORMAL",
    [PP.MSG.LOOT_INTEREST]    = "NORMAL",
    [PP.MSG.LOOT_AWARD]       = "NORMAL",
    [PP.MSG.LOOT_CANCEL]      = "NORMAL",
    [PP.MSG.LOOT_CLEAR]       = "NORMAL",
    -- Session lifecycle
    [PP.MSG.SESSION_CREATE]   = "NORMAL",
    [PP.MSG.SESSION_CLOSE]    = "NORMAL",
    -- Sync / informational
    [PP.MSG.ACK]              = "NORMAL",
    [PP.MSG.ROSTER_DELTA]     = "NORMAL",
    [PP.MSG.GROUP_SCORE]      = "NORMAL",
    [PP.MSG.GROUP_SCORE_ACK]  = "NORMAL",
    [PP.MSG.SYNC_REQUEST]     = "NORMAL",
    [PP.MSG.VERSION_REQUEST]  = "NORMAL",
    [PP.MSG.VERSION_REPLY]    = "NORMAL",
    -- Large payloads / background recovery
    [PP.MSG.LOOT_STATE_QUERY] = "BULK",
    [PP.MSG.RAID_SETTINGS]    = "BULK",
}

---------------------------------------------------------------------------
-- Send a structured message to the raid / party
---------------------------------------------------------------------------
function PP:SendAddonMessage(msgType, data, target)
    if self._sandbox then return end
    if type(data) == "table" and data._ackId then
        if not PP._criticalAckSnapshots then PP._criticalAckSnapshots = {} end
        if not PP._criticalAckSnapshots[data._ackId] then
            local gk = data.guildKey or self:GetActiveGuildKey()
            local gd = PP.Repo.Roster:GetData(gk)
            local h  = gd and ComputeRosterHash(gd.roster) or nil
            local id = data._ackId
            PP._criticalAckSnapshots[id] = { hash = h, guildKey = gk, rosterVersion = gd and gd.rosterVersion or nil, syncTriggered = false }
            PP:ScheduleTimer(function()
                if PP._criticalAckSnapshots then PP._criticalAckSnapshots[id] = nil end
            end, 30)
        end
    end
    local payload = self:Serialize(msgType, data)
    local prio    = MSG_PRIORITY[msgType] or "NORMAL"
    if target then
        self:SendCommMessage(PP.COMM_PREFIX, payload, "WHISPER", target, prio)
    elseif IsInRaid() then
        self:SendCommMessage(PP.COMM_PREFIX, payload, "RAID", nil, prio)
    elseif IsInGroup() then
        self:SendCommMessage(PP.COMM_PREFIX, payload, "PARTY", nil, prio)
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
    PP._ppUsers = PP._ppUsers or {}
    PP._ppUsers[sender] = true

    if type(data) == "table" and data._ackId then
        local gk = (type(data) == "table" and data.guildKey) or self:GetActiveGuildKey()
        local gd = PP.Repo.Roster:GetData(gk)
        self:SendAddonMessage(PP.MSG.ACK, {
            ackId         = data._ackId,
            hash          = gd and ComputeRosterHash(gd.roster) or nil,
            guildKey      = gk,
            rosterVersion = gd and gd.rosterVersion or nil,
        }, sender)
    end

    if msgType == PP.MSG.ACK then
        if data and data.ackId then self:_handleAck(data, sender) end

    elseif msgType == PP.MSG.SYNC_REQUEST then
        self:HandleSyncRequest(sender, data)

    elseif msgType == PP.MSG.SYNC_FULL then
        self:HandleSyncFull(data, sender, distribution)

    elseif msgType == PP.MSG.ROSTER_UPDATE then
        self:HandleRosterUpdate(data, sender)

    elseif msgType == PP.MSG.SESSION_CREATE then
        self:HandleSessionCreate(data, sender)

    elseif msgType == PP.MSG.SESSION_CLOSE then
        self:HandleSessionClose(data, sender)

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

    elseif msgType == PP.MSG.LOOT_VOTE then
        self:HandleLootVote(data, sender)

    elseif msgType == PP.MSG.RAID_SETTINGS then
        self:HandleRaidSettings(data, sender)

    elseif msgType == PP.MSG.SESSION_DELETE then
        self:HandleSessionDelete(data, sender)

    elseif msgType == PP.MSG.LOOT_STATE_QUERY then
        self:HandleLootStateQuery(sender, data)

    elseif msgType == PP.MSG.LOOT_STATE_REPLY then
        self:HandleLootStateReply(data)

    elseif msgType == PP.MSG.VERSION_REQUEST then
        self:HandleVersionRequest(sender)

    elseif msgType == PP.MSG.VERSION_REPLY then
        self:HandleVersionReply(data, sender)

    elseif msgType == PP.MSG.ROSTER_DELTA then
        self:HandleRosterDelta(data, sender)

    elseif msgType == PP.MSG.GROUP_SCORE then
        self:HandleGroupScore(data, sender)

    elseif msgType == PP.MSG.GROUP_SCORE_ACK then
        self:HandleGroupScoreAck(data, sender)

    elseif msgType == PP.MSG.LOOT_CLEAR then
        self:HandleLootClear(sender)
    end
end

---------------------------------------------------------------------------
-- Version check handlers
---------------------------------------------------------------------------

-- Received a version-check broadcast: reply with our own version via whisper.
function PP:HandleVersionRequest(sender)
    self:SendAddonMessage(PP.MSG.VERSION_REPLY, { version = PP.VERSION }, sender)
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

---------------------------------------------------------------------------
-- Reliable broadcast: broadcast to the group and attach an ackId so
-- recipients send back their roster hash. Any hash mismatch triggers a full
-- sync — no per-member whisper retries (WoW's RAID/PARTY channel is
-- reliable for online members; offline/loading clients recover via
-- RequestSync on reconnect).
---------------------------------------------------------------------------
function PP:BroadcastCritical(msgType, data)
    if self._sandbox or not IsInGroup() then return end
    local id = newAckId()
    data._ackId = id
    self:SendAddonMessage(msgType, data)
end

function PP:_handleAck(data, sender)
    if not data.ackId then return end
    local snap = PP._criticalAckSnapshots and PP._criticalAckSnapshots[data.ackId]
    if not snap then return end
    -- Snapshot cleanup is timer-driven (30s); don't nil it here so all members' hashes are checked.
    if snap.syncTriggered then return end
    if not (data.hash and snap.hash and snap.rosterVersion and data.rosterVersion) then return end
    if snap.rosterVersion == data.rosterVersion then
        local match = snap.hash == data.hash
        if PP._debug then
            local label = match and "|cFF00FF00match \226\156\147|r" or "|cFFFF4400MISMATCH \226\156\151|r"
            self:Print("[Sync] ACK hash from " .. self:GetShortName(sender) .. ": " .. label)
        end
        if not match then
            snap.syncTriggered = true
            self:ScheduleTimer(function() self:SendFullSync(snap.guildKey) end, 0.5)
        end
    end
end

function PP:WipeRetryQueue()
    PP._criticalAckSnapshots = {}
    if PP._lootIdleTimer then
        PP:CancelTimer(PP._lootIdleTimer)
        PP._lootIdleTimer = nil
    end
end

-- Received from raid leader after 60s of no pending loot — clears any items
-- stuck on the response frame that were missed during distribution.
function PP:HandleLootClear(sender)
    -- Only accept from the current raid leader
    local isLeader = false
    for i = 1, GetNumGroupMembers() do
        local name, rank = GetRaidRosterInfo(i)
        if rank == 2 and self:GetFullName(name) == sender then
            isLeader = true
            break
        end
    end
    if not isLeader then return end

    local pendingLoot = PP.Repo.Loot:GetAll()
    if next(pendingLoot) == nil then return end
    for lootKey in pairs(pendingLoot) do
        PP._completedLootKeys[lootKey] = true
    end
    PP:LocalClearLoot()
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
    local gd = PP.Repo.Roster:GetData(gk)
    if not gd then return end
    if PP._debug then
        self:Print("[Sync] Full roster broadcast sent (v" .. gd.rosterVersion .. ")")
    end
    self:SendAddonMessage(PP.MSG.ROSTER_UPDATE, {
        roster   = gd.roster,
        version  = gd.rosterVersion,
        guildKey = gk,
        hash     = ComputeRosterHash(gd.roster),
    })
end

function PP:BroadcastRosterDelta(changed, removed)
    if not IsInGroup() then return end
    local gk = self:GetActiveGuildKey()
    local gd = PP.Repo.Roster:GetData(gk)
    if not gd then return end
    if PP._debug then
        local nc = changed and (function() local n=0; for _ in pairs(changed) do n=n+1 end; return n end)() or 0
        local nr = removed and #removed or 0
        self:Print("[Sync] Delta broadcast sent (v" .. gd.rosterVersion .. "): " .. nc .. " changed, " .. nr .. " removed")
    end
    self:SendAddonMessage(PP.MSG.ROSTER_DELTA, {
        changed  = changed,
        removed  = removed,
        version  = gd.rosterVersion,
        hash     = ComputeRosterHash(gd.roster),
        guildKey = gk,
    })
end

function PP:BroadcastGroupScore(amount)
    if not IsInGroup() then return end
    local gk = self:GetActiveGuildKey()
    local gd = PP.Repo.Roster:GetData(gk)
    if not gd then return end
    local ver = gd.rosterVersion
    if not PP._groupScoreHashes then PP._groupScoreHashes = {} end
    PP._groupScoreHashes[ver] = ComputeRosterHash(gd.roster)
    for v in pairs(PP._groupScoreHashes) do
        if v < ver - 10 then PP._groupScoreHashes[v] = nil end
    end
    if PP._debug then
        self:Print("[Sync] Group score +" .. (amount or 1) .. " broadcast (v" .. ver .. ")")
    end
    self:SendAddonMessage(PP.MSG.GROUP_SCORE, {
        amount   = amount or 1,
        version  = ver,
        guildKey = gk,
    })
end

function PP:BroadcastSessionCreate(sessionID)
    if not IsInGroup() then return end
    local gk = self:GetActiveGuildKey()
    local gd = PP.Repo.Roster:GetData(gk)
    if not gd then return end
    local s = gd.sessions[sessionID]
    if not s then return end
    self:BroadcastCritical(PP.MSG.SESSION_CREATE, {
        raidID   = sessionID,
        raid     = {
            name      = s.name,
            startTime = s.startTime,
        },
        guildKey = gk,
    })
end

function PP:BroadcastSessionClose(sessionID)
    if not IsInGroup() then return end
    self:BroadcastCritical(PP.MSG.SESSION_CLOSE, {
        raidID   = sessionID,
        guildKey = self:GetActiveGuildKey(),
    })
end

function PP:BroadcastSessionDelete(sessionID, guildKey, newVersion)
    if not IsInGroup() then return end
    self:BroadcastCritical(PP.MSG.SESSION_DELETE, {
        raidID   = sessionID,
        guildKey = guildKey,
        version  = newVersion,
    })
end

function PP:RequestSync()
    if not IsInGroup() then return end
    local gk = self:GetActiveGuildKey()
    local gd = PP.Repo.Roster:GetData(gk)
    local rosterVersion   = gd and gd.rosterVersion   or -1
    local activeSessionID = gd and gd.activeSessionID or nil
    local raidItemCount   = 0
    if gd then
        for _, session in pairs(gd.sessions or {}) do
            raidItemCount = raidItemCount + #(session.items or {})
        end
    end
    local payload = {
        guildKey        = gk,
        rosterVersion   = rosterVersion,
        raidItemCount   = raidItemCount,
        activeSessionID = activeSessionID,
        hash            = gd and ComputeRosterHash(gd.roster) or nil,
    }
    self:SendAddonMessage(PP.MSG.SYNC_REQUEST, payload)
end

function PP:SendFullSync(guildKey, target)
    -- Cooldown only applies to broadcasts; targeted whispers respond to a
    -- specific request and must not be suppressed by an unrelated broadcast.
    if not target then
        local now = time()
        if PP._lastFullSyncSent and (now - PP._lastFullSyncSent) < FULL_SYNC_COOLDOWN then
            if PP._debug then
                self:Print("[Sync] Full sync suppressed (cooldown)")
            end
            return
        end
        PP._lastFullSyncSent = now
    end
    if PP._debug then
        local label = target and (" -> " .. self:GetShortName(target)) or " (broadcast)"
        self:Print("[Sync] Full sync" .. label .. (guildKey and (" [" .. guildKey .. "]") or " [all guilds]"))
    end
    local guilds = {}
    if guildKey then
        local gd = PP.Repo.Roster:GetData(guildKey)
        if gd then guilds[guildKey] = gd end
    else
        for gk, gd in pairs(self.db.global.guilds) do
            guilds[gk] = gd
        end
    end
    self:SendAddonMessage(PP.MSG.SYNC_FULL, {
        guilds       = guilds,
        raidSettings = {
            autoPassEpicRolls = self.db.global.autoPassEpicRolls,
        },
    }, target)
end

---------------------------------------------------------------------------
-- Handlers
---------------------------------------------------------------------------

-- Someone requests a full sync – only officers respond, and only if they
-- have a higher version than the requester. A small random jitter prevents
-- all online officers from whispering back simultaneously.
function PP:HandleSyncRequest(sender, data)
    if not self:CanModify() then return end
    -- Respond using OUR active guild key, not the requester's.  A joiner whose
    -- _activeGuildKey is still stale (own guild instead of the raid leader's)
    -- would otherwise be ignored by every officer in the raid.
    local gk = self:GetActiveGuildKey()
    local gd = PP.Repo.Roster:GetData(gk)
    if not gd or not gd.activeSessionID then return end
    local requesterVersion   = data and data.rosterVersion   or -1
    local requesterRaidItems = data and data.raidItemCount   or -1
    -- Count our own awarded items across all sessions
    local myRaidItems = 0
    for _, session in pairs(gd.sessions or {}) do
        myRaidItems = myRaidItems + #(session.items or {})
    end
    local myActiveID        = gd.activeSessionID
    local requesterActiveID = data and data.activeSessionID
    local sessionMismatch   = (myActiveID ~= requesterActiveID)
                           and (myActiveID ~= nil or requesterActiveID ~= nil)
                           and myActiveID ~= nil
    -- Roster comparison only meaningful when requester referenced the same
    -- guild key we're about to respond with.  Otherwise treat as not-synced.
    local sameGuild = (data and data.guildKey == gk)
    local rosterSynced
    if sameGuild and data.hash then
        rosterSynced = (ComputeRosterHash(gd.roster) == data.hash)
    elseif sameGuild then
        rosterSynced = (requesterVersion >= gd.rosterVersion)
    else
        rosterSynced = false
    end
    if rosterSynced and requesterRaidItems >= myRaidItems and not sessionMismatch then return end
    -- Random jitter 0.3-1.5 s so multiple officers don't reply simultaneously.
    -- Whisper to the requester so the cooldown on broadcast SendFullSync cannot
    -- swallow the reply.
    local delay = 0.3 + math.random() * 1.2
    self:ScheduleTimer(function()
        self:SendFullSync(gk, sender)
    end, delay)
end

-- Receive full sync data
function PP:HandleSyncFull(data, sender, distribution)
    if not data or not data.guilds then return end
    -- Only accept data for guild keys we already know about or that match our
    -- own guild / active key.  This prevents foreign guild records from being
    -- auto-created in our database just because an officer has stale history.
    -- Whispered SYNC_FULL was sent specifically to us in response to our request,
    -- so trust foreign-guild data (auto-creates the local record).
    local myGuild      = self:GetPlayerGuild()
    local activeKey    = self:GetActiveGuildKey()
    local trustForeign = (distribution == "WHISPER")
    for gk, incoming in pairs(data.guilds) do
        -- Skip keys that are wholly foreign to this client (broadcast only)
        if gk ~= myGuild and gk ~= activeKey and not self.db.global.guilds[gk] and not trustForeign then
            -- (do nothing – ignore this guild's data entirely)
        else
            local local_gd = PP.Repo.Roster:EnsureData(gk)
            -- Roster: take higher version
            if incoming.rosterVersion and incoming.rosterVersion > local_gd.rosterVersion then
                local_gd.roster        = incoming.roster or local_gd.roster
                local_gd.rosterVersion = incoming.rosterVersion
            end
            -- Sessions: merge (add unknown, update known if incoming has more data)
            if incoming.sessions then
                for id, session in pairs(incoming.sessions) do
                    local local_session = local_gd.sessions[id]
                    if not local_session then
                        -- Only add if we have no tombstone for this session
                        if not (local_gd.deletedSessions and local_gd.deletedSessions[id]) then
                            local_gd.sessions[id] = session
                        end
                    else
                        if session.items and #session.items > #(local_session.items or {}) then
                            local_session.items = session.items
                        end
                        if session.bosses and #session.bosses > #(local_session.bosses or {}) then
                            local_session.bosses = session.bosses
                        end
                        if session.endTime and not local_session.endTime then
                            local_session.endTime = session.endTime
                            local_session.active  = false
                        end
                    end
                end
            end

            -- Tombstones: apply deletions from the sender that we haven't seen yet
            if incoming.deletedSessions then
                if not local_gd.deletedSessions then local_gd.deletedSessions = {} end
                for sessionID, tombVer in pairs(incoming.deletedSessions) do
                    if not local_gd.deletedSessions[sessionID] then
                        -- We haven't recorded this deletion yet – apply it
                        local_gd.sessions[sessionID] = nil
                        local_gd.deletedSessions[sessionID] = tombVer
                        -- Advance our version so future syncs from us carry the tombstone
                        if tombVer > local_gd.rosterVersion then
                            local_gd.rosterVersion = tombVer
                        end
                        if local_gd.activeSessionID == sessionID then
                            PP.Session:End(PP.SESSION_END.SYNC_FULL, sessionID, gk)
                        end
                    end
                end
            end
            local incomingSessionVer = incoming.activeSessionVersion or 0
            local localSessionVer    = local_gd.activeSessionVersion or 0
            if incoming.activeSessionID and incomingSessionVer >= localSessionVer then
                local incomingID = incoming.activeSessionID
                local existingID = local_gd.activeSessionID
                if existingID and existingID ~= incomingID
                   and local_gd.sessions[existingID]
                   and local_gd.sessions[existingID].active then
                    PP.Session:End(PP.SESSION_END.SYNC_FULL, existingID, gk)
                end
                local_gd.activeSessionID      = incomingID
                local_gd.activeSessionVersion = incomingSessionVer
                if local_gd.sessions[incomingID] and not local_gd.sessions[incomingID].active then
                    local_gd.sessions[incomingID].active  = true
                    local_gd.sessions[incomingID].endTime = nil
                end
                if self.db.global.pendingSessionEnd
                    and self.db.global.pendingSessionEnd.sessionID == incomingID then
                    self.db.global.pendingSessionEnd = nil
                    if self._pendingSessionEndTimer then
                        self:CancelTimer(self._pendingSessionEndTimer)
                        self._pendingSessionEndTimer = nil
                    end
                end
                if IsInRaid() and gk == activeKey then
                    PP.Session:CheckLeaderPresent()
                end
            elseif incoming.activeSessionID == nil
                   and incomingSessionVer > localSessionVer
                   and local_gd.activeSessionID then
                -- Sender authoritatively cleared their active session at a
                -- newer version than ours; end our stale local session too.
                PP.Session:End(PP.SESSION_END.SYNC_FULL, local_gd.activeSessionID, gk)
                local_gd.activeSessionVersion = incomingSessionVer
            end
        end
    end
    -- Apply raid settings carried in the sync payload.  RAID_SETTINGS broadcast
    -- is the primary path but can lose the race with loot rolls on reconnect;
    -- this acts as a reliable fallback since only officers respond to SYNC_REQUEST.
    if data.raidSettings then
        if data.raidSettings.autoPassEpicRolls ~= nil then
            self.db.global.autoPassEpicRolls = data.raidSettings.autoPassEpicRolls
        end
    end
    self:RefreshMainWindow()
end

function PP:HandleRosterUpdate(data, sender)
    if not data or not data.guildKey then return end
    local gd = PP.Repo.Roster:GetData(data.guildKey)
    if not gd then return end
    if data.version and data.version > gd.rosterVersion then
        gd.roster        = data.roster or gd.roster
        gd.rosterVersion = data.version
        if PP._debug then
            local match = not data.hash or ComputeRosterHash(gd.roster) == data.hash
            local label = match and "|cFF00FF00match \226\156\147|r" or "|cFFFF4400MISMATCH \226\156\151|r"
            self:Print("[Sync] Full roster from " .. self:GetShortName(sender) .. " (v" .. data.version .. "): hash " .. label)
        end
        if data.hash and ComputeRosterHash(gd.roster) ~= data.hash then
            self:ScheduleTimer(function() self:RequestSync() end, math.random())
        end
        self:RefreshMainWindow()
    end
end

function PP:HandleRosterDelta(data, sender)
    if not data or not data.guildKey then return end
    local gd = PP.Repo.Roster:GetData(data.guildKey)
    if not gd then return end
    if not data.version then return end
    if data.version <= gd.rosterVersion then return end
    -- Require sequential application; a gap means we missed a delta — fall back to full sync
    if data.version ~= gd.rosterVersion + 1 then
        self:ScheduleTimer(function() self:RequestSync() end, math.random())
        return
    end
    if data.changed then
        for fullName, entry in pairs(data.changed) do
            gd.roster[fullName] = entry
        end
    end
    if data.removed then
        for _, fullName in ipairs(data.removed) do
            gd.roster[fullName] = nil
        end
    end
    gd.rosterVersion = data.version
    local match = not data.hash or ComputeRosterHash(gd.roster) == data.hash
    if PP._debug then
        local label = match and "|cFF00FF00match \226\156\147|r" or "|cFFFF4400MISMATCH \226\156\151|r"
        self:Print("[Sync] Delta from " .. self:GetShortName(sender) .. " (v" .. data.version .. "): hash " .. label)
    end
    if not match then
        self:ScheduleTimer(function() self:RequestSync() end, math.random())
    end
    self:RefreshMainWindow()
end

function PP:HandleGroupScore(data, sender)
    if not data or not data.guildKey then return end
    local gd = PP.Repo.Roster:GetData(data.guildKey)
    if not gd then return end
    if not (data.version and data.version > gd.rosterVersion) then return end
    local amount = data.amount or 1
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name = GetRaidRosterInfo(i)
            if name then
                local fullName = self:GetFullName(name)
                if gd.roster[fullName] then
                    gd.roster[fullName].score = gd.roster[fullName].score + amount
                end
            end
        end
    end
    gd.rosterVersion = data.version
    local hash = ComputeRosterHash(gd.roster)
    if PP._debug then
        local label = "|cFFFFD100pending ACK|r"
        self:Print("[Sync] Group score from " .. self:GetShortName(sender) .. " (v" .. data.version .. "): " .. label)
    end
    self:SendAddonMessage(PP.MSG.GROUP_SCORE_ACK, {
        version  = data.version,
        hash     = hash,
        guildKey = data.guildKey,
    }, sender)
    self:RefreshMainWindow()
end

function PP:HandleGroupScoreAck(data, sender)
    if not data or not data.version or not data.hash then return end
    if not PP._groupScoreHashes then return end
    local expected = PP._groupScoreHashes[data.version]
    if not expected then return end
    local match = expected == data.hash
    if PP._debug then
        local label = match and "|cFF00FF00match \226\156\147|r" or "|cFFFF4400MISMATCH \226\156\151 \226\134\146 sending full sync|r"
        self:Print("[Sync] Hash ACK from " .. self:GetShortName(sender) .. ": " .. label)
    end
    if not match and data.guildKey then
        self:SendFullSync(data.guildKey)
    end
end

-- Session created by an officer
function PP:HandleSessionCreate(data, sender)
    if not data or not data.raidID or not data.raid then return end
    local gk = data.guildKey or self:GetActiveGuildKey()
    local gd = PP.Repo.Roster:EnsureData(gk)
    -- End any conflicting locally-active session before adopting the incoming one.
    -- Guards against the race where two officers create sessions before either
    -- receives the other's broadcast.
    local existingID = gd.activeSessionID
    if existingID and existingID ~= data.raidID
       and gd.sessions[existingID]
       and gd.sessions[existingID].active then
        PP.Session:End(PP.SESSION_END.SYNC_RECEIVED, existingID, gk)
    end
    gd.sessions[data.raidID] = {
        name      = data.raid.name,
        startTime = data.raid.startTime,
        guildKey  = data.guildKey,
        leader    = sender,
        items     = {},
        bosses    = {},
        members   = {},
        active    = true,
        endTime   = nil,
    }
    PP.Repo.Roster:SetActiveSessionID(gk, data.raidID)
    -- When in a raid, always adopt the session's guild key — guards against the
    -- timing race where GetRaidLeaderGuild() returned nil in OnGroupRosterUpdate
    -- before unit data had populated.  Outside a raid, only set if unset.
    if IsInRaid() or not self._activeGuildKey then
        self._activeGuildKey = gk
    end
    -- If we have no roster data yet (fresh install / cleared vars), request a
    -- sync so the officer sends us the full roster now that a session is active.
    if gd.rosterVersion == 0 then
        self:ScheduleTimer(function() self:RequestSync() end, 1)
    end
    self:Print("Session started: " .. (data.raid.name or data.raidID))
    PP._seenAckIds        = {}
    PP._completedLootKeys = {}
    self:RefreshMainWindow()
end

-- Session deleted by an officer
function PP:HandleSessionDelete(data, sender)
    if not data or not data.raidID or not data.guildKey then return end
    local gd = PP.Repo.Roster:GetData(data.guildKey)
    if not gd then return end

    -- Only apply if the incoming version is newer than ours (same guard as roster updates)
    if data.version and data.version <= gd.rosterVersion then return end

    gd.sessions[data.raidID] = nil
    gd.rosterVersion = data.version

    -- Record tombstone so this deletion propagates to offline peers via future syncs
    if not gd.deletedSessions then gd.deletedSessions = {} end
    gd.deletedSessions[data.raidID] = data.version

    if gd.activeSessionID == data.raidID then
        PP.Session:End(PP.SESSION_END.SYNC_DELETE, data.raidID, data.guildKey)
    end

    -- Close the detail window if it was showing the deleted session
    if self._raidDetailWindow then
        self._raidDetailWindow:Release()
        self._raidDetailWindow = nil
    end

    self:Print("A session record was deleted by an officer.")
    self:RefreshMainWindow()
end

-- Session closed
function PP:HandleSessionClose(data, sender)
    if not data or not data.raidID then return end
    local gk = data.guildKey or self:GetActiveGuildKey()
    local gd = PP.Repo.Roster:GetData(gk)
    if not gd then return end
    local session = gd.sessions[data.raidID]
    if session then
        session.active  = false
        session.endTime = time()
    end
    if gd.activeSessionID == data.raidID then
        PP.Session:End(PP.SESSION_END.SYNC_RECEIVED, data.raidID, gk)
    end
    self:RefreshMainWindow()
end

-- Score update
function PP:HandleScoreUpdate(data, sender)
    if not data or not data.guildKey then return end
    local gd = PP.Repo.Roster:GetData(data.guildKey)
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
    if PP._completedLootKeys[data.key] then return end
    if data._ackId then
        local key = sender .. ":" .. tostring(data._ackId)
        if PP._seenAckIds[key] then return end
        PP._seenAckIds[key] = true
    end
    -- Store locally so we can respond
    PP.Repo.Loot:SetEntry(data.key, {
        itemLink      = data.itemLink,
        itemID        = data.itemID,
        postedBy      = data.postedBy or sender,
        postedAt      = GetTime(),
        responses     = {},
        votes         = {},
        awarded       = false,
        awardedTo     = nil,
        allowTransmog = data.allowTransmog ~= false,  -- default true
    })
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
    if data._ackId then
        local key = sender .. ":" .. tostring(data._ackId)
        if PP._seenAckIds[key] then return end
        PP._seenAckIds[key] = true
    end
    -- Record item in raid history for all clients.  Use the guildKey from the
    -- award payload so receivers with a stale _activeGuildKey still write the
    -- item into the correct session.
    if data.itemLink and data.awardedTo then
        PP.Session:RecordItemAward(data.itemLink, data.itemID, data.awardedTo, data.pointsSpent, data.response, data.key, data.guildKey)
    end
    -- Apply score deduction to the winner
    if data.awardedTo and data.newScore ~= nil then
        local roster = PP.Repo.Roster:GetRoster(data.guildKey)
        if roster[data.awardedTo] then
            roster[data.awardedTo].score = data.newScore
        end
    end
    -- Advance local rosterVersion to match the loot master and verify hash.
    -- No separate ROSTER_DELTA is sent for awards — the version and hash travel
    -- in the LOOT_AWARD payload so receivers stay in sync with one message.
    if data.rosterVersion and data.guildKey then
        local gd = PP.Repo.Roster:GetData(data.guildKey)
        if gd then
            if data.rosterVersion > gd.rosterVersion + 1 then
                -- Gap: missed prior delta(s). Don't bump version; full sync will fix it.
                self:ScheduleTimer(function() self:RequestSync() end, math.random())
            elseif data.rosterVersion == gd.rosterVersion + 1 then
                gd.rosterVersion = data.rosterVersion
                if data.rosterHash and ComputeRosterHash(gd.roster) ~= data.rosterHash then
                    self:ScheduleTimer(function() self:RequestSync() end, math.random())
                end
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
    PP._completedLootKeys[data.key] = true
    PP.Repo.Loot:ClearEntry(data.key)
    self:RefreshLootMasterWindow()
    self:RefreshLootResponseFrame()
    self:RefreshMainWindow()
end

-- Vote cast by an officer or the raid leader suggesting a recipient
function PP:HandleLootVote(data, sender)
    if not data or not data.key or not data.target then return end
    local voter = data.voter or sender
    self:ReceiveVote(data.key, voter, data.target)
end

-- Loot item flag updated (e.g. allowTransmog toggled by loot master)
function PP:HandleLootUpdate(data)
    if not data or not data.key then return end
    local entry = PP.Repo.Loot:GetEntry(data.key)
    if entry then
        if data.allowTransmog ~= nil then
            entry.allowTransmog = data.allowTransmog
            PP.Repo.Loot:Save()
        end
        self:RefreshLootResponseFrame()
        self:RefreshLootMasterWindow()
    end
end

-- Loot state query: sent by a client re-entering world to resolve stale pending items.
-- Any player who can post loot (officer, raid leader/assist) may reply.
function PP:HandleLootStateQuery(sender, data)
    if not self:CanPostLoot() then return end
    if not data or not data.keys then return end

    local results = {}
    for _, key in ipairs(data.keys) do
        if PP.Repo.Loot:GetEntry(key) then
            results[key] = { status = "pending" }
        else
            -- Check session items for an awarded record matching this key
            local session = PP.Repo.Roster:GetActiveSession()
            local found = false
            if session and session.items then
                for _, item in ipairs(session.items) do
                    if item.key == key then
                        results[key] = {
                            status      = "awarded",
                            awardedTo   = item.awardedTo,
                            pointsSpent = item.pointsSpent,
                        }
                        found = true
                        break
                    end
                end
            end
            if not found then
                results[key] = { status = "unknown" }
            end
        end
    end

    self:SendAddonMessage(PP.MSG.LOOT_STATE_REPLY, { results = results }, sender)
end

-- Loot state reply: resolve stale pending loot entries on the querying client.
function PP:HandleLootStateReply(data)
    if not data or not data.results then return end
    -- Cancel the fallback timer set by _requestStateSync()
    PP._lootStateVerifyPending = false

    local changed = false
    for key, result in pairs(data.results) do
        if result.status == "awarded" or result.status == "unknown" then
            if PP.Repo.Loot:GetEntry(key) then
                if self.lootPopups[key] then
                    self.lootPopups[key]:Hide()
                    self.lootPopups[key] = nil
                end
                PP.Repo.Loot:ClearEntry(key)
                changed = true
            end
        end
        -- "pending": leave local entry as-is
    end
    if changed then
        self:RefreshLootResponseFrame()
        self:RefreshLootMasterWindow()
    end
    -- Show popup for any items still pending that we haven't responded to
    self:ShowLootResponseFrameIfNeeded()
end

-- Loot posting cancelled
function PP:HandleLootCancel(data, sender)
    if not data or not data.key then return end
    if data._ackId then
        local key = sender .. ":" .. tostring(data._ackId)
        if PP._seenAckIds[key] then return end
        PP._seenAckIds[key] = true
    end
    PP._completedLootKeys[data.key] = true
    PP.Repo.Loot:ClearEntry(data.key)
    if self.lootPopups[data.key] then
        self.lootPopups[data.key]:Hide()
        self.lootPopups[data.key] = nil
    end
    self:RefreshLootMasterWindow()
    self:RefreshLootResponseFrame()
end

