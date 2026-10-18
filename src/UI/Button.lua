local _, PCBar = ...

--------------------------------------------------------------------------------
-- Button
--
-- One consumable, as a secure action button.
--
-- Clicking an item has to go through the secure environment: no addon may use
-- an item on the player's behalf, it may only build a button the player clicks.
-- That makes two things true of everything in this file.
--
-- THE ACTION IS A MACRO, NOT A BAG SLOT. The item attribute also accepts a bag
-- and slot pair, and that is the obvious thing to write - the scanner already
-- knows where the item is. It is also wrong the moment the player moves a stack
-- or a bag sorts itself, and the button then uses whatever landed in that slot.
-- "/use item:<id>" names the item rather than its location, so it stays correct
-- through any amount of rearranging.
--
-- NOTHING HERE MAY RUN IN COMBAT. A secure button is a protected frame: its
-- attributes cannot be rewritten and it cannot be shown or hidden while the
-- player is in combat. Every call into this file therefore comes from Bar, which
-- holds changes until combat ends. Textures, text and the cooldown sweep are not
-- protected and are updated freely.
--------------------------------------------------------------------------------

local PeaversCommons = _G.PeaversCommons
local Utils = PeaversCommons.Utils

local Button = {}
PCBar.Button = Button
Button.__index = Button

local ICON_INSET = 1

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
}

-- Items share one cooldown family far more often than spells do - every combat
-- potion in the game is on the same five-minute lockout - so the sweep is read
-- per item on every refresh rather than cached per button.
local function ItemCooldown(itemID)
    if C_Item and C_Item.GetItemCooldown then
        return C_Item.GetItemCooldown(itemID)
    end
    if C_Container and C_Container.GetItemCooldown then
        return C_Container.GetItemCooldown(itemID)
    end
    return nil
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

--- @param parent Frame the bar frame
--- @param index number position in the pool, for the frame name
--- @param onHover function called with true/false as the cursor comes and goes
function Button.New(parent, index, onHover)
    local self = setmetatable({}, Button)

    local frame = CreateFrame("Button", "PeaversConsumableBarButton" .. index, parent,
        "SecureActionButtonTemplate, BackdropTemplate")
    frame:SetBackdrop(BACKDROP)
    frame:Hide()

    -- One edge, matching the player's own action button setting. Registering
    -- both edges fires the action twice, which on an item means the stack drops
    -- by two and the second use is wasted on a full buff.
    local onKeyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    frame:RegisterForClicks(onKeyDown and "AnyDown" or "AnyUp")

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", ICON_INSET, -ICON_INSET)
    icon:SetPoint("BOTTOMRIGHT", -ICON_INSET, ICON_INSET)
    -- Trim the border baked into every item icon so the art sits flush inside
    -- the hairline rather than inside two of them.
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.icon = icon

    local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(icon)
    highlight:SetColorTexture(1, 1, 1, 0.18)

    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(false)
    self.cooldown = cooldown

    local count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", -2, 2)
    count:SetJustifyH("RIGHT")
    self.count = count

    frame:SetScript("OnEnter", function(button)
        if self.itemID then
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            -- By ID rather than by bag slot: the tooltip then describes the item
            -- the button actually uses, even if the stack has since moved.
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end
        if onHover then onHover(true) end
    end)

    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if onHover then onHover(false) end
    end)

    self.frame = frame
    return self
end

--------------------------------------------------------------------------------
-- Appearance
--------------------------------------------------------------------------------

--- Size, font and colours. Separate from SetItem because the look changes on a
--- settings edit while the contents only change on a bag update.
function Button:Layout(config)
    local size = config.buttonSize or 36
    self.frame:SetSize(size, size)

    local color = config.borderColor or { r = 0, g = 0, b = 0 }
    self.frame:SetBackdropColor(color.r, color.g, color.b, config.bgAlpha or 0.8)
    self.borderColor = color
    self.borderAlpha = config.borderAlpha or 1
    self.colorByQuality = config.colorByQuality and true or false

    -- The count sits on the icon with nothing behind it, so it is outlined
    -- whatever the player's font settings say. Scaled with the button rather
    -- than fixed: a 24px button with 12pt text is mostly text.
    local fontSize = math.max(8, math.floor(size * 0.32))
    local face = (Utils.GetDefaultFont and Utils.GetDefaultFont()) or "Fonts\\FRIZQT__.TTF"
    -- Through Utils rather than SetFont directly: a font the client cannot load
    -- makes SetFont fail and leaves the string with no font at all, which is an
    -- invisible count rather than an ugly one.
    Utils.SafeSetFont(self.count, face, fontSize, "OUTLINE")
    self.count:SetShown(config.showCount ~= false)

    self.cooldown:SetHideCountdownNumbers(config.showCooldownText == false)

    self:ApplyBorder()
end

function Button:ApplyBorder()
    local color = self.borderColor or { r = 0, g = 0, b = 0 }

    if self.colorByQuality and self.quality and self.quality > 1 then
        local r, g, b = C_Item.GetItemQualityColor(self.quality)
        if r then
            self.frame:SetBackdropBorderColor(r, g, b, self.borderAlpha or 1)
            return
        end
    end

    self.frame:SetBackdropBorderColor(color.r, color.g, color.b, self.borderAlpha or 1)
end

--------------------------------------------------------------------------------
-- Contents
--------------------------------------------------------------------------------

--- Point the button at an item. Only called out of combat; see the file header.
--- @param entry table a scanner entry
function Button:SetItem(entry)
    self.itemID = entry.itemID
    self.quality = entry.quality

    self.icon:SetTexture(entry.icon)
    self.frame:SetAttribute("type", "macro")
    self.frame:SetAttribute("macrotext", "/use item:" .. entry.itemID)

    self:ApplyBorder()
    self:Refresh(entry.count)
    self.frame:Show()
end

--- Count and cooldown sweep. Cheap enough to run for every button on a bag
--- update, and safe to run in combat.
--- @param count number|nil re-read from the client when not supplied
function Button:Refresh(count)
    if not self.itemID then return end

    count = count or C_Item.GetItemCount(self.itemID) or 0
    self.count:SetText(count > 1 and count or "")

    local start, duration, enable = ItemCooldown(self.itemID)
    if start and duration and duration > 0 then
        self.cooldown:SetCooldown(start, duration)
        self.cooldown:SetDrawSwipe(enable ~= 0)
    else
        self.cooldown:Clear()
    end
end

--- Take the button out of use. The attributes are cleared as well as the frame
--- hidden, so a button parked in the pool cannot be clicked through a keybind
--- or a click-cast binding that outlived the item.
function Button:Release()
    self.itemID = nil
    self.quality = nil
    self.frame:Hide()
    self.frame:SetAttribute("type", nil)
    self.frame:SetAttribute("macrotext", nil)
    self.cooldown:Clear()
    self.count:SetText("")
end

return Button
