-- KuiNameplates: core setup, saved settings and global events.
local ADDON, ns = ...

ns.plates = {} -- nameplate unit token -> our plate frame

ns.defaults = {
    width = 132,          -- health bar width
    height = 11,          -- health bar height
    nameSize = 11,        -- name font size
    scale = 1,            -- overall plate size multiplier
    nameOnly = true,      -- friendly units show a coloured name and no bar
    nonTargetAlpha = 0.5, -- alpha of other plates while you have a target
    classColors = true,   -- colour enemy players by class
    healthText = true,    -- show health percent when damaged
    showLevel = false,
    tankMode = false,     -- colour bars by whether you hold threat
    castBars = true,
    castHeight = 5,
    auras = true,         -- your debuffs on enemies
    maxAuras = 6,
    auraWidth = 22,
    maxDistance = nil,    -- nameplateMaxDistance CVar; nil leaves the game's value
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

-- Coalesce frequent updates (health, auras) into at most one per plate per frame.
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
            if pending.auras then ns.Try(plate.UpdateAuras, plate) end
        end
        pending.health, pending.auras = nil, nil
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
end

function ns:ADDON_LOADED(name)
    if name ~= ADDON then return end
    events:UnregisterEvent("ADDON_LOADED")
    KuiNameplatesForeverDB = CopyDefaults(self.defaults, KuiNameplatesForeverDB or {})
    self.db = KuiNameplatesForeverDB

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
    if self.CreateOptions then self:CreateOptions() end
end

function ns:NAME_PLATE_UNIT_ADDED(unit)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    -- Friendly plates inside instances are forbidden to addons; leave them alone.
    if not nameplate or (nameplate.IsForbidden and nameplate:IsForbidden()) then return end
    local plate = nameplate.KuiForeverPlate or self:CreatePlate(nameplate)
    self.plates[unit] = plate
    plate:OnUnitAdded(unit)
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
end

events:RegisterEvent("ADDON_LOADED")
