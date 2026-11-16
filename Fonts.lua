-- KuiNameplates: fonts.
--
-- Text is drawn with a font family: the chosen font for Latin letters, and
-- the game's own fonts for Korean, Chinese and Cyrillic, which the chosen
-- font may not have. Names in any language then show instead of blanks.
local _, ns = ...

local MEDIA = "Interface\\AddOns\\KuiNameplates\\media\\"

-- The game's fonts for other alphabets, from its own Fonts folder.
local KOREAN = "Fonts\\2002.TTF"
local SIMPLIFIED = "Fonts\\ARKai_T.ttf"
local TRADITIONAL = "Fonts\\blei00d.TTF"
local CYRILLIC = "Fonts\\FRIZQT___CYR.TTF"

local function GameFont()
    return UNIT_NAME_FONT or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

-- key -> Latin file, Cyrillic file (nil uses the game's Cyrillic font)
local FONTS = {
    francois = { MEDIA .. "FrancoisOne.ttf" },
    game = { GameFont },
    friz = { "Fonts\\FRIZQT__.TTF", "Fonts\\FRIZQT___CYR.TTF" },
    arial = { "Fonts\\ARIALN.TTF", "Fonts\\ARIALN.TTF" },
    morpheus = { "Fonts\\MORPHEUS.ttf", "Fonts\\MORPHEUS_CYR.ttf" },
    skurri = { "Fonts\\skurri.ttf", "Fonts\\SKURRI_CYR.TTF" },
}

ns.FONT_KEYS = { "francois", "game", "friz", "arial", "morpheus", "skurri" }
ns.FONT_NAMES = {
    francois = "Francois One (addon's own)",
    game = "Game's name font (your language)",
    friz = "Friz Quadrata",
    arial = "Arial Narrow",
    morpheus = "Morpheus",
    skurri = "Skurri",
}

-- Clients in languages that don't use Latin letters start with the game's font.
local LATIN = {
    enUS = true, enGB = true, deDE = true, frFR = true, esES = true,
    esMX = true, itIT = true, ptBR = true, ptPT = true,
}
function ns.DefaultFont()
    local locale = GetLocale and GetLocale()
    if locale and not LATIN[locale] then return "game" end
    return "francois"
end

local function Chosen()
    local key = ns.db and ns.db.font
    return FONTS[key] and key or "francois"
end

-- The Latin font file, for text that is only numbers.
function ns.FontFile()
    local file = FONTS[Chosen()][1]
    if type(file) == "function" then file = file() end
    return file
end

local cache = {}
local count = 0

-- A font object for this size, with the other alphabets filled in.
function ns.FontObject(size, flags)
    flags = flags or "OUTLINE"
    size = math.floor(size + 0.5)
    local key = Chosen()
    local id = key .. ":" .. size .. ":" .. flags
    if cache[id] then return cache[id] end

    local latin = ns.FontFile()
    local cyrillic = FONTS[key][2]
    if key == "game" and GetLocale and GetLocale() == "ruRU" then cyrillic = latin end
    count = count + 1
    local name = "KuiNameplatesFont" .. count
    local font
    if CreateFontFamily then
        local ok, family = pcall(CreateFontFamily, name, {
            { alphabet = "roman", file = latin, height = size, flags = flags },
            { alphabet = "korean", file = KOREAN, height = size, flags = flags },
            { alphabet = "simplifiedchinese", file = SIMPLIFIED, height = size, flags = flags },
            { alphabet = "traditionalchinese", file = TRADITIONAL, height = size, flags = flags },
            { alphabet = "russian", file = cyrillic or CYRILLIC, height = size, flags = flags },
        })
        if ok and family then font = family end
    end
    if not font then
        font = CreateFont(name)
        font:SetFont(latin, size, flags)
    end
    cache[id] = font
    return font
end

-- Give a font string the chosen font, keeping its colour and shadow, which
-- switching font objects would otherwise reset.
function ns.SetFont(fs, size, flags)
    local r, g, b, a = fs:GetTextColor()
    local sr, sg, sb, sa = fs:GetShadowColor()
    local sx, sy = fs:GetShadowOffset()
    fs:SetFontObject(ns.FontObject(size, flags))
    fs:SetTextColor(r, g, b, a)
    fs:SetShadowColor(sr, sg, sb, sa)
    fs:SetShadowOffset(sx, sy)
end

ns.defaults.font = ns.DefaultFont()
