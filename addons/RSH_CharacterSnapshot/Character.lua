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
                    }
                    table.insert(talents, talent)

                    if spellID and passive == false then
                        activeTalentSpells[spellID] = talent.name
                    end
                end
            end
        end
    end

    table.sort(talents, SortByNameAndID)
    return nil, configID
end

local function AddAbility(abilitiesBySpellID, spellID, name, source)
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
        }
        abilitiesBySpellID[spellID] = ability
    end

    ability.sources[source] = true
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

    for lineIndex = 1, lineCount do
        local lineInfo = addon:SafeCall(
            C_SpellBook.GetSpellBookSkillLineInfo,
            lineIndex
        )

        if lineInfo and not lineInfo.shouldHide then
            local firstIndex = (lineInfo.itemIndexOffset or 0) + 1
            local lastIndex = firstIndex + (lineInfo.numSpellBookItems or 0) - 1

            for itemIndex = firstIndex, lastIndex do
                local itemInfo = addon:SafeCall(
                    C_SpellBook.GetSpellBookItemInfo,
                    itemIndex,
                    bank
                )

                if itemInfo and not itemInfo.isOffSpec then
                    local spellID = itemInfo.spellID or itemInfo.actionID
                    AddAbility(
                        abilitiesBySpellID,
                        spellID,
                        itemInfo.name,
                        "Spellbook: " .. (lineInfo.name or "Unknown")
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

    for spellID, name in pairs(activeTalentSpells) do
        AddAbility(abilitiesBySpellID, spellID, name, "Selected talent")
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
