local _, addon = ...

local FRESHNESS_SECONDS = 14 * 24 * 60 * 60
local AMBIGUOUS_EQUIP_LOCS = {
    ["INVTYPE_TRINKET"] = true,
    ["INVTYPE_WEAPON"] = true,
    ["INVTYPE_WEAPONMAINHAND"] = true,
    ["INVTYPE_WEAPONOFFHAND"] = true,
    ["INVTYPE_2HWEAPON"] = true,
    ["INVTYPE_RANGED"] = true,
    ["INVTYPE_RANGEDRIGHT"] = true,
    ["INVTYPE_SHIELD"] = true,
    ["INVTYPE_HOLDABLE"] = true,
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
    local staleCharacters = {}
    for _, character in ipairs(considered) do
        local gear, gearError = adapter:GetEquippedGear(character.key)
        if not gear or not IsFresh(gear.lastScan) then
            uncertainty[character.key] = gearError
                or "equipped gear snapshot is missing or older than 14 days"
            staleCharacters[character.key] = true
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
        staleCharacters = staleCharacters,
        KEEP = {},
        REVIEW = {},
        DE_CANDIDATE = {},
    }
    local bankFresh = IsFresh(bankTimestamp)
    local reviewItemIndex = 0
    for _, rawItem in ipairs(items) do
        local item = adapter:GetItemDetails(rawItem)
        if adapter:IsEquippableGear(item) then
            reviewItemIndex = reviewItemIndex + 1
            item.bindingCategory, item.binding =
                adapter:GetBindingCategory(rawItem)
            item.hasSpecialEffect = adapter:HasSpecialEffect(rawItem)
            item.matches = matchesByIdentity[item.identity]
                or (not item.itemLink and matchesByItemID[item.itemID])
                or {}
            item.quantity = tonumber(rawItem.stackCount)
                or tonumber(rawItem.quantity) or 1
            if not item.minimumLevel and item.matches[1] then
                item.minimumLevel = tonumber(
                    item.matches[1].candidate.requiredLevel
                )
            end

            item.compatibleCharacters = {}
            local compatibleByKey = {}
            for _, character in ipairs(considered) do
                if adapter:IsItemCompatible(character, item) then
                    table.insert(item.compatibleCharacters, character)
                    compatibleByKey[character.key] = true
                end
            end
            local relevantMatches = {}
            local freshMatches = {}
            for _, match in ipairs(item.matches) do
                if compatibleByKey[match.character.key] then
                    table.insert(relevantMatches, match)
                    if not uncertainty[match.character.key] then
                        table.insert(freshMatches, match)
                    end
                end
            end
            item.matches = relevantMatches
            local uncertainNames = {}
            for _, character in ipairs(item.compatibleCharacters) do
                if uncertainty[character.key] then
                    table.insert(
                        uncertainNames,
                        character.name or character.key
                    )
                end
            end
            table.sort(uncertainNames)

            if #considered == 0 then
                item.classification = "REVIEW"
                item.reason = "No characters are selected for consideration"
            elseif not item.itemLevel or item.itemLevel <= 0
                or not item.itemID then
                item.classification = "REVIEW"
                item.reason = "Item metadata is incomplete"
            elseif not bankFresh then
                item.classification = "REVIEW"
                item.reason = "Warband Bank snapshot is missing or older than 14 days"
            elseif #item.compatibleCharacters == 0 then
                item.classification = "DE_CANDIDATE"
                item.reason = "No considered character can use this item type"
            elseif item.isCosmetic then
                item.classification = "REVIEW"
                item.reason = "Cosmetic gear needs manual review"
            elseif item.hasSpecialEffect
                or AMBIGUOUS_EQUIP_LOCS[item.equipLoc] then
                item.classification = "REVIEW"
                if #freshMatches > 0 then
                    local match = freshMatches[1]
                    local candidate = match.candidate
                    local difference = (candidate.itemLevel or item.itemLevel)
                        - (candidate.equippedIlvlAtFind or 0)
                    item.comparedItemLevel = candidate.equippedIlvlAtFind
                    item.difference = difference
                    item.relevantCharacter = match.character.name
                        or match.character.key
                    item.reason = "Potential +" .. difference
                        .. " ilvl upgrade for " .. item.relevantCharacter
                        .. (item.hasSpecialEffect
                            and "; special-effect value needs manual review"
                            or "; weapon/trinket value needs manual review")
                else
                    item.reason = item.hasSpecialEffect
                        and "Special-effect value needs manual review"
                        or "Weapon/trinket value cannot be decided safely from item level alone"
                end
            elseif #freshMatches > 0 then
                local match = freshMatches[1]
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
            elseif #uncertainNames > 0 then
                item.classification = "REVIEW"
                item.reason = "Missing or stale comparison data for "
                    .. table.concat(uncertainNames, ", ")
            else
                item.classification = "DE_CANDIDATE"
                item.reason = "All compatible considered characters have equal or better gear"
            end
            item.reviewIndex = reviewItemIndex
            table.insert(review[item.classification], item)
        end
    end

    local function Deduplicate(list)
        local deduplicated = {}
        local byKey = {}
        for _, item in ipairs(list) do
            local key
            if item.itemLink and item.itemLink ~= "" then
                key = table.concat({
                    item.itemLink,
                    tostring(item.itemLevel or ""),
                    tostring(item.equipLoc or ""),
                    tostring(item.bindingCategory or "unknown"),
                    item.classification,
                    item.reason or "",
                }, "\031")
            end
            local existing = key and byKey[key]
            if existing then
                existing.quantity = (existing.quantity or 1)
                    + (item.quantity or 1)
            else
                table.insert(deduplicated, item)
                if key then byKey[key] = item end
            end
        end
        return deduplicated
    end
    review.KEEP = Deduplicate(review.KEEP)
    review.REVIEW = Deduplicate(review.REVIEW)
    review.DE_CANDIDATE = Deduplicate(review.DE_CANDIDATE)

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
