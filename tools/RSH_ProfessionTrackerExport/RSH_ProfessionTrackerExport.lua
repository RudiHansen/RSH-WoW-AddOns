#!/usr/bin/env lua5.4

-- Creates one text export per character from RSH Profession Tracker data.

local USER_HOME = os.getenv("HOME") or "."
local DEFAULT_INPUT = USER_HOME
    .. "/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/"
    .. "_retail_/WTF/Account/RUDIHANSEN2/SavedVariables/"
    .. "RSH_ProfessionTracker.lua"
local DEFAULT_OUTPUT = USER_HOME .. "/Nextcloud/06_Spil/Wow/Profession"

local function fail(message)
    io.stderr:write("RSH Profession Tracker Export: " .. message .. "\n")
    os.exit(1)
end

local function print_usage()
    print([[
Usage:
  lua5.4 RSH_ProfessionTrackerExport.lua [options] [SavedVariables-file]

Options:
  --output DIRECTORY    Output directory
  -h, --help            Show this help

Defaults:
  SavedVariables: ]] .. DEFAULT_INPUT .. [[

  Output:         ]] .. DEFAULT_OUTPUT)
end

local function parse_arguments(arguments)
    local options = {
        input = DEFAULT_INPUT,
        output = DEFAULT_OUTPUT,
    }
    local input_was_set = false
    local index = 1

    while index <= #arguments do
        local argument = arguments[index]

        if argument == "-h" or argument == "--help" then
            print_usage()
            os.exit(0)
        elseif argument == "--output" then
            index = index + 1
            if not arguments[index] then
                fail("--output requires a directory")
            end
            options.output = arguments[index]
        elseif argument:sub(1, 1) == "-" then
            fail("unknown option: " .. argument)
        elseif not input_was_set then
            options.input = argument
            input_was_set = true
        else
            fail("only one SavedVariables file can be supplied")
        end

        index = index + 1
    end

    return options
end

local function load_database(path)
    local handle, open_error = io.open(path, "r")

    if not handle then
        fail("could not open SavedVariables file:\n  "
            .. path .. "\n" .. tostring(open_error))
    end

    handle:close()

    local environment = {}
    local chunk, load_error = loadfile(path, "t", environment)

    if not chunk then
        fail("could not parse SavedVariables file:\n" .. tostring(load_error))
    end

    local ok, run_error = pcall(chunk)

    if not ok then
        fail("could not evaluate SavedVariables file:\n" .. tostring(run_error))
    end

    local database = environment.RSHProfessionTrackerDB

    if type(database) ~= "table" then
        fail("RSHProfessionTrackerDB was not found")
    end

    if tonumber(database.version) ~= 1 then
        fail("unsupported database version: " .. tostring(database.version))
    end

    if type(database.characters) ~= "table" then
        fail("RSHProfessionTrackerDB.characters is missing")
    end

    return database
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function ensure_directory(path)
    local result, reason, code =
        os.execute("mkdir -p -- " .. shell_quote(path))

    if result ~= true and result ~= 0 then
        fail("could not create output directory:\n  "
            .. path .. "\n" .. tostring(reason) .. " " .. tostring(code))
    end
end

local function format_timestamp(timestamp)
    timestamp = tonumber(timestamp)

    if not timestamp then
        return "Unknown"
    end

    return os.date("%Y-%m-%d %H:%M:%S", timestamp)
end

local function stat_name(stat_key)
    local name = tostring(stat_key)
        :gsub("^ITEM_MOD_", "")
        :gsub("_SHORT$", "")
        :gsub("_", " ")
        :lower()

    return name:gsub("(%a)([%w']*)", function(first_letter, remainder)
        return first_letter:upper() .. remainder
    end)
end

local function sorted_stats(stats)
    local result = {}

    for stat_key, value in pairs(stats or {}) do
        if type(value) == "number" and value ~= 0 then
            result[#result + 1] = {
                key = tostring(stat_key),
                name = stat_name(stat_key),
                value = value,
            }
        end
    end

    table.sort(result, function(left, right)
        if left.name == right.name then
            return left.key < right.key
        end

        return left.name < right.name
    end)

    return result
end

local function add_equipment_line(lines, label, item)
    item = type(item) == "table" and item or {
        description = "None",
        stats = {},
    }
    lines[#lines + 1] = "  " .. label .. ": "
        .. tostring(item.description or "None")

    for _, stat in ipairs(sorted_stats(item.stats)) do
        lines[#lines + 1] = string.format(
            "    %s: %+.0f",
            stat.name,
            stat.value
        )
    end
end

local function add_equipment_totals(lines, equipment)
    local totals = {}

    for _, item in ipairs(equipment or {}) do
        for stat_key, value in pairs(item.stats or {}) do
            if type(value) == "number" then
                totals[stat_key] = (totals[stat_key] or 0) + value
            end
        end
    end

    local stats = sorted_stats(totals)

    if #stats == 0 then
        return
    end

    lines[#lines + 1] = "Profession gear totals:"

    for _, stat in ipairs(stats) do
        lines[#lines + 1] = string.format(
            "  %s: %+.0f",
            stat.name,
            stat.value
        )
    end
end

local function add_path(lines, path, depth)
    if type(path) ~= "table" then
        return
    end

    lines[#lines + 1] = string.rep("  ", depth)
        .. string.format(
            "%s %d/%d",
            tostring(path.name or "Unknown node"),
            tonumber(path.currentRank) or 0,
            tonumber(path.maxRank) or 0
        )

    for _, child in ipairs(path.children or {}) do
        add_path(lines, child, depth + 1)
    end
end

local function add_craftable_gear(lines, recipes)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Craftable profession gear:"

    if type(recipes) ~= "table" or #recipes == 0 then
        lines[#lines + 1] = "  None"
        return
    end

    local previous_profession

    for _, recipe in ipairs(recipes) do
        if recipe.targetProfession ~= previous_profession then
            lines[#lines + 1] = "  "
                .. tostring(recipe.targetProfession or "Unknown profession")
                .. ":"
            previous_profession = recipe.targetProfession
        end

        lines[#lines + 1] = "    " .. tostring(recipe.slot or "Profession gear")
            .. ": " .. tostring(recipe.name or "Unknown recipe")
        lines[#lines + 1] = "      Rarity: "
            .. tostring(recipe.rarity or "Unknown")
        lines[#lines + 1] = "      Available qualities: "
            .. tostring(recipe.availableQualities or "Unknown")
        if recipe.bestQuality then
            lines[#lines + 1] = "      Best quality: "
                .. recipe.bestQuality
        else
            lines[#lines + 1] = "      Best quality: Unable to calculate"
        end

        if recipe.bestQuality
            and recipe.concentrationQuality
            and recipe.concentrationQuality <= recipe.bestQuality
        then
            lines[#lines + 1] =
                "      Best quality with Concentration: Not required"
        elseif recipe.concentrationQuality and recipe.concentrationCost then
            local available = tonumber(recipe.concentrationAvailable) or 0
            local cost = tonumber(recipe.concentrationCost) or 0
            local availability = available >= cost and "available" or "unavailable"

            lines[#lines + 1] = "      Best quality with Concentration: "
                .. recipe.concentrationQuality
            lines[#lines + 1] = string.format(
                "      Concentration required: %d (%s; %d available)",
                cost,
                availability,
                available
            )
        else
            lines[#lines + 1] =
                "      Best quality with Concentration: Unable to calculate"
        end
    end
end

local function add_profession(lines, snapshot)
    lines[#lines + 1] = "Profession: "
        .. tostring(snapshot.professionName or "Unknown")
    lines[#lines + 1] = "Collected: "
        .. format_timestamp(snapshot.collectedAt)
    lines[#lines + 1] = string.format(
        "Skill: %d/%d",
        tonumber(snapshot.skillLevel) or 0,
        tonumber(snapshot.maxSkillLevel) or 0
    )
    lines[#lines + 1] = "Available knowledge: "
        .. tostring(snapshot.availableKnowledge or 0)
    lines[#lines + 1] = "Gear:"

    local equipment = snapshot.equipment or {}
    add_equipment_line(lines, "Tool", equipment[1])
    add_equipment_line(lines, "Accessory 1", equipment[2])
    add_equipment_line(lines, "Accessory 2", equipment[3])
    add_equipment_totals(lines, equipment)

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Specializations:"

    if type(snapshot.specializations) ~= "table"
        or #snapshot.specializations == 0
    then
        lines[#lines + 1] = "  None"
    else
        for _, specialization in ipairs(snapshot.specializations) do
            add_path(lines, specialization, 1)
        end
    end

    add_craftable_gear(lines, snapshot.craftableGear)
end

local function sorted_professions(professions)
    local result = {}

    for _, snapshot in pairs(professions or {}) do
        if type(snapshot) == "table" then
            result[#result + 1] = snapshot
        end
    end

    table.sort(result, function(left, right)
        local left_name = tostring(left.professionName or "")
        local right_name = tostring(right.professionName or "")

        if left_name == right_name then
            return (tonumber(left.professionID) or 0)
                < (tonumber(right.professionID) or 0)
        end

        return left_name < right_name
    end)

    return result
end

local function build_export(character, realm)
    local fused_vitality = character.fusedVitality

    if fused_vitality == nil then
        fused_vitality = "Unknown"
    end

    local lines = {
        "Character: " .. tostring(character.character or "Unknown"),
        "Realm: " .. tostring(character.realm or realm or "Unknown"),
        "Resources collected: "
            .. format_timestamp(character.resourcesCollectedAt),
        "Fused Vitality: " .. tostring(fused_vitality),
        "",
    }
    local profession_count = 0

    for _, snapshot in ipairs(sorted_professions(character.professions)) do
        if profession_count > 0 then
            lines[#lines + 1] = ""
        end

        add_profession(lines, snapshot)
        profession_count = profession_count + 1
    end

    return table.concat(lines, "\n") .. "\n"
end

local function safe_filename(value)
    local name = tostring(value or "Unknown")
    name = name:gsub("[%z\1-\31/\\:*?\"<>|]", "_")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")

    if name == "" or name == "." or name == ".." then
        return "Unknown"
    end

    return name
end

local function write_atomic(path, contents)
    local temporary_path = path .. ".tmp"
    local handle, open_error = io.open(temporary_path, "wb")

    if not handle then
        fail("could not create temporary file:\n  "
            .. temporary_path .. "\n" .. tostring(open_error))
    end

    local ok, write_error = handle:write(contents)
    local close_ok, close_error = handle:close()

    if not ok or not close_ok then
        os.remove(temporary_path)
        fail("could not write file:\n  " .. path .. "\n"
            .. tostring(write_error or close_error))
    end

    local renamed, rename_error = os.rename(temporary_path, path)

    if not renamed then
        os.remove(temporary_path)
        fail("could not replace file:\n  " .. path .. "\n"
            .. tostring(rename_error))
    end
end

local function export_characters(database, output_directory)
    ensure_directory(output_directory)

    local jobs = {}

    for realm, characters in pairs(database.characters) do
        if type(characters) == "table" then
            for character_name, character in pairs(characters) do
                if type(character) == "table" then
                    jobs[#jobs + 1] = {
                        realm = tostring(realm),
                        name = tostring(character_name),
                        character = character,
                    }
                end
            end
        end
    end

    table.sort(jobs, function(left, right)
        if left.name == right.name then
            return left.realm < right.realm
        end

        return left.name < right.name
    end)

    if #jobs == 0 then
        fail("the database contains no characters")
    end

    for _, job in ipairs(jobs) do
        local filename = safe_filename(job.name)
            .. "-" .. safe_filename(job.realm) .. ".txt"
        local output_path = output_directory .. "/" .. filename
        write_atomic(output_path, build_export(job.character, job.realm))
        print("Wrote " .. output_path)
    end

    print(string.format("Exported %d character(s).", #jobs))
end

local options = parse_arguments(arg)
local database = load_database(options.input)
export_characters(database, options.output)
