# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pirates Plunder is a World of Warcraft AddOn for guild-based loot distribution during raids. It is written in Lua using the Ace3 addon framework. There is no build or compilation step — changes take effect by reloading the UI in WoW (`/reload`).

## No Build/Test Commands

This is a native WoW addon. There are no build, lint, or test commands. The `.pkgmeta` file configures packaging for CurseForge/WoWInterface release tooling, but development is done by editing Lua files directly and testing in-game.

The sandbox mode (`/pp sandbox`) provides an in-game testing environment with fake data — no persistent changes are made while it's active.

## Architecture

### Entry Point & Load Order

Defined in `PiratesPlunder.toc`. Load order matters — sub-tables must exist before use:

1. `embeds.xml` — initializes all bundled Ace3 libraries
2. `main.lua` — core addon object, database schema, events, utilities
3. `Repository/` — DB access wrappers (`PP.Repo.Roster`, `PP.Repo.Loot`)
4. `Services/` — business logic sub-tables (`PP.Session`, `PP.Roster`, `PP.Loot`)
5. `Modules/` — thin game-event wrappers; Sync.lua calls service layer
6. `Commands/` — slash command handlers registered via `PP._commandGroups`
7. `UI/` — window rendering

All files get the addon object via `local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")`. Sub-table methods use `self` for their own table; cross-calls use `PP` explicitly.

### Database Schema (`main.lua`)

Persistent data lives in `PiratesPlunderDB` (AceDB-3.0, global scope). The top-level key structure:

```
guilds[guildKey] = {
  roster: {},          -- player records with scores
  rosterVersion: int,  -- incremented on every roster change for sync
  sessions: {},        -- session records keyed by sessionID
  activeSessionID: str,
  deletedSessions: {}  -- tombstone set to prevent re-syncing deletions
}
pendingLootCache: {}   -- survives UI reloads
pendingTradesCache: {} -- pending trade deliveries, survives UI reloads
minimapIcon: {}        -- LibDBIcon position/visibility persistence
```

Guild keys: real guild names use the guild name as key; unguilded/custom rosters use `__custom__:Name`. The `__sandbox__` key is used during sandbox mode.

Session records include an additive `endReason` field (nil on old records) set when `PP.Session:End()` is called.

### Repository Layer (`Repository/`)

Wraps all DB reads and writes. No business logic lives here. **Sandbox routing is exclusively in `PP.Repo.Roster:GetData()`** — all other methods call it rather than branching on `_sandbox` individually. `EnsureData()` wraps `GetData()` and auto-creates the guild entry if nil — use it for write-path callers; use `GetData` for read-path callers that should handle absence.

- **RosterRepository.lua** (`PP.Repo.Roster`) — all `db.global.guilds` access: `GetData`, `EnsureData`, `GetRoster`, `GetSessions`, `GetActiveSession`, `HasActiveSession`, `GetAllGuildKeys`, `SetActiveSessionID`, `ClearActiveSessionID`, `MarkSessionEnded`, `AddTombstone`, `BumpRosterVersion`, `GetRosterVersion`
- **LootRepository.lua** (`PP.Repo.Loot`) — wraps `PP.pendingLoot` / `PP.lootQueue` / `PP.pendingTrades` runtime tables: `GetEntry`, `SetEntry`, `ClearEntry`, `WipeAll`, `GetAll`, `GetQueue`, `AddToQueue`, `GetPendingTrades`, `RemovePendingTrade`, `Save`, `Restore`

### Service Layer (`Services/`)

Business logic that formerly lived as flat methods on PP.

- **SessionService.lua** (`PP.Session`) — canonical session lifecycle. `PP.SESSION_END` constants: `OFFICER_ACTION`, `LEFT_GROUP`, `LEADER_LEFT`, `SYNC_RECEIVED`, `SYNC_DELETE`, `SYNC_FULL`, `STARTUP_CHECK`. `PP.Session:End(reason, sessionID, guildKey)` is the single teardown path — persists `endReason`, clears loot state, reason-specific messaging, single UI refresh. Also: `Create`, `Delete`, `CheckLeaderPresent`, `AddBoss`, `RecordItemAward`.
- **RosterService.lua** (`PP.Roster`) — `Add`, `Remove`, `SetScore`, `Randomize`, `Clear`, `AutoPopulate`, `AddScoreToRaidMembers`, `GetSorted`, `GetRaidMemberSet`
- **LootService.lua** (`PP.Loot`) — `Post`, `Cancel`, `Award`, `SubmitResponse`, `PostAll`

### Modules (`Modules/`)

Thin wrappers; most logic has moved to Services.

- **Roster.lua** — `OnBossKill` event handler only (calls `PP.Session:AddBoss` + `PP.Roster:AddScoreToRaidMembers`)
- **Raid.lua** — `GetRaidHistory()` only (reads via `PP.Repo.Roster:GetSessions`)
- **Loot.lua** — loot utilities retained here: `GetEquippedComparisonData`, `ReceiveLootInterest`, `GetMinorUpgradeScore`, `GetSortedResponses`, `CastVote`, `ReceiveVote`, `GetPendingLootList`, `AddToLootQueue`, `RemoveFromLootQueue`, `SetLootTransmog`
- **AwardedLoot.lua** — query per-player loot history (unchanged)
- **Sync.lua** — all inter-client communication via AceComm-3.0 over the `"PPLNDR"` prefix. Handles 15+ message types. Session teardown paths call `PP.Session:End(reason, id, gk)`.
- **Trade.lua** — hooks the trade window to auto-populate pending deliveries (unchanged; accesses `PP.pendingTrades` directly since it predates the repo layer)

### Commands (`Commands/`)

Slash dispatch uses a registration table. Each file inserts a handler function into `PP._commandGroups`. `main.lua:SlashCommand()` iterates them and stops at the first truthy return.

- **DevCommands.lua** — `help`, `loot`/`l`, `response`/`r`, `version`/`v`, `sandbox`/`s`, `sandbox mod`/`s m`, `setrank N`, `bagdebug`, `status`
- **SessionCommands.lua** — `session`, `session new [name]`, `session end`
- **RosterCommands.lua** — `roster add <name>`, `roster remove <name>`, `roster clear`, `roster randomize`

### UI (`UI/`)

- **MainWindow.lua** — Three-tab window: Roster (view/edit scores), Raids (history), Settings. All guild data access via `PP.Repo.Roster:*`. Uses lib-st (ScrollTable) for tabular data.
- **MinimapIcon.lua** — Registers LibDataBroker-1.1 data object and LibDBIcon-1.0 minimap button. `PP:SetupMinimapIcon()` called from `OnInitialize`. Left-click toggles the main window. Custom icon: place `Media/icon.tga` (64×64 px, 32-bit Targa with alpha) in the addon root; otherwise the texture path must be updated in `UI/MinimapIcon.lua` if you want a different icon.
- **LootWindow.lua** — Two distinct windows: *Loot Master Window* (`/pp loot`) and *Response Popup* (shown to all raid members). All loot state via `PP.Repo.Loot:*`.
- **AwardedLootWindow.lua** — Per-player loot history popup, opened from the Roster tab
- **VersionCheckWindow.lua** — Query and display addon versions of all raid members

The `Media/` directory holds addon artwork. `Media/icon.tga` is the minimap button icon (64×64 px Targa, 32-bit with alpha). WoW texture path: `"Interface\\AddOns\\PiratesPlunder\\Media\\icon"` (no extension in path strings).

### Key Runtime State

The following tables live on the addon object and are the backing store for the Repository layer:

```lua
PP.pendingLoot     -- active loot postings: key → {itemLink, responses, ...}
PP.pendingTrades   -- items waiting to be traded to winners
PP.lootQueue       -- items staged but not yet posted
PP.lootPopups      -- per-item response popup frames
```

Access these through `PP.Repo.Loot:*` except in `Trade.lua` and `ResetAddon()`.

### Sync Protocol

`Sync.lua` is the communication backbone. All messages use AceComm-3.0 (`RegisterComm("PPLNDR")`). Data is serialized with AceSerializer-3.0. Messages are broadcast to RAID/PARTY or whispered for point-to-point sync. The wire protocol (`PP.MSG` constants and payload shapes) must not change — it affects cross-version interop.

### Officer Detection

`main.lua:IsOfficer()` uses a multi-API fallback chain: `C_GuildInfo.IsGuildOfficer()` → `CanUseGuildOfficerChat()` → `GuildControlGetRankFlags()` → rank index threshold (configurable via `/pp setrank N`).

## Slash Commands

| Command | Action |
|---|---|
| `/pp` | Toggle main window |
| `/pp loot` / `/pp l` | Toggle loot-master window |
| `/pp response` / `/pp r` | Toggle loot response frame |
| `/pp version` / `/pp v` | Version check window |
| `/pp sandbox` / `/pp s` | Toggle sandbox mode (in-memory test data) |
| `/pp sandbox mod` / `/pp s m` | Toggle CanModify override in sandbox |
| `/pp session` | Show current session status |
| `/pp session new [name]` | Create a new session |
| `/pp session end` | End the active session |
| `/pp roster add/remove/clear/randomize` | Roster management |
| `/pp status` | Officer detection diagnostics |
| `/pp bagdebug` | Diagnose alt+right-click bag hook |
| `/pp setrank N` | Set officer rank threshold |

## Loot Response Types

`NEED` → character needs it | `MINOR` → minor upgrade | `TRANSMOG` → cosmetic | `PASS` → no interest

Points are deducted from the winner's score on award. MINOR responses cost extra points relative to NEED.
