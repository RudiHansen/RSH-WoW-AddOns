local eventFrame = CreateFrame("Frame")
local snapshotCreated = false

local function InitialiseDatabase()
    CurrencyTrackerDB = CurrencyTrackerDB or {}
    CurrencyTrackerDB.version = 2
    CurrencyTrackerDB.entries = CurrencyTrackerDB.entries or {}
end

local function ScanCurrencies()
    local currencies = {}
    local foundCount = 0
    local currencyCount = C_CurrencyInfo.GetCurrencyListSize()

    for index = 1, currencyCount do
        local listInfo = C_CurrencyInfo.GetCurrencyListInfo(index)

        if listInfo and not listInfo.isHeader and listInfo.currencyID then
            local currencyID = listInfo.currencyID
            local currencyInfo =
                C_CurrencyInfo.GetCurrencyInfo(currencyID)

            if not currencies[currencyID] then
                foundCount = foundCount + 1
            end

            currencies[currencyID] = {
                currencyID = currencyID,
                name = currencyInfo and currencyInfo.name
                    or listInfo.name
                    or "Unknown",
                quantity =
                    currencyInfo and currencyInfo.quantity
                    or listInfo.quantity
                    or 0,
                quantityEarnedThisWeek =
                    currencyInfo
                    and currencyInfo.quantityEarnedThisWeek,
                maxWeeklyQuantity =
                    currencyInfo and currencyInfo.maxWeeklyQuantity,
                maxQuantity =
                    currencyInfo and currencyInfo.maxQuantity,
            }
        end
    end

    return currencies, foundCount
end

local function FindLatestSnapshot(characterName, realmName)
    local latestSnapshot
    local latestTimestamp = 0

    for _, entry in ipairs(CurrencyTrackerDB.entries) do
        if entry.character == characterName and entry.realm == realmName then
            local timestamp = tonumber(entry.timestamp) or 0

            if not latestSnapshot or timestamp >= latestTimestamp then
                latestSnapshot = entry
                latestTimestamp = timestamp
            end
        end
    end

    return latestSnapshot
end

local function CurrencyMatches(left, right)
    return type(left) == "table"
        and type(right) == "table"
        and left.currencyID == right.currencyID
        and left.name == right.name
        and left.quantity == right.quantity
        and left.quantityEarnedThisWeek
            == right.quantityEarnedThisWeek
        and left.maxWeeklyQuantity == right.maxWeeklyQuantity
        and left.maxQuantity == right.maxQuantity
end

local function CurrenciesMatch(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then
        return false
    end

    local leftCount = 0
    local rightCount = 0

    for currencyID, currency in pairs(left) do
        leftCount = leftCount + 1

        if not CurrencyMatches(currency, right[currencyID]) then
            return false
        end
    end

    for _ in pairs(right) do
        rightCount = rightCount + 1
    end

    return leftCount == rightCount
end

local function CreateSnapshot()
    if snapshotCreated then
        return
    end

    InitialiseDatabase()

    local characterName = UnitName("player")
    local realmName = GetRealmName()
    local _, className = UnitClass("player")
    local currencies, foundCount = ScanCurrencies()
    local latestSnapshot =
        FindLatestSnapshot(characterName, realmName)

    snapshotCreated = true

    if latestSnapshot
        and CurrenciesMatch(currencies, latestSnapshot.currencies)
    then
        print(
            string.format(
                "|cffffcc00RSH Currency Tracker:|r "
                    .. "No currency changes for %s-%s.",
                characterName or "Unknown",
                realmName or "Unknown"
            )
        )
        return
    end

    local snapshot = {
        timestamp = GetServerTime(),
        character = characterName,
        realm = realmName,
        class = className,
        currencies = currencies,
    }

    table.insert(CurrencyTrackerDB.entries, snapshot)

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
eventFrame:RegisterEvent("PLAYER_LOGOUT")

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        InitialiseDatabase()
        ScheduleSnapshot()
    elseif event == "PLAYER_LOGOUT" then
        snapshotCreated = false
        CreateSnapshot()
    end
end)

SLASH_RSHCURRENCYTRACKER1 = "/currencylog"

SlashCmdList.RSHCURRENCYTRACKER = function()
    snapshotCreated = false
    CreateSnapshot()
end
