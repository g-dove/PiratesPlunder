---------------------------------------------------------------------------
-- Pirates Plunder – Minimap Icon
---------------------------------------------------------------------------
---@type PPAddon
local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

local ICON_CUSTOM = "Interface\\AddOns\\PiratesPlunder\\Media\\icon"

function PP:SetupMinimapIcon()
    local ldb  = LibStub("LibDataBroker-1.1")
    local icon = LibStub("LibDBIcon-1.0")

    local broker = ldb:NewDataObject("PiratesPlunder", {
        type = "launcher",
        text = "Pirates Plunder",
        icon = ICON_CUSTOM,
        OnClick = function(_, button)
            if button == "LeftButton" then
                PP:ToggleMainWindow()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Pirates Plunder")
            tooltip:AddLine("|cFFAAAAAA Left-click to open/close|r")
        end,
    })

    icon:Register("PiratesPlunder", broker, self.db.global.minimapIcon)
end
