local addonName, addon = ...

_G.RSH_CharacterSnapshot = addon

addon.name = addonName
addon.formatVersion = 1

function addon:SafeCall(callable, ...)
    if type(callable) ~= "function" then
        return nil
    end

    local results = { pcall(callable, ...) }

    if not results[1] then
        return nil
    end

    table.remove(results, 1)
    return unpack(results)
end

function addon:IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

function addon:SafeString(value, fallback)
    if value == nil or self:IsSecret(value) then
        return fallback or "Unavailable"
    end

    local ok, text = pcall(tostring, value)
    return ok and text or (fallback or "Unavailable")
end

function addon:GenerateSnapshot()
    local snapshot = {
        formatVersion = self.formatVersion,
        generatedAt = GetServerTime and GetServerTime() or nil,
        build = { GetBuildInfo() },
    }

    snapshot.character = self:CollectCharacter()
    snapshot.talents, snapshot.abilities = self:CollectTalentsAndAbilities()
    snapshot.actionState, snapshot.actionPages, snapshot.actionSpellIDs =
        self:CollectActionBars()
    snapshot.editMode = self:CollectEditModeActionBars()
    snapshot.uncoveredAbilities = {}

    for _, ability in ipairs(snapshot.abilities) do
        if ability.spellID and not snapshot.actionSpellIDs[ability.spellID] then
            table.insert(snapshot.uncoveredAbilities, ability)
        end
    end

    return self:FormatSnapshot(snapshot)
end

SLASH_RSHCHARACTERSNAPSHOT1 = "/rshsnap"
SLASH_RSHCHARACTERSNAPSHOT2 = "/rshsnapshot"

SlashCmdList.RSHCHARACTERSNAPSHOT = function()
    addon:ShowExport()
end
