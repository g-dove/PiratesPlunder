---------------------------------------------------------------------------
-- Pirates Plunder – Ledger Repository
-- Officer-side score storage that merges without losing edits: one running
-- total per (player, author) plus a last-writer-wins reset per player.
-- gd.roster is rebuilt from it and stays the shape everything else reads.
-- Design: docs/plans/compact-ledger.md
--
-- Everything above "Guild binding" is pure Lua (no WoW API) so
-- tests/ledger_spec.lua can run it outside the game.
---------------------------------------------------------------------------
---@type PPAddon
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

PP.Repo        = PP.Repo or {}
PP.Repo.Ledger = PP.Repo.Ledger or {}

local Ledger = PP.Repo.Ledger

Ledger.SCHEMA = 1
-- Raiders hold legacy rosterVersion counters far below this, so the first
-- derived version they receive from a ledger leader is accepted.
Ledger.VERSION_OFFSET = 1000000

---------------------------------------------------------------------------
-- Internals
---------------------------------------------------------------------------
local function copyMap(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

local function copyReset(r)
    if not r then return nil end
    return { e = r.e, a = r.a, s = r.s, base = r.base, rm = r.rm, bl = copyMap(r.bl) }
end

local function getPlayer(ledger, name)
    local p = ledger.players[name]
    if not p then
        p = { c = {} }
        ledger.players[name] = p
    end
    return p
end

-- Stamp for one local change: this author's next sequence number.
local function nextSeq(ledger)
    local a = ledger.self
    local s = (ledger.seq[a] or 0) + 1
    ledger.seq[a] = s
    return a, s
end

local function isVisible(ledger, p, name)
    if p and p.reset then return not p.reset.rm end
    return ledger.seed.scores[name] ~= nil
end

-- Unclamped score: base plus every author's total since the last reset.
local function rawScore(ledger, p, name)
    local base, bl
    if p and p.reset then
        base, bl = p.reset.base or 0, p.reset.bl or {}
    else
        base, bl = ledger.seed.scores[name] or 0, {}
    end
    local total = base
    if p then
        for a, entry in pairs(p.c) do
            total = total + entry.d - (bl[a] or 0)
        end
    end
    return total
end

-- true if reset x supersedes reset y: higher epoch, then author, then seq.
local function resetWins(x, y)
    if not x then return false end
    if not y then return true end
    if x.e ~= y.e then return x.e > y.e end
    if x.a ~= y.a then return x.a > y.a end
    return (x.s or 0) > (y.s or 0)
end

---------------------------------------------------------------------------
-- New(author, seedVersion, scores)
-- author: "<Name-Realm>#<incarnation>" — a fresh ID per install, so a wiped
-- SavedVariables never reuses (and gets ignored under) an old sequence.
---------------------------------------------------------------------------
function Ledger:New(author, seedVersion, scores)
    return {
        schema  = self.SCHEMA,
        self    = author,
        seq     = {},
        epoch   = 0,
        seed    = { v = seedVersion or 0, a = author, scores = copyMap(scores) },
        players = {},
    }
end

---------------------------------------------------------------------------
-- Reads
---------------------------------------------------------------------------
-- Displayed score, or nil if the player isn't on the roster.
function Ledger:Score(ledger, name)
    local p = ledger.players[name]
    if not isVisible(ledger, p, name) then return nil end
    return math.max(0, rawScore(ledger, p, name))
end

-- Unclamped score. Absolute targets are computed against this so a stored
-- total below zero can't leave the result short of the target.
function Ledger:RawScore(ledger, name)
    return rawScore(ledger, ledger.players[name], name)
end

-- Returns { [fullName] = score } for visible players, and the derived
-- rosterVersion. Each local change raises the version by exactly 1.
function Ledger:Derive(ledger)
    local scores = {}
    for name in pairs(ledger.seed.scores) do
        scores[name] = self:Score(ledger, name)
    end
    for name in pairs(ledger.players) do
        scores[name] = self:Score(ledger, name)
    end
    local version = self.VERSION_OFFSET + (ledger.seed.v or 0)
    for _, s in pairs(ledger.seq) do
        version = version + s
    end
    return scores, version
end

---------------------------------------------------------------------------
-- Local changes. Each call is one change (one sequence number).
---------------------------------------------------------------------------
-- deltas: { [fullName] = n }
function Ledger:Adjust(ledger, deltas)
    local a, s = nextSeq(ledger)
    for name, d in pairs(deltas) do
        local p = getPlayer(ledger, name)
        local entry = p.c[a]
        p.c[a] = { d = (entry and entry.d or 0) + d, s = s }
    end
end

-- targets: { [fullName] = score }. Expressed as deltas, so a concurrent edit
-- by another officer still lands on top.
function Ledger:SetTo(ledger, targets)
    local deltas = {}
    for name, target in pairs(targets) do
        deltas[name] = target - self:RawScore(ledger, name)
    end
    self:Adjust(ledger, deltas)
end

-- resets: { [fullName] = { base = n } | { rm = true } }. Cancels the totals
-- this client has seen for each player; totals it hasn't seen survive.
function Ledger:Reset(ledger, resets)
    local a, s = nextSeq(ledger)
    local e = ledger.epoch + 1
    ledger.epoch = e
    for name, r in pairs(resets) do
        local p = getPlayer(ledger, name)
        local bl = {}
        for author, entry in pairs(p.c) do bl[author] = entry.d end
        p.reset = { e = e, a = a, s = s, base = r.base or 0, rm = r.rm or nil, bl = bl }
    end
end

-- A change with no roster effect (session delete) that still has to raise
-- the version so raiders accept it.
function Ledger:Touch(ledger)
    nextSeq(ledger)
end

---------------------------------------------------------------------------
-- Ingesting changes from a leader without a ledger. The entry is keyed by
-- the event itself, so every officer who hears it writes the identical
-- entry and merging them can't double count.
---------------------------------------------------------------------------
-- Returns false if this event was already recorded.
function Ledger:AddEvent(ledger, eventID, deltas)
    if ledger.seq[eventID] then return false end
    ledger.seq[eventID] = 1
    for name, d in pairs(deltas) do
        getPlayer(ledger, name).c[eventID] = { d = d, s = 1 }
    end
    return true
end

-- A member added by a non-ledger leader. Epoch 0, so any officer's own reset
-- (e.g. a removal) outranks it. Returns false if nothing changed.
function Ledger:AddJoin(ledger, name)
    local p = ledger.players[name]
    if isVisible(ledger, p, name) or (p and p.reset) then return false end
    local eventID = "join:" .. name
    if ledger.seq[eventID] then return false end
    ledger.seq[eventID] = 1
    getPlayer(ledger, name).reset = { e = 0, a = eventID, s = 1, base = 0, bl = {} }
    return true
end

---------------------------------------------------------------------------
-- Merge(dst, src)
-- Folds src into dst. Commutative, associative and idempotent: merging in
-- any order, any number of times, gives the same result. Copies everything
-- it takes from src. Returns true if dst changed.
---------------------------------------------------------------------------
function Ledger:Merge(dst, src)
    local changed = false

    local ss, ds = src.seed, dst.seed
    if ss and (ss.v > ds.v or (ss.v == ds.v and ss.a > ds.a)) then
        dst.seed = { v = ss.v, a = ss.a, scores = copyMap(ss.scores) }
        changed = true
    end

    if (src.epoch or 0) > dst.epoch then dst.epoch = src.epoch end

    for a, s in pairs(src.seq or {}) do
        if s > (dst.seq[a] or 0) then
            dst.seq[a] = s
            changed = true
        end
    end

    for name, sp in pairs(src.players or {}) do
        local dp = getPlayer(dst, name)
        if resetWins(sp.reset, dp.reset) then
            dp.reset = copyReset(sp.reset)
            changed = true
        end
        for a, entry in pairs(sp.c or {}) do
            local de = dp.c[a]
            -- Equal stamps should carry equal totals; the lower-total
            -- tie-break only keeps a mismatch deterministic.
            if not de or entry.s > de.s or (entry.s == de.s and entry.d < de.d) then
                dp.c[a] = { d = entry.d, s = entry.s }
                changed = true
            end
        end
    end
    return changed
end

---------------------------------------------------------------------------
-- Summaries (officer handshake)
-- { seed = "v|a", seq = { [author] = max }, sum = { [author] = Σ s } }.
-- max alone misses a single lost update when a later one from the same
-- author arrived; the per-author sum of entry stamps catches it.
---------------------------------------------------------------------------
function Ledger:Summary(ledger)
    local sum = {}
    for _, p in pairs(ledger.players) do
        for a, entry in pairs(p.c) do
            sum[a] = (sum[a] or 0) + entry.s
        end
        if p.reset then
            sum[p.reset.a] = (sum[p.reset.a] or 0) + (p.reset.s or 0)
        end
    end
    return {
        seed = tostring(ledger.seed.v) .. "|" .. tostring(ledger.seed.a),
        seq  = copyMap(ledger.seq),
        sum  = sum,
    }
end

local function sameMap(x, y)
    for k, v in pairs(x or {}) do if (y or {})[k] ~= v then return false end end
    for k, v in pairs(y or {}) do if (x or {})[k] ~= v then return false end end
    return true
end

function Ledger:SummariesEqual(x, y)
    if not x or not y then return false end
    return x.seed == y.seed and sameMap(x.seq, y.seq) and sameMap(x.sum, y.sum)
end

-- The entries this author wrote for the given players, plus its seq and the
-- Lamport epoch: a partial ledger Merge() accepts. Sent after a local change.
function Ledger:ExtractOps(ledger, names)
    local a = ledger.self
    local players = {}
    for name in pairs(names) do
        local p = ledger.players[name]
        if p then
            local out = { c = {} }
            if p.c[a] then out.c[a] = { d = p.c[a].d, s = p.c[a].s } end
            if p.reset and p.reset.a == a then out.reset = copyReset(p.reset) end
            players[name] = out
        end
    end
    return { seq = { [a] = ledger.seq[a] }, epoch = ledger.epoch, players = players }
end

-- Authors (and event IDs) whose seq or stamp sum differ between two
-- summaries, and whether the seeds differ. Returns authors set, seedDiffers.
function Ledger:DiffAuthors(x, y)
    local authors = {}
    for _, field in ipairs({ "seq", "sum" }) do
        local xs, ys = x[field] or {}, y[field] or {}
        for a, v in pairs(xs) do if ys[a] ~= v then authors[a] = true end end
        for a, v in pairs(ys) do if xs[a] ~= v then authors[a] = true end end
    end
    return authors, x.seed ~= y.seed
end

-- Partial ledger holding only the given authors' entries (and the seed if
-- asked). What one officer sends another in place of its whole ledger.
function Ledger:ExtractAuthors(ledger, authors, includeSeed)
    local seq, players = {}, {}
    for a in pairs(authors) do
        if ledger.seq[a] then seq[a] = ledger.seq[a] end
    end
    for name, p in pairs(ledger.players) do
        local out
        for a, entry in pairs(p.c) do
            if authors[a] then
                out = out or { c = {} }
                out.c[a] = { d = entry.d, s = entry.s }
            end
        end
        if p.reset and authors[p.reset.a] then
            out = out or { c = {} }
            out.reset = copyReset(p.reset)
        end
        if out then players[name] = out end
    end
    local partial = { seq = seq, epoch = ledger.epoch, players = players }
    if includeSeed then
        local sd = ledger.seed
        partial.seed = { v = sd.v, a = sd.a, scores = copyMap(sd.scores) }
    end
    return partial
end

-- Shape check for a summary from the wire.
function Ledger:IsSummary(s)
    if type(s) ~= "table" or type(s.seed) ~= "string" then return false end
    if type(s.seq) ~= "table" or type(s.sum) ~= "table" then return false end
    for _, v in pairs(s.seq) do if type(v) ~= "number" then return false end end
    for _, v in pairs(s.sum) do if type(v) ~= "number" then return false end end
    return true
end

-- Minimal shape check for a ledger (or partial ledger) from the wire, so a
-- malformed payload can't throw inside Merge.
function Ledger:IsWellFormed(src, partial)
    if type(src) ~= "table" or type(src.seq) ~= "table" or type(src.players) ~= "table" then
        return false
    end
    if not partial and src.schema ~= self.SCHEMA then return false end
    -- Required on a full ledger; optional on a partial one.
    if not partial or src.seed ~= nil then
        if type(src.seed) ~= "table" or type(src.seed.v) ~= "number"
           or type(src.seed.a) ~= "string" or type(src.seed.scores) ~= "table" then
            return false
        end
    end
    for _, s in pairs(src.seq) do
        if type(s) ~= "number" then return false end
    end
    for _, p in pairs(src.players) do
        if type(p) ~= "table" or type(p.c or {}) ~= "table" then return false end
        for _, e in pairs(p.c or {}) do
            if type(e) ~= "table" or type(e.d) ~= "number" or type(e.s) ~= "number" then
                return false
            end
        end
        local r = p.reset
        if r ~= nil and (type(r) ~= "table" or type(r.e) ~= "number"
                         or type(r.a) ~= "string" or type(r.base or 0) ~= "number") then
            return false
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Guild binding (WoW API from here down)
---------------------------------------------------------------------------
-- The ledger for gk if this client keeps one: an officer, on their own
-- guild's roster. Everyone else edits gd.roster directly as before.
local function isRealOfficer()
    -- IsOfficerOrHigher() is forced true in sandbox mode; use the real status.
    if PP._sandbox then return PP._isOfficer == true end
    return PP:IsOfficerOrHigher()
end

function Ledger:GetActive(gk)
    if not gk or gk ~= PP:GetPlayerGuild() then return nil end
    if not isRealOfficer() then return nil end
    local gd = PP.Repo.Roster:GetData(gk)
    return gd and gd.ledger
end

-- Rewrites gd.roster and gd.rosterVersion from the ledger.
function Ledger:Rebuild(gk)
    local gd = PP.Repo.Roster:GetData(gk)
    if not gd or not gd.ledger then return end
    local scores, version = self:Derive(gd.ledger)
    local roster = {}
    for name, score in pairs(scores) do
        roster[name] = {
            name  = PP:GetShortName(name),
            realm = name:match("-(.+)$") or "",
            score = score,
        }
    end
    gd.roster        = roster
    gd.rosterVersion = version
end

-- Creates the ledger the first time this client is an officer of gk, seeded
-- from the current roster, then rebuilds. Returns the ledger or nil.
function Ledger:Ensure(gk)
    if PP._sandbox then return nil end
    if not gk or gk ~= PP:GetPlayerGuild() or not isRealOfficer() then return nil end
    local gd = PP.Repo.Roster:EnsureData(gk)
    if not gd.ledger then
        local scores = {}
        for name, entry in pairs(gd.roster) do scores[name] = entry.score or 0 end
        local author = PP:GetPlayerFullName() .. "#" .. GetServerTime()
        gd.ledger = self:New(author, gd.rosterVersion or 0, scores)
    end
    self:Rebuild(gk)
    return gd.ledger
end
