--------------------------------------------------------------------------------
-- What gets stored when the player ticks a box.
--
-- Two things here are only wrong once and then wrong forever: the migration,
-- which rewrites a real SavedVariables table, and the rule that only deviations
-- from the category are kept. Get the second wrong and every box ticked once
-- pins its item, so turning a category on later does nothing for the items the
-- player already looked at.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or "."
local harness = dofile(here .. "/harness.lua")

local FLASK = 1000       -- Flasks are on by default
local RUNE = 2000        -- Other Consumables are off by default

---A freshly initialized Config, optionally on top of existing saved data.
local function freshConfig(saved)
    local PCBar = {}

    do
        local path = harness.root() .. "/src/Core/Categories.lua"
        assert(loadfile(path))("PeaversConsumableBar", PCBar)
    end

    local config = harness.loadConfig(PCBar, saved)
    config:Initialize()
    return config, PCBar
end

--------------------------------------------------------------------------------
-- The aliasing guard
--------------------------------------------------------------------------------

do
    local config = freshConfig()

    harness.check("overrides is not the defaults table it was seeded from",
        config.overrides ~= config.defaults.overrides)

    config.overrides[FLASK] = false
    harness.check("so writing an override leaves the defaults alone",
        next(config.defaults.overrides) == nil)
end

--------------------------------------------------------------------------------
-- Migration from the one-way ignore list
--------------------------------------------------------------------------------

do
    local config = freshConfig({ ignored = { [FLASK] = true } })

    harness.equal("an ignored item becomes an explicit never-show",
        config.overrides[FLASK], false)
    harness.equal("and the old table is dropped rather than kept alongside",
        config.ignored, nil)
end

do
    -- An override already recorded wins: the new table is the current answer and
    -- the old one is history.
    local config = freshConfig({
        ignored = { [FLASK] = true },
        overrides = { [FLASK] = true },
    })
    harness.equal("migration does not overwrite an override already set",
        config.overrides[FLASK], true)
end

--------------------------------------------------------------------------------
-- Only deviations are stored
--------------------------------------------------------------------------------

do
    local config = freshConfig()

    -- Flasks are on, so "show this flask" is what would happen anyway.
    config:SetItemShown(FLASK, true, "flask")
    harness.equal("ticking an item its category already shows stores nothing",
        config.overrides[FLASK], nil)

    config:SetItemShown(FLASK, false, "flask")
    harness.equal("unticking it stores a never-show", config.overrides[FLASK], false)

    config:SetItemShown(FLASK, true, "flask")
    harness.equal("and ticking it again clears the row rather than pinning it",
        config.overrides[FLASK], nil)

    -- Other Consumables are off, so this is the oil case: an explicit yes.
    config:SetItemShown(RUNE, true, "other")
    harness.equal("ticking an item in an off category stores an always-show",
        config.overrides[RUNE], true)

    config:SetItemShown(RUNE, false, "other")
    harness.equal("unticking it again clears the row", config.overrides[RUNE], nil)
end

--------------------------------------------------------------------------------
-- Reading it back
--------------------------------------------------------------------------------

do
    local config = freshConfig()

    harness.check("with no override, the category decides",
        config:IsItemShown(FLASK, "flask") == true)
    harness.check("including when the category is off",
        config:IsItemShown(RUNE, "other") == false)

    config.overrides[FLASK] = false
    config.overrides[RUNE] = true

    harness.check("an override beats a category that is on",
        config:IsItemShown(FLASK, "flask") == false)
    harness.check("and a category that is off",
        config:IsItemShown(RUNE, "other") == true)

    config:ClearOverride(RUNE)
    harness.check("clearing one returns it to its category",
        config:IsItemShown(RUNE, "other") == false)
    harness.check("and leaves the others alone",
        config:IsItemShown(FLASK, "flask") == false)
end

--------------------------------------------------------------------------------
-- Reset
--------------------------------------------------------------------------------

do
    local config = freshConfig({ ignored = { [FLASK] = true } })
    config.overrides[RUNE] = true

    config:Reset()

    harness.equal("reset clears every override", next(config.overrides), nil)
    harness.equal("and does not resurrect the migrated list", config.ignored, nil)
    harness.check("overrides is still not the defaults table",
        config.overrides ~= config.defaults.overrides)
end

os.exit(harness.report("config"))
