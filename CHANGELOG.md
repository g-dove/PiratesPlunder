# Pirates Plunder – Changelog

## 0.2.1 (2026-03-15)

### Fixed
- Equipped item icons/ilvl diffs in loot master window now appear immediately when a player responds, without requiring the officer to cast a vote first (deferred refresh fires once item cache is populated).
- Loot response frame width now correctly accounts for transmog being enabled by the raid leader even when the local player has it disabled.
- Rows with no equipped item comparison data no longer expand to an unusually tall height in the loot master window.
- "Continue Raid" popup now correctly shows when the raid leader passes lead to another player (not only when they leave the group).
- Players leaving the raid group now have the active raid correctly marked as ended in their UI.
- Raid leader leaving the group no longer broadcasts a `RAID_CLOSE` that can't be received; remaining members instead receive a `GROUP_ROSTER_UPDATE` and are offered the continuation prompt.
- Foreign guild keys received via full sync no longer get auto-created in the local database.
- Vote button is now available to the loot poster as well as observers.
- Tooltip in the loot master window now only appears when hovering over the item name in the heading, not the entire group frame.
- "Clear" (per-row) and "Clear All Trades" button widths corrected in the pending trades section.
- Arrow character in pending trades list replaced with `->` (WoW font compatible).
- Reopen loot window button label now uses `>>` instead of a Unicode triangle (WoW font compatible).

### Added
- **Manage Guild Rosters** section in the Settings tab — locally delete any guild roster record from your client without syncing the deletion to other players.

---

## 0.2.0

### Added
- Loot distribution system: post items, collect Need / Minor Upgrade / Transmog / Pass responses, view equipped-item comparisons with ilvl diffs, award items and track pending trades.
- Loot master window (`/pploot`, `/ppl`) restricted to officers and the raid leader.
- Loot response popup shown to all raid members when an item is posted.
- Vote system: officers and the raid leader can vote to suggest a recipient; vote tallies shown in the loot master window.
- Full real-time sync of loot state across all addon users via AceComm.
- Transmog roll option toggle (global setting, synced by the raid leader).
- Auto-pass Epic+ in-game loot rolls for non-leaders (toggled by raid leader, synced on enable).
- Pending trades list in the loot master window.
- Loot queue: stage multiple items before broadcasting; Alt+right-click bag items to add them.
- Version check window (`/pp version`) — broadcasts to the raid and collects replies.

### Changed
- Roster auto-populate now only runs when a raid is explicitly created via the addon, not on every group roster update.

---

## 0.1.0

### Added
- Initial release.
- Guild roster management with point scoring.
- Raid creation, tracking (boss kills, loot awards), and history.
- Officer / raid leader permission system.
- Full data sync via AceComm on group join.
- Sandbox mode for testing without a live group (`/pp sandbox`).
- Custom roster support (non-guild named rosters).
- AceDB-3.0 persistent storage with per-guild data isolation.
