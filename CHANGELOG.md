# Changelog

## v0.2.0
- Fixed: errors on WoW: Forever, which hides enemy health and other numbers from addons. Hidden values now go straight to the bars, and percent text comes from the game's own percent API.
- Fixed: one failing part (cast bar, debuffs, ...) no longer stops the rest of the plate from drawing.
- New look closer to Kui: Francois One font, shaded bar texture, soft glow on target and threat, thinner cast bar, faded non-target plates.
- Interface version set to 16001 for WoW: Forever.

## v0.1.0
First release.
- Flat health bars with the name above and level and health % inside
- Reaction colours, class colours for enemy players, grey for tapped mobs
- White outline on your target, faded non-target plates
- Threat glow, plus optional tank mode bar colours
- Cast bars with spell icon and name, an "Interrupted" flash, and grey bars for uninterruptible casts
- Your debuffs on enemies, with cooldown swipes and stack counts
- Raid target icons
- Settings panel (`/kui config`) and slash commands (`/kui`)
- Max nameplate distance setting for WoW: Forever's longer ranges
- Health and debuff updates are batched to once per frame, so lots of plates on screen stay smooth
