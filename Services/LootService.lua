---------------------------------------------------------------------------
-- Pirates Plunder – Loot Service
-- All loot posting / cancellation / awarding logic goes through this table.
---------------------------------------------------------------------------
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

PP.Loot = PP.Loot or {}

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
    PP:SendAddonMessage(PP.MSG.LOOT_POST, {
        key           = key,
        itemLink      = itemLink,
        itemID        = itemID,
        postedBy      = PP:GetPlayerFullName(),
        allowTransmog = PP.db.global.allowTransmogRolls ~= false,
    })

    -- Also show the unified response popup (adds this item to it)
    PP:ShowLootResponseFrame()

    PP:Print("Posted for distribution: " .. itemLink)
    PP.Repo.Loot:Save()
    PP:RefreshLootMasterWindow()
end

---------------------------------------------------------------------------
-- Cancel(key)
-- Moved from PP:CancelLoot() in Loot.lua.
---------------------------------------------------------------------------
function PP.Loot:Cancel(key)
    if not PP:CanPostLoot() then return end
    if not PP.Repo.Loot:GetEntry(key) then return end
    PP.Repo.Loot:ClearEntry(key)

    PP:SendAddonMessage(PP.MSG.LOOT_CANCEL, { key = key })
    PP.Repo.Loot:Save()
    PP:RefreshLootMasterWindow()
    PP:RefreshLootResponseFrame()
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

    -- Determine cost: TRANSMOG costs 1 pt, NEED zeroes the score
    local winnerResp     = entry.responses[fullName]
    local winnerResponse = winnerResp and winnerResp.response or PP.RESPONSE.NEED
    local pointsSpent, newScore = 0, 0

    local roster = PP.Repo.Roster:GetRoster()
    if roster[fullName] then
        local currentScore = roster[fullName].score or 0
        if free then
            -- Free award: keep score exactly as-is
            pointsSpent = 0
            newScore    = currentScore
        elseif winnerResponse == PP.RESPONSE.TRANSMOG then
            pointsSpent = 1
            newScore    = math.max(0, currentScore - 1)
        elseif winnerResponse == PP.RESPONSE.MINOR then
            -- Drop to 1 below the next person on the roster
            newScore    = PP:GetMinorUpgradeScore(fullName)
            pointsSpent = math.max(0, currentScore - newScore)
        else  -- NEED
            pointsSpent = currentScore
            newScore    = 0
        end
        roster[fullName].score = newScore
        PP.Repo.Roster:BumpRosterVersion()
        -- Broadcast updated roster so all clients reflect the new score
        local gk = PP:GetActiveGuildKey()
        local gd = PP.Repo.Roster:GetData(gk)
        PP:SendAddonMessage(PP.MSG.SCORE_UPDATE, {
            roster   = gd.roster,
            version  = gd.rosterVersion,
            guildKey = gk,
        })
    end

    -- Record in session history with cost info (key stored for LOOT_STATE_QUERY matching)
    PP.Session:RecordItemAward(entry.itemLink, entry.itemID, fullName, pointsSpent, winnerResponse, key)

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
    C_ChatInfo.SendChatMessage(
        "Pirates Plunder: " .. entry.itemLink .. " awarded to " .. shortName .. "!",
        IsInRaid() and "RAID" or "PARTY"
    )

    -- Broadcast award (include score data so all clients apply correct deduction)
    PP:SendAddonMessage(PP.MSG.LOOT_AWARD, {
        key         = key,
        itemLink    = entry.itemLink,
        itemID      = entry.itemID,
        awardedTo   = fullName,
        response    = winnerResponse,
        pointsSpent = pointsSpent,
        newScore    = newScore,
    })

    -- Remove from pending loot
    PP.Repo.Loot:ClearEntry(key)

    PP:Print(entry.itemLink .. " awarded to " .. shortName)
    PP.Repo.Loot:Save()
    PP:RefreshLootMasterWindow()
    PP:RefreshMainWindow()
    PP:RefreshLootResponseFrame()
end

---------------------------------------------------------------------------
-- SubmitResponse(key, response)
-- Moved from PP:ExpressInterest() in Loot.lua.
---------------------------------------------------------------------------
function PP.Loot:SubmitResponse(key, response)
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
