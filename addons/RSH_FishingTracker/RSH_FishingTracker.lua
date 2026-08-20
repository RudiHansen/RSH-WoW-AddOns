local addonName = ...
local eventFrame = CreateFrame("Frame")
local DATABASE_VERSION = 1
local DUNDUN_CURRENCY_ID = 3376
local FISHING_SKILL_LINE_ID = 356
local FISHING_SPELL_IDS = {
    [7620] = true,
    [131474] = true,
}

local characterRecord
local pendingCast
local lastFishingCastGUID
local lastFishingAttemptAt = 0
local session = {
    attempts = 0,
    catches = 0,
    dundun = 0,
}

local function PrintMessage(message)
    print("|cff33aaffRSH Fishing Tracker:|r " .. message)
end

local function InitialiseDatabase()
    RSHFishingTrackerDB = RSHFishingTrackerDB or {}
    RSHFishingTrackerDB.version = DATABASE_VERSION
    RSHFishingTrackerDB.characters =
        RSHFishingTrackerDB.characters or {}
end

local function GetCharacterRecord()
    InitialiseDatabase()

    local realmName = GetRealmName() or "Unknown"
    local characterName = UnitName("player") or "Unknown"
    local realmCharacters = RSHFishingTrackerDB.characters[realmName]

    if not realmCharacters then
        realmCharacters = {}
        RSHFishingTrackerDB.characters[realmName] = realmCharacters
    end

    local record = realmCharacters[characterName]

    if not record then
        record = {
            character = characterName,
            realm = realmName,
            attempts = 0,
            catches = 0,
            dundun = 0,
            loot = {},
        }
        realmCharacters[characterName] = record
    end

    record.attempts = record.attempts or 0
    record.catches = record.catches or 0
    record.dundun = record.dundun or 0
    record.loot = record.loot or {}

    return record
end

local function GetCurrencyQuantity(currencyID)
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    return info and info.quantity or 0
end

local function GetFishingSkill()
    local _, _, _, fishingIndex = GetProfessions()

    if not fishingIndex then
        return nil
    end

    local name, _, skillLevel, maxSkillLevel, _, _, skillLineID =
        GetProfessionInfo(fishingIndex)

    return {
        name = name or "Fishing",
        skillLevel = skillLevel or 0,
        maxSkillLevel = maxSkillLevel or 0,
        skillLineID = skillLineID or FISHING_SKILL_LINE_ID,
    }
end

local function IsFishingSpell(spellID)
    if FISHING_SPELL_IDS[spellID] then
        return true
    end

    local fishingName = C_Spell.GetSpellName(131474)
    local spellName = C_Spell.GetSpellName(spellID)
    return fishingName and spellName == fishingName
end

local function FormatRate(drops, catches)
    if catches == 0 then
        return "0.00%"
    end

    return string.format("%.2f%%", drops * 100 / catches)
end

local function RecordLoot(kind, id, name, quantity, countCatch)
    local key = kind .. ":" .. id
    local lootRecord = characterRecord.loot[key]

    if not lootRecord then
        lootRecord = {
            kind = kind,
            id = id,
            name = name,
            quantity = 0,
            catches = 0,
        }
        characterRecord.loot[key] = lootRecord
    end

    lootRecord.name = name or lootRecord.name
    lootRecord.quantity = lootRecord.quantity + quantity
    lootRecord.catches = lootRecord.catches or 0

    if countCatch then
        lootRecord.catches = lootRecord.catches + 1
    end
end

local function AnnounceDundun(quantity)
    local average = characterRecord.catches / characterRecord.dundun

    PrintMessage(string.format(
        "Caught %d Shard of Dundun! Character: %d from %d catches (%s, 1 per %.1f catches).",
        quantity,
        characterRecord.dundun,
        characterRecord.catches,
        FormatRate(characterRecord.dundun, characterRecord.catches),
        average
    ))
end

local function RecordDundun(quantity)
    if quantity <= 0 or not pendingCast then
        return
    end

    local unrecordedQuantity = quantity - pendingCast.dundunRecorded

    if unrecordedQuantity <= 0 then
        return
    end

    local isFirstDundunRecord = pendingCast.dundunRecorded == 0
    pendingCast.dundunRecorded =
        pendingCast.dundunRecorded + unrecordedQuantity
    characterRecord.dundun = characterRecord.dundun + unrecordedQuantity
    session.dundun = session.dundun + unrecordedQuantity

    local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(DUNDUN_CURRENCY_ID)
    RecordLoot(
        "currency",
        DUNDUN_CURRENCY_ID,
        currencyInfo and currencyInfo.name or "Shard of Dundun",
        unrecordedQuantity,
        isFirstDundunRecord
    )
    AnnounceDundun(unrecordedQuantity)
end

local function ReadLoot()
    if not pendingCast or pendingCast.caught then
        return
    end

    pendingCast.caught = true
    characterRecord.catches = characterRecord.catches + 1
    session.catches = session.catches + 1

    local fishingSkill = GetFishingSkill()

    if fishingSkill then
        characterRecord.lastFishingSkill = fishingSkill
    end

    characterRecord.lastCatch = {
        timestamp = GetServerTime(),
        mapID = C_Map.GetBestMapForUnit("player"),
        fishingSkill = fishingSkill,
    }

    local recordedLoot = {}

    for lootSlot = 1, GetNumLootItems() do
        local _, itemName, quantity, currencyID =
            GetLootSlotInfo(lootSlot)
        quantity = quantity or 1

        if currencyID and currencyID > 0 then
            if currencyID == DUNDUN_CURRENCY_ID then
                RecordDundun(quantity)
            else
                local lootKey = "currency:" .. currencyID
                RecordLoot(
                    "currency",
                    currencyID,
                    itemName or "Unknown currency",
                    quantity,
                    not recordedLoot[lootKey]
                )
                recordedLoot[lootKey] = true
            end
        else
            local itemLink = GetLootSlotLink(lootSlot)
            local itemID = itemLink and C_Item.GetItemInfoInstant(itemLink)

            if itemID then
                local lootKey = "item:" .. itemID
                RecordLoot(
                    "item",
                    itemID,
                    itemName or itemLink,
                    quantity,
                    not recordedLoot[lootKey]
                )
                recordedLoot[lootKey] = true
            end
        end
    end
end

local function CheckDundunCurrency(cast)
    cast = cast or pendingCast

    if not cast or not cast.caught then
        return
    end

    local gained = GetCurrencyQuantity(DUNDUN_CURRENCY_ID)
        - cast.dundunBefore
    RecordDundun(gained)
end

local function FinishCatch()
    if not pendingCast or not pendingCast.caught then
        return
    end

    local completedCast = pendingCast
    CheckDundunCurrency(completedCast)

    C_Timer.After(1, function()
        if pendingCast == completedCast then
            CheckDundunCurrency(completedCast)
            pendingCast = nil
        end
    end)
end

local function StartFishingCast(castGUID)
    local currentTime = GetTime()

    if castGUID and castGUID == lastFishingCastGUID then
        return
    end

    -- Retail can report more than one fishing spell for a single physical cast.
    if currentTime - lastFishingAttemptAt < 1 then
        return
    end

    lastFishingCastGUID = castGUID
    lastFishingAttemptAt = currentTime
    characterRecord.attempts = characterRecord.attempts + 1
    session.attempts = session.attempts + 1
    pendingCast = {
        startedAt = GetTime(),
        dundunBefore = GetCurrencyQuantity(DUNDUN_CURRENCY_ID),
        dundunRecorded = 0,
        caught = false,
    }

    C_Timer.After(45, function()
        if pendingCast
            and GetTime() - pendingCast.startedAt >= 45
        then
            pendingCast = nil
        end
    end)
end

local function PrintStatistics(label, attempts, catches, dundun)
    PrintMessage(string.format(
        "%s: %d attempts, %d catches, %d Shard of Dundun (%s).",
        label,
        attempts,
        catches,
        dundun,
        FormatRate(dundun, catches)
    ))
end

local function PrintLootStatistics()
    local lootRecords = {}

    for _, lootRecord in pairs(characterRecord.loot) do
        table.insert(lootRecords, lootRecord)
    end

    table.sort(lootRecords, function(left, right)
        local leftName = left.name or ""
        local rightName = right.name or ""
        return leftName < rightName
    end)

    if #lootRecords == 0 then
        PrintMessage("No fishing loot has been recorded yet.")
        return
    end

    PrintMessage("Recorded fishing loot:")

    for _, lootRecord in ipairs(lootRecords) do
        local lootCatches = lootRecord.catches or 0

        PrintMessage(string.format(
            "  %s: %d from %d catches (%s drop rate).",
            lootRecord.name or "Unknown",
            lootRecord.quantity or 0,
            lootCatches,
            FormatRate(lootCatches, characterRecord.catches)
        ))
    end
end

local function HandleSlashCommand(arguments)
    local command = string.lower(strtrim(arguments or ""))

    if command == "session" then
        PrintStatistics(
            "Session",
            session.attempts,
            session.catches,
            session.dundun
        )
    elseif command == "help" then
        PrintMessage("Commands: /fishingtracker, /fishingtracker session")
    else
        PrintStatistics(
            characterRecord.character,
            characterRecord.attempts,
            characterRecord.catches,
            characterRecord.dundun
        )

        local skill = characterRecord.lastFishingSkill

        if skill then
            PrintMessage(string.format(
                "Last fishing skill: %s %d/%d.",
                skill.name,
                skill.skillLevel,
                skill.maxSkillLevel
            ))
        end

        PrintLootStatistics()
    end
end

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("LOOT_READY")
eventFrame:RegisterEvent("LOOT_CLOSED")
eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        characterRecord = GetCharacterRecord()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unitTarget, castGUID, spellID = ...

        if unitTarget == "player" and IsFishingSpell(spellID) then
            StartFishingCast(castGUID)
        end
    elseif event == "LOOT_READY" then
        ReadLoot()
    elseif event == "LOOT_CLOSED" then
        FinishCatch()
    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        CheckDundunCurrency()
    end
end)

SLASH_RSHFISHINGTRACKER1 = "/fishingtracker"
SLASH_RSHFISHINGTRACKER2 = "/fishtracker"

SlashCmdList.RSHFISHINGTRACKER = HandleSlashCommand
