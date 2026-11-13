-- KuiNameplates: slash commands. The settings panel lives in Options.lua.
local _, ns = ...

local function OnOff(value)
    return value and "on" or "off"
end

local toggles = {
    class = { key = "classColors", label = "Class colours on enemy players" },
    tank = { key = "tankMode", label = "Tank mode" },
    level = { key = "showLevel", label = "Level text" },
    hp = { key = "healthText", label = "Health percent" },
    cast = { key = "castBars", label = "Cast bars" },
    debuffs = { key = "auras", label = "Debuff icons" },
    friendly = { key = "nameOnly", label = "Name only on friendly units" },
    colors = { key = "auraColors", label = "Debuff borders coloured by type" },
    minimap = { key = "minimapButton", label = "Minimap button" },
    titles = { key = "showTitle", label = "NPC titles and guild names" },
    dots = { key = "dotPrediction", label = "DoT damage prediction (experimental)" },
}

local numbers = {
    width = { key = "width", min = 40, max = 300 },
    height = { key = "height", min = 4, max = 40 },
    font = { key = "nameSize", min = 6, max = 24 },
    scale = { key = "scale", min = 0.5, max = 2 },
    alpha = { key = "nonTargetAlpha", min = 0, max = 1 },
    icons = { key = "auraWidth", min = 12, max = 40 },
    debuffoffset = { key = "auraOffset", min = -20, max = 40 },
    friendlyheight = { key = "nameOnlyOffset", min = -40, max = 60 },
    marksize = { key = "raidSize", min = 12, max = 40 },
}

function ns:ResetSettings()
    local db = self.db
    local keep = db.maxDistance
    wipe(db)
    for k, v in pairs(self.defaults) do db[k] = v end
    db.maxDistance = keep -- the game's distance setting isn't reverted automatically
    self:RefreshAll()
end

local function Help()
    ns.Print("commands:")
    print("  /kui config  - open the settings panel")
    print("  /kui test  - show sample plates to try settings on")
    print("  /kui range [yards]  - show or set max nameplate distance")
    print("  /kui width|height|font <n>  - bar size and name font size")
    print("  /kui scale <0.5-2>  - overall plate size")
    print("  /kui alpha <0-1>  - transparency of non-target plates")
    print("  /kui names full|first|last  - which parts of player names to show")
    print("  /kui caststyle thin|tall|icon  - cast bar style")
    print("  /kui icons <12-40>  - debuff icon size")
    print("  /kui debuffpos top|topleft|bottom|left|right  - where debuff icons sit")
    print("  /kui debuffoffset <n>  - move debuff icons further from the bar")
    print("  /kui friendlyheight <n>  - raise or lower friendly names")
    print("  /kui markpos top|left|right  - where raid marks sit")
    print("  /kui marksize <12-40>  - raid mark size")
    print("  /kui class|tank|level|hp|cast|debuffs|friendly|colors|minimap|titles|dots  - toggle features")
    print("  /kui reset  - restore defaults")
end

local function Handle(msg)
    local cmd, arg = strsplit(" ", (msg or ""):lower(), 2)
    local db = ns.db

    if cmd == "config" or cmd == "options" then
        ns:OpenOptions()
    elseif cmd == "range" then
        local value = tonumber(arg)
        if value then
            db.maxDistance = value
            ns:ApplyCVars()
            if InCombatLockdown() then
                ns.Print("range will change to " .. value .. " when combat ends.")
            else
                -- Report what the client actually accepted; it may clamp the value.
                ns.Print("max nameplate distance is now " .. tostring(GetCVar("nameplateMaxDistance")))
            end
        else
            ns.Print("max nameplate distance: " .. tostring(GetCVar("nameplateMaxDistance")))
        end
    elseif cmd == "test" then
        ns:SetTestMode(not ns.testMode)
        ns.Print("test mode " .. OnOff(ns.testMode))
    elseif cmd == "names" then
        if arg and ns.NAME_PART_NAMES[arg] then
            db.nameParts = arg
            ns:RefreshAll()
        end
        ns.Print("player names: " .. tostring(db.nameParts) .. " (full, first, last)")
    elseif cmd == "caststyle" then
        if arg and ns.CAST_STYLE_NAMES[arg] then
            db.castStyle = arg
            ns:RefreshAll()
        end
        ns.Print("cast bar style: " .. tostring(db.castStyle) .. " (thin, tall, icon)")
    elseif cmd == "debuffpos" then
        if arg and ns.AURA_SPOT_NAMES[arg] then
            db.auraSpot = arg
            ns:RefreshAll()
        end
        ns.Print("debuff position: " .. tostring(db.auraSpot) .. " (top, topleft, bottom, left, right)")
    elseif cmd == "markpos" then
        if arg and ns.RAID_SPOT_NAMES[arg] then
            db.raidSpot = arg
            ns:RefreshAll()
        end
        ns.Print("raid mark position: " .. tostring(db.raidSpot) .. " (top, left, right)")
    elseif toggles[cmd] then
        local t = toggles[cmd]
        db[t.key] = not db[t.key]
        ns.Print(t.label .. ": " .. OnOff(db[t.key]))
        ns:RefreshAll()
    elseif numbers[cmd] then
        local n, value = numbers[cmd], tonumber(arg)
        if not value then
            ns.Print(cmd .. " is " .. tostring(db[n.key]))
            return
        end
        db[n.key] = math.min(math.max(value, n.min), n.max)
        ns.Print(cmd .. " set to " .. db[n.key])
        ns:RefreshAll()
    elseif cmd == "reset" then
        ns:ResetSettings()
        ns.Print("settings reset. Max distance is left as it is; use /kui range to change it.")
    else
        Help()
    end
end

SLASH_KUINAMEPLATESFOREVER1 = "/kui"
SLASH_KUINAMEPLATESFOREVER2 = "/kuiforever"
SlashCmdList.KUINAMEPLATESFOREVER = Handle
