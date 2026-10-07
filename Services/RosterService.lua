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

-- Build a new roster entry table from a normalised fullName.
local function NewEntry(fullName)
    return {
        name  = PP:GetShortName(fullName),
        realm = fullName:match("-(.+)$") or "",
        score = 0,
    }
end

---------------------------------------------------------------------------
-- Score writes
-- Officers on their own guild's roster write to the ledger
-- (Repository/LedgerRepository.lua) and gd.roster is rebuilt from it; every
-- other client edits gd.roster directly. Each call is one change; follow it
-- with Commit.
---------------------------------------------------------------------------

-- Players changed in the ledger since the last Commit, per guild key; Commit
-- sends them to the other officers as LEDGER_OPS.
local touched = {}

local function Touched(gk, names)
    touched[gk] = touched[gk] or {}
    for fullName in pairs(names) do touched[gk][fullName] = true end
end

-- targets: { [fullName] = newScore } for players already on the roster.
function PP.Roster:SetScores(targets, gk)
    gk = gk or PP:GetActiveGuildKey()
    local ledger = PP.Repo.Ledger:GetActive(gk)
    if ledger then
        PP.Repo.Ledger:SetTo(ledger, targets)
        Touched(gk, targets)
        return
    end
    local roster = PP.Repo.Roster:GetRoster(gk)
    for fullName, score in pairs(targets) do
        if roster[fullName] then roster[fullName].score = score end
    end
end

-- deltas: { [fullName] = n } for players already on the roster.
function PP.Roster:AddScores(deltas, gk)
    gk = gk or PP:GetActiveGuildKey()
    local ledger = PP.Repo.Ledger:GetActive(gk)
    if ledger then
        PP.Repo.Ledger:Adjust(ledger, deltas)
        Touched(gk, deltas)
        return
    end
    local roster = PP.Repo.Roster:GetRoster(gk)
    for fullName, d in pairs(deltas) do
        if roster[fullName] then roster[fullName].score = roster[fullName].score + d end
    end
end

-- resets: { [fullName] = { base = n } | { rm = true } }. Adds missing
-- players, overwrites scores, or removes players.
function PP.Roster:ResetEntries(resets, gk)
    gk = gk or PP:GetActiveGuildKey()
    local ledger = PP.Repo.Ledger:GetActive(gk)
    if ledger then
        PP.Repo.Ledger:Reset(ledger, resets)
        Touched(gk, resets)
        return
    end
    local roster = PP.Repo.Roster:GetRoster(gk)
    for fullName, r in pairs(resets) do
        if r.rm then
            roster[fullName] = nil
        else
            roster[fullName] = roster[fullName] or NewEntry(fullName)
            roster[fullName].score = r.base or 0
        end
    end
end

-- Advances rosterVersion (derived on a ledger client), then optionally
-- broadcasts the roster and refreshes the UI.
function PP.Roster:Commit(gk, broadcast)
    gk = gk or PP:GetActiveGuildKey()
    if PP.Repo.Ledger:GetActive(gk) then
        PP.Repo.Ledger:Rebuild(gk)
        if touched[gk] then
            PP:SendLedgerOps(gk, touched[gk])
            touched[gk] = nil
        end
    else
        PP.Repo.Roster:BumpRosterVersion(gk)
    end
    if broadcast then PP:BroadcastRoster() end
    PP:RefreshMainWindow()
end

local function CommitRosterChange()
    PP.Roster:Commit(nil, true)
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
    self:ResetEntries({ [fullName] = { base = 0 } })
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
    self:ResetEntries({ [fullName] = { rm = true } })
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
    self:SetScores({ [fullName] = newScore })
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
    local resets = {}
    for idx, fullName in ipairs(names) do
        resets[fullName] = { base = #names - idx + 1 }
    end
    self:ResetEntries(resets)

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
    local resets = {}
    for fullName in pairs(PP.Repo.Roster:GetRoster()) do
        resets[fullName] = { rm = true }
    end
    self:ResetEntries(resets)
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
    local roster = PP.Repo.Roster:GetRoster()
    local resets = {}

    for i = 1, count do
        local fullName = PP:GetUnitFullName("raid" .. i)
        if fullName and not roster[fullName] then
            resets[fullName] = { base = 0 }
        end
    end

    if next(resets) then
        self:ResetEntries(resets)
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
    local deltas = {}
    for i = 1, count do
        local name = GetRaidRosterInfo(i)
        if name then
            local fullName = PP:GetFullName(name)
            if roster[fullName] then
                deltas[fullName] = amount
            end
        end
    end
    if not next(deltas) then return end
    self:AddScores(deltas)
    self:Commit()
    PP:BroadcastGroupScore(amount)
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
