# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pirates Plunder is a World of Warcraft AddOn for guild-based loot distribution during raids. It is written in Lua using the Ace3 addon framework. There is no build or compilation step — changes take effect by reloading the UI in WoW (`/reload`).

## No Build/Test Commands

This is a native WoW addon. There are no build, lint, or test commands. The `.pkgmeta` file configures packaging for CurseForge/WoWInterface release tooling, but development is done by editing Lua files directly and testing in-game.

The sandbox mode (`/pp sandbox`) provides an in-game testing environment with fake data — no persistent changes are made while it's active.

## Architecture

### Entry Point & Load Order

Defined in `PiratesPlunder.toc`. Load order:
1. `embeds.xml` — initializes all bundled Ace3 libraries
2. `main.lua` — core addon object, database schema, utilities
3. `Modules/*.lua` — game logic modules
4. `UI/*.lua` — UI windows

The addon object (`PiratesPlunder`) is an AceAddon-3.0 mixin. All modules and UI files access the addon via the global `PiratesPlunder` variable, which is set at the top of `main.lua`.

### Database Schema (`main.lua`)

Persistent data lives in `PiratesPlunderDB` (AceDB-3.0, global scope). The top-level key structure:

```
guilds[guildKey] = {
  roster: {},         -- player records with scores
  rosterVersion: int, -- incremented on every roster change for sync
  raids: {},          -- raid records keyed by raidID
  activeRaidID: str,
  deletedRaids: {}    -- tombstone set to prevent re-syncing deletions
}
pendingLootCache: {}  -- survives UI reloads
```

Guild keys: real guild names use the guild name as key; unguilded/custom rosters use `__custom__:Name`.

### Modules (`Modules/`)

Each module file calls `PiratesPlunder:GetModule("ModuleName")` — they are registered as AceAddon sub-modules.

- **Roster.lua** — Add/remove players, set scores, auto-populate from raid members, rotation/randomize scoring
- **Raid.lua** — Create/end raids, track boss kills, record item awards
- **Loot.lua** — Post items for bidding, handle responses (NEED/MINOR/TRANSMOG/PASS), award loot with point deduction, item comparison data
- **AwardedLoot.lua** — Query per-player loot history by scanning raid records
- **Sync.lua** — All inter-client communication via AceComm-3.0 over the `"PPLNDR"` prefix. Handles 15+ message types for roster/raid/loot state synchronization across raid members
- **Trade.lua** — Hooks the trade window to auto-populate items pending delivery to the winner

### UI (`UI/`)

- **MainWindow.lua** — Three-tab window: Roster (view/edit scores), Raids (history), Settings (guild/roster config). Uses lib-st (ScrollTable) for tabular data.
- **LootWindow.lua** — Two distinct windows sharing this file:
  - *Loot Master Window* (`/pp loot`): post items from a queue, view responses, award loot
  - *Response Popup*: shown to all raid members when loot is posted; one row per pending item with NEED/MINOR/TRANSMOG/PASS buttons
- **AwardedLootWindow.lua** — Per-player loot history popup, opened from the Roster tab
- **VersionCheckWindow.lua** — Query and display addon versions of all raid members

### Key Runtime State (`main.lua` globals on the addon object)

```lua
PiratesPlunder.pendingLoot     -- active loot postings: key → {itemLink, responses, ...}
PiratesPlunder.pendingTrades   -- items waiting to be traded to winners
PiratesPlunder.lootQueue       -- items staged but not yet posted
PiratesPlunder.lootPopups      -- per-item response popup frames
```

### Sync Protocol

Sync.lua is the communication backbone. All messages use AceComm-3.0 (`RegisterComm("PPLNDR")`). Data is serialized with AceSerializer-3.0. Messages are broadcast to RAID/PARTY or whispered for point-to-point sync. When a new player joins the raid, `SYNC_REQUEST` triggers a full state transfer from the loot master.

### Officer Detection

`main.lua:IsOfficer()` uses a multi-API fallback chain: `C_GuildInfo.IsGuildOfficer()` → `CanUseGuildOfficerChat()` → `GuildControlGetRankFlags()` → rank index threshold (configurable via `/pp setrank N`).

## Slash Commands

| Command | Action |
|---|---|
| `/pp` | Toggle main window |
| `/pp loot` / `/pp l` | Toggle loot-master window |
| `/pp version` / `/pp v` | Version check window |
| `/pp sandbox` / `/pp s` | Toggle sandbox mode (in-memory test data) |
| `/pp sandbox mod` / `/pp s m` | Toggle CanModify override in sandbox |
| `/pp status` | Show officer detection diagnostics |
| `/pp bagdebug` | Diagnose alt+right-click bag hook |
| `/pp setrank N` | Set officer rank threshold |

## Loot Response Types

`NEED` → character needs it | `MINOR` → minor upgrade | `TRANSMOG` → cosmetic | `PASS` → no interest

Points are deducted from the winner's score on award. MINOR responses cost extra points relative to NEED.
