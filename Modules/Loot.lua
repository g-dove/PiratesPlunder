---------------------------------------------------------------------------
-- Pirates Plunder – Loot Distribution
---------------------------------------------------------------------------
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

---------------------------------------------------------------------------
-- Post an item for distribution (officer / raid leader only)
---------------------------------------------------------------------------
function PP:PostLoot(itemLink)
    if not self:HasActiveRaid() then
        self:Print("No active raid.")
        return
    end
    if not self:CanModify() and not self:IsRaidLeaderOrAssist() then
        self:Print("Only officers or raid leader/assistants can post loot.")
        return
    end

    -- Try to get itemID from cache; fall back to parsing the link directly
    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then
        -- Extract itemID from the hyperlink: |Hitem:12345:...|h
        itemID = tonumber(itemLink:match("item:(%d+)"))
    end
    if not itemID then
        self:Print("Invalid item link.")
        return
    end

    local key = self:LootKey(itemLink)
    self.pendingLoot[key] = {
        itemLink      = itemLink,
        itemID        = itemID,
        postedBy      = self:GetPlayerFullName(),
        postedAt      = GetTime(),
        responses     = {},  -- fullName => { response, score, roll }
        awarded       = false,
        awardedTo     = nil,
        allowTransmog = self.db.global.allowTransmogRolls ~= false,
    }

    -- Broadcast to raid (other players will show their own popup via HandleLootPost)
    self:SendAddonMessage(PP.MSG.LOOT_POST, {
        key           = key,
        itemLink      = itemLink,
        itemID        = itemID,
        postedBy      = self:GetPlayerFullName(),
        allowTransmog = self.db.global.allowTransmogRolls ~= false,
    })

    -- Also show the unified response popup (adds this item to it)
    self:ShowLootResponseFrame()

    self:Print("Posted for distribution: " .. itemLink)
    self:SavePendingLoot()
    self:RefreshLootMasterWindow()
end

---------------------------------------------------------------------------
-- Cancel a loot posting
---------------------------------------------------------------------------
function PP:CancelLoot(key)
    if not self.pendingLoot[key] then return end
    self.pendingLoot[key] = nil

    self:SendAddonMessage(PP.MSG.LOOT_CANCEL, { key = key })
    self:SavePendingLoot()
    self:RefreshLootMasterWindow()
    self:RefreshLootResponseFrame()
end

---------------------------------------------------------------------------
-- Express interest in an item (any raid member)
---------------------------------------------------------------------------
function PP:ExpressInterest(key, response)
    local me = self:GetPlayerFullName()
    local score = 0
    local roster = self:GetRoster()
    if roster[me] then
        score = roster[me].score
    end

    -- Record locally immediately (OnCommReceived filters out self-messages,
    -- so we cannot rely on the broadcast looping back to us)
    self:ReceiveLootInterest(key, me, response, score)

    -- Broadcast to everyone else in the group
    self:SendAddonMessage(PP.MSG.LOOT_INTEREST, {
        key      = key,
        player   = me,
        response = response,
        score    = score,
    })

    self:Print("You expressed " .. response .. " for this item.")
    self:SavePendingLoot()
    self:RefreshLootResponseFrame()
end

---------------------------------------------------------------------------
-- Receive an interest response (loot master processes this)
---------------------------------------------------------------------------
function PP:ReceiveLootInterest(key, playerName, response, score)
    if not self.pendingLoot[key] then return end
    self.pendingLoot[key].responses[playerName] = {
        response = response,
        score    = score,
        roll     = math.random(1, 100),  -- tiebreaker
    }
    self:SavePendingLoot()
    self:RefreshLootMasterWindow()
end

---------------------------------------------------------------------------
-- Compute the score a MINOR winner ends up with.
-- Finds the first roster entry with a score strictly below theirs and
-- returns (that score - 1), floored at 0.
---------------------------------------------------------------------------
function PP:GetMinorUpgradeScore(fullName)
    local roster  = self:GetRoster()
    local myScore = roster[fullName] and roster[fullName].score or 0
    local best    = nil  -- highest score that is still < myScore
    for name, data in pairs(roster) do
        if name ~= fullName then
            local s = data.score or 0
            if s < myScore then
                if best == nil or s > best then
                    best = s
                end
            end
        end
    end
    if best == nil then return 0 end
    return math.max(0, best - 1)
end

---------------------------------------------------------------------------
-- Get sorted responses for an item (highest score first, random tiebreak)
---------------------------------------------------------------------------
function PP:GetSortedResponses(key)
    local entry = self.pendingLoot[key]
    if not entry then return {} end

    local list = {}
    for fullName, resp in pairs(entry.responses) do
        if resp.response ~= PP.RESPONSE.PASS then
            list[#list + 1] = {
                fullName = fullName,
                name     = self:GetShortName(fullName),
                response = resp.response,
                score    = resp.score,
                roll     = resp.roll,
            }
        end
    end

    -- Sort: Need > Minor > Transmog, then score desc, then roll desc
    table.sort(list, function(a, b)
        local function prio(r)
            if r == PP.RESPONSE.NEED    then return 2 end
            if r == PP.RESPONSE.MINOR   then return 1 end
            return 0
        end
        local ap, bp = prio(a.response), prio(b.response)
        if ap ~= bp then return ap > bp end
        if a.score ~= b.score then return a.score > b.score end
        return a.roll > b.roll
    end)
    return list
end

---------------------------------------------------------------------------
-- Award an item to a player
---------------------------------------------------------------------------
function PP:AwardItem(key, fullName)
    local entry = self.pendingLoot[key]
    if not entry then return end

    entry.awarded   = true
    entry.awardedTo = fullName

    -- Determine cost: TRANSMOG costs 1 pt, NEED zeroes the score
    local winnerResp = entry.responses[fullName]
    local winnerResponse = winnerResp and winnerResp.response or PP.RESPONSE.NEED
    local pointsSpent, newScore = 0, 0

    local roster = self:GetRoster()
    if roster[fullName] then
        local currentScore = roster[fullName].score or 0
        if winnerResponse == PP.RESPONSE.TRANSMOG then
            pointsSpent = 1
            newScore    = math.max(0, currentScore - 1)
        elseif winnerResponse == PP.RESPONSE.MINOR then
            -- Drop to 1 below the next person on the roster
            newScore    = self:GetMinorUpgradeScore(fullName)
            pointsSpent = math.max(0, currentScore - newScore)
        else  -- NEED
            pointsSpent = currentScore
            newScore    = 0
        end
        roster[fullName].score = newScore
        self:BumpRosterVersion()
        -- Broadcast updated roster so all clients reflect the new score
        local gk = self:GetActiveGuildKey()
        local gd = self:GetGuildData(gk)
        self:SendAddonMessage(PP.MSG.SCORE_UPDATE, {
            roster   = gd.roster,
            version  = gd.rosterVersion,
            guildKey = gk,
        })
    end

    -- Record in raid history with cost info
    self:RecordItemAward(entry.itemLink, entry.itemID, fullName, pointsSpent, winnerResponse)

    -- Add to pending trades ONLY if the awardee is not the loot master
    local me = self:GetPlayerFullName()
    if fullName ~= me then
        self.pendingTrades[#self.pendingTrades + 1] = {
            itemLink  = entry.itemLink,
            itemID    = entry.itemID,
            awardedTo = fullName,
        }
    end

    -- Announce in raid
    local shortName = self:GetShortName(fullName)
    SendChatMessage(
        "Pirates Plunder: " .. entry.itemLink .. " awarded to " .. shortName .. "!",
        IsInRaid() and "RAID" or "PARTY"
    )

    -- Broadcast award (include score data so all clients apply correct deduction)
    self:SendAddonMessage(PP.MSG.LOOT_AWARD, {
        key         = key,
        itemLink    = entry.itemLink,
        itemID      = entry.itemID,
        awardedTo   = fullName,
        response    = winnerResponse,
        pointsSpent = pointsSpent,
        newScore    = newScore,
    })

    -- Remove from pending loot
    self.pendingLoot[key] = nil

    self:Print(entry.itemLink .. " awarded to " .. shortName)
    self:SavePendingLoot()
    self:RefreshLootMasterWindow()
    self:RefreshMainWindow()
    self:RefreshLootResponseFrame()
end

---------------------------------------------------------------------------
-- Close all loot popups
---------------------------------------------------------------------------
function PP:CloseLootPopups()
    for key, frame in pairs(self.lootPopups) do
        if frame and frame.Hide then frame:Hide() end
    end
    wipe(self.lootPopups)
end

---------------------------------------------------------------------------
-- Get list of all pending (unawarded) loot items
---------------------------------------------------------------------------
function PP:GetPendingLootList()
    local list = {}
    for key, entry in pairs(self.pendingLoot) do
        if not entry.awarded then
            local responseCount = 0
            for _ in pairs(entry.responses) do
                responseCount = responseCount + 1
            end
            list[#list + 1] = {
                key           = key,
                itemLink      = entry.itemLink,
                itemID        = entry.itemID,
                postedBy      = entry.postedBy,
                responseCount = responseCount,
            }
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Loot Queue – stage items before broadcasting
---------------------------------------------------------------------------

-- Add an item to the loot queue (called by alt+right-click or manual link)
function PP:AddToLootQueue(itemLink)
    if not itemLink or itemLink:trim() == "" then return end
    -- Avoid exact duplicates in the queue
    for _, entry in ipairs(self.lootQueue) do
        if entry.itemLink == itemLink then
            self:Print("Already queued: " .. itemLink)
            if not self.lootMasterWindow then self:CreateLootMasterWindow() end
            return
        end
    end
    self.lootQueue[#self.lootQueue + 1] = { itemLink = itemLink }
    if not self.lootMasterWindow then
        self:CreateLootMasterWindow()
    else
        self:RefreshLootMasterWindow()
    end
    self:Print("Added to queue: " .. itemLink)
end

-- Remove one entry from the queue by index
function PP:RemoveFromLootQueue(index)
    table.remove(self.lootQueue, index)
    self:RefreshLootMasterWindow()
end

-- Toggle transmog responses allowed for a live loot item
function PP:SetLootTransmog(key, allow)
    if not self.pendingLoot[key] then return end
    self.pendingLoot[key].allowTransmog = allow
    self:SendAddonMessage(PP.MSG.LOOT_UPDATE, { key = key, allowTransmog = allow })
    self:RefreshLootMasterWindow()
    self:RefreshLootResponseFrame()
end

-- Post every queued item then clear the queue
function PP:PostLootQueue()
    if #self.lootQueue == 0 then
        self:Print("Loot queue is empty.")
        return
    end
    for _, entry in ipairs(self.lootQueue) do
        self:PostLoot(entry.itemLink)
    end
    wipe(self.lootQueue)
    self:RefreshLootMasterWindow()
end
