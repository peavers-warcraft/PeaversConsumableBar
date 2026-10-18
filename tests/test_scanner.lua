--------------------------------------------------------------------------------
-- What lands on the bar, and in what order.
--
-- Every case here is one a player can hit and nobody can easily reproduce on
-- demand: an item whose info has not arrived, a reagent filed under the same
-- class as a flask, six stacks of the same food, a bagful that overflows the
-- cap.
--------------------------------------------------------------------------------

local harness = dofile((debug.getinfo(1, "S").source:sub(2)
    :match("^(.*)[/\\][^/\\]+$") or ".") .. "/harness.lua")

local PCBar = harness.load()
local Scanner = PCBar.Scanner
local Categories = PCBar.Categories

local CLASS, SUB = harness.CLASS, harness.SUB

local FLASK = 1000
local OLD_FLASK = 900
local POTION = 1100
local FOOD = 1200
local RETAIL_OIL = 1300
local LEGACY_OIL = 1310
local ELIXIR = 1400
local REAGENT = 1500
local TRASH_FOOD = 1600
local PLATE_BOOTS = 1700
local MAGE_FOOD = 1800
local HEALTHSTONE = 1900

local function defineAll()
    harness.defineItem(FLASK, { classID = CLASS.consumable, subclassID = SUB.flask,
        quality = 3, name = "Flask of Now" })
    harness.defineItem(OLD_FLASK, { classID = CLASS.consumable, subclassID = SUB.flask,
        quality = 3, name = "Flask of Then" })
    harness.defineItem(POTION, { classID = CLASS.consumable, subclassID = SUB.potion,
        quality = 3, name = "Healing Potion" })
    harness.defineItem(FOOD, { classID = CLASS.consumable, subclassID = SUB.food,
        quality = 1, name = "Feast" })
    harness.defineItem(RETAIL_OIL, { classID = CLASS.enhancement, subclassID = 0,
        quality = 3, name = "Howling Rune" })
    harness.defineItem(LEGACY_OIL, { classID = CLASS.consumable,
        subclassID = SUB.enhancement, quality = 2, name = "Shadowcore Oil" })
    harness.defineItem(ELIXIR, { classID = CLASS.consumable, subclassID = SUB.elixir,
        quality = 2, name = "Elixir of Something" })
    -- A consumable with no use effect: a crafting reagent filed under Generic.
    harness.defineItem(REAGENT, { classID = CLASS.consumable, subclassID = SUB.generic,
        quality = 1, name = "Awakened Fire", spell = false })
    -- Poor-quality food, which is vendor trash with a use effect attached.
    harness.defineItem(TRASH_FOOD, { classID = CLASS.consumable, subclassID = SUB.food,
        quality = 0, name = "Mystery Meat" })
    harness.defineItem(PLATE_BOOTS, { classID = CLASS.armor, subclassID = 4,
        quality = 4, name = "Greaves of Not A Consumable" })
    harness.defineItem(MAGE_FOOD, { classID = CLASS.consumable, subclassID = SUB.food,
        quality = 1, name = "Conjured Mana Bun", conjured = true })
    -- Conjured as well, which is why hiding conjured items is not the same
    -- request as hiding mage food, and why the setting says so.
    harness.defineItem(HEALTHSTONE, { classID = CLASS.consumable, subclassID = SUB.potion,
        quality = 2, name = "Healthstone", conjured = true })
end

--------------------------------------------------------------------------------
-- Classification
--------------------------------------------------------------------------------

do
    harness.reset()
    defineAll()

    harness.equal("flask is a flask", Categories.Classify(FLASK), "flask")
    harness.equal("potion is a potion", Categories.Classify(POTION), "potion")
    harness.equal("food is food", Categories.Classify(FOOD), "food")
    harness.equal("elixir is an elixir", Categories.Classify(ELIXIR), "elixir")

    -- The two shapes of weapon oil in circulation have to reach the same bucket:
    -- retail moved them into a class of their own and the older ones stayed put.
    harness.equal("retail rune is an enhancement",
        Categories.Classify(RETAIL_OIL), "enhancement")
    harness.equal("legacy oil is an enhancement",
        Categories.Classify(LEGACY_OIL), "enhancement")

    harness.equal("armour is not a consumable", Categories.Classify(PLATE_BOOTS), nil)
    harness.equal("an unknown item is not a consumable", Categories.Classify(1), nil)
end

--------------------------------------------------------------------------------
-- Filters
--------------------------------------------------------------------------------

do
    harness.reset()
    defineAll()
    harness.fillBag(0, { FLASK, POTION, FOOD, RETAIL_OIL, ELIXIR, REAGENT,
        TRASH_FOOD, PLATE_BOOTS })

    local config = harness.config(PCBar)
    local items = Scanner:Scan(config)

    -- Flask, potion, food and oil are the four categories on by default.
    harness.equal("defaults admit exactly the pre-combat four",
        harness.ids(items),
        table.concat({ FLASK, POTION, FOOD, RETAIL_OIL }, ","))

    local byID = {}
    for _, item in ipairs(items) do byID[item.itemID] = item end

    harness.check("elixir is off by default", byID[ELIXIR] == nil)
    harness.check("a reagent with no use effect never appears", byID[REAGENT] == nil)
    harness.check("poor-quality food is below the floor", byID[TRASH_FOOD] == nil)
    harness.check("armour never appears", byID[PLATE_BOOTS] == nil)
end

do
    harness.reset()
    defineAll()
    harness.fillBag(0, { FLASK, ELIXIR })

    local config = harness.config(PCBar, { showElixir = true })
    local items = Scanner:Scan(config)
    harness.equal("turning a category on admits it",
        harness.ids(items), table.concat({ FLASK, ELIXIR }, ","))
end

--------------------------------------------------------------------------------
-- Per-item overrides
--
-- The case that drove this: a weapon oil the game files under a category the
-- player keeps switched off. Before overrides went both ways there was no way to
-- show it at all short of turning on the whole category.
--------------------------------------------------------------------------------

do
    harness.reset()
    defineAll()
    harness.fillBag(0, { FLASK, OLD_FLASK })

    local config = harness.config(PCBar, { overrides = { [OLD_FLASK] = false } })
    harness.equal("an item overridden off is dropped though its category is on",
        harness.ids(Scanner:Scan(config)), tostring(FLASK))
end

do
    harness.reset()
    defineAll()
    -- An augment rune is Consumable / Other, which is off by default - the same
    -- bucket the oil that prompted this lands in.
    local RUNE = 2000
    harness.defineItem(RUNE, { classID = CLASS.consumable, subclassID = SUB.other,
        quality = 3, name = "Augment Rune" })
    harness.fillBag(0, { FLASK, RUNE })

    harness.equal("an item in an off category is not shown unasked",
        harness.ids(Scanner:Scan(harness.config(PCBar))), tostring(FLASK))

    local forced = harness.config(PCBar, { overrides = { [RUNE] = true } })
    harness.equal("overriding it on shows it without turning the category on",
        harness.ids(Scanner:Scan(forced)), table.concat({ FLASK, RUNE }, ","))
    harness.check("and the category is still off",
        forced:IsCategoryShown("other") == false)
end

do
    harness.reset()
    PCBar.Conjured.Forget()
    defineAll()
    harness.fillBag(0, { TRASH_FOOD, MAGE_FOOD })

    -- An override is the player saying, so it beats the quality floor and the
    -- conjured filter as well as the category - all three are guesses.
    local config = harness.config(PCBar, {
        minQuality = 3,
        hideConjured = true,
        overrides = { [TRASH_FOOD] = true, [MAGE_FOOD] = true },
    })
    harness.equal("an override beats the quality floor and the conjured filter",
        harness.ids(Scanner:Scan(config)),
        table.concat({ MAGE_FOOD, TRASH_FOOD }, ","))
end

do
    harness.reset()
    defineAll()
    harness.fillBag(0, { REAGENT })

    -- The one filter an override cannot beat: there is nothing to override it
    -- into, because the button would have nothing to do.
    local config = harness.config(PCBar, {
        showOther = true,
        overrides = { [REAGENT] = true },
    })
    harness.equal("an override cannot conjure a use effect",
        harness.ids(Scanner:Scan(config)), "")
end

--------------------------------------------------------------------------------
-- Conjured items
--------------------------------------------------------------------------------

do
    harness.reset()
    PCBar.Conjured.Forget()
    defineAll()
    harness.fillBag(0, { FOOD, MAGE_FOOD, HEALTHSTONE, POTION })

    local on = Scanner:Scan(harness.config(PCBar, { hideConjured = false }))
    harness.equal("conjured items are shown by default",
        harness.ids(on), table.concat({ POTION, HEALTHSTONE, MAGE_FOOD, FOOD }, ","))

    local off = Scanner:Scan(harness.config(PCBar, { hideConjured = true }))
    harness.equal("hiding conjured items drops the mage food and the healthstone",
        harness.ids(off), table.concat({ POTION, FOOD }, ","))
end

do
    -- The tooltip is where the answer comes from, so an item whose data has not
    -- arrived has no answer yet. It must not be remembered as "not conjured",
    -- or a mage food looted at login is on the bar until the next reload.
    harness.reset()
    PCBar.Conjured.Forget()
    defineAll()
    harness.items[MAGE_FOOD].cached = false

    harness.equal("an uncached item is not claimed to be unconjured",
        PCBar.Conjured.Is(MAGE_FOOD), false)

    harness.items[MAGE_FOOD].cached = true
    harness.equal("and is recognised once its tooltip arrives",
        PCBar.Conjured.Is(MAGE_FOOD), true)
end

do
    harness.reset()
    PCBar.Conjured.Forget()
    defineAll()
    harness.fillBag(0, { LEGACY_OIL, FOOD })

    -- Rare and above, which the uncommon oil and the common food both fail.
    local config = harness.config(PCBar, { minQuality = 3 })
    harness.equal("the quality floor drops everything below it",
        harness.ids(Scanner:Scan(config)), "")
end

--------------------------------------------------------------------------------
-- One button per item
--------------------------------------------------------------------------------

do
    harness.reset()
    defineAll()
    -- Six stacks of the same food across two bags.
    harness.fillBag(0, { FOOD, FOOD, FOOD })
    harness.fillBag(1, { FOOD, FOOD, FOOD })

    local items = Scanner:Scan(harness.config(PCBar))
    harness.equal("six stacks are one entry", #items, 1)
    harness.equal("the count is the total across every stack", items[1].count, 6)
end

--------------------------------------------------------------------------------
-- A cold item cache
--------------------------------------------------------------------------------

do
    harness.reset()
    defineAll()
    harness.items[FLASK].cached = false
    harness.fillBag(0, { FLASK, FOOD })

    local config = harness.config(PCBar)
    local items, incomplete = Scanner:Scan(config)

    harness.equal("an uncached item is held back, not shown",
        harness.ids(items), tostring(FOOD))
    harness.check("the scan reports itself incomplete", incomplete == true)
    harness.equal("the client was asked to load it", harness.loadRequests[1], FLASK)

    -- What Core does when GET_ITEM_INFO_RECEIVED arrives.
    harness.items[FLASK].cached = true
    local again, stillIncomplete = Scanner:Scan(config)
    harness.equal("the rescan picks it up",
        harness.ids(again), table.concat({ FLASK, FOOD }, ","))
    harness.check("and reports itself complete", stillIncomplete == false)
end

--------------------------------------------------------------------------------
-- Order
--------------------------------------------------------------------------------

do
    harness.reset()
    defineAll()
    -- Deliberately scattered: bag order is the reverse of category order.
    harness.fillBag(0, { FOOD, POTION, OLD_FLASK, FLASK })

    local items = Scanner:Scan(harness.config(PCBar, { sortMode = "category" }))
    harness.equal("categories come out in the order they are declared, newest first",
        harness.ids(items),
        table.concat({ FLASK, OLD_FLASK, POTION, FOOD }, ","))

    local byName = Scanner:Scan(harness.config(PCBar, { sortMode = "name" }))
    harness.equal("by name sorts across categories",
        harness.ids(byName),
        -- Feast, Flask of Now, Flask of Then, Healing Potion
        table.concat({ FOOD, FLASK, OLD_FLASK, POTION }, ","))

    local byBags = Scanner:Scan(harness.config(PCBar, { sortMode = "bags" }))
    harness.equal("bag order is the order they sit in",
        harness.ids(byBags),
        table.concat({ FOOD, POTION, OLD_FLASK, FLASK }, ","))
end

--------------------------------------------------------------------------------
-- The cap
--------------------------------------------------------------------------------

do
    harness.reset()
    defineAll()
    harness.fillBag(0, { FOOD, POTION, OLD_FLASK, FLASK })

    local items = Scanner:Scan(harness.config(PCBar, { maxButtons = 2 }))
    harness.equal("the cap keeps the first entries in order",
        harness.ids(items), table.concat({ FLASK, OLD_FLASK }, ","))

    local uncapped = Scanner:Scan(harness.config(PCBar, { maxButtons = 0 }))
    harness.equal("a cap of zero is no cap", #uncapped, 4)
end

--------------------------------------------------------------------------------
-- The settings page's own scan
--------------------------------------------------------------------------------

do
    harness.reset()
    defineAll()
    harness.fillBag(0, { FLASK, ELIXIR, REAGENT, PLATE_BOOTS })

    local all = Scanner:ScanAll()
    harness.equal("ScanAll ignores the category filters", #all, 3)
    harness.equal("but still only lists consumables",
        harness.ids(all), table.concat({ FLASK, ELIXIR, REAGENT }, ","))
end

os.exit(harness.report("scanner"))
