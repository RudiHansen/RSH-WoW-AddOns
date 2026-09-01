local _, addon = ...

local function AddField(lines, name, value)
    table.insert(lines, name .. ": " .. addon:SafeString(value))
end

local function YesNo(value)
    if value == nil then
        return "Unavailable"
    end

    return value and "Yes" or "No"
end

local function FormatBindings(entry)
    if entry.bindingStatus ~= "Bound" then
        return entry.bindingStatus
    end

    return table.concat(entry.bindings, ", ")
end

local function FormatAction(action)
    if not action then
        return "Empty"
    end

    local parts = { action.type, action.name }

    if action.spellID then
        table.insert(parts, "SpellID " .. addon:SafeString(action.spellID))
    elseif action.itemID then
        table.insert(parts, "ItemID " .. addon:SafeString(action.itemID))
    elseif action.macroID then
        table.insert(parts, "MacroID " .. addon:SafeString(action.macroID))
    elseif action.equipmentSetID then
        table.insert(parts, "EquipmentSetID " .. addon:SafeString(action.equipmentSetID))
    elseif action.flyoutID then
        table.insert(parts, "FlyoutID " .. addon:SafeString(action.flyoutID))
    elseif action.mountID then
        table.insert(parts, "MountID " .. addon:SafeString(action.mountID))
    elseif action.id ~= nil then
        table.insert(parts, "ID " .. addon:SafeString(action.id))
    end

    if action.subType then
        table.insert(parts, "Subtype " .. addon:SafeString(action.subType))
    end

    return table.concat(parts, " | ")
end


local function AddCharacter(lines, character)
    table.insert(lines, "[CHARACTER]")
    AddField(lines, "Name", character.name)
    AddField(lines, "Realm", character.realm)
    AddField(lines, "Level", character.level)
    AddField(lines, "Class", character.className)
    AddField(lines, "Class file", character.classFile)
    AddField(lines, "Class ID", character.classID)
    AddField(lines, "Specialization", character.specName)
    AddField(lines, "Spec ID", character.specID)
    table.insert(lines, "")
end

local function AddActionState(lines, state)
    table.insert(lines, "[CURRENT ACTION STATE]")
    AddField(lines, "Current action bar page", state.currentPage)
    AddField(lines, "Bonus bar index", state.bonusIndex)
    AddField(lines, "Bonus bar offset", state.bonusOffset)
    AddField(lines, "Bonus bar active", YesNo(state.bonusActive))
    AddField(lines, "Override page", state.overridePage)
    AddField(lines, "Override bar active", YesNo(state.overrideActive))
    AddField(lines, "Vehicle page", state.vehiclePage)
    AddField(lines, "Vehicle bar active", YesNo(state.vehicleActive))
    AddField(lines, "Temporary shapeshift page", state.tempShapeshiftPage)
    AddField(lines, "Temporary shapeshift active", YesNo(state.tempShapeshiftActive))
    AddField(lines, "Extra action page", state.extraPage)
    AddField(lines, "Extra action bar active", YesNo(state.extraActive))
    AddField(lines, "Multi-cast page", state.multiCastPage)
    AddField(lines, "Possess bar visible", YesNo(state.possessVisible))
    AddField(lines, "Current shapeshift form index", state.shapeshiftForm)
    AddField(lines, "Current shapeshift form", state.shapeshiftFormName)
    AddField(lines, "Current shapeshift spell ID", state.shapeshiftFormSpellID)
    AddField(lines, "Mounted", YesNo(state.mounted))
    table.insert(lines, "")
end

local function AddTalents(lines, talents)
    table.insert(lines, "[TALENTS]")
    AddField(lines, "Active config ID", talents.configID)

    if talents.error then
        AddField(lines, "Status", talents.error)
    elseif #talents == 0 then
        table.insert(lines, "None selected or no selected nodes returned")
    else
        for _, talent in ipairs(talents) do
            local parts = {
                talent.name,
                "SpellID " .. addon:SafeString(talent.spellID),
                "NodeID " .. addon:SafeString(talent.nodeID),
                "EntryID " .. addon:SafeString(talent.entryID),
                "Rank " .. addon:SafeString(talent.rank)
                    .. "/" .. addon:SafeString(talent.maxRanks),
                "Type " .. (talent.passive == nil and "Unknown"
                    or talent.passive and "Passive" or "Active"),
            }

            if talent.replacesSpellID then
                table.insert(
                    parts,
                    "Replaces SpellID "
                        .. addon:SafeString(talent.replacesSpellID)
                )
            end

            table.insert(lines, table.concat(parts, " | "))
        end
    end

    table.insert(lines, "")
end

local function AddAbilities(lines, abilities)
    table.insert(lines, "[KNOWN / RELEVANT ACTIVE ABILITIES]")

    if abilities.error then
        AddField(lines, "Spellbook status", abilities.error)
    end

    if #abilities == 0 then
        table.insert(lines, "None found")
    else
        for _, ability in ipairs(abilities) do
            local parts = {
                ability.name,
                "SpellID " .. addon:SafeString(ability.spellID),
                "Source: " .. table.concat(ability.sources, ", "),
            }

            if ability.replacesSpellID then
                table.insert(
                    parts,
                    "Replaces SpellID "
                        .. addon:SafeString(ability.replacesSpellID)
                )
            end

            if ability.overrideSpellID then
                local overrideName = addon:SafeCall(
                    C_Spell.GetSpellName,
                    ability.overrideSpellID
                )
                table.insert(
                    parts,
                    "Current override "
                        .. (overrideName or "Unknown")
                        .. " (SpellID " .. ability.overrideSpellID .. ")"
                )
            end

            if ability.baseSpellID then
                table.insert(
                    parts,
                    "Base SpellID " .. ability.baseSpellID
                )
            end

            if ability.covered then
                table.insert(
                    parts,
                    "Covered: Yes via SpellID "
                        .. ability.coveredBySpellID
                        .. " (" .. ability.coveredByRelationship .. ")"
                )
            else
                table.insert(parts, "Covered: No")
            end

            table.insert(
                parts,
                "Current-state direct coverage: "
                    .. (ability.currentStateCovered and "Yes" or "No")
            )

            if ability.otherControlCoverage then
                table.insert(parts, ability.otherControlCoverage)
            end

            if ability.stateCoverageNote then
                table.insert(parts, "State note: " .. ability.stateCoverageNote)
            end

            table.insert(
                lines,
                table.concat(parts, " | ")
            )
        end
    end

    table.insert(lines, "")
end

local function AddEditMode(lines, editMode, debugEnabled)
    table.insert(lines, "[BLIZZARD ACTION BAR LAYOUT]")
    AddField(lines, "Active layout index", editMode.activeLayout)
    AddField(lines, "Layout name", editMode.layoutName)
    AddField(
        lines,
        "Layout type",
        editMode.layoutTypeName and (
            editMode.layoutTypeName
                .. " (" .. addon:SafeString(editMode.layoutType) .. ")"
        ) or editMode.layoutType
    )
    AddField(lines, "Layout source", editMode.layoutSource)
    AddField(lines, "Blizzard Edit Mode loaded", YesNo(editMode.editModeLoaded))

    if editMode.error then
        AddField(lines, "Status", editMode.error)
    end

    if #editMode.bars == 0 then
        table.insert(lines, "No action-bar systems returned")
    end

    for _, bar in ipairs(editMode.bars) do
        local includeBar = debugEnabled
            or bar.configuredEnabled ~= false

        if includeBar then
            table.insert(lines, "")
            table.insert(
                lines,
                "Bar system " .. addon:SafeString(bar.systemIndex)
                    .. " | Frame " .. addon:SafeString(bar.frameName)
            )
            table.insert(lines, "Runtime shown: " .. YesNo(bar.runtimeShown))
            table.insert(lines, "Runtime visible: " .. YesNo(bar.runtimeVisible))
            table.insert(
                lines,
                "Configured/enabled: " .. YesNo(bar.configuredEnabled)
            )
            AddField(lines, "Runtime effective scale", bar.runtimeScale)
            AddField(lines, "Configured buttons", bar.buttonCount)
            AddField(lines, "Configured rows", bar.rowCount)
            AddField(lines, "Derived columns", bar.columnCount)
            AddField(lines, "Orientation", bar.orientation)
            AddField(lines, "Icon size", bar.iconSize)
            AddField(lines, "Icon padding", bar.iconPadding)

            if bar.anchor then
                table.insert(
                    lines,
                    "Anchor: " .. addon:SafeString(bar.anchor.point)
                        .. " -> " .. addon:SafeString(bar.anchor.relativeTo)
                        .. " / " .. addon:SafeString(bar.anchor.relativePoint)
                        .. " | X " .. addon:SafeString(bar.anchor.offsetX)
                        .. " | Y " .. addon:SafeString(bar.anchor.offsetY)
                )
            else
                table.insert(lines, "Anchor: Unavailable")
            end

            if debugEnabled then
                for _, setting in ipairs(bar.settings) do
                    table.insert(
                        lines,
                        "Setting: " .. setting.name
                            .. " | ID " .. addon:SafeString(setting.id)
                            .. " | Value " .. addon:SafeString(setting.value)
                            .. (setting.decodedValue
                                and " (" .. setting.decodedValue .. ")"
                                or "")
                    )
                end
            else
                for _, setting in ipairs(bar.visibilitySettings or {}) do
                    table.insert(
                        lines,
                        setting.name .. ": "
                            .. addon:SafeString(
                                setting.decodedValue or setting.value
                            )
                    )
                end
            end
        end
    end

    table.insert(lines, "")
end

local FIXED_PAGE_SYSTEMS = {
    [3] = 4,
    [4] = 5,
    [5] = 3,
    [6] = 2,
    [13] = 6,
    [14] = 7,
    [15] = 8,
}

local function ShouldIncludePage(page, editMode, debugEnabled)
    if debugEnabled or page.active then
        return true
    end

    if not page.containsActions then
        return false
    end

    local fixedSystem = FIXED_PAGE_SYSTEMS[page.page]

    if not fixedSystem then
        return true
    end

    for _, bar in ipairs(editMode.bars or {}) do
        if bar.systemIndex == fixedSystem then
            return bar.configuredEnabled ~= false
        end
    end

    return true
end

local function AddActionPages(lines, pages, editMode, debugEnabled)
    table.insert(lines, "[ACTION BAR CONTENTS AND ALTERNATE PAGES]")

    for _, page in ipairs(pages) do
        if ShouldIncludePage(page, editMode, debugEnabled) then
            table.insert(lines, "")
            table.insert(lines, "[" .. page.name .. "]")
            AddField(lines, "Logical/page type", page.type)
            AddField(lines, "Page/index", page.page)
            table.insert(
                lines,
                "Underlying slots: " .. page.firstSlot .. "-" .. page.lastSlot
            )
            if page.activeApplicable then
                table.insert(lines, "Currently active: " .. YesNo(page.active))
            else
                table.insert(lines, "Currently active: N/A (fixed bar)")
            end
            table.insert(
                lines,
                "Contains actions: " .. YesNo(page.containsActions)
            )
            AddField(lines, "Form/state association", page.association)

            if #page.specialTypes > 0 then
                table.insert(
                    lines,
                    "Special roles: " .. table.concat(page.specialTypes, ", ")
                )
            end

            for _, entry in ipairs(page.actions) do
                if debugEnabled or entry.action then
                    table.insert(
                        lines,
                        "Button " .. entry.button
                            .. " | Slot " .. entry.slot
                            .. " | " .. FormatAction(entry.action)
                            .. " | Bind " .. FormatBindings(entry)
                            .. " | BindingCommand " .. entry.bindingCommand
                    )

                    if entry.action and entry.action.type == "macro" then
                        table.insert(lines, "  Macro body:")
                        local body = entry.action.macroBody or "Unavailable"

                        for macroLine in (body .. "\n"):gmatch("(.-)\n") do
                            table.insert(lines, "    " .. macroLine)
                        end
                    end
                end
            end
        end
    end

    table.insert(lines, "")
end

local function AddCoverage(lines, abilities)
    table.insert(lines, "[ABILITY COVERAGE]")
    table.insert(lines, "")
    table.insert(lines, "[ACTIVE ABILITIES NOT DIRECTLY ON ACTION BARS]")
    table.insert(
        lines,
        "Macros are intentionally not parsed when determining direct coverage."
    )

    if #abilities == 0 then
        table.insert(lines, "None")
    else
        for _, ability in ipairs(abilities) do
            table.insert(
                lines,
                ability.name .. " | SpellID " .. addon:SafeString(ability.spellID)
                    .. (ability.overrideSpellID
                        and " | Current override SpellID "
                            .. ability.overrideSpellID
                        or "")
                    .. (ability.baseSpellID
                        and " | Base SpellID " .. ability.baseSpellID
                        or "")
                    .. (not ability.hasReportedReplacementRelationship
                        and " | Override/base relationship: None reported by API"
                        or "")
                    .. (ability.otherControlCoverage
                        and " | " .. ability.otherControlCoverage
                        or "")
                    .. (ability.stateCoverageNote
                        and " | State note: " .. ability.stateCoverageNote
                        or "")
            )
        end
    end

    table.insert(lines, "")
end

function addon:FormatSnapshot(snapshot, debugEnabled)
    local lines = {
        "# RSH Character Snapshot",
        "Format Version: " .. snapshot.formatVersion,
        "Debug: " .. (debugEnabled and "On" or "Off"),
        "Generated: " .. (snapshot.generatedAt
            and date("%Y-%m-%d %H:%M:%S", snapshot.generatedAt)
            or "Unavailable"),
        "WoW Build: " .. self:SafeString(snapshot.build[1])
            .. " | " .. self:SafeString(snapshot.build[2])
            .. " | Interface " .. self:SafeString(snapshot.build[4]),
        "",
    }

    AddCharacter(lines, snapshot.character)
    AddActionState(lines, snapshot.actionState)
    AddTalents(lines, snapshot.talents)
    AddAbilities(lines, snapshot.abilities)
    AddEditMode(lines, snapshot.editMode, debugEnabled)
    AddActionPages(
        lines,
        snapshot.actionPages,
        snapshot.editMode,
        debugEnabled
    )
    AddCoverage(lines, snapshot.uncoveredAbilities)
    table.insert(lines, "[NOTES / LIMITATIONS]")
    if debugEnabled then
        table.insert(
            lines,
            "Empty pages are included intentionally for diagnostics."
        )
    else
        table.insert(
            lines,
            "Empty unknown pages and disabled empty bars are omitted."
        )
    end
    table.insert(lines, "Bonus-page form/state names are not guessed.")
    table.insert(
        lines,
        "The General spellbook line is excluded because Retail does not "
            .. "provide stable combat/racial classification for its mixed entries."
    )
    table.insert(
        lines,
        "Inactive override, vehicle, or temporary pages may not be "
            .. "populated by the client."
    )
    table.insert(lines, "Runtime visibility can differ from Edit Mode configuration.")
    return table.concat(lines, "\n")
end
