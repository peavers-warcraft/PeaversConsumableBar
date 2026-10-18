local addonName, PCBar = ...

--------------------------------------------------------------------------------
-- ConfigUI
--
-- Two pages in PeaversConfig.
--
-- Information, which is the standard page: what the addon does, the slash
-- commands, and the notice that the settings themselves are in Edit Mode.
--
-- Items, which is this addon's own. The category filters answer "show me my
-- flasks"; they cannot answer "but not that one". A per-item switch needs the
-- whole list of consumables in your bags with a row each, which is a scrolling
-- list - exactly the shape an Edit Mode dialog has no room for, and exactly the
-- shape a settings page with a scroll bar is for.
--------------------------------------------------------------------------------

local ConfigUI = {}
PCBar.ConfigUI = ConfigUI

local PeaversCommons = _G.PeaversCommons
if not PeaversCommons then
    print("|cffff0000Error:|r PeaversCommons not found.")
    return
end

local W = PeaversCommons.Widgets
local Style = PeaversCommons.Style
local ConfigUIUtils = PeaversCommons.ConfigUIUtils

local Categories = PCBar.Categories
local Scanner = PCBar.Scanner

local INDENT = 25
local ROW_HEIGHT = 26
local ICON_SIZE = 18

-- Room kept on the right of every row for the note, so a long item name is
-- clipped by its own checkbox rather than running underneath "category off".
local NOTE_WIDTH = 120

--------------------------------------------------------------------------------
-- Information
--------------------------------------------------------------------------------

function ConfigUI:BuildInfoPage(parentFrame)
    ConfigUIUtils.BuildInfoPageWithEditMode(parentFrame, "Consumable Bar", {
        "Puts the consumables already in your bags onto a bar, so applying a "
            .. "flask, a weapon oil and your food before a pull is three clicks "
            .. "in one place instead of three trips through your bags.",

        { command = "/pcbar", desc = "open the settings" },
        { command = "/pcbar list", desc = "print every consumable found, with its category" },
        { command = "/pcbar unlock", desc = "show the bar so it can be dragged" },
        { command = "/pcbar lock", desc = "finish positioning" },
        { command = "/pcbar reset", desc = "restore every setting to its default" },

        { header = "What lands on the bar" },
        "Anything in your bags that the game itself files under a category you "
            .. "have turned on, and that has something to do when you click it. "
            .. "Nothing is matched by name and nothing comes from a list of item "
            .. "IDs, so a flask added in a patch appears without this addon being "
            .. "updated. Flasks, potions, food and weapon oils are on to begin "
            .. "with; elixirs, bandages, scrolls and the long tail are off, "
            .. "because a full set of bags holds far more consumables than anyone "
            .. "wants on screen.",
        { header = "One item at a time" },
        "The Items tab above lists every consumable in your bags with a tick "
            .. "each, and the tick overrules the category both ways. Tick an item "
            .. "whose category is off and it goes on the bar anyway - which is "
            .. "how you get one weapon oil without turning on the whole of Other "
            .. "Consumables. Untick one whose category is on and it stays off, "
            .. "for the flask you are saving rather than drinking.",
        "An override also skips the quality floor and the conjured filter, "
            .. "because it is you saying rather than the addon guessing. Only the "
            .. "difference from the category is remembered, so turning a category "
            .. "on later still sweeps in everything you never spoke about.",
        "Not sure which category something is in? /pcbar list prints every "
            .. "consumable it found with its category and whether it is on the "
            .. "bar. An item you have spoken for and then run out of keeps a row "
            .. "at the bottom of the Items page, with a Reset button, so one "
            .. "choice can be undone without clearing them all.",
        "Hide Conjured Items clears out mage food and water in one go. It "
            .. "catches Healthstones too, since those are summoned as well, so "
            .. "leave it off if you want yours on the bar.",

        { header = "Which way it grows" },
        "Grow Sideways and Grow Vertically decide the corner the buttons are "
            .. "built out from. The bar resizes itself around them, so pair the "
            .. "growth with the anchor: growing right from a bar anchored "
            .. "bottom-left keeps its left edge still as consumables come and "
            .. "go, and growing left from one anchored bottom-right keeps its "
            .. "right edge still.",

        { header = "In combat" },
        "The bar hides itself in combat by default. That is handled by the game "
            .. "rather than by this addon, which is the only way it can work: an "
            .. "addon may not touch a button that can use an item once a fight "
            .. "has started, so the rule is handed over before combat and the "
            .. "client applies it. Anything that changes which buttons exist "
            .. "waits for the fight to end.",

        { header = "Built for performance" },
        "There is no OnUpdate anywhere in this addon. The bar is rebuilt when "
            .. "your bags change and at no other time, and a burst of bag events "
            .. "- looting a stack, sorting, vendoring a bagful - is coalesced "
            .. "into a single scan. Cooldown sweeps are drawn by the client's own "
            .. "Cooldown widget. Idle cost is nil.",
    }, {
        title = "the consumable bar",
        select = "the consumable bar",
        reset = function()
            PCBar.Config:Reset()
            if PCBar.ApplySetting then PCBar.ApplySetting() end
            if PeaversCommons.EditModePanel then
                PeaversCommons.EditModePanel:Refresh()
            end
            self:Rebuild()
        end,
    })
end

--------------------------------------------------------------------------------
-- Items
--
-- A checkbox per item, grouped by the same categories the bar orders by. A
-- ticked row is on the bar.
--
-- The box asks "show this on the bar", and it answers in both directions: it
-- can pull an item out of a category that is on, and it can pull one in from a
-- category that is off. Those are the same question to the player, so they are
-- the same control - and what gets stored is only the difference from the
-- category, never the current answer for every item.
--
-- Stated as "show this" rather than "hide this" even though hiding is the more
-- common use. A page of boxes where ticking one makes something vanish reads
-- backwards, and the stored shape should not decide how the question is put.
--------------------------------------------------------------------------------

local function CategoryLabel(key)
    local category = Categories.BY_KEY[key]
    return category and category.label or key
end

--- The frame, icon and right-hand note every row shares.
--- @return Frame row, Texture icon
local function RowFrame(container, y, width, item, note)
    local row = CreateFrame("Frame", nil, container)
    row:SetSize(width, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, y)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", 0, 0)
    icon:SetTexture(item.icon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    if note then
        local label = Style.Label(row, note, Style.Size.value, Style.Alpha.muted)
        label:SetPoint("RIGHT", -4, 0)
    end

    return row, icon
end

--- What the right-hand side of a row says, when it has anything to say.
---
--- The tick already shows whether the item is on the bar. What it cannot show is
--- *why*, and the case that matters is a ticked item in a category that is off -
--- which is the bar obeying an override rather than contradicting its own
--- settings. An untouched item in an off category names the category, so the
--- player can see at a glance that turning it on is the other way out.
local function RowNote(itemID, category)
    local config = PCBar.Config
    local override = config:GetOverride(itemID)
    local byCategory = config:IsCategoryShown(category)

    if override == true and not byCategory then return "shown anyway" end
    if override == false and byCategory then return "hidden by you" end
    if override == nil and not byCategory then
        return (CategoryLabel(category)) .. " off"
    end
    return nil
end

--- One item in the bags: its icon and a tick meaning "show this on the bar".
---
--- The tick says what the player wants, not what is stored. Ticking an item in a
--- category that is switched off pins it on; unticking one in a category that is
--- on pins it off; and matching the category again stores nothing at all.
--- @return number nextY
local function ItemRow(container, y, width, item)
    local config = PCBar.Config
    local itemID, category = item.itemID, item.category

    local _, icon = RowFrame(container, y, width, item, RowNote(itemID, category))

    local checkbox = W:CreateCheckbox(icon:GetParent(), item.name, {
        width = width - (ICON_SIZE + 8) - NOTE_WIDTH,
        checked = config:IsItemShown(itemID, category),
        onChange = function(checked)
            config:SetItemShown(itemID, checked, category)
            if PCBar.ApplySetting then PCBar.ApplySetting() end
        end,
    })
    checkbox:SetPoint("LEFT", icon, "RIGHT", 8, 0)

    return y - ROW_HEIGHT
end

--- An item the player has spoken for that is no longer in their bags.
---
--- A tick here would be a question with no good answer: the item is not in the
--- bags, so "show this on the bar" is neither true nor false. The only useful
--- action is to stop overriding it, so that is the only control - as a button
--- that says so, rather than a checkbox that means something different from
--- every other checkbox on the page.
--- @return number nextY
local function OverrideRow(container, y, width, item, onChanged)
    local row, icon = RowFrame(container, y, width, item,
        item.override == true and "shown anyway" or "hidden by you")

    local name = Style.Label(row, item.name, Style.Size.label, Style.Alpha.primary)
    name:SetPoint("LEFT", icon, "RIGHT", 8, 0)

    local reset = W:CreateButton(row, "Reset", {
        width = 70,
        height = 20,
        onClick = function()
            PCBar.Config:ClearOverride(item.itemID)
            if PCBar.ApplySetting then PCBar.ApplySetting() end
            if onChanged then onChanged() end
        end,
    })
    reset:SetPoint("RIGHT", -(NOTE_WIDTH + 4), 0)

    return y - ROW_HEIGHT
end

--- Items the player has hidden that are no longer in their bags.
---
--- Without this a hidden item that leaves the bags cannot be brought back: it
--- has no row, because the list is built from what is in the bags. The only way
--- out was Show All Again, which un-hides everything and loses the other
--- choices with it.
--- @return table
local function StrandedOverrides(found)
    local config = PCBar.Config
    local stranded = {}

    for itemID, override in pairs(config.overrides or {}) do
        if not found[itemID] then
            stranded[#stranded + 1] = {
                itemID = itemID,
                override = override,
                -- Named if the client still remembers it, and by ID if not. An
                -- item ID is a poor label, but it is the honest one, and it is
                -- still enough to identify the right row.
                name = C_Item.GetItemNameByID(itemID) or ("Item " .. itemID),
                icon = C_Item.GetItemIconByID(itemID),
            }
        end
    end

    table.sort(stranded, function(a, b) return a.name < b.name end)
    return stranded
end

--- @param onChanged function rebuilds the list, for rows that remove themselves
function ConfigUI:BuildItemRows(container, width, onChanged)
    local items = Scanner:ScanAll()
    local found = {}
    local y = 0
    local lastCategory = nil

    for _, item in ipairs(items) do
        found[item.itemID] = true

        if item.category ~= lastCategory then
            lastCategory = item.category
            y = y - 12
            local _, nextY = W:CreateSectionHeader(container,
                CategoryLabel(item.category), 0, y, { width = width })
            y = nextY - 4
        end

        y = ItemRow(container, y, width, item)
    end

    if #items == 0 then
        local empty = Style.Label(container,
            "No consumables found in your bags.", Style.Size.label, Style.Alpha.muted)
        empty:SetPoint("TOPLEFT", 0, y)
        y = y - 30
    end

    local stranded = StrandedOverrides(found)
    if #stranded > 0 then
        y = y - 12
        local _, nextY = W:CreateSectionHeader(container,
            "Spoken For, Not In Your Bags", 0, y, { width = width })
        y = nextY - 4

        for _, item in ipairs(stranded) do
            y = OverrideRow(container, y, width, item, onChanged)
        end
    end

    return math.abs(y)
end

function ConfigUI:BuildItemsPage(parentFrame)
    local width = parentFrame:GetWidth()
    if not width or width <= 100 then width = 360 end
    width = width - (INDENT * 2) - 10

    local title = Style.Label(parentFrame, "Items", Style.Size.hero, Style.Alpha.primary)
    title:SetPoint("TOPLEFT", INDENT, -10)

    local intro = Style.Label(parentFrame,
        "Every consumable in your bags. Tick one to put it on the bar even if its "
            .. "category is off; untick one to keep it off even if its category is on.",
        Style.Size.value, Style.Alpha.secondary)
    intro:SetPoint("TOPLEFT", INDENT, -40)
    intro:SetWidth(width)
    intro:SetJustifyH("LEFT")

    -- The rows live in a container of their own so they can be thrown away and
    -- built again without disturbing the title or the buttons. PeaversConfig
    -- caches a page once it is built, so without this a page opened before you
    -- looted a flask would never mention it.
    local container = CreateFrame("Frame", nil, parentFrame)
    container:SetPoint("TOPLEFT", INDENT, -120)
    container:SetWidth(width)

    local Populate

    Populate = function()
        if container.rows then
            container.rows:Hide()
            container.rows:SetParent(nil)
        end

        local rows = CreateFrame("Frame", nil, container)
        rows:SetPoint("TOPLEFT")
        rows:SetWidth(width)
        container.rows = rows

        -- Deferred by a frame when a row asks for it: the row that asked is
        -- about to be reparented away underneath its own click handler.
        local height = self:BuildItemRows(rows, width, function()
            C_Timer.After(0, Populate)
        end)

        rows:SetHeight(height)
        container:SetHeight(height)
        parentFrame:SetHeight(height + 150)
    end

    local rescan = W:CreateButton(parentFrame, "Rescan Bags", {
        width = 150,
        onClick = function() Populate() end,
    })
    rescan:SetPoint("TOPLEFT", INDENT, -84)

    local clear = W:CreateButton(parentFrame, "Forget Every Choice", {
        width = 170,
        onClick = function()
            PCBar.Config:ClearOverrides()
            if PCBar.ApplySetting then PCBar.ApplySetting() end
            Populate()
        end,
    })
    clear:SetPoint("TOPLEFT", INDENT + 158, -84)

    Populate()
end

--------------------------------------------------------------------------------
-- Page registration
--------------------------------------------------------------------------------

function ConfigUI:GetPages()
    return {
        { key = "info", label = "Information", builder = function(f) self:BuildInfoPage(f) end },
        { key = "items", label = "Items", builder = function(f) self:BuildItemsPage(f) end },
    }
end

-- Ask PeaversConfig to throw its cached pages away and build them again. Needed
-- after a reset, where the controls on screen are bound to a config table that
-- no longer exists. Deferred a frame so the click handler that triggered it has
-- returned before its own page is torn down.
function ConfigUI:Rebuild()
    local PeaversConfig = _G.PeaversConfig
    local contentArea = PeaversConfig and PeaversConfig.ContentArea
    if not contentArea or not contentArea.InvalidateCache then return end

    C_Timer.After(0, function()
        contentArea:InvalidateCache(addonName)
        if contentArea.ShowAddon then
            contentArea:ShowAddon(addonName)
        end
    end)
end

function ConfigUI:OpenOptions()
    if _G.PeaversConfig and _G.PeaversConfig.MainFrame then
        _G.PeaversConfig.MainFrame:Show()
        _G.PeaversConfig.MainFrame:SelectAddon("PeaversConsumableBar")
        return
    end

    if Settings and Settings.OpenToCategory then
        if PCBar.directSettingsCategoryID then
            if pcall(Settings.OpenToCategory, PCBar.directSettingsCategoryID) then return end
        end
        if PCBar.directCategoryID then
            if pcall(Settings.OpenToCategory, PCBar.directCategoryID) then return end
        end
    end

    if SettingsPanel then
        SettingsPanel:Open()
    end
end

function ConfigUI:BuildIntoFrame(parentFrame)
    self:BuildInfoPage(parentFrame)
    return parentFrame
end

function ConfigUI:Initialize()
end

return ConfigUI
