# 🍷 Ashoholic - Ebonhold Roster

[![Download Latest Release](https://img.shields.io/github/v/release/CrimsonDC143C/Ashoholic?label=Download&style=for-the-badge&color=blue)](https://github.com/CrimsonDC143C/Ashoholic/releases/latest/download/Ashoholic.zip)

**A highly customizable character, gold, and Soul Ash tracker for Project Ebonhold (WotLK 3.3.5).**

Tired of logging into 10 different alts just to check your gold, Soul Ash, or raid lockouts? Ashoholic gives you a beautiful, unified dashboard of your entire account's progress in one single window.

Whether you are a hardcore prestige grinder, an altoholic, or someone who multiboxes across multiple accounts, this addon was built for you.

## Special Thanks & Credits

Ashoholic was originally a fork of [Altoholic](https://www.wowace.com/projects/altoholic) by Thaoky, modified for Ebonhold by Crimson, with contributions and large UI overhaul courtesy of MarkusLastu.

## Key Features

*   **Comprehensive Character Tracking**
    *   **Soul Ash Breakdown:** Tracks your *Run*, *Unspent*, and *Committed* Soul Ash separately. Hover over the Soul Ash column to see a detailed breakdown.
    *   **World Tour Lockouts:** Instantly see if your characters are locked to 10-man or 25-man raids (Naxxramas, Obsidian Sanctum, Eye of Eternity) with clear icons and detailed tooltips.
    *   **Reset Costs & Gold:** Automatically scrapes your current Raid Reset Cost from the game client and tracks total gold across all characters.
    *   **Location & Last Seen:** Know exactly where you left your alts and how long ago you played them.
*   **Multi-Account Sync:** Includes custom PowerShell scripts to merge the SavedVariables of multiple WoW accounts before launch. See all your characters, across all your accounts, in one list.
*   **Fully Customizable UI:** 
    *   15+ built-in themes.
    *   Full RGBA color picker for every element.
    *   Font choices for the title, column headers, and roster row types. 
    *   Drag-and-drop column reordering and resizing.
    *   Save your own custom themes.
*   **Prestige Automation:** Hooks into the Ebonhold Prestige Service to automatically wipe your active Soul Ash tracking the moment you prestige.

## Screenshots

![Main Roster UI](images/main-roster.jpg)

*The main dashboard with class-colored names, account grouping, and totals.*

![Theme Options](images/themes-tab.jpg)
![Customization Options](images/customize-tab.jpg)

*Pick between preset themes or customize your own, featuring full color pickers and opacity sliders.*

![Multi-Account Sync](images/sync-tab.jpg)

*The Sync tab, which explains how to set up multi-account merging.*

## Installation

1.  Download [Ashoholic.zip](https://github.com/CrimsonDC143C/Ashoholic/releases/latest/download/Ashoholic.zip) from the button above.
2.  Extract it into `Ebonhold\Interface\AddOns\`. The zip contains three addon folders: `Ashoholic`, `FastSwap`, and `SharedMedia`. Each has its own `.toc` file.
3.  Launch Ebonhold with `Ashoholic.bat` at least once to install the FastSwap character-selection hook. FastSwap will not switch characters until the hook has been synced. Launch with the batch file again after Ebonhold updates.
4.  Make sure you have the **ProjectEbonhold** addon enabled.
5.  Log in and type `/ash` or `/ashoholic`, or left-click on the minimap icon, to open the roster!

## PTR testing download

For the Ebonhold PTR, download [Ashoholic-PTR.zip](https://github.com/CrimsonDC143C/Ashoholic/releases/download/ptr-latest/Ashoholic-PTR.zip). This link becomes available after the first successful PTR publication. The [PTR prerelease page](https://github.com/CrimsonDC143C/Ashoholic/releases/tag/ptr-latest) identifies the packaged commit.

Close WoW, back up your PTR SavedVariables, and extract the ZIP into your **PTR client's** `Interface\AddOns\` folder. It contains the same three addon folders as the live package; follow the remaining installation steps above using the PTR client. ProjectEbonhold must already be installed. PTR builds are experimental and should not replace your live-client addon installation.

### Publishing PTR builds

- Commit and push PTR changes to `PTR-main`. The **Package PTR addon** workflow builds the install-ready ZIP, including the preview UI, and publishes it as a prerelease.
- Each successful publication moves the dedicated `ptr-latest` tag to the packaged commit and replaces `Ashoholic-PTR.zip`, keeping the download URL unchanged. It does not retain previous PTR builds.
- Live release tags, the live ZIP, and the latest stable release are not changed. The live packaging job only runs on `main`.
- If the workflow is available in GitHub's manual-run menu, select `PTR-main` when running it. GitHub normally requires a workflow to exist on the default branch before exposing manual dispatch; automatic PTR pushes do not have that requirement.
- Repository rules must allow GitHub Actions to create releases and update the dedicated `ptr-latest` tag. Do not use that tag for a stable release.
- Nothing is published until these changes are committed and pushed. If the workflow fails, the download may still be the previous successful build; check the Actions run before announcing an update.

## Multi-Account Syncing (Optional)

If you play on multiple WoW accounts and want to see all your characters in one list:
1. Log into each account once and play briefly so the addon generates/updates the `SavedVariables/Ashoholic.lua` file for that account.
2. Locate the `Ashoholic.bat` file in the addon folder.
3. Use it to launch the game instead of `Wow.exe`. It will automatically merge all your account data before launching.

## Commands

### UI design preview (PTR)

Use `/ash preview` for the separate, session-local design preview. All characters,
balances, activity objectives, timers and records are samples, not live tracking.
Closing preserves preview choices until `/reload`; it does not change your saved roster.
Hover the currency cards for explanations of their account-level totals.
Preview roster Swap buttons explain switching without logging out or passing
fictional character names to FastSwap.
Drag roster header edges to resize columns. Minimum widths fit each header and
the widest sample value across all accounts. Overflow scrolls horizontally;
widths follow their column when reordered and reset on `/reload`.
Settings > Roster Columns can enable all eleven optional columns, not just six.
In Raids & Dungeons, hide the tracking-selection sidebar to make room for ten
compact character columns without widening the main window. Wider columns and
horizontal scrolling remain available for larger selections.
Click the watched matrix's Raids or Dungeons section header to collapse its
instances and bosses without changing the watchlist.
Activities uses the full width for one account, separating Daily and Weekly
examples; multiple accounts retain a two-column overview. Reset times and
objectives are explicitly illustrative, not live server data.
Themes separates read-only Default Presets from Custom Presets. Custom presets
can be saved, applied, starred, renamed, edited and deleted; they capture colors,
fonts, icons and row layout, but not account filters. They last until `/reload`
and never replace the live addon's saved themes.

*   `/ash` or `/ashoholic` - Toggles the main roster window.
*   `/ash config` or `/ashoholic config` - Opens the settings menu directly.
*   `/ash memory` - Collects Lua garbage and reports addon memory before and after collection. Run between repeated test batches to check whether retained memory keeps growing; this does not measure the game client's native memory or font cache.

## Feedback & Issues

If you find any bugs, have feature requests, or want to share your custom themes, please open an **Issue** here on GitHub! 

**Hope you enjoy!** 
— ML
