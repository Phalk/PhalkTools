local _, ns = ...

-- Cosmetic changes only. Never invoke Blizzard unit/text update functions:
-- those functions can compare secret health/power values in addon context.
local states = setmetatable({}, { __mode = "k" })
local refreshing, queued = false, false
local restyling = false
local unpack = unpack or table.unpack
local combatTextLayers = setmetatable({}, { __mode = "k" })

local function Usable(object)
    return object and not (object.IsForbidden and object:IsForbidden())
end

local function SetCombatTextLayer(textFrame, enabled, level)
    if not Usable(textFrame) or not textFrame.SetFrameStrata then return end
    local saved = combatTextLayers[textFrame]
    if enabled then
        if not saved then
            saved = { strata = textFrame:GetFrameStrata(), level = textFrame:GetFrameLevel() }
            combatTextLayers[textFrame] = saved
        end
        textFrame:SetFrameStrata("HIGH")
        if level then textFrame:SetFrameLevel(math.max(saved.level, level)) end
    elseif saved then
        textFrame:SetFrameStrata(saved.strata)
        textFrame:SetFrameLevel(saved.level)
        combatTextLayers[textFrame] = nil
    end
end

local function RaiseUnitCombatText(frame, content, enabled)
    if not frame then return end
    local main = content and (content.PlayerFrameContentMain or content.TargetFrameContentMain)
    local indicator = main and main.HitIndicator or frame.HitIndicator
    SetCombatTextLayer(indicator, enabled, frame:GetFrameLevel() + 32)
end

local function Remember(state, object)
    if not Usable(object) then return end
    local saved = state.objects[object]
    if saved then return saved end
    saved = { alpha = object:GetAlpha() }
    state.objects[object] = saved
    return saved
end

local function RememberLayout(state, object)
    local saved = Remember(state, object)
    if not saved or saved.points then return saved end
    local count = object:GetNumPoints()
    local width, height = object:GetSize()
    if not ns.Plain(count) or type(count) ~= "number"
        or not ns.Plain(width) or type(width) ~= "number"
        or not ns.Plain(height) or type(height) ~= "number" then return end
    local points = {}
    for i = 1, count do
        local point, relative, relativePoint, x, y = object:GetPoint(i)
        if not ns.Plain(point) or type(point) ~= "string"
            or (relative ~= nil and not ns.Plain(relative))
            or not ns.Plain(relativePoint) or type(relativePoint) ~= "string"
            or not ns.Plain(x) or type(x) ~= "number"
            or not ns.Plain(y) or type(y) ~= "number" then return end
        points[i] = { point, relative, relativePoint, x, y }
    end
    -- Commit only complete snapshots. A failed capture must never leave a
    -- partial layout for Restore to apply on the next refresh.
    saved.points, saved.width, saved.height = points, width, height
    return saved
end

local function HideArt(state, object)
    if Remember(state, object) then object:SetAlpha(0) end
end

local function SuppressPortraitTexture(state, texture)
    if not Usable(texture) or not texture.SetTexture then return end
    local saved = Remember(state, texture)
    if not saved.textureSaved then
        saved.textureSaved = true
        saved.texture = texture:GetTexture()
        saved.atlas = texture.GetAtlas and texture:GetAtlas()
        saved.coords = { texture:GetTexCoord() }
    end
    texture:SetAlpha(0)
    texture:SetTexture(nil)
end

local function UpdateRestIndicator()
    local frame = _G.PlayerFrame
    local state = frame and states[frame]
    if not state then return end
    if InCombatLockdown() then
        if state.restLabel then state.restLabel:Hide() end
        return
    end
    if not state.active or not ns.db.enabledUnitFrames or not ns.db.unitFramesPlayer
        or not ns.db.unitFramesHidePortrait then
        if state.restLabel then state.restLabel:Hide() end
        return
    end
    local content = frame.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    local contextual = content and content.PlayerFrameContentContextual
    local art = frame.PlayerFrameContainer
    local loop = contextual and contextual.PlayerRestLoop
    if loop then
        HideArt(state, loop)
        SuppressPortraitTexture(state, loop.RestTexture)
    end
    SuppressPortraitTexture(state, main and main.StatusTexture)
    SuppressPortraitTexture(state, art and art.FrameFlash)
    SuppressPortraitTexture(state, _G.PlayerStatusTexture)
    HideArt(state, _G.PlayerRestIcon)
    HideArt(state, _G.PlayerRestGlow)
    if state.restLabel then
        local attack = contextual and contextual.AttackIcon or _G.PlayerAttackIcon
        local attacking = false
        if Usable(attack) then
            local shown = attack:IsShown()
            attacking = not ns.Plain(shown) or shown
        end
        state.restLabel:SetShown(IsResting() and not InCombatLockdown() and not attacking)
    end
end

local function Move(state, object, point, relative, relativePoint, x, y, width, height)
    if not RememberLayout(state, object) then return end
    object:ClearAllPoints()
    object:SetPoint(point, relative, relativePoint, x, y)
    if width then object:SetWidth(width) end
    if height then object:SetHeight(height) end
end

local function Restore(state)
    state.active = false
    if state.portrait3D then state.portrait3D.holder:Hide() end
    if state.visual then
        state.visual.active = false
        state.visual.health:Hide()
        state.visual.power:Hide()
        if state.visual.prediction then state.visual.prediction:Hide() end
        if state.visual.textOverlay then state.visual.textOverlay:Hide() end
    end
    if state.targetMaskTargets then
        for texture, original in pairs(state.targetMaskTargets) do
            texture:RemoveMaskTexture(state.targetMask)
            texture:AddMaskTexture(original)
        end
        wipe(state.targetMaskTargets)
    end
    ns.StyleHealPrediction(state.predictionHealth, nil)
    state.predictionHealth = nil
    if state.restLabel then state.restLabel:Hide() end
    if state.levelOverlay then state.levelOverlay:Hide() end
    for object, saved in pairs(state.objects) do
        if Usable(object) then
            object:SetAlpha(saved.alpha)
            if saved.visibilitySaved then object:SetShown(saved.shown) end
            if saved.justifyH then object:SetJustifyH(saved.justifyH) end
            if saved.justifyV then object:SetJustifyV(saved.justifyV) end
            if saved.fontObject then object:SetFontObject(saved.fontObject) end
            if saved.points then
                object:ClearAllPoints()
                for _, point in ipairs(saved.points) do object:SetPoint(unpack(point, 1, 5)) end
                if not saved.anchorOnly then object:SetSize(saved.width, saved.height) end
            end
            if saved.textureSaved then
                if saved.atlas then object:SetAtlas(saved.atlas) else object:SetTexture(saved.texture) end
                object:SetTexCoord(unpack(saved.coords))
            end
            if saved.color then object:SetStatusBarColor(unpack(saved.color)) end
            if saved.barTexture then
                object:SetStatusBarTexture(saved.barTexture)
                local texture = object:GetStatusBarTexture()
                if saved.barAtlas then texture:SetAtlas(saved.barAtlas) end
                texture:SetTexCoord(unpack(saved.barCoords))
            end
        end
    end
    for _, texture in ipairs(state.decorations) do texture:Hide() end
    wipe(state.objects)
end

local function QueueRefresh()
    if queued or refreshing then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        ns.RefreshUnitFrames()
    end)
end

local function Resolve(frame, player)
    local content = player and frame.PlayerFrameContent or frame.TargetFrameContent
    local main = content and (player and content.PlayerFrameContentMain or content.TargetFrameContentMain)
    local container = main and main.HealthBarsContainer
    local health = frame.healthbar or (container and container.HealthBar) or frame.HealthBar
    local power = frame.manabar or (main and (main.ManaBar or (main.ManaBarArea and main.ManaBarArea.ManaBar))) or frame.ManaBar
    return main, container, health, power
end

function ns.UnitFrameVisualHealth(frame)
    local state = states[frame]
    return state and state.active and state.visual and state.visual.active and state.visual.health
end

local function StyleText(state, text, font, justify)
    local saved = Remember(state, text)
    if not saved then return end
    if not saved.fontObject then saved.fontObject = text:GetFontObject() end
    if not saved.justifyH then saved.justifyH = text:GetJustifyH() end
    text:SetFontObject(font)
    text:SetJustifyH(justify)
end

local function LayoutTargetName(frame, state, name, health, width)
    if not Usable(name) then return end
    if not state.nameOverlay then
        local overlay = CreateFrame("Frame", nil, frame)
        overlay:SetFrameLevel(state.visual.power:GetFrameLevel() + 1)
        local text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetJustifyH("LEFT")
        local function Sync()
            if not state.active or not state.visual.active then return end
            text:SetText(name:GetText())
            overlay:SetShown(name:IsShown())
        end
        for _, method in ipairs({ "SetText", "SetFormattedText", "SetShown", "Show", "Hide" }) do
            hooksecurefunc(name, method, Sync)
        end
        state.nameOverlay, state.nameLabel, state.syncName = overlay, text, Sync
        table.insert(state.decorations, overlay)
    end
    local label = state.nameLabel
    label:ClearAllPoints()
    label:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 0, 4)
    label:SetWidth(math.max(20, width - 30))
    HideArt(state, name)
    state.syncName()
end

local function MirrorStatusText(state, bar, text)
    if not Usable(text) then return end
    state.textMirrors = state.textMirrors or {}
    local mirror = state.textMirrors[text]
    if not mirror then
        mirror = bar:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
        mirror:SetPoint("LEFT", bar, "LEFT", 2, 0)
        mirror:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
        mirror:SetJustifyH("RIGHT")
        state.textMirrors[text] = mirror
        table.insert(state.decorations, mirror)
        hooksecurefunc(text, "SetText", function(_, value)
            mirror:SetText(value)
            mirror:Show()
        end)
        hooksecurefunc(text, "Show", function() mirror:Show() end)
        hooksecurefunc(text, "Hide", function() mirror:Hide() end)
    end
    local saved = Remember(state, text)
    if saved then text:SetAlpha(0) end
    local font = text:GetFontObject()
    if font then mirror:SetFontObject(font) end
end

local function LayoutBarText(state, bar, container, power)
    container = container or bar
    local center = power and (container.ManaBarText or bar.ManaBarText or bar.TextString)
        or (container.HealthBarText or bar.HealthBarText or bar.TextString)
    local texts = { center, bar.TextString, bar.HealthBarText, bar.ManaBarText,
        container.HealthBarText, container.ManaBarText }
    local positioned = {}
    for _, text in ipairs(texts) do
        if Usable(text) and not positioned[text] then
            positioned[text] = true
            Move(state, text, "RIGHT", bar, "RIGHT", -5, 0)
            state.objects[text].anchorOnly = true
            text:SetWidth(bar:GetWidth())
            StyleText(state, text, "TextStatusBarText", "RIGHT")
            if text == bar.TextString or text == bar.HealthBarText or text == bar.ManaBarText then
                MirrorStatusText(state, bar, text)
            end
        end
    end
    for _, entry in ipairs({
        { container.LeftText or bar.LeftText, "LEFT", 2 },
        { container.RightText or bar.RightText, "RIGHT", -5 },
        { container.DeadText, "CENTER", 0 }, { container.UnconsciousText, "CENTER", 0 } }) do
        local text = entry[1]
        if Usable(text) then
            Move(state, text, entry[2], bar, entry[2], entry[3], 0)
            state.objects[text].anchorOnly = true
            StyleText(state, text, "TextStatusBarText", entry[2])
        end
    end
end

-- Both the personal resource display and the target use RogueComboPointTemplate.
-- Keep Blizzard's original points and animations, changing only their layout.
local comboVisual

local function RestoreComboPoints(visual)
    if not visual or not visual.enabled then return end
    visual.enabled = false
    for point, scale in pairs(visual.originalScale) do
        if Usable(point) then point:SetScale(scale) end
    end
    wipe(visual.originalScale)
    if Usable(visual.native) then
        visual.native:LayoutPointsCircle()
    end
end

local function LayoutComboPoints(visual)
    if not visual.enabled then return end
    local native = visual.native
    local count = native.maxComboPoints
    if not ns.Plain(count) or type(count) ~= "number" or count < 1
        or count > #native.ComboPoints then return end
    local anchor = visual.health
    if Usable(visual.power) then
        local shown = visual.power:IsShown()
        if ns.Plain(shown) and shown then anchor = visual.power end
    end
    if not Usable(anchor) then return end

    -- The personal resource template is 20px with a 4px gap. Fit narrow
    -- target bars proportionally and keep the row centered below the bars.
    local pointSize, spacing = 20, 4
    local rowWidth = count * pointSize + (count - 1) * spacing
    local scale = math.min(1, visual.width / rowWidth)
    for i = 1, count do
        local point = native.ComboPoints[i]
        if not Usable(point) then return end
        if visual.originalScale[point] == nil then
            local original = point:GetScale()
            if not ns.Plain(original) then return end
            visual.originalScale[point] = original
        end
    end
    for i = 1, count do
        -- The native target fills in reverse index order. Reverse the layout
        -- so that its unchanged animations fill the row from left to right.
        local point = native.ComboPoints[count - i + 1]
        if point:GetScale() ~= scale then point:SetScale(scale) end
        point:ClearAllPoints()
        point:SetPoint("TOP", anchor, "BOTTOM", (i - (count + 1) / 2) * (pointSize + spacing), -3 / scale)
    end
end

local function RefreshComboPoints(target)
    local native = _G.ComboFrame
    local db = ns.db
    local state = target and states[target]
    local enabled = state and state.active and db.enabledUnitFrames and db.unitFramesTarget
        and db.unitFramesComboPoints
    if not enabled or not Usable(native) or type(native.ComboPoints) ~= "table"
        or type(native.LayoutPointsCircle) ~= "function" then
        RestoreComboPoints(comboVisual)
        return
    end
    local _, _, health, power = Resolve(target, false)
    if state.visual then health, power = state.visual.health, state.visual.power end
    if not Usable(health) then return end
    if not comboVisual then
        local visual = { native = native, originalScale = {} }
        comboVisual = visual
        hooksecurefunc(native, "LayoutPointsCircle", function() LayoutComboPoints(visual) end)
        if Usable(power) then
            power:HookScript("OnShow", function() LayoutComboPoints(visual) end)
            power:HookScript("OnHide", function() LayoutComboPoints(visual) end)
        end
    end
    local visual = comboVisual
    visual.health, visual.power, visual.width = health, power, db.unitFramesWidth
    visual.enabled = true
    LayoutComboPoints(visual)
end

-- Fixed header slots keep native indicators from moving across the bars when
-- their visibility changes. The name/level have a separate line below them.
local function LayoutStatusHeader(frame, player, state)
    if InCombatLockdown() or not state.active or not ns.db.unitFramesHidePortrait then return end
    local main, _, health = Resolve(frame, player)
    local visual = states[frame] and states[frame].visual
    if visual and visual.health:IsShown() then health = visual.health end
    if not Usable(health) then return end
    local content = player and frame.PlayerFrameContent or frame.TargetFrameContent
    local contextual = content and (player and content.PlayerFrameContentContextual or content.TargetFrameContentContextual)
    if not contextual then return end
    local width = ns.db.unitFramesWidth
    local size, gap, pitch = 16, 2, 20
    local used, row = 0, 0
    state.statusHeaderObjects = {}
    local function Slot(w)
        if used > 0 and used + w > width then
            row, used = row + 1, 0
        end
        local x, y = -used - w / 2, 20 + row * pitch
        used = used + w + gap
        return x, y
    end
    local function Place(object, x, y, w, h)
        if not Usable(object) then return end
        table.insert(state.statusHeaderObjects, { object = object, y = y, height = h })
        -- During combat update regions only. All native frames have already
        -- been positioned outside combat and keep their visibility logic.
        if InCombatLockdown() then
            if not state.objects[object] or not object.IsObjectType
                or not (object:IsObjectType("Texture") or object:IsObjectType("FontString")) then return end
            pcall(Move, state, object, "BOTTOM", health, "TOPRIGHT", x, y, w, h)
        else
            Move(state, object, "BOTTOM", health, "TOPRIGHT", x, y, w, h)
            if not w and not h and state.objects[object] then state.objects[object].anchorOnly = true end
        end
    end
    local function Icon(object, x, y, w, h)
        Place(object, x, y, w or size, h or size)
    end
    -- The outer corner is reserved for combat/rest or the target raid marker.
    -- PvP and prestige always occupy the next slot on every unit frame.
    local x, y = Slot(size)
    if player then
        Icon(contextual.AttackIcon or _G.PlayerAttackIcon, x, y)
        HideArt(state, contextual.PlayerPortraitCornerIcon)
    else
        Icon(contextual.RaidTargetIcon, x, y)
    end
    x, y = Slot(size)
    if not player then
        Icon(contextual.PrestigePortrait, x, y, 16, 17)
        Icon(contextual.PrestigeBadge, x, y + 3, 10, 10)
    end
    x, y = Slot(size)
    Icon(contextual.LeaderIcon, x, y)
    Icon(contextual.GuideIcon, x, y)
    if player then
        x, y = Slot(size)
        Icon(contextual.RoleIcon, x, y)
        x, y = Slot(size)
        Icon(contextual.ReadyCheck, x, y)
        x, y = Slot(size)
        local playTime = contextual.PlayerPlayTime
        Icon(playTime, x, y)
        if Usable(playTime) then Icon(playTime.PlayTimeIcon, x, y) end
        x, y = Slot(54)
        local group = contextual.GroupIndicator
        if Usable(group) and Usable(_G.PlayerFrameGroupIndicatorText) then
            -- Keep the native group visibility/text, but remove its oversized banner.
            for _, region in ipairs({ group:GetRegions() }) do
                if region:IsObjectType("Texture") then HideArt(state, region) end
            end
            Place(_G.PlayerFrameGroupIndicatorText, x, y + 2, 54, 12)
        else
            Place(group, x, y)
        end
    else
        x, y = Slot(size)
        Icon(contextual.BossIcon, x, y)
        Icon(contextual.QuestIcon, x, y)
        x, y = Slot(size)
        if frame == TargetFrame then
            Icon(contextual.PetBattleIcon, -34, 9)
        else
            Icon(contextual.PetBattleIcon, x, y)
        end
        x, y = Slot(size)
        Icon(contextual.PingIconFrame, x, y)
        x, y = Slot(49)
        Place(contextual.NumericalThreat, x, y)
        -- Skull/high-level marker is an alternative to the level number.
        Icon(contextual.HighLevelTexture, -8, 4, 14, 14)
    end
    local name = player and _G.PlayerName or (main and main.Name) or frame.name
    if Usable(name) and (player or not (visual and visual.active)) then
        StyleText(state, name, "GameFontNormalSmall", "LEFT")
        Move(state, name, "BOTTOMLEFT", health, "TOPLEFT", 0, 4, math.max(20, width - 30))
        if player and state.restLabel then
            local textWidth = name:GetStringWidth()
            if ns.Plain(textWidth) and type(textWidth) == "number" then
                state.restLabel:ClearAllPoints()
                state.restLabel:SetPoint("LEFT", name, "LEFT", textWidth + 4, 0)
            end
        end
    end
    local level = player and _G.PlayerLevelText or (main and main.LevelText)
    if Usable(level) then
        local pvp = (main and main.PvpBackgroundIcon) or contextual.PvpBackgroundIcon
            or contextual.PVPIcon or contextual.PvpIcon or (player and _G.PlayerPVPIcon)
        if not player and Usable(pvp) then
            Move(state, pvp, "CENTER", health, "TOPRIGHT", frame == TargetFrame and -12 or -14, 17, 30, 30)
        end
        if player then
            local playerPvP = contextual.PVPIcon or contextual.PvpIcon or _G.PlayerPVPIcon
            local pvpX = Usable(pvp) and -14 or -16
            for _, icon in pairs({ background = pvp, faction = playerPvP, prestige = contextual.PrestigePortrait }) do
                if Usable(icon) then Move(state, icon, "CENTER", health, "TOPRIGHT", pvpX, 17, 30, 30) end
            end
            if Usable(contextual.PrestigeBadge) then
                Move(state, contextual.PrestigeBadge, "CENTER", health, "TOPRIGHT", pvpX, 17, 10, 10)
            end
            local timer = _G.PlayerPVPTimerText or contextual.PvpTimerText
            if Usable(timer) then
                Move(state, timer, "BOTTOM", Usable(pvp) and pvp or level,
                    Usable(pvp) and "TOP" or "BOTTOM", 0, 2, 34, 12)
                StyleText(state, timer, "GameFontNormalSmall", "CENTER")
            end
        end
        if not state.levelOverlay then
            local overlay = CreateFrame("Frame", nil, frame)
            overlay:SetFrameLevel(frame:GetFrameLevel() + 20)
            local text = overlay:CreateFontString(nil, "OVERLAY", "GameNormalNumberFont")
            text:SetJustifyH("CENTER")
            text:SetJustifyV("MIDDLE")
            text:SetTextColor(1, 1, 1)
            local font, size = text:GetFont()
            if font and ns.Plain(size) then text:SetFont(font, size, "OUTLINE") end
            hooksecurefunc(level, "SetText", function(_, value) text:SetText(value) end)
            hooksecurefunc(level, "SetFormattedText", function(_, ...) text:SetFormattedText(...) end)
            hooksecurefunc(level, "Show", function() if state.active then pcall(text.Show, text) end end)
            hooksecurefunc(level, "Hide", function() pcall(text.Hide, text) end)
            state.levelOverlay, state.levelMirror = overlay, text
        end
        local anchor = Usable(pvp) and pvp or health
        local anchorPoint = Usable(pvp) and "CENTER" or "TOPRIGHT"
        state.levelMirror:ClearAllPoints()
        if player then
            state.levelMirror:SetPoint("CENTER", health, "TOPRIGHT", Usable(pvp) and -12 or -14, 17)
        else
            state.levelMirror:SetPoint("CENTER", anchor, anchorPoint,
                Usable(pvp) and (frame == TargetFrame and 0 or 2) or -14, Usable(pvp) and 0 or 17)
        end
        state.levelMirror:SetSize(30, 30)
        state.levelMirror:SetText(level:GetText())
        state.levelMirror:SetShown(level:IsShown())
        state.levelOverlay:Show()
        HideArt(state, level)
        if not player and frame.unit and UnitEffectiveLevel then
            local ok, unitLevel = pcall(UnitEffectiveLevel, frame.unit)
            if ok and ns.Plain(unitLevel) and type(unitLevel) == "number" and unitLevel > 0 then
                level:Show()
                state.levelMirror:Show()
            end
        end
    end
    if main then HideArt(state, main.LevelBackgroundCircle) end
end

function ns.UnitFrameStatusAuraOffset(frame)
    return 26
end

local function UpdatePlayerStatusHeader()
    local frame = _G.PlayerFrame
    local state = frame and states[frame]
    if state and not refreshing then pcall(LayoutStatusHeader, frame, true, state) end
    if ns.LayoutPlayerFrameBuffs then ns.LayoutPlayerFrameBuffs() end
end

local function RectangularMask(state, mask, bar)
    if not Usable(mask) or not mask.SetTexture then return end
    local saved = RememberLayout(state, mask)
    if not saved then return end
    if not saved.textureSaved then
        saved.textureSaved = true
        saved.texture = mask:GetTexture()
        saved.atlas = mask.GetAtlas and mask:GetAtlas()
        saved.coords = { mask:GetTexCoord() }
    end
    mask:SetTexture("Interface\\Buttons\\WHITE8X8")
    mask:ClearAllPoints()
    mask:SetAllPoints(bar)
end

local function ApplyColor(bar, unit, power)
    if power then
        local powerType, token = UnitPowerType(unit)
        if not ns.Plain(token) or not ns.Plain(powerType) then return end
        local color = PowerBarColor[token] or PowerBarColor[powerType] or PowerBarColor.MANA
        if color then bar:SetStatusBarColor(color.r, color.g, color.b) end
    else
        if unit ~= "player" and UnitPlayerControlled and UnitIsTapDenied then
            local controlled = UnitPlayerControlled(unit)
            local denied = UnitIsTapDenied(unit)
            if ns.Plain(controlled) and ns.Plain(denied) and not controlled and denied then
                bar:SetStatusBarColor(0.5, 0.5, 0.5)
                return
            end
        end
        local isPlayer = unit == "player" or UnitIsPlayer(unit)
        local _, class = UnitClass(unit)
        local color = ns.db.unitFramesClassColor and ns.Plain(isPlayer) and isPlayer
            and ns.Plain(class) and RAID_CLASS_COLORS[class]
        if color then bar:SetStatusBarColor(color.r, color.g, color.b)
        else bar:SetStatusBarColor(0, 1, 0) end
    end
end

local function StyleBar(state, bar, border, path, unit, power)
    if not Usable(bar) or not bar.GetStatusBarTexture then return end
    local saved = Remember(state, bar)
    local texture = bar:GetStatusBarTexture()
    if not texture then return end
    if not saved.color then saved.color = { bar:GetStatusBarColor() } end
    if not saved.barTexture then
        saved.barTexture = texture:GetTexture()
        saved.barAtlas = texture.GetAtlas and texture:GetAtlas()
        saved.barCoords = { texture:GetTexCoord() }
    end
    if path then
        bar:SetStatusBarTexture(path)
        bar:GetStatusBarTexture():SetTexCoord(0, 1, 0, 1)
        ApplyColor(bar, unit, power)
    end
    local binding = state.bindings[bar]
    if not binding then
        binding = {}
        state.bindings[bar] = binding
        -- Blizzard replaces the baked-color atlas on power/form/unit updates.
        -- Reapply only cosmetic texture/color here, including during combat.
        local function MaintainStyle()
            if refreshing or restyling or not state.active or not binding.path then return end
            restyling = true
            local ok, message = pcall(function()
                bar:SetStatusBarTexture(binding.path)
                bar:GetStatusBarTexture():SetTexCoord(0, 1, 0, 1)
                ApplyColor(bar, binding.unit, binding.power)
            end)
            restyling = false
            if not ok then geterrorhandler()(message) end
        end
        binding.maintain = MaintainStyle
        hooksecurefunc(bar, "SetStatusBarTexture", MaintainStyle)
        hooksecurefunc(bar, "SetStatusBarColor", MaintainStyle)
        for _, method in ipairs({ "SetBarText", "UpdateTextString" }) do
            if type(bar[method]) == "function" then
                hooksecurefunc(bar, method, function(self)
                    if state.active and not refreshing and not InCombatLockdown() then
                        LayoutBarText(state, self, self:GetParent(), power)
                    end
                end)
            end
        end
        -- Classification also changes the texture directly, bypassing the bar.
        hooksecurefunc(texture, "SetAtlas", function()
            if not refreshing and not restyling and state.active and binding.path then
                local original = state.objects[bar]
                if original then
                    original.barTexture = texture:GetTexture()
                    original.barAtlas = texture:GetAtlas()
                    original.barCoords = { texture:GetTexCoord() }
                end
            end
            MaintainStyle()
        end)
        hooksecurefunc(texture, "SetTexture", MaintainStyle)
    end
    binding.path, binding.unit, binding.power = path, unit, power
    RectangularMask(state, bar.HealthBarMask, bar)
    RectangularMask(state, bar.ManaBarMask, bar)
    local edges = state.edges[bar]
    if not edges then
        edges = {}
        local background = bar:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(bar)
        background:SetColorTexture(0.025, 0.03, 0.04, 0.9)
        edges.background = background
        table.insert(state.decorations, background)
        for i = 1, 4 do
            local edge = bar:CreateTexture(nil, "OVERLAY", nil, 7)
            edge:SetColorTexture(0, 0, 0, 1)
            edges[i] = edge
            table.insert(state.decorations, edge)
        end
        state.edges[bar] = edges
    end
    edges.background:Show()
    local thickness = border == "thick" and 2 or 1
    for i, edge in ipairs(edges) do
        edge:ClearAllPoints()
        if i <= 2 then
            local point = i == 1 and "TOP" or "BOTTOM"
            edge:SetPoint(point .. "LEFT", bar, point .. "LEFT", -thickness, i == 1 and thickness or -thickness)
            edge:SetPoint(point .. "RIGHT", bar, point .. "RIGHT", thickness, i == 1 and thickness or -thickness)
            edge:SetHeight(thickness)
        else
            local point = i == 3 and "LEFT" or "RIGHT"
            edge:SetPoint("TOP" .. point, bar, "TOP" .. point, i == 3 and -thickness or thickness, 0)
            edge:SetPoint("BOTTOM" .. point, bar, "BOTTOM" .. point, i == 3 and -thickness or thickness, 0)
            edge:SetWidth(thickness)
        end
        edge:SetShown(border ~= "none" and border ~= "default")
    end
end

local function StyleUnitBars(state, health, power, unit)
    local db = ns.db
    local path = ns.barTextures and ns.barTextures[db.unitFramesTexture]
    StyleBar(state, health, db.unitFramesBorder, path, unit, false)
    StyleBar(state, power, db.unitFramesBorder, path, unit, true)
    return path
end

local function StyleShadow(frame, state, health, power, unit)
    local keys = {
        player = "unitFramesPlayerShadow", target = "unitFramesTargetShadow",
        focus = "unitFramesFocusShadow", targettarget = "unitFramesTargetOfTargetShadow",
    }
    if not ns.db[keys[unit]] then return end
    if not state.shadow then
        state.shadow = CreateFrame("Frame", nil, frame)
        for spread = 1, 8 do
            local texture = state.shadow:CreateTexture(nil, "BACKGROUND")
            texture:SetColorTexture(0, 0, 0, 0.055)
            texture:SetPoint("TOPLEFT", state.shadow, "TOPLEFT", -spread, spread)
            texture:SetPoint("BOTTOMRIGHT", state.shadow, "BOTTOMRIGHT", spread, -spread)
        end
        table.insert(state.decorations, state.shadow)
    end
    local shadow = state.shadow
    shadow:SetFrameStrata(health:GetFrameStrata())
    shadow:SetFrameLevel(math.max(0, math.min(health:GetFrameLevel(), power:GetFrameLevel()) - 1))
    shadow:ClearAllPoints()
    shadow:SetPoint("TOPLEFT", health, "TOPLEFT")
    local shown = power:IsShown()
    local bottom = ns.Plain(shown) and shown and power or health
    shadow:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT")
    shadow:Show()
end

local function UpdatePortrait3D(state)
    local portrait = state.portrait3D
    if not portrait or not state.active or not portrait.holder:IsShown() then return end
    if portrait.mode == "2d" then
        portrait.texture:SetTexture(nil)
        local ok = pcall(SetPortraitTexture, portrait.texture, portrait.unit, true)
        if not ok then state.pendingPortrait3D = true end
        return
    end
    -- A failed model update should leave the portrait empty rather than
    -- show the previous target's model.
    pcall(portrait.model.ClearModel, portrait.model)
    local ok = pcall(portrait.model.SetUnit, portrait.model, portrait.unit)
    if not ok then state.pendingPortrait3D = true end
end

local function LayoutPortrait3D(frame, state, bar, unit)
    if unit ~= "player" and unit ~= "target" then return end
    if not ns.db.unitFramesHidePortrait or not ns.db.unitFramesPortrait3D then return end
    local portrait = state.portrait3D
    if not portrait then
        local holder = CreateFrame("Frame", nil, frame)
        holder:SetFrameLevel(bar:GetFrameLevel() + 1)
        local background = holder:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(holder)
        local model = CreateFrame("PlayerModel", nil, holder)
        model:SetFrameLevel(holder:GetFrameLevel() + 1)
        model:SetPortraitZoom(1)
        local texture = holder:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints(holder)
        local mask = holder:CreateMaskTexture(nil, "ARTWORK")
        mask:SetAllPoints(holder)
        texture:AddMaskTexture(mask)
        local overlay = CreateFrame("Frame", nil, holder)
        overlay:SetAllPoints(holder)
        overlay:SetFrameLevel(model:GetFrameLevel() + 1)
        local border = overlay:CreateTexture(nil, "OVERLAY")
        border:SetAllPoints(overlay)
        portrait = { holder = holder, model = model, texture = texture, mask = mask,
            background = background, border = border, unit = unit }
        state.portrait3D = portrait
        local events = CreateFrame("Frame")
        events:RegisterEvent("PLAYER_TARGET_CHANGED")
        events:RegisterEvent("UNIT_MODEL_CHANGED")
        events:RegisterEvent("UNIT_PORTRAIT_UPDATE")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:SetScript("OnEvent", function(_, event, changedUnit)
            if (event == "PLAYER_TARGET_CHANGED" and unit == "target")
                or (event == "PLAYER_REGEN_ENABLED" and state.pendingPortrait3D)
                or ((event == "UNIT_MODEL_CHANGED" or event == "UNIT_PORTRAIT_UPDATE")
                    and changedUnit == unit) then
                state.pendingPortrait3D = nil
                UpdatePortrait3D(state)
            end
        end)
        portrait.events = events
    end
    local size = ns.db.unitFramesPortrait3DSize
    local radius = math.max(0, math.min(50, math.floor(ns.db.unitFramesPortrait3DRadius or 0)))
    local borderStyle = ns.db.unitFramesBorder
    portrait.mode = ns.db.unitFramesPortraitMode == "2d" and "2d" or "3d"
    local shapePath = "Interface\\AddOns\\PhalkTools\\Media\\Buttons\\Shapes\\"
    portrait.background:SetTexture(shapePath .. "Mask-" .. radius .. ".tga")
    portrait.background:SetVertexColor(0.025, 0.03, 0.04, 1)
    portrait.border:SetTexture(shapePath .. (borderStyle == "thick" and "Thick-" or "Thin-")
        .. radius .. ".tga")
    portrait.border:SetVertexColor(0, 0, 0, 1)
    portrait.border:SetShown(borderStyle == "thin" or borderStyle == "thick")
    local contentShape = borderStyle == "thick" and "ContentThick-"
        or (borderStyle == "thin" and "ContentThin-" or "Mask-")
    portrait.mask:SetTexture(shapePath .. contentShape .. radius .. ".tga",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    portrait.texture:SetShown(portrait.mode == "2d")
    portrait.model:SetShown(portrait.mode == "3d")
    local thickness = borderStyle == "thick" and 2 or 1
    -- A Model frame cannot use a Texture mask. Fit its square viewport inside
    -- the rounded opening so no model pixels extend beyond the transparent edge.
    local cornerRadius = size * radius / 100
    local inset = math.ceil(cornerRadius * (1 - 1 / math.sqrt(2))) + thickness
    portrait.model:ClearAllPoints()
    portrait.model:SetPoint("TOPLEFT", portrait.holder, "TOPLEFT", inset, -inset)
    portrait.model:SetPoint("BOTTOMRIGHT", portrait.holder, "BOTTOMRIGHT", -inset, inset)
    portrait.holder:SetSize(size, size)
    portrait.holder:ClearAllPoints()
    if unit == "player" then
        portrait.holder:SetPoint("RIGHT", bar, "LEFT", -8, 0)
    else
        portrait.holder:SetPoint("LEFT", bar, "RIGHT", 8, 0)
    end
    portrait.holder:Show()
    UpdatePortrait3D(state)
end

-- The Forever target mixin resets its protected health container to 126 pixels
-- on classification updates. These bars have fixed geometry before combat;
-- only their values change when the unit changes.
local function UpdateVisualBars(visual)
    if not visual or not visual.active then return end
    local unit = visual.unit
    visual.health:SetMinMaxValues(0, UnitHealthMax(unit))
    visual.health:SetValue(UnitHealth(unit))
    if visual.prediction then
        visual.prediction:SetMinMaxValues(0, UnitHealthMax(unit))
        local incoming = UnitGetIncomingHeals(unit)
        if not (issecretvalue and issecretvalue(incoming)) then incoming = incoming or 0 end
        visual.prediction:SetValue(incoming)
    end
    visual.power:SetMinMaxValues(0, UnitPowerMax(unit))
    visual.power:SetValue(UnitPower(unit))
    ApplyColor(visual.health, unit, false)
    ApplyColor(visual.power, unit, true)
end

local function CreateVisualBar(frame)
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetFrameLevel(frame:GetFrameLevel() + 8)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    return bar
end

local function ApplyTargetVisual(frame, state, main, container, nativeHealth, nativePower, unit)
    local db = ns.db
    local player = unit == "player"
    -- Camelot's faction-colored ReputationColor sits behind the target name.
    -- Its blue/red tint is native art, independent of the health and power bars.
    if main then
        local reputation = not player and main.ReputationColor
        if Usable(reputation) then
            SuppressPortraitTexture(state, reputation)
            if not state.reputationHooked then
                state.reputationHooked = true
                hooksecurefunc(reputation, "SetAtlas", function()
                    if state.active and ns.db and ns.db.unitFramesHidePortrait then
                        reputation:SetTexture(nil)
                    end
                end)
            end
        end
        HideArt(state, main.StatusTexture)
    end
    local visual = state.visual
    if not visual then
        visual = { unit = unit }
        visual.health = CreateVisualBar(frame)
        visual.power = CreateVisualBar(frame)
        if player then
            visual.health:SetPoint("TOP", frame, "TOP", 0, -38)
            visual.prediction = CreateVisualBar(frame)
            visual.prediction:SetFrameLevel(visual.health:GetFrameLevel() + 1)
            visual.prediction:SetPoint("TOPLEFT", visual.health:GetStatusBarTexture(), "TOPRIGHT")
            visual.prediction:SetStatusBarColor(0.28, 0.95, 0.55, 0.8)
            visual.predictionMask = visual.prediction:CreateMaskTexture(nil, "OVERLAY")
            visual.predictionMask:SetTexture("Interface\\Buttons\\WHITE8X8",
                "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            visual.predictionMask:SetAllPoints(visual.health)
            visual.prediction:GetStatusBarTexture():AddMaskTexture(visual.predictionMask)
            visual.textOverlay = CreateFrame("Frame", nil, frame)
            visual.textOverlay:SetFrameLevel(visual.prediction:GetFrameLevel() + 1)
        else
            visual.health:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -38)
        end
        visual.power:SetPoint("TOPLEFT", visual.health, "BOTTOMLEFT", 0, 0)
        local function CopyText(source, destination)
            if not Usable(source) then return end
            hooksecurefunc(source, "SetText", function(_, value) destination:SetText(value) end)
            hooksecurefunc(source, "SetFormattedText", function(_, ...) destination:SetFormattedText(...) end)
            destination:SetText(source:GetText())
        end
        for _, spec in ipairs({
            { native = container.LeftText, bar = visual.health, side = "LEFT" },
            { native = container.RightText, bar = visual.health, side = "RIGHT" },
            { native = nativePower.LeftText, bar = visual.power, side = "LEFT" },
            { native = nativePower.RightText, bar = visual.power, side = "RIGHT" },
        }) do
            local label = (visual.textOverlay or spec.bar):CreateFontString(nil, "OVERLAY", "TextStatusBarText")
            label:SetPoint(spec.side, spec.bar, spec.side,
                spec.side == "LEFT" and 5 or (spec.side == "RIGHT" and -5 or 0), 0)
            label:SetJustifyH(spec.side)
            CopyText(spec.native, label)
        end
        visual.events = CreateFrame("Frame")
        visual.events:RegisterEvent("UNIT_HEALTH")
        if player then visual.events:RegisterEvent("UNIT_HEAL_PREDICTION") end
        visual.events:RegisterEvent("UNIT_MAXHEALTH")
        visual.events:RegisterEvent("UNIT_POWER_UPDATE")
        visual.events:RegisterEvent("UNIT_MAXPOWER")
        visual.events:RegisterEvent("UNIT_DISPLAYPOWER")
        visual.events:RegisterEvent("UNIT_FACTION")
        visual.events:RegisterEvent("UNIT_FLAGS")
        visual.events:RegisterEvent("PLAYER_TARGET_CHANGED")
        visual.events:RegisterEvent("PLAYER_FOCUS_CHANGED")
        visual.events:SetScript("OnEvent", function(_, event, changedUnit)
            if not visual.active then return end
            if event == "PLAYER_TARGET_CHANGED" and unit ~= "target" then return end
            if event == "PLAYER_FOCUS_CHANGED" and unit ~= "focus" then return end
            if event:sub(1, 5) == "UNIT_" and changedUnit ~= unit then return end
            UpdateVisualBars(visual)
        end)
        state.visual = visual
    end
    visual.active = true
    visual.health:SetSize(db.unitFramesWidth, db.unitFramesHealthHeight)
    if visual.prediction then
        visual.prediction:SetSize(db.unitFramesWidth, db.unitFramesHealthHeight)
        visual.prediction:Show()
    end
    visual.power:ClearAllPoints()
    visual.power:SetPoint("TOPLEFT", visual.health, "BOTTOMLEFT", 0, -db.unitFramesSpacing)
    visual.power:SetSize(db.unitFramesWidth, db.unitFramesPowerHeight)
    local path = StyleUnitBars(state, visual.health, visual.power, unit)
    visual.health:Show()
    visual.power:Show()
    if visual.textOverlay then visual.textOverlay:Show() end
    HideArt(state, container)
    HideArt(state, nativePower)
    if player then
        HideArt(state, frame.PlayerFrameContainer)
        if Usable(_G.PlayerName) then
            Move(state, _G.PlayerName, "BOTTOMLEFT", visual.health, "TOPLEFT", 0, 4, db.unitFramesWidth - 30)
        end
        if Usable(_G.PlayerLevelText) then Move(state, _G.PlayerLevelText, "BOTTOMRIGHT", visual.health, "TOPRIGHT", 0, 4) end
    else
        LayoutTargetName(frame, state, (main and main.Name) or frame.name, visual.health, db.unitFramesWidth)
    end
    UpdateVisualBars(visual)
    if player then
        if not state.restLabel then
            state.restLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            state.restLabel:SetText("(resting)")
            state.restLabel:SetTextColor(1, 0.82, 0.2)
        end
        UpdateRestIndicator()
    end
    LayoutStatusHeader(frame, player, state)
    StyleShadow(frame, state, visual.health, visual.power, unit)
    LayoutPortrait3D(frame, state, visual.health, unit)
end

-- ToT is a small native secure button with its own aura and cast-bar clearance.
-- Keep its original frame footprint and anchor; only arrange the visual regions.
local function HideTargetOfTargetPortrait(frame, state)
    local function Hide(object)
        if not Usable(object) then return end
        local saved = Remember(state, object)
        if not saved then return end
        if not saved.visibilitySaved then
            saved.visibilitySaved = true
            saved.shown = object:IsShown()
        end
        object:SetAlpha(0)
        if object.SetTexture then SuppressPortraitTexture(state, object) end
        object:Hide()
    end
    Hide(frame.Portrait or frame.portrait)
    Hide(frame.PortraitMask or frame.portraitMask)
    Hide(frame.FrameTexture)
    local container = frame.TargetFrameContainer
    if container then
        Hide(container.Portrait)
        Hide(container.PortraitMask)
        Hide(container.FrameTexture)
        Hide(container.Flash)
    end
end

local function LayoutTargetOfTarget(frame, state, health, power)
    local db = ns.db
    if not db.unitFramesHidePortrait then return end
    HideTargetOfTargetPortrait(frame, state)
    local prefix = frame:GetName()
    if prefix then
        for _, suffix in ipairs({ "Portrait", "Texture", "Background" }) do
            HideArt(state, _G[prefix .. suffix])
        end
    end
    local width = math.max(50, math.min(112, math.floor(db.unitFramesWidth * 0.5 + 0.5)))
    local healthHeight = math.max(6, math.min(17, math.floor(db.unitFramesHealthHeight * 0.5 + 0.5)))
    local powerHeight = math.max(3, math.min(10, math.floor(db.unitFramesPowerHeight * 0.5 + 0.5)))
    local spacing = math.min(4, math.floor(db.unitFramesSpacing * 0.5 + 0.5))
    Move(state, health, "TOPRIGHT", frame, "TOPRIGHT", -6, -25, width, healthHeight)
    Move(state, power, "TOPLEFT", health, "BOTTOMLEFT", 0, -spacing, width, powerHeight)
    local name = frame.Name or frame.name
    if Usable(name) then
        Move(state, name, "BOTTOMLEFT", health, "TOPLEFT", 0, 2, width)
        state.objects[name].anchorOnly = true
        StyleText(state, name, "GameFontNormalSmall", "LEFT")
    end
    LayoutBarText(state, health, health, false)
    LayoutBarText(state, power, power, true)
    for i = 1, 4 do
        local icon = frame["Debuff" .. i] or (prefix and _G[prefix .. "Debuff" .. i])
        if Usable(icon) then
            local x = (i - 1) * 16
            Move(state, icon, "BOTTOMLEFT", health, "TOPLEFT", x, 22, 14, 14)
        end
    end
end

-- The native target mask is resized by classification changes. Replace it on
-- every fill, including the status bar itself, with our independently sized mask.
local function StyleTargetPredictionMask(state, container, health)
    local original = container.HealthBarMask
    if not Usable(original) or not health.CreateMaskTexture then return end
    if not state.targetMask then
        state.targetMask = health:CreateMaskTexture(nil, "OVERLAY")
        state.targetMask:SetTexture("Interface\\Buttons\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        state.targetMaskTargets = {}
    end
    state.targetMask:SetAllPoints(health)
    local mine, other = health.MyHealPredictionBar, health.OtherHealPredictionBar
    local absorb, healAbsorb = health.TotalAbsorbBar, health.HealAbsorbBar
    local loss = container.TempMaxHealthLoss
    for _, texture in pairs({ health = health:GetStatusBarTexture(),
        loss = loss and loss:GetStatusBarTexture(),
        mine = mine and mine.Fill, other = other and other.Fill,
        absorb = absorb and absorb.Fill, tiled = absorb and absorb.TiledFillOverlay,
        overAbsorb = health.OverAbsorbGlow, overHealAbsorb = health.OverHealAbsorbGlow,
        healAbsorb = healAbsorb and healAbsorb.Fill, left = healAbsorb and healAbsorb.LeftShadow,
        right = healAbsorb and healAbsorb.RightShadow }) do
        if Usable(texture) and texture.GetNumMaskTextures and texture.RemoveMaskTexture and texture.AddMaskTexture then
            local count = texture:GetNumMaskTextures()
            if ns.Plain(count) then
                local i = 1
                while i <= count do
                    if texture:GetMaskTexture(i) == original then
                        texture:RemoveMaskTexture(original)
                        texture:AddMaskTexture(state.targetMask)
                        state.targetMaskTargets[texture] = original
                        count = count - 1
                    else
                        i = i + 1
                    end
                end
            end
        end
    end
end

local function LayoutTargetHealthText(state, container, health)
    LayoutBarText(state, health, container, false)
end

-- Target classification changes resize and reanchor the native container even
-- in combat. Keep our bars and the native health text independent of it.
local function LayoutTargetHealth(state, container, health, frame, hidePortrait)
    local db = ns.db
    if hidePortrait then
        Move(state, container, "TOP", frame, "TOP", 0, -38, db.unitFramesWidth, db.unitFramesHealthHeight)
        Move(state, health, "TOPLEFT", container, "TOPLEFT", 0, 0, db.unitFramesWidth, db.unitFramesHealthHeight)
    else
        Move(state, health, "BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0, db.unitFramesWidth, db.unitFramesHealthHeight)
    end
    LayoutTargetHealthText(state, container, health)
    do
        local object = container.TempMaxHealthLoss
        local saved = RememberLayout(state, object)
        if saved then
            saved.anchorOnly = true
            object:ClearAllPoints()
            for _, point in ipairs(saved.points) do
                object:SetPoint(point[1], health, point[3], point[4], point[5])
            end
        end
    end
end

local function MaintainTargetPortrait(frame)
    local state = states[frame]
    if refreshing or not state or not state.active or not ns.db.unitFramesHidePortrait then return end
    local art = frame.TargetFrameContainer or frame.FocusFrameContainer
    HideArt(state, frame.portrait)
    HideArt(state, frame.Portrait)
    if art then
        for _, key in ipairs({ "Portrait", "FrameTexture", "FrameFlash", "Flash", "BossPortraitFrameTexture" }) do
            HideArt(state, art[key])
        end
    end
end

local function MaintainTargetPortraitForFrame(frame)
    local state = states[frame]
    local selection = frame == _G.FocusFrame and "unitFramesFocus" or "unitFramesTarget"
    if state and state.active and ns.db and ns.db.enabledUnitFrames
        and ns.db[selection] and ns.db.unitFramesHidePortrait then
        pcall(MaintainTargetPortrait, frame)
    end
end

local function MaintainTargetHealth(frame)
    local state = states[frame]
    if refreshing or restyling or not state or not state.active then return end
    if state.visual and state.visual.active then return end
    if InCombatLockdown() then
        state.pendingCombatLayout = true
        return
    end
    local _, container, health, power = Resolve(frame, false)
    if not Usable(container) or not Usable(health) then return end
    if not pcall(StyleTargetPredictionMask, state, container, health) then
        state.pendingCombatLayout = true
    end
    if not pcall(LayoutTargetHealthText, state, container, health) then
        state.pendingCombatLayout = true
    end
    if Usable(power) and not pcall(LayoutBarText, state, power, power, true) then
        state.pendingCombatLayout = true
    end
    LayoutTargetHealth(state, container, health, frame, ns.db.unitFramesHidePortrait)
    if Usable(power) then
        Move(state, power, "TOPLEFT", health, "BOTTOMLEFT", 0, -ns.db.unitFramesSpacing,
            ns.db.unitFramesWidth, ns.db.unitFramesPowerHeight)
    end
    local binding = state.bindings[health]
    if binding and binding.path then
        binding.maintain()
    end
    MaintainTargetPortrait(frame)
    pcall(LayoutStatusHeader, frame, false, state)
    if Usable(health.TextString) then
        pcall(function()
            Move(state, health.TextString, "RIGHT", health, "RIGHT", -5, 0)
            health.TextString:SetWidth(health:GetWidth())
            state.objects[health.TextString].anchorOnly = true
            StyleText(state, health.TextString, "TextStatusBarText", "RIGHT")
        end)
    end
end

local function Apply(frame, player, unit)
    local main, container, health, power = Resolve(frame, player)
    if not Usable(health) or not Usable(power) then return end
    local state = states[frame]
    if not state then
        state = { objects = {}, edges = {}, decorations = {}, bindings = {} }
        states[frame] = state
        frame:HookScript("OnShow", QueueRefresh)
    end
    -- Restore before a new configuration so switching styles is reversible.
    Restore(state)
    state.active = true
    state.pendingCombatLayout = nil
    local db = ns.db
    if state.visual then
        state.visual.active = false
        state.visual.health:Hide()
        state.visual.power:Hide()
        if state.visual.prediction then state.visual.prediction:Hide() end
        if state.visual.textOverlay then state.visual.textOverlay:Hide() end
    end
    if unit ~= "targettarget" and db.unitFramesHidePortrait and container then
        local art = player and frame.PlayerFrameContainer
            or (unit == "focus" and frame.FocusFrameContainer or frame.TargetFrameContainer)
        HideArt(state, frame.portrait)
        HideArt(state, frame.Portrait)
        if player then
            HideArt(state, _G.PlayerPortrait)
            HideArt(state, _G.PlayerRestIcon)
            HideArt(state, _G.PlayerRestGlow)
        end
        if art then
            for _, key in ipairs({ "Portrait", "FrameTexture", "FrameFlash", "Flash", "BossPortraitFrameTexture" }) do
                HideArt(state, art[key])
            end
        end
        ApplyTargetVisual(frame, state, main, container, health, power, unit)
        return
    end
    local path = StyleUnitBars(state, health, power, unit)
    LayoutBarText(state, health, container or health, false)
    LayoutBarText(state, power, power, true)
    -- The player's incoming-heal segments have their own atlas and tint.
    -- Replacing their fill with the bar texture obscures that visual.
    ns.StyleHealPrediction(health, player and nil or path)
    state.predictionHealth = health
    if unit ~= "targettarget" and container then
        StyleTargetPredictionMask(state, container, health)
    end
    RectangularMask(state, container and container.HealthBarMask, health)

    if unit == "targettarget" then
        LayoutTargetOfTarget(frame, state, health, power)
        StyleShadow(frame, state, health, power, unit)
        return
    end

    if db.unitFramesHidePortrait then
        -- The rest flipbook is anchored to the removed portrait and otherwise
        -- draws a large yellow ring over the new bars. Leave its animation
        -- managed by Blizzard, suppress only the decorative region.
        local content = frame.PlayerFrameContent
        local contextual = content and content.PlayerFrameContentContextual
        if player and contextual then
            HideArt(state, contextual.PlayerRestLoop)
        end
        if player then
            HideArt(state, _G.PlayerRestIcon)
            HideArt(state, _G.PlayerRestGlow)
        end
        HideArt(state, frame.portrait)
        HideArt(state, frame.Portrait)
        if player then HideArt(state, _G.PlayerPortrait) end
        local art = player and frame.PlayerFrameContainer
            or (unit == "focus" and frame.FocusFrameContainer or frame.TargetFrameContainer)
        if art then
            for _, key in ipairs({ "PlayerPortrait", "Portrait", "FrameTexture", "VehicleFrameTexture",
                "AlternatePowerFrameTexture", "FrameFlash", "Flash", "BossPortraitFrameTexture" }) do
                HideArt(state, art[key])
            end
        end
        -- Older layouts expose these as globals instead of nested regions.
        local prefix = frame:GetName()
        if prefix then
            for _, suffix in ipairs({ "Portrait", "Texture", "Background", "Flash" }) do
                HideArt(state, _G[prefix .. suffix])
            end
        end
        if main then
            for _, key in ipairs({ "StatusTexture", "LevelBackgroundCircle", "ReputationColor" }) do HideArt(state, main[key]) end
        end
        local width = db.unitFramesWidth
        if not player and container then
            LayoutTargetHealth(state, container, health, frame, true)
        else
            local holder = container or health
            Move(state, holder, "TOP", frame, "TOP", 0, -38, width, db.unitFramesHealthHeight)
            if container then
                Move(state, health, "TOPLEFT", container, "TOPLEFT", 0, 0, width, db.unitFramesHealthHeight)
            end
        end
        Move(state, power, "TOPLEFT", health, "BOTTOMLEFT", 0, -db.unitFramesSpacing, width, db.unitFramesPowerHeight)
        local name = player and _G.PlayerName or (main and main.Name) or frame.name
        if Usable(name) then Move(state, name, "BOTTOMLEFT", health, "TOPLEFT", 0, 4, width - (player and 60 or 30)) end
        local level = player and _G.PlayerLevelText or (main and main.LevelText)
        if Usable(level) then Move(state, level, "BOTTOMRIGHT", health, "TOPRIGHT", 0, 4) end
        if player then
            if not state.restLabel then
                state.restLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                state.restLabel:SetText("(resting)")
                state.restLabel:SetTextColor(1, 0.82, 0.2)
                state.restLabel:SetShadowOffset(1, -1)
            end
            UpdateRestIndicator()
        end
        LayoutStatusHeader(frame, player, state)
    elseif not player and container then
        LayoutTargetHealth(state, container, health, frame, false)
        Move(state, power, "TOPLEFT", health, "BOTTOMLEFT", 0, -db.unitFramesSpacing, db.unitFramesWidth, db.unitFramesPowerHeight)
    else
        local holder = container or health
        local point, relative, relativePoint, x, y = holder:GetPoint(1)
        if point then
            Move(state, holder, point, relative, relativePoint, x, y, db.unitFramesWidth, db.unitFramesHealthHeight)
            if container then Move(state, health, "TOPLEFT", container, "TOPLEFT", 0, 0, db.unitFramesWidth, db.unitFramesHealthHeight) end
            Move(state, power, "TOPLEFT", health, "BOTTOMLEFT", 0, -db.unitFramesSpacing, db.unitFramesWidth, db.unitFramesPowerHeight)
        end
    end
    StyleShadow(frame, state, health, power, unit)
    LayoutPortrait3D(frame, state, health, unit)
end

function ns.RefreshUnitFrames()
    if refreshing or InCombatLockdown() or not ns.db then return end
    if ns.ReleaseUnitFrameTextureBarLayouts then ns.ReleaseUnitFrameTextureBarLayouts() end
    refreshing = true
    local ok, message = pcall(function()
        local target = _G.TargetFrame
        local player = _G.PlayerFrame
        local stylePlayer = ns.db.enabledUnitFrames and ns.db.unitFramesPlayer
        local styleTarget = ns.db.enabledUnitFrames and ns.db.unitFramesTarget
        RaiseUnitCombatText(player, player and player.PlayerFrameContent, stylePlayer)
        RaiseUnitCombatText(target, target and target.TargetFrameContent, styleTarget)
        SetCombatTextLayer(_G.CombatText, stylePlayer or styleTarget)
        local tot = (target and target.totFrame) or _G.TargetFrameToT or _G.TargetofTargetFrame
        for _, entry in ipairs({ { _G.PlayerFrame, "unitFramesPlayer", true, "player" },
            { target, "unitFramesTarget", false, "target" },
            { _G.FocusFrame, "unitFramesFocus", false, "focus" },
            { tot, "unitFramesTargetOfTarget", false, "targettarget" } }) do
            local frame = entry[1]
            if Usable(frame) then
                local frameOK, frameMessage = true, nil
                if ns.db.enabledUnitFrames and ns.db[entry[2]] then
                    frameOK, frameMessage = pcall(Apply, frame, entry[3], entry[4])
                elseif states[frame] then
                    frameOK, frameMessage = pcall(Restore, states[frame])
                end
                if not frameOK then geterrorhandler()(frameMessage) end
            end
        end
        RefreshComboPoints(target)
    end)
    refreshing = false
    if not ok then geterrorhandler()(message) end
end

function ns.InitUnitFrames()
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ADDON_LOADED",
        "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_UPDATE_RESTING",
        "PLAYER_REGEN_DISABLED", "PLAYER_FLAGS_CHANGED", "UNIT_FACTION", "UNIT_TARGET" }) do events:RegisterEvent(event) end
    -- This event is not available on every client build. The PvP hooks and
    -- faction/flag events still keep the header updated if it is unavailable.
    pcall(events.RegisterEvent, events, "PVP_TIMER_UPDATE")
    pcall(events.RegisterEvent, events, "PLAYER_PVP_FLAG_CHANGED")
    events:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_TARGET" then
            if ns.Plain(unit) and unit == "target" and ns.db and ns.db.enabledUnitFrames
                and ns.db.unitFramesTargetOfTarget then QueueRefresh() end
            return
        end
        if event == "PLAYER_TARGET_CHANGED" then MaintainTargetPortraitForFrame(_G.TargetFrame) end
        if event == "PLAYER_FOCUS_CHANGED" then MaintainTargetPortraitForFrame(_G.FocusFrame) end
        UpdateRestIndicator()
        if event == "PVP_TIMER_UPDATE" or event == "PLAYER_PVP_FLAG_CHANGED" then
            UpdatePlayerStatusHeader()
        elseif event ~= "PLAYER_UPDATE_RESTING" and event ~= "PLAYER_REGEN_DISABLED" then
            QueueRefresh()
        end
        if event == "PLAYER_REGEN_ENABLED" then
            C_Timer.After(0.15, function()
                if InCombatLockdown() then return end
                for _, state in pairs(states) do
                    if state.pendingCombatLayout then
                        ns.RefreshUnitFrames()
                        return
                    end
                end
            end)
        end
    end)
    -- These hooks only update our decoration after Blizzard has finished.
    -- Never call the original status functions from addon execution context.
    for _, name in ipairs({ "PlayerFrame_UpdateStatus", "PlayerFrame_UpdatePlayerRestLoop",
        "PlayerFrame_UpdateStatusTextureVisuals" }) do
        if type(_G[name]) == "function" then hooksecurefunc(name, UpdateRestIndicator) end
    end
    for _, name in ipairs({ "PlayerFrame_UpdatePvPStatus", "PlayerFrame_UpdatePvPTimerText",
        "PlayerFrame_UpdateArt", "PlayerFrame_UpdatePlayerNameTextAnchor", "PlayerFrame_UpdateRolesAssigned",
        "PlayerFrame_UpdatePlaytime" }) do
        if type(_G[name]) == "function" then hooksecurefunc(name, UpdatePlayerStatusHeader) end
    end
    for _, frame in pairs({ TargetFrame, FocusFrame }) do
        if Usable(frame) then
            frame:HookScript("OnShow", function(self)
                MaintainTargetPortraitForFrame(self)
                QueueRefresh()
            end)
            local container = frame.TargetFrameContainer or frame.FocusFrameContainer
            if Usable(container) then
                container:HookScript("OnShow", function() MaintainTargetPortraitForFrame(frame) end)
            end
            for _, method in ipairs({ "CheckFaction", "CheckClassification", "CheckLevel", "CheckPartyLeader", "CheckBattlePet" }) do
                if type(frame[method]) == "function" then
                    hooksecurefunc(frame, method, function(self)
                        local state = states[self]
                        if state and not refreshing then pcall(LayoutStatusHeader, self, false, state) end
                    end)
                end
            end
            if type(frame.UpdateHealthBarVisuals) == "function" then
                hooksecurefunc(frame, "UpdateHealthBarVisuals", MaintainTargetHealth)
            end
            for _, method in ipairs({ "Update", "HealthUpdate", "CheckClassification", "UpdatePortrait" }) do
                if type(frame[method]) == "function" then
                    hooksecurefunc(frame, method, function(self)
                        MaintainTargetHealth(self)
                        MaintainTargetPortraitForFrame(self)
                    end)
                end
            end

        end
    end
    local targetOfTarget = (TargetFrame and TargetFrame.totFrame) or _G.TargetFrameToT or _G.TargetofTargetFrame
    if Usable(targetOfTarget) and type(targetOfTarget.Update) == "function" then
        hooksecurefunc(targetOfTarget, "Update", function(self)
            local state = states[self]
            if state and state.active and ns.db.unitFramesHidePortrait then
                pcall(HideTargetOfTargetPortrait, self, state)
            end
        end)
    end
    if type(_G.UnitFrame_Update) == "function" then
        hooksecurefunc("UnitFrame_Update", function(frame)
            if frame ~= targetOfTarget then return end
            local state = states[frame]
            if state and state.active and ns.db.unitFramesHidePortrait then
                pcall(HideTargetOfTargetPortrait, frame, state)
            end
        end)
    end
    if EventRegistry then EventRegistry:RegisterCallback("EditMode.Exit", QueueRefresh) end
end
