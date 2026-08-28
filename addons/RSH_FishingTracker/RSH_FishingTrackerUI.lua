local RSH = _G.RSH

if not RSH or not RSH.RegisterPage then
    return
end

local DUNDUN_CURRENCY_ID = 3376
local ALL_CHARACTERS = "__all"
local ALL_LOCATIONS = "__all_locations"
local SUMMARY_CARD_COUNT = 4
local SUMMARY_CARD_GAP = 6
local LOOT_ROW_HEIGHT = 28

local function InitialiseDatabase()
    RSHFishingTrackerDB = RSHFishingTrackerDB or {}
    RSHFishingTrackerDB.characters =
        RSHFishingTrackerDB.characters or {}
end

local function HasFishingData(record)
    if type(record) ~= "table" then
        return false
    end

    if (tonumber(record.attempts) or 0) > 0
        or (tonumber(record.catches) or 0) > 0
        or (tonumber(record.dundun) or 0) > 0
    then
        return true
    end

    return type(record.loot) == "table" and next(record.loot) ~= nil
end

local function GetRecordsWithData()
    local records = {}

    for _, realmCharacters in pairs(RSHFishingTrackerDB.characters) do
        if type(realmCharacters) == "table" then
            for characterName, record in pairs(realmCharacters) do
                if HasFishingData(record) then
                    table.insert(records, {
                        name = record.character or characterName or "Unknown",
                        record = record,
                    })
                end
            end
        end
    end

    return records
end


local function MergeRecord(summary, record)
    summary.attempts = summary.attempts
        + (tonumber(record.attempts) or 0)
    summary.catches = summary.catches
        + (tonumber(record.catches) or 0)
    summary.dundun = summary.dundun + (tonumber(record.dundun) or 0)

    if type(record.loot) == "table" then
        for key, lootRecord in pairs(record.loot) do
            if type(lootRecord) == "table" then
                local kind = lootRecord.kind or "item"
                local id = tonumber(lootRecord.id)
                local lootKey = id and (kind .. ":" .. id) or tostring(key)
                local mergedLoot = summary.loot[lootKey]

                if not mergedLoot then
                    mergedLoot = {
                        kind = kind,
                        id = id,
                        name = lootRecord.name or "Unknown",
                        quantity = 0,
                        catches = 0,
                    }
                    summary.loot[lootKey] = mergedLoot
                end

                mergedLoot.name = lootRecord.name or mergedLoot.name
                mergedLoot.quantity = mergedLoot.quantity
                    + (tonumber(lootRecord.quantity) or 0)
                mergedLoot.catches = mergedLoot.catches
                    + (tonumber(lootRecord.catches) or 0)
            end
        end
    end

    local lastCatchTimestamp = record.lastCatch
        and tonumber(record.lastCatch.timestamp)
        or 0

    if lastCatchTimestamp > summary.lastCatchTimestamp then
        summary.lastCatchTimestamp = lastCatchTimestamp
        summary.lastCatch = record.lastCatch
        summary.lastFishingSkill = record.lastFishingSkill
            or record.lastCatch.fishingSkill
    elseif not summary.lastFishingSkill and record.lastFishingSkill then
        summary.lastFishingSkill = record.lastFishingSkill
    end
end

local function BuildSummary(selectedCharacter, selectedLocation)
    local summary = {
        attempts = 0,
        catches = 0,
        dundun = 0,
        loot = {},
        lastCatchTimestamp = 0,
    }

    for _, characterRecord in ipairs(GetRecordsWithData()) do
        if selectedCharacter == ALL_CHARACTERS
            or characterRecord.name == selectedCharacter
        then
            local record = characterRecord.record

            if selectedLocation == ALL_LOCATIONS then
                MergeRecord(summary, record)
            elseif type(record.locations) == "table" then
                local locationRecord = record.locations[selectedLocation]

                if locationRecord then
                    MergeRecord(summary, locationRecord)
                end
            end
        end
    end

    return summary
end

local function FormatNumber(value)
    value = tonumber(value) or 0
    return BreakUpLargeNumbers and BreakUpLargeNumbers(value)
        or tostring(value)
end

local function FormatRate(part, total)
    if total <= 0 then
        return "0.00%"
    end

    return string.format("%.2f%%", part * 100 / total)
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

local function CreateSummaryCard(parent, titleText)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetHeight(62)
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    card:SetBackdropColor(0.05, 0.05, 0.05, 0.78)
    card:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    card.title = CreateLabel(
        card,
        titleText,
        { "TOP", 0, -9 },
        "GameFontNormalSmall"
    )
    card.value = CreateLabel(
        card,
        "0",
        { "BOTTOM", 0, 10 },
        "GameFontHighlightLarge"
    )
    return card
end

local function GetLootIcon(lootRecord)
    if lootRecord.kind == "currency" then
        local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(lootRecord.id)
        return currencyInfo and currencyInfo.iconFileID
    end

    return lootRecord.id and C_Item.GetItemIconByID(lootRecord.id)
end

local function ShowLootTooltip(button)
    local lootRecord = button.lootRecord

    if not lootRecord then
        return
    end

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")

    if lootRecord.kind == "item" and lootRecord.id then
        GameTooltip:SetHyperlink("item:" .. lootRecord.id)
    else
        GameTooltip:SetText(lootRecord.name or "Unknown")
        GameTooltip:AddLine(
            "Currency ID: " .. tostring(lootRecord.id or "Unknown"),
            1,
            1,
            1
        )
    end

    GameTooltip:Show()
end

local function CreateHeaderButton(parent, text, anchor, width, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint(unpack(anchor))
    button:SetSize(width, 25)
    button.background = button:CreateTexture(nil, "BACKGROUND")
    button.background:SetAllPoints()
    button.background:SetColorTexture(0.18, 0.18, 0.18, 1)
    button.text = CreateLabel(
        button,
        text,
        { "LEFT", 5, 0 },
        "GameFontNormalSmall"
    )
    button:SetHighlightTexture(
        "Interface\\QuestFrame\\UI-QuestTitleHighlight"
    )
    button:SetScript("OnClick", onClick)
    return button
end

local function CreateLootTable(parent, onSort)
    local tableFrame = CreateFrame("Frame", nil, parent)
    tableFrame:SetPoint("TOPLEFT", 0, -225)
    tableFrame:SetPoint("BOTTOMRIGHT")

    local header = CreateFrame("Frame", nil, tableFrame)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT", -24, 0)
    header:SetHeight(25)

    local iconHeader = CreateHeaderButton(
        header,
        "",
        { "TOPLEFT" },
        32,
        function()
        end
    )
    local nameHeader = CreateHeaderButton(
        header,
        "Loot",
        { "TOPLEFT", iconHeader, "TOPRIGHT", 1, 0 },
        100,
        function()
            onSort("name")
        end
    )
    nameHeader:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -235, 0)
    local quantityHeader = CreateHeaderButton(
        header,
        "Quantity",
        { "TOPLEFT", nameHeader, "TOPRIGHT", 1, 0 },
        78,
        function()
            onSort("quantity")
        end
    )
    local catchesHeader = CreateHeaderButton(
        header,
        "Catches",
        { "TOPLEFT", quantityHeader, "TOPRIGHT", 1, 0 },
        72,
        function()
            onSort("catches")
        end
    )
    CreateHeaderButton(
        header,
        "Catch rate",
        { "TOPLEFT", catchesHeader, "TOPRIGHT", 1, 0 },
        82,
        function()
            onSort("rate")
        end
    )

    local scrollFrame = CreateFrame(
        "ScrollFrame",
        nil,
        tableFrame,
        "UIPanelScrollFrameTemplate"
    )
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, 0)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)

    local lootTable = {
        frame = tableFrame,
        scrollFrame = scrollFrame,
        content = content,
        rows = {},
    }

    function lootTable:SetLoot(lootRecords, totalCatches)
        content:SetWidth(math.max(1, scrollFrame:GetWidth()))

        for index, lootRecord in ipairs(lootRecords) do
            local row = self.rows[index]

            if not row then
                row = CreateFrame("Button", nil, content)
                row:SetHeight(LOOT_ROW_HEIGHT - 1)
                row:SetPoint("LEFT")
                row:SetPoint("RIGHT")
                row.background = row:CreateTexture(nil, "BACKGROUND")
                row.background:SetAllPoints()
                row:SetHighlightTexture(
                    "Interface\\QuestFrame\\UI-QuestTitleHighlight"
                )
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(22, 22)
                row.icon:SetPoint("LEFT", 5, 0)
                row.name = CreateLabel(
                    row,
                    "",
                    { "LEFT", 34, 0 },
                    "GameFontHighlightSmall"
                )
                row.name:SetPoint("RIGHT", -235, 0)
                row.name:SetJustifyH("LEFT")
                row.name:SetWordWrap(false)
                row.quantity = CreateLabel(
                    row,
                    "",
                    { "RIGHT", -158, 0 },
                    "GameFontHighlightSmall"
                )
                row.catches = CreateLabel(
                    row,
                    "",
                    { "RIGHT", -84, 0 },
                    "GameFontHighlightSmall"
                )
                row.rate = CreateLabel(
                    row,
                    "",
                    { "RIGHT", -6, 0 },
                    "GameFontHighlightSmall"
                )
                row:SetScript("OnEnter", ShowLootTooltip)
                row:SetScript("OnLeave", GameTooltip_Hide)
                self.rows[index] = row
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -((index - 1) * LOOT_ROW_HEIGHT))
            row:SetPoint("RIGHT")
            row.background:SetColorTexture(
                index % 2 == 0 and 0.08 or 0.04,
                index % 2 == 0 and 0.08 or 0.04,
                index % 2 == 0 and 0.08 or 0.04,
                0.75
            )
            row.lootRecord = lootRecord
            row.icon:SetTexture(
                GetLootIcon(lootRecord)
                    or "Interface\\Icons\\INV_Misc_QuestionMark"
            )
            row.name:SetText(lootRecord.name or "Unknown")
            row.quantity:SetText(FormatNumber(lootRecord.quantity))
            row.catches:SetText(FormatNumber(lootRecord.catches))
            row.rate:SetText(FormatRate(lootRecord.catches, totalCatches))
            row:Show()
        end

        for index = #lootRecords + 1, #self.rows do
            self.rows[index]:Hide()
        end

        content:SetHeight(math.max(1, #lootRecords * LOOT_ROW_HEIGHT))
        scrollFrame:SetVerticalScroll(0)
    end

    tableFrame:SetScript("OnSizeChanged", function()
        content:SetWidth(math.max(1, scrollFrame:GetWidth()))
    end)
    return lootTable
end

local function CreateFishingPage(parent)
    InitialiseDatabase()
    local page = CreateFrame("Frame", nil, parent)
    local selectedCharacter
    local selectedLocation = ALL_LOCATIONS
    local characterOptions = {}
    local locationOptions = {}
    local sortKey = "catches"
    local sortDescending = true
    local currentSummary

    local title = CreateLabel(
        page,
        "Fishing",
        { "TOPLEFT", 0, -7 },
        "GameFontNormalHuge"
    )
    CreateLabel(page, "Character", {
        "TOPLEFT", title, "BOTTOMLEFT", 0, -12,
    })
    CreateLabel(page, "Zone", {
        "TOPLEFT", title, "BOTTOMLEFT", 210, -12,
    })

    local characterDropdown
    local locationDropdown
    local lootTable
    local emptyMessage = CreateLabel(
        page,
        "No characters have recorded fishing data yet.",
        { "CENTER", 0, -20 },
        "GameFontDisable"
    )
    local cards = {
        CreateSummaryCard(page, "Attempts"),
        CreateSummaryCard(page, "Catches"),
        CreateSummaryCard(page, "Catch rate"),
        CreateSummaryCard(page, "Fishing skill"),
    }

    cards[1]:SetPoint("TOPLEFT", 0, -82)

    for index = 2, #cards do
        cards[index]:SetPoint(
            "LEFT",
            cards[index - 1],
            "RIGHT",
            SUMMARY_CARD_GAP,
            0
        )
    end

    local dundunFrame = CreateFrame(
        "Frame",
        nil,
        page,
        "BackdropTemplate"
    )
    dundunFrame:SetPoint("TOPLEFT", 0, -151)
    dundunFrame:SetPoint("TOPRIGHT")
    dundunFrame:SetHeight(48)
    dundunFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    dundunFrame:SetBackdropColor(0.08, 0.12, 0.18, 0.82)
    dundunFrame:SetBackdropBorderColor(0.25, 0.55, 0.85, 1)
    local dundunIcon = dundunFrame:CreateTexture(nil, "ARTWORK")
    dundunIcon:SetSize(30, 30)
    dundunIcon:SetPoint("LEFT", 10, 0)
    local dundunInfo = C_CurrencyInfo.GetCurrencyInfo(DUNDUN_CURRENCY_ID)
    dundunIcon:SetTexture(
        dundunInfo and dundunInfo.iconFileID
            or "Interface\\Icons\\INV_Misc_QuestionMark"
    )
    local dundunTitle = CreateLabel(
        dundunFrame,
        dundunInfo and dundunInfo.name or "Shard of Dundun",
        { "TOPLEFT", dundunIcon, "TOPRIGHT", 8, -4 },
        "GameFontNormal"
    )
    local dundunText = CreateLabel(
        dundunFrame,
        "",
        { "TOPLEFT", dundunTitle, "BOTTOMLEFT", 0, -3 },
        "GameFontHighlightSmall"
    )

    local lastCatchText = CreateLabel(
        page,
        "",
        { "TOPLEFT", dundunFrame, "BOTTOMLEFT", 2, -7 },
        "GameFontHighlightSmall"
    )
    lastCatchText:SetPoint("RIGHT", page, "RIGHT", -2, 0)
    lastCatchText:SetJustifyH("LEFT")

    local function GetSortedLoot(summary)
        local lootRecords = {}

        for _, lootRecord in pairs(summary.loot) do
            table.insert(lootRecords, lootRecord)
        end

        table.sort(lootRecords, function(left, right)
            local leftValue
            local rightValue

            if sortKey == "name" then
                leftValue = string.lower(left.name or "")
                rightValue = string.lower(right.name or "")
            elseif sortKey == "rate" then
                leftValue = left.catches or 0
                rightValue = right.catches or 0
            else
                leftValue = tonumber(left[sortKey]) or 0
                rightValue = tonumber(right[sortKey]) or 0
            end

            if leftValue == rightValue then
                return string.lower(left.name or "")
                    < string.lower(right.name or "")
            end

            if sortDescending then
                return leftValue > rightValue
            end

            return leftValue < rightValue
        end)
        return lootRecords
    end

    local function RefreshLootTable()
        if currentSummary then
            lootTable:SetLoot(
                GetSortedLoot(currentSummary),
                currentSummary.catches
            )
        end
    end

    lootTable = CreateLootTable(page, function(newSortKey)
        if sortKey == newSortKey then
            sortDescending = not sortDescending
        else
            sortKey = newSortKey
            sortDescending = newSortKey ~= "name"
        end

        RefreshLootTable()
    end)

    local function RefreshSummary()
        currentSummary = selectedCharacter
            and BuildSummary(selectedCharacter, selectedLocation)

        if not currentSummary then
            emptyMessage:Show()
            lootTable.frame:Hide()
            dundunFrame:Hide()
            lastCatchText:Hide()

            for _, card in ipairs(cards) do
                card:Hide()
            end

            return
        end

        emptyMessage:Hide()
        lootTable.frame:Show()
        dundunFrame:Show()
        lastCatchText:Show()

        for _, card in ipairs(cards) do
            card:Show()
        end

        cards[1].value:SetText(FormatNumber(currentSummary.attempts))
        cards[2].value:SetText(FormatNumber(currentSummary.catches))
        cards[3].value:SetText(FormatRate(
            currentSummary.catches,
            currentSummary.attempts
        ))

        if selectedCharacter == ALL_CHARACTERS then
            cards[4].value:SetText("Multiple")
        else
            local skill = currentSummary.lastFishingSkill
            cards[4].value:SetText(
                skill and string.format(
                    "%d / %d",
                    tonumber(skill.skillLevel) or 0,
                    tonumber(skill.maxSkillLevel) or 0
                ) or "-"
            )
        end

        local dundunLoot = currentSummary.loot[
            "currency:" .. DUNDUN_CURRENCY_ID
        ]
        local dundunCatches = dundunLoot
            and (tonumber(dundunLoot.catches) or 0)
            or 0
        local averageText = currentSummary.dundun > 0
            and string.format(
                "1 per %.1f catches",
                currentSummary.catches / currentSummary.dundun
            )
            or "no drops yet"
        dundunText:SetText(string.format(
            "%s total  -  %s catch rate  -  %s",
            FormatNumber(currentSummary.dundun),
            FormatRate(dundunCatches, currentSummary.catches),
            averageText
        ))

        if currentSummary.lastCatch then
            local timestamp = tonumber(currentSummary.lastCatch.timestamp) or 0
            local mapInfo = currentSummary.lastCatch.mapID
                and C_Map.GetMapInfo(currentSummary.lastCatch.mapID)
            lastCatchText:SetText(string.format(
                "Last catch: %s%s",
                timestamp > 0 and date("%d-%m-%Y %H:%M", timestamp) or "-",
                mapInfo and ("  -  " .. mapInfo.name) or ""
            ))
        else
            lastCatchText:SetText("Last catch: -")
        end

        RefreshLootTable()
    end

    characterDropdown = CreateDropdown(
        page,
        165,
        { "TOPLEFT", -16, -42 },
        function()
            return characterOptions
        end,
        function(value)
            selectedCharacter = value
            page:Refresh()
        end
    )

    locationDropdown = CreateDropdown(
        page,
        165,
        { "TOPLEFT", 194, -42 },
        function()
            return locationOptions
        end,
        function(value)
            selectedLocation = value
            RefreshSummary()
        end
    )

    function page:Refresh()
        InitialiseDatabase()
        local records = GetRecordsWithData()
        local names = {}
        local seen = {}

        for _, characterRecord in ipairs(records) do
            if not seen[characterRecord.name] then
                seen[characterRecord.name] = true
                table.insert(names, characterRecord.name)
            end
        end

        table.sort(names, function(left, right)
            return string.lower(left) < string.lower(right)
        end)
        characterOptions = {}

        if #names > 0 then
            table.insert(characterOptions, {
                value = ALL_CHARACTERS,
                label = "All characters",
            })
        end

        for _, name in ipairs(names) do
            table.insert(characterOptions, { value = name, label = name })
        end

        local selectedExists = selectedCharacter == ALL_CHARACTERS
            and #names > 0

        for _, name in ipairs(names) do
            if name == selectedCharacter then
                selectedExists = true
                break
            end
        end

        if not selectedExists then
            local currentCharacter = UnitName("player")
            selectedCharacter = seen[currentCharacter]
                and currentCharacter
                or names[1]
        end

        local selectedLabel = selectedCharacter == ALL_CHARACTERS
            and "All characters"
            or selectedCharacter
            or "No characters"
        characterDropdown:SetSelectedValue(
            selectedCharacter,
            selectedLabel
        )

        local locations = {}

        for _, characterRecord in ipairs(records) do
            if selectedCharacter == ALL_CHARACTERS
                or characterRecord.name == selectedCharacter
            then
                for key, locationRecord in pairs(
                    characterRecord.record.locations or {}
                ) do
                    if HasFishingData(locationRecord) then
                        locations[key] = locationRecord.name
                            or (locationRecord.mapID
                                and C_Map.GetMapInfo(locationRecord.mapID)
                                and C_Map.GetMapInfo(locationRecord.mapID).name)
                            or "Unknown location"
                    end
                end
            end
        end

        local locationKeys = {}

        for key in pairs(locations) do
            table.insert(locationKeys, key)
        end

        table.sort(locationKeys, function(left, right)
            return string.lower(locations[left])
                < string.lower(locations[right])
        end)
        locationOptions = {
            { value = ALL_LOCATIONS, label = "All zones" },
        }

        for _, key in ipairs(locationKeys) do
            table.insert(locationOptions, {
                value = key,
                label = locations[key],
            })
        end

        local selectedLocationExists = selectedLocation == ALL_LOCATIONS

        if not selectedLocationExists then
            selectedLocationExists = locations[selectedLocation] ~= nil
        end

        if not selectedLocationExists then
            selectedLocation = ALL_LOCATIONS
        end

        locationDropdown:SetSelectedValue(
            selectedLocation,
            selectedLocation == ALL_LOCATIONS
                and "All zones"
                or locations[selectedLocation]
        )
        RefreshSummary()
    end

    page:SetScript("OnSizeChanged", function()
        local availableWidth = page:GetWidth()
            - ((SUMMARY_CARD_COUNT - 1) * SUMMARY_CARD_GAP)
        local cardWidth = math.max(100, availableWidth / SUMMARY_CARD_COUNT)

        for _, card in ipairs(cards) do
            card:SetWidth(cardWidth)
        end
    end)

    page:Refresh()
    return page
end

RSH:RegisterPage({
    id = "fishing",
    title = "Fishing",
    order = 20,
    create = CreateFishingPage,
    onShow = function(page)
        page:Refresh()
    end,
})
