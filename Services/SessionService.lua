---------------------------------------------------------------------------
-- Pirates Plunder – Session Service
-- Canonical session lifecycle management.
---------------------------------------------------------------------------
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
}

---------------------------------------------------------------------------
-- End(reason, sessionID, guildKey)
-- THE canonical session teardown.
---------------------------------------------------------------------------
function PP.Session:End(reason, sessionID, guildKey)
    guildKey  = guildKey  or PP:GetActiveGuildKey()
    local gd  = PP.Repo.Guild:GetData(guildKey)
    sessionID = sessionID or (gd and gd.activeSessionID)
    if not sessionID then return end

    PP.Repo.Guild:MarkSessionEnded(guildKey, sessionID, time(), reason)
    PP.Repo.Guild:ClearActiveSessionID(guildKey)
    PP.Repo.Loot:WipeAll()
    PP:CloseLootPopups()
    PP.Repo.Loot:Save()

    -- Reason-specific messaging
    if reason == PP.SESSION_END.OFFICER_ACTION then
        local gd2 = PP.Repo.Guild:GetData(guildKey)
        local session = gd2 and gd2.sessions and gd2.sessions[sessionID]
        PP:Print("Session ended: " .. (session and session.name or sessionID))
        PP:BroadcastSessionClose(sessionID)
    elseif reason == PP.SESSION_END.LEFT_GROUP then
        local me = PP:GetPlayerFullName()
        local gd2 = PP.Repo.Guild:GetData(guildKey)
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
    if PP.Repo.Guild:HasActiveSession() then
        PP:Print("A session is already active. Close it before creating a new one.")
        return
    end
    if not IsInRaid() then
        PP:Print("You must be in a raid group to create a session.")
        return
    end

    local sessionID = tostring(time()) .. "-" .. math.random(1000, 9999)
    local leader    = PP:GetPlayerFullName()
    local gk        = PP:GetActiveGuildKey()
    local gd        = PP.Repo.Guild:GetData(gk)
    raidName        = raidName or ("Session " .. date("%Y-%m-%d %H:%M"))

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
    PP.Repo.Guild:SetActiveSessionID(gk, sessionID)

    -- Snapshot current members
    PP.Roster:AutoPopulate()
    local session = gd.sessions[sessionID]
    for i = 1, GetNumGroupMembers() do
        local name = GetRaidRosterInfo(i)
        if name then session.members[PP:GetFullName(name)] = true end
    end

    PP:Print("Session created: " .. raidName)
    PP:BroadcastSessionCreate(sessionID)
    PP:RefreshMainWindow()
end

---------------------------------------------------------------------------
-- Delete(raidID)
-- Moved from PP:DeleteRaid() in Raid.lua.
---------------------------------------------------------------------------
function PP.Session:Delete(raidID)
    if not PP:IsOfficerOrHigher() then
        PP:Print("Only guild officers can delete sessions.")
        return
    end

    local gk = PP:GetActiveGuildKey()
    local gd = PP.Repo.Guild:GetData(gk)
    if not gd or not gd.sessions[raidID] then
        PP:Print("Session not found.")
        return
    end

    -- If this is the active session, clear it first
    if gd.activeSessionID == raidID then
        PP.Repo.Guild:ClearActiveSessionID(gk)
        PP.Repo.Loot:WipeAll()
        PP:CloseLootPopups()
    end

    gd.sessions[raidID] = nil
    PP.Repo.Guild:BumpRosterVersion(gk)  -- version bump so peers accept the delete

    -- Write tombstone so full-syncs propagate the deletion to offline peers
    PP.Repo.Guild:AddTombstone(gk, raidID, PP.Repo.Guild:GetRosterVersion(gk))

    PP:BroadcastSessionDelete(raidID, gk, PP.Repo.Guild:GetRosterVersion(gk))

    -- Close the detail window if it was showing this raid
    if PP._raidDetailWindow then
        PP._raidDetailWindow:Release()
        PP._raidDetailWindow = nil
    end

    PP:RefreshMainWindow()
    PP:RefreshLootMasterWindow()
    PP:Print("Session deleted.")
end

---------------------------------------------------------------------------
-- CheckLeaderPresent()
-- Moved from PP:CheckSessionLeaderPresent() in Raid.lua.
---------------------------------------------------------------------------
function PP.Session:CheckLeaderPresent()
    local raid, id = PP.Repo.Guild:GetActiveSession()
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
    if leaderStillLeading then return end

    -- Original leader is gone. Find the new raid leader (rank == 2).
    local newLeader = nil
    for i = 1, GetNumGroupMembers() do
        local name, rank = GetRaidRosterInfo(i)
        if rank == 2 then
            newLeader = PP:GetFullName(name)
            break
        end
    end

    local me = PP:GetPlayerFullName()
    if newLeader and newLeader == me then
        -- Show the continuation prompt to the new session leader
        PP._pendingContinueRaidID = id
        StaticPopup_Show("PP_CONTINUE_RAID")
    elseif not newLeader then
        -- No raid leader at all; end the session immediately
        PP.Session:End(PP.SESSION_END.LEADER_LEFT)
    end
    -- If someone else is the new leader, their client handles the prompt
end

---------------------------------------------------------------------------
-- AddBoss(id, name)
-- Moved from PP:AddBossToRaid() in Raid.lua.
---------------------------------------------------------------------------
function PP.Session:AddBoss(encounterID, encounterName)
    local raid = PP.Repo.Guild:GetActiveSession()
    if not raid then return end
    raid.bosses[#raid.bosses + 1] = {
        encounterID   = encounterID,
        encounterName = encounterName or "Unknown",
        time          = time(),
    }
end

---------------------------------------------------------------------------
-- RecordItemAward(itemLink, itemID, awardedTo, pointsSpent, response, lootKey)
-- Moved from PP:RecordItemAward() in Raid.lua.
---------------------------------------------------------------------------
function PP.Session:RecordItemAward(itemLink, itemID, awardedTo, pointsSpent, response, lootKey)
    local session = PP.Repo.Guild:GetActiveSession()
    if not session then return end
    session.items[#session.items + 1] = {
        itemLink    = itemLink,
        itemID      = itemID,
        awardedTo   = awardedTo,
        pointsSpent = pointsSpent or 0,
        response    = response or PP.RESPONSE.NEED,
        time        = time(),
        key         = lootKey,  -- loot key for LOOT_STATE_QUERY matching
    }
end
