local addonName, PCBar = ...

local PeaversCommons = _G.PeaversCommons
local Utils = PeaversCommons.Utils

PCBar.name = addonName
PCBar.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0.0"

PeaversCommons.SlashCommands:Register(addonName, "pcbar", {
    default = function()
        PCBar.ConfigUI:OpenOptions()
    end,
    unlock = function()
        if PCBar.Core:SetUnlocked(true) then
            Utils.Print(PCBar, "Bar unlocked - drag it into place, then /pcbar lock.")
        else
            Utils.Print(PCBar, "The bar cannot be moved in combat.")
        end
    end,
    lock = function()
        if PCBar.Core:SetUnlocked(false) then
            Utils.Print(PCBar, "Bar locked.")
        else
            Utils.Print(PCBar, "The bar cannot be moved in combat.")
        end
    end,
    toggle = function()
        local unlocked = PCBar.Core:ToggleUnlocked()
        if unlocked == nil then
            Utils.Print(PCBar, "The bar cannot be moved in combat.")
        else
            Utils.Print(PCBar, unlocked and "Bar unlocked." or "Bar locked.")
        end
    end,
    -- Answers "why is this not on my bar". Every filter in the addon decides
    -- from the item's category, so printing the category each item was put in -
    -- next to whether it made it onto the bar - is enough to see which setting
    -- is responsible, without guessing which bucket the game files an oil under.
    list = function()
        local items = PCBar.Scanner:ScanAll()
        Utils.Print(PCBar, ("%d consumables in your bags:"):format(#items))

        for _, item in ipairs(items) do
            local category = PCBar.Categories.BY_KEY[item.category]
            local shown = PCBar.Config:IsItemShown(item.itemID, item.category)
            print(("  %s |cff808080(%d)|r  %s  |cff%s%s|r"):format(
                item.name,
                item.itemID,
                category and category.label or item.category,
                shown and "40c040" or "c04040",
                shown and "on the bar" or "not shown"))
        end
    end,
    reset = function()
        PCBar.Config:Reset()
        PCBar.Core:ApplyConfig()
        if PCBar.ConfigUI and PCBar.ConfigUI.Rebuild then
            PCBar.ConfigUI:Rebuild()
        end
        Utils.Print(PCBar, "All settings restored to defaults.")
    end,
    help = function()
        Utils.Print(PCBar, "Commands:")
        print("  /pcbar - Open settings")
        print("  /pcbar list - Print every consumable found, with its category")
        print("  /pcbar unlock - Show the bar so it can be dragged")
        print("  /pcbar lock - Finish positioning")
        print("  /pcbar reset - Restore every setting to its default")
    end,
})

PeaversCommons.Events:Init(addonName, function()
    PCBar.Config:Initialize()
    PCBar.Core:Initialize()

    -- After Core, because it registers the frame Core builds.
    if PCBar.EditMode then
        PCBar.EditMode:Register()
    end

    if PCBar.ConfigUI and PCBar.ConfigUI.Initialize then
        PCBar.ConfigUI:Initialize()
    end

    if PCBar.Patrons and PCBar.Patrons.Initialize then
        PCBar.Patrons:Initialize()
    end

    -- Use the centralized SettingsUI system from PeaversCommons
    C_Timer.After(0.5, function()
        PeaversCommons.SettingsUI:CreateRedirectPage(PCBar, "PeaversConsumableBar",
            "Peavers Consumable Bar")
    end)

    -- Register with the PeaversConfig registry
    if PeaversCommons.ConfigRegistry then
        PeaversCommons.ConfigRegistry:Register({
            name = "PeaversConsumableBar",
            displayName = "Consumable Bar",
            description = "Your flasks, food and oils on one bar, straight from your bags",
            addonRef = PCBar,
            config = PCBar.Config,
            pages = PCBar.ConfigUI:GetPages(),
            order = 16,
        })
    end
end, {
    suppressAnnouncement = true
})

_G.PeaversConsumableBar = PCBar
