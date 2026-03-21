# Changelog

## [0.2.3] - 2026-03-21
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
