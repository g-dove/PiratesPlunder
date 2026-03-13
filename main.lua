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

-- Library references
PiratesPlunder.AceGUI = LibStub("AceGUI-3.0")

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
PiratesPlunder.COMM_PREFIX = "PPLNDR"
PiratesPlunder.VERSION     = "0.1.0"

-- Comm message types
PiratesPlunder.MSG = {
    SYNC_REQUEST   = "SYN_REQ",
    SYNC_FULL      = "SYN_FULL",
    ROSTER_UPDATE  = "ROS_UPD",
    RAID_CREATE    = "RAD_CRE",
    RAID_CLOSE     = "RAD_CLS",
    SCORE_UPDATE   = "SCR_UPD",
    LOOT_POST      = "LOT_PST",
    LOOT_INTEREST  = "LOT_INT",
    LOOT_AWARD     = "LOT_AWD",
    LOOT_CANCEL    = "LOT_CAN",
    LOOT_UPDATE    = "LOT_UPD",
    RAID_SETTINGS  = "RAD_SET",
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
        -- Per-guild data: guilds[guildName] = { roster, rosterVersion, raids, activeRaidID }
        guilds = {},
        -- Transient cache for pending loot across reloads
        pendingLootCache = {},
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
            local gd = self:GetGuildData(migrateKey)
            for k, v in pairs(self.db.global.roster) do gd.roster[k] = v end
            gd.rosterVersion = self.db.global.rosterVersion or 0
        end
        if self.db.global.raids and next(self.db.global.raids) ~= nil then
            local gd = self:GetGuildData(migrateKey)
            for id, raid in pairs(self.db.global.raids) do
                gd.raids[id] = raid
                if raid.active then gd.activeRaidID = id end
            end
        end
        self.db.global.roster       = nil
        self.db.global.raids        = nil
        self.db.global.rosterVersion = nil
        self.db.global.activeRaidID = nil
        self.db.global.migrated_v2  = true
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
    self._isOfficer       = nil -- cached; nil = not yet determined
    self._wasInGroup      = IsInGroup() -- tracks group membership for auto-sync
    self._activeGuildKey  = nil -- set in OnEnable / OnPlayerEnteringWorld
    self._sandbox         = false -- sandbox mode: simulates raid leader, no DB writes
    self._sandboxData     = nil  -- in-memory guild data block used while sandbox active

    self:Print("Pirates Plunder v" .. self.VERSION .. " loaded. Type /pp to open.")
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

    -- Always ensure the default (unguilded) roster exists in the database
    self:GetGuildData("__unguilded__")
    -- Set initial active guild key: prefer own guild if its roster already exists, else Default
    local _initGuild = self:GetPlayerGuild()
    if _initGuild and self.db.global.guilds[_initGuild] then
        self._activeGuildKey = _initGuild
    else
        self._activeGuildKey = "__unguilded__"
    end

    self:CheckActiveRaid()

    -- Restore pending loot saved across reloads
    self:RestorePendingLoot()

    -- Hook alt+right-click on items to auto-post to loot window
    self:InstallAltRightClickHook()
end

---------------------------------------------------------------------------
-- Slash handlers
---------------------------------------------------------------------------
function PiratesPlunder:SlashCommand(input)
    input = input and input:trim() or ""
    if input == "" then
        self:ToggleMainWindow()
    elseif input == "help" then
        self:Print("/pp – Toggle main window")
        self:Print("/pp loot (or /pp l) – Toggle loot-master window")
        self:Print("/pp sandbox (or /pp s) – Toggle sandbox mode")
        self:Print("/pp sandbox mod (or /pp s m) – Toggle canModify override in sandbox")
        self:Print("/pp status – Show officer detection info")
        self:Print("/pp bagdebug – Diagnose alt+right-click bag hook")
    elseif input == "loot" or input == "l" then
        self:SlashCommandLoot()
    elseif input == "sandbox" or input == "s" then
        if self:IsSandbox() then
            self:DisableSandbox()
        else
            self:EnableSandbox()
        end
    elseif input == "sandbox mod" or input == "s m" then
        if not self:IsSandbox() then
            self:Print("Sandbox is not active. Run /pp sandbox first.")
        else
            self._sandboxModOverride = not self._sandboxModOverride
            if self._sandboxModOverride then
                self:Print("|cFFFFD100[Sandbox] CanModify override: ON — acting as officer.|r")
            else
                self:Print("|cFF888888[Sandbox] CanModify override: OFF — acting as non-officer.|r")
            end
            self:RefreshMainWindow()
        end
    elseif input:match("^setrank%s+(%d+)$") then
        local n = tonumber(input:match("^setrank%s+(%d+)$"))
        self.db.global.officerRankThreshold = n
        self._isOfficer = nil  -- force re-detect
        self:RefreshOfficerStatus()
        self:Print("Officer rank threshold set to " .. n .. ". Status: " .. (self._isOfficer and "|cFF00FF00Officer|r" or "|cFFFF4400Not officer|r"))
        self:RefreshMainWindow()
    elseif input == "bagdebug" then
        self:Print("GameTooltip shown: " .. tostring(GameTooltip:IsShown()))
        local _, tipLink = GameTooltip:GetItem()
        self:Print("Tooltip item link: " .. tostring(tipLink))
        self:Print("IsMouseButtonDown RightButton: " .. tostring(IsMouseButtonDown("RightButton")))
    elseif input == "status" then
        self._isOfficer = nil  -- force re-detect
        self:RefreshOfficerStatus()
        local inGuild   = IsInGuild() and "yes" or "no"
        local myGuild   = self:GetPlayerGuild() or "none"
        local activeKey = self:GetActiveGuildKey()
        local officer   = self._isOfficer and "|cFF00FF00yes|r" or "|cFFFF4400no|r"
        local canMod    = self:CanModify()   and "|cFF00FF00yes|r" or "|cFFFF4400no|r"
        local apiUsed
        if C_GuildInfo.IsGuildOfficer then
            apiUsed = "C_GuildInfo.IsGuildOfficer()"
        elseif CanUseGuildOfficerChat then
            apiUsed = "CanUseGuildOfficerChat()"
        elseif GuildControlGetRankFlags then
            apiUsed = "GuildControlGetRankFlags (flag 13)"
        else
            apiUsed = "rank index threshold (" .. (self.db.global.officerRankThreshold or 1) .. ")"
        end
        self:Print("Guild: " .. inGuild .. " (" .. myGuild .. ")  Active roster: " .. activeKey)
        self:Print("Officer: " .. officer .. "  Can modify: " .. canMod .. "  API: " .. apiUsed)
    else
        self:Print("Unknown command. Type /pp help for usage.")
    end
end

function PiratesPlunder:SlashCommandLoot()
    if self:HasActiveRaid() and (self:IsRaidLeaderOrAssist() or self:CanModify()) then
        self:ToggleLootMasterWindow()
    else
        self:Print("You must be raid leader/assistant with an active raid to use /pploot.")
    end
end

---------------------------------------------------------------------------
-- Utility helpers
---------------------------------------------------------------------------
function PiratesPlunder:GetFullName(name)
    if not name then return nil end
    if not name:find("-") then
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
    return self._activeGuildKey or self:GetPlayerGuild() or "__unguilded__"
end

-- Ensures a per-guild data block exists and returns it.
function PiratesPlunder:GetGuildData(guildKey)
    -- Sandbox: route the sandbox key to the transient in-memory table
    if self._sandbox and guildKey == "__sandbox__" then
        return self._sandboxData
    end
    if not guildKey then return nil end
    if not self.db.global.guilds[guildKey] then
        self.db.global.guilds[guildKey] = {
            roster        = {},
            rosterVersion = 0,
            raids         = {},
            activeRaidID  = nil,
        }
    end
    return self.db.global.guilds[guildKey]
end

---------------------------------------------------------------------------
-- Roster display-name helpers
---------------------------------------------------------------------------

-- Human-readable label for a roster key shown in the UI.
function PiratesPlunder:GetRosterDisplayName(key)
    if key == "__unguilded__" then return "Default" end
    if key == "__sandbox__"   then return "Sandbox" end
    local custom = key and key:match("^__custom__:(.+)$")
    if custom then return custom end
    return key or "Unknown"
end

-- True for custom (non-guild) rosters: the Default roster and __custom__:* keys.
function PiratesPlunder:IsCustomRoster(key)
    if key == "__unguilded__" then return true end
    return key ~= nil and key:match("^__custom__:") ~= nil
end

-- Creates a new custom roster with the given display name and activates it.
function PiratesPlunder:CreateCustomRoster(name)
    local trimmed = name and name:trim() or ""
    if trimmed == "" then return end
    local key = (trimmed == "Default") and "__unguilded__" or ("__custom__:" .. trimmed)
    self:GetGuildData(key)     -- creates db entry if missing
    self._activeGuildKey = key
    self:RefreshMainWindow()
end

-- Renames a custom roster: copies data to new key, removes old key.
function PiratesPlunder:RenameCustomRoster(oldKey, newName)
    local trimmed = newName and newName:trim() or ""
    if trimmed == "" then return end
    local newKey = (trimmed == "Default") and "__unguilded__" or ("__custom__:" .. trimmed)
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
    -- Build a fresh in-memory guild data block with a pre-created active raid
    self._sandboxData = {
        roster        = {},
        rosterVersion = 0,
        raids         = {},
        activeRaidID  = "sandbox_raid",
    }
    self._sandboxData.raids["sandbox_raid"] = {
        id             = "sandbox_raid",
        name           = "[Sandbox] Test Raid",
        startedAt      = GetTime(),
        active         = true,
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
    -- Discard any loot state accumulated during the sandbox session
    wipe(self.pendingLoot)
    wipe(self.pendingTrades)
    wipe(self.lootQueue)
    if self.lootMasterWindow then self:RefreshLootMasterWindow() end
    self:RefreshLootResponseFrame()
    self:RefreshMainWindow()
    self:Print("|cFF888888[Sandbox] Disabled.|r")
end

function PiratesPlunder:GetRoster(guildKey)
    return self:GetGuildData(guildKey or self:GetActiveGuildKey()).roster
end

function PiratesPlunder:GetGuildRaids(guildKey)
    return self:GetGuildData(guildKey or self:GetActiveGuildKey()).raids
end

function PiratesPlunder:BumpRosterVersion(guildKey)
    local gd = self:GetGuildData(guildKey or self:GetActiveGuildKey())
    gd.rosterVersion = gd.rosterVersion + 1
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

function PiratesPlunder:IsRaidLeaderOrAssist()
    if self._sandbox then return true end
    if not IsInRaid() then return false end
    local me = self:GetPlayerFullName()
    for i = 1, GetNumGroupMembers() do
        local name, rank = GetRaidRosterInfo(i)
        if name and self:GetFullName(name) == me then
            return rank >= 1   -- 2 = leader, 1 = assistant
        end
    end
    return false
end

function PiratesPlunder:CanModify()
    if self._sandbox then return self._sandboxModOverride ~= false end
    -- Must have officer or raid-leader/assistant role
    if not (self:IsOfficerOrHigher() or self:IsRaidLeaderOrAssist()) then
        return false
    end
    -- Player's guild must match the active roster guild to prevent officers
    -- from other guilds modifying this roster and syncing it to everyone.
    local myGuild   = self:GetPlayerGuild() or "__unguilded__"
    local activeKey = self:GetActiveGuildKey()
    return myGuild == activeKey
end

function PiratesPlunder:HasActiveRaid()
    -- In sandbox, the fake raid is always active
    if self._sandbox then
        return self._sandboxData ~= nil
            and self._sandboxData.raids["sandbox_raid"] ~= nil
    end
    local gd = self:GetGuildData(self:GetActiveGuildKey())
    if not gd then return false end
    local id = gd.activeRaidID
    if id and gd.raids[id] then
        return gd.raids[id].active == true
    end
    return false
end

function PiratesPlunder:GetActiveRaid()
    local gd = self:GetGuildData(self:GetActiveGuildKey())
    if not gd then return nil, nil end
    local id = gd.activeRaidID
    if id then return gd.raids[id], id end
    return nil, nil
end

function PiratesPlunder:CheckActiveRaid()
    if self:HasActiveRaid() and not IsInGroup() then
        self:EndRaid()
    end
    -- Clear stale pending loot when there is no active raid
    if not self:HasActiveRaid() and next(self.pendingLoot) ~= nil then
        wipe(self.pendingLoot)
        self:SavePendingLoot()
        self:RefreshLootResponseFrame()
        self:RefreshLootMasterWindow()
    end
end

-- Generate a unique key from an item link + timestamp
function PiratesPlunder:LootKey(itemLink)
    return tostring(itemLink) .. ":" .. tostring(GetTime())
end

---------------------------------------------------------------------------
-- Persist / restore pending loot across reloads
---------------------------------------------------------------------------
function PiratesPlunder:SavePendingLoot()
    -- Store in DB so it survives /reload; skip entirely in sandbox mode
    if not self.db then return end
    if self._sandbox then return end
    self.db.global.pendingLootCache = {}
    for key, entry in pairs(self.pendingLoot) do
        if not entry.awarded then
            self.db.global.pendingLootCache[key] = {
                itemLink  = entry.itemLink,
                itemID    = entry.itemID,
                postedBy  = entry.postedBy,
                responses = entry.responses or {},
            }
        end
    end
end

function PiratesPlunder:RestorePendingLoot()
    -- Don't restore stale loot if there is no active raid
    if not self:HasActiveRaid() then
        self.db.global.pendingLootCache = {}
        return
    end
    local cache = self.db and self.db.global.pendingLootCache
    if not cache then return end
    for key, saved in pairs(cache) do
        self.pendingLoot[key] = {
            itemLink  = saved.itemLink,
            itemID    = saved.itemID,
            postedBy  = saved.postedBy,
            postedAt  = GetTime(),
            responses = saved.responses or {},
            awarded   = false,
            awardedTo = nil,
        }
    end
    -- Show the unified response popup for any items we haven't responded to yet
    self:ScheduleTimer(function()
        local me = self:GetPlayerFullName()
        local hasUnresponded = false
        for key, entry in pairs(self.pendingLoot) do
            if not entry.responses[me] then
                hasUnresponded = true
                break
            end
        end
        if hasUnresponded then
            self:ShowLootResponseFrame()
        end
    end, 2) -- short delay so UI is fully loaded
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
    if not self:HasActiveRaid() then
        self:Print("No active raid – cannot post loot.")
        return
    end
    if not self:CanModify() and not self:IsRaidLeaderOrAssist() then
        self:Print("Only officers or raid leader/assistants can post loot.")
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

    -- When in a raid, track the raid leader's guild as the active guild key.
    -- This prevents officers from foreign guilds from modifying the roster.
    if IsInRaid() then
        local leaderGuild = self:GetRaidLeaderGuild()
        if leaderGuild then
            self._activeGuildKey = leaderGuild
        end
    end

    if self:HasActiveRaid() and IsInRaid() then
        self:AutoPopulateRoster()
        self:CheckRaidLeaderPresent()
    end
    self:RefreshMainWindow()
end

function PiratesPlunder:OnEncounterEnd(_, encounterID, encounterName, difficultyID, groupSize, success)
    if success == 1 and self:HasActiveRaid() and IsInRaid() then
        self:OnBossKill(encounterID, encounterName)
    end
end

function PiratesPlunder:OnGroupLeft()
    if self:HasActiveRaid() then
        local me = self:GetPlayerFullName()
        local raid = self:GetActiveRaid()
        if raid and raid.leader == me then
            self:EndRaid()
            self:Print("Raid ended – you left the group.")
        end
    end
    -- Reset active guild to own guild when leaving the group
    self._activeGuildKey = self:GetPlayerGuild() or "__unguilded__"
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
    -- Leaders and officers roll normally
    if self:IsRaidLeaderOrAssist() or self:IsOfficerOrHigher() then return end
    local _, _, _, quality = GetLootRollItemInfo(rollID)
    if quality and quality >= 4 then  -- 4 = Epic, 5 = Legendary, …
        RollOnLoot(rollID, 0)  -- 0 = Pass
        local _, name = GetLootRollItemInfo(rollID)
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
    self.db.global.migrated_v2 = true  -- don't re-run migration on empty data
    -- Clear runtime state
    wipe(self.pendingLoot)
    wipe(self.pendingTrades)
    self._activeGuildKey = self:GetPlayerGuild() or "__unguilded__"
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
    -- Ensure the default roster exists
    self:GetGuildData("__unguilded__")
    -- Ensure active guild key is set after world load
    local myGuild = self:GetPlayerGuild()
    if myGuild then
        self._activeGuildKey = self._activeGuildKey or myGuild
    else
        self._activeGuildKey = self._activeGuildKey or "__unguilded__"
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
    end
end