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
    "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "UNIT_AURA",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
}

local CAST_EVENTS = {
    UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_DELAYED = true, UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_CHANNEL_UPDATE = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
}

local COLOR_CAST        = { 0.95, 0.75, 0.20 }
local COLOR_CHANNEL     = { 0.40, 0.80, 0.40 }
local COLOR_UNINTERRUPT = { 0.60, 0.60, 0.60 }
local COLOR_INTERRUPTED = { 1.00, 0.20, 0.20 }

local Plate = {}

-- A 1px black border plus dark fill behind a bar or icon.
local function AddBorder(frame, fillAlpha)
    local border = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    border:SetTexture(BAR)
    border:SetVertexColor(0, 0, 0, 1)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    if fillAlpha then
        local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
        fill:SetTexture(BAR)
        fill:SetVertexColor(0.08, 0.08, 0.08, fillAlpha)
        fill:SetAllPoints(frame)
    end
end

local function CastOnUpdate(cast, elapsed)
    local now = GetTime()
    if now >= cast.endTime then
        cast:Hide()
        return
    end
    if cast.frozen then return end
    if cast.channel then
        cast:SetValue(cast.endTime - now)
    else
        cast:SetValue(now - cast.startTime)
    end
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

    AddBorder(health, 0.9)

    -- Cast bar under the health bar, with the spell icon to its left.
    local cast = CreateFrame("StatusBar", nil, plate)
    cast:SetStatusBarTexture(BAR)
    cast:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -3)
    cast:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -3)
    AddBorder(cast, 0.9)
    cast.icon = cast:CreateTexture(nil, "ARTWORK")
    cast.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    cast.icon:SetPoint("TOPRIGHT", health, "TOPLEFT", -3, 0)
    cast.icon:SetPoint("BOTTOMRIGHT", cast, "BOTTOMLEFT", -3, 0)
    cast.iconBorder = cast:CreateTexture(nil, "BACKGROUND", nil, -7)
    cast.iconBorder:SetTexture(BAR)
    cast.iconBorder:SetVertexColor(0, 0, 0, 1)
    cast.iconBorder:SetPoint("TOPLEFT", cast.icon, -1, 1)
    cast.iconBorder:SetPoint("BOTTOMRIGHT", cast.icon, 1, -1)
    cast.text = cast:CreateFontString(nil, "OVERLAY")
    cast.text:SetPoint("TOP", cast, "BOTTOM", 0, -2)
    cast:SetScript("OnUpdate", CastOnUpdate)
    cast:Hide()
    plate.cast = cast

    plate.auraButtons = {}
    plate.pending = {}

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
    plate.raidIcon:SetPoint("LEFT", health, "RIGHT", 4, 0)
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
    self.cast:SetHeight(db.castHeight)
    self.cast.text:SetFont(FONT, math.max(db.nameSize - 1, 7), "OUTLINE")
    self.cast.icon:SetWidth(db.height + db.castHeight + 3)
    for _, button in ipairs(self.auraButtons) do
        button:SetSize(db.auraWidth, math.floor(db.auraWidth * 0.65 + 0.5))
    end
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
    self.cast:Hide()
    self:Hide()
end

function Plate:OnEvent(event)
    if not self.unit then return end
    if event == "UNIT_HEALTH" or event == "UNIT_HEALTH_FREQUENT" or event == "UNIT_MAXHEALTH" then
        ns:Queue(self, "health")
    elseif event == "UNIT_AURA" then
        ns:Queue(self, "auras")
    elseif CAST_EVENTS[event] then
        self:UpdateCast()
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        self:ShowInterrupted()
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
    self:UpdateCast()
    self:UpdateAuras()
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

-- Cast bars -----------------------------------------------------------------

-- Returns name, icon, start (s), end (s), isChannel, notInterruptible.
-- Classic clients return a spell ID where retail returns notInterruptible,
-- so only a real boolean counts.
local function GetCast(unit)
    if UnitCastingInfo then
        local name, _, icon, startMS, endMS, _, _, notInt = UnitCastingInfo(unit)
        if name then return name, icon, startMS / 1000, endMS / 1000, false, notInt == true end
    end
    if UnitChannelInfo then
        local name, _, icon, startMS, endMS, _, notInt = UnitChannelInfo(unit)
        if name then return name, icon, startMS / 1000, endMS / 1000, true, notInt == true end
    end
end

function Plate:UpdateCast()
    local cast = self.cast
    if not ns.db.castBars then cast:Hide() return end
    local name, icon, startTime, endTime, channel, notInt = GetCast(self.unit)
    if not name then
        if not cast.frozen then
            if cast:IsShown() then cast.stoppedAt = GetTime() end
            cast:Hide()
        end
        return
    end
    cast.frozen = nil
    cast.startTime, cast.endTime, cast.channel = startTime, endTime, channel
    cast:SetMinMaxValues(0, math.max(endTime - startTime, 0.001))
    local c = notInt and COLOR_UNINTERRUPT or (channel and COLOR_CHANNEL or COLOR_CAST)
    cast:SetStatusBarColor(c[1], c[2], c[3])
    cast.icon:SetTexture(icon)
    cast.text:SetText(name)
    CastOnUpdate(cast, 0)
    if GetTime() < endTime then cast:Show() end
end

-- Briefly show a red "Interrupted" bar before hiding it.
function Plate:ShowInterrupted()
    local cast = self.cast
    -- The STOP event can arrive just before INTERRUPTED and hide the bar first.
    local justStopped = cast.stoppedAt and GetTime() - cast.stoppedAt < 0.2
    if not ns.db.castBars or not (cast:IsShown() or justStopped) then return end
    cast.frozen = true
    cast:Show()
    cast.endTime = GetTime() + 0.6
    cast:SetValue(select(2, cast:GetMinMaxValues()))
    cast:SetStatusBarColor(COLOR_INTERRUPTED[1], COLOR_INTERRUPTED[2], COLOR_INTERRUPTED[3])
    cast.text:SetText(INTERRUPTED or "Interrupted")
end

-- Auras ---------------------------------------------------------------------

-- Returns name, icon, count, duration, expirationTime for one aura,
-- using whichever aura API this client has.
local function GetAura(unit, index, filter)
    if UnitAura then
        local name, icon, count, _, duration, expiration = UnitAura(unit, index, filter)
        return name, icon, count, duration, expiration
    elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local a = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
        if a then return a.name, a.icon, a.applications, a.duration, a.expirationTime end
    end
end

function Plate:GetAuraButton(i)
    local button = self.auraButtons[i]
    if button then return button end
    button = CreateFrame("Frame", nil, self)
    local db = ns.db
    button:SetSize(db.auraWidth, math.floor(db.auraWidth * 0.65 + 0.5))
    AddBorder(button)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.1, 0.9, 0.25, 0.75) -- crop to the wide icon shape
    button.cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cd:SetAllPoints()
    button.cd:SetReverse(true)
    button.count = button:CreateFontString(nil, "OVERLAY")
    button.count:SetFont(FONT, 9, "OUTLINE")
    button.count:SetPoint("BOTTOMRIGHT", 2, -2)
    self.auraButtons[i] = button
    return button
end

-- Your own debuffs on attackable units, in a centred row above the name.
function Plate:UpdateAuras()
    local unit, db = self.unit, ns.db
    local shown = 0
    if db.auras and db.maxAuras > 0 and UnitCanAttack("player", unit) then
        for i = 1, 40 do
            local name, icon, count, duration, expiration = GetAura(unit, i, "HARMFUL|PLAYER")
            if not name then break end
            shown = shown + 1
            local button = self:GetAuraButton(shown)
            button.icon:SetTexture(icon)
            button.count:SetText((count and count > 1) and count or "")
            if duration and duration > 0 and expiration then
                button.cd:SetCooldown(expiration - duration, duration)
                button.cd:Show()
            else
                button.cd:Hide()
            end
            button:Show()
            if shown >= db.maxAuras then break end
        end
    end
    for i = shown + 1, #self.auraButtons do
        self.auraButtons[i]:Hide()
    end
    if shown == 0 then return end

    local gap = 2
    local total = shown * db.auraWidth + (shown - 1) * gap
    local x = (db.width - total) / 2
    for i = 1, shown do
        local button = self.auraButtons[i]
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", self.health, "TOPLEFT",
            x + (i - 1) * (db.auraWidth + gap), db.nameSize + 7)
    end
end
