---------------------------------------------------------------------------
-- Pirates Plunder – Roster Service
-- All roster manipulation goes through this table.
---------------------------------------------------------------------------
---@type PPAddon
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

PP.Roster = PP.Roster or {}

---------------------------------------------------------------------------
-- Private helpers
---------------------------------------------------------------------------

-- Bump version, broadcast, and redraw after any roster mutation.
local function CommitRosterChange()
    PP.Repo.Roster:BumpRosterVersion()
    PP:BroadcastRoster()
    PP:RefreshMainWindow()
end

-- Build a new roster entry table from a normalised fullName.
local function NewEntry(fullName)
    return {
        name  = PP:GetShortName(fullName),
        realm = fullName:match("-(.+)$") or "",
        score = 0,
    }
end

---------------------------------------------------------------------------
-- Add(fullName)
-- Moved from PP:AddToRoster() in Roster.lua.
---------------------------------------------------------------------------
function PP.Roster:Add(fullName)
    if not PP:CanModify() then
        PP:Print("Insufficient Permissions.")
        return
    end
    fullName = PP:GetFullName(fullName)
    local roster = PP.Repo.Roster:GetRoster()
    if roster[fullName] then
        PP:Print(PP:GetShortName(fullName) .. " is already in the roster.")
        return
    end
    roster[fullName] = NewEntry(fullName)
    CommitRosterChange()
end

---------------------------------------------------------------------------
-- Remove(fullName)
-- Moved from PP:RemoveFromRoster() in Roster.lua.
---------------------------------------------------------------------------
function PP.Roster:Remove(fullName)
    if not PP:CanModify() then
        PP:Print("Insufficient Permissions.")
        return
    end
    fullName = PP:GetFullName(fullName)
    PP.Repo.Roster:GetRoster()[fullName] = nil
    CommitRosterChange()
end

---------------------------------------------------------------------------
-- SetScore(fullName, score)
-- Moved from PP:SetPlayerScore() in Roster.lua.
---------------------------------------------------------------------------
function PP.Roster:SetScore(fullName, newScore)
    if not PP:CanModify() then
        PP:Print("Only officers can adjust scores.")
        return
    end
    fullName = PP:GetFullName(fullName)
    local roster = PP.Repo.Roster:GetRoster()
    if not roster[fullName] then
        PP:Print("Player not found in roster.")
        return
    end
    newScore = tonumber(newScore) or 0
    roster[fullName].score = newScore
    CommitRosterChange()
    PP:Print(PP:GetShortName(fullName) .. " score set to " .. newScore)
end

---------------------------------------------------------------------------
-- Randomize()
-- Moved from PP:RandomizeRosterOrder() in Roster.lua.
---------------------------------------------------------------------------
function PP.Roster:Randomize()
    if not PP:CanModify() then
        PP:Print("Only officers can randomize the roster.")
        return
    end

    local roster = PP.Repo.Roster:GetRoster()
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

    PP:Print("Roster order randomized!")
    CommitRosterChange()
end

---------------------------------------------------------------------------
-- Clear()
-- Moved from PP:ClearRoster() in Roster.lua.
---------------------------------------------------------------------------
function PP.Roster:Clear()
    if not PP:CanModify() then
        PP:Print("Only officers can clear the roster.")
        return
    end
    wipe(PP.Repo.Roster:GetRoster())
    PP:Print("Roster cleared.")
    CommitRosterChange()
end

---------------------------------------------------------------------------
-- AutoPopulate()
-- Moved from PP:AutoPopulateRoster() in Roster.lua.
---------------------------------------------------------------------------
function PP.Roster:AutoPopulate()
    if not IsInRaid() then return end
    if not PP:IsRaidLeader() then return end
    local count = GetNumGroupMembers()
    local added = false

    for i = 1, count do
        local unit = "raid" .. i
        local name, realm = UnitName(unit)
        if name and name ~= UNKNOWNOBJECT and name ~= "" then
            local fullName = PP:GetFullName(name .. (realm and realm ~= "" and ("-" .. realm) or ""))
            local roster = PP.Repo.Roster:GetRoster()
            if not roster[fullName] then
                roster[fullName] = NewEntry(fullName)
                added = true
            end
        end
    end

    if added then
        CommitRosterChange()
    end
end

---------------------------------------------------------------------------
-- AddScoreToRaidMembers(amount)
-- Moved from PP:AddScoreToRaidMembers() in Roster.lua.
---------------------------------------------------------------------------
function PP.Roster:AddScoreToRaidMembers(amount)
    if not PP:CanModify() then return end
    amount = amount or 1
    if not IsInRaid() then return end
    local roster = PP.Repo.Roster:GetRoster()
    local count = GetNumGroupMembers()
    for i = 1, count do
        local name = GetRaidRosterInfo(i)
        if name then
            local fullName = PP:GetFullName(name)
            if roster[fullName] then
                roster[fullName].score = roster[fullName].score + amount
            end
        end
    end
    CommitRosterChange()
end

---------------------------------------------------------------------------
-- GetSorted()
-- Moved from PP:GetSortedRoster() in Roster.lua.
---------------------------------------------------------------------------
function PP.Roster:GetSorted()
    local list = {}
    for fullName, data in pairs(PP.Repo.Roster:GetRoster()) do
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

---------------------------------------------------------------------------
-- GetRaidMemberSet()
-- Moved from PP:GetRaidMemberSet() in Roster.lua.
---------------------------------------------------------------------------
function PP.Roster:GetRaidMemberSet()
    if PP._sandbox then
        local set = {}
        set[PP:GetPlayerFullName()] = true
        return set
    end
    local set = {}
    if not IsInRaid() then return set end
    for i = 1, GetNumGroupMembers() do
        local name = GetRaidRosterInfo(i)
        if name then
            set[PP:GetFullName(name)] = true
        end
    end
    return set
end
