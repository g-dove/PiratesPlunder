---------------------------------------------------------------------------
-- Pirates Plunder – Loot Distribution
---------------------------------------------------------------------------
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

-- Maps an item's equipLoc string to the inventory slot ID(s) that hold it.
-- Dual-slot types (rings, trinkets) list both slots so we can pick the best.
local EQUIP_SLOT_MAP = {
    INVTYPE_HEAD           = { 1 },
    INVTYPE_NECK           = { 2 },
    INVTYPE_SHOULDER       = { 3 },
    INVTYPE_CHEST          = { 5 },
    INVTYPE_ROBE           = { 5 },
    INVTYPE_WAIST          = { 6 },
    INVTYPE_LEGS           = { 7 },
    INVTYPE_FEET           = { 8 },
    INVTYPE_WRIST          = { 9 },
    INVTYPE_HAND           = { 10 },
    INVTYPE_FINGER         = { 11, 12 },  -- both ring slots
    INVTYPE_TRINKET        = { 13, 14 },  -- both trinket slots
    INVTYPE_CLOAK          = { 15 },
    INVTYPE_WEAPON         = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_2HWEAPON       = { 16 },
    INVTYPE_SHIELD         = { 17 },
    INVTYPE_WEAPONOFFHAND  = { 17 },
    INVTYPE_HOLDABLE       = { 17 },
    INVTYPE_RANGED         = { 18 },
    INVTYPE_RANGEDRIGHT    = { 18 },
}

---------------------------------------------------------------------------
-- Post an item for distribution (officer / raid leader only)
---------------------------------------------------------------------------
function PP:PostLoot(itemLink)
    if not self:HasActiveRaid() then
        self:Print("No active raid.")
        return
    end
    if not self:CanPostLoot() then
        self:Print("Only the raid leader can post loot for this roster.")
        return
    end

    -- Try to get itemID from cache; fall back to parsing the link directly
    local itemID = C_Item.GetItemInfoInstant(itemLink)
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
        votes         = {},  -- voterFullName => targetFullName
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
-- Build equipped-item comparison data for the local player against a new item.
-- Returns nil if the item is not equippable or GetItemInfo data is unavailable.
-- Only the equipped item links are returned; ilvl diffs are computed by the
-- loot master locally to keep the message payload small.
--
-- Special case: if the new item is an off-hand piece and the off-hand slot is
-- empty, check whether a two-handed weapon is equipped in the main-hand slot
-- and return that instead – equipping an off-hand requires unequipping the 2H.
---------------------------------------------------------------------------
function PP:GetEquippedComparisonData(newItemLink)
    if not newItemLink then return nil end
    local _, _, _, _, _, _, _, _, equipLoc, _ = C_Item.GetItemInfo(newItemLink)
    if not equipLoc or equipLoc == "" then return nil end

    local slots = EQUIP_SLOT_MAP[equipLoc]
    if not slots then return nil end

    local equippedLinks = {}
    for _, slotID in ipairs(slots) do
        local equippedLink = GetInventoryItemLink("player", slotID)
        if equippedLink then
            equippedLinks[#equippedLinks + 1] = equippedLink
        end
    end

    -- Off-hand fallback: if the off-hand slot (17) is one of the target slots
    -- and nothing was found there, check whether a 2H weapon fills slot 16.
    -- Equipping an off-hand forces the 2H to be unequipped, so it is the
    -- relevant comparison item.
    local isOffhand = (equipLoc == "INVTYPE_SHIELD"
                    or equipLoc == "INVTYPE_WEAPONOFFHAND"
                    or equipLoc == "INVTYPE_HOLDABLE")
    if isOffhand and #equippedLinks == 0 then
        local mhLink = GetInventoryItemLink("player", 16)
        if mhLink then
            local _, _, _, _, _, _, _, _, mhEquipLoc = C_Item.GetItemInfo(mhLink)
            if mhEquipLoc == "INVTYPE_2HWEAPON" then
                equippedLinks[1] = mhLink
            end
        end
    end

    -- Return even if equippedLinks is empty so the loot master knows
    -- this slot exists (they can show "empty slot" in the UI).
    return { equippedLinks = equippedLinks }
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

    -- For NEED/MINOR responses, collect equipped-item comparison data.
    local comp = nil
    if response == PP.RESPONSE.NEED or response == PP.RESPONSE.MINOR then
        local entry = self.pendingLoot[key]
        if entry and entry.itemLink then
            comp = self:GetEquippedComparisonData(entry.itemLink)
        end
    end

    -- Record locally immediately (OnCommReceived filters out self-messages,
    -- so we cannot rely on the broadcast looping back to us)
    self:ReceiveLootInterest(key, me, response, score, comp)

    -- Broadcast to everyone else in the group
    self:SendAddonMessage(PP.MSG.LOOT_INTEREST, {
        key           = key,
        player        = me,
        response      = response,
        score         = score,
        equippedLinks = comp and comp.equippedLinks,
    })

    self:SavePendingLoot()
    self:RefreshLootResponseFrame()
end

---------------------------------------------------------------------------
-- Receive an interest response (loot master processes this)
---------------------------------------------------------------------------
function PP:ReceiveLootInterest(key, playerName, response, score, comp)
    if not self.pendingLoot[key] then return end
    self.pendingLoot[key].responses[playerName] = {
        response      = response,
        score         = score,
        roll          = math.random(1, 100),  -- tiebreaker
        equippedLinks = comp and comp.equippedLinks,
    }
    self:SavePendingLoot()
    self:RefreshLootMasterWindow()

    -- C_Item.GetItemInfo returns nil for uncached items and queues a server
    -- fetch.  Schedule a deferred re-render so equipped-item icons and ilvl
    -- diffs appear once the data arrives rather than waiting for the next
    -- manual action (e.g. voting) to trigger a refresh.
    if comp and comp.equippedLinks and #comp.equippedLinks > 0 then
        local needsDeferred = false
        for _, eLink in ipairs(comp.equippedLinks) do
            if not C_Item.GetItemInfo(eLink) then
                needsDeferred = true
            end
        end
        if needsDeferred then
            self:ScheduleTimer(function()
                self:RefreshLootMasterWindow()
            end, 2)
        end
    end
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
                fullName      = fullName,
                name          = self:GetShortName(fullName),
                response      = resp.response,
                score         = resp.score,
                roll          = resp.roll,
                equippedLinks = resp.equippedLinks,
                voteCount     = 0,  -- filled below
            }
        end
    end

    -- Count votes per target from the votes table
    local votes = entry.votes or {}
    for _, target in pairs(votes) do
        for _, r in ipairs(list) do
            if r.fullName == target then
                r.voteCount = r.voteCount + 1
                break
            end
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
-- Pass free=true to award without deducting any points from their score.
---------------------------------------------------------------------------
function PP:AwardItem(key, fullName, free)
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
        if free then
            -- Free award: keep score exactly as-is
            pointsSpent = 0
            newScore    = currentScore
        elseif winnerResponse == PP.RESPONSE.TRANSMOG then
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
    C_ChatInfo.SendChatMessage(
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
-- Vote on who should receive an item (officers / raid leader – observer mode)
-- Each voter may hold at most one vote per loot key; casting again replaces the
-- previous vote, allowing observers to change their mind before the item is awarded.
---------------------------------------------------------------------------
function PP:CastVote(key, targetFullName)
    if not self.pendingLoot[key] then return end
    local me = self:GetPlayerFullName()
    self:ReceiveVote(key, me, targetFullName)
    self:SendAddonMessage(PP.MSG.LOOT_VOTE, {
        key    = key,
        voter  = me,
        target = targetFullName,
    })
end

function PP:ReceiveVote(key, voterName, targetFullName)
    if not self.pendingLoot[key] then return end
    if not self.pendingLoot[key].votes then
        self.pendingLoot[key].votes = {}
    end
    self.pendingLoot[key].votes[voterName] = targetFullName
    self:SavePendingLoot()
    self:RefreshLootMasterWindow()
end

---------------------------------------------------------------------------
-- Close all loot popups
---------------------------------------------------------------------------
function PP:CloseLootPopups()    for key, frame in pairs(self.lootPopups) do
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
