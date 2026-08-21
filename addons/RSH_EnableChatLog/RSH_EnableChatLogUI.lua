local RSH = _G.RSH

if not RSH or not RSH.RegisterPage then
    return
end

local function InitialiseDatabase()
    RSHChatLogDB = RSHChatLogDB or {}

    if RSHChatLogDB.enabled == nil then
        RSHChatLogDB.enabled = true
    end
end

local function CreateChatLogPage(parent)
    InitialiseDatabase()
    local page = CreateFrame("Frame", nil, parent)

    local title = page:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalHuge"
    )
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Chat Log")

    local description = page:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontHighlight"
    )
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    description:SetPoint("RIGHT", page, "RIGHT", -8, 0)
    description:SetJustifyH("LEFT")
    description:SetText(
        "Automatically write chat messages to WoWChatLog.txt. "
            .. "This setting applies to the entire account."
    )

    local enabledCheckbox = CreateFrame(
        "CheckButton",
        nil,
        page,
        "UICheckButtonTemplate"
    )
    enabledCheckbox:SetSize(26, 26)
    enabledCheckbox:SetPoint(
        "TOPLEFT",
        description,
        "BOTTOMLEFT",
        0,
        -18
    )

    local checkboxLabel = enabledCheckbox:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormal"
    )
    checkboxLabel:SetPoint("LEFT", enabledCheckbox, "RIGHT", 5, 0)
    checkboxLabel:SetText("Enable chat logging")

    local statusLabel = page:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontHighlight"
    )
    statusLabel:SetPoint(
        "TOPLEFT",
        enabledCheckbox,
        "BOTTOMLEFT",
        4,
        -16
    )

    local pathLabel = page:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontHighlightSmall"
    )
    pathLabel:SetPoint("TOPLEFT", statusLabel, "BOTTOMLEFT", 0, -14)
    pathLabel:SetText(
        "Log file: World of Warcraft/_retail_/Logs/WoWChatLog.txt"
    )

    local function Refresh()
        InitialiseDatabase()
        enabledCheckbox:SetChecked(RSHChatLogDB.enabled)

        if LoggingChat() then
            statusLabel:SetText("|cff00ff00Current status: Enabled|r")
        else
            statusLabel:SetText("|cffff5555Current status: Disabled|r")
        end
    end

    enabledCheckbox:SetScript("OnClick", function(button)
        RSHChatLogDB.enabled = button:GetChecked() == true
        LoggingChat(RSHChatLogDB.enabled)
        Refresh()
    end)

    page.Refresh = Refresh
    Refresh()
    return page
end

RSH:RegisterPage({
    id = "chat-log",
    title = "Chat Log",
    order = 30,
    create = CreateChatLogPage,
    onShow = function(page)
        page.Refresh()
    end,
})
