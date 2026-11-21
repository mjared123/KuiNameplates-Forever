-- KuiNameplates: experimental DoT damage prediction.
--
-- Shows how much damage your damage-over-time spells will still do, as a
-- green section at the end of the health bar, and a skull beside the bar
-- when that is enough to kill.
--
-- WoW: Forever hides enemy health from addons and blocks reading auras and
-- the combat log in combat, so this works without any of them:
--   * Your own DoT casts are noted when you cast them, with the damage and
--     duration read from the spell's description (English client only).
--   * The damage left is an estimate. Misses, resists, immunities, haste and
--     crits are not known to the addon.
--   * The addon never compares or does maths on the hidden health. It hands
--     its own plain number to status bars, and the game draws the result.
local _, ns = ...

local SOLID = "Interface\\Buttons\\WHITE8X8"
local RAID_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local OVERLAY_COLOR = { 0.35, 1.00, 0.30, 0.70 } -- bright green over the dark bar
local SKULL_SIZE = 12
local SENSE_WIDTH = 4000 -- width of the hidden bar behind the skull, see below
local UPDATE_EVERY = 0.1

-- DoTs counted, by their English spell name. Any rank works, since the
-- numbers come from the spell description of the rank you cast.
local DOTS = {
    ["Rake"] = true, ["Rip"] = true, ["Pounce"] = true, ["Moonfire"] = true,
    ["Insect Swarm"] = true, ["Rupture"] = true, ["Garrote"] = true,
    ["Rend"] = true, ["Corruption"] = true, ["Curse of Agony"] = true,
    ["Immolate"] = true, ["Siphon Life"] = true, ["Shadow Word: Pain"] = true,
    ["Devouring Plague"] = true, ["Holy Fire"] = true, ["Serpent Sting"] = true,
}
ns.DOT_SPELLS = DOTS

-- Hunter traps. The trap is placed on the ground, not cast on a target, and
-- burns whichever enemy walks into it, so the damage can't be put on your
-- target when you cast. Instead the trap waits until an enemy nameplate gets
-- the trap's effect debuff (named here), and the damage goes on that plate.
local TRAPS = {
    ["Immolation Trap"] = { effect = "Immolation Trap Effect" },
    ["Explosive Trap"] = { effect = "Explosive Trap Effect", aoe = true },
}
local TRAP_LIFETIME = 60 -- an armed trap lasts a minute unless the tooltip says otherwise
local AOE_WINDOW = 1     -- an area trap counts every enemy it catches in this long

local issecret = issecretvalue or function() return false end
local canaccess = canaccessvalue or function() return true end
local function Plain(value)
    if value ~= nil and (issecret(value) or not canaccess(value)) then return nil end
    return value
end

local function Number(text)
    return tonumber((text:gsub(",", "")))
end

-- Read "X damage over Y sec" from a description. Finishing moves list one
-- line per combo point ("3 points: 120 damage over 14 sec"); the line for
-- the points spent is used. When the game hides how many points were spent,
-- the top line is used, since finishers are mostly used at full points.
local function ParseDescription(desc, points)
    if type(desc) ~= "string" or desc == "" then return nil end
    local best, bestDmg, bestDur
    for cp, dmg, dur in desc:gmatch("(%d) points?%s*:%s*([%d,]+)[^%d]-damage over ([%d%.]+) sec") do
        cp = tonumber(cp)
        if points and cp == points then return Number(dmg), tonumber(dur) end
        if not best or cp > best then best, bestDmg, bestDur = cp, dmg, dur end
    end
    if best then return Number(bestDmg), tonumber(bestDur) end
    local dmg, dur = desc:match("([%d,]+)[%a%s]-damage over ([%d%.]+) sec")
    if dmg then return Number(dmg), tonumber(dur) end
    -- Some text ranges the amount: "12 to 16 damage over 9 sec".
    local low, high
    low, high, dur = desc:match("([%d,]+) to ([%d,]+)[%a%s]-damage over ([%d%.]+) sec")
    if low then return (Number(low) + Number(high)) / 2, tonumber(dur) end
end
ns.ParseDotDescription = ParseDescription

local function SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok then return Plain(name) end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok then return Plain(name) end
    end
end

-- Spell text can come back empty until the game has loaded that spell's
-- data, often on the first cast after logging in. Ask for it to load, and
-- keep every description once seen.
local descriptions = {}
local function SpellDescription(spellID)
    if descriptions[spellID] then return descriptions[spellID] end
    local get = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
    if not get then return nil end
    local ok, desc = pcall(get, spellID)
    desc = ok and Plain(desc) or nil
    if type(desc) == "string" and desc ~= "" then
        descriptions[spellID] = desc
        return desc
    end
    if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, spellID) end
end

local function ComboPoints()
    local ok, points
    if GetComboPoints then
        ok, points = pcall(GetComboPoints, "player", "target")
    end
    if not (ok and Plain(points)) and UnitPower and Enum and Enum.PowerType then
        ok, points = pcall(UnitPower, "player", Enum.PowerType.ComboPoints)
    end
    return ok and Plain(points) or nil
end

-- Drawing ----------------------------------------------------------------------
--
-- Damage section: a reverse-fill bar the size of the health bar, whose right
-- edge is pinned to the end of the health fill. Its range is the unit's
-- (hidden) max health and its value is the damage left, so the game sizes it.
-- A clip frame keeps anything past the bar's left edge out of sight.
--
-- Skull: a hidden, very wide bar whose range is 0 to the damage left and
-- whose value is the unit's (hidden) health. The game clamps the value, so
-- the bar is full unless health is below the damage left. A mask from the
-- end of its fill to its right edge reveals the skull, which sits in that
-- right edge, only when the bar is short of full: when the DoTs are lethal.

local function Build(plate)
    local health = plate.health
    local clip = CreateFrame("Frame", nil, health)
    clip:SetAllPoints(health)
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(health:GetFrameLevel() + 1)

    local bar = CreateFrame("StatusBar", nil, clip)
    bar:SetStatusBarTexture(SOLID)
    bar:SetStatusBarColor(OVERLAY_COLOR[1], OVERLAY_COLOR[2], OVERLAY_COLOR[3], OVERLAY_COLOR[4])
    bar:SetReverseFill(true)
    local fill = health:GetStatusBarTexture()
    bar:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
    bar:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
    -- A bright line where your DoTs will leave the health.
    bar.edge = bar:CreateTexture(nil, "OVERLAY")
    bar.edge:SetTexture(SOLID)
    bar.edge:SetVertexColor(0.75, 1, 0.65, 1)
    bar.edge:SetWidth(1)
    bar.edge:SetPoint("TOPRIGHT", bar:GetStatusBarTexture(), "TOPLEFT")
    bar.edge:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMLEFT")

    local skullBox = CreateFrame("Frame", nil, plate)
    skullBox:SetSize(SKULL_SIZE, SKULL_SIZE)
    skullBox:SetPoint("LEFT", health, "RIGHT", 4, 0)
    skullBox:SetFrameLevel(plate.text:GetFrameLevel())

    -- The hidden bar ends a little to the right of the skull, and the mask
    -- reaches a little further still, so the mask never has zero width and
    -- sits clear of the skull until the bar is short of full.
    local sense = CreateFrame("StatusBar", nil, skullBox)
    sense:SetStatusBarTexture(SOLID)
    sense:SetStatusBarColor(0, 0, 0, 0)
    sense:SetSize(SENSE_WIDTH, SKULL_SIZE)
    sense:SetPoint("RIGHT", skullBox, "RIGHT", 20, 0)
    sense:SetAlpha(0)
    local senseFill = sense:GetStatusBarTexture()

    local skull = skullBox:CreateTexture(nil, "OVERLAY")
    skull:SetTexture(RAID_ICONS)
    skull:SetTexCoord(0.75, 1, 0.25, 0.5)
    -- Tinted red so it can't be mistaken for a raid skull mark.
    skull:SetVertexColor(1, 0.3, 0.25, 1)
    skull:SetAllPoints(skullBox)
    local masked = pcall(function()
        local mask = skullBox:CreateMaskTexture()
        mask:SetTexture(SOLID, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetPoint("TOPLEFT", senseFill, "TOPRIGHT")
        mask:SetPoint("BOTTOMRIGHT", sense, "BOTTOMRIGHT", 10, 0)
        skull:AddMaskTexture(mask)
    end)
    if not masked then
        -- No masks: show a red square in the same place instead, cut to the
        -- skull's box by a clipping frame.
        skull:Hide()
        local box = CreateFrame("Frame", nil, skullBox)
        box:SetAllPoints(skullBox)
        box:SetClipsChildren(true)
        local holder = CreateFrame("Frame", nil, box)
        holder:SetAllPoints(box)
        local square = holder:CreateTexture(nil, "OVERLAY")
        square:SetTexture(SOLID)
        square:SetVertexColor(1, 0.15, 0.1, 1)
        square:SetPoint("TOPLEFT", senseFill, "TOPRIGHT")
        square:SetPoint("BOTTOMRIGHT", sense, "BOTTOMRIGHT", 10, 0)
    end

    plate.dotBar, plate.dotSense, plate.dotSkull = bar, sense, skullBox
end

local function HideDots(plate)
    if plate.dotBar then
        plate.dotBar:Hide()
        plate.dotSkull:Hide()
    end
end

-- Draw `damage` (a plain number) against the plate's health. `cur` and
-- `max` may be hidden values; they only go to status bars.
local function DrawDots(plate, damage, cur, max)
    if not damage or damage <= 0 then HideDots(plate) return end
    if not plate.dotBar then Build(plate) end
    local bar, sense = plate.dotBar, plate.dotSense
    bar:SetWidth(ns.db.width)
    bar:SetMinMaxValues(0, max)
    bar:SetValue(damage)
    bar:Show()
    sense:SetMinMaxValues(0, damage)
    sense:SetValue(cur)
    plate.dotSkull:Show()
end

-- Tracking -------------------------------------------------------------------

local tracked = {} -- plate -> true while it has DoTs on it
-- DoTs by unit GUID, when the game shows it, so they come back if the
-- unit's plate leaves the screen for a moment (out of sight, camera turned).
local byGuid = {}

local function Guid(unit)
    local ok, guid = pcall(UnitGUID, unit)
    return ok and Plain(guid) or nil
end

local function DamageLeft(plate, now)
    local total, dots = 0, plate.dots
    if not dots and plate.unit then
        local guid = Guid(plate.unit)
        dots = guid and byGuid[guid]
        plate.dots, plate.dotGuid = dots, dots and guid
    end
    if not dots then return 0 end
    for name, dot in pairs(dots) do
        local left = dot.ends - now
        if left <= 0 then
            dots[name] = nil
        else
            total = total + dot.damage * left / dot.duration
        end
    end
    if next(dots) == nil then
        if plate.dotGuid then byGuid[plate.dotGuid] = nil end
        plate.dots, plate.dotGuid = nil, nil
    end
    return total
end

function ns.UpdateDots(plate)
    if not ns.db.dotPrediction then HideDots(plate) return end
    if plate.testDots then
        DrawDots(plate, plate.testDots, 62, 100)
        return
    end
    local unit = plate.unit
    local damage = unit and DamageLeft(plate, GetTime()) or 0
    if damage <= 0 then
        tracked[plate] = nil
        HideDots(plate)
        return
    end
    DrawDots(plate, damage, UnitHealth(unit), UnitHealthMax(unit))
    -- Keep counting down, also for DoTs brought back by GUID.
    if not tracked[plate] then
        tracked[plate] = true
        if ns.dotTicker then ns.dotTicker:Show() end
    end
end

-- The plate is going away or being reused: let go of its DoTs. Those saved
-- by GUID stay until they run out.
function ns.ClearDots(plate)
    plate.dots, plate.dotGuid = nil, nil
    tracked[plate] = nil
    HideDots(plate)
end

local ticker = CreateFrame("Frame")
ticker:Hide()
ns.dotTicker = ticker
local elapsed = 0
ticker:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed < UPDATE_EVERY then return end
    elapsed = 0
    if next(tracked) == nil then self:Hide() return end
    for plate in pairs(tracked) do ns.Try(ns.UpdateDots, plate) end
end)

local lastPoints -- combo points just before the latest cast

-- Put `damage` over `duration` on a plate under `key`, replacing an earlier
-- one with the same key (recasting a DoT restarts it).
local function AddDot(plate, key, damage, duration, castAt)
    if not plate.dots then
        local guid = Guid(plate.unit)
        plate.dots = guid and byGuid[guid] or {}
        if guid then
            byGuid[guid] = plate.dots
            plate.dotGuid = guid
        end
    end
    plate.dots[key] = { damage = damage, duration = duration, ends = (castAt or GetTime()) + duration }
    tracked[plate] = true
    ticker:Show()
    ns.Try(ns.UpdateDots, plate)
end

-- Traps -------------------------------------------------------------------------

local pending = {} -- effect name -> { damage, duration, expires, aoe }
local trapWatcher = CreateFrame("Frame")
local warned

-- True or false when the game says whether `unit` has your debuff `name`, nil
-- when it won't say. The answer may be hidden, but checking it against nil is
-- allowed.
local function HasMyDebuff(unit, name)
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    if not get then return nil end
    local ok, aura = pcall(get, unit, name, "HARMFUL|PLAYER")
    if not ok then return nil end
    return aura ~= nil
end

local function StopTrapWatch()
    if next(pending) == nil then trapWatcher:UnregisterEvent("UNIT_AURA") end
end

trapWatcher:SetScript("OnEvent", function(_, _, unit)
    local plate = unit and ns.plates[unit]
    if not (plate and plate.unit) then return end
    local now = GetTime()
    for effect, trap in pairs(pending) do
        if now > trap.expires then
            pending[effect] = nil
        else
            local has = HasMyDebuff(unit, effect)
            if has == nil and not warned then
                warned = true
                ns.Print("DoT prediction: the game won't say which enemy your trap caught, so trap damage can't be shown.")
            end
            if has and not (plate.dots and plate.dots[effect] and plate.dots[effect].trapAt == trap.placed) then
                AddDot(plate, effect, trap.damage, trap.duration)
                plate.dots[effect].trapAt = trap.placed
                if trap.aoe then
                    trap.expires = math.min(trap.expires, now + AOE_WINDOW)
                else
                    pending[effect] = nil
                end
            end
        end
    end
    StopTrapWatch()
end)

local function ArmTrap(trap, spellID)
    local desc = SpellDescription(spellID)
    local damage, duration = ParseDescription(desc)
    if not (damage and duration and damage > 0 and duration > 0) then return end
    local minutes = type(desc) == "string" and tonumber(desc:match("exist for ([%d%.]+) min"))
    local now = GetTime()
    pending[trap.effect] = {
        damage = damage, duration = duration, aoe = trap.aoe, placed = now,
        expires = now + (minutes and minutes * 60 or TRAP_LIFETIME),
    }
    trapWatcher:RegisterEvent("UNIT_AURA")
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(_, event, _, _, spellID)
    if event == "UNIT_SPELLCAST_SENT" then
        lastPoints = ComboPoints()
        return
    end
    -- UNIT_SPELLCAST_SUCCEEDED: unit, castGUID, spellID
    spellID = Plain(spellID)
    if not spellID then return end
    local name = SpellName(spellID)
    if name and TRAPS[name] then
        ArmTrap(TRAPS[name], spellID)
        return
    end
    if not (name and DOTS[name]) then return end
    local points = lastPoints
    lastPoints = nil
    local nameplate = UnitExists("target") and C_NamePlate.GetNamePlateForUnit("target")
    local plate = nameplate and nameplate.KuiForeverPlate
    if not (plate and plate.unit) then return end
    local unit, castAt, tries = plate.unit, GetTime(), 0
    local function Apply()
        if plate.unit ~= unit then return end -- the plate moved on to another unit
        local damage, duration = ParseDescription(SpellDescription(spellID), points)
        if damage and duration and damage > 0 and duration > 0 then
            AddDot(plate, name, damage, duration, castAt)
        elseif tries < 3 and C_Timer and C_Timer.After then
            -- The spell text may still be loading; try again shortly.
            tries = tries + 1
            C_Timer.After(0.3, Apply)
        end
    end
    Apply()
end)

-- Listen for your own casts only while the option is on.
function ns:ApplyDotPrediction()
    if self.db.dotPrediction then
        pcall(watcher.RegisterUnitEvent, watcher, "UNIT_SPELLCAST_SENT", "player")
        pcall(watcher.RegisterUnitEvent, watcher, "UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        watcher:UnregisterAllEvents()
        wipe(pending)
        trapWatcher:UnregisterAllEvents()
        for plate in pairs(tracked) do ns.ClearDots(plate) end
    end
end
