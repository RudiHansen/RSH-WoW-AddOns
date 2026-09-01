local addonName, addon = ...

local exportFrame
local sharedPage

local function Populate(editBox)
    local text = addon:GenerateSnapshot(addon:IsDebugEnabled())
    editBox:SetText(text)
    editBox:SetCursorPosition(0)
end

local function CreateExportContent(parent, standaloneWindow)
    local content = CreateFrame("Frame", nil, parent)
    content:SetAllPoints()

    local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Character Snapshot")

    local hint = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    hint:SetText("Press Ctrl+A and Ctrl+C to copy")

    local debugCheckbox = CreateFrame(
        "CheckButton",
        nil,
        content,
        "UICheckButtonTemplate"
    )
    debugCheckbox:SetSize(24, 24)
    debugCheckbox:SetPoint("LEFT", hint, "RIGHT", 14, 0)
    local debugLabel = debugCheckbox:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalSmall"
    )
    debugLabel:SetPoint("LEFT", debugCheckbox, "RIGHT", 2, 0)
    debugLabel:SetText("Debug")
    debugCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Debug")
        GameTooltip:AddLine(
            "Include empty/unknown action pages and additional "
                .. "diagnostic API data.",
            1,
            1,
            1,
            true
        )
        GameTooltip:Show()
    end)
    debugCheckbox:SetScript("OnLeave", GameTooltip_Hide)

    local refreshButton = CreateFrame(
        "Button",
        nil,
        content,
        "UIPanelButtonTemplate"
    )
    refreshButton:SetSize(130, 24)
    refreshButton:SetPoint("TOPRIGHT", -8, -8)
    refreshButton:SetText("Regenerate")

    local closeButton = CreateFrame(
        "Button",
        nil,
        content,
        "UIPanelButtonTemplate"
    )
    closeButton:SetSize(90, 24)
    closeButton:SetPoint("RIGHT", refreshButton, "LEFT", -6, 0)
    closeButton:SetText("Close")

    local border = CreateFrame("Frame", nil, content, "BackdropTemplate")
    border:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -10)
    border:SetPoint("BOTTOMRIGHT", -8, 8)
    border:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    border:SetBackdropColor(0.02, 0.02, 0.02, 0.9)

    local scrollFrame = CreateFrame(
        "ScrollFrame",
        nil,
        border,
        "UIPanelScrollFrameTemplate"
    )
    scrollFrame:SetPoint("TOPLEFT", 7, -7)
    scrollFrame:SetPoint("BOTTOMRIGHT", -27, 7)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(560)
    editBox:SetTextInsets(4, 4, 4, 4)
    local textMeasure = content:CreateFontString(
        nil,
        "ARTWORK",
        "ChatFontNormal"
    )
    textMeasure:SetWidth(560)
    textMeasure:SetWordWrap(true)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnTextChanged", function(self)
        textMeasure:SetText(self:GetText() or "")
        self:SetHeight(math.max(1, textMeasure:GetStringHeight() + 12))
    end)
    scrollFrame:SetScrollChild(editBox)
    content.EditBox = editBox

    refreshButton:SetScript("OnClick", function()
        Populate(editBox)
        editBox:SetFocus()
        editBox:HighlightText()
    end)
    debugCheckbox:SetScript("OnClick", function(self)
        addon:SetDebugEnabled(self:GetChecked() == true)
        Populate(editBox)
    end)
    closeButton:SetScript("OnClick", function()
        if standaloneWindow then
            standaloneWindow:Hide()
        elseif _G.RSH and _G.RSH.Close then
            _G.RSH:Close()
        else
            content:Hide()
        end
    end)

    function content:Refresh()
        debugCheckbox:SetChecked(addon:IsDebugEnabled())
        Populate(editBox)
    end

    return content
end

local function CreateStandaloneWindow()
    local window = CreateFrame(
        "Frame",
        addonName .. "ExportWindow",
        UIParent,
        "BasicFrameTemplateWithInset"
    )
    window:SetSize(760, 600)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window.TitleText:SetText("RSH Character Snapshot")
    local content = CreateFrame("Frame", nil, window)
    content:SetPoint("TOPLEFT", 8, -28)
    content:SetPoint("BOTTOMRIGHT", -8, 8)
    window.Content = CreateExportContent(content, window)
    window:Hide()
    table.insert(UISpecialFrames, window:GetName())
    return window
end

function addon:ShowExport()
    if _G.RSH and _G.RSH.Open then
        _G.RSH:Open("character-snapshot")

        if sharedPage then
            sharedPage.EditBox:SetFocus()
            sharedPage.EditBox:HighlightText()
        end

        return
    end

    exportFrame = exportFrame or CreateStandaloneWindow()
    exportFrame.Content:Refresh()
    exportFrame:Show()
    exportFrame.Content.EditBox:SetFocus()
    exportFrame.Content.EditBox:HighlightText()
end

if _G.RSH and _G.RSH.RegisterPage then
    _G.RSH:RegisterPage({
        id = "character-snapshot",
        title = "Character Snapshot",
        order = 50,
        create = function(parent)
            sharedPage = CreateExportContent(parent)
            return sharedPage
        end,
        onShow = function(page)
            page:Refresh()
        end,
    })
end
