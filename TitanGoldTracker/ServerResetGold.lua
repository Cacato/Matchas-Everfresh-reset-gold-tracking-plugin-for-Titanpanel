-- Persistent server-reset tracking, independent of the built-in session counters.
local loaded, inWorld = false, false
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Copy(item) end
    return result
end
local function Database()
    if type(TitanGoldTrackerResetDB) ~= "table" then
        TitanGoldTrackerResetDB = type(TitanCurrencyAccountDB) == "table" and Copy(TitanCurrencyAccountDB) or {}
    end
    local db = TitanGoldTrackerResetDB
    db.characters = db.characters or {}
    db.generation = db.generation or 0
    return db
end
local function Update(reason)
    if not loaded or not inWorld then return end
    local db = Database()
    local realm, name = GetRealmName(), UnitName("player")
    db.characters[realm] = db.characters[realm] or {}
    local record = db.characters[realm][name]
    if not record then
        record = { startingMoney = GetMoney(), startedAt = db.startedAt or time() }
        db.characters[realm][name] = record
    end
    local current = GetMoney()
    record.balanceLog = record.balanceLog or {}
    if reason == "PLAYER_ENTERING_WORLD" or reason == "VARIABLES_LOADED"
        or record.currentMoney ~= current then
        record.balanceLog[#record.balanceLog + 1] = {
            at = time(), reason = reason or "tooltip",
            before = record.currentMoney, after = current, baseline = record.startingMoney,
        }
        while #record.balanceLog > 30 do table.remove(record.balanceLog, 1) end
    end
    record.currentMoney = current
    return record
end
local function Money(amount)
    local sign = amount < 0 and "-" or "+"
    amount = math.floor(math.abs(amount))
    return sign .. string.format("%dg %ds %dc", math.floor(amount / 10000), math.floor(amount / 100) % 100, amount % 100)
end
local function ColoredMoney(amount)
    return (amount < 0 and "|cffff6060" or "|cff60ff60") .. Money(amount) .. "|r"
end
local originalEvent = TitanGoldTracker_OnEvent
function TitanGoldTracker_OnEvent(self, event, ...)
    originalEvent(self, event, ...)
    if event == "VARIABLES_LOADED" then loaded = true end
    if event == "PLAYER_ENTERING_WORLD" then inWorld = true end
    Update(event)
end
local function Totals()
    local total, count = 0, 0
    for _, characters in pairs(Database().characters) do
        for _, character in pairs(characters) do
            total = total + (character.currentMoney or character.startingMoney) - character.startingMoney
            count = count + 1
        end
    end
    return total, count
end
local originalTooltip = TitanPanelGoldTrackerButton_GetTooltipText
function TitanPanelGoldTrackerButton_GetTooltipText()
    local original = originalTooltip()
    local record = Update()
    if not record or Database().goldEnabled == false then return original end
    local total, count = Totals()
    return original .. "\n\n|cffffffffGold since last server reset|r\nStarted\t"
        .. date("%Y-%m-%d %H:%M", record.startedAt)
        .. "\nStarting gold\t" .. Money(record.startingMoney):sub(2)
        .. "\nCharacter net gold gain\t" .. ColoredMoney(GetMoney() - record.startingMoney)
        .. "\nAccount net gold gain\t" .. ColoredMoney(total)
        .. "\nTracked characters\t" .. count
end
local originalMenu = TitanPanelRightClickMenu_PrepareGoldTrackerMenu
function TitanPanelRightClickMenu_PrepareGoldTrackerMenu()
    originalMenu()
    if (UIDROPDOWNMENU_MENU_LEVEL or 1) ~= 1 then return end
    TitanPanelRightClickMenu_AddSpacer()
    UIDropDownMenu_AddButton({text = "Show gold gain since last server reset",
        checked = Database().goldEnabled ~= false,
        func = function()
            Database().goldEnabled = Database().goldEnabled == false
            TitanPanelButton_UpdateTooltip(_G.TitanPanelGoldTrackerButton)
        end})
    UIDropDownMenu_AddButton({text = "Reset gold gain since last server reset", notCheckable = true,
        disabled = not (loaded and inWorld),
        func = function() StaticPopup_Show("TITAN_GOLDTRACKER_RESET_SERVER_GOLD") end})
end
StaticPopupDialogs["TITAN_GOLDTRACKER_RESET_SERVER_GOLD"] = {
    text = "Are you sure you want to reset your entire account's gold gain for the current server reset?",
    button1 = YES, button2 = NO,
    OnAccept = function()
        if not loaded or not inWorld then return end
        local db = Database()
        db.characters = {}
        db.generation = db.generation + 1
        db.startedAt = time()
        Update()
        if TitanPanelButton_UpdateTooltip then TitanPanelButton_UpdateTooltip(_G.TitanPanelGoldTrackerButton) end
        return false -- Wrath closes the confirmation when OnAccept returns false/nil.
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

SLASH_MATCHAEVERFRESHGOLD1 = "/matchagolddebug"
SlashCmdList["MATCHAEVERFRESHGOLD"] = function()
    local record = Update("diagnostic")
    if not record then print("Everfresh gold: waiting for character data."); return end
    print("Everfresh gold: " .. UnitName("player") .. " - " .. GetRealmName())
    print("Baseline " .. Money(record.startingMoney) .. "; current " .. Money(record.currentMoney)
        .. "; net " .. Money(record.currentMoney - record.startingMoney))
    for index = math.max(1, #record.balanceLog - 9), #record.balanceLog do
        local entry = record.balanceLog[index]
        print(date("%H:%M:%S", entry.at) .. " " .. entry.reason
            .. " " .. Money(entry.before or entry.after) .. " -> " .. Money(entry.after)
            .. " (baseline " .. Money(entry.baseline) .. ")")
    end
end
