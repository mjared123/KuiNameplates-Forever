-- ForeverPlates: building and updating a single nameplate.
local _, ns = ...

local BAR = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT
local RAID_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

local COLOR_HOSTILE  = { 0.85, 0.20, 0.20 }
local COLOR_NEUTRAL  = { 0.95, 0.80, 0.25 }
local COLOR_FRIENDLY = { 0.35, 0.75, 0.35 }
local COLOR_PLAYER   = { 0.35, 0.55, 0.95 } -- friendly players without class colours
local COLOR_TAPPED   = { 0.55, 0.55, 0.55 }
local COLOR_TANK_OK  = { 0.30, 0.55, 0.95 } -- tank mode: you hold threat
local COLOR_TANK_BAD = { 1.00, 0.45, 0.10 } -- tank mode: threat slipping

-- Unit events each plate listens to, registered only for its own unit.
-- Some don't exist on every client, so each is registered safely.
local UNIT_EVENTS = {
    "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH",
    "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_CLASSIFICATION_CHANGED",
    "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE",
}

local Plate = {}

local function SetColor(tex, c, a)
    tex:SetVertexColor(c[1], c[2], c[3], a or 1)
end

function ns:CreatePlate(nameplate)
    local db = self.db
    local plate = CreateFrame("Frame", nil, nameplate)
    for k, v in pairs(Plate) do plate[k] = v end
    plate:SetAllPoints(nameplate)
    plate.nameplate = nameplate

    local health = CreateFrame("StatusBar", nil, plate)
    health:SetStatusBarTexture(BAR)
    health:SetPoint("CENTER", plate, "CENTER", 0, 0)
    plate.health = health

    -- Outer glow: target highlight / threat warning. Sits behind the border.
    local glow = health:CreateTexture(nil, "BACKGROUND", nil, -8)
    glow:SetTexture(BAR)
    glow:SetPoint("TOPLEFT", -2, 2)
    glow:SetPoint("BOTTOMRIGHT", 2, -2)
    glow:Hide()
    plate.glow = glow

    -- 1px black border with a dark fill behind the bar.
    local border = health:CreateTexture(nil, "BACKGROUND", nil, -7)
    border:SetTexture(BAR)
    border:SetVertexColor(0, 0, 0, 1)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)

    local fill = health:CreateTexture(nil, "BACKGROUND", nil, -6)
    fill:SetTexture(BAR)
    fill:SetVertexColor(0.08, 0.08, 0.08, 0.9)
    fill:SetAllPoints(health)

    plate.name = plate:CreateFontString(nil, "OVERLAY")
    plate.name:SetPoint("BOTTOM", health, "TOP", 0, 3)
    plate.name:SetWordWrap(false)

    plate.level = health:CreateFontString(nil, "OVERLAY")
    plate.level:SetPoint("LEFT", health, "LEFT", 2, 0)

    plate.healthText = health:CreateFontString(nil, "OVERLAY")
    plate.healthText:SetPoint("RIGHT", health, "RIGHT", -2, 0)

    plate.raidIcon = health:CreateTexture(nil, "OVERLAY")
    plate.raidIcon:SetTexture(RAID_ICONS)
    plate.raidIcon:SetSize(18, 18)
    plate.raidIcon:SetPoint("RIGHT", health, "LEFT", -4, 0)
    plate.raidIcon:Hide()

    plate:SetScript("OnEvent", plate.OnEvent)
    plate:ApplyLayout()

    nameplate.ForeverPlate = plate
    ns.allPlates = ns.allPlates or {}
    ns.allPlates[plate] = true
    return plate
end

function Plate:ApplyLayout()
    local db = ns.db
    self.health:SetSize(db.width, db.height)
    self.name:SetFont(FONT, db.nameSize, "OUTLINE")
    self.name:SetWidth(db.width + 30)
    local small = math.max(db.height - 1, 8)
    self.level:SetFont(FONT, small, "OUTLINE")
    self.healthText:SetFont(FONT, small, "OUTLINE")
end

-- Keep Blizzard's own plate hidden underneath ours.
local function HideBlizzard(nameplate)
    local uf = nameplate.UnitFrame
    if not uf then return end
    if not uf.ForeverPlatesHooked then
        uf:HookScript("OnShow", uf.Hide)
        uf.ForeverPlatesHooked = true
    end
    uf:Hide()
end

function Plate:OnUnitAdded(unit)
    self.unit = unit
    HideBlizzard(self.nameplate)
    for _, event in ipairs(UNIT_EVENTS) do
        pcall(self.RegisterUnitEvent, self, event, unit)
    end
    self:UpdateAll()
    self:Show()
end

function Plate:OnUnitRemoved()
    self:UnregisterAllEvents()
    self.unit = nil
    self:Hide()
end

function Plate:OnEvent(event)
    if not self.unit then return end
    if event == "UNIT_HEALTH" or event == "UNIT_HEALTH_FREQUENT" or event == "UNIT_MAXHEALTH" then
        self:UpdateHealth()
    elseif event == "UNIT_NAME_UPDATE" then
        self:UpdateName()
    elseif event == "UNIT_LEVEL" or event == "UNIT_CLASSIFICATION_CHANGED" then
        self:UpdateLevel()
    else -- faction or threat changes
        self:UpdateColor()
    end
end

function Plate:UpdateAll()
    if not self.unit then return end
    self:UpdateName()
    self:UpdateLevel()
    self:UpdateHealth()
    self:UpdateColor()
    self:UpdateRaidIcon()
    self:UpdateTarget()
end

function Plate:UpdateName()
    self.name:SetText(UnitName(self.unit) or "")
end

local CLASSIFICATION_SUFFIX = { elite = "+", rare = "r", rareelite = "r+", worldboss = "b" }

function Plate:UpdateLevel()
    local unit = self.unit
    if not ns.db.showLevel then self.level:SetText("") return end
    local level = UnitLevel(unit)
    local suffix = CLASSIFICATION_SUFFIX[UnitClassification(unit)] or ""
    if level and level > 0 then
        local getColor = GetCreatureDifficultyColor or GetQuestDifficultyColor
        local c = getColor(level)
        self.level:SetText(level .. suffix)
        self.level:SetTextColor(c.r, c.g, c.b)
    else
        self.level:SetText("??" .. suffix)
        self.level:SetTextColor(1, 0.2, 0.2)
    end
end

function Plate:UpdateHealth()
    local unit = self.unit
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    if not max or max <= 0 then max = 1 end
    self.health:SetMinMaxValues(0, max)
    self.health:SetValue(cur)
    if ns.db.healthText and cur < max and cur > 0 then
        self.healthText:SetFormattedText("%d%%", cur / max * 100 + 0.5)
    else
        self.healthText:SetText("")
    end
end

-- 0 = no threat, 1 = above tank but not tanking, 2 = tanking insecurely, 3 = securely tanking.
local function ThreatStatus(unit)
    if not UnitThreatSituation then return nil end
    return UnitThreatSituation("player", unit)
end

function Plate:UpdateColor()
    local unit, db = self.unit, ns.db
    local color
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local cc = class and RAID_CLASS_COLORS[class]
        if db.classColors and cc and UnitCanAttack("player", unit) then
            color = { cc.r, cc.g, cc.b }
        elseif UnitCanAttack("player", unit) then
            color = COLOR_HOSTILE
        else
            color = COLOR_PLAYER
        end
    elseif UnitIsTapDenied and UnitIsTapDenied(unit) then
        color = COLOR_TAPPED
    else
        local reaction = UnitReaction(unit, "player") or 4
        if reaction <= 3 then color = COLOR_HOSTILE
        elseif reaction == 4 then color = COLOR_NEUTRAL
        else color = COLOR_FRIENDLY end
    end

    local threat = UnitAffectingCombat(unit) and ThreatStatus(unit)
    if db.tankMode and threat then
        color = (threat == 3) and COLOR_TANK_OK or COLOR_TANK_BAD
    end
    self.health:SetStatusBarColor(color[1], color[2], color[3])
    self.threat = threat
    self:UpdateGlow()
end

function Plate:UpdateRaidIcon()
    local index = self.unit and GetRaidTargetIndex(self.unit)
    if index then
        SetRaidTargetIconTexture(self.raidIcon, index)
        self.raidIcon:Show()
    else
        self.raidIcon:Hide()
    end
end

function Plate:UpdateTarget()
    local unit = self.unit
    if not unit then return end
    self.isTarget = UnitIsUnit(unit, "target")
    if self.isTarget or not UnitExists("target") then
        self:SetAlpha(1)
    else
        self:SetAlpha(ns.db.nonTargetAlpha)
    end
    self:SetFrameLevel(self.isTarget and 10 or 1)
    self:UpdateGlow()
end

-- Target gets a white outline; otherwise, outside tank mode, a threat warning glow.
function Plate:UpdateGlow()
    local glow, threat = self.glow, self.threat
    if self.isTarget then
        glow:SetVertexColor(1, 1, 1, 0.9)
        glow:Show()
    elseif not ns.db.tankMode and threat and threat >= 1 then
        if threat >= 2 then glow:SetVertexColor(1, 0.1, 0.1, 0.9)
        else glow:SetVertexColor(1, 0.6, 0.1, 0.9) end
        glow:Show()
    else
        glow:Hide()
    end
end
