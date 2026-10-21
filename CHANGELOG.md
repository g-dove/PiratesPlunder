# Changelog

## [1.0.7] - 2026-10-21

### Added
- Session loot history: `/pp history` (`/pp h`) opens a list of every item awarded in the active session (officers and raid leader only) with winner, response, and cost. **View** opens the responses captured for that item — score, roll, response, equipped ilvl, votes — in the same layout as the Loot Master window.
- Loot reassign: from the history detail view the raid leader can **Award** / **Free** the item to a different responder (`PP.Loot:Reassign`). The previous winner is refunded what they spent onto their current score; the new winner is charged from their current score using the response they gave. Raid chat announces the refund plus the usual award message. The pending trade moves to the new winner; if the item has already left pending trades, a confirm popup (`PP_CONFIRM_REASSIGN_TRADED`) warns it may already have been traded.
- `LOOT_REASSIGN` message (`"LOT_RSN"`, NORMAL priority, additive): accepted only from the current raid leader. Receivers set both scores, rewrite the `session.items` record (new `reassignedFrom` field), update their history entry, and advance `rosterVersion`. Older clients ignore it and catch up on the next version gap.
- `PP.lootHistory` runtime table + `lootHistoryCache` saved variable: history survives `/reload` while its session is still active, and is wiped when the session ends or a new one is created.
- `PP.Repo.Loot` history accessors (`GetHistory`, `GetHistoryEntry`, `SetHistoryEntry`, `WipeHistory`, `RestoreHistory`) and pending-trade helpers (`RemovePendingTradeFor`, `HasPendingTradeFor`). `PP.Session:UpdateItemAward` for rewriting an award record.
- Loot Master window: red "(N not responded)" warning next to an item's name while raid members still haven't responded.
- Sandbox testing: posting an item makes the fake roster members respond at random after a short delay, all fake members count as raid members, raid announcements print locally, and pending trades get a **Sim Trade** button — award, reassign, and trade flows can be tested solo.

### Changed
- Award cost rules extracted to `PP.Loot:_ChargeWinner`, shared by `Award` and `Reassign`.
- Loot response table rendering extracted to `PP.LootUI.DrawResponseRows`, shared by the Loot Master window and the history detail view. `PP:SortResponses(entry)` added alongside `GetSortedResponses(key)`.
- `LOOT_AWARD` roster-version handling moved into `PP:_applyRosterVersion`; raid-leader sender check available as `PP:_isSenderRaidLeader`.

## [1.0.6] - 2026-10-14

### Changed
- Interface version list updated to `120100, 120105` (drops `120000`, `120001`, `120005`).

## [1.0.5] - 2026-10-07

### Added
- Stale session sweep (`PP.Session:SweepStale`): at login, ends active sessions under every roster that aren't grouped or are older than `PP.SESSION_MAX_AGE` (16 h); on every grouped `GROUP_ROSTER_UPDATE`, ends sessions whose leader isn't in our group. `PP.Session:EndStale` routes the selected roster through `End()` and only tears down records for other rosters.
- Orphan cleanup (`PP.Session:CloseOrphans`): closes any session record still flagged `active` that isn't the roster's current session. Runs for every roster at login and after `SYNC_FULL` / `SESSION_SYNC_REPLY` merges. New `ORPHAN_CLEANUP` end reason.
- `PP.SESSION_END_SOFT`: marks locally-inferred end reasons (`LEFT_GROUP`, `LEADER_LEFT`, `STARTUP_CHECK`, `ORPHAN_CLEANUP`). A session dropped this way can be re-adopted from the leader at an equal `activeSessionVersion`.
- `PP.Session:IsLeaderInGroup`: returns nil when group names haven't loaded so callers only act on a definite `false`.
- `PP:GetUnitFullName(unit)`: resolves a unit's real Name-Realm by GUID, then raid roster, then `UnitName`. Disguises (toys, costumes, quest illusions) no longer produce the wrong name for the player, roster auto-populate, or trade partner.

### Changed
- Only the raid leader can create a session (the create broadcast is leader-gated, so a non-leader officer's session was invisible to everyone else).
- `activeSessionVersion` advances only on changes the raid hears about (leader create, announced close, delete). Local-only ends (left group, startup check, sync teardown) no longer bump it, which had let receivers drift ahead of the leader and reject its broadcasts as stale. One-time migration (`migrated_session_version_reset`) resets every roster's counter to 0.
- `ClearActiveSessionID(gk, keepVersion)` can clear the pointer without advancing the version.
- Leaving a group: the 30 s pending session end is cancelled only by rejoining a group that contains the session leader; joining any other group (dungeon party, LFR) lets it run. The pending end now targets its own roster even if joining another raid switched the selected roster.
- `HandleSessionSyncReply` picks up leader hand-offs that happened while offline. `HandleSessionClose` marks the record `SYNC_RECEIVED` (so it can't be re-adopted) and takes the leader's post-close version.
- `_ensureSessionRecord` installs a record as active only when it matches the current session pointer.
- `.idea` added to `.pkgmeta` ignore list.

### Fixed
- Closing a Kit window by any means (e.g. Escape) now runs its close handler, not just the close button.
- Reopening the main window rebuilds its tab lists instead of reusing stale references.

## [1.0.0] - 2026-08-15

### Changed
- Entire UI layer rebuilt on the new Kit widget system: main window (Roster / Sessions / Settings tabs), Loot Master window, Awarded Loot window, Version Check window, minimap icon.
- ChatThrottleLib bumped 29 → 31.
- `CanViewLootMaster()` no longer falls back to a blanket `IsOfficerOrHigher()` check — visibility now strictly follows `CanPostLoot()` (previously could leak loot-master visibility to officers of a different guild during someone else's active session).
- `PP.Session:Delete` permission check switched from a raw `IsOfficerOrHigher()` to `CanModify()`, matching every other guarded action (also fixes sandbox-mode session delete, which the raw check never special-cased).
- Interface version list gains `120100` (client patch 12.1.0).

### Removed
- Custom (non-guild) roster support entirely: `IsCustomRoster`, `CreateCustomRoster`, `RenameCustomRoster`, `DeleteCustomRoster`, `FindCustomRosterWithActiveRaid`, the "New Roster" / "Manage Custom Rosters" UI, and their `StaticPopupDialogs`. `CanModify` / `CanPostLoot` simplified back to guild-only logic.
- AceGUI-3.0 (+ SharedMediaWidgets), AceConfig-3.0 (+ Cmd/Dialog/Registry), AceDBOptions-3.0, AceLocale-3.0, AceTab-3.0, AceBucket-3.0, lib-st, LibDialog-1.0, LibSharedMedia-3.0, MSA-DropDownMenu-1.0 — unused by the new UI.


## [0.6.0] - 2026-04-30
### Added
- `SESSION_SYNC_REQUEST` / `SESSION_SYNC_REPLY` (`PP:RequestSessionSync`, `PP:HandleSessionSyncRequest`, `PP:HandleSessionSyncReply`): leader-only, narrow alternative to `SYNC_REQUEST` / `SYNC_FULL`. Reply carries the active guild's roster, the active session record, in-flight `pendingLoot`, and `_completedLootKeys`. Broadcast-only with a 5 s cooldown so concurrent requesters from the same burst are coalesced into a single broadcast. `SESSION_SYNC_REPLY` ships at `BULK` priority.
- `PP:_ensureSessionRecord(guildKey, sessionID, sessionData)`: installs a minimal session shell when the local record is missing. Used by `HandleSessionCreate`, `HandleLootPost`, `HandleLootAward`, and the new `HandleSessionSyncReply`.
- `LOOT_POST` and `LOOT_AWARD` payloads now carry a minimal `session` field (`{ name, startTime, leader, guildKey }`) so receivers who missed `SESSION_CREATE` can install a record before showing the response popup or recording an award.

### Changed
- All internal `RequestSync` callers swapped to `RequestSessionSync` (`_ScheduleJoinSync`, `CompletePendingSessionEnd`, `OnGuildRosterUpdate`, `OnPlayerEnteringWorld` ungrouped path, `HandleSessionCreate` fresh-roster trigger, and the `LOOT_AWARD` version-gap recovery in `HandleLootAward`). The Settings-tab "Request Sync" button still calls `RequestSync` / `SYNC_FULL` as the manual escape hatch for a multi-guild dump.
- `HandleLootPost` gates the response popup behind `_ensureSessionRecord`. If the receiver missed `SESSION_CREATE` and the sender did not carry the `session` field (old client), the post is dropped and a `RequestSessionSync` is issued; the leader's reply repopulates `pendingLoot`.
- `HandleLootAward` invokes `_ensureSessionRecord` before `RecordItemAward`. If installation fails, the score change still applies (roster is independent) but the item is not recorded into a phantom session and a `RequestSessionSync` is issued.

### Removed
- `ComputeRosterHash` and the `PP.ComputeRosterHash` export. Roster broadcasts ship the full table on every mutation alongside a strictly-monotonic `rosterVersion`; equal versions imply equal state.
- `hash` field on `ROSTER_UPDATE` and `SYNC_REQUEST` payloads, `rosterHash` on `LOOT_AWARD` and `GROUP_SCORE`.
- `_groupScoreHashes` cache and the `GROUP_SCORE_ACK` round-trip (`PP.MSG.GROUP_SCORE_ACK`, `HandleGroupScoreAck`). `GROUP_SCORE` itself stays — only the per-receiver acknowledgement dies. **Wire-breaking:** clients on older versions still send `GROUP_SCORE_ACK`, which new clients silently ignore (no dispatch branch).
- Hash-mismatch recovery branches in `HandleRosterUpdate` and `HandleLootAward`. Version-gap detection on `LOOT_AWARD` is retained and now triggers `RequestSessionSync`.
- "Roster hash:" line from the `/pp` Settings status panel.

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
