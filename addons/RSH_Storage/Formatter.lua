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
    local fields = {
        item.name,
        "Item ID: " .. addon:SafeText(item.itemID),
        "Item level: " .. addon:SafeText(item.itemLevel),
        "Equip location: " .. addon:SafeText(item.equipLoc),
        "Binding: " .. addon:SafeText(item.binding),
        "Source: " .. addon:SafeText(item.source),
    }
    if item.relevantCharacter then
        table.insert(fields, "Character: " .. item.relevantCharacter)
    end
    if item.matches and #item.matches > 1 then
        local names = {}
        for _, match in ipairs(item.matches) do
            table.insert(
                names,
                match.character.name or match.character.key
            )
        end
        table.sort(names)
        table.insert(fields, "Relevant characters: " .. table.concat(names, ", "))
    end
    if item.comparedItemLevel then
        table.insert(fields, "Current: " .. item.comparedItemLevel)
    end
    table.insert(fields, "Reason: " .. addon:SafeText(item.reason))
    return table.concat(fields, " | ")
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
    local currentKey = self.WarbandNexus:IsAvailable()
        and self.WarbandNexus:GetCurrentCharacterKey() or nil
    local lines = {
        "# RSH Storage Review",
        "Generated: " .. Date(time()),
        "Current character: " .. self:SafeText(currentKey),
        "Advisory only: DE Candidate never means safe to disenchant.",
        "",
        "[CONSIDERED CHARACTERS]",
    }
    local characters = self:GetConsideredCharacters()
    if #characters == 0 then table.insert(lines, "None") end
    for _, character in ipairs(characters) do
        table.insert(lines, table.concat({
            self:SafeText(character.name),
            "Realm: " .. self:SafeText(character.realm),
            "Class: " .. self:SafeText(character.class or character.classFile),
            "Level: " .. self:SafeText(character.level),
            "Last seen: " .. Date(character.lastSeen),
        }, " | "))
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
