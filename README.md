# Ashoholic

Ashoholic is an account roster for the Ebonhold Wrath server (WoW 3.3.5). One window lists every character's world-tour locks, Soul Ash, the Soul Ash cost to clear instance IDs, and gold.

It is a fork of [Altoholic](https://www.wowace.com/projects/altoholic) by Thaoky, modified for Ebonhold by Crimmy.

## Opening it

Use the minimap button, `/ash`, or `/ashoholic`.

## Roster

Characters come from DataStore. Each realm can be collapsed, and a totals row sums Soul Ash and gold. Click a column header to sort.

| Column | What it shows |
| --- | --- |
| Name | Faction icon and character name |
| Level | Character level |
| 10m WT / 25m WT | Lock status for Naxxramas, The Obsidian Sanctum, and The Eye of Eternity |
| Reset Cost | Soul Ash charged by Clear Instance IDs |
| Soul Ash | Soul Ash currently held |
| Money | Gold |

World-tour icons, shown separately for 10-player and 25-player:

- Green check: level 80 and saved to none of the three raids
- Yellow LVL: not level 80
- Hourglass: saved to one or two of the three
- Red X: saved to all three

Right-click a character's level to remove that alt, or a realm header to remove that realm. The character you are logged into cannot be removed.

## How the numbers stay current

**Soul Ash** is read from the Ebonhold player run frame about every two seconds while you are on that character. Confirming Prestige sets Soul Ash to 0 for every character.

**Reset Cost** is read from the Clear IDs button while the Raid panel is open. Each clear multiplies the cost by 5, starting from 50,000.

**Weekly cost reset.** The "Next cost reset" countdown under that button is saved the first time the Raid panel is opened. When it runs out, Reset Cost becomes 50,000 for every character. That still happens if the Raid panel is closed, and on the next login if you were offline when it elapsed. Open the Raid panel once after installing or updating so the countdown can be stored. The panel shows whole minutes, so with it closed the column can update up to about a minute after the server reset. While the panel is open, the logged-in character uses the button's current cost.

All of this is stored in the `AltoholicDB` saved variable.

## Requirements

- World of Warcraft 3.3.5 (interface 30300)
- DataStore, DataStore_Characters, DataStore_Currencies, DataStore_Stats, and DataStore_Achievements

Those DataStore addons are installed separately. This repository is Ashoholic only.

## Install

Copy this folder into `Interface/AddOns` and reload the UI. WoW loads the folder name; the window title is Ashoholic.
