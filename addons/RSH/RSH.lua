local RSH = _G.RSH or {}
_G.RSH = RSH

local WINDOW_WIDTH = 760
local WINDOW_HEIGHT = 500
local NAVIGATION_WIDTH = 150
local MINIMAP_BUTTON_RADIUS = 80
local pages = {}
local pageByID = {}
local navigationButtons = {}
local mainFrame
local contentFrame
local selectedPageID

RSHDB = RSHDB or {}
RSHDB.minimapButtonAngle = RSHDB.minimapButtonAngle or 225

local function SortPages()
    table.sort(pages, function(left, right)
        if left.order == right.order then
            return left.title < right.title
        end

        return left.order < right.order
    end)
end

local function SetButtonSelected(button, selected)
    if selected then
        button:LockHighlight()
    else
        button:UnlockHighlight()
    end
end

local function ShowPage(pageID)
    local page = pageByID[pageID]

    if not page or not contentFrame then
        return
    end

    for _, registeredPage in ipairs(pages) do
        if registeredPage.frame then
            registeredPage.frame:Hide()
        end

        local button = navigationButtons[registeredPage.id]

        if button then
            SetButtonSelected(button, registeredPage.id == pageID)
        end
    end

    if not page.frame then
        page.frame = page.create(contentFrame)

        if not page.frame then
            error("RSH page '" .. page.id .. "' did not return a frame")
        end

        page.frame:SetAllPoints(contentFrame)
    end

    selectedPageID = pageID
    page.frame:Show()

    if page.onShow then
        page.onShow(page.frame)
    end
end

local function RefreshNavigation()
    if not mainFrame then
        return
    end

    for _, button in pairs(navigationButtons) do
        button:Hide()
    end

    SortPages()

    for index, page in ipairs(pages) do
        local button = navigationButtons[page.id]
        local pageID = page.id

        if not button then
            button = CreateFrame(
                "Button",
                nil,
                mainFrame.navigation,
                "UIPanelButtonTemplate"
            )
            button:SetHeight(28)
            button:SetScript("OnClick", function()
                ShowPage(pageID)
            end)
            navigationButtons[page.id] = button
        end

        button:SetText(page.title)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 10, -10 - ((index - 1) * 32))
        button:SetPoint("RIGHT", -10, 0)
        SetButtonSelected(button, page.id == selectedPageID)
        button:Show()
    end
end

local function CreateMainFrame()
    if mainFrame then
        return
    end

    mainFrame = CreateFrame(
        "Frame",
        "RSHMainFrame",
        UIParent,
        "BackdropTemplate"
    )
    mainFrame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })

    local title = mainFrame:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontHighlightLarge"
    )
    title:SetPoint("TOP", 0, -16)
    title:SetText("RSH")

    local closeButton = CreateFrame(
        "Button",
        nil,
        mainFrame,
        "UIPanelCloseButton"
    )
    closeButton:SetPoint("TOPRIGHT", -5, -5)

    local navigation = CreateFrame(
        "Frame",
        nil,
        mainFrame,
        "BackdropTemplate"
    )
    navigation:SetPoint("TOPLEFT", 12, -48)
    navigation:SetPoint("BOTTOMLEFT", 12, 12)
    navigation:SetWidth(NAVIGATION_WIDTH)
    navigation:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    navigation:SetBackdropColor(0.05, 0.05, 0.05, 0.65)
    mainFrame.navigation = navigation

    contentFrame = CreateFrame("Frame", nil, mainFrame)
    contentFrame:SetPoint("TOPLEFT", navigation, "TOPRIGHT", 14, 0)
    contentFrame:SetPoint("BOTTOMRIGHT", -18, 18)

    mainFrame:Hide()
    table.insert(UISpecialFrames, mainFrame:GetName())

    RefreshNavigation()

    if pages[1] then
        ShowPage(selectedPageID or pages[1].id)
    end
end

function RSH:RegisterPage(page)
    if type(page) ~= "table"
        or type(page.id) ~= "string"
        or type(page.title) ~= "string"
        or type(page.create) ~= "function"
    then
        error("RSH:RegisterPage requires id, title, and create")
    end

    if pageByID[page.id] then
        error("RSH page already registered: " .. page.id)
    end

    page.order = tonumber(page.order) or 100
    pageByID[page.id] = page
    table.insert(pages, page)
    RefreshNavigation()

    if mainFrame and not selectedPageID then
        ShowPage(page.id)
    end
end

function RSH:Toggle()
    CreateMainFrame()

    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
    end
end

function RSH:Open(pageID)
    CreateMainFrame()

    if pageID then
        ShowPage(pageID)
    elseif not selectedPageID and pages[1] then
        ShowPage(pages[1].id)
    end

    mainFrame:Show()
end

function RSH:Close()
    if mainFrame then
        mainFrame:Hide()
    end
end

local function PositionMinimapButton(button)
    local angle = math.rad(RSHDB.minimapButtonAngle)

    button:ClearAllPoints()
    button:SetPoint(
        "CENTER",
        Minimap,
        "CENTER",
        math.cos(angle) * MINIMAP_BUTTON_RADIUS,
        math.sin(angle) * MINIMAP_BUTTON_RADIUS
    )
end

local function UpdateMinimapButtonPosition(button)
    local cursorX, cursorY = GetCursorPosition()
    local minimapX, minimapY = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()

    cursorX = cursorX / scale
    cursorY = cursorY / scale
    RSHDB.minimapButtonAngle = math.deg(math.atan2(
        cursorY - minimapY,
        cursorX - minimapX
    ))
    PositionMinimapButton(button)
end

local function CreateMinimapButton()
    local button = CreateFrame("Button", "RSHMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_01")
    button:SetHighlightTexture(
        "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
    )

    local icon = button:GetNormalTexture()
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function()
        RSH:Toggle()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("RSH")
        GameTooltip:AddLine("Click to open the RSH window.", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", UpdateMinimapButtonPosition)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    PositionMinimapButton(button)
end

function RSH_OnAddonCompartmentClick()
    RSH:Toggle()
end

SLASH_RSH1 = "/rsh"

SlashCmdList.RSH = function()
    RSH:Toggle()
end

CreateMinimapButton()
