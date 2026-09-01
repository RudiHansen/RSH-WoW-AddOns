local _, addon = ...

local ACTION_BAR_FRAMES = {
    [1] = "MainActionBar",
    [2] = "MultiBarBottomLeft",
    [3] = "MultiBarBottomRight",
    [4] = "MultiBarRight",
    [5] = "MultiBarLeft",
    [6] = "MultiBar5",
    [7] = "MultiBar6",
    [8] = "MultiBar7",
}

local SETTING_NAMES = {
    Orientation = "Orientation",
    NumRows = "Rows",
    NumIcons = "Buttons",
    IconSize = "Icon size",
    IconPadding = "Icon padding",
    HideBarArt = "Hide bar art",
    HideBarScrolling = "Hide bar scrolling",
    AlwaysShowButtons = "Always show buttons",
    Visibility = "Visibility",
}

local function BuildEnumLookup(enumTable, preferredNames)
    local lookup = {}

    for enumName, enumValue in pairs(enumTable or {}) do
        lookup[enumValue] = preferredNames and preferredNames[enumName]
            or enumName
    end

    return lookup
end

local function FindActiveLayout(layoutInfo)
    if not layoutInfo then
        return nil
    end

    for _, collectionName in ipairs({ "layouts", "accountLayouts", "characterLayouts" }) do
        for _, layout in ipairs(layoutInfo[collectionName] or {}) do
            if layout.layoutIndex == layoutInfo.activeLayout
                or layout.layoutID == layoutInfo.activeLayout
            then
                return layout
            end
        end
    end

    if layoutInfo.layouts and layoutInfo.layouts[layoutInfo.activeLayout] then
        return layoutInfo.layouts[layoutInfo.activeLayout]
    end

    return nil
end

function addon:CollectEditModeActionBars()
    local result = { bars = {} }

    if not C_EditMode or not C_EditMode.GetLayouts then
        result.error = "Edit Mode API unavailable"
        return result
    end

    local layoutInfo = self:SafeCall(C_EditMode.GetLayouts)
    local activeLayout = FindActiveLayout(layoutInfo)
    result.activeLayout = layoutInfo and layoutInfo.activeLayout
    result.layoutName = activeLayout and activeLayout.layoutName
    result.layoutType = activeLayout and activeLayout.layoutType

    if not activeLayout then
        result.error = "Active Edit Mode layout could not be resolved"
        return result
    end

    local actionBarSystem = Enum and Enum.EditModeSystem
        and Enum.EditModeSystem.ActionBar
    local settingNames = BuildEnumLookup(
        Enum and Enum.EditModeActionBarSetting,
        SETTING_NAMES
    )

    for _, systemInfo in ipairs(activeLayout.systems or {}) do
        if systemInfo.system == actionBarSystem then
            local bar = {
                systemIndex = systemInfo.systemIndex,
                frameName = ACTION_BAR_FRAMES[systemInfo.systemIndex],
                anchor = systemInfo.anchorInfo,
                settings = {},
            }
            local frame = bar.frameName and _G[bar.frameName]

            if frame then
                bar.runtimeShown = self:SafeCall(frame.IsShown, frame)
                bar.runtimeVisible = self:SafeCall(frame.IsVisible, frame)
                bar.runtimeScale = self:SafeCall(frame.GetEffectiveScale, frame)
            end

            for _, settingInfo in ipairs(systemInfo.settings or {}) do
                local setting = {
                    id = settingInfo.setting,
                    name = settingNames[settingInfo.setting]
                        or ("Setting " .. self:SafeString(settingInfo.setting)),
                    value = settingInfo.value,
                }
                table.insert(bar.settings, setting)

                if setting.name == "Buttons" then
                    bar.buttonCount = setting.value
                elseif setting.name == "Rows" then
                    bar.rowCount = setting.value
                end
            end

            if type(bar.buttonCount) == "number"
                and type(bar.rowCount) == "number"
                and bar.rowCount > 0
            then
                bar.columnCount = math.ceil(bar.buttonCount / bar.rowCount)
            end

            table.sort(bar.settings, function(left, right)
                return (left.id or 0) < (right.id or 0)
            end)
            table.insert(result.bars, bar)
        end
    end

    table.sort(result.bars, function(left, right)
        return (left.systemIndex or 0) < (right.systemIndex or 0)
    end)
    return result
end
