local _, ns = ...

local meter, window, resizeHandle, headerDrag, hooked
local scrollBoxes, entries, originalTextures = {}, {}, {}
local barBorders = {}
local nativeEdgeAlpha = {}
local placementHooks = {}
local restoringPlacement, placementQueued, editingLayout = false, false, false
local lastPlacementError

local function StyleBarBorder(entry, bar)
    local style = ns.db.enabledDamageMeter and ns.db.damageMeterBorder
    local edge = entry.GetBackgroundEdge and entry:GetBackgroundEdge()
    if edge then
        if style and style ~= "default" then
            if nativeEdgeAlpha[edge] == nil then nativeEdgeAlpha[edge] = edge:GetAlpha() end
            edge:SetAlpha(0)
        elseif nativeEdgeAlpha[edge] ~= nil then
            edge:SetAlpha(nativeEdgeAlpha[edge])
            nativeEdgeAlpha[edge] = nil
        end
    end
    local size = style == "thin" and 1 or style == "thick" and 3
    local border = barBorders[entry]
    if not size then
        if border then border:Hide() end
        return
    end
    if not border then
        border = CreateFrame("Frame", nil, entry, "BackdropTemplate")
        border:SetAllPoints(bar)
        border:SetFrameLevel(math.max(entry:GetFrameLevel(), bar:GetFrameLevel()) + 5)
        border:EnableMouse(false)
        barBorders[entry] = border
    end
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = size })
    border:SetBackdropBorderColor(0, 0, 0, 1)
    border:Show()
end

local function StyleEntry(entry)
    if InCombatLockdown() then return end
    local bar = entry.GetStatusBar and entry:GetStatusBar()
    if bar then StyleBarBorder(entry, bar) end
    local texture = bar and bar:GetStatusBarTexture()
    if not texture then return end
    local path = ns.db.enabledDamageMeter and ns.barTextures and ns.barTextures[ns.db.damageMeterTexture]
    local atlas = texture:GetAtlas()
    if path then
        if atlas or not originalTextures[texture] then
            originalTextures[texture] = { atlas = atlas, file = texture:GetTexture() }
        end
        texture:SetTexture(path)
    elseif originalTextures[texture] then
        local original = originalTextures[texture]
        if not atlas then
            if original.atlas then texture:SetAtlas(original.atlas) else texture:SetTexture(original.file) end
        end
        originalTextures[texture] = nil
    end
end

local function StyleRows(session)
    local box = session.GetScrollBox and session:GetScrollBox()
    if not box then return end
    local function RowHeight()
        if ns.db.enabledDamageMeter then return ns.db.damageMeterBarHeight end
        if session.GetBarHeight then return session:GetBarHeight() end
    end
    local function Track(entry)
        local height = RowHeight()
        if height and entry.SetBarHeight then entry:SetBarHeight(height) end
        if not entries[entry] and entry.SetStyle then
            entries[entry] = true
            hooksecurefunc(entry, "SetStyle", StyleEntry)
        end
        StyleEntry(entry)
    end
    if not scrollBoxes[box] and ScrollUtil and ScrollUtil.AddAcquiredFrameCallback then
        scrollBoxes[box] = true
        ScrollUtil.AddAcquiredFrameCallback(box, function(_, entry) Track(entry) end, box)
        if session.SetBarHeight then
            hooksecurefunc(session, "SetBarHeight", function()
                C_Timer.After(0, function()
                    if ns.db.enabledDamageMeter and not InCombatLockdown() then StyleRows(session) end
                end)
            end)
        end
    end
    local view = box.GetView and box:GetView()
    local height = RowHeight()
    local currentHeight
    if view and view.HasIdenticalElementExtent and view.GetIdenticalElementExtent
        and view:HasIdenticalElementExtent() then
        currentHeight = view:GetIdenticalElementExtent()
    end
    if height and view and view.SetElementExtent and currentHeight ~= height then
        view:SetElementExtent(height)
        if box.FullUpdate then box:FullUpdate() end
    end
    if session.ForEachEntryFrame then
        session:ForEachEntryFrame(Track)
    elseif box.ForEachFrame then
        box:ForEachFrame(Track)
    end
end

local function GetMeter()
    return _G.DamageMeter
end

local function GetPrimaryWindow(frame)
    return frame and frame.GetPrimarySessionWindow and frame:GetPrimarySessionWindow()
end

local function SavePosition(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    local width, height = frame:GetSize()
    local scale = UIParent:GetScale()
    if ns.Plain(left) and ns.Plain(top) and ns.Plain(width) and ns.Plain(height)
        and width > 0 and height > 0 and scale > 0 then
        ns.db.damageMeterX = math.floor(left * scale + 0.5)
        ns.db.damageMeterY = math.floor(top * scale + 0.5)
        ns.db.damageMeterWidth = math.floor(width * scale + 0.5)
        ns.db.damageMeterHeight = math.floor(height * scale + 0.5)
    end
end

local function PlaceMeter(frame)
    if ns.db.damageMeterX == nil or ns.db.damageMeterY == nil then return end
    local scale = UIParent:GetScale()
    local anchor = GetMeter()
    if not anchor then return end
    anchor:ClearAllPoints()
    anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ns.db.damageMeterX / scale,
        ns.db.damageMeterY / scale)
    if ns.db.damageMeterWidth and ns.db.damageMeterHeight then
        anchor:SetSize(ns.db.damageMeterWidth / scale, ns.db.damageMeterHeight / scale)
    end
    frame:ClearAllPoints()
    frame:SetAllPoints(anchor)
end

local function QueueSavedPlacement()
    if restoringPlacement or placementQueued or editingLayout or not ns.db
        or ns.db.damageMeterUnlocked or ns.db.damageMeterX == nil or ns.db.damageMeterY == nil then return end
    placementQueued = true
    C_Timer.After(0, function()
        placementQueued = false
        if InCombatLockdown() or editingLayout or ns.db.damageMeterUnlocked then return end
        local primary = GetPrimaryWindow(GetMeter())
        if not primary then return end
        restoringPlacement = true
        local ok, message = pcall(PlaceMeter, primary)
        restoringPlacement = false
        lastPlacementError = not ok and message or nil
        if not ok then geterrorhandler()(message) end
    end)
end

local function WatchPlacement(frame)
    if placementHooks[frame] then return end
    placementHooks[frame] = true
    for _, method in ipairs({ "SetPoint", "SetAllPoints", "SetSize", "SetWidth", "SetHeight" }) do
        if frame[method] then hooksecurefunc(frame, method, QueueSavedPlacement) end
    end
end

local function EnsureHandle(frame)
    if not resizeHandle then
        local header = frame:GetHeader()
        local drag = CreateFrame("Frame", nil, frame)
        headerDrag = drag
        drag:SetPoint("TOPLEFT", header, "TOPLEFT")
        drag:SetPoint("BOTTOMRIGHT", header, "BOTTOM")
        header = drag
        local moving
        header:EnableMouse(true)
        header:RegisterForDrag("LeftButton")
        header:HookScript("OnDragStart", function()
            if ns.db.damageMeterUnlocked and not InCombatLockdown() then
                frame:StartMoving()
                moving = true
            end
        end)
        header:HookScript("OnDragStop", function()
            if not moving then return end
            moving = nil
            frame:StopMovingOrSizing()
            SavePosition(frame)
        end)
        resizeHandle = CreateFrame("Button", nil, frame)
        resizeHandle:SetSize(16, 16)
        resizeHandle:SetFrameStrata("DIALOG")
        resizeHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        resizeHandle:SetScript("OnMouseDown", function()
            if ns.db and ns.db.damageMeterUnlocked and not InCombatLockdown() then
                frame:StartSizing("BOTTOMRIGHT")
            end
        end)
        resizeHandle:SetScript("OnMouseUp", function()
            frame:StopMovingOrSizing()
            SavePosition(frame)
        end)
    end
    resizeHandle:SetParent(frame)
    local unlocked = ns.db.damageMeterLockMenu and ns.db.damageMeterUnlocked
    resizeHandle:SetShown(unlocked)
    headerDrag:SetShown(unlocked)
end

local function ApplyLock()
    local unlocked = ns.db.damageMeterLockMenu and ns.db.damageMeterUnlocked
    if unlocked or resizeHandle then
        window:SetMovable(unlocked)
        window:SetResizable(unlocked)
        EnsureHandle(window)
    end
end

local function ApplyPlacement()
    local unlocked = ns.db.damageMeterLockMenu and ns.db.damageMeterUnlocked
    if unlocked then
        window:SetClampedToScreen(true)
        if window.SetResizeBounds then window:SetResizeBounds(160, 100) end
    end
    if unlocked and (ns.db.damageMeterX == nil or ns.db.damageMeterY == nil) then
        SavePosition(window)
    end
    if ns.db.damageMeterX ~= nil and ns.db.damageMeterY ~= nil then
        window:SetUserPlaced(false)
        if unlocked then PlaceMeter(window) else QueueSavedPlacement() end
    end
end

local function Apply()
    if not ns.db or InCombatLockdown() then return end
    meter = GetMeter()
    if not meter then return end
    window = GetPrimaryWindow(meter)
    if not window then return end
    WatchPlacement(meter)
    WatchPlacement(window)
    local placementOK, placementError = pcall(ApplyPlacement)
    local lockOK, lockError = pcall(ApplyLock)
    if ns.db.damageMeterLockMenu and window.GetResizeButton then
        local nativeResize = window:GetResizeButton()
        if nativeResize then nativeResize:Hide() end
    end
    if not (ns.db.damageMeterLockMenu and ns.db.damageMeterUnlocked) and resizeHandle then
        resizeHandle:Hide()
        headerDrag:Hide()
    end
    if not hooked then
        hooked = true
        meter:HookScript("OnShow", function() C_Timer.After(0, Apply) end)
        if meter.SetupSessionWindow then
            hooksecurefunc(meter, "SetupSessionWindow", function(_, _, data)
                if data and data.sessionWindow then
                    if data.sessionWindow == GetPrimaryWindow(meter) then
                        C_Timer.After(0, Apply)
                    else
                        StyleRows(data.sessionWindow)
                    end
                end
            end)
        end
    end
    local enabled = ns.db.enabledDamageMeter
    if enabled then
        local styles = Enum and Enum.DamageMeterStyle
        if styles and meter.SetStyle then
            local style = ({ minimal = styles.Thin, bordered = styles.Bordered })[ns.db.damageMeterStyle] or styles.Default
            if style == styles.Bordered and ns.db.damageMeterBorder ~= "default" then
                style = styles.Default
            end
            if style ~= nil then meter:SetStyle(style) end
        end
        if meter.SetShowBarIcons then meter:SetShowBarIcons(ns.db.damageMeterIcons) end
        if meter.SetBackgroundTransparency then meter:SetBackgroundTransparency(ns.db.damageMeterBackground) end
        if meter.SetWindowTransparency then meter:SetWindowTransparency(ns.db.damageMeterOpacity) end
        if meter.SetBarSpacing then meter:SetBarSpacing(ns.db.damageMeterSpacing) end
        if meter.SetUseClassColor then meter:SetUseClassColor(ns.db.damageMeterClassColors) end
        if meter.SetTextScale then meter:SetTextScale(ns.db.damageMeterTextSize / 12) end
    end
    if meter.ForEachSessionWindow then meter:ForEachSessionWindow(StyleRows) end
    if not placementOK then geterrorhandler()(placementError) end
    if not lockOK then geterrorhandler()(lockError) end
end

function ns.InitDamageMeter()
    if Menu and Menu.ModifyMenu then
        Menu.ModifyMenu("MENU_DAMAGE_METER_WINDOW_SETTINGS", function(_, root)
            if not ns.db.damageMeterLockMenu then return end
            root:CreateButton(ns.db.damageMeterUnlocked and "Lock" or "Unlock", function()
                if ns.db.damageMeterUnlocked and window and not InCombatLockdown() then SavePosition(window) end
                ns.db.damageMeterUnlocked = not ns.db.damageMeterUnlocked
                if InCombatLockdown() then
                    ns.Refresh()
                    return
                end
                if not ns.db.damageMeterUnlocked and resizeHandle then
                    resizeHandle:Hide()
                    headerDrag:Hide()
                end
                C_Timer.After(0, function()
                    if window and not InCombatLockdown() then ApplyLock() end
                end)
                QueueSavedPlacement()
            end)
        end)
    end
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_LOGIN")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("ADDON_LOADED")
    events:SetScript("OnEvent", function(_, event, addon)
        if event ~= "ADDON_LOADED" or addon == "Blizzard_DamageMeter" then
            C_Timer.After(0, Apply)
        end
    end)
    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function() editingLayout = true end)
        EventRegistry:RegisterCallback("EditMode.Exit", function()
            editingLayout = false
            C_Timer.After(0, Apply)
        end)
    end
end

function ns.RefreshDamageMeter()
    if not ns.db or InCombatLockdown() then return end
    if ns.db.enabledDamageMeter and C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_DamageMeter")
    end
    Apply()
end

function ns.PrintDamageMeterStatus()
    local frame = GetPrimaryWindow(GetMeter())
    local function Value(value)
        return ns.Plain(value) and tostring(value) or "-"
    end
    print(("PhalkTools Meter | unlocked=%s | salvo x=%s y=%s largura=%s altura=%s | escala=%s")
        :format(tostring(ns.db.damageMeterUnlocked), Value(ns.db.damageMeterX), Value(ns.db.damageMeterY),
            Value(ns.db.damageMeterWidth), Value(ns.db.damageMeterHeight), Value(UIParent:GetScale())))
    if frame then
        print(("PhalkTools Meter | janela x=%s y=%s largura=%s altura=%s | pontos=%d")
            :format(Value(frame:GetLeft()), Value(frame:GetTop()), Value(frame:GetWidth()), Value(frame:GetHeight()),
                frame:GetNumPoints()))
        local _, relative = frame:GetPoint(1)
        print("PhalkTools Meter | âncora=" .. (relative and relative:GetName() or "-")
            .. " | erro ao restaurar=" .. tostring(lastPlacementError or "-"))
    else
        print("PhalkTools Meter | janela principal indisponível")
    end
end
