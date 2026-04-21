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
---@field LOOT_STATE_QUERY string
---@field LOOT_STATE_REPLY string
---@field VERSION_REQUEST  string
---@field VERSION_REPLY    string
---@field ROSTER_DELTA     string
---@field GROUP_SCORE      string
---@field GROUP_SCORE_ACK  string

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
function PPAddon:BroadcastRosterDelta(changed, removed) end
function PPAddon:HandleRosterDelta(data, sender) end
function PPAddon:BroadcastGroupScore(amount) end
function PPAddon:HandleGroupScore(data, sender) end
function PPAddon:HandleGroupScoreAck(data, sender) end

---@param sessionID string
function PPAddon:BroadcastSessionCreate(sessionID) end

---@param sessionID string
function PPAddon:BroadcastSessionClose(sessionID) end

---@param sessionID  string
---@param guildKey   string
---@param newVersion number
function PPAddon:BroadcastSessionDelete(sessionID, guildKey, newVersion) end

function PPAddon:RequestSync() end

---@param guildKey? string
function PPAddon:SendFullSync(guildKey) end

---@param sender string
---@param data   table
function PPAddon:HandleSyncRequest(sender, data) end

---@param data   table
---@param sender string
function PPAddon:HandleSyncFull(data, sender) end

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
