---------------------------------------------------------------------------
-- Pirates Plunder - Loot Manager for World of Warcraft
-- Core initialization, DB schema, utilities, slash commands
---------------------------------------------------------------------------
local addonName, NS = ...

local PiratesPlunder = LibStub("AceAddon-3.0"):NewAddon("PiratesPlunder",
    "AceConsole-3.0", "AceHook-3.0", "AceComm-3.0",
    "AceSerializer-3.0", "AceEvent-3.0", "AceTimer-3.0")

NS.addon = PiratesPlunder
_G.PiratesPlunder = PiratesPlunder -- global for module files
---@type PPAddon
local PP = PiratesPlunder          -- local alias used throughout this file

-- Library references
PiratesPlunder.AceGUI = LibStub("AceGUI-3.0")

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
PiratesPlunder.COMM_PREFIX = "PPLNDR"
PiratesPlunder.VERSION     = C_AddOns.GetAddOnMetadata(addonName, "Version") or "Unable to find version info."

-- Comm message types
PiratesPlunder.MSG = {
    SYNC_REQUEST      = "SYN_REQ",
    SYNC_FULL         = "SYN_FULL",
    ROSTER_UPDATE     = "ROS_UPD",
    SESSION_CREATE    = "SES_CRE",
    SESSION_CLOSE     = "SES_CLS",
    SCORE_UPDATE      = "SCR_UPD",
    LOOT_POST         = "LOT_PST",
    LOOT_INTEREST     = "LOT_INT",
    LOOT_AWARD        = "LOT_AWD",
    LOOT_CANCEL       = "LOT_CAN",
    LOOT_UPDATE       = "LOT_UPD",
    RAID_SETTINGS     = "RAD_SET",
    SESSION_DELETE    = "SES_DEL",
    LOOT_VOTE         = "LOT_VOT",
    LOOT_STATE_QUERY  = "LOT_SQR",
    LOOT_STATE_REPLY  = "LOT_SRP",
    VERSION_REQUEST   = "VER_REQ",
    VERSION_REPLY     = "VER_REP",
}

-- Loot response types
PiratesPlunder.RESPONSE = {
    NEED    = "NEED",
    MINOR   = "MINOR",   -- minor upgrade: costs pts to drop to 1 below the next player down
    TRANSMOG = "TRANSMOG",
    PASS    = "PASS",
}

---------------------------------------------------------------------------
-- Saved-variable DB defaults
---------------------------------------------------------------------------
local defaults = {
    global = {
        -- Per-guild data: guilds[guildName] = { roster, rosterVersion, sessions, activeSessionID }
        guilds = {},
        -- Transient cache for pending loot across reloads
        pendingLootCache = {},
        -- Transient cache for pending trades across reloads
        pendingTradesCache = {},
        -- Fallback officer rank threshold (used if GuildControlGetRankFlags unavailable)
        officerRankThreshold = 1,
        -- Migration flag: set true once legacy flat data has been moved into guilds
        migrated_v2 = false,
        -- Global loot rule: whether Transmog is a valid roll option
        allowTransmogRolls = true,
        -- Auto-pass in-game loot rolls of Epic+ for non-leaders (synced by raid leader)
        autoPassEpicRolls = false,
    },
    profile = {},
}

---------------------------------------------------------------------------
-- Lifecycle callbacks
---------------------------------------------------------------------------
function PiratesPlunder:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("PiratesPlunderDB", defaults, true)

    -- One-time migration: move legacy flat roster/raids into per-guild structure
    if not self.db.global.migrated_v2 then
        local migrateKey = GetGuildInfo("player") or "__unguilded__"
        if self.db.global.roster and next(self.db.global.roster) ~= nil then
            local gd = PP.Repo.Roster:EnsureData(migrateKey)
            for k, v in pairs(self.db.global.roster) do gd.roster[k] = v end
            gd.rosterVersion = self.db.global.rosterVersion or 0
        end
        if self.db.global.raids and next(self.db.global.raids) ~= nil then
            local gd = PP.Repo.Roster:EnsureData(migrateKey)
            gd.sessions = gd.sessions or {}
            for id, raid in pairs(self.db.global.raids) do
                gd.sessions[id] = raid
                if raid.active then gd.activeSessionID = id end
            end
        end
        self.db.global.roster       = nil
        self.db.global.raids        = nil
        self.db.global.rosterVersion = nil
        self.db.global.activeRaidID = nil
        self.db.global.migrated_v2  = true
    end

    -- One-time migration: rename raids/activeRaidID/deletedRaids → sessions/activeSessionID/deletedSessions
    if not self.db.global.migrated_sessions then
        for _, gd in pairs(self.db.global.guilds or {}) do
            if gd.raids and not gd.sessions then
                gd.sessions = gd.raids
                gd.raids = nil
            end
            if gd.activeRaidID and not gd.activeSessionID then
                gd.activeSessionID = gd.activeRaidID
                gd.activeRaidID = nil
            end
            if gd.deletedRaids and not gd.deletedSessions then
                gd.deletedSessions = gd.deletedRaids
                gd.deletedRaids = nil
            end
        end
        self.db.global.migrated_sessions = true
    end

    -- One-time migration: rename __unguilded__ (the old "Default" roster) to __custom__:Default
    if self.db.global.guilds and self.db.global.guilds["__unguilded__"] then
        local ud     = self.db.global.guilds["__unguilded__"]
        local newKey = "__custom__:Default"
        if ud.roster and next(ud.roster) ~= nil then
            -- Preserve existing data only if the target key doesn't already exist
            if not self.db.global.guilds[newKey] then
                self.db.global.guilds[newKey] = ud
            end
        end
        self.db.global.guilds["__unguilded__"] = nil
    end

    -- Slash commands
    self:RegisterChatCommand("pp", "SlashCommand")
    self:RegisterChatCommand("piratesplunder", "SlashCommand")

    -- Comm
    self:RegisterComm(self.COMM_PREFIX)

    -- Runtime state (not persisted)
    self.pendingLoot      = {}  -- key => { itemLink, itemID, postedBy, responses={} }
    self.pendingTrades    = {}  -- { itemLink, itemID, awardedTo }
    self.lootQueue        = {}  -- { itemLink } items staged to post
    self.mainWindow       = nil
    self.lootMasterWindow = nil
    self.lootPopups       = {}  -- key => frame
    self.lootResponseFrame = nil -- unified multi-item response popup
    self.lootReopenBtn    = nil -- small reopen button shown when response frame is hidden
    self.awardedLootWindow = nil -- per-player awarded loot history window
    self._awardedLootTarget = nil -- fullName currently shown in the awarded loot window
    self._pendingDeleteRaidID = nil -- raidID pending delete confirmation
    self._pendingContinueRaidID = nil -- raidID awaiting new-leader continuation prompt
    self._isOfficer       = nil -- cached; nil = not yet determined
    self._wasInGroup      = IsInGroup() -- tracks group membership for auto-sync
    self._activeGuildKey  = nil -- set in OnEnable / OnPlayerEnteringWorld
    self._sandbox         = false -- sandbox mode: simulates raid leader, no DB writes
    self._sandboxData     = nil  -- in-memory guild data block used while sandbox active

    -- Command group dispatch table (populated by Commands/*.lua at file-load time)
    -- Do not wipe; handlers are already registered before OnInitialize fires.
    self._commandGroups = self._commandGroups or {}

    self:Print("Pirates Plunder v" .. self.VERSION .. " loaded. Type /pp to open.")
end

-- Returns the key of the first custom roster that has an active raid, or nil.
function PiratesPlunder:FindCustomRosterWithActiveRaid()
    for key, gd in pairs(self.db.global.guilds) do
        if self:IsCustomRoster(key) and gd.activeSessionID and gd.sessions and gd.sessions[gd.activeSessionID] then
            if gd.sessions[gd.activeSessionID].active == true then
                return key
            end
        end
    end
    return nil
end

function PiratesPlunder:OnEnable()
    self:RegisterEvent("GROUP_ROSTER_UPDATE",  "OnGroupRosterUpdate")
    self:RegisterEvent("ENCOUNTER_END",        "OnEncounterEnd")
    self:RegisterEvent("TRADE_SHOW",           "OnTradeShow")
    self:RegisterEvent("TRADE_CLOSED",         "OnTradeClosed")
    self:RegisterEvent("GROUP_LEFT",           "OnGroupLeft")
    self:RegisterEvent("GUILD_ROSTER_UPDATE",  "OnGuildRosterUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD","OnPlayerEnteringWorld")
    self:RegisterEvent("START_LOOT_ROLL",       "OnStartLootRoll")

    if IsInGuild() then
        C_GuildInfo.GuildRoster()  -- async; result arrives via GUILD_ROSTER_UPDATE
    end

    -- Set initial active guild key.
    -- Priority: own guild roster > custom roster with an active raid > first available.
    local _initGuild = self:GetPlayerGuild()
    if _initGuild and self.db.global.guilds[_initGuild] then
        self._activeGuildKey = _initGuild
    else
        self._activeGuildKey = self:FindCustomRosterWithActiveRaid()
            or next(self.db.global.guilds)
            or nil
    end

    -- Hook alt+right-click on items to auto-post to loot window
    self:InstallAltRightClickHook()
end

---------------------------------------------------------------------------
-- Slash handlers
---------------------------------------------------------------------------
function PiratesPlunder:SlashCommand(input)
    input = input and input:trim() or ""
    if input == "" then self:ToggleMainWindow(); return end
    for _, handler in ipairs(self._commandGroups) do
        if handler(input) then return end
    end
    self:Print("Unknown command. Type /pp help for usage.")
end

function PiratesPlunder:SlashCommandLoot()
    if self:CanPostLoot() then
        self:ToggleLootMasterWindow()
    else
        self:Print("You must be raid leader/assistant with an active session to use /pp loot.")
    end
end

function PiratesPlunder:SlashCommandResponse()
    local frameVisible  = self.lootResponseFrame and self.lootResponseFrame:IsShown()
    local buttonVisible = self.lootReopenBtn and self.lootReopenBtn:IsShown()
    if frameVisible or buttonVisible then
        -- Dismiss both (clear/dismiss path)
        if self.lootResponseFrame then self.lootResponseFrame:Hide() end
        self:HideLootReopenButton()
    else
        -- Reopen path
        self:ShowLootResponseFrame()
    end
end

---------------------------------------------------------------------------
-- Utility helpers
---------------------------------------------------------------------------
function PiratesPlunder:GetFullName(name)
    if not name then return nil end
    if not string.find(name, "-", 1, true) then
        local _, realm = UnitFullName("player")
        realm = realm or GetRealmName():gsub("%s+", "")
        name = name .. "-" .. realm
    end
    return name
end

function PiratesPlunder:GetShortName(fullName)
    if not fullName then return "" end
    return fullName:match("^(.+)-") or fullName
end

function PiratesPlunder:GetPlayerFullName()
    local name, realm = UnitFullName("player")
    realm = realm or GetRealmName():gsub("%s+", "")
    return name .. "-" .. realm
end

---------------------------------------------------------------------------
-- Guild helpers
---------------------------------------------------------------------------
function PiratesPlunder:GetPlayerGuild()
    if not IsInGuild() then return nil end
    return GetGuildInfo("player") or nil
end

function PiratesPlunder:GetRaidLeaderGuild()
    if not IsInRaid() then return nil end
    for i = 1, GetNumGroupMembers() do
        local unit = "raid" .. i
        if UnitIsGroupLeader(unit) then
            return GetGuildInfo(unit)
        end
    end
    return nil
end

-- Returns the guild key currently in use for roster/raid operations.
-- Priority: manually selected (_activeGuildKey) > player's own guild > fallback
function PiratesPlunder:GetActiveGuildKey()
    if self._sandbox then return "__sandbox__" end
    return self._activeGuildKey or self:GetPlayerGuild() or nil
end

---------------------------------------------------------------------------
-- Roster display-name helpers
---------------------------------------------------------------------------

-- Human-readable label for a roster key shown in the UI.
function PiratesPlunder:GetRosterDisplayName(key)
    if key == "__sandbox__" then return "Sandbox" end
    local custom = key and key:match("^__custom__:(.+)$")
    if custom then return custom end
    return key or "Unknown"
end

-- True for custom (non-guild) rosters: only __custom__:* keys.
function PiratesPlunder:IsCustomRoster(key)
    return key ~= nil and key:match("^__custom__:") ~= nil
end

-- Creates a new custom roster with the given display name and activates it.
function PiratesPlunder:CreateCustomRoster(name)
    local trimmed = name and name:trim() or ""
    if trimmed == "" then return end
    local key = "__custom__:" .. trimmed
    PP.Repo.Roster:EnsureData(key)  -- creates db entry if missing
    self._activeGuildKey = key
    self:RefreshMainWindow()
end

-- Renames a custom roster: copies data to new key, removes old key.
function PiratesPlunder:RenameCustomRoster(oldKey, newName)
    local trimmed = newName and newName:trim() or ""
    if trimmed == "" then return end
    local newKey = "__custom__:" .. trimmed
    if newKey == oldKey then return end
    local data = self.db.global.guilds[oldKey]
    if not data then return end
    self.db.global.guilds[newKey] = data
    self.db.global.guilds[oldKey] = nil
    if self._activeGuildKey == oldKey then
        self._activeGuildKey = newKey
    end
    self:RefreshMainWindow()
end

-- Deletes a guild roster locally only (does NOT sync to other players).
function PiratesPlunder:DeleteGuildRoster(key)
    if not key or self:IsCustomRoster(key) or key == "__sandbox__" then return end
    self.db.global.guilds[key] = nil
    if self._activeGuildKey == key then
        local guild = self:GetPlayerGuild()
        if guild and guild ~= key and self.db.global.guilds[guild] then
            self._activeGuildKey = guild
        else
            self._activeGuildKey = next(self.db.global.guilds) or nil
        end
    end
    self:RefreshMainWindow()
end

-- Deletes a custom roster and all its saved data.
function PiratesPlunder:DeleteCustomRoster(key)
    if not self:IsCustomRoster(key) then return end
    self.db.global.guilds[key] = nil
    -- If the deleted roster was active, switch to guild roster or first available
    if self._activeGuildKey == key then
        local guild = self:GetPlayerGuild()
        if guild and self.db.global.guilds[guild] then
            self._activeGuildKey = guild
        else
            self._activeGuildKey = next(self.db.global.guilds) or nil
        end
    end
    self:RefreshMainWindow()
end

---------------------------------------------------------------------------
-- Sandbox mode helpers
---------------------------------------------------------------------------
function PiratesPlunder:IsSandbox()
    return self._sandbox == true
end

function PiratesPlunder:EnableSandbox()
    if self._sandbox then return end
    self._sandbox = true
    self._sandboxModOverride = true  -- default: act as officer in sandbox
    -- Build a fresh in-memory guild data block with a pre-created active session
    self._sandboxData = {
        roster          = {},
        rosterVersion   = 0,
        sessions        = {},
        activeSessionID = "sandbox_raid",
    }
    self._sandboxData.sessions["sandbox_raid"] = {
        id             = "sandbox_raid",
        name           = "[Sandbox] Test Raid",
        startedAt      = GetTime(),
        active         = true,
        items          = {},  -- required by RecordItemAward
        bosses         = {},  -- required by ShowRaidDetail / AddBossToRaid
        bossKills      = {},
        lootAwarded    = {},
        guildKey       = "__sandbox__",
        memberSnapshot = {},
    }
    -- Populate a fake roster of 10 players including the local player
    local realm = GetRealmName():gsub("%s+", "") or "TestRealm"
    local myName = UnitName("player") or "Player"
    local fakeNames = { myName, "Aragorn", "Legolas", "Gimli", "Gandalf",
                        "Boromir", "Frodo", "Samwise", "Pippin", "Merry" }
    local roster = self._sandboxData.roster
    for i, name in ipairs(fakeNames) do
        local fullName = name .. "-" .. realm
        roster[fullName] = {
            name      = name,
            realm     = realm,
            fullName  = fullName,
            score     = math.floor((11 - i) * 10 + math.random(0, 9)),
            joinedAt  = GetTime(),
        }
    end
    self:Print("|cFFFFD100[Sandbox] Enabled. Simulating raid leader in an active raid. Nothing will be saved to disk.|r")
    self:Print("|cFFFFD100[Sandbox] /pp sandbox mod toggles CanModify override (currently ON).|r")
    self:RefreshMainWindow()
end

function PiratesPlunder:DisableSandbox()
    if not self._sandbox then return end
    self._sandbox     = false
    self._sandboxData = nil
    self._sandboxModOverride = nil
    -- Discard any loot state accumulated during the sandbox session.
    -- Wipe runtime tables directly (no Save()) so the pre-sandbox
    -- pendingLootCache in the DB is not overwritten.
    wipe(self.pendingLoot)
    wipe(self.pendingTrades)
    wipe(self.lootQueue)
    if self.lootMasterWindow then self:RefreshLootMasterWindow() end
    self:RefreshLootResponseFrame()
    self:RefreshMainWindow()
    self:Print("|cFF888888[Sandbox] Disabled.|r")
end

-- 1st: C_GuildInfo.IsGuildOfficer() – canonical Blizzard API.
-- 2nd: CanUseGuildOfficerChat() – older API fallback.
-- 3rd: GuildControlGetRankFlags flag 13 (Speak in Officer Chat).
-- 4th: rank index <= officerRankThreshold fallback.
function PiratesPlunder:RefreshOfficerStatus()
    self._isOfficer = false

    if not IsInGuild() then return end

    -- Most direct check: canonical officer API
    if C_GuildInfo.IsGuildOfficer then
        self._isOfficer = C_GuildInfo.IsGuildOfficer() == true
        return
    end

    -- Older direct check
    if CanUseGuildOfficerChat and CanUseGuildOfficerChat() then
        self._isOfficer = true
        return
    end

    local n = GetNumGuildMembers and GetNumGuildMembers() or 0
    if n == 0 then
        C_GuildInfo.GuildRoster()
        self._isOfficer = nil
        return
    end

    local playerName = UnitName("player")
    for i = 1, n do
        local rName, _, rankIndex = GetGuildRosterInfo(i)
        if rName and (rName == playerName or rName:match("^" .. playerName .. "-")) then
            if GuildControlGetRankFlags then
                local canSpeakOfficer = select(13, GuildControlGetRankFlags(rankIndex + 1))
                self._isOfficer = canSpeakOfficer and true or false
            else
                local threshold = self.db and self.db.global.officerRankThreshold or 1
                self._isOfficer = rankIndex <= threshold
            end
            return
        end
    end
end

-- Officer+ guild rank check (uses cached value; refreshed by GUILD_ROSTER_UPDATE)
function PiratesPlunder:IsOfficerOrHigher()
    if self._sandbox then return true end
    if self._isOfficer == nil then
        self:RefreshOfficerStatus()
    end
    return self._isOfficer == true
end

-- Returns the current player's raid rank (2=leader, 1=assist, 0=member), or -1 if not in raid.
function PiratesPlunder:GetMyRaidRank()
    if not IsInRaid() then return -1 end
    local me = self:GetPlayerFullName()
    for i = 1, GetNumGroupMembers() do
        local name, rank = GetRaidRosterInfo(i)
        if name and self:GetFullName(name) == me then
            return rank
        end
    end
    return -1
end

function PiratesPlunder:IsRaidLeaderOrAssist()
    if self._sandbox then return true end
    return self:GetMyRaidRank() >= 1
end

function PiratesPlunder:IsRaidLeader()
    if self._sandbox then return true end
    return self:GetMyRaidRank() == 2
end

function PiratesPlunder:CanModify()
    if self._sandbox then return self._sandboxModOverride ~= false end
    local activeKey = self:GetActiveGuildKey()
    if not activeKey then return false end
    -- Custom rosters: only the raid leader may modify
    if self:IsCustomRoster(activeKey) then
        return self:IsRaidLeader()
    end
    -- Guild rosters: officer only (raid leader/assist can post loot but not modify roster/scores)
    if not self:IsOfficerOrHigher() then
        return false
    end
    local myGuild = self:GetPlayerGuild()
    return myGuild ~= nil and myGuild == activeKey
end

-- Whether the current player may open the loot master window (post OR observe).
-- Officers of the active guild and the raid leader/assist qualify.
function PiratesPlunder:CanViewLootMaster()
    if self._sandbox then return self._sandboxModOverride ~= false end
    if not PP.Repo.Roster:HasActiveSession() then return false end
    return self:CanPostLoot() or self:IsOfficerOrHigher()
end

-- Whether the current player may post loot for rolling.
-- Custom rosters: raid leader only.
-- Guild rosters: officer or raid-leader/assist.
function PiratesPlunder:CanPostLoot()
    if self._sandbox then return self._sandboxModOverride ~= false end
    if not PP.Repo.Roster:HasActiveSession() then return false end
    local activeKey = self:GetActiveGuildKey()
    if activeKey and self:IsCustomRoster(activeKey) then
        return self:IsRaidLeader()
    end
    return self:CanModify() or self:IsRaidLeaderOrAssist()
end

function PiratesPlunder:CheckActiveRaid()
    if PP.Repo.Roster:HasActiveSession() and not IsInGroup() then
        PP.Session:End(PP.SESSION_END.STARTUP_CHECK)
    end
    -- Clear stale pending loot when there is no active session
    if not PP.Repo.Roster:HasActiveSession() and next(PP.Repo.Loot:GetAll()) ~= nil then
        PP.Repo.Loot:WipeAll()
        self:RefreshLootResponseFrame()
        self:RefreshLootMasterWindow()
    end
end

-- Register a WoW frame so it can be dismissed with the ESC key.
function PiratesPlunder:RegisterEscFrame(frame, frameName)
    _G[frameName] = frame.frame
    tinsert(UISpecialFrames, frameName)
end

-- Generate a unique key from an item link + timestamp + monotonic index.
-- The index ensures two identical items posted in the same frame (same
-- GetTime() value) always produce distinct keys.
local _lootKeyIndex = 0
function PiratesPlunder:LootKey(itemLink)
    _lootKeyIndex = _lootKeyIndex + 1
    return tostring(itemLink) .. ":" .. tostring(GetTime()) .. ":" .. _lootKeyIndex
end

---------------------------------------------------------------------------
-- Alt + Right-click hook to auto-post items
---------------------------------------------------------------------------
function PiratesPlunder:InstallAltRightClickHook()
    -- Detect Alt + Right-click via OnUpdate (edge-triggered: fires once per press).
    -- We read GameTooltip:GetItem() at the instant the button goes down — the
    -- tooltip is still visible at that point, so the link is always available.
    local prevRightDown = false
    local detector = CreateFrame("Frame")
    detector:SetScript("OnUpdate", function()
        local rightDown = IsMouseButtonDown("RightButton")
        if rightDown and not prevRightDown then
            if IsAltKeyDown() and GameTooltip:IsShown() then
                local _, link = GameTooltip:GetItem()
                if link then
                    PiratesPlunder:AltRightClickPost(link)
                end
            end
        end
        prevRightDown = rightDown
    end)
end

function PiratesPlunder:AltRightClickPost(itemLink)
    if not PP.Repo.Roster:HasActiveSession() then
        self:Print("No active session – cannot post loot.")
        return
    end
    if not self:CanPostLoot() then
        self:Print("Only the raid leader can post loot for this roster.")
        return
    end
    -- Queue the item and open/refresh the loot master window
    self:AddToLootQueue(itemLink)
end

---------------------------------------------------------------------------
-- Event stubs (implementations in module files)
---------------------------------------------------------------------------
function PiratesPlunder:OnGroupRosterUpdate()
    local nowInGroup = IsInGroup()
    -- Auto-request sync when first joining a group
    if nowInGroup and not self._wasInGroup then
        self:ScheduleTimer(function()
            self:RequestSync()
        end, 3) -- delay lets the comms channel open and officers load in
    end
    self._wasInGroup = nowInGroup

    -- If a deferred session-end is pending and we are still in a group, cancel it
    if self.db.global.pendingSessionEnd and nowInGroup then
        self.db.global.pendingSessionEnd = nil
        if self._pendingSessionEndTimer then
            self:CancelTimer(self._pendingSessionEndTimer)
            self._pendingSessionEndTimer = nil
        end
    end

    -- When in a raid, prefer the raid leader's guild as the active key — but
    -- only if we already have data for it.  If not, fall back to our own guild
    -- so we don't start operating on a fresh empty record for an unknown guild.
    -- HandleSessionCreate will set the key correctly once a session is broadcast.
    if IsInRaid() then
        local leaderGuild = self:GetRaidLeaderGuild()
        if leaderGuild and self.db.global.guilds[leaderGuild] then
            self._activeGuildKey = leaderGuild
        else
            self._activeGuildKey = self:GetPlayerGuild() or nil
        end
    end

    if PP.Repo.Roster:HasActiveSession() and IsInRaid() then
        PP.Roster:AutoPopulate()
        PP.Session:CheckLeaderPresent()
        -- Push the leader's autoPassEpicRolls setting to anyone who just joined
        if self:IsRaidLeader() then
            self:BroadcastRaidSettings()
        end
    end
    self:RefreshMainWindow()
end

function PiratesPlunder:OnEncounterEnd(_, encounterID, encounterName, difficultyID, groupSize, success)
    if success == 1 and PP.Repo.Roster:HasActiveSession() and IsInRaid() then
        self:OnBossKill(encounterID, encounterName)
    end
end

function PiratesPlunder:OnGroupLeft()
    if PP.Repo.Roster:HasActiveSession() then
        -- GROUP_LEFT fires when the server removes the player from the group,
        -- which happens on disconnect. Defer the session end to give the player
        -- time to reconnect; OnGroupRosterUpdate or OnPlayerEnteringWorld will
        -- cancel the deferred end if they rejoin within the window.
        if IsInRaid() then
            local _, id = PP.Repo.Roster:GetActiveSession()
            local activeGuildKey = self:GetActiveGuildKey()
            self.db.global.pendingSessionEnd = { sessionID = id, guildKey = activeGuildKey }
            self._pendingSessionEndTimer = self:ScheduleTimer(function()
                -- Timer fired: if still not in a group, complete the session end
                if not IsInGroup() then
                    self:CompletePendingSessionEnd()
                else
                    -- Rejoined but timer still fired somehow; cancel cleanly
                    self.db.global.pendingSessionEnd = nil
                    self._pendingSessionEndTimer = nil
                end
            end, 30)
            -- Do NOT wipe pendingLoot or clear activeSessionID yet
            return
        end

        -- Party group (no zone-transition ambiguity): end immediately
        self:CompletePendingSessionEnd()
    end
    -- Reset active guild to own guild when leaving the group (nil if not guilded)
    self._activeGuildKey = self:GetPlayerGuild() or nil
end

-- Extracted teardown: delegates to PP.Session:End with LEFT_GROUP reason.
-- Called by timer callback, OnPlayerEnteringWorld (not in group), OnGroupLeft (party case).
function PiratesPlunder:CompletePendingSessionEnd()
    -- Cancel any running timer
    if self._pendingSessionEndTimer then
        self:CancelTimer(self._pendingSessionEndTimer)
        self._pendingSessionEndTimer = nil
    end
    self.db.global.pendingSessionEnd = nil

    if PP.Repo.Roster:HasActiveSession() then
        PP.Session:End(PP.SESSION_END.LEFT_GROUP)
        -- If we are somehow still in a group (e.g. disconnect timer fired just
        -- before reconnect), request a sync immediately so HandleSyncFull can
        -- reactivate the session before the player notices.
        if IsInGroup() then
            self:ScheduleTimer(function() self:RequestSync() end, 1)
        end
    end
    -- Reset active guild to own guild
    self._activeGuildKey = self:GetPlayerGuild() or nil
end

-- Show the response popup only if there are unresponded items.
function PiratesPlunder:ShowLootResponseFrameIfNeeded()
    local me = self:GetPlayerFullName()
    for _, entry in pairs(PP.Repo.Loot:GetAll()) do
        if not entry.responses[me] then
            self:ShowLootResponseFrame()
            return
        end
    end
end

function PiratesPlunder:OnGuildRosterUpdate()
    self:RefreshOfficerStatus()
    self:RefreshMainWindow()
    -- If a sync was deferred waiting for guild data to load, fire it now
    if self._pendingSyncOnGuildLoad and IsInGroup() then
        self._pendingSyncOnGuildLoad = false
        self:ScheduleTimer(function() self:RequestSync() end, 1)
    end
end

-- Auto-pass in-game loot rolls of Epic+ quality for non-leaders
function PiratesPlunder:OnStartLootRoll(_, rollID)
    if not self.db.global.autoPassEpicRolls then return end
    -- Only auto-pass when there is an active addon-managed session
    if not PP.Repo.Roster:HasActiveSession() then return end
    -- Leaders and officers roll normally
    if self:IsRaidLeader() then return end
    local _, name, _, quality = GetLootRollItemInfo(rollID)
    if quality and quality >= 4 then  -- 4 = Epic, 5 = Legendary, …
        RollOnLoot(rollID, 0)  -- 0 = Pass
        self:Print("|cFFFF4400Auto-passed|r " .. (name or "item") .. " (epic+ auto-pass)")
    end
end

---------------------------------------------------------------------------
-- Reset
---------------------------------------------------------------------------
function PiratesPlunder:ResetAddon()
    -- Wipe all per-guild saved data for this machine
    wipe(self.db.global.guilds)
    self.db.global.pendingLootCache = {}
    self.db.global.pendingTradesCache = {}
    self.db.global.pendingSessionEnd = nil
    self.db.global.migrated_v2 = true       -- don't re-run migration on empty data
    self.db.global.migrated_sessions = true -- ditto
    -- Clear runtime state (skip Save() since DB was already wiped above)
    wipe(self.pendingLoot)
    wipe(self.pendingTrades)
    PP:CloseLootPopups()
    if self._pendingSessionEndTimer then
        self:CancelTimer(self._pendingSessionEndTimer)
        self._pendingSessionEndTimer = nil
    end
    self._activeGuildKey = self:GetPlayerGuild() or nil
    self._isOfficer = nil
    -- Close any open windows
    if self.mainWindow then
        self.mainWindow:Release()
        self.mainWindow = nil
    end
    if self.lootMasterWindow then
        self.lootMasterWindow:Release()
        self.lootMasterWindow = nil
    end
    self:CloseLootPopups()
    self:Print("|cFFFF4400Addon data reset.|r Reload the UI to start fresh, or re-open /pp.")
end

function PiratesPlunder:OnPlayerEnteringWorld(_, isInitialLogin, isReloadingUi)
    -- Ensure active guild key is set after world load.
    -- Priority: own guild > custom roster with active session > first available.
    if not self._activeGuildKey then
        local myGuild = self:GetPlayerGuild()
        self._activeGuildKey = (myGuild and self.db.global.guilds[myGuild] and myGuild)
            or self:FindCustomRosterWithActiveRaid()
            or next(self.db.global.guilds)
            or nil
    end

    -- Handle deferred session end from GROUP_LEFT during a zone transition
    if self.db.global.pendingSessionEnd then
        if IsInGroup() then
            -- Still in the group after zone transition – cancel the deferred end
            self.db.global.pendingSessionEnd = nil
            if self._pendingSessionEndTimer then
                self:CancelTimer(self._pendingSessionEndTimer)
                self._pendingSessionEndTimer = nil
            end
            -- Sync loot state to resolve any items awarded during loading screen
            self:ScheduleTimer(function() PP.Loot:Restore() end, 3)
        else
            -- Not in a group any more – complete the session end now
            self:CompletePendingSessionEnd()
        end
    end

    -- On login/reload: request guild roster first; sync will fire from
    -- OnGuildRosterUpdate once the guild data is actually populated.
    if isInitialLogin or isReloadingUi then
        if IsInGuild() then
            self._pendingSyncOnGuildLoad = true
            C_GuildInfo.GuildRoster()  -- async; triggers GUILD_ROSTER_UPDATE
        elseif IsInGroup() then
            -- Not guilded but in a group – sync immediately
            self:ScheduleTimer(function() self:RequestSync() end, 5)
        end
        -- Restore cached loot, verify against loot master, then check for stale
        -- session state now that group membership is accurate.
        self:ScheduleTimer(function()
            PP.Loot:Restore()
            self:CheckActiveRaid()
        end, 4)
    elseif not self.db.global.pendingSessionEnd then
        -- Ordinary zone transition: re-verify pending loot in case AWARD/CANCEL
        -- was missed during the loading screen. Restore() skips the DB read when
        -- pendingLoot is non-empty and is a no-op when there is nothing pending.
        self:ScheduleTimer(function() PP.Loot:Restore() end, 3)
    end
end
