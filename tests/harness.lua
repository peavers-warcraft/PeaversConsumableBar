--------------------------------------------------------------------------------
-- The offline harness - loads src/Core/Categories.lua and src/Core/Scanner.lua
-- under a stubbed client so the scan can be driven by hand.
--
-- The scan is the part of this addon that cannot be checked by playing it. What
-- lands on the bar depends on the class and subclass the client reports for each
-- item, which bag slot it was found in, whether its info had arrived yet, and
-- which filters are on - and reproducing any particular combination in game
-- means finding the items and carrying them. So the combinations are written
-- down here instead and driven directly.
--
-- Deliberately not a WoW emulator: nothing with a frame in it is loaded, because
-- nothing with a frame in it makes a decision.
--
-- Run with the system lua (tests/run.sh). Two things differ from WoW's 5.1:
-- loop control variables are const in 5.4+, and `unpack` is `table.unpack`.
-- Neither may appear in addon code - it would work in game and break here,
-- which is where the checking happens.
--------------------------------------------------------------------------------

-- Substituting client globals is the entire job of this file, so the language
-- server's objection to redefining them is correct about the code and wrong
-- about the intent.
---@diagnostic disable: duplicate-set-field

local harness = {}

---This file is `<PeaversConsumableBar>/tests/harness.lua`, whatever the checkout
---is called and wherever a worktree puts it, so the addon root is two levels up.
---@return string
local function root()
    local here = debug.getinfo(1, "S").source:sub(2)
    local testsDir = here:match("^(.*)[/\\][^/\\]+$") or "."
    return testsDir .. "/.."
end

harness.root = root

--------------------------------------------------------------------------------
-- The item database
--
-- Keyed by item ID, the way the client's own is. A test adds the items it cares
-- about and nothing else, so an assertion about flasks cannot be disturbed by
-- the fixture for an assertion about food.
--------------------------------------------------------------------------------

harness.items = {}
harness.bags = {}
harness.loadRequests = {}

harness.CLASS = { consumable = 0, enhancement = 8, armor = 4 }
harness.SUB = {
    generic = 0, potion = 1, elixir = 2, flask = 3, scroll = 4,
    food = 5, enhancement = 6, bandage = 7, other = 8,
}

---Define an item. `cached` defaults to true and `spell` to a use effect, because
---the ordinary case is an item whose info has arrived and which does something.
---@param itemID number
---@param spec table { classID, subclassID, quality, name, spell, cached, conjured }
function harness.defineItem(itemID, spec)
    harness.items[itemID] = {
        classID = spec.classID,
        subclassID = spec.subclassID,
        quality = spec.quality or 1,
        name = spec.name or ("Item " .. itemID),
        icon = spec.icon or 1,
        spell = spec.spell ~= false and (spec.spell or ("Use " .. itemID)) or nil,
        cached = spec.cached ~= false,
        conjured = spec.conjured and true or false,
    }
end

---Put item IDs into a bag, one per slot, in order. A nil entry is an empty slot.
---@param bag number
---@param itemIDs table
function harness.fillBag(bag, itemIDs)
    harness.bags[bag] = itemIDs
end

function harness.reset()
    harness.items = {}
    harness.bags = {}
    harness.loadRequests = {}
end

--------------------------------------------------------------------------------
-- Client stubs
--------------------------------------------------------------------------------

local function install()
    _G.NUM_BAG_SLOTS = 4
    _G.Enum = {
        ItemClass = { Consumable = 0, ItemEnhancement = 8 },
        BagIndex = { Backpack = 0, ReagentBag = 5 },
    }

    _G.C_Container = {
        GetContainerNumSlots = function(bag)
            local contents = harness.bags[bag]
            return contents and #contents or 0
        end,

        GetContainerItemInfo = function(bag, slot)
            local contents = harness.bags[bag]
            local itemID = contents and contents[slot]
            local item = itemID and harness.items[itemID]
            if not item then return nil end

            return {
                itemID = itemID,
                iconFileID = item.icon,
                quality = item.quality,
                stackCount = 1,
            }
        end,
    }

    -- The only place the client admits an item is conjured is its tooltip, so
    -- that is what the stub serves: a one-line tooltip carrying ITEM_CONJURED
    -- for the items a test marked conjured, and an unremarkable one otherwise.
    _G.ITEM_CONJURED = "Conjured Item"
    _G.TooltipUtil = nil

    _G.C_TooltipInfo = {
        GetItemByID = function(itemID)
            local item = harness.items[itemID]
            if not item or not item.cached then return nil end

            local lines = { { leftText = item.name } }
            if item.conjured then
                lines[#lines + 1] = { leftText = _G.ITEM_CONJURED }
            end
            return { lines = lines }
        end,
    }

    _G.C_Item = {
        GetItemInfoInstant = function(itemID)
            local item = harness.items[itemID]
            if not item then return nil end
            -- itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subclassID
            return itemID, nil, nil, nil, item.icon, item.classID, item.subclassID
        end,

        GetItemQualityByID = function(itemID)
            local item = harness.items[itemID]
            return item and item.quality
        end,

        GetItemNameByID = function(itemID)
            local item = harness.items[itemID]
            return item and item.name
        end,

        GetItemIconByID = function(itemID)
            local item = harness.items[itemID]
            return item and item.icon
        end,

        GetItemCount = function(itemID)
            local count = 0
            for _, contents in pairs(harness.bags) do
                for _, id in pairs(contents) do
                    if id == itemID then count = count + 1 end
                end
            end
            return count
        end,

        GetItemSpell = function(itemID)
            local item = harness.items[itemID]
            if not item or not item.spell then return nil end
            return item.spell, itemID
        end,

        IsItemDataCachedByID = function(itemID)
            local item = harness.items[itemID]
            return item and item.cached or false
        end,

        RequestLoadItemDataByID = function(itemID)
            harness.loadRequests[#harness.loadRequests + 1] = itemID
            -- The real client answers this asynchronously with
            -- GET_ITEM_INFO_RECEIVED; a test that wants the answer marks the
            -- item cached itself and scans again.
        end,
    }
end

---Load Categories and Scanner into a shared addon table and return it.
---@return table PCBar
function harness.load()
    install()

    local PCBar = {}

    local files = {
        "src/Core/Categories.lua",
        "src/Core/Conjured.lua",
        "src/Core/Scanner.lua",
    }

    for _, file in ipairs(files) do
        local path = root() .. "/" .. file
        local chunk = assert(loadfile(path), "cannot load " .. path)
        chunk("PeaversConsumableBar", PCBar)
    end

    return PCBar
end

--------------------------------------------------------------------------------
-- The real Config, on a stubbed ConfigManager
--
-- Reproduces the one behaviour of ConfigManager that Config.lua is written
-- around: on a first run the live value for a key is seeded with the *same
-- table* held as its default, so writing through it would rewrite the default.
-- A stub that deep-copied instead would quietly pass a test of the guard
-- against exactly that.
--
-- @param saved table|nil stand-in for an existing SavedVariables table
-- @return table Config
function harness.loadConfig(PCBar, saved)
    install()

    -- Only the ConfigManager slice Config.lua reaches for, not the whole library.
    local commons = {
        ConfigManager = {
            New = function(_, _, defaults)
                local config = {}

                config.defaults = defaults
                for key, value in pairs(defaults) do
                    config[key] = value
                end

                -- Whatever a previous version of the addon left behind.
                for key, value in pairs(saved or {}) do
                    config[key] = value
                end

                config.saves = 0
                function config:Save() self.saves = self.saves + 1 end
                function config:Initialize() end

                function config:Reset()
                    for key, value in pairs(self.defaults) do
                        self[key] = value
                    end
                    return true
                end

                return config
            end,
        },
    }
    _G.PeaversCommons = commons

    local path = root() .. "/src/Utils/Config.lua"
    local chunk = assert(loadfile(path), "cannot load " .. path)
    return chunk("PeaversConsumableBar", PCBar)
end

--------------------------------------------------------------------------------
-- A config stub
--
-- The same two questions the real Config answers for the scanner, and the same
-- plain fields. Not the real Config, which needs ConfigManager and a whole
-- library behind it to answer them the same way.
--------------------------------------------------------------------------------

---@param overrides table|nil
function harness.config(PCBar, overrides)
    local config = {
        sortMode = "category",
        minQuality = 1,
        maxButtons = 0,
        hideConjured = false,
        overrides = {},
    }

    for _, category in ipairs(PCBar.Categories.LIST) do
        config[PCBar.Categories.ConfigKey(category.key)] = category.default
    end

    for key, value in pairs(overrides or {}) do
        config[key] = value
    end

    function config:IsCategoryShown(key)
        return self[PCBar.Categories.ConfigKey(key)] and true or false
    end

    function config:GetOverride(itemID)
        return self.overrides[itemID]
    end

    function config:IsItemShown(itemID, category)
        local override = self:GetOverride(itemID)
        if override ~= nil then return override end
        return self:IsCategoryShown(category)
    end

    return config
end

--------------------------------------------------------------------------------
-- Assertions
--------------------------------------------------------------------------------

local failures, checks = {}, 0

function harness.check(label, ok, detail)
    checks = checks + 1
    if not ok then
        table.insert(failures, label .. (detail and ("  -> " .. detail) or ""))
    end
end

function harness.equal(label, got, want)
    harness.check(label, got == want,
        ("got %s, want %s"):format(tostring(got), tostring(want)))
end

---The item IDs a scan returned, in order, as a comma-separated string - which
---reads far better in a failure than a table address does.
---@param items table
---@return string
function harness.ids(items)
    local out = {}
    for index, item in ipairs(items) do out[index] = item.itemID end
    return table.concat(out, ",")
end

function harness.report(name)
    if #failures == 0 then
        print(("%s: %d checks OK"):format(name, checks))
        return 0
    end

    print(("%s: %d of %d checks FAILED"):format(name, #failures, checks))
    for _, failure in ipairs(failures) do
        print("  " .. failure)
    end
    return 1
end

return harness
