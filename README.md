# KuiNameplates

Unofficial Kui-style nameplates for WoW: Forever. Not affiliated with Kesava's Kui Nameplates. Thin flat bars, the name above the bar, level and health inside it.

## Install
Copy the `KuiNameplates` folder into the `Interface/AddOns/` folder of your WoW: Forever install and restart the game.

## Features
- Reaction-coloured health bars, class colours for enemy players
- Level with elite/rare markers, health percent when damaged
- White outline on your target, faded non-target plates
- Threat glow (orange: close to pulling aggro, red: you have aggro), optional tank mode colouring
- Cast bars with spell icon, interrupted flash and uninterruptible colouring
- Your debuffs on enemies with timers and stacks
- Raid target icons
- Max nameplate distance setting for Forever's longer ranges
- Batched updates so big pulls at long range stay smooth

## Settings
`/kui config` opens the settings panel (also under Options > AddOns). `/kui` lists all slash commands.

## Releasing
1. Create the project on CurseForge and add `## X-Curse-Project-ID: <id>` to `KuiNameplates.toc`.
2. Add a CurseForge API token as the `CF_API_KEY` secret in the GitHub repo settings.
3. Update `CHANGELOG.md`, then push a tag such as `v0.1.0`. The Release workflow builds the zip and uploads it.

## License
MIT. See `LICENSE`.

The Francois One font in `media/` is by Vernon Adams and is used under the SIL Open Font License (`media/FrancoisOne-OFL.txt`). The bar and glow textures are original to this addon.
