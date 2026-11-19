local _, ns = ...

-- CustomAuraContainer delegates aura selection and rendering to the client,
-- including auras whose contents are secret during combat.
local panels = {}
local ICON_SIZE = 20
local entries = {
    { name = "PlayerFrame", unit = "player", key = "unitFramesPlayer" },
    { name = "TargetFrame", unit = "target", key = "unitFramesTarget" },
    { name = "FocusFrame", unit = "focus", key = "unitFramesFocus" },
}

local function InitializeIcon(button)
    button:SetSize(ICON_SIZE, ICON_SIZE)
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints(button)
    local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetJustifyH("RIGHT")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, 0)
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    cooldown:SetReverse(true)
    cooldown:SetDrawEdge(true)
    cooldown:SetDrawBling(false)
    cooldown:SetHideCountdownNumbers(true)
    button:SetIcon(icon)
    button:SetApplicationCount(count)
    button:SetDurationCooldown(cooldown)
end

local function HealthBar(frame, unit)
    if ns.UnitFrameVisualHealth then
        local visual = ns.UnitFrameVisualHealth(frame)
        if visual then return visual end
    end
    local content = unit == "player" and frame.PlayerFrameContent or frame.TargetFrameContent
    local main = content and (unit == "player" and content.PlayerFrameContentMain or content.TargetFrameContentMain)
    local container = main and main.HealthBarsContainer
    return frame.healthbar or (container and container.HealthBar) or frame.HealthBar
end

local function CreatePanel(frame, entry)
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(1, 1)
    holder:Hide()
    local container = CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    container:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT")
    container:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
    container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up)
    container:AddAuraGroup("Buffs", "HELPFUL", {
        maxFrameCount = 40,
        initializeFrame = InitializeIcon,
    })
    if entry.unit ~= "player" then
        container:AddAuraGroup("Debuffs", "HARMFUL", {
            maxFrameCount = 16,
            initializeFrame = InitializeIcon,
            layout = { forceNewLine = true, layoutIndex = 2 },
        })
    end
    container:SetUnit(entry.unit)
    local state = { holder = holder, container = container, frame = frame, unit = entry.unit }
    panels[entry.unit] = state
    return state
end

local function Layout(state)
    if InCombatLockdown() then return end
    local health = HealthBar(state.frame, state.unit)
    if not health then return end
    local defaults = TargetFrameAuraContainerDefaults or {}
    local match = state.unit == "player" or ns.db.unitFramesMatchBuffs
    local size = match and ns.db.unitFramesBuffSize or (defaults.SmallAuraSize or 20)
    local gap = match and ns.db.unitFramesBuffSpacing or (defaults.FlowLayoutElementSpacing or 3)
    local scale = size / ICON_SIZE
    state.holder:ClearAllPoints()
    state.holder:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 0, ns.UnitFrameStatusAuraOffset(state.frame))
    state.holder:SetFrameLevel(state.frame:GetFrameLevel() + 10)
    -- Scale the whole container so existing restricted buttons also resize.
    state.container:SetScale(scale)
    state.container:SetFlowLayoutMaximumLineSize(ns.db.unitFramesWidth / scale + 0.01)
    local options = { elementSpacing = gap / scale, lineSpacing = gap / scale, layoutIndex = 1 }
    state.container:SetAuraGroupLayout("Buffs", options)
    if state.unit ~= "player" then
        state.container:SetAuraGroupLayout("Debuffs", {
            elementSpacing = gap / scale, lineSpacing = gap / scale,
            groupSpacing = gap / scale, forceNewLine = true, layoutIndex = 2,
        })
    end
end

local function ConfigureNative(state, enabled)
    if state.unit == "player" or not state.frame.GetAuraContainer then return end
    local native = state.frame:GetAuraContainer()
    if not native then return end
    -- These are public delegated methods. The native container's geometry and
    -- its private frame table are deliberately never inspected.
    if enabled then
        if not state.native then
            state.native = native
            state.maxBuffs, state.maxDebuffs = native:GetMaxBuffs(), native:GetMaxDebuffs()
        end
        native:SetMaxBuffs(0)
        native:SetMaxDebuffs(0)
    elseif state.native then
        state.native:SetMaxBuffs(state.maxBuffs)
        state.native:SetMaxDebuffs(state.maxDebuffs)
        state.native = nil
    end
end

local function Configure(entry)
    local frame = _G[entry.name]
    if not frame or InCombatLockdown() then return end
    local enabled = ns.db.enabledUnitFrames and ns.db[entry.key]
        and (entry.unit ~= "player" or ns.db.unitFramesPlayerBuffs)
    local state = panels[entry.unit]
    if not enabled and not state then return end
    state = state or CreatePanel(frame, entry)
    if not state.hooked and entry.unit ~= "player" and frame.ConfigureAuraContainer then
        hooksecurefunc(frame, "ConfigureAuraContainer", function()
            if state.enabled then ConfigureNative(state, true) end
        end)
        state.hooked = true
    end
    state.enabled = enabled
    if enabled then
        Layout(state)
        state.container:SetEnabled(true)
        state.container:UpdateAllAuras()
        state.holder:Show()
        ConfigureNative(state, true)
    else
        state.container:SetEnabled(false)
        state.holder:Hide()
        ConfigureNative(state, false)
    end
end

function ns.LayoutPlayerFrameBuffs()
    for _, state in pairs(panels) do
        if state.enabled then Layout(state) end
    end
end

function ns.RefreshPlayerFrameBuffs(layoutChanged)
    if not ns.db then return end
    if layoutChanged then
        for _, entry in ipairs(entries) do
            local ok, message = pcall(Configure, entry)
            if not ok then geterrorhandler()(message) end
        end
    end
end

function ns.InitPlayerFrameBuffs()
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("PLAYER_FOCUS_CHANGED")
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
            local unit = event == "PLAYER_TARGET_CHANGED" and "target" or "focus"
            local state = panels[unit]
            if state and state.enabled then state.container:UpdateAllAuras() end
        else
            ns.RefreshPlayerFrameBuffs(true)
        end
    end)
end
