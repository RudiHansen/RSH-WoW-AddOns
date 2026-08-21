local RSH = _G.RSH

if not RSH or not RSH.RegisterPage then
    return
end

local LIST_ROW_HEIGHT = 26
local LIST_WIDTH = 205
local LIST_HEIGHT = 230
local TABLE_ROW_HEIGHT = 27
local TABLE_VISIBLE_ROWS = 10
local DATE_COLUMN_WIDTH = 138
local CURRENCY_COLUMN_WIDTH = 132
local TABLE_VIEW_WIDTH = 390

local PERIOD_OPTIONS = {
    { value = "7", label = "Last 7 days" },
    { value = "30", label = "Last 30 days" },
    { value = "90", label = "Last 90 days" },
    { value = "year", label = "This year" },
    { value = "all", label = "All history" },
}

local GROUP_OPTIONS = {
    { value = "entry", label = "Individual entries" },
    { value = "day", label = "Day" },
    { value = "week", label = "Week" },
    { value = "month", label = "Month" },
    { value = "year", label = "Year" },
}

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

local function CreateLabel(parent, text, anchor, template)
    local label = parent:CreateFontString(
        nil,
        "OVERLAY",
        template or "GameFontNormal"
    )
    label:SetPoint(unpack(anchor))
    label:SetText(text)
    return label
end

local function CreateDropdown(parent, width, anchor, getOptions, onSelect)
    local dropdown = CreateFrame(
        "Frame",
        nil,
        parent,
        "UIDropDownMenuTemplate"
    )
    dropdown:SetPoint(unpack(anchor))
    UIDropDownMenu_SetWidth(dropdown, width)
    UIDropDownMenu_Initialize(dropdown, function()
        for _, option in ipairs(getOptions()) do
            local optionValue = option.value
            local optionLabel = option.label
            local info = UIDropDownMenu_CreateInfo()
            info.text = optionLabel
            info.value = optionValue
            info.checked = optionValue == dropdown.selectedValue
            info.func = function()
                dropdown.selectedValue = optionValue
                UIDropDownMenu_SetText(dropdown, optionLabel)
                onSelect(optionValue)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    function dropdown:SetSelectedValue(value, label)
        self.selectedValue = value
        UIDropDownMenu_SetText(self, label or value or "")
    end

    return dropdown
end

local function CreateCurrencyList(parent, anchor, onSelect, onActivate)
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
                row:SetHeight(LIST_ROW_HEIGHT)
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
            row:SetPoint("TOPLEFT", 0, -((index - 1) * LIST_ROW_HEIGHT))
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

        content:SetHeight(math.max(1, #items * LIST_ROW_HEIGHT))
    end

    return list
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

local function CreateSetupPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    local selectedAvailableCurrencyID
    local selectedDisplayedCurrencyID

    CreateLabel(panel, "Available currencies", { "TOPLEFT", 0, -8 })
    CreateLabel(panel, "Shown currencies", { "TOPLEFT", 265, -8 })

    local searchBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    searchBox:SetSize(LIST_WIDTH, 24)
    searchBox:SetPoint("TOPLEFT", 5, -27)
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

    availableList = CreateCurrencyList(
        panel,
        { "TOPLEFT", searchBox, "BOTTOMLEFT", -5, -6 },
        function(currencyID)
            selectedAvailableCurrencyID = currencyID
            selectedDisplayedCurrencyID = nil
            Refresh()
        end,
        AddCurrency
    )
    displayedList = CreateCurrencyList(
        panel,
        { "TOPLEFT", searchBox, "BOTTOMLEFT", 260, -6 },
        function(currencyID)
            selectedDisplayedCurrencyID = currencyID
            selectedAvailableCurrencyID = nil
            Refresh()
        end,
        RemoveCurrency
    )

    addButton = CreateButton(panel, ">", 38, {
        "TOPLEFT", availableList.frame, "TOPRIGHT", 11, -68,
    }, function()
        AddCurrency(selectedAvailableCurrencyID)
    end)
    removeButton = CreateButton(panel, "<", 38, {
        "TOP", addButton, "BOTTOM", 0, -8,
    }, function()
        RemoveCurrency(selectedDisplayedCurrencyID)
    end)
    moveUpButton = CreateButton(panel, "Up", 68, {
        "TOPLEFT", displayedList.frame, "TOPRIGHT", 9, -68,
    }, function()
        local index = FindDisplayedIndex(selectedDisplayedCurrencyID)

        if index and index > 1 then
            local ids = CurrencyTrackerDB.displayedCurrencyIds
            ids[index], ids[index - 1] = ids[index - 1], ids[index]
            Refresh()
        end
    end)
    moveDownButton = CreateButton(panel, "Down", 68, {
        "TOP", moveUpButton, "BOTTOM", 0, -8,
    }, function()
        local index = FindDisplayedIndex(selectedDisplayedCurrencyID)
        local ids = CurrencyTrackerDB.displayedCurrencyIds

        if index and index < #ids then
            ids[index], ids[index + 1] = ids[index + 1], ids[index]
            Refresh()
        end
    end)

    CreateButton(panel, "Add all", 90, {
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
    CreateButton(panel, "Remove all", 90, {
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

    panel.Refresh = Refresh
    Refresh()
    return panel
end

local function GetTimestamp(entry)
    return tonumber(entry.timestamp) or 0
end

local function GetCurrencyQuantity(entry, currencyID)
    if not entry or type(entry.currencies) ~= "table" then
        return nil
    end

    local currency = entry.currencies[currencyID]
        or entry.currencies[tostring(currencyID)]

    if type(currency) == "number" then
        return currency
    end

    if type(currency) ~= "table" or currency.unavailable then
        return nil
    end

    return tonumber(currency.quantity)
end

local function FormatQuantity(quantity, delta)
    if quantity == nil then
        return "-"
    end

    local quantityText = BreakUpLargeNumbers
        and BreakUpLargeNumbers(quantity)
        or tostring(quantity)

    if delta and delta ~= 0 then
        return string.format("%s (%+d)", quantityText, delta)
    end

    return quantityText
end

local function GetCharacters()
    local names = {}
    local seen = {}

    for _, entry in ipairs(CurrencyTrackerDB.entries) do
        local name = entry.character or "Unknown"

        if not seen[name] then
            seen[name] = true
            table.insert(names, name)
        end
    end

    table.sort(names, function(left, right)
        return string.lower(left) < string.lower(right)
    end)

    return names
end

local function GetCharacterEntries(characterName)
    local entries = {}

    for _, entry in ipairs(CurrencyTrackerDB.entries) do
        if (entry.character or "Unknown") == characterName then
            table.insert(entries, entry)
        end
    end

    table.sort(entries, function(left, right)
        return GetTimestamp(left) < GetTimestamp(right)
    end)
    return entries
end

local function EntryMatchesPeriod(entry, period)
    local timestamp = GetTimestamp(entry)

    if period == "all" then
        return true
    end

    if period == "year" then
        return date("%Y", timestamp) == date("%Y", GetServerTime())
    end

    local days = tonumber(period) or 30
    return timestamp >= GetServerTime() - (days * 24 * 60 * 60)
end

local function GetGroupKeyAndLabel(timestamp, grouping)
    if grouping == "day" then
        return date("%Y-%m-%d", timestamp), date("%d-%m-%Y", timestamp)
    elseif grouping == "week" then
        return date("%Y-%W", timestamp),
            string.format(
                "Week %d, %s",
                tonumber(date("%W", timestamp)) or 0,
                date("%Y", timestamp)
            )
    elseif grouping == "month" then
        return date("%Y-%m", timestamp), date("%B %Y", timestamp)
    elseif grouping == "year" then
        return date("%Y", timestamp), date("%Y", timestamp)
    end
end

local function BuildOverviewRows(entries, period, grouping, currencyIDs)
    local rows = {}

    if grouping == "entry" then
        for index, entry in ipairs(entries) do
            if EntryMatchesPeriod(entry, period) then
                local previous = entries[index - 1]
                local values = {}

                for _, currencyID in ipairs(currencyIDs) do
                    local quantity = GetCurrencyQuantity(entry, currencyID)
                    local previousQuantity = GetCurrencyQuantity(
                        previous,
                        currencyID
                    )
                    local delta

                    if quantity ~= nil and previousQuantity ~= nil then
                        delta = quantity - previousQuantity
                    end

                    table.insert(values, FormatQuantity(quantity, delta))
                end

                table.insert(rows, {
                    label = date("%d-%m-%Y  %H:%M", GetTimestamp(entry)),
                    values = values,
                })
            end
        end

        return rows
    end

    local groups = {}
    local groupByKey = {}

    for index, entry in ipairs(entries) do
        if EntryMatchesPeriod(entry, period) then
            local key, label = GetGroupKeyAndLabel(
                GetTimestamp(entry),
                grouping
            )
            local group = groupByKey[key]

            if not group then
                group = {
                    label = label,
                    firstIndex = index,
                    lastIndex = index,
                }
                groupByKey[key] = group
                table.insert(groups, group)
            else
                group.lastIndex = index
            end
        end
    end

    for _, group in ipairs(groups) do
        local lastEntry = entries[group.lastIndex]
        local previousEntry = entries[group.firstIndex - 1]
        local values = {}

        for _, currencyID in ipairs(currencyIDs) do
            local quantity = GetCurrencyQuantity(lastEntry, currencyID)
            local previousQuantity = GetCurrencyQuantity(
                previousEntry,
                currencyID
            )
            local delta

            if quantity ~= nil and previousQuantity ~= nil then
                delta = quantity - previousQuantity
            end

            table.insert(values, FormatQuantity(quantity, delta))
        end

        table.insert(rows, { label = group.label, values = values })
    end

    return rows
end


local function CreateSlider(parent, orientation, anchor, width, height)
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation(orientation)
    slider:SetPoint(unpack(anchor))
    slider:SetSize(width, height)
    slider:SetMinMaxValues(0, 0)
    slider:SetValue(0)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)

    local background = slider:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.12, 0.12, 0.12, 0.9)

    if orientation == "VERTICAL" then
        slider:SetThumbTexture(
            "Interface\\Buttons\\UI-SliderBar-Button-Vertical"
        )
    else
        slider:SetThumbTexture(
            "Interface\\Buttons\\UI-SliderBar-Button-Horizontal"
        )
    end

    local thumb = slider:GetThumbTexture()
    thumb:SetSize(18, 18)
    return slider
end

local function CreateOverviewTable(parent)
    local tableFrame = CreateFrame("Frame", nil, parent)
    tableFrame:SetPoint("TOPLEFT", 0, -91)
    tableFrame:SetSize(DATE_COLUMN_WIDTH + TABLE_VIEW_WIDTH + 18, 310)

    local dateHeader = CreateFrame("Frame", nil, tableFrame, "BackdropTemplate")
    dateHeader:SetPoint("TOPLEFT")
    dateHeader:SetSize(DATE_COLUMN_WIDTH, TABLE_ROW_HEIGHT)
    dateHeader:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    dateHeader:SetBackdropColor(0.18, 0.18, 0.18, 1)
    CreateLabel(dateHeader, "Date / Time", { "LEFT", 6, 0 })

    local headerViewport = CreateFrame("Frame", nil, tableFrame)
    headerViewport:SetPoint("TOPLEFT", dateHeader, "TOPRIGHT", 1, 0)
    headerViewport:SetSize(TABLE_VIEW_WIDTH, TABLE_ROW_HEIGHT)
    headerViewport:SetClipsChildren(true)

    local body = CreateFrame("Frame", nil, tableFrame)
    body:SetPoint("TOPLEFT", dateHeader, "BOTTOMLEFT", 0, -1)
    body:SetSize(DATE_COLUMN_WIDTH + TABLE_VIEW_WIDTH + 1,
        TABLE_VISIBLE_ROWS * TABLE_ROW_HEIGHT)
    body:SetClipsChildren(true)

    local currencyViewport = CreateFrame("Frame", nil, body)
    currencyViewport:SetPoint("TOPLEFT", DATE_COLUMN_WIDTH + 1, 0)
    currencyViewport:SetSize(
        TABLE_VIEW_WIDTH,
        TABLE_VISIBLE_ROWS * TABLE_ROW_HEIGHT
    )
    currencyViewport:SetClipsChildren(true)

    local verticalSlider = CreateSlider(
        tableFrame,
        "VERTICAL",
        { "TOPLEFT", body, "TOPRIGHT", 3, 0 },
        14,
        TABLE_VISIBLE_ROWS * TABLE_ROW_HEIGHT
    )
    local horizontalSlider = CreateSlider(
        tableFrame,
        "HORIZONTAL",
        { "TOPLEFT", currencyViewport, "BOTTOMLEFT", 0, -5 },
        TABLE_VIEW_WIDTH,
        14
    )

    local view = {
        frame = tableFrame,
        body = body,
        headerViewport = headerViewport,
        currencyViewport = currencyViewport,
        verticalSlider = verticalSlider,
        horizontalSlider = horizontalSlider,
        dateRows = {},
        currencyRows = {},
        headers = {},
        rows = {},
        currencies = {},
    }

    local function Render()
        local _, maximumVertical = verticalSlider:GetMinMaxValues()
        local firstIndex = maximumVertical
            - math.floor(verticalSlider:GetValue())
            + 1
        local horizontalOffset = horizontalSlider:GetValue()

        for index, header in ipairs(view.headers) do
            header:ClearAllPoints()
            header:SetPoint(
                "TOPLEFT",
                ((index - 1) * CURRENCY_COLUMN_WIDTH) - horizontalOffset,
                0
            )
        end

        for visibleIndex = 1, TABLE_VISIBLE_ROWS do
            local rowData = view.rows[firstIndex + visibleIndex - 1]
            local dateRow = view.dateRows[visibleIndex]
            local currencyRow = view.currencyRows[visibleIndex]

            if rowData then
                dateRow.text:SetText(rowData.label)
                dateRow:Show()
                currencyRow:Show()

                for columnIndex, cell in ipairs(currencyRow.cells) do
                    cell:ClearAllPoints()
                    cell:SetPoint(
                        "TOPLEFT",
                        ((columnIndex - 1) * CURRENCY_COLUMN_WIDTH)
                            - horizontalOffset,
                        0
                    )
                    cell.text:SetText(rowData.values[columnIndex] or "-")
                end
            else
                dateRow:Hide()
                currencyRow:Hide()
            end
        end
    end

    for visibleIndex = 1, TABLE_VISIBLE_ROWS do
        local dateRow = CreateFrame("Frame", nil, body, "BackdropTemplate")
        dateRow:SetPoint(
            "TOPLEFT",
            0,
            -((visibleIndex - 1) * TABLE_ROW_HEIGHT)
        )
        dateRow:SetSize(DATE_COLUMN_WIDTH, TABLE_ROW_HEIGHT - 1)
        dateRow:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        dateRow:SetBackdropColor(0.08, 0.08, 0.08, 0.75)
        dateRow.text = CreateLabel(
            dateRow,
            "",
            { "LEFT", 6, 0 },
            "GameFontHighlightSmall"
        )
        view.dateRows[visibleIndex] = dateRow

        local currencyRow = CreateFrame("Frame", nil, currencyViewport)
        currencyRow:SetPoint(
            "TOPLEFT",
            0,
            -((visibleIndex - 1) * TABLE_ROW_HEIGHT)
        )
        currencyRow:SetSize(TABLE_VIEW_WIDTH, TABLE_ROW_HEIGHT - 1)
        currencyRow.cells = {}
        view.currencyRows[visibleIndex] = currencyRow
    end

    function view:SetData(rows, currencies)
        self.rows = rows
        self.currencies = currencies

        for index, currency in ipairs(currencies) do
            local header = self.headers[index]

            if not header then
                header = CreateFrame("Button", nil, headerViewport)
                header:SetSize(CURRENCY_COLUMN_WIDTH - 1, TABLE_ROW_HEIGHT)
                header.background = header:CreateTexture(nil, "BACKGROUND")
                header.background:SetAllPoints()
                header.background:SetColorTexture(0.18, 0.18, 0.18, 1)
                header.icon = header:CreateTexture(nil, "ARTWORK")
                header.icon:SetSize(18, 18)
                header.icon:SetPoint("LEFT", 5, 0)
                header.text = CreateLabel(
                    header,
                    "",
                    { "LEFT", header.icon, "RIGHT", 4, 0 },
                    "GameFontNormalSmall"
                )
                header.text:SetPoint("RIGHT", -3, 0)
                header.text:SetJustifyH("LEFT")
                header:SetScript("OnEnter", function(button)
                    GameTooltip:SetOwner(button, "ANCHOR_TOP")
                    GameTooltip:SetText(button.currencyName)
                    GameTooltip:AddLine(
                        "Currency ID: " .. button.currencyID,
                        1,
                        1,
                        1
                    )
                    GameTooltip:AddLine(
                        "Balance (change since previous entry or period)",
                        0.8,
                        0.8,
                        0.8,
                        true
                    )
                    GameTooltip:Show()
                end)
                header:SetScript("OnLeave", GameTooltip_Hide)
                self.headers[index] = header
            end

            header.currencyID = currency.currencyID
            header.currencyName = currency.name
            header.icon:SetTexture(
                currency.iconFileID
                    or "Interface\\Icons\\INV_Misc_QuestionMark"
            )
            header.text:SetText(currency.name)
            header:Show()

            for visibleIndex = 1, TABLE_VISIBLE_ROWS do
                local currencyRow = self.currencyRows[visibleIndex]
                local cell = currencyRow.cells[index]

                if not cell then
                    cell = CreateFrame(
                        "Frame",
                        nil,
                        currencyRow,
                        "BackdropTemplate"
                    )
                    cell:SetSize(
                        CURRENCY_COLUMN_WIDTH - 1,
                        TABLE_ROW_HEIGHT - 1
                    )
                    cell:SetBackdrop({
                        bgFile = "Interface\\Buttons\\WHITE8X8",
                    })
                    cell:SetBackdropColor(0.08, 0.08, 0.08, 0.75)
                    cell.text = CreateLabel(
                        cell,
                        "",
                        { "RIGHT", -6, 0 },
                        "GameFontHighlightSmall"
                    )
                    cell.text:SetJustifyH("RIGHT")
                    currencyRow.cells[index] = cell
                end

                cell:Show()
            end
        end

        for index = #currencies + 1, #self.headers do
            self.headers[index]:Hide()

            for visibleIndex = 1, TABLE_VISIBLE_ROWS do
                self.currencyRows[visibleIndex].cells[index]:Hide()
            end
        end

        local maximumVertical = math.max(0, #rows - TABLE_VISIBLE_ROWS)
        local maximumHorizontal = math.max(
            0,
            (#currencies * CURRENCY_COLUMN_WIDTH) - TABLE_VIEW_WIDTH
        )
        verticalSlider:SetMinMaxValues(0, maximumVertical)
        horizontalSlider:SetMinMaxValues(0, maximumHorizontal)
        verticalSlider:SetValue(0)
        horizontalSlider:SetValue(
            math.min(horizontalSlider:GetValue(), maximumHorizontal)
        )
        verticalSlider:SetShown(maximumVertical > 0)
        horizontalSlider:SetShown(maximumHorizontal > 0)
        Render()
    end

    verticalSlider:SetScript("OnValueChanged", Render)
    horizontalSlider:SetScript("OnValueChanged", Render)
    body:EnableMouseWheel(true)
    body:SetScript("OnMouseWheel", function(_, delta)
        local minimum, maximum = verticalSlider:GetMinMaxValues()
        local value = verticalSlider:GetValue() + delta
        verticalSlider:SetValue(math.max(minimum, math.min(maximum, value)))
    end)

    return view
end

local function FindOptionLabel(options, value)
    for _, option in ipairs(options) do
        if option.value == value then
            return option.label
        end
    end

    return value
end

local function CreateOverviewPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    local selectedCharacter
    local selectedPeriod = "30"
    local selectedGrouping = "entry"
    local characterOptions = {}

    CreateLabel(panel, "Character", { "TOPLEFT", 0, -8 })
    CreateLabel(panel, "Period", { "TOPLEFT", 188, -8 })
    CreateLabel(panel, "Grouping", { "TOPLEFT", 365, -8 })

    local characterDropdown
    local periodDropdown
    local groupingDropdown
    local overviewTable
    local emptyMessage = CreateLabel(
        panel,
        "",
        { "CENTER", 0, -20 },
        "GameFontDisable"
    )

    local function RefreshTable()
        InitialiseSettings()
        local registered = GetRegisteredCurrencies()
        local currencies = {}

        for _, currencyID in ipairs(
            CurrencyTrackerDB.displayedCurrencyIds
        ) do
            table.insert(
                currencies,
                GetCurrencyDetails(currencyID, registered)
            )
        end

        local entries = selectedCharacter
            and GetCharacterEntries(selectedCharacter)
            or {}
        local rows = BuildOverviewRows(
            entries,
            selectedPeriod,
            selectedGrouping,
            CurrencyTrackerDB.displayedCurrencyIds
        )

        overviewTable:SetData(rows, currencies)

        local hasTableData = #currencies > 0
            and selectedCharacter ~= nil
            and #rows > 0
        overviewTable.frame:SetShown(hasTableData)

        if #currencies == 0 then
            emptyMessage:SetText(
                "No currencies selected. Choose currencies on the Setup tab."
            )
            emptyMessage:Show()
        elseif not selectedCharacter then
            emptyMessage:SetText("No characters have been registered yet.")
            emptyMessage:Show()
        elseif #rows == 0 then
            emptyMessage:SetText("No entries match the selected period.")
            emptyMessage:Show()
        else
            emptyMessage:Hide()
        end
    end

    characterDropdown = CreateDropdown(
        panel,
        145,
        { "TOPLEFT", -16, -24 },
        function()
            return characterOptions
        end,
        function(value)
            selectedCharacter = value
            RefreshTable()
        end
    )
    periodDropdown = CreateDropdown(
        panel,
        135,
        { "TOPLEFT", 172, -24 },
        function()
            return PERIOD_OPTIONS
        end,
        function(value)
            selectedPeriod = value
            RefreshTable()
        end
    )
    groupingDropdown = CreateDropdown(
        panel,
        160,
        { "TOPLEFT", 349, -24 },
        function()
            return GROUP_OPTIONS
        end,
        function(value)
            selectedGrouping = value
            RefreshTable()
        end
    )
    periodDropdown:SetSelectedValue(
        selectedPeriod,
        FindOptionLabel(PERIOD_OPTIONS, selectedPeriod)
    )
    groupingDropdown:SetSelectedValue(
        selectedGrouping,
        FindOptionLabel(GROUP_OPTIONS, selectedGrouping)
    )

    overviewTable = CreateOverviewTable(panel)

    function panel:Refresh()
        local names = GetCharacters()
        characterOptions = {}

        for _, name in ipairs(names) do
            table.insert(characterOptions, { value = name, label = name })
        end

        local currentCharacter = UnitName("player")
        local selectedExists = false

        for _, name in ipairs(names) do
            if name == selectedCharacter then
                selectedExists = true
                break
            end
        end

        if not selectedExists then
            selectedCharacter = nil

            for _, name in ipairs(names) do
                if name == currentCharacter then
                    selectedCharacter = name
                    break
                end
            end

            selectedCharacter = selectedCharacter or names[1]
        end

        characterDropdown:SetSelectedValue(
            selectedCharacter,
            selectedCharacter or "No characters"
        )
        RefreshTable()
    end

    panel:Refresh()
    return panel
end

local function CreateCurrencyPage(parent)
    InitialiseSettings()
    local page = CreateFrame("Frame", nil, parent)
    local activePanel

    local overviewButton
    local setupButton
    local overviewPanel
    local setupPanel

    local function ShowPanel(panelName)
        local showOverview = panelName == "overview"
        overviewPanel:SetShown(showOverview)
        setupPanel:SetShown(not showOverview)

        if showOverview then
            overviewButton:LockHighlight()
            setupButton:UnlockHighlight()
            activePanel = overviewPanel
        else
            overviewButton:UnlockHighlight()
            setupButton:LockHighlight()
            activePanel = setupPanel
        end

        activePanel:Refresh()
    end

    overviewButton = CreateButton(
        page,
        "Overview",
        110,
        { "TOPLEFT", 0, -2 },
        function()
            ShowPanel("overview")
        end
    )
    setupButton = CreateButton(
        page,
        "Setup",
        110,
        { "LEFT", overviewButton, "RIGHT", 6, 0 },
        function()
            ShowPanel("setup")
        end
    )

    local panelContainer = CreateFrame("Frame", nil, page)
    panelContainer:SetPoint("TOPLEFT", 0, -32)
    panelContainer:SetPoint("BOTTOMRIGHT")
    overviewPanel = CreateOverviewPanel(panelContainer)
    setupPanel = CreateSetupPanel(panelContainer)
    page.Refresh = function()
        activePanel:Refresh()
    end

    ShowPanel("overview")
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
