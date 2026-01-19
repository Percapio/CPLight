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
    * **Travel Mode**: Movement follows the direction of the analog stick (360° freedom).
    * **Tank Mode (Combat/Focus)**: Maintains forward-facing orientation; allows strafing and walking backward.
* **Technical Requirements**:
    * **Deadzone Management**: Ignores stick input below a specific threshold (e.g., 0.2) to prevent "stick drift."
    * **Camera Integration**: Manages Pitch and Yaw to ensure the character/camera follows stick direction.
    * **Casting Guard**: Adjusts movement behavior or stops movement during active spell casts (`UNIT_SPELLCAST_START`).

### 2. Cursor Hijack (`View/Cursors/Hijack.lua`)
* **Purpose**: Intercepts gamepad input when specific UI windows are open.
* **Functionality**:
    * **Visibility Heartbeat**: Uses a monitor to check `IsVisible()` and `GetAlpha() > 0` on `ALLOWED_FRAMES`.
    * **Input Override**: Uses a dedicated **Binding Driver Frame** (not `UIParent`) to override the D-Pad and PAD buttons.
    * **Secure Proxy**: Utilizes `SecureActionButtonTemplate` to perform `LeftButton` (PAD1) and `RightButton` (PAD2) clicks on UI nodes.
    * **Gauntlet Visual**: A 32x32 texture (`Interface\CURSOR\Point`) that follows the focused node.
    * **Navigation**: Combines `ConsolePortNode` library logic with a coordinate-distance fallback for multi-frame jumping.

### 3. API & Constants (`Utils/Const.lua`)
* **Purpose**: Abstracts version-specific API changes to prevent Lua errors.
* **Crucial Bridges**:
    * **Cursor API**: `CPAPI.SetCursor` maps to `C_Cursor.SetCursorPosition` (Required for 2.5.5).
    * **Mouse Focus**: `CPAPI.GetMouseFocus` maps to `GetMouseFoci()[1]` (Handles modern UI changes).
    * **Version Constants**: `CPAPI.IsAnniVersion` to toggle logic specific to the 2.5.5 client.

### 4. State Orchestrator (`Core/State.lua`)
* **Purpose**: Manages the "Hand-off" between the World (Movement) and the UI (Hijack).
* **Logic**:
    * **Release Mechanism**: Ensures `ClearOverrideBindings` is called immediately when windows close, returning Jump/Movement to the player.
    * **Combat Safety**: Automatically disables UI Hijack during `PLAYER_REGEN_DISABLED` to prevent secure header errors.

---

## Guidelines for Refactoring
1.  **Strictly 2.5.5**: Never use Retail-only APIs (like EditMode) or Vanilla-only APIs.
2.  **No Logic Stripping**: Do not remove the "Distance Fallback" in navigation; it is required for jumping between two different open windows.
3.  **Binding Safety**: Never call `ClearOverrideBindings(UIParent)` unless absolutely necessary; always prefer a dedicated Driver Frame to keep the character's core movement map intact.