---------------------------------------------------------------------------
-- Pirates Plunder – Roster & Scoring
-- All roster manipulation has moved to Services/RosterService.lua.
-- This file retains only the boss-kill event handler.
---------------------------------------------------------------------------
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

---------------------------------------------------------------------------
-- Boss kill handler
---------------------------------------------------------------------------
function PP:OnBossKill(encounterID, encounterName)
    -- Record the boss in the active session
    PP.Session:AddBoss(encounterID, encounterName)
    -- +1 score to all raid members
    PP.Roster:AddScoreToRaidMembers(1)
    self:Print("Boss defeated: " .. (encounterName or "Unknown") .. " – +1 score to all raid members!")
end
