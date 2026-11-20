local _, ns = ...

local buttons, roots = {}, {}
local cooldownManagerHooks = setmetatable({}, { __mode = "k" })
local cooldownLabels = setmetatable({}, { __mode = "k" })
local rangeSources = setmetatable({}, { __mode = "k" })
local alphaState = setmetatable({}, { __mode = "k" })
local refreshing, queued, editing = false, false, false
local finishes = {
    gloss = "Gloss", glass = "Glass", crystal = "Crystal", lacquer = "Lacquer",
    chrome = "Chrome", obsidian = "Obsidian", soft = "Soft",
}
local finishPath = "Interface\\AddOns\\PhalkTools\\Media\\Buttons\\"

local unpack = unpack or table.unpack

local groups = {
    { root = "MainActionBar", prefix = "ActionButton", count = 12, option = "actionBarsMain" },
    { root = "MultiBarBottomLeft", prefix = "MultiBarBottomLeftButton", count = 12, option = "actionBarsExtra" },
    { root = "MultiBarBottomRight", prefix = "MultiBarBottomRightButton", count = 12, option = "actionBarsExtra" },
    { root = "MultiBarRight", prefix = "MultiBarRightButton", count = 12, option = "actionBarsExtra" },
    { root = "MultiBarLeft", prefix = "MultiBarLeftButton", count = 12, option = "actionBarsExtra" },
    { root = "MultiBar5", prefix = "MultiBar5Button", count = 12, option = "actionBarsExtra" },
    { root = "MultiBar6", prefix = "MultiBar6Button", count = 12, option = "actionBarsExtra" },
    { root = "MultiBar7", prefix = "MultiBar7Button", count = 12, option = "actionBarsExtra" },
    { root = "PetActionBar", prefix = "PetActionButton", count = 10, option = "actionBarsPet" },
    { root = "StanceBar", prefix = "StanceButton", count = 10, option = "actionBarsStance" },
}

local function Usable(object)
    return object and not (object.IsForbidden and object:IsForbidden())
end

local function SetAlpha(object, alpha)
    if not Usable(object) or not object.SetAlpha then return end
    if alphaState[object] == nil then alphaState[object] = object:GetAlpha() end
    object:SetAlpha(alpha)
end

local function RestoreAlpha(object)
    if object and alphaState[object] ~= nil then
        object:SetAlpha(alphaState[object])
        alphaState[object] = nil
    end
end

local function QueueRefresh()
    if queued or refreshing then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        ns.RefreshActionBars()
    end)
end

local function Region(button, key)
    local overlay = button.TextOverlayContainer
    local name = button:GetName()
    return (overlay and overlay[key]) or button[key] or (name and _G[name .. key])
end

local function ButtonIcon(button)
    local icon = button.icon or button.Icon or Region(button, "Icon")
    if Usable(icon) and icon.Icon and icon.Icon.SetTexCoord then return icon.Icon end
    return icon
end

local shapePath = finishPath .. "Shapes\\"

local function RestoreMasks(state)
    if not state.maskTargets then return end
    for texture, originals in pairs(state.maskTargets) do
        texture:RemoveMaskTexture(originals.appliedMask)
        for _, mask in ipairs(originals) do texture:AddMaskTexture(mask) end
    end
    wipe(state.maskTargets)
end

local function RoundTexture(state, texture, mask)
    if not Usable(texture) or not texture.AddMaskTexture or not texture.GetNumMaskTextures then return end
    if state.maskTargets[texture] then return end
    local originals = {}
    local count = texture:GetNumMaskTextures()
    if not ns.Plain(count) then return end
    for i = 1, count do originals[i] = texture:GetMaskTexture(i) end
    for _, mask in ipairs(originals) do texture:RemoveMaskTexture(mask) end
    originals.appliedMask = mask or state.roundMask
    state.maskTargets[texture] = originals
    texture:AddMaskTexture(originals.appliedMask)
end

local function RestoreCooldownSwipes(state)
    if not state.cooldownSwipes then return end
    for cooldown, saved in pairs(state.cooldownSwipes) do
        cooldown:SetSwipeTexture(saved.texture, unpack(saved.color))
        if saved.circular ~= nil then cooldown:SetUseCircularEdge(saved.circular) end
        if saved.points then
            cooldown:ClearAllPoints()
            for _, point in ipairs(saved.points) do cooldown:SetPoint(unpack(point, 1, 5)) end
        end
    end
    wipe(state.cooldownSwipes)
end

local function RestoreProcGlow(state)
    if not state.procGlow then return end
    for object, saved in pairs(state.procGlow) do
        object:ClearAllPoints()
        object:SetSize(saved.width, saved.height)
        for _, point in ipairs(saved.points) do object:SetPoint(unpack(point, 1, 5)) end
    end
    wipe(state.procGlow)
end

local function AlignProcGlow(button, state)
    local alert = button.SpellActivationAlert
    local icon = state.relative
    if not Usable(alert) or not Usable(icon) or (InCombatLockdown() and alert:IsProtected()) then return end
    local width, height = icon:GetSize()
    if not ns.Plain(width) or not ns.Plain(height) or width <= 0 or height <= 0 then return end
    state.procGlow = state.procGlow or {}
    local function SaveLayout(object)
        if state.procGlow[object] then return end
        local w, h = object:GetSize()
        local points = {}
        for i = 1, object:GetNumPoints() do points[i] = { object:GetPoint(i) } end
        state.procGlow[object] = { width = w, height = h, points = points }
    end
    SaveLayout(alert)
    -- The flipbook has transparent margins. Blizzard gives its frame a 40% bleed.
    alert:ClearAllPoints()
    alert:SetPoint("TOPLEFT", icon, "TOPLEFT", -width * 0.2, height * 0.2)
    alert:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", width * 0.2, -height * 0.2)
    if Usable(alert.ProcAltGlow) then
        SaveLayout(alert.ProcAltGlow)
        alert.ProcAltGlow:ClearAllPoints()
        alert.ProcAltGlow:SetAllPoints(alert)
    end
end

local function StyleCooldownSwipes(button, state)
    if state.nativeArt then return end
    state.cooldownSwipes = state.cooldownSwipes or {}
    local shape = shapePath .. "Mask-" .. state.radius .. ".tga"
    for _, entry in ipairs({
        { button.cooldown or button.Cooldown or Region(button, "Cooldown")
            or (button.Icon and (button.Icon.Cooldown or Region(button.Icon, "Cooldown"))), { 0, 0, 0, 0.64 } },
        { button.lossOfControlCooldown, { 0.17, 0, 0, 0.64 } },
    }) do
        local cooldown, color = entry[1], entry[2]
        local styled = Usable(cooldown) and state.cooldownSwipes[cooldown]
        if styled and styled.points and state.relative then
            cooldown:ClearAllPoints()
            cooldown:SetAllPoints(state.relative)
        elseif Usable(cooldown) and cooldown.SetSwipeTexture and not styled then
            local texture = cooldown.GetSwipeTexture and cooldown:GetSwipeTexture()
            if cooldown.GetSwipeColor then
                local r, g, b, a = cooldown:GetSwipeColor()
                if ns.Plain(r) and ns.Plain(g) and ns.Plain(b) and ns.Plain(a)
                    and type(r) == "number" and type(a) == "number" then color = { r, g, b, a } end
            end
            local saved = { texture = ns.Plain(texture) and (type(texture) == "string" or type(texture) == "number") and texture or "", color = color }
            state.cooldownSwipes[cooldown] = saved
            if state.relative then
                saved.points = {}
                for i = 1, cooldown:GetNumPoints() do saved.points[i] = { cooldown:GetPoint(i) } end
                cooldown:ClearAllPoints()
                cooldown:SetAllPoints(state.relative)
            end
            cooldown:SetSwipeTexture(shape, unpack(color))
            if cooldown.SetUseCircularEdge and state.radius == 50 then
                saved.circular = cooldown.GetUseCircularEdge and cooldown:GetUseCircularEdge() or false
                cooldown:SetUseCircularEdge(true)
            end
        end
    end
end

local function RestoreButton(button, state)
    if not state.active then return end
    state.active = false
    RestoreMasks(state)
    RestoreCooldownSwipes(state)
    RestoreProcGlow(state)
    if state.roundBorder then state.roundBorder:Hide() end
    if state.nextMeleeRing then state.nextMeleeRing:Hide() end
    if state.background then state.background:Hide() end
    if state.cooldownPulse then
        state.cooldownPulseAnim:Stop()
        state.cooldownPulse:Hide()
    end
    RestoreAlpha(button)
    for object, saved in pairs(state.regions) do
        RestoreAlpha(object)
        if saved.font then object:SetFont(unpack(saved.font)) end
        if saved.coords then object:SetTexCoord(unpack(saved.coords)) end
        if saved.effectTexture then
            if saved.atlas then object:SetAtlas(saved.atlas) else object:SetTexture(saved.texture) end
            object:SetTexCoord(unpack(saved.hoverCoords))
            object:SetBlendMode(saved.blend)
            object:SetVertexColor(unpack(saved.color))
            object:ClearAllPoints()
            for _, point in ipairs(saved.points) do object:SetPoint(unpack(point)) end
            object:SetSize(saved.width, saved.height)
            if saved.snap ~= nil and object.SetSnapToPixelGrid then object:SetSnapToPixelGrid(saved.snap) end
            if saved.bias ~= nil and object.SetTexelSnappingBias then object:SetTexelSnappingBias(saved.bias) end
            saved.effectTexture = nil
        end
    end
    state.finish:Hide()
    state.shine:Hide()
end

local function RememberRegion(state, object)
    if not Usable(object) then return end
    if not state.regions[object] then state.regions[object] = {} end
    return state.regions[object]
end

local function StyleText(button, state, key, shown, object)
    object = object or Region(button, key)
    local saved = RememberRegion(state, object)
    if not saved then return end
    SetAlpha(object, shown and 1 or 0)
    if object.GetFont and object.SetFont then
        if not saved.font then saved.font = { object:GetFont() } end
        if saved.font[1] then object:SetFont(saved.font[1], ns.db.actionBarsFontSize, saved.font[3]) end
    end
end

-- The native pushed/checked/spell textures have their own baked square art.
-- Replace the art itself, keeping all engine-controlled visibility and animation.
local function StyleEffect(state, texture, relative, radius, shape, blend, r, g, b, a)
    local saved = RememberRegion(state, texture)
    if not saved or not texture.SetTexture then return end
    if not saved.effectTexture then
        saved.effectTexture = true
        saved.texture = texture:GetTexture()
        saved.atlas = texture.GetAtlas and texture:GetAtlas()
        saved.hoverCoords = { texture:GetTexCoord() }
        saved.blend = texture:GetBlendMode()
        saved.color = { texture:GetVertexColor() }
        saved.points = {}
        for i = 1, texture:GetNumPoints() do saved.points[i] = { texture:GetPoint(i) } end
        saved.width, saved.height = texture:GetSize()
        saved.snap = texture.GetSnapToPixelGrid and texture:GetSnapToPixelGrid()
        saved.bias = texture.GetTexelSnappingBias and texture:GetTexelSnappingBias()
    elseif texture.GetAtlas and texture:GetAtlas() then
        -- Blizzard can replace pushed art and cast/channel atlases at runtime.
        -- Keep the latest native asset for restoration, but retain native anchors.
        saved.atlas = texture:GetAtlas()
        saved.texture = texture:GetTexture()
        saved.hoverCoords = { texture:GetTexCoord() }
        saved.width, saved.height = texture:GetSize()
    end
    texture:SetTexture(shapePath .. shape .. "-" .. radius .. ".tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    texture:SetTexCoord(0, 1, 0, 1)
    texture:ClearAllPoints()
    texture:SetAllPoints(relative)
    texture:SetBlendMode(blend)
    texture:SetVertexColor(r, g, b, a)
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
end

local function StyleButtonFeedback(button, state)
    local relative, radius = state.relative, state.radius
    if not relative or not state.outlineMask then return end
    local pushed = (button.GetPushedTexture and button:GetPushedTexture()) or button.PushedTexture
    local checked = (button.GetCheckedTexture and button:GetCheckedTexture()) or button.CheckedTexture
    local hover = (button.GetHighlightTexture and button:GetHighlightTexture()) or button.HighlightTexture
    -- A dark pressed fill, gold active outline and red auto-repeat flash are
    -- distinct feedback states. The native button still decides when they show.
    StyleEffect(state, pushed, relative, radius, "Mask", "BLEND", 0, 0, 0, 0.38)
    local activeRing = ns.db.actionBarsBorder == "thick" and "Thick" or "Thin"
    StyleEffect(state, checked, relative, radius, activeRing, "ADD", 1, 0.82, 0.28, 1)
    StyleEffect(state, hover, relative, radius, "Hover", "BLEND", 1, 0.86, 0.45, 0.85)
    StyleEffect(state, button.SpellHighlightTexture, relative, radius, activeRing, "ADD", 1, 0.85, 0.40, 1)
    StyleEffect(state, button.NewActionTexture, relative, radius, "Hover", "BLEND", 1, 0.86, 0.45, 1)
    StyleEffect(state, button.Flash, relative, radius, "Hover", "ADD", 1, 0.22, 0.12, 1)
    for _, texture in pairs({ pushed = pushed, checked = checked, hover = hover,
        spell = button.SpellHighlightTexture, newAction = button.NewActionTexture, flash = button.Flash }) do
        RoundTexture(state, texture, state.outlineMask)
    end
end

-- IsCurrentSpell matches the queued rank exactly on Forever. Check every
-- classic rank instead of the ID represented by an action or macro slot.
local nextMeleeRanks = {
    { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 },
    { 845, 7369, 11608, 11609, 20569 },
    { 2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266 },
    { 6807, 6808, 6809, 8972, 9745, 9880, 9881 },
}
local nextMeleeFamily = {}
for family, ranks in ipairs(nextMeleeRanks) do
    for _, spellID in ipairs(ranks) do nextMeleeFamily[spellID] = family end
end

local function RefreshNextMeleeRings()
    if not C_Spell or not C_Spell.IsCurrentSpell then return end
    local queuedFamily
    for family, ranks in ipairs(nextMeleeRanks) do
        for _, spellID in ipairs(ranks) do
            if C_Spell.IsCurrentSpell(spellID) then
                queuedFamily = family
                break
            end
        end
        if queuedFamily then break end
    end
    for button, state in pairs(buttons) do
        local ring = state.nextMeleeRing
        if ring and state.active then
            pcall(function()
                local actionType, actionID = GetActionInfo(button.action)
                local spellID = actionType == "spell" and actionID
                if actionType == "macro" and type(GetMacroSpell) == "function" then
                    spellID = GetMacroSpell(actionID)
                end
                ring:SetAlpha(queuedFamily and nextMeleeFamily[spellID] == queuedFamily and 1 or 0)
            end)
        end
    end
end

local function StyleNextMeleeRing(button, state)
    if not state.nextMeleeRing then
        -- Same top sublevel as our black border, created after it so the
        -- amber detail is visible instead of being painted underneath it.
        state.nextMeleeRing = button:CreateTexture(nil, "OVERLAY", nil, 7)
        state.nextMeleeRing:SetBlendMode("ADD")
    end
    local ring = state.nextMeleeRing
    ring:SetTexture(shapePath .. "Thick-" .. state.radius .. ".tga")
    ring:SetVertexColor(1, 0.7, 0.12, 1)
    ring:ClearAllPoints()
    ring:SetAllPoints(state.relative)
    ring:SetAlpha(0)
    ring:Show()
end

local function StyleCastFeedback(button, state)
    local cast = button.SpellCastAnimFrame
    if not Usable(cast) or not state.relative then return end
    local relative, radius = state.relative, state.radius
    local fill, burst = cast.Fill, cast.EndBurst
    if Usable(fill) then
        -- The cast fill translates across the icon; change the mask, not its
        -- animated position or texture. The glow itself uses our rounded art.
        if not state.castMask then state.castMask = fill:CreateMaskTexture(nil, "ARTWORK") end
        state.castMask:SetTexture(shapePath .. "Mask-" .. radius .. ".tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        state.castMask:ClearAllPoints()
        state.castMask:SetAllPoints(relative)
        RoundTexture(state, fill.CastFill, state.castMask)
        StyleEffect(state, fill.InnerGlowTexture, relative, radius, "Hover", "ADD", 1, 0.85, 0.45, 1)
        RoundTexture(state, fill.InnerGlowTexture, state.castMask)
    end
    if Usable(burst) then
        if not state.burstMask then state.burstMask = burst:CreateMaskTexture(nil, "ARTWORK") end
        state.burstMask:SetTexture(shapePath .. "Mask-" .. radius .. ".tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        state.burstMask:ClearAllPoints()
        state.burstMask:SetAllPoints(relative)
        StyleEffect(state, burst.GlowRing, relative, radius, "Hover", "ADD", 1, 0.91, 0.66, 1)
        RoundTexture(state, burst.GlowRing, state.burstMask)
    end
end

local function StyleInterruptFeedback(button, state)
    if state.nativeArt then return end
    local display = button.InterruptDisplay
    if not Usable(display) or not state.relative then return end
    local base = display.Base and display.Base.Base
    local highlight = display.Highlight and display.Highlight.HighlightTexture
    local shape = ns.db.actionBarsBorder == "thick" and "Thick" or "Thin"
    StyleEffect(state, base, state.relative, state.radius, shape, "ADD", 1, 0.15, 0.12, 1)
    -- The native 128px moving highlight is square and extends outside the
    -- icon. Keep Blizzard's display timing while suppressing that artwork.
    StyleEffect(state, highlight, state.relative, state.radius, "Mask", "BLEND", 0, 0, 0, 0)
end

local function StyleCooldownFeedback(button, state)
    local flash = button.CooldownFlash
    if not Usable(flash) or not Usable(flash.Flipbook) or not flash.CreateTexture then return end
    if not state.cooldownPulse then
        -- The native flipbook contains a square glow in every frame. Use a
        -- shaped pulse, triggered by the same native setup and parent lifetime.
        local pulse = flash:CreateTexture(nil, "ARTWORK", nil, 1)
        pulse:SetBlendMode("ADD")
        local anim = pulse:CreateAnimationGroup()
        local fade = anim:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetDuration(0.75)
        fade:SetSmoothing("OUT")
        state.cooldownPulse, state.cooldownPulseAnim = pulse, anim
        if type(flash.Setup) == "function" then
            hooksecurefunc(flash, "Setup", function()
                if not state.active or InCombatLockdown() then return end
                anim:Stop()
                pulse:Show()
                anim:Play()
            end)
        end
    end
    local pulse = state.cooldownPulse
    pulse:SetTexture(shapePath .. "Hover-" .. state.radius .. ".tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    pulse:SetTexCoord(0, 1, 0, 1)
    pulse:ClearAllPoints()
    pulse:SetAllPoints(state.relative)
    pulse:SetVertexColor(1, 0.94, 0.76, 1)
    RememberRegion(state, flash.Flipbook)
    SetAlpha(flash.Flipbook, 0)
    -- An already running native flash can finish with the new visual.
    if flash:IsShown() then
        pulse:Show()
        state.cooldownPulseAnim:Play()
    else
        pulse:Hide()
    end
end

local function BorderColor()
    if ns.db.actionBarsBorderColor == "custom" then
        return ns.db.actionBarsBorderR, ns.db.actionBarsBorderG, ns.db.actionBarsBorderB
    elseif ns.db.actionBarsBorderColor == "class" then
        local _, class = UnitClass("player")
        local color = ns.Plain(class) and RAID_CLASS_COLORS[class]
        if color then return color.r, color.g, color.b end
    elseif ns.db.actionBarsBorderColor == "gold" then
        return 0.85, 0.65, 0.2
    end
    return 0, 0, 0
end

function ns.OpenActionBorderColorPicker()
    if not ColorPickerFrame and C_AddOns then C_AddOns.LoadAddOn("Blizzard_ColorPickerFrame") end
    if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
    local previous = { mode = ns.db.actionBarsBorderColor, r = ns.db.actionBarsBorderR,
        g = ns.db.actionBarsBorderG, b = ns.db.actionBarsBorderB }
    local r, g, b = BorderColor()
    local function Changed()
        if Settings and Settings.NotifyUpdate then Settings.NotifyUpdate("PhalkTools_actionBarsBorderColor") end
        ns.RefreshActionBars()
    end
    ColorPickerFrame:SetupColorPickerAndShow({
        r = r, g = g, b = b, hasOpacity = false,
        swatchFunc = function()
            ns.db.actionBarsBorderR, ns.db.actionBarsBorderG, ns.db.actionBarsBorderB = ColorPickerFrame:GetColorRGB()
            ns.db.actionBarsBorderColor = "custom"
            Changed()
        end,
        cancelFunc = function()
            ns.db.actionBarsBorderColor = previous.mode
            ns.db.actionBarsBorderR, ns.db.actionBarsBorderG, ns.db.actionBarsBorderB = previous.r, previous.g, previous.b
            Changed()
        end,
    })
end

-- The native empty-slot background also contains frame art. Suppress all
-- three native decorative layers whenever a custom shape or border is used.
-- Blizzard can replace the normal atlas when changing bar art or layout.
local function ApplyNativeArt(button, state)
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    for _, object in pairs({
        normal = normal, normalRegion = button.NormalTexture,
        slot = button.SlotArt, background = button.SlotBackground,
    }) do
        if RememberRegion(state, object) then
            if state.nativeArt then RestoreAlpha(object) else SetAlpha(object, 0) end
        end
    end
    if state.isCooldownManager and not state.nativeArt then
        for _, parent in ipairs({ button, button.Icon }) do
            if Usable(parent) and parent.GetRegions then
                for _, region in ipairs({ parent:GetRegions() }) do
                    if Usable(region) and region.GetAtlas and region:GetAtlas() == "UI-HUD-CoolDownManager-IconOverlay" then
                        if RememberRegion(state, region) then SetAlpha(region, 0) end
                    end
                end
            end
        end
    end
end

local function StyleButton(button, isCooldownManager)
    local state = buttons[button]
    if not state then
        state = { regions = {} }
        buttons[button] = state
        -- Cosmetic textures on the existing button; no action attributes,
        -- click handlers, cooldown state or key bindings are changed.
        state.background = button:CreateTexture(nil, "BACKGROUND", nil, -1)
        state.background:SetColorTexture(0.055, 0.06, 0.065, 1)
        state.background:Hide()
        if type(button.UpdateButtonArt) == "function" then
            hooksecurefunc(button, "UpdateButtonArt", function()
                if state.active and not InCombatLockdown() then
                    ApplyNativeArt(button, state)
                    StyleButtonFeedback(button, state)
                    StyleCooldownSwipes(button, state)
                end
            end)
        end
        local cast = button.SpellCastAnimFrame
        if Usable(cast) and type(cast.SetupAnimAtlases) == "function" then
            hooksecurefunc(cast, "SetupAnimAtlases", function()
                if state.active and not InCombatLockdown() then StyleCastFeedback(button, state) end
            end)
        end
        state.finish = button:CreateTexture(nil, "ARTWORK", nil, 1)
        state.finish:SetBlendMode("BLEND")
        state.shine = button:CreateTexture(nil, "ARTWORK", nil, 2)
        state.shine:SetBlendMode("BLEND")
        for _, layer in ipairs({ state.finish, state.shine }) do
            if layer.SetSnapToPixelGrid then layer:SetSnapToPixelGrid(false) end
            if layer.SetTexelSnappingBias then layer:SetTexelSnappingBias(0) end
        end
        button:HookScript("OnShow", QueueRefresh)
    end
    RestoreButton(button, state)
    state.active = true
    state.isCooldownManager = isCooldownManager == true
    local db = ns.db
    local border = db.actionBarsBorder
    local radius = math.floor(math.max(0, math.min(50, tonumber(db.actionBarsRadius) or 0)))
    state.nativeArt = border == "default" and radius == 0
    ApplyNativeArt(button, state)
    local icon = ButtonIcon(button)
    if Usable(icon) then
        local saved = RememberRegion(state, icon)
        if not saved.coords then saved.coords = { icon:GetTexCoord() } end
        local crop = db.actionBarsZoom / 100
        if crop > 0 then icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop) end
    end
    local relative = Usable(icon) and icon or button
    state.relative, state.radius = relative, radius
    state.background:ClearAllPoints()
    state.background:SetAllPoints(relative)
    state.background:SetShown(not state.nativeArt)
    local r, g, b = BorderColor()
    local finish = finishes[db.actionBarsFinish]
    if finish then
        local intensity = math.max(0, math.min(100, tonumber(db.actionBarsFinishIntensity) or 75)) / 100
        state.finish:SetTexture(finishPath .. finish .. "-Shade.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        state.shine:SetTexture(finishPath .. finish .. "-Light.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        for _, layer in ipairs({ state.finish, state.shine }) do
            layer:SetAllPoints(relative)
            layer:SetAlpha(intensity)
            layer:Show()
        end
    else
        state.finish:Hide()
        state.shine:Hide()
    end
    if not state.roundMask then
        state.roundMask = button:CreateMaskTexture(nil, "ARTWORK")
        state.outlineMask = button:CreateMaskTexture(nil, "ARTWORK")
        state.sheenMask = button:CreateMaskTexture(nil, "ARTWORK")
        state.roundBorder = button:CreateTexture(nil, "OVERLAY", nil, 7)
        if state.roundBorder.SetSnapToPixelGrid then state.roundBorder:SetSnapToPixelGrid(false) end
        if state.roundBorder.SetTexelSnappingBias then state.roundBorder:SetTexelSnappingBias(0) end
        state.maskTargets = {}
    end
    -- Overlap icon pixels with the opaque inner edge of the border so the
    -- independently antialiased layers do not leave a transparent inner ring.
    local shapedBorder = not state.nativeArt and border ~= "none"
    local contentShape = shapedBorder and (border == "thick" and "ContentThick-" or "ContentThin-") or "Mask-"
    local sheenShape = shapedBorder and (border == "thick" and "SheenThick-" or "SheenThin-") or "Sheen-"
    state.roundMask:SetTexture(shapePath .. contentShape .. radius .. ".tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    state.roundMask:SetAllPoints(relative)
    state.outlineMask:SetTexture(shapePath .. "Mask-" .. radius .. ".tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    state.outlineMask:SetAllPoints(relative)
    state.sheenMask:SetTexture(shapePath .. sheenShape .. radius .. ".tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    state.sheenMask:SetAllPoints(relative)
    for _, texture in pairs({ icon = icon, shade = state.finish,
        background = state.background, itemBorder = button.Border }) do RoundTexture(state, texture) end
    RoundTexture(state, state.shine, state.sheenMask)
    state.roundBorder:SetBlendMode("BLEND")
    state.roundBorder:SetAllPoints(relative)
    state.roundBorder:SetTexture(shapePath .. (border == "thick" and "Thick-" or "Thin-") .. radius .. ".tga")
    state.roundBorder:SetVertexColor(r, g, b, 1)
    state.roundBorder:SetShown(shapedBorder)
    StyleButtonFeedback(button, state)
    if not isCooldownManager then
        StyleNextMeleeRing(button, state)
        StyleCastFeedback(button, state)
        StyleInterruptFeedback(button, state)
    end
    StyleCooldownSwipes(button, state)
    AlignProcGlow(button, state)
    StyleCooldownFeedback(button, state)
    SetAlpha(button, db.actionBarsOpacity / 100)
    StyleText(button, state, "HotKey", not isCooldownManager and db.actionBarsHotkeys)
    StyleText(button, state, "Name", db.actionBarsMacros)
    local count
    if isCooldownManager then
        count = button.ChargeCount and button.ChargeCount.Current
        if not count and button.GetApplicationsFontString then
            count = button:GetApplicationsFontString()
        end
    end
    StyleText(button, state, "Count", db.actionBarsCounts, count)
end

local function MirrorHotkeyRange(overlay, source)
    if overlay.rangeSource and overlay.rangeSource ~= source then
        rangeSources[overlay.rangeSource][overlay] = nil
    end
    overlay.rangeSource = source
    if not source or not source.SetVertexColor then return end
    local listeners = rangeSources[source]
    if not listeners then
        listeners = setmetatable({}, { __mode = "k" })
        rangeSources[source] = listeners
        hooksecurefunc(source, "SetVertexColor", function(_, r, g, b)
            if not ns.Plain(r) or not ns.Plain(g) or not ns.Plain(b) then return end
            for label in pairs(listeners) do label.text:SetVertexColor(r, g, b, 1) end
        end)
    end
    listeners[overlay] = true
    local getColor = source.GetVertexColor or source.GetTextColor
    if getColor then
        local ok, r, g, b = pcall(getColor, source)
        if ok and ns.Plain(r) and ns.Plain(g) and ns.Plain(b) then
            overlay.text:SetVertexColor(r, g, b, 1)
        end
    end
end

local function UpdateCooldownLabel(button, binding)
    local overlay = cooldownLabels[button]
    if not binding then
        if overlay then
            MirrorHotkeyRange(overlay, nil)
            overlay:Hide()
        end
        return
    end
    local icon = ButtonIcon(button)
    if not overlay then
        overlay = CreateFrame("Frame", nil, button)
        overlay:SetFrameStrata("HIGH")
        local template = NumberFontNormalSmallGray and "NumberFontNormalSmallGray" or "NumberFontNormalSmall"
        overlay.text = overlay:CreateFontString(nil, "OVERLAY", template)
        overlay.text:SetPoint("TOPRIGHT", -2, -2)
        overlay.text:SetJustifyH("RIGHT")
        cooldownLabels[button] = overlay
    end
    overlay:SetAllPoints(icon)
    overlay:SetFrameLevel(button:GetFrameLevel() + 20)
    overlay.text:SetText(binding.text)
    overlay:Show()
    local action = binding.button
    local source = action and (action.HotKey or Region(action, "HotKey"))
    if source and source.GetFont then
        local ok, font, _, flags = pcall(source.GetFont, source)
        if ok and ns.Plain(font) and type(font) == "string" then
            pcall(overlay.text.SetFont, overlay.text, font, ns.db.actionBarsFontSize, flags)
        end
    end
    MirrorHotkeyRange(overlay, source)
end

local function CooldownSpellID(button, cooldownInfoByID, layoutCooldownID, spellCache)
    if not button or type(button.GetSpellID) ~= "function" then return end
    local cooldownID = layoutCooldownID
    if type(button.GetCooldownID) == "function" then
        local readable, assigned = pcall(button.GetCooldownID, button)
        if readable and ns.Plain(assigned) and type(assigned) == "number" then cooldownID = assigned end
    end
    local ok, spellID = pcall(button.GetSpellID, button)
    local current = ok and ns.Plain(spellID) and type(spellID) == "number" and spellID
    if type(button.GetBaseSpellID) == "function" then
        ok, spellID = pcall(button.GetBaseSpellID, button)
        if ok and ns.Plain(spellID) and type(spellID) == "number" then
            if cooldownID then spellCache[cooldownID] = spellID end
            return current or spellID, current and "current" or "base", cooldownID
        end
    end
    -- The viewer can create a pooled item before filling in its spell data.
    -- Resolve its assigned cooldown directly when the client exposes that ID.
    if cooldownID then
        local info = cooldownInfoByID and cooldownInfoByID[cooldownID]
        if not ns.Plain(info) and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
            local found, apiInfo = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
            if found then info = apiInfo end
        end
        if ns.Plain(info) and type(info) == "table" then
            local base = info.spellID
            if ns.Plain(base) and type(base) == "number" then
                spellCache[cooldownID] = base
                return current or base, current and "current" or "cooldown info", cooldownID
            end
        end
        if current then return current, "current", cooldownID end
        if spellCache[cooldownID] then return spellCache[cooldownID], "saved base", cooldownID end
    end
    if current then return current, "current" end
    return nil, nil, cooldownID
end

local function GetViewerCooldownInfo()
    local settings = _G.CooldownViewerSettings
    if not settings or not settings.GetDataProvider then return end
    local provider = settings:GetDataProvider()
    local data = provider and provider.GetDisplayData and provider:GetDisplayData()
    local info = ns.Plain(data) and data.cooldownInfoByID
    if ns.Plain(info) and type(info) == "table" then return info end
end

local function ActionSpellIDs(button)
    if not button or type(GetActionInfo) ~= "function" then return end
    local slot = ns.Plain(button.action) and button.action or nil
    if not slot and button.GetAttribute then
        local ok, value = pcall(button.GetAttribute, button, "action")
        if ok and ns.Plain(value) and type(value) == "number" then slot = value end
    end
    if not ns.Plain(slot) or type(slot) ~= "number" then return end
    local ok, kind, id = pcall(GetActionInfo, slot)
    if not ok then return end
    if kind == "spell" and ns.Plain(id) and type(id) == "number" then return id end
    if kind == "macro" and ns.Plain(id) and type(id) == "number" and type(GetMacroSpell) == "function" then
        local good, first, second = pcall(GetMacroSpell, id)
        if good then
            if ns.Plain(first) and type(first) == "number" then return first end
            if ns.Plain(second) and type(second) == "number" then return second end
        end
    end
    if C_ActionBar and C_ActionBar.GetSpell then
        local good, spellID = pcall(C_ActionBar.GetSpell, slot)
        if good and ns.Plain(spellID) and type(spellID) == "number" and spellID > 0 then return spellID end
    end
end

local bindingPrefixes = {
    ActionButton = "ACTIONBUTTON", MultiBarBottomLeftButton = "MULTIACTIONBAR1BUTTON",
    MultiBarBottomRightButton = "MULTIACTIONBAR2BUTTON", MultiBarRightButton = "MULTIACTIONBAR3BUTTON",
    MultiBarLeftButton = "MULTIACTIONBAR4BUTTON", MultiBar5Button = "MULTIACTIONBAR5BUTTON",
    MultiBar6Button = "MULTIACTIONBAR6BUTTON", MultiBar7Button = "MULTIACTIONBAR7BUTTON",
}

local function ReadActionHotkey(button, prefix, index)
    local command = button and button.bindingAction
    if not command and bindingPrefixes[prefix] then command = bindingPrefixes[prefix] .. index end
    if GetBindingKey then
        local key = command and GetBindingKey(command)
        if not ns.Plain(key) and button and button:GetName() then
            key = GetBindingKey("CLICK " .. button:GetName() .. ":LeftButton")
        end
        if ns.Plain(key) and type(key) == "string" then
            if GetBindingText then
                local ok, label = pcall(GetBindingText, key, 1)
                if ok and ns.Plain(label) and type(label) == "string" and label ~= "" then return label end
            end
            return key
        end
    end
    local region = button and Region(button, "HotKey")
    local label = region and region.GetText and region:GetText()
    if ns.Plain(label) and type(label) == "string" and label ~= "" and label ~= RANGE_INDICATOR then
        return label
    end
end

local function FindActionHotkeys()
    local bySpell = {}
    for _, group in ipairs(groups) do
        for i = 1, group.count do
            local actionButton = _G[group.prefix .. i]
            local spellID = ActionSpellIDs(actionButton)
            local text = ReadActionHotkey(actionButton, group.prefix, i)
            if spellID and not bySpell[spellID] and ns.Plain(text) and type(text) == "string"
                and text ~= "" and text ~= RANGE_INDICATOR then
                local binding = { text = text, button = actionButton }
                bySpell[spellID] = binding
                if C_Spell and C_Spell.GetBaseSpell then
                    local ok, base = pcall(C_Spell.GetBaseSpell, spellID)
                    if ok and ns.Plain(base) and type(base) == "number" and not bySpell[base] then
                        bySpell[base] = binding
                    end
                end
            end
        end
    end
    return bySpell
end

local function ActionHotkeyForSpell(spellID, bySpell)
    if bySpell[spellID] then return bySpell[spellID] end
    if not (C_ActionBar and C_ActionBar.FindSpellActionButtons) then return end
    local ok, slots = pcall(C_ActionBar.FindSpellActionButtons, spellID)
    if not ok or type(slots) ~= "table" then return end
    for _, slot in ipairs(slots) do
        for _, group in ipairs(groups) do
            for i = 1, group.count do
                local actionButton = _G[group.prefix .. i]
                local actionSlot = actionButton and actionButton.action
                if (not ns.Plain(actionSlot) or actionSlot ~= slot) and actionButton and actionButton.GetAttribute then
                    local good, value = pcall(actionButton.GetAttribute, actionButton, "action")
                    if good then actionSlot = value end
                end
                if ns.Plain(actionSlot) and actionSlot == slot then
                    local text = ReadActionHotkey(actionButton, group.prefix, i)
                    if ns.Plain(text) and type(text) == "string" and text ~= ""
                        and text ~= RANGE_INDICATOR then return { text = text, button = actionButton } end
                end
            end
        end
    end
end

local function IsCooldownManagerItem(frame)
    return Usable(frame) and type(frame.GetSpellID) == "function" and Usable(frame.Icon)
        and frame.CreateTexture and frame.HookScript
end

local QueueCooldownHotkeys
local lastHotkeyScan
local viewerCooldownIDs = {}
local hotkeyTrace = {}
local function TraceHotkeyScan(message)
    if #hotkeyTrace >= 12 then table.remove(hotkeyTrace, 1) end
    hotkeyTrace[#hotkeyTrace + 1] = ("%.1fs %s"):format(GetTime(), message)
end
local function RefreshCooldownManagerButtons(labelsOnly)
    local enabled = ns.db.enabledActionBars
    local showKeys = enabled and ns.db.actionBarsCooldownHotkeys
    if labelsOnly and not showKeys then
        for _, overlay in pairs(cooldownLabels) do overlay:Hide() end
    end
    local bySpell = labelsOnly and showKeys and FindActionHotkeys() or {}
    local cooldownInfoByID = labelsOnly and showKeys and GetViewerCooldownInfo()
    local spellCache
    if labelsOnly and showKeys then
        local build = select(2, GetBuildInfo())
        local cache = ns.db.cooldownSpellCache
        if type(cache) ~= "table" or cache.build ~= build or type(cache.spells) ~= "table" then
            cache = { build = build, spells = {} }
            ns.db.cooldownSpellCache = cache
        end
        spellCache = cache.spells
    end
    local scan = { items = 0, visibleItems = 0, spells = 0, matches = 0, actionSpells = 0, errors = 0, details = {} }
    if labelsOnly then
        for _ in pairs(bySpell) do scan.actionSpells = scan.actionSpells + 1 end
        lastHotkeyScan = scan
    end
    local viewerName, orderedIDs
    local function StyleViewerItem(frame)
        if IsCooldownManagerItem(frame) then
            if not cooldownManagerHooks[frame] then
                cooldownManagerHooks[frame] = true
                frame:HookScript("OnShow", QueueRefresh)
                if type(frame.OnCooldownIDSet) == "function" then
                    hooksecurefunc(frame, "OnCooldownIDSet", QueueRefresh)
                end
                if type(frame.SetCooldownID) == "function" then
                    hooksecurefunc(frame, "SetCooldownID", QueueCooldownHotkeys)
                end
                if type(frame.RefreshSpellTexture) == "function" then
                    hooksecurefunc(frame, "RefreshSpellTexture", QueueCooldownHotkeys)
                end
            end
            if labelsOnly then
                scan.items = scan.items + 1
                if frame:IsVisible() then scan.visibleItems = scan.visibleItems + 1 end
                local spellID, source, cooldownID
                if showKeys then
                    local index = frame.layoutIndex
                    local assigned = orderedIDs and ns.Plain(index) and orderedIDs[index]
                    if not ns.Plain(assigned) or type(assigned) ~= "number" then assigned = nil end
                    spellID, source, cooldownID = CooldownSpellID(frame, cooldownInfoByID, assigned, spellCache)
                end
                if not cooldownID and frame.GetCooldownID then
                    local ok, value = pcall(frame.GetCooldownID, frame)
                    if ok and ns.Plain(value) and type(value) == "number" then cooldownID = value end
                end
                if spellID then scan.spells = scan.spells + 1 end
                local key = spellID and ActionHotkeyForSpell(spellID, bySpell)
                if showKeys and not key and type(frame.GetBaseSpellID) == "function" then
                    local ok, baseSpellID = pcall(frame.GetBaseSpellID, frame)
                    if ok and ns.Plain(baseSpellID) then key = ActionHotkeyForSpell(baseSpellID, bySpell) end
                end
                if key then scan.matches = scan.matches + 1 end
                UpdateCooldownLabel(frame, key)
                local overlay = cooldownLabels[frame]
                scan.details[#scan.details + 1] = ("%s | ícone=%s cooldown=%s spell=%s fonte=%s tecla=%s texto visível=%s")
                    :format(viewerName, tostring(frame:IsVisible()), cooldownID or "-", spellID or "-",
                        source or "-", key and key.text or "-", tostring(overlay ~= nil and overlay:IsVisible()))
                return
            end
            if enabled then
                StyleButton(frame, true)
            elseif buttons[frame] then
                RestoreButton(frame, buttons[frame])
            end
        end
    end
    local function VisitItem(frame)
        if not labelsOnly then
            StyleViewerItem(frame)
            return
        end
        local ok, message = pcall(StyleViewerItem, frame)
        if not ok then
            scan.errors = scan.errors + 1
            scan.firstError = scan.firstError or message
        end
    end
    local function VisitTree(frame, depth)
        if not frame or depth < 0 then return end
        VisitItem(frame)
        if not frame.GetChildren then return end
        for _, child in ipairs({ frame:GetChildren() }) do VisitTree(child, depth - 1) end
    end
    for _, name in ipairs({ "EssentialCooldownViewer", "UtilityCooldownViewer",
        "BuffIconCooldownViewer", "BuffBarCooldownViewer" }) do
        viewerName = name
        local viewer = _G[name]
        if viewer then
            if not cooldownManagerHooks[viewer] then
                cooldownManagerHooks[viewer] = true
                viewer:HookScript("OnShow", QueueCooldownHotkeys)
                if viewer.RefreshLayout then hooksecurefunc(viewer, "RefreshLayout", QueueRefresh) end
                if viewer.RefreshData then
                    hooksecurefunc(viewer, "RefreshData", function(self, ids)
                        viewerCooldownIDs[self] = ns.Plain(ids) and type(ids) == "table" and ids or nil
                        QueueCooldownHotkeys()
                    end)
                end
            end
            orderedIDs = viewerCooldownIDs[viewer]
            if labelsOnly and showKeys and not orderedIDs and viewer.GetCooldownIDs then
                local ok, ids = pcall(viewer.GetCooldownIDs, viewer)
                if ok and ns.Plain(ids) and type(ids) == "table" then orderedIDs = ids end
            end
            if viewer.itemFramePool then
                for item in viewer.itemFramePool:EnumerateActive() do VisitItem(item) end
            else
                VisitTree(viewer, 5)
            end
        end
    end
    if labelsOnly then
        local result = ("%d/%d ícones visíveis, %d spells, %d teclas, %d erros"):format(
            scan.visibleItems, scan.items, scan.spells, scan.matches, scan.errors)
        if result ~= hotkeyTrace.lastResult then
            hotkeyTrace.lastResult = result
            TraceHotkeyScan(result)
        end
    end
end

local hotkeyRefreshQueued = false
local actionHotkeyHooks = {}
QueueCooldownHotkeys = function()
    if hotkeyRefreshQueued then return end
    hotkeyRefreshQueued = true
    C_Timer.After(0, function()
        hotkeyRefreshQueued = false
        if not ns.db or not ns.db.enabledActionBars or not ns.db.actionBarsCooldownHotkeys
            or InCombatLockdown() then return end
        local ok, message = pcall(RefreshCooldownManagerButtons, true)
        if not ok then
            TraceHotkeyScan("falha na atualização: " .. tostring(message))
            geterrorhandler()(message)
        end
    end)
end

local function WatchActionHotkeys()
    for _, group in ipairs(groups) do
        for index = 1, group.count do
            local button = _G[group.prefix .. index]
            if button and button.UpdateHotkeys and not actionHotkeyHooks[button] then
                actionHotkeyHooks[button] = true
                hooksecurefunc(button, "UpdateHotkeys", QueueCooldownHotkeys)
            end
        end
    end
end

function ns.PrintCooldownHotkeyStatus(verbose)
    local visible = 0
    for _, overlay in pairs(cooldownLabels) do
        if overlay:IsVisible() then visible = visible + 1 end
    end
    local scan = lastHotkeyScan or {}
    print(("PhalkTools CDM | Action Bars=%s | keybinds=%s | ícones=%s | ícones visíveis=%s | habilidades=%s | atalhos nas barras=%s | correspondências=%s | textos visíveis=%d")
        :format(tostring(ns.db.enabledActionBars), tostring(ns.db.actionBarsCooldownHotkeys),
            scan.items or "-", scan.visibleItems or "-", scan.spells or "-", scan.actionSpells or "-", scan.matches or "-", visible))
    if scan.firstError then
        print("PhalkTools CDM | erros nos ícones: " .. scan.errors .. " | " .. tostring(scan.firstError))
    end
    if verbose then
        print(("PhalkTools CDM | combate=%s | Edit Mode=%s | atualização pendente=%s")
            :format(tostring(InCombatLockdown()), tostring(editing), tostring(queued or hotkeyRefreshQueued)))
        for _, line in ipairs(hotkeyTrace) do print(line) end
        for _, line in ipairs(scan.details or {}) do print(line) end
    end
end

local function RootFor(group)
    local root = _G[group.root]
    if root then return root end
    if group.root == "MainActionBar" then return _G.MainMenuBar end
    if group.root == "PetActionBar" then return _G.PetActionBarFrame end
    if group.root == "StanceBar" then return _G.StanceBarFrame or _G.ShapeshiftBarFrame end
end

local function CaptureNativeScale(root, state)
    state.scale = root:GetScale()
    state.containers = nil
    for _, button in pairs(root.actionButtons or {}) do
        local container = button.container
        if Usable(container) then
            state.containers = state.containers or {}
            state.containers[container] = container:GetScale()
        end
    end
end

local function ApplyBarScale(root, state, multiplier)
    if state.settingScale or InCombatLockdown() then return end
    state.settingScale = true
    if state.containers then
        -- Blizzard owns the bar's outer scale and can reset it on combat
        -- visibility updates. Edit Mode sizes the actual button containers.
        local changed, iconScale = false, nil
        for container, nativeScale in pairs(state.containers) do
            local desired = nativeScale * multiplier
            iconScale = desired
            if math.abs(container:GetScale() - desired) >= 0.0001 then
                container:SetScale(desired)
                changed = true
            end
        end
        if changed then
            if root.EditModeSetScale then root:EditModeSetScale(iconScale) end
            root:Layout()
            if root.MarkDividersDirty then root:MarkDividersDirty() end
            if root.MarkBarArtDirty then root:MarkBarArtDirty() end
            if EditModeManagerFrame and EditModeManagerFrame.UpdateActionBarLayout then
                EditModeManagerFrame:UpdateActionBarLayout(root)
            end
        end
    else
        -- Compatibility with older bars without Edit Mode containers.
        local desired = state.scale * multiplier
        if math.abs(root:GetScale() - desired) >= 0.0001 then root:SetScale(desired) end
    end
    state.settingScale = false
end

local function MaintainBarScale(root, state)
    if editing or not state.active then return end
    ApplyBarScale(root, state, ns.db.actionBarsScale / 100)
end

local function StyleDividers(root, state)
    if InCombatLockdown() then return end
    if not state.active then return end
    local hide = ns.db.actionBarsHideArt
    if not hide and state.dividers then
        for divider in pairs(state.dividers) do RestoreAlpha(divider) end
    end
    state.dividers = state.dividers or {}
    for _, key in ipairs({ "HorizontalDividersPool", "VerticalDividersPool" }) do
        local pool = root[key]
        if pool and pool.EnumerateActive then
            for divider in pool:EnumerateActive() do
                if Usable(divider) then
                    state.dividers[divider] = true
                    state.art[divider] = divider
                    if hide then SetAlpha(divider, 0) else RestoreAlpha(divider) end
                end
            end
        end
    end
end

local function StyleRoot(root, enabled, main)
    if not Usable(root) then return end
    local state = roots[root]
    if not state and not enabled then return end
    if not state then
        state = { art = {} }
        roots[root] = state
        CaptureNativeScale(root, state)
        if not state.containers then
            hooksecurefunc(root, "SetScale", function() MaintainBarScale(root, state) end)
        end
        if type(root.UpdateSystemSettingIconSize) == "function" then
            hooksecurefunc(root, "UpdateSystemSettingIconSize", function()
                -- The native method has just applied the unmodified icon size.
                CaptureNativeScale(root, state)
                MaintainBarScale(root, state)
            end)
        end
        root:HookScript("OnShow", function() MaintainBarScale(root, state) end)
        if main and type(root.UpdateDividers) == "function" then
            -- Pools are rebuilt on paging, form changes and Edit Mode layout.
            hooksecurefunc(root, "UpdateDividers", function() StyleDividers(root, state) end)
        end
    end
    if not enabled then
        local wasActive = state.active
        state.active = false
        if wasActive then ApplyBarScale(root, state, 1) end
        for _, object in pairs(state.art) do RestoreAlpha(object) end
        state.active = false
        return
    end
    if not state.active then CaptureNativeScale(root, state) end
    state.active = true
    -- Do not restart Blizzard layout/size work on every slot or form event.
    MaintainBarScale(root, state)
    if main then
        StyleDividers(root, state)
        for key, object in pairs({ border = root.BorderArt, caps = root.EndCaps,
            left = _G.MainMenuBarLeftEndCap, right = _G.MainMenuBarRightEndCap,
            texture0 = _G.MainMenuBarTexture0, texture1 = _G.MainMenuBarTexture1,
            texture2 = _G.MainMenuBarTexture2, texture3 = _G.MainMenuBarTexture3 }) do
            if Usable(object) then
                state.art[key] = object
                if ns.db.actionBarsHideArt then SetAlpha(object, 0) else RestoreAlpha(object) end
            end
        end
    end
end

-- Bags and micro buttons have separate native artwork and keep their own layout.
local auxiliaryButtons, auxiliaryRoots = {}, {}
local microNames = {
    "CharacterMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton",
    "TalentMicroButton", "SpellbookMicroButton", "AchievementMicroButton", "LegacyMicroButton",
    "QuestLogMicroButton", "HousingMicroButton", "GuildMicroButton", "LFDMicroButton",
    "CollectionsMicroButton", "EJMicroButton", "HelpMicroButton", "StoreMicroButton",
    "MainMenuMicroButton", "SocialsMicroButton", "PVPFrameMicroButton",
    "PVPMicroButton", "LFGMicroButton", "WorldMapMicroButton",
}
local bagNames = {
    "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
    "CharacterBag2Slot", "CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton",
}

local function StyleAuxiliaryRoot(root, enabled)
    if not Usable(root) then return end
    local state = auxiliaryRoots[root]
    if not state and not enabled then return end
    if not state then
        state = { art = {} }
        auxiliaryRoots[root] = state
        if type(root.UpdateDividers) == "function" then
            hooksecurefunc(root, "UpdateDividers", function() StyleDividers(root, state) end)
        end
        root:HookScript("OnShow", QueueRefresh)
        for _, method in ipairs({ "UpdateArt", "UpdateBackground", "Layout" }) do
            if type(root[method]) == "function" then
                hooksecurefunc(root, method, QueueRefresh)
            end
        end
    end
    state.active = enabled
    -- Forever also puts tray artwork directly on the bar/container, rather
    -- than exclusively in the retail BorderArt and BackgroundArt fields.
    local function CaptureArt(object)
        if not Usable(object) then return end
        if object.IsObjectType and object:IsObjectType("Texture") then
            state.art[object] = object
        elseif object.GetRegions then
            for _, region in pairs({ object:GetRegions() }) do
                if region.IsObjectType and region:IsObjectType("Texture") then
                    state.art[region] = region
                end
            end
        end
    end
    CaptureArt(root)
    for _, key in ipairs({ "BorderArt", "BackgroundArt", "Background", "Border", "ArtFrame", "NineSlice" }) do
        CaptureArt(root[key])
    end
    if enabled then StyleDividers(root, state) end
    for art in pairs(state.art) do
        if enabled and ns.db.actionBarsHideArt then SetAlpha(art, 0) else RestoreAlpha(art) end
    end
end

local function RestoreAuxiliaryButton(state)
    for art in pairs(state.art) do RestoreAlpha(art) end
    wipe(state.art)
    RestoreMasks(state)
    state.background:Hide()
    state.border:Hide()
    if state.hover then state.hover:Hide() end
    state.active = false
end

local function StyleAuxiliaryButton(button, isMicro, enabled)
    if not Usable(button) then return end
    local state = auxiliaryButtons[button]
    local border = ns.db.actionBarsBorder
    local radius = math.floor(math.max(0, math.min(50, tonumber(ns.db.actionBarsRadius) or 0)))
    local custom = enabled and (border ~= "default" or radius > 0)
    if not custom then
        if state and state.active then RestoreAuxiliaryButton(state) end
        return
    end
    if not state then
        state = { art = {}, maskTargets = {} }
        auxiliaryButtons[button] = state
        state.background = button:CreateTexture(nil, "BACKGROUND", nil, -1)
        state.background:SetColorTexture(0.055, 0.06, 0.065, 1)
        state.border = button:CreateTexture(nil, "OVERLAY", nil, 7)
        state.roundMask = button:CreateMaskTexture(nil, "ARTWORK")
        if not isMicro then
            state.hover = button:CreateTexture(nil, "HIGHLIGHT")
            state.hover:SetColorTexture(1, 1, 1, 0.18)
        end
        for _, texture in ipairs({ state.background, state.border, state.hover }) do
            if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
            if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
        end
        if not isMicro and type(button.UpdateTextures) == "function" then
            hooksecurefunc(button, "UpdateTextures", function()
                if state.active then QueueRefresh() end
            end)
        end
        button:HookScript("OnShow", QueueRefresh)
    end
    RestoreAuxiliaryButton(state)
    state.active = true
    -- Micro menu icon atlases are independent of their decorative backgrounds.
    -- Bag normal/pushed atlases are slot frames; the inventory icon is separate.
    local art = isMicro and { button.Background, button.PushedBackground, button.Border,
            button.Shadow, button.PushedShadow }
        or { button:GetNormalTexture(), button:GetPushedTexture(), button:GetHighlightTexture(),
            button.SlotArt, button.SlotBackground, button.IconBorder }
    for _, texture in pairs(art) do
        if Usable(texture) then
            state.art[texture] = true
            SetAlpha(texture, 0)
        end
    end
    local icon = not isMicro and (button.icon or button.Icon or Region(button, "IconTexture"))
    local relative = Usable(icon) and icon or button
    local function Anchor(texture)
        texture:ClearAllPoints()
        if isMicro then
            -- The native micro menu overlaps button hit rectangles by five pixels.
            texture:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
            texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
        else
            texture:SetAllPoints(relative)
        end
    end
    local shapedBorder = border ~= "none"
    local contentShape = shapedBorder and (border == "thick" and "ContentThick-" or "ContentThin-") or "Mask-"
    state.roundMask:SetTexture(shapePath .. contentShape .. radius .. ".tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    Anchor(state.roundMask)
    Anchor(state.background)
    RoundTexture(state, state.background)
    state.background:Show()
    if isMicro then
        -- Preserve the normal, disabled, pushed and mouseover icon atlases.
        for _, texture in pairs({ button:GetNormalTexture(), button:GetPushedTexture(),
            button:GetDisabledTexture(), button:GetHighlightTexture() }) do
            RoundTexture(state, texture)
        end
        -- The character portrait has its own Blizzard mask and inset geometry.
    else
        RoundTexture(state, icon)
        Anchor(state.hover)
        RoundTexture(state, state.hover)
        state.hover:Show()
    end
    Anchor(state.border)
    state.border:SetTexture(shapePath .. (border == "thick" and "Thick-" or "Thin-") .. radius .. ".tga")
    state.border:SetVertexColor(BorderColor())
    state.border:SetShown(shapedBorder)
end

local function StyleAuxiliaryBars()
    local enabled = ns.db.enabledActionBars
    StyleAuxiliaryRoot(_G.BagsBar, enabled)
    StyleAuxiliaryRoot(_G.MicroMenu, enabled)
    StyleAuxiliaryRoot(_G.MicroMenuContainer, enabled)
    StyleAuxiliaryRoot(_G.MicroButtonAndBagsBar, enabled)
    for _, name in ipairs(bagNames) do StyleAuxiliaryButton(_G[name], false, enabled) end
    for _, name in ipairs(microNames) do StyleAuxiliaryButton(_G[name], true, enabled) end
    -- Include client-specific micro buttons without depending on retail names.
    for _, entry in pairs(_G.MICRO_BUTTONS or {}) do
        local button = type(entry) == "string" and _G[entry] or entry
        if type(button) == "table" and button.CreateTexture then
            StyleAuxiliaryButton(button, true, enabled)
        end
    end
end

function ns.RefreshActionBars()
    if refreshing or editing or InCombatLockdown() or not ns.db then return end
    refreshing = true
    local ok, message = pcall(function()
        StyleAuxiliaryBars()
        for _, group in ipairs(groups) do
            local enabled = ns.db.enabledActionBars and ns.db[group.option]
            StyleRoot(RootFor(group), enabled, group.option == "actionBarsMain")
            for i = 1, group.count do
                local button = _G[group.prefix .. i]
                if Usable(button) then
                    if enabled then StyleButton(button)
                    elseif buttons[button] then RestoreButton(button, buttons[button]) end
                end
            end
        end
    end)
    local labelsOK, labelsMessage = pcall(RefreshCooldownManagerButtons, true)
    local cooldownOK, cooldownMessage = pcall(RefreshCooldownManagerButtons)
    refreshing = false
    if not ok then geterrorhandler()(message) end
    if not cooldownOK then geterrorhandler()(cooldownMessage) end
    if not labelsOK then geterrorhandler()(labelsMessage) end
    pcall(RefreshNextMeleeRings)
end

function ns.InitActionBars()
    if ActionButtonSpellAlertManager and ActionButtonSpellAlertManager.ShowAlert then
        hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, button)
            local state = buttons[button]
            if state and state.active then AlignProcGlow(button, state) end
        end)
    end
    WatchActionHotkeys()
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ADDON_LOADED",
        "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
        "UPDATE_MACROS", "UPDATE_BINDINGS" }) do events:RegisterEvent(event) end
    events:SetScript("OnEvent", function(_, event)
        QueueRefresh()
        if event == "PLAYER_LOGIN" or event == "ADDON_LOADED" then WatchActionHotkeys() end
        if event == "PLAYER_ENTERING_WORLD" then
            TraceHotkeyScan("PLAYER_ENTERING_WORLD")
            WatchActionHotkeys()
            C_Timer.After(1, QueueCooldownHotkeys)
        end
    end)
    local queuedEvents = CreateFrame("Frame")
    for _, event in ipairs({ "CURRENT_SPELL_CAST_CHANGED", "ACTIONBAR_SLOT_CHANGED",
        "UPDATE_SHAPESHIFT_FORM" }) do queuedEvents:RegisterEvent(event) end
    queuedEvents:SetScript("OnEvent", function()
        pcall(RefreshNextMeleeRings)
    end)
    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function()
            if InCombatLockdown() then return end
            editing = true
            -- Show the native icon sizes while editing, then adopt the new sizes.
            for root, state in pairs(roots) do
                if state.active then ApplyBarScale(root, state, 1); state.editing = true end
            end
        end)
        EventRegistry:RegisterCallback("EditMode.Exit", function()
            editing = false
            for root, state in pairs(roots) do
                if state.editing then CaptureNativeScale(root, state); state.editing = nil end
            end
            QueueRefresh()
        end)
    end
end
