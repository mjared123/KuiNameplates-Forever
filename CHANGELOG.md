# Changelog

## v0.3.0
- Compact look: plates are now sized in screen pixels instead of following the game's nameplate scale, so they are much smaller and stay the same size at any UI scale. New "Overall size" slider and `/kui scale`.
- Darker, muted bar colours, with the empty part of the bar a dark shade of the same colour.
- The name now sits on the top edge of the bar; level and health percent sit on the bottom edge.
- New soft glow: blue on your target, red or orange for threat, and a faint shadow on everything else. Replaces the white box.
- Friendly units show as a coloured name with no bar (toggle in settings or `/kui friendly`).
- Debuff icons are short, wide and thin-bordered, with the time left as a yellow number on the corner. Each icon is placed by the addon, so they always line up.
- Debuff borders can be coloured by type: blue magic, purple curse, brown disease, green poison, red bleed (toggle in settings or `/kui colors`).
- Debuff position: above (centred or from the left), below, or left or right of the bar, plus a distance setting (`/kui debuffpos`, `/kui debuffoffset`).
- Cast bars: thin pale bar under the health bar with a bright spark on the leading edge, square spell icon to the left of both bars, spell name underneath.
- Debuffs now show in combat. WoW: Forever blocks addons from reading auras during combat, so the icons are the game's own nameplate debuff row, moved onto the plate above the name. The addon turns on the game's "show debuffs on enemy nameplates" and "show all my debuffs" settings so the row is filled. The "Max debuff icons" setting is gone; "Debuff icon size" still works.

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
