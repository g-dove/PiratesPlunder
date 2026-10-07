---------------------------------------------------------------------------
-- Pirates Plunder – Officer Sync
-- Keeps officers' ledgers (Repository/LedgerRepository.lua) converged over
-- the guild OFFICER addon channel, so no group is needed.
--   LEDGER_HELLO { guildKey, summary, fast? }  login, session start, manual
--   LEDGER_STATE { guildKey, ledger }          full ledger (BULK)
--   LEDGER_OPS   { guildKey, ops }             one local change
-- Trust: OFFICER distribution (only members with officer chat can send or
-- read it), our own guild's key, and a ledger of our own for it.
-- Design: docs/plans/compact-ledger.md §7
---------------------------------------------------------------------------
---@type PPAddon
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

local REPLY_DELAY        = { 1, 5 }     -- answering a login / manual HELLO
local REPLY_DELAY_FAST   = { 0.2, 1 }   -- answering a session-start HELLO
local STATE_RECENT       = 5            -- a STATE we sent this recently already answers a HELLO
local GAP_HELLO_COOLDOWN = 30           -- an OPS gap triggers a HELLO at most this often
local LOGIN_HELLO_DELAY  = 5

PP._ledgerStateTimer = PP._ledgerStateTimer or {}  -- gk → pending STATE timer
PP._ledgerStateSent  = PP._ledgerStateSent  or {}  -- gk → time() of our last STATE
PP._ledgerGapHello   = PP._ledgerGapHello   or {}  -- gk → time() of our last gap HELLO
PP._ledgerHelloSent  = PP._ledgerHelloSent  or {}  -- gk → true once the login HELLO went out

local function debugPrint(msg)
    if PP._debug then PP:Print("[Ledger] " .. msg) end
end

-- After a merge changed our ledger: rebuild the roster, refresh, and as group
-- leader hand the new standings to raiders the legacy way.
local function applied(gk)
    PP.Repo.Ledger:Rebuild(gk)
    PP:RefreshMainWindow()
    if IsInGroup() and PP:IsGroupLeader() and PP:GetActiveGuildKey() == gk then
        PP:BroadcastRoster()
    end
end

-- gk → summaries the pending STATE answers; it carries only the authors
-- that differ from any of them.
PP._ledgerStateAgainst = PP._ledgerStateAgainst or {}

local function cancelState(gk)
    if PP._ledgerStateTimer[gk] then
        PP:CancelTimer(PP._ledgerStateTimer[gk])
        PP._ledgerStateTimer[gk] = nil
    end
    PP._ledgerStateAgainst[gk] = nil
end

-- against: the summary we're answering. Several triggers before the timer
-- fires fold into one STATE.
local function scheduleState(gk, range, against)
    local list = PP._ledgerStateAgainst[gk] or {}
    list[#list + 1] = against
    PP._ledgerStateAgainst[gk] = list
    if PP._ledgerStateTimer[gk] then return end
    local delay = range[1] + math.random() * (range[2] - range[1])
    PP._ledgerStateTimer[gk] = PP:ScheduleTimer(function()
        PP._ledgerStateTimer[gk] = nil
        local answering = PP._ledgerStateAgainst[gk]
        PP._ledgerStateAgainst[gk] = nil
        PP:SendLedgerState(gk, answering)
    end, delay)
end

---------------------------------------------------------------------------
-- Senders
---------------------------------------------------------------------------
function PP:SendLedgerHello(gk, fast)
    local ledger = PP.Repo.Ledger:GetActive(gk)
    if not ledger then return end
    self:SendAddonMessage(PP.MSG.LEDGER_HELLO, {
        guildKey = gk,
        summary  = PP.Repo.Ledger:Summary(ledger),
        fast     = fast or nil,
    }, nil, "OFFICER")
    debugPrint("HELLO sent" .. (fast and " (session start)" or ""))
end

-- answering: summaries to answer. With them, only the authors that differ
-- from any are sent (nothing at all if none do); without, the whole ledger
-- (manual "Broadcast Roster"). Our full summary always rides along so
-- listeners can tell whether we still hold something they lack.
function PP:SendLedgerState(gk, answering)
    local Ledger = PP.Repo.Ledger
    local ledger = Ledger:GetActive(gk)
    if not ledger then return end
    cancelState(gk)
    local mine = Ledger:Summary(ledger)
    local payload = { guildKey = gk, summary = mine }
    if answering and #answering > 0 then
        local authors, seed = {}, false
        for _, theirs in ipairs(answering) do
            local diff, seedDiff = Ledger:DiffAuthors(mine, theirs)
            for a in pairs(diff) do authors[a] = true end
            seed = seed or seedDiff
        end
        if not next(authors) and not seed then
            debugPrint("STATE skipped (nothing differs)")
            return
        end
        payload.ledger  = Ledger:ExtractAuthors(ledger, authors, seed)
        payload.partial = true
    else
        payload.ledger = ledger
    end
    PP._ledgerStateSent[gk] = time()
    self:SendAddonMessage(PP.MSG.LEDGER_STATE, payload, nil, "OFFICER")
    debugPrint("STATE sent" .. (payload.partial and " (delta)" or " (full)"))
end

-- names: set of fullNames touched by the change just committed.
function PP:SendLedgerOps(gk, names)
    local ledger = PP.Repo.Ledger:GetActive(gk)
    if not ledger then return end
    self:SendAddonMessage(PP.MSG.LEDGER_OPS, {
        guildKey = gk,
        ops      = PP.Repo.Ledger:ExtractOps(ledger, names),
    }, nil, "OFFICER")
end

-- Called on GUILD_ROSTER_UPDATE once the ledger exists: one HELLO per login.
function PP:ScheduleLoginLedgerHello(gk)
    if not gk or PP._ledgerHelloSent[gk] then return end
    if not PP.Repo.Ledger:GetActive(gk) then return end
    PP._ledgerHelloSent[gk] = true
    self:ScheduleTimer(function() self:SendLedgerHello(gk) end, LOGIN_HELLO_DELAY)
end

---------------------------------------------------------------------------
-- Receiver (dispatched from OnCommReceived before group bookkeeping)
---------------------------------------------------------------------------
function PP:HandleLedgerMessage(msgType, data, sender, distribution)
    if distribution ~= "OFFICER" then return end
    if type(data) ~= "table" or type(data.guildKey) ~= "string" then return end
    local gk = data.guildKey
    local ledger = PP.Repo.Ledger:GetActive(gk)
    if not ledger then return end
    local Ledger = PP.Repo.Ledger

    if msgType == PP.MSG.LEDGER_HELLO then
        if not Ledger:IsSummary(data.summary) then return end
        if Ledger:SummariesEqual(Ledger:Summary(ledger), data.summary) then return end
        local sent = PP._ledgerStateSent[gk]
        if sent and time() - sent < STATE_RECENT then return end
        debugPrint("HELLO from " .. self:GetShortName(sender) .. " differs; replying")
        scheduleState(gk, data.fast and REPLY_DELAY_FAST or REPLY_DELAY, data.summary)

    elseif msgType == PP.MSG.LEDGER_STATE then
        local partial = data.partial == true
        if not Ledger:IsWellFormed(data.ledger, partial) then return end
        -- The sender's full summary; a delta STATE can't be summarised itself.
        local theirs = data.summary
        if not Ledger:IsSummary(theirs) then
            if partial then return end
            theirs = Ledger:Summary(data.ledger)
        end
        if Ledger:Merge(ledger, data.ledger) then
            debugPrint("STATE from " .. self:GetShortName(sender) .. " merged")
            applied(gk)
        end
        -- Every officer hears every STATE. If we now match the sender, any
        -- reply we had queued is redundant; otherwise answer the sender too
        -- (it, or we, still lack something).
        if Ledger:SummariesEqual(Ledger:Summary(ledger), theirs) then
            cancelState(gk)
        else
            scheduleState(gk, REPLY_DELAY, theirs)
        end

    elseif msgType == PP.MSG.LEDGER_OPS then
        local ops = data.ops
        if not Ledger:IsWellFormed(ops, true) then return end
        -- A jump in the author's seq means we missed one of their changes.
        local gap = false
        for a, s in pairs(ops.seq) do
            if s > (ledger.seq[a] or 0) + 1 then gap = true end
        end
        if Ledger:Merge(ledger, ops) then applied(gk) end
        if gap then
            local last = PP._ledgerGapHello[gk]
            if not last or time() - last >= GAP_HELLO_COOLDOWN then
                PP._ledgerGapHello[gk] = time()
                debugPrint("missed a change from " .. self:GetShortName(sender) .. "; HELLO")
                self:SendLedgerHello(gk)
            end
        end
    end
end
