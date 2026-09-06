local _, addon = ...

local FRESHNESS_SECONDS = 14 * 24 * 60 * 60
local AMBIGUOUS_EQUIP_LOCS = {
    INVTYPE_TRINKET = true,
    INVTYPE_WEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_2HWEAPON = true,
    INVTYPE_RANGED = true,
    INVTYPE_RANGEDRIGHT = true,
    INVTYPE_SHIELD = true,
    INVTYPE_HOLDABLE = true,
}

local function IsFresh(timestamp)
    timestamp = tonumber(timestamp)
    if not timestamp or timestamp <= 0 then return false end
    return time() - timestamp <= FRESHNESS_SECONDS
end

local function FlattenFindings(findings)
    local result = {}
    for slotID, candidates in pairs(findings or {}) do
        for _, candidate in ipairs(candidates) do
            local copy = {}
            for key, value in pairs(candidate) do copy[key] = value end
            copy.slotID = slotID
            table.insert(result, copy)
        end
    end
    table.sort(result, function(left, right)
        if (left.slotID or 0) ~= (right.slotID or 0) then
            return (left.slotID or 0) < (right.slotID or 0)
        end
        if (left.itemLevel or 0) ~= (right.itemLevel or 0) then
            return (left.itemLevel or 0) > (right.itemLevel or 0)
        end
        return (left.itemID or 0) < (right.itemID or 0)
    end)
    return result
end

function addon:FindCurrentCharacterUpgrades()
    if not self.WarbandNexus:IsAvailable() then
        self.upgrades = { error = self.WarbandNexus:GetUnavailableMessage() }
        self:RefreshUI()
        return self.upgrades
    end
    local currentKey, keyError = self.WarbandNexus:GetCurrentCharacterKey()
    if not currentKey then
        self.upgrades = { error = keyError or "Current character is unavailable" }
    else
        local findings, findError = self.WarbandNexus:FindUpgrades(currentKey)
        local items = {}
        for _, candidate in ipairs(FlattenFindings(findings)) do
            if type(candidate.source) ~= "string"
                or candidate.source:sub(1, 10) ~= "Guild Bank" then
                table.insert(items, candidate)
            end
        end
        self.upgrades = {
            characterKey = currentKey,
            items = items,
            error = findings and nil or findError,
        }
    end
    self:RefreshUI()
    return self.upgrades
end

local function AddMatch(matchesByIdentity, identity, character, candidate)
    matchesByIdentity[identity] = matchesByIdentity[identity] or {}
    table.insert(matchesByIdentity[identity], {
        character = character,
        candidate = candidate,
    })
end

function addon:ReviewWarbandGear()
    local adapter = self.WarbandNexus
    if not adapter:IsAvailable() then
        self.review = { error = adapter:GetUnavailableMessage() }
        self:RefreshUI()
        return self.review
    end

    local considered = self:GetConsideredCharacters()
    local items, bankTimestamp, bankError = adapter:GetWarbandGear()
    if not items then
        self.review = { error = bankError or "Warband Bank data is unavailable" }
        self:RefreshUI()
        return self.review
    end

    local matchesByIdentity = {}
    local matchesByItemID = {}
    local uncertainty = {}
    for _, character in ipairs(considered) do
        local gear, gearError = adapter:GetEquippedGear(character.key)
        if not gear or not IsFresh(gear.lastScan) then
            uncertainty[character.key] = gearError
                or "equipped gear snapshot is missing or older than 14 days"
        end
        local findings, findError = adapter:FindUpgrades(character.key)
        if not findings then
            uncertainty[character.key] = findError or "upgrade finder failed"
        else
            for _, candidate in ipairs(FlattenFindings(findings)) do
                if candidate.source == "Warband Bank" then
                    local identity = adapter:GetItemIdentity(candidate)
                    AddMatch(matchesByIdentity, identity, character, candidate)
                    if candidate.itemID then
                        matchesByItemID[candidate.itemID] =
                            matchesByItemID[candidate.itemID] or {}
                        table.insert(
                            matchesByItemID[candidate.itemID],
                            { character = character, candidate = candidate }
                        )
                    end
                end
            end
        end
    end

    local review = {
        generatedAt = time(),
        bankTimestamp = bankTimestamp,
        consideredCharacters = considered,
        enchanter = adapter:IsCurrentCharacterEnchanter(
            adapter:GetCharacters(),
            adapter:GetCurrentCharacterKey()
        ),
        KEEP = {},
        REVIEW = {},
        DE_CANDIDATE = {},
    }
    local bankFresh = IsFresh(bankTimestamp)
    local hasUncertainty = next(uncertainty) ~= nil

    for _, rawItem in ipairs(items) do
        local item = adapter:GetItemDetails(rawItem)
        if item.equipLoc and item.equipLoc ~= ""
            and item.equipLoc ~= "INVTYPE_NON_EQUIP" then
            item.bindingCategory, item.binding =
                adapter:GetBindingCategory(rawItem)
            item.hasSpecialEffect = adapter:HasSpecialEffect(rawItem)
            item.matches = matchesByIdentity[item.identity]
                or matchesByItemID[item.itemID]
                or {}
            if not item.minimumLevel and item.matches[1] then
                item.minimumLevel = tonumber(
                    item.matches[1].candidate.requiredLevel
                )
            end

            if #considered == 0 then
                item.classification = "REVIEW"
                item.reason = "No characters are selected for consideration"
            elseif not item.bindingCategory then
                item.classification = "REVIEW"
                item.reason = "Warbound binding could not be confirmed"
            elseif not item.itemLevel or item.itemLevel <= 0
                or not item.itemID then
                item.classification = "REVIEW"
                item.reason = "Item metadata is incomplete"
            elseif item.isCosmetic then
                item.classification = "REVIEW"
                item.reason = "Cosmetic gear is outside item-level upgrade evaluation"
            elseif item.hasSpecialEffect then
                item.classification = "REVIEW"
                item.reason = "Special-effect item needs manual review"
            elseif not bankFresh then
                item.classification = "REVIEW"
                item.reason = "Warband Bank snapshot is missing or older than 14 days"
            elseif hasUncertainty then
                item.classification = "REVIEW"
                local names = {}
                for _, character in ipairs(considered) do
                    if uncertainty[character.key] then
                        table.insert(names, character.name or character.key)
                    end
                end
                item.reason = "Missing or stale comparison data for "
                    .. table.concat(names, ", ")
            elseif AMBIGUOUS_EQUIP_LOCS[item.equipLoc] then
                item.classification = "REVIEW"
                if #item.matches > 0 then
                    local match = item.matches[1]
                    local candidate = match.candidate
                    local difference = (candidate.itemLevel or item.itemLevel)
                        - (candidate.equippedIlvlAtFind or 0)
                    item.comparedItemLevel = candidate.equippedIlvlAtFind
                    item.difference = difference
                    item.relevantCharacter = match.character.name
                        or match.character.key
                    item.reason = "Potential +" .. difference
                        .. " ilvl upgrade for " .. item.relevantCharacter
                        .. "; weapon/trinket value needs manual review"
                else
                    item.reason = "Weapon/trinket value cannot be decided safely from item level alone"
                end
            elseif #item.matches > 0 then
                local match = item.matches[1]
                local character = match.character
                local candidate = match.candidate
                local difference = (candidate.itemLevel or item.itemLevel)
                    - (candidate.equippedIlvlAtFind or 0)
                item.comparedItemLevel = candidate.equippedIlvlAtFind
                item.difference = difference
                item.relevantCharacter = character.name or character.key
                if item.minimumLevel and character.level
                    and character.level < item.minimumLevel then
                    item.classification = "KEEP"
                    item.reason = "Potential upgrade for " .. item.relevantCharacter
                        .. " when level " .. item.minimumLevel .. " is reached"
                else
                    item.classification = "KEEP"
                    item.reason = "+" .. difference .. " ilvl upgrade for "
                        .. item.relevantCharacter
                end
            else
                item.classification = "DE_CANDIDATE"
                item.reason = "Warband Nexus found no upgrade use for any considered character"
            end
            table.insert(review[item.classification], item)
        end
    end

    local function SortItems(left, right)
        if (left.itemLevel or 0) ~= (right.itemLevel or 0) then
            return (left.itemLevel or 0) > (right.itemLevel or 0)
        end
        if left.name ~= right.name then return left.name < right.name end
        return (left.itemID or 0) < (right.itemID or 0)
    end
    table.sort(review.KEEP, SortItems)
    table.sort(review.REVIEW, SortItems)
    table.sort(review.DE_CANDIDATE, SortItems)
    self.review = review
    self:RefreshUI()
    return review
end

addon.FRESHNESS_SECONDS = FRESHNESS_SECONDS
