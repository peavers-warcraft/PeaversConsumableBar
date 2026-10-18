local _, PCBar = ...

--------------------------------------------------------------------------------
-- Edit Mode
--
-- One frame, so one registration. The schema here is the whole of the addon's
-- settings bar the per-item ignore list, which lives on its own page in
-- PeaversConfig: a scrolling list of everything in your bags is not something
-- an Edit Mode dialog has room for.
--
-- The config is flat, so the schema needs no scope - every entry reads and
-- writes the config table itself.
--------------------------------------------------------------------------------

local PeaversCommons = _G.PeaversCommons

local Categories = PCBar.Categories
local Scanner = PCBar.Scanner
local Bar = PCBar.Bar

local EditMode = {}
PCBar.EditMode = EditMode

--------------------------------------------------------------------------------
-- Applying a change
--------------------------------------------------------------------------------

function PCBar.ApplySetting()
    if PCBar.Core and PCBar.Core.ApplyConfig then
        PCBar.Core:ApplyConfig()
    end
end

--------------------------------------------------------------------------------
-- Groups
--------------------------------------------------------------------------------

EditMode.SECTIONS = {
    { key = "layout", label = "Layout" },
    { key = "position", label = "Position" },
    { key = "behaviour", label = "Behaviour" },
    { key = "contents", label = "What To Show" },
    { key = "appearance", label = "Appearance" },
}

-- The quality names the client already has, so the dropdown reads in the
-- player's own language rather than in English item-tooltip jargon.
local function QualityValues()
    local values = {}
    for quality = 0, 4 do
        values[#values + 1] = {
            value = quality,
            label = _G["ITEM_QUALITY" .. quality .. "_DESC"] or tostring(quality),
        }
    end
    return values
end

local function CategoryEntries()
    local entries = {}
    for _, category in ipairs(Categories.LIST) do
        entries[#entries + 1] = {
            key = Categories.ConfigKey(category.key),
            label = category.label,
            kind = "checkbox",
            section = "contents",
            default = category.default,
        }
    end
    return entries
end

EditMode.ENTRIES = {
    ---------------------------------------------------------------- layout ---
    {
        key = "buttonSize", label = "Button Size", kind = "slider", section = "layout",
        min = 20, max = 64, step = 1, unit = "px", default = 36,
    },
    {
        key = "buttonSpacing", label = "Spacing", kind = "slider", section = "layout",
        min = 0, max = 16, step = 1, unit = "px", default = 2,
    },
    {
        key = "orientation", label = "Arrangement", kind = "dropdown", section = "layout",
        fallback = "horizontal", values = Bar.ORIENTATIONS,
    },
    {
        key = "buttonsPerLine", label = "Buttons Per Line", kind = "slider",
        section = "layout", min = 1, max = 24, step = 1, default = 12,
        desc = "How many buttons before the bar wraps onto another row or column.",
    },
    {
        key = "growX", label = "Grow Sideways", kind = "dropdown",
        section = "layout", fallback = "RIGHT", values = Bar.GROW_X,
        desc = "In rows, the direction the buttons march. In columns, the "
            .. "direction each new column is added.",
    },
    {
        key = "growY", label = "Grow Vertically", kind = "dropdown",
        section = "layout", fallback = "DOWN", values = Bar.GROW_Y,
        desc = "In rows, the direction each new row is added. In columns, the "
            .. "direction the buttons march.",
    },

    -------------------------------------------------------------- position ---
    {
        key = "framePoint", label = "Anchor", kind = "dropdown", section = "position",
        fallback = "BOTTOM",
        desc = "Buttons grow right and down from the bar's top-left corner, so "
            .. "the anchor decides which edge stays still as the number of "
            .. "consumables changes.",
        values = {
            { value = "CENTER", label = "Centre" },
            { value = "TOP", label = "Top" },
            { value = "BOTTOM", label = "Bottom" },
            { value = "TOPLEFT", label = "Top left" },
            { value = "TOPRIGHT", label = "Top right" },
            { value = "BOTTOMLEFT", label = "Bottom left" },
            { value = "BOTTOMRIGHT", label = "Bottom right" },
        },
    },
    { key = "frameX", label = "X Offset", kind = "number", section = "position", default = 0 },
    { key = "frameY", label = "Y Offset", kind = "number", section = "position", default = 240 },

    ------------------------------------------------------------- behaviour ---
    {
        key = "visibility", label = "Show The Bar", kind = "dropdown",
        section = "behaviour", surface = "config",
        fallback = "outOfCombat", values = Bar.VISIBILITY_MODES,
        desc = "Hiding in combat is handled by the game itself, so it still "
            .. "works during a fight.",
    },
    {
        key = "hideWhenEmpty", label = "Hide When Empty", kind = "checkbox",
        section = "behaviour", default = true,
        desc = "Takes the bar off screen entirely when nothing in your bags "
            .. "matches, rather than leaving an empty frame behind.",
    },
    {
        key = "sortMode", label = "Order", kind = "dropdown", section = "behaviour",
        surface = "config", fallback = "category", values = Scanner.SORT_MODES,
    },
    {
        key = "maxButtons", label = "Most Buttons", kind = "slider",
        section = "behaviour", min = 4, max = 60, step = 1, default = 24,
        desc = "A ceiling, not a target. With the default order the newest of "
            .. "each kind comes first, so a cap trims the oldest.",
    },
    {
        key = "minQuality", label = "Lowest Quality", kind = "dropdown",
        section = "behaviour", surface = "config", fallback = 1,
        values = QualityValues(),
    },
    {
        key = "hideConjured", label = "Hide Conjured Items", kind = "checkbox",
        section = "behaviour", default = false,
        desc = "Mage food and water, and anything else summoned rather than "
            .. "made - which includes Healthstones, so leave this off if you "
            .. "want yours on the bar.",
    },

    ------------------------------------------------------------ appearance ---
    {
        key = "barAlpha", label = "Opacity", kind = "slider", section = "appearance",
        min = 0.1, max = 1, step = 0.05, unit = "percent", default = 1,
    },
    {
        key = "fadeAlpha", label = "Opacity When Not Hovered", kind = "slider",
        section = "appearance", min = 0.1, max = 1, step = 0.05, unit = "percent",
        default = 1,
        desc = "Set below the opacity above to fade the bar out until you put "
            .. "the cursor on it.",
    },
    {
        key = "showCount", label = "Show Stack Counts", kind = "checkbox",
        section = "appearance", default = true,
    },
    {
        key = "showCooldownText", label = "Show Cooldown Numbers", kind = "checkbox",
        section = "appearance", default = true,
    },
    {
        key = "colorByQuality", label = "Colour Borders By Quality", kind = "checkbox",
        section = "appearance", default = true,
    },
    {
        key = "borderColor", label = "Border Colour", kind = "color",
        section = "appearance", default = { r = 0, g = 0, b = 0 },
        hidden = function(cfg) return cfg.colorByQuality end,
    },
    {
        key = "showFrameBackground", label = "Show A Background", kind = "checkbox",
        section = "appearance", default = false, revealsOthers = true,
    },
    {
        key = "bgColor", section = "appearance",
        hidden = function(cfg) return not cfg.showFrameBackground end,
    },
    {
        key = "bgAlpha", section = "appearance",
        hidden = function(cfg) return not cfg.showFrameBackground end,
    },
    {
        key = "frameStrata", label = "Layer", kind = "dropdown", section = "appearance",
        surface = "config", fallback = "MEDIUM",
        desc = "Which layer the bar sits on, if something else is covering it.",
        values = {
            { value = "LOW", label = "Low" },
            { value = "MEDIUM", label = "Medium" },
            { value = "HIGH", label = "High" },
            { value = "DIALOG", label = "Dialog" },
        },
    },
}

for _, entry in ipairs(CategoryEntries()) do
    EditMode.ENTRIES[#EditMode.ENTRIES + 1] = entry
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

function EditMode:BuildSchema()
    if self.schema then return self.schema end

    self.schema = PeaversCommons.SettingsSchema:New({
        config = PCBar.Config,
        sections = self.SECTIONS,
        entries = self.ENTRIES,
        apply = function() PCBar.ApplySetting() end,
    })

    return self.schema
end

function EditMode:Register()
    if not PeaversCommons.EditMode or not PeaversCommons.EditMode.available then
        return false
    end
    if self.registered then return true end

    local frame = Bar.frame
    if not frame then return false end

    local config = PCBar.Config

    PeaversCommons.EditMode:Register({
        frame = frame,
        name = "Peavers Consumable Bar",
        schema = self:BuildSchema(),
        default = {
            point = config.framePoint or "BOTTOM",
            x = config.frameX or 0,
            y = config.frameY or 240,
        },

        onPositionChanged = function(movedFrame, point, x, y)
            local _, _, relativePoint = movedFrame:GetPoint()
            config.framePoint = point
            config.frameRelativePoint = relativePoint or point
            config.frameX = x
            config.frameY = y
            config:Save()
        end,

        -- Forces the bar visible and takes our own drag handlers off: a bar set
        -- to hide in combat, or hidden because the bags hold nothing, has no
        -- handle for Edit Mode to grab.
        onEnter = function() Bar:SetEditModeActive(true) end,

        onExit = function()
            Bar:SetEditModeActive(false)
            PCBar.ApplySetting()
        end,
    })

    self.registered = true
    return true
end

return EditMode
