local _, PCBar = ...

--------------------------------------------------------------------------------
-- Conjured
--
-- Whether an item was conjured: mage food and water, warlock Healthstones, and
-- the rest of the summoned consumables.
--
-- There is no field for this. GetItemInfo returns twenty-odd values and none of
-- them says conjured; the only place the client admits it is the tooltip, as a
-- line reading exactly ITEM_CONJURED. So the tooltip is what gets read - once
-- per item, and cached forever, because no item has ever stopped being conjured.
--
-- Read through C_TooltipInfo rather than by scanning a hidden GameTooltip. The
-- old technique needs a frame, a SetItemByID, and a walk over
-- GameTooltipTextLeftN font strings; it is also the technique that leaves a
-- tooltip frame behind on the first call and reads stale text on the second.
--
-- The filter fails open. Where C_TooltipInfo is missing, or the tooltip has not
-- arrived, the answer is "not conjured" - an unfiltered bar is a far smaller
-- problem than a flask that silently never appears.
--------------------------------------------------------------------------------

local Conjured = {}
PCBar.Conjured = Conjured

local cache = {}

--- @param itemID number
--- @return boolean
function Conjured.Is(itemID)
    local known = cache[itemID]
    if known ~= nil then return known end

    local label = _G.ITEM_CONJURED
    if not label or not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then
        return false
    end

    local data = C_TooltipInfo.GetItemByID(itemID)
    -- No tooltip yet means the item's data has not landed. Not cached, so the
    -- next scan asks again rather than remembering a guess.
    if not data or not data.lines then return false end

    local conjured = false
    for _, line in ipairs(data.lines) do
        -- Pre-surfaced since 10.1.5; still surfaced by hand on the clients that
        -- need it, where leftText is nil until this is called.
        if line.leftText == nil and TooltipUtil and TooltipUtil.SurfaceArgs then
            TooltipUtil.SurfaceArgs(line)
        end

        if line.leftText == label then
            conjured = true
            break
        end
    end

    cache[itemID] = conjured
    return conjured
end

--- Test seam, and a way out if a client ever reports the line wrongly after a
--- patch. Nothing in the addon calls this.
function Conjured.Forget()
    cache = {}
end

return Conjured
