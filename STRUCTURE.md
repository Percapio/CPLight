# CPLight - Lightweight ConsolePort

## Status
**✅ Standalone Addon** – Independent database and API system. No ConsolePort dependency.  
**✅ Environment** – Targeted specifically for **WoW TBC Anniversary (2.5.5)**.

## Purpose
A high-performance, minimalist gamepad interface. It provides the "ConsolePort feel" by handling movement and UI navigation without the overhead of heavy configuration menus or decorative UI elements.

---

## Core Components

### 1. Movement System (`Controller/Movement.lua`)
* **Purpose**: Translates analog stick input into character movement.
* **Logic Modes**:
    * **Travel Mode (Out of Combat)**: Movement follows the direction of the analog stick (360° freedom). Uses 45° strafe angle for smooth interpolation and immediate turning response.
    * **Tank Mode (In Combat)**: Maintains forward-facing orientation; always strafes (180° angle). Character never turns with movement stick.
* **Technical Requirements**:
    * **Angle System**: Uses `RegisterAttributeDriver` with `[combat] 180; 45` macro to switch between modes without taint.
        * Lower angle (45°) = character faces movement direction quickly
        * Higher angle (180°) = character strafes, never turns
    * **Deadzone Management**: Ignores stick input below a specific threshold (e.g., 0.2) to prevent "stick drift."
    * **Camera Integration**: Manages Pitch and Yaw to ensure the character/camera follows stick direction.
    * **Casting Guard**: Locks camera (TurnWithCamera=2) during active spell casts (`UNIT_SPELLCAST_START`) and vehicle usage.

### 2. Cursor Hijack (`View/Cursors/Hijack.lua`)
* **Purpose**: Intercepts gamepad input when specific UI windows are open.
* **Functionality**:
    * **Frame Visibility Check**: During buttonDown events check for Frame visibility
    * **Input Override**: Uses a dedicated **Binding Driver Frame** (not `UIParent`) to override the D-Pad and PAD buttons when Blizzard UI windows are open.
    * **Secure Proxy**: Utilizes `SecureActionButtonTemplate` to perform `LeftButton` (PAD1) and `RightButton` (PAD2) clicks on UI nodes.
    * **Gauntlet Visual**: A 32x32 texture (`Interface\CURSOR\Point`) that follows the focused node.
    * **Navigation**: Utilizes a `ConsolePortNode`-like logic with a coordinate-distance fallback for multi-frame jumping and UI window traversal.
    * **Tooltip**:Show tooltip only when gauntlet is hover over a node with an object in it.
    * **Use spell/consumable**: Cast/Use spell or consumable the gauntlet is hovering over with SetOverrideBindingClick on SecureHandlerStateTemplate that covers the entire screen.

### 3. API & Constants (`Utils/Const.lua`)
* **Purpose**: Abstracts version-specific API changes to prevent Lua errors.
* **Crucial Bridges**:
    * **Cursor API**: `CPAPI.SetCursor` maps to `C_Cursor.SetCursorPosition` (Required for 2.5.5).
    * **Mouse Focus**: `CPAPI.GetMouseFocus` maps to `GetMouseFoci()[1]` (Handles modern UI changes).
    * **Version Constants**: `CPAPI.IsAnniVersion` to toggle logic specific to the 2.5.5 client.
    * **Movement Constants**: `CPAPI.Movement` table defines angles (Combat=180, Travel=45) and camera lock behavior for consistent project-wide usage.

### 4. State Orchestrator (`Core/State.lua`)
* **Purpose**: Manages the "Hand-off" between the World (Movement) and the UI (Hijack).
* **Logic**:
    * **Release Mechanism**: Ensures `ClearOverrideBindings` is called immediately when windows close, returning Jump/Movement to the player.
    * **Combat Safety**: Automatically disables UI Hijack during `PLAYER_REGEN_DISABLED` to prevent secure header errors.

### 5. Bonus Feature(s)
* **Purpose**: Any additional nice to have if able to implement later on in the project's life cycle.
* **Logic**: 
    * **Target tooltip**: when soft/hard lock a target, show tooltip.
    * **Center mouse cursor**: When not in combat, or when mouse not in use, center mouse to middle of the screen.
    * **External addon support**: Some support for addons like node traversal on Questie/Bagnator/etc.

---

## Guidelines for Refactoring & Implementing
1.  **Strictly 2.5.5**: Never use Retail-only APIs (like EditMode) or Vanilla-only APIs.
2.  **No Logic Stripping**: Do not remove the "Distance Fallback" in navigation; it is required for jumping between two different open windows.
3.  **Binding Safety**: Never call `ClearOverrideBindings(UIParent)` unless absolutely necessary; always prefer a dedicated Driver Frame to keep the character's core movement map intact.
4.  **Structurally Sound**: Always ensure is our code is scalable, modular, resiliant, efficient, testable and readable.