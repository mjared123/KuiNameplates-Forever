-- KuiNameplates: settings panel under Options > AddOns.
-- Built from plain frames (no option templates) so it works across client versions.
local _, ns = ...

local SOLID = "Interface\\Buttons\\WHITE8X8"
local COLUMN_WIDTH = 270
local CONTROL_WIDTH = 230

-- The panel is a row of tabs. Each tab is two columns of sections, and each
-- entry in a section is one control:
--   { "check", key, label }
--   { "slider", key, label, min, max, step }
--   { "dropdown", key, label, values, names }
--   { "color", keyPrefix, label }       -- uses keyPrefix .. "R" / "G" / "B"
--   { "button", label, onClick }
--   { "note", text }                    -- grey help text
--   { "custom", builder }               -- builder(page, x, y) returns widget, height
-- Builders for the Hide tab, filled in further down.
local Lists = {}

local function Pages()
    return {
        { name = "General",
          { { title = "All plates",
              { "slider", "scale", "Overall size", 0.5, 2, 0.05 },
              { "slider", "nonTargetAlpha", "Opacity of plates you aren't targeting", 0, 1, 0.05 },
              { "slider", "maxDistance", "Max nameplate distance (yards)", 10, 100, 1 },
              { "dropdown", "nameParts", "Player names", ns.NAME_PARTS, ns.NAME_PART_NAMES },
              { "dropdown", "font", "Font", ns.FONT_KEYS, ns.FONT_NAMES },
            },
            { title = "Raid marks",
              { "dropdown", "raidSpot", "Position", ns.RAID_SPOTS, ns.RAID_SPOT_NAMES },
              { "slider", "raidSize", "Size", 12, 40, 1 },
            } },
          { { title = "Target",
              { "check", "targetArrows", "Arrows either side of your target" },
              { "color", "arrow", "Arrow colour" },
              { "slider", "arrowScale", "Arrow size", 0.5, 3, 0.05 },
              { "slider", "arrowX", "Arrow distance from the bar", -10, 40, 1 },
              { "slider", "arrowY", "Arrow height (up or down)", -20, 20, 1 },
              { "slider", "targetScale", "Size of your target's plate", 1, 1.3, 0.01 },
              { "check", "comboPoints", "Combo points on your target (rogues, cat druids)" },
              { "check", "targetName", "Show who each enemy is targeting" },
            },
            { title = "Tools",
              { "check", "minimapButton", "Show minimap button" },
              { "button", "Toggle test mode", function()
                    ns:SetTestMode(not ns.testMode)
                end },
              { "button", "Reset to defaults", function(panel)
                    ns:ResetSettings()
                    panel:Refresh()
                end },
            } },
        },
        { name = "Enemies",
          { { title = "Health bar",
              { "slider", "width", "Bar width", 40, 300, 2 },
              { "slider", "height", "Bar height", 4, 40, 1 },
              { "check", "classColors", "Class colours on enemy players" },
            },
            { title = "Tank mode",
              { "check", "tankMode", "Tank mode (colour bars by threat)" },
              { "color", "tankOk", "You hold threat" },
              { "color", "tankBad", "Threat slipping, or not on you" },
            },
            { title = "Casters",
              { "check", "casterColors", "Colour enemy caster NPCs" },
              { "color", "caster", "Caster colour" },
            } },
          { { title = "Text",
              { "slider", "nameSize", "Name size", 6, 24, 1 },
              { "slider", "nameOffset", "Name height above the bar", -10, 20, 1 },
              { "check", "healthText", "Show health percent" },
              { "slider", "healthTextX", "Health percent left or right", -100, 100, 1 },
              { "slider", "healthTextY", "Health percent up or down", -40, 40, 1 },
              { "check", "showLevel", "Show level" },
              { "slider", "levelX", "Level left or right", -100, 100, 1 },
              { "slider", "levelY", "Level up or down", -40, 40, 1 },
              { "slider", "infoSize", "Level and health text size", 6, 20, 1 },
            } },
        },
        { name = "Layout",
          { { title = "Health number",
              { "check", "healthNumber", "Show current health as a number" },
              { "dropdown", "healthNumberStyle", "Style", ns.NUMBER_STYLES, ns.NUMBER_STYLE_NAMES },
              { "check", "numberCommas", "Commas in big numbers (3,432)" },
              { "slider", "healthNumberX", "Left or right", -100, 100, 1 },
              { "slider", "healthNumberY", "Up or down", -40, 40, 1 },
            },
            { title = "Power number",
              { "check", "powerText", "Show a number on the power bar" },
              { "dropdown", "powerTextStyle", "Style", ns.NUMBER_STYLES, ns.NUMBER_STYLE_NAMES },
              { "slider", "powerTextX", "Left or right", -100, 100, 1 },
              { "slider", "powerTextY", "Up or down", -40, 40, 1 },
            } },
          { { title = "Power bar (energy, rage, mana)",
              { "dropdown", "powerBar", "Show on", ns.POWER_SHOWS, ns.POWER_SHOW_NAMES },
              { "slider", "powerHeight", "Height", 1, 12, 1 },
              { "slider", "powerX", "Left or right", -100, 100, 1 },
              { "slider", "powerY", "Up or down", -40, 40, 1 },
              { "note", "Your own plate shows when the game's personal resource display is on." },
            },
            { title = "Combo points (turn them on in General)",
              { "slider", "comboX", "Left or right", -100, 100, 1 },
              { "slider", "comboY", "Up or down", -40, 40, 1 },
              { "slider", "comboBgAlpha", "Opacity of empty points", 0, 1, 0.05 },
            } },
        },
        { name = "Friendly",
          { { title = "Name",
              { "check", "nameOnly", "Show a name only, with no bar" },
              { "check", "healthName", "Health as name (grey out name by missing health)" },
              { "slider", "friendNameSize", "Name size", 6, 24, 1 },
              { "slider", "nameOnlyOffset", "Height above the head", -40, 60, 1 },
              { "check", "friendlyNoFade", "Keep friendly plates bright when you have a target" },
            },
            { title = "Level",
              { "check", "friendLevel", "Show the level left of the name" },
              { "slider", "friendLevelSize", "Size", 6, 24, 1 },
              { "slider", "friendLevelX", "Left or right", -100, 100, 1 },
              { "slider", "friendLevelY", "Up or down", -40, 40, 1 },
            } },
          { { title = "Title and guild line",
              { "check", "showTitle", "Show NPC titles and guild names" },
              { "slider", "titleSize", "Text size", 6, 24, 1 },
              { "slider", "titleSpacing", "Gap between name and this line", -6, 20, 1 },
              { "color", "title", "Text colour" },
            } },
        },
        { name = "Cast bars",
          { { title = "Bar",
              { "check", "castBars", "Show cast bars" },
              { "dropdown", "castStyle", "Style", ns.CAST_STYLES, ns.CAST_STYLE_NAMES },
              { "slider", "castHeight", "Size", 2, 20, 1 },
            },
            { title = "Colours",
              { "color", "cast", "Casts you can interrupt" },
              { "color", "castLock", "Casts you can't interrupt" },
            } },
          { { title = "Text",
              { "slider", "castTextSize", "Spell name size", 6, 20, 1 },
              { "slider", "castTextOffset", "Spell name height (up or down)", -15, 15, 1 },
            } },
        },
        { name = "Auras",
          { { title = "Debuffs",
              { "check", "auras", "Show your debuffs on enemies" },
              { "dropdown", "auraSpot", "Position", ns.AURA_SPOTS, ns.AURA_SPOT_NAMES },
            },
            { title = "Buffs",
              { "check", "buffs", "Show enemy buffs you can purge or steal" },
              { "dropdown", "buffSpot", "Position", ns.BUFF_SPOTS, ns.BUFF_SPOT_NAMES },
              { "note", "The game picks these: buffs you can dispel or steal, and a few important ones. With debuffs on the same side, buffs sit beyond them." },
            } },
          { { title = "Icons",
              { "check", "auraColors", "Colour borders by type (magic, poison, curse...)" },
              { "slider", "auraWidth", "Icon size", 12, 40, 1 },
              { "slider", "auraTextSize", "Timer and stack text size", 6, 24, 1 },
              { "slider", "auraOffset", "Distance from the bar", -20, 40, 1 },
            } },
        },
        { name = "Hide",
          { { title = "Hidden auras",
              { "note", "These buffs and debuffs never show on plates. Type a spell name (hides every rank) or a spell ID, or tick one on the right." },
              { "custom", function(...) return Lists.Hidden(...) end },
              { "custom", function(...) return Lists.HideBox(...) end },
              { "check", "hideOnFriends", "Hide them on friendly plates too" },
            } },
          { { title = "Seen on plates",
              { "custom", function(...) return Lists.Seen(...) end },
              { "note", "In combat the game may keep the spell from the addon. A hidden aura is then made invisible but can leave a gap until combat ends." },
            } },
        },
        { name = "Experimental",
          { { title = "Test features (may change or go away)",
              { "check", "dotPrediction", "DoT damage prediction (test)" },
            } },
          { { title = "About DoT prediction",
              { "note", "A green section at the end of the health bar, and a number, show the damage your DoTs and bleeds will still do. A skull beside the bar means they are enough to kill. A DoT counts once the game shows your debuff is on the enemy, so immunities and misses drop out. A question mark after the number means the game would not confirm one of them. Damage comes from spell tooltips, so crits are not counted. English client only. /kui dotprobe shows what the addon can see." },
            } },
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
    return fill
end

-- Controls ---------------------------------------------------------------------
-- Each builder places its control at (x, y) on a page and returns the widget
-- and the vertical space it used.

local function CreateHeader(page, text, x, y)
    local label = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(text)
    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetTexture(SOLID)
    line:SetVertexColor(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", x, y - 16)
    line:SetWidth(COLUMN_WIDTH)
    return 26
end

local function CreateCheckbox(page, key, text, x, y)
    local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
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
    return cb, 26
end

local function CreateSlider(page, key, text, min, max, step, x, y)
    local label = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y - 2)
    label:SetText(text)

    local valueText = page:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    valueText:SetPoint("TOPRIGHT", page, "TOPLEFT", x + CONTROL_WIDTH, y - 2)

    local slider = CreateFrame("Slider", nil, page)
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
    return slider, 42
end

-- A button showing the current choice; clicking it opens a list to pick from.
local function CreateDropdown(page, key, text, values, names, x, y)
    local label = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y - 2)
    label:SetText(text)

    local button = CreateFrame("Button", nil, page)
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
    return button, 50
end

-- Open the game's colour picker on a colour, calling onChange(r, g, b) as it
-- changes and restoring the old colour if the picker is cancelled.
local function PickColor(r, g, b, onChange)
    local picker = ColorPickerFrame
    if not picker then return end
    local function Changed()
        onChange(picker:GetColorRGB())
    end
    local function Cancelled()
        onChange(r, g, b)
    end
    if picker.SetupColorPickerAndShow then
        picker:SetupColorPickerAndShow({
            r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = Changed, cancelFunc = Cancelled,
        })
    else
        picker.hasOpacity = false
        picker.func = Changed
        picker.cancelFunc = Cancelled
        picker:SetColorRGB(r, g, b)
        picker:Hide() -- makes sure OnShow runs with the new colour
        picker:Show()
    end
end

-- A colour swatch; clicking it opens the colour picker.
local function CreateColor(page, prefix, text, x, y)
    local keyR, keyG, keyB = prefix .. "R", prefix .. "G", prefix .. "B"
    local button = CreateFrame("Button", nil, page)
    button:SetSize(34, 18)
    button:SetPoint("TOPLEFT", x, y - 4)
    local fill = AddBox(button)
    local label = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("LEFT", button, "RIGHT", 8, 0)
    label:SetText(text)
    button:SetHitRectInsets(0, -label:GetStringWidth() - 10, 0, 0)

    button.Refresh = function()
        local db = ns.db
        fill:SetVertexColor(db[keyR], db[keyG], db[keyB], 1)
    end
    button:SetScript("OnClick", function()
        local db = ns.db
        PickColor(db[keyR], db[keyG], db[keyB], function(r, g, b)
            db[keyR], db[keyG], db[keyB] = r, g, b
            button:Refresh()
            ns:RefreshAll()
        end)
    end)
    return button, 30
end

-- A paragraph of grey help text.
local function CreateNote(page, text, x, y)
    local label = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", x, y - 2)
    label:SetWidth(COLUMN_WIDTH)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    local note = { Refresh = function() end }
    return note, math.ceil(label:GetStringHeight()) + 8
end

local function CreateButton(page, text, onClick, x, y, panel)
    local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    button:SetSize(150, 22)
    button:SetPoint("TOPLEFT", x, y - 4)
    button:SetText(text)
    button:SetScript("OnClick", function() onClick(panel) end)
    button.Refresh = function() end
    return button, 30
end

-- Aura hide lists -------------------------------------------------------------

local LIST_ROW = 22
local KIND_NAMES = { buff = "buff", debuff = "debuff" }

-- A scrolling list of rows. getList() returns the entries; fill(row, entry)
-- sets one row up. The mouse wheel scrolls it.
local function CreateRowList(page, x, y, count, empty, makeRow, getList, fill)
    local frame = CreateFrame("Frame", nil, page)
    frame:SetPoint("TOPLEFT", x, y)
    frame:SetSize(COLUMN_WIDTH, count * LIST_ROW + 16)
    frame:EnableMouseWheel(true)
    frame.offset = 0
    local rows = {}
    for i = 1, count do
        local row = makeRow(frame)
        row:SetSize(COLUMN_WIDTH, LIST_ROW)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * LIST_ROW)
        if i % 2 == 1 then
            local stripe = row:CreateTexture(nil, "BACKGROUND")
            stripe:SetTexture(SOLID)
            stripe:SetVertexColor(1, 1, 1, 0.04)
            stripe:SetAllPoints(row)
        end
        rows[i] = row
    end
    local emptyText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    emptyText:SetPoint("TOPLEFT", 4, -4)
    emptyText:SetWidth(COLUMN_WIDTH - 8)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetText(empty)
    local more = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    more:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -count * LIST_ROW - 2)

    frame.Refresh = function(self)
        local list = getList()
        local maxOffset = math.max(0, #list - count)
        self.offset = math.min(math.max(self.offset, 0), maxOffset)
        for i, row in ipairs(rows) do
            local entry = list[self.offset + i]
            row:SetShown(entry ~= nil)
            if entry then fill(row, entry) end
        end
        emptyText:SetShown(#list == 0)
        if maxOffset > 0 then
            more:SetFormattedText("%d-%d of %d, scroll for more", self.offset + 1, self.offset + count, #list)
        else
            more:SetText("")
        end
    end
    frame:SetScript("OnMouseWheel", function(self, delta)
        self.offset = self.offset - delta * 3
        self:Refresh()
    end)
    return frame, count * LIST_ROW + 18
end

-- Icon and name on the left of a list row.
local function AddIconAndName(row, left)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", left, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetJustifyH("LEFT")
    row.kind = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
end

local function FillIconAndName(row, entry)
    row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.name:SetText(entry.name or "?")
    row.kind:SetText(KIND_NAMES[entry.kind] or "")
end

-- Left column: the hidden auras, each with a button to show it again.
local function CreateHiddenList(page, x, y)
    return CreateRowList(page, x, y, 8, "Nothing hidden yet.",
        function(frame)
            local row = CreateFrame("Frame", nil, frame)
            AddIconAndName(row, 4)
            row.remove = CreateFrame("Button", nil, row)
            row.remove:SetSize(20, 20)
            row.remove:SetPoint("RIGHT", -2, 0)
            local cross = row.remove:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            cross:SetPoint("CENTER")
            cross:SetText("x")
            cross:SetTextColor(1, 0.35, 0.3)
            local hover = row.remove:CreateTexture(nil, "HIGHLIGHT")
            hover:SetTexture(SOLID)
            hover:SetVertexColor(1, 1, 1, 0.1)
            hover:SetAllPoints(row.remove)
            row.remove:SetScript("OnClick", function() ns:ShowAura(row.key) end)
            row.kind:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
            row.name:SetPoint("RIGHT", row.kind, "LEFT", -6, 0)
            return row
        end,
        function() return ns:HiddenAuraList() end,
        function(row, item)
            row.key = item.key
            FillIconAndName(row, item.entry)
            if type(item.key) == "number" then
                row.name:SetText((item.entry.name or "?") .. " |cff888888(ID " .. item.key .. ")|r")
            end
        end)
end

-- A box to type a spell name or ID into, with an Add button.
local function CreateHideBox(page, x, y)
    local box = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    box:SetSize(COLUMN_WIDTH - 80, 20)
    box:SetPoint("TOPLEFT", x + 6, y - 4)
    box:SetAutoFocus(false)
    box:SetMaxLetters(80)
    local hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 2, 0)
    hint:SetText("Spell name or ID")
    local add = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    add:SetSize(64, 22)
    add:SetPoint("LEFT", box, "RIGHT", 8, 0)
    add:SetText("Hide")
    local function Add()
        local name, why = ns:HideAura(box:GetText())
        if name then
            box:SetText("")
            box:ClearFocus()
        else
            ns.Print(why)
        end
    end
    add:SetScript("OnClick", Add)
    box:SetScript("OnEnterPressed", Add)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
    box.Refresh = function() end
    return box, 32
end

-- Right column: auras seen on plates, ticked when hidden. A row of buttons
-- picks all, buffs only or debuffs only.
local seenKind = nil
local function CreateSeenList(page, x, y)
    local filters = CreateFrame("Frame", nil, page)
    filters:SetPoint("TOPLEFT", x, y)
    filters:SetSize(COLUMN_WIDTH, 22)
    local list
    local buttons = {}
    local bx = 0
    for _, choice in ipairs({ { "All" }, { "Buffs", "buff" }, { "Debuffs", "debuff" } }) do
        local b = CreateFrame("Button", nil, filters)
        AddBox(b)
        b.label = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        b.label:SetPoint("CENTER")
        b.label:SetText(choice[1])
        b:SetSize(b.label:GetStringWidth() + 18, 20)
        b:SetPoint("LEFT", bx, 0)
        bx = bx + b:GetWidth() + 6
        b.kind = choice[2]
        b:SetScript("OnClick", function()
            seenKind = b.kind
            list.offset = 0
            filters:Refresh()
        end)
        buttons[#buttons + 1] = b
    end

    list = CreateRowList(page, x, y - 28, 9, "Nothing seen yet. Buffs and debuffs are listed here once they show on a plate out of combat.",
        function(frame)
            local row = CreateFrame("Frame", nil, frame)
            row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.check:SetSize(22, 22)
            row.check:SetPoint("LEFT", 0, 0)
            AddIconAndName(row, 26)
            row.kind:SetPoint("RIGHT", -4, 0)
            row.name:SetPoint("RIGHT", row.kind, "LEFT", -6, 0)
            row.check:SetScript("OnClick", function(self)
                if self:GetChecked() then
                    ns:HideAura(row.entry.name, row.entry.kind)
                else
                    local key = ns:HiddenKeyFor(row.key)
                    if key then ns:ShowAura(key) end
                end
            end)
            return row
        end,
        function() return ns:SeenAuraList(seenKind) end,
        function(row, item)
            row.key, row.entry = item.key, item.entry
            FillIconAndName(row, item.entry)
            row.check:SetChecked(ns:HiddenKeyFor(item.key) ~= nil)
        end)

    filters.Refresh = function()
        for _, b in ipairs(buttons) do
            if b.kind == seenKind then b.label:SetTextColor(1, 0.82, 0) else b.label:SetTextColor(0.75, 0.75, 0.75) end
        end
        list:Refresh()
    end
    return filters, 28 + 9 * LIST_ROW + 18
end

Lists.Hidden, Lists.HideBox, Lists.Seen = CreateHiddenList, CreateHideBox, CreateSeenList

-- Panel ------------------------------------------------------------------------

-- Fill one tab's page with its two columns of sections.
local function BuildPage(panel, page, columns, widgets)
    for columnIndex, column in ipairs(columns) do
        local x = (columnIndex - 1) * (COLUMN_WIDTH + 30)
        local y = 0
        for _, section in ipairs(column) do
            y = y - CreateHeader(page, section.title, x, y)
            for _, item in ipairs(section) do
                local kind, widget, used = item[1]
                if kind == "check" then
                    widget, used = CreateCheckbox(page, item[2], item[3], x, y)
                elseif kind == "slider" then
                    widget, used = CreateSlider(page, item[2], item[3], item[4], item[5], item[6], x, y)
                elseif kind == "dropdown" then
                    widget, used = CreateDropdown(page, item[2], item[3], item[4], item[5], x, y)
                elseif kind == "color" then
                    widget, used = CreateColor(page, item[2], item[3], x, y)
                elseif kind == "note" then
                    widget, used = CreateNote(page, item[2], x, y)
                elseif kind == "custom" then
                    widget, used = item[2](page, x, y)
                else
                    widget, used = CreateButton(page, item[2], item[3], x, y, panel)
                end
                widgets[#widgets + 1] = widget
                y = y - used
            end
            y = y - 14 -- space between sections
        end
    end
end

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
    sub:SetText("Changes apply instantly. Type /kui test to preview them on sample plates.")

    -- Tab row, with a thin rule under it.
    local rule = panel:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(SOLID)
    rule:SetVertexColor(1, 1, 1, 0.12)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 16, -70)
    rule:SetWidth(COLUMN_WIDTH * 2 + 30)

    local widgets, tabs = {}, {}
    local function SelectTab(index)
        for i, tab in ipairs(tabs) do
            local selected = i == index
            tab.page:SetShown(selected)
            tab.mark:SetShown(selected)
            if selected then tab.label:SetTextColor(1, 0.82, 0) else tab.label:SetTextColor(0.75, 0.75, 0.75) end
        end
    end

    local tabX = 16
    for index, info in ipairs(Pages()) do
        local tab = CreateFrame("Button", nil, panel)
        tab.label = tab:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        tab.label:SetPoint("CENTER")
        tab.label:SetText(info.name)
        tab:SetSize(tab.label:GetStringWidth() + 16, 24) -- eight tabs share one row
        tab:SetPoint("TOPLEFT", tabX, -46)
        tabX = tabX + tab:GetWidth() + 4
        local hover = tab:CreateTexture(nil, "HIGHLIGHT")
        hover:SetTexture(SOLID)
        hover:SetVertexColor(1, 1, 1, 0.06)
        hover:SetAllPoints(tab)
        tab.mark = tab:CreateTexture(nil, "OVERLAY")
        tab.mark:SetTexture(SOLID)
        tab.mark:SetVertexColor(1, 0.82, 0, 1)
        tab.mark:SetHeight(2)
        tab.mark:SetPoint("BOTTOMLEFT", 0, -1)
        tab.mark:SetPoint("BOTTOMRIGHT", 0, -1)

        tab.page = CreateFrame("Frame", nil, panel)
        tab.page:SetPoint("TOPLEFT", 16, -88)
        tab.page:SetSize(COLUMN_WIDTH * 2 + 30, 400)
        BuildPage(panel, tab.page, info, widgets)

        tab:SetScript("OnClick", function() SelectTab(index) end)
        tabs[index] = tab
    end
    SelectTab(1)

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
