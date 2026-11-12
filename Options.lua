-- KuiNameplates: settings panel under Options > AddOns.
-- Built from plain frames (no option templates) so it works across client versions.
local _, ns = ...

local SOLID = "Interface\\Buttons\\WHITE8X8"
local COLUMN_WIDTH = 270
local CONTROL_WIDTH = 230

-- The panel is two columns of sections. Each entry is one control:
--   { "check", key, label }
--   { "slider", key, label, min, max, step }
--   { "dropdown", key, label, values, names }
--   { "button", label, onClick }
local function Layout()
    return {
        { -- left column
            { title = "Appearance",
              { "slider", "scale", "Overall size", 0.5, 2, 0.05 },
              { "slider", "width", "Bar width", 40, 300, 2 },
              { "slider", "height", "Bar height", 4, 40, 1 },
              { "slider", "nameSize", "Name font size", 6, 24, 1 },
              { "slider", "nonTargetAlpha", "Opacity of plates you aren't targeting", 0, 1, 0.05 },
            },
            { title = "Units",
              { "check", "classColors", "Class colours on enemy players" },
              { "check", "healthText", "Show health percent" },
              { "check", "showLevel", "Show level" },
              { "check", "tankMode", "Tank mode (colour bars by threat)" },
              { "check", "nameOnly", "Friendly units: name only, no bar" },
              { "slider", "nameOnlyOffset", "Friendly name height", -40, 60, 1 },
            },
        },
        { -- right column
            { title = "Cast bars",
              { "check", "castBars", "Show cast bars" },
              { "slider", "castHeight", "Cast bar height", 2, 20, 1 },
            },
            { title = "Debuffs",
              { "check", "auras", "Show your debuffs on enemies" },
              { "check", "auraColors", "Colour borders by type (poison, curse...)" },
              { "dropdown", "auraSpot", "Position", ns.AURA_SPOTS, ns.AURA_SPOT_NAMES },
              { "slider", "auraWidth", "Icon size", 12, 40, 1 },
              { "slider", "auraOffset", "Distance from the bar", -20, 40, 1 },
            },
            { title = "Other",
              { "slider", "maxDistance", "Max nameplate distance (yards)", 10, 100, 1 },
              { "check", "minimapButton", "Show minimap button" },
              { "button", "Reset to defaults", function(panel)
                    ns:ResetSettings()
                    panel:Refresh()
                end },
            },
        },
    }
end

local function Round(value, step)
    return math.floor(value / step + 0.5) * step
end

local function FormatValue(value, step)
    if step < 1 then return string.format("%.2f", value) end
    return tostring(value)
end

local function Apply(key)
    if key == "maxDistance" then
        ns:ApplyCVars()
    else
        ns:RefreshAll()
    end
end

local function CurrentValue(key)
    if key == "maxDistance" and not ns.db.maxDistance then
        return tonumber(GetCVar("nameplateMaxDistance")) or 20
    end
    return ns.db[key]
end

-- A flat dark box with a thin border, used by the dropdown and its list.
local function AddBox(frame, r, g, b)
    local edge = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
    edge:SetTexture(SOLID)
    edge:SetVertexColor(0.32, 0.32, 0.36, 1)
    edge:SetAllPoints(frame)
    local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    fill:SetTexture(SOLID)
    fill:SetVertexColor(r or 0.07, g or 0.07, b or 0.09, 1)
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
end

-- Controls ---------------------------------------------------------------------
-- Each builder places its control at (x, y) and returns the widget and the
-- vertical space it used.

local function CreateHeader(panel, text, x, y)
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(text)
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetTexture(SOLID)
    line:SetVertexColor(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", x, y - 16)
    line:SetWidth(COLUMN_WIDTH)
    return 24
end

local function CreateCheckbox(panel, key, text, x, y)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x - 2, y)
    local label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    label:SetText(text)
    cb:SetHitRectInsets(0, -label:GetStringWidth() - 4, 0, 0)
    cb:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        Apply(key)
    end)
    cb.Refresh = function(self) self:SetChecked(ns.db[key]) end
    return cb, 24
end

local function CreateSlider(panel, key, text, min, max, step, x, y)
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y - 2)
    label:SetText(text)

    local valueText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    valueText:SetPoint("TOPRIGHT", panel, "TOPLEFT", x + CONTROL_WIDTH, y - 2)

    local slider = CreateFrame("Slider", nil, panel)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(CONTROL_WIDTH, 14)
    slider:SetPoint("TOPLEFT", x, y - 17)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:EnableMouseWheel(true)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(SOLID)
    track:SetVertexColor(0.16, 0.16, 0.19, 1)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(SOLID)
    thumb:SetVertexColor(0.62, 0.84, 1, 1)
    thumb:SetSize(8, 14)
    slider:SetThumbTexture(thumb)

    slider:SetScript("OnValueChanged", function(self, value)
        value = Round(value, step)
        valueText:SetText(FormatValue(value, step))
        if self.refreshing then return end
        ns.db[key] = value
        Apply(key)
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * step)
    end)
    slider.Refresh = function(self)
        self.refreshing = true
        local value = CurrentValue(key) or min
        self:SetValue(value)
        valueText:SetText(FormatValue(value, step))
        self.refreshing = nil
    end
    return slider, 38
end

-- A button showing the current choice; clicking it opens a list to pick from.
local function CreateDropdown(panel, key, text, values, names, x, y)
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y - 2)
    label:SetText(text)

    local button = CreateFrame("Button", nil, panel)
    button:SetSize(CONTROL_WIDTH, 22)
    button:SetPoint("TOPLEFT", x, y - 17)
    AddBox(button)
    local current = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    current:SetPoint("LEFT", 8, 0)
    local arrow = button:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetRotation(-math.pi / 2) -- point down
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetTexture(SOLID)
    hover:SetVertexColor(1, 1, 1, 0.06)
    hover:SetAllPoints(button)

    local list = CreateFrame("Frame", nil, button)
    list:SetFrameStrata("DIALOG")
    list:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    list:SetSize(CONTROL_WIDTH, #values * 20 + 4)
    list:EnableMouse(true)
    AddBox(list, 0.09, 0.09, 0.12)
    list:Hide()

    local rows = {}
    for i, value in ipairs(values) do
        local row = CreateFrame("Button", nil, list)
        row:SetSize(CONTROL_WIDTH - 4, 20)
        row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 20)
        local rowHover = row:CreateTexture(nil, "HIGHLIGHT")
        rowHover:SetTexture(SOLID)
        rowHover:SetVertexColor(0.62, 0.84, 1, 0.18)
        rowHover:SetAllPoints(row)
        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetText(names[value] or value)
        row:SetScript("OnClick", function()
            ns.db[key] = value
            list:Hide()
            button:Refresh()
            Apply(key)
        end)
        rows[value] = row
    end

    button:SetScript("OnClick", function()
        list:SetShown(not list:IsShown())
    end)
    button:SetScript("OnHide", function() list:Hide() end)
    button.Refresh = function()
        local value = ns.db[key]
        if not rows[value] then value = values[1] end
        current:SetText(names[value] or value)
        for v, row in pairs(rows) do
            if v == value then row.text:SetTextColor(1, 0.82, 0) else row.text:SetTextColor(1, 1, 1) end
        end
    end
    return button, 46
end

local function CreateButton(panel, text, onClick, x, y)
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(140, 22)
    button:SetPoint("TOPLEFT", x, y - 6)
    button:SetText(text)
    button:SetScript("OnClick", function() onClick(panel) end)
    button.Refresh = function() end
    return button, 32
end

-- Panel ------------------------------------------------------------------------

function ns:CreateOptions()
    if self.optionsPanel then return end
    local panel = CreateFrame("Frame")
    panel.name = "KuiNameplates"
    panel:Hide()

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("KuiNameplates")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sub:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 10, 1)
    sub:SetText("Changes apply instantly. Type /kui for commands.")

    local widgets = {}
    for columnIndex, column in ipairs(Layout()) do
        local x = 16 + (columnIndex - 1) * (COLUMN_WIDTH + 30)
        local y = -48
        for _, section in ipairs(column) do
            y = y - CreateHeader(panel, section.title, x, y)
            for _, item in ipairs(section) do
                local kind, widget, used = item[1]
                if kind == "check" then
                    widget, used = CreateCheckbox(panel, item[2], item[3], x, y)
                elseif kind == "slider" then
                    widget, used = CreateSlider(panel, item[2], item[3], item[4], item[5], item[6], x, y)
                elseif kind == "dropdown" then
                    widget, used = CreateDropdown(panel, item[2], item[3], item[4], item[5], x, y)
                else
                    widget, used = CreateButton(panel, item[2], item[3], x, y)
                end
                widgets[#widgets + 1] = widget
                y = y - used
            end
            y = y - 12 -- space between sections
        end
    end

    panel.Refresh = function()
        for _, widget in ipairs(widgets) do widget:Refresh() end
    end
    panel:SetScript("OnShow", panel.Refresh)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        self.optionsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
    self.optionsPanel = panel
end

function ns:OpenOptions()
    -- The game does not let addons open its settings window during combat.
    if InCombatLockdown() then
        ns.Print("the settings panel can't be opened in combat. Try again after the fight.")
        return
    end
    self:CreateOptions()
    if Settings and Settings.OpenToCategory and self.optionsCategory then
        Settings.OpenToCategory(self.optionsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Called twice: the first call can land on the wrong page in older clients.
        InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
    end
end
