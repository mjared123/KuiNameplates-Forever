-- KuiNameplates: hiding chosen buffs and debuffs.
--
-- The aura icons are the game's own (see Plate.lua), so to hide one the addon
-- has to tell which spell an icon shows. Out of combat the game hands that
-- over, so a hidden aura is taken out of the row and the rest close up.
--
-- In combat WoW: Forever may hide the spell from addons (a "secret" value).
-- The addon can't compare a secret, but it can pass one to the game: a step
-- curve that is 0 at every hidden spell ID and 1 elsewhere turns the spell ID
-- into an opacity, and the game makes the icon invisible for us. That icon
-- still holds its place in the row, so it can leave a gap until the row is
-- next rebuilt out of combat. `/kui auraprobe` shows which of these works.
--
-- Saved data:
--   db.hiddenAuras[key] = { name, icon, kind, ids = { [spellID] = true } }
--     key is a lower-case spell name (hides every rank) or a spell ID typed
--     by the player (hides that ID only).
--   db.seenAuras[lower-case name] = { name, icon, kind, id, t }
--     buffs and debuffs spotted on plates, for the settings list.
local _, ns = ...

local SEEN_LIMIT = 80

local issecret = issecretvalue or function() return false end
local canaccess = canaccessvalue or function() return true end
local function IsSecret(value)
    return value ~= nil and (issecret(value) or not canaccess(value))
end

function ns:InitAuraFilters()
    local db = self.db
    if type(db.hiddenAuras) ~= "table" then db.hiddenAuras = {} end
    if type(db.seenAuras) ~= "table" then db.seenAuras = {} end
end

-- Spell name and icon for an ID, from the game's spell data.
local function SpellInfo(id)
    local name, icon
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok then name = n end
        if C_Spell.GetSpellTexture then
            local okIcon, i = pcall(C_Spell.GetSpellTexture, id)
            if okIcon then icon = i end
        end
    end
    if not name and GetSpellInfo then
        local ok, n, _, i = pcall(GetSpellInfo, id)
        if ok then name, icon = n, icon or i end
    end
    if IsSecret(name) then name = nil end
    if IsSecret(icon) then icon = nil end
    return name, icon
end

-- The spell ID, name and icon of an aura, or nils where the game hides them.
-- Also reports whether the spell ID was there but hidden.
function ns.ReadAura(aura)
    if type(aura) ~= "table" then return end
    local ok, id, name, icon = pcall(function() return aura.spellId, aura.name, aura.icon end)
    if not ok then return nil, nil, nil, false, "refused" end
    local hiddenID = IsSecret(id) and id or nil
    if IsSecret(id) then id = nil end
    if IsSecret(name) then name = nil end
    if IsSecret(icon) then icon = nil end
    return id, name, icon, hiddenID, nil
end

-- The hidden-list entry matching an aura, if any.
function ns:FindHidden(id, name)
    local hidden = self.db.hiddenAuras
    if id and hidden[id] then return hidden[id] end
    if name then
        local entry = hidden[name:lower()]
        if entry then return entry end
    end
    if id then
        -- A name typed before the spell was ever seen has no IDs yet.
        for _, entry in pairs(hidden) do
            if entry.ids and entry.ids[id] then return entry end
        end
    end
end

-- Should an aura with this spell ID and name be hidden on this unit?
function ns:IsAuraHidden(id, name, unit)
    if not (id or name) then return false end
    if not self.db.hideOnFriends and unit and ns.Plain(UnitCanAttack("player", unit)) == false then
        return false
    end
    local entry = self:FindHidden(id, name)
    if entry and id and not (entry.ids and entry.ids[id]) then
        entry.ids = entry.ids or {}
        -- Remember the ID, so the aura can still be hidden in combat.
        entry.ids[id] = true
        self:AuraFiltersChanged(true)
    end
    return entry ~= nil
end

-- Note an aura seen on a plate, for the "Seen on plates" list.
function ns:NoteSeenAura(id, name, icon, kind)
    if not name then return end
    local seen = self.db.seenAuras
    local key = name:lower()
    local entry = seen[key]
    if not entry then
        entry = { name = name }
        seen[key] = entry
        local count, oldestKey, oldest = 0, nil, nil
        for k, e in pairs(seen) do
            count = count + 1
            if not oldest or (e.t or 0) < oldest then oldestKey, oldest = k, e.t or 0 end
        end
        if count > SEEN_LIMIT and oldestKey ~= key then seen[oldestKey] = nil end
        if self.optionsPanel and self.optionsPanel:IsShown() then self.optionsPanel.Refresh() end
    end
    entry.icon = icon or entry.icon
    entry.kind = kind or entry.kind
    entry.id = id or entry.id
    entry.t = time()
    -- A name typed into the hidden list gets its icon once it is seen.
    local hidden = self.db.hiddenAuras[key]
    if hidden then
        hidden.icon = hidden.icon or entry.icon
        hidden.kind = hidden.kind or entry.kind
    end
end

-- Seen auras, newest first, optionally only buffs or only debuffs.
function ns:SeenAuraList(kind)
    local list = {}
    for key, entry in pairs(self.db.seenAuras) do
        if not kind or entry.kind == kind then
            list[#list + 1] = { key = key, entry = entry }
        end
    end
    table.sort(list, function(a, b)
        local ta, tb = a.entry.t or 0, b.entry.t or 0
        if ta ~= tb then return ta > tb end
        return a.key < b.key
    end)
    return list
end

-- Hidden auras, sorted by name.
function ns:HiddenAuraList()
    local list = {}
    for key, entry in pairs(self.db.hiddenAuras) do
        list[#list + 1] = { key = key, entry = entry }
    end
    table.sort(list, function(a, b)
        return (a.entry.name or ""):lower() < (b.entry.name or ""):lower()
    end)
    return list
end

-- Hide a spell. `text` is a spell name or ID typed by the player. Returns the
-- name shown in the list, or nil and a reason.
function ns:HideAura(text, kind)
    text = text and strtrim(tostring(text)) or ""
    if text == "" then return nil, "type a spell name or ID" end
    local hidden = self.db.hiddenAuras
    local id = tonumber(text)
    if id then
        id = math.floor(id)
        local name, icon = SpellInfo(id)
        hidden[id] = { name = name or ("Spell " .. id), icon = icon, kind = kind, ids = { [id] = true } }
        self:AuraFiltersChanged()
        return hidden[id].name
    end
    local key = text:lower()
    local seen = self.db.seenAuras[key]
    local entry = hidden[key] or { ids = {} }
    entry.name = (seen and seen.name) or entry.name or text
    entry.icon = entry.icon or (seen and seen.icon)
    entry.kind = entry.kind or kind or (seen and seen.kind)
    if seen and seen.id then entry.ids[seen.id] = true end
    hidden[key] = entry
    self:AuraFiltersChanged()
    return entry.name
end

function ns:ShowAura(key)
    self.db.hiddenAuras[key] = nil
    self:AuraFiltersChanged()
end

-- The hidden-list key that covers a seen aura, if any.
function ns:HiddenKeyFor(seenKey)
    local seen = self.db.seenAuras[seenKey]
    if self.db.hiddenAuras[seenKey] then return seenKey end
    if seen and seen.id then
        if self.db.hiddenAuras[seen.id] then return seen.id end
        for key, entry in pairs(self.db.hiddenAuras) do
            if entry.ids and entry.ids[seen.id] then return key end
        end
    end
end

-- Combat curve ---------------------------------------------------------------

local alphaCurve -- false when the game has no curves, nil when not built yet

function ns:AuraFiltersChanged(quiet)
    alphaCurve = nil
    if quiet then return end
    self:RefreshAll()
    if self.optionsPanel and self.optionsPanel:IsShown() then self.optionsPanel.Refresh() end
end

-- A step curve that is 0 at every hidden spell ID and 1 everywhere else.
local function AlphaCurve()
    if alphaCurve ~= nil then return alphaCurve or nil end
    alphaCurve = false
    local ids = {}
    for key, entry in pairs(ns.db.hiddenAuras) do
        if type(key) == "number" then ids[key] = true end
        for id in pairs(entry.ids or {}) do ids[id] = true end
    end
    local sorted = {}
    for id in pairs(ids) do sorted[#sorted + 1] = id end
    if #sorted == 0 then return nil end
    table.sort(sorted)
    pcall(function()
        local curve = C_CurveUtil.CreateCurve()
        -- Without steps the curve would fade every spell in between.
        curve:SetType(Enum.LuaCurveType.Step)
        curve:AddPoint(0, 1)
        for i, id in ipairs(sorted) do
            curve:AddPoint(id, 0)
            if sorted[i + 1] ~= id + 1 then curve:AddPoint(id + 1, 1) end
        end
        alphaCurve = curve
    end)
    return alphaCurve or nil
end

-- Let the game hide an icon whose spell ID is hidden from the addon. Returns
-- true when the game took the curve.
function ns.HideBySecret(item, secretID)
    local curve = AlphaCurve()
    if not curve then return false end
    local ok, alpha = pcall(curve.Evaluate, curve, secretID)
    if not ok then return false end
    return (pcall(item.SetAlpha, item, alpha))
end

-- /kui auraprobe ---------------------------------------------------------------

local function Describe(value)
    if value == nil then return "nil" end
    if IsSecret(value) then return "hidden" end
    return tostring(value)
end

function ns:AuraProbe()
    local inCombat = InCombatLockdown()
    ns.Print("aura probe (in combat: " .. tostring(inCombat) .. "):")
    local count = 0
    for name in pairs(self.db.hiddenAuras) do count = count + 1 end
    local curve = AlphaCurve()
    print("  hidden list: " .. count .. " entries, combat curve: " .. (curve and "ready" or "none"))
    if not UnitExists("target") then
        print("  no target")
        return
    end
    local items = self.TargetAuraItems and self:TargetAuraItems()
    if not items or #items == 0 then
        print("  no buff or debuff icons on your target's plate")
        return
    end
    for _, info in ipairs(items) do
        local id, name, icon, hiddenID, err = ns.ReadAura(info.aura)
        local line
        if err then
            line = "data refused"
        elseif not info.aura then
            line = "no data"
        else
            line = string.format("%s, ID %s", name or "name hidden", id and tostring(id) or (hiddenID and "hidden" or "nil"))
            if hiddenID then
                local okEval, alpha = false, nil
                if curve then okEval, alpha = pcall(curve.Evaluate, curve, hiddenID) end
                line = line .. ", curve " .. (not curve and "not built" or okEval and ("gives " .. Describe(alpha)) or "refused")
            end
            if (id or name) and self:IsAuraHidden(id, name, "target") then line = line .. ", on hidden list" end
        end
        print("  " .. info.kind .. ": " .. line)
    end
end
