local _, addon = ...

function addon:SynchronizeConsideredCharacters()
    RSHStorageDB = RSHStorageDB or {}
    RSHStorageDB.consideredCharacters =
        RSHStorageDB.consideredCharacters or {}
    if not self.WarbandNexus:IsAvailable() then return {} end

    local characters = self.WarbandNexus:GetCharacters()
    for _, character in ipairs(characters) do
        if RSHStorageDB.consideredCharacters[character.key] == nil then
            RSHStorageDB.consideredCharacters[character.key] = true
        end
    end
    return characters
end

function addon:IsCharacterConsidered(characterKey)
    return RSHStorageDB.consideredCharacters[characterKey] == true
end

function addon:SetCharacterConsidered(characterKey, considered)
    RSHStorageDB.consideredCharacters[characterKey] = considered == true
    self.review = nil
    self:RefreshUI()
end

function addon:GetConsideredCharacters()
    local result = {}
    for _, character in ipairs(self:SynchronizeConsideredCharacters()) do
        if self:IsCharacterConsidered(character.key) then
            table.insert(result, character)
        end
    end
    return result
end
