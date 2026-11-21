# KuiNameplates

Unofficial Kui-style nameplates for WoW: Forever. Not affiliated with Kesava's Kui Nameplates.

Small, thin bars that stay readable in a crowded pull: the name on the top edge of the bar, level and health on the bottom edge, a soft blue glow on your target, and everything else faded back.

## Install
Copy the `KuiNameplates` folder into `World of Warcraft/_forever_/Interface/AddOns/` and restart the game.

## Features
**Enemy plates**
- Compact bars sized in screen pixels, the same at any UI scale, with an overall size slider
- Muted reaction colours, class colours for enemy players
- Level with elite/rare markers and health percent on the bottom edge of the bar
- Soft glow: blue on your target, orange or red for threat; optional tank mode bar colours
- Arrows either side of your target (optional)
- Crowd control icons next to the bar, raid target icons

**Friendly plates**
- Coloured name with no bar (optional)
- NPC title or player guild on a second line, with a colour picker

**Cast bars**
- Three styles: thin, tall with the spell name inside, or icon only
- Spell icon, leading-edge spark, interrupted flash, uninterruptible colouring

**Auras**
- Your debuffs on enemies, in combat too, with the time left on the corner
- Above, below, left or right of the bar, with a distance setting
- Enemy buffs you can purge or steal in their own row, above the name or below the bar
- Borders coloured by type (magic, curse, disease, poison, bleed)

**Experimental (off by default)**
- DoT damage prediction: a green section at the end of the health bar shows the damage your DoTs and bleeds will still do, and a red skull beside the bar means they are enough to kill. Turn it on in the Experimental tab or with `/kui dots`. A DoT only counts once the game shows your debuff is on the enemy, so immunities and misses drop out; a "?" on the damage number means the game would not confirm it. Damage is read from spell tooltips (English client), so crits are not counted. `/kui dotprobe` prints what the addon can see.

**Range and performance**
- Max nameplate distance setting for Forever's longer ranges
- Batched updates so big pulls at long range stay smooth

## Settings
`/kui config`, the minimap button, or Options > AddOns opens the settings, split into General, Enemies, Friendly, Cast bars, Auras and Experimental tabs.
`/kui test` (or right-click the minimap button) shows sample plates, a looping cast, debuffs and buffs to try settings on.
`/kui` lists all slash commands.

## Releasing
1. Create the project on CurseForge and add `## X-Curse-Project-ID: <id>` to `KuiNameplates.toc`.
2. Add a CurseForge API token as the `CF_API_KEY` secret in the GitHub repo settings.
3. Update `CHANGELOG.md`, then push a tag such as `v0.3.0`. The Release workflow builds the zip and uploads it.

## License
Copyright (c) 2026 mjared123. All Rights Reserved. See `LICENSE`.
Versions before v0.3.0 were released under the MIT License.

The Francois One font in `media/` is by Vernon Adams and is used under the SIL Open Font License (`media/FrancoisOne-OFL.txt`). The bar, glow and icon textures are original to this addon.
