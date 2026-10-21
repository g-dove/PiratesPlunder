---------------------------------------------------------------------------
-- Pirates Plunder – Loot Repository
-- All runtime loot state access goes through this table.
---------------------------------------------------------------------------
---@type PPAddon
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

PP.Repo      = PP.Repo or {}
PP.Repo.Loot = PP.Repo.Loot or {}

---------------------------------------------------------------------------
-- pendingLoot accessors
---------------------------------------------------------------------------
function PP.Repo.Loot:GetEntry(key)
    return PP.pendingLoot[key]
end

function PP.Repo.Loot:SetEntry(key, entry)
    PP.pendingLoot[key] = entry
    PP.Repo.Loot:Save()
end

function PP.Repo.Loot:ClearEntry(key)
    PP.pendingLoot[key] = nil
    PP.Repo.Loot:Save()
end

function PP.Repo.Loot:WipeAll()
    wipe(PP.pendingLoot)
    PP.Repo.Loot:Save()
end

function PP.Repo.Loot:GetAll()
    return PP.pendingLoot
end

---------------------------------------------------------------------------
-- lootQueue accessors
---------------------------------------------------------------------------
function PP.Repo.Loot:GetQueue()
    return PP.lootQueue
end

function PP.Repo.Loot:AddToQueue(link)
    PP.lootQueue[#PP.lootQueue + 1] = { itemLink = link }
end

---------------------------------------------------------------------------
-- pendingTrades accessors
---------------------------------------------------------------------------
function PP.Repo.Loot:GetPendingTrades()
    return PP.pendingTrades
end

function PP.Repo.Loot:RemovePendingTrade(idx)
    table.remove(PP.pendingTrades, idx)
    PP.Repo.Loot:Save()
end

-- Removes the first pending trade matching itemID + recipient.
-- Returns true if one was found.
function PP.Repo.Loot:RemovePendingTradeFor(itemID, awardedTo)
    for i, p in ipairs(PP.pendingTrades) do
        if p.itemID == itemID and p.awardedTo == awardedTo then
            table.remove(PP.pendingTrades, i)
            PP.Repo.Loot:Save()
            return true
        end
    end
    return false
end

function PP.Repo.Loot:HasPendingTradeFor(itemID, awardedTo)
    for _, p in ipairs(PP.pendingTrades) do
        if p.itemID == itemID and p.awardedTo == awardedTo then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- lootHistory accessors
-- Awarded items for the active session, keyed by loot key, with the
-- responses captured at award time. Cleared when the session ends.
---------------------------------------------------------------------------
function PP.Repo.Loot:GetHistory()
    return PP.lootHistory
end

function PP.Repo.Loot:GetHistoryEntry(key)
    return PP.lootHistory[key]
end

function PP.Repo.Loot:SetHistoryEntry(key, entry)
    PP.lootHistory[key] = entry
    PP.Repo.Loot:Save()
end

-- WipeHistory(guildKey?, sessionID?) – no args wipes everything; otherwise
-- only entries matching the given roster (and session, if passed).
function PP.Repo.Loot:WipeHistory(guildKey, sessionID)
    if not guildKey then
        wipe(PP.lootHistory)
    else
        for key, h in pairs(PP.lootHistory) do
            if h.guildKey == guildKey and (not sessionID or h.sessionID == sessionID) then
                PP.lootHistory[key] = nil
            end
        end
    end
    PP.Repo.Loot:Save()
end

---------------------------------------------------------------------------
-- Save() – persist pending loot across reloads
-- (moved from PP:SavePendingLoot in main.lua)
---------------------------------------------------------------------------
function PP.Repo.Loot:Save()
    -- Store in DB so it survives /reload; skip entirely in sandbox mode
    if not PP.db then return end
    if PP._sandbox then return end
    PP.db.global.pendingLootCache = {}
    for key, entry in pairs(PP.pendingLoot) do
        if not entry.awarded then
            PP.db.global.pendingLootCache[key] = {
                itemLink      = entry.itemLink,
                itemID        = entry.itemID,
                postedBy      = entry.postedBy,
                responses     = entry.responses or {},
                votes         = entry.votes or {},
                allowTransmog = entry.allowTransmog ~= false,
            }
        end
    end
    PP.db.global.pendingTradesCache = {}
    for i, entry in ipairs(PP.pendingTrades) do
        PP.db.global.pendingTradesCache[i] = {
            itemLink  = entry.itemLink,
            itemID    = entry.itemID,
            awardedTo = entry.awardedTo,
        }
    end
    PP.db.global.lootHistoryCache = {}
    for key, entry in pairs(PP.lootHistory) do
        PP.db.global.lootHistoryCache[key] = entry
    end
end

---------------------------------------------------------------------------
-- Restore() – restore pending loot saved across reloads
-- (moved from PP:RestorePendingLoot in main.lua)
---------------------------------------------------------------------------
function PP.Repo.Loot:Restore()
    -- History is checked per entry: each one carries its own roster/session
    -- and only those whose session is still active come back.
    PP.Repo.Loot:RestoreHistory()
    -- Don't restore stale loot if there is no active session
    if not PP.Repo.Roster:HasActiveSession() then
        PP.db.global.pendingLootCache = {}
        PP.db.global.pendingTradesCache = {}
        return
    end
    local cache = PP.db and PP.db.global.pendingLootCache
    if not cache then return end
    for key, saved in pairs(cache) do
        PP.pendingLoot[key] = {
            itemLink      = saved.itemLink,
            itemID        = saved.itemID,
            postedBy      = saved.postedBy,
            postedAt      = GetTime(),
            responses     = saved.responses or {},
            votes         = saved.votes or {},
            awarded       = false,
            awardedTo     = nil,
            allowTransmog = saved.allowTransmog ~= false,
        }
    end
    -- Restore pending trades only on a true reload (empty table = not a zone transition)
    local tradesCache = PP.db.global.pendingTradesCache
    if tradesCache and #PP.pendingTrades == 0 then
        for i, saved in ipairs(tradesCache) do
            PP.pendingTrades[i] = {
                itemLink  = saved.itemLink,
                itemID    = saved.itemID,
                awardedTo = saved.awardedTo,
            }
        end
    end
end

---------------------------------------------------------------------------
-- RestoreHistory() – reload loot history for sessions that are still active.
-- Skipped when memory already holds history (zone transition).
---------------------------------------------------------------------------
function PP.Repo.Loot:RestoreHistory()
    if not PP.db or PP._sandbox then return end
    if next(PP.lootHistory) ~= nil then return end
    local cache = PP.db.global.lootHistoryCache
    if not cache then return end
    for key, saved in pairs(cache) do
        local gd = PP.Repo.Roster:GetData(saved.guildKey)
        local session = gd and saved.sessionID and gd.activeSessionID == saved.sessionID
                        and gd.sessions[saved.sessionID]
        if session and session.active then
            PP.lootHistory[key] = saved
        end
    end
end
