-- KuiNameplates: core setup, saved settings and global events.
local ADDON, ns = ...

ns.plates = {} -- nameplate unit token -> our plate frame

ns.defaults = {
    width = 132,          -- health bar width
    height = 11,          -- health bar height
    nameParts = "full",   -- player names: full, first or last
    nameSize = 11,        -- enemy name font size
    nameOffset = 0,       -- moves the enemy name up or down from the bar's top edge
    infoSize = 8,         -- level and health percent font size
    castTextSize = 9,     -- spell name font size
    friendNameSize = 11,  -- font size of friendly names shown without a bar
    titleSize = 10,       -- NPC title / guild line font size
    titleSpacing = 0,     -- gap between a friendly name and its title line
    titleR = 0.93, titleG = 0.80, titleB = 0.52, -- title line colour (warm sand)
    scale = 1,            -- overall plate size multiplier
    nameOnly = true,      -- friendly units show a coloured name and no bar
    showTitle = true,     -- NPC titles and guild names under friendly names
    healthName = true,    -- name-only plates grey out the name by missing health
    nameOnlyOffset = 0,   -- height of those names above the bottom of the plate
    nonTargetAlpha = 0.5, -- alpha of other plates while you have a target
    classColors = true,   -- colour enemy players by class
    healthText = true,    -- show health percent when damaged
    showLevel = false,
    tankMode = false,     -- colour bars by whether you hold threat
    tankOkR = 0.16, tankOkG = 0.36, tankOkB = 0.66,    -- tank mode: you hold threat
    tankBadR = 0.72, tankBadG = 0.32, tankBadB = 0.06, -- tank mode: slipping, or not on you
    casterColors = false, -- colour enemy NPCs that use mana
    casterR = 0.14, casterG = 0.36, casterB = 0.80,    -- that colour (blue)
    castBars = true,
    castHeight = 4,
    castStyle = "thin",   -- thin, tall or icon
    castR = 0.62, castG = 0.62, castB = 0.78,          -- casts you can interrupt (pale grey-lilac)
    castLockR = 0.62, castLockG = 0.44, castLockB = 0.30, -- casts you can't (dull orange)
    thinCast = true,      -- marks saved settings as already moved to the thin cast bar
    auras = true,         -- your debuffs on enemies
    auraWidth = 20,       -- debuff icon size
    auraSpot = "top",     -- where debuff icons sit: top, topleft, bottom, left, right
    auraOffset = 0,       -- extra distance of the debuff icons from the bar
    raidSpot = "top",     -- raid mark: top (above name and debuffs), left or right of the bar
    raidSize = 22,        -- raid mark size
    targetArrows = true,  -- arrows either side of your target's bar
    arrowScale = 1,       -- arrow size, as a multiple of the usual size
    arrowX = 0,           -- extra distance of the arrows from the bar
    arrowY = 0,           -- arrows moved up (+) or down (-)
    arrowR = 0.30, arrowG = 0.70, arrowB = 1.00, -- arrow colour (target blue)
    comboPoints = true,   -- combo point pips on your target's plate
    targetName = false,   -- each enemy's target named under its bar
    castTextOffset = 0,   -- spell name moved up (+) or down (-)
    auraTextSize = 11,    -- aura timer and stack text size
    font = nil,           -- set in Fonts.lua from the client language
    buffs = true,         -- purgeable and important buffs on enemies
    buffSpot = "top",     -- buff row: top (above the name) or bottom (below the bar)
    minimapButton = true, -- show the minimap button
    minimapAngle = 215,   -- its place around the minimap, in degrees
    auraColors = true,    -- colour debuff borders by type (poison, curse, ...)
    maxDistance = nil,    -- nameplateMaxDistance CVar; nil leaves the game's value
    dotPrediction = false, -- experimental: DoT damage still to come on the health bar
    hideOnFriends = true, -- hidden auras are hidden on friendly plates too
    -- hiddenAuras and seenAuras are lists, set up in Filters.lua
}

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if dst[k] == nil then dst[k] = v end
    end
    return dst
end

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff9fd5ffKuiNameplates|r: " .. tostring(msg))
end

local events = CreateFrame("Frame")
ns.events = events
events:SetScript("OnEvent", function(_, event, ...)
    local handler = ns[event]
    if handler then handler(ns, ...) end
end)

-- Coalesce frequent health updates into at most one per plate per frame.
-- With long nameplate ranges, dozens of plates can fire events every frame in big pulls.
local queued = {}
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self)
    self:Hide()
    for plate in pairs(queued) do
        queued[plate] = nil
        local pending = plate.pending
        if plate.unit then
            if pending.health then ns.Try(plate.UpdateHealth, plate) end
        end
        pending.health = nil
    end
end)

function ns:Queue(plate, kind)
    plate.pending[kind] = true
    queued[plate] = true
    driver:Show()
end

-- CVars can't be changed in combat, so queue the change until it ends.
function ns:ApplyCVars()
    local dist = self.db.maxDistance
    if not dist then return end
    if InCombatLockdown() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    SetCVar("nameplateMaxDistance", dist)
end

function ns:PLAYER_REGEN_ENABLED()
    events:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:ApplyCVars()
    self:ApplyAuraCVars()
end

-- Turn on one part of the game's enemy nameplate aura display.
local function EnableAuraBit(cvar, enum, field)
    pcall(function()
        local bit = Enum[enum][field]
        if not C_CVar.GetCVarBitfield(cvar, bit) then
            C_CVar.SetCVarBitfield(cvar, bit, true)
        end
    end)
end

-- The debuff and buff icons are drawn by the game's own nameplate code (see
-- Plate.lua), so the game's settings decide what it draws. Make sure it shows
-- debuffs and buffs on enemies, and all of your debuffs rather than a short
-- built-in list. Turning an option off here hides the icons on our plates
-- but leaves the game's settings alone.
function ns:ApplyAuraCVars()
    local db = self.db
    if not (db.auras or db.buffs) then return end
    if InCombatLockdown() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if db.auras then
        pcall(SetCVar, "nameplateShowAllPersonalAuras", "1")
        EnableAuraBit("nameplateEnemyNpcAuraDisplay", "NamePlateEnemyNpcAuraDisplay", "Debuffs")
        EnableAuraBit("nameplateEnemyPlayerAuraDisplay", "NamePlateEnemyPlayerAuraDisplay", "Debuffs")
    end
    if db.buffs then
        EnableAuraBit("nameplateEnemyNpcAuraDisplay", "NamePlateEnemyNpcAuraDisplay", "Buffs")
        EnableAuraBit("nameplateEnemyPlayerAuraDisplay", "NamePlateEnemyPlayerAuraDisplay", "Buffs")
    end
end

function ns:ADDON_LOADED(name)
    if name ~= ADDON then return end
    events:UnregisterEvent("ADDON_LOADED")
    local saved = KuiNameplatesForeverDB or {}
    -- One-time move to the thin cast bar introduced with the v0.3 look.
    if not saved.thinCast then saved.castHeight = nil end
    KuiNameplatesForeverDB = CopyDefaults(self.defaults, saved)
    self.db = KuiNameplatesForeverDB
    self:InitAuraFilters()

    events:RegisterEvent("PLAYER_LOGIN")
    events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("RAID_TARGET_UPDATE")
    -- Plates are sized in screen pixels, so re-fit them when the display changes.
    pcall(events.RegisterEvent, events, "DISPLAY_SIZE_CHANGED")
    pcall(events.RegisterEvent, events, "UI_SCALE_CHANGED")
end

function ns:DISPLAY_SIZE_CHANGED()
    self:RefreshAll()
end
ns.UI_SCALE_CHANGED = ns.DISPLAY_SIZE_CHANGED

function ns:PLAYER_LOGIN()
    self:ApplyCVars()
    self:ApplyAuraCVars()
    if self.ApplyDotPrediction then self:ApplyDotPrediction() end
    if self.CreateOptions then self:CreateOptions() end
    if self.UpdateMinimapButton then self:UpdateMinimapButton() end
end

function ns:NAME_PLATE_UNIT_ADDED(unit)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    -- Friendly plates inside instances are forbidden to addons; leave them alone.
    if not nameplate or (nameplate.IsForbidden and nameplate:IsForbidden()) then return end
    local plate = nameplate.KuiForeverPlate or self:CreatePlate(nameplate)
    self.plates[unit] = plate
    plate:OnUnitAdded(unit)
    if self.UpdateCombo then self.Try(self.UpdateCombo, self) end
end

function ns:NAME_PLATE_UNIT_REMOVED(unit)
    local plate = self.plates[unit]
    if not plate then return end
    self.plates[unit] = nil
    plate:OnUnitRemoved()
end

function ns:PLAYER_TARGET_CHANGED()
    for _, plate in pairs(self.plates) do
        plate:UpdateTarget()
    end
    if self.UpdateCombo then self.Try(self.UpdateCombo, self) end
end

function ns:RAID_TARGET_UPDATE()
    for _, plate in pairs(self.plates) do
        plate:UpdateRaidIcon()
    end
end

-- Re-apply sizes and fonts to every plate after a setting changes.
function ns:RefreshAll()
    for plate in pairs(self.allPlates or {}) do
        plate:ApplyLayout()
    end
    for _, plate in pairs(self.plates) do
        plate:UpdateAll()
    end
    self:ApplyAuraCVars()
    if self.ApplyDotPrediction then self:ApplyDotPrediction() end
    if self.UpdateCombo then self.Try(self.UpdateCombo, self) end
    if self.UpdateMinimapButton then self:UpdateMinimapButton() end
    if self.UpdateTestMode then self:UpdateTestMode() end
end

events:RegisterEvent("ADDON_LOADED")
