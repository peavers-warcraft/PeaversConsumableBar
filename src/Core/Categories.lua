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
--
-- WOW FOREVER IS THE ONE EXCEPTION, AND IT IS A LIST. Forever's item table is
-- retail's, rows from 2004 included, and in those rows Blizzard never moved the
-- weapon oils, sharpening stones, weightstones or rogue poisons out of
-- Consumable / Other - where they sit beside quest writs, crates and fireworks.
-- Retail carries the same rows and nobody misses them there; on Forever they are
-- the pre-pull routine. Nothing the client hands an addon tells them apart from
-- their neighbours: the class and subclass are the same, there is no field for
-- "goes on a weapon", and the tooltip only says so in prose. The client's spell
-- data does say so, so scripts/forever_enhancements.py reads it ahead of time and
-- writes src/Data/ForeverEnhancements.lua - every Forever item whose use enchants
-- a weapon for a while. Generated rather than hand-kept, and it cannot misfile
-- anything: an item it has not seen yet falls back to the game's own subclass,
-- which is what this file did before the list existed.
--------------------------------------------------------------------------------

local Categories = {}
PCBar.Categories = Categories

-- Which game this is comes from PeaversCommons.Client (Commons revision 4) and
-- nowhere else. An older Commons gets one line in chat from Require, and the bar
-- behaves as it does on retail, which is what it did before Forever existed.
local Commons = _G.PeaversCommons
local Client = Commons and Commons.Require
    and Commons:Require(4, "PeaversConsumableBar") and Commons.Client
Categories.isForever = (Client and Client.isForever) == true

-- Item ID -> true. Only consulted on Forever: the list is built from Forever's
-- data, and retail players keep the filing they already have.
local FOREVER_ENHANCEMENTS = (Categories.isForever and PCBar.ForeverEnhancements) or {}

-- Enum.ItemClass.Consumable and Enum.ItemClass.ItemEnhancement. Taken from Enum
-- where it exists only so a future renumber is picked up; the literals are the
-- values every client this addon loads on reports today.
local CLASS_CONSUMABLE = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
local CLASS_ENHANCEMENT = (Enum and Enum.ItemClass and Enum.ItemClass.ItemEnhancement) or 8

-- Enum.ItemConsumableSubclass.
--
-- 13 to 15 are Forever's. Retail's item table has nothing in them (they are
-- "RESERVED" there), so filing them changes nothing on retail.
local CONSUMABLE_SUBCLASS = {
    [0] = "other",        -- Generic; on Forever, Explosives
    [1] = "potion",       -- Potion
    [2] = "elixir",       -- Elixir
    [3] = "flask",        -- FlaskAlchemy; phials and tinctures land here too
    [4] = "scroll",       -- Scroll
    [5] = "food",         -- FoodAndDrink
    [6] = "enhancement",  -- ItemEnhancement; Forever's "Permanent": kits, enchant scrolls
    [7] = "bandage",      -- Bandage
    [8] = "other",        -- Other: augment runes and the long tail
    -- Empty in every build so far. Forever's Draught-named items today are
    -- Potions (Major Healing Draught) and Elixirs (Catseye Draught), so Potion
    -- is the likelier home, and a guess that shows them beats one that hides them.
    [13] = "potion",      -- Draught
    [14] = "other",       -- Device: target dummies, repair bots, scopes
    [15] = "enhancement", -- ItemenhancementTemporary: coatings; Forever's AH lists it with 6
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
--
-- Forever adds elixirs to the four. On retail an elixir is what you drink when
-- you have no flask; on Forever a flask is a raid luxury and elixirs are the
-- routine itself. SavedVariables are kept per game, so this default never
-- reaches a retail install.
--------------------------------------------------------------------------------

Categories.LIST = {
    { key = "flask",       label = "Flasks & Phials",       default = true },
    { key = "potion",      label = "Potions",               default = true },
    { key = "food",        label = "Food & Drink",          default = true },
    { key = "enhancement", label = "Oils, Stones & Kits",   default = true },
    { key = "elixir",      label = "Elixirs",               default = Categories.isForever },
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

    -- Before the subclass, because the subclass is what is wrong about these.
    -- See the header.
    if FOREVER_ENHANCEMENTS[itemID] then
        return "enhancement"
    end

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
