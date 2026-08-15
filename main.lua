---------------------------------------------------------------------------
-- Pirates Plunder - Core initialization, DB schema, utilities, slash commands
---------------------------------------------------------------------------
local addonName, NS = ...

local PiratesPlunder = LibStub("AceAddon-3.0"):NewAddon("PiratesPlunder",
    "AceConsole-3.0", "AceHook-3.0", "AceComm-3.0",
    "AceSerializer-3.0", "AceEvent-3.0", "AceTimer-3.0")

NS.addon = PiratesPlunder
_G.PiratesPlunder = PiratesPlunder
---@type PPAddon
local PP = PiratesPlunder

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
PiratesPlunder.COMM_PREFIX = "PPLNDR"
PiratesPlunder.VERSION     = C_AddOns.GetAddOnMetadata(addonName, "Version") or "Unable to find version info."

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
    LOOT_CLEAR        = "LOT_CLR",
    LOOT_STATE_QUERY  = "LOT_SQR",
    LOOT_STATE_REPLY  = "LOT_SRP",
    VERSION_REQUEST   = "VER_REQ",
    VERSION_REPLY     = "VER_REP",
    ACK               = "ACK",
    GROUP_SCORE       = "GRP_SCR",
    SNAPSHOT_REQUEST  = "SNP_REQ",
    SNAPSHOT_REPLY    = "SNP_REP",
    SESSION_SYNC_REQUEST = "SES_SRQ",
    SESSION_SYNC_REPLY   = "SES_SRP",
}

PiratesPlunder.RESPONSE = {
    NEED    = "NEED",
    MINOR   = "MINOR",
    TRANSMOG = "TRANSMOG",
    PASS    = "PASS",
}

---------------------------------------------------------------------------
-- Saved-variable DB defaults
---------------------------------------------------------------------------
local defaults = {
    global = {
        guilds = {},
        pendingLootCache = {},
        pendingTradesCache = {},
        officerRankThreshold = 1,
        migrated_v2 = false,
        allowTransmogRolls = true,
        autoPassEpicRolls = false,
        minimapIcon = { hide = false },
        lootBarsAnchor = { point = "BOTTOMRIGHT", x = -230, y = 100 },
    },
    profile = {},
}

---------------------------------------------------------------------------
-- Lifecycle callbacks
---------------------------------------------------------------------------
function PiratesPlunder:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("PiratesPlunderDB", defaults, true)

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

    if self.db.global.guilds and self.db.global.guilds["__unguilded__"] then
        local ud     = self.db.global.guilds["__unguilded__"]
        local newKey = "__custom__:Default"
        if ud.roster and next(ud.roster) ~= nil then
            if not self.db.global.guilds[newKey] then
                self.db.global.guilds[newKey] = ud
            end
        end
        self.db.global.guilds["__unguilded__"] = nil
    end

    self:RegisterChatCommand("pp", "SlashCommand")
    self:RegisterChatCommand("piratesplunder", "SlashCommand")

    self:RegisterComm(self.COMM_PREFIX)

    self.pendingLoot      = {}
    self.pendingTrades    = {}
    self.lootQueue        = {}
    self.mainWindow       = nil
    self.lootMasterWindow = nil
    self.lootPopups       = {}
    self.lootResponseFrame = nil
    self.lootBarsFrame    = nil
    self.awardedLootWindow = nil
    self._awardedLootTarget = nil
    self._pendingDeleteRaidID = nil
    self._pendingContinueRaidID = nil
    self._isOfficer       = nil
    self._wasInGroup      = IsInGroup()
    self._activeGuildKey  = nil
    self._sandbox         = false
    self._sandboxData     = nil

    self._commandGroups = self._commandGroups or {}

    self:SetupMinimapIcon()
    self:Print("Pirates Plunder " .. self.VERSION .. " loaded. Type /pp to open.")
end

function PiratesPlunder:OnEnable()
    self:RegisterEvent("GROUP_ROSTER_UPDATE",  "OnGroupRosterUpdate")
    self:RegisterEvent("ENCOUNTER_END",        "OnEncounterEnd")
    self:RegisterEvent("TRADE_SHOW",           "OnTradeShow")
    self:RegisterEvent("TRADE_CLOSED",         "OnTradeClosed")
    self:RegisterEvent("GROUP_LEFT",           "OnGroupLeft")
    self:RegisterEvent("PARTY_LEADER_CHANGED", "OnPartyLeaderChanged")
    self:RegisterEvent("GUILD_ROSTER_UPDATE",  "OnGuildRosterUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD","OnPlayerEnteringWorld")
    self:RegisterEvent("START_LOOT_ROLL",       "OnStartLootRoll")

    if IsInGuild() then
        C_GuildInfo.GuildRoster()
    end

    local _initGuild = self:GetPlayerGuild()
    if _initGuild and self.db.global.guilds[_initGuild] then
        self._activeGuildKey = _initGuild
    else
        self._activeGuildKey = next(self.db.global.guilds) or nil
    end

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

function PiratesPlunder:SlashCommandResponse()
    local frameVisible  = self.lootResponseFrame and self.lootResponseFrame:IsShown()
    local barsVisible   = self.lootBarsFrame and self.lootBarsFrame:IsShown()
    if frameVisible or barsVisible then
        if self.lootResponseFrame then
            self._suppressLootBars = true
            self.lootResponseFrame:Hide()
            self._suppressLootBars = nil
        end
        self:HideLootBars()
    else
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

function PiratesPlunder:GetActiveGuildKey()
    if self._sandbox then return "__sandbox__" end
    return self._activeGuildKey or self:GetPlayerGuild() or nil
end

---------------------------------------------------------------------------
-- Roster display-name helpers
---------------------------------------------------------------------------
function PiratesPlunder:GetRosterDisplayName(key)
    if key == "__sandbox__" then return "Sandbox" end
    local custom = key and key:match("^__custom__:(.+)$")
    if custom then return custom end
    return key or "Unknown"
end

function PiratesPlunder:DeleteGuildRoster(key)
    if not key or key == "__sandbox__" then return end
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

---------------------------------------------------------------------------
-- Sandbox mode helpers
---------------------------------------------------------------------------
function PiratesPlunder:IsSandbox()
    return self._sandbox == true
end

function PiratesPlunder:EnableSandbox()
    if self._sandbox then return end
    self._sandbox = true
    self._sandboxModOverride = true
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
        items          = {},
        bosses         = {},
        bossKills      = {},
        lootAwarded    = {},
        guildKey       = "__sandbox__",
        memberSnapshot = {},
    }
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
    wipe(self.pendingLoot)
    wipe(self.pendingTrades)
    wipe(self.lootQueue)
    if self.lootMasterWindow then self:RefreshLootMasterWindow() end
    self:RefreshLootResponseFrame()
    self:RefreshMainWindow()
    self:Print("|cFF888888[Sandbox] Disabled.|r")
end

function PiratesPlunder:RefreshOfficerStatus()
    self._isOfficer = false

    if not IsInGuild() then return end

    if C_GuildInfo.IsGuildOfficer then
        self._isOfficer = C_GuildInfo.IsGuildOfficer() == true
        return
    end

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

function PiratesPlunder:IsOfficerOrHigher()
    if self._sandbox then return true end
    if self._isOfficer == nil then
        self:RefreshOfficerStatus()
    end
    return self._isOfficer == true
end

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
    if not self:IsOfficerOrHigher() then
        return false
    end
    local myGuild = self:GetPlayerGuild()
    return myGuild ~= nil and myGuild == activeKey
end

function PiratesPlunder:CanViewLootMaster()
    if self._sandbox then return self._sandboxModOverride ~= false end
    if not PP.Repo.Roster:HasActiveSession() then return false end
    return self:CanPostLoot()
end

function PiratesPlunder:CanPostLoot()
    if self._sandbox then return self._sandboxModOverride ~= false end
    if not PP.Repo.Roster:HasActiveSession() then return false end
    return self:CanModify() or self:IsRaidLeaderOrAssist()
end

function PiratesPlunder:CheckActiveRaid()
    if PP.Repo.Roster:HasActiveSession() and not IsInGroup() then
        PP.Session:End(PP.SESSION_END.STARTUP_CHECK)
    end
    if not PP.Repo.Roster:HasActiveSession() and next(PP.Repo.Loot:GetAll()) ~= nil then
        PP.Repo.Loot:WipeAll()
        self:RefreshLootResponseFrame()
        self:RefreshLootMasterWindow()
    end
end

function PiratesPlunder:RegisterEscFrame(frame, frameName)
    _G[frameName] = frame.frame or frame
    tinsert(UISpecialFrames, frameName)
end

local _lootKeyIndex = 0
function PiratesPlunder:LootKey(itemLink)
    _lootKeyIndex = _lootKeyIndex + 1
    return tostring(itemLink) .. ":" .. tostring(time()) .. ":" .. _lootKeyIndex
end

---------------------------------------------------------------------------
-- Alt + Right-click hook to auto-post items
---------------------------------------------------------------------------
function PiratesPlunder:InstallAltRightClickHook()
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
    self:AddToLootQueue(itemLink)
end

---------------------------------------------------------------------------
-- Event stubs (implementations in module files)
---------------------------------------------------------------------------
function PiratesPlunder:_ScheduleJoinSync(attempt)
    attempt = attempt or 1
    if attempt > 3 then return end
    local delay = (attempt == 1) and 3 or 6
    self:ScheduleTimer(function()
        if not IsInGroup() then return end
        if attempt == 1 then
            self:SendAddonMessage(PP.MSG.VERSION_REPLY, { version = PP.VERSION })
        end
        self:RequestSessionSync()
        self:ScheduleTimer(function()
            if IsInGroup()
               and PP._ppUsers and next(PP._ppUsers)
               and not PP.Repo.Roster:HasActiveSession() then
                self:_ScheduleJoinSync(attempt + 1)
            end
        end, 10)
    end, delay)
end

function PiratesPlunder:OnGroupRosterUpdate()
    local nowInGroup = IsInGroup()
    if nowInGroup and not self._wasInGroup then
        self:_ScheduleJoinSync(1)
    end
    self._wasInGroup = nowInGroup

    if not nowInGroup then
        PP._ppUsers = nil
        PP._versionCheckData = nil
    end

    if self.db.global.pendingSessionEnd and nowInGroup then
        self.db.global.pendingSessionEnd = nil
        if self._pendingSessionEndTimer then
            self:CancelTimer(self._pendingSessionEndTimer)
            self._pendingSessionEndTimer = nil
        end
    end

    if IsInRaid() then
        local leaderGuild = self:GetRaidLeaderGuild()
        if leaderGuild then
            self._activeGuildKey = leaderGuild
        end
    end

    if PP.Repo.Roster:HasActiveSession() and IsInRaid() then
        PP.Roster:AutoPopulate()
        PP.Session:CheckLeaderPresent()
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
        if IsInRaid() then
            local _, id = PP.Repo.Roster:GetActiveSession()
            local activeGuildKey = self:GetActiveGuildKey()
            self.db.global.pendingSessionEnd = { sessionID = id, guildKey = activeGuildKey }
            self._pendingSessionEndTimer = self:ScheduleTimer(function()
                if not IsInGroup() then
                    self:CompletePendingSessionEnd()
                else
                    self.db.global.pendingSessionEnd = nil
                    self._pendingSessionEndTimer = nil
                end
            end, 30)
            return
        end

        self:CompletePendingSessionEnd()
    end
    self._activeGuildKey = self:GetPlayerGuild() or nil
end

function PiratesPlunder:CompletePendingSessionEnd()
    if self._pendingSessionEndTimer then
        self:CancelTimer(self._pendingSessionEndTimer)
        self._pendingSessionEndTimer = nil
    end
    self.db.global.pendingSessionEnd = nil

    if PP.Repo.Roster:HasActiveSession() then
        PP.Session:End(PP.SESSION_END.LEFT_GROUP)
        if IsInGroup() then
            self:ScheduleTimer(function() self:RequestSessionSync() end, 1)
        end
    end
    self._activeGuildKey = self:GetPlayerGuild() or nil
end

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
    if self._pendingSyncOnGuildLoad and IsInGroup() then
        self._pendingSyncOnGuildLoad = false
        self:ScheduleTimer(function() self:RequestSessionSync() end, 1)
    end
end

function PiratesPlunder:OnStartLootRoll(_, rollID)
    if not self.db.global.autoPassEpicRolls then return end
    if not PP.Repo.Roster:HasActiveSession() then return end
    if self:IsRaidLeader() then return end
    local _, name, _, quality = GetLootRollItemInfo(rollID)
    if quality and quality >= 4 then
        RollOnLoot(rollID, 0)
        self:Print("|cFFFF4400Auto-passed|r " .. (name or "item") .. " (epic+ auto-pass)")
    end
end

---------------------------------------------------------------------------
-- Reset
---------------------------------------------------------------------------
function PiratesPlunder:ResetAddon()
    wipe(self.db.global.guilds)
    self.db.global.pendingLootCache = {}
    self.db.global.pendingTradesCache = {}
    self.db.global.pendingSessionEnd = nil
    self.db.global.migrated_v2 = true
    self.db.global.migrated_sessions = true
    wipe(self.pendingLoot)
    wipe(self.pendingTrades)
    PP:CloseLootPopups()
    if self._pendingSessionEndTimer then
        self:CancelTimer(self._pendingSessionEndTimer)
        self._pendingSessionEndTimer = nil
    end
    self._activeGuildKey = self:GetPlayerGuild() or nil
    self._isOfficer = nil
    if self.mainWindow then
        self.mainWindow:Hide()
        self.mainWindow = nil
    end
    if self.lootMasterWindow then
        self.lootMasterWindow:Hide()
        self.lootMasterWindow = nil
    end
    self:CloseLootPopups()
    self:Print("|cFFFF4400Addon data reset.|r Reload the UI to start fresh, or re-open /pp.")
end

function PiratesPlunder:OnPlayerEnteringWorld(_, isInitialLogin, isReloadingUi)
    if not self._activeGuildKey then
        local myGuild = self:GetPlayerGuild()
        self._activeGuildKey = (myGuild and self.db.global.guilds[myGuild] and myGuild)
            or next(self.db.global.guilds)
            or nil
    end

    if self.db.global.pendingSessionEnd then
        if IsInGroup() then
            self.db.global.pendingSessionEnd = nil
            if self._pendingSessionEndTimer then
                self:CancelTimer(self._pendingSessionEndTimer)
                self._pendingSessionEndTimer = nil
            end
            self:ScheduleTimer(function() PP.Loot:Restore() end, 3)
        else
            self:CompletePendingSessionEnd()
        end
    end

    if isInitialLogin or isReloadingUi then
        if IsInGuild() then
            self._pendingSyncOnGuildLoad = true
            C_GuildInfo.GuildRoster()
        elseif IsInGroup() then
            self:ScheduleTimer(function() self:RequestSessionSync() end, 5)
        end
        self:ScheduleTimer(function()
            PP.Loot:Restore()
            self:CheckActiveRaid()
        end, 4)
    elseif not self.db.global.pendingSessionEnd then
        self:ScheduleTimer(function() PP.Loot:Restore() end, 3)
    end
end
