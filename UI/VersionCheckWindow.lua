---------------------------------------------------------------------------
-- Pirates Plunder – Version Check Window
---------------------------------------------------------------------------
local PP    = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")
local AceGUI = PP.AceGUI

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

local function versionGreater(a, b)
    -- Compare dot-separated version strings numerically segment by segment.
    local function parts(v)
        local t = {}
        for n in tostring(v):gmatch("%d+") do t[#t+1] = tonumber(n) end
        return t
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local ai, bi = pa[i] or 0, pb[i] or 0
        if ai ~= bi then return ai > bi end
    end
    return false
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function PP:ShowVersionCheckWindow()
    -- Reset collected data and (re)open the window
    PP._versionCheckData = {}

    -- Record local player immediately
    local me = self:GetPlayerFullName()
    PP._versionCheckData[me] = PP.VERSION

    if PP._versionCheckWindow then
        PP._versionCheckWindow:Release()
        PP._versionCheckWindow = nil
    end

    local f = AceGUI:Create("Frame")
    f:SetTitle("Pirates Plunder – Version Check")
    f:SetLayout("Fill")
    f:SetWidth(320)
    f:SetHeight(400)
    f:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        PP._versionCheckWindow = nil
    end)
    PP._versionCheckWindow = f

    PP:RegisterEscFrame(f, "PPVersionCheckFrame")

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    scroll:SetLayout("List")
    f:AddChild(scroll)
    PP._versionCheckScroll = scroll

    -- Broadcast to raid / party; everyone whispers back
    if IsInGroup() and not self._sandbox then
        self:SendAddonMessage(PP.MSG.VERSION_REQUEST, {})
        local waitLbl = AceGUI:Create("Label")
        waitLbl:SetFullWidth(true)
        waitLbl:SetText("|cFFAAAAAA  Waiting for responses…|r")
        scroll:AddChild(waitLbl)
    else
        -- Not in a group — just show own version
        PP:DrawVersionList()
    end
end

function PP:UpdateVersionCheckWindow(sender, version)
    if not PP._versionCheckWindow then return end
    PP._versionCheckData[sender] = version
    PP:DrawVersionList()
end

function PP:DrawVersionList()
    local scroll = PP._versionCheckScroll
    if not scroll then return end
    scroll:ReleaseChildren()

    local data = PP._versionCheckData or {}

    -- Find the highest version present
    local maxVer = nil
    for _, v in pairs(data) do
        if maxVer == nil or versionGreater(v, maxVer) then
            maxVer = v
        end
    end

    -- Sort player names alphabetically for a stable list
    local names = {}
    for name in pairs(data) do names[#names+1] = name end
    table.sort(names)

    local heading = AceGUI:Create("Heading")
    heading:SetFullWidth(true)
    heading:SetText("Addon Versions  (" .. #names .. " response" .. (#names == 1 and "" or "s") .. ")")
    scroll:AddChild(heading)

    local me = PP:GetPlayerFullName()
    for _, name in ipairs(names) do
        local ver       = data[name]
        local isTop     = (ver == maxVer)
        local color     = isTop and "|cFFB8FFB8" or "|cFFFFFFFF"
        local label     = AceGUI:Create("Label")
        label:SetFullWidth(true)
        local shortName = PP:GetShortName(name)
        local youTag    = (name == me) and " |cFFAAAAAA(you)|r" or ""
        label:SetText("  " .. shortName .. youTag .. "  " .. color .. ver .. "|r")
        scroll:AddChild(label)
    end

    if #names == 0 then
        local empty = AceGUI:Create("Label")
        empty:SetFullWidth(true)
        empty:SetText("|cFFAAAAAA  No responses yet.|r")
        scroll:AddChild(empty)
    end
end
