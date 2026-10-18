# PeaversConsumableBar

[![AddonSentry](https://addonsentry.io/api/public/repos/peavers-warcraft/PeaversConsumableBar/badge.svg)](https://addonsentry.io/dashboard/peavers-warcraft/PeaversConsumableBar)

Puts the consumables already in your bags onto a bar, so applying a flask, a weapon oil and your food before a pull is three clicks in one place instead of three trips through your bags.

**No bundled libraries. No `OnUpdate` anywhere. The bar is rebuilt when your bags change and at no other time.**

## What lands on the bar

Anything in your bags that the game itself files under a category you have turned on, and that has something to do when you click it.

Nothing is matched by name and nothing comes from a list of item IDs. The category comes from the item's own class and subclass in the client's item database, which means a flask added in a patch appears without this addon being updated — and it means the categories read correctly in every locale, which a name match never could.

| Category | On by default |
|---|:--:|
| Flasks & Phials | yes |
| Potions | yes |
| Food & Drink | yes |
| Oils, Stones & Kits | yes |
| Elixirs | no |
| Bandages | no |
| Scrolls | no |
| Other Consumables | no |

The four on by default are the pre-combat routine the bar exists for. The rest are off because a full set of bags holds far more consumables than anyone wants on screen, and a bar that opens with forty buttons is a bar nobody positions.

Three filters run on top of the categories. Items with no on-use effect are dropped — reagents, quest turn-ins, the fish you have not cooked yet — because a button that does nothing when clicked is worse than no button. A quality floor, at Common by default, drops the vendor trash that happens to have a use effect attached. And **Hide Conjured Items** clears out mage food and water in one go; it is off by default because conjured food is the food a mage actually eats, and because Healthstones are conjured too.

Conjured-ness is not a field the client exposes. The only place it is stated is the item's tooltip, as a line reading `ITEM_CONJURED`, so that is what gets read — once per item, through `C_TooltipInfo`, and cached for the session. The filter fails open: an item whose tooltip has not arrived is shown, because an unfiltered bar is a far smaller problem than a flask that silently never appears.

## One item at a time

The **Items** page lists every consumable in your bags with a tick each, and the tick overrules the category both ways:

- Tick an item whose category is **off** and it goes on the bar anyway — that is how you get one weapon oil without switching on the whole of Other Consumables.
- Untick an item whose category is **on** and it stays off, for the flask you are saving rather than drinking.

An override also skips the quality floor and the conjured filter, because at that point it is you saying rather than the addon guessing. The one thing it cannot do is give an item a use effect it does not have.

Only the *difference* from the category is remembered, never the current answer for every item. So ticking a box that already matched its category stores nothing, and turning a category on later still sweeps in everything you never spoke about.

Not sure which category something is in? `/pcbar list` prints every consumable it found with its category and whether it is on the bar. An item you have spoken for and then run out of keeps a row at the bottom of the Items page with a **Reset** button, so one choice can be undone without clearing them all.

## In combat

The bar hides itself in combat by default, and that is handled by the game rather than by this addon. It has to be: no addon may touch a button that can use an item once a fight has started. The rule is handed to the secure environment as a macro conditional before combat and the client applies it, so it works during the pull whether or not this addon is doing anything at all.

Anything that changes which buttons exist — looting a flask mid-fight, running out of food — waits for combat to end and is applied then. Counts and cooldown sweeps keep updating throughout.

## Built for performance

- **No `OnUpdate`, anywhere.** Not on the bar, not on a button. Idle cost is nil.
- **Bag events, coalesced.** Looting a stack, sorting your bags or vendoring a bagful each fire a burst of events; they settle into a single scan a fifth of a second later.
- **One button per item, not per stack.** Six stacks of the same food is one button, with the count read from the client rather than from whichever stack was found first.
- **The cooldown sweep is the client's own.** A `Cooldown` widget, animated by the game, not by Lua.
- **Item info is waited for once.** `GET_ITEM_INFO_RECEIVED` fires for every item anything in the UI looks at — hundreds, at login. It is only listened to while a scan is actually waiting on something.

## Features

<!-- peavers:features -->
- Scans your bags and builds a bar from what it finds, with no list to maintain
- Eight categories, each switchable, classified from the game's own item data rather than by name
- Per-item switches that overrule the category both ways — show one item from a category you keep off, or hide one from a category you keep on
- **Hide Conjured Items** for mage food and water
- Rows or columns, with a configurable button size, spacing and wrap point
- Grows left or right and up or down, so the bar can keep whichever edge you anchored it by
- Hides in combat by default, through the game's own secure visibility rules
- Hides itself entirely when nothing in your bags matches
- Stack counts and cooldown sweeps on every button, including the shared potion lockout
- Quality-coloured borders, or a colour of your own
- Optional fade until you put the cursor on it
- Fully positionable in Blizzard's Edit Mode, or by dragging with `/pcbar unlock`
- Full appearance control, and optional sync with the shared Peavers global appearance profile
<!-- /peavers:features -->

## Usage

<!-- peavers:usage -->
Open the settings with `/pcbar`. The bar appears above where the action bars sit on a stock UI, and starts with your flasks, potions, food and weapon oils.

To move it, press Escape and choose **Edit Mode**, then select the consumable bar — or use `/pcbar unlock`, drag it where you want it, and `/pcbar lock`. Unlocking forces the bar on screen even when it is empty or set to hide in combat, so there is always something to grab.

**Grow Sideways** and **Grow Vertically** decide which corner the buttons are built out from, and the bar resizes itself around them. So pair the growth with the anchor: growing right from a bar anchored bottom-left keeps its left edge still as consumables come and go, growing left from one anchored bottom-right keeps its right edge still, and a bar anchored bottom stays centred whichever way it grows.

### Slash Commands

- `/pcbar` - Open settings
- `/pcbar list` - Print every consumable found, with its category
- `/pcbar unlock` - Show the bar so it can be dragged
- `/pcbar lock` - Finish positioning
- `/pcbar reset` - Restore every setting to its default
<!-- /peavers:usage -->

## Installation

### Recommended: PeaversUpdater

Download and install [PeaversUpdater](https://github.com/peavers-warcraft/PeaversUpdater/releases/latest), the desktop updater for the whole Peavers collection. It installs PeaversConsumableBar together with its required dependencies and delivers updates before they reach CurseForge.

### Alternative: CurseForge

1. Download from [CurseForge](https://www.curseforge.com/wow/addons/peaversconsumablebar)
2. Ensure [PeaversCommons](https://www.curseforge.com/wow/addons/peaverscommons) is also installed
3. Ensure [PeaversConfig](https://www.curseforge.com/wow/addons/peaversconfig) is also installed
4. Enable the addon on the character selection screen

---

*Part of the [Peavers](https://peavers.io) addon collection · [Report an issue](https://github.com/peavers-warcraft/PeaversConsumableBar/issues) · [Support development on Patreon](https://www.patreon.com/Peavers)*
