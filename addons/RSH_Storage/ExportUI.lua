local addonName, addon = ...

local sharedPage
local standaloneWindow
local exportWindow

local function CreateScrollText(parent)
    local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    border:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    border:SetBackdropColor(0.02, 0.02, 0.02, 0.9)
    local scroll = CreateFrame(
        "ScrollFrame", nil, border, "UIPanelScrollFrameTemplate"
    )
    scroll:SetPoint("TOPLEFT", 7, -7)
    scroll:SetPoint("BOTTOMRIGHT", -27, 7)
    local text = CreateFrame("EditBox", nil, scroll)
    text:SetMultiLine(true)
    text:SetAutoFocus(false)
    text:SetFontObject(ChatFontNormal)
    text:SetWidth(500)
    text:SetTextInsets(4, 4, 4, 4)
    local measure = parent:CreateFontString(nil, "ARTWORK", "ChatFontNormal")
    measure:SetWidth(500)
    measure:SetWordWrap(true)
    text:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    text:SetScript("OnTextChanged", function(self)
        measure:SetText(self:GetText() or "")
        self:SetHeight(math.max(1, measure:GetStringHeight() + 12))
    end)
    border:SetScript("OnSizeChanged", function(self, width)
        local textWidth = math.max(100, width - 38)
        text:SetWidth(textWidth)
        measure:SetWidth(textWidth)
    end)
    scroll:SetScrollChild(text)
    border.EditBox = text
    return border
end

local function CreateButton(parent, label, width, point, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetPoint(unpack(point))
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    return button
end

local function CreateCharacterList(parent)
    local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    border:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    border:SetBackdropColor(0.03, 0.03, 0.03, 0.8)
    local scroll = CreateFrame(
        "ScrollFrame", nil, border, "UIPanelScrollFrameTemplate"
    )
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -27, 6)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(250, 1)
    scroll:SetScrollChild(content)
    border.rows = {}

    function border:Refresh()
        local characters = addon:SynchronizeConsideredCharacters()
        local realms = {}
        for _, character in ipairs(characters) do
            if character.realm and character.realm ~= "" then
                realms[character.realm] = true
            end
        end
        local realmCount = 0
        for _ in pairs(realms) do realmCount = realmCount + 1 end
        local showRealms = realmCount > 1
        local rowHeight = showRealms and 36 or 28

        for index, character in ipairs(characters) do
            local row = self.rows[index]
            if not row then
                row = CreateFrame("Frame", nil, content)
                row:SetSize(270, rowHeight)

                row.highlight = row:CreateTexture(nil, "BACKGROUND")
                row.highlight:SetAllPoints()
                row.highlight:SetColorTexture(1, 1, 1, 0.06)
                row.highlight:Hide()
                row:SetScript("OnEnter", function(self) self.highlight:Show() end)
                row:SetScript("OnLeave", function(self) self.highlight:Hide() end)

                row.checkbox = CreateFrame(
                    "CheckButton", nil, row, "UICheckButtonTemplate"
                )
                row.checkbox:SetSize(24, 24)
                row.checkbox:SetPoint("LEFT", 2, 0)
                row.checkbox:SetScript("OnClick", function(self)
                    addon:SetCharacterConsidered(
                        self.characterKey,
                        self:GetChecked()
                    )
                end)

                row.name = row:CreateFontString(
                    nil, "OVERLAY", "GameFontHighlightSmall"
                )
                row.name:SetPoint("LEFT", row.checkbox, "RIGHT", 3, 0)
                row.name:SetWidth(105)
                row.name:SetJustifyH("LEFT")
                row.name:SetWordWrap(false)

                row.class = row:CreateFontString(
                    nil, "OVERLAY", "GameFontHighlightSmall"
                )
                row.class:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
                row.class:SetWidth(78)
                row.class:SetJustifyH("LEFT")
                row.class:SetWordWrap(false)

                row.level = row:CreateFontString(
                    nil, "OVERLAY", "GameFontHighlightSmall"
                )
                row.level:SetPoint("LEFT", row.class, "RIGHT", 4, 0)
                row.level:SetWidth(55)
                row.level:SetJustifyH("LEFT")
                row.level:SetWordWrap(false)
                self.rows[index] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -((index - 1) * rowHeight))
            row:SetHeight(rowHeight)
            row.checkbox.characterKey = character.key
            row.checkbox:SetChecked(addon:IsCharacterConsidered(character.key))
            local characterName = character.name or character.key
            if showRealms and character.realm and character.realm ~= "" then
                characterName = characterName .. "\n" .. character.realm
            end
            row.name:SetText(characterName)
            row.class:SetText(addon:SafeText(
                character.class or character.classFile
            ))
            row.level:SetText("Level " .. addon:SafeText(character.level))
            row:Show()
        end
        for index = #characters + 1, #self.rows do self.rows[index]:Hide() end
        content:SetHeight(math.max(1, #characters * rowHeight))
    end
    return border
end

local function ShowExport()
    if not exportWindow then
        exportWindow = CreateFrame(
            "Frame", addonName .. "ExportWindow", UIParent,
            "BasicFrameTemplateWithInset"
        )
        exportWindow:SetSize(760, 600)
        exportWindow:SetPoint("CENTER")
        exportWindow:SetFrameStrata("DIALOG")
        exportWindow:SetClampedToScreen(true)
        exportWindow:SetMovable(true)
        exportWindow:EnableMouse(true)
        exportWindow:RegisterForDrag("LeftButton")
        exportWindow:SetScript("OnDragStart", exportWindow.StartMoving)
        exportWindow:SetScript("OnDragStop", exportWindow.StopMovingOrSizing)
        exportWindow.TitleText:SetText("RSH Storage Export")
        local text = CreateScrollText(exportWindow)
        text:SetPoint("TOPLEFT", 10, -32)
        text:SetPoint("BOTTOMRIGHT", -10, 10)
        exportWindow.EditBox = text.EditBox
        table.insert(UISpecialFrames, exportWindow:GetName())
    end
    exportWindow.EditBox:SetText(addon:GenerateExport())
    exportWindow.EditBox:SetCursorPosition(0)
    exportWindow:Show()
    exportWindow.EditBox:SetFocus()
    exportWindow.EditBox:HighlightText()
end

local function CreatePage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Storage")

    local currentHeading = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    currentHeading:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
    currentHeading:SetText("Current Character")
    CreateButton(page, "Find Upgrades", 130,
        { "LEFT", currentHeading, "RIGHT", 12, 0 },
        function() addon:FindCurrentCharacterUpgrades() end)
    CreateButton(page, "Review Warband Gear", 175,
        { "TOPLEFT", currentHeading, "BOTTOMLEFT", 0, -12 },
        function() addon:ReviewWarbandGear() end)
    CreateButton(page, "Export", 90,
        { "TOPLEFT", currentHeading, "BOTTOMLEFT", 185, -12 }, ShowExport)

    local reviewHeading = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    reviewHeading:SetPoint("TOPLEFT", currentHeading, "BOTTOMLEFT", 0, -50)
    reviewHeading:SetText("Warband Gear Review")
    local result = CreateScrollText(page)
    result:SetPoint("TOPLEFT", reviewHeading, "BOTTOMLEFT", 0, -6)
    result:SetPoint("BOTTOMRIGHT", page, "BOTTOM", -4, 8)
    page.Result = result.EditBox

    local charactersHeading = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    charactersHeading:SetPoint("TOPLEFT", page, "TOP", 12, -52)
    charactersHeading:SetText("Characters / Settings")
    local hint = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", charactersHeading, "BOTTOMLEFT", 0, -5)
    hint:SetWidth(290)
    hint:SetJustifyH("LEFT")
    hint:SetText("Only checked characters count for KEEP and DE Candidate decisions.")
    local characters = CreateCharacterList(page)
    characters:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    characters:SetPoint("BOTTOMRIGHT", -8, 8)
    page.Characters = characters

    function page:Refresh()
        self.Characters:Refresh()
        self.Result:SetText(addon:FormatResults())
        self.Result:SetCursorPosition(0)
    end
    addon:RegisterRefreshCallback(function()
        if page:IsShown() then page:Refresh() end
    end)
    return page
end

function addon:ShowStandalone()
    if not standaloneWindow then
        standaloneWindow = CreateFrame(
            "Frame", addonName .. "Window", UIParent,
            "BasicFrameTemplateWithInset"
        )
        standaloneWindow:SetSize(900, 650)
        standaloneWindow:SetPoint("CENTER")
        standaloneWindow:SetMovable(true)
        standaloneWindow:EnableMouse(true)
        standaloneWindow:RegisterForDrag("LeftButton")
        standaloneWindow:SetScript("OnDragStart", standaloneWindow.StartMoving)
        standaloneWindow:SetScript("OnDragStop", standaloneWindow.StopMovingOrSizing)
        standaloneWindow.TitleText:SetText("RSH Storage")
        local content = CreateFrame("Frame", nil, standaloneWindow)
        content:SetPoint("TOPLEFT", 8, -28)
        content:SetPoint("BOTTOMRIGHT", -8, 8)
        standaloneWindow.Page = CreatePage(content)
        table.insert(UISpecialFrames, standaloneWindow:GetName())
    end
    standaloneWindow.Page:Refresh()
    standaloneWindow:Show()
end

if _G.RSH and _G.RSH.RegisterPage then
    _G.RSH:RegisterPage({
        id = "storage",
        title = "Storage",
        order = 60,
        create = function(parent)
            sharedPage = CreatePage(parent)
            return sharedPage
        end,
        onShow = function(page) page:Refresh() end,
    })
end
