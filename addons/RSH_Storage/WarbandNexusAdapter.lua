local _, addon = ...

local adapter = {}
addon.WarbandNexus = adapter

local EQUIPPABLE_LOCATIONS = {
    ["INVTYPE_HEAD"] = true, ["INVTYPE_NECK"] = true,
    ["INVTYPE_SHOULDER"] = true, ["INVTYPE_CLOAK"] = true,
    ["INVTYPE_BACK"] = true, ["INVTYPE_CHEST"] = true,
    ["INVTYPE_ROBE"] = true, ["INVTYPE_WRIST"] = true,
    ["INVTYPE_HAND"] = true, ["INVTYPE_WAIST"] = true,
    ["INVTYPE_LEGS"] = true, ["INVTYPE_FEET"] = true,
    ["INVTYPE_FINGER"] = true, ["INVTYPE_TRINKET"] = true,
    ["INVTYPE_WEAPON"] = true, ["INVTYPE_WEAPONMAINHAND"] = true,
    ["INVTYPE_WEAPONOFFHAND"] = true, ["INVTYPE_2HWEAPON"] = true,
    ["INVTYPE_SHIELD"] = true, ["INVTYPE_HOLDABLE"] = true,
    ["INVTYPE_RANGED"] = true, ["INVTYPE_RANGEDRIGHT"] = true,
}

local ARMOR_SUBCLASS_BY_CLASS = {
    WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
    HUNTER = 3, SHAMAN = 3, EVOKER = 3,
    ROGUE = 2, DRUID = 2, MONK = 2, DEMONHUNTER = 2,
    MAGE = 1, PRIEST = 1, WARLOCK = 1,
}

local function Set(values)
    local result = {}
    for _, value in ipairs(values) do result[value] = true end
    return result
end

local WEAPON_SUBCLASSES_BY_CLASS = {
    WARRIOR = Set({ 0, 1, 4, 5, 6, 7, 8, 10, 13, 15 }),
    PALADIN = Set({ 0, 1, 4, 5, 6, 7, 8 }),
    DEATHKNIGHT = Set({ 0, 1, 4, 5, 6, 7, 8 }),
    HUNTER = Set({ 0, 1, 2, 3, 6, 7, 8, 10, 18 }),
    SHAMAN = Set({ 0, 1, 4, 5, 10, 13, 15 }),
    EVOKER = Set({ 0, 4, 7, 10, 13, 15 }),
    ROGUE = Set({ 0, 4, 7, 13, 15 }),
    DRUID = Set({ 4, 5, 6, 10, 13, 15 }),
    MONK = Set({ 0, 4, 6, 7, 10, 13 }),
    DEMONHUNTER = Set({ 0, 7, 9, 13 }),
    MAGE = Set({ 7, 10, 15, 19 }),
    PRIEST = Set({ 4, 10, 15, 19 }),
    WARLOCK = Set({ 7, 10, 15, 19 }),
}

local INTELLECT_SPECIALIZATIONS = {
    [62] = true, [63] = true, [64] = true,
    [65] = true, [102] = true, [105] = true,
    [1467] = true, [1468] = true, [1473] = true,
    [256] = true, [257] = true, [258] = true,
    [262] = true, [264] = true, [265] = true,
    [266] = true, [267] = true, [270] = true,
    [1480] = true,
}

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
                    specID = tonumber(character.specID),
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

function adapter:GetCurrentCharacterDisplayName()
    local currentKey = self:GetCurrentCharacterKey()
    for _, character in ipairs(self:GetCharacters()) do
        if character.key == currentKey then
            local name = character.name or character.key
            if character.realm and character.realm ~= "" then
                name = name .. " - " .. character.realm
            end
            return name
        end
    end
    local name = UnitName and UnitName("player")
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
        or GetRealmName and GetRealmName()
    if name then
        return realm and realm ~= "" and (name .. " - " .. realm) or name
    end
    return currentKey
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
    local itemClassID = item and tonumber(item.classID)
    local itemSubclassID = item and tonumber(item.subclassID)
    if C_Item
        and C_Item.GetItemInfoInstant then
        local ok, _, _, _, instantEquipLoc, _, instantClassID,
            instantSubclassID = pcall(
            C_Item.GetItemInfoInstant,
            link or itemID
        )
        if ok then
            if not equipLoc or equipLoc == "" then equipLoc = instantEquipLoc end
            itemClassID = itemClassID or tonumber(instantClassID)
            itemSubclassID = itemSubclassID or tonumber(instantSubclassID)
        end
    end

    return {
        itemID = itemID,
        itemLink = link,
        name = name or ("Item " .. addon:SafeText(itemID)),
        itemLevel = tonumber(itemLevel),
        minimumLevel = minimumLevel,
        quality = quality,
        equipLoc = equipLoc,
        classID = itemClassID,
        subclassID = itemSubclassID,
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

function adapter:IsEquippableGear(item)
    return item and EQUIPPABLE_LOCATIONS[item.equipLoc] == true
end

function adapter:IsItemCompatible(character, item)
    if not character or not item or not self:IsEquippableGear(item) then
        return false
    end
    local equipLoc = item.equipLoc
    local classFile = character.classFile
    local armorClass = _G.LE_ITEM_CLASS_ARMOR or 4
    local weaponClass = _G.LE_ITEM_CLASS_WEAPON or 2
    local armorSlot = equipLoc == "INVTYPE_HEAD"
        or equipLoc == "INVTYPE_SHOULDER"
        or equipLoc == "INVTYPE_CHEST"
        or equipLoc == "INVTYPE_ROBE"
        or equipLoc == "INVTYPE_WRIST"
        or equipLoc == "INVTYPE_HAND"
        or equipLoc == "INVTYPE_WAIST"
        or equipLoc == "INVTYPE_LEGS"
        or equipLoc == "INVTYPE_FEET"
    if armorSlot then
        if item.classID and item.classID ~= armorClass then return false end
        local required = classFile and ARMOR_SUBCLASS_BY_CLASS[classFile]
        if required and item.subclassID then
            return item.subclassID == required
        end
        return true
    end
    if equipLoc == "INVTYPE_SHIELD" then
        return classFile == "WARRIOR" or classFile == "PALADIN"
            or classFile == "SHAMAN"
    end
    if equipLoc == "INVTYPE_HOLDABLE" then
        if character.specID then
            return INTELLECT_SPECIALIZATIONS[character.specID] == true
        end
        return true
    end
    if equipLoc == "INVTYPE_RANGED"
        or equipLoc == "INVTYPE_RANGEDRIGHT" then
        return classFile == "HUNTER"
    end
    local weaponLocation = equipLoc == "INVTYPE_WEAPON"
        or equipLoc == "INVTYPE_WEAPONMAINHAND"
        or equipLoc == "INVTYPE_WEAPONOFFHAND"
        or equipLoc == "INVTYPE_2HWEAPON"
    if weaponLocation then
        if item.classID and item.classID ~= weaponClass then return false end
        local allowed = classFile and WEAPON_SUBCLASSES_BY_CLASS[classFile]
        if allowed and item.subclassID then
            return allowed[item.subclassID] == true
        end
    end
    return true
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
    if C_Item and C_Item.GetItemInfo then
        local results = { pcall(C_Item.GetItemInfo, link or itemID) }
        local bindType = results[1] and results[15] or nil
        local itemBind = Enum and Enum.ItemBind
        if bindType == 2
            or bindType == (itemBind and itemBind.OnEquip) then
            return "boe", "Bind on equip"
        elseif bindType == 9
            or bindType == (itemBind and itemBind.ToBnetAccountUntilEquipped) then
            return "warbound_until_equipped", "Warbound until equipped"
        elseif bindType == 7 or bindType == 8
            or bindType == (itemBind and itemBind.ToWoWAccount)
            or bindType == (itemBind and itemBind.Warband) then
            return "warbound", "Warbound"
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
