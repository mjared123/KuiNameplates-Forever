# Changelog

## v0.10.0
- Hide buffs and debuffs you don't want to see. The new Filters tab has a list of hidden auras: type a spell name (hides every rank) or a spell ID. Next to it, "Seen on plates" lists every buff and debuff the addon has spotted, newest first, with a tick box to hide each one. Also `/kui hide <name or ID>`, `/kui unhide <name or ID>`, and `/kui hide` on its own to list them.
- Hidden auras are taken out of the row and the other icons close up. In combat the game may keep the spell from the addon; the icon is then made invisible but can leave a gap in the row until it is next rebuilt.
- An option to keep hidden auras showing on friendly plates.
- New `/kui auraprobe` command: lists the buff and debuff icons on your target and what the addon can see about each, to check how hiding works in combat.

## v0.9.0
- Target arrows: new settings on the General tab for their colour, size, distance from the bar and height. Also `/kui arrowsize`, `/kui arrowdistance` and `/kui arrowheight`.
- Caster colour: an option on the Enemies tab (or `/kui casters`) to give enemy NPCs that use mana their own bar colour, blue unless you pick another. Off by default. Player pets and neutral NPCs keep their usual colour, and tank mode colours come first.
- Cast bars: pick the colours of casts you can interrupt and casts you can't, on the Cast bars tab. The colour now also works when the game hides the answer from addons in combat, and changes mid-cast if a cast becomes interruptible or stops being so.
- Tank mode: pick both colours (you hold threat, threat slipping or not on you) on the Enemies tab.
- Enemy class colours, for battlegrounds and anywhere else the game hides an enemy's class from addons: the bar now asks the game for the colour of the hidden class instead of turning red.
- Test mode alternates casts you can and can't interrupt, and shows the caster and tank mode colours when those are on.

## v0.8.0
- DoT prediction (experimental) reworked. A cast no longer counts on its own: a DoT is added only once the game shows your debuff is really on the enemy. Immune targets (Serpent Sting on a water elemental), misses, resists and dodges no longer show damage, and DoTs that are dispelled or wear off early drop out.
- Every DoT on a target now adds to the total, and a green number on the bar shows the damage left, so you can see it recalculate as you add more.
- Where the game won't confirm a debuff during combat, the DoT is still shown as a guess, marked with a "?" after the number.
- New `/kui dotprobe` command: prints what the game lets the addon see on your target (your debuffs, hidden values, and your last few casts), to help track down problems.

## v0.7.2
- Fixed: the big crowd control icon on enemy players could jump far out to the right of the bar when the stun or root landed. The game resizes that icon without telling the addon; it is now placed again each time.
- Crowd control icons right of the bar no longer leave the extra space the left side needs for the cast icon, so they sit closer to the bar.
- DoT prediction (experimental) no longer randomly misses DoTs:
  - The first cast of a spell after logging in could be skipped while the game was still loading the spell's tooltip. It now waits for the tooltip and tries again.
  - DoTs come back when an enemy's plate leaves the screen for a moment and returns.
  - Rip and Rupture used to be skipped when the game hid how many combo points you spent. They now count as full combo points in that case.

## v0.7.1
- DoT prediction (experimental) now counts hunter Immolation Trap and Explosive Trap. A trap isn't cast on your target, so the damage is added to whichever enemy gets the trap's burn. Explosive Trap counts every enemy it catches. If the game won't tell the addon which enemy was caught, a chat message says so once and traps are left out.

## v0.7.0
- Combo points: rogues and cat-form druids see a row of gold pips on the bottom edge of their target's bar. On by default; toggle on the General tab or with `/kui combo`. Test mode shows three of five.
- Fonts: a new Font setting on the General tab (or `/kui fontface`) picks Francois One, the game's own name font, Friz Quadrata, Arial Narrow, Morpheus or Skurri. Korean, Chinese and Russian letters now always show, using the game's fonts for those alphabets, and clients in those languages start with the game's font.
- Target of target: an option to show who each enemy is targeting, under its bar ("> You" in orange when it's you, players in class colours). It moves below the spell name while the enemy casts. Off by default; turn it on on the General tab or with `/kui tot`.
- Cast bars: a slider to move the spell name up or down (`/kui casttextoffset`).
- Auras: a slider for the size of the timer and stack numbers on aura icons (`/kui auratext`).

## v0.6.2
- Fixed: the right target arrow no longer jumps outwards while your target casts. Only the left arrow steps out, to clear the spell icon.

## v0.6.1
- Health as name: on plates that show only a name (friendly units), the name now shows health. The healthy part is in the usual name colour and the missing part turns dark grey from the right, so at half health the right half of the name is grey. Names at full health look the same as before. On by default; turn it off on the Friendly tab or with `/kui hpname`. The sample friend in test mode is a little hurt to show it.

## v0.6.0
- Target arrows: two blue arrows either side of your target's bar, pointing in at it. On by default; turn them off on the General tab or with `/kui arrows`. They sit just outside the bar and step out past the cast icon while your target casts. Debuffs, crowd control and raid marks placed beside the bar now keep clear of them.
- Enemy buffs: a row of the buffs you can purge or spellsteal (plus a few important ones the game flags) on enemy plates, with magic buffs outlined in blue. By default the row sits above your debuffs, with the raid mark on top; set it to sit below the bar instead on the new Auras tab or with `/kui buffpos top|bottom`. Toggle with `/kui buffs`. These come from the game's own nameplate buff list, so they work in combat like debuffs do. Buffs no longer sit beside the bar with crowd control.
- The Debuffs tab is now the Auras tab, with debuff and buff settings together. Test mode shows sample buffs.

## v0.5.1
- Raid marks now sit above the name by default, stacked on top of the debuff row when debuffs are shown above the bar.
- New "Raid marks" settings on the General tab: position (above the name and debuffs, left of the bar, or right of the bar) and size. Also `/kui markpos top|left|right` and `/kui marksize <12-40>`. If debuffs use the chosen side, the mark goes on top instead. Friendly name-only plates always show the mark above the name.

## v0.5.0
- New experimental option, off by default: DoT damage prediction. A green section at the end of the health bar shows how much damage your DoTs and bleeds will still do, and a red skull beside the bar shows when that is enough to kill, so you can move on to the next target. Turn it on in the new Experimental tab or with `/kui dots`; test mode shows a sample.
- How it works on WoW: Forever: the addon can't read enemy health, auras or the combat log in combat, so it notes your own DoT casts and reads their damage and duration from the spell tooltip. The game draws the result against the hidden health. It is an estimate: misses, resists, immunities, crits and haste are not counted, and it needs an English client.
- Counted spells: Rake, Rip, Pounce, Moonfire, Insect Swarm, Rupture, Garrote, Rend, Corruption, Curse of Agony, Immolate, Siphon Life, Shadow Word: Pain, Devouring Plague, Holy Fire and Serpent Sting. DoTs are only counted on your target when you cast them, and they are forgotten if its plate leaves the screen.

## v0.4.1
- Fixed raid marks (skull, cross and the rest) never showing on plates. WoW: Forever hides the mark number from addons, and the plate took that as "no mark". Marks now show left of the bar, clear of the cast icon, or above the name on name-only plates and when debuffs sit beside the bar. The sample enemy in test mode shows a skull.

## v0.4.0
- Two-part names: WoW: Forever characters can now have a first name and a surname, and plates show both by default. A new "Player names" setting on the General tab (or `/kui names full|first|last`) switches to first name only or last name only.

## v0.3.0
- License changed from MIT to All Rights Reserved. Earlier versions keep the MIT License.
- Compact look: plates are now sized in screen pixels instead of following the game's nameplate scale, so they are much smaller and stay the same size at any UI scale. New "Overall size" slider and `/kui scale`.
- Darker, muted bar colours, with the empty part of the bar a dark shade of the same colour.
- The name now sits on the top edge of the bar; level and health percent sit on the bottom edge.
- New soft glow: blue on your target, red or orange for threat, and a faint shadow on everything else. Replaces the white box.
- Friendly units show as a coloured name with no bar (toggle in settings or `/kui friendly`), with the NPC's title or the player's guild on a second line (`/kui titles`).
- Debuff icons are short, wide and thin-bordered, with the time left as a yellow number on the corner. Each icon is placed by the addon, so they always line up.
- Debuff borders can be coloured by type: blue magic, purple curse, brown disease, green poison, red bleed (toggle in settings or `/kui colors`).
- Debuff position: above (centred or from the left), below, or left or right of the bar, plus a distance setting (`/kui debuffpos`, `/kui debuffoffset`).
- Settings are split into tabs (General, Enemies, Friendly, Cast bars, Debuffs), with separate text sizes and spacing for enemy and friendly plates, and a colour picker for the title and guild line.
- Test mode (`/kui test`, the settings button, or right-click the minimap button): sample enemy and friendly plates with a looping cast and sample debuffs, for trying settings.
- Minimap button: click opens the settings, drag moves it (toggle in settings or `/kui minimap`).
- Cast bar styles (settings dropdown or `/kui caststyle`): thin bar, tall bar with the spell name inside, or icon only.
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
