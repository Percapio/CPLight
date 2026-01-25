# CPLight

**CPLight** is a lightweight gamepad addon for **World of Warcraft: TBC Anniversary (2.5.5)**. Play WoW comfortably with your controller using smooth analog movement and intuitive menu navigation—no complicated setup required.

_Note: Project is not yet 100% feature complete_

## What Does It Do?

### 🎮 Analog Movement
- **Out of Combat**: Your character moves in the direction you point the left stick (full 360° freedom)
- **In Combat**: Your character faces forward and strafes when you move the stick (like a tank in an action game)
- Works seamlessly with the camera—just plug in and play

### 📦 Menu Navigation
- **Automatic**: When you open bags, spellbooks, or any menu, your D-Pad automatically controls the cursor
- **Smart**: Navigates between buttons across multiple windows—no more fumbling with the mouse
- **Safe**: Turns off during combat so it never interferes with your gameplay
- Press **PAD1** (A/Cross button) to click items, cast spells, or interact with menus
- Press **PAD2** (B/Circle button) to sell to vendors or use consumable/quest items in bags

## Installation

1. **Download** this addon (click the green "Code" button → "Download ZIP")
2. **Extract** the ZIP file
3. **Copy** the `CPLight` folder into your WoW AddOns directory:
   - Default location: `World of Warcraft\_anniversary_\Interface\AddOns\`
4. **Enable** gamepad support in WoW (if not already enabled):
   - Press ESC → System → Enable Gamepad
   - Or type `/console GamePadEnable 1` in chat
5. **Restart** WoW and enjoy!

## Requirements

- A gamepad/controller connected to your PC
- World of Warcraft TBC Anniversary (2.5.5) client
- WoW's built-in gamepad support enabled

## How to Use

1. **Connect your controller** before launching WoW
2. **Log in** to your character
3. **Move around** using the left analog stick—it just works!
4. **Open any menu** (press B for bags, P for spellbook, etc.)
5. **Navigate** using the D-Pad (up/down/left/right)
6. **Click items** using PAD1 (A button on Xbox, Cross on PlayStation) or PAD2 (B button Xbox, Circle on Playstation)

That's it! No configuration needed. _(At this time. Later, I will implement a minor button-mapping config window.)_

## Troubleshooting

**Controller not working?**
- Make sure WoW's gamepad support is enabled: `/console GamePadEnable 1`
- Restart WoW after enabling gamepad support

**D-Pad doesn't navigate menus?**
- The D-Pad only works when a menu is open (bags, character sheet, etc.)
- It automatically switches back to normal controls when you close menus

**Character won't turn in combat?**
- This is intentional! In combat, your character strafes instead of turning (like tank controls)
- This gives you better control during fights

**D-Pad doesn't navigate the windows while in combat?**
- Blizzard API restrictions.  There's probably a work-around for it, but (at the moment) I don't see that its worth the effort to implement.

## TODO:
- Ensure both primary features (movement and menu navigation) is 100% bug-free
- Add an action-bar button mapping menu (only button mapping, not the full ConsolePort package)
- Add some addon support (Questie, Immersion and the most popular & working bag addons)

## Credits

Inspired by the original **ConsolePort** addon by **MunkDev**. 

CPLight is a simplified, minimal-configuration version optimized for the TBC Anniversary client.

## License & Legal

This project is a **Modified Version** of **ConsolePort** addon by **MunkDev**. 

**CPLight** is distributed under the **Artistic License 2.0**. 
- Modifications by Thomas Vu include the removal of configuration menus into a minimal single pane window, core logic optimization for the 2.5.5 client, and a shift toward a minimalist "minimal-config" architecture.
