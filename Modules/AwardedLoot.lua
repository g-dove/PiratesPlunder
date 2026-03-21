---------------------------------------------------------------------------
-- Pirates Plunder – Per-Player Awarded Loot History (backend)
--
-- Raid history is the single source of truth. This module scans all
-- raid records across all guild data blocks to build a player's loot
-- history on demand — nothing extra is written to the DB.
--
-- Each returned entry contains:
--   itemLink, itemID, response, pointsSpent, awardedAt (time()),
--   raidName, raidID, guildKey
--
-- Public API:
--   PP:GetPlayerAwardedLoot(fullName)  → list, newest-first
---------------------------------------------------------------------------
---@type PPAddon
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

---------------------------------------------------------------------------
-- Retrieve loot history for a player by scanning all raid records
---------------------------------------------------------------------------
function PP:GetPlayerAwardedLoot(fullName)
    local list = {}

    -- Determine which data blocks to search.
    -- In sandbox mode, only the transient in-memory block is relevant.
    local blocks = {}
    if self._sandbox and self._sandboxData then
        blocks["__sandbox__"] = self._sandboxData
    else
        if self.db and self.db.global and self.db.global.guilds then
            for k, gd in pairs(self.db.global.guilds) do
                blocks[k] = gd
            end
        end
    end

    for guildKey, gd in pairs(blocks) do
        if gd.sessions then
            for raidID, raid in pairs(gd.sessions) do
                if raid.items then
                    for _, item in ipairs(raid.items) do
                        if item.awardedTo == fullName then
                            list[#list + 1] = {
                                itemLink    = item.itemLink,
                                itemID      = item.itemID,
                                response    = item.response,
                                pointsSpent = item.pointsSpent,
                                awardedAt   = item.time,
                                raidName    = raid.name,
                                raidID      = raidID,
                                guildKey    = guildKey,
                            }
                        end
                    end
                end
            end
        end
    end

    table.sort(list, function(a, b)
        return (a.awardedAt or 0) > (b.awardedAt or 0)
    end)
    return list
end
