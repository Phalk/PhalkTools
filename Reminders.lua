local _, ns = ...

local frame, icons, combatGate, listScroll, listContent
local elapsed, previous, lastSound = 0, {}, -1000

local spells = {}

local function BuildSpells()
    wipe(spells)
    for _, entry in ipairs(ns.db.customReminders) do
        if type(entry) == "table" and type(entry.id) == "number" and entry.id > 0 then
            spells[#spells + 1] = { id = entry.id, key = "custom:" .. entry.id,
                auraIDs = { entry.id }, label = "Spell " .. entry.id, icon = 134400, entry = entry }
        end
    end
end

local function IsBuffUp(spell)
    local auras = C_UnitAuras
    if auras and auras.GetPlayerAuraBySpellID then
        for _, id in ipairs(spell.auraIDs) do
            local ok, aura = pcall(auras.GetPlayerAuraBySpellID, id)
            if ok and aura ~= nil then
                if ns.Plain(aura) then return true end
                return nil
            end
        end
    end
    if auras and auras.GetAuraDataByIndex then
        for index = 1, 80 do
            local ok, aura = pcall(auras.GetAuraDataByIndex, "player", index, "HELPFUL")
            if not ok then break end
            if aura == nil then return false end
            if not ns.Plain(aura) then return nil end
            if ns.Plain(aura.name) and aura.name == spell.name then return true end
            if ns.Plain(aura.spellId) then
                for _, id in ipairs(spell.auraIDs) do
                    if aura.spellId == id then return true end
                end
            end
        end
    end
    if UnitBuff then
        for index = 1, 80 do
            local ok, name, _, _, _, _, _, _, _, _, _, id = pcall(UnitBuff, "player", index)
            if not ok then break end
            if name == nil then return false end
            if not ns.Plain(name) then return nil end
            if ns.Plain(id) then
                for _, spellID in ipairs(spell.auraIDs) do
                    if id == spellID then return true end
                end
            end
            if spell.name and name == spell.name then return true end
        end
    end
    if spell.name and auras and auras.GetAuraDataBySpellName then
        local ok, aura = pcall(auras.GetAuraDataBySpellName, "player", spell.name, "HELPFUL")
        if ok then
            if aura == nil then return false end
            if ns.Plain(aura) then return true end
        end
    end
end

local function SavePosition()
    if InCombatLockdown() then return end
    frame:StopMovingOrSizing()
    local x, y = frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if x and y and parentX and parentY then
        ns.db.reminderX = math.floor(x - parentX + 0.5)
        ns.db.reminderY = math.floor(y - parentY + 0.5)
    end
end

local function MakeIcon(index)
    local holder = CreateFrame("Button", "PhalkToolsReminderButton" .. index, listContent,
        "SecureActionButtonTemplate,BackdropTemplate")
    holder:SetSize(272, 40)
    holder:RegisterForClicks("AnyUp", "AnyDown")
    holder:SetAttribute("*type1", "spell")
    holder:SetAttribute("unit", "player")
    holder:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    holder:SetBackdropColor(0.075, 0.09, 0.11, 1)
    holder:SetBackdropBorderColor(0.22, 0.30, 0.28, 1)
    holder:RegisterForDrag("RightButton")
    holder:SetScript("OnDragStart", function()
        if not InCombatLockdown() then frame:StartMoving() end
    end)
    holder:SetScript("OnDragStop", SavePosition)

    local art = holder:CreateTexture(nil, "ARTWORK")
    art:SetPoint("LEFT", 6, 0)
    art:SetSize(28, 28)
    art:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    holder.art = art

    local accent = holder:CreateTexture(nil, "OVERLAY")
    accent:SetPoint("TOPLEFT", 0, -1)
    accent:SetPoint("BOTTOMLEFT", 0, 1)
    accent:SetWidth(2)
    accent:SetColorTexture(0.45, 0.78, 0.57, 1)

    holder.name = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    holder.name:SetPoint("TOPLEFT", 44, -7)
    holder.name:SetWidth(218)
    holder.name:SetJustifyH("LEFT")
    local hint = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("BOTTOMLEFT", 44, 7)
    hint:SetText("Click to cast")
    hint:SetTextColor(0.55, 0.78, 0.63)

    local highlight = holder:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.65, 0.9, 0.75, 0.1)
    holder:SetHighlightTexture(highlight)
    local pressed = holder:CreateTexture(nil, "ARTWORK", nil, 3)
    pressed:SetAllPoints()
    pressed:SetColorTexture(0, 0, 0, 0.25)
    holder:SetPushedTexture(pressed)
    holder:SetScript("OnEnter", function(self)
        local spell = self.spell
        if not spell then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(spell.name or spell.label, 0.65, 0.9, 0.72)
        GameTooltip:AddLine("Click to cast on yourself.", 1, 1, 1)
        GameTooltip:AddLine("Right-drag to move.", 0.65, 0.65, 0.65)
        GameTooltip:Show()
    end)
    holder:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return holder
end

local function Update()
    -- Secure buttons and all their ancestors must remain untouched in combat.
    -- The secure visibility driver hides the panel until combat ends.
    if not frame or InCombatLockdown() then return end
    if not ns.db or not ns.db.enabledReminders or UnitIsDeadOrGhost("player") then
        frame:Hide()
        return
    end
    local count, newlyMissing = 0, false
    for index, spell in ipairs(spells) do
        local missing = previous[spell.key] or false
        -- Localized names select the highest learned rank in the secure spell action.
        local name, icon = ns.SpellInfo(spell.id)
        spell.name = name or spell.name or spell.label
        spell.icon = icon or spell.icon
        icons[index].spell = spell
        icons[index]:SetAttribute("spell", spell.name)
        icons[index].name:SetText(spell.name)
        icons[index].art:SetTexture(spell.icon)
        if spell.entry.enabled == false then
            missing = false
        else
            local knows = ns.KnowsSpell(spell.id)
            if knows == false then
                local _, _, resolved = ns.SpellInfo(spell.name)
                if resolved then knows = ns.KnowsSpell(resolved) end
            end
            if knows ~= false then
                local active = ns.TrackingActive(spell.id)
                if active == nil then active = IsBuffUp(spell) end
                if active ~= nil then missing = not active end
            else
                missing = false
            end
        end

        if missing then
            count = count + 1
            icons[index]:ClearAllPoints()
            icons[index]:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -(count - 1) * 46)
            icons[index]:Show()
            if not previous[spell.key] then newlyMissing = true end
        else
            icons[index]:Hide()
        end
        previous[spell.key] = missing
    end

    if count == 0 then
        frame:Hide()
    else
        local height = count * 46 - 6
        listContent:SetHeight(height)
        frame:SetSize(324, math.min(height, 362) + 62)
        listScroll:SetVerticalScroll(math.min(listScroll:GetVerticalScroll(), math.max(0, height - 362)))
        frame:Show()
    end
    local now = GetTime()
    if newlyMissing and ns.db.reminderSound and now - lastSound >= 90 then
        ns.PlayPing()
        lastSound = now
    end
end

function ns.RefreshReminders()
    if not frame or InCombatLockdown() then return end
    BuildSpells()
    for index = 1, #spells do
        if not icons[index] then icons[index] = MakeIcon(index) end
    end
    for index = #spells + 1, #icons do icons[index]:Hide(); icons[index].spell = nil end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", ns.db.reminderX or 0, ns.db.reminderY or 190)
    elapsed = 2
    Update()
end

function ns.GetReminderEntries()
    local entries = {}
    for _, entry in ipairs(ns.db.customReminders) do
        if type(entry) == "table" and type(entry.id) == "number" and entry.id > 0 then
            local name, icon = ns.SpellInfo(entry.id)
            entries[#entries + 1] = { key = "custom:" .. entry.id, id = entry.id,
                name = name or ("Spell " .. entry.id), icon = icon or 134400,
                enabled = entry.enabled ~= false }
        end
    end
    return entries
end

function ns.AddReminder(input)
    if InCombatLockdown() then return false, "Leave combat to edit the list." end
    input = tostring(input or ""):match("^%s*(.-)%s*$")
    if input == "" then return false, "Enter the name or ID of a buff spell." end
    local name, _, id = ns.SpellInfo(tonumber(input) or input)
    if not name or not id or type(id) ~= "number" or id <= 0 or id ~= math.floor(id) then
        return false, "Spell not found. Try its ID or its name in the game language."
    end
    for _, entry in ipairs(ns.GetReminderEntries()) do
        if entry.id == id or entry.name == name then return false, "This buff is already in the list." end
    end
    ns.db.customReminders[#ns.db.customReminders + 1] = { id = id, enabled = true }
    ns.RefreshReminders()
    return true, name .. " added. Only appears when learned and missing."
end

function ns.SetReminderEnabled(key, enabled)
    if InCombatLockdown() then return false, "Leave combat to edit the list." end
    for _, entry in ipairs(ns.db.customReminders) do
        if type(entry) == "table" and key == "custom:" .. tostring(entry.id) then
            entry.enabled = enabled
            ns.RefreshReminders()
            return true
        end
    end
    return false, "Buff not found."
end

function ns.RemoveReminder(key)
    if InCombatLockdown() then return false, "Leave combat to edit the list." end
    for index, entry in ipairs(ns.db.customReminders) do
        if type(entry) == "table" and key == "custom:" .. tostring(entry.id) then
            table.remove(ns.db.customReminders, index)
            previous[key] = nil
            ns.RefreshReminders()
            return true, "Buff removed."
        end
    end
    return false, "Buff not found."
end

local editor
function ns.OpenReminderEditor()
    if not editor then
        editor = CreateFrame("Frame", "PhalkToolsBuffEditor", UIParent, "BackdropTemplate")
        editor:SetSize(440, 520)
        editor:SetPoint("CENTER")
        editor:SetFrameStrata("DIALOG")
        editor:SetClampedToScreen(true)
        editor:SetMovable(true)
        editor:EnableMouse(true)
        editor:RegisterForDrag("LeftButton")
        editor:SetScript("OnDragStart", editor.StartMoving)
        editor:SetScript("OnDragStop", editor.StopMovingOrSizing)
        editor:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        editor:SetBackdropColor(0.025, 0.035, 0.045, 0.98)
        editor:SetBackdropBorderColor(0.22, 0.35, 0.27, 1)
        if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "PhalkToolsBuffEditor" end
        local close = CreateFrame("Button", nil, editor, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        local title = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 18, -18)
        title:SetText("Buff list")
        local help = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        help:SetPoint("TOPLEFT", 18, -48)
        help:SetWidth(400)
        help:SetJustifyH("LEFT")
        help:SetText("Add a spell by its name in the game language or by spell ID.\nReminders appear for learned spells that are missing from you.")
        local input = CreateFrame("EditBox", "PhalkToolsBuffInput", editor, "InputBoxTemplate")
        input:SetSize(280, 28)
        input:SetPoint("TOPLEFT", 24, -90)
        input:SetAutoFocus(false)
        input:SetMaxLetters(128)
        input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        local add = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
        add:SetSize(100, 28)
        add:SetPoint("LEFT", input, "RIGHT", 12, 0)
        add:SetText("Add")
        local status = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status:SetPoint("TOPLEFT", 18, -128)
        status:SetWidth(400)
        status:SetJustifyH("LEFT")
        local scroll = CreateFrame("ScrollFrame", "PhalkToolsBuffEditorScroll", editor, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -166)
        scroll:SetPoint("BOTTOMRIGHT", -36, 38)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(386, 1)
        scroll:SetScrollChild(content)
        local empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        empty:SetPoint("TOPLEFT", 8, -12)
        empty:SetWidth(370)
        empty:SetJustifyH("LEFT")
        empty:SetText("No buffs added yet. Add your first buff using the field above.")
        local footer = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        footer:SetPoint("BOTTOMLEFT", 18, 14)
        footer:SetText("Uncheck to pause a buff. Editing is available out of combat.")
        local rows = {}
        local function Message(ok, message)
            status:SetText(message or "")
            status:SetTextColor(ok and 0.55 or 1, ok and 0.85 or 0.45, 0.6)
        end
        local function RefreshRows()
            local entries = ns.GetReminderEntries()
            empty:SetShown(#entries == 0)
            for index, entry in ipairs(entries) do
                local row = rows[index]
                if not row then
                    row = CreateFrame("Frame", nil, content)
                    row:SetSize(386, 44)
                    row:SetPoint("TOPLEFT", 0, -(index - 1) * 46)
                    row.toggle = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                    row.toggle:SetSize(26, 26)
                    row.toggle:SetPoint("LEFT")
                    row.icon = row:CreateTexture(nil, "ARTWORK")
                    row.icon:SetSize(28, 28)
                    row.icon:SetPoint("LEFT", 30, 0)
                    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.label:SetPoint("TOPLEFT", 66, -7)
                    row.label:SetWidth(222)
                    row.label:SetJustifyH("LEFT")
                    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                    row.detail:SetPoint("BOTTOMLEFT", 66, 7)
                    row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.remove:SetSize(78, 24)
                    row.remove:SetPoint("RIGHT")
                    row.remove:SetText("Remove")
                    row.toggle:SetScript("OnClick", function(self)
                        local ok, message = ns.SetReminderEnabled(row.entry.key, self:GetChecked())
                        Message(ok, message)
                        RefreshRows()
                    end)
                    row.remove:SetScript("OnClick", function()
                        Message(ns.RemoveReminder(row.entry.key))
                        RefreshRows()
                    end)
                    rows[index] = row
                end
                row.entry = entry
                row.toggle:SetChecked(entry.enabled)
                row.icon:SetTexture(entry.icon)
                row.label:SetText(entry.name)
                row.detail:SetText("ID: " .. entry.id)
                row.remove:Show()
                row:Show()
            end
            for index = #entries + 1, #rows do rows[index]:Hide() end
            local height = math.max(46, #entries * 46)
            content:SetHeight(height)
            scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), math.max(0, height - scroll:GetHeight())))
        end
        local function Add()
            local ok, message = ns.AddReminder(input:GetText())
            Message(ok, message)
            if ok then input:SetText(""); input:ClearFocus() end
            RefreshRows()
        end
        add:SetScript("OnClick", Add)
        input:SetScript("OnEnterPressed", Add)
        editor:SetScript("OnShow", function()
            Message(true, "")
            RefreshRows()
        end)
    end
    -- Newly created frames are already shown, so explicitly trigger the refresh.
    editor:Hide()
    editor:Show()
end

function ns.InitReminders()
    if InCombatLockdown() then
        local deferred = CreateFrame("Frame")
        deferred:RegisterEvent("PLAYER_REGEN_ENABLED")
        deferred:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            ns.InitReminders()
            ns.RefreshReminders()
        end)
        return
    end
    BuildSpells()
    for _, spell in ipairs(spells) do
        local name, icon = ns.SpellInfo(spell.id)
        spell.name = name or spell.label
        spell.icon = icon or spell.icon
    end

    combatGate = CreateFrame("Frame", "PhalkToolsReminderCombatGate", UIParent, "SecureHandlerStateTemplate")
    combatGate:SetAllPoints(UIParent)
    RegisterStateDriver(combatGate, "visibility", "[combat] hide; show")
    frame = CreateFrame("Frame", "PhalkToolsReminderFrame", combatGate, "BackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(324, 102)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", SavePosition)

    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0.025, 0.035, 0.045, 0.94)
    frame:SetBackdropBorderColor(0.18, 0.25, 0.23, 1)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 12, -12)
    label:SetText("MISSING BUFFS")
    label:SetTextColor(0.65, 0.83, 0.71)
    listScroll = CreateFrame("ScrollFrame", "PhalkToolsReminderScroll", frame, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 12, -32)
    listScroll:SetPoint("BOTTOMRIGHT", -32, 30)
    listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(272, 1)
    listScroll:SetScrollChild(listContent)

    icons = {}
    for index = 1, #spells do icons[index] = MakeIcon(index) end
    frame:Hide()

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("UNIT_AURA")
    frame:RegisterEvent("SPELLS_CHANGED")
    frame:RegisterEvent("MINIMAP_UPDATE_TRACKING")
    frame:RegisterEvent("PLAYER_ALIVE")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(_, event, unit)
        if event ~= "UNIT_AURA" or unit == "player" then ns.RefreshReminders() end
    end)
    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 2 then
            elapsed = 0
            Update()
        end
    end)
end
