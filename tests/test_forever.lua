--------------------------------------------------------------------------------
-- WoW Forever.
--
-- Forever runs retail's client on retail's item table, rows from 2004 included,
-- and files its consumables in ways retail never shows: weapon oils, stones and
-- rogue poisons under Other, two oils under Trade Goods, imbues under Scrolls,
-- and three subclasses of its own. Every item below carries its real Forever ID,
-- class, subclass and item level (build 1.60.1.71139), so a test here is a claim
-- about the game rather than about a fixture.
--
-- Each case runs on both clients. Forever's rules must not leak into retail,
-- where the same item IDs exist and existing players already have a bar.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or "."
local harness = dofile(here .. "/harness.lua")

local CLASS, SUB = harness.CLASS, harness.SUB

local ROUGH_STONE = 287978         -- Rough Sharpening Stone, re-issued for Forever
local DENSE_STONE = 12404          -- Dense Sharpening Stone
local ELEMENTAL_STONE = 18262      -- Elemental Sharpening Stone
local BRILLIANT_OIL = 20749        -- Brilliant Wizard Oil
local LESSER_OIL = 20746           -- Lesser Wizard Oil, filed under Trade Goods
local INSTANT_POISON = 8928        -- Instant Poison VI
local IMBUE_SCROLL = 277500        -- Scroll of Imbue Greater Flame
local SHIELD_COATING = 228980      -- Conductive Shield Coating
local NIGHTCRAWLERS = 6530         -- a fishing lure: goes on a pole
local HEALTHSTONE = 19013          -- Major Healthstone
local FIRESTONE = 13699            -- armour, not a consumable
local MAJOR_HEALING = 13446        -- Major Healing Potion
local MINOR_HEALING = 287966       -- Minor Healing Potion, re-issued for Forever
local MONGOOSE = 13452             -- Elixir of the Mongoose
local SAPPER = 10646               -- Goblin Sapper Charge: Forever's "Explosives"
local TARGET_DUMMY = 4366          -- Forever's "Device"
local DRAUGHT = 900001             -- nothing uses Draught yet; a stand-in

local function defineAll()
    local function item(id, classID, subclassID, level, name, quality)
        harness.defineItem(id, { classID = classID, subclassID = subclassID,
            level = level, name = name, quality = quality or 1 })
    end

    item(ROUGH_STONE, CLASS.consumable, SUB.other, 5, "Rough Sharpening Stone")
    item(DENSE_STONE, CLASS.consumable, SUB.other, 45, "Dense Sharpening Stone")
    item(ELEMENTAL_STONE, CLASS.consumable, SUB.other, 60, "Elemental Sharpening Stone", 2)
    item(BRILLIANT_OIL, CLASS.consumable, SUB.other, 55, "Brilliant Wizard Oil")
    item(LESSER_OIL, CLASS.tradegoods, 12, 30, "Lesser Wizard Oil")
    item(INSTANT_POISON, CLASS.consumable, SUB.other, 60, "Instant Poison VI")
    item(IMBUE_SCROLL, CLASS.consumable, SUB.scroll, 50, "Scroll of Imbue Greater Flame")
    item(SHIELD_COATING, CLASS.consumable, SUB.temporary, 40, "Conductive Shield Coating", 2)
    item(NIGHTCRAWLERS, CLASS.consumable, SUB.other, 15, "Nightcrawlers")
    item(HEALTHSTONE, CLASS.consumable, SUB.other, 58, "Major Healthstone")
    item(FIRESTONE, CLASS.armor, 0, 46, "Firestone", 2)
    item(MAJOR_HEALING, CLASS.consumable, SUB.potion, 55, "Major Healing Potion")
    item(MINOR_HEALING, CLASS.consumable, SUB.potion, 5, "Minor Healing Potion")
    item(MONGOOSE, CLASS.consumable, SUB.elixir, 56, "Elixir of the Mongoose")
    item(SAPPER, CLASS.consumable, SUB.generic, 46, "Goblin Sapper Charge")
    item(TARGET_DUMMY, CLASS.consumable, SUB.device, 22, "Target Dummy")
    item(DRAUGHT, CLASS.consumable, SUB.draught, 50, "Draught of Tomorrow")
end

local forever = harness.load("forever")
local retail = harness.load("retail")

--------------------------------------------------------------------------------
-- Which game it thinks it is
--------------------------------------------------------------------------------

harness.check("Forever is recognised", forever.Categories.isForever == true)
harness.check("retail is not Forever", retail.Categories.isForever == false)

--------------------------------------------------------------------------------
-- Classification
--------------------------------------------------------------------------------

do
    harness.reset()
    defineAll()
    local classify = forever.Categories.Classify

    -- The point of the list: what the game files under Other, Trade Goods or
    -- Scrolls but you put on a weapon before a pull.
    for _, case in ipairs({
        { DENSE_STONE, "a sharpening stone" },
        { BRILLIANT_OIL, "a wizard oil" },
        { LESSER_OIL, "a wizard oil filed under Trade Goods" },
        { INSTANT_POISON, "a rogue poison" },
        { IMBUE_SCROLL, "an imbue scroll" },
        { ROUGH_STONE, "a re-issued stone" },
        { SHIELD_COATING, "a shield coating" },
    }) do
        harness.equal("Forever: " .. case[2] .. " is an enhancement",
            classify(case[1]), "enhancement")
    end

    -- And what it leaves alone. A lure goes on a fishing pole, and a
    -- Healthstone is not something you put on anything.
    harness.equal("Forever: a fishing lure stays in Other", classify(NIGHTCRAWLERS), "other")
    harness.equal("Forever: a Healthstone stays in Other", classify(HEALTHSTONE), "other")
    harness.equal("Forever: a Firestone is armour, not a consumable", classify(FIRESTONE), nil)

    harness.equal("Forever: Explosives are Other", classify(SAPPER), "other")
    harness.equal("Forever: a Device is Other", classify(TARGET_DUMMY), "other")
    harness.equal("Forever: a Draught is a potion", classify(DRAUGHT), "potion")
    harness.equal("Forever: potions are still potions", classify(MAJOR_HEALING), "potion")
end

do
    harness.reset()
    defineAll()
    local classify = retail.Categories.Classify

    -- Retail keeps the filing it already had: the same item IDs exist there,
    -- and the list was built from Forever's data, not retail's.
    harness.equal("retail: a vanilla stone is still Other", classify(DENSE_STONE), "other")
    harness.equal("retail: a vanilla poison is still Other", classify(INSTANT_POISON), "other")
    harness.equal("retail: Trade Goods are still not consumables", classify(LESSER_OIL), nil)
    harness.equal("retail: a scroll is still a scroll", classify(IMBUE_SCROLL), "scroll")

    -- Retail has no items in Forever's three subclasses, so filing them there
    -- costs nothing - and means a retail item that ever lands in one is filed
    -- the same way Forever files it.
    harness.equal("retail: subclass 15 is an enhancement", classify(SHIELD_COATING), "enhancement")
    harness.equal("retail: subclass 14 is Other", classify(TARGET_DUMMY), "other")
    harness.equal("retail: subclass 13 is a potion", classify(DRAUGHT), "potion")
end

--------------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------------

do
    harness.reset()
    defineAll()
    harness.fillBag(0, { MONGOOSE, MAJOR_HEALING, DENSE_STONE, NIGHTCRAWLERS,
        HEALTHSTONE, SAPPER })

    local items = forever.Scanner:Scan(harness.config(forever))
    harness.equal("Forever: elixirs are on to begin with, beside potions and stones",
        harness.ids(items), table.concat({ MAJOR_HEALING, DENSE_STONE, MONGOOSE }, ","))

    local retailItems = retail.Scanner:Scan(harness.config(retail))
    harness.equal("retail: elixirs are still off, and the stone is still in Other",
        harness.ids(retailItems), tostring(MAJOR_HEALING))
end

--------------------------------------------------------------------------------
-- Order
--
-- Forever re-issued some vanilla consumables under new, higher IDs, so the
-- highest ID is no longer the newest tier. Item level is.
--------------------------------------------------------------------------------

do
    harness.reset()
    defineAll()
    harness.fillBag(0, { MINOR_HEALING, MAJOR_HEALING, ROUGH_STONE, DENSE_STONE,
        BRILLIANT_OIL, ELEMENTAL_STONE })

    local items = forever.Scanner:Scan(harness.config(forever))
    harness.equal("Forever: highest level first within a category, after quality",
        harness.ids(items), table.concat({
            MAJOR_HEALING, MINOR_HEALING,
            ELEMENTAL_STONE, BRILLIANT_OIL, DENSE_STONE, ROUGH_STONE,
        }, ","))

    local capped = forever.Scanner:Scan(harness.config(forever, { maxButtons = 1 }))
    harness.equal("Forever: so the cap keeps the strongest potion, not the newest ID",
        harness.ids(capped), tostring(MAJOR_HEALING))

    local all = forever.Scanner:ScanAll()
    harness.equal("Forever: the settings list orders the same way",
        harness.ids(all), harness.ids(items))
end

do
    harness.reset()
    defineAll()
    harness.fillBag(0, { MAJOR_HEALING, MINOR_HEALING })

    local items = retail.Scanner:Scan(harness.config(retail))
    harness.equal("retail: the order is still newest ID first",
        harness.ids(items), table.concat({ MINOR_HEALING, MAJOR_HEALING }, ","))
    harness.equal("retail: and it never asks for the item level", harness.itemInfoCalls, 0)
end

do
    harness.reset()
    defineAll()
    harness.items[MAJOR_HEALING].cached = false
    harness.fillBag(0, { MAJOR_HEALING, MINOR_HEALING })

    -- The settings list does not wait for item data, so an item can be seen
    -- before its level is known. It sorts as level 0 rather than breaking.
    local all = forever.Scanner:ScanAll()
    harness.equal("Forever: an item with no data yet sorts as level 0",
        harness.ids(all), table.concat({ MINOR_HEALING, MAJOR_HEALING }, ","))
end

do
    local function label(PCBar)
        for _, mode in ipairs(PCBar.Scanner.SORT_MODES) do
            if mode.value == "category" then return mode.label end
        end
    end

    harness.equal("Forever: the order is described as it is",
        label(forever), "By category, highest level first")
    harness.equal("retail: and retail's description is unchanged",
        label(retail), "By category, newest first")
end

--------------------------------------------------------------------------------
-- The generated list itself
--
-- Read straight from the committed file, so a regeneration that broke the
-- selection rule fails here rather than in somebody's bags.
--------------------------------------------------------------------------------

do
    local list = forever.ForeverEnhancements
    harness.check("the generated list loaded", type(list) == "table")

    local count, malformed = 0, 0
    for itemID, value in pairs(list or {}) do
        count = count + 1
        if type(itemID) ~= "number" or itemID <= 0 or value ~= true then
            malformed = malformed + 1
        end
    end
    harness.check("it is not empty", count > 0)
    harness.equal("every entry is an item ID mapped to true", malformed, 0)

    for _, case in ipairs({
        { 2862, "Rough Sharpening Stone" }, { 12643, "Dense Weightstone" },
        { 18262, "Elemental Sharpening Stone" }, { 20749, "Brilliant Wizard Oil" },
        { 23123, "Blessed Wizard Oil" }, { 8928, "Instant Poison VI" },
        { 20844, "Deadly Poison V" }, { 10922, "Wound Poison IV" },
        { 20746, "Lesser Wizard Oil" }, { 277500, "Scroll of Imbue Greater Flame" },
    }) do
        harness.check("it holds " .. case[2], list[case[1]] == true)
    end

    for _, case in ipairs({
        { 6529, "Shiny Bauble, a lure" }, { 6530, "Nightcrawlers, a lure" },
        { 13699, "Firestone, which is armour" }, { 19013, "Major Healthstone" },
        { 13446, "Major Healing Potion" },
    }) do
        harness.check("it leaves out " .. case[2], list[case[1]] == nil)
    end
end

os.exit(harness.report("forever"))
