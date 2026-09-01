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
    VisibleSetting = "Visibility",
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

    local manager = _G.EditModeManagerFrame

    if manager and manager.GetActiveLayoutInfo then
        local activeLayout = addon:SafeCall(
            manager.GetActiveLayoutInfo,
            manager
        )

        if activeLayout then
            return activeLayout, "EditModeManagerFrame"
        end
    end

    local combinedLayouts = {}
    local presetManager = _G.EditModePresetLayoutManager

    if presetManager and presetManager.GetCopyOfPresetLayouts then
        local presetLayouts = addon:SafeCall(
            presetManager.GetCopyOfPresetLayouts,
            presetManager
        ) or {}

        for _, layout in ipairs(presetLayouts) do
            table.insert(combinedLayouts, layout)
        end
    end

    for _, layout in ipairs(layoutInfo.layouts or {}) do
        table.insert(combinedLayouts, layout)
    end

    if combinedLayouts[layoutInfo.activeLayout] then
        return combinedLayouts[layoutInfo.activeLayout], "Combined presets and saved layouts"
    end

    if layoutInfo.layouts and layoutInfo.layouts[layoutInfo.activeLayout] then
        return layoutInfo.layouts[layoutInfo.activeLayout], "C_EditMode.GetLayouts"
    end

    return nil
end

local function DecodeSettingValue(settingName, value)
    local valueEnums = {
        Orientation = Enum and Enum.ActionBarOrientation,
        Visibility = Enum and (
            Enum.ActionBarVisibleSetting
            or Enum.EditModeActionBarVisibleSetting
        ),
    }
    local valueNames = BuildEnumLookup(valueEnums[settingName])
    return valueNames[value]
end

local function EnsureEditModeLoaded()
    if _G.EditModeManagerFrame then
        return true
    end

    local loadAddOn = C_AddOns and C_AddOns.LoadAddOn or _G.LoadAddOn

    if loadAddOn then
        addon:SafeCall(loadAddOn, "Blizzard_EditMode")
    end

    return _G.EditModeManagerFrame ~= nil
end

function addon:CollectEditModeActionBars()
    local result = { bars = {} }

    if not C_EditMode or not C_EditMode.GetLayouts then
        result.error = "Edit Mode API unavailable"
        return result
    end

    result.editModeLoaded = EnsureEditModeLoaded()
    local layoutInfo = self:SafeCall(C_EditMode.GetLayouts)
    local activeLayout, layoutSource = FindActiveLayout(layoutInfo)
    result.activeLayout = layoutInfo and layoutInfo.activeLayout
    result.layoutSource = layoutSource
    result.layoutName = activeLayout and activeLayout.layoutName
    result.layoutType = activeLayout and activeLayout.layoutType
    result.layoutTypeName = activeLayout
        and BuildEnumLookup(Enum and Enum.EditModeLayoutType)[
            activeLayout.layoutType
        ]

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
            local manager = _G.EditModeManagerFrame
            local frame = manager
                and manager.GetRegisteredSystemFrame
                and self:SafeCall(
                    manager.GetRegisteredSystemFrame,
                    manager,
                    actionBarSystem,
                    systemInfo.systemIndex
                )
                or bar.frameName and _G[bar.frameName]

            if frame then
                bar.frameName = frame.GetName
                    and self:SafeCall(frame.GetName, frame)
                    or bar.frameName
                bar.runtimeShown = self:SafeCall(frame.IsShown, frame)
                bar.runtimeVisible = self:SafeCall(frame.IsVisible, frame)
                bar.runtimeScale = self:SafeCall(frame.GetEffectiveScale, frame)
                bar.configuredEnabled = bar.runtimeShown
            end

            for _, settingInfo in ipairs(systemInfo.settings or {}) do
                local setting = {
                    id = settingInfo.setting,
                    name = settingNames[settingInfo.setting]
                        or ("Setting " .. self:SafeString(settingInfo.setting)),
                    value = settingInfo.value,
                    decodedValue = DecodeSettingValue(
                        settingNames[settingInfo.setting],
                        settingInfo.value
                    ),
                }
                table.insert(bar.settings, setting)

                if setting.name == "Buttons" then
                    bar.buttonCount = setting.value
                elseif setting.name == "Rows" then
                    bar.rowCount = setting.value
                elseif setting.name == "Orientation" then
                    bar.orientation = setting.decodedValue or setting.value
                elseif setting.name == "Icon size" then
                    bar.iconSize = setting.value
                elseif setting.name == "Icon padding" then
                    bar.iconPadding = setting.value
                end

                local lowerName = string.lower(setting.name)

                if string.find(lowerName, "visibility", 1, true)
                    or string.find(lowerName, "hide", 1, true)
                    or string.find(lowerName, "show", 1, true)
                then
                    bar.visibilitySettings = bar.visibilitySettings or {}
                    table.insert(bar.visibilitySettings, setting)
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
