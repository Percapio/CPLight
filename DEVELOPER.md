# CPLight Developer Documentation

> **High-level overview for developers adapting CPLight to their own projects**  
> For detailed implementation, see inline LuaDoc comments in each `.lua` file.

---

## 🎯 Project Overview

CPLight is a lightweight gamepad addon for WoW TBC Anniversary (2.5.5) providing analog movement and UI navigation without complex configuration menus.

**Target API**: WoW 2.5.5 Anniversary (uses 12.0.1 Retail restrictions without Retail-exclusive features)  
**License**: The Artistic License 2.0 (ok to fork and modify)  
**Core Philosophy**: Minimal footprint, event-driven architecture, zero taint risk for core gameplay

---

## 📐 System Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      USER INPUT FLOW                          │
└──────────────────────────────────────────────────────────────┘

┌─────────────────┐         ┌─────────────────┐
│  Analog Stick   │────────▶│  Movement.lua   │
│  (Left Stick)   │         │  (Controller/)  │
└─────────────────┘         └─────────────────┘
                                   │
                            Combat/Travel Mode
                            Angle Switching
                                   │
                                   ▼
                            Character Movement


┌─────────────────┐         ┌─────────────────────────────────┐
│   D-Pad Input   │────────▶│         Hijack.lua              │
│   (Navigation)  │         │          (View/)                │
└─────────────────┘         └────────────┬────────────────────┘
                                         │
                    ┌────────────────────┼────────────────────┐
                    │                    │                    │
                    ▼                    ▼                    ▼
          ┌──────────────────┐  ┌──────────────┐   ┌─────────────────┐
          │ NavigationGraph  │  │  CVarManager │   │  Visual Feedback│
          │   (View/)        │  │  (Config/)   │   │  (Gauntlet)     │
          └──────────────────┘  └──────────────┘   └─────────────────┘
                    │
                    │ uses
                    ▼
          ┌──────────────────┐
          │ ConsolePortNode  │
          │   (Libs/)        │
          └──────────────────┘


┌─────────────────┐         ┌─────────────────┐
│   UI Controls   │────────▶│   Options.lua   │
│  (ESC → AddOns) │         │   (Config/)     │
└─────────────────┘         └─────────────────┘
                                   │
                            AceConfig + AceDB
                                   │
                                   ▼
                            SavedVariables (CPLightDB)
```

---

## 🔄 Data Flow: UI Navigation

```
1. UI Opens (Bags/Character/Spellbook)
         │
         ▼
2. Hijack: OnShow Hook Triggered (Event-Driven)
         │
         ▼
3. Hijack: EnableNavigation()
         │
         ├─▶ Check InCombatLockdown() ──✗── ABORT
         │
         ├─▶ CollectVisibleFrames() ──▶ FRAMES registry
         │
         ├─▶ CanReuseGraph()?
         │        │
         │        ├─ YES ──▶ Reuse LastGraphState (FAST PATH)
         │        │
         │        └─ NO ──▶ NavigationGraph:BuildGraph()
         │                        │
         │                        ├─▶ NODE() scans frames
         │                        ├─▶ Calculate edges (up/down/left/right)
         │                        └─▶ Store graph + timestamps
         │
         └─▶ SetupSecureWidgets()
                  │
                  ├─▶ Skip buttons in CVarManager.IsModifier()
                  ├─▶ Create SecureActionButtonTemplates
                  └─▶ SetOverrideBindingClick() for D-Pad


4. Player Presses D-Pad UP
         │
         ▼
5. Hijack: Navigate("up")
         │
         ├─▶ GetTargetNodeInDirection(currentIndex, "up")
         │        │
         │        ├─▶ Try: Strict edges (pre-calculated graph)
         │        ├─▶ Fallback: NODE.NavigateToBestCandidateV3 (real-time)
         │        └─▶ Final fallback: Relaxed directional search
         │
         ├─▶ ValidateNodeFocus(targetNode) ──✗── Skip to next
         │
         └─▶ SetFocus(targetNode)
                  │
                  ├─▶ ConfigureWidgetsForNode() ──▶ PAD1/PAD2 → clickbutton
                  │
                  └─▶ UpdateVisualFeedback()
                           │
                           ├─▶ UpdateGauntletPosition()
                           └─▶ ShowTooltipForNode()


6. Player Presses PAD1 (A Button)
         │
         ▼
7. SecureActionButton: Clicks focused node
         │
         └─▶ Game's native click handler (secure context)


8. UI Closes
         │
         ▼
9. Hijack: OnHide Hook Triggered
         │
         └─▶ DisableNavigation()
                  │
                  ├─▶ ClearOverrideBindings()
                  ├─▶ Hide Gauntlet
                  └─▶ IsActive = false
```

---

## 📦 Module Reference

### Core Modules

#### **Movement.lua** (`Controller/`)
- **Purpose**: Analog stick → character movement
- **Key APIs**: 
  - Angle switching via `RegisterAttributeDriver` (combat: 180°, travel: 45°)
  - Deadzone filtering for stick drift
  - Camera lock during casting (`UNIT_SPELLCAST_START`)

#### **Hijack.lua** (`View/`)
- **Purpose**: D-pad navigation orchestrator
- **Key APIs**:
  - `EnableNavigation()` / `DisableNavigation()`
  - `Navigate(direction)` - Routes D-pad input to graph (3-tier fallback strategy)
  - `RefreshNavigation()` - Rebuilds graph and restores focus to nearest node
  - `SetFocus(node)` - Updates current focus + visual feedback
  - `IsModifier(button)` - Checks if button assigned to Shift/Ctrl/Alt
- **Events**: 
  - `OnShow/OnHide` hooks (event-driven frame detection)
  - `BAG_UPDATE_DELAYED` (rebuilds graph when items change, auto-debounced)
  - `ADDON_LOADED` (catches late-loaded Blizzard UIs and bag addons)
  - `PLAYER_REGEN_DISABLED/ENABLED` (combat safety)
- **Navigation Fallback Chain**:
  1. Strict pre-calculated edges (fast, predictable)
  2. NODE library real-time navigation (smart, handles dynamic layouts)
  3. Relaxed directional search (handles edge cases like MailFrame, addon UIs)

#### **NavigationGraph.lua** (`View/`)
- **Purpose**: Pre-calculated navigation graph builder
- **Key APIs**:
  - `BuildGraph(frames)` - Scans frames via NODE(), calculates edges
  - `GetNodeEdges(index)` → `{up, down, left, right}`
  - `GetValidatedNodeEdges(index)` - Real-time validation of edges
  - `GetClosestNodeToPosition(x, y)` - Find nearest node to coordinates
  - `FindNodeInRelaxedDirection(index, direction)` - Relaxed directional search
  - `NodeToIndex(node)` / `IndexToNode(index)` - Bidirectional mapping
  - `InvalidateGraph()` - Forces rebuild on next access
- **Performance**: Builds in <50ms, reuses when frame state unchanged
- **Smart Recovery**: 
  - Detects stale nodes (deleted bag items) and auto-rebuilds
  - Restores focus to nearest valid node when current node disappears
  - Relaxed fallback handles unusual frame layouts (MailFrame tabs, addon UIs)

#### **CVarManager.lua** (`Config/`)
- **Purpose**: Controller button → keyboard modifier mapping
- **Key APIs**:
  - `Initialize()` - Saves original CVars on first load
  - `IsModifier(button)` - O(1) cache lookup (called per button press)
  - `ApplyModifierBindings()` - Writes settings to CVars
  - `RestoreOriginalCVars()` - Reverts to pre-CPLight state
- **CVars**: `GamePadEmulateShift`, `GamePadEmulateCtrl`, `GamePadEmulateAlt`

#### **Options.lua** (`Config/`)
- **Purpose**: AceConfig-based UI panel (ESC → AddOns → CPLight)
- **Features**:
  - Dropdown menus for modifier assignment (dynamic filtering)
  - Apply/Restore buttons with confirmation dialogs
  - Debug mode checkbox (restart required)
  - Live CVar status display

#### **IconMapping.lua** (`Config/`)
- **Purpose**: Replace keybind text with controller button icons
- **Key APIs**:
  - `Apply()` - One-time setup (tracked in SavedVariables)
  - `UpdateModifierIcons()` - Dynamically updates modifier abbreviations
  - `Restore()` - Reverts to original KEY_* strings
- **Features**:
  - Converts `KEY_PAD1` → `|A:Gamepad_Button_Down:16:16|t` (Blizzard atlas icons)
  - Works with all action bar addons (Bartender, Dominos, ElvUI, default UI)
  - Modifier icons reuse assigned controller buttons (e.g., Shift = shoulder icon if bound)
  - Zero taint, minimal footprint, runs once on PLAYER_LOGIN

#### **API.lua** (`Core/`)
- **Purpose**: Global helper functions and version abstraction
- **Key APIs**:
  - `CPAPI.CreateEventHandler()` - Event-driven frame creation
  - `CPAPI.RegisterFrameForUnitEvents()` - Unit event registration
  - `CPAPI.Log(msg)` - Production user messages
  - `CPAPI.DebugLog(msg)` - Debug messages (opt-in via checkbox)
  - `CPAPI.SetDebugMode(enabled)` / `GetDebugMode()` - Toggle debug output
- **Note**: Cleaned of legacy ConsolePort functions; contains only actively used APIs

---

## 🛠️ Adapting CPLight to Your Project

### 1. **Copy the Public APIs**
Core functions you can reuse directly:
- **Movement angles**: `CPAPI.Movement.AngleCombat` (180°), `CPAPI.Movement.AngleTravel` (45°)
- **Cursor positioning**: `CPAPI.SetCursor(x, y)` - Handles 2.5.5/12.0.1 API changes
- **Navigation graph**: `NavigationGraph:BuildGraph(frames)` - Reusable for any UI traversal system
- **Modifier detection**: `CVarManager:IsModifier(button)` - Check if button is bound to Shift/Ctrl/Alt

### 2. **Modify the Frame Registry**
Edit `Hijack.lua` → `FRAMES` table to target different UI windows:
```lua
local FRAMES = {
    CharacterFrame = {priority = 10},
    YourCustomFrame = {priority = 5},  -- Add your addon's frames here
}
```

### 3. **Customize Visual Feedback**
Hijack.lua Section 5 (Visual Feedback):
- `CreateGauntlet()` - Change cursor texture/size
- `ShowTooltipForNode()` - Customize tooltip display logic
- `SetGauntletState()` - Adjust pointing/pressing states

### 4. **Extend with Smart Actions**
Actions.lua (currently disabled) provides button type detection:
- `GetButtonType(button)` - Identifies containers, merchants, equipment, etc.
- `HandleContainer()` / `HandleMerchant()` - Context-aware click handlers
- Integrate by calling from `_ConfigureWidgetsForNode()` in Hijack.lua

### 5. **Add Support for Addon UIs**
For custom addon frames (e.g., Questie, Immersion, Bagnon, Baganator):
1. Add addon name and frame names to `ADDON_FRAMES` registry in Hijack.lua
2. Frames are auto-detected on ADDON_LOADED and PLAYER_LOGIN events
3. Ensure frames have clickable child widgets detectable by NODE()
4. BAG_UPDATE_DELAYED handles dynamic content (items deleted/sold)
5. Relaxed fallback navigation handles unusual layouts automatically

---

## ⚙️ Technical Requirements

### WoW 2.5.5 Anniversary API Constraints
- ✅ **Available**: Secure action system, `C_Cursor`, `GetMouseFoci()`, modern event system
- ❌ **Unavailable**: EditMode API, Adventure Journal, Transmog, Modern Talent UI
- ⚠️ **Combat Lockdown**: All `SetOverrideBindingClick()` / `ClearOverrideBindings()` must check `InCombatLockdown()` first

### Performance Targets
- Graph build: <50ms for typical UIs
- Navigation response: <16ms (1 frame)
- OnUpdate overhead: <0.1% CPU (1.0s polling interval as fallback)
- Memory growth: <1MB per session
- Graph cache hit rate: >80% (reuse vs rebuild)

### Security Considerations
- **Accepted Risk**: D-pad navigation uses insecure PreClick handlers
- **Mitigation**: Separate navigation from action execution; clicks remain secure
- **Best Practice**: All widget operations use dedicated driver frame (not UIParent)

---

## 🧪 Testing & Debugging

### Enable Debug Mode
Two methods:
1. **UI Checkbox**: ESC → AddOns → CPLight → Debug Mode (restart required)
2. **Console Command**: `/run CPAPI.SetDebugMode(true)`

### Debug Output Categories
- Graph building: "Building navigation graph for X frames"
- Cache usage: "Graph reused" vs "Graph rebuilt"
- CVar changes: "Applied modifier bindings", "Restored original CVars"
- Navigation warnings: "Invalid gauntlet transition", "Graph is stale"

### Common Issues
1. **Navigation stops working**: Check `InCombatLockdown()` - automatic recovery on combat end
2. **Graph not updating**: BAG_UPDATE_DELAYED event triggers rebuild; verify hooks registered
3. **Stale node errors**: RefreshNavigation() auto-detects and rebuilds; check debug logs
4. **Can't navigate to certain buttons**: Relaxed fallback should handle; verify node visibility
5. **Buttons don't respond**: Check if assigned as modifiers via CVarManager
6. **Memory leaks**: Verify tooltips hidden on navigation disable, hooks not duplicated

---

## 📚 Additional Resources

### Key Dependencies
- **Ace3**: AceAddon, AceDB, AceConfig, AceGUI, AceEvent (all in `Libs/Ace3/`)
- **LibStub**: Addon library management (`Libs/LibStub/`)
- **ConsolePortNode**: Frame scanning and validation (`Libs/ConsolePortNode/`)

### Code Organization
Each `.lua` file has detailed inline comments:
- **Section headers** separate logical blocks
- **LuaDoc annotations** on all public methods (`@param`, `@return`, `@public`)
- **Private methods** marked with underscore prefix (`_MethodName`)

### File Structure
```
Core/          - Addon initialization (AceAddon, AceDB, API)
Controller/    - Movement system (analog stick handling)
View/          - UI navigation (Hijack, NavigationGraph, Actions)
Config/        - Options panel (CVarManager, Options, AceConfig)
Utils/         - Constants and helpers (version detection, CPAPI)
Libs/          - Third-party libraries (Ace3, LibStub, ConsolePortNode)
```

---

## 📝 License & Contributing

**License**: MIT - Fork, modify, and distribute freely  
**Attribution**: Inspired by ConsolePort by MunkDev

When adapting CPLight:
- ✅ Keep API.lua version detection logic (handles client differences)
- ✅ Preserve combat lockdown checks (prevents secure header errors)
- ✅ Maintain event-driven architecture (performance benefit)
- ⚠️ Test thoroughly on target WoW version (API differences exist)

---

## 🚀 Quick Start Checklist

For developers adapting this code:

1. **Understand the flow**: Read "Data Flow: UI Navigation" section above
2. **Identify modules to reuse**: Copy APIs from Core/API.lua, View/NavigationGraph.lua
3. **Customize frame registry**: Edit FRAMES table in View/Hijack.lua
4. **Test incrementally**: Enable debug mode, verify graph building, test navigation
5. **Handle edge cases**: Combat lockdown, late-loaded frames, rapid UI changes
6. **Profile performance**: Check graph build time, navigation latency, memory usage
7. **Document changes**: Update inline comments if modifying core logic

**Need more detail?** Every `.lua` file has comprehensive LuaDoc comments explaining method parameters, return values, and internal logic.
