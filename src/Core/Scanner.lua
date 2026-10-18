local _, PCBar = ...

--------------------------------------------------------------------------------
-- Scanner
--
-- Walks the player's bags once and returns the consumables that belong on the
-- bar, in the order they should appear.
--
-- Three things this has to get right.
--
-- ONE STACK PER ITEM. Six stacks of the same food is one button, not six, so
-- every item ID is judged once and the count comes from GetItemCount rather
-- than from whichever stack happened to be found first.
--
-- A COLD ITEM CACHE IS NOT AN EMPTY BAG. Deciding whether an item has a use
-- effect needs its full info, which on a fresh login may not have arrived yet.
-- An item in that state is set aside rather than rejected, the client is asked
-- to load it, and the scan reports that it was incomplete so Core can run it
-- again when the data lands. Rejecting it instead would show an empty bar at
-- login and fill it only when something else next touched the bags.
--
-- NO WORK WHEN NOTHING CHANGED. A scan costs a handful of client calls per bag
-- slot and it runs on a bag update, never on a timer. Core coalesces the bursts;
-- this file is only ever asked once per settled change.
--------------------------------------------------------------------------------

local Categories = PCBar.Categories
local Conjured = PCBar.Conjured

local Scanner = {}
PCBar.Scanner = Scanner

-- Set aside rather than accepted or rejected: the item's full info has not
-- arrived, so there is nothing yet to judge it on.
local PENDING = {}

-- Enum.BagIndex.Backpack. The negative bag indices are the bank and the keyring,
-- neither of which is reachable from where you stand when you drink a flask.
local FIRST_BAG = 0

local function LastBag()
    local last = NUM_BAG_SLOTS or 4
    local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
    if reagent and reagent > last then
        last = reagent
    end
    return last
end

--------------------------------------------------------------------------------
-- Judging one item
--------------------------------------------------------------------------------

local function Consider(itemID, bag, slot, info, config)
    local category = Categories.Classify(itemID)
    if not category then return nil end

    local override = config:GetOverride(itemID)
    if override == false then return nil end

    -- An explicit yes beats every filter below it. The category, the quality
    -- floor and the conjured filter are all guesses about what the player wants;
    -- an override is the player saying. Without this a weapon oil the game files
    -- under a category you keep switched off cannot be shown at all, which is
    -- the one thing a per-item list exists to fix.
    local forced = override == true
    local quality = info.quality or C_Item.GetItemQualityByID(itemID) or 1

    if not forced then
        if not config:IsCategoryShown(category) then return nil end
        if quality < (config.minQuality or 1) then return nil end
    end

    -- Everything below here needs the item's full info.
    if C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
        C_Item.RequestLoadItemDataByID(itemID)
        return PENDING
    end

    -- Consumables with no on-use effect exist in quantity: reagents filed under
    -- Generic, quest turn-ins, the fish you have not cooked yet. A button that
    -- does nothing when clicked is worse than no button, so they are dropped
    -- here rather than left for the player to find out by clicking - and this
    -- one is not overridable, because there is nothing to override it into.
    local spellName, spellID = C_Item.GetItemSpell(itemID)
    if not spellName and not spellID then return nil end

    -- Asked after the cache check, because the answer comes out of the item's
    -- tooltip and there is no tooltip until the item's data has arrived.
    if not forced and config.hideConjured and Conjured.Is(itemID) then return nil end

    return {
        itemID = itemID,
        bag = bag,
        slot = slot,
        category = category,
        quality = quality,
        name = C_Item.GetItemNameByID(itemID) or spellName or tostring(itemID),
        icon = info.iconFileID or C_Item.GetItemIconByID(itemID),
        count = C_Item.GetItemCount(itemID) or info.stackCount or 1,
    }
end

--------------------------------------------------------------------------------
-- Order
--
-- Within a category, newest first. Item IDs rise with every patch, so the
-- highest ID in a bucket is the current tier's flask far more reliably than
-- quality is - and unlike item level it needs nothing from the server, so the
-- order does not shuffle about as the cache fills in. Name is the tie-break, to
-- keep the order stable rather than merely consistent.
--------------------------------------------------------------------------------

local COMPARATORS = {
    category = function(a, b)
        local orderA = Categories.ORDER[a.category] or math.huge
        local orderB = Categories.ORDER[b.category] or math.huge
        if orderA ~= orderB then return orderA < orderB end
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.itemID ~= b.itemID then return a.itemID > b.itemID end
        return a.name < b.name
    end,

    name = function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.itemID < b.itemID
    end,

    bags = function(a, b)
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end,
}

Scanner.SORT_MODES = {
    { value = "category", label = "By category, newest first" },
    { value = "name",     label = "By name" },
    { value = "bags",     label = "Bag order" },
}

--------------------------------------------------------------------------------
-- The scan
--------------------------------------------------------------------------------

--- @param config table the addon config
--- @return table items, boolean incomplete
function Scanner:Scan(config)
    local items, judged = {}, {}
    local incomplete = false

    for bag = FIRST_BAG, LastBag() do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local itemID = info and info.itemID

            if itemID and not judged[itemID] then
                judged[itemID] = true

                local entry = Consider(itemID, bag, slot, info, config)
                if entry == PENDING then
                    -- Not judged after all: this item has to be looked at again
                    -- once its info arrives.
                    judged[itemID] = nil
                    incomplete = true
                elseif entry then
                    items[#items + 1] = entry
                end
            end
        end
    end

    table.sort(items, COMPARATORS[config.sortMode] or COMPARATORS.category)

    local limit = config.maxButtons or 0
    if limit > 0 then
        for index = #items, limit + 1, -1 do
            items[index] = nil
        end
    end

    return items, incomplete
end

--- Every consumable in the bags, ignoring the category filters and the ignore
--- list, for the settings page that manages them. Sorted the same way the bar
--- is, so the list does not reorder itself between visits.
--- @return table
function Scanner:ScanAll()
    local items, judged = {}, {}

    for bag = FIRST_BAG, LastBag() do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local itemID = info and info.itemID

            if itemID and not judged[itemID] then
                judged[itemID] = true

                local category = Categories.Classify(itemID)
                if category then
                    items[#items + 1] = {
                        itemID = itemID,
                        bag = bag,
                        slot = slot,
                        category = category,
                        quality = info.quality or C_Item.GetItemQualityByID(itemID) or 1,
                        name = C_Item.GetItemNameByID(itemID) or tostring(itemID),
                        icon = info.iconFileID or C_Item.GetItemIconByID(itemID),
                        count = C_Item.GetItemCount(itemID) or info.stackCount or 1,
                    }
                end
            end
        end
    end

    table.sort(items, COMPARATORS.category)
    return items
end

return Scanner
