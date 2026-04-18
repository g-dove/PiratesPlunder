---------------------------------------------------------------------------
-- Pirates Plunder – Sync (AceComm messaging)
---------------------------------------------------------------------------
---@type PPAddon
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

---------------------------------------------------------------------------
-- Reliable broadcast state
---------------------------------------------------------------------------
local RETRY_DELAY            = 4    -- seconds between whisper retry attempts
local MAX_RETRIES            = 3    -- max whisper retries before giving up
local PERIODIC_SYNC_INTERVAL = 90   -- seconds between version-check broadcasts
local SYNC_INHIBIT_WINDOW    = 60   -- skip check if SYNC_FULL received within N seconds

PP._retryQueue           = {}
PP._seenAckIds           = {}
PP._ackCounter           = 0
PP._lastSyncFullReceived = 0
PP._periodicSyncTicker   = nil

-- ChatThrottleLib priority per message type. Omitted = "NORMAL".
local MSG_PRIORITY = {
    LOT_PST  = "ALERT",  -- LOOT_POST
    LOT_AWD  = "ALERT",  -- LOOT_AWARD
    LOT_CAN  = "ALERT",  -- LOOT_CANCEL
    LOT_INT  = "ALERT",  -- LOOT_INTEREST
    SES_CRE  = "ALERT",  -- SESSION_CREATE
    SES_CLS  = "ALERT",  -- SESSION_CLOSE
    ACK      = "ALERT",
    SYN_REQ  = "BULK",   -- SYNC_REQUEST
    LOT_SQR  = "BULK",   -- LOOT_STATE_QUERY
    RAD_SET  = "BULK",   -- RAID_SETTINGS
    VER_REQ  = "BULK",   -- VERSION_REQUEST
    VER_REP  = "BULK",   -- VERSION_REPLY
}

local function snapshotGroup(self)
    local members, me = {}, self:GetPlayerFullName()
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
            if name and online then
                local full = self:GetFullName(name)
                if full ~= me then members[full] = false end
            end
        end
    else
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local name, realm = UnitName(unit)
                if name then
                    local full = self:GetFullName(name .. (realm and realm ~= "" and ("-" .. realm) or ""))
                    if full ~= me then members[full] = false end
                end
            end
        end
    end
    return members
end

---------------------------------------------------------------------------
-- Send a structured message to the raid / party
---------------------------------------------------------------------------
function PP:SendAddonMessage(msgType, data, target)
    -- Never broadcast real messages while in sandbox mode
    if self._sandbox then return end
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

    -- ACK any critical broadcast so the sender can cancel whisper retries
    if data and data._ackId then
        self:SendAddonMessage(PP.MSG.ACK, { ackId = data._ackId }, sender)
    end

    -- Dispatch
    if msgType == PP.MSG.ACK then
        if data and data.ackId then self:_handleAck(data.ackId, sender) end

    elseif msgType == PP.MSG.SYNC_REQUEST then
        self:HandleSyncRequest(sender, data)

    elseif msgType == PP.MSG.SYNC_FULL then
        self:HandleSyncFull(data, sender)

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
-- Reliable broadcast: initial RAID/PARTY broadcast + whisper retry for
-- members who don't ACK. Used for ephemeral loot events that have no
-- recovery path if dropped (LOOT_POST, LOOT_AWARD, LOOT_CANCEL).
---------------------------------------------------------------------------
function PP:BroadcastCritical(msgType, data, maxRetries)
    PP._ackCounter = PP._ackCounter + 1
    local id = PP._ackCounter
    data._ackId = id
    local entry = {
        msgType    = msgType,
        data       = data,
        expected   = snapshotGroup(self),
        retries    = 0,
        maxRetries = maxRetries or MAX_RETRIES,
    }
    PP._retryQueue[id] = entry
    self:SendAddonMessage(msgType, data)
    entry.timerId = self:ScheduleTimer(function() self:_retryBroadcast(id) end, RETRY_DELAY)
end

function PP:_retryBroadcast(id)
    local e = PP._retryQueue[id]
    if not e then return end

    local current = snapshotGroup(self)
    for name in pairs(e.expected) do
        if current[name] == nil then e.expected[name] = nil end
    end

    local anyPending = false
    for _, acked in pairs(e.expected) do
        if not acked then anyPending = true; break end
    end

    if not anyPending or e.retries >= e.maxRetries then
        PP._retryQueue[id] = nil
        return
    end

    e.retries = e.retries + 1
    for name, acked in pairs(e.expected) do
        if not acked then
            self:SendAddonMessage(e.msgType, e.data, name)
        end
    end
    e.timerId = self:ScheduleTimer(function() self:_retryBroadcast(id) end, RETRY_DELAY)
end

function PP:_handleAck(ackId, sender)
    local e = PP._retryQueue[ackId]
    if not e then return end
    local full = self:GetFullName(sender)
    if e.expected[full] == false then
        e.expected[full] = true
    end
end

---------------------------------------------------------------------------
-- Periodic version check: reuses RequestSync() every 90s (out of combat)
-- so mid-raid score/state drift is caught without spamming full syncs.
-- Officers only respond if requester is verifiably behind (existing gate).
---------------------------------------------------------------------------
function PP:StartPeriodicSync()
    if PP._periodicSyncTicker then return end
    PP._periodicSyncTicker = C_Timer.NewTicker(PERIODIC_SYNC_INTERVAL, function()
        if UnitAffectingCombat("player") then return end
        if not PP.Repo.Roster:HasActiveSession() then return end
        if (GetTime() - PP._lastSyncFullReceived) < SYNC_INHIBIT_WINDOW then return end
        PP:RequestSync()
    end)
end

function PP:StopPeriodicSync()
    if PP._periodicSyncTicker then
        PP._periodicSyncTicker:Cancel()
        PP._periodicSyncTicker = nil
    end
end

function PP:WipeRetryQueue()
    for _, e in pairs(PP._retryQueue) do
        if e.timerId then PP:CancelTimer(e.timerId) end
    end
    PP._retryQueue = {}
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
    self:SendAddonMessage(PP.MSG.ROSTER_UPDATE, {
        roster   = gd.roster,
        version  = gd.rosterVersion,
        guildKey = gk,
    })
end

function PP:BroadcastSessionCreate(sessionID)
    if not IsInGroup() then return end
    local gk = self:GetActiveGuildKey()
    local gd = PP.Repo.Roster:GetData(gk)
    if not gd then return end
    self:SendAddonMessage(PP.MSG.SESSION_CREATE, {
        raidID   = sessionID,
        raid     = gd.sessions[sessionID],
        guildKey = gk,
    })
end

function PP:BroadcastSessionClose(sessionID)
    if not IsInGroup() then return end
    self:SendAddonMessage(PP.MSG.SESSION_CLOSE, {
        raidID   = sessionID,
        guildKey = self:GetActiveGuildKey(),
    })
end

function PP:BroadcastSessionDelete(sessionID, guildKey, newVersion)
    if not IsInGroup() then return end
    self:SendAddonMessage(PP.MSG.SESSION_DELETE, {
        raidID      = sessionID,
        guildKey    = guildKey,
        version     = newVersion,
    })
end

function PP:RequestSync()
    if not IsInGroup() then return end
    local gk = self:GetActiveGuildKey()
    local gd = PP.Repo.Roster:GetData(gk)
    -- If we have no local record at all, send floor values so any officer with
    -- data for this guild key will see us as behind and respond with SYNC_FULL.
    local rosterVersion   = gd and gd.rosterVersion   or -1
    local activeSessionID = gd and gd.activeSessionID or nil
    local raidItemCount   = 0
    if gd then
        for _, session in pairs(gd.sessions or {}) do
            raidItemCount = raidItemCount + #(session.items or {})
        end
    end
    self:SendAddonMessage(PP.MSG.SYNC_REQUEST, {
        guildKey        = gk,
        rosterVersion   = rosterVersion,
        raidItemCount   = raidItemCount,
        activeSessionID = activeSessionID,
    })
end

function PP:SendFullSync(target, guildKey)
    -- Send only the requested guild's data; sending all keys is wasteful and
    -- risks the receiver merging data for guilds it has no context for.
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
    local gk = (data and data.guildKey) or self:GetActiveGuildKey()
    -- Only respond if the requester's guild matches ours
    local myGuild = self:GetPlayerGuild()
    if not myGuild or gk ~= myGuild then return end
    local gd = PP.Repo.Roster:GetData(gk)
    if not gd then return end
    -- Only respond when we have an active session — without one there is nothing
    -- meaningful to restore and we avoid syncing roster data to non-members.
    if not gd.activeSessionID then return end
    local requesterVersion   = data and data.rosterVersion   or -1
    local requesterRaidItems = data and data.raidItemCount   or -1
    -- Count our own awarded items across all sessions
    local myRaidItems = 0
    for _, session in pairs(gd.sessions or {}) do
        myRaidItems = myRaidItems + #(session.items or {})
    end
    -- Respond if roster OR raid-award records are behind.
    -- Also respond if active session IDs differ — LEADER_LEFT ends sessions
    -- without changing versions, so version parity alone is not enough to
    -- detect that the requester needs a restore.
    local myActiveID        = gd.activeSessionID
    local requesterActiveID = data and data.activeSessionID
    -- Only treat a session-ID mismatch as a sync trigger when we actually have
    -- an active session to offer.  If we have no session, responding would just
    -- send a large payload that can't help the requester restore anything.
    local sessionMismatch   = (myActiveID ~= requesterActiveID)
                           and (myActiveID ~= nil or requesterActiveID ~= nil)
                           and myActiveID ~= nil
    if requesterVersion >= gd.rosterVersion and requesterRaidItems >= myRaidItems
       and not sessionMismatch then return end
    -- Random jitter 0.3-1.5 s so multiple officers don't reply simultaneously
    local delay = 0.3 + math.random() * 1.2
    self:ScheduleTimer(function()
        self:SendFullSync(sender, gk)
    end, delay)
end

-- Receive full sync data
function PP:HandleSyncFull(data, sender)
    if not data or not data.guilds then return end
    PP._lastSyncFullReceived = GetTime()
    -- Only accept data for guild keys we already know about or that match our
    -- own guild / active key.  This prevents foreign guild records from being
    -- auto-created in our database just because an officer has stale history.
    local myGuild   = self:GetPlayerGuild()
    local activeKey = self:GetActiveGuildKey()
    for gk, incoming in pairs(data.guilds) do
        -- Skip keys that are wholly foreign to this client
        if gk ~= myGuild and gk ~= activeKey and not self.db.global.guilds[gk] then
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
            if incoming.activeSessionID then
                local incomingID = incoming.activeSessionID
                -- End any conflicting locally-active session before adopting the synced one.
                local existingID = local_gd.activeSessionID
                if existingID and existingID ~= incomingID
                   and local_gd.sessions[existingID]
                   and local_gd.sessions[existingID].active then
                    PP.Session:End(PP.SESSION_END.SYNC_FULL, existingID, gk)
                end
                local_gd.activeSessionID = incomingID
                -- Part 3: if we previously ended this session prematurely, restore it
                if local_gd.sessions[incomingID] and not local_gd.sessions[incomingID].active then
                    local_gd.sessions[incomingID].active  = true
                    local_gd.sessions[incomingID].endTime = nil
                end
                -- Cancel any deferred session end that referenced this session
                if self.db.global.pendingSessionEnd
                    and self.db.global.pendingSessionEnd.sessionID == incomingID then
                    self.db.global.pendingSessionEnd = nil
                    if self._pendingSessionEndTimer then
                        self:CancelTimer(self._pendingSessionEndTimer)
                        self._pendingSessionEndTimer = nil
                    end
                end
                -- A restored session may make us the active leader; re-run the
                -- leader check so the "Continue?" prompt fires if we hold rank 2.
                -- Gate on active guild key to avoid redundant calls if the sync
                -- payload happens to contain multiple guild keys.
                if IsInRaid() and gk == activeKey then
                    PP.Session:CheckLeaderPresent()
                end
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

-- Roster update from an officer
function PP:HandleRosterUpdate(data, sender)
    if not data or not data.guildKey then return end
    local gd = PP.Repo.Roster:GetData(data.guildKey)
    if not gd then return end
    if data.version and data.version > gd.rosterVersion then
        gd.roster        = data.roster or gd.roster
        gd.rosterVersion = data.version
        self:RefreshMainWindow()
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
    gd.sessions[data.raidID] = data.raid
    gd.activeSessionID = data.raidID
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
    PP._seenAckIds = {}
    self:StartPeriodicSync()
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
    -- Record item in raid history for all clients
    if data.itemLink and data.awardedTo then
        PP.Session:RecordItemAward(data.itemLink, data.itemID, data.awardedTo, data.pointsSpent, data.response, data.key)
    end
    -- Apply score deduction to the winner
    if data.awardedTo then
        local roster = PP.Repo.Roster:GetRoster()
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
    PP.Repo.Loot:ClearEntry(data.key)
    if self.lootPopups[data.key] then
        self.lootPopups[data.key]:Hide()
        self.lootPopups[data.key] = nil
    end
    self:RefreshLootMasterWindow()
    self:RefreshLootResponseFrame()
end
