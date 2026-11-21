-- KuiNameplates: experimental DoT damage prediction.
--
-- Shows how much damage your damage-over-time spells will still do, as a
-- green section at the end of the health bar, and a skull beside the bar
-- when that is enough to kill.
--
-- WoW: Forever hides enemy health from addons and blocks the combat log and
-- most aura reading in combat, so this works like this:
--   * Your own DoT casts are noted when you cast them, with the damage and
--     duration read from the spell's description (English client only).
--   * A DoT only counts once the game confirms your debuff is on the enemy
--     (see Tracking below), so immunities and misses drop out.
--   * The damage left is an estimate: crits, haste and partial resists are
--     not known to the addon.
--   * The addon never compares or does maths on the hidden health. It hands
--     its own plain number to status bars, and the game draws the result.
--   * `/kui dotprobe` prints what the game lets the addon see.
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

    -- The estimated damage left, as a number on the bar's bottom-left edge.
    local text = plate.text:CreateFontString(nil, "OVERLAY")
    if ns.SetFont then ns.SetFont(text, ns.db.infoSize or 8, "OUTLINE") end
    text:SetTextColor(0.55, 1, 0.5)
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    plate.dotText = text

    plate.dotBar, plate.dotSense, plate.dotSkull = bar, sense, skullBox
end

local function HideDots(plate)
    if plate.dotBar then
        plate.dotBar:Hide()
        plate.dotSkull:Hide()
        plate.dotText:Hide()
    end
end

-- Draw `damage` (a plain number) against the plate's health. `cur` and
-- `max` may be hidden values; they only go to status bars.
local function DrawDots(plate, damage, cur, max, guess)
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
    local text = plate.dotText
    text:ClearAllPoints()
    if ns.db.showLevel then
        text:SetPoint("LEFT", plate.level, "RIGHT", 3, 0)
    else
        text:SetPoint("LEFT", plate.health, "BOTTOMLEFT", 2, 1)
    end
    -- A "?" marks a total that includes DoTs the game would not confirm.
    text:SetFormattedText(guess and "%d?" or "%d", math.floor(damage + 0.5))
    text:Show()
end

-- Tracking -------------------------------------------------------------------
--
-- A cast only says you tried. The DoT counts once the game confirms your
-- debuff is really on that enemy, so immunities, misses, resists and dodges
-- drop out, and so do DoTs that are dispelled or broken early.
--
-- Each DoT on a plate is in one of three states:
--   "pending"   cast, waiting for the debuff to appear (allows for travel
--               time); not drawn.
--   "confirmed" the game says the debuff is there; drawn.
--   "assumed"   the game won't say either way; drawn, as the best guess.
--
-- The check is C_UnitAuras.GetAuraDataBySpellName with your own debuffs
-- only. Its answer may be hidden, but checking it against nil is allowed.
-- Out of combat a "no" is always believed. In combat a "no" for a debuff is
-- believed once the game has answered "yes" for that debuff in combat this
-- session; until then the addon can't tell "not there" from "not telling",
-- and keeps its guess.

local CONFIRM_GRACE = 1.5 -- seconds a cast may take to land its debuff
local RECHECK_EVERY = 0.5

-- Debuff names that differ from the spell you cast.
local AURA_NAMES = { ["Pounce"] = "Pounce Bleed" }

local tracked = {} -- plate -> true while it has DoTs on it
-- DoTs by unit GUID, when the game shows it, so they come back if the
-- unit's plate leaves the screen for a moment (out of sight, camera turned).
local byGuid = {}
local seesInCombat = {} -- debuff name -> the game has answered "yes" for it in combat

local function Guid(unit)
    local ok, guid = pcall(UnitGUID, unit)
    return ok and Plain(guid) or nil
end

local function Restricted()
    if InCombatLockdown and InCombatLockdown() then return true end
    return Plain(UnitAffectingCombat("player")) == true
end

-- true, false, or nil when the game won't answer. Also returns the time the
-- debuff ends, when the game shows it.
local function AuraState(unit, auraName)
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    if not (get and unit) then return nil end
    local ok, aura = pcall(get, unit, auraName, "HARMFUL|PLAYER")
    if not ok then return nil end
    if aura == nil then return false end
    if Restricted() then seesInCombat[auraName] = true end
    local okEnd, ends = pcall(function() return Plain(aura.expirationTime) end)
    ends = okEnd and type(ends) == "number" and ends > 0 and ends or nil
    return true, ends
end
ns.DotAuraState = AuraState

-- Whether a "no" from AuraState for this debuff can be believed right now.
local function TrustNo(auraName)
    return seesInCombat[auraName] or not Restricted()
end

-- Bring each DoT on a plate up to date with what the game shows.
local function Verify(plate, now)
    local dots, unit = plate.dots, plate.unit
    if not (dots and unit) then return end
    for key, dot in pairs(dots) do
        local has, ends = AuraState(unit, dot.aura)
        if has then
            dot.state = "confirmed"
            if ends then
                dot.ends = ends
                dot.duration = math.max(dot.duration, ends - now)
            end
        elseif has == false and TrustNo(dot.aura) then
            -- Not there: immune, missed, resisted, dispelled or worn off.
            if dot.state ~= "pending" or now - dot.castAt > CONFIRM_GRACE then
                dots[key] = nil
            end
        elseif dot.state == "pending" and now - dot.castAt > CONFIRM_GRACE then
            dot.state = "assumed"
        end
    end
end

local function DamageLeft(plate, now)
    local total, guess, dots = 0, false, plate.dots
    if not dots and plate.unit then
        local guid = Guid(plate.unit)
        dots = guid and byGuid[guid]
        plate.dots, plate.dotGuid = dots, dots and guid
    end
    if not dots then return 0, false end
    for key, dot in pairs(dots) do
        local left = dot.ends - now
        if left <= 0 then
            dots[key] = nil
        elseif dot.state ~= "pending" then
            total = total + dot.damage * math.min(left, dot.duration) / dot.duration
            if dot.state == "assumed" then guess = true end
        end
    end
    if next(dots) == nil then
        if plate.dotGuid then byGuid[plate.dotGuid] = nil end
        plate.dots, plate.dotGuid = nil, nil
    end
    return total, guess
end

function ns.UpdateDots(plate)
    if not ns.db.dotPrediction then HideDots(plate) return end
    if plate.testDots then
        DrawDots(plate, plate.testDots, 62, 100)
        return
    end
    local unit = plate.unit
    local damage, guess = 0, false
    if unit then damage, guess = DamageLeft(plate, GetTime()) end
    if plate.dots and not tracked[plate] then
        -- Keep counting down, also for DoTs brought back by GUID.
        tracked[plate] = true
        if ns.dotTicker then ns.dotTicker:Show() end
    elseif not plate.dots then
        tracked[plate] = nil
    end
    if damage <= 0 then
        HideDots(plate)
        return
    end
    DrawDots(plate, damage, UnitHealth(unit), UnitHealthMax(unit), guess)
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
local elapsed, sinceCheck = 0, 0
ticker:SetScript("OnUpdate", function(self, dt)
    elapsed, sinceCheck = elapsed + dt, sinceCheck + dt
    if elapsed < UPDATE_EVERY then return end
    elapsed = 0
    if next(tracked) == nil then self:Hide() return end
    local check = sinceCheck >= RECHECK_EVERY
    if check then sinceCheck = 0 end
    local now = GetTime()
    for plate in pairs(tracked) do
        if check then ns.Try(Verify, plate, now) end
        ns.Try(ns.UpdateDots, plate)
    end
end)

-- Put a DoT on a plate under `key`, replacing an earlier one with the same
-- key (recasting a DoT restarts it).
local function AddDot(plate, key, info)
    if not plate.dots then
        local guid = Guid(plate.unit)
        plate.dots = guid and byGuid[guid] or {}
        if guid then
            byGuid[guid] = plate.dots
            plate.dotGuid = guid
        end
    end
    local castAt = info.castAt or GetTime()
    plate.dots[key] = {
        damage = info.damage, duration = info.duration, castAt = castAt,
        ends = castAt + info.duration, aura = info.aura or key,
        state = info.state or "pending",
    }
    tracked[plate] = true
    ticker:Show()
    ns.Try(Verify, plate, GetTime())
    ns.Try(ns.UpdateDots, plate)
end

-- Last few casts and what became of them, for /kui dotprobe.
local castLog = {}
local function Log(text)
    table.insert(castLog, 1, string.format("%.1f %s", GetTime(), text))
    castLog[6] = nil
end

-- Traps -------------------------------------------------------------------------

local pending = {} -- effect name -> { damage, duration, expires, aoe, placed }

local function ArmTrap(trap, spellID, name)
    local desc = SpellDescription(spellID)
    local damage, duration = ParseDescription(desc)
    if not (damage and duration and damage > 0 and duration > 0) then
        Log(name .. ": no damage found in the tooltip")
        return
    end
    local minutes = type(desc) == "string" and tonumber(desc:match("exist for ([%d%.]+) min"))
    local now = GetTime()
    pending[trap.effect] = {
        damage = damage, duration = duration, aoe = trap.aoe, placed = now,
        expires = now + (minutes and minutes * 60 or TRAP_LIFETIME),
    }
    Log(string.format("%s placed: %d over %ds, waiting for an enemy", name, math.floor(damage), math.floor(duration)))
end

local function CheckTraps(plate)
    local unit, now = plate.unit, GetTime()
    for effect, trap in pairs(pending) do
        if now > trap.expires then
            pending[effect] = nil
        else
            local dot = plate.dots and plate.dots[effect]
            if not (dot and dot.placed == trap.placed) and AuraState(unit, effect) then
                AddDot(plate, effect, { damage = trap.damage, duration = trap.duration, state = "confirmed" })
                plate.dots[effect].placed = trap.placed
                Log(effect .. " caught an enemy")
                if trap.aoe then
                    trap.expires = math.min(trap.expires, now + AOE_WINDOW)
                else
                    pending[effect] = nil
                end
            end
        end
    end
end

-- Events ------------------------------------------------------------------------

local lastPoints -- combo points just before the latest cast

local function OnCast(spellID)
    local name = SpellName(spellID)
    if name and TRAPS[name] then
        ArmTrap(TRAPS[name], spellID, name)
        return
    end
    if not (name and DOTS[name]) then return end
    local points = lastPoints
    lastPoints = nil
    local nameplate = UnitExists("target") and C_NamePlate.GetNamePlateForUnit("target")
    local plate = nameplate and nameplate.KuiForeverPlate
    if not (plate and plate.unit) then
        Log(name .. ": your target has no plate on screen")
        return
    end
    local unit, castAt, tries = plate.unit, GetTime(), 0
    local function Apply()
        if plate.unit ~= unit then return end -- the plate moved on to another unit
        local damage, duration = ParseDescription(SpellDescription(spellID), points)
        if damage and duration and damage > 0 and duration > 0 then
            AddDot(plate, name, { damage = damage, duration = duration, castAt = castAt, aura = AURA_NAMES[name] })
            local note = ""
            if not points and (name == "Rip" or name == "Rupture") then note = " (combo points hidden)" end
            Log(string.format("%s: %d over %ds%s", name, math.floor(damage), math.floor(duration), note))
        elseif tries < 3 and C_Timer and C_Timer.After then
            -- The spell text may still be loading; try again shortly.
            tries = tries + 1
            C_Timer.After(0.3, Apply)
        else
            Log(name .. ": no damage found in the tooltip")
        end
    end
    Apply()
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(_, event, unit, _, a)
    if event == "UNIT_AURA" then
        local plate = ns.plates[unit]
        if not (plate and plate.unit) then return end
        if next(pending) then ns.Try(CheckTraps, plate) end
        if plate.dots then
            ns.Try(Verify, plate, GetTime())
            ns.Try(ns.UpdateDots, plate)
        end
    elseif event == "UNIT_SPELLCAST_SENT" then
        lastPoints = ComboPoints()
    else -- UNIT_SPELLCAST_SUCCEEDED: unit, castGUID, spellID
        local spellID = Plain(a)
        if not spellID then
            if a ~= nil then Log("a cast's spell was hidden by the game") end
            return
        end
        ns.Try(OnCast, spellID)
    end
end)

-- Listen only while the option is on.
function ns:ApplyDotPrediction()
    if self.db.dotPrediction then
        pcall(watcher.RegisterUnitEvent, watcher, "UNIT_SPELLCAST_SENT", "player")
        pcall(watcher.RegisterUnitEvent, watcher, "UNIT_SPELLCAST_SUCCEEDED", "player")
        watcher:RegisterEvent("UNIT_AURA")
    else
        watcher:UnregisterAllEvents()
        wipe(pending)
        for plate in pairs(tracked) do ns.ClearDots(plate) end
    end
end

-- /kui dotprobe: print what the game lets the addon see about your target,
-- to find out what works on WoW: Forever in and out of combat.
local function Describe(value)
    if value == nil then return "nil" end
    if issecret(value) or not canaccess(value) then return "hidden" end
    return tostring(value)
end

function ns:DotProbe()
    local out = {}
    local function Add(text) out[#out + 1] = text end
    local answered = {}
    for name in pairs(seesInCombat) do answered[#answered + 1] = name end
    Add("in combat: " .. tostring(Restricted()) .. ", answered in combat for: "
        .. (#answered > 0 and table.concat(answered, ", ") or "nothing yet"))
    if not UnitExists("target") then
        Add("no target")
    else
        local okCp, cp = pcall(GetComboPoints, "player", "target")
        Add("target health: " .. Describe(UnitHealth("target")) .. ", GUID: " .. Describe(UnitGUID("target"))
            .. ", combo points: " .. (okCp and Describe(cp) or "refused"))
        local names, seen = {}, {}
        for name in pairs(DOTS) do names[#names + 1] = AURA_NAMES[name] or name end
        for _, trap in pairs(TRAPS) do names[#names + 1] = trap.effect end
        table.sort(names)
        local found, errors, asked = {}, 0, 0
        local get = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
        for _, name in ipairs(names) do
            if not seen[name] then
                seen[name] = true
                asked = asked + 1
                local ok, aura = false, nil
                if get then ok, aura = pcall(get, "target", name, "HARMFUL|PLAYER") end
                if not ok then
                    errors = errors + 1
                elseif aura ~= nil then
                    local okEnd, ends = pcall(function() return aura.expirationTime end)
                    found[#found + 1] = name .. " (data " .. Describe(aura) .. ", ends "
                        .. (okEnd and Describe(ends) or "unreadable") .. ")"
                end
            end
        end
        Add("your debuffs the game reports: " .. (#found > 0 and table.concat(found, "; ") or "none"))
        if errors > 0 then Add("debuff lookups refused: " .. errors .. " of " .. asked) end
        local okAll, all = pcall(C_UnitAuras.GetUnitAuras, "target", "HARMFUL|PLAYER")
        Add("full debuff list: " .. (okAll and Describe(all) or "refused"))
        local nameplate = C_NamePlate.GetNamePlateForUnit("target")
        local plate = nameplate and nameplate.KuiForeverPlate
        local now = GetTime()
        for key, dot in pairs(plate and plate.dots or {}) do
            Add(string.format("tracking %s: %s, %d dmg, %.1fs left", key, dot.state, math.floor(dot.damage), dot.ends - now))
        end
    end
    for _, line in ipairs(castLog) do Add("cast " .. line) end
    ns.Print("DoT probe:")
    for _, line in ipairs(out) do print("  " .. line) end
end
