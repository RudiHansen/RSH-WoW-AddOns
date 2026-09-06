local _, addon = ...

local adapter = {}
addon.WarbandNexus = adapter

local function GetNexus()
    local nexus = _G.WarbandNexus
    if type(nexus) ~= "table" then return nil end
    return nexus
end

local function CallMethod(name, ...)
    local nexus = GetNexus()
    local method = nexus and nexus[name]
    if type(method) ~= "function" then
        return nil, "Warband Nexus method " .. name .. " is unavailable"
    end
    local results = { pcall(method, nexus, ...) }
    if not results[1] then return nil, tostring(results[2]) end
    table.remove(results, 1)
    return unpack(results)
end

local function IsSafeString(value)
    return type(value) == "string"
        and not (type(issecretvalue) == "function" and issecretvalue(value))
end

function adapter:IsAvailable()
    local nexus = GetNexus()
    return nexus ~= nil
        and type(nexus.GetAllCharacters) == "function"
        and type(nexus.GetWarbandBankData) == "function"
        and type(nexus.FindGearStorageUpgrades) == "function"
end

function adapter:GetUnavailableMessage()
    return "RSH Storage requires Warband Nexus. Enable Warband Nexus and reload the UI."
end

function adapter:GetCharacters()
    local characters, errorMessage = CallMethod("GetAllCharacters")
    if type(characters) ~= "table" then return {}, errorMessage end
    local result = {}
    for _, character in ipairs(characters) do
        if type(character) == "table" and character.isTracked == true then
            local key = character._key or character.guid
            if not key and character.name then
                key = character.name .. "-" .. (character.realm or "UnknownRealm")
            end
            if key then
                table.insert(result, {
                    key = key,
                    name = character.name,
                    realm = character.realm,
                    class = character.class,
                    classFile = character.classFile,
                    level = tonumber(character.level),
                    lastSeen = tonumber(character.lastSeen),
                    professions = character.professions,
                    raw = character,
                })
            end
        end
    end
    table.sort(result, function(left, right)
        local leftName = (left.name or left.key):lower()
        local rightName = (right.name or right.key):lower()
        if leftName ~= rightName then return leftName < rightName end
        return (left.realm or "") < (right.realm or "")
    end)
    return result
end

function adapter:GetCurrentCharacterKey()
    return CallMethod("GetCurrentGearStorageKey")
end

function adapter:GetEquippedGear(characterKey)
    return CallMethod("GetEquippedGear", characterKey)
end

function adapter:FindUpgrades(characterKey)
    local nexus = GetNexus()
    if nexus and type(nexus.IsGearStorageRecommendationsEnabled) == "function" then
        local ok, enabled = pcall(
            nexus.IsGearStorageRecommendationsEnabled,
            nexus
        )
        if ok and enabled == false then
            return nil, "Warband Nexus storage recommendations are disabled"
        end
    end
    local findings, errorMessage = CallMethod(
        "FindGearStorageUpgrades",
        characterKey
    )
    if type(findings) ~= "table" then return nil, errorMessage end
    return findings
end

function adapter:GetWarbandGear()
    local data, errorMessage = CallMethod("GetWarbandBankData")
    if type(data) ~= "table" then return nil, nil, errorMessage end
    return data.items or {}, tonumber(data.lastUpdate) or 0
end

function adapter:GetItemIdentity(item)
    local link = item and (item.itemLink or item.link)
    if IsSafeString(link) and link ~= "" then return "link:" .. link end
    return "item:" .. addon:SafeText(item and item.itemID, "unknown")
end

function adapter:GetItemDetails(item)
    local link = item and (item.itemLink or item.link)
    local itemID = item and tonumber(item.itemID)
    local name = item and item.name
    local itemLevel = item and (tonumber(item.itemLevel) or tonumber(item.ilvl))
    local quality = item and tonumber(item.quality)
    local equipLoc = item and item.equipLoc
    local minimumLevel

    if C_Item and C_Item.GetItemInfo then
        local ok, infoName, _, infoQuality, infoLevel, minLevel, _, _, _,
            infoEquipLoc = pcall(C_Item.GetItemInfo, link or itemID)
        if ok then
            name = name or infoName
            quality = quality or infoQuality
            itemLevel = itemLevel or infoLevel
            minimumLevel = tonumber(minLevel)
            equipLoc = equipLoc or infoEquipLoc
        end
    end
    if (not equipLoc or equipLoc == "") and C_Item
        and C_Item.GetItemInfoInstant then
        local ok, _, _, _, instantEquipLoc = pcall(
            C_Item.GetItemInfoInstant,
            link or itemID
        )
        if ok then equipLoc = instantEquipLoc end
    end

    return {
        itemID = itemID,
        itemLink = link,
        name = name or ("Item " .. addon:SafeText(itemID)),
        itemLevel = tonumber(itemLevel),
        minimumLevel = minimumLevel,
        quality = quality,
        equipLoc = equipLoc,
        source = "Warband Bank",
        identity = self:GetItemIdentity(item),
        isCosmetic = (function()
            if not C_Item or not C_Item.IsCosmeticItem then return false end
            local ok, cosmetic = pcall(
                C_Item.IsCosmeticItem,
                link or itemID
            )
            return ok and cosmetic == true
        end)(),
    }
end

function adapter:GetBindingCategory(item)
    local link = item and (item.itemLink or item.link)
    local itemID = item and item.itemID
    local tooltip
    if C_TooltipInfo and IsSafeString(link) and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
        if ok then tooltip = data end
    end
    if not tooltip and C_TooltipInfo and itemID
        and C_TooltipInfo.GetItemByID then
        local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
        if ok then tooltip = data end
    end

    local untilEquipped = _G.ITEM_ACCOUNTBOUND_UNTIL_EQUIP
        or "Warbound until equipped"
    local warboundLabels = {
        _G.ITEM_BIND_TO_WARBAND or "Binds to Warband",
        _G.ITEM_BIND_TO_BNETACCOUNT or "Binds to Battle.net Account",
        _G.ITEM_BIND_TO_ACCOUNT or "Binds to Account",
        "Warbound",
    }
    for _, line in ipairs(tooltip and tooltip.lines or {}) do
        local text = line and line.leftText
        if IsSafeString(text) then
            if text:find(untilEquipped, 1, true)
                or text:find("until equipped", 1, true) then
                return "warbound_until_equipped", "Warbound until equipped"
            end
            for _, label in ipairs(warboundLabels) do
                if text:find(label, 1, true) then
                    return "warbound", "Warbound"
                end
            end
        end
    end
    return nil, "Unknown"
end

function adapter:HasSpecialEffect(item)
    local link = item and (item.itemLink or item.link)
    local itemID = item and item.itemID
    local tooltip
    if C_TooltipInfo and IsSafeString(link) and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
        if ok then tooltip = data end
    end
    if not tooltip and C_TooltipInfo and itemID
        and C_TooltipInfo.GetItemByID then
        local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
        if ok then tooltip = data end
    end
    local triggers = {
        _G.ITEM_SPELL_TRIGGER_ONEQUIP,
        _G.ITEM_SPELL_TRIGGER_ONUSE,
        _G.ITEM_SPELL_TRIGGER_ONPROC,
    }
    for _, line in ipairs(tooltip and tooltip.lines or {}) do
        local text = line and line.leftText
        if IsSafeString(text) then
            for _, formatText in pairs(triggers) do
                if IsSafeString(formatText) then
                    local prefix = formatText:gsub("%%s", ""):match("^%s*(.-)%s*$")
                    if prefix ~= "" and text:find(prefix, 1, true) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function adapter:IsCurrentCharacterEnchanter(characters, currentKey)
    for _, character in ipairs(characters or {}) do
        if character.key == currentKey then
            for key, profession in pairs(character.professions or {}) do
                local name = type(profession) == "table" and profession.name
                    or type(key) == "string" and key or nil
                if name and name:lower():find("enchant", 1, true) then
                    return true
                end
            end
        end
    end
    if GetProfessions and GetProfessionInfo then
        local professions = { GetProfessions() }
        for _, professionIndex in ipairs(professions) do
            if professionIndex then
                local name = GetProfessionInfo(professionIndex)
                if name and name:lower():find("enchant", 1, true) then
                    return true
                end
            end
        end
    end
    return false
end
