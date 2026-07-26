local addonName = ...

local currenciesToLog = {
    "Field Accolade",
    "Adventurer Dawncrest",
    "Veteran Dawncrest",
    "Champion Dawncrest",
    "Hero Dawncrest",
    "Myth Dawncrest",
}

local eventFrame = CreateFrame("Frame")
local snapshotCreated = false

local function InitialiseDatabase()
    CurrencyTrackerDB = CurrencyTrackerDB or {}
    CurrencyTrackerDB.version = CurrencyTrackerDB.version or 1
    CurrencyTrackerDB.currencyIDs = CurrencyTrackerDB.currencyIDs or {}
    CurrencyTrackerDB.entries = CurrencyTrackerDB.entries or {}
end

local function DiscoverCurrencyIDs()
    local wantedCurrencies = {}

    for _, currencyName in ipairs(currenciesToLog) do
        wantedCurrencies[currencyName] = true
    end

    local currencyCount = C_CurrencyInfo.GetCurrencyListSize()

    for index = 1, currencyCount do
        local info = C_CurrencyInfo.GetCurrencyListInfo(index)

        if info
            and not info.isHeader
            and wantedCurrencies[info.name]
        then
            CurrencyTrackerDB.currencyIDs[info.name] = info.currencyID
        end
    end
end

local function CreateSnapshot()
    if snapshotCreated then
        return
    end

    InitialiseDatabase()
    DiscoverCurrencyIDs()

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
            "|cff00ff00CurrencyLoginLog:|r Saved %d currencies for %s-%s.",
            foundCount,
            characterName or "Unknown",
            realmName or "Unknown"
        )
    )
end

local function ScheduleSnapshot()
    -- Currency-oplysninger er ikke altid helt klar øjeblikkeligt.
    C_Timer.After(5, CreateSnapshot)
end

eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        InitialiseDatabase()
        ScheduleSnapshot()
    end
end)

SLASH_CURRENCYLOGINLOG1 = "/currencylog"

SlashCmdList.CURRENCYLOGINLOG = function()
    snapshotCreated = false
    CreateSnapshot()
end