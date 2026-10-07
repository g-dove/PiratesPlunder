---------------------------------------------------------------------------
-- Pirates Plunder – Session Service
-- Canonical session lifecycle management.
---------------------------------------------------------------------------
---@type PPAddon
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

PP.Session = PP.Session or {}

---------------------------------------------------------------------------
-- Session-end reason constants
---------------------------------------------------------------------------
PP.SESSION_END = {
    OFFICER_ACTION = "officer_action",
    LEFT_GROUP     = "left_group",
    LEADER_LEFT    = "leader_left",
    SYNC_RECEIVED  = "sync_received",
    SYNC_DELETE    = "sync_delete",
    SYNC_FULL      = "sync_full",
    STARTUP_CHECK  = "startup_check",
    RESET          = "reset",
    ORPHAN_CLEANUP = "orphan_cleanup",
}

-- Ends this client inferred on its own, without word from the leader. A
-- record ended this way may be re-adopted at an equal activeSessionVersion
-- (see _isLocallyDropped in Sync.lua); every other reason is authoritative.
PP.SESSION_END_SOFT = {
    [PP.SESSION_END.LEFT_GROUP]     = true,
    [PP.SESSION_END.LEADER_LEFT]    = true,
    [PP.SESSION_END.STARTUP_CHECK]  = true,
    [PP.SESSION_END.ORPHAN_CLEANUP] = true,
}

-- No raid night runs this long; an older active session found at login is
-- leftover state, not a live raid.
PP.SESSION_MAX_AGE = 16 * 60 * 60

---------------------------------------------------------------------------
-- End(reason, sessionID, guildKey)
-- THE canonical session teardown.
---------------------------------------------------------------------------
function PP.Session:End(reason, sessionID, guildKey)
    guildKey  = guildKey  or PP:GetActiveGuildKey()
    local gd  = PP.Repo.Roster:GetData(guildKey)
    sessionID = sessionID or (gd and gd.activeSessionID)
    if not sessionID then return end

    -- Only an end the raid will hear about advances activeSessionVersion.
    -- Local-only ends (left group, sync teardown, non-leader close) used to
    -- bump it too, so receivers' counters drifted ahead of the leader's and
    -- the leader's later broadcasts were rejected as stale.
    local announce = (reason == PP.SESSION_END.OFFICER_ACTION)
                     and IsInGroup() and PP:IsRaidLeader()

    PP:WipeRetryQueue()
    PP.Repo.Roster:MarkSessionEnded(guildKey, sessionID, time(), reason)
    PP.Repo.Roster:ClearActiveSessionID(guildKey, not announce)
    PP.Repo.Loot:WipeAll()
    PP:CloseLootPopups()

    -- Capture a roster snapshot tagged with the current rosterVersion. Every
    -- client that runs End() locally writes its own snapshot; rosterVersion
    -- arbitration in SetSessionSnapshot keeps the highest-version copy.
    -- RESET wipes data deliberately; SYNC_DELETE arrives after the session
    -- and its snapshot have already been removed, so capturing here would
    -- resurrect a snapshot for a deleted session.
    local capturedSnapshot
    local skipSnapshot = (reason == PP.SESSION_END.RESET)
                          or (reason == PP.SESSION_END.SYNC_DELETE)
    if not skipSnapshot then
        capturedSnapshot = PP.Repo.Roster:BuildRosterSnapshot(guildKey)
        if capturedSnapshot then
            PP.Repo.Roster:SetSessionSnapshot(guildKey, sessionID, capturedSnapshot)
        end
    end

    -- Reason-specific messaging
    if reason == PP.SESSION_END.OFFICER_ACTION then
        local gd2 = PP.Repo.Roster:GetData(guildKey)
        local session = gd2 and gd2.sessions and gd2.sessions[sessionID]
        PP:Print("Session ended: " .. (session and session.name or sessionID))
        PP:BroadcastSessionClose(sessionID, capturedSnapshot)
    elseif reason == PP.SESSION_END.LEFT_GROUP then
        local me = PP:GetPlayerFullName()
        local gd2 = PP.Repo.Roster:GetData(guildKey)
        local session = gd2 and gd2.sessions and gd2.sessions[sessionID]
        if session and session.leader == me then
            PP:Print("You left the group. The active session has been closed on your end.")
        end
    elseif reason == PP.SESSION_END.LEADER_LEFT then
        PP:Print("Session ended – the session leader left the group.")
    elseif reason == PP.SESSION_END.STARTUP_CHECK then
        -- silent; no message needed
    elseif reason == PP.SESSION_END.SYNC_RECEIVED then
        PP:Print("Session ended.")
    elseif reason == PP.SESSION_END.SYNC_DELETE then
        -- handled by caller printing "A session record was deleted by an officer."
    elseif reason == PP.SESSION_END.SYNC_FULL then
        -- silent merge teardown
    elseif reason == PP.SESSION_END.RESET then
        -- silent; reset addon handles its own messaging
    end

    PP:RefreshMainWindow()
    PP:RefreshLootMasterWindow()
    PP:RefreshLootResponseFrame()
end

---------------------------------------------------------------------------
-- Create(raidName)
-- Moved from PP:CreateSession() in Raid.lua.
---------------------------------------------------------------------------
function PP.Session:Create(raidName)
    if not PP:CanModify() then
        PP:Print("Only officers can create a session.")
        return
    end
    if PP.Repo.Roster:HasActiveSession() then
        PP:Print("A session is already active. Close it before creating a new one.")
        return
    end
    if not IsInRaid() then
        PP:Print("You must be in a raid group to create a session.")
        return
    end
    -- BroadcastSessionCreate is leader-gated; a non-leader officer would end up
    -- with a session (and a bumped activeSessionVersion) that no one else sees.
    if not PP:IsRaidLeader() then
        PP:Print("Only the raid leader can create a session.")
        return
    end

    PP:WipeRetryQueue()

    local sessionID = tostring(time()) .. "-" .. math.random(1000, 9999)
    local leader    = PP:GetPlayerFullName()
    local gk        = PP:GetActiveGuildKey()
    local gd        = PP.Repo.Roster:EnsureData(gk)
    if not raidName then
        local today = date("%Y-%m-%d")
        local count = 0
        for _, s in pairs(gd.sessions or {}) do
            if s.startTime and date("%Y-%m-%d", s.startTime) == today then
                count = count + 1
            end
        end
        raidName = "Session " .. today .. (count > 0 and (" #" .. (count + 1)) or "")
    end

    gd.sessions[sessionID] = {
        name      = raidName,
        startTime = time(),
        endTime   = nil,
        leader    = leader,
        guildKey  = gk,
        items     = {},   -- { itemLink, itemID, awardedTo, key }
        bosses    = {},   -- { encounterID, encounterName, time }
        members   = {},   -- fullName => true
        active    = true,
    }
    PP.Repo.Roster:SetActiveSessionID(gk, sessionID)

    
    PP.Roster:AutoPopulate()

    -- this does f all right now, why tf are we storing this?
    local session = gd.sessions[sessionID]
    for i = 1, GetNumGroupMembers() do
        local name = GetRaidRosterInfo(i)
        if name then session.members[PP:GetFullName(name)] = true end
    end

    PP:Print("Session created: " .. raidName)
    PP:BroadcastSessionCreate(sessionID)
    -- Catch up with the other officers' ledgers; replies land in a second or
    -- two, well before the first loot. The session doesn't wait for them.
    PP:SendLedgerHello(gk, true)
    PP:RefreshMainWindow()
end

---------------------------------------------------------------------------
-- Delete(raidID)
-- Moved from PP:DeleteRaid() in Raid.lua.
---------------------------------------------------------------------------
function PP.Session:Delete(raidID)
    if not PP:CanModify() then
        PP:Print("Only officers of the active guild can delete sessions.")
        return
    end

    local gk = PP:GetActiveGuildKey()
    local gd = PP.Repo.Roster:GetData(gk)
    if not gd or not gd.sessions[raidID] then
        PP:Print("Session not found.")
        return
    end

    -- If this is the active session, clear it first
    if gd.activeSessionID == raidID then
        PP.Repo.Roster:ClearActiveSessionID(gk)
        PP.Repo.Loot:WipeAll()
        PP:CloseLootPopups()
    end

    gd.sessions[raidID] = nil
    if gd.sessionSnapshots then gd.sessionSnapshots[raidID] = nil end
    PP.Repo.Roster:BumpRosterVersion(gk)  -- version bump so peers accept the delete

    -- Write tombstone so full-syncs propagate the deletion to offline peers
    PP.Repo.Roster:AddTombstone(gk, raidID, PP.Repo.Roster:GetRosterVersion(gk))

    PP:BroadcastSessionDelete(raidID, gk, PP.Repo.Roster:GetRosterVersion(gk))

    -- Close the detail window if it was showing this raid
    if PP._raidDetailWindow then
        PP._raidDetailWindow:Hide()
    end
    if PP._snapshotWindow then
        PP._snapshotWindow:Hide()
    end

    PP:RefreshMainWindow()
    PP:RefreshLootMasterWindow()
    PP:Print("Session deleted.")
end

---------------------------------------------------------------------------
-- CloseOrphans(guildKey)
-- A record can carry active = true without being gd.activeSessionID (e.g.
-- installed from a peer while our pointer was elsewhere). Every teardown path
-- follows the pointer, so such a record would show [ACTIVE] forever. Marks
-- them ended at their last recorded activity. Returns the number closed.
---------------------------------------------------------------------------
function PP.Session:CloseOrphans(guildKey)
    local gd = PP.Repo.Roster:GetData(guildKey)
    if not gd or not gd.sessions then return 0 end
    local closed = 0
    for id, s in pairs(gd.sessions) do
        if s.active and id ~= gd.activeSessionID then
            local last = s.startTime or time()
            for _, b in ipairs(s.bosses or {}) do
                if b.time and b.time > last then last = b.time end
            end
            for _, it in ipairs(s.items or {}) do
                if it.time and it.time > last then last = it.time end
            end
            PP.Repo.Roster:MarkSessionEnded(guildKey, id, last, PP.SESSION_END.ORPHAN_CLEANUP)
            closed = closed + 1
        end
    end
    return closed
end

---------------------------------------------------------------------------
-- IsLeaderInGroup(guildKey, sessionID)
-- true if the session's leader is in our current group, false if not, nil
-- when it can't be told yet (no leader recorded, or a member's name hasn't
-- loaded). Callers only act on an explicit false.
---------------------------------------------------------------------------
function PP.Session:IsLeaderInGroup(guildKey, sessionID)
    local gd = PP.Repo.Roster:GetData(guildKey)
    local s  = gd and sessionID and gd.sessions and gd.sessions[sessionID]
    if not s or not s.leader then return nil end
    if not IsInGroup() then return false end

    local unresolved = false
    for _, unit in ipairs(PP:GetGroupUnits()) do
        local name = PP:GetUnitFullName(unit)
        if name == s.leader then return true end
        if not name then unresolved = true end
    end
    if unresolved then return nil end
    return false
end

---------------------------------------------------------------------------
-- EndStale(guildKey, reason)
-- Ends the active session under any roster, not just the selected one.
-- The selected roster goes through End(); another roster only has its own
-- records torn down, since live loot state belongs to the selected roster.
-- Returns true if a session was ended.
---------------------------------------------------------------------------
function PP.Session:EndStale(guildKey, reason)
    local gd = PP.Repo.Roster:GetData(guildKey)
    local id = gd and gd.activeSessionID
    if not id then return false end
    if guildKey == PP:GetActiveGuildKey() then
        self:End(reason, id, guildKey)
        return true
    end
    local snap = PP.Repo.Roster:BuildRosterSnapshot(guildKey)
    if snap then PP.Repo.Roster:SetSessionSnapshot(guildKey, id, snap) end
    PP.Repo.Roster:MarkSessionEnded(guildKey, id, time(), reason)
    PP.Repo.Roster:ClearActiveSessionID(guildKey, true)
    return true
end

---------------------------------------------------------------------------
-- SweepStale(atLogin)
-- Ends active sessions, under every roster, that can't still be running:
--   * not in a group (login only; leaving a group goes through the 30 s
--     pendingSessionEnd grace in OnGroupLeft)
--   * older than SESSION_MAX_AGE (login only)
--   * the session leader isn't in our group. The selected roster in a raid
--     is left to CheckLeaderPresent, which handles leader hand-offs.
-- The session awaiting its pendingSessionEnd timer is skipped. Returns the
-- number of sessions ended.
---------------------------------------------------------------------------
function PP.Session:SweepStale(atLogin)
    local activeKey = PP:GetActiveGuildKey()
    local pending   = PP.db.global.pendingSessionEnd
    local now       = time()
    local ended     = 0
    for _, gk in ipairs(PP.Repo.Roster:GetAllGuildKeys()) do
        local gd = PP.Repo.Roster:GetData(gk)
        local id = gd and gd.activeSessionID
        local s  = id and gd.sessions and gd.sessions[id]
        local isPending = pending and pending.guildKey == gk and pending.sessionID == id
        if s and s.active and not isPending then
            local reason
            if not IsInGroup() then
                if atLogin then reason = PP.SESSION_END.STARTUP_CHECK end
            elseif atLogin and s.startTime and now - s.startTime > PP.SESSION_MAX_AGE then
                reason = PP.SESSION_END.STARTUP_CHECK
            elseif (gk ~= activeKey or not IsInRaid())
                   and self:IsLeaderInGroup(gk, id) == false then
                reason = atLogin and PP.SESSION_END.STARTUP_CHECK or PP.SESSION_END.LEADER_LEFT
            end
            if reason and self:EndStale(gk, reason) then
                ended = ended + 1
            end
        end
    end
    return ended
end

-- A new raid leader may only take over a session if they belong to it: on the
-- session's roster or in its guild. Otherwise we've ended up in someone else's
-- raid (LFR, a pug) with a session still open.
local function _belongsToSession(guildKey, fullName, unit)
    local roster = PP.Repo.Roster:GetRoster(guildKey)
    if roster[fullName] then return true end
    return unit ~= nil and GetGuildInfo(unit) == guildKey
end

---------------------------------------------------------------------------
-- CheckLeaderPresent()
-- Moved from PP:CheckSessionLeaderPresent() in Raid.lua.
---------------------------------------------------------------------------
function PP.Session:CheckLeaderPresent()
    local raid, id = PP.Repo.Roster:GetActiveSession()
    if not raid then return end

    -- If a continuation prompt is already pending, don't fire again
    if PP._pendingContinueRaidID then return end

    -- Check if the original raid leader is still in the group AND still holds rank 2.
    local leaderStillLeading = false
    for i = 1, GetNumGroupMembers() do
        local name, rank = GetRaidRosterInfo(i)
        if name and PP:GetFullName(name) == raid.leader and rank == 2 then
            leaderStillLeading = true
            break
        end
    end
    if leaderStillLeading then
        -- Original leader is back / still present; cancel any pending end timer.
        if PP._pendingLeaderLeftTimer then
            PP:CancelTimer(PP._pendingLeaderLeftTimer)
            PP._pendingLeaderLeftTimer = nil
        end
        return
    end

    -- Original leader is gone. Find the new raid leader (rank == 2).
    local newLeader, newLeaderUnit = nil, nil
    for i = 1, GetNumGroupMembers() do
        local name, rank = GetRaidRosterInfo(i)
        if rank == 2 then
            newLeader     = PP:GetFullName(name)
            newLeaderUnit = "raid" .. i
            break
        end
    end

    if newLeader and not _belongsToSession(PP:GetActiveGuildKey(), newLeader, newLeaderUnit) then
        if PP._pendingLeaderLeftTimer then
            PP:CancelTimer(PP._pendingLeaderLeftTimer)
            PP._pendingLeaderLeftTimer = nil
        end
        PP.Session:End(PP.SESSION_END.LEADER_LEFT)
        return
    end

    local me = PP:GetPlayerFullName()
    if newLeader and newLeader == me then
        -- A new leader has been found; cancel any pending end timer.
        if PP._pendingLeaderLeftTimer then
            PP:CancelTimer(PP._pendingLeaderLeftTimer)
            PP._pendingLeaderLeftTimer = nil
        end
        -- Show the continuation prompt to the new session leader
        PP._pendingContinueRaidID = id
        StaticPopup_Show("PP_CONTINUE_RAID")
    elseif not newLeader then
        -- No raid leader visible yet. During a promotion there is a brief window
        -- where no player holds rank 2. Defer the end for 5 seconds so a normal
        -- leader transition does not accidentally kill the session.
        if not PP._pendingLeaderLeftTimer then
            PP._pendingLeaderLeftTimer = PP:ScheduleTimer(function()
                PP._pendingLeaderLeftTimer = nil
                -- Re-check: a new leader may have appeared since the timer was set.
                local stillNoLeader = true
                for i = 1, GetNumGroupMembers() do
                    local _, rank = GetRaidRosterInfo(i)
                    if rank == 2 then
                        stillNoLeader = false
                        break
                    end
                end
                if stillNoLeader then
                    PP.Session:End(PP.SESSION_END.LEADER_LEFT)
                end
            end, 5)
        end
    else
        -- Someone else became leader; their client handles the prompt.
        -- Cancel any deferred end timer — the transition was clean.
        if PP._pendingLeaderLeftTimer then
            PP:CancelTimer(PP._pendingLeaderLeftTimer)
            PP._pendingLeaderLeftTimer = nil
        end
        -- Keep local raid.leader current. Without this, if leadership later
        -- returns to us, leaderStillLeading would falsely fire the early-return
        -- guard (our name still stored as leader) and we would skip the prompt.
        if newLeader then
            local gk = PP:GetActiveGuildKey()
            local gd = PP.Repo.Roster:GetData(gk)
            if gd and gd.sessions and gd.sessions[id] then
                gd.sessions[id].leader = newLeader
            end
        end
    end
end

---------------------------------------------------------------------------
-- AddBoss(id, name)
-- Moved from PP:AddBossToRaid() in Raid.lua.
---------------------------------------------------------------------------
function PP.Session:AddBoss(encounterID, encounterName)
    local raid = PP.Repo.Roster:GetActiveSession()
    if not raid then return end
    raid.bosses[#raid.bosses + 1] = {
        encounterID   = encounterID,
        encounterName = encounterName or "Unknown",
        time          = time(),
    }
end

---------------------------------------------------------------------------
-- RecordItemAward(itemLink, itemID, awardedTo, pointsSpent, response, lootKey)
-- Receivers run _adoptSessionContext before this fires, so the active session
-- is already correct for the receiver's local state.
---------------------------------------------------------------------------
function PP.Session:RecordItemAward(itemLink, itemID, awardedTo, pointsSpent, response, lootKey)
    local session = PP.Repo.Roster:GetActiveSession()
    if not session then return end
    session.items[#session.items + 1] = {
        itemLink    = itemLink,
        itemID      = itemID,
        awardedTo   = awardedTo,
        pointsSpent = pointsSpent or 0,
        response    = response or PP.RESPONSE.NEED,
        time        = time(),
        key         = lootKey,
    }
end
