local addonName = ...
local eventFrame = CreateFrame("Frame")
local professionSnapshots = {}
local exportWindow

local function PrintMessage(message)
    print("|cff00ff00RSH Profession Tracker:|r " .. message)
end

local function GetPrimaryProfessions()
    local firstProfession, secondProfession = GetProfessions()
    local professions = {}

    for _, professionIndex in ipairs({ firstProfession, secondProfession }) do
        if professionIndex then
            local name, _, _, _, _, _, skillLineID =
                GetProfessionInfo(professionIndex)
            local professionInfo

            if skillLineID then
                professionInfo =
                    C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLineID)
            end

            table.insert(professions, {
                name = name or "Unknown",
                skillLineID = skillLineID,
                profession = professionInfo and professionInfo.profession,
            })
        end
    end

    return professions
end

local function GetNewestChildProfessionInfo()
    local childProfessionInfos = C_TradeSkillUI.GetChildProfessionInfos()
    local newestInfo

    for _, professionInfo in ipairs(childProfessionInfos or {}) do
        if professionInfo.isPrimaryProfession
            and (not newestInfo
                or professionInfo.sourceCounter > newestInfo.sourceCounter)
        then
            newestInfo = professionInfo
        end
    end

    return newestInfo
end

local function GetPathName(configID, pathID)
    local entryID = C_ProfSpecs.GetSpendEntryForPath(pathID)
    local entryInfo = entryID
        and C_Traits.GetEntryInfo(configID, entryID)
    local definitionInfo = entryInfo
        and entryInfo.definitionID
        and C_Traits.GetDefinitionInfo(entryInfo.definitionID)

    if definitionInfo then
        if definitionInfo.overrideName and definitionInfo.overrideName ~= "" then
            return definitionInfo.overrideName
        end

        if definitionInfo.spellID then
            local spellName = C_Spell.GetSpellName(definitionInfo.spellID)

            if spellName then
                return spellName
            end
        end
    end

    return "Unknown node"
end

local function GetPathRanks(configID, pathID)
    local nodeInfo = C_Traits.GetNodeInfo(configID, pathID)

    if not nodeInfo then
        return nil
    end

    -- The first rank unlocks the path and is not shown as knowledge in the UI.
    local unlockEntryID = C_ProfSpecs.GetUnlockEntryForPath(pathID)
    local unlockEntryInfo = unlockEntryID
        and C_Traits.GetEntryInfo(configID, unlockEntryID)
    local unlockRanks = unlockEntryInfo and unlockEntryInfo.maxRanks or 0
    local currentRank = nodeInfo.currentRank or 0

    if currentRank > 0 then
        currentRank = currentRank - unlockRanks
    end

    return math.max(0, currentRank),
        math.max(0, (nodeInfo.maxRanks or 0) - unlockRanks)
end

local function ScanPath(configID, pathID, name, visited)
    if visited[pathID] then
        return nil
    end

    visited[pathID] = true

    local currentRank, maxRank = GetPathRanks(configID, pathID)

    if currentRank == nil then
        return nil
    end

    local path = {
        name = name or GetPathName(configID, pathID),
        currentRank = currentRank,
        maxRank = maxRank,
        children = {},
    }
    local childIDs = C_ProfSpecs.GetChildrenForPath(pathID)

    for _, childID in ipairs(childIDs or {}) do
        local child = ScanPath(configID, childID, nil, visited)

        if not child then
            return nil
        end

        table.insert(path.children, child)
    end

    return path
end

local function ScanSpecializations(professionID)
    if not C_ProfSpecs.SkillLineHasSpecialization(professionID) then
        return {}, true
    end

    local configID = C_ProfSpecs.GetConfigIDForSkillLine(professionID)

    if not configID or configID == 0 then
        return nil, false
    end

    local tabIDs = C_ProfSpecs.GetSpecTabIDsForSkillLine(professionID)

    if not tabIDs or #tabIDs == 0 then
        return nil, false
    end

    local specializations = {}
    local visited = {}

    for _, tabID in ipairs(tabIDs) do
        local tabInfo = C_ProfSpecs.GetTabInfo(tabID)

        if not tabInfo or not tabInfo.rootNodeID then
            return nil, false
        end

        local specialization = ScanPath(
            configID,
            tabInfo.rootNodeID,
            tabInfo.name,
            visited
        )

        if not specialization then
            return nil, false
        end

        table.insert(specializations, specialization)
    end

    return specializations, true
end

local function GetStatName(statKey)
    local localizedName = _G[statKey]

    if localizedName and localizedName ~= "" then
        localizedName = localizedName:gsub("%%[%d%.$%+%-]*[dfs]", "")
        localizedName = localizedName:gsub("^%s*%+%s*", "")
        localizedName = localizedName:gsub("%s+", " ")
        localizedName = strtrim(localizedName)

        if localizedName ~= "" then
            return localizedName
        end
    end

    local name = statKey:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", "")
    name = name:gsub("_", " "):lower()

    return name:gsub("(%a)([%w']*)", function(firstLetter, remainder)
        return firstLetter:upper() .. remainder
    end)
end

local function GetItemDescription(inventorySlot)
    local itemLink = GetInventoryItemLink("player", inventorySlot)

    if not itemLink then
        return {
            description = "None",
            stats = {},
        }
    end

    local itemName, _, itemQuality = C_Item.GetItemInfo(itemLink)
    local itemLevel = C_Item.GetDetailedItemLevelInfo(itemLink)
    local qualityName = itemQuality
        and _G["ITEM_QUALITY" .. itemQuality .. "_DESC"]
    local parts = { itemName or itemLink:match("%[(.-)%]") or "Unknown item" }

    if itemLevel then
        table.insert(parts, "ilvl " .. itemLevel)
    end

    if qualityName then
        table.insert(parts, qualityName)
    end

    local stats = C_Item.GetItemStats(itemLink) or {}

    return {
        description = table.concat(parts, ", "),
        stats = stats,
    }
end

local function ScanEquipment(profession)
    local equipment = {
        { description = "None", stats = {} },
        { description = "None", stats = {} },
        { description = "None", stats = {} },
    }

    if profession == nil then
        return equipment
    end

    local inventorySlots = C_TradeSkillUI.GetProfessionSlots(profession)

    for index = 1, math.min(3, #(inventorySlots or {})) do
        equipment[index] = GetItemDescription(inventorySlots[index])
    end

    return equipment
end

local function GetHighestQualityReagent(reagents)
    local bestReagent
    local bestQuality = -1

    for _, reagent in ipairs(reagents or {}) do
        local quality = reagent.itemID
            and C_TradeSkillUI.GetItemReagentQualityByItemInfo(reagent.itemID)
            or 0

        if not bestReagent or (quality or 0) >= bestQuality then
            bestReagent = reagent
            bestQuality = quality or 0
        end
    end

    return bestReagent
end

local function BuildBestReagentAllocation(recipeID)
    local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)

    if not schematic then
        return nil
    end

    local allocation = {}

    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        if slot.dataSlotType == Enum.TradeskillSlotDataType.ModifiedReagent
            and slot.required
        then
            local reagent = GetHighestQualityReagent(slot.reagents)

            if not reagent then
                return nil
            end

            table.insert(allocation, {
                reagent = reagent,
                dataSlotIndex = slot.dataSlotIndex,
                quantity = slot.quantityRequired,
            })
        end
    end

    return allocation
end


local function GetOperationQuality(operationInfo)
    if not operationInfo or not operationInfo.isQualityCraft then
        return nil
    end

    return operationInfo.craftingQuality
end

local function GetRecipeOutputItemID(recipeID, recipeInfo)
    local qualityItemIDs = recipeInfo.qualityItemIDs
        or C_TradeSkillUI.GetRecipeQualityItemIDs(recipeID)

    if qualityItemIDs then
        for index = #qualityItemIDs, 1, -1 do
            if qualityItemIDs[index] then
                return qualityItemIDs[index]
            end
        end
    end

    local outputInfo = C_TradeSkillUI.GetRecipeOutputItemData(recipeID)

    return outputInfo and outputInfo.itemID
end

local function GetGearSlotName(itemID)
    local _, _, _, inventoryType = C_Item.GetItemInfoInstant(itemID)

    if inventoryType == "INVTYPE_PROFESSION_TOOL" then
        return "Tool"
    end

    if inventoryType == "INVTYPE_PROFESSION_GEAR" then
        return "Accessory"
    end

    return "Profession gear"
end

local function GetProfessionDisplayName(skillLineID)
    local professionInfo =
        C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLineID)

    if professionInfo
        and professionInfo.professionName
        and professionInfo.professionName ~= ""
    then
        return professionInfo.professionName
    end

    return C_TradeSkillUI.GetTradeSkillDisplayName(skillLineID)
        or "Unknown profession"
end

local function GetAvailableQualityText(recipeID, recipeInfo)
    local maxQuality = recipeInfo.maxQuality
    local qualityIDs = recipeInfo.qualityIDs
        or C_TradeSkillUI.GetQualitiesForRecipe(recipeID)

    if not maxQuality and qualityIDs then
        maxQuality = #qualityIDs
    end

    if not maxQuality or maxQuality == 0 then
        return "None"
    end

    if maxQuality == 1 then
        return "1"
    end

    return "1-" .. maxQuality
end

local function ScanCraftableProfessionGear(professionInfo)
    local currentInfo = C_TradeSkillUI.GetChildProfessionInfo()

    if not currentInfo
        or currentInfo.professionID ~= professionInfo.professionID
    then
        return nil, false
    end

    local concentrationCurrencyID =
        C_TradeSkillUI.GetConcentrationCurrencyID(professionInfo.professionID)
    local concentrationInfo = concentrationCurrencyID
        and concentrationCurrencyID > 0
        and C_CurrencyInfo.GetCurrencyInfo(concentrationCurrencyID)
    local concentrationAvailable = concentrationInfo
        and concentrationInfo.quantity
        or 0
    local gearRecipes = {}

    for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)

        if recipeInfo and recipeInfo.learned then
            local itemID = GetRecipeOutputItemID(recipeID, recipeInfo)
            local targetSkillLineID = itemID
                and C_TradeSkillUI.GetSkillLineForGear(itemID)

            if targetSkillLineID then
                local allocation = BuildBestReagentAllocation(recipeID)
                local withoutConcentration = allocation
                    and C_TradeSkillUI.GetCraftingOperationInfo(
                        recipeID,
                        allocation,
                        nil,
                        false
                    )
                local withConcentration = allocation
                    and C_TradeSkillUI.GetCraftingOperationInfo(
                        recipeID,
                        allocation,
                        nil,
                        true
                    )

                table.insert(gearRecipes, {
                    name = recipeInfo.name,
                    targetProfession =
                        GetProfessionDisplayName(targetSkillLineID),
                    slot = GetGearSlotName(itemID),
                    availableQualities =
                        GetAvailableQualityText(recipeID, recipeInfo),
                    bestQuality = GetOperationQuality(withoutConcentration),
                    concentrationQuality =
                        GetOperationQuality(withConcentration),
                    concentrationCost = withConcentration
                        and withConcentration.concentrationCost,
                    concentrationAvailable = concentrationAvailable,
                })
            end
        end
    end

    table.sort(gearRecipes, function(left, right)
        if left.targetProfession ~= right.targetProfession then
            return left.targetProfession < right.targetProfession
        end

        if left.slot ~= right.slot then
            return left.slot < right.slot
        end

        return left.name < right.name
    end)

    return gearRecipes, true
end

local function GetSortedStats(stats)
    local sortedStats = {}

    for statKey, value in pairs(stats or {}) do
        if type(value) == "number" and value ~= 0 then
            table.insert(sortedStats, {
                key = statKey,
                name = GetStatName(statKey),
                value = value,
            })
        end
    end

    table.sort(sortedStats, function(left, right)
        if left.name == right.name then
            return left.key < right.key
        end

        return left.name < right.name
    end)

    return sortedStats
end

local function AddEquipmentLine(lines, label, item)
    table.insert(lines, "  " .. label .. ": " .. item.description)

    for _, stat in ipairs(GetSortedStats(item.stats)) do
        table.insert(
            lines,
            string.format("    %s: %+.0f", stat.name, stat.value)
        )
    end
end

local function AddEquipmentTotals(lines, equipment)
    local totals = {}

    for _, item in ipairs(equipment) do
        for statKey, value in pairs(item.stats or {}) do
            if type(value) == "number" then
                totals[statKey] = (totals[statKey] or 0) + value
            end
        end
    end

    local sortedTotals = GetSortedStats(totals)

    if #sortedTotals == 0 then
        return
    end

    table.insert(lines, "Profession gear totals:")

    for _, stat in ipairs(sortedTotals) do
        table.insert(
            lines,
            string.format("  %s: %+.0f", stat.name, stat.value)
        )
    end
end

local function ScanCurrentProfession()
    local professionInfo = GetNewestChildProfessionInfo()

    if not professionInfo or not professionInfo.profession then
        return false
    end

    local specializations, isComplete =
        ScanSpecializations(professionInfo.professionID)

    if not isComplete then
        return false
    end

    local currencyInfo =
        C_ProfSpecs.GetCurrencyInfoForSkillLine(professionInfo.professionID)
    local craftableGear, recipesComplete =
        ScanCraftableProfessionGear(professionInfo)

    if not recipesComplete then
        return false
    end

    professionSnapshots[professionInfo.profession] = {
        profession = professionInfo.profession,
        professionID = professionInfo.professionID,
        professionName = professionInfo.professionName,
        expansionName = professionInfo.expansionName,
        skillLevel = professionInfo.skillLevel,
        maxSkillLevel = professionInfo.maxSkillLevel,
        availableKnowledge = currencyInfo and currencyInfo.numAvailable or 0,
        equipment = ScanEquipment(professionInfo.profession),
        specializations = specializations,
        craftableGear = craftableGear,
    }

    return true
end

local function AddCraftableGearLines(lines, gearRecipes)
    table.insert(lines, "")
    table.insert(lines, "Craftable profession gear:")

    if not gearRecipes or #gearRecipes == 0 then
        table.insert(lines, "  None")
        return
    end

    local previousProfession

    for _, recipe in ipairs(gearRecipes) do
        if recipe.targetProfession ~= previousProfession then
            table.insert(lines, "  " .. recipe.targetProfession .. ":")
            previousProfession = recipe.targetProfession
        end

        table.insert(lines, "    " .. recipe.slot .. ": " .. recipe.name)
        table.insert(
            lines,
            "      Available qualities: " .. recipe.availableQualities
        )

        if recipe.bestQuality then
            table.insert(
                lines,
                "      Best reagents: Quality " .. recipe.bestQuality
            )
        else
            table.insert(lines, "      Best reagents: Unable to calculate")
        end

        if recipe.concentrationQuality and recipe.concentrationCost then
            local availability = recipe.concentrationAvailable
                >= recipe.concentrationCost
                and "available"
                or "unavailable"

            table.insert(
                lines,
                "      Best reagents + concentration: Quality "
                    .. recipe.concentrationQuality
            )
            table.insert(
                lines,
                string.format(
                    "      Concentration required: %d (%s; %d available)",
                    recipe.concentrationCost,
                    availability,
                    recipe.concentrationAvailable
                )
            )
        else
            table.insert(
                lines,
                "      Best reagents + concentration: Unable to calculate"
            )
        end
    end
end

local function AddPathLines(lines, path, depth)
    table.insert(
        lines,
        string.rep("  ", depth)
            .. string.format(
                "%s %d/%d",
                path.name,
                path.currentRank,
                path.maxRank
            )
    )

    for _, child in ipairs(path.children) do
        AddPathLines(lines, child, depth + 1)
    end
end

local function BuildProfessionLines(lines, snapshot)
    local displayName = snapshot.professionName

    table.insert(lines, "Profession: " .. displayName)
    table.insert(
        lines,
        string.format("Skill: %d/%d", snapshot.skillLevel, snapshot.maxSkillLevel)
    )
    table.insert(
        lines,
        "Available knowledge: " .. snapshot.availableKnowledge
    )
    table.insert(lines, "Gear:")
    AddEquipmentLine(lines, "Tool", snapshot.equipment[1])
    AddEquipmentLine(lines, "Accessory 1", snapshot.equipment[2])
    AddEquipmentLine(lines, "Accessory 2", snapshot.equipment[3])
    AddEquipmentTotals(lines, snapshot.equipment)
    table.insert(lines, "")
    table.insert(lines, "Specializations:")

    if #snapshot.specializations == 0 then
        table.insert(lines, "  None")
    else
        for _, specialization in ipairs(snapshot.specializations) do
            AddPathLines(lines, specialization, 1)
        end
    end

    AddCraftableGearLines(lines, snapshot.craftableGear)
end

local function CreateExportWindow()
    local window = CreateFrame(
        "Frame",
        addonName .. "ExportWindow",
        UIParent,
        "BasicFrameTemplateWithInset"
    )
    window:SetSize(650, 520)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetClampedToScreen(true)
    window:Hide()

    window.TitleText:SetText("RSH Profession Tracker Export")

    local scrollFrame = CreateFrame(
        "ScrollFrame",
        nil,
        window,
        "UIPanelScrollFrameTemplate"
    )
    scrollFrame:SetPoint("TOPLEFT", 12, -32)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 42)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(590)
    editBox:SetTextInsets(6, 6, 6, 6)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        window:Hide()
    end)
    editBox:SetScript("OnTextChanged", function(self)
        scrollFrame:UpdateScrollChildRect()
    end)
    scrollFrame:SetScrollChild(editBox)
    window.EditBox = editBox

    local selectButton = CreateFrame(
        "Button",
        nil,
        window,
        "UIPanelButtonTemplate"
    )
    selectButton:SetSize(110, 24)
    selectButton:SetPoint("BOTTOM", 0, 10)
    selectButton:SetText("Select all")
    selectButton:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)

    return window
end

local function ShowExport(text)
    exportWindow = exportWindow or CreateExportWindow()
    exportWindow.EditBox:SetText(text)
    exportWindow:Show()
    exportWindow.EditBox:SetFocus()
    exportWindow.EditBox:HighlightText()
end

local function ExportProfessions()
    ScanCurrentProfession()

    for _, snapshot in pairs(professionSnapshots) do
        snapshot.equipment = ScanEquipment(snapshot.profession)
    end

    local primaryProfessions = GetPrimaryProfessions()
    local missingProfessions = {}
    local lines = {
        "Character: " .. (UnitName("player") or "Unknown"),
        "Realm: " .. (GetRealmName() or "Unknown"),
        "",
    }
    local exportedCount = 0

    for _, primaryProfession in ipairs(primaryProfessions) do
        local snapshot = primaryProfession.profession
            and professionSnapshots[primaryProfession.profession]

        if snapshot then
            if exportedCount > 0 then
                table.insert(lines, "")
            end

            BuildProfessionLines(lines, snapshot)
            exportedCount = exportedCount + 1
        else
            table.insert(missingProfessions, primaryProfession.name)
        end
    end

    if #missingProfessions > 0 then
        PrintMessage(
            "Missing specialization data for "
                .. table.concat(missingProfessions, " and ")
                .. ". Open each profession window once, then run "
                .. "/rshprof export again."
        )
        return
    end

    if exportedCount == 0 then
        PrintMessage("No primary professions were found.")
        return
    end

    ShowExport(table.concat(lines, "\n"))
end

local function ScheduleCurrentProfessionScan()
    C_Timer.After(0.25, function()
        if ScanCurrentProfession() then
            local professionInfo = GetNewestChildProfessionInfo()

            if professionInfo then
                PrintMessage(
                    "Scanned "
                        .. (professionInfo.expansionName
                            or professionInfo.professionName)
                        .. "."
                )
            end
        end
    end)
end

eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("SKILL_LINE_SPECS_RANKS_CHANGED")
eventFrame:RegisterEvent("SKILL_LINE_SPECS_UNLOCKED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "TRADE_SKILL_SHOW" then
        ScheduleCurrentProfessionScan()
    else
        C_Timer.After(0, ScanCurrentProfession)
    end
end)

SLASH_RSHPROFESSIONTRACKER1 = "/rshprof"

SlashCmdList.RSHPROFESSIONTRACKER = function(arguments)
    local command = strtrim(arguments or ""):lower()

    if command == "export" then
        ExportProfessions()
    else
        PrintMessage("Use /rshprof export to create a copyable export.")
    end
end
