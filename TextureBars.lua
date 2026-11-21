local _, ns = ...

-- Texture and optional layout settings for Blizzard status bars.
local records = setmetatable({}, { __mode = "k" })
local barLayouts = setmetatable({}, { __mode = "k" })
local meterTextures = setmetatable({}, { __mode = "k" })
local meterTicker
local applying = false

local function Usable(bar)
    return bar and not (bar.IsForbidden and bar:IsForbidden())
        and type(bar.GetStatusBarTexture) == "function"
        and type(bar.SetStatusBarTexture) == "function"
end

local playerCastPalette = {
    ["ui-castingbar-filling-standard"] = "CASTBAR_CLASSIC_YELLOW",
    ["ui-castingbar-full-standard"] = "CASTBAR_CLASSIC_GREEN",
    ["ui-castingbar-filling-applyingcrafting"] = "CASTBAR_CLASSIC_YELLOW",
    ["ui-castingbar-full-applyingcrafting"] = "CASTBAR_CLASSIC_GREEN",
    ["ui-castingbar-filling-channel"] = "CASTBAR_CLASSIC_GREEN",
    ["ui-castingbar-full-channel"] = "CASTBAR_CLASSIC_GREEN",
    ["ui-castingbar-uninterruptable"] = "CASTBAR_CLASSIC_GRAY",
    ["ui-castingbar-interrupted"] = "CASTBAR_CLASSIC_RED",
}

local castColors = {
    CASTBAR_CLASSIC_YELLOW = { 1, 0.7, 0, 1 },
    CASTBAR_CLASSIC_GREEN = { 0, 1, 0, 1 },
    CASTBAR_CLASSIC_GRAY = { 0.7, 0.7, 0.7, 1 },
    CASTBAR_CLASSIC_RED = { 1, 0, 0, 1 },
}

local function NativeTint(record)
    -- Modern casting bars bake their color into the atlas and use a white tint.
    if record.setting == "textureBarsPlayerCast" then
        local db = ns.db
        if db.textureBarsPlayerCastCustomColor then
            return { db.textureBarsPlayerCastColorR, db.textureBarsPlayerCastColorG,
                db.textureBarsPlayerCastColorB, 1 }, true
        end
        local atlas = ns.Plain(record.atlas) and record.atlas or record.file
        local key = ns.Plain(atlas) and playerCastPalette[atlas]
        if key then
            local color = _G[key]
            if color then
                local r, g, b = color:GetRGB()
                return { r, g, b, 1 }, true
            end
            return castColors[key], true
        end
    end
    -- Forever's native unit-frame bars often have lockColor enabled. In that
    -- case their green/power color is baked into the texture and both APIs
    -- report white. Recreate that tint explicitly on the replacement.
    if record.lockColor and record.unit then
        if record.power then
            if type(UnitPowerType) == "function" and _G.PowerBarColor then
                local ok, powerType, token = pcall(UnitPowerType, record.unit)
                if ok then
                    local color = PowerBarColor[token] or PowerBarColor[powerType] or PowerBarColor.MANA
                    if color then return { color.r, color.g, color.b, 1 }, true end
                end
            end
        else
            -- The Forever unit-frame health texture is green when its color is
            -- locked (including target/focus); dead/disconnected states are
            -- represented by the native frame, not a status-bar color.
            return { 0, 1, 0, 1 }, true
        end
    end
    if record.color then return record.color, false end
    return record.vertexColor, false
end

function ns.OpenPlayerCastColorPicker()
    if not ColorPickerFrame and C_AddOns then C_AddOns.LoadAddOn("Blizzard_ColorPickerFrame") end
    if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
    local db = ns.db
    local custom = db.textureBarsPlayerCastCustomColor
    local r, g, b = db.textureBarsPlayerCastColorR, db.textureBarsPlayerCastColorG, db.textureBarsPlayerCastColorB
    local function SetColor(enabled, red, green, blue)
        db.textureBarsPlayerCastCustomColor = enabled
        db.textureBarsPlayerCastColorR, db.textureBarsPlayerCastColorG, db.textureBarsPlayerCastColorB = red, green, blue
        if Settings and Settings.NotifyUpdate then Settings.NotifyUpdate("PhalkTools_textureBarsPlayerCastCustomColor") end
        ns.RefreshTextureBars()
    end
    ColorPickerFrame:SetupColorPickerAndShow({
        r = r, g = g, b = b, hasOpacity = false,
        swatchFunc = function() SetColor(true, ColorPickerFrame:GetColorRGB()) end,
        cancelFunc = function() SetColor(custom, r, g, b) end,
    })
end

local function Save(bar, record)
    if not record.colorSaved then
        local colorOK, red, green, blue, alpha = pcall(bar.GetStatusBarColor, bar)
        if colorOK then record.color = { red, green, blue, alpha } end
        record.lockColor = bar.lockColor == true
        if bar.GetStatusBarDesaturated then
            local ok, value = pcall(bar.GetStatusBarDesaturated, bar)
            if ok then record.barDesaturated = value end
        end
        record.colorSaved = true
    end
    local texture = bar:GetStatusBarTexture()
    if not texture then return end
    if not record.applied then
        local vertexOK, vertexRed, vertexGreen, vertexBlue, vertexAlpha = pcall(texture.GetVertexColor, texture)
        if vertexOK then record.vertexColor = { vertexRed, vertexGreen, vertexBlue, vertexAlpha } end
        if texture.IsDesaturated then
            local ok, value = pcall(texture.IsDesaturated, texture)
            if ok then record.textureDesaturated = value end
        end
    end
    local ok, path = pcall(texture.GetTexture, texture)
    local atlasOk, atlas = pcall(texture.GetAtlas, texture)
    local coordsOk, left, right, top, bottom = pcall(texture.GetTexCoord, texture)
    if not ok or not atlasOk or not coordsOk then return end
    record.path, record.atlas = path, atlas
    record.coords = { left, right, top, bottom }
end

local function ApplyCastBackground(bar, record, path)
    local background = bar.Background
    if not background or (background.IsForbidden and background:IsForbidden()) then return end
    local original = record.castBackground
    local atlas, file = background:GetAtlas(), background:GetTexture()
    if issecretvalue and (issecretvalue(atlas) or issecretvalue(file)) then return end
    if not original or original.region ~= background or atlas or file ~= original.applied then
        original = {
            region = background,
            atlas = atlas,
            file = file,
            coords = { background:GetTexCoord() },
            color = { background:GetVertexColor() },
        }
        record.castBackground = original
    elseif original.path == path then
        return
    end
    background:SetTexture(path)
    background:SetTexCoord(0, 1, 0, 1)
    local r, g, b, a = unpack(original.color)
    if ns.Plain(r) and ns.Plain(g) and ns.Plain(b) then
        background:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, a)
    end
    original.applied, original.path = background:GetTexture(), path
end

local function RestoreCastBackground(record)
    local original = record.castBackground
    if not original then return end
    local background = original.region
    if not (background.IsForbidden and background:IsForbidden())
        and not background:GetAtlas() and background:GetTexture() == original.applied then
        if original.atlas then background:SetAtlas(original.atlas) else background:SetTexture(original.file) end
        background:SetTexCoord(unpack(original.coords))
        background:SetVertexColor(unpack(original.color))
    end
    record.castBackground = nil
end

local function Apply(bar, record, path)
    if not Usable(bar) or not path then return end
    applying = true
    local ok = pcall(function()
        bar:SetStatusBarTexture(path)
        local texture = bar:GetStatusBarTexture()
        if texture then
            texture:SetTexCoord(0, 1, 0, 1)
        end
        texture = bar:GetStatusBarTexture()
        local tint, desaturate = NativeTint(record)
        if texture and tint then
            -- The old unit-frame art has its color baked in. Remove that color
            -- from the replacement first, then apply the native tint.
            if texture.SetDesaturated then texture:SetDesaturated(desaturate == true) end
            texture:SetVertexColor(unpack(tint))
        end
    end)
    applying = false
    record.applied = ok
    if ok and not record.unit then ApplyCastBackground(bar, record, path) end
end

local function Restore(bar, record)
    RestoreCastBackground(record)
    if not Usable(bar) or not record.path then return end
    applying = true
    pcall(function()
        bar:SetStatusBarTexture(record.path)
        local texture = bar:GetStatusBarTexture()
        if texture then
            if record.atlas and texture.SetAtlas then texture:SetAtlas(record.atlas) end
            if record.coords then texture:SetTexCoord(unpack(record.coords)) end
            if texture.SetDesaturated then texture:SetDesaturated(record.textureDesaturated == true) end
        end
        if record.color then bar:SetStatusBarColor(unpack(record.color)) end
        if bar.SetStatusBarDesaturated and record.barDesaturated ~= nil then
            bar:SetStatusBarDesaturated(record.barDesaturated)
        end
        texture = bar:GetStatusBarTexture()
        if texture and record.vertexColor then texture:SetVertexColor(unpack(record.vertexColor)) end
    end)
    applying = false
    record.applied = false
end

local unitFrameOwned = {
    textureBarsPlayerHealth = "unitFramesPlayer",
    textureBarsPlayerPower = "unitFramesPlayer",
    textureBarsTargetHealth = "unitFramesTarget",
    textureBarsTargetPower = "unitFramesTarget",
    textureBarsFocusHealth = "unitFramesFocus",
    textureBarsFocusPower = "unitFramesFocus",
    textureBarsTargetOfTargetHealth = "unitFramesTargetOfTarget",
}

function ns.UnitFramesOwnTextureBar(setting)
    local db = ns.db
    local owner = unitFrameOwned[setting]
    return db and db.enabledUnitFrames and owner and db[owner]
end

local function SelectedTexture(setting)
    local db = ns.db
    if db and db.enabledTextureBars and db[setting] == true
        and not ns.UnitFramesOwnTextureBar(setting) and ns.barTextures then
        local override = db[setting .. "Texture"]
        if override and override ~= "global" and ns.barTextures[override] then
            return ns.barTextures[override]
        end
        return ns.barTextures[db.textureBarsTexture]
    end
end

local function Track(bar, setting, unit, power)
    if not Usable(bar) then return end
    local record = records[bar]
    local path = SelectedTexture(setting)
    if not record then
        if not path then return end
        record = { setting = setting, unit = unit, power = power }
        records[bar] = record
        hooksecurefunc(bar, "SetStatusBarTexture", function(self)
            if applying then return end
            local current = records[self]
            local selected = current and SelectedTexture(current.setting)
            if not selected then
                if current then current.applied = false end
                return
            end
            Save(self, current)
            Apply(self, current, selected)
        end)
        hooksecurefunc(bar, "SetStatusBarColor", function(self)
            if applying then return end
            local current = records[self]
            local selected = current and SelectedTexture(current.setting)
            if not selected or not current.applied then return end
            local ok, red, green, blue, alpha = pcall(self.GetStatusBarColor, self)
            if ok then current.color = { red, green, blue, alpha } end
            local texture = self:GetStatusBarTexture()
            if texture then
                local vertexOK, vertexRed, vertexGreen, vertexBlue, vertexAlpha =
                    pcall(texture.GetVertexColor, texture)
                if vertexOK then current.vertexColor = { vertexRed, vertexGreen, vertexBlue, vertexAlpha } end
            end
            Apply(self, current, selected)
        end)
    end
    record.setting, record.unit, record.power = setting, unit, power
    if path then
        -- Capture the native texture each refresh, before applying ours.
        if not record.applied then Save(bar, record) end
        Apply(bar, record, path)
    end
end

local function GetUnitBars()
    local target = _G.TargetFrame
    local targetMain = target and target.TargetFrameContent and target.TargetFrameContent.TargetFrameContentMain
    local focus = _G.FocusFrame
    local focusMain = focus and focus.FocusFrameContent and focus.FocusFrameContent.FocusFrameContentMain
    local tot = (target and target.totFrame) or _G.TargetFrameToT or _G.TargetofTargetFrame
    return {
        { _G.PlayerFrame and (_G.PlayerFrame.healthbar or _G.PlayerFrame.HealthBar), "textureBarsPlayerHealth", "player", false },
        { _G.PlayerFrame and (_G.PlayerFrame.manabar or _G.PlayerFrame.ManaBar), "textureBarsPlayerPower", "player", true },
        { target and (target.healthbar or (targetMain and targetMain.HealthBarsContainer
            and targetMain.HealthBarsContainer.HealthBar) or target.HealthBar), "textureBarsTargetHealth", "target", false },
        { target and (target.manabar or (targetMain and targetMain.ManaBarArea
            and targetMain.ManaBarArea.ManaBar) or target.ManaBar), "textureBarsTargetPower", "target", true },
        { focus and (focus.healthbar or (focusMain and focusMain.HealthBarsContainer
            and focusMain.HealthBarsContainer.HealthBar) or focus.HealthBar), "textureBarsFocusHealth", "focus", false },
        { focus and (focus.manabar or (focusMain and focusMain.ManaBarArea
            and focusMain.ManaBarArea.ManaBar) or focus.ManaBar), "textureBarsFocusPower", "focus", true },
        { tot and (tot.healthbar or tot.HealthBar), "textureBarsTargetOfTargetHealth", "targettarget", false },
        { _G.PlayerCastingBarFrame or _G.CastingBarFrame
            or (_G.PlayerFrame and _G.PlayerFrame.castBar), "textureBarsPlayerCast" },
        { target and (target.spellbar or target.SpellBar or target.castBar)
            or _G.TargetFrameSpellBar, "textureBarsTargetCast" },
        { focus and (focus.spellbar or focus.SpellBar or focus.castBar)
            or _G.FocusFrameSpellBar, "textureBarsFocusCast" },
    }
end

local function RestoreBarLayout(bar, layout, restoreHeight, restoreSpacing)
    if not Usable(bar) then return end
    if restoreHeight and layout.height then
        bar:SetHeight(layout.height)
        layout.height = nil
    end
    if restoreSpacing and layout.points then
        bar:ClearAllPoints()
        for _, point in ipairs(layout.points) do bar:SetPoint(unpack(point, 1, 5)) end
        layout.points = nil
    end
    if not layout.height and not layout.points then barLayouts[bar] = nil end
end

function ns.ReleaseUnitFrameTextureBarLayouts()
    if InCombatLockdown() then return end
    for bar, layout in pairs(barLayouts) do
        if ns.UnitFramesOwnTextureBar(layout.setting) then RestoreBarLayout(bar, layout, true, true) end
    end
end

local function SetPowerSpacing(bar, health, layout, gap)
    if not health then return end
    local top, bottom = bar:GetTop(), health:GetBottom()
    local barScale, healthScale = bar:GetEffectiveScale(), health:GetEffectiveScale()
    if not (ns.Plain(top) and ns.Plain(bottom) and ns.Plain(barScale) and ns.Plain(healthScale))
        or barScale <= 0 or healthScale <= 0 then return end
    local offset = bottom * healthScale / barScale - top - gap
    if math.abs(offset) < 0.01 then return end
    local count = bar:GetNumPoints()
    if not ns.Plain(count) or count == 0 then return end
    local points = {}
    for index = 1, count do
        local point, relative, relativePoint, x, y = bar:GetPoint(index)
        if not (ns.Plain(point) and ns.Plain(relativePoint) and ns.Plain(x) and ns.Plain(y)) then return end
        if issecretvalue and issecretvalue(relative) then return end
        points[index] = { point, relative, relativePoint, x, y }
    end
    layout.points = layout.points or points
    bar:ClearAllPoints()
    for _, point in ipairs(points) do bar:SetPoint(point[1], point[2], point[3], point[4], point[5] + offset) end
end

local function RefreshBarLayouts(bars)
    if InCombatLockdown() then return end
    local healthBars, current = {}, {}
    for _, entry in ipairs(bars) do
        local bar, unit, power = entry[1], entry[3], entry[4]
        if bar and unit and not power then healthBars[unit] = bar end
    end
    for _, entry in ipairs(bars) do
        local bar, setting, unit, power = unpack(entry, 1, 4)
        local enabled = SelectedTexture(setting)
        local height = enabled and ns.db[setting .. "Height"] or 0
        local gap = enabled and ns.db[setting .. "Spacing"] or -1
        if Usable(bar) and (height > 0 or gap >= 0) then
            current[bar] = true
            local layout = barLayouts[bar] or { setting = setting }
            barLayouts[bar] = layout
            RestoreBarLayout(bar, layout, height <= 0, gap < 0)
            barLayouts[bar] = layout
            if height > 0 then
                local nativeHeight = bar:GetHeight()
                if ns.Plain(nativeHeight) and nativeHeight ~= height then
                    layout.height = layout.height or nativeHeight
                    bar:SetHeight(height)
                end
            end
            if gap >= 0 and power then SetPowerSpacing(bar, healthBars[unit], layout, gap) end
        end
    end
    for bar, layout in pairs(barLayouts) do
        if not current[bar] then RestoreBarLayout(bar, layout, true, true) end
    end
end

local function RefreshMeterTextures(path)
    if InCombatLockdown() then return end
    if not path then
        for texture, original in pairs(meterTextures) do
            local usable = not (texture.IsForbidden and texture:IsForbidden())
            local atlas, file
            if usable then atlas, file = texture:GetAtlas(), texture:GetTexture() end
            local restricted = issecretvalue and (issecretvalue(atlas) or issecretvalue(file))
            if usable and not restricted and not atlas and file == original.applied then
                if original.atlas then
                    texture:SetAtlas(original.atlas)
                else
                    texture:SetTexture(original.file)
                end
            end
            meterTextures[texture] = nil
        end
        return
    end

    local meter = _G.DamageMeter
    if not meter then return end
    local function StyleRow(row)
        local bar = row.GetStatusBar and row:GetStatusBar()
        local texture = bar and bar:GetStatusBarTexture()
        if not texture or (texture.IsForbidden and texture:IsForbidden()) then return end
        local atlas, file = texture:GetAtlas(), texture:GetTexture()
        if issecretvalue and (issecretvalue(atlas) or issecretvalue(file)) then return end
        local original = meterTextures[texture]
        if not original or atlas or file ~= original.applied then
            original = { atlas = atlas, file = file }
            meterTextures[texture] = original
        elseif original.path == path then
            return
        end
        texture:SetTexture(path)
        original.applied, original.path = texture:GetTexture(), path
    end
    local function StyleWindow(window)
        if not window or (window.IsVisible and not window:IsVisible()) then return end
        local box = window.GetScrollBox and window:GetScrollBox()
        if window.ForEachEntryFrame then
            window:ForEachEntryFrame(StyleRow)
        elseif box and box.ForEachFrame then
            box:ForEachFrame(StyleRow)
        end
    end
    local function StyleSession(session)
        StyleWindow(session)
        if session.GetSourceWindow then StyleWindow(session:GetSourceWindow()) end
    end
    if meter.ForEachSessionWindow then
        meter:ForEachSessionWindow(StyleSession)
    elseif meter.GetPrimarySessionWindow then
        local primary = meter:GetPrimarySessionWindow()
        if primary then StyleSession(primary) end
    end
end

function ns.RefreshTextureBars()
    if not ns.db then return end
    local bars = GetUnitBars()
    RefreshBarLayouts(bars)
    for _, entry in ipairs(bars) do
        if ns.UnitFramesOwnTextureBar(entry[2]) then
            -- UnitFrames applies its own selected texture earlier in the same
            -- refresh cycle. Relinquish ownership without overwriting it.
            local record = records[entry[1]]
            if record then record.applied = false end
        else
            Track(entry[1], entry[2], entry[3], entry[4])
        end
    end
    -- Restore disabled bars that are no longer in the current global list.
    for bar, record in pairs(records) do
        if not SelectedTexture(record.setting) then
            if record.applied then Restore(bar, record) else RestoreCastBackground(record) end
        end
    end
    local meterPath = SelectedTexture("textureBarsDamageMeter")
    RefreshMeterTextures(meterPath)
    if meterPath and not meterTicker then
        -- Recycled rows can appear while scrolling without a combat-session event.
        meterTicker = C_Timer.NewTicker(0.25, function()
            RefreshMeterTextures(SelectedTexture("textureBarsDamageMeter"))
        end)
    elseif not meterPath and meterTicker then
        meterTicker:Cancel()
        meterTicker = nil
    end
end

function ns.InitTextureBars()
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "PLAYER_REGEN_ENABLED", "UNIT_TARGET" }) do events:RegisterEvent(event) end
    events:SetScript("OnEvent", function() ns.RefreshTextureBars() end)
end
