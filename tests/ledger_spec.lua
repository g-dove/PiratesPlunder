-- Offline checks for Repository/LedgerRepository.lua (the pure part).
-- Run from the addon root with any Lua 5.1+ interpreter:
--   lua tests/ledger_spec.lua

local PP = {}
LibStub = function() return { GetAddon = function() return PP end } end
dofile("Repository/LedgerRepository.lua")
local L = PP.Repo.Ledger

local passed, failed = 0, 0
local function check(name, cond)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name)
    end
end

-- Deep copy, so each merge order starts from identical replicas.
local function clone(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = clone(v) end
    return out
end

local function scores(ledger)
    local s = L:Derive(ledger)
    return s
end

local function sameScores(a, b)
    local sa, sb = scores(a), scores(b)
    for k, v in pairs(sa) do if sb[k] ~= v then return false end end
    for k, v in pairs(sb) do if sa[k] ~= v then return false end end
    return true
end

-- Two officers starting from the same seed.
local function pair(seedScores)
    local a = L:New("A#1", 10, seedScores)
    local b = clone(a)
    b.self = "B#1"
    return a, b
end

---------------------------------------------------------------------------
-- Concurrent deltas both survive (the 105-vs-97 case)
---------------------------------------------------------------------------
do
    local a, b = pair({ Bob = 100 })
    L:Adjust(a, { Bob = 5 })
    L:Adjust(b, { Bob = -3 })
    local ab, ba = clone(a), clone(b)
    L:Merge(ab, b)
    L:Merge(ba, a)
    check("concurrent deltas sum", scores(ab).Bob == 102)
    check("merge is commutative", sameScores(ab, ba))
    local again = clone(ab)
    check("merge is idempotent (no change)", L:Merge(again, b) == false)
    check("merge is idempotent (same scores)", sameScores(again, ab))
end

---------------------------------------------------------------------------
-- SetTo is a delta: a concurrent edit lands on top
---------------------------------------------------------------------------
do
    local a, b = pair({ Bob = 100 })
    L:SetTo(a, { Bob = 0 })      -- leader awards NEED
    L:Adjust(b, { Bob = 2 })     -- officer bonus the leader hasn't seen
    L:Merge(a, b)
    check("SetTo + concurrent delta", scores(a).Bob == 2)
end

---------------------------------------------------------------------------
-- Reset cancels what it saw, keeps what it didn't
---------------------------------------------------------------------------
do
    local a, b = pair({ Bob = 100 })
    L:Adjust(a, { Bob = 5 })
    L:Merge(b, a)                -- B has seen A's +5
    L:Reset(b, { Bob = { base = 50 } })
    L:Adjust(a, { Bob = 1 })     -- A, concurrently, +1 more
    local ab, ba = clone(a), clone(b)
    L:Merge(ab, b)
    L:Merge(ba, a)
    check("reset keeps unseen delta", scores(ab).Bob == 51)
    check("reset merge commutative", sameScores(ab, ba))
end

---------------------------------------------------------------------------
-- Concurrent resets: one wins deterministically
---------------------------------------------------------------------------
do
    local a, b = pair({ Bob = 100 })
    L:Reset(a, { Bob = { base = 10 } })
    L:Reset(b, { Bob = { base = 20 } })
    local ab, ba = clone(a), clone(b)
    L:Merge(ab, b)
    L:Merge(ba, a)
    check("concurrent resets converge", sameScores(ab, ba))
    check("tie broken by author", scores(ab).Bob == 20)
end

---------------------------------------------------------------------------
-- Remove, re-add, and Clear
---------------------------------------------------------------------------
do
    local a = L:New("A#1", 0, { Bob = 7, Ann = 3 })
    L:Reset(a, { Bob = { rm = true } })
    check("removed player hidden", scores(a).Bob == nil)
    L:Reset(a, { Bob = { base = 0 } })
    check("re-added player starts at base", scores(a).Bob == 0)
    L:Reset(a, { Bob = { rm = true }, Ann = { rm = true } })
    check("clear hides everyone", next(scores(a)) == nil)
end

---------------------------------------------------------------------------
-- Clamp applies to display only; SetTo targets the raw value
---------------------------------------------------------------------------
do
    local a = L:New("A#1", 0, { Bob = 0 })
    L:Adjust(a, { Bob = -3 })
    check("display clamps at 0", scores(a).Bob == 0)
    L:SetTo(a, { Bob = 5 })
    check("SetTo reaches target from below 0", scores(a).Bob == 5)
end

---------------------------------------------------------------------------
-- Events: same event from two officers counts once
---------------------------------------------------------------------------
do
    local a, b = pair({ Bob = 40 })
    check("event recorded", L:AddEvent(a, "award:k1", { Bob = -40 }) == true)
    check("event not re-recorded", L:AddEvent(a, "award:k1", { Bob = -40 }) == false)
    L:AddEvent(b, "award:k1", { Bob = -40 })
    L:Merge(a, b)
    check("shared event counted once", scores(a).Bob == 0)
end

---------------------------------------------------------------------------
-- Joins from a non-ledger leader lose to an officer's removal
---------------------------------------------------------------------------
do
    local a, b = pair({ Bob = 5 })
    L:Reset(a, { Bob = { rm = true } })
    L:AddJoin(b, "Cal")
    check("join adds a new player", scores(b).Cal == 0)
    check("join ignores visible player", L:AddJoin(b, "Bob") == false)
    local ab, ba = clone(a), clone(b)
    L:Merge(ab, b)
    L:Merge(ba, a)
    check("removal beats nothing / join converges", sameScores(ab, ba))
    check("removal stands after merge", scores(ab).Bob == nil)
end

---------------------------------------------------------------------------
-- Wiped install comes back as a new author; old edits survive
---------------------------------------------------------------------------
do
    local a, b = pair({ Bob = 10 })
    L:Adjust(a, { Bob = 5 })
    L:Merge(b, a)
    local wiped = L:New("A#2", 10, { Bob = 10 })   -- A after losing SavedVariables
    L:Adjust(wiped, { Bob = 1 })
    L:Merge(b, wiped)
    check("new incarnation adds, old kept", scores(b).Bob == 16)
end

---------------------------------------------------------------------------
-- Seed: higher legacy version wins
---------------------------------------------------------------------------
do
    local a = L:New("A#1", 30, { Bob = 1 })
    local b = L:New("B#1", 50, { Bob = 9 })
    local ab, ba = clone(a), clone(b)
    L:Merge(ab, b)
    L:Merge(ba, a)
    check("seed picks higher version", scores(ab).Bob == 9)
    check("seed merge commutative", sameScores(ab, ba))
end

---------------------------------------------------------------------------
-- Derived version: +1 per change, equal for equal ledgers
---------------------------------------------------------------------------
do
    local a = L:New("A#1", 7, { Bob = 1 })
    local _, v0 = L:Derive(a)
    check("version offset", v0 == L.VERSION_OFFSET + 7)
    L:Adjust(a, { Bob = 1 })
    local _, v1 = L:Derive(a)
    check("one change = +1", v1 == v0 + 1)
    L:Touch(a)
    local _, v2 = L:Derive(a)
    check("touch = +1", v2 == v1 + 1)
    local b = clone(a); b.self = "B#1"
    local _, va = L:Derive(a)
    local _, vb = L:Derive(b)
    check("same ledger, same version", va == vb)
end

---------------------------------------------------------------------------
-- Summaries: equal ledgers agree, a single missed update is detected
---------------------------------------------------------------------------
do
    local a, b = pair({ Bob = 10, Ann = 10 })
    check("fresh pair summaries equal", L:SummariesEqual(L:Summary(a), L:Summary(b)))
    L:Adjust(a, { Bob = 1 })            -- seq 1
    L:Adjust(a, { Ann = 1 })            -- seq 2
    -- B receives only the second change (missed seq 1 for Bob).
    L:Merge(b, L:ExtractOps(a, { Ann = true }))
    check("same max seq", b.seq["A#1"] == a.seq["A#1"])
    check("missed update detected", not L:SummariesEqual(L:Summary(a), L:Summary(b)))
    L:Merge(b, a)
    check("full merge equalises summaries", L:SummariesEqual(L:Summary(a), L:Summary(b)))
end

---------------------------------------------------------------------------
-- ExtractOps carries only the author's own entries
---------------------------------------------------------------------------
do
    local a, b = pair({ Bob = 10 })
    L:Adjust(b, { Bob = 2 })
    L:Merge(a, b)
    L:Adjust(a, { Bob = 3 })
    local ops = L:ExtractOps(a, { Bob = true })
    check("ops has own entry", ops.players.Bob.c["A#1"].d == 3)
    check("ops omits others' entries", ops.players.Bob.c["B#1"] == nil)
    check("ops is well-formed partial", L:IsWellFormed(ops, true))
    L:Merge(b, ops)
    check("ops merge applies", scores(b).Bob == 15)
end

---------------------------------------------------------------------------
-- Shape check rejects malformed payloads
---------------------------------------------------------------------------
do
    local a = L:New("A#1", 0, { Bob = 1 })
    check("full ledger well-formed", L:IsWellFormed(a))
    check("non-table rejected", not L:IsWellFormed("x"))
    local bad = clone(a); bad.schema = 99
    check("wrong schema rejected", not L:IsWellFormed(bad))
    local bad2 = clone(a); bad2.players.Bob = { c = { X = { d = "1", s = 1 } } }
    check("bad entry rejected", not L:IsWellFormed(bad2))
end

---------------------------------------------------------------------------
-- Delta STATE: only differing authors travel, and that is enough
---------------------------------------------------------------------------
do
    local a, b = pair({ Bob = 10, Ann = 10 })
    L:Adjust(a, { Bob = 1 })
    L:Adjust(b, { Ann = 2 })
    L:Merge(a, b)                        -- A now has both authors
    L:Adjust(a, { Bob = 4 })             -- B lacks this A change
    local diff, seedDiff = L:DiffAuthors(L:Summary(a), L:Summary(b))
    check("diff names only the stale author", diff["A#1"] and not diff["B#1"])
    check("seed same", seedDiff == false)
    local delta = L:ExtractAuthors(a, diff, seedDiff)
    check("delta omits other authors", delta.players.Ann == nil or delta.players.Ann.c["B#1"] == nil)
    check("delta is well-formed partial", L:IsWellFormed(delta, true))
    L:Merge(b, delta)
    check("delta brings B level", L:SummariesEqual(L:Summary(a), L:Summary(b)))
    check("delta scores match", sameScores(a, b))
end

do
    local a = L:New("A#1", 30, { Bob = 1 })
    local b = L:New("B#1", 50, { Bob = 9 })
    local _, seedDiff = L:DiffAuthors(L:Summary(b), L:Summary(a))
    check("seed difference detected", seedDiff == true)
    local delta = L:ExtractAuthors(b, {}, true)
    check("seed-only delta well-formed", L:IsWellFormed(delta, true))
    L:Merge(a, delta)
    check("seed delta applies", scores(a).Bob == 9)
    local bad = { seq = {}, players = {}, seed = { v = "x" } }
    check("bad partial seed rejected", not L:IsWellFormed(bad, true))
    check("summary shape ok", L:IsSummary(L:Summary(a)))
    check("summary shape bad", not L:IsSummary({ seed = 1, seq = {}, sum = {} }))
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
