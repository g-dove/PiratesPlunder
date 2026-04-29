---@meta
---------------------------------------------------------------------------
-- Pirates Plunder – EmmyLua type stubs
-- For IDE navigation only — this file is NOT loaded by WoW.
--
-- Add `---@type PPAddon` before each `local PP = LibStub(...)` line in
-- module files to enable F12 go-to-definition and Find All References.
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

---@class PPMsgConstants
---@field SYNC_REQUEST     string
---@field SYNC_FULL        string
---@field ROSTER_UPDATE    string
---@field SESSION_CREATE   string
---@field SESSION_CLOSE    string
---@field SCORE_UPDATE     string
---@field LOOT_POST        string
---@field LOOT_INTEREST    string
---@field LOOT_AWARD       string
---@field LOOT_CANCEL      string
---@field LOOT_UPDATE      string
---@field RAID_SETTINGS    string
---@field SESSION_DELETE   string
---@field LOOT_VOTE        string
---@field LOOT_CLEAR       string
---@field LOOT_STATE_QUERY string
---@field LOOT_STATE_REPLY string
---@field VERSION_REQUEST  string
---@field VERSION_REPLY    string
---@field GROUP_SCORE      string
---@field GROUP_SCORE_ACK  string
---@field SNAPSHOT_REQUEST string
---@field SNAPSHOT_REPLY   string

---@class PPResponseConstants
---@field NEED     string
---@field MINOR    string
---@field TRANSMOG string
---@field PASS     string

---@class PPSessionEndConstants
---@field OFFICER_ACTION string
---@field LEFT_GROUP     string
---@field LEADER_LEFT    string
---@field SYNC_RECEIVED  string
---@field SYNC_DELETE    string
---@field SYNC_FULL      string
---@field STARTUP_CHECK  string
---@field RESET          string

---@class PPMinimapIconConfig
---@field hide              boolean       whether the button is hidden
---@field minimapPos        number|nil    angle position around the minimap (written by LibDBIcon during drag)
---@field lock              boolean|nil   when true, drag-to-reposition is disabled
---@field showInCompartment boolean|nil   when true, button is also shown in the addon compartment

---------------------------------------------------------------------------
-- Repository layer – Repository/RosterRepository.lua
---------------------------------------------------------------------------

---@class PPRosterRepo
local PPRosterRepo = {}

--- Canonical per-guild data accessor. Sandbox routing is exclusively here.
---@param guildKey string
---@return table guildData
function PPRosterRepo:GetData(guildKey) end

---@param guildKey string
---@return table
function PPRosterRepo:GetRoster(guildKey) end

---@param guildKey string
---@return table
function PPRosterRepo:GetSessions(guildKey) end

---@return table|nil session, string|nil sessionID
function PPRosterRepo:GetActiveSession() end

---@return boolean
function PPRosterRepo:HasActiveSession() end

---@return string[]
function PPRosterRepo:GetAllGuildKeys() end

---@param gk string
---@param id string
function PPRosterRepo:SetActiveSessionID(gk, id) end

---@param gk string
function PPRosterRepo:ClearActiveSessionID(gk) end

---@param gk string
---@param sessionID string
---@param ts number
---@param reason string
function PPRosterRepo:MarkSessionEnded(gk, sessionID, ts, reason) end

---@param gk string
---@param id string
---@param ver number
function PPRosterRepo:AddTombstone(gk, id, ver) end

---@param guildKey string
function PPRosterRepo:BumpRosterVersion(guildKey) end

---@param gk string
---@return number
function PPRosterRepo:GetRosterVersion(gk) end

--- Returns the stored end-of-session roster snapshot, if any.
---@param gk string
---@param sessionID string
---@return table|nil snapshot  { capturedAt:number, rosterVersion:number, entries:table<string, table> }
function PPRosterRepo:GetSessionSnapshot(gk, sessionID) end

--- Stores a snapshot only when its rosterVersion exceeds what we already hold.
---@param gk string
---@param sessionID string
---@param snapshot table
---@return boolean stored
function PPRosterRepo:SetSessionSnapshot(gk, sessionID, snapshot) end

--- Builds a snapshot of the current roster tagged with the current rosterVersion.
--- Returns nil for sandbox / unknown guilds.
---@param gk string
---@return table|nil snapshot
function PPRosterRepo:BuildRosterSnapshot(gk) end

--- Returns { [sessionID] = rosterVersion } for every snapshot stored under gk.
--- Sessions present locally without a snapshot map to 0. Used to build SNAPSHOT_REQUEST payloads.
---@param gk string
---@return table<string, number>
function PPRosterRepo:GetAllSnapshotVersions(gk) end

---------------------------------------------------------------------------
-- Repository layer – Repository/LootRepository.lua
---------------------------------------------------------------------------

---@class PPLootRepo
local PPLootRepo = {}

---@param key string
---@return table|nil
function PPLootRepo:GetEntry(key) end

---@param key string
---@param entry table
function PPLootRepo:SetEntry(key, entry) end

---@param key string
function PPLootRepo:ClearEntry(key) end

function PPLootRepo:WipeAll() end

---@return table<string, table>
function PPLootRepo:GetAll() end

---@return string[]
function PPLootRepo:GetQueue() end

---@param link string
function PPLootRepo:AddToQueue(link) end

---@return table[]
function PPLootRepo:GetPendingTrades() end

---@param idx number
function PPLootRepo:RemovePendingTrade(idx) end

function PPLootRepo:Save() end

function PPLootRepo:Restore() end

---@class PPRepo
---@field Roster PPRosterRepo
---@field Loot   PPLootRepo

---------------------------------------------------------------------------
-- Service layer – Services/SessionService.lua
---------------------------------------------------------------------------

---@class PPSession
local PPSession = {}

--- Canonical session teardown — the single path for all session ends.
---@param reason    string   PP.SESSION_END.*
---@param sessionID? string  defaults to active session
---@param guildKey?  string  defaults to active guild key
function PPSession:End(reason, sessionID, guildKey) end

---@param raidName? string
function PPSession:Create(raidName) end

---@param raidID string
function PPSession:Delete(raidID) end

function PPSession:CheckLeaderPresent() end

---@param encounterID   number
---@param encounterName string
function PPSession:AddBoss(encounterID, encounterName) end

---@param itemLink    string
---@param itemID      number
---@param awardedTo   string
---@param pointsSpent number
---@param response    string  PP.RESPONSE.*
---@param lootKey     string
function PPSession:RecordItemAward(itemLink, itemID, awardedTo, pointsSpent, response, lootKey) end

---------------------------------------------------------------------------
-- Service layer – Services/RosterService.lua
---------------------------------------------------------------------------

---@class PPRosterService
local PPRosterService = {}

---@param fullName string  "Name-Realm"
function PPRosterService:Add(fullName) end

---@param fullName string
function PPRosterService:Remove(fullName) end

---@param fullName string
---@param newScore number
function PPRosterService:SetScore(fullName, newScore) end

function PPRosterService:Randomize() end

function PPRosterService:Clear() end

function PPRosterService:AutoPopulate() end

---@param amount number
function PPRosterService:AddScoreToRaidMembers(amount) end

---@return table[]
function PPRosterService:GetSorted() end

---@return table<string, boolean>
function PPRosterService:GetRaidMemberSet() end

---------------------------------------------------------------------------
-- Service layer – Services/LootService.lua
---------------------------------------------------------------------------

---@class PPLootService
local PPLootService = {}

function PPLootService:Restore() end

---@param itemLink string
function PPLootService:Post(itemLink) end

---@param key string
function PPLootService:Cancel(key) end

---@param key      string
---@param fullName string
---@param free?    boolean  true = skip score deduction (e.g. officer override)
function PPLootService:Award(key, fullName, free) end

---@param key      string
---@param response string  PP.RESPONSE.*
function PPLootService:SubmitResponse(key, response) end

function PPLootService:PostAll() end

--- Raid-leader-only: schedules a 60 s LOOT_CLEAR broadcast once the queue empties.
function PPLootService:_ScheduleIdleClear() end

function PPLootService:_CancelIdleClear() end

---------------------------------------------------------------------------
-- Main addon object – methods spread across main.lua + all module files
---------------------------------------------------------------------------

---@class PPAddon
---@field COMM_PREFIX   string
---@field VERSION       string
---@field MSG           PPMsgConstants
---@field RESPONSE      PPResponseConstants
---@field SESSION_END   PPSessionEndConstants
---@field Repo          PPRepo
---@field Session       PPSession
---@field Roster        PPRosterService
---@field Loot          PPLootService
---@field db            table                    AceDB-3.0 instance; db.global.minimapIcon is PPMinimapIconConfig
---@field pendingLoot   table<string, table>
---@field pendingTrades table[]
---@field lootQueue     string[]
---@field lootPopups    table<string, table>
---@field AceGUI        table
---@field _commandGroups function[]
---@field _sandbox      boolean
---@field _sandboxMod   boolean
---@field _debug        boolean
---@field _ppUsers      table<string, boolean>|nil
---@field _completedLootKeys      table<string, boolean>
---@field _groupScoreHashes     table<string, number>|nil
---@field _lastFullSyncSent     number|nil
---@field _lastSyncRequestSent  number|nil
---@field _lastSnapshotFetchSent number|nil
---@field _snapshotFetchAppliedCount number|nil
---@field _lootIdleTimer        any|nil
---@field _snapshotWindow       table|nil
---@field _lootStateVerifyPending boolean|nil
---@field _currentTradePartner string|nil
---@field _currentTradeSlotted table|nil
local PPAddon = {}

-- main.lua ----------------------------------------------------------------

function PPAddon:OnInitialize() end
function PPAddon:OnEnable() end

---@return table|nil
function PPAddon:FindCustomRosterWithActiveRaid() end

---@param input string
function PPAddon:SlashCommand(input) end
function PPAddon:SlashCommandResponse() end

--- Normalize a bare name or "Name-Realm" to "Name-Realm".
---@param name string
---@return string
function PPAddon:GetFullName(name) end

--- Strip the realm suffix from a full name.
---@param fullName string
---@return string
function PPAddon:GetShortName(fullName) end

---@return string
function PPAddon:GetPlayerFullName() end

---@return string|nil
function PPAddon:GetPlayerGuild() end

---@return string|nil
function PPAddon:GetRaidLeaderGuild() end

---@return string
function PPAddon:GetActiveGuildKey() end

---@param key string
---@return string
function PPAddon:GetRosterDisplayName(key) end

---@param key string
---@return boolean
function PPAddon:IsCustomRoster(key) end

---@param name string
function PPAddon:CreateCustomRoster(name) end

---@param oldKey  string
---@param newName string
function PPAddon:RenameCustomRoster(oldKey, newName) end

---@param key string
function PPAddon:DeleteGuildRoster(key) end

---@param key string
function PPAddon:DeleteCustomRoster(key) end

---@return boolean
function PPAddon:IsSandbox() end
function PPAddon:EnableSandbox() end
function PPAddon:DisableSandbox() end

function PPAddon:RefreshOfficerStatus() end

---@return boolean
function PPAddon:IsOfficerOrHigher() end

--- Returns 2=leader, 1=assist, 0=member, -1=not in raid.
---@return number
function PPAddon:GetMyRaidRank() end

---@return boolean
function PPAddon:IsRaidLeaderOrAssist() end

---@return boolean
function PPAddon:IsRaidLeader() end

---@return boolean
function PPAddon:CanModify() end

---@return boolean
function PPAddon:CanViewLootMaster() end

---@return boolean
function PPAddon:CanPostLoot() end

---@return boolean
function PPAddon:CheckActiveRaid() end

---@param frame     table
---@param frameName string
function PPAddon:RegisterEscFrame(frame, frameName) end

---@param itemLink string
---@return string
function PPAddon:LootKey(itemLink) end

function PPAddon:InstallAltRightClickHook() end

---@param itemLink string
function PPAddon:AltRightClickPost(itemLink) end

function PPAddon:OnGroupRosterUpdate() end

---@param _            any
---@param encounterID  number
---@param encounterName string
---@param difficultyID number
---@param groupSize    number
---@param success      number
function PPAddon:OnEncounterEnd(_, encounterID, encounterName, difficultyID, groupSize, success) end

function PPAddon:OnGroupLeft() end
function PPAddon:OnPartyLeaderChanged() end
function PPAddon:CompletePendingSessionEnd() end
function PPAddon:ShowLootResponseFrameIfNeeded() end
function PPAddon:OnGuildRosterUpdate() end

---@param _      any
---@param rollID number
function PPAddon:OnStartLootRoll(_, rollID) end

function PPAddon:ResetAddon() end

---@param _             any
---@param isInitialLogin boolean
---@param isReloadingUi  boolean
function PPAddon:OnPlayerEnteringWorld(_, isInitialLogin, isReloadingUi) end

-- Modules/Roster.lua ------------------------------------------------------

---@param encounterID   number
---@param encounterName string
function PPAddon:OnBossKill(encounterID, encounterName) end

-- Modules/Raid.lua --------------------------------------------------------

---@return table[]
function PPAddon:GetRaidHistory() end

-- Modules/Loot.lua --------------------------------------------------------

---@param newItemLink string
---@return table  { equippedLinks: string[] }
function PPAddon:GetEquippedComparisonData(newItemLink) end

---@param key        string
---@param playerName string
---@param response   string
---@param score      number
---@param comp       table
function PPAddon:ReceiveLootInterest(key, playerName, response, score, comp) end

---@param fullName string
---@return number
function PPAddon:GetMinorUpgradeScore(fullName) end

---@param key string
---@return table[]
function PPAddon:GetSortedResponses(key) end

---@param key            string
---@param targetFullName string
function PPAddon:CastVote(key, targetFullName) end

---@param key            string
---@param voterName      string
---@param targetFullName string
function PPAddon:ReceiveVote(key, voterName, targetFullName) end

---@return table[]
function PPAddon:GetPendingLootList() end

---@param itemLink string
function PPAddon:AddToLootQueue(itemLink) end

---@param index number
function PPAddon:RemoveFromLootQueue(index) end

---@param key   string
---@param allow boolean
function PPAddon:SetLootTransmog(key, allow) end

-- Modules/AwardedLoot.lua -------------------------------------------------

---@param fullName string
---@return table[]
function PPAddon:GetPlayerAwardedLoot(fullName) end

-- Modules/Sync.lua --------------------------------------------------------

--- Send an addon comm message. Whispers `target` if provided, else broadcasts to RAID/PARTY.
---@param msgType string   PP.MSG.*
---@param data    table
---@param target? string   player name for point-to-point whisper
function PPAddon:SendAddonMessage(msgType, data, target) end

---@param prefix       string
---@param message      string
---@param distribution string
---@param sender       string
function PPAddon:OnCommReceived(prefix, message, distribution, sender) end

---@param sender string
function PPAddon:HandleVersionRequest(sender) end

---@param data   table
---@param sender string
function PPAddon:HandleVersionReply(data, sender) end

function PPAddon:BroadcastRaidSettings() end

---@param data   table
---@param sender string
function PPAddon:HandleRaidSettings(data, sender) end

function PPAddon:BroadcastRoster() end

--- Apply (guildKey, activeSessionID, activeSessionVersion) from any inbound
--- broadcast. Adopts a newer active session, ends a stale local one, updates
--- _activeGuildKey when in a raid. Idempotent.
---@param guildKey             string
---@param activeSessionID      string|nil
---@param activeSessionVersion number|nil
function PPAddon:_adoptSessionContext(guildKey, activeSessionID, activeSessionVersion) end

function PPAddon:WipeRetryQueue() end

function PPAddon:BroadcastGroupScore(amount) end
function PPAddon:HandleGroupScore(data, sender) end
function PPAddon:HandleGroupScoreAck(data, sender) end

---@param sessionID string
function PPAddon:BroadcastSessionCreate(sessionID) end

---@param sessionID string
---@param snapshot? table  optional roster snapshot rebuilt at session-end and shipped inline
function PPAddon:BroadcastSessionClose(sessionID, snapshot) end

---@param sessionID  string
---@param guildKey   string
---@param newVersion number
function PPAddon:BroadcastSessionDelete(sessionID, guildKey, newVersion) end

function PPAddon:RequestSync() end

---@param guildKey? string
---@param target?   string  optional whisper target; bypasses the broadcast cooldown
function PPAddon:SendFullSync(guildKey, target) end

---@param sender string
---@param data   table
function PPAddon:HandleSyncRequest(sender, data) end

---@param data         table
---@param sender       string
---@param distribution? string  AceComm distribution channel ("WHISPER" enforces the trust window)
function PPAddon:HandleSyncFull(data, sender, distribution) end

---@param sender string
---@return boolean
function PPAddon:_isSenderInGroup(sender) end

---@param data   table
---@param sender string
function PPAddon:HandleRosterUpdate(data, sender) end

---@param data   table
---@param sender string
function PPAddon:HandleSessionCreate(data, sender) end

---@param data   table
---@param sender string
function PPAddon:HandleSessionDelete(data, sender) end

---@param data   table
---@param sender string
function PPAddon:HandleSessionClose(data, sender) end

---@param data   table
---@param sender string
function PPAddon:HandleScoreUpdate(data, sender) end

---@param data   table
---@param sender string
function PPAddon:HandleLootPost(data, sender) end

---@param data   table
---@param sender string
function PPAddon:HandleLootInterest(data, sender) end

---@param data   table
---@param sender string
function PPAddon:HandleLootAward(data, sender) end

---@param data   table
---@param sender string
function PPAddon:HandleLootVote(data, sender) end

---@param data table
function PPAddon:HandleLootUpdate(data) end

---@param sender string
---@param data   table
function PPAddon:HandleLootStateQuery(sender, data) end

---@param data table
function PPAddon:HandleLootStateReply(data) end

---@param data   table
---@param sender string
function PPAddon:HandleLootCancel(data, sender) end

---@param sender string
function PPAddon:HandleLootClear(sender) end

--- User-triggered backfill: ask the group for any session snapshots they hold
--- at a higher rosterVersion than what we have locally. 5 s cooldown.
function PPAddon:RequestSessionSnapshots() end

---@param sender       string
---@param data         table
---@param distribution string  AceComm distribution channel
function PPAddon:HandleSnapshotRequest(sender, data, distribution) end

---@param data         table
---@param sender       string
---@param distribution string
function PPAddon:HandleSnapshotReply(data, sender, distribution) end

--- Bounded post-join sync handshake: up to 3 attempts to RequestSync until an
--- active session is adopted, the group is left, or no PP users remain.
---@param attempt? number
function PPAddon:_ScheduleJoinSync(attempt) end

-- Modules/Trade.lua -------------------------------------------------------

function PPAddon:OnTradeShow() end
function PPAddon:OnTradeClosed() end

---@param itemID number
---@return number|nil bag, number|nil slot
function PPAddon:FindItemInBags(itemID) end

---@param itemID    number
---@param awardedTo string
function PPAddon:RemovePendingTrade(itemID, awardedTo) end

-- UI/MainWindow.lua -------------------------------------------------------

function PPAddon:ToggleMainWindow() end
function PPAddon:RefreshMainWindow() end
function PPAddon:CreateMainWindow() end

---@param container table
function PPAddon:DrawRosterTab(container) end

---@param container table
function PPAddon:DrawSessionsTab(container) end

---@param container table
function PPAddon:DrawSettingsTab(container) end

--- Roster snapshot popup for an ended session.
---@param guildKey  string
---@param sessionID string
function PPAddon:ShowRosterSnapshot(guildKey, sessionID) end

-- UI/LootWindow.lua -------------------------------------------------------

function PPAddon:ToggleLootMasterWindow() end
function PPAddon:RefreshLootMasterWindow() end
function PPAddon:CreateLootMasterWindow() end

---@param container table
function PPAddon:DrawLootMasterContent(container) end

function PPAddon:ShowLootResponseFrame() end
function PPAddon:HideLootResponseFrame() end
function PPAddon:RefreshLootResponseFrame() end
function PPAddon:CloseLootPopups() end

---@param key      string
---@param itemLink string
function PPAddon:ShowLootPopup(key, itemLink) end

function PPAddon:CreateLootBarsFrame() end
function PPAddon:ShowLootBars() end
function PPAddon:HideLootBars() end
function PPAddon:RefreshLootBars() end

--- Wipe pending loot for this client only (no broadcast). Bound to /pp loot clear
--- and the Settings tab "Clear My Loot Display" button.
function PPAddon:LocalClearLoot() end

-- UI/AwardedLootWindow.lua ------------------------------------------------

---@param fullName string
function PPAddon:ShowAwardedLootWindow(fullName) end

function PPAddon:HideAwardedLootWindow() end
function PPAddon:RefreshAwardedLootWindow() end

---@param container table
---@param fullName  string
function PPAddon:DrawAwardedLootContent(container, fullName) end

-- UI/MinimapIcon.lua -------------------------------------------------------

--- Registers the LibDataBroker data object and LibDBIcon minimap button.
--- Called once at the end of OnInitialize after self.db is available.
function PPAddon:SetupMinimapIcon() end

--- Show the minimap button and persist the visible state across reloads.
function PPAddon:ShowMinimapIcon() end

--- Hide the minimap button and persist the hidden state across reloads.
function PPAddon:HideMinimapIcon() end

-- UI/VersionCheckWindow.lua -----------------------------------------------

function PPAddon:ShowVersionCheckWindow() end

---@param sender  string
---@param version string
function PPAddon:UpdateVersionCheckWindow(sender, version) end

function PPAddon:DrawVersionList() end

---------------------------------------------------------------------------
-- Global declaration
-- The addon instance set via _G.PiratesPlunder in main.lua.
---------------------------------------------------------------------------
---@type PPAddon
PiratesPlunder = nil
