local _, ns = ...

local combatSettings
local featureSettings = {}

function ns.OpenCombatSettings()
    if combatSettings and combatSettings:IsShown() then
        combatSettings:Hide()
        return
    end
    if not combatSettings then
        local panel = CreateFrame("Frame", "PhalkToolsCombatSettings", UIParent, "BackdropTemplate")
        panel:SetSize(385, 90 + #featureSettings * 28)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("DIALOG")
        panel:EnableMouse(true)
        panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        panel:SetBackdropColor(0.04, 0.04, 0.05, 0.98)
        local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 18, -16)
        title:SetText("PhalkTools")
        local help = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
        help:SetText("Alterações são aplicadas ao sair de combate.")
        local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT")
        close:SetScript("OnClick", function() panel:Hide() end)
        panel.rows = {}
        for i, feature in ipairs(featureSettings) do
            local row = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -62 - (i - 1) * 28)
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", row, "RIGHT", 4, 0)
            label:SetText(feature.label)
            row:SetScript("OnClick", function(self)
                feature.setting:SetValue(self:GetChecked() == true)
            end)
            panel.rows[i] = row
        end
        table.insert(UISpecialFrames, panel:GetName())
        combatSettings = panel
    end
    for i, feature in ipairs(featureSettings) do
        combatSettings.rows[i]:SetChecked(ns.db[feature.key])
    end
    combatSettings:Show()
end

-- A single Settings object backs each module's checkbox on both the overview
-- and its own tab. Switching in either place immediately updates the other.
function ns.RegisterSettings()
    if not (Settings and Settings.RegisterVerticalLayoutCategory
        and Settings.RegisterVerticalLayoutSubcategory and Settings.RegisterAddOnCategory) then return end

    local main, mainLayout = Settings.RegisterVerticalLayoutCategory("PhalkTools")
    local reminders, remindersLayout = Settings.RegisterVerticalLayoutSubcategory(main, "Buff Reminders")
    local personal, personalLayout = Settings.RegisterVerticalLayoutSubcategory(main, "Personal Resource Display")

    local actions, actionsLayout = Settings.RegisterVerticalLayoutSubcategory(main, "Action Bars")
    local units, unitsLayout = Settings.RegisterVerticalLayoutSubcategory(main, "Unit Frames")
    local textureBars, textureBarsLayout = Settings.RegisterVerticalLayoutSubcategory(main, "Texture Bars")
    local plates, platesLayout = Settings.RegisterVerticalLayoutSubcategory(main, "Nameplates")
    local meter, meterLayout = Settings.RegisterVerticalLayoutSubcategory(main, "Damage Meter")
    local chat, chatLayout = Settings.RegisterVerticalLayoutSubcategory(main, "Chat")

    local function Header(layout, title)
        if CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title))
        end
    end

    local function Register(category, key, label)
        local setting = Settings.RegisterAddOnSetting(category, "PhalkTools_" .. key, key,
            ns.db, type(ns.defaults[key]), label, ns.defaults[key])
        setting:SetValueChangedCallback(function() ns.Refresh() end)
        if category == main and type(ns.defaults[key]) == "boolean" then
            featureSettings[#featureSettings + 1] = { key = key, label = label, setting = setting }
        end
        return setting
    end

    local function Checkbox(category, key, label, help)
        local setting = Register(category, key, label)
        Settings.CreateCheckbox(category, setting, help)
        return setting
    end

    local function Dropdown(category, key, label, values, help)
        local setting = Register(category, key, label)
        Settings.CreateDropdown(category, setting, function()
            local options = Settings.CreateControlTextContainer()
            for _, entry in ipairs(values) do options:Add(entry[1], entry[2]) end
            return options:GetData()
        end, help)
    end

    local function PixelSlider(category, key, label, low, high, help)
        local setting = Register(category, key, label)
        local options = Settings.CreateSliderOptions(low, high, 1)
        if options.SetLabelFormatter and MinimalSliderWithSteppersMixin then
            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
                function(value) return tostring(math.floor(value)) .. " px" end)
        end
        Settings.CreateSlider(category, setting, options, help)
    end

    Header(mainLayout, "FEATURES | Check to enable")
    local remindersOn = Checkbox(main, "enabledReminders", "Buff Reminders",
        "Shows buffs that need to be reapplied to yourself. Open the subcategory to customize.")
    local personalOn = Checkbox(main, "enabledPersonalResource", "Personal Resource Display",
        "Customizes the default WoW Personal Resource Display. Open the subcategory to customize.")

    local unitsOn = Checkbox(main, "enabledUnitFrames", "Unit Frames",
        "Applies rectangular bars to the player, target, target of target and focus. Open the subcategory to customize.")
    Header(unitsLayout, "UNIT FRAMES")
    Settings.CreateCheckbox(units, unitsOn, "Enables styling for the original Blizzard unit frames.")
    Checkbox(units, "unitFramesPlayer", "Player", "Applies the style to the player frame.")
    Checkbox(units, "unitFramesPlayerBuffs", "Show player buffs",
        "Shows helpful effects above the name, like the target frame. Includes tooltips, stacks and cooldowns when available.")
    Checkbox(units, "unitFramesMatchBuffs", "Match target and focus aura style",
        "Uses the same icon size and spacing as player buffs. All three frames show auras above their bars using the client aura renderer.")
    PixelSlider(units, "unitFramesBuffSize", "Buff size", 14, 36, "Shared size of player, target and focus aura icons.")
    PixelSlider(units, "unitFramesBuffSpacing", "Buff spacing", 0, 10, "Shared distance between icons. Additional rows grow upward.")
    Checkbox(units, "unitFramesTarget", "Target", "Applies the style to the target frame.")
    Checkbox(units, "unitFramesComboPoints", "Personal resource combo points",
        "Arranges the native combo points below the target bars using the personal resource display style and animations.")
    Checkbox(units, "unitFramesTargetOfTarget", "Target of Target",
        "Applies the same style to the compact target of target frame. Uses the game's Target of Target visibility setting.")
    Checkbox(units, "unitFramesFocus", "Focus", "Applies the style to the focus frame, when available in the client.")
    Checkbox(units, "unitFramesHidePortrait", "Remove portrait and circular frame",
        "Hides the portrait, circle and decorative art while keeping the name, level and functional indicators.")
    Checkbox(units, "unitFramesPortrait3D", "Side portraits",
        "Shows a side portrait beside the player and target bars when the native circular portrait is removed.")
    Dropdown(units, "unitFramesPortraitMode", "Side portrait mode", {
        { "3d", "3D model" }, { "2d", "2D portrait" },
    }, "3D shows the animated unit model. 2D uses a portrait texture that follows the corner radius exactly.")
    PixelSlider(units, "unitFramesPortrait3DSize", "Side portrait size", 32, 80,
        "Size of the player and target side portraits.")
    PixelSlider(units, "unitFramesPortrait3DRadius", "Side portrait corner radius", 0, 50,
        "Rounds the portrait frame corners; 50 makes it circular. Uses the unit frame border style.")
    Checkbox(units, "unitFramesClassColor", "Class-colored health bar",
        "Uses the class color when known, or green otherwise. Power uses the corresponding mana, energy or rage color.")
    Checkbox(units, "unitFramesPlayerShadow", "Player shadow", "Adds a soft black shadow around the player bars.")
    Checkbox(units, "unitFramesTargetShadow", "Target shadow", "Adds a soft black shadow around the target bars.")
    Checkbox(units, "unitFramesFocusShadow", "Focus shadow", "Adds a soft black shadow around the focus bars.")
    Checkbox(units, "unitFramesTargetOfTargetShadow", "Target of target shadow", "Adds a soft black shadow around the target of target bars.")
    Dropdown(units, "unitFramesBorder", "Borders", {
        { "default", "WoW Default" }, { "none", "No borders" },
        { "thin", "Thin black" }, { "thick", "Thick black" },
    }, "Choose the unit frame border.")
    Dropdown(units, "unitFramesTexture", "Texture", {
        { "default", "WoW Default" }, { "flat", "Flat" }, { "smooth", "Smooth" },
        { "raid", "Raid Bar" }, { "gradient", "Gradient" }, { "gloss", "Glossy" },
        { "soft", "Satin" }, { "metal", "Metallic" }, { "striped", "Striped" }, { "beveled", "Beveled" },
    }, "Choose the unit frame bar texture.")
    PixelSlider(units, "unitFramesWidth", "Bar width", 100, 320, "Width of the health and power bars.")
    PixelSlider(units, "unitFramesHealthHeight", "Health bar height", 10, 40, "Height of the health bar.")
    PixelSlider(units, "unitFramesPowerHeight", "Power bar height", 6, 24, "Height of the power bar.")
    PixelSlider(units, "unitFramesSpacing", "Bar spacing", 0, 20, "Distance between the health and power bars.")
    Header(unitsLayout, "Position is controlled in Edit Mode. Changes made in combat are applied afterward. Disabling restores the previous appearance.")

    local textureBarsOn = Checkbox(main, "enabledTextureBars", "Texture Bars",
        "Applies a separate bar texture to selected Blizzard unit and cast bars. Open the subcategory to choose bars.")
    Header(textureBarsLayout, "TEXTURE BARS")
    Settings.CreateCheckbox(textureBars, textureBarsOn,
        "Enables texture styling independently of the Unit Frames module.")
    Dropdown(textureBars, "textureBarsTexture", "Texture", {
        { "flat", "Flat" }, { "smooth", "Smooth" }, { "raid", "Raid Bar" },
        { "gradient", "Gradient" }, { "gloss", "Glossy" }, { "soft", "Satin" },
        { "metal", "Metallic" }, { "striped", "Striped" }, { "beveled", "Beveled" },
    }, "Choose the fill texture applied to selected bars.")
    Header(textureBarsLayout, "UNIT BARS")
    for _, option in ipairs({
        { "textureBarsPlayerHealth", "Player health" }, { "textureBarsPlayerPower", "Player power" },
        { "textureBarsTargetHealth", "Target health" }, { "textureBarsTargetPower", "Target power" },
        { "textureBarsFocusHealth", "Focus health" }, { "textureBarsFocusPower", "Focus power" },
        { "textureBarsTargetOfTargetHealth", "Target of target health" },
    }) do Checkbox(textureBars, option[1], option[2], "Applies the selected texture to this Blizzard status bar.") end
    Header(textureBarsLayout, "CAST BARS")
    for _, option in ipairs({
        { "textureBarsPlayerCast", "Player cast bar" }, { "textureBarsTargetCast", "Target cast bar" },
        { "textureBarsFocusCast", "Focus cast bar" },
    }) do Checkbox(textureBars, option[1], option[2], "Applies the selected texture to this Blizzard cast bar.") end
    Header(textureBarsLayout, "Changes made in combat are applied when combat ends.")

    local actionsOn = Checkbox(main, "enabledActionBars", "Action Bars",
        "Customizes action button appearance. Open the subcategory to adjust.")
    Header(actionsLayout, "ACTION BARS")
    Settings.CreateCheckbox(actions, actionsOn, "Enables action bar styling independently of the other features.")
    Checkbox(actions, "actionBarsMain", "Main action bar", "Applies the style to the main action bar.")
    Checkbox(actions, "actionBarsExtra", "Additional action bars", "Applies the style to the additional WoW action bars.")
    Checkbox(actions, "actionBarsPet", "Pet action bar", "Applies the style to pet action buttons.")
    Checkbox(actions, "actionBarsStance", "Stances and forms", "Applies the style to stance and shapeshift buttons.")
    Dropdown(actions, "actionBarsBorder", "Borders", {
        { "default", "WoW Default" }, { "none", "No borders" },
        { "thin", "Thin" }, { "thick", "Thick" },
    }, "Choose the border for action buttons, bags and the micro menu.")
    Dropdown(actions, "actionBarsBorderColor", "Border color", {
        { "black", "Black" }, { "class", "Class color" }, { "gold", "Gold" },
        { "custom", "Custom" },
    }, "Choose a preset color or use the picker below for any color.")
    if CreateSettingsButtonInitializer then
        actionsLayout:AddInitializer(CreateSettingsButtonInitializer("Custom color", "Choose color...",
            ns.OpenActionBorderColorPicker, "Opens the WoW color picker with hexadecimal input and a preview. Cancel restores the previous color.", false))
    end
    Dropdown(actions, "actionBarsFinish", "Icon finish", {
        { "none", "No effect" }, { "gloss", "Classic Glossy" },
        { "glass", "Convex Glass" }, { "crystal", "Faceted Crystal" },
        { "lacquer", "Mirror Lacquer" }, { "chrome", "Chrome" },
        { "obsidian", "Obsidian" }, { "soft", "Satin" },
    }, "Layered reflections, specular highlights and shadows inspired by Masque skin finishes.")
    Checkbox(actions, "actionBarsHideArt", "Remove decorative art", "Hides the decorative frames and dividers on the main action bar, bags and micro menu.")
    Checkbox(actions, "actionBarsHotkeys", "Show keybinds", "Shows the keys assigned to each button.")
    Checkbox(actions, "actionBarsCooldownHotkeys", "Show keybinds in Cooldown Manager",
        "Shows the key assigned to the matching action bar spell on Cooldown Manager icons.")
    Checkbox(actions, "actionBarsMacros", "Show macro names", "Shows the name beneath each macro.")
    Checkbox(actions, "actionBarsCounts", "Show counts", "Shows item counts and charges.")
    local function ActionSlider(key, label, low, high, suffix, help)
        local setting = Register(actions, key, label)
        local options = Settings.CreateSliderOptions(low, high, 1)
        if options.SetLabelFormatter and MinimalSliderWithSteppersMixin then
            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
                function(value) return tostring(math.floor(value)) .. suffix end)
        end
        Settings.CreateSlider(actions, setting, options, help)
    end
    ActionSlider("actionBarsRadius", "Corner radius", 0, 50, "%",
        "Radius relative to icon size: 0% square, 10% subtle, 25% rounded, 50% circular. Also affects the finish and border, including bags and micro menu buttons; a radius above zero replaces the original frame with a simple border.")
    ActionSlider("actionBarsFinishIntensity", "Finish intensity", 0, 100, "%",
        "Controls the shine and depth of the finish. Try Mirror Lacquer or Convex Glass at 70% to 100%.")
    ActionSlider("actionBarsScale", "Action bar scale", 60, 150, "%", "Scale relative to the size set in WoW.")
    ActionSlider("actionBarsOpacity", "Opacity", 50, 100, "%", "Opacity of the action buttons.")
    ActionSlider("actionBarsZoom", "Icon zoom", 0, 15, "%", "Crops the inner margins of spell icons.")
    ActionSlider("actionBarsFontSize", "Text size", 8, 18, " px", "Size of keybinds, names and counts.")
    Header(actionsLayout, "Position, rows and spacing are controlled in WoW Edit Mode. Changes made in combat are applied afterward. Disabling restores the previous appearance.")

    local meterOn = Checkbox(main, "enabledDamageMeter", "Damage Meter",
        "Customizes Blizzard's Damage Meter. Open the subcategory to adjust its appearance and unlock movement.")
    Header(meterLayout, "DAMAGE METER")
    Settings.CreateCheckbox(meter, meterOn, "Enables Damage Meter styling and settings.")
    Checkbox(meter, "damageMeterLockMenu", "Add Lock / Unlock to the options context menu",
        "Adds Lock / Unlock to the Damage Meter options menu.")
    Dropdown(meter, "damageMeterStyle", "Visual style", {
        { "default", "WoW Default" }, { "minimal", "Thin" }, { "bordered", "Bordered" },
    }, "Select the built-in Damage Meter presentation style.")
    Dropdown(meter, "damageMeterBorder", "Bar borders", {
        { "default", "WoW Default" }, { "none", "No borders" },
        { "thin", "Thin black" }, { "thick", "Thick black" },
    }, "Choose the outline around each Damage Meter bar.")
    Dropdown(meter, "damageMeterTexture", "Bar texture", {
        { "default", "WoW Default" }, { "flat", "Flat" }, { "smooth", "Smooth" },
        { "raid", "Raid Bar" }, { "gradient", "Gradient" }, { "gloss", "Glossy" },
        { "soft", "Satin" }, { "metal", "Metallic" }, { "striped", "Striped" }, { "beveled", "Beveled" },
    }, "Changes the fill texture of Damage Meter rows.")
    Checkbox(meter, "damageMeterClassColors", "Class colors", "Uses class colors for player rows.")
    PixelSlider(meter, "damageMeterBarHeight", "Bar height", 12, 45, "Sets the height of Damage Meter rows.")
    Checkbox(meter, "damageMeterIcons", "Show bar icons", "Shows spell and ability icons in Damage Meter rows.")
    PixelSlider(meter, "damageMeterBackground", "Background opacity", 0, 100,
        "Adjusts the Damage Meter background transparency.")
    PixelSlider(meter, "damageMeterOpacity", "Window opacity", 0, 100,
        "Adjusts the opacity of the Damage Meter window.")
    PixelSlider(meter, "damageMeterSpacing", "Bar spacing", 0, 12,
        "Sets the spacing between Damage Meter rows.")
    PixelSlider(meter, "damageMeterTextSize", "Text size", 8, 20,
        "Sets the text size used by Damage Meter rows.")
    Header(meterLayout, "Changes made in combat are applied when combat ends.")

    Header(chatLayout, "CHAT WINDOW")
    local chatOn = Checkbox(main, "chatLockMenu", "Chat", "Restores Lock / Unlock in the chat tab menu.")
    Settings.CreateCheckbox(chat, chatOn, "Restore old chat Lock / Unlock")
    Checkbox(chat, "chatCopyText", "Copy chat text",
        "Adds Copy chat text to the tab menu. Select text and press Ctrl+C.")
    Checkbox(chat, "chatKeepHistory", "Keep chat history for 24 hours",
        "Restores saved messages in each chat tab on login or reload. Turning this off clears the saved history.")

    local platesOn = Checkbox(main, "enabledNameplates", "Nameplates",
        "Customizes the original nameplates above units. Open the subcategory to customize.")
    Header(platesLayout, "NAMEPLATES")
    Settings.CreateCheckbox(plates, platesOn, "Enables nameplate styling independently of other features.")
    Checkbox(plates, "nameplatesEnemy", "Enemy nameplates", "Styles hostile and neutral units.")
    Checkbox(plates, "nameplatesFriendly", "Friendly nameplates", "Styles friendly units when the game permits customization.")
    Dropdown(plates, "nameplatesTexture", "Health bar texture", {
        { "default", "WoW Default" }, { "flat", "Flat" }, { "smooth", "Smooth" },
        { "raid", "Raid Bar" }, { "gradient", "Gradient" }, { "gloss", "Glossy" },
        { "soft", "Satin" }, { "metal", "Metallic" }, { "striped", "Striped" }, { "beveled", "Beveled" },
    }, "Changes the bar finish while preserving native health, reaction, threat and class colors.")
    Dropdown(plates, "nameplatesBorder", "Borders", {
        { "default", "WoW Default" }, { "none", "No borders" },
        { "thin", "Thin black" }, { "thick", "Thick black" },
    }, "Changes the health bar border while retaining the target selection highlight.")
    Dropdown(plates, "nameplatesSize", "Nameplate size", ns.GetNameplateSizeOptions(),
        "Uses the native global nameplate size setting for consistent spacing and click areas. WoW Default restores the previous setting.")
    Checkbox(plates, "nameplatesHealthHighlight", "Health bar selection outline",
        "Shows the native target and focus outline around the health bar.")
    Header(platesLayout, "LEVEL INDICATOR")
    Checkbox(plates, "nameplatesLevelVisible", "Show level indicator",
        "Shows the native level or skull badge whenever the game displays it.")
    Dropdown(plates, "nameplatesLevelStyle", "Level badge style", {
        { "default", "WoW Default" }, { "match", "Match health bar border" },
        { "none", "No border" }, { "thin", "Thin border" },
        { "thick", "Thick border" }, { "text", "Text only" },
    }, "Customizes the level badge background and border while preserving difficulty colors and skulls.")
    Checkbox(plates, "nameplatesLevelHighlight", "Level badge selection outline",
        "Shows the native target and focus outline around the level badge.")
    if CreateSettingsButtonInitializer then
        platesLayout:AddInitializer(CreateSettingsButtonInitializer("Level background", "Choose color...",
            function() ns.OpenNameplateLevelColorPicker("Background") end,
            "Background color for custom badge styles.", false))
        platesLayout:AddInitializer(CreateSettingsButtonInitializer("Level border color", "Choose color...",
            function() ns.OpenNameplateLevelColorPicker("Border") end,
            "Border color for custom badge styles.", false))
    end
    PixelSlider(plates, "nameplatesLevelWidth", "Level badge width", 0, 48,
        "0 uses the native width. Positive values set the width in pixels.")
    PixelSlider(plates, "nameplatesLevelOffsetX", "Level horizontal offset", -12, 24,
        "Moves the badge horizontally relative to its native position.")
    PixelSlider(plates, "nameplatesLevelOffsetY", "Level vertical offset", -16, 16,
        "Moves the badge vertically relative to its native position.")
    PixelSlider(plates, "nameplatesLevelFontSize", "Level text size", 0, 24,
        "0 uses the native font size. Positive values resize the level text.")
    Header(platesLayout, "UNIT NAME")
    PixelSlider(plates, "nameplatesNameFontSize", "Name text size", 0, 32,
        "0 uses the native name size. Positive values resize the unit name.")
    Header(platesLayout, "COMBO POINTS")
    Checkbox(plates, "nameplatesComboPoints", "Show combo points on target nameplate",
        "Shows your current combo points as a compact row on the current target's nameplate.")
    Header(platesLayout, "Restricted nameplates retain their native appearance. Geometry changes are applied after combat.")

    Header(personalLayout, "PERSONAL RESOURCE DISPLAY")
    Settings.CreateCheckbox(personal, personalOn, "Enables customization of the default Personal Resource Display.")
    Checkbox(personal, "personalResourceHideFull", "Hide at full health out of combat",
        "Hides the entire Personal Resource Display when you are at full health and out of combat. It reappears when you lose health or enter combat.")
    Dropdown(personal, "personalResourceBorder", "Borders", {
        { "default", "WoW Default" }, { "none", "No borders" },
        { "thin", "Thin black" }, { "thick", "Thick black" },
    }, "Choose the border of the health and resource bars.")
    Dropdown(personal, "personalResourceTexture", "Texture", {
        { "default", "WoW Default" }, { "flat", "Flat" },
        { "smooth", "Smooth" }, { "raid", "Raid Bar" },
        { "gradient", "Gradient" }, { "gloss", "Glossy" },
        { "soft", "Satin" }, { "metal", "Metallic" },
        { "striped", "Striped" }, { "beveled", "Beveled" },
    }, "Choose the health and resource bar texture while preserving the game colors.")
    PixelSlider(personal, "personalResourceSpacing", "Bar spacing", 0, 32,
        "Distance between bars in UI pixels, from 0 to 32. Borders and shadows may occupy part of this space.")
    Header(personalLayout, "DEFAULT WOW SETTINGS")
    local function Native(key, label, fallback)
        ns.db.personalResourceNative = ns.db.personalResourceNative or {}
        local choices = ns.db.personalResourceNative
        local initial = ns.GetPersonalNative(key, fallback)
        local setting = Settings.RegisterAddOnSetting(personal, "PhalkTools_Native_" .. key,
            key, choices, type(fallback), label, initial)
        setting:SetValueChangedCallback(function(_, value)
            ns.SetPersonalNative(key, value)
        end)
        return setting
    end
    Settings.CreateCheckbox(personal, Native("Enabled", "Enable Personal Resource Display", false),
        "Enables or disables the default WoW display independently of the customization above.")
    for _, option in ipairs({
        { "Size", "Size", 100, 70, 150, 10, "%" },
        { "BarWidth", "Bar width", 100, 50, 150, 10, "%" },
        { "HealthBarHeight", "Health bar height", 20, 10, 30, 1, " px" },
        { "PowerBarHeight", "Power bar height", 10, 10, 30, 1, " px" },
        { "Padding", "Padding", 0, 0, 10, 1, " px" },
        { "Opacity", "Opacity", 100, 50, 100, 1, "%" },
    }) do
        local suffix = option[7]
        local options = Settings.CreateSliderOptions(option[4], option[5], option[6])
        if options.SetLabelFormatter and MinimalSliderWithSteppersMixin then
            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
                function(value) return tostring(math.floor(value)) .. suffix end)
        end
        Settings.CreateSlider(personal, Native(option[1], option[2], option[3]), options,
            option[1] == "Padding" and "Default WoW padding. Custom bar spacing above takes priority when enabled."
                or "Applied to the default WoW display. Changes made in combat are applied afterward.")
    end
    local visibility = Enum.PersonalResourceDisplayVisibleSetting
    Settings.CreateDropdown(personal, Native("VisibleSetting", "Visibility", visibility.Always), function()
        local options = Settings.CreateControlTextContainer()
        options:Add(visibility.Always, "Always")
        options:Add(visibility.InCombat, "In Combat")
        options:Add(visibility.Hidden, "Hidden")
        return options:GetData()
    end, "Choose Always to allow the display to appear when you lose health out of combat.")
    for _, option in ipairs({
        { "HideHealth", "Hide health bar", false },
        { "HidePower", "Hide power bar", false },
        { "HideAltPower", "Hide alternate power bar", false },
        { "HideClassInfo", "Hide class resources", false },
        { "ShowClassColor", "Show class color", false },
        { "ShowBarText", "Show bar text", true },
    }) do
        Settings.CreateCheckbox(personal, Native(option[1], option[2], option[3]),
            "Controls the Personal Resource Display. Available resources depend on class and specialization.")
    end
    Header(personalLayout, "PhalkTools saves these settings and reapplies them when entering the game or changing layouts. Position is controlled in WoW Edit Mode.")

    Header(remindersLayout, "BUFF REMINDERS")
    Settings.CreateCheckbox(reminders, remindersOn,
        "Enables or disables all reminders. This option also appears on the main page.")
    if CreateSettingsButtonInitializer then
        remindersLayout:AddInitializer(CreateSettingsButtonInitializer("Buff list", "Edit list",
            ns.OpenReminderEditor, "Add buffs by name or ID, pause effects and remove reminders from the list.", false))
    end
    Checkbox(reminders, "reminderSound", "Sound for missing buffs",
        "Plays a sound when a new missing buff is detected, with a minimum interval of 90 seconds.")
    Header(remindersLayout, "Left-click to cast. Drag the title or right-drag a reminder to move the panel. Changes made during combat are applied afterward.")

    Settings.RegisterAddOnCategory(main)
    ns.categoryID = main:GetID()
end
