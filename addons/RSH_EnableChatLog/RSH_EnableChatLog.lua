local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")

f:SetScript("OnEvent", function()
    LoggingChat(true)
    print("|cff00ff00Chat logging enabled.|r")
end)