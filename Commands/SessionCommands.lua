---------------------------------------------------------------------------
-- Pirates Plunder – Session slash-command handlers
---------------------------------------------------------------------------
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

PP._commandGroups = PP._commandGroups or {}
table.insert(PP._commandGroups, function(input)
    if input == "session" then
        -- Show status
        if PP.Repo.Roster:HasActiveSession() then
            local session, id = PP.Repo.Roster:GetActiveSession()
            PP:Print("Active session: " .. (session and session.name or id))
        else
            PP:Print("No active session.")
        end
        return true

    elseif input:match("^session new") then
        local name = input:match("^session new%s+(.+)$")
        PP.Session:Create(name)
        return true

    elseif input == "session end" then
        if not PP:CanModify() then
            PP:Print("Only officers can end a session.")
            return true
        end
        PP.Session:End(PP.SESSION_END.OFFICER_ACTION)
        return true
    end

    return false
end)
