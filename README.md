# PhalkTools - WoW Forever

A quality-of-life addon with independent modules.

**Open settings:** `/pt` or `/phalktools`, or Game Menu > Options > AddOns > PhalkTools.
Enable or disable modules on the main page. Each module has its own subcategory;
the checkboxes on the main page and in each subcategory stay synchronized.

## Personal Resource Display

In `/pt`, enable **Personal Resource Display** and open the subcategory of the
same name. In that subcategory, **Enable Personal Resource Display** toggles the
native WoW display itself.

The controls include size, bar width, heights, padding, opacity, visibility,
options to hide health, power, alternate power and class resources, class color
and bar text. Choose **Always** to allow the display to appear when you lose health
out of combat. PhalkTools saves the settings and reapplies them when you enter
the game or change layouts. Changes made in combat are applied afterward.
Position is controlled in Edit Mode. Custom bar spacing takes priority over
Padding. These controls work even when customization is disabled.

- **Hide at full health out of combat:** hides the entire display when your
  health is full; it reappears when you lose health or enter combat.
- **Borders:** WoW Default, No borders, Thin black or Thick black.
- **Texture:** WoW Default, Flat, Smooth, Raid Bar, Gradient, Glossy, Satin,
  Metallic, Striped or Beveled. The six new textures are included in the addon.
- **Custom bar spacing:** enables a 0-32 pixel adjustment between health, power,
  alternate power and class resources. The value represents the actual distance
  between frames; borders and shadows may occupy part of it. Uncheck to restore
  the spacing set in WoW.

Appearance changes affect the health and resource bars while preserving their
colors. Disabling the module restores the original appearance and opacity.
The display remains visible in Edit Mode. The implementation uses the new
`PersonalResourceDisplayFrame`; hiding uses `UnitHealthPercent` with an opacity
curve compatible with the current API's secret health values.

## Buff Reminders

Reminders come exclusively from the list you create. The list starts empty;
no spells are added automatically. Existing buff entries are preserved.
Only learned abilities with missing effects are shown. Left-click to cast the
buff on yourself, using the localized spell name.

The panel displays a **vertical list**, with one effect per row, an icon, its name
and a clickable cast button. Long lists can be scrolled. Drag the title or
right-drag a reminder to move the panel. Sound is optional.

To add buffs, open **`/pt buffs`** or **Buff Reminders > Edit list** in the settings.
Enter a spell name in the game language or its ID and click **Add**. Uncheck
buffs to pause them or click **Remove** to delete them.

The list is saved between sessions. Reminders work for any class and only appear
for learned spells that are missing from you. Choose buff spells that can be
cast on yourself; clicking casts the same spell you added. Ranks with the same
name are recognized as the same effect. Tracking abilities added to the list
are also checked against the minimap tracking state.

The buttons use `SecureActionButtonTemplate`, and the panel is hidden in combat
by a secure visibility driver. Checks and settings changes resume after combat.

The herb glow module was removed. During an update, its soft-target settings
are restored if they still match the values applied by the addon.

## Unit Frames

In `/pt`, enable **Unit Frames** and open the corresponding subcategory.
The module styles the player, target, target of target and focus frames (where
supported by the client), with individual selection. It is disabled by default.
Target of Target uses the shared texture, color and border settings. With the
portrait removed, its bars use compact dimensions derived from the shared size
settings to fit the native button and leave room for auras and the cast bar.
Its visibility still follows the game's Target of Target option.

- **Remove portrait and circular frame:** a rectangular layout with the name
  and level above the bars. Preserves the original buttons and menus.
- **Borders and Texture:** independent unit frame settings, separate from the
  Personal Resource Display.
- Adjustable width, health and power heights, and spacing, with or without portraits.
- **Segmented target combo points:** replaces the native circular indicators with
  a compact red horizontal row below the target bars. Fills left to right and
  highlights maximum points; follows the native target-bound combo state.
- Preserves native unit frame text, values, PvP faction and prestige indicators, buffs and update routines.
- Portrait hiding is reapplied after target and focus frame updates, including while in combat. Disabling restores the saved mask, texture, position and visibility state.
- With portraits hidden, status indicators use fixed header slots above the name:
  PvP/prestige, combat/rest, leadership, role, ready check, raid marker and target
  classification. Aura rows above the frame leave space for this header.

## Texture Bars

The independent **Texture Bars** module applies a selected fill texture to
Blizzard player, target, focus and target of target bars, plus the player,
target and focus cast bars. Choose each bar separately. It can style the
original unit bars when Unit Frames is off; when Unit Frames owns a bar, that
module's texture setting takes precedence. Blizzard's native cast bars can be
textured without enabling Unit Frames. Disabling Texture Bars restores each
selected bar's prior texture and coordinates.
- Shared icon sizing and spacing for player, target and focus auras, with native target aura filtering.
  Does not process protected health or power values.
- Position is controlled in Edit Mode. Changes made in combat are applied afterward.
  Disabling the module or an individual unit restores its previous appearance.

### Unit frame colors

Neutral textures are tinted with the class color (optional), with green as a
fallback for health, and the corresponding power color (mana, energy, rage, etc.).
The style is reapplied when WoW replaces the texture or color, including during
combat, without invoking Blizzard's bar value reading or update routines.

## Action Bars

In `/pt`, enable **Action Bars** and open the subcategory of the same name.
The module is disabled by default and has settings independent of the Personal
Resource Display and unit frames.

- Select individual groups: main, additional, pet and stance/form bars.
- Original, no, thin or thick borders; black, gold or class-colored borders.
- Glossy or satin finishes, icon zoom and removal of decorative art.
- Scale, opacity, keybinds, macro names, counts and text size.
- Position, rows and spacing remain controlled in WoW Edit Mode.
- Preserves the original buttons, actions, keybinds, ability glows and cooldowns.
  Changes made in combat are applied afterward; disabling restores the previous look.

In the portraitless unit frame layout, the circular resting effect is hidden
so it does not overlap the bars. Experimental nameplate anchoring was removed.

### Glossy button finishes

**Icon finish** offers Classic Glossy, Convex Glass, Faceted Crystal, Mirror
Lacquer, Chrome, Obsidian and Satin. **Finish intensity** ranges from 0 to 100%
(default 75%). Mirror Lacquer and Convex Glass at 80-100% provide stronger
reflections.

Original textures in `Media/Buttons` combine translucent shadows and alpha-blended
reflections in separate layers, inspired by the gloss/shadow concept of Masque
skins. They do not depend on Masque or copy its files. They are generated using
`python tools/generate_button_finishes.py`; personal resource and unit frame
bar textures remain independent. Cooldowns and text remain above the button finish.

Resting in portraitless unit frames is indicated by a small **zzz** in the
header, between the name and level, above the bars. The portrait circle and
flipbook animation are suppressed even after native updates. The indicator
tracks entering and leaving resting areas and disappears in combat. Disabling
the style restores the original Blizzard art.

**Corner radius** in Action Bars sets the radius as a percentage of icon size:
0% square, 10% subtle, 25% rounded and 50% circular. Icons, backgrounds, highlights
and finishes use the same mask; thin and thick borders follow the radius.
A radius above zero replaces the default border with a simple outline.
Original masks are restored when disabled. Generator:
`python tools/generate_button_shapes.py`.

Action bar scale is only written when it actually changes. Slot and form
updates do not reset the setting; native scale resets out of combat are corrected
immediately, without waiting for a timer. Edit Mode can still change the base scale.

Finishes use smoothly blended reflections without white lines around the perimeter.
The sheen has its own inner mask and does not reach the outer corners. Borders
and masks use gradual antialiasing to reduce fringes at small sizes and different scales.

Button hover uses a soft gold highlight with the same radius as the icon,
replacing the square frame of the original atlas. WoW still controls when
the highlight appears. Disabling restores the original texture, anchors and colors.

### Player frame buffs

In **Unit Frames**, **Show player buffs** displays up to 40 helpful effects above
the name, with hover tooltips, stacks and duration indicators when available.
Size and spacing have their own controls; additional rows grow upward. Updates
during combat without creating buttons or moving the protected frame. Does not
modify the global buff panel or the effects shown on the target frame.

**Custom color > Choose color...** opens the native WoW color picker for button
borders, with a preview and hexadecimal input. Cancel restores the previous
color and mode. The inner masks account for border thickness and overlap the opaque inner edge
to avoid a transparent seam between the icon and outline. Reflections remain
inset from the edge.

In the portraitless style, the PvP symbol appears in the header next to the
name, with the player timer immediately to its right. The name reserves space
according to the visibility of these indicators, keeping the level and resting
indicator separate. The original WoW timer continues to handle the countdown.


## Nameplates

In /pt, enable **Nameplates** and open its subcategory. Choose friendly
and/or enemy nameplates, a health bar texture, and default, hidden, thin
or thick borders. The optional size control uses the native global WoW
size setting, so click areas and stacking stay consistent. Disabling the
module restores the previous appearance and size setting.

Native health values, reaction and threat colors, name visibility,
selection indicators, and cast bars are preserved. Restricted nameplates
retain their native appearance. The module also respects the native
visibility and opacity of health bars.

Incoming healing uses the selected health texture as well. The style is
reapplied after native layout changes and when nameplates are reused. The
friendly/enemy options control which visible nameplates are styled; WoW
continues to control whether those nameplates are shown. If a cosmetic
operation fails, a diagnostic prefixed with PhalkTools Nameplates appears
in chat instead of being silently ignored.

**Show combo points on target nameplate** adds a compact point row to your
current target's nameplate and updates it as combo points change.
