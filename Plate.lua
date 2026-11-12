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
local GLOW_SIZE = 7      -- how far the glow reaches past the bar
local GLOW_EDGE = 12 / 32 -- part of the glow texture used by each edge slice

-- Bar colours are deliberately dark and muted.
local COLOR_HOSTILE  = { 0.56, 0.16, 0.08 }
local COLOR_NEUTRAL  = { 0.66, 0.54, 0.08 }
local COLOR_FRIENDLY = { 0.16, 0.46, 0.10 }
local COLOR_PLAYER   = { 0.14, 0.34, 0.62 } -- friendly players without class colours
local COLOR_TAPPED   = { 0.40, 0.40, 0.40 }
local COLOR_TANK_OK  = { 0.16, 0.36, 0.66 } -- tank mode: you hold threat
local COLOR_TANK_BAD = { 0.72, 0.32, 0.06 } -- tank mode: threat slipping
local CLASS_DIM = 0.72 -- class colours are toned down to sit with the rest

local GLOW_TARGET = { 0.30, 0.70, 1.00, 1 }
local GLOW_THREAT = { 1.00, 0.10, 0.10, 1 }
local GLOW_THREAT_LOW = { 1.00, 0.55, 0.10, 1 }
local GLOW_SHADOW = { 0, 0, 0, 0.55 }

-- Name colours for friendly units shown as a name with no bar.
local NAME_FRIENDLY = { 0.55, 0.95, 0.55 }
local NAME_NEUTRAL  = { 1.00, 0.90, 0.45 }
local NAME_PLAYER   = { 0.62, 0.72, 1.00 }

local COLOR_CAST        = { 0.62, 0.62, 0.78 } -- pale grey-lilac
local COLOR_CHANNEL     = { 0.62, 0.62, 0.78 }
local COLOR_UNINTERRUPT = { 0.62, 0.44, 0.30 } -- dull orange: can't be interrupted
local COLOR_INTERRUPTED = { 0.80, 0.20, 0.16 }

-- Unit events each plate listens to, registered only for its own unit.
-- Some don't exist on every client, so each is registered safely.
local UNIT_EVENTS = {
    "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH",
    "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_CLASSIFICATION_CHANGED",
    "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE",
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
        fill:SetVertexColor(0.05, 0.03, 0.03, fillAlpha)
        fill:SetAllPoints(frame)
        return fill
    end
end

-- Soft glow around a frame. The glow texture is a blurred box; it is drawn as
-- four corners and four edges so it keeps its shape at any bar size.
local function AddGlow(frame)
    local pieces = {}
    local e, s = GLOW_EDGE, GLOW_SIZE
    local function Piece(left, right, top, bottom)
        local tex = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        tex:SetTexture(GLOW)
        tex:SetTexCoord(left, right, top, bottom)
        pieces[#pieces + 1] = tex
        return tex
    end
    -- The glow starts at the outside of the 1px border.
    local tl = Piece(0, e, 0, e)
    tl:SetSize(s, s)
    tl:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", -1, 1)
    local tr = Piece(1 - e, 1, 0, e)
    tr:SetSize(s, s)
    tr:SetPoint("BOTTOMLEFT", frame, "TOPRIGHT", 1, 1)
    local bl = Piece(0, e, 1 - e, 1)
    bl:SetSize(s, s)
    bl:SetPoint("TOPRIGHT", frame, "BOTTOMLEFT", -1, -1)
    local br = Piece(1 - e, 1, 1 - e, 1)
    br:SetSize(s, s)
    br:SetPoint("TOPLEFT", frame, "BOTTOMRIGHT", 1, -1)
    local top = Piece(e, 1 - e, 0, e)
    top:SetPoint("BOTTOMLEFT", tl, "BOTTOMRIGHT")
    top:SetPoint("TOPRIGHT", tr, "TOPLEFT")
    local bottom = Piece(e, 1 - e, 1 - e, 1)
    bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT")
    bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    local left = Piece(0, e, e, 1 - e)
    left:SetPoint("TOPRIGHT", tl, "BOTTOMRIGHT")
    left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT")
    local right = Piece(1 - e, 1, e, 1 - e)
    right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
    right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")

    local glow = {}
    function glow:Set(color)
        if self.color == color then return end
        self.color = color
        for _, tex in ipairs(pieces) do
            tex:SetVertexColor(color[1], color[2], color[3], color[4])
            tex:Show()
        end
    end
    function glow:Hide()
        if self.color == false then return end
        self.color = false
        for _, tex in ipairs(pieces) do tex:Hide() end
    end
    glow:Hide()
    return glow
end

-- Scale that makes one layout unit one screen pixel on a 1080p display, and
-- the same apparent size on larger ones, whatever the UI scale is set to.
local function PixelScale()
    local height
    if GetPhysicalScreenSize then
        local _, h = GetPhysicalScreenSize()
        height = h
    end
    if not height or height <= 0 then
        return UIParent:GetEffectiveScale()
    end
    return 768 / height * math.max(1, height / 1080)
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
    health.fill = AddBorder(health, 0.9)
    -- Darkens the bar when the game picks the colour for us (see UpdateColor).
    health.dim = health:CreateTexture(nil, "ARTWORK", nil, 1)
    health.dim:SetTexture(SOLID)
    health.dim:SetVertexColor(0, 0, 0, 0.4)
    health.dim:SetAllPoints(health)
    health.dim:Hide()
    plate.health = health
    plate.glow = AddGlow(health)

    -- Cast bar under the health bar, spell icon to the left of both bars.
    local cast = CreateFrame("StatusBar", nil, plate)
    cast:SetStatusBarTexture(BAR)
    cast:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -3)
    cast:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -3)
    local castFill = AddBorder(cast, 0.9)
    castFill:SetVertexColor(0.07, 0.07, 0.11, 0.9)
    -- Bright spark riding the leading edge of the bar. It is anchored to the
    -- bar's own texture, so it follows hidden cast timers with no maths.
    local edge = cast:GetStatusBarTexture()
    cast.sparkGlow = cast:CreateTexture(nil, "OVERLAY", nil, 1)
    cast.sparkGlow:SetTexture(SOLID)
    cast.sparkGlow:SetVertexColor(0.85, 0.85, 1, 0.3)
    cast.sparkGlow:SetWidth(4)
    cast.sparkGlow:SetPoint("CENTER", edge, "RIGHT", 0, 0)
    cast.spark = cast:CreateTexture(nil, "OVERLAY", nil, 2)
    cast.spark:SetTexture(SOLID)
    cast.spark:SetVertexColor(0.93, 0.93, 1, 0.95)
    cast.spark:SetWidth(2)
    cast.spark:SetPoint("CENTER", edge, "RIGHT", 0, 0)
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
    cast.text:SetPoint("TOP", cast, "BOTTOM", 0, -3)
    cast:SetScript("OnUpdate", CastOnUpdate)
    cast:Hide()
    plate.cast = cast

    plate.pending = {}

    -- Text sits on its own frame above the bars so nothing draws over it.
    local text = CreateFrame("Frame", nil, plate)
    text:SetAllPoints(health)
    text:SetFrameLevel(health:GetFrameLevel() + 3)
    plate.text = text

    plate.name = text:CreateFontString(nil, "OVERLAY")
    plate.name:SetWordWrap(false)

    -- Level and health percent straddle the bottom edge of the bar.
    plate.level = health:CreateFontString(nil, "OVERLAY")
    plate.level:SetPoint("LEFT", health, "BOTTOMLEFT", 2, 1)

    plate.healthText = health:CreateFontString(nil, "OVERLAY")
    plate.healthText:SetPoint("RIGHT", health, "BOTTOMRIGHT", -2, 1)

    plate.raidIcon = text:CreateTexture(nil, "OVERLAY")
    plate.raidIcon:SetTexture(RAID_ICONS)
    plate.raidIcon:SetSize(16, 16)
    plate.raidIcon:SetPoint("RIGHT", health, "LEFT", -5, 0)
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
    -- Size plates in screen pixels rather than following the nameplate's own
    -- scale, which makes them far larger than intended.
    local scale = PixelScale() * (db.scale or 1)
    if self.SetIgnoreParentScale then
        self:SetIgnoreParentScale(true)
        self:SetScale(scale)
    else
        local ok, parentScale = pcall(self.nameplate.GetEffectiveScale, self.nameplate)
        parentScale = ok and Plain(parentScale)
        if parentScale and parentScale > 0 then self:SetScale(scale / parentScale) end
    end
    self.health:SetSize(db.width, db.height)
    self.name:SetFont(FONT, db.nameSize, "OUTLINE")
    self.name:SetWidth(db.width + 60)
    self:PlaceName()
    local small = math.max(db.nameSize - 2, 7)
    self.level:SetFont(FONT, small, "OUTLINE")
    self.healthText:SetFont(FONT, small, "OUTLINE")
    self.cast:SetHeight(db.castHeight)
    self.cast.spark:SetHeight(db.castHeight + 2)
    self.cast.sparkGlow:SetHeight(db.castHeight + 2)
    self.cast.text:SetFont(FONT, math.max(db.nameSize - 1, 7), "OUTLINE")
    self.cast.icon:SetWidth(db.height + db.castHeight + 3)
    self:PlaceAuras()
end

-- The name overlaps the top edge of the bar. With no bar it takes the bar's place.
function Plate:PlaceName()
    local name = self.name
    name:ClearAllPoints()
    if self.nameOnly then
        name:SetPoint("CENTER", self.health, "CENTER", 0, 0)
    else
        name:SetPoint("BOTTOM", self.health, "TOP", 0, -math.floor(ns.db.nameSize * 0.36 + 0.5))
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
    Try(self.DetachAuras, self)
    self.unit = nil
    self.cast:Hide()
    self:Hide()
end

function Plate:OnEvent(event)
    if not self.unit then return end
    if event == "UNIT_HEALTH" or event == "UNIT_HEALTH_FREQUENT" or event == "UNIT_MAXHEALTH" then
        ns:Queue(self, "health")
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
    Try(self.AttachAuras, self)
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

-- Friendly units can be shown as just a coloured name, with no bar.
function Plate:UpdateMode()
    local unit, db = self.unit, ns.db
    -- Only when the game plainly says the unit can't be attacked.
    local nameOnly = db.nameOnly and Plain(UnitCanAttack("player", unit)) == false
    if nameOnly ~= self.nameOnly then
        self.nameOnly = nameOnly
        self.health:SetShown(not nameOnly)
        self:PlaceName()
        if nameOnly then self.cast:Hide() end
    end
    if not nameOnly then
        self.name:SetTextColor(1, 1, 1)
        return
    end
    local color
    if Plain(UnitIsPlayer(unit)) then
        local class = Plain(select(2, UnitClass(unit)))
        local cc = class and RAID_CLASS_COLORS[class]
        if cc then
            self.name:SetTextColor(cc.r, cc.g, cc.b)
            return
        end
        color = NAME_PLAYER
    else
        local reaction = Plain(UnitReaction(unit, "player"))
        color = (reaction and reaction <= 4) and NAME_NEUTRAL or NAME_FRIENDLY
    end
    self.name:SetTextColor(color[1], color[2], color[3])
end

function Plate:UpdateColor()
    local unit, db = self.unit, ns.db
    self:UpdateMode()
    local threat = ThreatStatus(unit)
    self.threat = threat
    local color
    self.health.dim:Hide()

    if db.tankMode and threat then
        color = (threat == 3) and COLOR_TANK_OK or COLOR_TANK_BAD
    elseif Plain(UnitIsPlayer(unit)) then
        local canAttack = Plain(UnitCanAttack("player", unit))
        local class = Plain(select(2, UnitClass(unit)))
        local cc = class and RAID_CLASS_COLORS[class]
        if canAttack and db.classColors and cc then
            color = { cc.r * CLASS_DIM, cc.g * CLASS_DIM, cc.b * CLASS_DIM }
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
            -- It can't be toned down with maths, so a dark overlay does it.
            self.health:SetStatusBarColor(UnitSelectionColor(unit))
            self.health.dim:Show()
            self.health.fill:SetVertexColor(0.05, 0.03, 0.03, 0.9)
        else
            color = COLOR_HOSTILE
        end
    end

    if color then
        self.health:SetStatusBarColor(color[1], color[2], color[3])
        -- The empty part of the bar is a very dark shade of the same colour.
        self.health.fill:SetVertexColor(color[1] * 0.22, color[2] * 0.22, color[3] * 0.22, 0.9)
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

-- Target gets a soft blue glow; otherwise, outside tank mode, a red threat
-- glow; everything else a faint dark shadow.
function Plate:UpdateGlow()
    local threat = self.threat
    if self.isTarget then
        self.glow:Set(GLOW_TARGET)
    elseif not ns.db.tankMode and threat and threat >= 1 then
        self.glow:Set(threat >= 2 and GLOW_THREAT or GLOW_THREAT_LOW)
    else
        self.glow:Set(GLOW_SHADOW)
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
    if not ns.db.castBars or self.nameOnly then cast:Hide() return end
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
    cast.spark:Show()
    cast.sparkGlow:Show()
    if not cast.timed or GetTime() < cast.endTime then cast:Show() end
end

-- Briefly show a red "Interrupted" bar before hiding it.
function Plate:ShowInterrupted()
    local cast = self.cast
    -- The STOP event can arrive just before INTERRUPTED and hide the bar first.
    local justStopped = cast.stoppedAt and GetTime() - cast.stoppedAt < 0.2
    if not ns.db.castBars or self.nameOnly or not (cast:IsShown() or justStopped) then return end
    cast.timed = false
    cast.hideAt = GetTime() + 0.6
    cast:SetMinMaxValues(0, 1)
    cast:SetValue(1)
    cast:SetStatusBarColor(COLOR_INTERRUPTED[1], COLOR_INTERRUPTED[2], COLOR_INTERRUPTED[3])
    cast.text:SetText(INTERRUPTED or "Interrupted")
    cast.spark:Hide()
    cast.sparkGlow:Hide()
    cast:Show()
end

-- Debuffs --------------------------------------------------------------------
--
-- While combat restrictions are active, WoW: Forever refuses addons any aura
-- data at all (C_UnitAuras calls raise an error), so this addon cannot draw
-- debuff icons itself. The game's own nameplate keeps a debuff row up to date
-- for every unit, and its code is allowed to read auras. That row is borrowed:
-- it is re-parented onto our plate and placed above the name. Only engine
-- properties (parent, scale, anchors) are touched, never the game's own Lua
-- data, so its code keeps running untainted.

local GAME_ICON_SIZE = 25 -- size the game draws its nameplate aura icons at
local auraOwners = setmetatable({}, { __mode = "k" }) -- game unit frame -> our plate
local hookedFrames = setmetatable({}, { __mode = "k" })

local hookedAuras = setmetatable({}, { __mode = "k" })
local styledIcons = setmetatable({}, { __mode = "k" }) -- game icon frame -> font size styled at

local ICON_HEIGHT = 15 -- of GAME_ICON_SIZE wide: a short, wide icon
local LIST_KEYS = { "DebuffListFrame", "BuffListFrame", "CrowdControlListFrame" }

-- One-off restyle of a game aura icon: wide crop, thin black border, no
-- rounded mask or frame art, and the timer as a yellow number on the top-left
-- corner. Only looks are changed; the game still decides what is shown.
local function StyleIcon(item, fontSize)
    if styledIcons[item] == fontSize then return end
    local first = not styledIcons[item]
    styledIcons[item] = fontSize
    local icon, cd = item.Icon, item.Cooldown
    if first then
        item:SetHeight(ICON_HEIGHT)
        if icon then
            for _, region in ipairs({ item:GetRegions() }) do
                if region ~= icon then
                    if region:IsObjectType("MaskTexture") then
                        icon:RemoveMaskTexture(region)
                    else
                        region:Hide() -- the rounded frame art
                    end
                end
            end
            -- Black backing one pixel larger than the icon, with a pixel of
            -- space on the right so neighbouring icons don't touch.
            local back = item:CreateTexture(nil, "BACKGROUND")
            back:SetTexture(SOLID)
            back:SetVertexColor(0, 0, 0, 1)
            back:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 0)
            back:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -1, 0)
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", item, "TOPLEFT", 1, -1)
            icon:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -2, 1)
            icon:SetTexCoord(0.08, 0.92, 0.25, 0.75)
        end
    end
    if cd then
        for _, region in ipairs({ cd:GetRegions() }) do
            if region:IsObjectType("FontString") then
                region:SetFont(FONT, fontSize, "OUTLINE")
                region:SetTextColor(1, 0.85, 0.25)
                region:ClearAllPoints()
                region:SetPoint("TOPLEFT", item, "TOPLEFT", -3, 5)
            end
        end
    end
    local count = item.CountFrame and item.CountFrame.Count
    if count then
        count:SetFont(FONT, fontSize, "OUTLINE")
        count:SetTextColor(1, 1, 1)
        count:ClearAllPoints()
        count:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 2, -4)
    end
end

-- Style every icon the game is currently showing in a borrowed row.
local function StyleAuras(auras)
    local db = ns.db
    local fontSize = math.floor(db.nameSize * GAME_ICON_SIZE / db.auraWidth + 0.5)
    for _, key in ipairs(LIST_KEYS) do
        local list = auras[key]
        if list then
            for _, item in ipairs({ list:GetChildren() }) do
                StyleIcon(item, fontSize)
                local cd = item.Cooldown
                if cd then
                    -- The game sets these again each time it fills an icon.
                    cd:SetDrawSwipe(false)
                    cd:SetDrawEdge(false)
                    cd:SetHideCountdownNumbers(false)
                end
            end
        end
    end
end

function Plate:PlaceAuras()
    local auras = self.gameAuras
    if not auras then return end
    local db = ns.db
    local scale = db.auraWidth / GAME_ICON_SIZE
    auras:SetScale(scale)
    Try(StyleAuras, auras)
    local list = auras.DebuffListFrame
    if list then
        list:ClearAllPoints()
        -- Offsets are in the row's own scale, so convert from plate units.
        list:SetPoint("BOTTOM", self.health, "TOP", 0, (db.nameSize + 3) / scale)
    end
end

function Plate:AttachAuras()
    self:DetachAuras()
    if not ns.db.auras then return end
    local frame = self.nameplate.UnitFrame
    local auras = frame and frame.AurasFrame
    if not auras or (auras.IsForbidden and auras:IsForbidden()) then return end
    -- The game re-anchors the row whenever it lays its plate out again.
    if not hookedFrames[frame] and frame.UpdateAnchors then
        hookedFrames[frame] = true
        hooksecurefunc(frame, "UpdateAnchors", function(f)
            local owner = auraOwners[f]
            if owner then Try(owner.PlaceAuras, owner) end
        end)
    end
    -- Restyle icons each time the game refills the row.
    if not hookedAuras[auras] and auras.RefreshAuras then
        hookedAuras[auras] = true
        hooksecurefunc(auras, "RefreshAuras", function(a)
            if a:GetParent() ~= frame then Try(StyleAuras, a) end
        end)
    end
    auraOwners[frame] = self
    self.gameFrame, self.gameAuras = frame, auras
    auras:SetParent(self)
    auras:SetFrameLevel(self.text:GetFrameLevel() + 1)
    self:PlaceAuras()
end

-- Hand the row back to the game's frame, which is reused for other units.
function Plate:DetachAuras()
    local frame, auras = self.gameFrame, self.gameAuras
    if not auras then return end
    self.gameFrame, self.gameAuras = nil, nil
    if auraOwners[frame] == self then auraOwners[frame] = nil end
    auras:SetParent(frame)
    auras:SetScale(1)
end
