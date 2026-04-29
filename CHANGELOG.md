# Changelog

## [0.5.1] - 2026-04-28
### Added
- Roster snapshots: end-of-session standings frozen per session. Captured locally by every client on `PP.Session:End()` (skipped for `RESET` and `SYNC_DELETE`); shipped inline on `SESSION_CLOSE`; backfilled on demand via `SNAPSHOT_REQUEST` / `SNAPSHOT_REPLY` (BULK priority). `sessionSnapshots` table added to `guilds[guildKey]` schema (auto-backfilled by `EnsureData`). Arbitration by `rosterVersion` — newest wins.
- New `PP.Repo.Roster` methods: `GetSessionSnapshot`, `SetSessionSnapshot`, `BuildRosterSnapshot`, `GetAllSnapshotVersions`.
- Roster snapshot UI: "View Roster Snapshot" button on ended-session detail view; popup window lists frozen standings sorted by score. "Fetch Session Snapshots" button in the Settings tab triggers a group-wide backfill (5 s cooldown).
- `LOOT_CLEAR` message type: raid leader broadcasts after 60 s of an empty queue. Receivers wipe their loot display and mark the cleared keys as completed so late `LOOT_POST` messages cannot re-pop them. Idle timer cancels on new posts and on session end/create.
- `PP:LocalClearLoot()` and `/pp loot clear` (`/pp l clear`): wipes pending loot for this client only, no broadcast. Settings tab gains a "Clear My Loot Display" button.
- `PARTY_LEADER_CHANGED` handler (`OnPartyLeaderChanged`): hands off the idle-clear timer when leadership transfers.
- Bounded post-join sync retry (`_ScheduleJoinSync`): up to 3 attempts (3 s, then 9 s, then 15 s) issuing `RequestSync`; stops once an active session is adopted, the group is left, or no other PP users are present.
- `_completedLootKeys` runtime table tracks cleared/awarded/cancelled loot keys to suppress late re-posts.

### Changed
- Reliable broadcast simplified: per-member whisper retry loop removed. `BroadcastCritical` now broadcasts once and relies on the `ACK` hash check to detect divergence — any mismatch schedules a single `SendFullSync`. `_criticalAckSnapshots` entries auto-expire after 30 s.
- Message priority dropped from `ALERT` to `NORMAL` for loot/session/sync traffic. `LOOT_STATE_QUERY`, `RAID_SETTINGS`, and the new `SNAPSHOT_*` messages remain at `BULK`.
- `LOOT_AWARD` payload now carries `rosterVersion` and `rosterHash` — receivers update score, advance `rosterVersion`, and verify the hash from a single message. Separate `ROSTER_DELTA` on award removed; gap detection requests a full sync.
- `ROSTER_DELTA` requires sequential version application; any gap (`incoming != local + 1`) triggers `RequestSync`.
- `LOOT_CANCEL` payload now includes `guildKey` so the ACK hash compares against the same roster on every client.
- `BroadcastSessionCreate` payload reduced to `{name, startTime}` — recipients reconstruct the session shell locally.
- `HandleSyncRequest` responds using the responder's own active guild key (no longer filters by requester guild match) so a joining player with a stale `_activeGuildKey` is not ignored by every officer.
- `SendFullSync(guildKey, target)`: targeted whispers bypass the broadcast cooldown.
- `HandleSyncFull` only auto-creates foreign guild records when the message is a whispered reply received within 15 s of our own `RequestSync` and the sender is currently in our group.
- `HandleSyncFull` ends a local stale session when the sender authoritatively cleared theirs at a newer `activeSessionVersion`.
- `PP.Session:RecordItemAward` accepts an optional `guildKey` parameter; `HandleLootAward` passes the payload's `guildKey` so receivers with a stale `_activeGuildKey` still write into the correct session.
- Default session names: when multiple sessions are created on the same day they auto-increment as `Session YYYY-MM-DD #2`, `#3`, …
- `HandleSessionCreate` rebuilds the session shell from the trimmed payload and routes via `PP.Repo.Roster:SetActiveSessionID`.

### Fixed
- Whisper-only `SYNC_FULL` and `SNAPSHOT_REPLY` no longer accepted from non-group senders or outside their request trust window — prevents arbitrary guild-key injection and snapshot-poisoning via unsolicited whispers.
- `LOOT_CLEAR` validated as raid-leader-only; pending keys are marked completed before the local wipe so a delayed `LOOT_POST` cannot re-introduce a cleared item.
- Snapshot pop-up window released on `SESSION_DELETE` so it cannot reference a deleted session.

## [0.5.0] - 2026-04-22
### Added
- Reliable broadcast (`BroadcastCritical`): initial RAID/PARTY broadcast + per-member whisper retry for critical messages (LOOT_POST, LOOT_AWARD, LOOT_CANCEL, SESSION_CREATE, SESSION_CLOSE, SESSION_DELETE, ROSTER_DELTA, GROUP_SCORE). Retries 3× with 4s delay before giving up.
- ACK message type: receivers echo back a roster hash so the sender can detect divergence and trigger a delta or full sync.
- Roster delta sync (`ROSTER_DELTA` / `BroadcastRosterDelta`): sends only changed/removed entries instead of the full roster on every update.
- Group score sync (`GROUP_SCORE` / `GROUP_SCORE_ACK`): dedicated round-trip for boss-kill point awards with per-member acknowledgement.
- Message priority system: LOOT, SESSION, and SYNC messages sent at ALERT priority; bulk sync at BULK priority.
- Handshake on group join: automatically requests a version check from all online members.
- Full sync throttle: additional full syncs are suppressed within a 10-second cooldown.
- `ComputeRosterHash`: deterministic roster hash used to detect drift without exchanging the full payload.
- `/pp debug` command: toggles sync debug output to chat (replaces `/pp bagdebug`).
- `/pp minimap` command: toggles minimap icon visibility.
- Minimap visibility checkbox in the Settings tab.
- `ShowMinimapIcon()` / `HideMinimapIcon()` methods with persistence across reloads.
- Default session names auto-increment within a day (`Session YYYY-MM-DD`, `Session YYYY-MM-DD #2`, …).
- `_ppUsers` runtime table: tracks which group members have the addon loaded.

### Changed
- All slash-command handlers consolidated into `Commands/Commands.lua` (was split across `DevCommands.lua`, `RosterCommands.lua`, `SessionCommands.lua`).
- `SendFullSync` no longer accepts a `target` parameter — full syncs always broadcast to the group.
- Loot key format changed to `itemLink:timestamp:index` for stable chronological sort across reloads.
- Loot master window width increased to 850.
- Tooltip overlay frames reused instead of recreated on each draw.

### Fixed
- Loot master window sort order: entries now sort chronologically by timestamp, with index as tiebreaker within the same second.
- Whisper reflection attack vector: the addon no longer echoes whisper-delivered messages back to the sender.
- Potential duplicate ACK keys replaced with a time-based GUID.

## [0.4.0] - 2026-03-22
### Added
- Minimap icon with LibDBIcon-1.0: left-click toggles main window, right-click opens loot master window
- Pending loot bars UI: visual progress bars for active loot postings

### Fixed
- Leader change stale raid: session now correctly reactivates on rejoin after leader swap
- Sync gating to prevent unintentional guild entry creation

## [0.3.2] - 2026-03-21
### Changed
- Clarified `GetData` vs `EnsureData` API in `PP.Repo.Roster`: `EnsureData` auto-creates the guild entry if missing; `GetData` returns nil for absent entries

### Fixed
- Added nil-guards after `GetData()` calls in Sync.lua, LootService, SessionService, and main.lua to prevent crashes when guild data is absent

## [0.3.1] - 2026-03-21
### Changed
- Sync improvements for roster and session state propagation
- Session renamed to use more descriptive identifiers

### Fixed
- Prevent auto-pass triggering when not in an active raid
- Scroll position preserved on UI redraw

## [0.3.0] - 2026-03-21
### Changed
- Refactored data access into Repository layer (PP.Repo.Roster, PP.Repo.Loot)
- Refactored business logic into Service layer (PP.Session, PP.Roster, PP.Loot)
- Session teardown consolidated into single PP.Session:End() path
- Pending trades now persist across UI reloads

### Fixed
- Spurious client-side session ends on disconnect/reconnect (disconnect recovery window)
- LEADER_LEFT session end now deferred 5 seconds to survive leader promotion windows
- CheckActiveRaid moved to fire after world load so IsInGroup() is accurate on reload
- Auto-pass epic+ setting now included in full sync payload (resilient to race with loot rolls)
- Cancel and Award loot actions now gated by CanPostLoot() permission check

## [0.2.2]
### Fixed
- Session window reopening on UI redraw
- Sync improvements for roster version propagation

## [0.2.1]
### Added
- Initial guild roster and session sync via AceComm
- Loot response system (NEED / MINOR / TRANSMOG / PASS)
- Auto-trade window population for pending deliveries

## [0.2.0]
### Added
- Initial public release
- Guild-based loot distribution with score tracking
- Sandbox mode for in-game testing
