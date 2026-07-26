#!/usr/bin/env lua5.4

-- RSH Currency Tracker report
-- Reads the SavedVariables file created by the RSH Currency Tracker WoW addon
-- and prints the collected snapshots as a terminal table.

local HOME = os.getenv("HOME") or "."
local DEFAULT_FILE = HOME
    .. "/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/"
    .. "_retail_/WTF/Account/RUDIHANSEN2/SavedVariables/RSH_CurrencyTracker.lua"

local CURRENCIES = {
    { name = "Field Accolade",       heading = "Field" },
    { name = "Adventurer Dawncrest", heading = "Adventurer" },
    { name = "Veteran Dawncrest",    heading = "Veteran" },
    { name = "Champion Dawncrest",   heading = "Champion" },
    { name = "Hero Dawncrest",       heading = "Hero" },
    { name = "Myth Dawncrest",       heading = "Myth" },
}

local function print_usage()
    print([[
Usage:
  lua5.4 RSH_CurrencyTrackerReport.lua [options] [SavedVariables-file]

Options:
  --latest              Show only the newest snapshot for each character
  --character NAME      Show only snapshots for the named character
  --oldest-first        Sort each character's snapshots oldest first (default)
  --newest-first        Sort each character's snapshots newest first
  -h, --help            Show this help

If no file is supplied, this file is used:
  ]] .. DEFAULT_FILE)
end

local function fail(message)
    io.stderr:write("RSH Currency Tracker report: " .. message .. "\n")
    os.exit(1)
end

local function parse_arguments(arguments)
    local options = {
        file = DEFAULT_FILE,
        latest = false,
        character = nil,
        oldest_first = true,
    }

    local file_was_set = false
    local index = 1

    while index <= #arguments do
        local argument = arguments[index]

        if argument == "-h" or argument == "--help" then
            print_usage()
            os.exit(0)
        elseif argument == "--latest" then
            options.latest = true
        elseif argument == "--oldest-first" then
            options.oldest_first = true
        elseif argument == "--newest-first" then
            options.oldest_first = false
        elseif argument == "--character" then
            index = index + 1
            if not arguments[index] then
                fail("--character requires a character name")
            end
            options.character = arguments[index]
        elseif argument:sub(1, 1) == "-" then
            fail("unknown option: " .. argument)
        elseif not file_was_set then
            options.file = argument
            file_was_set = true
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
        fail("could not open file:\n  " .. path .. "\n" .. tostring(open_error))
    end
    handle:close()

    -- The file is loaded in its own environment. A normal WoW SavedVariables
    -- file only assigns Lua tables, so it does not need access to globals.
    local environment = {}
    local chunk, load_error = loadfile(path, "t", environment)

    if not chunk then
        fail("could not parse the SavedVariables file:\n" .. tostring(load_error))
    end

    local ok, run_error = pcall(chunk)
    if not ok then
        fail("the SavedVariables file could not be evaluated:\n" .. tostring(run_error))
    end

    local database = environment.CurrencyTrackerDB
    if type(database) ~= "table" then
        fail("CurrencyTrackerDB was not found in the file")
    end

    if type(database.entries) ~= "table" then
        fail("CurrencyTrackerDB.entries was not found or is not a table")
    end

    return database
end

local function character_matches(actual_name, requested_name)
    if not requested_name then
        return true
    end

    return tostring(actual_name or ""):lower() == requested_name:lower()
end

local function copy_matching_entries(entries, requested_character)
    local result = {}

    for _, entry in ipairs(entries) do
        if type(entry) == "table"
            and character_matches(entry.character, requested_character)
        then
            result[#result + 1] = entry
        end
    end

    return result
end

local function timestamp_of(entry)
    return tonumber(entry.timestamp) or 0
end

local function sort_entries(entries, oldest_first)
    table.sort(entries, function(left, right)
        local left_name = tostring(left.character or "Unknown"):lower()
        local right_name = tostring(right.character or "Unknown"):lower()

        if left_name ~= right_name then
            return left_name < right_name
        end

        local left_realm = tostring(left.realm or "Unknown"):lower()
        local right_realm = tostring(right.realm or "Unknown"):lower()

        if left_realm ~= right_realm then
            return left_realm < right_realm
        end

        local left_time = timestamp_of(left)
        local right_time = timestamp_of(right)

        if left_time ~= right_time then
            if oldest_first then
                return left_time < right_time
            end

            return left_time > right_time
        end

        -- Stable-looking fallback when two snapshots have the same timestamp.
        return tostring(left.character or "") < tostring(right.character or "")
    end)
end

local function keep_latest_per_character(entries)
    local newest = {}

    for _, entry in ipairs(entries) do
        local key = tostring(entry.character or "Unknown")
            .. "-"
            .. tostring(entry.realm or "Unknown")

        local current = newest[key]
        if not current or timestamp_of(entry) > timestamp_of(current) then
            newest[key] = entry
        end
    end

    local result = {}
    for _, entry in pairs(newest) do
        result[#result + 1] = entry
    end

    return result
end

local function currency_quantity(entry, currency_name)
    if type(entry.currencies) ~= "table" then
        return nil
    end

    local value = entry.currencies[currency_name]

    if type(value) == "number" then
        return value
    end

    if type(value) ~= "table" or value.unavailable then
        return nil
    end

    return tonumber(value.quantity)
end

local function entry_key(entry)
    return tostring(entry.character or "Unknown")
        .. "-"
        .. tostring(entry.realm or "Unknown")
end

local function calculate_changes(entries)
    local chronological = {}
    for index, entry in ipairs(entries) do
        chronological[index] = entry
    end
    sort_entries(chronological, true)

    local previous_by_character = {}
    local changes = {}

    for _, entry in ipairs(chronological) do
        local key = entry_key(entry)
        local previous = previous_by_character[key]
        local entry_changes = {}

        if previous then
            for _, currency in ipairs(CURRENCIES) do
                local current_quantity = currency_quantity(entry, currency.name)
                local previous_quantity = currency_quantity(previous, currency.name)

                if current_quantity ~= nil and previous_quantity ~= nil then
                    entry_changes[currency.name] = current_quantity - previous_quantity
                end
            end
        end

        changes[entry] = entry_changes
        previous_by_character[key] = entry
    end

    return changes
end

local function currency_display(entry, currency_name, changes)
    local quantity = currency_quantity(entry, currency_name)
    if quantity == nil then
        return "-"
    end

    local delta = changes[entry] and changes[entry][currency_name]
    if delta and delta ~= 0 then
        return string.format("%d (%+d)", quantity, delta)
    end

    return tostring(quantity)
end

local function formatted_date(timestamp)
    if timestamp <= 0 then
        return "-"
    end

    return os.date("%d-%m-%Y", timestamp)
end

local function formatted_time(timestamp)
    if timestamp <= 0 then
        return "-"
    end

    return os.date("%H:%M:%S", timestamp)
end

local function make_rows(entries, changes)
    local rows = {}

    for _, entry in ipairs(entries) do
        local timestamp = timestamp_of(entry)
        local row = {
            formatted_date(timestamp),
            formatted_time(timestamp),
            tostring(entry.character or "Unknown"),
            tostring(entry.realm or "Unknown"),
        }

        for _, currency in ipairs(CURRENCIES) do
            row[#row + 1] = currency_display(entry, currency.name, changes)
        end

        rows[#rows + 1] = row
    end

    return rows
end

local function text_length(value)
    local text = tostring(value)

    if utf8 and utf8.len then
        local length = utf8.len(text)
        if length then
            return length
        end
    end

    return #text
end

local function pad(value, width, align_right)
    local text = tostring(value)
    local spaces = math.max(0, width - text_length(text))

    if align_right then
        return string.rep(" ", spaces) .. text
    end

    return text .. string.rep(" ", spaces)
end

local function print_table(rows)
    local headers = {
        "Date",
        "Time",
        "Character",
        "Realm",
    }

    for _, currency in ipairs(CURRENCIES) do
        headers[#headers + 1] = currency.heading
    end

    local numeric_from_column = 5
    local widths = {}

    for column, header in ipairs(headers) do
        widths[column] = text_length(header)
    end

    for _, row in ipairs(rows) do
        for column, value in ipairs(row) do
            widths[column] = math.max(widths[column], text_length(value))
        end
    end

    local function render_row(row)
        local cells = {}

        for column, value in ipairs(row) do
            cells[column] = pad(value, widths[column], column >= numeric_from_column)
        end

        return table.concat(cells, "  ")
    end

    print(render_row(headers))

    local separator = {}
    for column, width in ipairs(widths) do
        separator[column] = string.rep("-", width)
    end
    print(table.concat(separator, "  "))

    local previous_character_key = nil

    for _, row in ipairs(rows) do
        local character_key = tostring(row[3]) .. "\0" .. tostring(row[4])

        if previous_character_key and character_key ~= previous_character_key then
            print()
        end

        print(render_row(row))
        previous_character_key = character_key
    end
end

local options = parse_arguments(arg)
local database = load_database(options.file)
local entries = copy_matching_entries(database.entries, options.character)
local changes = calculate_changes(entries)

if options.latest then
    entries = keep_latest_per_character(entries)
end

sort_entries(entries, options.oldest_first)

if #entries == 0 then
    if options.character then
        fail("no snapshots found for character " .. options.character)
    end
    fail("no snapshots were found")
end

print_table(make_rows(entries, changes))
print(string.format("\n%d snapshot(s) from %s", #entries, options.file))
