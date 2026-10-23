local _, PCBar = ...

--------------------------------------------------------------------------------
-- Core
--
-- Decides when to look in the bags and when the bar may be rebuilt.
--
-- COALESCED, NEVER POLLED. Picking up a stack of forty flasks fires several bag
-- events; vendoring a bagful fires dozens. Each one schedules the same single
-- rescan a fifth of a second out, so a burst of events costs one scan. There is
-- no timer running the rest of the time.
--
-- COMBAT IS A WALL, NOT A DELAY TO BE RETRIED. A secure button cannot be
-- rewritten while the player is fighting, so a scan that lands mid-combat is
-- kept and applied the moment combat ends. Only the last one is kept: an
-- intermediate state of the bags during a fight is of no interest to anybody.
--
-- A COLD CACHE IS WAITED FOR, ONCE. GET_ITEM_INFO_RECEIVED fires for every item
-- anything in the UI looks at, which at login is hundreds. It is only listened
-- to while a scan is actually waiting on an item, and ignored the rest of the
-- time.
--------------------------------------------------------------------------------

local PeaversCommons = _G.PeaversCommons
local Events = PeaversCommons.Events

local Scanner = PCBar.Scanner
local Bar = PCBar.Bar

local Core = {}
PCBar.Core = Core

-- Long enough to swallow the burst a looted stack or a bag sort produces, short
-- enough that the bar has caught up before the player has finished reading the
-- loot text.
local RESCAN_DELAY = 0.2

--------------------------------------------------------------------------------
-- Rescanning
--------------------------------------------------------------------------------

--- Whether there is any point doing work right now.
---
--- Switched off has to be checked here rather than only at the drawing end. The
--- bags change constantly - every loot, every vendor trip, every cooldown tick -
--- and an addon the player has turned off scanning all of it to decide not to
--- draw anything is exactly the idle cost this file is written to avoid. The
--- bar is hidden by Bar:ApplyVisibility either way; this is about not paying for
--- it. Switching back on goes through Core:ApplyConfig, which schedules the scan
--- that was skipped.
local function Enabled()
    return PCBar.Config.enabled ~= false
end

function Core:ScheduleRescan()
    if not Enabled() then return end
    if self.rescanQueued then return end
    self.rescanQueued = true

    C_Timer.After(RESCAN_DELAY, function()
        self.rescanQueued = false
        self:Rescan()
    end)
end

function Core:Rescan()
    local items, incomplete = Scanner:Scan(PCBar.Config)
    self.waitingOnItemData = incomplete
    self:ApplyItems(items)
end

function Core:ApplyItems(items)
    if InCombatLockdown() then
        self.pendingItems = items
        return
    end

    self.pendingItems = nil
    Bar:Apply(items)
end

--- Called after a settings change. A rescan comes with it, because a change to
--- the category filters, the sort order or the cap changes which items belong on
--- the bar at all.
---
--- Almost nothing here is safe mid-fight. Resizing a button, re-anchoring one
--- and showing or hiding the bar are all protected operations, so a settings
--- change made during combat - from the Items page, say - is held and applied
--- when the fight ends. Opacity is the exception and is applied at once, so the
--- one setting a player might reasonably reach for during a pull still answers.
function Core:ApplyConfig()
    if InCombatLockdown() then
        self.pendingConfig = true
        Bar:ApplyAlpha()
        return
    end

    self.pendingConfig = nil
    Bar:ApplyConfig()
    self:ScheduleRescan()
end

--------------------------------------------------------------------------------
-- Locking
--------------------------------------------------------------------------------

--- Refused in combat rather than queued. Unlocking shows the bar and takes the
--- secure visibility rule off it, neither of which is allowed mid-fight - and
--- nobody positions a pre-combat bar during a pull anyway.
--- @return boolean whether it happened
function Core:SetUnlocked(unlocked)
    if InCombatLockdown() then return false end
    Bar:SetUnlocked(unlocked)
    return true
end

--- @return boolean? unlocked the new state, or nil if combat refused the change
function Core:ToggleUnlocked()
    if InCombatLockdown() then return nil end
    return Bar:ToggleUnlocked()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Core:BindEvents()
    -- Settled rather than raw: BAG_UPDATE fires per bag, BAG_UPDATE_DELAYED
    -- fires once after the client has finished changing them.
    Events:RegisterEvent("BAG_UPDATE_DELAYED", function()
        self:ScheduleRescan()
    end)

    -- Counts and the shared potion lockout, which do not change which buttons
    -- exist. Safe in combat, and the only thing that runs during a fight.
    Events:RegisterEvent("BAG_UPDATE_COOLDOWN", function()
        if not Enabled() then return end
        Bar:Refresh()
    end)

    Events:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
        if self.waitingOnItemData then
            self:ScheduleRescan()
        end
    end)

    -- A held settings change takes precedence over a held scan, because
    -- applying the settings rescans anyway and the fresh scan is the one worth
    -- having.
    Events:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if self.pendingConfig then
            self:ApplyConfig()
        elseif self.pendingItems then
            self:ApplyItems(self.pendingItems)
        end
    end)

    -- Zoning rebuilds the bags from the server, and a reload lands here with an
    -- empty bar.
    Events:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        self:ScheduleRescan()
    end)
end

--------------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------------

function Core:Initialize()
    Bar:Initialize()
    Bar:SetUnlocked(false)
    self:BindEvents()
    self:ScheduleRescan()
end

return Core
