---------------------------------------------------------------------------
-- Pirates Plunder – Guild Repository
-- All access to per-guild saved data goes through this table.
---------------------------------------------------------------------------
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

PP.Repo        = PP.Repo or {}
PP.Repo.Roster  = PP.Repo.Roster or {}

---------------------------------------------------------------------------
-- GetData(guildKey)
-- THE canonical accessor for per-guild data.  Sandbox routing lives here.
---------------------------------------------------------------------------
function PP.Repo.Roster:GetData(guildKey)
    -- Sandbox: route the sandbox key to the transient in-memory table
    if PP._sandbox and guildKey == "__sandbox__" then
        return PP._sandboxData
    end
    if not guildKey then return nil end
    if not PP.db.global.guilds[guildKey] then
        PP.db.global.guilds[guildKey] = {
            roster          = {},
            rosterVersion   = 0,
            sessions        = {},
            activeSessionID = nil,
            deletedSessions = {},  -- [sessionID] = rosterVersion; tombstones
        }
    end
    return PP.db.global.guilds[guildKey]
end

---------------------------------------------------------------------------
-- GetRoster(guildKey)
---------------------------------------------------------------------------
function PP.Repo.Roster:GetRoster(guildKey)
    local gd = self:GetData(guildKey or PP:GetActiveGuildKey())
    return gd and gd.roster or {}
end

---------------------------------------------------------------------------
-- GetSessions(guildKey)
---------------------------------------------------------------------------
function PP.Repo.Roster:GetSessions(guildKey)
    local gd = self:GetData(guildKey or PP:GetActiveGuildKey())
    return gd and gd.sessions or {}
end

---------------------------------------------------------------------------
-- GetActiveSession()
---------------------------------------------------------------------------
function PP.Repo.Roster:GetActiveSession()
    local gd = self:GetData(PP:GetActiveGuildKey())
    if not gd then return nil, nil end
    local id = gd.activeSessionID
    if id then return gd.sessions[id], id end
    return nil, nil
end

---------------------------------------------------------------------------
-- HasActiveSession()
---------------------------------------------------------------------------
function PP.Repo.Roster:HasActiveSession()
    local gd = self:GetData(PP:GetActiveGuildKey())
    if not gd then return false end
    local id = gd.activeSessionID
    if id and gd.sessions[id] then
        return gd.sessions[id].active == true
    end
    return false
end

---------------------------------------------------------------------------
-- GetAllGuildKeys()
-- Returns an array of all keys in PP.db.global.guilds.
---------------------------------------------------------------------------
function PP.Repo.Roster:GetAllGuildKeys()
    local keys = {}
    for gk in pairs(PP.db.global.guilds) do
        keys[#keys + 1] = gk
    end
    return keys
end

---------------------------------------------------------------------------
-- SetActiveSessionID(gk, id)
---------------------------------------------------------------------------
function PP.Repo.Roster:SetActiveSessionID(gk, id)
    local gd = self:GetData(gk)
    if gd then gd.activeSessionID = id end
end

---------------------------------------------------------------------------
-- ClearActiveSessionID(gk)
---------------------------------------------------------------------------
function PP.Repo.Roster:ClearActiveSessionID(gk)
    local gd = self:GetData(gk)
    if gd then gd.activeSessionID = nil end
end

---------------------------------------------------------------------------
-- MarkSessionEnded(gk, sessionID, ts, reason)
---------------------------------------------------------------------------
function PP.Repo.Roster:MarkSessionEnded(gk, sessionID, ts, reason)
    local gd = self:GetData(gk)
    if not gd then return end
    if sessionID and gd.sessions and gd.sessions[sessionID] then
        gd.sessions[sessionID].active    = false
        gd.sessions[sessionID].endTime   = gd.sessions[sessionID].endTime or ts
        gd.sessions[sessionID].endReason = reason
    end
end

---------------------------------------------------------------------------
-- AddTombstone(gk, id, ver)
---------------------------------------------------------------------------
function PP.Repo.Roster:AddTombstone(gk, id, ver)
    local gd = self:GetData(gk)
    if not gd then return end
    if not gd.deletedSessions then gd.deletedSessions = {} end
    gd.deletedSessions[id] = ver
end

---------------------------------------------------------------------------
-- BumpRosterVersion(guildKey)
---------------------------------------------------------------------------
function PP.Repo.Roster:BumpRosterVersion(guildKey)
    local gd = self:GetData(guildKey or PP:GetActiveGuildKey())
    if gd then gd.rosterVersion = gd.rosterVersion + 1 end
end

---------------------------------------------------------------------------
-- GetRosterVersion(gk)
---------------------------------------------------------------------------
function PP.Repo.Roster:GetRosterVersion(gk)
    local gd = self:GetData(gk)
    return gd and gd.rosterVersion or 0
end
