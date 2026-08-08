local addonName = ...
local eventFrame = CreateFrame("Frame")
local professionSnapshots = {}
local professionMidnightStatus = {}
local exportWindow
local FUSED_VITALITY_ITEM_ID = 245345
local DATABASE_VERSION = 1

local function InitialiseDatabase()
    RSHProfessionTrackerDB = RSHProfessionTrackerDB or {}
    RSHProfessionTrackerDB.version = DATABASE_VERSION
    RSHProfessionTrackerDB.characters =
        RSHProfessionTrackerDB.characters or {}
end

local function GetCharacterRecord()
    InitialiseDatabase()

    local realmName = GetRealmName() or "Unknown"
    local characterName = UnitName("player") or "Unknown"
    local realmCharacters = RSHProfessionTrackerDB.characters[realmName]

    if not realmCharacters then
        realmCharacters = {}
        RSHProfessionTrackerDB.characters[realmName] = realmCharacters
    end

    local characterRecord = realmCharacters[characterName]

    if not characterRecord then
        characterRecord = {
            character = characterName,
            realm = realmName,
            professions = {},
            midnightStatus = {},
        }
        realmCharacters[characterName] = characterRecord
    end

    characterRecord.professions = characterRecord.professions or {}
    characterRecord.midnightStatus = characterRecord.midnightStatus or {}

    return characterRecord
end

local function LoadCharacterData()
    local characterRecord = GetCharacterRecord()
    professionSnapshots = characterRecord.professions
    professionMidnightStatus = characterRecord.midnightStatus
end

local function SaveCharacterResources()
    local characterRecord = GetCharacterRecord()
    characterRecord.fusedVitality = C_Item.GetItemCount(
        FUSED_VITALITY_ITEM_ID,
        true,
        false,
        true,
        false
    )
    characterRecord.resourcesCollectedAt = GetServerTime()

    return characterRecord.fusedVitality,
        characterRecord.resourcesCollectedAt
end

local function FormatTimestamp(timestamp)
    if not timestamp then
        return "Unknown"
    end

    return date("%Y-%m-%d %H:%M:%S", timestamp)
end

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

local function GetMidnightChildProfessionInfo()
    local childProfessionInfos = C_TradeSkillUI.GetChildProfessionInfos()
    local midnightExpansionName =
        _G["EXPANSION_NAME" .. Enum.ExpansionLevel.Midnight]

    for _, professionInfo in ipairs(childProfessionInfos or {}) do
        if professionInfo.isPrimaryProfession
            and professionInfo.expansionName == midnightExpansionName
        then
            return professionInfo
        end
    end

    return nil
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

local function GetRecipeOutputItemIDs(recipeID, recipeInfo)
    local itemIDs = {}
    local seenItemIDs = {}
    local qualityItemIDs = recipeInfo.qualityItemIDs
        or C_TradeSkillUI.GetRecipeQualityItemIDs(recipeID)

    if qualityItemIDs then
        for index = #qualityItemIDs, 1, -1 do
            local itemID = qualityItemIDs[index]

            if itemID and not seenItemIDs[itemID] then
                table.insert(itemIDs, itemID)
                seenItemIDs[itemID] = true
            end
        end
    end

    local outputInfo = C_TradeSkillUI.GetRecipeOutputItemData(recipeID)
    local outputItemID = outputInfo and outputInfo.itemID

    if outputItemID and not seenItemIDs[outputItemID] then
        table.insert(itemIDs, outputItemID)
    end

    return itemIDs
end

local PROFESSION_SKILL_LINES_BY_NAME = {
    { name = "Alchemy", skillLineID = 171 },
    { name = "Blacksmithing", skillLineID = 164 },
    { name = "Cooking", skillLineID = 185 },
    { name = "Enchanting", skillLineID = 333 },
    { name = "Engineering", skillLineID = 202 },
    { name = "Fishing", skillLineID = 356 },
    { name = "Herbalism", skillLineID = 182 },
    { name = "Inscription", skillLineID = 773 },
    { name = "Jewelcrafting", skillLineID = 755 },
    { name = "Leatherworking", skillLineID = 165 },
    { name = "Mining", skillLineID = 186 },
    { name = "Skinning", skillLineID = 393 },
    { name = "Tailoring", skillLineID = 197 },
}

-- GetSkillLineForGear does not currently identify every Midnight profession
-- item. Keep narrowly scoped recipe overrides for confirmed API omissions.
local PROFESSION_SKILL_LINE_BY_RECIPE_ID = {
    [1229602] = 182, -- Sun-Blessed Sickle: Herbalism
}

local function GetProfessionSkillLineFromRecipeName(recipeName)
    for _, profession in ipairs(PROFESSION_SKILL_LINES_BY_NAME) do
        if recipeName:find(profession.name, 1, true) then
            return profession.skillLineID
        end
    end

    return nil
end

local function GetProfessionGearInfo(recipeID, recipeInfo)
    local itemIDs = GetRecipeOutputItemIDs(recipeID, recipeInfo)

    for _, itemID in ipairs(itemIDs) do
        local skillLineID = C_TradeSkillUI.GetSkillLineForGear(itemID)

        if skillLineID then
            return itemID, skillLineID
        end
    end

    local overrideSkillLineID = PROFESSION_SKILL_LINE_BY_RECIPE_ID[recipeID]

    if overrideSkillLineID and itemIDs[1] then
        return itemIDs[1], overrideSkillLineID
    end

    local fallbackSkillLineID =
        GetProfessionSkillLineFromRecipeName(recipeInfo.name or "")

    if fallbackSkillLineID then
        for _, itemID in ipairs(itemIDs) do
            local _, _, _, inventoryType = C_Item.GetItemInfoInstant(itemID)

            if inventoryType == "INVTYPE_PROFESSION_TOOL"
                or inventoryType == "INVTYPE_PROFESSION_GEAR"
            then
                return itemID, fallbackSkillLineID
            end
        end
    end

    for _, itemID in ipairs(itemIDs) do
        local _, _, _, inventoryType = C_Item.GetItemInfoInstant(itemID)

        if inventoryType == "INVTYPE_PROFESSION_TOOL"
            or inventoryType == "INVTYPE_PROFESSION_GEAR"
        then
            return itemID, nil, inventoryType, itemIDs
        end
    end

    return nil, nil
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

local function GetItemRarityName(itemID)
    local _, _, itemQuality = C_Item.GetItemInfo(itemID)

    return itemQuality and _G["ITEM_QUALITY" .. itemQuality .. "_DESC"]
        or "Unknown"
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
    local gearWarnings = {}

    for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)

        if recipeInfo and recipeInfo.learned then
            local itemID, targetSkillLineID, inventoryType, outputItemIDs =
                GetProfessionGearInfo(recipeID, recipeInfo)

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
                    rarity = GetItemRarityName(itemID),
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
            elseif itemID and inventoryType then
                local clientVersion, clientBuild = GetBuildInfo()

                table.insert(gearWarnings, {
                    recipeID = recipeID,
                    recipeName = recipeInfo.name,
                    itemID = itemID,
                    outputItemIDs = outputItemIDs,
                    inventoryType = inventoryType,
                    sourceProfession = professionInfo.professionName,
                    sourceProfessionID = professionInfo.professionID,
                    clientVersion = clientVersion,
                    clientBuild = clientBuild,
                    clientLocale = GetLocale(),
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

    table.sort(gearWarnings, function(left, right)
        return left.recipeID < right.recipeID
    end)

    return gearRecipes, true, gearWarnings
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
    local childProfessionInfos = C_TradeSkillUI.GetChildProfessionInfos()

    if not childProfessionInfos or #childProfessionInfos == 0 then
        return false
    end

    local professionInfo = GetMidnightChildProfessionInfo()

    if not professionInfo or not professionInfo.profession then
        local baseProfessionInfo = C_TradeSkillUI.GetBaseProfessionInfo()

        if baseProfessionInfo
            and baseProfessionInfo.isPrimaryProfession
            and baseProfessionInfo.profession
        then
            professionMidnightStatus[baseProfessionInfo.profession] = false
            professionSnapshots[baseProfessionInfo.profession] = nil
            local characterRecord = GetCharacterRecord()
            characterRecord.midnightStatus = professionMidnightStatus
            characterRecord.professions = professionSnapshots
        end

        return false
    end

    professionMidnightStatus[professionInfo.profession] = true

    local specializations, isComplete =
        ScanSpecializations(professionInfo.professionID)

    if not isComplete then
        return false
    end

    local currencyInfo =
        C_ProfSpecs.GetCurrencyInfoForSkillLine(professionInfo.professionID)
    local craftableGear, recipesComplete, craftableGearWarnings =
        ScanCraftableProfessionGear(professionInfo)

    if not recipesComplete then
        return false
    end

    local collectedAt = GetServerTime()
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
        craftableGearWarnings = craftableGearWarnings,
        collectedAt = collectedAt,
    }

    local characterRecord = GetCharacterRecord()
    characterRecord.professions = professionSnapshots
    characterRecord.midnightStatus = professionMidnightStatus
    characterRecord.lastProfessionCollectedAt = collectedAt

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
        table.insert(lines, "      Rarity: " .. (recipe.rarity or "Unknown"))
        table.insert(
            lines,
            "      Available qualities: " .. recipe.availableQualities
        )
        if recipe.bestQuality then
            table.insert(
                lines,
                "      Best quality: " .. recipe.bestQuality
            )
        else
            table.insert(lines, "      Best quality: Unable to calculate")
        end

        if recipe.bestQuality
            and recipe.concentrationQuality
            and recipe.concentrationQuality <= recipe.bestQuality
        then
            table.insert(
                lines,
                "      Best quality with Concentration: Not required"
            )
        elseif recipe.concentrationQuality and recipe.concentrationCost then
            local availability = recipe.concentrationAvailable
                >= recipe.concentrationCost
                and "available"
                or "unavailable"

            table.insert(
                lines,
                "      Best quality with Concentration: "
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
                "      Best quality with Concentration: Unable to calculate"
            )
        end
    end
end

local function AddCraftableGearWarningLines(lines, warnings)
    if not warnings or #warnings == 0 then
        return
    end

    table.insert(lines, "")
    table.insert(lines, "WARNING: Unclassified craftable profession gear")
    table.insert(
        lines,
        "WoW returned no target profession. Copy this block when reporting it:"
    )

    for _, warning in ipairs(warnings) do
        local outputItemIDs = {}

        for _, itemID in ipairs(warning.outputItemIDs or {}) do
            table.insert(outputItemIDs, tostring(itemID))
        end

        table.insert(lines, "  Recipe: " .. (warning.recipeName or "Unknown"))
        table.insert(
            lines,
            "    Crafting profession: "
                .. tostring(warning.sourceProfession or "Unknown")
                .. " ("
                .. tostring(warning.sourceProfessionID or "Unknown")
                .. ")"
        )
        table.insert(lines, "    Recipe ID: " .. tostring(warning.recipeID))
        table.insert(lines, "    Item ID: " .. tostring(warning.itemID))
        table.insert(
            lines,
            "    Output item IDs: " .. table.concat(outputItemIDs, ", ")
        )
        table.insert(
            lines,
            "    Inventory type: " .. tostring(warning.inventoryType)
        )
        table.insert(lines, "    GetSkillLineForGear: nil")
        table.insert(
            lines,
            "    Client: "
                .. tostring(warning.clientVersion or "Unknown")
                .. " (build "
                .. tostring(warning.clientBuild or "Unknown")
                .. ", "
                .. tostring(warning.clientLocale or "Unknown")
                .. ")"
        )
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
    table.insert(lines, "Collected: " .. FormatTimestamp(snapshot.collectedAt))
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
    AddCraftableGearWarningLines(lines, snapshot.craftableGearWarnings)
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

    local fusedVitality, resourcesCollectedAt = SaveCharacterResources()

    local primaryProfessions = GetPrimaryProfessions()
    local missingProfessions = {}
    local lines = {
        "Character: " .. (UnitName("player") or "Unknown"),
        "Realm: " .. (GetRealmName() or "Unknown"),
        "Resources collected: " .. FormatTimestamp(resourcesCollectedAt),
        "Fused Vitality: " .. fusedVitality,
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
        elseif not primaryProfession.profession
            or professionMidnightStatus[primaryProfession.profession] ~= false
        then
            table.insert(missingProfessions, primaryProfession.name)
        end
    end

    if #missingProfessions > 0 then
        PrintMessage(
            "Missing specialization data for "
                .. table.concat(missingProfessions, " and ")
                .. ". Open each Midnight profession window once, then run "
                .. "/rshprof export again."
        )
        return
    end

    if exportedCount == 0 then
        PrintMessage("No Midnight primary professions were found.")
        return
    end

    ShowExport(table.concat(lines, "\n"))
end

local function ScheduleCurrentProfessionScan()
    C_Timer.After(0.25, function()
        if ScanCurrentProfession() then
            local professionInfo = GetMidnightChildProfessionInfo()

            if professionInfo then
                local snapshot = professionSnapshots[professionInfo.profession]

                PrintMessage(
                    "Scanned "
                        .. (professionInfo.expansionName
                            or professionInfo.professionName)
                        .. "."
                )

                if snapshot
                    and snapshot.craftableGearWarnings
                    and #snapshot.craftableGearWarnings > 0
                then
                    PrintMessage(
                        "Warning: Found "
                            .. #snapshot.craftableGearWarnings
                            .. " unclassified profession gear recipe(s). "
                            .. "Run /rshprof export and copy the WARNING block."
                    )
                end
            end
        else
            local baseProfessionInfo = C_TradeSkillUI.GetBaseProfessionInfo()

            if baseProfessionInfo
                and baseProfessionInfo.profession
                and professionMidnightStatus[baseProfessionInfo.profession]
                    == false
            then
                PrintMessage(
                    (baseProfessionInfo.professionName or "This profession")
                        .. " has no Midnight skill line and will be excluded."
                )
            end
        end
    end)
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("BANKFRAME_CLOSED")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("SKILL_LINE_SPECS_RANKS_CHANGED")
eventFrame:RegisterEvent("SKILL_LINE_SPECS_UNLOCKED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddonName = ...

        if loadedAddonName == addonName then
            LoadCharacterData()
            eventFrame:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "TRADE_SKILL_SHOW" then
        ScheduleCurrentProfessionScan()
    elseif event == "PLAYER_LOGIN" then
        -- Bag contents may not be fully available during initial addon loading.
        C_Timer.After(2, SaveCharacterResources)
    elseif event == "BAG_UPDATE_DELAYED"
        or event == "BANKFRAME_CLOSED"
    then
        SaveCharacterResources()
    elseif event == "SKILL_LINE_SPECS_RANKS_CHANGED"
        or event == "SKILL_LINE_SPECS_UNLOCKED"
        or event == "PLAYER_EQUIPMENT_CHANGED"
    then
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
