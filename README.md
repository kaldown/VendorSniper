# VendorSniper

[![CurseForge](https://img.shields.io/badge/CurseForge-VendorSniper-orange)](https://www.curseforge.com/wow/addons/vendorsniper)
[![Wago](https://img.shields.io/badge/Wago-VendorSniper-c1272d)](https://addons.wago.io/addons/vendorsniper)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?logo=paypal&logoColor=white)](https://www.paypal.com/donate/?hosted_button_id=FG4KES3HNPLVG)

If you find this useful, consider [supporting development](https://www.paypal.com/donate/?hosted_button_id=FG4KES3HNPLVG).

Other addons:
- [LazyProf](https://www.curseforge.com/wow/addons/lazyprof) - Profession leveling optimizer
- [Silencer](https://www.curseforge.com/wow/addons/silencer-whispers) - Whisper gatekeeper
- [CraftLib](https://www.curseforge.com/wow/addons/craftlib) - Recipe database

Never miss a limited-supply vendor restock again. Park an alt at a vendor, pick the items you want, and VendorSniper auto-buys them the instant they restock.

## Features

- **Auto-buy on restock** - Automatically purchases watched items when the vendor restocks
- **Global watchlist** - Watch items across any vendor, persists between sessions
- **Quantity targets** - Set how many you need; VendorSniper tracks progress and stops when complete
- **Raid warning alerts** - Screen flash and looping sound when a purchase is made so you don't miss it
- **Three view modes** - Vendor scan (pick items), Watchlist (manage), Monitoring (live sniping)
- **Auto-close merchant** - Closes vendor window after scan, ready for external reopen cycle
- **Purchase log** - Track what was bought, when, and from which vendor
- **Minimap button** - Left-click to toggle window, right-click to toggle sniping

## Screenshots

### Vendor view
Open any vendor with limited-supply items. Check the ones you want to watch.

![Vendor view](screenshots/vendor-view.png)

## Installation

1. Download from [CurseForge](https://www.curseforge.com/wow/addons/vendorsniper) or [Wago](https://addons.wago.io/addons/vendorsniper)
2. Extract to your `Interface/AddOns/` folder
3. Type `/vs` in-game to open

## Usage

1. Visit a vendor that sells limited-supply items
2. VendorSniper automatically shows limited items with checkboxes
3. Check items you want to watch (shift-click for custom quantity)
4. Click **Start Watching** to begin sniping
5. The addon auto-buys watched items whenever the vendor restocks
6. A raid warning alert fires on each purchase

**Tip:** Auto-close is enabled by default. After scanning, VendorSniper closes the merchant window so an external macro or tool can reopen it for the next restock cycle.

## Slash Commands

| Command | Description |
|---------|-------------|
| `/vs` | Toggle window |
| `/vs watch [itemlink]` | Add item to watchlist |
| `/vs start` | Start sniping |
| `/vs stop` | Stop sniping |
| `/vs clear` | Clear watchlist |
| `/vs status` | Show status and watched items |
| `/vs log` | Show recent purchase log |
| `/vs autoclose` | Toggle auto-close after scan |

## Minimap Button

- **Left-click** - Toggle the VendorSniper window
- **Right-click** - Toggle sniping on/off

## Compatibility

Works on Anniversary Edition (TBC 2.5.5).

## License

MIT - See [LICENSE](LICENSE) for details.
