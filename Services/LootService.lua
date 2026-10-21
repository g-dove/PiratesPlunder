---------------------------------------------------------------------------
-- Pirates Plunder – Loot Service
-- All loot posting / cancellation / awarding logic goes through this table.
---------------------------------------------------------------------------
---@type PPAddon
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

PP.Loot = PP.Loot or {}

local LOOT_IDLE_CLEAR_DELAY = 60  -- seconds of no pending loot before broadcasting a clear

-- Raid announcement; sandbox prints it locally instead of sending.
local function announce(msg)
    if PP:IsSandbox() then
        PP:Print("|cFFFFD100[Sandbox] Raid chat:|r " .. msg)
        return
    end
    C_ChatInfo.SendChatMessage(msg, IsInRaid() and "RAID" or "PARTY")
end

---------------------------------------------------------------------------
-- _ScheduleIdleClear() / _CancelIdleClear()
-- After the last item is cleared, raid leader schedules a broadcast telling
-- all clients to wipe their loot display. Cancelled if a new item is posted
-- before the timer fires (no race with new posts). Also cancelled on
-- session end/create via WipeRetryQueue.
---------------------------------------------------------------------------
function PP.Loot:_ScheduleIdleClear()
    self:_CancelIdleClear()
    if not PP:IsRaidLeader() or not IsInGroup() then return end
    PP._lootIdleTimer = PP:ScheduleTimer(function()
        PP._lootIdleTimer = nil
        if not PP:IsRaidLeader() or not IsInGroup() then return end
        if next(PP.Repo.Loot:GetAll()) ~= nil then return end
        PP:SendAddonMessage(PP.MSG.LOOT_CLEAR, {})
        if PP._debug then
            PP:Print("[Sync] Loot idle clear broadcast (" .. LOOT_IDLE_CLEAR_DELAY .. "s with no pending loot)")
        end
    end, LOOT_IDLE_CLEAR_DELAY)
end

function PP.Loot:_CancelIdleClear()
    if PP._lootIdleTimer then
        PP:CancelTimer(PP._lootIdleTimer)
        PP._lootIdleTimer = nil
    end
end

---------------------------------------------------------------------------
-- LocalClearLoot() – wipe pending loot from this client's display only.
-- No broadcast. Used by the slash command and the Settings button.
---------------------------------------------------------------------------
function PP:LocalClearLoot()
    PP.Loot:_CancelIdleClear()
    PP.Repo.Loot:WipeAll()
    self:CloseLootPopups()
    self:RefreshLootMasterWindow()
    self:RefreshLootResponseFrame()
end

---------------------------------------------------------------------------
-- OnPartyLeaderChanged()
-- Leadership transferred. Cancel any timer held as the old leader and, if
-- we are the new leader with an empty queue, take over the idle clear.
---------------------------------------------------------------------------
function PP:OnPartyLeaderChanged()
    PP.Loot:_CancelIdleClear()
    if PP:IsRaidLeader() and IsInGroup() and next(PP.Repo.Loot:GetAll()) == nil then
        PP.Loot:_ScheduleIdleClear()
    end
end

---------------------------------------------------------------------------
-- Restore() – public entry point for post-load loot recovery.
-- Called from OnPlayerEnteringWorld for both reload and zone-transition
-- paths. Conditionally restores from DB (skipped if pendingLoot already
-- has items, e.g. during a zone transition where loot was never wiped),
-- then verifies state against the loot master.
---------------------------------------------------------------------------
function PP.Loot:Restore()
    -- Only pull from DB cache when pendingLoot is empty (fresh reload/login).
    -- Zone transitions leave pendingLoot intact, so we skip the DB restore.
    if next(PP.Repo.Loot:GetAll()) == nil then
        PP.Repo.Loot:Restore()
    end
    -- Verify whatever is now in pendingLoot (from DB or from memory)
    if next(PP.Repo.Loot:GetAll()) ~= nil then
        self:_requestStateSync()
    end
end

---------------------------------------------------------------------------
-- _requestStateSync() – internal. Broadcasts LOOT_STATE_QUERY and sets a
-- 10-second fallback to show the response popup if no reply arrives.
---------------------------------------------------------------------------
function PP.Loot:_requestStateSync()
    if PP._lootStateVerifyPending then return end
    if not IsInGroup() then
        PP:ShowLootResponseFrameIfNeeded()
        return
    end
    if not PP.Repo.Roster:HasActiveSession() then return end
    local keys = {}
    for k in pairs(PP.Repo.Loot:GetAll()) do
        keys[#keys + 1] = k
    end
    if #keys == 0 then return end

    PP:SendAddonMessage(PP.MSG.LOOT_STATE_QUERY, { keys = keys })

    PP._lootStateVerifyPending = true
    PP:ScheduleTimer(function()
        if PP._lootStateVerifyPending then
            PP._lootStateVerifyPending = false
            PP:ShowLootResponseFrameIfNeeded()
        end
    end, 10)
end

---------------------------------------------------------------------------
-- Post(itemLink)
-- Moved from PP:PostLoot() in Loot.lua.
---------------------------------------------------------------------------
function PP.Loot:Post(itemLink)
    if not PP.Repo.Roster:HasActiveSession() then
        PP:Print("No active session.")
        return
    end
    if not PP:CanPostLoot() then
        PP:Print("Only the raid leader can post loot for this roster.")
        return
    end

    -- Try to get itemID from cache; fall back to parsing the link directly
    local itemID = C_Item.GetItemInfoInstant(itemLink)
    if not itemID then
        -- Extract itemID from the hyperlink: |Hitem:12345:...|h
        itemID = tonumber(itemLink:match("item:(%d+)"))
    end
    if not itemID then
        PP:Print("Invalid item link.")
        return
    end

    PP.Loot:_CancelIdleClear()
    local key = PP:LootKey(itemLink)
    PP.Repo.Loot:SetEntry(key, {
        itemLink      = itemLink,
        itemID        = itemID,
        postedBy      = PP:GetPlayerFullName(),
        postedAt      = GetTime(),
        responses     = {},  -- fullName => { response, score, roll }
        votes         = {},  -- voterFullName => targetFullName
        awarded       = false,
        awardedTo     = nil,
        allowTransmog = PP.db.global.allowTransmogRolls ~= false,
    })

    -- Broadcast to raid (other players will show their own popup via HandleLootPost)
    if PP:IsRaidLeader() and IsInGroup() then
        local gk     = PP:GetActiveGuildKey()
        local gd     = PP.Repo.Roster:GetData(gk)
        local active = gd and gd.activeSessionID and gd.sessions[gd.activeSessionID] or nil
        PP:SendAddonMessage(PP.MSG.LOOT_POST, {
            key                  = key,
            itemLink             = itemLink,
            itemID               = itemID,
            postedBy             = PP:GetPlayerFullName(),
            allowTransmog        = PP.db.global.allowTransmogRolls ~= false,
            guildKey             = gk,
            activeSessionID      = gd and gd.activeSessionID or nil,
            activeSessionVersion = gd and gd.activeSessionVersion or nil,
            -- Minimal session shell so receivers who missed SESSION_CREATE
            -- can install a record before showing the response popup.
            session              = active and {
                name      = active.name,
                startTime = active.startTime,
                leader    = active.leader,
                guildKey  = gk,
            } or nil,
        })
    end

    if PP:IsSandbox() then
        self:_SimulateSandboxResponses(key)
    end

    -- Also show the unified response popup (adds this item to it)
    PP:ShowLootResponseFrame()

    PP:Print("Posted for distribution: " .. itemLink)
    PP:RefreshLootMasterWindow()
end

---------------------------------------------------------------------------
-- _SimulateSandboxResponses(key)
-- Sandbox only. Each fake roster member answers the posted item after a
-- short random delay with a random response (some pass, some never answer),
-- so award / reassign / pending-trade flows can be tested solo.
---------------------------------------------------------------------------
function PP.Loot:_SimulateSandboxResponses(key)
    local me = PP:GetPlayerFullName()
    for fullName, data in pairs(PP.Repo.Roster:GetRoster()) do
        if fullName ~= me then
            local r = math.random(1, 10)
            local response = (r <= 4 and PP.RESPONSE.NEED)
                          or (r <= 6 and PP.RESPONSE.MINOR)
                          or (r <= 8 and PP.RESPONSE.TRANSMOG)
                          or (r == 9 and PP.RESPONSE.PASS)
                          or nil  -- never responds
            if response then
                PP:ScheduleTimer(function()
                    if not PP:IsSandbox() then return end
                    local entry = PP.Repo.Loot:GetEntry(key)
                    if not entry or entry.awarded then return end
                    local resp = response
                    if resp == PP.RESPONSE.TRANSMOG and entry.allowTransmog == false then
                        resp = PP.RESPONSE.MINOR
                    end
                    -- Borrow our own gear for the equipped/ilvl columns
                    local comp
                    if resp == PP.RESPONSE.NEED or resp == PP.RESPONSE.MINOR then
                        comp = PP:GetEquippedComparisonData(entry.itemLink)
                    end
                    PP:ReceiveLootInterest(key, fullName, resp, data.score or 0, comp)
                end, 0.5 + math.random() * 2.5)
            end
        end
    end
    PP:Print("|cFFFFD100[Sandbox] Fake raid members are responding to this item.|r")
end

---------------------------------------------------------------------------
-- Cancel(key)
-- Moved from PP:CancelLoot() in Loot.lua.
---------------------------------------------------------------------------
function PP.Loot:Cancel(key)
    if not PP:CanPostLoot() then return end
    if not PP.Repo.Loot:GetEntry(key) then return end
    PP.Repo.Loot:ClearEntry(key)

    if PP:IsRaidLeader() and IsInGroup() then
        local gk = PP:GetActiveGuildKey()
        local gd = PP.Repo.Roster:GetData(gk)
        PP:SendAddonMessage(PP.MSG.LOOT_CANCEL, {
            key                  = key,
            guildKey             = gk,
            activeSessionID      = gd and gd.activeSessionID or nil,
            activeSessionVersion = gd and gd.activeSessionVersion or nil,
        })
    end
    if next(PP.Repo.Loot:GetAll()) == nil then
        PP.Loot:_ScheduleIdleClear()
    end
    PP:RefreshLootMasterWindow()
    PP:RefreshLootResponseFrame()
end

---------------------------------------------------------------------------
-- _ChargeWinner(fullName, response, free)
-- Applies the award cost to fullName's current score: TRANSMOG costs 1 pt,
-- MINOR drops to 1 below the next person, NEED zeroes the score, free keeps
-- it. Returns pointsSpent, newScore (newScore nil if not on the roster).
---------------------------------------------------------------------------
function PP.Loot:_ChargeWinner(fullName, response, free)
    local roster = PP.Repo.Roster:GetRoster()
    if not roster[fullName] then return 0, nil end
    local currentScore = roster[fullName].score or 0
    local pointsSpent, newScore
    if free then
        pointsSpent = 0
        newScore    = currentScore
    elseif response == PP.RESPONSE.TRANSMOG then
        pointsSpent = 1
        newScore    = math.max(0, currentScore - 1)
    elseif response == PP.RESPONSE.MINOR then
        newScore    = PP:GetMinorUpgradeScore(fullName)
        pointsSpent = math.max(0, currentScore - newScore)
    else  -- NEED
        pointsSpent = currentScore
        newScore    = 0
    end
    roster[fullName].score = newScore
    return pointsSpent, newScore
end

---------------------------------------------------------------------------
-- _RecordHistory(key, lootEntry, awardedTo, response, pointsSpent, free,
--                guildKey?, sessionID?)
-- Snapshots the responses of a just-awarded item into the session loot
-- history. Runs on the loot master and on every receiver of LOOT_AWARD.
---------------------------------------------------------------------------
function PP.Loot:_RecordHistory(key, lootEntry, awardedTo, response, pointsSpent, free, guildKey, sessionID)
    guildKey = guildKey or PP:GetActiveGuildKey()
    if not sessionID then
        local gd = PP.Repo.Roster:GetData(guildKey)
        sessionID = gd and gd.activeSessionID
    end
    if not sessionID or not lootEntry then return end
    PP.Repo.Loot:SetHistoryEntry(key, {
        key         = key,
        itemLink    = lootEntry.itemLink,
        itemID      = lootEntry.itemID,
        awardedTo   = awardedTo,
        response    = response,
        pointsSpent = pointsSpent or 0,
        free        = free and true or false,
        responses   = lootEntry.responses or {},
        votes       = lootEntry.votes or {},
        guildKey    = guildKey,
        sessionID   = sessionID,
        time        = time(),
    })
    PP:RefreshLootHistoryWindow()
end

---------------------------------------------------------------------------
-- Award(key, fullName, free)
-- Moved from PP:AwardItem() in Loot.lua.
---------------------------------------------------------------------------
function PP.Loot:Award(key, fullName, free)
    if not PP:CanPostLoot() then return end
    local entry = PP.Repo.Loot:GetEntry(key)
    if not entry then return end

    entry.awarded   = true
    entry.awardedTo = fullName

    local winnerResp     = entry.responses[fullName]
    local winnerResponse = winnerResp and winnerResp.response or PP.RESPONSE.NEED
    local pointsSpent, newScore = self:_ChargeWinner(fullName, winnerResponse, free)
    if newScore then
        PP.Repo.Roster:BumpRosterVersion()
    else
        newScore = 0
    end

    -- Record in session history with cost info (key stored for LOOT_STATE_QUERY matching)
    PP.Session:RecordItemAward(entry.itemLink, entry.itemID, fullName, pointsSpent, winnerResponse, key)
    self:_RecordHistory(key, entry, fullName, winnerResponse, pointsSpent, free)

    -- Add to pending trades ONLY if the awardee is not the loot master
    local me = PP:GetPlayerFullName()
    if fullName ~= me then
        local trades = PP.Repo.Loot:GetPendingTrades()
        trades[#trades + 1] = {
            itemLink  = entry.itemLink,
            itemID    = entry.itemID,
            awardedTo = fullName,
        }
    end

    -- Announce in raid
    local shortName = PP:GetShortName(fullName)
    announce("Pirates Plunder: " .. entry.itemLink .. " awarded to " .. shortName .. "!")

    -- Single broadcast carries the score change + roster version so receivers
    -- can update scores and detect missed broadcasts; a version gap triggers
    -- RequestSessionSync to converge on the leader.
    if PP:IsRaidLeader() and IsInGroup() then
        local gk        = PP:GetActiveGuildKey()
        local gd        = PP.Repo.Roster:GetData(gk)
        local rosterVer = PP.Repo.Roster:GetRosterVersion(gk)
        local active    = gd and gd.activeSessionID and gd.sessions[gd.activeSessionID] or nil
        PP:SendAddonMessage(PP.MSG.LOOT_AWARD, {
            key                  = key,
            itemLink             = entry.itemLink,
            itemID               = entry.itemID,
            awardedTo            = fullName,
            response             = winnerResponse,
            pointsSpent          = pointsSpent,
            newScore             = newScore,
            guildKey             = gk,
            rosterVersion        = rosterVer,
            activeSessionID      = gd and gd.activeSessionID or nil,
            activeSessionVersion = gd and gd.activeSessionVersion or nil,
            session              = active and {
                name      = active.name,
                startTime = active.startTime,
                leader    = active.leader,
                guildKey  = gk,
            } or nil,
        })
    end

    -- Remove from pending loot; schedule idle clear if queue is now empty
    PP.Repo.Loot:ClearEntry(key)
    if next(PP.Repo.Loot:GetAll()) == nil then
        PP.Loot:_ScheduleIdleClear()
    end

    PP:Print(entry.itemLink .. " awarded to " .. shortName)
    PP:RefreshLootMasterWindow()
    PP:RefreshMainWindow()
    PP:RefreshLootResponseFrame()
end

---------------------------------------------------------------------------
-- Reassign(key, newName, free, confirmed)
-- Moves an already-awarded item to another player. The previous winner gets
-- back what they spent; the new winner pays from their current score using
-- the response they gave for the item. Raid leader only. If the item is no
-- longer in pending trades (likely already handed over) a confirm popup is
-- shown first; `confirmed` skips it.
---------------------------------------------------------------------------
function PP.Loot:Reassign(key, newName, free, confirmed)
    if not PP:IsRaidLeader() then
        PP:Print("Only the raid leader can reassign loot.")
        return
    end
    local hist = PP.Repo.Loot:GetHistoryEntry(key)
    local gk   = PP:GetActiveGuildKey()
    local gd   = PP.Repo.Roster:GetData(gk)
    if not hist or not gd or hist.guildKey ~= gk or hist.sessionID ~= gd.activeSessionID then
        PP:Print("That item is not part of the active session.")
        return
    end
    local oldName = hist.awardedTo
    if oldName == newName then return end

    local me = PP:GetPlayerFullName()
    if not confirmed and oldName ~= me
       and not PP.Repo.Loot:HasPendingTradeFor(hist.itemID, oldName) then
        PP._pendingReassign = { key = key, newName = newName, free = free }
        StaticPopup_Show("PP_CONFIRM_REASSIGN_TRADED", hist.itemLink or "This item", PP:GetShortName(oldName))
        return
    end

    -- Refund first so MINOR pricing for the new winner sees the restored score.
    local roster   = PP.Repo.Roster:GetRoster()
    local refund   = hist.pointsSpent or 0
    local oldScore
    if roster[oldName] then
        roster[oldName].score = (roster[oldName].score or 0) + refund
        oldScore = roster[oldName].score
    end

    local newResp     = hist.responses and hist.responses[newName]
    local newResponse = newResp and newResp.response or PP.RESPONSE.NEED
    local pointsSpent, newScore = self:_ChargeWinner(newName, newResponse, free)
    PP.Repo.Roster:BumpRosterVersion()

    if not PP.Session:UpdateItemAward(key, newName, pointsSpent, newResponse, oldName) then
        PP.Session:RecordItemAward(hist.itemLink, hist.itemID, newName, pointsSpent, newResponse, key)
    end
    hist.awardedTo      = newName
    hist.response       = newResponse
    hist.pointsSpent    = pointsSpent
    hist.free           = free and true or false
    hist.reassignedFrom = oldName
    PP.Repo.Loot:SetHistoryEntry(key, hist)

    -- Swap the pending trade over to the new winner
    PP.Repo.Loot:RemovePendingTradeFor(hist.itemID, oldName)
    if newName ~= me then
        local trades = PP.Repo.Loot:GetPendingTrades()
        trades[#trades + 1] = {
            itemLink  = hist.itemLink,
            itemID    = hist.itemID,
            awardedTo = newName,
        }
        PP.Repo.Loot:Save()
    end

    local oldShort, newShort = PP:GetShortName(oldName), PP:GetShortName(newName)
    if IsInGroup() or PP:IsSandbox() then
        announce("Pirates Plunder: " .. oldShort .. " has been refunded " .. refund .. " points for " .. hist.itemLink .. ".")
        announce("Pirates Plunder: " .. hist.itemLink .. " awarded to " .. newShort .. "!")
    end
    if IsInGroup() then
        PP:SendAddonMessage(PP.MSG.LOOT_REASSIGN, {
            key                  = key,
            itemLink             = hist.itemLink,
            itemID               = hist.itemID,
            oldWinner            = oldName,
            oldScore             = oldScore,
            refund               = refund,
            awardedTo            = newName,
            newScore             = newScore,
            response             = newResponse,
            pointsSpent          = pointsSpent,
            free                 = free and true or false,
            guildKey             = gk,
            rosterVersion        = PP.Repo.Roster:GetRosterVersion(gk),
            activeSessionID      = gd.activeSessionID,
            activeSessionVersion = gd.activeSessionVersion,
        })
    end

    PP:Print(hist.itemLink .. " reassigned from " .. oldShort .. " (refunded " .. refund .. ") to " .. newShort)
    PP:RefreshLootMasterWindow()
    PP:RefreshMainWindow()
    PP:RefreshLootHistoryWindow()
end

---------------------------------------------------------------------------
-- SubmitResponse(key, response)
-- Moved from PP:ExpressInterest() in Loot.lua.
---------------------------------------------------------------------------
function PP.Loot:SubmitResponse(key, response)
    if not PP.Repo.Loot:GetEntry(key) then return end
    local me = PP:GetPlayerFullName()
    local score = 0
    local roster = PP.Repo.Roster:GetRoster()
    if roster[me] then
        score = roster[me].score
    end

    -- For NEED/MINOR responses, collect equipped-item comparison data.
    local comp = nil
    if response == PP.RESPONSE.NEED or response == PP.RESPONSE.MINOR then
        local entry = PP.Repo.Loot:GetEntry(key)
        if entry and entry.itemLink then
            comp = PP:GetEquippedComparisonData(entry.itemLink)
        end
    end

    -- Record locally immediately (OnCommReceived filters out self-messages,
    -- so we cannot rely on the broadcast looping back to us)
    PP:ReceiveLootInterest(key, me, response, score, comp)

    -- Broadcast to everyone else in the group
    PP:SendAddonMessage(PP.MSG.LOOT_INTEREST, {
        key           = key,
        player        = me,
        response      = response,
        score         = score,
        equippedLinks = comp and comp.equippedLinks,
    })

    PP.Repo.Loot:Save()
    PP:RefreshLootResponseFrame()
end

---------------------------------------------------------------------------
-- PostAll()
-- Moved from PP:PostLootQueue() in Loot.lua.
---------------------------------------------------------------------------
function PP.Loot:PostAll()
    local queue = PP.Repo.Loot:GetQueue()
    if #queue == 0 then
        PP:Print("Loot queue is empty.")
        return
    end
    for _, entry in ipairs(queue) do
        PP.Loot:Post(entry.itemLink)
    end
    wipe(queue)
    PP:RefreshLootMasterWindow()
end
