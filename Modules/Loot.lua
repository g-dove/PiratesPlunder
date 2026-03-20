---------------------------------------------------------------------------
-- Pirates Plunder – Loot Distribution
-- PostLoot, CancelLoot, AwardItem, ExpressInterest, PostLootQueue have
-- moved to Services/LootService.lua.
-- This file retains loot utilities, queue management, and sync callbacks.
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
-- Receive an interest response (loot master processes this)
---------------------------------------------------------------------------
function PP:ReceiveLootInterest(key, playerName, response, score, comp)
    if not PP.Repo.Loot:GetEntry(key) then return end
    local entry = PP.Repo.Loot:GetEntry(key)
    entry.responses[playerName] = {
        response      = response,
        score         = score,
        roll          = math.random(1, 100),  -- tiebreaker
        equippedLinks = comp and comp.equippedLinks,
    }
    PP.Repo.Loot:Save()
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
    local roster  = PP.Repo.Guild:GetRoster()
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
    local entry = PP.Repo.Loot:GetEntry(key)
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
-- Vote on who should receive an item (officers / raid leader – observer mode)
-- Each voter may hold at most one vote per loot key; casting again replaces the
-- previous vote, allowing observers to change their mind before the item is awarded.
---------------------------------------------------------------------------
function PP:CastVote(key, targetFullName)
    if not PP.Repo.Loot:GetEntry(key) then return end
    local me = self:GetPlayerFullName()
    self:ReceiveVote(key, me, targetFullName)
    self:SendAddonMessage(PP.MSG.LOOT_VOTE, {
        key    = key,
        voter  = me,
        target = targetFullName,
    })
end

function PP:ReceiveVote(key, voterName, targetFullName)
    local entry = PP.Repo.Loot:GetEntry(key)
    if not entry then return end
    if not entry.votes then
        entry.votes = {}
    end
    entry.votes[voterName] = targetFullName
    PP.Repo.Loot:Save()
    self:RefreshLootMasterWindow()
end

---------------------------------------------------------------------------
-- Get list of all pending (unawarded) loot items
---------------------------------------------------------------------------
function PP:GetPendingLootList()
    local list = {}
    for key, entry in pairs(PP.Repo.Loot:GetAll()) do
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
    PP.Repo.Loot:AddToQueue(itemLink)
    if not self.lootMasterWindow then
        self:CreateLootMasterWindow()
    else
        self:RefreshLootMasterWindow()
    end
    self:Print("Added to queue: " .. itemLink)
end

-- Remove one entry from the queue by index
function PP:RemoveFromLootQueue(index)
    table.remove(PP.Repo.Loot:GetQueue(), index)
    self:RefreshLootMasterWindow()
end

-- Toggle transmog responses allowed for a live loot item
function PP:SetLootTransmog(key, allow)
    local entry = PP.Repo.Loot:GetEntry(key)
    if not entry then return end
    entry.allowTransmog = allow
    self:SendAddonMessage(PP.MSG.LOOT_UPDATE, { key = key, allowTransmog = allow })
    self:RefreshLootMasterWindow()
    self:RefreshLootResponseFrame()
end
