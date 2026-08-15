local PP = LibStub("AceAddon-3.0"):GetAddon("PiratesPlunder")

local Kit = {}
PP.Kit = Kit

Kit.Palette = {
    backdrop    = {0.05, 0.05, 0.07, 0.96},
    panel       = {0.10, 0.10, 0.13, 0.90},
    panelLight  = {0.14, 0.14, 0.18, 0.90},
    border      = {0.34, 0.28, 0.14, 0.85},
    accent      = {0.86, 0.66, 0.20, 1.0},
    accentDim   = {0.86, 0.66, 0.20, 0.35},
    good        = {0.30, 0.85, 0.35, 1.0},
    bad         = {0.90, 0.30, 0.30, 1.0},
    text        = {0.92, 0.92, 0.90, 1.0},
    textDim     = {0.62, 0.60, 0.58, 1.0},
    fieldBg     = {0.03, 0.03, 0.04, 1.0},
    rowA        = {1, 1, 1, 0.02},
    rowB        = {1, 1, 1, 0.00},
    hover       = {1, 1, 1, 0.06},
}

local FONT = "Fonts\\FRIZQT__.TTF"
local FontTitle  = CreateFont("PPFontTitle")
FontTitle:SetFont(FONT, 16, "OUTLINE")
local FontHead   = CreateFont("PPFontHead")
FontHead:SetFont(FONT, 13, "OUTLINE")
local FontBody   = CreateFont("PPFontBody")
FontBody:SetFont(FONT, 12, "")
local FontSmall  = CreateFont("PPFontSmall")
FontSmall:SetFont(FONT, 11, "")

Kit.Font = { title = FontTitle, head = FontHead, body = FontBody, small = FontSmall }

local function tint(region, c, a)
    region:SetColorTexture(c[1], c[2], c[3], a or c[4] or 1)
end
Kit.Tint = tint

function Kit:Fill(parent, c)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(parent)
    tint(t, c)
    return t
end

function Kit:Rule(parent, c, h)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(h or 1)
    tint(t, c)
    return t
end

function Kit:Panel(parent)
    local f = CreateFrame("Frame", nil, parent)
    Kit:Fill(f, Kit.Palette.panel)
    local top = Kit:Rule(f, Kit.Palette.border, 1)
    top:SetPoint("TOPLEFT", f, "TOPLEFT")
    top:SetPoint("TOPRIGHT", f, "TOPRIGHT")
    local bot = Kit:Rule(f, Kit.Palette.border, 1)
    bot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
    bot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
    return f
end

---------------------------------------------------------------------------
-- Button
---------------------------------------------------------------------------
function Kit:Button(parent, text, onClick, kind)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetHeight(22)
    b:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    local lbl = b:CreateFontString(nil, "OVERLAY", "PPFontBody")
    lbl:SetAllPoints(b)
    lbl:SetJustifyH("CENTER")
    lbl:SetTextColor(Kit.Palette.text[1], Kit.Palette.text[2], Kit.Palette.text[3])
    lbl:SetText(text or "")
    b._lbl = lbl
    b.SetText = function(_, t) lbl:SetText(t) end
    b.GetFontString = function() return lbl end

    local isDanger = (kind == "danger")

    local function rest()
        if isDanger then
            b:SetBackdropColor(0.14, 0.05, 0.05, 1)
            b:SetBackdropBorderColor(Kit.Palette.bad[1], Kit.Palette.bad[2], Kit.Palette.bad[3], 0.75)
        else
            b:SetBackdropColor(0.11, 0.10, 0.08, 1)
            b:SetBackdropBorderColor(Kit.Palette.border[1], Kit.Palette.border[2], Kit.Palette.border[3], Kit.Palette.border[4] or 1)
        end
    end
    rest()

    b:SetScript("OnEnter", function()
        if isDanger then
            b:SetBackdropColor(0.22, 0.07, 0.07, 1)
        else
            b:SetBackdropColor(0.20, 0.16, 0.06, 1)
        end
        b:SetBackdropBorderColor(Kit.Palette.accent[1], Kit.Palette.accent[2], Kit.Palette.accent[3], 0.9)
    end)
    b:SetScript("OnLeave", rest)
    if onClick then b:SetScript("OnClick", onClick) end

    b.SetDisabled = function(_, dis)
        b:EnableMouse(not dis)
        lbl:SetTextColor(dis and 0.45 or Kit.Palette.text[1],
                          dis and 0.45 or Kit.Palette.text[2],
                          dis and 0.45 or Kit.Palette.text[3])
    end

    return b
end

---------------------------------------------------------------------------
-- Checkbox
---------------------------------------------------------------------------
function Kit:Checkbox(parent, text, onChange)
    local f = CreateFrame("Button", nil, parent)
    f:SetHeight(20)

    local box = f:CreateTexture(nil, "BACKGROUND")
    box:SetSize(16, 16)
    box:SetPoint("LEFT", f, "LEFT", 0, 0)
    tint(box, Kit.Palette.border)

    local inner = f:CreateTexture(nil, "ARTWORK")
    inner:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
    tint(inner, Kit.Palette.fieldBg)

    local check = f:CreateTexture(nil, "OVERLAY")
    check:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
    check:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
    tint(check, Kit.Palette.accent)
    check:Hide()

    local lbl = f:CreateFontString(nil, "OVERLAY", "PPFontBody")
    lbl:SetPoint("LEFT", box, "RIGHT", 6, 0)
    lbl:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetText(text or "")
    lbl:SetTextColor(Kit.Palette.text[1], Kit.Palette.text[2], Kit.Palette.text[3])

    local checked = false
    f.SetValue = function(_, v) checked = v and true or false; check:SetShown(checked) end
    f.GetValue = function() return checked end
    f.SetDisabled = function(_, dis)
        f:EnableMouse(not dis)
        lbl:SetTextColor(dis and 0.45 or Kit.Palette.text[1],
                          dis and 0.45 or Kit.Palette.text[2],
                          dis and 0.45 or Kit.Palette.text[3])
    end

    f:SetScript("OnClick", function()
        checked = not checked
        check:SetShown(checked)
        if onChange then onChange(checked) end
    end)

    return f
end

---------------------------------------------------------------------------
-- EditBox
---------------------------------------------------------------------------
function Kit:EditBox(parent, width, onEnter)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 150, 20)
    Kit:Fill(f, Kit.Palette.fieldBg)
    local border = Kit:Rule(f, Kit.Palette.border, 1)
    border:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
    border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")

    local eb = CreateFrame("EditBox", nil, f)
    eb:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -3)
    eb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 3)
    eb:SetAutoFocus(false)
    eb:SetFontObject("PPFontBody")
    eb:SetTextColor(Kit.Palette.text[1], Kit.Palette.text[2], Kit.Palette.text[3])
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if onEnter then
        eb:SetScript("OnEnterPressed", function(self)
            onEnter(self:GetText())
            self:ClearFocus()
        end)
    end
    f._eb = eb
    f.SetText = function(_, t) eb:SetText(t or "") end
    f.GetText = function() return eb:GetText() end
    f.SetNumeric = function(_, v) eb:SetNumeric(v) end
    return f
end

---------------------------------------------------------------------------
-- Dropdown (button + scrollable popup)
---------------------------------------------------------------------------
function Kit:Dropdown(parent, width, onSelect)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 180, 22)
    Kit:Fill(btn, Kit.Palette.fieldBg)
    local border = Kit:Rule(btn, Kit.Palette.border, 1)
    border:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT")
    border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT")

    local lbl = btn:CreateFontString(nil, "OVERLAY", "PPFontBody")
    lbl:SetPoint("LEFT", btn, "LEFT", 6, 0)
    lbl:SetPoint("RIGHT", btn, "RIGHT", -16, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetTextColor(Kit.Palette.text[1], Kit.Palette.text[2], Kit.Palette.text[3])

    local arrow = btn:CreateFontString(nil, "OVERLAY", "PPFontSmall")
    arrow:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    arrow:SetText("v")
    arrow:SetTextColor(Kit.Palette.textDim[1], Kit.Palette.textDim[2], Kit.Palette.textDim[3])

    local popup = CreateFrame("Frame", nil, UIParent)
    popup:SetFrameStrata("TOOLTIP")
    popup:Hide()
    Kit:Fill(popup, {0.04, 0.04, 0.05, 0.98})
    local pb = Kit:Rule(popup, Kit.Palette.border, 1)
    pb:SetPoint("TOPLEFT", popup, "TOPLEFT")
    pb:SetPoint("TOPRIGHT", popup, "TOPRIGHT")
    local pb2 = Kit:Rule(popup, Kit.Palette.border, 1)
    pb2:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT")
    pb2:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT")

    local rows = {}
    local items = {}
    local rowH = 20

    local function hide()
        popup:Hide()
        if Kit._openDropdown == popup then Kit._openDropdown = nil end
    end

    local function build()
        for _, r in ipairs(rows) do r:Hide() end
        local y = -2
        for i, it in ipairs(items) do
            local r = rows[i]
            if not r then
                r = CreateFrame("Button", nil, popup)
                r:SetHeight(rowH)
                local rb = r:CreateTexture(nil, "BACKGROUND")
                rb:SetAllPoints(r)
                r._bg = rb
                local rBorder = CreateFrame("Frame", nil, r, "BackdropTemplate")
                rBorder:SetAllPoints(r)
                rBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
                rBorder:SetBackdropBorderColor(Kit.Palette.accent[1], Kit.Palette.accent[2], Kit.Palette.accent[3], 0.85)
                rBorder:Hide()
                r._border = rBorder
                local rl = r:CreateFontString(nil, "OVERLAY", "PPFontBody")
                rl:SetPoint("LEFT", r, "LEFT", 6, 0)
                rl:SetPoint("RIGHT", r, "RIGHT", -4, 0)
                rl:SetJustifyH("LEFT")
                r._lbl = rl
                r:SetScript("OnEnter", function() tint(rb, Kit.Palette.hover); rBorder:Show() end)
                r:SetScript("OnLeave", function() tint(rb, {0,0,0,0}); rBorder:Hide() end)
                rows[i] = r
            end
            r:SetPoint("TOPLEFT", popup, "TOPLEFT", 2, y)
            r:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -2, y)
            r._lbl:SetText(it.label or tostring(it.value))
            r._lbl:SetTextColor(Kit.Palette.text[1], Kit.Palette.text[2], Kit.Palette.text[3])
            tint(r._bg, {0,0,0,0})
            r:SetScript("OnClick", function()
                lbl:SetText(it.label or tostring(it.value))
                hide()
                if onSelect then onSelect(it.value) end
            end)
            r:Show()
            y = y - rowH
        end
        popup:SetHeight(math.max(rowH, -y + 2))
        popup:SetWidth(btn:GetWidth())
    end

    btn:SetScript("OnClick", function()
        if popup:IsShown() then hide(); return end
        if Kit._openDropdown and Kit._openDropdown ~= popup then Kit._openDropdown:Hide() end
        Kit._openDropdown = popup
        build()
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
        popup:Show()
    end)

    local dismissLayer = CreateFrame("Frame", nil, UIParent)
    dismissLayer:SetFrameStrata("DIALOG")
    dismissLayer:SetAllPoints(UIParent)
    dismissLayer:Hide()
    dismissLayer:EnableMouse(false)

    local function dismiss()
        dismissLayer:EnableMouse(false)
        dismissLayer:Hide()
        hide()
    end
    dismissLayer:SetScript("OnMouseDown", dismiss)

    popup:HookScript("OnShow", function()
        dismissLayer:Show()
        dismissLayer:EnableMouse(true)
    end)
    popup:HookScript("OnHide", function()
        dismissLayer:EnableMouse(false)
        dismissLayer:Hide()
    end)

    btn.SetItems = function(_, list) items = list end
    btn.SetLabel = function(_, text) lbl:SetText(text or "") end
    return btn
end

---------------------------------------------------------------------------
-- Heading (section title with a rule)
---------------------------------------------------------------------------
function Kit:Heading(parent, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(20)
    local bar = f:CreateTexture(nil, "ARTWORK")
    bar:SetSize(2, 12)
    bar:SetPoint("LEFT", f, "LEFT", 0, 0)
    tint(bar, Kit.Palette.accent)
    local lbl = f:CreateFontString(nil, "OVERLAY", "PPFontHead")
    lbl:SetPoint("LEFT", bar, "RIGHT", 6, 0)
    lbl:SetText(text or "")
    lbl:SetTextColor(Kit.Palette.accent[1], Kit.Palette.accent[2], Kit.Palette.accent[3])
    return f
end

---------------------------------------------------------------------------
-- Label
---------------------------------------------------------------------------
function Kit:Label(parent, text, fontKey)
    local fs = parent:CreateFontString(nil, "OVERLAY", "PPFont" .. (fontKey or "Body"):gsub("^%l", string.upper))
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    fs:SetTextColor(Kit.Palette.text[1], Kit.Palette.text[2], Kit.Palette.text[3])
    return fs
end

---------------------------------------------------------------------------
-- ScrollList — vertical stack of rows inside a scroll frame; caller
-- appends widgets via :Add(widget, height) and finishes with :Layout()
---------------------------------------------------------------------------
function Kit:ScrollList(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:EnableMouseWheel(true)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(1)
    child:SetHeight(1)
    scroll:SetScrollChild(child)

    local track = CreateFrame("Frame", nil, parent)
    track:SetWidth(4)
    track:SetPoint("TOP", parent, "TOP", -2, 0)
    track:SetPoint("BOTTOM", parent, "BOTTOM", -2, 0)
    track:SetPoint("RIGHT", parent, "RIGHT", -2, 0)
    Kit:Fill(track, {1, 1, 1, 0.05})
    track:Hide()

    local sb = CreateFrame("Slider", nil, parent)
    sb:SetOrientation("VERTICAL")
    sb:SetWidth(4)
    sb:SetPoint("TOP", track, "TOP", 0, 0)
    sb:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
    sb:SetPoint("RIGHT", track, "RIGHT", 0, 0)
    sb:SetHitRectInsets(-4, -4, 0, 0)
    sb:EnableMouse(true)
    sb:SetValueStep(1)
    -- Row content nests several frame levels below `parent` (content -> child
    -- -> row), and a deeper level always wins the mouse hit-test on overlap.
    -- Without this, any row under the thumb/track eats the drag/click.
    sb:SetFrameLevel(child:GetFrameLevel() + 10)
    track:SetFrameLevel(child:GetFrameLevel() + 10)
    local thumbTex = sb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetWidth(4)
    thumbTex:SetHeight(40)
    tint(thumbTex, Kit.Palette.accent, 0.75)
    sb:SetThumbTexture(thumbTex)
    sb:Hide()

    local suppress = false
    sb:SetScript("OnValueChanged", function(_, value)
        if suppress then return end
        scroll:SetVerticalScroll(value)
    end)

    local function syncScrollbar()
        local range = scroll:GetVerticalScrollRange() or 0
        if range <= 1 then
            sb:Hide()
            track:Hide()
            return
        end
        track:Show()
        sb:Show()
        suppress = true
        sb:SetMinMaxValues(0, range)
        local viewH = math.max(1, scroll:GetHeight() or 1)
        local contentH = viewH + range
        thumbTex:SetHeight(math.max(20, (track:GetHeight() or 1) * (viewH / contentH)))
        sb:SetValue(scroll:GetVerticalScroll())
        suppress = false
    end

    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        local newVal = math.max(0, math.min(range, self:GetVerticalScroll() - delta * 32))
        self:SetVerticalScroll(newVal)
        suppress = true
        sb:SetValue(newVal)
        suppress = false
    end)

    local api = {}
    local entries = {}
    local savedScroll = 0

    function api:Add(widget, height, gapAfter, stretch)
        entries[#entries + 1] = { widget = widget, height = height, gap = gapAfter or 6, stretch = stretch ~= false }
    end

    function api:Clear()
        savedScroll = scroll:GetVerticalScroll() or 0
        for _, e in ipairs(entries) do
            if e.widget.Hide then e.widget:Hide() end
            if e.widget.SetParent then e.widget:SetParent(nil) end
        end
        wipe(entries)
    end

    function api:Layout()
        child:SetWidth(math.max(1, scroll:GetWidth()))
        local y = 0
        for _, e in ipairs(entries) do
            e.widget:ClearAllPoints()
            e.widget:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
            if e.stretch then
                e.widget:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
            end
            y = y + (e.height or 20) + e.gap
        end
        child:SetHeight(math.max(y, scroll:GetHeight() or 1))
        if savedScroll > 0 then
            local range = scroll:GetVerticalScrollRange() or 0
            scroll:SetVerticalScroll(math.min(savedScroll, range))
        end
        syncScrollbar()
        C_Timer.After(0, syncScrollbar)
    end

    -- The scrollbar overlay (track/sb) lives outside the ScrollFrame's own
    -- hierarchy (sibling of `scroll`, not a descendant), so hiding `api.frame`
    -- alone leaves it on screen. Callers that need to hide/show the whole
    -- list (e.g. switching between tabs that each keep their own persistent
    -- list) should go through this instead of touching api.frame directly.
    function api:SetShown(shown)
        if shown then
            scroll:Show()
            syncScrollbar()
        else
            scroll:Hide()
            track:Hide()
            sb:Hide()
        end
    end

    api.frame = scroll
    api.child = child
    return api
end

---------------------------------------------------------------------------
-- Row helper — horizontal flex row (children packed left to right)
---------------------------------------------------------------------------
function Kit:Row(parent, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(height or 22)
    return f
end

function Kit:PackLeft(row, widgets, gap)
    gap = gap or 6
    local prev
    for _, w in ipairs(widgets) do
        w:ClearAllPoints()
        if prev then
            w:SetPoint("LEFT", prev, "RIGHT", gap, 0)
        else
            w:SetPoint("LEFT", row, "LEFT", 0, 0)
        end
        prev = w
    end
end

---------------------------------------------------------------------------
-- Window shell — draggable, resizable frame with title bar and close button
---------------------------------------------------------------------------
function Kit:Window(title, w, h)
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetToplevel(true)

    Kit:Fill(f, Kit.Palette.backdrop)
    local border = CreateFrame("Frame", nil, f, "BackdropTemplate")
    border:SetAllPoints(f)
    border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    border:SetBackdropBorderColor(Kit.Palette.border[1], Kit.Palette.border[2], Kit.Palette.border[3], 1)

    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT")
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT")
    titleBar:SetHeight(28)
    Kit:Fill(titleBar, Kit.Palette.panelLight)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:Raise(); f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f:SetScript("OnMouseDown", function() f:Raise() end)

    local rule = Kit:Rule(f, Kit.Palette.accent, 2)
    rule:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT")
    rule:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT")

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "PPFontTitle")
    titleLbl:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleLbl:SetTextColor(Kit.Palette.text[1], Kit.Palette.text[2], Kit.Palette.text[3])
    titleLbl:SetText(title or "")
    f._titleLbl = titleLbl
    f.SetTitle = function(_, t) titleLbl:SetText(t or "") end

    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
    local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY", "PPFontHead")
    closeLbl:SetAllPoints(closeBtn)
    closeLbl:SetJustifyH("CENTER")
    closeLbl:SetText("x")
    closeLbl:SetTextColor(Kit.Palette.textDim[1], Kit.Palette.textDim[2], Kit.Palette.textDim[3])
    closeBtn:SetScript("OnEnter", function() closeLbl:SetTextColor(Kit.Palette.bad[1], Kit.Palette.bad[2], Kit.Palette.bad[3]) end)
    closeBtn:SetScript("OnLeave", function() closeLbl:SetTextColor(Kit.Palette.textDim[1], Kit.Palette.textDim[2], Kit.Palette.textDim[3]) end)
    f._closeBtn = closeBtn

    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 10, -10)
    body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    f.body = body

    f.SetOnClose = function(_, fn)
        closeBtn:SetScript("OnClick", fn)
    end

    f:Raise()
    return f
end

---------------------------------------------------------------------------
-- Tab strip — horizontal tabs above a content area; caller supplies panels
---------------------------------------------------------------------------
function Kit:TabStrip(parent, tabs, onSelect)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(24)

    local buttons = {}
    local active = tabs[1] and tabs[1].value

    local function paint()
        for value, b in pairs(buttons) do
            if value == active then
                tint(b._bg, Kit.Palette.accent, 0.85)
                b._lbl:SetTextColor(0.08, 0.08, 0.08)
            else
                tint(b._bg, Kit.Palette.panelLight, 1)
                b._lbl:SetTextColor(Kit.Palette.text[1], Kit.Palette.text[2], Kit.Palette.text[3])
            end
        end
    end

    local prev
    for _, tabDef in ipairs(tabs) do
        local b = CreateFrame("Button", nil, bar)
        b:SetSize(100, 24)
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
        else
            b:SetPoint("LEFT", bar, "LEFT", 0, 0)
        end
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(b)
        b._bg = bg
        local lbl = b:CreateFontString(nil, "OVERLAY", "PPFontBody")
        lbl:SetAllPoints(b)
        lbl:SetJustifyH("CENTER")
        lbl:SetText(tabDef.text)
        b._lbl = lbl
        b:SetScript("OnClick", function()
            active = tabDef.value
            paint()
            if onSelect then onSelect(tabDef.value) end
        end)
        buttons[tabDef.value] = b
        prev = b
    end
    bar:SetWidth(#tabs * 102 - 2)
    paint()

    bar.Select = function(_, value)
        active = value
        paint()
        if onSelect then onSelect(value) end
    end
    return bar
end

return Kit
