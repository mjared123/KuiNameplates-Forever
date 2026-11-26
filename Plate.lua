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
local ARROW = MEDIA .. "arrow.tga" -- right-pointing arrowhead, drawn for this addon
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
local CLASS_DIM = 0.72 -- class colours are toned down to sit with the rest

local GLOW_TARGET = { 0.30, 0.70, 1.00, 1 }
local GLOW_THREAT = { 1.00, 0.10, 0.10, 1 }
local GLOW_THREAT_LOW = { 1.00, 0.55, 0.10, 1 }
local GLOW_SHADOW = { 0, 0, 0, 0.55 }

-- Name colours for friendly units shown as a name with no bar.
local NAME_FRIENDLY = { 0.64, 0.97, 0.66 } -- pale mint
local NAME_NEUTRAL  = { 1.00, 0.90, 0.45 }
local NAME_PLAYER   = { 0.66, 0.68, 1.00 } -- lilac

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
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_TARGET", "UNIT_DISPLAYPOWER", "UNIT_MAXPOWER",
    "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE",
}

local CAST_EVENTS = {
    UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_DELAYED = true, UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_CHANNEL_UPDATE = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_INTERRUPTIBLE = true, UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true,
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
    return ok, err
end
ns.Try = Try
ns.Plain = Plain

-- A colour the player picked in the settings, such as "arrow" or "caster".
local function PickedColor(prefix)
    local db = ns.db
    return { db[prefix .. "R"], db[prefix .. "G"], db[prefix .. "B"] }
end

-- A unit's class colour as r, g, b, plus true when those are hidden values.
-- In battlegrounds the game can hide which class an enemy is. The hidden
-- class can still be handed back to the game for its colour, which widgets
-- accept. Returns nil when there is no class colour to use.
local function ClassColor(unit)
    local class = select(2, UnitClass(unit))
    if class == nil then return nil end -- nil checks are allowed on hidden values
    if IsSecret(class) then
        local ok, r, g, b = pcall(function()
            return C_ClassColor.GetClassColor(class):GetRGB()
        end)
        if ok and r ~= nil then return r, g, b, true end
        return nil
    end
    local cc = RAID_CLASS_COLORS[class]
    if cc then return cc.r, cc.g, cc.b, false end
end

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

-- Elite icon -------------------------------------------------------------------
--
-- A small gem on the top left corner of the bar marks elites, rares and
-- bosses. It is built from squares turned 45 degrees, so it needs no image.

local GEM_GOLD = { 1.00, 0.80, 0.20 }
local GEMS = {
    elite     = { light = { 1.00, 0.84, 0.30 }, dark = { 0.62, 0.40, 0.04 } },
    rare      = { light = { 0.90, 0.94, 1.00 }, dark = { 0.45, 0.50, 0.58 } },
    rareelite = { light = { 0.90, 0.94, 1.00 }, dark = { 0.45, 0.50, 0.58 }, rim = GEM_GOLD },
    worldboss = { light = { 1.00, 0.36, 0.26 }, dark = { 0.50, 0.06, 0.04 }, rim = GEM_GOLD },
}
ns.GEMS = GEMS

local function CreateGem(parent)
    local gem = CreateFrame("Frame", nil, parent)
    local function Piece(sublevel)
        local t = gem:CreateTexture(nil, "ARTWORK", nil, sublevel)
        t:SetTexture(SOLID)
        t:SetPoint("CENTER")
        if t.SetRotation then t:SetRotation(math.pi / 4) end
        return t
    end
    gem.edge = Piece(0)
    gem.edge:SetVertexColor(0, 0, 0, 1)
    gem.rim = Piece(1)
    gem.fill = Piece(2)
    gem.shine = Piece(3)
    gem.shine:SetVertexColor(1, 1, 1, 0.85)
    gem:Hide()
    return gem
end

-- size is the gem's height from point to point.
local function SizeGem(gem, size)
    gem:SetSize(size, size)
    local side = size / math.sqrt(2) -- a turned square is this much taller
    gem.edge:SetSize(side + 2, side + 2)
    gem.rim:SetSize(side, side)
    gem.side = side
    local shine = math.max(2, side * 0.32)
    gem.shine:SetSize(shine, shine)
    gem.shine:ClearAllPoints()
    gem.shine:SetPoint("CENTER", 0, size * 0.17)
end

-- Show the gem for a classification ("elite", "rare", ...), or hide it.
local function SetGem(gem, kind)
    local look = kind and GEMS[kind]
    if not look then gem:Hide() return end
    local side = gem.side or 8
    if look.rim then
        gem.rim:SetVertexColor(look.rim[1], look.rim[2], look.rim[3], 1)
        gem.rim:Show()
        gem.fill:SetSize(side - 2.5, side - 2.5)
    else
        gem.rim:Hide()
        gem.fill:SetSize(side, side)
    end
    local l, d = look.light, look.dark
    local ok = gem.fill.SetGradient and CreateColor and pcall(gem.fill.SetGradient, gem.fill,
        "VERTICAL", CreateColor(d[1], d[2], d[3], 1), CreateColor(l[1], l[2], l[3], 1))
    if ok then
        gem.fill:SetVertexColor(1, 1, 1, 1)
    else
        gem.fill:SetVertexColor(l[1], l[2], l[3], 1)
    end
    gem:Show()
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

    -- Cast bar. Its position, size and icon depend on the chosen style and
    -- are set in LayoutCast.
    local cast = CreateFrame("StatusBar", nil, plate)
    cast:SetStatusBarTexture(BAR)
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
    -- Below the bar's own texture, so the bar can sweep across the icon.
    cast.icon = cast:CreateTexture(nil, "BORDER")
    local iconBorder = cast:CreateTexture(nil, "BACKGROUND", nil, -7)
    iconBorder:SetTexture(SOLID)
    iconBorder:SetVertexColor(0, 0, 0, 1)
    iconBorder:SetPoint("TOPLEFT", cast.icon, -1, 1)
    iconBorder:SetPoint("BOTTOMRIGHT", cast.icon, 1, -1)
    cast.text = cast:CreateFontString(nil, "OVERLAY")
    cast.text:SetDrawLayer("OVERLAY", 7) -- above the spark
    cast.text:SetShadowColor(0, 0, 0, 1)
    cast.text:SetShadowOffset(1, -1)
    cast:SetScript("OnUpdate", CastOnUpdate)
    cast:Hide()
    -- Target arrows step out past the cast icon while a cast shows.
    -- The target-of-target name moves below the spell name.
    cast:SetScript("OnShow", function() plate:PlaceArrows() plate:PlaceTargetName() end)
    cast:SetScript("OnHide", function() plate:PlaceArrows() plate:PlaceTargetName() end)
    plate.cast = cast

    plate.pending = {}

    -- Text sits on its own frame above the bars so nothing draws over it.
    local text = CreateFrame("Frame", nil, plate)
    text:SetAllPoints(health)
    text:SetFrameLevel(health:GetFrameLevel() + 3)
    plate.text = text

    plate.name = text:CreateFontString(nil, "OVERLAY")
    plate.name:SetWordWrap(false)

    -- Second line under a friendly name: an NPC's title or a player's guild.
    plate.title = text:CreateFontString(nil, "OVERLAY")
    plate.title:SetWordWrap(false)
    plate.title:SetTextColor(0.84, 0.84, 0.82)
    plate.title:Hide()
    -- A hard drop shadow on top of the outline keeps both lines crisp.
    for _, fs in ipairs({ plate.name, plate.title }) do
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    end

    -- Health as name: on name-only plates the name itself shows health. The
    -- name above is drawn dark grey (the missing part), and a copy in the
    -- normal colour is laid exactly over it inside a clipping frame. The
    -- clip's right edge follows the fill of an invisible status bar covering
    -- the text, so the game sizes it from the (hidden) health; no maths.
    local hpBar = CreateFrame("StatusBar", nil, text)
    hpBar:SetStatusBarTexture(SOLID)
    hpBar:SetStatusBarColor(0, 0, 0, 0)
    hpBar:SetAlpha(0)
    hpBar:SetPoint("TOP", plate.name, "TOP")
    hpBar:SetPoint("BOTTOM", plate.name, "BOTTOM")
    hpBar:SetWidth(1)
    hpBar:SetMinMaxValues(0, 1)
    hpBar:SetValue(1)
    local hpClip = CreateFrame("Frame", nil, text)
    hpClip:SetFrameLevel(text:GetFrameLevel() + 1)
    hpClip:SetClipsChildren(true)
    hpClip:SetPoint("TOPLEFT", hpBar, "TOPLEFT")
    hpClip:SetPoint("BOTTOMLEFT", hpBar, "BOTTOMLEFT")
    hpClip:SetPoint("RIGHT", hpBar:GetStatusBarTexture(), "RIGHT")
    local hpHolder = CreateFrame("Frame", nil, hpClip)
    hpHolder:SetAllPoints(hpClip)
    local hpText = hpHolder:CreateFontString(nil, "OVERLAY")
    hpText:SetWordWrap(false)
    hpText:SetShadowColor(0, 0, 0, 1)
    hpText:SetShadowOffset(1, -1)
    hpText:SetPoint("TOPLEFT", plate.name, "TOPLEFT")
    hpText:SetPoint("BOTTOMRIGHT", plate.name, "BOTTOMRIGHT")
    hpClip:Hide()
    plate.hpName = { bar = hpBar, clip = hpClip, text = hpText }
    plate.nameColor = { 1, 1, 1 }

    -- Level and health percent straddle the bottom edge of the bar. The
    -- level is placed in ApplyLayout, where the player's nudge is added.
    plate.level = health:CreateFontString(nil, "OVERLAY")

    plate.healthText = health:CreateFontString(nil, "OVERLAY")

    -- Level on the left of a friendly name shown without a bar.
    plate.friendLevel = text:CreateFontString(nil, "OVERLAY")
    plate.friendLevel:SetShadowColor(0, 0, 0, 1)
    plate.friendLevel:SetShadowOffset(1, -1)
    plate.friendLevel:Hide()

    -- Current health as a plain number. It starts on the bottom left edge of
    -- the bar, where the level sits when that is on, and can be moved.
    plate.healthNumber = health:CreateFontString(nil, "OVERLAY")

    -- Power bar (mana, energy, rage) under the health bar.
    local power = CreateFrame("StatusBar", nil, plate)
    power:SetStatusBarTexture(BAR)
    AddBorder(power, 0.9)
    power:SetMinMaxValues(0, 1)
    power:SetValue(0)
    power:Hide()
    plate.power = power
    plate.powerGap = 0
    -- Power number, drawn above the bars on a frame that hides with the bar.
    local powerTextHolder = CreateFrame("Frame", nil, power)
    powerTextHolder:SetAllPoints(power)
    powerTextHolder:SetFrameLevel(text:GetFrameLevel())
    plate.powerText = powerTextHolder:CreateFontString(nil, "OVERLAY")

    -- Elite, rare and boss gem. It belongs to the bar, so it hides on
    -- name-only plates along with it.
    plate.elite = CreateGem(health)
    plate.elite:SetFrameLevel(text:GetFrameLevel() + 1)

    plate.raidIcon = text:CreateTexture(nil, "OVERLAY")
    plate.raidIcon:SetTexture(RAID_ICONS)
    plate.raidIcon:SetSize(22, 22)
    plate.raidIcon:Hide()

    -- Arrows either side of the bar on your target, pointing in at it.
    plate.arrows = {}
    for _, side in ipairs({ "left", "right" }) do
        local arrow = text:CreateTexture(nil, "OVERLAY", nil, -1)
        arrow:SetTexture(ARROW)
        if side == "right" then arrow:SetTexCoord(1, 0, 0, 1) end -- mirrored
        arrow:Hide()
        plate.arrows[side] = arrow
    end

    -- Who this unit is targeting, under the bar.
    plate.targetName = text:CreateFontString(nil, "OVERLAY")
    plate.targetName:SetWordWrap(false)
    plate.targetName:SetShadowColor(0, 0, 0, 1)
    plate.targetName:SetShadowOffset(1, -1)
    plate.targetName:Hide()

    plate:SetScript("OnEvent", plate.OnEvent)
    plate:ApplyLayout()

    nameplate.KuiForeverPlate = plate
    ns.allPlates = ns.allPlates or {}
    ns.allPlates[plate] = true
    return plate
end

-- Size plates in screen pixels rather than following the nameplate's own
-- scale, which makes them far larger than intended. Your target can be made
-- a little bigger so it stands out.
function Plate:ApplyScale()
    local db = ns.db
    local scale = PixelScale() * (db.scale or 1)
    if self.isTarget then scale = scale * (db.targetScale or 1) end
    if self.appliedScale == scale then return end
    self.appliedScale = scale
    if self.SetIgnoreParentScale then
        self:SetIgnoreParentScale(true)
        self:SetScale(scale)
    else
        local ok, parentScale = pcall(self.nameplate.GetEffectiveScale, self.nameplate)
        parentScale = ok and Plain(parentScale)
        if parentScale and parentScale > 0 then self:SetScale(scale / parentScale) end
    end
end

function Plate:ApplyLayout()
    self.appliedScale = nil -- size settings may have changed
    local db = ns.db
    self:ApplyScale()
    self.health:SetSize(db.width, db.height)
    self.name:SetWidth(db.width + 60)
    ns.SetFont(self.title, db.titleSize)
    self.title:SetTextColor(db.titleR, db.titleG, db.titleB)
    self.title:SetWidth(db.width + 60)
    self:PlaceName()
    self.level:SetFont(ns.FontFile(), db.infoSize, "OUTLINE")
    self.healthText:SetFont(ns.FontFile(), db.infoSize, "OUTLINE")
    self.healthText:ClearAllPoints()
    self.healthText:SetPoint("RIGHT", self.health, "BOTTOMRIGHT", -2 + (db.healthTextX or 0), 1 + (db.healthTextY or 0))
    ns.SetFont(self.friendLevel, db.friendLevelSize or 10)
    self.healthNumber:SetFont(ns.FontFile(), db.infoSize, "OUTLINE")
    self.powerText:SetFont(ns.FontFile(), db.infoSize, "OUTLINE")
    self.powerText:ClearAllPoints()
    self.powerText:SetPoint("CENTER", self.power, "CENTER", db.powerTextX or 0, db.powerTextY or 0)
    self.level:ClearAllPoints()
    self.level:SetPoint("LEFT", self.health, "BOTTOMLEFT", 2 + (db.levelX or 0), 1 + (db.levelY or 0))
    self.healthNumber:ClearAllPoints()
    self.healthNumber:SetPoint("LEFT", self.health, "BOTTOMLEFT", 2 + (db.healthNumberX or 0), 1 + (db.healthNumberY or 0))
    self:PlaceElite()
    self:PlacePower()
    ns.SetFont(self.cast.text, db.castTextSize)
    ns.SetFont(self.targetName, db.castTextSize)
    self.targetName:SetWidth(db.width)
    self:LayoutCast()
    self:PlaceTargetName()
    self:PlaceArrows()
    self:PlaceAuras()
end

ns.CAST_STYLES = { "thin", "tall", "icon" }
ns.CAST_STYLE_NAMES = {
    thin = "Thin bar, icon beside both bars",
    tall = "Tall bar with the spell name inside",
    icon = "Icon only",
}

-- Arrange the cast bar, its icon and the spell name for the chosen style.
function Plate:LayoutCast()
    local db, cast, health = ns.db, self.cast, self.health
    local icon, text = cast.icon, cast.text
    local style = ns.CAST_STYLE_NAMES[db.castStyle] and db.castStyle or "thin"
    local dy = db.castTextOffset or 0 -- the spell name moved up (+) or down (-)
    local gap = self.powerGap or 0     -- room left for the power bar
    cast.style = style
    cast:ClearAllPoints()
    icon:ClearAllPoints()
    text:ClearAllPoints()
    local height
    if style == "icon" then
        -- A wide spell icon under the bar; progress sweeps across the icon
        -- and the spell name sits on its bottom edge.
        height = db.castHeight + 13
        cast:SetSize(height * 2, height)
        cast:SetPoint("TOP", health, "BOTTOM", 0, -6 - gap)
        icon:SetAllPoints(cast)
        icon:SetTexCoord(0.08, 0.92, 0.29, 0.71)
        text:SetPoint("CENTER", cast, "BOTTOM", 0, -1 + dy)
    elseif style == "tall" then
        -- A taller bar under the health bar with the spell name inside it,
        -- and a square icon to the left as tall as both bars together.
        height = db.castHeight + 11
        cast:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -3 - gap)
        cast:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -3 - gap)
        cast:SetHeight(height)
        icon:SetPoint("TOPRIGHT", health, "TOPLEFT", -3, 0)
        icon:SetPoint("BOTTOMRIGHT", cast, "BOTTOMLEFT", -3, 0)
        icon:SetWidth(db.height + height + 3)
        icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        text:SetPoint("CENTER", cast, "CENTER", 0, dy)
    else
        -- A thin bar under the health bar, a square icon to the left of
        -- both bars, and the spell name underneath.
        height = db.castHeight
        cast:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -3 - gap)
        cast:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -3 - gap)
        cast:SetHeight(height)
        icon:SetPoint("TOPRIGHT", health, "TOPLEFT", -3, 0)
        icon:SetPoint("BOTTOMRIGHT", cast, "BOTTOMLEFT", -3, 0)
        icon:SetWidth(db.height + height + 3)
        icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        text:SetPoint("TOP", cast, "BOTTOM", 0, -3 + dy)
    end
    cast.spark:SetHeight(height + 2)
    cast.sparkGlow:SetHeight(height + 2)
end

-- Colour the cast bar. Over the icon it is a light see-through wash instead.
local function SetCastColor(cast, color)
    cast:SetStatusBarColor(color[1], color[2], color[3], cast.style == "icon" and 0.4 or 1)
end

-- Colour the cast bar by whether the cast can be interrupted. In combat the
-- game may hide the answer; it then picks between the two colours itself.
local function SetInterruptColor(cast, notInterruptible)
    local open, locked = PickedColor("cast"), PickedColor("castLock")
    if not IsSecret(notInterruptible) then
        SetCastColor(cast, notInterruptible and locked or open)
        return
    end
    SetCastColor(cast, open)
    local alpha = cast.style == "icon" and 0.4 or 1
    pcall(function()
        cast:GetStatusBarTexture():SetVertexColorFromBoolean(notInterruptible,
            CreateColor(locked[1], locked[2], locked[3], alpha),
            CreateColor(open[1], open[2], open[3], alpha))
    end)
end

-- The name overlaps the top edge of the bar. With no bar it takes the bar's place.
function Plate:PlaceName()
    local db = ns.db
    local name, title = self.name, self.title
    -- Names on a bar and names standing on their own have separate sizes.
    ns.SetFont(name, self.nameOnly and db.friendNameSize or db.nameSize)
    name:ClearAllPoints()
    title:ClearAllPoints()
    if self.nameOnly and self.hasTitle then
        -- Title lowest, close to the unit's head, with the name above it. A
        -- gap of 0 has the two lines just touching.
        title:SetPoint("BOTTOM", self, "BOTTOM", 0, db.nameOnlyOffset or 0)
        name:SetPoint("BOTTOM", title, "TOP", 0, (db.titleSpacing or 0) - 2)
    elseif self.nameOnly then
        -- Sit low on the plate, close to the unit's head.
        name:SetPoint("BOTTOM", self, "BOTTOM", 0, db.nameOnlyOffset or 0)
    else
        -- Overlapping the top edge of the bar, plus the chosen nudge.
        name:SetPoint("BOTTOM", self.health, "TOP", 0,
            (db.nameOffset or 0) - math.floor(db.nameSize * 0.36 + 0.5))
    end
    self:PlaceRaidIcon()
    self:SyncHealthName()
end

-- Health as name -------------------------------------------------------------

local NAME_MISSING = { 0.35, 0.35, 0.35 } -- the part of the name standing for lost health

-- Set the name's colour. With health as name showing, the colour goes to the
-- overlay and the name underneath stays grey.
function Plate:SetNameColor(r, g, b)
    local c = self.nameColor
    c[1], c[2], c[3] = r, g, b
    if self.hpName.clip:IsShown() then
        self.hpName.text:SetTextColor(r, g, b)
    else
        self.name:SetTextColor(r, g, b)
    end
end

-- Copy the name's text and font to the overlay and fit the hidden bar to the
-- text. Values are only passed from one widget to another, never inspected.
function Plate:SyncHealthName()
    local hp, name = self.hpName, self.name
    if not hp.clip:IsShown() then return end
    local object = name:GetFontObject()
    if object then
        local r, g, b = hp.text:GetTextColor()
        hp.text:SetFontObject(object)
        hp.text:SetTextColor(r, g, b)
        hp.text:SetShadowColor(0, 0, 0, 1)
        hp.text:SetShadowOffset(1, -1)
    else
        local font, size, flags = name:GetFont()
        if font then hp.text:SetFont(font, size, flags) end
    end
    hp.text:SetJustifyH(name:GetJustifyH())
    hp.text:SetText(name:GetText())
    if not pcall(hp.bar.SetWidth, hp.bar, name:GetStringWidth()) then
        -- Can't size the bar to the text: fall back to a plain name.
        self:ShowHealthName(false)
    end
end

-- Turn health as name on or off for this plate, keeping the name's colour.
function Plate:ShowHealthName(show)
    local hp, c = self.hpName, self.nameColor
    show = (show and ns.db.healthName and self.nameOnly) and true or false
    hp.clip:SetShown(show)
    if show then
        self.name:SetTextColor(NAME_MISSING[1], NAME_MISSING[2], NAME_MISSING[3])
        hp.text:SetTextColor(c[1], c[2], c[3])
        self:SyncHealthName()
    else
        self.name:SetTextColor(c[1], c[2], c[3])
    end
end

-- Feed the hidden bar. Health may be secret, so it goes straight in.
function Plate:SetHealthNameValue(cur, max)
    local bar = self.hpName.bar
    if cur == nil or max == nil then -- unknown health: show the whole name
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        return
    end
    bar:SetMinMaxValues(0, max)
    bar:SetValue(cur)
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
    Try(ns.ClearDots, self)
    self.unit = nil
    self.cast:Hide()
    self:SetHealthNameValue(nil, nil)
    self:ShowHealthName(false)
    self.friendLevel:Hide()
    self.isTarget, self.friendly = false, nil
    self.wantsPower = false
    if self.power:IsShown() then
        self.power:Hide()
        self:RelayoutBelow()
    end
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
    elseif event == "UNIT_TARGET" then
        Try(self.UpdateTargetName, self)
    elseif event == "UNIT_NAME_UPDATE" then
        Try(self.UpdateName, self)
    elseif event == "UNIT_LEVEL" or event == "UNIT_CLASSIFICATION_CHANGED" then
        Try(self.UpdateLevel, self)
        Try(self.UpdateElite, self)
    elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" then
        if self.wantsPower then Try(self.UpdatePower, self) end
    else -- faction, threat or power type changes
        Try(self.UpdateColor, self)
        if event == "UNIT_DISPLAYPOWER" or event == "UNIT_MAXPOWER" then
            Try(self.UpdatePower, self)
        end
    end
end

-- Each part updates on its own, so one failure can't stop the plate drawing.
function Plate:UpdateAll()
    if not self.unit then return end
    Try(self.UpdateName, self)
    Try(self.UpdateLevel, self)
    Try(self.UpdateElite, self)
    Try(self.UpdateHealth, self)
    Try(self.UpdateColor, self)
    Try(self.UpdateRaidIcon, self)
    Try(self.UpdateTarget, self)
    Try(self.UpdateCast, self)
    Try(self.UpdateTargetName, self)
    Try(self.AttachAuras, self)
    Try(ns.UpdateDots, self)
end

ns.NAME_PARTS = { "full", "first", "last" }
ns.NAME_PART_NAMES = {
    full = "First and last name",
    first = "First name only",
    last = "Last name only",
}

-- WoW: Forever characters can have a first name and a surname. The game
-- joins the two with this separator.
local function SurnameSeparator()
    local consts = Constants and Constants.CharacterNameSeparatorConsts
    local sep = consts and consts.CHARACTERNAME_SURNAME_SEPARATOR
    if type(sep) == "string" and sep ~= "" then return sep end
    return " "
end

-- Pick the parts of a player's name to show. `first` and `last` are plain
-- strings; `last` may be nil.
local function ChooseNameParts(first, last, mode)
    if not last or last == "" then return first end
    if mode == "first" then return first end
    if mode == "last" then return last end
    return first .. SurnameSeparator() .. last
end
ns.ChooseNameParts = ChooseNameParts

function Plate:UpdateName()
    self:SetNameText()
    self:SyncHealthName()
    if self.friendLevel:IsShown() then self:PlaceFriendLevel() end
end

function Plate:SetNameText()
    local unit, label = self.unit, self.name
    -- UnitName returns the first name and, for characters that have one,
    -- the surname.
    local name, surname = UnitName(unit)
    if name == nil then -- nil checks are allowed on hidden values
        label:SetText("")
        return
    end
    local mode = ns.db.nameParts or "full"
    local first, last = Plain(name), Plain(surname)

    if first == nil or (surname ~= nil and last == nil) then
        -- The game is hiding the text: it can be shown but not inspected.
        if surname == nil or mode == "first" then
            label:SetText(name)
        elseif mode == "last" then
            label:SetText(surname)
        elseif not pcall(label.SetFormattedText, label, "%s" .. SurnameSeparator() .. "%s", name, surname) then
            label:SetText(name)
        end
        return
    end

    -- Some realms hand back both parts joined in the first value. Only
    -- players have surnames, so NPC names with spaces are left alone.
    if (last == nil or last == "") and Plain(UnitIsPlayer(unit)) then
        local sep = SurnameSeparator()
        local at = first:find(sep, 1, true)
        if at and at > 1 and at + #sep <= #first then
            first, last = first:sub(1, at - 1), first:sub(at + #sep)
        end
    end
    label:SetText(ChooseNameParts(first, last, mode))
end

-- Write a unit's level, with elite/rare marks, into a font string,
-- coloured by difficulty. Returns false when the level is hidden.
local function SetLevelText(fs, unit)
    local level = Plain(UnitLevel(unit))
    local class = Plain(UnitClassification(unit))
    local suffix = (class and CLASSIFICATION_SUFFIX[class]) or ""
    if level and level > 0 then
        local getColor = GetCreatureDifficultyColor or GetQuestDifficultyColor
        local c = getColor and getColor(level)
        fs:SetText(level .. suffix)
        if c then fs:SetTextColor(c.r, c.g, c.b) end
    elseif level then
        fs:SetText("??" .. suffix)
        fs:SetTextColor(1, 0.2, 0.2)
    else
        fs:SetText("")
        return false
    end
    return true
end

function Plate:UpdateLevel()
    local unit = self.unit
    if ns.db.showLevel then SetLevelText(self.level, unit) else self.level:SetText("") end
    self:UpdateFriendLevel()
end

-- The level left of a friendly name, when the plate shows just the name.
function Plate:UpdateFriendLevel()
    local fs = self.friendLevel
    if not (ns.db.friendLevel and self.nameOnly and self.unit) or not SetLevelText(fs, self.unit) then
        fs:Hide()
        return
    end
    self:PlaceFriendLevel()
    fs:Show()
end

-- The name's font string is wider than its text and centred, so the level is
-- placed half the text's width left of the centre.
function Plate:PlaceFriendLevel()
    local db, fs = ns.db, self.friendLevel
    local ok, half = pcall(function() return self.name:GetStringWidth() / 2 end)
    if not ok or type(half) ~= "number" then half = 30 end
    fs:ClearAllPoints()
    fs:SetPoint("RIGHT", self.name, "CENTER", -half - 3 + (db.friendLevelX or 0), db.friendLevelY or 0)
end

-- Health ---------------------------------------------------------------------

function Plate:UpdateHealth()
    local unit = self.unit
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    -- Status bars accept secret values directly.
    self.health:SetMinMaxValues(0, max)
    self.health:SetValue(cur)
    self:SetHealthNameValue(cur, max)
    self:UpdateHealthText(cur, max)
    self:UpdateHealthNumber(cur, max)
    if self.dotBar then Try(ns.UpdateDots, self) end
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

-- Number styles ---------------------------------------------------------------

ns.NUMBER_STYLES = { "number", "short", "percent", "curmax", "numpercent", "curmaxpercent" }
ns.NUMBER_STYLE_NAMES = {
    number = "Number (3432)",
    short = "Short (3.4k)",
    percent = "Percent (62%)",
    curmax = "Number / max (3432 / 5500)",
    numpercent = "Number and percent (3432 | 62%)",
    curmaxpercent = "Number / max and percent",
}

-- Readable numbers are formatted here. 3432 -> "3,432" with commas on.
local function Commas(n)
    local s = string.format("%d", n)
    local sign, digits = s:match("^(-?)(%d+)$")
    if not digits then return s end
    digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return sign .. digits
end

local function Short(n)
    local a = math.abs(n)
    if a >= 1e9 then return string.format("%.1fb", n / 1e9):gsub("%.0b", "b") end
    if a >= 1e6 then return string.format("%.1fm", n / 1e6):gsub("%.0m", "m") end
    if a >= 1e4 then return string.format("%.0fk", n / 1e3) end
    if a >= 1e3 then return string.format("%.1fk", n / 1e3):gsub("%.0k", "k") end
    return string.format("%d", n)
end

-- One number as text. A readable number is formatted in Lua; a hidden one
-- is handed to the game's own formatters, which accept hidden values, or
-- else passed on as it is.
local function FormatOne(value, short, commas)
    local plain = Plain(value)
    if plain then
        if short then return (Short(plain)) end
        return commas and Commas(plain) or string.format("%d", plain)
    end
    if short and AbbreviateNumbers then
        local ok, s = pcall(AbbreviateNumbers, value)
        if ok and s ~= nil then return s end
    elseif commas and BreakUpLargeNumbers then
        local ok, s = pcall(BreakUpLargeNumbers, value)
        if ok and s ~= nil then return s end
    end
    return value
end

-- Fill a font string with cur and max in the chosen style. getPercent()
-- returns the game's own 0-100 percent (possibly hidden) when the numbers
-- themselves are hidden; it may be nil.
local function SetNumberText(fs, style, cur, max, getPercent)
    if cur == nil then fs:SetText("") return end
    local commas = ns.db.numberCommas
    local wantPct = style == "percent" or style == "numpercent" or style == "curmaxpercent"
    local pct
    if wantPct then
        local c, m = Plain(cur), Plain(max)
        if c and m then
            pct = m > 0 and math.floor(c / m * 100 + 0.5) or 0
        elseif getPercent then
            local ok, p = pcall(getPercent)
            if ok then pct = p end
        end
    end
    local num = FormatOne(cur, style == "short", commas)
    local ok
    if style == "percent" then
        ok = pct ~= nil and pcall(fs.SetFormattedText, fs, "%.0f%%", pct)
    elseif style == "curmax" or style == "curmaxpercent" then
        local mx = max ~= nil and FormatOne(max, false, commas) or nil
        if mx == nil then
            ok = pcall(fs.SetFormattedText, fs, "%s", num)
        elseif style == "curmaxpercent" and pct ~= nil then
            ok = pcall(fs.SetFormattedText, fs, "%s / %s | %.0f%%", num, mx, pct)
        else
            ok = pcall(fs.SetFormattedText, fs, "%s / %s", num, mx)
        end
    elseif style == "numpercent" and pct ~= nil then
        ok = pcall(fs.SetFormattedText, fs, "%s | %.0f%%", num, pct)
    else
        ok = pcall(fs.SetFormattedText, fs, "%s", num)
    end
    if not ok and not pcall(fs.SetText, fs, cur) then fs:SetText("") end
end
ns.SetNumberText = SetNumberText

-- Current health as text, such as 3432, shown at any health. Hidden values
-- are handed straight to the text and never inspected.
function Plate:UpdateHealthNumber(cur, max)
    local text, unit = self.healthNumber, self.unit
    if not ns.db.healthNumber then text:SetText("") return end
    SetNumberText(text, ns.db.healthNumberStyle, cur, max, function()
        return UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
    end)
end

-- Power bar ------------------------------------------------------------------

ns.POWER_SHOWS = { "off", "self", "target", "enemies", "all" }
ns.POWER_SHOW_NAMES = {
    off = "Off",
    self = "Your own plate only",
    target = "Your target (and your own plate)",
    enemies = "All enemies (and your own plate)",
    all = "Every plate with a health bar",
}

local POWER_FALLBACK = { 0.00, 0.55, 1.00 } -- mana blue
local POWER_ENERGY = { 1.00, 0.96, 0.41 }

-- The power bar hangs under the health bar, moved by the player's nudge.
-- While it shows, the cast bar, target name and combo points move down to
-- make room for as much of it as sits below the health bar.
function Plate:PlacePower()
    local db, power = ns.db, self.power
    local height = db.powerHeight or 3
    local x, y = db.powerX or 0, db.powerY or 0
    power:ClearAllPoints()
    power:SetPoint("TOPLEFT", self.health, "BOTTOMLEFT", x, y - 2)
    power:SetPoint("TOPRIGHT", self.health, "BOTTOMRIGHT", x, y - 2)
    power:SetHeight(height)
    self.powerGap = power:IsShown() and math.max(0, height + 2 - y) or 0
end

-- Re-place everything that sits under the health bar.
function Plate:RelayoutBelow()
    self:PlacePower()
    self:LayoutCast()
    self:PlaceTargetName()
    if self.combo and self.combo:IsShown() and ns.UpdateCombo then Try(ns.UpdateCombo, ns) end
end

-- Whether this plate should show a power bar, from the setting.
function Plate:WantsPower()
    local mode = ns.db.powerBar
    if not (self.unit and ns.POWER_SHOW_NAMES[mode]) or mode == "off" or self.nameOnly then
        return false
    end
    if mode == "all" then return true end
    -- Your own plate (the game's personal resource display, when it's on).
    local ok, own = pcall(C_NamePlate.GetNamePlateForUnit, "player")
    if (ok and own and own == self.nameplate) or Plain(UnitIsUnit(self.unit, "player")) then
        return true
    end
    if mode == "enemies" then return Plain(UnitCanAttack("player", self.unit)) == true end
    return mode == "target" and self.isTarget or false
end

-- Power numbers may be hidden, so they go straight to the bar.
function Plate:UpdatePower()
    local power, unit = self.power, self.unit
    local show = self:WantsPower()
    self.wantsPower = show
    local max = show and UnitPowerMax(unit) or nil
    if max == nil or Plain(max) == 0 then show = false end
    if show then
        local ptype, token = UnitPowerType(unit)
        ptype, token = Plain(ptype), Plain(token)
        local colors = PowerBarColor
        local c = colors and ((token and colors[token]) or (ptype and colors[ptype])) or nil
        if c and c.r then
            power:SetStatusBarColor(c.r, c.g, c.b)
        else
            power:SetStatusBarColor(POWER_FALLBACK[1], POWER_FALLBACK[2], POWER_FALLBACK[3])
        end
        local cur = UnitPower(unit)
        power:SetMinMaxValues(0, max)
        power:SetValue(cur)
        if ns.db.powerText then
            SetNumberText(self.powerText, ns.db.powerTextStyle, cur, max, function()
                return UnitPowerPercent(unit, nil, true, CurveConstants.ScaleTo100)
            end)
        else
            self.powerText:SetText("")
        end
    end
    if show ~= power:IsShown() then
        power:SetShown(show)
        self:RelayoutBelow()
    end
end

-- A sample energy bar on the test plate.
function Plate:TestPower(show)
    local power, mode = self.power, ns.db.powerBar
    show = (show and mode ~= "off" and ns.POWER_SHOW_NAMES[mode]) and true or false
    if show then
        local c = PowerBarColor and PowerBarColor.ENERGY
        if c and c.r then
            power:SetStatusBarColor(c.r, c.g, c.b)
        else
            power:SetStatusBarColor(POWER_ENERGY[1], POWER_ENERGY[2], POWER_ENERGY[3])
        end
        power:SetMinMaxValues(0, 100)
        power:SetValue(60)
        if ns.db.powerText then
            SetNumberText(self.powerText, ns.db.powerTextStyle, 60, 100)
        else
            self.powerText:SetText("")
        end
    end
    power:SetShown(show)
    self:RelayoutBelow()
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

-- The line shown under a friendly name: "<Guild>" for players, and for NPCs
-- the title from the second line of their tooltip ("Flight Master"). Returns
-- nil when there is none or the game is hiding it.
local function GetSubtitle(unit)
    if Plain(UnitIsPlayer(unit)) then
        local guild = GetGuildInfo and Plain(GetGuildInfo(unit))
        if type(guild) == "string" and guild ~= "" then return "<" .. guild .. ">" end
        return nil
    end
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok or type(data) ~= "table" or IsSecret(data) then return nil end
    local okLine, text = pcall(function() return data.lines[2].leftText end)
    text = okLine and Plain(text)
    if type(text) ~= "string" or text == "" then return nil end
    -- With no title, the second line is the level line instead.
    local levelWord = type(LEVEL) == "string" and LEVEL or "Level"
    if text:find(levelWord, 1, true) then return nil end
    return text
end

function Plate:UpdateTitle()
    local text = self.nameOnly and ns.db.showTitle and GetSubtitle(self.unit) or nil
    local has = text ~= nil
    if has then self.title:SetText(text) end
    self.title:SetShown(has)
    if has ~= self.hasTitle then
        self.hasTitle = has
        self:PlaceName()
    end
end

-- Friendly units can be shown as just a coloured name, with no bar.
function Plate:UpdateMode()
    local unit, db = self.unit, ns.db
    -- Only when the game plainly says the unit can't be attacked.
    self.friendly = Plain(UnitCanAttack("player", unit)) == false
    local nameOnly = db.nameOnly and self.friendly
    if nameOnly ~= self.nameOnly then
        self.nameOnly = nameOnly
        self.health:SetShown(not nameOnly)
        self:PlaceName()
        if nameOnly then self.cast:Hide() end
    end
    Try(self.UpdateFriendLevel, self)
    Try(self.UpdateTitle, self)
    self:ShowHealthName(nameOnly)
    if not nameOnly then
        self:SetNameColor(1, 1, 1)
        return
    end
    local color
    if Plain(UnitIsPlayer(unit)) then
        local r, g, b = ClassColor(unit)
        if r ~= nil then
            self:SetNameColor(r, g, b)
            return
        end
        color = NAME_PLAYER
    else
        local reaction = Plain(UnitReaction(unit, "player"))
        color = (reaction and reaction <= 4) and NAME_NEUTRAL or NAME_FRIENDLY
    end
    self:SetNameColor(color[1], color[2], color[3])
end

-- Power type 0 is mana.
local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

-- True for NPCs that use mana: mages, priests, shamans and other casters.
-- Player pets (an imp, say) don't count. The class the game gives an NPC can
-- be hidden, and so can the size of its mana pool, but its power type isn't.
local function IsCaster(unit)
    if Plain(UnitPlayerControlled(unit)) then return false end
    local class = Plain((select(2, UnitClass(unit))))
    if class == "WARRIOR" or class == "ROGUE" then return false end
    local power = Plain((UnitPowerType(unit)))
    if power == nil then return class == "MAGE" or class == "PALADIN" end
    if power ~= MANA then return false end
    local pool = Plain(UnitPowerMax(unit, MANA))
    return pool == nil or pool > 0
end

-- Colour the bar with values the game may be hiding. They can't be toned
-- down with maths, so a dark overlay does it.
function Plate:SetHiddenBarColor(dim, r, g, b)
    local health = self.health
    health:SetStatusBarColor(r, g, b)
    health.dim:SetVertexColor(0, 0, 0, dim)
    health.dim:Show()
    health.fill:SetVertexColor(0.05, 0.03, 0.03, 0.9)
end

-- Colour the bar, with the empty part a very dark shade of the same colour.
function Plate:SetBarColor(color)
    local health = self.health
    health.dim:Hide()
    health:SetStatusBarColor(color[1], color[2], color[3])
    health.fill:SetVertexColor(color[1] * 0.22, color[2] * 0.22, color[3] * 0.22, 0.9)
end

function Plate:UpdateColor()
    local unit, db = self.unit, ns.db
    self:UpdateMode()
    local threat = ThreatStatus(unit)
    self.threat = threat
    local color

    if db.tankMode and threat then
        color = PickedColor(threat == 3 and "tankOk" or "tankBad")
    elseif Plain(UnitIsPlayer(unit)) then
        if Plain(UnitCanAttack("player", unit)) then
            color = COLOR_HOSTILE
            if db.classColors then
                local r, g, b, hidden = ClassColor(unit)
                if hidden then
                    if pcall(self.SetHiddenBarColor, self, 1 - CLASS_DIM, r, g, b) then color = nil end
                elseif r then
                    color = { r * CLASS_DIM, g * CLASS_DIM, b * CLASS_DIM }
                end
            end
        else
            color = COLOR_PLAYER
        end
    elseif UnitIsTapDenied and Plain(UnitIsTapDenied(unit)) then
        color = COLOR_TAPPED
    else
        local reaction = Plain(UnitReaction(unit, "player"))
        if reaction then
            if reaction <= 3 then
                color = COLOR_HOSTILE
                if db.casterColors then
                    local ok, caster = pcall(IsCaster, unit)
                    if ok and caster then color = PickedColor("caster") end
                end
            elseif reaction == 4 then color = COLOR_NEUTRAL
            else color = COLOR_FRIENDLY end
        elseif UnitSelectionColor then
            -- Reaction hidden: let the game pick the colour; widgets accept secrets.
            self:SetHiddenBarColor(0.4, UnitSelectionColor(unit))
        else
            color = COLOR_HOSTILE
        end
    end

    if color then self:SetBarColor(color) end
    self:UpdateGlow()
end

function Plate:PlaceElite()
    local db = ns.db
    SizeGem(self.elite, db.eliteSize or 12)
    self.elite:ClearAllPoints()
    self.elite:SetPoint("CENTER", self.health, "TOPLEFT", 1 + (db.eliteX or 0), db.eliteY or 0)
end

function Plate:UpdateElite()
    local kind = ns.db.showElite and self.unit and Plain(UnitClassification(self.unit))
    SetGem(self.elite, kind)
end

-- Show a raid mark index (1 to 8) on the icon. The index may be a secret
-- value, so it goes straight to the texture with no maths or comparisons.
local function SetRaidIcon(icon, index)
    if icon.SetSpriteSheetCell then
        icon:SetSpriteSheetCell(index, 4, 4)
    else
        SetRaidTargetIconTexture(icon, index)
    end
end

function Plate:UpdateRaidIcon()
    -- Forever hands back the mark as a secret value, so test only for nil.
    local index = self.unit and GetRaidTargetIndex(self.unit)
    if Has(index) then
        SetRaidIcon(self.raidIcon, index)
        self.raidIcon:Show()
    else
        self.raidIcon:Hide()
    end
end

ns.RAID_SPOTS = { "top", "left", "right" }
ns.RAID_SPOT_NAMES = {
    top = "Above the name and debuffs",
    left = "Left of the bar",
    right = "Right of the bar",
}

-- Raid mark position. "top" stacks it above the name and any debuff rows;
-- "left" and "right" put it beside the bar, clear of the cast icon. If
-- debuffs already use that side, or the plate is just a name, it goes on
-- top instead.
function Plate:PlaceRaidIcon()
    local db, icon = ns.db, self.raidIcon
    local size = db.raidSize or 22
    icon:SetSize(size, size)
    icon:ClearAllPoints()
    local spot = db.raidSpot or "top"
    local auraSpot = db.auras and (db.auraSpot or "top")
    if self.nameOnly then
        icon:SetPoint("BOTTOM", self.name, "TOP", 0, 2)
    elseif spot == "left" and auraSpot ~= "left" then
        local x = 4
        if db.castBars and db.castStyle == "tall" then
            x = db.height + db.castHeight + 20
        elseif db.castBars and db.castStyle ~= "icon" then
            x = db.height + db.castHeight + 9
        end
        if db.targetArrows then x = ns.ArrowRoom("left") end
        icon:SetPoint("RIGHT", self.health, "LEFT", -x, 0)
    elseif spot == "right" and auraSpot ~= "right" then
        -- Past the DoT prediction skull when that is on.
        local x = db.dotPrediction and 20 or 4 -- that skull is 12 wide
        if db.targetArrows then x = ns.ArrowRoom("right") end
        icon:SetPoint("LEFT", self.health, "RIGHT", x, 0)
    elseif (self.debuffHeight or 0) > 0 then
        -- Just above the highest debuff row, with room for its timer text.
        local y = db.nameSize + 3 + (db.auraOffset or 0) + self.debuffHeight + 5
        icon:SetPoint("BOTTOM", self.health, "TOP", 0, y)
    else
        icon:SetPoint("BOTTOM", self.name, "TOP", 0, 1)
    end
end

-- Target arrows ----------------------------------------------------------------
--
-- Both arrows sit just outside the bar, the same distance either side. While
-- a cast shows its icon left of the bar, the left arrow moves out past it;
-- the right arrow never moves, as nothing appears on that side. Both always
-- stay clear of the DoT prediction skull. Anything else placed beside
-- the bar keeps ArrowRoom() free, so it never sits under an arrow.

local function ArrowSize()
    return (ns.db.height + 8) * (ns.db.arrowScale or 1)
end

-- Distance from the bar's edge to the arrow's box. Negative when the arrows
-- are moved in over the bar.
local function ArrowGap(casting)
    local db = ns.db
    local gap = 2
    if not (casting and db.castBars) then
        -- no cast icon to clear
    elseif db.castStyle == "tall" then
        gap = db.height + db.castHeight + 11 + 3 + 3
    elseif db.castStyle ~= "icon" then
        gap = db.height + db.castHeight + 3 + 3 + 3
    end
    if db.dotPrediction then gap = math.max(gap, 4 + 12 + 2) end -- the skull is 12 wide
    return gap + (db.arrowX or 0)
end

-- Room that things beside the bar on `side` ("left" or "right") leave for
-- the arrows, in plate units. Only the left arrow steps out past a cast
-- icon, so the right side needs much less room. The right side also keeps
-- clear of the DoT prediction skull.
function ns.ArrowRoom(side)
    local db = ns.db
    if side == "right" then
        local skull = db.dotPrediction and (4 + 12 + 4) or 0
        if not db.targetArrows then return skull end
        return math.max(ArrowGap(false) + ArrowSize() + 2, skull, 4)
    end
    if not db.targetArrows then return 0 end
    -- Arrows moved in over the bar still leave the cast icon its room.
    return math.max(ArrowGap(true) + ArrowSize() + 2, ArrowGap(true) - (db.arrowX or 0))
end

function Plate:PlaceArrows()
    if not self.arrows then return end
    local size = ArrowSize()
    local leftGap, rightGap = ArrowGap(self.cast:IsShown()), ArrowGap(false)
    local left, right = self.arrows.left, self.arrows.right
    left:SetSize(size, size)
    right:SetSize(size, size)
    left:ClearAllPoints()
    right:ClearAllPoints()
    local y, color = ns.db.arrowY or 0, PickedColor("arrow")
    left:SetVertexColor(color[1], color[2], color[3], 1)
    right:SetVertexColor(color[1], color[2], color[3], 1)
    left:SetPoint("RIGHT", self.health, "LEFT", -leftGap, y)
    right:SetPoint("LEFT", self.health, "RIGHT", rightGap, y)
end

function Plate:ShowArrows(show)
    show = (show and ns.db.targetArrows and not self.nameOnly) and true or false
    self.arrows.left:SetShown(show)
    self.arrows.right:SetShown(show)
end

-- Target of target -------------------------------------------------------------
--
-- The name of whoever this unit is targeting, under the bar: "You" in
-- orange when it is you, players in their class colour.

local TOT_YOU = { 1.00, 0.50, 0.30 }
local TOT_OTHER = { 0.86, 0.86, 0.86 }

function Plate:PlaceTargetName()
    local fs, cast = self.targetName, self.cast
    if not fs then return end
    fs:ClearAllPoints()
    if cast:IsShown() and cast.style == "tall" then
        fs:SetPoint("TOP", cast, "BOTTOM", 0, -3)
    elseif cast:IsShown() then
        fs:SetPoint("TOP", cast.text, "BOTTOM", 0, -1)
    else
        fs:SetPoint("TOP", self.health, "BOTTOM", 0, -4 - (self.powerGap or 0))
    end
end

function Plate:SetTargetName(text, color)
    local fs = self.targetName
    if not pcall(fs.SetFormattedText, fs, "> %s", text) then fs:SetText(text) end
    fs:SetTextColor(color[1], color[2], color[3])
    fs:Show()
end

function Plate:UpdateTargetName()
    local fs = self.targetName
    if not (ns.db.targetName and self.unit and not self.nameOnly) then
        fs:Hide()
        return
    end
    local tt = self.unit .. "target"
    local name = UnitName(tt)
    if name == nil then -- no target; nil checks are allowed on hidden values
        fs:Hide()
        return
    end
    if Plain(UnitIsUnit(tt, "player")) then
        self:SetTargetName(YOU or "You", TOT_YOU)
        return
    end
    local color = TOT_OTHER
    if Plain(UnitIsPlayer(tt)) then
        local r, g, b = ClassColor(tt)
        if r ~= nil then color = { r, g, b } end
    end
    self:SetTargetName(name, color)
end

-- Target and glow ------------------------------------------------------------

function Plate:UpdateTarget()
    if not self.unit then return end
    -- Compare plate frames rather than unit info, which may be hidden.
    local targetPlate = UnitExists("target") and C_NamePlate.GetNamePlateForUnit("target")
    self.isTarget = (targetPlate == self.nameplate)
    self:ApplyScale()
    if self.isTarget or not UnitExists("target") or (self.friendly and ns.db.friendlyNoFade) then
        self:SetAlpha(1)
    elseif self.nameOnly then
        -- Bare names stay readable instead of fading with the bars.
        self:SetAlpha(math.max(ns.db.nonTargetAlpha, 0.9))
    else
        self:SetAlpha(ns.db.nonTargetAlpha)
    end
    self:SetFrameLevel(self.isTarget and 10 or 1)
    self:ShowArrows(self.isTarget)
    self:UpdateGlow()
    -- You may have become (or stopped being) this unit's target.
    Try(self.UpdateTargetName, self)
    Try(self.UpdatePower, self)
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

    SetInterruptColor(cast, notInt)
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
    SetCastColor(cast, COLOR_INTERRUPTED)
    cast.text:SetText(INTERRUPTED or "Interrupted")
    cast.spark:Hide()
    cast.sparkGlow:Hide()
    cast:Show()
end

-- Debuffs --------------------------------------------------------------------
--
-- While combat restrictions are active, WoW: Forever refuses addons any aura
-- data at all (C_UnitAuras calls raise an error), so this addon cannot draw
-- debuff icons itself. The game's own nameplate keeps aura rows up to date
-- for every unit, and its code is allowed to read auras. Those rows are
-- borrowed: they are re-parented onto our plate, and each icon is restyled
-- and positioned here. Only engine properties (parent, scale, anchors, looks)
-- are touched, never the game's own Lua data, so its code keeps running
-- untainted.

local GAME_ICON_SIZE = 25 -- width the game draws its nameplate aura icons at
local ICON_HEIGHT = 15    -- our icons are short and wide
local ICON_GAP = 2
local ROW_STEP = ICON_HEIGHT + 8 -- row spacing, with room for the timer text

local weak = { __mode = "k" }
local auraOwners = setmetatable({}, weak)   -- game unit frame -> our plate
local auraPlates = setmetatable({}, weak)   -- game auras frame -> our plate
local hookedFrames = setmetatable({}, weak)
local hookedAuras = setmetatable({}, weak)
local styledIcons = setmetatable({}, weak)  -- game icon frame -> font size styled at
local iconBorders = setmetatable({}, weak)  -- game icon frame -> our border texture
local lastAura = setmetatable({}, weak)     -- game icon frame -> aura it last showed

-- Border colours by debuff type.
local DISPEL_COLORS = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.64, 0.19, 0.94 },
    Disease = { 0.70, 0.48, 0.10 },
    Poison  = { 0.10, 0.75, 0.15 },
    Bleed   = { 0.85, 0.12, 0.12 },
    Enrage  = { 0.95, 0.45, 0.10 },
}
-- The game's numeric ids for the same types, used when the type is hidden.
local DISPEL_IDS = { Magic = 1, Curse = 2, Disease = 3, Poison = 4, Enrage = 9, Bleed = 11 }

ns.AURA_SPOTS = { "top", "topleft", "bottom", "left", "right" }
ns.AURA_SPOT_NAMES = {
    top = "Above, centred", topleft = "Above, from the left",
    bottom = "Below", left = "Left of the bar", right = "Right of the bar",
}

ns.BUFF_SPOTS = { "top", "bottom" }
ns.BUFF_SPOT_NAMES = {
    top = "Above the name",
    bottom = "Below the bar",
}

-- Remember which aura each icon shows, so its border can be coloured. The
-- hook runs after the game's own code and does not interfere with it.
local itemsHooked = false
local function HookAuraItems()
    if itemsHooked or type(NamePlateAuraItemMixin) ~= "table" then return end
    itemsHooked = true
    hooksecurefunc(NamePlateAuraItemMixin, "SetAura", function(item, aura)
        lastAura[item] = aura
    end)
end
pcall(HookAuraItems)

-- A colour curve mapping the game's debuff type ids to our border colours.
-- With it the game can colour a border for us when the type itself is hidden.
local dispelCurve
local function DispelCurve()
    if dispelCurve ~= nil then return dispelCurve or nil end
    dispelCurve = false
    pcall(function()
        local curve = C_CurveUtil.CreateColorCurve()
        if Enum and Enum.LuaCurveType then curve:SetType(Enum.LuaCurveType.Step) end
        curve:AddPoint(0, CreateColor(0, 0, 0, 1))
        for name, id in pairs(DISPEL_IDS) do
            local c = DISPEL_COLORS[name]
            curve:AddPoint(id, CreateColor(c[1], c[2], c[3], 1))
        end
        dispelCurve = curve
    end)
    return dispelCurve or nil
end

local function SetHiddenTypeColor(border, unit, auraInstanceID)
    local curve = DispelCurve()
    if not curve then error("no colour curve") end
    local color = C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, curve)
    border:SetVertexColor(color:GetRGBA())
end

local function ColorBorder(item, unit)
    local border = iconBorders[item]
    if not border then return end
    local aura = lastAura[item]
    if ns.db.auraColors and aura then
        -- Even reading these fields can be refused in combat.
        local ok, dispel, id = pcall(function() return aura.dispelName, aura.auraInstanceID end)
        if not ok or IsSecret(dispel) then
            if unit and ok and pcall(SetHiddenTypeColor, border, unit, id) then return end
        elseif dispel ~= nil then
            local c = DISPEL_COLORS[dispel]
            if c then
                border:SetVertexColor(c[1], c[2], c[3], 1)
                return
            end
        end
    end
    border:SetVertexColor(0, 0, 0, 1)
end

-- One-off restyle of a game aura icon: wide crop, thin border, no rounded
-- mask or frame art, and the timer as a yellow number on the top-left corner.
local function StyleIcon(item, fontSize)
    local style = fontSize .. ns.FontFile()
    if styledIcons[item] == style then return end
    local first = not styledIcons[item]
    styledIcons[item] = style
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
            local border = item:CreateTexture(nil, "BACKGROUND")
            border:SetTexture(SOLID)
            border:SetVertexColor(0, 0, 0, 1)
            border:SetAllPoints(item)
            iconBorders[item] = border
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", item, "TOPLEFT", 1, -1)
            icon:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -1, 1)
            icon:SetTexCoord(0.08, 0.92, 0.25, 0.75)
        end
    end
    if cd then
        for _, region in ipairs({ cd:GetRegions() }) do
            if region:IsObjectType("FontString") then
                region:SetFont(ns.FontFile(), fontSize, "OUTLINE")
                region:SetTextColor(1, 0.85, 0.25)
                region:ClearAllPoints()
                region:SetPoint("TOPLEFT", item, "TOPLEFT", -3, 5)
            end
        end
    end
    local count = item.CountFrame and item.CountFrame.Count
    if count then
        count:SetFont(ns.FontFile(), fontSize, "OUTLINE")
        count:SetTextColor(1, 1, 1)
        count:ClearAllPoints()
        count:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 2, -4)
    end
end

local function ByLayoutIndex(a, b)
    return (Plain(a.layoutIndex) or 0) < (Plain(b.layoutIndex) or 0)
end

-- Position a set of icons around the health bar. Every icon is anchored
-- straight to the bar, so they always line up whatever the game's own row
-- layout did. Distances are converted from plate units to the icon's scale.
--
-- `stack` (plate units) pushes the rows further out, so a second group can
-- sit beyond a first one: buffs above or below the debuffs.
local function LayoutIcons(plate, items, spot, auraScale, stack)
    local n = #items
    if n == 0 then return end
    local db = ns.db
    local health = plate.health
    local k = auraScale * (Plain(items[1]:GetScale()) or 1)
    if k <= 0 then k = auraScale end
    local w, step = GAME_ICON_SIZE, GAME_ICON_SIZE + ICON_GAP
    local offset = ((db.auraOffset or 0) + (stack or 0)) / k
    -- Beside the bar, clear of the target arrows.
    local room = ns.ArrowRoom(spot == "left" and "left" or "right") / k
    local across = (spot == "left" or spot == "right") and 3
        or math.max(1, math.floor((db.width / k + ICON_GAP) / step))

    for i, item in ipairs(items) do
        local row = math.floor((i - 1) / across)
        local col = (i - 1) % across
        local inRow = math.min(across, n - row * across)
        local rowWidth = inRow * w + (inRow - 1) * ICON_GAP
        item:ClearAllPoints()
        if spot == "bottom" then
            local y = (db.castHeight + db.nameSize + 9) / k + offset
            item:SetPoint("TOPLEFT", health, "BOTTOM", -rowWidth / 2 + col * step, -y - row * ROW_STEP)
        elseif spot == "left" then
            -- Clear of the cast icon, which sits directly left of the bar.
            local x = math.max((db.height + db.castHeight + 9) / k, room) + offset
            item:SetPoint("RIGHT", health, "LEFT", -x - col * step, -row * ROW_STEP)
        elseif spot == "right" then
            local x = math.max(5 / k, room) + offset
            item:SetPoint("LEFT", health, "RIGHT", x + col * step, -row * ROW_STEP)
        elseif spot == "topleft" then
            local y = (db.nameSize + 3) / k + offset
            item:SetPoint("BOTTOMLEFT", health, "TOPLEFT", col * step, y + row * ROW_STEP)
        else -- top, centred
            local y = (db.nameSize + 3) / k + offset
            item:SetPoint("BOTTOMLEFT", health, "TOP", -rowWidth / 2 + col * step, y + row * ROW_STEP)
        end
    end
end

-- Space between a group of rows and the next group stacked beyond it, in
-- plate units, with room for the timer text on the outer group's icons.
local GROUP_GAP = 7

-- Height of a group of icon rows above or below the bar, in plate units.
-- 0 for an empty group or one beside the bar.
local function RowsHeight(items, spot, auraScale)
    local n = #items
    if n == 0 or not (spot == "top" or spot == "topleft" or spot == "bottom") then return 0 end
    local k = auraScale * (Plain(items[1]:GetScale()) or 1)
    if k <= 0 then k = auraScale end
    local step = GAME_ICON_SIZE + ICON_GAP
    local across = math.max(1, math.floor((ns.db.width / k + ICON_GAP) / step))
    local rows = math.ceil(n / across)
    return ((rows - 1) * ROW_STEP + ICON_HEIGHT) * k
end

local function SafeRowsHeight(items, spot, auraScale)
    local ok, height = pcall(RowsHeight, items, spot, auraScale)
    return ok and height or 0
end

local function IsAbove(spot)
    return spot == "top" or spot == "topleft"
end

-- Where the buff group goes. Above the name it lines up with debuffs that
-- start from the left.
local function BuffSpot()
    local db = ns.db
    if db.buffSpot == "bottom" then return "bottom" end
    return db.auraSpot == "topleft" and "topleft" or "top"
end

-- Lay out the debuff and buff groups. Debuffs sit nearest the bar; when both
-- groups are on the same side, buffs stack beyond them. The total height
-- above the name is kept so the raid mark can sit on top.
local function LayoutGroups(plate, debuffs, buffs, auraScale)
    local db = ns.db
    local debuffSpot = db.auraSpot or "top"
    local buffSpot = BuffSpot()
    Try(LayoutIcons, plate, debuffs, debuffSpot, auraScale)
    local debuffHeight = SafeRowsHeight(debuffs, debuffSpot, auraScale)
    local sameSide = (IsAbove(debuffSpot) and IsAbove(buffSpot)) or (debuffSpot == buffSpot)
    local stack = 0
    if sameSide and debuffHeight > 0 then stack = debuffHeight + GROUP_GAP end
    Try(LayoutIcons, plate, buffs, buffSpot, auraScale, stack)
    local buffHeight = SafeRowsHeight(buffs, buffSpot, auraScale)

    local above = 0
    if IsAbove(debuffSpot) then above = debuffHeight end
    if IsAbove(buffSpot) and buffHeight > 0 then
        above = (above > 0) and (above + GROUP_GAP + buffHeight) or buffHeight
    end
    plate.debuffHeight = above
    Try(plate.PlaceRaidIcon, plate)
end

local function ShownChildren(list, into)
    if not list then return into end
    for _, item in ipairs({ list:GetChildren() }) do
        if item:IsShown() then into[#into + 1] = item end
    end
    return into
end

-- Drop the icons of hidden auras from a group (see Filters.lua). Out of
-- combat a hidden icon is made invisible and left out of the layout, so the
-- rest close up. When the game hides the spell from the addon, the game is
-- asked to make the icon invisible instead, and it keeps its place.
local function FilterHidden(items, kind, unit)
    local kept = {}
    for _, item in ipairs(items) do
        local id, name, icon, hiddenID = ns.ReadAura(lastAura[item])
        if id or name then
            ns:NoteSeenAura(id, name, icon, kind)
            if ns:IsAuraHidden(id, name, unit) then
                item:SetAlpha(0)
            else
                item:SetAlpha(1)
                kept[#kept + 1] = item
            end
        else
            if not (hiddenID and ns.HideBySecret(item, hiddenID)) then item:SetAlpha(1) end
            kept[#kept + 1] = item
        end
    end
    return kept
end

-- The buff and debuff icons on your target's plate, with the aura each one
-- shows, for /kui auraprobe.
function ns:TargetAuraItems()
    local nameplate = C_NamePlate.GetNamePlateForUnit("target")
    local plate = nameplate and nameplate.KuiForeverPlate
    local auras = plate and plate.gameAuras
    if not auras then return nil end
    local out = {}
    for _, group in ipairs({ { "debuff", auras.DebuffListFrame }, { "buff", auras.BuffListFrame } }) do
        for _, item in ipairs(ShownChildren(group[2], {})) do
            out[#out + 1] = { kind = group[1], aura = lastAura[item] }
        end
    end
    return out
end

local function PlaceList(list, plate, auraScale)
    if not list then return end
    list:ClearAllPoints()
    list:SetPoint("BOTTOM", plate.health, "TOP", 0, (ns.db.nameSize + 3) / auraScale)
end

-- The game sets these again each time it fills an icon.
local function ResetCooldownLook(item)
    local cd = item.Cooldown
    if not cd then return end
    cd:SetDrawSwipe(false)
    cd:SetDrawEdge(false)
    cd:SetHideCountdownNumbers(false)
end

-- Restyle, colour and position every icon the game is showing in borrowed rows.
local function ArrangeAuras(auras)
    local plate = auraPlates[auras]
    if not plate then return end
    local db = ns.db
    local auraScale = db.auraWidth / GAME_ICON_SIZE
    local fontSize = math.floor((db.auraTextSize or db.nameSize) / auraScale + 0.5)
    -- A group that is switched off is made invisible rather than hidden, so
    -- the game's own code is left to run as it likes.
    if auras.DebuffListFrame then auras.DebuffListFrame:SetAlpha(db.auras and 1 or 0) end
    if auras.BuffListFrame then auras.BuffListFrame:SetAlpha(db.buffs and 1 or 0) end
    local debuffs = db.auras and ShownChildren(auras.DebuffListFrame, {}) or {}
    -- On enemies the game keeps only buffs you can purge or steal, and a
    -- short list of important ones; on friends, the buffs you cast.
    local buffs = db.buffs and ShownChildren(auras.BuffListFrame, {}) or {}
    local okDebuffs, keptDebuffs = Try(FilterHidden, debuffs, "debuff", plate.unit)
    if okDebuffs then debuffs = keptDebuffs end
    local okBuffs, keptBuffs = Try(FilterHidden, buffs, "buff", plate.unit)
    if okBuffs then buffs = keptBuffs end
    local others = ShownChildren(auras.CrowdControlListFrame, {})
    local spot = db.auraSpot or "top"
    local side = spot == "right" and "left" or "right"

    -- Each step is protected on its own, so a failure in one (for example
    -- the game refusing a colour lookup) can never leave icons misplaced.
    -- Baseline: put the game's debuff row itself above the name.
    Try(PlaceList, auras.DebuffListFrame, plate, auraScale)
    -- Then place every icon exactly.
    Try(table.sort, debuffs, ByLayoutIndex)
    Try(table.sort, buffs, ByLayoutIndex)
    LayoutGroups(plate, debuffs, buffs, auraScale)
    -- Crowd control goes beside the bar, away from the debuffs.
    Try(LayoutIcons, plate, others, side, auraScale)
    for _, items in ipairs({ debuffs, buffs, others }) do
        for _, item in ipairs(items) do
            Try(StyleIcon, item, fontSize)
            Try(ResetCooldownLook, item)
            Try(ColorBorder, item, plate.unit)
        end
    end
    -- The single large crowd control icon shown on enemy players sits just
    -- past those, instead of where the game's hidden plate would put it.
    local control = auras.LossOfControlFrame
    if control then
        local scale = Plain(control:GetScale()) or 1
        if scale <= 0 then scale = 1 end
        local room = math.max(5, ns.ArrowRoom(side))
        local gap = (room / auraScale + math.min(#others, 3) * (GAME_ICON_SIZE + ICON_GAP)) / scale
        control:ClearAllPoints()
        if side == "right" then
            control:SetPoint("LEFT", plate.health, "RIGHT", gap, 0)
        else
            gap = gap + math.max(0, ns.db.height + ns.db.castHeight + 4 - room + 5) / auraScale / scale
            control:SetPoint("RIGHT", plate.health, "LEFT", -gap, 0)
        end
    end
end

function Plate:PlaceAuras()
    local auras = self.gameAuras
    if not auras then return end
    auras:SetScale(ns.db.auraWidth / GAME_ICON_SIZE)
    Try(ArrangeAuras, auras)
end

function Plate:AttachAuras()
    self:DetachAuras()
    if not (ns.db.auras or ns.db.buffs) then return end
    local frame = self.nameplate.UnitFrame
    local auras = frame and frame.AurasFrame
    if not auras or (auras.IsForbidden and auras:IsForbidden()) then return end
    pcall(HookAuraItems)
    -- The game re-anchors its rows whenever it lays its plate out again.
    if not hookedFrames[frame] and frame.UpdateAnchors then
        hookedFrames[frame] = true
        hooksecurefunc(frame, "UpdateAnchors", function(f)
            local owner = auraOwners[f]
            if owner then owner:PlaceAuras() end
        end)
    end
    -- Arrange the icons each time the game refills its rows.
    if not hookedAuras[auras] and auras.RefreshAuras then
        hookedAuras[auras] = true
        hooksecurefunc(auras, "RefreshAuras", function(a)
            Try(ArrangeAuras, a)
        end)
        -- When crowd control lands, the game rescales its big crowd control
        -- icon without refilling the rows. Our offset for that icon is
        -- measured in its own scale, so it must be placed again, or it ends
        -- up far out to the side.
        for _, method in ipairs({ "RefreshLossOfControl", "UpdateAuraScale" }) do
            if auras[method] then
                hooksecurefunc(auras, method, function(a)
                    Try(ArrangeAuras, a)
                end)
            end
        end
    end
    auraOwners[frame] = self
    auraPlates[auras] = self
    self.gameFrame, self.gameAuras = frame, auras
    auras:SetParent(self)
    auras:SetFrameLevel(self.text:GetFrameLevel() + 1)
    self:PlaceAuras()
end

-- Hand the rows back to the game's frame, which is reused for other units.
function Plate:DetachAuras()
    local frame, auras = self.gameFrame, self.gameAuras
    if not auras then return end
    self.gameFrame, self.gameAuras = nil, nil
    self.debuffHeight = 0
    Try(self.PlaceRaidIcon, self)
    if auraOwners[frame] == self then auraOwners[frame] = nil end
    if auraPlates[auras] == self then auraPlates[auras] = nil end
    auras:SetParent(frame)
    auras:SetScale(1)
    if auras.DebuffListFrame then auras.DebuffListFrame:SetAlpha(1) end
    if auras.BuffListFrame then auras.BuffListFrame:SetAlpha(1) end
end

-- Test mode --------------------------------------------------------------------
--
-- Sample plates in the middle of the screen, so settings can be tried without
-- finding something to fight: an enemy with a looping cast and sample debuffs,
-- and a friendly name with a title. Nothing here reads unit data.

local TEST_CAST_ICON = "Interface\\Icons\\Spell_Holy_HolyBolt"
local TEST_CAST_TIME = 2.5
local TEST_AURAS = {
    { icon = "Interface\\Icons\\Spell_Shadow_CurseOfSargeras", dispel = "Curse", time = "12" },
    { icon = "Interface\\Icons\\Ability_Hunter_Quickshot", dispel = "Poison", time = "17" },
    { icon = "Interface\\Icons\\Ability_Gouge", time = "4" },
}
-- Purgeable magic buffs, as the game would show on an enemy.
local TEST_BUFFS = {
    { icon = "Interface\\Icons\\Spell_Holy_PowerWordShield", dispel = "Magic", time = "24" },
    { icon = "Interface\\Icons\\Spell_Nature_Rejuvenation", dispel = "Magic", time = "9" },
}

-- Sample bar colour. In tank mode it changes with each cast, showing both
-- threat colours; otherwise the sample enemy counts as a caster.
function Plate:TestColor(friendly)
    local db = ns.db
    if friendly then
        self:SetBarColor(COLOR_FRIENDLY)
    elseif db.tankMode then
        self:SetBarColor(PickedColor(self.testAlternate and "tankBad" or "tankOk"))
    elseif db.casterColors then
        self:SetBarColor(PickedColor("caster"))
    else
        self:SetBarColor(COLOR_HOSTILE)
    end
end

-- Restart the sample cast from the beginning.
function Plate:TestCast()
    local cast = self.cast
    if not ns.db.castBars or self.nameOnly then cast:Hide() return end
    cast.hideAt = nil
    cast.channel = false
    cast.timed = true
    cast.startTime = GetTime()
    cast.endTime = cast.startTime + TEST_CAST_TIME
    cast:SetMinMaxValues(0, TEST_CAST_TIME)
    cast:SetValue(0)
    -- Every other sample cast can't be interrupted, to show both colours.
    SetInterruptColor(cast, self.testAlternate or false)
    cast.icon:SetTexture(TEST_CAST_ICON)
    cast.text:SetText(self.testAlternate and "Can't interrupt" or "Holy Light")
    cast.spark:Show()
    cast.sparkGlow:Show()
    cast:Show()
end

-- A holder of sample icons, drawn the same way as the real ones.
local function MakeTestHolder(plate, list)
    local holder = CreateFrame("Frame", nil, plate)
    holder:SetSize(1, 1)
    holder:SetPoint("CENTER")
    holder:SetFrameLevel(plate.text:GetFrameLevel() + 1)
    holder.items = {}
    for i, info in ipairs(list) do
        local item = CreateFrame("Frame", nil, holder)
        item:SetSize(GAME_ICON_SIZE, ICON_HEIGHT)
        item.border = item:CreateTexture(nil, "BACKGROUND")
        item.border:SetTexture(SOLID)
        item.border:SetAllPoints(item)
        local icon = item:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(info.icon)
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.25, 0.75)
        item.time = item:CreateFontString(nil, "OVERLAY")
        item.time:SetPoint("TOPLEFT", item, "TOPLEFT", -3, 5)
        item.time:SetTextColor(1, 0.85, 0.25)
        holder.items[i] = item
    end
    return holder
end

local function StyleTestHolder(holder, list, auraScale, fontSize)
    local db = ns.db
    holder:SetScale(auraScale)
    for i, item in ipairs(holder.items) do
        local info = list[i]
        local c = db.auraColors and info.dispel and DISPEL_COLORS[info.dispel]
        if c then
            item.border:SetVertexColor(c[1], c[2], c[3], 1)
        else
            item.border:SetVertexColor(0, 0, 0, 1)
        end
        item.time:SetFont(ns.FontFile(), fontSize, "OUTLINE")
        item.time:SetText(info.time)
    end
    holder:Show()
end

-- Sample debuffs and buffs, placed the same way as the real ones.
function Plate:TestAuras(show)
    local db = ns.db
    local showDebuffs, showBuffs = show and db.auras, show and db.buffs
    if showDebuffs and not self.testAuras then self.testAuras = MakeTestHolder(self, TEST_AURAS) end
    if showBuffs and not self.testBuffs then self.testBuffs = MakeTestHolder(self, TEST_BUFFS) end
    local auraScale = db.auraWidth / GAME_ICON_SIZE
    local fontSize = math.floor((db.auraTextSize or db.nameSize) / auraScale + 0.5)
    local debuffs, buffs = {}, {}
    if showDebuffs then
        StyleTestHolder(self.testAuras, TEST_AURAS, auraScale, fontSize)
        debuffs = self.testAuras.items
    elseif self.testAuras then
        self.testAuras:Hide()
    end
    if showBuffs then
        StyleTestHolder(self.testBuffs, TEST_BUFFS, auraScale, fontSize)
        buffs = self.testBuffs.items
    elseif self.testBuffs then
        self.testBuffs:Hide()
    end
    LayoutGroups(self, debuffs, buffs, auraScale)
end

-- Fill a plate with sample values: an enemy you are targeting, or a friend.
function Plate:ShowTest(friendly)
    local db = ns.db
    self.unit = nil
    self.nameOnly = (friendly and db.nameOnly) and true or false
    self.hasTitle = (self.nameOnly and db.showTitle) and true or false
    self.health:SetShown(not self.nameOnly)
    self.title:SetText("Flight Master")
    self.title:SetShown(self.hasTitle)
    self.name:SetText(friendly and ChooseNameParts("Joan", "Weber", db.nameParts or "full") or "Riverbottom Hunter")
    self:PlaceName()
    if self.nameOnly then
        self:SetNameColor(NAME_FRIENDLY[1], NAME_FRIENDLY[2], NAME_FRIENDLY[3])
    else
        self:SetNameColor(1, 1, 1)
    end
    -- The sample friend is a little hurt, to show health as name.
    self:SetHealthNameValue(70, 100)
    self:ShowHealthName(self.nameOnly)

    self:TestColor(friendly)
    self.health:SetMinMaxValues(0, 100)
    self.health:SetValue(friendly and 100 or 62)
    self.healthText:SetAlpha(1)
    self.healthText:SetText((db.healthText and not friendly) and "62%" or "")
    self.level:SetText(db.showLevel and "25" or "")
    self.level:SetTextColor(1, 0.82, 0)
    if friendly and db.friendLevel and self.nameOnly then
        self.friendLevel:SetText("60")
        self.friendLevel:SetTextColor(1, 0.82, 0)
        self:PlaceFriendLevel()
        self.friendLevel:Show()
    else
        self.friendLevel:Hide()
    end
    -- The sample enemy is your target, at the target size.
    self.isTarget = not friendly
    self:ApplyScale()
    if db.healthNumber and not friendly then
        SetNumberText(self.healthNumber, db.healthNumberStyle, 3432, 5500)
    else
        self.healthNumber:SetText("")
    end
    self:TestPower(not friendly)
    -- The sample enemy is an elite.
    SetGem(self.elite, (db.showElite and not friendly) and "elite" or nil)
    -- A skull on the sample enemy shows where raid marks go.
    if friendly then
        self.raidIcon:Hide()
    else
        SetRaidIcon(self.raidIcon, 8)
        self.raidIcon:Show()
    end
    self.glow:Set(friendly and GLOW_SHADOW or GLOW_TARGET)
    self:ShowArrows(not friendly)
    self:SetAlpha(1)

    if friendly then self.cast:Hide() else self:TestCast() end
    -- The sample enemy is attacking you, and you have three combo points on it.
    if db.targetName and not friendly then
        self:SetTargetName(YOU or "You", TOT_YOU)
    else
        self.targetName:Hide()
    end
    self:PlaceTargetName()
    if ns.ShowCombo then Try(ns.ShowCombo, self, (db.comboPoints and not friendly) and 3 or nil, 5) end
    self:TestAuras(not friendly)
    -- Sample DoT damage of 70 against 62 health, so the skull shows too.
    self.testDots = (not friendly) and 70 or nil
    Try(ns.UpdateDots, self)
    self:Show()
end

local testHost, testPlates, testTicker

function ns:UpdateTestMode()
    if not self.testMode or not testPlates then return end
    testPlates.enemy:ShowTest(false)
    testPlates.friend:ShowTest(true)
end

function ns:SetTestMode(on)
    on = on and true or false
    if on and not testHost then
        testHost = CreateFrame("Frame", "KuiNameplatesTestFrame", UIParent)
        testHost:SetSize(460, 150)
        testHost:SetPoint("CENTER", UIParent, "CENTER", 0, 190)
        testHost:SetFrameStrata("MEDIUM")
        testHost:SetClampedToScreen(true)
        testHost:SetMovable(true)
        testHost:EnableMouse(true)
        testHost:RegisterForDrag("LeftButton")
        testHost:SetScript("OnDragStart", testHost.StartMoving)
        testHost:SetScript("OnDragStop", testHost.StopMovingOrSizing)
        local back = testHost:CreateTexture(nil, "BACKGROUND")
        back:SetTexture(SOLID)
        back:SetVertexColor(0, 0, 0, 0.35)
        back:SetAllPoints(testHost)
        local label = testHost:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        label:SetPoint("BOTTOM", 0, 5)
        label:SetText("KuiNameplates test mode. Drag to move. Type /kui test to close.")

        local function MakePlate(x)
            local host = CreateFrame("Frame", nil, testHost)
            host:SetSize(170, 50)
            host:SetPoint("CENTER", testHost, "CENTER", x, 0)
            return ns:CreatePlate(host)
        end
        testPlates = { enemy = MakePlate(-100), friend = MakePlate(125) }
    end
    self.testMode = on
    if testHost then testHost:SetShown(on) end
    if testTicker then
        testTicker:Cancel()
        testTicker = nil
    end
    if on then
        self:UpdateTestMode()
        if C_Timer and C_Timer.NewTicker then
            testTicker = C_Timer.NewTicker(TEST_CAST_TIME + 0.7, function()
                local enemy = testPlates.enemy
                enemy.testAlternate = not enemy.testAlternate
                ns.Try(enemy.TestColor, enemy)
                ns.Try(enemy.TestCast, enemy)
            end)
        end
    end
end
