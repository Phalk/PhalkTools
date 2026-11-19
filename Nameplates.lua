local _, ns = ...

local states = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local queued = false
local driverHooked = false
local errors = {}
local unpack = unpack or table.unpack
local Plain, Usable

local function ReadNativeComboPoints()
    local native = _G.ComboFrame
    if not native or type(native.ComboPoints) ~= "table" then return end
    local maximum = native.maxComboPoints
    if not Plain(maximum) or type(maximum) ~= "number" then maximum = #native.ComboPoints end
    maximum = math.max(1, math.min(10, maximum))
    local first = native.startComboPointIndex
    if not Plain(first) or type(first) ~= "number" then first = 1 end
    local count, sawState = 0, false
    for index = first, first + maximum - 1 do
        local point = native.ComboPoints[index]
        local highlight = point and point.Highlight
        if Usable(highlight) and highlight.GetAlpha then
            local ok, alpha = pcall(highlight.GetAlpha, highlight)
            if ok and Plain(alpha) and type(alpha) == "number" then
                sawState = true
                if alpha > 0 then count = count + 1 end
            end
        end
    end
    if sawState then return count, maximum end
end

local function ComboPointCount()
    local count
    if type(GetComboPoints) == "function" then
        local ok, value = pcall(GetComboPoints, "player", "target")
        if ok and Plain(value) and type(value) == "number" then count = value end
    end
    local maximum
    local native = _G.ComboFrame
    if native and Plain(native.maxComboPoints) and type(native.maxComboPoints) == "number"
        and native.maxComboPoints > 0 then
        maximum = native.maxComboPoints
    end
    if maximum == nil and UnitPowerMax and Enum and Enum.PowerType and Enum.PowerType.ComboPoints then
        local ok, value = pcall(UnitPowerMax, "player", Enum.PowerType.ComboPoints)
        if ok and Plain(value) and type(value) == "number" and value > 0 then maximum = value end
    end
    if maximum == nil then
        local nativeCount, nativeMaximum = ReadNativeComboPoints()
        if nativeCount ~= nil then return nativeCount, nativeMaximum end
        -- ComboFrame can be initialized after nameplates during login. Keep
        -- rogue points available during that brief gap instead of flickering
        -- the row away until another power event arrives.
        if type(UnitClass) == "function" then
            local ok, _, class = pcall(UnitClass, "player")
            if ok and (class == "ROGUE" or class == "DRUID") then maximum = 5 end
        end
        if maximum == nil then return end
    end
    maximum = math.max(1, math.min(10, maximum))
    if count == nil then
        local nativeCount, nativeMaximum = ReadNativeComboPoints()
        if nativeCount ~= nil then return nativeCount, nativeMaximum end
    end
    return count ~= nil and math.max(0, math.min(maximum, math.floor(count))) or 0, maximum
end

local function IsCurrentTarget(frame)
    if Plain(frame and frame.isTarget) and frame.isTarget == true then return true end
    local unit = frame and (frame.unit or frame.displayedUnit)
    if not Plain(unit) or type(unit) ~= "string" or not UnitIsUnit then return false end
    local ok, matches = pcall(UnitIsUnit, unit, "target")
    return ok and Plain(matches) and matches == true
end

local function CreateComboPointRow(state, frame)
    if state.comboRow then return state.comboRow end
    if not _G.RogueComboPointMixin then return end
    local bar = frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar or frame.healthBar
    if not Usable(bar) then return end
    local row = CreateFrame("Frame", nil, frame)
    row:SetFrameLevel((bar:GetFrameLevel() or frame:GetFrameLevel()) + 5)
    row:SetSize(1, 7)
    row:SetPoint("TOP", bar, "BOTTOM", 0, -3)
    row.points = {}
    local template = "RogueComboPointTemplate"
    for index = 1, 10 do
        local point = CreateFrame("Frame", nil, row, template)
        if not point then return end
        point:Setup()
        point:Update(false, false, true)
        row.points[index] = point
    end
    row:Hide()
    state.comboRow = row
    return row
end

local function StyleComboPoints(state, frame, enabled)
    if not enabled or not ns.db.nameplatesComboPoints then
        if state.comboRow then state.comboRow:Hide() end
        return
    end
    local row = CreateComboPointRow(state, frame)
    if not row then return end
    if not IsCurrentTarget(frame) then row:Hide(); return end
    local count, maximum = ComboPointCount()
    if count ~= nil and maximum then
        state.comboCount, state.comboMaximum = count, maximum
    else
        count, maximum = state.comboCount, state.comboMaximum
    end
    if count == nil or not maximum then row:Hide(); return end
    local pointScale, gap = 0.75, 5
    local pitch = 20 * pointScale + gap
    row:SetSize(maximum * pitch - gap, 20 * pointScale)
    row:ClearAllPoints()
    local bar = frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar or frame.healthBar
    if not Usable(bar) then row:Hide(); return end
    row:SetPoint("TOP", bar, "BOTTOM", 0, -3)
    for index, point in ipairs(row.points) do
        point:ClearAllPoints()
        if index <= maximum then
            point:SetScale(pointScale)
            point:SetPoint("CENTER", row, "CENTER", (index - (maximum + 1) / 2) * pitch, 0)
            point:Show()
            if point.Update then
                point:Update(index <= count, false)
            else
                point:SetActiveNoAnimation(index <= count)
            end
        else
            point:Hide()
        end
    end
    row:Show()
end

local function Secret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

Plain = function(value)
    return not Secret(value) and value ~= nil
end

Usable = function(object)
    return Plain(object) and not (object.IsForbidden and object:IsForbidden())
end

-- Keep each cosmetic operation independent. Report failures once instead of
-- silently swallowing them on every plate/event.
local function Run(operation, fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        local message = tostring(result)
        if errors[operation] ~= message then
            errors[operation] = message
            print("|cffff9900PhalkTools Nameplates|r " .. operation .. ": " .. message)
        end
    end
    return ok, result
end

local sizeOptions = {
    { "default", "WoW Default" },
    { "Small", "Small" },
    { "Medium", "Medium" },
    { "Large", "Large" },
    { "ExtraLarge", "Extra Large" },
    { "Huge", "Huge" },
}

function ns.GetNameplateSizeOptions()
    -- Settings can be registered before Blizzard_NamePlates loads.
    return sizeOptions
end

local function ApplyNativeSize()
    if InCombatLockdown() then return end
    local cvar = NamePlateConstants and NamePlateConstants.SIZE_CVAR or "nameplateSize"
    local sizes = Enum and Enum.NamePlateSize
    local get = C_CVar and C_CVar.GetCVar or GetCVar
    local set = C_CVar and C_CVar.SetCVar or SetCVar
    if not (get and set) then return end
    local current = get(cvar)
    if not Plain(current) then return end
    local desired = ns.db.enabledNameplates and sizes and sizes[ns.db.nameplatesSize]
    local saved = ns.db.nameplatesNativeSize
    if desired ~= nil and desired ~= false then
        desired = tostring(desired)
        if not saved then
            saved = { previous = current }
            ns.db.nameplatesNativeSize = saved
        elseif saved.applied and current ~= saved.applied then
            saved.previous = current
        end
        if current ~= desired then
            set(cvar, desired)
            if get(cvar) ~= desired then error("Could not change nameplateSize to " .. desired) end
        end
        saved.applied = desired
    elseif saved then
        if current == saved.applied and saved.previous ~= current then
            set(cvar, saved.previous)
            if get(cvar) ~= saved.previous then error("Could not restore nameplateSize") end
        end
        ns.db.nameplatesNativeSize = nil
    end
end

local function Selected(frame)
    local db = ns.db
    if not db.enabledNameplates then return false end
    -- No unit query is needed when both types are enabled. In particular, a
    -- secret unit token must not prevent all visible plates from being styled.
    if db.nameplatesFriendly and db.nameplatesEnemy then return true end
    if not db.nameplatesFriendly and not db.nameplatesEnemy then return false end
    local friendly = frame.isFriend
    if not Plain(friendly) then
        local unit = frame.unit
        if not Plain(unit) or type(unit) ~= "string" then return false end
        friendly = UnitIsFriend("player", unit)
    end
    if not Plain(friendly) then return false end
    return (friendly and db.nameplatesFriendly) or (not friendly and db.nameplatesEnemy)
end

local NATIVE_FILL = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill"
local NATIVE_ATLAS = "UI-HUD-CoolDownManager-Bar"

local function NativeFill(texture)
    -- Blizzard's UpdateAnchors selects these two assets. Never read the
    -- statusbar's dynamic UVs, which can depend on protected health values.
    local options = NamePlateSetupOptions
    if Plain(options) and Plain(options.useClassicHealthBar) then
        if options.useClassicHealthBar then return { file = NATIVE_FILL } end
        return { atlas = NATIVE_ATLAS }
    end
    local atlas = texture:GetAtlas()
    if Plain(atlas) and atlas ~= "" then return { atlas = atlas } end
    local file = texture:GetTexture()
    if Plain(file) then return { file = file } end
    return { atlas = NATIVE_ATLAS }
end

local function SetPrediction(bar, path)
    for _, key in ipairs({ "myHealPrediction", "otherHealPrediction" }) do
        local texture = bar[key]
        if Usable(texture) then
            texture:SetTexture(path or NATIVE_FILL)
            texture:SetTexCoord(0, 1, 0, 1)
        end
    end
end

local function StyleTexture(state, path)
    local bar, texture = state.bar, state.barTexture
    if not Usable(texture) then return end
    if path then
        if not state.nativeFill then state.nativeFill = NativeFill(texture) end
        if state.path ~= path then
            -- Change the existing native region. Its color, fill amount,
            -- anchors and all other indicators stay under Blizzard control.
            texture:SetTexture(path)
            texture:SetTexCoord(0, 1, 0, 1)
            state.path = path
        end
    elseif state.nativeFill then
        local saved = state.nativeFill
        if saved.atlas then
            texture:SetAtlas(saved.atlas, false)
        else
            texture:SetTexture(saved.file)
            texture:SetTexCoord(0, 1, 0, 1)
        end
        state.nativeFill, state.path = nil, nil
    end
end

local function StylePrediction(state, path)
    if not path and not state.predictionPath then return end
    if state.predictionPath ~= path then
        SetPrediction(state.bar, path)
        state.predictionPath = path
    end
end

local function RestoreBorder(state)
    if state.bgAlpha ~= nil and Usable(state.background) then
        state.background:SetAlpha(state.bgAlpha)
        state.bgAlpha = nil
    end
    if state.fill then state.fill:Hide() end
    if state.edges then
        for _, edge in ipairs(state.edges) do edge:Hide() end
    end
end

local function SetRegionAlpha(state, key, region, hidden)
    local saved = state[key]
    if saved and (saved.region ~= region or not hidden) then
        if Usable(saved.region) then saved.region:SetAlpha(saved.alpha) end
        state[key] = nil
        saved = nil
    end
    if hidden and Usable(region) then
        if not saved then
            local alpha = region:GetAlpha()
            if not Plain(alpha) then return end
            state[key] = { region = region, alpha = alpha }
        end
        region:SetAlpha(0)
    end
end

local function NativeFontHeight(region, key)
    local options = NamePlateSetupOptions
    local height = options and options[key]
    if Plain(height) and type(height) == "number" then return height end
    local _, size = region:GetFont()
    if Plain(size) then return size end
end

local function StyleFontSize(state, key, region, size, nativeKey)
    local saved = state[key]
    if saved and (saved.region ~= region or size == 0) then
        if Usable(saved.region) then
            saved.region:SetTextHeight(NativeFontHeight(saved.region, nativeKey) or saved.height)
        end
        state[key] = nil
        saved = nil
    end
    if size > 0 and Usable(region) then
        if not saved then
            local height = NativeFontHeight(region, nativeKey)
            if not height then return end
            state[key] = { region = region, height = height }
        end
        region:SetTextHeight(size)
    end
end

local function SaveLevelGeometry(badge)
    local width = badge:GetWidth()
    if not Plain(width) then return end
    local points = {}
    for i = 1, badge:GetNumPoints() do
        local point, relative, relativePoint, x, y = badge:GetPoint(i)
        if not (Plain(point) and Usable(relative) and Plain(relativePoint)
            and Plain(x) and Plain(y)) then return end
        points[i] = { point, relative, relativePoint, x, y }
    end
    if #points == 0 then return end
    return { badge = badge, width = width, points = points }
end

local function SetLevelGeometry(saved, width, x, y)
    local badge = saved.badge
    local options = NamePlateSetupOptions
    local nativeWidth = options and options.playerLevelDiffWidth
    if not Plain(nativeWidth) then nativeWidth = saved.width end
    local desiredWidth = width > 0 and width or nativeWidth
    local currentWidth = badge:GetWidth()
    if Plain(currentWidth) and currentWidth ~= desiredWidth then badge:SetWidth(desiredWidth) end
    if saved.x ~= x or saved.y ~= y then
        badge:ClearAllPoints()
        for _, point in ipairs(saved.points) do
            badge:SetPoint(point[1], point[2], point[3], point[4] + x, point[5] + y)
        end
        saved.x, saved.y = x, y
    end
end

local function StyleLevelGeometry(state, badge, width, x, y)
    if InCombatLockdown() then return end
    local saved = state.levelGeometry
    local custom = width > 0 or x ~= 0 or y ~= 0
    if saved and (saved.badge ~= badge or not custom) then
        if Usable(saved.badge) then SetLevelGeometry(saved, 0, 0, 0) end
        state.levelGeometry = nil
        saved = nil
    end
    if custom and Usable(badge) then
        if not saved then
            saved = SaveLevelGeometry(badge)
            if not saved then return end
            state.levelGeometry = saved
        end
        SetLevelGeometry(saved, width, x, y)
    end
end

local function HideLevelArt(state)
    if state.levelFill then state.levelFill:Hide() end
    if state.levelEdges then
        for _, edge in ipairs(state.levelEdges) do edge:Hide() end
    end
end

local function StyleLevelArt(state, badge, style)
    local db = ns.db
    if style == "match" then style = db.nameplatesBorder end
    local custom = style ~= "default"
    SetRegionAlpha(state, "levelIconAlpha", badge and badge.playerLevelDiffIcon, custom)
    if not custom or style == "text" or not Usable(badge) then
        HideLevelArt(state)
        return
    end
    if state.levelArtBadge ~= badge then
        HideLevelArt(state)
        state.levelFill, state.levelEdges = nil, nil
        state.levelArtBadge = badge
    end
    if not state.levelFill then
        state.levelFill = badge:CreateTexture(nil, "BACKGROUND", nil, 1)
        state.levelFill:SetAllPoints(badge)
    end
    state.levelFill:SetColorTexture(db.nameplatesLevelBackgroundR,
        db.nameplatesLevelBackgroundG, db.nameplatesLevelBackgroundB, 1)
    state.levelFill:Show()
    state.levelEdges = state.levelEdges or {}
    local thickness = style == "thick" and 2 or 1
    for i = 1, 4 do
        local edge = state.levelEdges[i]
        if not edge then
            edge = badge:CreateTexture(nil, "ARTWORK", nil, 1)
            state.levelEdges[i] = edge
        end
        edge:SetColorTexture(db.nameplatesLevelBorderR, db.nameplatesLevelBorderG,
            db.nameplatesLevelBorderB, 1)
        edge:ClearAllPoints()
        if i <= 2 then
            local side = i == 1 and "TOP" or "BOTTOM"
            edge:SetPoint(side .. "LEFT", badge, side .. "LEFT")
            edge:SetPoint(side .. "RIGHT", badge, side .. "RIGHT")
            edge:SetHeight(thickness)
        else
            local side = i == 3 and "LEFT" or "RIGHT"
            edge:SetPoint("TOP" .. side, badge, "TOP" .. side)
            edge:SetPoint("BOTTOM" .. side, badge, "BOTTOM" .. side)
            edge:SetWidth(thickness)
        end
        edge:SetShown(style ~= "none")
    end
end

local function StyleLevel(state, frame)
    local db = ns.db
    local badge = frame.PlayerLevelDiffFrame
    if not Usable(badge) then return end
    Run("level visibility", SetRegionAlpha, state, "levelAlpha", badge, not db.nameplatesLevelVisible)
    Run("level art", StyleLevelArt, state, badge, db.nameplatesLevelStyle)
    Run("level highlight", SetRegionAlpha, state, "levelHighlightAlpha",
        badge.selectedBorder, not db.nameplatesLevelHighlight or db.nameplatesLevelStyle == "text")
    Run("level geometry", StyleLevelGeometry, state, badge, db.nameplatesLevelWidth,
        db.nameplatesLevelOffsetX, db.nameplatesLevelOffsetY)
    Run("level font", StyleFontSize, state, "levelFont", badge.playerLevelDiffText,
        db.nameplatesLevelFontSize, "levelFontHeight")
end

local function RestoreExtras(state)
    for _, key in ipairs({ "levelAlpha", "levelIconAlpha", "levelHighlightAlpha", "healthHighlightAlpha" }) do
        Run("restore " .. key, SetRegionAlpha, state, key, nil, false)
    end
    Run("restore level art", HideLevelArt, state)
    Run("restore level geometry", StyleLevelGeometry, state, nil, 0, 0, 0)
    Run("restore level font", StyleFontSize, state, "levelFont", nil, 0, "levelFontHeight")
    Run("restore name font", StyleFontSize, state, "nameFont", nil, 0, "healthBarFontHeight")
end

function ns.OpenNameplateLevelColorPicker(part)
    if part ~= "Background" and part ~= "Border" then return end
    if not ColorPickerFrame and C_AddOns then C_AddOns.LoadAddOn("Blizzard_ColorPickerFrame") end
    if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
    local prefix = "nameplatesLevel" .. part
    local db = ns.db
    local r, g, b = db[prefix .. "R"], db[prefix .. "G"], db[prefix .. "B"]
    local function SetColor(red, green, blue)
        db[prefix .. "R"], db[prefix .. "G"], db[prefix .. "B"] = red, green, blue
        ns.RefreshNameplates()
    end
    ColorPickerFrame:SetupColorPickerAndShow({
        r = r, g = g, b = b, hasOpacity = false,
        swatchFunc = function() SetColor(ColorPickerFrame:GetColorRGB()) end,
        cancelFunc = function() SetColor(r, g, b) end,
    })
end

local function Restore(state)
    RestoreExtras(state)
    Run("restore texture", StyleTexture, state, nil)
    Run("restore healing", StylePrediction, state, nil)
    Run("restore border", RestoreBorder, state)
    if state.comboRow then state.comboRow:Hide() end
end

local function MakeEdges(bar, state)
    if state.edgesReady then return end
    if not state.fill then
        state.fill = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
        state.fill:Hide()
    end
    state.fill:SetAllPoints(bar)
    state.fill:SetColorTexture(0.025, 0.03, 0.04, 0.92)
    state.edges = state.edges or {}
    for i = 1, 4 do
        local edge = state.edges[i]
        if not edge then
            edge = bar:CreateTexture(nil, "OVERLAY", nil, 7)
            state.edges[i] = edge
            edge:Hide()
        end
        edge:SetColorTexture(0, 0, 0, 1)
    end
    state.edgesReady = true
end

local function StyleBorder(state, border)
    if border == "default" or not border then
        RestoreBorder(state)
        return
    end
    local bar, background = state.bar, state.background
    if not Usable(background) then return end
    MakeEdges(bar, state)
    if state.bgAlpha == nil then
        local alpha = background:GetAlpha()
        -- Native background has no alpha override in the nameplate template.
        state.bgAlpha = Plain(alpha) and alpha or 1
    end
    background:SetAlpha(0)
    state.fill:Show()
    local thickness = border == "thick" and 2 or 1
    local show = border ~= "none"
    for i, edge in ipairs(state.edges) do
        edge:ClearAllPoints()
        if i <= 2 then
            local point = i == 1 and "TOP" or "BOTTOM"
            local y = i == 1 and thickness or -thickness
            edge:SetPoint(point .. "LEFT", bar, point .. "LEFT", -thickness, y)
            edge:SetPoint(point .. "RIGHT", bar, point .. "RIGHT", thickness, y)
            edge:SetHeight(thickness)
        else
            local side = i == 3 and "LEFT" or "RIGHT"
            local x = i == 3 and -thickness or thickness
            edge:SetPoint("TOP" .. side, bar, "TOP" .. side, x, 0)
            edge:SetPoint("BOTTOM" .. side, bar, "BOTTOM" .. side, x, 0)
            edge:SetWidth(thickness)
        end
        edge:SetShown(show)
    end
end

local function Apply(frame)
    if not Usable(frame) then return end
    local container = frame.HealthBarsContainer
    local bar = container and container.healthBar or frame.healthBar
    if not Usable(bar) then return end
    -- The native template already exposes the texture region. Prefer it over
    -- a getter whose result may be restricted on a combat nameplate.
    local texture = bar.barTexture
    if not Usable(texture) and bar.GetStatusBarTexture then
        texture = bar:GetStatusBarTexture()
    end
    if not Usable(texture) then return end
    local state = states[frame]
    if not state or state.bar ~= bar or state.barTexture ~= texture then
        if state then Restore(state) end
        state = { bar = bar, barTexture = texture, background = bar.bgTexture }
        states[frame] = state
    end
    if not Selected(frame) then
        Restore(state)
        return
    end
    local path = ns.barTextures[ns.db.nameplatesTexture]
    Run("health texture", StyleTexture, state, path)
    Run("heal prediction", StylePrediction, state, path)
    Run("border", StyleBorder, state, ns.db.nameplatesBorder)
    Run("level", StyleLevel, state, frame)
    Run("health highlight", SetRegionAlpha, state, "healthHighlightAlpha",
        bar.selectedBorder, not ns.db.nameplatesHealthHighlight)
    Run("name font", StyleFontSize, state, "nameFont", frame.name,
        ns.db.nameplatesNameFontSize, "healthBarFontHeight")
    Run("combo points", StyleComboPoints, state, frame, true)
end

local RefreshVisible
local function QueueRefresh()
    if queued or not ns.db or not ns.db.enabledNameplates then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        RefreshVisible()
    end)
end

local function HookFrame(frame)
    local hooks = hooked[frame]
    if not hooks then hooks = {}; hooked[frame] = hooks end
    if not hooks.UpdateAnchors and type(frame.UpdateAnchors) == "function" then
        hooksecurefunc(frame, "UpdateAnchors", function(self)
            local state = states[self]
            if state then
                -- Blizzard just replaced the native fill. Do not restore an
                -- obsolete texture or accidentally save our own custom file.
                state.nativeFill, state.path = nil, nil
            end
            QueueRefresh()
        end)
        hooks.UpdateAnchors = true
    end
    if not hooks.OnUnitSet and type(frame.OnUnitSet) == "function" then
        hooksecurefunc(frame, "OnUnitSet", QueueRefresh)
        hooks.OnUnitSet = true
    end
    if not hooks.OnUnitCleared and type(frame.OnUnitCleared) == "function" then
        hooksecurefunc(frame, "OnUnitCleared", function(self)
            local state = states[self]
            if state then Restore(state) end
        end)
        hooks.OnUnitCleared = true
    end
    if not hooks.UpdateIsFriend and type(frame.UpdateIsFriend) == "function" then
        hooksecurefunc(frame, "UpdateIsFriend", QueueRefresh)
        hooks.UpdateIsFriend = true
    end
end

local function StylePlate(plate)
    if not Usable(plate) then return end
    local frame = plate.UnitFrame
    if not Usable(frame) then return end
    Run("frame hooks", HookFrame, frame)
    Run("apply", Apply, frame)
end

RefreshVisible = function()
    if not ns.db or not ns.db.enabledNameplates or not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    local ok, plates = Run("enumerate plates", C_NamePlate.GetNamePlates)
    if ok and Plain(plates) and type(plates) == "table" then
        for _, plate in pairs(plates) do Run("plate", StylePlate, plate) end
    end
end

local function AttachDriver()
    if driverHooked or not NamePlateDriverFrame then return end
    if type(NamePlateDriverFrame.OnNamePlateAdded) == "function" then
        hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", QueueRefresh)
        driverHooked = true
    end
end

function ns.RefreshNameplates()
    if not ns.db then return end
    Run("driver hooks", AttachDriver)
    Run("size", ApplyNativeSize)
    if not ns.db.enabledNameplates then
        for _, state in pairs(states) do Restore(state) end
    else
        RefreshVisible()
    end
end

function ns.InitNameplates()
    local events = CreateFrame("Frame")
    for _, event in ipairs({
        "ADDON_LOADED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "UNIT_FACTION", "CVAR_UPDATE",
        "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_POWER_FREQUENT", "COMBO_TARGET_CHANGED",
    }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, addon)
        if not ns.db then return end
        if event == "ADDON_LOADED" then
            if addon == "Blizzard_NamePlates" then ns.RefreshNameplates() end
        elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
            ns.RefreshNameplates()
        elseif event == "PLAYER_TARGET_CHANGED" then
            for _, state in pairs(states) do
                state.comboCount, state.comboMaximum = nil, nil
            end
            QueueRefresh()
        elseif (event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_POWER_FREQUENT")
            and (not Plain(addon) or addon == "player") then
            QueueRefresh()
        else
            QueueRefresh()
        end
    end)
    -- These events exist on Forever builds but not every client flavor.
    pcall(events.RegisterEvent, events, "UNIT_COMBO_POINTS")
    pcall(events.RegisterEvent, events, "UPDATE_SHAPESHIFT_FORM")
    if type(_G.ComboFrame_Update) == "function" then
        hooksecurefunc("ComboFrame_Update", QueueRefresh)
    end
    Run("driver hooks", AttachDriver)
end
