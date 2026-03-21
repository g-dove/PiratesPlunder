---------------------------------------------------------------------------
-- Pirates Plunder – Raid Management
-- Session lifecycle has moved to Services/SessionService.lua.
-- This file retains only the session history query helper.
---------------------------------------------------------------------------
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

---------------------------------------------------------------------------
-- Session history helpers
---------------------------------------------------------------------------
function PP:GetRaidHistory()
    local list = {}
    for id, raid in pairs(PP.Repo.Roster:GetSessions()) do
        list[#list + 1] = {
            id        = id,
            name      = raid.name,
            startTime = raid.startTime or raid.startedAt or 0,
            endTime   = raid.endTime,
            leader    = raid.leader,
            active    = raid.active,
            bossCount = #raid.bosses,
            itemCount = #raid.items,
        }
    end
    table.sort(list, function(a, b) return a.startTime > b.startTime end)
    return list
end
