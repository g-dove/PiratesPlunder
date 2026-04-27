---------------------------------------------------------------------------
-- Pirates Plunder – Guild Repository
-- All access to per-guild saved data goes through this table.
---------------------------------------------------------------------------
---@type PPAddon
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
    return PP.db.global.guilds[guildKey]  -- nil if not found; no auto-create
end

---------------------------------------------------------------------------
-- EnsureData(guildKey)
-- Like GetData but creates the guild entry if it does not exist yet.
-- Only call this when creation is intentional (session creation, sync receive).
---------------------------------------------------------------------------
function PP.Repo.Roster:EnsureData(guildKey)
    if PP._sandbox and guildKey == "__sandbox__" then
        return PP._sandboxData
    end
    if not guildKey then return nil end
    if not PP.db.global.guilds[guildKey] then
        PP.db.global.guilds[guildKey] = {
            roster                = {},
            rosterVersion         = 0,
            sessions              = {},
            activeSessionID       = nil,
            activeSessionVersion  = 0,
            deletedSessions       = {},
            sessionSnapshots      = {},
        }
    end
    -- Backfill for guild records created before sessionSnapshots existed
    if not PP.db.global.guilds[guildKey].sessionSnapshots then
        PP.db.global.guilds[guildKey].sessionSnapshots = {}
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
    if gd then
        gd.activeSessionID     = id
        gd.activeSessionVersion = (gd.activeSessionVersion or 0) + 1
    end
end

---------------------------------------------------------------------------
-- ClearActiveSessionID(gk)
---------------------------------------------------------------------------
function PP.Repo.Roster:ClearActiveSessionID(gk)
    local gd = self:GetData(gk)
    if gd then
        gd.activeSessionID      = nil
        gd.activeSessionVersion = (gd.activeSessionVersion or 0) + 1
    end
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
-- GetSessionSnapshot(gk, sessionID)
---------------------------------------------------------------------------
function PP.Repo.Roster:GetSessionSnapshot(gk, sessionID)
    local gd = self:GetData(gk)
    if not gd or not gd.sessionSnapshots then return nil end
    return gd.sessionSnapshots[sessionID]
end

---------------------------------------------------------------------------
-- SetSessionSnapshot(gk, sessionID, snapshot)
-- Apply only if incoming rosterVersion is newer than what we have.
-- Returns true when the snapshot was stored.
---------------------------------------------------------------------------
function PP.Repo.Roster:SetSessionSnapshot(gk, sessionID, snapshot)
    if not sessionID or not snapshot then return false end
    local gd = self:EnsureData(gk)
    if not gd then return false end
    local existing = gd.sessionSnapshots[sessionID]
    local existingVer = existing and existing.rosterVersion or -1
    local incomingVer = snapshot.rosterVersion or -1
    if incomingVer <= existingVer then return false end
    gd.sessionSnapshots[sessionID] = snapshot
    return true
end

---------------------------------------------------------------------------
-- BuildRosterSnapshot(gk)
-- Deep-copies the current roster into a snapshot record tagged with the
-- current roster version. Returns nil for unknown / sandbox guilds.
---------------------------------------------------------------------------
function PP.Repo.Roster:BuildRosterSnapshot(gk)
    local gd = self:GetData(gk)
    if not gd then return nil end
    local entries = {}
    for fullName, data in pairs(gd.roster or {}) do
        entries[fullName] = {
            name  = data.name,
            realm = data.realm,
            score = data.score,
        }
    end
    return {
        capturedAt    = time(),
        rosterVersion = gd.rosterVersion or 0,
        entries       = entries,
    }
end

---------------------------------------------------------------------------
-- GetAllSnapshotVersions(gk)
-- Returns { [sessionID] = rosterVersion } for every snapshot stored under gk,
-- including 0 for sessions that exist locally but lack a snapshot. Used to
-- build SNAPSHOT_REQUEST payloads.
---------------------------------------------------------------------------
function PP.Repo.Roster:GetAllSnapshotVersions(gk)
    local gd = self:GetData(gk)
    if not gd then return {} end
    local versions = {}
    for sessionID in pairs(gd.sessions or {}) do
        local snap = gd.sessionSnapshots and gd.sessionSnapshots[sessionID]
        versions[sessionID] = snap and snap.rosterVersion or 0
    end
    return versions
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
