local PP  = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")
local Kit = PP.Kit

local function versionGreater(a, b)
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

function PP:ShowVersionCheckWindow()
    PP._versionCheckData = PP._versionCheckData or {}
    local me = self:GetPlayerFullName()
    PP._versionCheckData[me] = PP.VERSION

    local f = PP._versionCheckWindow
    if not f then
        f = Kit:Window("Pirates Plunder - Version Check", 320, 400)
        f:SetOnClose(function() f:Hide() end)
        PP._versionCheckWindow = f
        PP:RegisterEscFrame(f, "PPVersionCheckFrame")
        PP._versionCheckList = Kit:ScrollList(f.body)
        PP._versionCheckList.frame:SetAllPoints(f.body)
    end

    PP:DrawVersionList()
    f:Show()
    f:Raise()

    if IsInGroup() and not self._sandbox then
        self:SendAddonMessage(PP.MSG.VERSION_REQUEST, {})
    end
end

function PP:UpdateVersionCheckWindow(sender, version)
    if not PP._versionCheckWindow then return end
    PP._versionCheckData[sender] = version
    PP:DrawVersionList()
end

function PP:DrawVersionList()
    local list = PP._versionCheckList
    if not list then return end
    list:Clear()

    local data = PP._versionCheckData or {}
    local maxVer = nil
    for _, v in pairs(data) do
        if maxVer == nil or versionGreater(v, maxVer) then maxVer = v end
    end

    local names = {}
    for name in pairs(data) do names[#names+1] = name end
    table.sort(names)

    list:Add(Kit:Heading(list.child, "Addon Versions (" .. #names .. " response" .. (#names == 1 and "" or "s") .. ")"), 20)

    local me = PP:GetPlayerFullName()
    for _, name in ipairs(names) do
        local ver    = data[name]
        local isTop  = (ver == maxVer)
        local color  = isTop and "|cFFB8FFB8" or "|cFFFFFFFF"
        local short  = PP:GetShortName(name)
        local youTag = (name == me) and " |cFFAAAAAA(you)|r" or ""
        list:Add(Kit:Label(list.child, short .. youTag .. "  " .. color .. ver .. "|r", "body"), 18)
    end

    if #names == 0 then
        list:Add(Kit:Label(list.child, "No responses yet.", "small"), 20)
    end

    list:Layout()
end
