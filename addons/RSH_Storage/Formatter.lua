local _, addon = ...

local function Date(timestamp)
    if not timestamp or timestamp <= 0 then return "Unavailable" end
    return date("%Y-%m-%d %H:%M:%S", timestamp)
end

local function BindingLabel(sourceType)
    if sourceType == "warbound_until_equipped" then
        return "Warbound until equipped"
    elseif sourceType == "warbound" then
        return "Warbound"
    elseif sourceType == "boe" then
        return "Bind on equip"
    end
    return sourceType or "Unknown"
end

local EQUIP_LOCATION_LABELS = {
    ["INVTYPE_HEAD"] = "Head", ["INVTYPE_NECK"] = "Neck",
    ["INVTYPE_SHOULDER"] = "Shoulder", ["INVTYPE_CLOAK"] = "Back",
    ["INVTYPE_BACK"] = "Back", ["INVTYPE_CHEST"] = "Chest",
    ["INVTYPE_ROBE"] = "Chest", ["INVTYPE_WRIST"] = "Wrist",
    ["INVTYPE_HAND"] = "Hands", ["INVTYPE_WAIST"] = "Waist",
    ["INVTYPE_LEGS"] = "Legs", ["INVTYPE_FEET"] = "Feet",
    ["INVTYPE_FINGER"] = "Ring", ["INVTYPE_TRINKET"] = "Trinket",
    ["INVTYPE_WEAPON"] = "One-Hand Weapon",
    ["INVTYPE_WEAPONMAINHAND"] = "Main Hand",
    ["INVTYPE_WEAPONOFFHAND"] = "Off Hand",
    ["INVTYPE_2HWEAPON"] = "Two-Hand Weapon",
    ["INVTYPE_SHIELD"] = "Shield", ["INVTYPE_HOLDABLE"] = "Holdable",
    ["INVTYPE_RANGED"] = "Ranged", ["INVTYPE_RANGEDRIGHT"] = "Ranged",
}

local function EquipLocationLabel(equipLoc)
    return EQUIP_LOCATION_LABELS[equipLoc] or equipLoc or "Unknown slot"
end

local function FormatUpgrade(candidate)
    local difference = (candidate.itemLevel or 0)
        - (candidate.equippedIlvlAtFind or 0)
    return table.concat({
        candidate.itemLink or ("Item " .. addon:SafeText(candidate.itemID)),
        "Item level: " .. addon:SafeText(candidate.itemLevel),
        "Equip location: " .. addon:SafeText(candidate.equipLoc),
        "Source: " .. addon:SafeText(candidate.source),
        "Current: " .. addon:SafeText(candidate.equippedIlvlAtFind),
        "Difference: " .. (difference >= 0 and "+" or "") .. difference,
        "Binding: " .. BindingLabel(candidate.sourceType),
    }, " | ")
end

local function FormatReviewItem(item)
    local quantity = (item.quantity or 1) > 1
        and (" x" .. item.quantity) or ""
    local lines = {
        item.name .. quantity
            .. " | ilvl " .. addon:SafeText(item.itemLevel)
            .. " | " .. EquipLocationLabel(item.equipLoc)
            .. " | ItemID " .. addon:SafeText(item.itemID)
            .. " | Binding: " .. addon:SafeText(item.binding, "Unknown"),
    }
    local relevant = {}
    for _, character in ipairs(item.compatibleCharacters or {}) do
        table.insert(relevant, character.name or character.key)
    end
    table.sort(relevant)
    if #relevant > 0 then
        table.insert(lines, "Relevant: " .. table.concat(relevant, ", "))
    end
    if item.relevantCharacter and item.comparedItemLevel then
        table.insert(lines, item.relevantCharacter .. ": current "
            .. item.comparedItemLevel
            .. (item.difference and " -> +" .. item.difference or ""))
    end
    table.insert(lines, "Reason: " .. addon:SafeText(item.reason))
    return table.concat(lines, "\n")
end

function addon:FormatResults()
    if not self.WarbandNexus:IsAvailable() then
        return self.WarbandNexus:GetUnavailableMessage()
    end
    local lines = {}
    table.insert(lines, "CURRENT CHARACTER UPGRADES")
    if not self.upgrades then
        table.insert(lines, "Click Find Upgrades to run the Warband Nexus finder.")
    elseif self.upgrades.error then
        table.insert(lines, self.upgrades.error)
    elseif #(self.upgrades.items or {}) == 0 then
        table.insert(lines, "No storage upgrades found.")
    else
        for _, candidate in ipairs(self.upgrades.items) do
            table.insert(lines, FormatUpgrade(candidate))
        end
    end

    table.insert(lines, "")
    table.insert(lines, "WARBAND GEAR REVIEW")
    if not self.review then
        table.insert(lines, "Click Review Warband Gear to classify Warbound gear.")
    elseif self.review.error then
        table.insert(lines, self.review.error)
    else
        if self.review.enchanter then
            table.insert(lines, "Enchanting detected on the current character.")
        end
        local groups = {
            { "DE CANDIDATES", self.review.DE_CANDIDATE },
            { "REVIEW", self.review.REVIEW },
            { "KEEP", self.review.KEEP },
        }
        for _, group in ipairs(groups) do
            table.insert(lines, "")
            table.insert(lines, group[1] .. " (" .. #group[2] .. ")")
            if #group[2] == 0 then table.insert(lines, "None") end
            for _, item in ipairs(group[2]) do
                table.insert(lines, FormatReviewItem(item))
            end
        end
    end
    return table.concat(lines, "\n")
end

function addon:GenerateExport()
    local currentCharacter = self.WarbandNexus:IsAvailable()
        and self.WarbandNexus:GetCurrentCharacterDisplayName() or nil
    local lines = {
        "# RSH Storage Review",
        "Generated: " .. Date(time()),
        "Current character: " .. self:SafeText(currentCharacter),
        "Advisory only: DE Candidate never means safe to disenchant.",
        "",
        "[CONSIDERED CHARACTERS]",
    }
    local characters = self:GetConsideredCharacters()
    local realms = {}
    for _, character in ipairs(characters) do
        if character.realm and character.realm ~= "" then
            realms[character.realm] = true
        end
    end
    local realmCount = 0
    for _ in pairs(realms) do realmCount = realmCount + 1 end
    local showRealms = realmCount > 1
    if #characters == 0 then table.insert(lines, "None") end
    for _, character in ipairs(characters) do
        local identity = self:SafeText(character.name)
        if showRealms then
            identity = identity .. " - " .. self:SafeText(character.realm)
        end
        local fields = {
            identity,
            self:SafeText(character.class or character.classFile),
            self:SafeText(character.level),
        }
        if self.review and self.review.staleCharacters
            and self.review.staleCharacters[character.key] then
            table.insert(fields, "stale gear data")
        end
        table.insert(lines, table.concat(fields, " | "))
    end
    table.insert(lines, "")
    table.insert(lines, "[CURRENT CHARACTER UPGRADES]")
    if self.upgrades and self.upgrades.items and #self.upgrades.items > 0 then
        for _, candidate in ipairs(self.upgrades.items) do
            table.insert(lines, FormatUpgrade(candidate))
        end
    else
        table.insert(lines, self.upgrades and self.upgrades.error
            or "Not run or no upgrades found")
    end
    for _, classification in ipairs({ "KEEP", "REVIEW", "DE_CANDIDATE" }) do
        table.insert(lines, "")
        table.insert(lines, "[" .. classification:gsub("_", " ") .. "]")
        local items = self.review and self.review[classification] or {}
        if #items == 0 then table.insert(lines, "None or review not run") end
        for _, item in ipairs(items) do
            table.insert(lines, FormatReviewItem(item))
        end
    end
    if self.review then
        table.insert(lines, "")
        table.insert(lines, "Warband Bank snapshot: "
            .. Date(self.review.bankTimestamp))
    end
    return table.concat(lines, "\n")
end
