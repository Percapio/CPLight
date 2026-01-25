# CPLight - Lightweight ConsolePort

## Status
**✅ Standalone Addon** – Independent database and API system. No ConsolePort dependency.  
**✅ Environment** – Targeted specifically for **WoW TBC Anniversary (2.5.5)**.  
**✅ Phase 1 & 2 Complete** – Pre-calculated navigation graph, combat safety, and visual feedback decoupling implemented.

## Purpose
A high-performance, minimalist gamepad interface. It provides the "ConsolePort feel" by handling movement and UI navigation without the overhead of heavy configuration menus or decorative UI elements.

## API Compatibility Note
**2.5.5 Anniversary Client** uses the same public-facing Lua API as **12.0.1 (Retail)** with identical restrictions:
- Secure action system restrictions (combat lockdown, taint propagation)
- Modern event system (C_EventUtils, UnitAura changes)
- Updated cursor API (C_Cursor.SetCursorPosition)
- GetMouseFoci() instead of GetMouseFocus()

**Key Difference**: 2.5.5 does **NOT** include Retail-only features:
- No EditMode API
- No Adventure Journal
- No Transmog collections
- No Modern Talent UI (uses Classic talent trees)
- Limited C_Container functionality compared to Retail

This means code must be compatible with 12.0.1 restrictions while avoiding Retail-exclusive APIs.

---

## Current Implementation Status (Post Phase 1 & 2)

### ✅ Completed Features
- Pre-calculated navigation graph with smart invalidation
- NavigationGraph.lua module with proper separation of concerns
- Combat lockdown detection and automatic navigation disabling
- Graph validation and node visibility checking
- Tooltip memory leak fixes
- OnUpdate race condition mitigations
- Secure widget management system
- Driver frame with SecureHandlerStateTemplate
- Event-driven architecture (partial - uses OnUpdate fallback)
- Cache hit metrics and graph reuse optimization

### 🔧 In Progress (Phase 3 & 4)
- EventNavigation Graph Builder (`View/NavigationGraph.lua`)
* **Purpose**: Builds and maintains pre-calculated navigation graph for efficient UI traversal.
* **Status**: ✅ Phase 1 Complete - Well-separated, production-ready
* **Functionality**:
    * **Graph Building**: Scans visible UI frames using ConsolePortNode library once per UI session
    * **Edge Calculation**: Pre-calculates directional neighbors (up/down/left/right) for each node using spatial algorithms
    * **Smart Invalidation**: Compares frame names and node counts; rebuilds only when UI state changes
    * **Node Validation**: Ensures nodes remain visible and relevant before navigation (IsDrawn, IsRelevant checks)
    * **Index Mapping**: Provides bidirectional node ↔ index mapping for secure attribute storage
    * **Cache Metrics**: Optional performance tracking (hits/misses) for graph reuse monitoring
* **Technical Requirements**:
    * **Out-of-Combat Only**: Graph building disabled during `PLAYER_REGEN_DISABLED` (combat lockdown)
    * **Defensive Validation**: Gracefully handles NODE library failures with nil checks and fallback logic
    * **Performance**: Graph builds complete in <50ms for typical UIs (character sheet + bags)
    * **Memory Efficient**: Reuses existing graph when frame state unchanged (cache hit)
* **Public API**:
    * `BuildGraph(frames)` → boolean - Scans frames and builds navigation graph
    * `InvalidateGraph()` - Marks graph stale, triggers rebuild on next access
    * `NodeToIndex(node)` → index - Converts node reference to graph index
    * `IndexToNode(index)` → node - Converts graph index to node reference
    * `GetNodeEdges(index)` → {up, down, left, right} - Returns directional neighbor indices
    * `GetFirstNodeIndex()` → index - Returns first valid node for initial focus
    * `GetNodeCount()` → number - Returns total navigable nodes
    * `IsValid()` → boolean - Checks if current graph is valid
* **Architecture Notes**:
    * Uses NODE() function to scan frames and return cache array
    * Each cache item: {node, super, object, level, ...}
    * Stores nodes as: {node, x, y, super} with GetCenterScaled() positions
    * Edges calculated using directional algorithms (closest node in each direction)

### 3. Navigation Orchestrator (`View/Hijack.lua`)
* **Purpose**: Manages UI navigation lifecycle and coordinates between graph, input, and visual feedback.
* **Status**: 🔧 Phase 2 Complete, Phase 3 & 4 In Progress
* **Functionality**:
    * **Lifecycle Management**: Handles `EnableNavigation()`/`DisableNavigation()` with proper cleanup and rollback
    * **Input Handling**: Routes D-Pad input to graph navigation using `Navigate(direction)` with validation
    * **Focus Management**: Maintains `CurrentNode` state and validates navigation targets before traversal
    * **Visual Coordination**: Updates gauntlet cursor and tooltips via `UpdateVisualFeedback()` coordinator
    * **Combat Safety**: Automatically disables during combat lockdown with state restoration on exit
    * **Frame Detection**: Event-driven visibility monitoring with OnUpdate fallback (0.1s interval)
    * **Graph Integration**: Builds graph on UI open, reuses on subsequent opens if frames unchanged
* **Architecture**:
    * **Driver Frame**: Uses `SecureHandlerStateTemplate` with dedicated binding frame (CPLightInputDriver, not UIParent)
    * **Widget System**: Manages secure input widgets (PAD1, PAD2, PADDUP, PADDDOWN, PADDLEFT, PADDRIGHT) with `SecureActionButtonTemplate`
    * **State Machine**: Tracks navigation active state (`IsActive`), combat state, frame visibility
    * **Debounced Rebuilds**: RebuildState with pending flag and timer generation prevents rebuild storms
* **Combat Safety**:
    * Pre-checks `InCombatLockdown()` before all binding operations (`SetOverrideBindingClick`, `ClearOverrideBindings`)
    * Clears overrides immediately on combat start (`PLAYER_REGEN_DISABLED`)
    * Restores navigation on combat end if UI still visible (`PLAYER_REGEN_ENABLED`)
    * Widget combat lockdown handler via `_childupdate-combat` secure snippet
* **Performance Optimizations**:
    * **Graph Reuse**: Compares LastGraphState (frameNames, nodeCount) before rebuilding
    * **Cache Hit Tracking**: Optional GraphCacheStats metrics (hits/misses) for performance monitoring
    * **Debounced Rebuilds**: 0.3s delay on frame visibility changes prevents rapid rebuild cycles
    * **Lazy Hook Registration**: OnShow/OnHide hooks registered once, not per enable cycle
* **Current Issues (Phase 3/4 Targets)**:
    * ❌ Still uses OnUpdate polling (0.1s interval) for visibility detection
    * ❌ Visual feedback mixed with navigation logic (needs extraction)
    * ❌ PreClick handlers defined inline in EnableNavigation (should be named methods)
    * ❌ No clear method grouping/organization (8-section refactor planned)
    * ❌ Combat transition edge cases (graph invalidation during combat)
* **Planned Refactor Structure (Phase 4)**:
    ```
    SECTION 1: Module Setup & Constants
    SECTION 2: Driver Frame & State Management
    SECTION 3: Navigation Core (Navigate, SetFocus, traversal)
    SECTION 4: Widget & Binding Management
    SECTION 5: Visual Feedback (Gauntlet, Tooltips)
    SECTION 6: UI Frame Detection (Visibility hooks)
    SECTION 7: Combat Safety (lockdown handlers)
    SECTION 8: Module Lifecycle (OnEnable, OnDisable)
    ```
- Custom frame whitelist (user-configurable)
- Target tooltips on soft/hard lock
- External addon support (Questie, Immersion, bag addons)
- Minimal configuration UI (button mapping only)

### ⚠️ Known Limitations
- **PreClick Taint Risk**: D-pad navigation uses insecure PreClick handlers (pragmatic approach accepting potential taint)
- **NODE Library Dependency**: Relies on ConsolePortNode library for frame scanning
- **Blizzard UI Only**: No support for custom addon UIs without explicit integration
- **Actions Module Dormant**: Smart click handling code exists but not integrated into navigation flow
- **4. Smart Click Handler (`View/Actions.lua`) - **CURRENTLY DISABLED**
* **Status**: ❌ Module exists but commented out in `View/__manifest.xml` - Integration decision pending
* **Purpose**: Provide context-aware click handling for inventory, spells, merchants, and other UI elements
* **Current State**:
    * ✅ Module code complete with button type detection
    * ✅ Event handlers registered (MERCHANT_SHOW, TRADE_SHOW, etc.)
    * ❌ Not called by Hijack module
    * ❌ No hooks into PAD1/PAD2 click handlers
    6. API & Constants (`Utils/Const.lua`)
* **Purpose**: Abstracts version-specific API changes to prevent Lua errors across WoW client versions
* **Version Detection**:
    * `CPAPI.IsAnniVersion` - WoW TBC Anniversary (2.5.5) - **Primary Target**
    * `CPAPI.IsClassicEraVersion` - Classic Era (Vanilla)
    * `CPAPI.IsWrathVersion` - Wrath Classic
    * `CPAPI.IsRetailVersion` - Retail (Mainline)
* **Crucial API Bridges**:
    * **Cursor API**: `CPAPI.SetCursor` → `C_Cursor.SetCursorPosition` (Required for 2.5.5/12.0.1 API)
    * **Mouse Focus**: `CPAPI.GetMouseFocus` → `GetMouseFoci()[1]` (Handles modern UI multi-focus changes)
    * **Action Attributes**: 
        * `CPAPI.ActionTypeRelease` → `typerelease` (Anniversary/Retail) or `type` (Classic)
        * `CPAPI.ActionPressAndHold` → `pressAndHoldAction` (Controller support)
    * **Movement Constants**: 
        * `CPAPI.Movement.AngleCombat` = 180 (Tank Mode: Always strafe, never turn)
        * `CPAPI.Movement.AngleTravel` = 45 (Travel Mode: Smooth interpolation, immediate turning)
        * `CPAPI.Movement.CameraLocked` = 2 (TurnWithCamera: Lock during cast/vehicle)
* **Usage Pattern**:
    ```lua
    -- Version-specific logic
    if CPAPI.IsAnniVersion then
        widget:RegisterForClicks('AnyUp', 'AnyDown')
        widget:SetAttribute(CPAPI.ActionPressAndHold, true)
    end
    
    -- Movement angle switching
    self.Proxy.StrafeAngleCombat:Set(CPAPI.Movement.AngleCombat)
    ```
        * `HandleContainer()` - Use/equip items, stack splitting
        * `HandleEquipment()` - Character sheet slot interactions
        * `HandleMerchant()` - Buy/sell with quantity detection
        * `HandleTrade()` - Trade window item placement
        * `HandleGeneric()` - Fallback direct click
* **Public API** (Planned):
    * `GetButtonType(button)` → string - Returns button category
    * `ExecuteAction(button, clickType)` → boolean - Performs smart action
    * `GetContainerInfo(button)` → table - Returns bag/slot details
* **Integration Decision Required**:
    * **Option A (Current)**: Keep disabled - Use pass-through clicks (simpler, no additional complexity)
    * **Option B (Enhanced)**: Integrate with Hijack - Add smart action layer for improved UX
    * **Option C (Remove)**: Delete file if not on roadmap
* **Integration Plan (If Option B)**:
    ```lua
    -- In Hijack:_ConfigureWidgetsForNode(node)
    local buttonType = Actions:GetButtonType(node)
    if buttonType ~= "generic" then
        -- Prepare smart action context
        Actions:PrepareAction(node, buttonType)
    end
    ```

### 5. Click Handling (Current Implementation in `View/Hijack.lua`)
* **Current Approach**: Direct pass-through clicks using `SecureActionButtonTemplate`
* **Functionality**:
    * **Widget Configuration**: `_ConfigureWidgetsForNode()` sets up PAD1/PAD2 widgets targeting focused node
    * **Secure Clicks**: Widgets use `clickbutton` attribute to trigger game's native click handling
    * **Button States**: Driver.ButtonStates tracks button down/up to prevent double navigation on single press
    * **Click Registration**: Uses Anniversary client's `RegisterForClicks('AnyUp', 'AnyDown')`
    * **Press & Hold**: Sets `ActionPressAndHold` attribute for proper controller behavior
* **Technical Details**:
    * PAD1 → LeftButton click (primary action: use, equip, select)
    * PAD2 → RightButton click (secondary action: sell, consume, context menu)
    * Click handling entirely within secure context (no taint)
    * Widget ownership tracked via `owner` attribute
* **Future Enhancement**: Could integrate with Actions.lua for smart context detection and specialized handling
┌─────────────────────────────────────┐
│   ConsolePortNode (External Lib)   │
│   - Frame scanning (NODE)           │
│   - Node validation (IsDrawn)       │
│   - Position calculation            │
└─────────────────┬───────────────────┘
                  │ used by
┌─────────────────▼───────────────────┐
│   7. Core Systems (`Core/`)
* **Core.lua**: Ace3-based addon initialization and lifecycle management
    * Global CPLight frame object (`_G.CPLight`)
    * AceAddon-3.0 setup and module system
    * Namespace data initialization (`ns.Data`)
    * CVar helper for legacy/retail compatibility
    * SavedVariables initialization (CPLightSettings, CPLightCharacter)
    * Module loader notification system
* **Database.lua**: Minimal database system for CPLight
    * Module registration via `db:Register(id, obj)`

### Core Principles
1.  **Strictly 2.5.5 Compatible**: Never use Retail-only APIs (EditMode, Transmog, Modern Talent UI) or Vanilla-only APIs. Use 12.0.1 API patterns with Anniversary limitations.
2.  **No Logic Stripping**: Do not remove navigation fallbacks or distance calculations; required for cross-window jumping and edge cases.
3.  **Binding Safety**: Never call `ClearOverrideBindings()` during combat. Always use dedicated Driver Frame (CPLightInputDriver), never UIParent.
4.  **Graph Efficiency**: Reuse existing graph when possible; only rebuild when frames change (compare LastGraphState).
5.  **Combat Lockdown**: All secure operations (SetOverrideBindingClick, ClearOverrideBindings, widget configuration) wrapped in `InCombatLockdown()` checks.
6.  **Defensive Coding**: Validate all NODE library results; handle nil gracefully with fallback logic.
7.  **Structurally Sound**: Code must be scalable, modular, resilient, efficient, testable, and readable.

### Performance Targets
- **Graph Build Time**: <50ms for typical UIs (character sheet + bags)
- **Navigation Response**: <16ms (1 frame) for directional input
- **OnUpdate CPU**: <1% when idle
- **Memory Growth**: <1MB per session (no leaks)
- **Graph Cache Hit Rate**: >80% for normal gameplay (reuse vs rebuild)

### Code Quality Standards
- All methods under 50 lines (extract complex logic)
- Clear separation of concerns across modules
- No dead code or unused functions
- All public APIs documented with LuaDoc
- Logical organization within files (section comments)
- Consistent naming conventions (PascalCase for methods, camelCase for variables)

### Security & Taint
- **Accepted Risk**: D-pad navigation uses insecure PreClick handlers (pragmatic trade-off)
- **Mitigation**: Separate navigation from action execution; actions remain in secure context
- **No Protected Calls**: Avoid pcall/xpcall in secure code paths
- **Widget Ownership**: Track widget ownership to prevent cross-module conflicts

### Testing Requirements
- **Regression Tests**: Basic navigation, combat entry/exit, multiple frames, dynamic UI changes
- **Edge Cases**: Rapid frame open/close, navigation during loading, tooltip flicker prevention
- **Performance**: Profile graph build, navigation response, OnUpdate CPU usage
- **Memory**: Check for leaks from tooltips, hooks, widget references

### Module Interaction Rules
- **NavigationGraph** is stateless (pure functions for graph operations)
- **Hijack** orchestrates but delegates to NavigationGraph for graph logic
- **Actions** (if enabled) is consulted by Hijack but doesn't modify navigation state
- **Movement** is independent; no cross-dependency with navigation modules
- All inter-module communication via well-defined public APIs (no reaching into internal state)
* **API.lua**: Core API functions and helpers
* **Stubs.lua**: Placeholder/stub functions for missing features

### 8. Future Enhancements
* **Purpose**: Planned features pending project lifecycle/demand
* **Phase 1 & 2 Complete** ✅:
    * ✅ Pre-calculated navigation graph (NavigationGraph.lua)
    * ✅ Combat safety with automatic lockdown handling
    * ✅ Visual feedback decoupling (gauntlet, tooltips)
    * ✅ Graph caching with smart invalidation
* **Phase 3 Targets** 🔧:
    * ⏳ Event-driven visibility detection (replace OnUpdate with OnShow/OnHide hooks)
    * ⏳ Combat transition safety (WasActiveBeforeCombat state tracking)
    * ⏳ Binding safety audit (verify all lockdown checks)
* **Phase 4 Targets** 🔧:
    * ⏳ Hijack.lua reorganization (8-section refactor)
    * ⏳ Extract inline PreClick handlers to named methods
    * ⏳ Actions.lua integration decision (Option A/B/C)
    * ⏳ LuaDoc comments for all public methods
* **Future Roadmap** 📋:
    * 🔲 Target tooltip on soft/hard lock
    * 🔲 Center mouse cursor when idle/out of combat
    * 🔲 External addon support (Questie, Immersion, bag addons node traversal)
    * 🔲 Navigation history (back button functionality)
    * 🔲 Custom frame whitelist (user-configurable navigable frames)
    * 🔲 Minimal configuration UI (button mapping only, not full ConsolePort package)
    * 🔲 Smart Actions integration (context-aware clicks via Actions.lua)
                  │ used by
┌─────────────────▼───────────────────┐
│   Hijack.lua                        │
│   - Enable/Disable navigation       │
│   - D-Pad input routing             │
│   - Focus management                │
│   - Visual feedback (gauntlet)      │
│   - Combat lockdown handling        │
└─────────────────┬───────────────────┘
                  │ could use (future)
┌─────────────────▼───────────────────┐
│   Actions.lua (DISABLED)            │
│   - Smart click detection           │
│   - Context-aware actions           │
│   - Inventory operations            │
└─────────────────────────────────────┘
```

---

## Core Components

### 1. Movement System (`Controller/Movement.lua`)
* **Purpose**: Translates analog stick input into character movement.
* **Logic Modes**:
    * **Travel Mode (Out of Combat)**: Movement follows the direction of the analog stick (360° freedom). Uses 45° strafe angle for smooth interpolation and immediate turning response.
    * **Combat Mode (In Combat)**: Maintains forward-facing orientation; always strafes (180° angle). Character never turns with movement stick.
* **Technical Requirements**:
    * **Angle System**: Uses `RegisterAttributeDriver` with `[combat] 180; 45` macro to switch between modes without taint.
        * Lower angle (45°) = character faces movement direction quickly
        * Higher angle (180°) = character strafes, never turns
    * **Deadzone Management**: Ignores stick input below a specific threshold (e.g., 0.2) to prevent "stick drift."
    * **Camera Integration**: Manages Pitch and Yaw to ensure the character/camera follows stick direction.
    * **Casting Guard**: Locks camera (TurnWithCamera=2) during active spell casts (`UNIT_SPELLCAST_START`) and vehicle usage.

### 2. Cursor Hijack (`View/Hijack.lua`)
* **Purpose**: Intercepts gamepad input when specific UI windows are open.
* **Functionality**:
    * **Input Override**: Uses a dedicated **Binding Driver Frame** (not `UIParent`) to override the D-Pad and PAD buttons when Blizzard UI windows are open.
    * **Gauntlet Visual**: A 32x32 texture (`Interface\CURSOR\Point`) that follows the focused node.
    * **Tooltip**: Show tooltip only when gauntlet is hover over a node with an object in it.
    * **Release Mechanism**: Ensures `ClearOverrideBindings` is called immediately when windows close, returning Jump/Movement to the player.
    * **Combat Safety**: Automatically disables UI Hijack during `PLAYER_REGEN_DISABLED` to prevent secure header errors.

### 3. Cursor Action handling (`View\Actions.lua`)
* **Purpose**: Secure input handling on the down-press of the appropriate controller buttons.
* **Functionality**:
    * **Frame Visibility Check**: During buttonDown events check for Frame visibility
    * **Navigation**: Utilizes ConsolePortNode library for secure UI navigation.
    * **Secure Proxy**: Utilizes `SecureActionButtonTemplate` to perform `LeftButton` (PAD1) and `RightButton` (PAD2) clicks on UI nodes.
    * **Use spell/consumable**: Cast/Use spell or consumable the gauntlet is hovering over with SetOverrideBindingClick on SecureHandlerStateTemplate that covers the entire screen.

### 4. API & Constants (`Utils/Const.lua`)
* **Purpose**: Abstracts version-specific API changes to prevent Lua errors.
* **Crucial Bridges**:
    * **Cursor API**: `CPAPI.SetCursor` maps to `C_Cursor.SetCursorPosition` (Required for 2.5.5).
    * **Mouse Focus**: `CPAPI.GetMouseFocus` maps to `GetMouseFoci()[1]` (Handles modern UI changes).
    * **Version Constants**: `CPAPI.IsAnniVersion` to toggle logic specific to the 2.5.5 client.
    * **Movement Constants**: `CPAPI.Movement` table defines angles (Combat=180, Travel=45) and camera lock behavior for consistent project-wide usage.

### 5. Bonus Feature(s) (`TBD`)
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