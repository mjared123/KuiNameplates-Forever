-- ForeverPlates: core setup, saved settings and global events.
local ADDON, ns = ...

ns.plates = {} -- nameplate unit token -> our plate frame

ns.defaults = {
    width = 130,          -- health bar width
    height = 10,          -- health bar height
    nameSize = 10,        -- name font size
    nonTargetAlpha = 0.6, -- alpha of other plates while you have a target
    classColors = true,   -- colour enemy players by class
    healthText = true,    -- show health percent when damaged
    showLevel = true,
    tankMode = false,     -- colour bars by whether you hold threat
    maxDistance = nil,    -- nameplateMaxDistance CVar; nil leaves the game's value
}

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if dst[k] == nil then dst[k] = v end
    end
    return dst
end

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff9fd5ffForeverPlates|r: " .. tostring(msg))
end

local events = CreateFrame("Frame")
ns.events = events
events:SetScript("OnEvent", function(_, event, ...)
    local handler = ns[event]
    if handler then handler(ns, ...) end
end)

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
    ForeverPlatesDB = CopyDefaults(self.defaults, ForeverPlatesDB or {})
    self.db = ForeverPlatesDB

    events:RegisterEvent("PLAYER_LOGIN")
    events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("RAID_TARGET_UPDATE")
end

function ns:PLAYER_LOGIN()
    self:ApplyCVars()
end

function ns:NAME_PLATE_UNIT_ADDED(unit)
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    -- Friendly plates inside instances are forbidden to addons; leave them alone.
    if not nameplate or (nameplate.IsForbidden and nameplate:IsForbidden()) then return end
    local plate = nameplate.ForeverPlate or self:CreatePlate(nameplate)
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
    for nameplate in pairs(self.allPlates or {}) do
        nameplate:ApplyLayout()
    end
    for _, plate in pairs(self.plates) do
        plate:UpdateAll()
    end
end

events:RegisterEvent("ADDON_LOADED")
