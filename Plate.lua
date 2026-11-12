-- KuiNameplates: building and updating a single nameplate.
--
-- WoW: Forever hands addons "secret" values for many unit numbers (health,
-- and possibly cast and aura timings). Addon code may pass a secret straight
-- to a widget (StatusBar:SetValue, FontString:SetText, ...) but may not
-- compare it, do maths on it, test it in an if, or use it as a table key.
-- Every value read from a Unit* API is therefore either handed directly to
-- a widget, or run through Plain() first, which turns secrets into nil.
local _, ns = ...

local MEDIA = "Interface\\AddOns\\KuiNameplates\\media\\"
local BAR = MEDIA .. "bar.tga"
local GLOW = MEDIA .. "glow.tga"
local FONT = MEDIA .. "FrancoisOne.ttf"
local SOLID = "Interface\\Buttons\\WHITE8X8"
local RAID_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local GLOW_SIZE = 6

local COLOR_HOSTILE  = { 0.78, 0.22, 0.22 }
local COLOR_NEUTRAL  = { 0.92, 0.78, 0.28 }
local COLOR_FRIENDLY = { 0.30, 0.68, 0.30 }
local COLOR_PLAYER   = { 0.30, 0.50, 0.90 } -- friendly players without class colours
local COLOR_TAPPED   = { 0.55, 0.55, 0.55 }
local COLOR_TANK_OK  = { 0.30, 0.55, 0.95 } -- tank mode: you hold threat
local COLOR_TANK_BAD = { 1.00, 0.45, 0.10 } -- tank mode: threat slipping

local COLOR_CAST        = { 0.95, 0.75, 0.20 }
local COLOR_CHANNEL     = { 0.40, 0.80, 0.40 }
local COLOR_UNINTERRUPT = { 0.60, 0.60, 0.60 }
local COLOR_INTERRUPTED = { 1.00, 0.20, 0.20 }

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

local CLASSIFICATION_SUFFIX = { elite = "+", rare = "r", rareelite = "r+", worldboss = "b" }

-- Secret-value helpers -------------------------------------------------------

local issecret = issecretvalue or function() return false end
local canaccess = canaccessvalue or function() return true end

local function IsSecret(value)
    return value ~= nil and (issecret(value) or not canaccess(value))
end

-- The value itself if addon code may inspect it, otherwise nil.
local function Plain(value)
    if IsSecret(value) then return nil end
    return value
end

-- True when a value is present. A secret always counts as present.
local function Has(value)
    return value ~= nil -- comparing with nil is allowed even for hidden values
end

-- Run one update step; if it errors, report it once and keep the plate working.
local reported = {}
local function Try(func, ...)
    local ok, err = pcall(func, ...)
    if not ok and not reported[err] then
        reported[err] = true
        local handler = geterrorhandler and geterrorhandler()
        if handler then handler(err) end
    end
    return ok
end
ns.Try = Try

-- Building a plate -----------------------------------------------------------

local Plate = {}

-- A 1px black border plus dark fill behind a bar or icon.
local function AddBorder(frame, fillAlpha)
    local border = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    border:SetTexture(SOLID)
    border:SetVertexColor(0, 0, 0, 1)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    if fillAlpha then
        local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
        fill:SetTexture(SOLID)
        fill:SetVertexColor(0.06, 0.06, 0.06, fillAlpha)
        fill:SetAllPoints(frame)
    end
end

-- Soft glow around a frame, from four fading strips (opaque edge against the frame).
local function AddGlow(frame)
    local strips = {}
    local function Strip()
        local tex = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        tex:SetTexture(GLOW)
        tex:SetBlendMode("ADD")
        strips[#strips + 1] = tex
        return tex
    end
    local top = Strip()
    top:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -GLOW_SIZE - 1, 1)
    top:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", GLOW_SIZE + 1, 1)
    top:SetHeight(GLOW_SIZE)
    top:SetTexCoord(0, 1, 1, 0)
    local bottom = Strip()
    bottom:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -GLOW_SIZE - 1, -1)
    bottom:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", GLOW_SIZE + 1, -1)
    bottom:SetHeight(GLOW_SIZE)
    local left = Strip()
    left:SetPoint("TOPRIGHT", frame, "TOPLEFT", -1, 1)
    left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", -1, -1)
    left:SetWidth(GLOW_SIZE)
    left:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
    local right = Strip()
    right:SetPoint("TOPLEFT", frame, "TOPRIGHT", 1, 1)
    right:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 1, -1)
    right:SetWidth(GLOW_SIZE)
    right:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)

    local glow = { shown = false }
    function glow:Set(r, g, b, a)
        for _, tex in ipairs(strips) do
            tex:SetVertexColor(r, g, b, a)
            tex:Show()
        end
        self.shown = true
    end
    function glow:Hide()
        for _, tex in ipairs(strips) do tex:Hide() end
        self.shown = false
    end
    glow:Hide()
    return glow
end

local function CastOnUpdate(cast)
    local now = GetTime()
    if cast.hideAt and now >= cast.hideAt then
        cast:Hide()
        return
    end
    if not cast.timed then return end
    if now >= cast.endTime then
        cast:Hide()
    elseif cast.channel then
        cast:SetValue(cast.endTime - now)
    else
        cast:SetValue(now - cast.startTime)
    end
end

function ns:CreatePlate(nameplate)
    local plate = CreateFrame("Frame", nil, nameplate)
    for k, v in pairs(Plate) do plate[k] = v end
    plate:SetAllPoints(nameplate)
    plate.nameplate = nameplate

    local health = CreateFrame("StatusBar", nil, plate)
    health:SetStatusBarTexture(BAR)
    health:SetPoint("CENTER", plate, "CENTER", 0, 0)
    AddBorder(health, 0.85)
    plate.health = health
    plate.glow = AddGlow(health)

    -- Cast bar under the health bar, spell icon to the left of both bars.
    local cast = CreateFrame("StatusBar", nil, plate)
    cast:SetStatusBarTexture(BAR)
    cast:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -3)
    cast:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -3)
    AddBorder(cast, 0.85)
    cast.icon = cast:CreateTexture(nil, "ARTWORK")
    cast.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    cast.icon:SetPoint("TOPRIGHT", health, "TOPLEFT", -3, 0)
    cast.icon:SetPoint("BOTTOMRIGHT", cast, "BOTTOMLEFT", -3, 0)
    local iconBorder = cast:CreateTexture(nil, "BACKGROUND", nil, -7)
    iconBorder:SetTexture(SOLID)
    iconBorder:SetVertexColor(0, 0, 0, 1)
    iconBorder:SetPoint("TOPLEFT", cast.icon, -1, 1)
    iconBorder:SetPoint("BOTTOMRIGHT", cast.icon, 1, -1)
    cast.text = cast:CreateFontString(nil, "OVERLAY")
    cast.text:SetPoint("TOP", cast, "BOTTOM", 0, -2)
    cast.text:SetShadowOffset(1, -1)
    cast:SetScript("OnUpdate", CastOnUpdate)
    cast:Hide()
    plate.cast = cast

    plate.auraButtons = {}
    plate.pending = {}

    plate.name = plate:CreateFontString(nil, "OVERLAY")
    plate.name:SetPoint("BOTTOM", health, "TOP", 0, 3)
    plate.name:SetWordWrap(false)
    plate.name:SetShadowOffset(1, -1)

    plate.level = health:CreateFontString(nil, "OVERLAY")
    plate.level:SetPoint("LEFT", health, "LEFT", 2, 0)

    plate.healthText = health:CreateFontString(nil, "OVERLAY")
    plate.healthText:SetPoint("RIGHT", health, "RIGHT", -2, 0)

    plate.raidIcon = health:CreateTexture(nil, "OVERLAY")
    plate.raidIcon:SetTexture(RAID_ICONS)
    plate.raidIcon:SetSize(20, 20)
    plate.raidIcon:SetPoint("RIGHT", plate.name, "LEFT", -2, 0)
    plate.raidIcon:Hide()

    plate:SetScript("OnEvent", plate.OnEvent)
    plate:ApplyLayout()

    nameplate.KuiForeverPlate = plate
    ns.allPlates = ns.allPlates or {}
    ns.allPlates[plate] = true
    return plate
end

function Plate:ApplyLayout()
    local db = ns.db
    self.health:SetSize(db.width, db.height)
    self.name:SetFont(FONT, db.nameSize, "OUTLINE")
    self.name:SetWidth(db.width + 40)
    local small = math.max(db.nameSize - 2, 7)
    self.level:SetFont(FONT, small, "OUTLINE")
    self.healthText:SetFont(FONT, small, "OUTLINE")
    self.cast:SetHeight(db.castHeight)
    self.cast.text:SetFont(FONT, small, "OUTLINE")
    self.cast.icon:SetWidth(db.height + db.castHeight + 3)
    for _, button in ipairs(self.auraButtons) do
        button:SetSize(db.auraWidth, math.floor(db.auraWidth * 0.65 + 0.5))
        button.count:SetFont(FONT, small, "OUTLINE")
    end
end

-- Keep Blizzard's own plate hidden underneath ours.
local function HideBlizzard(nameplate)
    local uf = nameplate.UnitFrame
    if not uf then return end
    if not uf.KuiForeverHooked then
        uf:HookScript("OnShow", function(f) f:Hide() end)
        uf.KuiForeverHooked = true
    end
    uf:Hide()
end

function Plate:OnUnitAdded(unit)
    self.unit = unit
    Try(HideBlizzard, self.nameplate)
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
        Try(self.UpdateCast, self)
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        Try(self.ShowInterrupted, self)
    elseif event == "UNIT_NAME_UPDATE" then
        Try(self.UpdateName, self)
    elseif event == "UNIT_LEVEL" or event == "UNIT_CLASSIFICATION_CHANGED" then
        Try(self.UpdateLevel, self)
    else -- faction or threat changes
        Try(self.UpdateColor, self)
    end
end

-- Each part updates on its own, so one failure can't stop the plate drawing.
function Plate:UpdateAll()
    if not self.unit then return end
    Try(self.UpdateName, self)
    Try(self.UpdateLevel, self)
    Try(self.UpdateHealth, self)
    Try(self.UpdateColor, self)
    Try(self.UpdateRaidIcon, self)
    Try(self.UpdateTarget, self)
    Try(self.UpdateCast, self)
    Try(self.UpdateAuras, self)
end

function Plate:UpdateName()
    local name = UnitName(self.unit)
    if name == nil then name = "" end -- nil checks are allowed on hidden values
    self.name:SetText(name)
end

function Plate:UpdateLevel()
    local unit = self.unit
    if not ns.db.showLevel then self.level:SetText("") return end
    local level = Plain(UnitLevel(unit))
    local class = Plain(UnitClassification(unit))
    local suffix = (class and CLASSIFICATION_SUFFIX[class]) or ""
    if level and level > 0 then
        local getColor = GetCreatureDifficultyColor or GetQuestDifficultyColor
        local c = getColor and getColor(level)
        self.level:SetText(level .. suffix)
        if c then self.level:SetTextColor(c.r, c.g, c.b) end
    elseif level then
        self.level:SetText("??" .. suffix)
        self.level:SetTextColor(1, 0.2, 0.2)
    else
        self.level:SetText("")
    end
end

-- Health ---------------------------------------------------------------------

function Plate:UpdateHealth()
    local unit = self.unit
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    -- Status bars accept secret values directly.
    self.health:SetMinMaxValues(0, max)
    self.health:SetValue(cur)
    self:UpdateHealthText(cur, max)
end

function Plate:UpdateHealthText(cur, max)
    local text = self.healthText
    if not ns.db.healthText then text:SetText("") return end
    local c, m = Plain(cur), Plain(max)
    if c and m then
        text:SetAlpha(1)
        -- Readable numbers: show percent only while damaged.
        if m > 0 and c > 0 and c < m then
            text:SetFormattedText("%d%%", c / m * 100 + 0.5)
        else
            text:SetText("")
        end
        return
    end
    -- Hidden numbers: ask the game for a ready-made percent and print it as is,
    -- then fade it out at full health using a curve (no comparisons needed).
    local scale = CurveConstants and CurveConstants.ScaleTo100
    if UnitHealthPercent and scale then
        local ok, pct = pcall(UnitHealthPercent, self.unit, true, scale)
        if ok and pcall(text.SetFormattedText, text, "%.0f%%", pct) then
            local curve = ns.HideAtFullCurve()
            if curve then
                local okAlpha, alpha = pcall(UnitHealthPercent, self.unit, true, curve)
                if not (okAlpha and pcall(text.SetAlpha, text, alpha)) then text:SetAlpha(1) end
            end
            return
        end
    end
    text:SetText("")
end

-- A curve mapping health fraction to text alpha: visible below 100%, hidden at 100%.
function ns.HideAtFullCurve()
    if ns.hideAtFull ~= nil then return ns.hideAtFull or nil end
    ns.hideAtFull = false
    if C_CurveUtil and C_CurveUtil.CreateCurve then
        pcall(function()
            local curve = C_CurveUtil.CreateCurve()
            if Enum and Enum.LuaCurveType then curve:SetType(Enum.LuaCurveType.Linear) end
            curve:AddPoint(0, 1)
            curve:AddPoint(0.995, 1)
            curve:AddPoint(1, 0)
            ns.hideAtFull = curve
        end)
    end
    return ns.hideAtFull or nil
end

-- Colours --------------------------------------------------------------------

-- 0 = no threat, 1 = above tank but not tanking, 2 = tanking insecurely, 3 = securely tanking.
local function ThreatStatus(unit)
    if not UnitThreatSituation then return nil end
    if not Plain(UnitAffectingCombat(unit)) then return nil end
    return Plain(UnitThreatSituation("player", unit))
end

function Plate:UpdateColor()
    local unit, db = self.unit, ns.db
    local threat = ThreatStatus(unit)
    self.threat = threat
    local color

    if db.tankMode and threat then
        color = (threat == 3) and COLOR_TANK_OK or COLOR_TANK_BAD
    elseif Plain(UnitIsPlayer(unit)) then
        local canAttack = Plain(UnitCanAttack("player", unit))
        local class = Plain(select(2, UnitClass(unit)))
        local cc = class and RAID_CLASS_COLORS[class]
        if canAttack and db.classColors and cc then
            color = { cc.r, cc.g, cc.b }
        elseif canAttack then
            color = COLOR_HOSTILE
        else
            color = COLOR_PLAYER
        end
    elseif UnitIsTapDenied and Plain(UnitIsTapDenied(unit)) then
        color = COLOR_TAPPED
    else
        local reaction = Plain(UnitReaction(unit, "player"))
        if reaction then
            if reaction <= 3 then color = COLOR_HOSTILE
            elseif reaction == 4 then color = COLOR_NEUTRAL
            else color = COLOR_FRIENDLY end
        elseif UnitSelectionColor then
            -- Reaction hidden: let the game pick the colour; widgets accept secrets.
            self.health:SetStatusBarColor(UnitSelectionColor(unit))
        else
            color = COLOR_HOSTILE
        end
    end

    if color then
        self.health:SetStatusBarColor(color[1], color[2], color[3])
    end
    self:UpdateGlow()
end

function Plate:UpdateRaidIcon()
    local index = self.unit and Plain(GetRaidTargetIndex(self.unit))
    if index then
        SetRaidTargetIconTexture(self.raidIcon, index)
        self.raidIcon:Show()
    else
        self.raidIcon:Hide()
    end
end

-- Target and glow ------------------------------------------------------------

function Plate:UpdateTarget()
    if not self.unit then return end
    -- Compare plate frames rather than unit info, which may be hidden.
    local targetPlate = UnitExists("target") and C_NamePlate.GetNamePlateForUnit("target")
    self.isTarget = (targetPlate == self.nameplate)
    if self.isTarget or not UnitExists("target") then
        self:SetAlpha(1)
    else
        self:SetAlpha(ns.db.nonTargetAlpha)
    end
    self:SetFrameLevel(self.isTarget and 10 or 1)
    self:UpdateGlow()
end

-- Target gets a soft white glow; otherwise, outside tank mode, a threat glow.
function Plate:UpdateGlow()
    local threat = self.threat
    if self.isTarget then
        self.glow:Set(1, 1, 1, 0.75)
    elseif not ns.db.tankMode and threat and threat >= 1 then
        if threat >= 2 then self.glow:Set(1, 0.1, 0.1, 0.9)
        else self.glow:Set(1, 0.6, 0.1, 0.9) end
    else
        self.glow:Hide()
    end
end

-- Cast bars ------------------------------------------------------------------

-- Reads the current cast or channel. Timing values may be hidden.
local function GetCast(unit)
    if UnitCastingInfo then
        local name, _, icon, startMS, endMS, _, _, notInt = UnitCastingInfo(unit)
        if Has(name) then return name, icon, startMS, endMS, false, notInt end
    end
    if UnitChannelInfo then
        local name, _, icon, startMS, endMS, _, notInt = UnitChannelInfo(unit)
        if Has(name) then return name, icon, startMS, endMS, true, notInt end
    end
end

-- Hands a hidden cast timer straight to the bar, where the client supports it.
local function SetHiddenTimer(cast, unit, channel)
    local getDuration = channel and UnitChannelDuration or UnitCastingDuration
    if not (getDuration and cast.SetTimerDuration) then return false end
    local ok, duration = pcall(getDuration, unit)
    if not ok or duration == nil then return false end
    local direction
    if Enum and Enum.StatusBarTimerDirection then
        direction = channel and Enum.StatusBarTimerDirection.RemainingTime
            or Enum.StatusBarTimerDirection.ElapsedTime
    end
    return pcall(cast.SetTimerDuration, cast, duration, nil, direction)
end

function Plate:UpdateCast()
    local cast, unit = self.cast, self.unit
    if not ns.db.castBars then cast:Hide() return end
    local name, icon, startMS, endMS, channel, notInt = GetCast(unit)
    if name == nil then
        if not cast.hideAt then
            if cast:IsShown() then cast.stoppedAt = GetTime() end
            cast:Hide()
        end
        return
    end

    cast.hideAt = nil
    cast.channel = channel
    local s, e = Plain(startMS), Plain(endMS)
    if s and e then
        cast.timed = true
        cast.startTime, cast.endTime = s / 1000, e / 1000
        cast:SetMinMaxValues(0, math.max(cast.endTime - cast.startTime, 0.001))
        CastOnUpdate(cast)
    else
        cast.timed = false
        if not SetHiddenTimer(cast, unit, channel) then
            -- No way to show progress: show a full bar until the cast ends.
            cast:SetMinMaxValues(0, 1)
            cast:SetValue(1)
        end
    end

    local c = (Plain(notInt) == true) and COLOR_UNINTERRUPT or (channel and COLOR_CHANNEL or COLOR_CAST)
    cast:SetStatusBarColor(c[1], c[2], c[3])
    cast.icon:SetTexture(icon)
    cast.text:SetText(name)
    if not cast.timed or GetTime() < cast.endTime then cast:Show() end
end

-- Briefly show a red "Interrupted" bar before hiding it.
function Plate:ShowInterrupted()
    local cast = self.cast
    -- The STOP event can arrive just before INTERRUPTED and hide the bar first.
    local justStopped = cast.stoppedAt and GetTime() - cast.stoppedAt < 0.2
    if not ns.db.castBars or not (cast:IsShown() or justStopped) then return end
    cast.timed = false
    cast.hideAt = GetTime() + 0.6
    cast:SetMinMaxValues(0, 1)
    cast:SetValue(1)
    cast:SetStatusBarColor(COLOR_INTERRUPTED[1], COLOR_INTERRUPTED[2], COLOR_INTERRUPTED[3])
    cast.text:SetText(INTERRUPTED or "Interrupted")
    cast:Show()
end

-- Auras ----------------------------------------------------------------------

-- One aura as a table (name, icon, applications, duration, expirationTime,
-- auraInstanceID), using whichever aura API this client has.
local function GetAuraData(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        return C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    elseif UnitAura then
        local name, icon, count, _, duration, expiration = UnitAura(unit, index, filter)
        if not Has(name) then return nil end
        return { name = name, icon = icon, applications = count,
                 duration = duration, expirationTime = expiration }
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
    button.count:SetFont(FONT, math.max(db.nameSize - 2, 7), "OUTLINE")
    button.count:SetPoint("BOTTOMRIGHT", 2, -2)
    self.auraButtons[i] = button
    return button
end

local function SetAuraCount(button, unit, aura)
    local count = Plain(aura.applications)
    if count ~= nil or aura.auraInstanceID == nil then
        button.count:SetText((count and count > 1) and count or "")
        return
    end
    local get = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount
    if not (get and pcall(function()
        button.count:SetText(get(unit, aura.auraInstanceID, 2, 99))
    end)) then
        button.count:SetText("")
    end
end

local function SetAuraTimer(button, unit, aura)
    local duration, expiration = Plain(aura.duration), Plain(aura.expirationTime)
    if duration and expiration then
        if duration > 0 then
            button.cd:SetCooldown(expiration - duration, duration)
            button.cd:Show()
        else
            button.cd:Hide()
        end
        return
    end
    local get = C_UnitAuras and C_UnitAuras.GetAuraDuration
    if get and aura.auraInstanceID ~= nil and button.cd.SetCooldownFromDurationObject
        and pcall(function()
            button.cd:SetCooldownFromDurationObject(get(unit, aura.auraInstanceID))
        end) then
        button.cd:Show()
    else
        button.cd:Hide()
    end
end

-- Your own debuffs on attackable units, in a centred row above the name.
function Plate:UpdateAuras()
    local unit, db = self.unit, ns.db
    local shown = 0
    if db.auras and db.maxAuras > 0 and Plain(UnitCanAttack("player", unit)) then
        for i = 1, 40 do
            local aura = GetAuraData(unit, i, "HARMFUL|PLAYER")
            if not aura then break end
            shown = shown + 1
            local button = self:GetAuraButton(shown)
            button.icon:SetTexture(aura.icon)
            SetAuraCount(button, unit, aura)
            SetAuraTimer(button, unit, aura)
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
