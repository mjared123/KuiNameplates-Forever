-- KuiNameplates: combo points on your target's plate.
--
-- A row of small pips centred on the bottom edge of the target's bar, for
-- rogues and for druids in cat form. The point count may be a hidden value,
-- so it is never compared: each pip is a tiny status bar covering the range
-- (i - 1) to i, and the game fills it when the count reaches i.
local _, ns = ...

local SOLID = "Interface\\Buttons\\WHITE8X8"
local MAX_PIPS = 10
local PIP_WIDTH, PIP_HEIGHT, PIP_GAP = 9, 4, 2
local COLOR_ON = { 1.00, 0.82, 0.32 }    -- warm gold
local COLOR_OFF = { 0.10, 0.09, 0.08, 0.9 }
local CAT_FORM = 1

local _, playerClass = UnitClass("player")
local USES_COMBO = { ROGUE = true, DRUID = true }
local POWER_COMBO = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4

local function CreatePips(plate)
    local holder = CreateFrame("Frame", nil, plate.text)
    holder:SetAllPoints(plate.health)
    holder:SetFrameLevel(plate.text:GetFrameLevel() + 1)
    holder.pips = {}
    for i = 1, MAX_PIPS do
        local pip = CreateFrame("StatusBar", nil, holder)
        pip:SetSize(PIP_WIDTH, PIP_HEIGHT)
        pip:SetStatusBarTexture(SOLID)
        pip:SetStatusBarColor(COLOR_ON[1], COLOR_ON[2], COLOR_ON[3], 1)
        pip:SetMinMaxValues(i - 1, i)
        pip:SetValue(0)
        local border = pip:CreateTexture(nil, "BACKGROUND", nil, -7)
        border:SetTexture(SOLID)
        border:SetVertexColor(0, 0, 0, 1)
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        local empty = pip:CreateTexture(nil, "BACKGROUND", nil, -6)
        empty:SetTexture(SOLID)
        empty:SetVertexColor(COLOR_OFF[1], COLOR_OFF[2], COLOR_OFF[3], COLOR_OFF[4])
        empty:SetAllPoints(pip)
        pip.empty, pip.border = empty, border
        holder.pips[i] = pip
    end
    holder:Hide()
    plate.combo = holder
    return holder
end

-- Show `points` of `max` pips on a plate, or hide them when points is nil.
function ns.ShowCombo(plate, points, max)
    local holder = plate.combo or CreatePips(plate)
    if points == nil then
        holder:Hide()
        return
    end
    max = math.max(1, math.min(max or 5, MAX_PIPS))
    local total = max * PIP_WIDTH + (max - 1) * PIP_GAP
    local db = ns.db
    local x, y = db.comboX or 0, db.comboY or 0
    local bgAlpha = db.comboBgAlpha or COLOR_OFF[4]
    for i, pip in ipairs(holder.pips) do
        if i <= max then
            pip:ClearAllPoints()
            pip:SetPoint("CENTER", plate.health, "BOTTOM",
                x - total / 2 + PIP_WIDTH / 2 + (i - 1) * (PIP_WIDTH + PIP_GAP), y - (plate.powerGap or 0))
            -- The empty part (and its outline) can be made see-through.
            pip.empty:SetAlpha(math.min(1, bgAlpha / COLOR_OFF[4]))
            pip.border:SetAlpha(math.min(1, math.max(bgAlpha / COLOR_OFF[4], 0.25)))
            pip:SetValue(points)
            pip:Show()
        else
            pip:Hide()
        end
    end
    holder:Show()
end

local function MaxPoints()
    local ok, max = pcall(UnitPowerMax, "player", POWER_COMBO)
    max = ok and ns.Plain(max)
    if type(max) ~= "number" or max < 1 then return 5 end
    return max
end

-- Druids only build combo points in cat form.
local function CanHaveCombo()
    if not USES_COMBO[playerClass] then return false end
    if playerClass ~= "DRUID" then return true end
    local form = GetShapeshiftFormID and ns.Plain(GetShapeshiftFormID())
    return form == nil or form == CAT_FORM
end

function ns:UpdateCombo()
    local targetPlate
    if self.db and self.db.comboPoints and CanHaveCombo() and UnitExists("target") then
        local nameplate = C_NamePlate.GetNamePlateForUnit("target")
        targetPlate = nameplate and nameplate.KuiForeverPlate
        if targetPlate and (not targetPlate.unit or targetPlate.nameOnly) then
            targetPlate = nil
        end
    end
    for _, plate in pairs(self.plates) do
        if plate ~= targetPlate and plate.combo then plate.combo:Hide() end
    end
    if targetPlate then
        -- Points are kept on the target, as in the original game.
        local ok, points = pcall(GetComboPoints, "player", "target")
        if not ok or points == nil then
            ok, points = pcall(UnitPower, "player", POWER_COMBO)
        end
        if not ok or points == nil then points = 0 end
        ns.ShowCombo(targetPlate, points, MaxPoints())
    end
end

if USES_COMBO[playerClass] then
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "COMBO_TARGET_CHANGED", "UPDATE_SHAPESHIFT_FORM" }) do
        pcall(events.RegisterEvent, events, event)
    end
    for _, event in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER" }) do
        pcall(events.RegisterUnitEvent, events, event, "player")
    end
    events:SetScript("OnEvent", function()
        if ns.db then ns.Try(ns.UpdateCombo, ns) end
    end)
end
