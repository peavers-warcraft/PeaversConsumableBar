--------------------------------------------------------------------------------
-- Where each button ends up.
--
-- Four growth directions times two orientations is eight arrangements, and the
-- only way to check one in game is to carry the right number of consumables and
-- count pixels. The maths is pure, so it is driven directly instead.
--
-- Bar.lua is loaded whole rather than having its arithmetic copied here. A test
-- that reimplements the thing it is testing agrees with itself and nothing else.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or "."
local harness = dofile(here .. "/harness.lua")

--------------------------------------------------------------------------------
-- A frame that remembers where it was put
--------------------------------------------------------------------------------

local function stub()
    local frame = { _points = {} }

    function frame:SetPoint(point, _, relativePoint, x, y)
        self._points[#self._points + 1] = {
            point = point, relativePoint = relativePoint, x = x, y = y,
        }
    end

    function frame:ClearAllPoints() self._points = {} end
    function frame:SetSize(width, height) self._width, self._height = width, height end

    ---The single anchor a laid-out button should have, as "POINT x,y".
    function frame:placement()
        if #self._points ~= 1 then
            return ("%d anchors"):format(#self._points)
        end
        local p = self._points[1]
        return ("%s %d,%d"):format(p.point, p.x, p.y)
    end

    return frame
end

--------------------------------------------------------------------------------
-- Bar, with its frame and buttons replaced
--
-- Bar:Layout reads nothing but the config, its own frame and its buttons'
-- frames, so this is the whole of what it needs. Nothing else in Bar.lua is
-- touched, and nothing in it runs at load time.
--------------------------------------------------------------------------------

local PCBar = harness.load()

do
    local path = harness.root() .. "/src/UI/Bar.lua"
    assert(loadfile(path), "cannot load " .. path)("PeaversConsumableBar", PCBar)
end

local Bar = PCBar.Bar

-- A realistic button size on purpose: Bar floors the frame at a grabbable
-- minimum, and a toy size would sit under that floor and make every size
-- assertion below a test of the floor instead of the arithmetic.
local SIZE, SPACING, PADDING = 36, 2, 2
local STEP = SIZE + SPACING

---Lay out `count` buttons under the given settings and return their placements.
---@return table placements, number width, number height
local function layout(count, overrides)
    local config = {
        buttonSize = SIZE,
        buttonSpacing = SPACING,
        buttonsPerLine = 3,
        orientation = "horizontal",
        growX = "RIGHT",
        growY = "DOWN",
    }
    for key, value in pairs(overrides or {}) do config[key] = value end
    PCBar.Config = config

    Bar.frame = stub()
    Bar.items, Bar.buttons = {}, {}
    for index = 1, count do
        Bar.items[index] = { itemID = index }
        Bar.buttons[index] = { frame = stub() }
    end

    Bar:Layout()

    local placements = {}
    for index = 1, count do
        placements[index] = Bar.buttons[index].frame:placement()
    end

    return placements, Bar.frame._width, Bar.frame._height
end

local function check(label, overrides, want)
    local placements, width, height = layout(#want.at, overrides)

    for index, expected in ipairs(want.at) do
        harness.equal(("%s: button %d"):format(label, index),
            placements[index], expected)
    end

    harness.equal(label .. ": width", width, want.width)
    harness.equal(label .. ": height", height, want.height)
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

-- Four buttons, three per line: a full row of three and one below it. The frame
-- is three wide and two tall whichever corner they were built from, so the size
-- assertions are the same in all four cases below and only the anchors move.
local ROW_WIDTH = 3 * SIZE + 2 * SPACING + PADDING * 2
local ROW_HEIGHT = 2 * SIZE + 1 * SPACING + PADDING * 2

check("rows, right and down", {}, {
    at = {
        "TOPLEFT " .. PADDING .. ",-" .. PADDING,
        "TOPLEFT " .. (PADDING + STEP) .. ",-" .. PADDING,
        "TOPLEFT " .. (PADDING + STEP * 2) .. ",-" .. PADDING,
        -- Wrapped onto the second row, back at the left.
        "TOPLEFT " .. PADDING .. ",-" .. (PADDING + STEP),
    },
    width = ROW_WIDTH, height = ROW_HEIGHT,
})

check("rows, left and down", { growX = "LEFT" }, {
    at = {
        "TOPRIGHT -" .. PADDING .. ",-" .. PADDING,
        "TOPRIGHT -" .. (PADDING + STEP) .. ",-" .. PADDING,
        "TOPRIGHT -" .. (PADDING + STEP * 2) .. ",-" .. PADDING,
        "TOPRIGHT -" .. PADDING .. ",-" .. (PADDING + STEP),
    },
    width = ROW_WIDTH, height = ROW_HEIGHT,
})

check("rows, right and up", { growY = "UP" }, {
    at = {
        "BOTTOMLEFT " .. PADDING .. "," .. PADDING,
        "BOTTOMLEFT " .. (PADDING + STEP) .. "," .. PADDING,
        "BOTTOMLEFT " .. (PADDING + STEP * 2) .. "," .. PADDING,
        -- The second row goes above the first, not below it.
        "BOTTOMLEFT " .. PADDING .. "," .. (PADDING + STEP),
    },
    width = ROW_WIDTH, height = ROW_HEIGHT,
})

check("rows, left and up", { growX = "LEFT", growY = "UP" }, {
    at = {
        "BOTTOMRIGHT -" .. PADDING .. "," .. PADDING,
        "BOTTOMRIGHT -" .. (PADDING + STEP) .. "," .. PADDING,
        "BOTTOMRIGHT -" .. (PADDING + STEP * 2) .. "," .. PADDING,
        "BOTTOMRIGHT -" .. PADDING .. "," .. (PADDING + STEP),
    },
    width = ROW_WIDTH, height = ROW_HEIGHT,
})

--------------------------------------------------------------------------------
-- Columns
--
-- The same four buttons, three per line, filling downwards first: a full column
-- of three and one beside it. Width and height swap over.
--------------------------------------------------------------------------------

check("columns, right and down", { orientation = "vertical" }, {
    at = {
        "TOPLEFT " .. PADDING .. ",-" .. PADDING,
        "TOPLEFT " .. PADDING .. ",-" .. (PADDING + STEP),
        "TOPLEFT " .. PADDING .. ",-" .. (PADDING + STEP * 2),
        -- Wrapped into a second column, back at the top.
        "TOPLEFT " .. (PADDING + STEP) .. ",-" .. PADDING,
    },
    width = ROW_HEIGHT, height = ROW_WIDTH,
})

check("columns, left and up", { orientation = "vertical", growX = "LEFT", growY = "UP" }, {
    at = {
        "BOTTOMRIGHT -" .. PADDING .. "," .. PADDING,
        "BOTTOMRIGHT -" .. PADDING .. "," .. (PADDING + STEP),
        "BOTTOMRIGHT -" .. PADDING .. "," .. (PADDING + STEP * 2),
        "BOTTOMRIGHT -" .. (PADDING + STEP) .. "," .. PADDING,
    },
    width = ROW_HEIGHT, height = ROW_WIDTH,
})

--------------------------------------------------------------------------------
-- Degenerate cases
--------------------------------------------------------------------------------

do
    local _, width, height = layout(0, {})
    -- A minimum size, so an empty bar unlocked for positioning is still big
    -- enough to find and grab.
    harness.check("an empty bar keeps a grabbable size",
        width >= 40 and height >= 40,
        ("%sx%s"):format(tostring(width), tostring(height)))
end

do
    local placements, width = layout(2, { buttonsPerLine = 0 })
    -- A line of no buttons would divide by zero and anchor everything on top of
    -- itself, so the floor is one per line - which is a column.
    harness.equal("zero per line is treated as one", #placements, 2)
    harness.equal("and wraps every button onto its own line", width,
        math.max(40, SIZE + PADDING * 2))
end

os.exit(harness.report("layout"))
