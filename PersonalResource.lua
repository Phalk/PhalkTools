local _, ns = ...

local textures = {
    flat = "Interface\\Buttons\\WHITE8X8",
    smooth = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill",
    raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    gradient = "Interface\\AddOns\\PhalkTools\\Media\\Gradient.tga",
    gloss = "Interface\\AddOns\\PhalkTools\\Media\\Gloss.tga",
    soft = "Interface\\AddOns\\PhalkTools\\Media\\Soft.tga",
    metal = "Interface\\AddOns\\PhalkTools\\Media\\Metal.tga",
    striped = "Interface\\AddOns\\PhalkTools\\Media\\Striped.tga",
    beveled = "Interface\\AddOns\\PhalkTools\\Media\\Beveled.tga",
}
ns.barTextures = textures

-- Forever uses Blizzard_PersonalResourceDisplay, not a player nameplate.
-- See Gethe/wow-ui-source, branch forever, Blizzard_PersonalResourceDisplay.
local bars, display, originalAlpha = {}, nil, nil
local edgeCache = setmetatable({}, { __mode = "k" })
local updating = false
local healthAlphaCurve
local spacingApplied, spacingChanging, originalPadding = false, false, nil

-- Native choices are stored separately from the optional visual customizations.
local nativeOptions = {
    { "Size", "SetSize" }, { "BarWidth", "SetBarWidth" },
    { "HealthBarHeight", "SetHealthBarHeight" }, { "PowerBarHeight", "SetPowerBarHeight" },
    { "Padding", "SetBarPadding" }, { "VisibleSetting", "SetVisibleSetting" },
    { "HideHealth", "SetHideHealth" }, { "HidePower", "SetHidePower" },
    { "HideAltPower", "SetHideAltPower" }, { "HideClassInfo", "SetHideClassInfo" },

}
local nativeChanging = false
local nativeOpacity
local nativeErrors = {}
local function NativeError(key, message)
    if nativeErrors[key] == message then return end
    nativeErrors[key] = message
    print("|cffff9900PhalkTools|r " .. key .. ": " .. tostring(message))
end

function ns.GetPersonalNative(key, fallback)
    local choices = ns.db.personalResourceNative
    if choices and choices[key] ~= nil then return choices[key] end
    if key == "Enabled" then return C_CVar.GetCVarBool("nameplateShowSelf") end
    local frame = PersonalResourceDisplayFrame
    local setting = Enum.EditModePersonalResourceDisplaySetting[key]
    if frame and frame.IsInitialized and frame:IsInitialized() and setting then
        local value = frame:GetSettingValue(setting)
        if type(fallback) == "boolean" then return value == 1 end
        return value or fallback
    end
    return fallback
end

function ns.SetPersonalNative(key, value)
    ns.db.personalResourceNative = ns.db.personalResourceNative or {}
    ns.db.personalResourceNative[key] = value
    ns.RefreshPersonalResource()
end

local function ApplyNative()
    if nativeChanging or InCombatLockdown() then return end
    local choices = ns.db.personalResourceNative
    if not choices then return end
    nativeChanging = true
    local ok, message = pcall(function()
    if choices.Enabled ~= nil then
        local value = choices.Enabled and "1" or "0"
        if C_CVar.GetCVar("nameplateShowSelf") ~= value then C_CVar.SetCVar("nameplateShowSelf", value) end
    end
    -- A hidden PRD has not necessarily received OnShow/Setup yet. Native
    -- controls must work before the user first shows the bar as well.
    -- Blizzard alone initializes the display; Setup reads protected unit data.
    if display and display.hasBeenSetup then
        for _, option in ipairs(nativeOptions) do
            local key, method = option[1], option[2]
            if choices[key] ~= nil and type(display[method]) == "function" then
                local applied, errorMessage = pcall(display[method], display, choices[key])
                if not applied then NativeError(key, errorMessage) end
                if key == "Padding" and spacingApplied then originalPadding = choices[key] end
            end
        end
        if choices.Opacity then
            originalAlpha = choices.Opacity / 100
            if healthAlphaCurve and nativeOpacity ~= originalAlpha then
                healthAlphaCurve = C_CurveUtil.CreateCurve()
                healthAlphaCurve:SetType(Enum.LuaCurveType.Step)
                healthAlphaCurve:AddPoint(0, originalAlpha)
                healthAlphaCurve:AddPoint(1, 0)
                nativeOpacity = originalAlpha
            end
        end
    end
    end)
    nativeChanging = false
    if not ok then NativeError("ApplyNative", message) end
end

local textOverlays = setmetatable({}, { __mode = "k" })
local percentCurve
local function SetResourceAmount(text, value, abbreviate)
    if abbreviate and AbbreviateLargeNumbers then
        local ok, formatted = pcall(AbbreviateLargeNumbers, value)
        if ok then
            text:SetText(formatted)
            return
        end
    end
    text:SetFormattedText("%d", value)
end
local function UpdateEnergyText()
    if not display or not display:IsVisible() or not ns.db then return end
    local choices = ns.db.personalResourceNative
    local texts = display.PowerBar and textOverlays[display.PowerBar]
    if not choices or not choices.ShowBarText or not texts or not texts.Right:IsVisible() then return end
    local powerType = UnitPowerType("player")
    local energy = Enum and Enum.PowerType and Enum.PowerType.Energy or 3
    if ns.Plain(powerType) and powerType == energy then
        texts.Right:SetFormattedText("%d", UnitPower("player", energy))
    end
end

local function UpdateNativeText()
    if not display or not display.hasBeenSetup then return end
    local choices = ns.db.personalResourceNative
    if not choices then return end
    local container = display.HealthBarsContainer
    local health = display.healthbar or (container and container.healthBar)
    for key, bar in pairs({ health = health, power = display.PowerBar, alternate = display.AlternatePowerBar }) do
        if choices.ShowBarText ~= nil then
            -- Alpha changes do not invoke Blizzard's protected numeric formatter.
            for _, name in ipairs({ "TextString", "LeftText", "RightText" }) do
                if bar[name] then bar[name]:SetAlpha(0) end
            end
            local texts = textOverlays[bar]
            if not texts then
                texts = {}
                for _, side in ipairs({ "Left", "Right" }) do
                    local text = bar:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
                    local anchor = side == "Left" and "LEFT" or "RIGHT"
                    text:SetPoint(anchor, bar, anchor, side == "Left" and 5 or -5, 0)
                    text:SetJustifyH(anchor)
                    texts[side] = text
                end
                textOverlays[bar] = texts
            end
            texts.Left:SetShown(false)
            texts.Right:SetShown(choices.ShowBarText)
            if choices.ShowBarText then
                -- PRD uses Blizzard's BOTH layout: percent left, current value
                -- right. Non-mana power and alternate power only show current.
                if not percentCurve and C_CurveUtil and C_CurveUtil.CreateCurve then
                    percentCurve = C_CurveUtil.CreateCurve()
                    percentCurve:AddPoint(0, 0)
                    percentCurve:AddPoint(1, 100)
                end
                if key == "health" then
                    SetResourceAmount(texts.Right, UnitHealth("player"), bar.capNumericDisplay ~= false)
                    if percentCurve and UnitHealthPercent then
                        texts.Left:SetFormattedText("%.0f%%", UnitHealthPercent("player", false, percentCurve))
                        texts.Left:SetShown(true)
                    end
                elseif key == "power" then
                    local powerType = UnitPowerType("player")
                    local isMana = ns.Plain(powerType) and powerType == 0
                    SetResourceAmount(texts.Right, UnitPower("player"), isMana and bar.capNumericDisplay ~= false)
                    if isMana and percentCurve and UnitPowerPercent then
                        texts.Left:SetFormattedText("%.0f%%", UnitPowerPercent("player", powerType, false, percentCurve))
                        texts.Left:SetShown(true)
                    end
                else
                    texts.Right:SetFormattedText("%d", bar:GetValue())
                end
            end
        end
    end
    if health and choices.ShowClassColor ~= nil then
        if choices.ShowClassColor then
            local _, class = UnitClass("player")
            local color = RAID_CLASS_COLORS[class]
            if color then health:SetStatusBarColor(color.r, color.g, color.b) end
        else
            health:SetStatusBarColor(0, 1, 0)
        end
    end
end

local function ApplySpacing()
    if not display or not display.hasBeenSetup or not display.SetBarPadding
        or not display.GetMinimumBarPadding or spacingChanging then return end
    local custom = ns.db.enabledPersonalResource
    local padding
    if custom then
        if not spacingApplied then
            originalPadding = display.barPadding
            spacingApplied = true
        end
        local gap = tonumber(ns.db.personalResourceSpacing) or 4
        if gap ~= gap then gap = 4 end
        gap = math.floor(math.max(0, math.min(32, gap)))
        -- Blizzard adds its minimum padding to this value. Expose the actual
        -- gap in the slider, including zero, rather than an extra offset.
        padding = gap - display:GetMinimumBarPadding()
    elseif spacingApplied then
        padding = originalPadding or 0
        spacingApplied = false
    else
        return
    end
    if display.barPadding ~= padding then
        spacingChanging = true
        display:SetBarPadding(padding)
        spacingChanging = false
    end
end

local function Forbidden(frame)
    return frame.IsForbidden and frame:IsForbidden()
end

-- Incoming healing uses separate textures, not the status bar's texture.
-- Preserve native tint, masks, visibility and fill geometry.
local predictionTextures = setmetatable({}, { __mode = "k" })
local function StylePrediction(texture, path)
    if not texture or Forbidden(texture) then return end
    local saved = predictionTextures[texture]
    if path then
        if not saved then
            saved = {
                texture = texture:GetTexture(),
                atlas = texture:GetAtlas(),
                coords = { texture:GetTexCoord() },
            }
            predictionTextures[texture] = saved
        end
        texture:SetTexture(path)
        texture:SetTexCoord(0, 1, 0, 1)
    elseif saved then
        if saved.atlas then
            texture:SetAtlas(saved.atlas, false)
        else
            texture:SetTexture(saved.texture)
        end
        texture:SetTexCoord(unpack(saved.coords))
        predictionTextures[texture] = nil
    end
end

function ns.StyleHealPrediction(bar, path)
    if not bar or Forbidden(bar) then return end
    -- PRD textures and modern unit frame overlay segments use different keys.
    StylePrediction(bar.myHealPrediction, path)
    StylePrediction(bar.otherHealPrediction, path)
    local mine, other = bar.MyHealPredictionBar, bar.OtherHealPredictionBar
    StylePrediction(mine and mine.Fill, path)
    StylePrediction(other and other.Fill, path)
end

local function RestoreBar(bar, state)
    ns.StyleHealPrediction(bar, nil)
    if state.changedTexture then
        if state.atlas then
            bar:SetStatusBarTexture(state.texture)
            bar:GetStatusBarTexture():SetAtlas(state.atlas)
        else
            bar:SetStatusBarTexture(state.texture)
        end
        local texture = bar:GetStatusBarTexture()
        if texture and state.coords then texture:SetTexCoord(unpack(state.coords)) end
        state.changedTexture = false
    end
    for region, alpha in pairs(state.borders) do region:SetAlpha(alpha) end
    if state.background then state.background:Hide() end
    if state.edges then
        for _, edge in ipairs(state.edges) do edge:Hide() end
    end
end

local function Release()
    for bar, state in pairs(bars) do RestoreBar(bar, state) end
    wipe(bars)
    if display and originalAlpha ~= nil then
        display:SetAlpha(originalAlpha)
    end
end

local borderKeys = { "border", "Border", "BorderFrame", "selectedBorder" }

local function StyleBar(bar)
    if not bar or Forbidden(bar) or not bar.GetStatusBarTexture then return end
    local state = bars[bar]
    if not state then
        local texture = bar:GetStatusBarTexture()
        if not texture then return end
        state = {
            texture = texture:GetTexture(),
            atlas = texture.GetAtlas and texture:GetAtlas(),
            coords = { texture:GetTexCoord() },
            borders = {},
            edges = edgeCache[bar],
        }
        for _, key in ipairs(borderKeys) do
            local region = bar[key]
            if region and region.GetAlpha and not Forbidden(region) then
                state.borders[region] = region:GetAlpha()
            end
        end
        -- The new PRD border is baked into an anonymous background atlas.
        for _, region in ipairs({ bar:GetRegions() }) do
            if region.GetAtlas and region:GetAtlas() == "UI-HUD-CoolDownManager-Bar-BG" then
                state.borders[region] = region:GetAlpha()
            end
        end
        if state.edges then state.background = state.edges.background end
        bars[bar] = state
    end

    local path = textures[ns.db.personalResourceTexture]
    if path then
        bar:SetStatusBarTexture(path)
        bar:GetStatusBarTexture():SetTexCoord(0, 1, 0, 1)
        state.changedTexture = true
    elseif state.changedTexture then
        RestoreBar(bar, state)
    end
    ns.StyleHealPrediction(bar, path)

    local style = ns.db.personalResourceBorder
    local custom = style == "thin" or style == "thick"
    local hide = custom or style == "none"
    for region, alpha in pairs(state.borders) do region:SetAlpha(hide and 0 or alpha) end
    if hide and not state.edges then
        state.edges = {}
        state.background = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
        state.background:SetAllPoints(bar)
        state.background:SetColorTexture(0.025, 0.03, 0.04, 0.9)
        state.edges.background = state.background
        for i = 1, 4 do
            local edge = bar:CreateTexture(nil, "OVERLAY", nil, 7)
            edge:SetColorTexture(0, 0, 0, 1)
            state.edges[i] = edge
        end
        edgeCache[bar] = state.edges
    end
    if state.background then state.background:SetShown(hide) end
    if state.edges then
        local size = style == "thick" and 2 or 1
        for i, edge in ipairs(state.edges) do
            edge:ClearAllPoints()
            if i <= 2 then
                local point = i == 1 and "TOP" or "BOTTOM"
                edge:SetPoint(point .. "LEFT", bar, point .. "LEFT", -size, i == 1 and size or -size)
                edge:SetPoint(point .. "RIGHT", bar, point .. "RIGHT", size, i == 1 and size or -size)
                edge:SetHeight(size)
            else
                local point = i == 3 and "LEFT" or "RIGHT"
                edge:SetPoint("TOP" .. point, bar, "TOP" .. point, i == 3 and -size or size, 0)
                edge:SetPoint("BOTTOM" .. point, bar, "BOTTOM" .. point, i == 3 and -size or size, 0)
                edge:SetWidth(size)
            end
            edge:SetShown(custom)
        end
    end
end

local function UpdateAlpha()
    if not display or not ns.db then return end
    if ns.db.enabledPersonalResource and ns.db.personalResourceHideFull and healthAlphaCurve
        and not display.isInEditMode and not InCombatLockdown() and not UnitAffectingCombat("player") then
        -- The result can be secret. Pass it directly to the display API;
        -- never inspect it, compare it, or branch on the player's health.
        display:SetAlpha(UnitHealthPercent("player", false, healthAlphaCurve))
    else
        display:SetAlpha(originalAlpha)
    end
end

local function ApplyStyle()
    if updating or not display or not ns.db then return end
    updating = true
    local ok, message = pcall(function()
    ApplyNative()
    if ns.db.enabledPersonalResource then
        local container = display.HealthBarsContainer
        StyleBar(container and container.healthBar or display.healthbar)
        StyleBar(display.PowerBar)
        StyleBar(display.AlternatePowerBar)
    else
        Release()
    end
    ApplySpacing()
    UpdateNativeText()
    end)
    updating = false
    if not ok then NativeError("ApplyStyle", message) end
    UpdateAlpha()
end

local function Attach()
    if display or InCombatLockdown() or not PersonalResourceDisplayFrame or Forbidden(PersonalResourceDisplayFrame) then return end
    display = PersonalResourceDisplayFrame
    originalAlpha = display:GetAlpha()
    if not ns.Plain(originalAlpha) then originalAlpha = 1 end
    if UnitHealthPercent and C_CurveUtil and C_CurveUtil.CreateCurve then
        healthAlphaCurve = C_CurveUtil.CreateCurve()
        healthAlphaCurve:SetType(Enum.LuaCurveType.Step)
        healthAlphaCurve:AddPoint(0, originalAlpha)
        healthAlphaCurve:AddPoint(1, 0)
    end
    for _, method in ipairs({ "Setup" }) do
        if type(display[method]) == "function" then hooksecurefunc(display, method, ApplyStyle) end
    end
    if type(display.UpdateShownState) == "function" then
        hooksecurefunc(display, "UpdateShownState", UpdateAlpha)
    end
    if type(display.SetBarPadding) == "function" then
        hooksecurefunc(display, "SetBarPadding", function(_, padding)
            if spacingChanging or nativeChanging then return end
            -- Keep the latest Edit Mode choice for restoration when disabled.
            if spacingApplied then originalPadding = padding end
            ApplySpacing()
        end)
    end
    if type(display.UpdateSystemSetting) == "function" then
        local refreshQueued = false
        hooksecurefunc(display, "UpdateSystemSetting", function()
            if updating or nativeChanging or refreshQueued then return end
            refreshQueued = true
            C_Timer.After(0, function()
                refreshQueued = false
                ns.RefreshPersonalResource()
            end)
        end)
    end
    display:HookScript("OnShow", ApplyStyle)
    ApplyStyle()
end

function ns.RefreshPersonalResource()
    Attach()
    ApplyNative()
    ApplyStyle()
end

function ns.InitPersonalResource()
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "PLAYER_IN_COMBAT_CHANGED", "ADDON_LOADED" }) do
        frame:RegisterEvent(event)
    end
    frame:RegisterUnitEvent("UNIT_HEALTH", "player")
    frame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    frame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    frame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    frame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    frame:SetScript("OnEvent", function(_, event)
        if event == "UNIT_POWER_FREQUENT" then
            UpdateEnergyText()
            return
        end
        Attach()
        if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" or event == "ADDON_LOADED" then
            ns.RefreshPersonalResource()
        else
            UpdateAlpha()
            UpdateNativeText()
        end
    end)
    C_Timer.NewTicker(0.05, UpdateEnergyText)
    Attach()
end
