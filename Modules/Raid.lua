---------------------------------------------------------------------------
-- Pirates Plunder – Raid Management
---------------------------------------------------------------------------
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

---------------------------------------------------------------------------
-- Create a new raid
---------------------------------------------------------------------------
function PP:CreateRaid(raidName)
    if not self:CanModify() then
        self:Print("Only officers can create a raid.")
        return
    end
    if self:HasActiveRaid() then
        self:Print("A raid is already active. Close it before creating a new one.")
        return
    end
    if not IsInRaid() then
        self:Print("You must be in a raid group to create a raid.")
        return
    end

    local raidID   = tostring(time()) .. "-" .. math.random(1000, 9999)
    local leader   = self:GetPlayerFullName()
    local gk       = self:GetActiveGuildKey()
    local gd       = self:GetGuildData(gk)
    raidName       = raidName or ("Raid " .. date("%Y-%m-%d %H:%M"))

    gd.raids[raidID] = {
        name      = raidName,
        startTime = time(),
        endTime   = nil,
        leader    = leader,
        guildKey  = gk,
        items     = {},   -- { itemLink, itemID, awardedTo }
        bosses    = {},   -- { encounterID, encounterName, time }
        members   = {},   -- fullName => true
        active    = true,
    }
    gd.activeRaidID = raidID

    -- Snapshot current members
    self:AutoPopulateRoster()
    local raid = gd.raids[raidID]
    for i = 1, GetNumGroupMembers() do
        local name = GetRaidRosterInfo(i)
        if name then raid.members[self:GetFullName(name)] = true end
    end

    self:Print("Raid created: " .. raidName)
    self:BroadcastRaidCreate(raidID)
    self:RefreshMainWindow()
end

---------------------------------------------------------------------------
-- End / close a raid
---------------------------------------------------------------------------
function PP:EndRaid()
    local raid, id = self:GetActiveRaid()
    if not raid then return end

    raid.active  = false
    raid.endTime = time()
    self:GetGuildData(self:GetActiveGuildKey()).activeRaidID = nil

    -- Clear any pending loot
    wipe(self.pendingLoot)
    self:CloseLootPopups()

    self:Print("Raid ended: " .. (raid.name or id))
    self:BroadcastRaidClose(id)
    self:RefreshMainWindow()
    self:RefreshLootMasterWindow()
end

---------------------------------------------------------------------------
-- Boss tracking inside a raid
---------------------------------------------------------------------------
function PP:AddBossToRaid(encounterID, encounterName)
    local raid = self:GetActiveRaid()
    if not raid then return end
    raid.bosses[#raid.bosses + 1] = {
        encounterID   = encounterID,
        encounterName = encounterName or "Unknown",
        time          = time(),
    }
end

---------------------------------------------------------------------------
-- Item tracking inside a raid
---------------------------------------------------------------------------
function PP:RecordItemAward(itemLink, itemID, awardedTo, pointsSpent, response)
    local raid = self:GetActiveRaid()
    if not raid then return end
    raid.items[#raid.items + 1] = {
        itemLink    = itemLink,
        itemID      = itemID,
        awardedTo   = awardedTo,
        pointsSpent = pointsSpent or 0,
        response    = response or PP.RESPONSE.NEED,
        time        = time(),
    }
end

---------------------------------------------------------------------------
-- Delete a raid record permanently (officer only)
---------------------------------------------------------------------------
function PP:DeleteRaid(raidID)
    if not self:IsOfficerOrHigher() then
        self:Print("Only guild officers can delete raids.")
        return
    end

    local gk = self:GetActiveGuildKey()
    local gd = self:GetGuildData(gk)
    if not gd or not gd.raids[raidID] then
        self:Print("Raid not found.")
        return
    end

    -- If this is the active raid, clear it first
    if gd.activeRaidID == raidID then
        gd.activeRaidID = nil
        wipe(self.pendingLoot)
        self:CloseLootPopups()
    end

    gd.raids[raidID] = nil
    self:BumpRosterVersion(gk)  -- version bump so peers accept the delete

    -- Write tombstone so full-syncs propagate the deletion to offline peers
    if not gd.deletedRaids then gd.deletedRaids = {} end
    gd.deletedRaids[raidID] = gd.rosterVersion

    self:BroadcastRaidDelete(raidID, gk, gd.rosterVersion)

    -- Close the detail window if it was showing this raid
    if self._raidDetailWindow then
        self._raidDetailWindow:Release()
        self._raidDetailWindow = nil
    end

    self:RefreshMainWindow()
    self:RefreshLootMasterWindow()
    self:Print("Raid deleted.")
end

---------------------------------------------------------------------------
-- Check if the original raid leader is still present
---------------------------------------------------------------------------
function PP:CheckRaidLeaderPresent()
    local raid, id = self:GetActiveRaid()
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
        -- Show the continuation prompt to the new raid leader
        self._pendingContinueRaidID = id
        StaticPopup_Show("PP_CONTINUE_RAID")
    elseif not newLeader then
        -- No raid leader at all; end the raid immediately
        self:EndRaid()
        self:Print("Raid ended – the raid leader left the group.")
    end
    -- If someone else is the new leader, their client handles the prompt
end

---------------------------------------------------------------------------
-- Raid history helpers
---------------------------------------------------------------------------
function PP:GetRaidHistory()
    local list = {}
    for id, raid in pairs(self:GetGuildRaids()) do
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
