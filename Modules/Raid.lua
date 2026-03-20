---------------------------------------------------------------------------
-- Pirates Plunder – Raid Management
---------------------------------------------------------------------------
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

---------------------------------------------------------------------------
-- Create a new session
---------------------------------------------------------------------------
function PP:CreateSession(raidName)
    if not self:CanModify() then
        self:Print("Only officers can create a session.")
        return
    end
    if self:HasActiveSession() then
        self:Print("A session is already active. Close it before creating a new one.")
        return
    end
    if not IsInRaid() then
        self:Print("You must be in a raid group to create a session.")
        return
    end

    local sessionID = tostring(time()) .. "-" .. math.random(1000, 9999)
    local leader    = self:GetPlayerFullName()
    local gk        = self:GetActiveGuildKey()
    local gd        = self:GetGuildData(gk)
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
    gd.activeSessionID = sessionID

    -- Snapshot current members
    self:AutoPopulateRoster()
    local session = gd.sessions[sessionID]
    for i = 1, GetNumGroupMembers() do
        local name = GetRaidRosterInfo(i)
        if name then session.members[self:GetFullName(name)] = true end
    end

    self:Print("Session created: " .. raidName)
    self:BroadcastSessionCreate(sessionID)
    self:RefreshMainWindow()
end

---------------------------------------------------------------------------
-- End / close a session
---------------------------------------------------------------------------
function PP:EndSession()
    local session, id = self:GetActiveSession()
    if not session then return end

    session.active  = false
    session.endTime = time()
    self:GetGuildData(self:GetActiveGuildKey()).activeSessionID = nil

    -- Clear any pending loot
    wipe(self.pendingLoot)
    self:CloseLootPopups()

    self:Print("Session ended: " .. (session.name or id))
    self:BroadcastSessionClose(id)
    self:RefreshMainWindow()
    self:RefreshLootMasterWindow()
end

---------------------------------------------------------------------------
-- Boss tracking inside a session
---------------------------------------------------------------------------
function PP:AddBossToRaid(encounterID, encounterName)
    local raid = self:GetActiveSession()
    if not raid then return end
    raid.bosses[#raid.bosses + 1] = {
        encounterID   = encounterID,
        encounterName = encounterName or "Unknown",
        time          = time(),
    }
end

---------------------------------------------------------------------------
-- Item tracking inside a session
---------------------------------------------------------------------------
function PP:RecordItemAward(itemLink, itemID, awardedTo, pointsSpent, response, lootKey)
    local session = self:GetActiveSession()
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

---------------------------------------------------------------------------
-- Delete a session record permanently (officer only)
---------------------------------------------------------------------------
function PP:DeleteRaid(raidID)
    if not self:IsOfficerOrHigher() then
        self:Print("Only guild officers can delete sessions.")
        return
    end

    local gk = self:GetActiveGuildKey()
    local gd = self:GetGuildData(gk)
    if not gd or not gd.sessions[raidID] then
        self:Print("Session not found.")
        return
    end

    -- If this is the active session, clear it first
    if gd.activeSessionID == raidID then
        gd.activeSessionID = nil
        wipe(self.pendingLoot)
        self:CloseLootPopups()
    end

    gd.sessions[raidID] = nil
    self:BumpRosterVersion(gk)  -- version bump so peers accept the delete

    -- Write tombstone so full-syncs propagate the deletion to offline peers
    if not gd.deletedSessions then gd.deletedSessions = {} end
    gd.deletedSessions[raidID] = gd.rosterVersion

    self:BroadcastSessionDelete(raidID, gk, gd.rosterVersion)

    -- Close the detail window if it was showing this raid
    if self._raidDetailWindow then
        self._raidDetailWindow:Release()
        self._raidDetailWindow = nil
    end

    self:RefreshMainWindow()
    self:RefreshLootMasterWindow()
    self:Print("Session deleted.")
end

---------------------------------------------------------------------------
-- Check if the original session leader is still present
---------------------------------------------------------------------------
function PP:CheckSessionLeaderPresent()
    local raid, id = self:GetActiveSession()
    if not raid then return end

    -- If a continuation prompt is already pending, don't fire again
    if self._pendingContinueRaidID then return end

    -- Check if the original raid leader is still in the group AND still holds rank 2.
    -- If they passed lead to someone else they'll still be present but rank will have
    -- dropped, so we still need to offer the continuation prompt to the new leader.
    local leaderStillLeading = false
    for i = 1, GetNumGroupMembers() do
        local name, rank = GetRaidRosterInfo(i)
        if name and self:GetFullName(name) == raid.leader and rank == 2 then
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
            newLeader = self:GetFullName(name)
            break
        end
    end

    local me = self:GetPlayerFullName()
    if newLeader and newLeader == me then
        -- Show the continuation prompt to the new session leader
        self._pendingContinueRaidID = id
        StaticPopup_Show("PP_CONTINUE_RAID")
    elseif not newLeader then
        -- No raid leader at all; end the session immediately
        self:EndSession()
        self:Print("Session ended – the session leader left the group.")
    end
    -- If someone else is the new leader, their client handles the prompt
end

---------------------------------------------------------------------------
-- Session history helpers
---------------------------------------------------------------------------
function PP:GetRaidHistory()
    local list = {}
    for id, raid in pairs(self:GetGuildSessions()) do
        list[#list + 1] = {
            id        = id,
            name      = raid.name,
            startTime = raid.startTime,
            endTime   = raid.endTime,
            leader    = raid.leader,
            active    = raid.active,
            bossCount = #raid.bosses,
            itemCount = #raid.items,
        }
    end
    table.sort(list, function(a, b) return a.startTime > b.startTime end)
    return list
end
