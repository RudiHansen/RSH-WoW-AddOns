local _, addon = ...

local ACTION_BAR_FRAMES = {
    [1] = "MainActionBar", [2] = "MultiBarBottomLeft",
    [3] = "MultiBarBottomRight", [4] = "MultiBarRight",
    [5] = "MultiBarLeft", [6] = "MultiBar5",
    [7] = "MultiBar6", [8] = "MultiBar7",
}

local PREFERRED_SETTING_NAMES = {
    NumRows = "Rows", NumIcons = "Buttons", IconSize = "Icon size",
    IconPadding = "Icon padding", VisibleSetting = "Visibility",
}

local UNIT_FRAME_NAMES = {
    Player = "Player Frame", Target = "Target Frame",
    Focus = "Focus Frame", Party = "Party Frames",
    Raid = "Raid Frames", Boss = "Boss Frames",
    Arena = "Arena Frames", Pet = "Pet Frame",
}

local function BuildEnumLookup(enumTable)
    local lookup = {}
    for enumName, enumValue in pairs(enumTable or {}) do
        lookup[enumValue] = enumName
    end
    return lookup
end

local function Humanize(identifier)
    return type(identifier) == "string"
        and (identifier:gsub("(%l)(%u)", "%1 %2")) or nil
end

local function FindActiveLayout(layoutInfo)
    if not layoutInfo then return nil end
    local manager = _G.EditModeManagerFrame
    if manager and manager.GetActiveLayoutInfo then
        local layout = addon:SafeCall(manager.GetActiveLayoutInfo, manager)
        if layout then return layout, "EditModeManagerFrame" end
    end

    local combinedLayouts = {}
    local presetManager = _G.EditModePresetLayoutManager
    if presetManager and presetManager.GetCopyOfPresetLayouts then
        local presets = addon:SafeCall(
            presetManager.GetCopyOfPresetLayouts, presetManager
        ) or {}
        for _, layout in ipairs(presets) do table.insert(combinedLayouts, layout) end
    end
    for _, layout in ipairs(layoutInfo.layouts or {}) do
        table.insert(combinedLayouts, layout)
    end
    if combinedLayouts[layoutInfo.activeLayout] then
        return combinedLayouts[layoutInfo.activeLayout],
            "Combined presets and saved layouts"
    end
    if layoutInfo.layouts and layoutInfo.layouts[layoutInfo.activeLayout] then
        return layoutInfo.layouts[layoutInfo.activeLayout], "C_EditMode.GetLayouts"
    end
    return nil
end

local function EnsureEditModeLoaded()
    if _G.EditModeManagerFrame then return true end
    local loadAddOn = C_AddOns and C_AddOns.LoadAddOn or _G.LoadAddOn
    if loadAddOn then addon:SafeCall(loadAddOn, "Blizzard_EditMode") end
    return _G.EditModeManagerFrame ~= nil
end

local function GetSystemFrame(systemID, systemIndex, fallbackName)
    local manager = _G.EditModeManagerFrame
    local frame = manager and manager.GetRegisteredSystemFrame
        and addon:SafeCall(
            manager.GetRegisteredSystemFrame, manager, systemID, systemIndex
        )
    return frame or fallbackName and _G[fallbackName]
end

local function DecodeSetting(
    frame,
    settingInfo,
    settingEnumName,
    systemEnumName
)
    local displayInfo = frame and frame.settingDisplayInfoMap
        and frame.settingDisplayInfoMap[settingInfo.setting]
    local decodedValue
    if displayInfo then
        local displayTypes = Enum and Enum.EditModeSettingDisplayType
        if displayTypes and displayInfo.type == displayTypes.Checkbox then
            decodedValue = settingInfo.value == 1 and "Yes" or "No"
        elseif displayInfo.options then
            for _, option in ipairs(displayInfo.options) do
                if option.value == settingInfo.value then
                    decodedValue = option.text
                    break
                end
            end
        elseif frame.GetSettingValue then
            decodedValue = addon:SafeCall(
                frame.GetSettingValue, frame, settingInfo.setting
            )
        end
    end
    local valueEnum
    if settingEnumName == "VisibleSetting" then
        valueEnum = Enum and Enum[systemEnumName .. "VisibleSetting"]
    elseif settingEnumName == "Visibility" then
        valueEnum = Enum and Enum[systemEnumName .. "Visibility"]
    end
    local valueEnumName = BuildEnumLookup(valueEnum)[settingInfo.value]

    if decodedValue == nil and valueEnumName then
        decodedValue = Humanize(valueEnumName)
    end

    return {
        id = settingInfo.setting,
        enumName = settingEnumName,
        name = displayInfo and displayInfo.name
            or PREFERRED_SETTING_NAMES[settingEnumName]
            or Humanize(settingEnumName)
            or ("Setting " .. addon:SafeString(settingInfo.setting)),
        value = settingInfo.value,
        decodedValue = decodedValue,
        valueEnumName = valueEnumName,
    }
end

local function CollectSystem(systemInfo, systemNames)
    local systemEnumName = systemNames[systemInfo.system]
    local indexEnum = Enum and systemEnumName
        and Enum["EditMode" .. systemEnumName .. "SystemIndices"]
    local indexEnumName = BuildEnumLookup(indexEnum)[systemInfo.systemIndex]
    local fallbackName = systemEnumName == "ActionBar"
        and ACTION_BAR_FRAMES[systemInfo.systemIndex]
    local frame = GetSystemFrame(
        systemInfo.system, systemInfo.systemIndex, fallbackName
    )
    local entry = {
        systemID = systemInfo.system,
        systemType = Humanize(systemEnumName),
        systemTypeEnum = systemEnumName,
        systemIndex = systemInfo.systemIndex,
        systemIndexName = indexEnumName,
        anchor = systemInfo.anchorInfo,
        anchor2 = systemInfo.anchorInfo2,
        isInDefaultPosition = systemInfo.isInDefaultPosition,
        settings = {},
    }
    if frame then
        entry.frameName = frame.GetName
            and addon:SafeCall(frame.GetName, frame) or fallbackName
        entry.name = frame.GetSystemName
            and addon:SafeCall(frame.GetSystemName, frame)
        entry.runtimeShown = frame.IsShown
            and addon:SafeCall(frame.IsShown, frame)
        entry.runtimeVisible = frame.IsVisible
            and addon:SafeCall(frame.IsVisible, frame)
        entry.runtimeScale = frame.GetScale
            and addon:SafeCall(frame.GetScale, frame)
        entry.runtimeEffectiveScale = frame.GetEffectiveScale
            and addon:SafeCall(frame.GetEffectiveScale, frame)
    end
    entry.name = entry.name
        or (systemEnumName == "UnitFrame"
            and UNIT_FRAME_NAMES[indexEnumName])
        or (indexEnumName and Humanize(indexEnumName))
        or Humanize(systemEnumName)
        or ("Edit Mode system " .. addon:SafeString(systemInfo.system))

    local settingEnum = Enum and systemEnumName
        and Enum["EditMode" .. systemEnumName .. "Setting"]
    local settingNames = BuildEnumLookup(settingEnum)
    for _, settingInfo in ipairs(systemInfo.settings or {}) do
        local setting = DecodeSetting(
            frame,
            settingInfo,
            settingNames[settingInfo.setting],
            systemEnumName
        )
        table.insert(entry.settings, setting)
        if setting.valueEnumName == "Hidden" then
            entry.configuredEnabled = false
        elseif setting.enumName == "VisibleSetting"
            or setting.enumName == "Visibility"
        then
            entry.configuredEnabled = true
        end
        if setting.enumName == "NumIcons" then
            entry.buttonCount = setting.decodedValue or setting.value
        elseif setting.enumName == "NumRows" then
            entry.rowCount = setting.decodedValue or setting.value
        end
    end
    if type(entry.buttonCount) == "number"
        and type(entry.rowCount) == "number" and entry.rowCount > 0 then
        entry.columnCount = math.ceil(entry.buttonCount / entry.rowCount)
    end
    table.sort(entry.settings, function(left, right)
        return (left.id or 0) < (right.id or 0)
    end)
    return entry
end

function addon:CollectEditModeLayout()
    local result = { systems = {}, bars = {} }
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
        and BuildEnumLookup(Enum and Enum.EditModeLayoutType)[activeLayout.layoutType]
    if not activeLayout then
        result.error = "Active Edit Mode layout could not be resolved"
        return result
    end

    local systemNames = BuildEnumLookup(Enum and Enum.EditModeSystem)
    local actionBarSystem = Enum and Enum.EditModeSystem
        and Enum.EditModeSystem.ActionBar
    for _, systemInfo in ipairs(activeLayout.systems or {}) do
        local entry = CollectSystem(systemInfo, systemNames)
        table.insert(result.systems, entry)
        if systemInfo.system == actionBarSystem then
            -- Retained for fixed-page filtering and coverage compatibility.
            if entry.configuredEnabled == nil then
                entry.configuredEnabled = entry.runtimeShown
            end
            table.insert(result.bars, entry)
        end
    end
    local function SortSystems(left, right)
        if left.systemID ~= right.systemID then
            return (left.systemID or -1) < (right.systemID or -1)
        end
        return (left.systemIndex or 0) < (right.systemIndex or 0)
    end
    table.sort(result.systems, SortSystems)
    table.sort(result.bars, SortSystems)
    return result
end

-- Compatibility alias for callers outside this addon.
function addon:CollectEditModeActionBars()
    return self:CollectEditModeLayout()
end
