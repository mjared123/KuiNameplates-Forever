-- ForeverPlates: slash commands. A full settings panel comes in a later step.
local _, ns = ...

local function OnOff(value)
    return value and "on" or "off"
end

local toggles = {
    class = { key = "classColors", label = "Class colours on enemy players" },
    tank = { key = "tankMode", label = "Tank mode" },
    level = { key = "showLevel", label = "Level text" },
    hp = { key = "healthText", label = "Health percent" },
}

local numbers = {
    width = { key = "width", min = 40, max = 300 },
    height = { key = "height", min = 4, max = 40 },
    font = { key = "nameSize", min = 6, max = 24 },
    alpha = { key = "nonTargetAlpha", min = 0, max = 1 },
}

local function Help()
    ns.Print("commands:")
    print("  /fp range [yards]  - show or set max nameplate distance")
    print("  /fp width|height|font <n>  - bar size and name font size")
    print("  /fp alpha <0-1>  - transparency of non-target plates")
    print("  /fp class|tank|level|hp  - toggle features")
    print("  /fp reset  - restore defaults")
end

local function Handle(msg)
    local cmd, arg = strsplit(" ", (msg or ""):lower(), 2)
    local db = ns.db

    if cmd == "range" then
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
        wipe(db)
        for k, v in pairs(ns.defaults) do db[k] = v end
        ns:RefreshAll()
        ns.Print("settings reset. Max distance is left as it is; use /fp range to change it.")
    else
        Help()
    end
end

SLASH_FOREVERPLATES1 = "/fp"
SLASH_FOREVERPLATES2 = "/foreverplates"
SlashCmdList.FOREVERPLATES = Handle
