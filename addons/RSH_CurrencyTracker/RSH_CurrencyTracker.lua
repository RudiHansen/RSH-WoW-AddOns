local _, addon = ...

local currenciesToLog = {}
local definitionsByName = {}

for _, definition in ipairs(addon.currencyDefinitions) do
    definitionsByName[definition.name] = definition

    if definition.tracked then
        currenciesToLog[#currenciesToLog + 1] = definition.name
    end
end

local eventFrame = CreateFrame("Frame")
local snapshotCreated = false

local function InitialiseDatabase()
    CurrencyTrackerDB = CurrencyTrackerDB or {}
    CurrencyTrackerDB.version = CurrencyTrackerDB.version or 1
    CurrencyTrackerDB.currencyIDs = CurrencyTrackerDB.currencyIDs or {}
    CurrencyTrackerDB.entries = CurrencyTrackerDB.entries or {}
    CurrencyTrackerDB.unknownCurrencies =
        CurrencyTrackerDB.unknownCurrencies or {}
end

local function ScanCurrencies()
    local currencyList = {}
    local knownCurrencyIDs = {}
    local currencyCount = C_CurrencyInfo.GetCurrencyListSize()

    for index = 1, currencyCount do
        local info = C_CurrencyInfo.GetCurrencyListInfo(index)

        if info and not info.isHeader and info.currencyID then
            currencyList[#currencyList + 1] = info

            local definition = definitionsByName[info.name]
            if definition then
                knownCurrencyIDs[info.currencyID] = definition
                CurrencyTrackerDB.currencyIDs[definition.name] =
                    info.currencyID
            end
        end
    end

    local seenAt = GetServerTime()
    local characterName = UnitName("player") or "Unknown"

    for _, listInfo in ipairs(currencyList) do
        local currencyID = listInfo.currencyID

        if not knownCurrencyIDs[currencyID] then
            local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyID)
            local unknownCurrency =
                CurrencyTrackerDB.unknownCurrencies[currencyID]
            local firstDiscovery = unknownCurrency == nil

            if firstDiscovery then
                unknownCurrency = {
                    firstSeenAt = seenAt,
                    firstSeenCharacter = characterName,
                }
                CurrencyTrackerDB.unknownCurrencies[currencyID] =
                    unknownCurrency
            end

            unknownCurrency.name = listInfo.name
            unknownCurrency.quantity =
                currencyInfo and currencyInfo.quantity
                or listInfo.quantity
                or 0
            unknownCurrency.lastSeenAt = seenAt
            unknownCurrency.lastSeenCharacter = characterName

            if firstDiscovery then
                print(
                    string.format(
                        "|cffffcc00RSH Currency Tracker:|r "
                            .. "Discovered unknown currency %s (ID %d).",
                        listInfo.name or "Unknown",
                        currencyID
                    )
                )
            end
        end
    end
end

local function CreateSnapshot()
    if snapshotCreated then
        return
    end

    InitialiseDatabase()
    ScanCurrencies()

    local characterName = UnitName("player")
    local realmName = GetRealmName()
    local _, className = UnitClass("player")

    local snapshot = {
        timestamp = GetServerTime(),
        character = characterName,
        realm = realmName,
        class = className,
        currencies = {},
    }

    local foundCount = 0

    for _, currencyName in ipairs(currenciesToLog) do
        local currencyID = CurrencyTrackerDB.currencyIDs[currencyName]
        local currencyInfo

        if currencyID then
            currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        end

        if currencyInfo then
            snapshot.currencies[currencyName] = {
                currencyID = currencyInfo.currencyID,
                quantity = currencyInfo.quantity,
                quantityEarnedThisWeek =
                    currencyInfo.quantityEarnedThisWeek,
                maxWeeklyQuantity =
                    currencyInfo.maxWeeklyQuantity,
                maxQuantity =
                    currencyInfo.maxQuantity,
            }

            foundCount = foundCount + 1
        else
            snapshot.currencies[currencyName] = {
                currencyID = currencyID,
                quantity = 0,
                unavailable = true,
            }
        end
    end

    table.insert(CurrencyTrackerDB.entries, snapshot)
    snapshotCreated = true

    print(
        string.format(
            "|cff00ff00RSH Currency Tracker:|r Saved %d currencies for %s-%s.",
            foundCount,
            characterName or "Unknown",
            realmName or "Unknown"
        )
    )
end

local function ScheduleSnapshot()
    -- Currency data may not be fully available immediately after login.
    C_Timer.After(5, CreateSnapshot)
end

eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        InitialiseDatabase()
        ScheduleSnapshot()
    end
end)

SLASH_RSHCURRENCYTRACKER1 = "/currencylog"

SlashCmdList.RSHCURRENCYTRACKER = function()
    snapshotCreated = false
    CreateSnapshot()
end
