local addonName, addon = ...

_G.RSH_Storage = addon
addon.name = addonName
addon.review = nil
addon.upgrades = nil
addon.refreshCallbacks = {}

RSHStorageDB = RSHStorageDB or {}
RSHStorageDB.consideredCharacters = RSHStorageDB.consideredCharacters or {}

function addon:SafeCall(callable, ...)
    if type(callable) ~= "function" then return nil, "Unavailable" end
    local results = { pcall(callable, ...) }
    if not results[1] then return nil, results[2] end
    table.remove(results, 1)
    return unpack(results)
end

function addon:SafeText(value, fallback)
    if value == nil then return fallback or "Unavailable" end
    if type(issecretvalue) == "function" and issecretvalue(value) then
        return fallback or "Unavailable"
    end
    local ok, text = pcall(tostring, value)
    return ok and text or (fallback or "Unavailable")
end

function addon:RegisterRefreshCallback(callback)
    table.insert(self.refreshCallbacks, callback)
end

function addon:RefreshUI()
    for _, callback in ipairs(self.refreshCallbacks) do
        pcall(callback)
    end
end

function addon:Print(message)
    print("|cff33ff99RSH Storage:|r " .. self:SafeText(message))
end

function addon:Open()
    if _G.RSH and _G.RSH.Open then
        _G.RSH:Open("storage")
        return
    end
    self:ShowStandalone()
end

SLASH_RSHSTORAGE1 = "/rshstorage"
SLASH_RSHSTORAGE2 = "/rshstore"
SlashCmdList.RSHSTORAGE = function()
    addon:Open()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    addon:SynchronizeConsideredCharacters()
    addon:RefreshUI()
end)
