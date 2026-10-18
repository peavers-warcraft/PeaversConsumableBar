local _, PCBar = ...

--------------------------------------------------------------------------------
-- Categories
--
-- What counts as a consumable worth putting on the bar, and which bucket it
-- belongs in.
--
-- Classification comes from the item's own class and subclass, never from its
-- name and never from a hand-kept list of item IDs. A list of IDs is wrong the
-- week a patch adds a flask; a name match is wrong in every locale but one. The
-- class and subclass come straight from the client's item database, are
-- readable before the item's full info has loaded, and have not changed meaning
-- since Cataclysm.
--
-- The subclass IDs are written as numbers with their Enum name beside them
-- rather than read out of Enum. Enum.ItemConsumableSubclass is a retail table;
-- on the Classic clients it is absent, and indexing it there would file every
-- item under "other" - silently, which is the worst way for a filter to fail.
--------------------------------------------------------------------------------

local Categories = {}
PCBar.Categories = Categories

-- Enum.ItemClass.Consumable and Enum.ItemClass.ItemEnhancement. Taken from Enum
-- where it exists only so a future renumber is picked up; the literals are the
-- values every client this addon loads on reports today.
local CLASS_CONSUMABLE = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
local CLASS_ENHANCEMENT = (Enum and Enum.ItemClass and Enum.ItemClass.ItemEnhancement) or 8

-- Enum.ItemConsumableSubclass.
local CONSUMABLE_SUBCLASS = {
    [0] = "other",        -- Generic
    [1] = "potion",       -- Potion
    [2] = "elixir",       -- Elixir
    [3] = "flask",        -- FlaskAlchemy; phials and tinctures land here too
    [4] = "scroll",       -- Scroll
    [5] = "food",         -- FoodAndDrink
    [6] = "enhancement",  -- ItemEnhancement: the older oils, stones and kits
    [7] = "bandage",      -- Bandage
    [8] = "other",        -- Other: augment runes and the long tail
}

--------------------------------------------------------------------------------
-- The buckets
--
-- Order matters twice over: it is the order the buttons are laid out in and the
-- order the settings are listed in, so the bar reads the way the settings page
-- describes it.
--
-- The four on by default are the pre-combat routine the bar exists for - flask,
-- potion, food, weapon oil. The rest are off because a full set of bags holds
-- far more consumables than anyone wants on screen, and a bar that opens with
-- forty buttons is a bar nobody positions.
--------------------------------------------------------------------------------

Categories.LIST = {
    { key = "flask",       label = "Flasks & Phials",       default = true },
    { key = "potion",      label = "Potions",               default = true },
    { key = "food",        label = "Food & Drink",          default = true },
    { key = "enhancement", label = "Oils, Stones & Kits",   default = true },
    { key = "elixir",      label = "Elixirs",               default = false },
    { key = "bandage",     label = "Bandages",              default = false },
    { key = "scroll",      label = "Scrolls",               default = false },
    { key = "other",       label = "Other Consumables",     default = false },
}

Categories.ORDER = {}
Categories.BY_KEY = {}
for index, category in ipairs(Categories.LIST) do
    Categories.ORDER[category.key] = index
    Categories.BY_KEY[category.key] = category
end

--- The config field holding whether a category is shown.
--- @param key string
--- @return string
function Categories.ConfigKey(key)
    return "show" .. key:gsub("^%l", string.upper)
end

--- Which bucket an item belongs in, or nil if it is not a consumable at all.
---
--- GetItemInfoInstant reads the client's own item database rather than the
--- server, so it answers on the first call for anything in the player's bags -
--- no cache miss, no event to wait for.
--- @param itemID number
--- @return string|nil category
function Categories.Classify(itemID)
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if not classID then return nil end

    if classID == CLASS_CONSUMABLE then
        return CONSUMABLE_SUBCLASS[subclassID] or "other"
    end

    -- Retail moved weapon oils and armour kits out of Consumable into a class of
    -- their own, and both shapes are still in circulation: a Dragonflight rune
    -- is Item Enhancement, a Shadowlands oil is Consumable / Item Enhancement.
    -- They are the same thing to the player, so they are the same bucket here.
    if classID == CLASS_ENHANCEMENT then
        return "enhancement"
    end

    return nil
end

return Categories
