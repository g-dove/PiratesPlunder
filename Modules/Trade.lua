---------------------------------------------------------------------------
-- Pirates Plunder – Auto-Trade
---------------------------------------------------------------------------
---@type PPAddon
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

---------------------------------------------------------------------------
-- TRADE_SHOW – trade window opened
---------------------------------------------------------------------------
function PP:OnTradeShow()
    -- Determine who we are trading with
    local name, realm = UnitName("target")
    if not name then return end
    local tradeFullName = PP:GetFullName(name .. (realm and realm ~= "" and ("-" .. realm) or ""))
    self._currentTradePartner = tradeFullName
    self._currentTradeSlotted = {}  -- entries we placed in this trade window

    -- Check if this person has items pending for them
    local itemsToTrade = {}
    for i, pending in ipairs(self.pendingTrades) do
        if pending.awardedTo == tradeFullName then
            itemsToTrade[#itemsToTrade + 1] = {
                index    = i,
                itemID   = pending.itemID,
                itemLink = pending.itemLink,
            }
        end
    end

    if #itemsToTrade == 0 then return end

    -- Try to add items to the trade window
    local tradeSlot = 1
    for _, item in ipairs(itemsToTrade) do
        if tradeSlot > 6 then break end  -- max 6 trade slots

        local bag, slot = self:FindItemInBags(item.itemID)
        if bag and slot then
            C_Container.PickupContainerItem(bag, slot)
            ClickTradeButton(tradeSlot)
            tradeSlot = tradeSlot + 1
            self._currentTradeSlotted[#self._currentTradeSlotted + 1] = {
                itemID   = item.itemID,
                itemLink = item.itemLink,
            }
            self:Print("Auto-added " .. (item.itemLink or "item") .. " to trade window.")
        end
    end
end

---------------------------------------------------------------------------
-- TRADE_CLOSED – remove pending trades for items we placed in the window
---------------------------------------------------------------------------
function PP:OnTradeClosed()
    local partner  = self._currentTradePartner
    local slotted  = self._currentTradeSlotted
    self._currentTradePartner = nil
    self._currentTradeSlotted = nil

    if not partner or not slotted or #slotted == 0 then return end

    -- Remove each slotted item from pendingTrades regardless of whether the
    -- trade was accepted or cancelled: if cancelled the item is back in bags
    -- and the loot master can re-open trade; keeping stale entries causes
    -- them to re-fill on the next trade window open.
    for _, slottedItem in ipairs(slotted) do
        self:RemovePendingTrade(slottedItem.itemID, partner)
    end
    self:RefreshLootMasterWindow()
end

---------------------------------------------------------------------------
-- Find an item in the player's bags by itemID
-- Returns bag, slot  or nil, nil
---------------------------------------------------------------------------
function PP:FindItemInBags(itemID)
    if not itemID then return nil, nil end

    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID then
                return bag, slot
            end
        end
    end
    return nil, nil
end

---------------------------------------------------------------------------
-- Remove a pending trade entry after successful trade
---------------------------------------------------------------------------
function PP:RemovePendingTrade(itemID, awardedTo)
    for i = #self.pendingTrades, 1, -1 do
        local p = self.pendingTrades[i]
        if p.itemID == itemID and p.awardedTo == awardedTo then
            table.remove(self.pendingTrades, i)
            PP.Repo.Loot:Save()
            return
        end
    end
end
