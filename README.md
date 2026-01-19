# CPLight

**CPLight** is a high-performance, minimalist gamepad interface for **World of Warcraft: TBC Anniversary (2.5.5)**. It provides essential ConsolePort-style functionality—analog movement and UI navigation—without the overhead of heavy configuration menus or bloat.

## Features
- **Analog Movement**: Smooth 360-degree character control with "Tank" and "Travel" logic.
- **Smart UI Hijack**: Automatically overrides the D-Pad and PAD buttons only when UI frames (Bags, Spellbook, etc.) are open.
- **Node-Based Navigation**: Recursive UI scanning allows the gamepad to "snap" to buttons across multiple open windows.
- **Anniversary Ready**: Fully compatible with the 2.5.5 `C_Cursor` and Secure Action Button requirements.

## Installation
1. Download the repository.
2. Place the `CPLight` folder into your `_classic_era_/Interface/AddOns/` directory.
3. Ensure you have a controller connected and configured via WoW's built-in Gamepad settings (`/console GamePadEnable 1`).

## Project Structure
- **Controller/Movement.lua**: Analog stick translation and camera logic.
- **View/Cursors/Hijack.lua**: The secure binding driver and UI navigation engine.
- **Utils/Const.lua**: API bridges for version compatibility.

## Credits
Inspired by the original ConsolePort. Simplified and optimized for the 20th Anniversary client.