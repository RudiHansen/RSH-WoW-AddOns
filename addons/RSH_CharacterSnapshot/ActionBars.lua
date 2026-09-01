local _, addon = ...

local BUTTONS_PER_PAGE = 12
local DEFAULT_LAST_PAGE = 15

local PAGE_DESCRIPTORS = {
    [1] = { type = "Main action bar", name = "Main Bar - Page 1" },
    [2] = { type = "Main action bar page", name = "Main Bar - Page 2" },
    [3] = { type = "Fixed multi action bar", name = "Right Bar", binding = 3 },
    [4] = { type = "Fixed multi action bar", name = "Left Bar", binding = 4 },
    [5] = { type = "Fixed multi action bar", name = "Bottom Right Bar", binding = 2 },
    [6] = { type = "Fixed multi action bar", name = "Bottom Left Bar", binding = 1 },
    [7] = { type = "Bonus action bar", name = "Bonus Bar 1", bonus = 1 },
    [8] = { type = "Bonus action bar", name = "Bonus Bar 2", bonus = 2 },
    [9] = { type = "Bonus action bar", name = "Bonus Bar 3", bonus = 3 },
    [10] = { type = "Bonus action bar", name = "Bonus Bar 4", bonus = 4 },
    [11] = { type = "Bonus action bar", name = "Bonus Bar 5", bonus = 5 },
    [12] = { type = "Bonus action bar", name = "Bonus Bar 6", bonus = 6 },
    [13] = { type = "Fixed multi action bar", name = "Action Bar 6", binding = 5 },
    [14] = { type = "Fixed multi action bar", name = "Action Bar 7", binding = 6 },
    [15] = { type = "Fixed multi action bar", name = "Action Bar 8", binding = 7 },
}

local function ReadActionBarValue(methodName)
    local method = C_ActionBar and C_ActionBar[methodName]
    return addon:SafeCall(method)
end

local function ReadActionBarFlag(methodName)
    local value = ReadActionBarValue(methodName)

    if value == nil then
        return nil
    end

    return value == true
end

local function GetBindings(command)
    if not command then
        return {}, "Ambiguous"
    end

    local keys = { GetBindingKey(command) }

    if #keys == 0 then
        return {}, "Unbound"
    end

    return keys, "Bound"
end

local function GetBindingCommand(page, button)
    local descriptor = PAGE_DESCRIPTORS[page]

    if descriptor and descriptor.binding then
        return "MULTIACTIONBAR" .. descriptor.binding .. "BUTTON" .. button
    end

    return "ACTIONBUTTON" .. button
end


local function ResolveAction(slot)
    local actionType, actionID, subType, spellID = addon:SafeCall(
        GetActionInfo,
        slot
    )

    if addon:IsSecret(actionType)
        or addon:IsSecret(actionID)
        or addon:IsSecret(subType)
        or addon:IsSecret(spellID)
    then
        return {
            type = "Unavailable",
            name = "Restricted action data",
        }
    end

    if not actionType then
        return nil
    end

    local action = {
        type = actionType,
        id = actionID,
        subType = subType,
        spellID = spellID,
    }

    if actionType == "spell" then
        action.spellID = tonumber(actionID) or tonumber(spellID)
        action.name = action.spellID and C_Spell
            and C_Spell.GetSpellName
            and addon:SafeCall(C_Spell.GetSpellName, action.spellID)
    elseif actionType == "item" then
        action.itemID = tonumber(actionID)
        action.name = action.itemID and C_Item.GetItemNameByID(action.itemID)
    elseif actionType == "macro" then
        action.macroID = tonumber(actionID)

        if action.macroID then
            action.name, action.icon, action.macroBody = GetMacroInfo(action.macroID)
        end
    elseif actionType == "equipmentset" then
        if type(actionID) == "string" then
            action.name = actionID
            action.equipmentSetID = C_EquipmentSet
                and C_EquipmentSet.GetEquipmentSetID
                and addon:SafeCall(
                    C_EquipmentSet.GetEquipmentSetID,
                    actionID
                )
        elseif type(actionID) == "number" then
            action.equipmentSetID = actionID
            action.name = C_EquipmentSet
                and C_EquipmentSet.GetEquipmentSetInfo
                and addon:SafeCall(
                    C_EquipmentSet.GetEquipmentSetInfo,
                    actionID
                )
        end
    elseif actionType == "flyout" then
        action.flyoutID = actionID
        action.name = GetFlyoutInfo and select(1, GetFlyoutInfo(actionID))
    else
        action.name = GetActionText and GetActionText(slot)
    end

    action.name = action.name or "Unknown action"
    return action
end

local function AddPage(pagesByIndex, pageIndex, specialType, active)
    if type(pageIndex) ~= "number" or pageIndex < 1 then
        return
    end

    local page = pagesByIndex[pageIndex]

    if not page then
        local descriptor = PAGE_DESCRIPTORS[pageIndex] or {}
        page = {
            page = pageIndex,
            name = descriptor.name or ("Action Page " .. pageIndex),
            type = descriptor.type or "Other action page",
            association = descriptor.bonus and "Unknown" or "Known",
            active = false,
            specialTypes = {},
            actions = {},
        }
        pagesByIndex[pageIndex] = page
    end

    if specialType then
        table.insert(page.specialTypes, specialType)
        page.type = specialType
        page.association = "Known: " .. specialType
    end

    if active then
        page.active = true
    end
end

function addon:CollectActionBars()
    local currentPage = ReadActionBarValue("GetActionBarPage")
    local bonusIndex = ReadActionBarValue("GetBonusBarIndex")
    local bonusOffset = ReadActionBarValue("GetBonusBarOffset")
    local overridePage = ReadActionBarValue("GetOverrideBarIndex")
    local vehiclePage = ReadActionBarValue("GetVehicleBarIndex")
    local tempPage = ReadActionBarValue("GetTempShapeshiftBarIndex")
    local extraPage = ReadActionBarValue("GetExtraBarIndex")
    local multiCastPage = ReadActionBarValue("GetMultiCastBarIndex")
    local state = {
        currentPage = currentPage,
        bonusIndex = bonusIndex,
        bonusOffset = bonusOffset,
        overridePage = overridePage,
        vehiclePage = vehiclePage,
        tempShapeshiftPage = tempPage,
        extraPage = extraPage,
        multiCastPage = multiCastPage,
        bonusActive = ReadActionBarFlag("HasBonusActionBar"),
        overrideActive = ReadActionBarFlag("HasOverrideActionBar"),
        vehicleActive = ReadActionBarFlag("HasVehicleActionBar"),
        tempShapeshiftActive = ReadActionBarFlag("HasTempShapeshiftActionBar"),
        extraActive = ReadActionBarFlag("HasExtraActionBar"),
        possessVisible = ReadActionBarFlag("IsPossessBarVisible"),
        shapeshiftForm = GetShapeshiftForm and GetShapeshiftForm() or nil,
        mounted = IsMounted and IsMounted() or nil,
    }
    local pagesByIndex = {}

    local specialPageActive = state.bonusActive
        or state.overrideActive
        or state.vehicleActive
        or state.tempShapeshiftActive

    for pageIndex = 1, DEFAULT_LAST_PAGE do
        AddPage(
            pagesByIndex,
            pageIndex,
            nil,
            not specialPageActive and pageIndex == currentPage
        )
    end

    AddPage(pagesByIndex, overridePage, "Override action bar", state.overrideActive)
    AddPage(pagesByIndex, vehiclePage, "Vehicle action bar", state.vehicleActive)
    AddPage(pagesByIndex, tempPage, "Temporary shapeshift action bar", state.tempShapeshiftActive)
    AddPage(pagesByIndex, extraPage, "Extra action bar", state.extraActive)
    AddPage(pagesByIndex, multiCastPage, "Multi-cast action bar", false)

    if state.bonusActive and bonusIndex then
        AddPage(
            pagesByIndex,
            bonusIndex + 6,
            "Bonus action bar",
            true
        )
    end

    local pages = {}
    local actionSpellIDs = {}

    for _, page in pairs(pagesByIndex) do
        page.firstSlot = ((page.page - 1) * BUTTONS_PER_PAGE) + 1
        page.lastSlot = page.firstSlot + BUTTONS_PER_PAGE - 1
        page.containsActions = false

        for button = 1, BUTTONS_PER_PAGE do
            local slot = page.firstSlot + button - 1
            local command = GetBindingCommand(page.page, button)
            local keys, bindingStatus = GetBindings(command)
            local entry = {
                button = button,
                slot = slot,
                bindingCommand = command,
                bindings = keys,
                bindingStatus = bindingStatus,
                action = ResolveAction(slot),
            }

            if entry.action then
                page.containsActions = true

                if entry.action.type == "spell" and entry.action.spellID then
                    actionSpellIDs[entry.action.spellID] = true
                end
            end

            table.insert(page.actions, entry)
        end

        table.sort(page.specialTypes)
        table.insert(pages, page)
    end

    table.sort(pages, function(left, right)
        return left.page < right.page
    end)

    return state, pages, actionSpellIDs
end
