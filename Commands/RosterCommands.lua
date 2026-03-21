---------------------------------------------------------------------------
-- Pirates Plunder – Roster slash-command handlers
---------------------------------------------------------------------------
---@type PPAddon
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

PP._commandGroups = PP._commandGroups or {}
table.insert(PP._commandGroups, function(input)
    if input:match("^roster add%s+(.+)$") then
        local name = input:match("^roster add%s+(.+)$")
        PP.Roster:Add(name)
        return true

    elseif input:match("^roster remove%s+(.+)$") then
        local name = input:match("^roster remove%s+(.+)$")
        PP.Roster:Remove(name)
        return true

    elseif input == "roster clear" then
        PP.Roster:Clear()
        return true

    elseif input == "roster randomize" then
        PP.Roster:Randomize()
        return true
    end

    return false
end)
