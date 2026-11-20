local _, ns = ...

local hooked, grips, tabs = {}, {}, {}
local placementHooks, placementQueued, restoring = {}, {}, {}
local editingLayout = false
local copyWindow
local copyBuffers = {}

local function TrackCopyText(frame)
    if copyBuffers[frame] or not frame.AddMessage then return end
    local buffer = {}
    copyBuffers[frame] = buffer
    hooksecurefunc(frame, "AddMessage", function(_, message)
        if not ns.db.chatCopyText or not ns.Plain(message) or type(message) ~= "string" then return end
        if #buffer >= 500 then table.remove(buffer, 1) end
        buffer[#buffer + 1] = message
    end)
end
local historyHooks, restoredFrames = {}, {}
local historyReady, replaying = false, false
local historyLifetime = 24 * 60 * 60

local nextHistoryPrune = 0
local function PruneHistory(now)
    nextHistoryPrune = now + 300
    for character, windows in pairs(ns.db.chatHistory or {}) do
        for id, messages in pairs(windows) do
            local kept = 0
            for _, entry in ipairs(messages) do
                if entry.time > now - historyLifetime then
                    kept = kept + 1
                    messages[kept] = entry
                end
            end
            for i = #messages, kept + 1, -1 do messages[i] = nil end
            if kept == 0 then windows[id] = nil end
        end
        if not next(windows) then ns.db.chatHistory[character] = nil end
    end
end

local function HistoryKey()
    local name, realm = UnitFullName("player")
    if name and name ~= "" then return (realm or GetRealmName()) .. "/" .. name end
end

local function RefreshHistory()
    if not ns.db then return end
    if not ns.db.chatKeepHistory then
        ns.db.chatHistory = nil
        return
    end
    if not historyReady then return end
    local character = HistoryKey()
    if not character then return end
    local now = GetServerTime()
    if now >= nextHistoryPrune then PruneHistory(now) end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local name = "ChatFrame" .. i
        local frame = _G[name]
        if frame and frame.AddMessage and not historyHooks[frame] then
            historyHooks[frame] = true
            hooksecurefunc(frame, "AddMessage", function(_, message, r, g, b)
                if replaying or not ns.db.chatKeepHistory or not ns.Plain(message)
                    or type(message) ~= "string" then return end
                local history = ns.db.chatHistory or {}
                ns.db.chatHistory = history
                local windows = history[character] or {}
                history[character] = windows
                local messages = windows[name] or {}
                windows[name] = messages
                messages[#messages + 1] = {
                    time = GetServerTime(), text = message,
                    r = ns.Plain(r) and type(r) == "number" and r or 1,
                    g = ns.Plain(g) and type(g) == "number" and g or 1,
                    b = ns.Plain(b) and type(b) == "number" and b or 1,
                }
            end)
        end
        if frame and frame.AddMessage and not restoredFrames[frame] then
            restoredFrames[frame] = true
            local windows = ns.db.chatHistory and ns.db.chatHistory[character]
            local messages = windows and windows[name]
            if messages and #messages > 0 then
                replaying = true
                for _, entry in ipairs(messages) do
                    pcall(frame.AddMessage, frame, entry.text, entry.r, entry.g, entry.b)
                end
                pcall(frame.AddMessage, frame, "— End of saved chat history —", 0.65, 0.65, 0.65)
                replaying = false
            end
        end
    end
end

local function CopyChat(frame)
    local lines = {}
    local function Append(message)
        if ns.Plain(message) and type(message) == "string" then
            message = message:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            lines[#lines + 1] = message:gsub("|T.-|t", ""):gsub("|A.-|a", "")
        end
    end
    if frame and frame.GetNumMessages and frame.GetMessageInfo then
        local ok, count = pcall(frame.GetNumMessages, frame)
        if ok and ns.Plain(count) and type(count) == "number" then
            for i = 1, count do
                local readable, message = pcall(frame.GetMessageInfo, frame, i)
                if readable then Append(message) end
            end
        end
    end
    if #lines == 0 then
        for _, message in ipairs(copyBuffers[frame] or {}) do Append(message) end
    end
    if not copyWindow then
        copyWindow = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        copyWindow:SetSize(580, 360)
        copyWindow:SetPoint("CENTER")
        copyWindow:SetFrameStrata("DIALOG")
        copyWindow:EnableMouse(true)
        copyWindow:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        copyWindow:SetBackdropColor(0.04, 0.04, 0.05, 0.98)
        local title = copyWindow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 16, -15)
        title:SetText("Copy chat text  |  Ctrl+C")
        local close = CreateFrame("Button", nil, copyWindow, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT")
        close:SetScript("OnClick", function() copyWindow:Hide() end)
        local scroll = CreateFrame("ScrollFrame", nil, copyWindow, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -40)
        scroll:SetPoint("BOTTOMRIGHT", -34, 16)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal or GameFontHighlight)
        edit:SetWidth(530)
        edit:SetHeight(280)
        edit:SetScript("OnEscapePressed", function() copyWindow:Hide() end)
        scroll:SetScrollChild(edit)
        copyWindow.edit = edit
        copyWindow.scroll = scroll
        scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
    end
    copyWindow:Show()
    copyWindow.edit:SetText(#lines > 0 and table.concat(lines, "\n") or "No copyable messages in this tab.")
    copyWindow.edit:SetFocus()
    copyWindow.edit:SetCursorPosition(0)
    copyWindow.scroll:SetVerticalScroll(0)
    copyWindow.edit:HighlightText()
end

function ns.CopyCurrentChat()
    if not ns.db.chatCopyText then
        print("PhalkTools: ative Copy chat text nas opções de Chat.")
        return
    end
    CopyChat(SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME)
end

local function Save(frame)
    local name = frame:GetName()
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    local scale = UIParent:GetScale()
    if not name or not left or not bottom then return end
    ns.db.chatPositions = ns.db.chatPositions or {}
    ns.db.chatPositions[name] = { left = left * scale, bottom = bottom * scale,
        width = frame:GetWidth() * scale, height = frame:GetHeight() * scale }
end

local function Restore(frame)
    local saved = ns.db.chatPositions and ns.db.chatPositions[frame:GetName()]
    if not saved or editingLayout or InCombatLockdown()
        or (frame ~= DEFAULT_CHAT_FRAME and frame.isDocked)
        or (grips[frame] and grips[frame]:GetScript("OnUpdate")) then return end
    local scale = UIParent:GetScale()
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", saved.left / scale, saved.bottom / scale)
    frame:SetSize(saved.width / scale, saved.height / scale)
end

local function QueuePlacement(frame)
    if restoring[frame] or placementQueued[frame] or editingLayout or not ns.db.chatPositions
        or not ns.db.chatPositions[frame:GetName()] then return end
    placementQueued[frame] = true
    C_Timer.After(0, function()
        placementQueued[frame] = nil
        restoring[frame] = true
        local ok, message = pcall(Restore, frame)
        restoring[frame] = nil
        if not ok then geterrorhandler()(message) end
    end)
end

local function WatchPlacement(frame)
    if placementHooks[frame] then return end
    placementHooks[frame] = true
    for _, method in ipairs({ "SetPoint", "SetAllPoints", "SetSize", "SetWidth", "SetHeight" }) do
        if frame[method] then
            hooksecurefunc(frame, method, function() QueuePlacement(frame) end)
        end
    end
end

local function BeginDrag(control, frame, resize)
    if not ns.db.chatUnlocked or editingLayout or InCombatLockdown() then return end
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not left or not bottom then return end
    local width, height = frame:GetSize()
    local x, y = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, bottom + height)
    frame:SetSize(width, height)
    control:SetScript("OnUpdate", function(self)
        if InCombatLockdown() or not IsMouseButtonDown("LeftButton") then
            self:SetScript("OnUpdate", nil)
            if not InCombatLockdown() then Save(frame) end
            return
        end
        local cursorX, cursorY = GetCursorPosition()
        local dx, dy = (cursorX - x) / scale, (cursorY - y) / scale
        if resize then
            frame:SetSize(math.max(180, width + dx), math.max(80, height - dy))
        else
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left + dx, bottom + height + dy)
        end
    end)
end

local function Hook(frame)
    if not frame or hooked[frame] then return end
    hooked[frame] = true
    local grip = CreateFrame("Button", nil, frame)
    grips[frame] = grip
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then BeginDrag(self, frame, true) end
    end)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
end

local function Apply()
    if not ns.db or InCombatLockdown() then return end
    if copyWindow and not ns.db.chatCopyText then copyWindow:Hide() end
    if not ns.db.chatLockMenu then ns.db.chatUnlocked = false end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local frame = _G["ChatFrame" .. i]
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if frame and ns.db.chatCopyText then TrackCopyText(frame) end
        if frame and tab and not tabs[tab] then
            tabs[tab] = true
            tab:RegisterForDrag("LeftButton")
            tab:SetScript("OnDragStart", function()
                local target = frame.isDocked and DEFAULT_CHAT_FRAME or frame
                if ns.db.chatUnlocked and grips[target] then BeginDrag(grips[target], target, false) end
            end)
        end
        local eligible = frame and (frame == DEFAULT_CHAT_FRAME or not frame.isDocked)
        if eligible then
            WatchPlacement(frame)
            QueuePlacement(frame)
        end
        if frame and (eligible and ns.db.chatUnlocked or hooked[frame]) then
            Hook(frame)
            if not ns.db.chatUnlocked and grips[frame]:GetScript("OnUpdate") then
                grips[frame]:SetScript("OnUpdate", nil)
                Save(frame)
            end
            grips[frame]:SetShown(eligible and ns.db.chatUnlocked and not editingLayout)
        end
        if frame and frame.ResizeButton then frame.ResizeButton:Hide() end
    end
end

function ns.InitChat()
    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function() editingLayout = true end)
        EventRegistry:RegisterCallback("EditMode.Exit", function()
            editingLayout = false
            C_Timer.After(0, ns.RefreshChat)
        end)
    end
    if Menu and Menu.ModifyMenu then
        Menu.ModifyMenu("MENU_FCF_TAB", function(owner, root)
            if ns.db.chatCopyText then
                local id = owner and owner.GetID and owner:GetID()
                local frame = id and _G["ChatFrame" .. id] or SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
                root:CreateButton("Copy chat text", function()
                    C_Timer.After(0, function() CopyChat(frame) end)
                end)
            end
            if not ns.db.chatLockMenu then return end
            root:CreateButton(ns.db.chatUnlocked and "Lock" or "Unlock", function()
                ns.db.chatUnlocked = not ns.db.chatUnlocked
                ns.RefreshChat()
            end)
        end)
    end
    if FCF_UpdateResizeButton then
        hooksecurefunc("FCF_UpdateResizeButton", function(frame) frame.ResizeButton:Hide() end)
    end
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("UPDATE_CHAT_WINDOWS")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_LOGOUT")
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGOUT" then
            if ns.db then PruneHistory(GetServerTime()) end
            return
        end
        if event == "PLAYER_ENTERING_WORLD" then historyReady = true end
        C_Timer.After(0, ns.RefreshChat)
    end)
    C_Timer.NewTicker(300, function()
        if ns.db and ns.db.chatHistory then PruneHistory(GetServerTime()) end
    end)
end

function ns.RefreshChat()
    RefreshHistory()
    if InCombatLockdown() then return end
    Apply()
end
