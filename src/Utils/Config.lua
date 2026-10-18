local addonName, PCBar = ...

--------------------------------------------------------------------------------
-- PeaversConsumableBar Configuration
--
-- Account-wide: where the bar sits and how big its buttons are belong to the
-- screen rather than to a character, and the consumables themselves are mostly
-- account-wide too - a flask is a flask on every alt.
--
-- Appearance keys are stored flat on the config table rather than nested. That
-- is what lets PeaversCommons GlobalAppearance sync bgColor, bgAlpha and
-- friends across the collection, and it means the config table can be handed
-- straight to Bar and Button as their appearance table.
--------------------------------------------------------------------------------

local PeaversCommons = _G.PeaversCommons
local ConfigManager = PeaversCommons.ConfigManager

local Categories = PCBar.Categories

PCBar.name = PCBar.name or addonName

local PCBAR_DEFAULTS = {
    -- Buttons
    buttonSize = 36,
    buttonSpacing = 2,
    buttonsPerLine = 12,
    orientation = "horizontal",

    -- Which way the buttons march out from the bar's own corner, and which way
    -- it wraps. Right and down is what a bar anchored bottom-centre wants.
    growX = "RIGHT",
    growY = "DOWN",

    -- Position. Above where the action bars sit on a stock UI, centred, which
    -- puts it where a player already looks before a pull.
    framePoint = "BOTTOM",
    frameRelativePoint = "BOTTOM",
    frameX = 0,
    frameY = 240,

    -- Behaviour
    visibility = "outOfCombat",
    hideWhenEmpty = true,
    sortMode = "category",

    -- A cap rather than a promise: a packed set of bags can hold sixty items
    -- that pass every filter, and a sixty-button bar is one nobody positions.
    -- The order puts the newest of each kind first, so a cap trims the dregs.
    maxButtons = 24,

    -- Enum.ItemQuality.Common. Poor-quality consumables are vendor trash with a
    -- use effect attached.
    minQuality = 1,

    -- Mage food and water, Healthstones, and the rest of the summoned
    -- consumables. Off by default: conjured food is the food a mage actually
    -- eats, and a Healthstone is the last thing a warlock wants hidden. On, it
    -- clears the bar of everything somebody handed you.
    hideConjured = false,

    -- Appearance
    barAlpha = 1,
    fadeAlpha = 1,
    showFrameBackground = false,
    showCount = true,
    showCooldownText = true,
    colorByQuality = true,
    borderColor = { r = 0, g = 0, b = 0 },
    borderAlpha = 1,
    frameStrata = "MEDIUM",

    -- itemID -> true (always show) or false (never show). An item that is not
    -- in here does whatever its category says.
    --
    -- Only deviations are stored, never the current answer for every item. That
    -- is what makes turning a category on later pick up everything in it that
    -- the player never spoke about, and it is why the table stays a few rows
    -- long instead of growing a row per consumable ever carried.
    overrides = {},
}

for _, category in ipairs(Categories.LIST) do
    PCBAR_DEFAULTS[Categories.ConfigKey(category.key)] = category.default
end

local Config = ConfigManager:New(PCBar, PCBAR_DEFAULTS, {
    savedVariablesName = "PeaversConsumableBarDB",
})
PCBar.Config = Config

--------------------------------------------------------------------------------
-- Filters
--------------------------------------------------------------------------------

--- @param key string a category key
--- @return boolean
function Config:IsCategoryShown(key)
    return self[Categories.ConfigKey(key)] and true or false
end

--- What the player has said about this item specifically: true to always show
--- it, false to never, nil to leave it to its category.
--- @param itemID number
--- @return boolean|nil
function Config:GetOverride(itemID)
    if type(self.overrides) ~= "table" then return nil end
    return self.overrides[itemID]
end

--- Whether this item belongs on the bar, override first and category second.
--- @param itemID number
--- @param category string
--- @return boolean
function Config:IsItemShown(itemID, category)
    local override = self:GetOverride(itemID)
    if override ~= nil then return override end
    return self:IsCategoryShown(category)
end

--- Record what the player wants for one item.
---
--- Stores nothing when the answer already matches the category, so ticking a
--- box does not quietly pin an item to its current state. Pin only what was
--- asked for, and a category turned on later still sweeps the rest in.
--- @param itemID number
--- @param shown boolean
--- @param category string
function Config:SetItemShown(itemID, shown, category)
    if type(self.overrides) ~= "table" then self.overrides = {} end

    shown = shown and true or false
    if shown == self:IsCategoryShown(category) then
        self.overrides[itemID] = nil
    else
        self.overrides[itemID] = shown
    end

    self:Save()
end

--- Forget what was said about one item, leaving it to its category again.
--- @param itemID number
function Config:ClearOverride(itemID)
    if type(self.overrides) ~= "table" then return end
    self.overrides[itemID] = nil
    self:Save()
end

function Config:ClearOverrides()
    self.overrides = {}
    self:Save()
end

--------------------------------------------------------------------------------
-- Nested defaults
--
-- ConfigManager backfills missing top-level keys only, and on a first run it
-- seeds the live value with the *same table* it holds as the default. Writing
-- an ignored item would then quietly rewrite the default it is supposed to be
-- restorable to, so the alias is broken before anything can write through it.
--------------------------------------------------------------------------------

function Config:EnsureOverrides()
    if type(self.overrides) ~= "table" or self.overrides == self.defaults.overrides then
        self.overrides = {}
    end

    -- Migration from the first build, which kept a one-way ignore list and had
    -- no way to show an item its category was hiding. An ignored item becomes an
    -- explicit "never show", which is exactly what it meant.
    if type(self.ignored) == "table" then
        for itemID, ignored in pairs(self.ignored) do
            if ignored and self.overrides[itemID] == nil then
                self.overrides[itemID] = false
            end
        end
    end

    -- Dropped rather than left alongside, or the old table is written back to
    -- SavedVariables forever and the next migration has two sources to reconcile.
    self.ignored = nil
end

local baseInitialize = Config.Initialize
function Config:Initialize()
    baseInitialize(self)
    self:EnsureOverrides()
    self:Save()
end

local baseReset = Config.Reset
function Config:Reset()
    baseReset(self)
    self.overrides = {}
    self.ignored = nil
    self:Save()
    return true
end

return Config
