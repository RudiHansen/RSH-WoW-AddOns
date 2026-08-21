local RSH = _G.RSH

if not RSH or not RSH.RegisterPage then
    return
end

local ALL = "__all"
local STALE_AFTER_SECONDS = 7 * 24 * 60 * 60
local OVERVIEW_ROW_HEIGHT = 28

local CHARACTER_FILTER_OPTIONS = {
    { value = ALL, label = "All characters" },
}

local SHOW_FILTER_OPTIONS = {
    { value = "all", label = "All" },
    { value = "attention", label = "Needs attention" },
    { value = "knowledge", label = "Unspent knowledge" },
    { value = "skill", label = "Incomplete skill" },
    { value = "stale", label = "Stale data" },
}

local function InitialiseDatabase()
    RSHProfessionTrackerDB = RSHProfessionTrackerDB or {}
    RSHProfessionTrackerDB.characters =
        RSHProfessionTrackerDB.characters or {}
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

local function GetProfessionRows()
    local rows = {}

    for _, realmCharacters in pairs(
        RSHProfessionTrackerDB.characters
    ) do
        if type(realmCharacters) == "table" then
            for characterName, characterRecord in pairs(realmCharacters) do
                if type(characterRecord) == "table"
                    and type(characterRecord.professions) == "table"
                then
                    for professionKey, snapshot in pairs(
                        characterRecord.professions
                    ) do
                        if type(snapshot) == "table" then
                            table.insert(rows, {
                                character = characterRecord.character
                                    or characterName
                                    or "Unknown",
                                professionKey = professionKey,
                                snapshot = snapshot,
                                fusedVitality = tonumber(
                                    characterRecord.fusedVitality
                                ) or 0,
                            })
                        end
                    end
                end
            end
        end
    end

    table.sort(rows, function(left, right)
        local leftCharacter = string.lower(left.character)
        local rightCharacter = string.lower(right.character)

        if leftCharacter ~= rightCharacter then
            return leftCharacter < rightCharacter
        end

        return string.lower(left.snapshot.professionName or "")
            < string.lower(right.snapshot.professionName or "")
    end)
    return rows
end

local function IsStale(snapshot)
    local collectedAt = tonumber(snapshot.collectedAt) or 0
    return collectedAt <= 0
        or GetServerTime() - collectedAt > STALE_AFTER_SECONDS
end

local function NeedsAttention(snapshot)
    local skillLevel = tonumber(snapshot.skillLevel) or 0
    local maxSkillLevel = tonumber(snapshot.maxSkillLevel) or 0
    local availableKnowledge = tonumber(snapshot.availableKnowledge) or 0

    return availableKnowledge > 0
        or skillLevel < maxSkillLevel
        or IsStale(snapshot)
end

local function MatchesShowFilter(snapshot, showFilter)
    if showFilter == "attention" then
        return NeedsAttention(snapshot)
    elseif showFilter == "knowledge" then
        return (tonumber(snapshot.availableKnowledge) or 0) > 0
    elseif showFilter == "skill" then
        return (tonumber(snapshot.skillLevel) or 0)
            < (tonumber(snapshot.maxSkillLevel) or 0)
    elseif showFilter == "stale" then
        return IsStale(snapshot)
    end

    return true
end

local function FormatNumber(value)
    value = tonumber(value) or 0
    return BreakUpLargeNumbers and BreakUpLargeNumbers(value)
        or tostring(value)
end

local function FormatUpdated(timestamp)
    timestamp = tonumber(timestamp) or 0

    if timestamp <= 0 then
        return "Unknown"
    end

    local days = math.floor(
        math.max(0, GetServerTime() - timestamp) / (24 * 60 * 60)
    )

    if days == 0 then
        return "Today"
    elseif days == 1 then
        return "1 day ago"
    elseif days < 30 then
        return days .. " days ago"
    end

    return date("%d-%m-%Y", timestamp)
end

local function FindOptionLabel(options, value)
    for _, option in ipairs(options) do
        if option.value == value then
            return option.label
        end
    end

    return value
end

local function CreateOverviewHeader(parent, onSort)
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(26)
    local background = header:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.18, 0.18, 0.18, 1)

    local function AddColumn(text, sortKey, anchor, offset, width)
        local button = CreateFrame("Button", nil, header)

        if anchor == "LEFT" then
            button:SetPoint("TOPLEFT", offset, 0)
            button:SetPoint("BOTTOMLEFT", offset, 0)
        else
            button:SetPoint("TOPRIGHT", offset, 0)
            button:SetPoint("BOTTOMRIGHT", offset, 0)
        end

        button:SetWidth(width)
        button.text = CreateLabel(
            button,
            text,
            { "LEFT", 5, 0 },
            "GameFontNormalSmall"
        )
        button:SetHighlightTexture(
            "Interface\\QuestFrame\\UI-QuestTitleHighlight"
        )
        button:SetScript("OnClick", function()
            onSort(sortKey)
        end)
    end

    AddColumn("Character", "character", "LEFT", 0, 107)
    AddColumn("Profession", "profession", "LEFT", 107, 150)
    AddColumn("Skill", "skill", "RIGHT", -226, 78)
    AddColumn("Knowledge", "knowledge", "RIGHT", -147, 79)
    AddColumn("Vitality", "vitality", "RIGHT", -82, 65)
    AddColumn("Updated", "updated", "RIGHT", 0, 82)
    return header
end

local function CreateOverviewPanel(parent, openDetails)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    local selectedCharacter = ALL
    local selectedProfession = ALL
    local selectedShowFilter = "all"
    local selectedSortKey = "character"
    local sortDescending = false
    local characterOptions = CHARACTER_FILTER_OPTIONS
    local professionOptions = {
        { value = ALL, label = "All professions" },
    }

    CreateLabel(panel, "Character", { "TOPLEFT", 0, -7 })
    CreateLabel(panel, "Profession", { "TOPLEFT", 185, -7 })
    CreateLabel(panel, "Show", { "TOPLEFT", 370, -7 })

    local characterDropdown
    local professionDropdown
    local showDropdown
    local rows = {}

    local function ChangeSort(sortKey)
        if selectedSortKey == sortKey then
            sortDescending = not sortDescending
        else
            selectedSortKey = sortKey
            sortDescending = sortKey ~= "character"
                and sortKey ~= "profession"
        end
    end

    local header = CreateOverviewHeader(panel, function(sortKey)
        ChangeSort(sortKey)

        if panel.RefreshRows then
            panel.RefreshRows()
        end
    end)
    header:SetPoint("TOPLEFT", 0, -62)

    local scrollFrame = CreateFrame(
        "ScrollFrame",
        nil,
        panel,
        "UIPanelScrollFrameTemplate"
    )
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, 25)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)

    local hint = CreateLabel(
        panel,
        "Profession data updates when each profession window is opened.",
        { "BOTTOMLEFT", 2, 4 },
        "GameFontDisableSmall"
    )
    hint:SetPoint("RIGHT", -2, 0)
    hint:SetJustifyH("LEFT")

    local emptyMessage = CreateLabel(
        panel,
        "No profession data matches the selected filters.",
        { "CENTER", 0, -20 },
        "GameFontDisable"
    )

    local function SetRowText(row, rowData)
        local snapshot = rowData.snapshot
        local skillLevel = tonumber(snapshot.skillLevel) or 0
        local maxSkillLevel = tonumber(snapshot.maxSkillLevel) or 0
        local knowledge = tonumber(snapshot.availableKnowledge) or 0

        row.character:SetText(rowData.character)
        row.profession:SetText(snapshot.professionName or "Unknown")
        row.skill:SetText(string.format("%d/%d", skillLevel, maxSkillLevel))
        row.knowledge:SetText(FormatNumber(knowledge))
        row.vitality:SetText(FormatNumber(rowData.fusedVitality))
        row.updated:SetText(FormatUpdated(snapshot.collectedAt))
        row.skill:SetTextColor(
            skillLevel < maxSkillLevel and 1 or 0.9,
            skillLevel < maxSkillLevel and 0.75 or 0.9,
            skillLevel < maxSkillLevel and 0.15 or 0.9
        )
        row.knowledge:SetTextColor(
            knowledge > 0 and 1 or 0.9,
            knowledge > 0 and 0.82 or 0.9,
            knowledge > 0 and 0.1 or 0.9
        )
        row.updated:SetTextColor(
            IsStale(snapshot) and 1 or 0.8,
            IsStale(snapshot) and 0.45 or 0.8,
            IsStale(snapshot) and 0.3 or 0.8
        )
    end

    local function RefreshRows()
        local filteredRows = {}

        for _, rowData in ipairs(GetProfessionRows()) do
            local snapshot = rowData.snapshot

            if (selectedCharacter == ALL
                    or rowData.character == selectedCharacter)
                and (selectedProfession == ALL
                    or snapshot.professionName == selectedProfession)
                and MatchesShowFilter(snapshot, selectedShowFilter)
            then
                table.insert(filteredRows, rowData)
            end
        end

        table.sort(filteredRows, function(left, right)
            local leftSnapshot = left.snapshot
            local rightSnapshot = right.snapshot
            local leftValue
            local rightValue

            if selectedSortKey == "profession" then
                leftValue = string.lower(leftSnapshot.professionName or "")
                rightValue = string.lower(rightSnapshot.professionName or "")
            elseif selectedSortKey == "skill" then
                leftValue = tonumber(leftSnapshot.skillLevel) or 0
                rightValue = tonumber(rightSnapshot.skillLevel) or 0
            elseif selectedSortKey == "knowledge" then
                leftValue = tonumber(leftSnapshot.availableKnowledge) or 0
                rightValue = tonumber(rightSnapshot.availableKnowledge) or 0
            elseif selectedSortKey == "vitality" then
                leftValue = left.fusedVitality
                rightValue = right.fusedVitality
            elseif selectedSortKey == "updated" then
                leftValue = tonumber(leftSnapshot.collectedAt) or 0
                rightValue = tonumber(rightSnapshot.collectedAt) or 0
            else
                leftValue = string.lower(left.character)
                rightValue = string.lower(right.character)
            end

            if leftValue == rightValue then
                local leftName = left.character
                    .. (leftSnapshot.professionName or "")
                local rightName = right.character
                    .. (rightSnapshot.professionName or "")
                return leftName < rightName
            end

            if sortDescending then
                return leftValue > rightValue
            end

            return leftValue < rightValue
        end)

        content:SetWidth(math.max(1, scrollFrame:GetWidth()))

        for index, rowData in ipairs(filteredRows) do
            local row = rows[index]

            if not row then
                row = CreateFrame("Button", nil, content)
                row:SetHeight(OVERVIEW_ROW_HEIGHT - 1)
                row:SetPoint("LEFT")
                row:SetPoint("RIGHT")
                row.background = row:CreateTexture(nil, "BACKGROUND")
                row.background:SetAllPoints()
                row:SetHighlightTexture(
                    "Interface\\QuestFrame\\UI-QuestTitleHighlight"
                )
                row.character = CreateLabel(
                    row,
                    "",
                    { "LEFT", 6, 0 },
                    "GameFontHighlightSmall"
                )
                row.character:SetWidth(101)
                row.character:SetJustifyH("LEFT")
                row.character:SetWordWrap(false)
                row.profession = CreateLabel(
                    row,
                    "",
                    { "LEFT", 112, 0 },
                    "GameFontHighlightSmall"
                )
                row.profession:SetPoint("RIGHT", -310, 0)
                row.profession:SetJustifyH("LEFT")
                row.profession:SetWordWrap(false)
                row.skill = CreateLabel(
                    row,
                    "",
                    { "RIGHT", -232, 0 },
                    "GameFontHighlightSmall"
                )
                row.knowledge = CreateLabel(
                    row,
                    "",
                    { "RIGHT", -153, 0 },
                    "GameFontHighlightSmall"
                )
                row.vitality = CreateLabel(
                    row,
                    "",
                    { "RIGHT", -88, 0 },
                    "GameFontHighlightSmall"
                )
                row.updated = CreateLabel(
                    row,
                    "",
                    { "RIGHT", -7, 0 },
                    "GameFontHighlightSmall"
                )
                row:SetScript("OnClick", function(button)
                    openDetails(button.rowData)
                end)
                rows[index] = row
            end

            row:ClearAllPoints()
            row:SetPoint(
                "TOPLEFT",
                0,
                -((index - 1) * OVERVIEW_ROW_HEIGHT)
            )
            row:SetPoint("RIGHT")
            local shade = index % 2 == 0 and 0.08 or 0.04
            row.background:SetColorTexture(shade, shade, shade, 0.75)
            row.rowData = rowData
            SetRowText(row, rowData)
            row:Show()
        end

        for index = #filteredRows + 1, #rows do
            rows[index]:Hide()
        end

        content:SetHeight(math.max(1, #filteredRows * OVERVIEW_ROW_HEIGHT))
        scrollFrame:SetVerticalScroll(0)
        emptyMessage:SetShown(#filteredRows == 0)
    end

    panel.RefreshRows = RefreshRows

    characterDropdown = CreateDropdown(
        panel,
        145,
        { "TOPLEFT", -16, -24 },
        function()
            return characterOptions
        end,
        function(value)
            selectedCharacter = value
            RefreshRows()
        end
    )
    professionDropdown = CreateDropdown(
        panel,
        145,
        { "TOPLEFT", 169, -24 },
        function()
            return professionOptions
        end,
        function(value)
            selectedProfession = value
            RefreshRows()
        end
    )
    showDropdown = CreateDropdown(
        panel,
        145,
        { "TOPLEFT", 354, -24 },
        function()
            return SHOW_FILTER_OPTIONS
        end,
        function(value)
            selectedShowFilter = value
            RefreshRows()
        end
    )
    characterDropdown:SetSelectedValue(ALL, "All characters")
    professionDropdown:SetSelectedValue(ALL, "All professions")
    showDropdown:SetSelectedValue(
        selectedShowFilter,
        FindOptionLabel(SHOW_FILTER_OPTIONS, selectedShowFilter)
    )

    function panel:Refresh()
        local professionRows = GetProfessionRows()
        local characterNames = {}
        local professionNames = {}
        local seenCharacters = {}
        local seenProfessions = {}

        for _, rowData in ipairs(professionRows) do
            local professionName = rowData.snapshot.professionName or "Unknown"

            if not seenCharacters[rowData.character] then
                seenCharacters[rowData.character] = true
                table.insert(characterNames, rowData.character)
            end

            if not seenProfessions[professionName] then
                seenProfessions[professionName] = true
                table.insert(professionNames, professionName)
            end
        end

        table.sort(characterNames)
        table.sort(professionNames)
        characterOptions = {
            { value = ALL, label = "All characters" },
        }
        professionOptions = {
            { value = ALL, label = "All professions" },
        }

        for _, name in ipairs(characterNames) do
            table.insert(characterOptions, { value = name, label = name })
        end

        for _, name in ipairs(professionNames) do
            table.insert(professionOptions, { value = name, label = name })
        end

        if selectedCharacter ~= ALL
            and not seenCharacters[selectedCharacter]
        then
            selectedCharacter = ALL
            characterDropdown:SetSelectedValue(ALL, "All characters")
        end

        if selectedProfession ~= ALL
            and not seenProfessions[selectedProfession]
        then
            selectedProfession = ALL
            professionDropdown:SetSelectedValue(ALL, "All professions")
        end

        RefreshRows()
    end

    panel:SetScript("OnSizeChanged", function()
        content:SetWidth(math.max(1, scrollFrame:GetWidth()))
    end)
    return panel
end

local function GetStatName(statKey)
    local localizedName = _G[statKey]

    if localizedName and localizedName ~= "" then
        localizedName = localizedName:gsub("%%[%d%.$%+%-]*[dfs]", "")
        localizedName = localizedName:gsub("^%s*%+%s*", "")
        localizedName = localizedName:gsub("%s+", " ")
        localizedName = strtrim(localizedName)

        if localizedName ~= "" then
            return localizedName
        end
    end

    local name = statKey:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", "")
    name = name:gsub("_", " "):lower()
    return name:gsub("(%a)([%w']*)", function(firstLetter, remainder)
        return firstLetter:upper() .. remainder
    end)
end

local function GetSortedStats(stats)
    local sorted = {}

    for statKey, value in pairs(stats or {}) do
        if type(value) == "number" and value ~= 0 then
            table.insert(sorted, {
                name = GetStatName(statKey),
                value = value,
            })
        end
    end

    table.sort(sorted, function(left, right)
        return left.name < right.name
    end)
    return sorted
end

local function AddDetailLine(lines, text, style, indent)
    table.insert(lines, {
        text = text,
        style = style or "normal",
        indent = indent or 0,
    })
end

local function AddSpecializationLines(lines, path, depth)
    AddDetailLine(
        lines,
        string.format(
            "%s  %d/%d",
            path.name or "Unknown",
            tonumber(path.currentRank) or 0,
            tonumber(path.maxRank) or 0
        ),
        "normal",
        depth
    )

    for _, child in ipairs(path.children or {}) do
        AddSpecializationLines(lines, child, depth + 1)
    end
end

local function BuildDetailLines(rowData)
    local snapshot = rowData.snapshot
    local lines = {}
    AddDetailLine(lines, snapshot.professionName or "Unknown", "heading")
    AddDetailLine(
        lines,
        string.format(
            "Skill: %d/%d    Available knowledge: %d    Fused Vitality: %d",
            tonumber(snapshot.skillLevel) or 0,
            tonumber(snapshot.maxSkillLevel) or 0,
            tonumber(snapshot.availableKnowledge) or 0,
            rowData.fusedVitality
        )
    )
    AddDetailLine(
        lines,
        "Collected: "
            .. (snapshot.collectedAt
                and date("%d-%m-%Y %H:%M", snapshot.collectedAt)
                or "Unknown")
    )
    AddDetailLine(lines, "")
    AddDetailLine(lines, "Equipment", "section")

    local equipmentLabels = { "Tool", "Accessory 1", "Accessory 2" }
    local totals = {}

    for index = 1, 3 do
        local item = snapshot.equipment and snapshot.equipment[index]
            or { description = "None", stats = {} }
        AddDetailLine(
            lines,
            equipmentLabels[index] .. ": " .. (item.description or "None"),
            "normal",
            1
        )

        for _, stat in ipairs(GetSortedStats(item.stats)) do
            totals[stat.name] = (totals[stat.name] or 0) + stat.value
            AddDetailLine(
                lines,
                string.format("%s: %+.0f", stat.name, stat.value),
                "muted",
                2
            )
        end
    end

    AddDetailLine(lines, "Equipment totals", "section")
    local totalNames = {}

    for name in pairs(totals) do
        table.insert(totalNames, name)
    end

    table.sort(totalNames)

    if #totalNames == 0 then
        AddDetailLine(lines, "None", "muted", 1)
    else
        for _, name in ipairs(totalNames) do
            AddDetailLine(
                lines,
                string.format("%s: %+.0f", name, totals[name]),
                "normal",
                1
            )
        end
    end

    AddDetailLine(lines, "")
    AddDetailLine(lines, "Specializations", "section")

    if not snapshot.specializations or #snapshot.specializations == 0 then
        AddDetailLine(lines, "None", "muted", 1)
    else
        for _, specialization in ipairs(snapshot.specializations) do
            AddSpecializationLines(lines, specialization, 1)
        end
    end

    return lines
end

local function CreateDetailsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    local selectedCharacter
    local selectedProfessionKey
    local characterOptions = {}
    local professionOptions = {}
    local detailRows = {}
    local selectedRowData

    CreateLabel(panel, "Character", { "TOPLEFT", 0, -7 })
    CreateLabel(panel, "Profession", { "TOPLEFT", 205, -7 })

    local characterDropdown
    local professionDropdown

    local scrollFrame = CreateFrame(
        "ScrollFrame",
        nil,
        panel,
        "UIPanelScrollFrameTemplate"
    )
    scrollFrame:SetPoint("TOPLEFT", 0, -63)
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, 0)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)

    local emptyMessage = CreateLabel(
        panel,
        "Select a profession from Overview.",
        { "CENTER", 0, -20 },
        "GameFontDisable"
    )

    local function RenderDetails()
        local lines = selectedRowData and BuildDetailLines(selectedRowData)
            or {}
        local yOffset = 0
        content:SetWidth(math.max(1, scrollFrame:GetWidth()))

        for index, line in ipairs(lines) do
            local row = detailRows[index]

            if not row then
                row = content:CreateFontString(
                    nil,
                    "OVERLAY",
                    "GameFontHighlight"
                )
                row:SetJustifyH("LEFT")
                row:SetWordWrap(true)
                detailRows[index] = row
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 8 + (line.indent * 18), -yOffset)
            row:SetPoint("RIGHT", content, "RIGHT", -8, 0)
            row:SetText(line.text)

            if line.style == "heading" then
                row:SetFontObject(GameFontNormalLarge)
            elseif line.style == "section" then
                row:SetFontObject(GameFontNormal)
            elseif line.style == "muted" then
                row:SetFontObject(GameFontDisableSmall)
            else
                row:SetFontObject(GameFontHighlightSmall)
            end

            row:Show()
            yOffset = yOffset + math.max(18, row:GetStringHeight() + 4)
        end

        for index = #lines + 1, #detailRows do
            detailRows[index]:Hide()
        end

        content:SetHeight(math.max(1, yOffset))
        scrollFrame:SetVerticalScroll(0)
        emptyMessage:SetShown(not selectedRowData)
    end

    local function RefreshProfessionOptions()
        professionOptions = {}
        selectedRowData = nil

        for _, rowData in ipairs(GetProfessionRows()) do
            if rowData.character == selectedCharacter then
                table.insert(professionOptions, {
                    value = rowData.professionKey,
                    label = rowData.snapshot.professionName or "Unknown",
                    rowData = rowData,
                })
            end
        end

        table.sort(professionOptions, function(left, right)
            return left.label < right.label
        end)

        local selectedExists = false

        for _, option in ipairs(professionOptions) do
            if option.value == selectedProfessionKey then
                selectedExists = true
                selectedRowData = option.rowData
                break
            end
        end

        if not selectedExists then
            local firstOption = professionOptions[1]
            selectedProfessionKey = firstOption and firstOption.value
            selectedRowData = firstOption and firstOption.rowData
        end

        professionDropdown:SetSelectedValue(
            selectedProfessionKey,
            selectedRowData
                and selectedRowData.snapshot.professionName
                or "No professions"
        )
        RenderDetails()
    end

    characterDropdown = CreateDropdown(
        panel,
        165,
        { "TOPLEFT", -16, -24 },
        function()
            return characterOptions
        end,
        function(value)
            selectedCharacter = value
            selectedProfessionKey = nil
            RefreshProfessionOptions()
        end
    )
    professionDropdown = CreateDropdown(
        panel,
        200,
        { "TOPLEFT", 189, -24 },
        function()
            return professionOptions
        end,
        function(value)
            selectedProfessionKey = value

            for _, option in ipairs(professionOptions) do
                if option.value == value then
                    selectedRowData = option.rowData
                    break
                end
            end

            RenderDetails()
        end
    )

    function panel:Select(rowData)
        selectedCharacter = rowData.character
        selectedProfessionKey = rowData.professionKey
        self:Refresh()
    end

    function panel:Refresh()
        local names = {}
        local seen = {}

        for _, rowData in ipairs(GetProfessionRows()) do
            if not seen[rowData.character] then
                seen[rowData.character] = true
                table.insert(names, rowData.character)
            end
        end

        table.sort(names)
        characterOptions = {}

        for _, name in ipairs(names) do
            table.insert(characterOptions, { value = name, label = name })
        end

        if not selectedCharacter or not seen[selectedCharacter] then
            local currentCharacter = UnitName("player")
            selectedCharacter = seen[currentCharacter]
                and currentCharacter
                or names[1]
        end

        characterDropdown:SetSelectedValue(
            selectedCharacter,
            selectedCharacter or "No characters"
        )
        RefreshProfessionOptions()
    end

    panel:SetScript("OnSizeChanged", function()
        content:SetWidth(math.max(1, scrollFrame:GetWidth()))
    end)
    return panel
end

local function CreateProfessionPage(parent)
    InitialiseDatabase()
    local page = CreateFrame("Frame", nil, parent)
    local activePanel
    local overviewButton
    local detailsButton
    local overviewPanel
    local detailsPanel

    local function ShowPanel(panelName)
        local showOverview = panelName == "overview"
        overviewPanel:SetShown(showOverview)
        detailsPanel:SetShown(not showOverview)

        if showOverview then
            overviewButton:LockHighlight()
            detailsButton:UnlockHighlight()
            activePanel = overviewPanel
        else
            overviewButton:UnlockHighlight()
            detailsButton:LockHighlight()
            activePanel = detailsPanel
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
    detailsButton = CreateButton(
        page,
        "Details",
        110,
        { "LEFT", overviewButton, "RIGHT", 6, 0 },
        function()
            ShowPanel("details")
        end
    )

    local panelContainer = CreateFrame("Frame", nil, page)
    panelContainer:SetPoint("TOPLEFT", 0, -32)
    panelContainer:SetPoint("BOTTOMRIGHT")
    detailsPanel = CreateDetailsPanel(panelContainer)
    overviewPanel = CreateOverviewPanel(panelContainer, function(rowData)
        detailsPanel:Select(rowData)
        ShowPanel("details")
    end)

    page.Refresh = function()
        activePanel:Refresh()
    end

    ShowPanel("overview")
    return page
end

RSH:RegisterPage({
    id = "professions",
    title = "Professions",
    order = 40,
    create = CreateProfessionPage,
    onShow = function(page)
        page.Refresh()
    end,
})
