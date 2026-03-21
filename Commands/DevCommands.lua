---------------------------------------------------------------------------
-- Pirates Plunder – Dev/utility slash-command handlers
---------------------------------------------------------------------------
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

PP._commandGroups = PP._commandGroups or {}
table.insert(PP._commandGroups, function(input)
    if input == "help" then
        PP:Print("/pp – Toggle main window")
        PP:Print("/pp loot (or /pp l) – Toggle loot-master window")
        PP:Print("/pp response (or /pp r) – Toggle loot response frame")
        PP:Print("/pp version (or /pp v) – Check addon versions across the raid")
        PP:Print("/pp sandbox (or /pp s) – Toggle sandbox mode")
        PP:Print("/pp sandbox mod (or /pp s m) – Toggle canModify override in sandbox")
        PP:Print("/pp session – Show or manage the active loot session")
        PP:Print("/pp roster – Add, remove, clear, or randomize roster entries")
        PP:Print("/pp status – Show officer detection info")
        PP:Print("/pp bagdebug – Diagnose alt+right-click bag hook")
        return true

    elseif input == "loot" or input == "l" then
        PP:SlashCommandLoot()
        return true

    elseif input == "response" or input == "r" then
        PP:SlashCommandResponse()
        return true

    elseif input == "version" or input == "v" then
        PP:ShowVersionCheckWindow()
        return true

    elseif input == "sandbox" or input == "s" then
        if PP:IsSandbox() then
            PP:DisableSandbox()
        else
            PP:EnableSandbox()
        end
        return true

    elseif input == "sandbox mod" or input == "s m" then
        if not PP:IsSandbox() then
            PP:EnableSandbox()
        end
        PP._sandboxModOverride = not PP._sandboxModOverride
        if PP._sandboxModOverride then
            PP:Print("|cFFFFD100[Sandbox] CanModify override: ON — acting as officer.|r")
        else
            PP:Print("|cFF888888[Sandbox] CanModify override: OFF — acting as non-officer.|r")
        end
        PP:RefreshMainWindow()
        return true

    elseif input:match("^setrank%s+(%d+)$") then
        local n = tonumber(input:match("^setrank%s+(%d+)$"))
        PP.db.global.officerRankThreshold = n
        PP._isOfficer = nil  -- force re-detect
        PP:RefreshOfficerStatus()
        PP:Print("Officer rank threshold set to " .. n .. ". Status: " .. (PP._isOfficer and "|cFF00FF00Officer|r" or "|cFFFF4400Not officer|r"))
        PP:RefreshMainWindow()
        return true

    elseif input == "bagdebug" then
        PP:Print("GameTooltip shown: " .. tostring(GameTooltip:IsShown()))
        local _, tipLink = GameTooltip:GetItem()
        PP:Print("Tooltip item link: " .. tostring(tipLink))
        PP:Print("IsMouseButtonDown RightButton: " .. tostring(IsMouseButtonDown("RightButton")))
        return true

    elseif input == "status" then
        PP._isOfficer = nil  -- force re-detect
        PP:RefreshOfficerStatus()
        local inGuild   = IsInGuild() and "yes" or "no"
        local myGuild   = PP:GetPlayerGuild() or "none"
        local activeKey = PP:GetActiveGuildKey()
        local officer   = PP._isOfficer and "|cFF00FF00yes|r" or "|cFFFF4400no|r"
        local canMod    = PP:CanModify() and "|cFF00FF00yes|r" or "|cFFFF4400no|r"
        local apiUsed
        if C_GuildInfo.IsGuildOfficer then
            apiUsed = "C_GuildInfo.IsGuildOfficer()"
        elseif CanUseGuildOfficerChat then
            apiUsed = "CanUseGuildOfficerChat()"
        elseif GuildControlGetRankFlags then
            apiUsed = "GuildControlGetRankFlags (flag 13)"
        else
            apiUsed = "rank index threshold (" .. (PP.db.global.officerRankThreshold or 1) .. ")"
        end
        PP:Print("Guild: " .. inGuild .. " (" .. myGuild .. ")  Active roster: " .. activeKey)
        PP:Print("Officer: " .. officer .. "  Can modify: " .. canMod .. "  API: " .. apiUsed)
        return true
    end

    return false
end)
