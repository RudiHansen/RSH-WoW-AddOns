local RSH = _G.RSH

if not RSH or not RSH.RegisterPage then
    return
end

local function CreateCurrencyPage(parent)
    local page = CreateFrame("Frame", nil, parent)

    local title = page:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalHuge"
    )
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Currency")

    local description = page:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontHighlight"
    )
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
    description:SetPoint("RIGHT", page, "RIGHT", -8, 0)
    description:SetJustifyH("LEFT")
    description:SetText(
        "Currency Tracker is active. Currency history will be shown here."
    )

    return page
end

RSH:RegisterPage({
    id = "currency",
    title = "Currency",
    order = 10,
    create = CreateCurrencyPage,
})
