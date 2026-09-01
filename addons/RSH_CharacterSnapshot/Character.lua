local _, addon = ...

local function SortByNameAndID(left, right)
    local leftName = string.lower(left.name or "")
    local rightName = string.lower(right.name or "")

    if leftName == rightName then
        return (left.spellID or 0) < (right.spellID or 0)
    end

    return leftName < rightName
end

local function GetSpellName(spellID)
    if not spellID or not C_Spell then
        return nil
    end

    if C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end

    local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    return info and info.name
end

local function IsPassiveSpell(spellID)
    if not spellID or not C_Spell or not C_Spell.IsSpellPassive then
        return nil
    end

    return addon:SafeCall(C_Spell.IsSpellPassive, spellID)
end

function addon:CollectCharacter()
    local name, realm = UnitFullName("player")
    local localizedClass, classFile, classID = UnitClass("player")
    local specializationIndex = GetSpecialization()
    local specID, specName

    if specializationIndex then
        specID, specName = GetSpecializationInfo(specializationIndex)
    end

    return {
        name = name or UnitName("player"),
        realm = realm or GetRealmName(),
        level = UnitLevel("player"),
        className = localizedClass,
        classFile = classFile,
        classID = classID,
        specializationIndex = specializationIndex,
        specName = specName,
        specID = specID,
    }
end

local function CollectTalents(talents, activeTalentSpells)
    if not C_ClassTalents or not C_Traits then
        return "Talent APIs unavailable"
    end

    local configID = addon:SafeCall(C_ClassTalents.GetActiveConfigID)

    if not configID then
        return "No active talent configuration"
    end

    local configInfo = addon:SafeCall(C_Traits.GetConfigInfo, configID)
    local treeIDs = configInfo and configInfo.treeIDs or {}
    local seenNodes = {}

    for _, treeID in ipairs(treeIDs) do
        local nodeIDs = addon:SafeCall(C_Traits.GetTreeNodes, treeID) or {}

        for _, nodeID in ipairs(nodeIDs) do
            if not seenNodes[nodeID] then
                seenNodes[nodeID] = true
                local nodeInfo = addon:SafeCall(
                    C_Traits.GetNodeInfo,
                    configID,
                    nodeID
                )
                local activeEntry = nodeInfo and nodeInfo.activeEntry
                local entryID = activeEntry and activeEntry.entryID
                    or nodeInfo and nodeInfo.activeEntryID
                local rank = activeEntry and activeEntry.rank
                    or nodeInfo and nodeInfo.currentRank

                if entryID and rank and rank > 0 then
                    local entryInfo = addon:SafeCall(
                        C_Traits.GetEntryInfo,
                        configID,
                        entryID
                    )
                    local definitionID = entryInfo and entryInfo.definitionID
                    local definitionInfo = definitionID and addon:SafeCall(
                        C_Traits.GetDefinitionInfo,
                        definitionID
                    )
                    local spellID = definitionInfo and definitionInfo.spellID
                    local passive = IsPassiveSpell(spellID)
                    local overrideName = definitionInfo
                        and definitionInfo.overrideName
                    local talent = {
                        name = overrideName and overrideName ~= ""
                            and overrideName
                            or GetSpellName(spellID)
                            or "Unknown talent",
                        spellID = spellID,
                        nodeID = nodeID,
                        entryID = entryID,
                        definitionID = definitionID,
                        rank = rank,
                        maxRanks = entryInfo and entryInfo.maxRanks,
                        passive = passive,
                        replacesSpellID = definitionInfo
                            and definitionInfo.overriddenSpellID,
                    }
                    table.insert(talents, talent)

                    if spellID and passive == false then
                        activeTalentSpells[spellID] = talent
                    end
                end
            end
        end
    end

    table.sort(talents, SortByNameAndID)
    return nil, configID
end

local function AddAbility(
    abilitiesBySpellID,
    spellID,
    name,
    source,
    replacesSpellID
)
    if not spellID then
        return
    end

    local passive = IsPassiveSpell(spellID)

    if passive ~= false then
        return
    end

    local ability = abilitiesBySpellID[spellID]

    if not ability then
        ability = {
            spellID = spellID,
            name = name or GetSpellName(spellID) or "Unknown spell",
            sources = {},
            replacesSpellID = replacesSpellID,
        }
        abilitiesBySpellID[spellID] = ability
    end

    ability.sources[source] = true

    if replacesSpellID then
        ability.replacesSpellID = replacesSpellID
    end
end

local function CollectSpellBook(abilitiesBySpellID)
    if not C_SpellBook
        or not C_SpellBook.GetNumSpellBookSkillLines
        or not C_SpellBook.GetSpellBookSkillLineInfo
        or not C_SpellBook.GetSpellBookItemInfo
    then
        return "Spellbook APIs unavailable"
    end

    local bank = Enum and Enum.SpellBookSpellBank
        and Enum.SpellBookSpellBank.Player

    if bank == nil then
        return "Player spellbook bank unavailable"
    end

    local lineCount = addon:SafeCall(
        C_SpellBook.GetNumSpellBookSkillLines
    ) or 0
    local currentSpec = GetSpecialization()
    local currentSpecID = currentSpec
        and select(1, GetSpecializationInfo(currentSpec))
    local localizedClassName = UnitClass("player")
    local spellItemType = Enum and Enum.SpellBookItemType
        and Enum.SpellBookItemType.Spell

    for lineIndex = 1, lineCount do
        local lineInfo = addon:SafeCall(
            C_SpellBook.GetSpellBookSkillLineInfo,
            lineIndex
        )

        local isGeneralLine = lineIndex == 1
        local isCurrentSpecLine = lineInfo
            and lineInfo.specID == currentSpecID
        local isCurrentClassLine = lineInfo
            and lineInfo.name == localizedClassName
            and lineInfo.specID == nil
            and lineInfo.offSpecID == nil

        if lineInfo
            and not lineInfo.shouldHide
            and not isGeneralLine
            and (isCurrentClassLine or isCurrentSpecLine)
        then
            local firstIndex = (lineInfo.itemIndexOffset or 0) + 1
            local lastIndex = firstIndex + (lineInfo.numSpellBookItems or 0) - 1

            for itemIndex = firstIndex, lastIndex do
                local itemInfo = addon:SafeCall(
                    C_SpellBook.GetSpellBookItemInfo,
                    itemIndex,
                    bank
                )

                if itemInfo
                    and not itemInfo.isOffSpec
                    and (spellItemType == nil
                        or itemInfo.itemType == spellItemType)
                then
                    local spellID = itemInfo.spellID or itemInfo.actionID
                    AddAbility(
                        abilitiesBySpellID,
                        spellID,
                        itemInfo.name,
                        isCurrentSpecLine
                            and "Current specialization spellbook"
                            or "Current class spellbook"
                    )
                end
            end
        end
    end

    return nil
end

function addon:CollectTalentsAndAbilities()
    local talents = {}
    local activeTalentSpells = {}
    local abilitiesBySpellID = {}
    local talentError, configID = CollectTalents(talents, activeTalentSpells)
    local spellBookError = CollectSpellBook(abilitiesBySpellID)

    for spellID, talent in pairs(activeTalentSpells) do
        AddAbility(
            abilitiesBySpellID,
            spellID,
            talent.name,
            "Selected talent",
            talent.replacesSpellID
        )
    end

    local abilities = {}

    for _, ability in pairs(abilitiesBySpellID) do
        local sources = {}

        for source in pairs(ability.sources) do
            table.insert(sources, source)
        end

        table.sort(sources)
        ability.sources = sources
        table.insert(abilities, ability)
    end

    table.sort(abilities, SortByNameAndID)
    talents.error = talentError
    talents.configID = configID
    abilities.error = spellBookError
    return talents, abilities
end

local function AddCandidate(candidates, seenSpellIDs, spellID, relationship)
    if type(spellID) == "number"
        and spellID > 0
        and not seenSpellIDs[spellID]
    then
        seenSpellIDs[spellID] = true
        table.insert(candidates, {
            spellID = spellID,
            relationship = relationship,
        })
    end
end

local FIXED_PAGE_SYSTEMS = {
    [3] = 4,
    [4] = 5,
    [5] = 3,
    [6] = 2,
    [13] = 6,
    [14] = 7,
    [15] = 8,
}

local function CollectCurrentActionSpellIDs(actionPages, editMode)
    local enabledSystems = {}
    local currentSpellIDs = {}

    for _, bar in ipairs(editMode.bars or {}) do
        if bar.configuredEnabled then
            enabledSystems[bar.systemIndex] = true
        end
    end

    for _, page in ipairs(actionPages) do
        local fixedSystem = FIXED_PAGE_SYSTEMS[page.page]
        local isCurrent = page.active
            or fixedSystem and enabledSystems[fixedSystem]

        if isCurrent then
            for _, entry in ipairs(page.actions) do
                local action = entry.action

                if action and action.type == "spell" and action.spellID then
                    currentSpellIDs[action.spellID] = true
                end
            end
        end
    end

    return currentSpellIDs
end

function addon:ApplyAbilityCoverage(
    abilities,
    actionSpellIDs,
    actionPages,
    actionState,
    editMode
)
    local currentActionSpellIDs = CollectCurrentActionSpellIDs(
        actionPages,
        editMode
    )

    for _, ability in ipairs(abilities) do
        local candidates = {}
        local seenSpellIDs = {}
        AddCandidate(candidates, seenSpellIDs, ability.spellID, "Direct")
        AddCandidate(
            candidates,
            seenSpellIDs,
            ability.replacesSpellID,
            "Replaced spell"
        )

        if C_Spell and C_Spell.GetOverrideSpell then
            local overrideSpellID = self:SafeCall(
                C_Spell.GetOverrideSpell,
                ability.spellID
            )

            if overrideSpellID and overrideSpellID ~= ability.spellID then
                ability.overrideSpellID = overrideSpellID
                AddCandidate(
                    candidates,
                    seenSpellIDs,
                    overrideSpellID,
                    "Current override"
                )
            end
        end

        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
            local overrideSpellID = self:SafeCall(
                C_SpellBook.FindSpellOverrideByID,
                ability.spellID
            )

            if overrideSpellID and overrideSpellID ~= ability.spellID then
                ability.overrideSpellID = ability.overrideSpellID
                    or overrideSpellID
                AddCandidate(
                    candidates,
                    seenSpellIDs,
                    overrideSpellID,
                    "Spellbook override"
                )
            end
        end

        if C_SpellBook and C_SpellBook.FindBaseSpellByID then
            local baseSpellID = self:SafeCall(
                C_SpellBook.FindBaseSpellByID,
                ability.spellID
            )

            if baseSpellID and baseSpellID ~= ability.spellID then
                ability.baseSpellID = baseSpellID
                AddCandidate(
                    candidates,
                    seenSpellIDs,
                    baseSpellID,
                    "Base spell"
                )
            end
        end

        ability.hasReportedReplacementRelationship =
            ability.replacesSpellID ~= nil
            or ability.overrideSpellID ~= nil
            or ability.baseSpellID ~= nil

        ability.covered = false
        ability.currentStateCovered = false

        for _, candidate in ipairs(candidates) do
            if not ability.covered and actionSpellIDs[candidate.spellID] then
                ability.covered = true
                ability.coveredBySpellID = candidate.spellID
                ability.coveredByRelationship = candidate.relationship
            end

            if not ability.currentStateCovered
                and currentActionSpellIDs[candidate.spellID]
            then
                ability.currentStateCovered = true
                ability.currentStateCoveredBySpellID = candidate.spellID
                ability.currentStateCoveredByRelationship =
                    candidate.relationship
            end

            for _, form in ipairs(actionState.shapeshiftForms or {}) do
                if form.spellID == candidate.spellID then
                    ability.otherControlCoverage = form.name
                        and ("Shapeshift bar: " .. form.name)
                        or ("Shapeshift bar form index " .. form.index)
                    ability.otherControlActive = form.active == true
                end
            end
        end

        if C_Spell and C_Spell.IsSpellUsable then
            ability.usableInCurrentState = self:SafeCall(
                C_Spell.IsSpellUsable,
                ability.spellID
            )
        end

        if ability.covered and not ability.currentStateCovered then
            ability.stateCoverageNote =
                "Only found on an inactive/alternate underlying page"
        elseif not ability.covered and ability.otherControlCoverage then
            ability.stateCoverageNote =
                "Available through another Blizzard action control"
        elseif not ability.covered
            and actionState.shapeshiftForm
            and actionState.shapeshiftForm > 0
            and ability.usableInCurrentState == false
        then
            ability.stateCoverageNote =
                "Not usable in the current form; may be form/state-dependent"
        elseif not ability.covered and ability.usableInCurrentState == true then
            ability.stateCoverageNote =
                "Usable in the current state, but no direct action slot was found"
        elseif not ability.covered then
            ability.stateCoverageNote =
                "Form/state dependency could not be established"
        end
    end
end
