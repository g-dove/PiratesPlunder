---------------------------------------------------------------------------
-- Pirates Plunder – Roster & Scoring
---------------------------------------------------------------------------
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

---------------------------------------------------------------------------
-- Auto-populate roster from current raid/party
---------------------------------------------------------------------------
function PP:AutoPopulateRoster()
    if not IsInRaid() then return end
    local count = GetNumGroupMembers()

    for i = 1, count do
        local unit = "raid" .. i
        local name, realm = UnitName(unit)
        if name and name ~= UNKNOWNOBJECT and name ~= "" then
            local fullName = self:GetFullName(name .. (realm and realm ~= "" and ("-" .. realm) or ""))
            local roster = self:GetRoster()
            if not roster[fullName] then
                local shortName = self:GetShortName(fullName)
                local realmPart = fullName:match("-(.+)$") or ""
                roster[fullName] = {
                    name  = shortName,
                    realm = realmPart,
                    score = 0,
                }
            end
        end
    end
end

---------------------------------------------------------------------------
-- Manual add / remove
---------------------------------------------------------------------------
function PP:AddToRoster(fullName)
    fullName = self:GetFullName(fullName)
    local roster = self:GetRoster()
    if roster[fullName] then
        self:Print(self:GetShortName(fullName) .. " is already in the roster.")
        return
    end
    roster[fullName] = {
        name  = self:GetShortName(fullName),
        realm = fullName:match("-(.+)$") or "",
        score = 0,
    }
    self:BumpRosterVersion()
    self:BroadcastRoster()
    self:RefreshMainWindow()
end

function PP:RemoveFromRoster(fullName)
    fullName = self:GetFullName(fullName)
    self:GetRoster()[fullName] = nil
    self:BumpRosterVersion()
    self:BroadcastRoster()
    self:RefreshMainWindow()
end

---------------------------------------------------------------------------
-- Manual score adjustment
---------------------------------------------------------------------------
function PP:SetPlayerScore(fullName, newScore)
    if not self:CanModify() then
        self:Print("Only officers can adjust scores.")
        return
    end
    fullName = self:GetFullName(fullName)
    local roster = self:GetRoster()
    if not roster[fullName] then
        self:Print("Player not found in roster.")
        return
    end
    newScore = tonumber(newScore) or 0
    roster[fullName].score = newScore
    self:BumpRosterVersion()
    self:BroadcastRoster()
    self:RefreshMainWindow()
    self:Print(self:GetShortName(fullName) .. " score set to " .. newScore)
end

---------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------

-- Randomize order: shuffle all roster members and assign scores N..1
function PP:RandomizeRosterOrder()
    if not self:CanModify() then
        self:Print("Only officers can randomize the roster.")
        return
    end

    local roster = self:GetRoster()
    local names = {}
    for fullName in pairs(roster) do
        names[#names + 1] = fullName
    end

    -- Fisher-Yates shuffle
    for i = #names, 2, -1 do
        local j = math.random(1, i)
        names[i], names[j] = names[j], names[i]
    end

    -- Top of list = highest score = #names, bottom = 1
    for idx, fullName in ipairs(names) do
        roster[fullName].score = #names - idx + 1
    end

    self:BumpRosterVersion()
    self:Print("Roster order randomized!")
    self:BroadcastRoster()
    self:RefreshMainWindow()
end

-- Add +1 score to every player currently in the raid
function PP:AddScoreToRaidMembers(amount)
    amount = amount or 1
    if not IsInRaid() then return end
    local roster = self:GetRoster()
    local count = GetNumGroupMembers()
    for i = 1, count do
        local name = GetRaidRosterInfo(i)
        if name then
            local fullName = self:GetFullName(name)
            if roster[fullName] then
                roster[fullName].score = roster[fullName].score + amount
            end
        end
    end
    self:BumpRosterVersion()
    self:BroadcastRoster()
    self:RefreshMainWindow()
end

-- Boss kill handler
function PP:OnBossKill(encounterID, encounterName)
    -- Record the boss in the active raid
    self:AddBossToRaid(encounterID, encounterName)
    -- +1 score to all raid members
    self:AddScoreToRaidMembers(1)
    self:Print("Boss defeated: " .. (encounterName or "Unknown") .. " – +1 score to all raid members!")
end

-- Clear the entire roster
function PP:ClearRoster()
    if not self:CanModify() then
        self:Print("Only officers can clear the roster.")
        return
    end
    wipe(self:GetRoster())
    self:BumpRosterVersion()
    self:Print("Roster cleared.")
    self:BroadcastRoster()
    self:RefreshMainWindow()
end

-- Get roster sorted by score descending
function PP:GetSortedRoster()
    local list = {}
    for fullName, data in pairs(self:GetRoster()) do
        list[#list + 1] = {
            fullName = fullName,
            name     = data.name,
            realm    = data.realm,
            score    = data.score,
        }
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.name < b.name  -- alphabetical tiebreak for display
    end)
    return list
end

-- Get current raid member full names as a set.
-- In sandbox mode returns just the local player so non-responder tracking works.
function PP:GetRaidMemberSet()
    if self._sandbox then
        local set = {}
        set[self:GetPlayerFullName()] = true
        return set
    end
    local set = {}
    if not IsInRaid() then return set end
    for i = 1, GetNumGroupMembers() do
        local name = GetRaidRosterInfo(i)
        if name then
            set[self:GetFullName(name)] = true
        end
    end
    return set
end
