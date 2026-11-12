-- KuiNameplates: settings panel under Interface Options / Settings > AddOns.
-- Built from plain frames (no option templates) so it works across client versions.
local _, ns = ...

local CHECKBOXES = {
    { key = "classColors", label = "Class colours on enemy players" },
    { key = "healthText",  label = "Show health percent" },
    { key = "showLevel",   label = "Show level" },
    { key = "castBars",    label = "Show cast bars" },
    { key = "auras",       label = "Show your debuffs on enemies" },
    { key = "tankMode",    label = "Tank mode (colour bars by threat)" },
    { key = "nameOnly",    label = "Friendly units: name only, no bar" },
}

local SLIDERS = {
    { key = "maxDistance",    label = "Max nameplate distance (yards)", min = 10, max = 100, step = 1 },
    { key = "scale",          label = "Overall size",         min = 0.5, max = 2,  step = 0.05 },
    { key = "width",          label = "Bar width",           min = 40, max = 300, step = 5 },
    { key = "height",         label = "Bar height",           min = 4,  max = 40,  step = 1 },
    { key = "castHeight",     label = "Cast bar height",      min = 2,  max = 20,  step = 1 },
    { key = "nameSize",       label = "Name font size",       min = 6,  max = 24,  step = 1 },
    { key = "nonTargetAlpha", label = "Non-target opacity",   min = 0,  max = 1,   step = 0.05 },
    { key = "auraWidth",      label = "Debuff icon size",     min = 12, max = 40,  step = 1 },
}

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

local function CreateCheckbox(panel, info, x, y)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", x, y)
    local label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    label:SetText(info.label)
    cb:SetScript("OnClick", function(self)
        ns.db[info.key] = self:GetChecked() and true or false
        Apply(info.key)
    end)
    cb.Refresh = function(self) self:SetChecked(ns.db[info.key]) end
    return cb
end

local function CreateSlider(panel, info, x, y)
    local slider = CreateFrame("Slider", nil, panel)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(220, 16)
    slider:SetPoint("TOPLEFT", x, y)
    slider:SetMinMaxValues(info.min, info.max)
    slider:SetValueStep(info.step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:EnableMouseWheel(true)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetTexture("Interface\\Buttons\\WHITE8X8")
    track:SetVertexColor(0.2, 0.2, 0.2, 0.9)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(6)

    local label = slider:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 3)
    label:SetText(info.label)

    local valueText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    valueText:SetPoint("LEFT", slider, "RIGHT", 10, 0)

    slider:SetScript("OnValueChanged", function(self, value)
        value = Round(value, info.step)
        valueText:SetText(FormatValue(value, info.step))
        if self.refreshing then return end
        ns.db[info.key] = value
        Apply(info.key)
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * info.step)
    end)
    slider.Refresh = function(self)
        self.refreshing = true
        local value = CurrentValue(info.key)
        self:SetValue(value)
        valueText:SetText(FormatValue(value, info.step))
        self.refreshing = nil
    end
    return slider
end

function ns:CreateOptions()
    if self.optionsPanel then return end
    local panel = CreateFrame("Frame")
    panel.name = "KuiNameplates"
    panel:Hide()

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("KuiNameplates")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Changes apply instantly. Max distance changes wait until you leave combat. Type /kui for commands.")

    local widgets = {}
    for i, info in ipairs(CHECKBOXES) do
        widgets[#widgets + 1] = CreateCheckbox(panel, info, 16, -60 - (i - 1) * 30)
    end
    for i, info in ipairs(SLIDERS) do
        widgets[#widgets + 1] = CreateSlider(panel, info, 330, -80 - (i - 1) * 46)
    end

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(140, 24)
    reset:SetPoint("TOPLEFT", 16, -60 - #CHECKBOXES * 30 - 16)
    reset:SetText("Reset to defaults")
    reset:SetScript("OnClick", function()
        ns:ResetSettings()
        panel:Refresh()
    end)

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
    self:CreateOptions()
    if Settings and Settings.OpenToCategory and self.optionsCategory then
        Settings.OpenToCategory(self.optionsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Called twice: the first call can land on the wrong page in older clients.
        InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
    end
end
