local _, PCBar = ...

--------------------------------------------------------------------------------
-- Bar
--
-- The frame the buttons live on: where it sits, how the buttons are arranged on
-- it, and when it is on screen.
--
-- VISIBILITY IS A STATE DRIVER, NOT A SCRIPT. Hiding the bar in combat is the
-- whole point of it - a pre-combat bar in the middle of the screen during a
-- pull is clutter - but a secure button cannot be hidden by Lua once combat has
-- started. So the rule is handed to the secure environment as a macro
-- conditional and the client applies it, in combat or out, without this addon
-- running at the moment it happens.
--
-- THE BUTTON POOL ONLY EVER GROWS. Releasing a button leaves the frame in place
-- for the next refresh to claim. Frames cannot be destroyed in WoW, so a pool
-- that shrank would leak a frame per bag change; this one costs one frame per
-- consumable the player has ever carried in a session.
--
-- IDLE COST IS ZERO. There is no OnUpdate anywhere in this addon. The cooldown
-- sweep is a Cooldown widget, which the client animates itself, and everything
-- else is driven by bag events.
--------------------------------------------------------------------------------

local Button = PCBar.Button

local Bar = {}
PCBar.Bar = Bar

Bar.buttons = {}
Bar.items = {}
Bar.unlocked = false

local PADDING = 2
local MIN_SIZE = 40

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
}

-- What each visibility mode means to the secure environment. "show" with no
-- condition is still registered rather than skipped, so there is one code path
-- and no chance of a stale driver from a previous setting surviving a change.
local VISIBILITY = {
    always = "show",
    outOfCombat = "[combat] hide; show",
    inCombat = "[combat] show; hide",
}

Bar.VISIBILITY_MODES = {
    { value = "outOfCombat", label = "Only out of combat" },
    { value = "always",      label = "Always" },
    { value = "inCombat",    label = "Only in combat" },
}

Bar.ORIENTATIONS = {
    { value = "horizontal", label = "Rows (fills sideways, then wraps)" },
    { value = "vertical",   label = "Columns (fills vertically, then wraps)" },
}

Bar.GROW_X = {
    { value = "RIGHT", label = "To the right" },
    { value = "LEFT",  label = "To the left" },
}

Bar.GROW_Y = {
    { value = "DOWN", label = "Downwards" },
    { value = "UP",   label = "Upwards" },
}

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function Bar:Initialize()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "PeaversConsumableBarFrame", UIParent,
        "BackdropTemplate")
    frame:SetSize(MIN_SIZE, MIN_SIZE)
    frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 240)
    frame:SetBackdrop(BACKDROP)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    -- Off until the bar is being positioned. The frame is larger than the
    -- buttons on it and invisible unless a background is turned on, so a
    -- mouse-enabled container would quietly swallow clicks aimed at whatever is
    -- behind it. Hover is detected from the buttons and checked against the
    -- frame's rectangle, neither of which needs the mouse enabled here.
    frame:EnableMouse(false)

    -- Only visible while the bar is unlocked, so an empty or still-loading bar
    -- can be found and dragged. The buttons carry their own borders the rest of
    -- the time.
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("CENTER")
    hint:SetText("Consumable Bar")
    hint:Hide()
    self.hint = hint

    self.frame = frame
    self:ApplyChrome()
    return frame
end

--------------------------------------------------------------------------------
-- Hover fade
--
-- Checked against the frame rectangle rather than tracked as a count of enters
-- and leaves. Moving the cursor from the bar onto one of its own buttons fires
-- a leave on the bar and an enter on the button, and the reverse on the way
-- back; counting those correctly across a wrapped grid is more bookkeeping than
-- asking the frame where the cursor is.
--------------------------------------------------------------------------------

function Bar:SetHovered(hovered)
    if hovered then
        self.hovered = true
        self:ApplyAlpha()
        return
    end

    -- Deferred a frame: at the moment a leave fires the cursor may already be
    -- over a sibling button, and IsMouseOver on the parent is only correct once
    -- the move has settled.
    C_Timer.After(0, function()
        if not self.frame then return end
        self.hovered = self.frame:IsMouseOver() and true or false
        self:ApplyAlpha()
    end)
end

function Bar:ApplyAlpha()
    local config = PCBar.Config
    if not self.frame then return end

    if self:IsPositioning() then
        self.frame:SetAlpha(1)
        return
    end

    local base = config.barAlpha or 1
    local idle = config.fadeAlpha or base
    self.frame:SetAlpha(self.hovered and base or math.min(base, idle))
end

--------------------------------------------------------------------------------
-- Chrome
--------------------------------------------------------------------------------

function Bar:ApplyChrome()
    local config = PCBar.Config
    if not self.frame then return end

    local bg = config.bgColor or { r = 0, g = 0, b = 0 }

    -- Unlocked always paints the backdrop, whatever the setting says: an
    -- invisible frame is one you cannot find to drag, and with no consumables in
    -- the bags there are no buttons to aim at either.
    local painted = self:IsPositioning() or config.showFrameBackground
    self.frame:SetBackdropColor(bg.r, bg.g, bg.b, painted and (config.bgAlpha or 0.8) or 0)
    self.frame:SetBackdropBorderColor(1, 1, 1, self:IsPositioning() and 0.4 or 0)
    self.frame:SetFrameStrata(config.frameStrata or "MEDIUM")
    self.frame:EnableMouse(self:IsPositioning())
    self:ApplyAlpha()
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

function Bar:ApplyPosition()
    local config = PCBar.Config
    if not self.frame then return end

    self.frame:ClearAllPoints()
    self.frame:SetPoint(
        config.framePoint or "BOTTOM",
        UIParent,
        config.frameRelativePoint or config.framePoint or "BOTTOM",
        config.frameX or 0,
        config.frameY or 240)
end

function Bar:SavePosition()
    local config = PCBar.Config
    local point, _, relativePoint, x, y = self.frame:GetPoint()

    config.framePoint = point or "BOTTOM"
    -- Kept separately because StopMovingOrSizing is free to leave a frame
    -- anchored by a different corner than it was picked up by.
    config.frameRelativePoint = relativePoint or point or "BOTTOM"
    config.frameX = x or 0
    config.frameY = y or 0
    config:Save()
end

--- Unlocked for dragging, or held open by Edit Mode. Either way the bar is on
--- screen and painted, because a bar that hides in combat or hides when the
--- bags are empty has no handle to grab at the moment you want to place it.
function Bar:IsPositioning()
    return (self.unlocked or self.editMode) and true or false
end

--- Edit Mode owns the drag while it is open, through its own overlay, so this
--- forces the bar visible but leaves the drag handlers off - two systems
--- answering one drag is one of them losing.
function Bar:SetEditModeActive(active)
    self.editMode = active and true or false
    if not self.frame then return end

    self.frame:RegisterForDrag()
    self.frame:SetScript("OnDragStart", nil)
    self.frame:SetScript("OnDragStop", nil)

    self.hint:SetShown(self:IsPositioning())
    self:ApplyChrome()
    self:ApplyVisibility()
end

function Bar:SetUnlocked(unlocked)
    self.unlocked = unlocked and true or false
    if not self.frame then return end

    if self.unlocked and not self.editMode then
        self.frame:RegisterForDrag("LeftButton")
        self.frame:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
        self.frame:SetScript("OnDragStop", function(frame)
            frame:StopMovingOrSizing()
            self:SavePosition()
            self:ApplyPosition()
        end)
    else
        self.frame:RegisterForDrag()
        self.frame:SetScript("OnDragStart", nil)
        self.frame:SetScript("OnDragStop", nil)
    end

    self.hint:SetShown(self:IsPositioning())
    self:ApplyChrome()
    self:ApplyVisibility()
end

function Bar:ToggleUnlocked()
    self:SetUnlocked(not self.unlocked)
    return self.unlocked
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------

function Bar:ApplyVisibility()
    local config = PCBar.Config
    if not self.frame then return end

    -- Switched off beats every other rule below, Edit Mode included. A player
    -- who has said they do not want this bar should not have it reappear
    -- because they opened Edit Mode to move something else - the checkbox in
    -- the dialog is how they get it back, not the bar turning up uninvited.
    if config.enabled == false then
        UnregisterStateDriver(self.frame, "visibility")
        self.frame:Hide()
        return
    end

    -- While it is being positioned the bar stays on screen whatever the rule
    -- says, and whether or not there is anything in the bags to put on it.
    if self:IsPositioning() then
        UnregisterStateDriver(self.frame, "visibility")
        self.frame:Show()
        return
    end

    if #self.items == 0 and config.hideWhenEmpty ~= false then
        UnregisterStateDriver(self.frame, "visibility")
        -- Safe even mid-combat: the bar frame itself is unprotected, and with no
        -- items on it there is no secure button to take down with it.
        self.frame:Hide()
        return
    end

    RegisterStateDriver(self.frame, "visibility",
        VISIBILITY[config.visibility] or VISIBILITY.outOfCombat)
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

function Bar:AcquireButton(index)
    local button = self.buttons[index]
    if button then return button end

    button = Button.New(self.frame, index, function(hovered)
        self:SetHovered(hovered)
    end)
    self.buttons[index] = button
    return button
end

--- Which corner of its own frame the grid is built out from, and which way one
--- step along each axis moves. Growing left means starting at the right-hand
--- corner and stepping backwards, which is the same thing said twice - hence
--- deriving both from one answer rather than letting them disagree.
--- @return string corner, number stepX, number stepY
local function GrowthFrom(config)
    local toLeft = config.growX == "LEFT"
    local toUp = config.growY == "UP"

    return (toUp and "BOTTOM" or "TOP") .. (toLeft and "RIGHT" or "LEFT"),
        toLeft and -1 or 1,
        toUp and 1 or -1
end

--- Place the buttons and size the frame around them.
---
--- The frame is resized to fit its buttons, and the buttons are anchored from
--- whichever of its corners the growth settings name. So the growth settings
--- decide the order the buttons march in, and the frame's own anchor point
--- decides which edge stays still as the number of consumables changes: a bar
--- anchored BOTTOMLEFT keeps its left edge, one anchored BOTTOM stays centred.
--- The two are worth setting together - growing left from a bar anchored
--- BOTTOMRIGHT is the arrangement that neither moves nor wraps unexpectedly.
function Bar:Layout()
    local config = PCBar.Config
    local size = config.buttonSize or 36
    local spacing = config.buttonSpacing or 2
    local perLine = math.max(1, config.buttonsPerLine or 12)
    local count = #self.items
    local vertical = config.orientation == "vertical"

    local corner, stepX, stepY = GrowthFrom(config)

    for index = 1, count do
        local button = self.buttons[index]
        if button then
            local offset = index - 1
            local column, row

            -- perLine counts along the axis the buttons fill first: across a
            -- row when horizontal, down a column when vertical.
            if vertical then
                column, row = math.floor(offset / perLine), offset % perLine
            else
                column, row = offset % perLine, math.floor(offset / perLine)
            end

            button.frame:ClearAllPoints()
            button.frame:SetPoint(corner, self.frame, corner,
                stepX * (PADDING + column * (size + spacing)),
                stepY * (PADDING + row * (size + spacing)))
        end
    end

    local filled = math.min(count, perLine)
    local lines = count > 0 and math.ceil(count / perLine) or 0

    local columns, rows
    if vertical then
        columns, rows = lines, filled
    else
        columns, rows = filled, lines
    end

    local width = columns > 0 and (columns * size + (columns - 1) * spacing) or 0
    local height = rows > 0 and (rows * size + (rows - 1) * spacing) or 0

    self.frame:SetSize(
        math.max(MIN_SIZE, width + PADDING * 2),
        math.max(MIN_SIZE, height + PADDING * 2))
end

--------------------------------------------------------------------------------
-- Contents
--------------------------------------------------------------------------------

--- Hand the bar a fresh set of items. Only ever called out of combat: every
--- call below either rewrites a secure attribute or shows a protected frame.
--- @param items table scanner entries, already ordered
function Bar:Apply(items)
    self:Initialize()
    self.items = items

    for index = 1, #items do
        local button = self:AcquireButton(index)
        button:Layout(PCBar.Config)
        button:SetItem(items[index])
    end

    for index = #items + 1, #self.buttons do
        self.buttons[index]:Release()
    end

    self:Layout()
    self:ApplyChrome()
    self:ApplyPosition()
    self:ApplyVisibility()
end

--- Re-apply the appearance settings without touching what is on the buttons.
--- Used when a setting changes, which may happen in combat; nothing it calls is
--- protected.
function Bar:ApplyConfig()
    if not self.frame then return end

    for index = 1, #self.items do
        local button = self.buttons[index]
        if button then button:Layout(PCBar.Config) end
    end

    self:Layout()
    self:ApplyChrome()
    self:ApplyPosition()
    self:ApplyVisibility()
end

--- Counts and cooldown sweeps. Safe in combat, and the only thing that runs
--- while the player is fighting.
function Bar:Refresh()
    for index = 1, #self.items do
        local button = self.buttons[index]
        if button then button:Refresh() end
    end
end

return Bar
