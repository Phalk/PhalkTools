local ADDON, ns = ...

ns.defaults = {
    enabledReminders = true,
    reminderSound = false,
    reminderX = 0,
    reminderY = 190,
    enabledActionBars = false,
    actionBarsMain = true,
    actionBarsExtra = true,
    actionBarsPet = true,
    actionBarsStance = true,
    actionBarsBorder = "thin",
    actionBarsRadius = 0,
    actionBarsBorderColor = "black",
    actionBarsBorderR = 0,
    actionBarsBorderG = 0,
    actionBarsBorderB = 0,
    actionBarsFinish = "none",
    actionBarsFinishIntensity = 75,
    actionBarsHideArt = true,
    actionBarsHotkeys = true,
    actionBarsCooldownHotkeys = true,
    actionBarsMacros = false,
    actionBarsCounts = true,
    actionBarsScale = 100,
    actionBarsOpacity = 100,
    actionBarsZoom = 5,
    actionBarsFontSize = 12,
    enabledUnitFrames = false,
    unitFramesPlayer = true,
    unitFramesPlayerBuffs = true,
    unitFramesMatchBuffs = true,
    unitFramesBuffSize = 20,
    unitFramesBuffSpacing = 3,
    unitFramesTarget = true,
    unitFramesComboPoints = true,
    unitFramesTargetOfTarget = true,
    unitFramesFocus = true,
    unitFramesHidePortrait = true,
    unitFramesPortrait3D = false,
    unitFramesPortraitMode = "3d",
    unitFramesPortrait3DSize = 48,
    unitFramesPortrait3DRadius = 0,
    unitFramesClassColor = true,
    unitFramesPlayerShadow = true,
    unitFramesTargetShadow = true,
    unitFramesFocusShadow = true,
    unitFramesTargetOfTargetShadow = false,
    unitFramesTexture = "raid",
    unitFramesBorder = "thin",
    unitFramesWidth = 200,
    unitFramesHealthHeight = 20,
    unitFramesPowerHeight = 10,
    unitFramesSpacing = 4,
    enabledTextureBars = false,
    textureBarsTexture = "raid",
    textureBarsPlayerHealth = true,
    textureBarsPlayerPower = true,
    textureBarsTargetHealth = true,
    textureBarsTargetPower = true,
    textureBarsFocusHealth = true,
    textureBarsFocusPower = true,
    textureBarsTargetOfTargetHealth = false,
    textureBarsPlayerCast = true,
    textureBarsTargetCast = true,
    textureBarsFocusCast = true,
    textureBarsDamageMeter = false,
    textureBarsPlayerHealthTexture = "global",
    textureBarsPlayerPowerTexture = "global",
    textureBarsTargetHealthTexture = "global",
    textureBarsTargetPowerTexture = "global",
    textureBarsFocusHealthTexture = "global",
    textureBarsFocusPowerTexture = "global",
    textureBarsTargetOfTargetHealthTexture = "global",
    textureBarsPlayerCastTexture = "global",
    textureBarsTargetCastTexture = "global",
    textureBarsFocusCastTexture = "global",
    textureBarsDamageMeterTexture = "global",
    textureBarsPlayerCastCustomColor = false,
    textureBarsPlayerCastColorR = 1,
    textureBarsPlayerCastColorG = 0.7,
    textureBarsPlayerCastColorB = 0,
    textureBarsPlayerHealthHeight = 0,
    textureBarsPlayerPowerHeight = 0,
    textureBarsTargetHealthHeight = 0,
    textureBarsTargetPowerHeight = 0,
    textureBarsFocusHealthHeight = 0,
    textureBarsFocusPowerHeight = 0,
    textureBarsTargetOfTargetHealthHeight = 0,
    textureBarsPlayerCastHeight = 0,
    textureBarsTargetCastHeight = 0,
    textureBarsFocusCastHeight = 0,
    textureBarsPlayerPowerSpacing = -1,
    textureBarsTargetPowerSpacing = -1,
    textureBarsFocusPowerSpacing = -1,
    enabledNameplates = false,
    nameplatesFriendly = true,
    nameplatesEnemy = true,
    nameplatesTexture = "raid",
    nameplatesBorder = "thin",
    nameplatesSize = "default",
    nameplatesHealthHighlight = true,
    nameplatesLevelVisible = true,
    nameplatesLevelStyle = "default",
    nameplatesLevelHighlight = true,
    nameplatesLevelWidth = 0,
    nameplatesLevelOffsetX = 0,
    nameplatesLevelOffsetY = 0,
    nameplatesLevelFontSize = 0,
    nameplatesLevelBackgroundR = 0.025,
    nameplatesLevelBackgroundG = 0.03,
    nameplatesLevelBackgroundB = 0.04,
    nameplatesLevelBorderR = 0,
    nameplatesLevelBorderG = 0,
    nameplatesLevelBorderB = 0,
    nameplatesNameFontSize = 0,
    nameplatesComboPoints = true,
    enabledPersonalResource = false,
    chatUnlocked = false,
    chatLockMenu = true,
    chatCopyText = true,
    chatKeepHistory = false,
    personalResourceHideFull = true,
    personalResourceBorder = "default",
    personalResourceTexture = "default",
    personalResourceSpacing = 4,
}

function ns.Plain(value)
    if value == nil then return false end
    if type(issecretvalue) == "function" and issecretvalue(value) then return false end
    return true
end

function ns.SpellInfo(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and ns.Plain(info) and type(info) == "table" then
            return info.name, info.iconID, info.spellID
        end
    end
    if GetSpellInfo then
        local ok, name, _, icon = pcall(GetSpellInfo, id)
        if ok and ns.Plain(name) then return name, icon end
    end
end

-- nil means the client did not expose a reliable answer.
function ns.KnowsSpell(id)
    local check = C_SpellBook and C_SpellBook.IsSpellKnown or IsSpellKnown
    if not check then return nil end
    local ok, known = pcall(check, id)
    if not ok or not ns.Plain(known) then return nil end
    return known == true
end

-- nil means the spell isn't a tracking ability, or tracking data is unavailable.
function ns.TrackingActive(spellID)
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo) then return nil end
    local ok, count = pcall(C_Minimap.GetNumTrackingTypes)
    if not ok or not ns.Plain(count) or type(count) ~= "number" then return nil end
    for i = 1, count do
        local good, info = pcall(C_Minimap.GetTrackingInfo, i)
        if not good then return nil end
        if info ~= nil and not ns.Plain(info) then return nil end
        if info and ns.Plain(info.spellID) and info.spellID == spellID then
            if not ns.Plain(info.active) then return nil end
            return info.active == true
        end
    end
    return nil
end

function ns.PlayPing()
    if PlaySound and SOUNDKIT then
        PlaySound(SOUNDKIT.MAP_PING or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
end

-- Keep initialization failures isolated so one module cannot remove the settings UI.
local modules = {
    { "Reminders", "InitReminders", "RefreshReminders" },
    { "PersonalResource", "InitPersonalResource", "RefreshPersonalResource" },
    { "UnitFrames", "InitUnitFrames", "RefreshUnitFrames" },
    { "TextureBars", "InitTextureBars", "RefreshTextureBars" },
    { "PlayerBuffs", "InitPlayerFrameBuffs", "RefreshPlayerFrameBuffs" },
    { "ActionBars", "InitActionBars", "RefreshActionBars" },
    { "Chat", "InitChat", "RefreshChat" },
    { "Nameplates", "InitNameplates", "RefreshNameplates" },
}
local initialized = {}

local function RunSafely(label, fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, message = pcall(fn, ...)
    if not ok then
        local diagnostic = "PhalkTools [" .. label .. "]: " .. tostring(message)
        print(diagnostic)
        if geterrorhandler then pcall(geterrorhandler(), diagnostic) end
    end
    return ok
end

local function Start()
    PhalkToolsDB = type(PhalkToolsDB) == "table" and PhalkToolsDB or {}
    ns.db = PhalkToolsDB
    ns.db.enabledDamageMeter = nil
    for key in pairs(ns.db) do
        if type(key) == "string" and (key:match("^damageMeter")
            or (key:match("^textureBarsDamageMeter") and key ~= "textureBarsDamageMeter"
                and key ~= "textureBarsDamageMeterTexture")) then
            ns.db[key] = nil
        end
    end
    if ns.db.realmNamesPreviousValue == "1" and C_CVar then
        local function RestoreRealmNameCVar()
            local ok, current = pcall(C_CVar.GetCVar, "nameplateShowFriendlyRealmName")
            if ok and current == "0" then pcall(C_CVar.SetCVar, "nameplateShowFriendlyRealmName", "1") end
        end
        if InCombatLockdown() then
            local restore = CreateFrame("Frame")
            restore:RegisterEvent("PLAYER_REGEN_ENABLED")
            restore:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                RestoreRealmNameCVar()
            end)
        else
            RestoreRealmNameCVar()
        end
    end
    ns.db.realmNamesPreviousValue = nil
    ns.db.enabledRealmNames = nil
    ns.db.unitFramesUsePersonalStyle = nil
    ns.db.personalResourceFollowNameplate = nil
    ns.db.personalResourceNameplateGap = nil
    ns.db.personalResourceCustomSpacing = nil
    if type(ns.db.customReminders) ~= "table" then ns.db.customReminders = {} end
    if type(ns.db.chatPositions) ~= "table" then ns.db.chatPositions = {} end
    -- Retire the old fixed reminders without inserting them into the user's list.
    ns.db.remindMark, ns.db.remindThorns, ns.db.remindFindHerbs = nil, nil, nil
    for key, value in pairs(ns.defaults) do
        if type(ns.db[key]) ~= type(value) then ns.db[key] = value end
    end
    if ns.db.unitFramesStyleVersion ~= 1 then
        ns.db.unitFramesPlayerShadow = ns.db.unitFramesTargetShadow
        ns.db.unitFramesStyleVersion = 1
    end
    -- One-time cleanup: restore only CVars still equal to the removed module's
    -- last applied value, preserving subsequent changes made by the player.
    local function CleanupHerbSettings()
        local saved, applied = ns.db.herbCvarSaved, ns.db.herbCvarApplied
        if type(saved) == "table" and type(applied) == "table" and C_CVar then
            for _, name in ipairs({ "SoftTargetInteract", "SoftTargetIconGameObject", "SoftTargetIconInteract",
                "SoftTargetLowPriorityIcons", "SoftTargetNameplateInteract", "SoftTargetInteractArc", "SoftTargetInteractRange" }) do
                if saved[name] ~= nil and applied[name] ~= nil then
                    local ok, current = pcall(C_CVar.GetCVar, name)
                    if ok and ns.Plain(current) and (current == applied[name]
                        or (tonumber(current) and tonumber(current) == tonumber(applied[name]))) then
                        pcall(C_CVar.SetCVar, name, saved[name])
                    end
                end
            end
        end
        for _, key in ipairs({ "enabledHerbPing", "herbRadius", "herbSound", "herbVisual", "herbAlertX",
            "herbAlertTop", "herbCvarSaved", "herbCvarApplied" }) do ns.db[key] = nil end
    end
    if InCombatLockdown() then
        local cleanup = CreateFrame("Frame")
        cleanup:RegisterEvent("PLAYER_REGEN_ENABLED")
        cleanup:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            CleanupHerbSettings()
        end)
    else
        CleanupHerbSettings()
    end
    for _, module in ipairs(modules) do
        initialized[module[1]] = RunSafely(module[1] .. " init", ns[module[2]])
    end
    RunSafely("Settings", ns.RegisterSettings)
    ns.Refresh()
end

local pendingRefresh
function ns.Refresh()
    if InCombatLockdown() then
        if not pendingRefresh then
            print("PhalkTools: saia de combate para aplicar as alterações.")
            pendingRefresh = CreateFrame("Frame")
            pendingRefresh:RegisterEvent("PLAYER_REGEN_ENABLED")
            pendingRefresh:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                pendingRefresh = nil
                ns.Refresh()
            end)
        end
        return
    end
    for _, module in ipairs(modules) do
        if initialized[module[1]] then
            RunSafely(module[1] .. " refresh", ns[module[3]], module[1] == "PlayerBuffs" and true or nil)
        end
    end
end

function PhalkTools_Open()
    if InCombatLockdown() and ns.OpenCombatSettings then
        ns.OpenCombatSettings()
        return
    end
    if ns.categoryID and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(ns.categoryID)
    else
        print("PhalkTools: settings unavailable. Check Lua errors and reload the interface.")
    end
end

SLASH_PHALKTOOLS1 = "/phalktools"
SLASH_PHALKTOOLS2 = "/pt"
SlashCmdList.PHALKTOOLS = function(message)
    if message and message:match("^%s*buffs%s*$") then
        ns.OpenReminderEditor()
    elseif message and message:match("^%s*cdm%s*$") and ns.PrintCooldownHotkeyStatus then
        ns.PrintCooldownHotkeyStatus()
    elseif message and message:match("^%s*cdm%s+debug%s*$") and ns.PrintCooldownHotkeyStatus then
        ns.PrintCooldownHotkeyStatus(true)
    elseif message and message:match("^%s*copy%s*$") and ns.CopyCurrentChat then
        ns.CopyCurrentChat()
    else
        PhalkTools_Open()
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, loaded)
    if loaded ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    Start()
end)
