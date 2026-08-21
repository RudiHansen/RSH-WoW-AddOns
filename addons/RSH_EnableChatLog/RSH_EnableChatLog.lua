local eventFrame = CreateFrame("Frame")

local function InitialiseDatabase()
    RSHChatLogDB = RSHChatLogDB or {}

    if RSHChatLogDB.enabled == nil then
        RSHChatLogDB.enabled = true
    end
end

local function ApplySetting()
    InitialiseDatabase()
    LoggingChat(RSHChatLogDB.enabled)
end

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    ApplySetting()
end)
