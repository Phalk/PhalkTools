local _, ns = ...

-- Independent cosmetic texture pass for Blizzard status bars. This module
-- never changes bar values, dimensions, visibility or secure frame anchors.
local records = setmetatable({}, { __mode = "k" })
local applying = false

local function Usable(bar)
    return bar and not (bar.IsForbidden and bar:IsForbidden())
        and type(bar.GetStatusBarTexture) == "function"
        and type(bar.SetStatusBarTexture) == "function"
end

local function NativeTint(record)
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
end

local function Restore(bar, record)
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

local function Track(bar, enabled, path, unit, power)
    if not Usable(bar) then return end
    local record = records[bar]
    if not record then
        record = {}
        records[bar] = record
        record.unit, record.power = unit, power
        Save(bar, record)
        hooksecurefunc(bar, "SetStatusBarTexture", function(self)
            if applying then return end
            local current = records[self]
            if not current then return end
            Save(self, current)
            if ns.db and ns.db.enabledTextureBars then
                local selected = ns.barTextures[ns.db.textureBarsTexture]
                if selected then Apply(self, current, selected) end
            end
        end)
        hooksecurefunc(bar, "SetStatusBarColor", function(self)
            if applying then return end
            local current = records[self]
            if not current then return end
            local ok, red, green, blue, alpha = pcall(self.GetStatusBarColor, self)
            if ok then current.color = { red, green, blue, alpha } end
            local texture = self:GetStatusBarTexture()
            if texture then
                local vertexOK, vertexRed, vertexGreen, vertexBlue, vertexAlpha =
                    pcall(texture.GetVertexColor, texture)
                if vertexOK then current.vertexColor = { vertexRed, vertexGreen, vertexBlue, vertexAlpha } end
            end
            if current.applied and ns.db and ns.db.enabledTextureBars then
                local selected = ns.barTextures[ns.db.textureBarsTexture]
                if selected then Apply(self, current, selected) end
            end
        end)
    end
    record.unit, record.power = unit or record.unit, power ~= nil and power or record.power
    if enabled then
        -- Capture the native texture each refresh, before applying ours.
        if not record.applied then Save(bar, record) end
        Apply(bar, record, path)
    elseif record.applied then
        Restore(bar, record)
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

local unitFrameOwned = {
    textureBarsPlayerHealth = "unitFramesPlayer",
    textureBarsPlayerPower = "unitFramesPlayer",
    textureBarsTargetHealth = "unitFramesTarget",
    textureBarsTargetPower = "unitFramesTarget",
    textureBarsFocusHealth = "unitFramesFocus",
    textureBarsFocusPower = "unitFramesFocus",
    textureBarsTargetOfTargetHealth = "unitFramesTargetOfTarget",
}

function ns.RefreshTextureBars()
    if not ns.db then return end
    local enabled = ns.db.enabledTextureBars == true
    local path = ns.barTextures and ns.barTextures[ns.db.textureBarsTexture]
    for _, entry in ipairs(GetUnitBars()) do
        local ownerSetting = unitFrameOwned[entry[2]]
        local ownedByUnitFrames = ns.db.enabledUnitFrames and ownerSetting and ns.db[ownerSetting]
        if ownedByUnitFrames then
            -- UnitFrames applies its own selected texture earlier in the same
            -- refresh cycle. Relinquish ownership without overwriting it.
            local record = records[entry[1]]
            if record then record.applied = false end
        else
            Track(entry[1], enabled and ns.db[entry[2]] == true, path, entry[3], entry[4])
        end
    end
    -- A switched-off module must restore bars even if a frame was removed
    -- from the current global list (for example when a cast bar is replaced).
    if not enabled then
        for bar, record in pairs(records) do
            if record.applied then Restore(bar, record) end
        end
    end
end

function ns.InitTextureBars()
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "PLAYER_REGEN_ENABLED", "UNIT_TARGET" }) do events:RegisterEvent(event) end
    events:SetScript("OnEvent", function() ns.RefreshTextureBars() end)
end
