local RSH = _G.RSH

if not RSH or not RSH.RegisterPage then
    return
end

local ROW_HEIGHT = 26
local LIST_WIDTH = 205
local LIST_HEIGHT = 270
local selectedAvailableCurrencyID
local selectedDisplayedCurrencyID

local function InitialiseSettings()
    CurrencyTrackerDB = CurrencyTrackerDB or {}
    CurrencyTrackerDB.entries = CurrencyTrackerDB.entries or {}
    CurrencyTrackerDB.displayedCurrencyIds =
        CurrencyTrackerDB.displayedCurrencyIds or {}
end

local function GetRegisteredCurrencies()
    local registered = {}

    for _, entry in ipairs(CurrencyTrackerDB.entries) do
        if type(entry.currencies) == "table" then
            for key, currency in pairs(entry.currencies) do
                if type(currency) == "table" then
                    local currencyID = tonumber(currency.currencyID)
                        or tonumber(key)

                    if currencyID then
                        registered[currencyID] = registered[currencyID]
                            or { currencyID = currencyID }

                        if currency.name and currency.name ~= "" then
                            registered[currencyID].name = currency.name
                        end
                    end
                end
            end
        end
    end

    return registered
end

local function GetCurrencyDetails(currencyID, registered)
    local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    local savedCurrency = registered[currencyID]

    return {
        currencyID = currencyID,
        name = currencyInfo and currencyInfo.name
            or savedCurrency and savedCurrency.name
            or ("Currency " .. currencyID),
        iconFileID = currencyInfo and currencyInfo.iconFileID,
        available = currencyInfo ~= nil,
    }
end

local function GetDisplayedLookup()
    local displayed = {}

    for _, currencyID in ipairs(CurrencyTrackerDB.displayedCurrencyIds) do
        displayed[currencyID] = true
    end

    return displayed
end

local function SortCurrencies(currencies)
    table.sort(currencies, function(left, right)
        local leftName = string.lower(left.name)
        local rightName = string.lower(right.name)

        if leftName == rightName then
            return left.currencyID < right.currencyID
        end

        return leftName < rightName
    end)
end

local function CreateList(parent, anchor, onSelect, onActivate)
    local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    border:SetPoint(unpack(anchor))
    border:SetSize(LIST_WIDTH, LIST_HEIGHT)
    border:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    border:SetBackdropColor(0.03, 0.03, 0.03, 0.8)
    border:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)

    local scrollFrame = CreateFrame(
        "ScrollFrame",
        nil,
        border,
        "UIPanelScrollFrameTemplate"
    )
    scrollFrame:SetPoint("TOPLEFT", 6, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", -27, 6)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(LIST_WIDTH - 38, 1)
    scrollFrame:SetScrollChild(content)

    local list = { frame = border, content = content, rows = {} }

    function list:SetItems(items, selectedCurrencyID)
        for index, item in ipairs(items) do
            local row = self.rows[index]

            if not row then
                row = CreateFrame("Button", nil, content)
                row:SetHeight(ROW_HEIGHT)
                row:SetPoint("LEFT")
                row:SetPoint("RIGHT")

                row.selection = row:CreateTexture(nil, "BACKGROUND")
                row.selection:SetAllPoints()
                row.selection:SetColorTexture(0.25, 0.45, 0.75, 0.55)

                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(20, 20)
                row.icon:SetPoint("LEFT", 3, 0)

                row.text = row:CreateFontString(
                    nil,
                    "OVERLAY",
                    "GameFontHighlightSmall"
                )
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.text:SetPoint("RIGHT", -4, 0)
                row.text:SetJustifyH("LEFT")
                row.text:SetWordWrap(false)
                row:SetHighlightTexture(
                    "Interface\\QuestFrame\\UI-QuestTitleHighlight"
                )
                row:SetScript("OnClick", function(button)
                    onSelect(button.currencyID)
                end)
                row:SetScript("OnDoubleClick", function(button)
                    onActivate(button.currencyID)
                end)
                self.rows[index] = row
            end

            row.currencyID = item.currencyID
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
            row:SetPoint("RIGHT")
            row.text:SetText(item.name)
            row.icon:SetTexture(
                item.iconFileID or "Interface\\Icons\\INV_Misc_QuestionMark"
            )
            row.selection:SetShown(item.currencyID == selectedCurrencyID)
            row:SetAlpha(item.available and 1 or 0.55)
            row:Show()
        end

        for index = #items + 1, #self.rows do
            self.rows[index]:Hide()
        end

        content:SetHeight(math.max(1, #items * ROW_HEIGHT))
    end

    return list
end

local function CreateLabel(parent, text, anchor)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint(unpack(anchor))
    label:SetText(text)
end

local function CreateButton(parent, text, width, anchor, onClick)
    local button = CreateFrame(
        "Button",
        nil,
        parent,
        "UIPanelButtonTemplate"
    )
    button:SetSize(width, 24)
    button:SetPoint(unpack(anchor))
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function FindDisplayedIndex(currencyID)
    for index, displayedID in ipairs(
        CurrencyTrackerDB.displayedCurrencyIds
    ) do
        if displayedID == currencyID then
            return index
        end
    end
end

local function CreateCurrencyPage(parent)
    InitialiseSettings()
    local page = CreateFrame("Frame", nil, parent)

    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Currency setup")

    local description = page:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontHighlight"
    )
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetPoint("RIGHT", page, "RIGHT", -8, 0)
    description:SetJustifyH("LEFT")
    description:SetText(
        "Choose which registered currencies to show and their display order."
    )

    CreateLabel(page, "Available currencies", {
        "TOPLEFT", description, "BOTTOMLEFT", 0, -18,
    })
    CreateLabel(page, "Shown currencies", {
        "TOPLEFT", description, "BOTTOMLEFT", 265, -18,
    })

    local searchBox = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    searchBox:SetSize(LIST_WIDTH, 24)
    searchBox:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 5, -36)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(80)
    searchBox:SetTextInsets(4, 4, 0, 0)

    local searchHint = searchBox:CreateFontString(
        nil,
        "ARTWORK",
        "GameFontDisableSmall"
    )
    searchHint:SetPoint("LEFT", 5, 0)
    searchHint:SetText("Search...")

    local availableList
    local displayedList
    local addButton
    local removeButton
    local moveUpButton
    local moveDownButton

    local function Refresh()
        InitialiseSettings()
        local registered = GetRegisteredCurrencies()
        local displayedLookup = GetDisplayedLookup()
        local searchText = string.lower(searchBox:GetText() or "")
        local availableItems = {}
        local displayedItems = {}

        for currencyID in pairs(registered) do
            if not displayedLookup[currencyID] then
                local item = GetCurrencyDetails(currencyID, registered)

                if searchText == ""
                    or string.find(string.lower(item.name), searchText, 1, true)
                then
                    table.insert(availableItems, item)
                end
            end
        end

        SortCurrencies(availableItems)

        for _, currencyID in ipairs(
            CurrencyTrackerDB.displayedCurrencyIds
        ) do
            table.insert(
                displayedItems,
                GetCurrencyDetails(currencyID, registered)
            )
        end

        if selectedAvailableCurrencyID
            and displayedLookup[selectedAvailableCurrencyID]
        then
            selectedAvailableCurrencyID = nil
        end

        if selectedDisplayedCurrencyID
            and not displayedLookup[selectedDisplayedCurrencyID]
        then
            selectedDisplayedCurrencyID = nil
        end

        availableList:SetItems(availableItems, selectedAvailableCurrencyID)
        displayedList:SetItems(displayedItems, selectedDisplayedCurrencyID)
        addButton:SetEnabled(selectedAvailableCurrencyID ~= nil)
        removeButton:SetEnabled(selectedDisplayedCurrencyID ~= nil)

        local selectedIndex = selectedDisplayedCurrencyID
            and FindDisplayedIndex(selectedDisplayedCurrencyID)
        moveUpButton:SetEnabled(selectedIndex ~= nil and selectedIndex > 1)
        moveDownButton:SetEnabled(
            selectedIndex ~= nil
                and selectedIndex < #CurrencyTrackerDB.displayedCurrencyIds
        )
    end

    local function AddCurrency(currencyID)
        if not currencyID or FindDisplayedIndex(currencyID) then
            return
        end

        table.insert(CurrencyTrackerDB.displayedCurrencyIds, currencyID)
        selectedAvailableCurrencyID = nil
        selectedDisplayedCurrencyID = currencyID
        Refresh()
    end

    local function RemoveCurrency(currencyID)
        local index = currencyID and FindDisplayedIndex(currencyID)

        if not index then
            return
        end

        table.remove(CurrencyTrackerDB.displayedCurrencyIds, index)
        selectedDisplayedCurrencyID = nil
        selectedAvailableCurrencyID = currencyID
        Refresh()
    end

    availableList = CreateList(
        page,
        { "TOPLEFT", searchBox, "BOTTOMLEFT", -5, -6 },
        function(currencyID)
            selectedAvailableCurrencyID = currencyID
            selectedDisplayedCurrencyID = nil
            Refresh()
        end,
        AddCurrency
    )
    displayedList = CreateList(
        page,
        { "TOPLEFT", searchBox, "BOTTOMLEFT", 260, -6 },
        function(currencyID)
            selectedDisplayedCurrencyID = currencyID
            selectedAvailableCurrencyID = nil
            Refresh()
        end,
        RemoveCurrency
    )

    addButton = CreateButton(page, ">", 38, {
        "TOPLEFT", availableList.frame, "TOPRIGHT", 11, -82,
    }, function()
        AddCurrency(selectedAvailableCurrencyID)
    end)
    removeButton = CreateButton(page, "<", 38, {
        "TOP", addButton, "BOTTOM", 0, -8,
    }, function()
        RemoveCurrency(selectedDisplayedCurrencyID)
    end)
    moveUpButton = CreateButton(page, "Up", 68, {
        "TOPLEFT", displayedList.frame, "TOPRIGHT", 9, -82,
    }, function()
        local index = FindDisplayedIndex(selectedDisplayedCurrencyID)

        if index and index > 1 then
            local ids = CurrencyTrackerDB.displayedCurrencyIds
            ids[index], ids[index - 1] = ids[index - 1], ids[index]
            Refresh()
        end
    end)
    moveDownButton = CreateButton(page, "Down", 68, {
        "TOP", moveUpButton, "BOTTOM", 0, -8,
    }, function()
        local index = FindDisplayedIndex(selectedDisplayedCurrencyID)
        local ids = CurrencyTrackerDB.displayedCurrencyIds

        if index and index < #ids then
            ids[index], ids[index + 1] = ids[index + 1], ids[index]
            Refresh()
        end
    end)

    CreateButton(page, "Add all", 90, {
        "TOPLEFT", availableList.frame, "BOTTOMLEFT", 0, -8,
    }, function()
        local registered = GetRegisteredCurrencies()
        local displayedLookup = GetDisplayedLookup()
        local currencies = {}

        for currencyID in pairs(registered) do
            if not displayedLookup[currencyID] then
                table.insert(
                    currencies,
                    GetCurrencyDetails(currencyID, registered)
                )
            end
        end

        SortCurrencies(currencies)

        for _, currency in ipairs(currencies) do
            table.insert(
                CurrencyTrackerDB.displayedCurrencyIds,
                currency.currencyID
            )
        end

        selectedAvailableCurrencyID = nil
        Refresh()
    end)
    CreateButton(page, "Remove all", 90, {
        "TOPLEFT", displayedList.frame, "BOTTOMLEFT", 0, -8,
    }, function()
        CurrencyTrackerDB.displayedCurrencyIds = {}
        selectedDisplayedCurrencyID = nil
        Refresh()
    end)

    searchBox:SetScript("OnEscapePressed", searchBox.ClearFocus)
    searchBox:SetScript("OnEnterPressed", searchBox.ClearFocus)
    searchBox:SetScript("OnTextChanged", function(editBox)
        searchHint:SetShown(editBox:GetText() == "")

        if availableList then
            Refresh()
        end
    end)

    page.Refresh = Refresh
    Refresh()
    return page
end

RSH:RegisterPage({
    id = "currency",
    title = "Currency",
    order = 10,
    create = CreateCurrencyPage,
    onShow = function(page)
        page.Refresh()
    end,
})
