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

local function CreateSnapshot()
    if snapshotCreated then
        return
    end

    InitialiseDatabase()

    local characterName = UnitName("player")
    local realmName = GetRealmName()
    local _, className = UnitClass("player")
    local currencies, foundCount = ScanCurrencies()

    local snapshot = {
        timestamp = GetServerTime(),
        character = characterName,
        realm = realmName,
        class = className,
        currencies = currencies,
    }

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
