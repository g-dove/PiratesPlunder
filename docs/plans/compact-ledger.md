# Plan: Compact Ledger Roster & Officer Sync

Status: **Phases 0–3 implemented, untested in game** (Phase 3 folding
deferred, see §11). Phases 1 and 2 must ship together. All open decisions
in §12 are settled.

## 1. Problem

Roster scores are stored as plain numbers and synced as whole tables under a
single `rosterVersion` counter, with "higher version wins".

- **Concurrent edits are lost.** Officer A awards +5 and Officer B corrects −3
  while out of sync; one table replaces the other, so Bob ends at 105 or 97
  instead of 102. The loss comes from storing *results* instead of *changes*,
  so no ordering scheme (counter, timestamp, hybrid) can fix it.
- **Counters drift.** `BumpRosterVersion` is `+1` locally on every officer,
  but `BroadcastRoster` only sends when you are raid leader in a group. Edits
  made outside a raid stay local, two officers land on the same version with
  different content, and whichever broadcasts next silently wins.
- **Officers cannot sync with each other.** Every sync path is gated on the
  raid leader:
  - `HandleSyncRequest` only answers when `IsRaidLeader()` *and*
    `gd.activeSessionID` is set — so "Request Sync" does nothing in a party,
    and nothing in a raid without a running session.
  - `IsRaidLeader()` is always false in a party (`GetMyRaidRank()` returns −1
    outside `IsInRaid()`), so "Broadcast Roster" never sends in a party.
  - The Settings text promises "from any online officer", which hasn't been
    true since replies were restricted to the leader.
- **No sender trust on roster writes.** `ROSTER_UPDATE`, `SCORE_UPDATE` and
  `GROUP_SCORE` are applied from any group member with a higher version.

## 2. Goals / non-goals

Goals
- No officer edit is ever silently lost, regardless of who was online when.
- Officers converge on the same roster without needing to be in a group.
- Raiders (non-officers) keep working with zero protocol change, including
  raiders on old addon versions.
- Recovers cleanly from a wiped SavedVariables file.

Non-goals
- Per-change audit history (compaction deliberately drops it; awarded-loot
  history and session snapshots already cover most of that need).
- Resolving genuinely contradictory *absolute* intents (two officers setting
  the same player to different values at the same moment) — that stays
  last-writer-wins, and is called out as such.

## 3. Background: why this design

This is the standard answer from replicated-data research (CRDTs):

| Data | Standard type | Used for |
|---|---|---|
| Counter that goes up and down | **PN-Counter** | scores |
| Absolute overwrite | **LWW register** | resets (Set/Clear/Randomize/Remove) |
| "What have you seen?" | **Version vector** | officer handshake |

Survey of WoW loot addons: officer-note storage (CEPGP, QDKP) and
whole-table + timestamp (MonolithDKP) both lose concurrent edits; modern
addons (Core Loot Manager, PantheonDKP) use event-sourced ledgers. A
*compacted* ledger keeps the ledger's lossless merge but stores one running
total per (player, author) instead of every entry.

## 4. Data model

### 4.1 Author identity

```
authorID = "<Name-Realm>#<incarnation>"     -- e.g. "Captain-Draenor#1767225600"
```

`incarnation` is `GetServerTime()` at the moment this install first creates
the guild's ledger, stored in `gd.ledger.self`. A wiped SavedVariables (or the
same character on a second PC) produces a **new** author instead of reusing an
old one. This matters: if a wiped client restarted its own counter at 0 under
the old ID, every peer would ignore its edits as stale. New author = new
entries, old entries untouched.

### 4.2 Per-guild ledger

```lua
gd.ledger = {
  schema = 1,
  self   = "Captain-Draenor#1767225600",  -- this install's authorID
  seq    = { [authorID] = maxSeqSeen },   -- version vector
  epoch  = 0,                             -- Lamport clock for resets
  seed   = { v = rosterVersion, a = authorID, scores = { [fullName] = n } },
  players = {
    ["Bob-Draenor"] = {
      name = "Bob", realm = "Draenor",
      reset = {               -- LWW register; nil = use seed
        e  = 12,              -- epoch (Lamport)
        a  = authorID,        -- tie-break
        s  = 41,              -- author's seq when written
        base = 0,
        bl = { [authorID] = d },  -- each author's d at reset time ("baseline")
        rm = false,           -- true = player removed
      },
      c = {                   -- PN-counter: one entry per author
        [authorID] = { d = -10, s = 44 },   -- cumulative delta, seq
      },
    },
  },
}
```

`gd.roster` stays exactly as today — `{ [fullName] = { name, realm, score } }`
— but becomes a **derived cache**, rebuilt from the ledger. The UI, loot
logic, snapshots and every raider-facing message keep reading `gd.roster`
unchanged.

### 4.3 Deriving a score

```
base     = reset and reset.base or seed.scores[name] or 0
baseline = reset and reset.bl   or {}
score    = max(0, base + Σ_author (c[author].d − (baseline[author] or 0)))
visible  = not (reset and reset.rm)
```

The `max(0, …)` clamp is applied to the derived view only; the stored deltas
are never clamped, so merging stays order-independent.

## 5. Operations

Every local mutation increments `seq[self]` by exactly 1 and stamps what it
writes with that seq.

| Today | Becomes |
|---|---|
| `SetScore(x)` | delta `x − currentScore` on own `c` entry |
| `+1` / `−1` buttons | delta ±1 |
| Boss kill `AddScoreToRaidMembers(n)` | delta `+n` per raid member on roster |
| Loot award NEED | delta `−currentScore` |
| Loot award TRANSMOG | delta `−1` (if score > 0) |
| Loot award MINOR | delta `GetMinorUpgradeScore() − currentScore` |
| `Add(name)` | reset `{ base = 0, rm = false }` (only if not visible) |
| `AutoPopulate` | reset per new player, as `Add` |
| `Remove(name)` | reset `{ base = currentScore, rm = true }` |
| `Clear()` | reset `{ rm = true }` for every player |
| `Randomize()` | reset `{ base = rank }` for every player |

Resets take `e = epoch + 1` (then `epoch = e`) and capture `bl` = every
author's current `d` for that player, so they cancel exactly what the
resetting officer had seen and nothing more.

**Semantics worth knowing:**
- Officer A gives Bob +2 while the leader, not having seen it, awards Bob a
  NEED item (−current). After merge Bob has 2. The officer's adjustment
  survives the award — intended.
- Two officers *reset* the same player concurrently (e.g. both Set via a
  Randomize) → higher `(e, a)` wins. Concurrent absolute intents genuinely
  conflict; LWW is the accepted answer there. Concurrent *deltas* never
  conflict.

## 6. Merge

Pure function, no side effects, in `Repository/LedgerRepository.lua`:

```
merge(local, incoming):
  seed:   keep higher (v, a)
  epoch:  max
  seq:    per author max
  for each player in incoming:
    reset:  keep higher (e, a)
    c:      per author keep higher s
  rebuild gd.roster for touched players
```

Properties (to be covered by the offline test script, §11): commutative,
associative, idempotent — merging in any order, any number of times, gives
the same result.

## 7. Officer sync protocol

### 7.1 Channel

`OFFICER` addon channel (`C_ChatInfo.SendAddonMessage` supports it). Only
members with officer-chat permission receive it, so:
- no group required — fixes party / no-session / out-of-raid sync;
- roster data never reaches non-officers;
- it rides the guild's existing permission model rather than our rank
  heuristics.

`SendAddonMessage` gains an explicit-distribution path for `"OFFICER"`
(today it only picks WHISPER / RAID / PARTY).

### 7.2 Trust

Accept ledger messages only when they arrive on the OFFICER distribution,
`guildKey` equals our own guild, and we keep a ledger for it ourselves. Only
members whose rank can use officer chat can send or read OFFICER addon
messages, so no separate per-sender rank lookup is done (as built). Custom
(`__custom__:`) rosters do not use officer sync (no guild channel to use).

### 7.3 Messages (additive)

| Message | When | Payload |
|---|---|---|
| `LEDGER_HELLO` | login (after guild roster loads), and when the raid leader starts a session | `{ guildKey, summary }` |
| `LEDGER_STATE` | reply to a HELLO whose summary differs from ours | `{ guildKey, ledger, summary, partial? }` (BULK) — `ledger` holds only differing authors (Phase 3); full from "Broadcast Roster" |
| `LEDGER_OPS` | after every local mutation | `{ guildKey, players = { only touched entries }, seq, epoch }` |

`summary = { [authorID] = { max = maxSeq, sum = Σ s over that author's entries } }`.
`max` alone is not enough: a client that missed one update but received a
later one from the same author has the same `max` but a lower `sum`.

**Flow**
1. Officer logs in → `LEDGER_HELLO` on OFFICER.
2. Any officer whose summary differs schedules `LEDGER_STATE` with jitter.
   STATE goes out on OFFICER, so every officer sees every reply. When a STATE
   arrives while our own reply is still scheduled, merge it first, then
   cancel our reply unless we still hold something that STATE lacked (our
   summary has an author with a higher `max` or `sum` than the STATE's). Net
   effect: one reply per officer holding *unique* data — normally exactly
   one. Two replies crossing in flight are harmless (merge is idempotent),
   just wasted bandwidth.
3. On `LEDGER_STATE` → merge. If our summary still differs from the sender's
   (we had something they lacked) → send our own STATE once (60 s cooldown).
4. Live edits → `LEDGER_OPS` immediately; gaps are healed by the next HELLO.

**Session start.** `Session:Create` sends a HELLO but does not wait for
replies — the session starts immediately. Replies to a session-start HELLO
use short jitter (0.2–1 s); a ~3 KB STATE fits inside ChatThrottleLib's burst
allowance, so the merge normally lands within 1–2 s, long before the first
loot drop. After a merge that changes the derived roster, the leader sends a
`ROSTER_UPDATE` so raiders pick it up.

Size estimate: 150 players × (reset + 3 authors) ≈ 9 KB serialized, ~3 KB
after LibDeflate — a few seconds at BULK through ChatThrottleLib.

Old clients ignore unknown message types (the dispatch is an
`if/elseif` chain with no `else`), so these are safe to add — but they are a
wire-protocol addition and need sign-off (see §12).

## 8. Raid path (raiders unchanged)

Non-officer raiders never see the ledger. They keep receiving the derived
`gd.roster` via today's messages, unchanged on the wire:

- Leader still sends `ROSTER_UPDATE`, `GROUP_SCORE`, `LOOT_AWARD.newScore`,
  `SESSION_SYNC_REPLY.roster` built from the derived roster.
- **`rosterVersion` becomes derived, not counted:**

  ```
  rosterVersion = 1000000 + Σ_author seq[author]
  ```

  Every op raises it by exactly 1, so `LOOT_AWARD`'s `== rosterVersion + 1`
  gap check keeps working. Two officers with the same ledger produce the same
  version — whichever officer leads tonight, raiders accept it. The 1e6
  offset puts it above any counter raiders hold today.
- **Trust gate added** to `ROSTER_UPDATE` / `SCORE_UPDATE` / `GROUP_SCORE`:
  apply only from the current rank-2 leader (same check `SESSION_SYNC_REPLY`
  already uses). Officers ignore these entirely once their ledger is live —
  they get everything via OFFICER.

### 8.1 Leaders without a ledger

Non-officers never keep a ledger, but a non-officer can still change scores:
a non-officer raid leader runs `AutoPopulate`, and loot awards. Ledger
officers in that raid must take those in without double counting — each
officer would otherwise turn the same message into its own delta. So they
are recorded as **event entries keyed by the event itself**, identical on
every officer:

| Message (no `ledger = true` flag) | Event entry |
|---|---|
| `LOOT_AWARD` | `award:<lootKey>` → `−pointsSpent` on the winner |
| `GROUP_SCORE` | `grp:<sender>:<version>` → `+amount` per raid member on roster |
| `ROSTER_UPDATE` | `join:<name>` → reset at epoch 0 for players we don't have (any officer reset outranks it) |

Ledger senders add `ledger = true` (additive field) to `ROSTER_UPDATE`,
`GROUP_SCORE` and `LOOT_AWARD`; ledger officers skip those, since the change
arrives through the sender's ledger (Phase 2).

## 9. Officer-sync fixes folded in

| Fix | Phase |
|---|---|
| `HandleSyncRequest`: drop the `activeSessionID` requirement — the reply is roster + history, which doesn't need a live session | 0 |
| Leader checks used by manual sync/broadcast accept party leader (`UnitIsGroupLeader("player")`) | 0 |
| Settings text: "Request a roster and session sync from the group leader." | 0 |
| Trust gate on `ROSTER_UPDATE` / `SCORE_UPDATE` / `GROUP_SCORE` | 0 |
| Officer ↔ officer sync without a group (OFFICER channel) | 2 |
| "Request Sync" for officers also sends `LEDGER_HELLO` | 2 |
| "Broadcast Roster" for officers sends `LEDGER_STATE` | 2 |
| `rosterVersion` drift between officers | 1 (derived version) |

## 10. Migration

On first load with ledger code, per real guild key:

1. Create `gd.ledger`, `self = me .. "#" .. GetServerTime()`.
2. `seed = { v = gd.rosterVersion, a = self, scores = current gd.roster }`.
3. No per-player resets; every player derives from the seed.

Officers may disagree today. Seeds merge by higher `(v, a)` — the officer
with the most legacy edits wins the starting point, once. Any officer can
correct individual players afterwards with normal ops.

Raiders: no migration — their `gd.roster` keeps working; the 1e6 offset means
the first derived `rosterVersion` they see is accepted.

## 11. Implementation phases

**Phase 0 — quick fixes (independent, ship first)** — *implemented, untested*
- §9 Phase 0 rows. Small, no data-model change.
- Also gated `SYNC_FULL` on the group leader (any whisperer could previously
  push a higher-version roster for a known guild key) and made
  `_isSenderInGroup` unit-based so it works in a party.

**Phase 1 — local ledger** — *implemented, untested*
- `Repository/LedgerRepository.lua`: storage, `Derive`, `Merge` (pure).
- `Services/RosterService.lua`: route every mutation through ledger ops;
  rebuild `gd.roster`; derived `rosterVersion`.
- `Services/LootService.lua`: award deductions as ops.
- Migration (§10).
- Leaders without a ledger (§8.1).
- Sandbox: no ledger. The sandbox key never matches the player's guild, and
  `Ensure` skips while sandbox mode is on.
- **Must ship together with Phase 2.** Ledger officers ignore legacy roster
  writes from ledger leaders; without Phase 2's officer sync those changes
  never reach them.
- `tests/ledger_spec.lua`: plain Lua 5.1 script exercising `Merge` /
  `Derive` (commutativity, idempotence, concurrent delta + reset, wiped
  author). Runnable with a standalone `lua` — the only part of the addon that
  can be tested outside the game.

**Phase 2 — officer sync** — *implemented, untested*
- `Modules/OfficerSync.lua`: HELLO / STATE / OPS, trust, jitter, cooldowns.
- `SendAddonMessage` OFFICER path.
- Settings buttons rewired for officers.
- OPS gap detection: an author seq jump sends a HELLO (30 s cooldown).
- Trust is the OFFICER distribution itself plus our own guild key; no
  per-sender rank lookup (only officer-chat members can send there).
- The WHISPER fallback for officers without officer-chat permission (§13) is
  not implemented.

**Phase 3 — hardening (optional)**
- Delta STATE (send only authors whose summary differs) — *implemented,
  untested*. A STATE answering HELLOs/STATEs carries only the authors that
  differ from the summaries it answers, plus the sender's full summary so
  listeners can decide whether to answer in turn. "Broadcast Roster" still
  sends the full ledger.
- Folding retired authors into `seed` — **deferred, not planned.** Safe
  folding needs every officer, including offline ones, to have confirmed the
  same `seq`, which the addon can't observe; folding early or twice
  double-counts or loses edits (the class of bug PantheonDKP's "squish"
  entries hit). Size doesn't call for it: entries per player = authors who
  touched that player. Revisit only if SavedVariables size becomes a
  problem.

Load order: `LedgerRepository.lua` after `RosterRepository.lua`;
`OfficerSync.lua` after `Sync.lua`. Update `.vscode/types.lua` and CLAUDE.md
with each phase.

## 12. Open decisions

1. ~~Protocol additions~~ — **approved.** Three new message types plus the
   OFFICER distribution; no existing payload changes.
2. ~~Old-version officers~~ — **all officers update before the first raid.**
   Ledger clients ignore legacy roster writes from senders who haven't sent a
   `LEDGER_HELLO`.
3. ~~Seed choice~~ — **automatic only** (highest legacy `rosterVersion`).
   Officers are expected to hold a single roster already; any stray score is
   fixed with a normal edit after migration. No override button.
4. ~~HELLO cadence~~ — **login and session start** (§7.3).

## 13. Risks

- **Score floor.** Clamp is on the derived view; a player with a large
  negative stored total needs that many positive deltas before showing above
  0. Matches today's behaviour for a single officer; noted for concurrent
  cases.
- **Officer-chat permission.** Officers who can't read officer chat won't
  receive OFFICER addon messages. Their client should fall back to
  WHISPER-based HELLO to an online officer (Phase 2 detail).
- **Growth.** Entries per player = number of authors who ever touched them;
  new incarnations add authors. Fine for years at guild scale; Phase 3
  folding exists if it ever isn't.
