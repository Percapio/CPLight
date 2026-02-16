# CPLight — Source of Truth

> **Purpose:** Canonical reference for any AI agent (or developer) working on CPLight.
> Read this document *first* before modifying any file.

---

## 1. Project Overview

**CPLight** is a minimalist gamepad-driven UI navigation and movement addon for **World of Warcraft TBC Anniversary (client 2.5.5 which is similar to 12.x, Interface 20505)**. It allows a player using an Xbox-style controller to:

1. Move with analog sticks (tank mode / travel mode).
2. Navigate UI frames (menus, bags, vendors, quest logs) using the **D-pad**.
3. Click focused UI elements with **PAD1 (A)** / **PAD2 (B)** buttons.
4. Map controller buttons to keyboard modifiers (Shift / Ctrl / Alt).

It depends on the **ConsolePortNode** library (an external dependency by Sebastian Lindfors) for frame scanning and spatial navigation.

---

## 2. Folder Architecture

```
CPLight/
├── CPLight.toc                      # Entry point — defines load order & SavedVariables
├── TOCversion.lua                   # Version gate (hard-blocks non-20505 clients)
│
├── Core/                            # LAYER 1 — Foundation (loads first)
│   ├── __manifest.xml               # Load order: API → Core → Database
│   ├── API.lua                      # Global CPAPI namespace, polyfills, debug logging
│   ├── Core.lua                     # AceAddon bootstrap, DB init, lifecycle events
│   └── Database.lua                 # ns-scoped registry (db:Register, callbacks, variables)
│
├── Utils/                           # LAYER 2 — Shared Constants
│   ├── __manifest.xml               # Load order: Const
│   └── Const.lua                    # Movement angles, scroll constants, action types
│
├── Controller/                      # LAYER 3 — Input Handling
│   ├── __manifest.xml               # Load order: Movement
│   └── Movement.lua                 # Analog stick logic, tank/travel mode, CVar proxying
│
├── View/                            # LAYER 4 — UI Navigation
│   ├── __manifest.xml               # Load order: NavigationGraph → Hijack
│   ├── NavigationGraph.lua          # Graph builder wrapper around ConsolePortNode
│   └── Hijack.lua                   # D-Pad hijacking, gauntlet cursor, state machine
│
├── Config/                          # LAYER 5 — Settings
│   ├── __manifest.xml               # Load order: CVarManager → Options → IconMapping
│   ├── CVarManager.lua              # GamePad modifier CVar read/write + runtime cache
│   ├── Options.lua                  # AceConfig UI panel (ESC → Interface → AddOns)
│   └── IconMapping.lua              # Replaces KEY_PAD* strings with Xbox icon textures
│
├── Libs/                            # External Dependencies
│   ├── LibStub/                     # Library versioning
│   ├── Ace3/                        # AceAddon, AceDB, AceEvent, AceGUI, AceConfig
│   └── ConsolePortNode/             # Frame scanning & spatial navigation (THE bug source)
│       └── ConsolePortNode.lua      # 866 lines — see §9 for deep analysis
│
└── Media/
    └── XboxSeries/                  # Controller button icon textures
```

### Load Order (from CPLight.toc)

```
1. LibStub
2. Ace3 (AceAddon, AceDB, AceEvent, AceGUI, AceConfig)
3. ConsolePortNode
4. TOCversion.lua         ← version gate, blocks non-2.5.5
5. Core/__manifest.xml    ← API.lua → Core.lua → Database.lua
6. Utils/__manifest.xml   ← Const.lua
7. Controller/__manifest.xml ← Movement.lua
8. View/__manifest.xml    ← NavigationGraph.lua → Hijack.lua
9. Config/__manifest.xml  ← CVarManager.lua → Options.lua → IconMapping.lua
```

**Critical ordering constraint:** `NavigationGraph.lua` MUST load before `Hijack.lua` because Hijack does `local NavGraph = _G.CPLightNavigationGraph` at file scope.

---

## 3. Module Catalog

### Core/API.lua
**Responsibility:** Defines the global `CPAPI` namespace with polyfills (`GetMouseFocus`, `Mixin`, `GenerateClosure`), event handler creation (`CPAPI.CreateEventHandler`), and the debug logging system (`CPAPI.Log`, `CPAPI.DebugLog`, `CPAPI.SetDebugMode`).
**Dependencies:** None (loads first). Provides foundation for all other modules.
**Key detail:** `CPAPI.CreateEventHandler` creates a frame, mixes in a storage table, registers events, and wires `OnEvent` to dispatch `self[event](self, ...)`.

### Core/Core.lua
**Responsibility:** Bootstraps the addon. Creates the global `_G.CPLight` frame (for XML parenting), instantiates the AceAddon object `App`, initializes AceDB with `CPLightDB` SavedVariables, and calls `OnDataLoaded` on registered modules.
**Dependencies:** LibStub, AceAddon-3.0, AceDB-3.0, AceEvent-3.0. Writes to `ns.Data`.
**Key detail:** The AceAddon object (`App`) is separate from the global `_G.CPLight` frame to avoid overwriting the frame with a table.

### Core/Database.lua
**Responsibility:** Transforms the addon namespace `ns` into a database object with `Register()`, `Get()`, callback system (`RegisterCallback`, `TriggerEvent`), and simple key-value storage via `__call` metamethod.
**Dependencies:** Core/API.lua (for `GenerateClosure`). Sets `ns.db = ns` for backward compatibility.
**Key detail:** `db:Register('Movement', obj)` stores the module in `Registry` AND sets `db.Movement = obj` for dot-notation access.

### Utils/Const.lua
**Responsibility:** Declares project-wide numeric constants on the `CPAPI` namespace — movement angles (`AngleCombat=180`, `AngleTravel=45`), camera lock value, scroll parameters, action type strings, and lifecycle markers (`BurnAfterReading`, `KeepMeForLater`).
**Dependencies:** `CPAPI` global (from API.lua).

### Controller/Movement.lua
**Responsibility:** Manages analog stick movement by proxying GamePad CVars (`GamePadAnalogMovement`, `GamePadFaceMovementMaxAngle`, etc.) and using `RegisterAttributeDriver` to switch between tank mode (combat, angle=180) and travel mode (out-of-combat, angle=45). Handles casting/vehicle camera lock overrides.
**Dependencies:** `ns` (Database), `CPAPI` (constants, event handler), `CPLight` frame (parent). Registers for unit spellcast/vehicle events.
**Key detail:** Uses `SecureHandlerAttributeTemplate` with `RegisterAttributeDriver` for zero-taint state switching.

### View/NavigationGraph.lua
**Responsibility:** Wraps ConsolePortNode's scanning and caching. Provides `BuildGraph(frames)` (calls `NODE(...)` to scan), `NavigateInDirection(cacheItem, direction)` (calls `NODE.NavigateToBestCandidateV3`), `InvalidateGraph()`, and position/index lookups. Exposed globally as `_G.CPLightNavigationGraph`.
**Dependencies:** LibStub('ConsolePortNode'), `CPAPI` (debug logging).
**Key detail:** `BuildGraph` stores NODE's returned CACHE array and builds a `nodeToIndex` reverse-lookup map. `NavigateInDirection` is wrapped in `pcall` to catch ConsolePortNode crashes gracefully (see §9).

### View/Hijack.lua
**Responsibility:** The main orchestrator. Detects visible UI frames, enables/disables D-pad navigation, manages the gauntlet cursor state machine, handles scroll navigation, and sets up secure input widget bindings. This is the largest module (~1681 lines).
**Dependencies:** AceAddon (module of "CPLight"), LibStub('ConsolePortNode'), `_G.CPLightNavigationGraph`, `addon.CVarManager`, `CPAPI`.
**Key detail:** Uses a transaction-style `EnableNavigation()` with `_RollbackEnableState()` on failure. The `Driver` frame is a separate `SecureHandlerStateTemplate` that monitors combat state.

### Config/CVarManager.lua
**Responsibility:** Reads/writes `GamePadEmulateShift/Ctrl/Alt` CVars. Maintains a runtime cache for O(1) `IsModifier(button)` checks (avoids calling `GetCVar` on every button press). Saves/restores original CVar values.
**Dependencies:** AceAddon (for DB access), `CPAPI` (debug logging), `addon.IconMapping` (updates icons on apply).

### Config/Options.lua
**Responsibility:** AceConfig-3.0 options table for the Interface → AddOns → CPLight panel. Three dropdowns (Shift/Ctrl/Alt modifier mapping), Apply/Restore buttons, debug mode toggle.
**Dependencies:** AceConfig-3.0, AceConfigDialog-3.0, `addon.CVarManager`.

### Config/IconMapping.lua
**Responsibility:** Replaces global `KEY_PAD*` strings with Xbox Series controller icon textures (`|T...:16:16|t`). Runs once on `PLAYER_LOGIN`. Updates modifier abbreviation icons when CVarManager assignments change.
**Dependencies:** `CPAPI` (for `IsAnniVersion` check, debug logging), `addon.CVarManager`.

---

## 4. Data Schemas

### 4.1 Gauntlet State Machine (Hijack.lua)

```
States:
  HIDDEN    → Gauntlet invisible, no navigation active
  POINTING  → Gauntlet visible, cursor on a clickable node
  PRESSING  → Gauntlet enlarged ("interact" texture), PAD1/PAD2 pressed
  SCROLLING → Gauntlet shows D-pad icon, node is a scroll control

Transitions:
  HIDDEN ──→ POINTING          (frame becomes visible, navigation enabled)
  POINTING ──→ PRESSING        (PAD1/PAD2 down press)
  POINTING ──→ HIDDEN          (all frames close, combat starts)
  POINTING ──→ SCROLLING       (focus moves to scroll node)
  PRESSING ──→ POINTING        (PAD1/PAD2 released)
  PRESSING ──→ HIDDEN          (combat starts during press)
  SCROLLING ──→ POINTING       (focus moves off scroll node)
  SCROLLING ──→ HIDDEN         (all frames close)

Invalid transitions auto-correct through POINTING as intermediary.
Recursion depth guard: max 3 levels.
```

### 4.2 Navigation Graph (NavigationGraph.lua + ConsolePortNode)

```lua
-- Internal state table (module-local `graph`)
graph = {
    nodeCache = {},      -- Array of NODE cache items (from ConsolePortNode's CACHE)
    nodeToIndex = {},    -- Reverse map: node_frame → integer_index
    isDirty = false,     -- True = graph needs rebuild before next use
    lastBuildTime = 0,   -- GetTime() of last successful build
}

-- Each cache item in nodeCache (created by ConsolePortNode):
cacheItem = {
    node   = <Frame>,    -- The interactive UI element (Button, CheckBox, EditBox, Slider)
    object = "Button",   -- GetObjectType() result
    super  = <Frame>,    -- Clipping ancestor (ScrollFrame or DoesClipChildren parent)
    level  = 30042,      -- Absolute frame level: LEVELS[strata] + GetFrameLevel()
}
```

### 4.3 ConsolePortNode Internal Caches

```lua
CACHE = {}   -- Array of cache items (eligible interactive nodes), ordered by nodepriority
RECTS = {}   -- Array of {node, level} for rect-occlusion checks, ordered by descending level

-- Both are wiped on every NODE(...) call via ClearCache()
-- BOUNDS = Vector3D(screenWidth, screenHeight, UIParent:GetEffectiveScale())
```

### 4.4 Graph State Tracking (Hijack.lua — for cache reuse)

```lua
Hijack.LastGraphState = {
    frameNames = {},  -- Array of frame name strings from last build
    nodeCount = 0,    -- Node count from last build
    buildTime = 0,    -- GetTime() timestamp
}

-- Reuse criteria (_CanReuseGraph):
-- 1. NavGraph is valid (not dirty)
-- 2. Same frame name set as last build
-- 3. Same node count
-- 4. Graph age < 30 seconds (GRAPH_STALE_THRESHOLD)
```

### 4.5 SavedVariables Schema

```lua
-- CPLightDB (global SavedVariables)
CPLightDB = {
    global = {
        originalCVars = {           -- Captured on first-ever load
            shift = "PADLTRIGGER",  -- User's pre-CPLight values
            ctrl  = "NONE",
            alt   = "NONE",
        },
        iconsApplied = false,       -- Deprecated (now detected in-memory)
    },
    profiles = {
        ["Default"] = {
            modifiers = {
                shift = "PADLTRIGGER",
                ctrl  = "PADRSHOULDER",
                alt   = "NONE",
            },
            debugMode = false,
        },
    },
}
```

### 4.6 Rebuild State (Debouncing Schema)

```lua
Hijack.RebuildState = {
    pending = false,         -- Is a rebuild timer currently running?
    hooksRegistered = false, -- Have OnShow/OnHide hooks been set up?
    timerGeneration = 0,     -- Monotonic counter — stale timer callbacks are discarded
}
```

---

## 5. Interaction Map — D-Pad Press to Frame Click

### Phase 1: Activation (Frame Opens)

```
User opens CharacterFrame (or any registered frame)
    │
    ├─ OnShow hook fires → RequestGraphRebuild()
    │     ├─ Debounces: increments timerGeneration, sets pending=true
    │     └─ C_Timer.After(0.1) callback:
    │           ├─ Verifies timerGeneration matches (discards stale)
    │           ├─ Calls _CollectVisibleFrames() (scans FRAMES registry)
    │           └─ Calls EnableNavigation()
    │
    └─ EnableNavigation() [transaction-style with rollback]:
          ├─ Step 1: _BuildGraph(activeFrames)
          │     ├─ NavigationGraph:BuildGraph() → NODE(frame1, frame2, ...)
          │     │     ├─ ClearCache() → wipe(CACHE), wipe(RECTS)
          │     │     ├─ Scan(nil, frame1, frame2, ...) [recursive]
          │     │     │     Tests each child: IsRelevant? IsDrawn? IsInteractive?
          │     │     │     Eligible nodes → CacheItem() → inserted into CACHE
          │     │     │     Mouse-enabled non-interactive → CacheRect() (occlusion)
          │     │     └─ ScrubCache() removes nodes occluded by higher-level rects
          │     └─ Stores CACHE, builds nodeToIndex map
          │
          ├─ Step 2: _SetupSecureWidgets()
          │     Creates SecureActionButtonTemplate widgets for:
          │       PAD1 (A=left-click), PAD2 (B=right-click),
          │       PADDUP, PADDDOWN, PADDLEFT, PADDRIGHT
          │     Calls SetOverrideBindingClick() for each
          │
          ├─ Step 3: _SetupNavigationHandlers()
          │     PreClick scripts on D-Pad widgets → Hijack:Navigate(direction)
          │     PreClick/PostClick on PAD1/PAD2 → gauntlet press visual
          │
          ├─ Step 4: IsActive = true (commit point)
          │
          └─ Step 5: SetFocus(firstNode), SetGauntletState(POINTING)
```

### Phase 2: Navigation (D-Pad Press)

```
User presses D-Pad RIGHT
    │
    ├─ WoW fires binding → CPLight_Input_PADDRIGHT:PreClick(button, down=true)
    │
    └─ Hijack:Navigate('RIGHT')
          ├─ Check scroll node? → If yes, HandleScrollNavigation()
          ├─ Get currentIndex from NavGraph:NodeToIndex(CurrentNode)
          ├─ Get currentCacheItem from NavGraph:GetCacheItem(index)
          │
          └─ NavGraph:NavigateInDirection(currentCacheItem, 'RIGHT')
                ├─ pcall(NODE.NavigateToBestCandidateV3, cacheItem, 'RIGHT')
                │     ├─ GetCandidateVectorForCurrent: origin = {x, y, h=huge, v=huge}
                │     ├─ GetCandidatesForVectorV2: multi-point per candidate
                │     │     For each CACHE item, gets scaled rect, generates points,
                │     │     computes angle + distance to origin
                │     └─ Selects closest candidate with angle-weighted distance
                │
                ├─ If pcall fails → returns nil (stale node protection)
                └─ Returns nextCacheItem
          │
          └─ Hijack:SetFocus(nextCacheItem.node)
                ├─ _ValidateNodeFocus(node) — visibility + pcall safety
                ├─ _ConfigureWidgetsForNode(node)
                │     Sets PAD1/PAD2 clickbutton attribute → node
                ├─ _UpdateVisualFeedback(node)
                │     UpdateGauntletPosition() + ShowTooltipForNode()
                └─ SetGauntletState(POINTING or SCROLLING)
```

### Phase 3: Click (PAD1 Press)

```
User presses PAD1 (A button)
    │
    ├─ PreClick fires (insecure) → SetGauntletPressed(true) → visual feedback
    │
    ├─ SecureActionButtonTemplate executes (secure context)
    │     Reads clickbutton attribute → fires Click() on the target node
    │     This is a real protected mouse click with no taint.
    │
    └─ PostClick fires (insecure) → SetGauntletPressed(false) → visual restore
```

### Phase 4: Deactivation (Frame Closes)

```
User closes CharacterFrame
    │
    ├─ OnHide hook fires → RequestGraphRebuild()
    │     Debounced check → _CollectVisibleFrames() finds 0 frames
    │     → DisableNavigation()
    │
    └─ DisableNavigation()
          ├─ StopScrollRepeat()
          ├─ Driver:ReleaseAll() (clears clickbutton, hides widgets)
          ├─ ClearOverrideBindings() for all widgets
          ├─ HideGauntlet() → state → HIDDEN
          ├─ HideTooltip()
          ├─ CurrentNode = nil
          └─ Graph is PRESERVED (not invalidated) for potential reuse
```

---

## 6. Technical Constraints

### 6.1 Client API: TBC Anniversary 2.5.5

| Constraint | Detail |
|---|---|
| Lua version | 5.1 (has `setfenv`, no `goto`, no bitwise ops) |
| Interface version | 20505 — hardcoded gate in `TOCversion.lua` |
| Protected actions | `Click()`, `CastSpellByID()`, etc. require secure execution context |
| Secure templates | Must use `SecureActionButtonTemplate` + `SetOverrideBindingClick` |
| CVar API | Uses `GetCVar`/`SetCVar` directly (no `C_CVar` wrapper in 2.5.5 — polyfilled in Core.lua) |
| Timer API | `C_Timer.After()` and `C_Timer.NewTicker()` are available |
| Frame API | `GetRect()` can return nil for frames without anchors or during hide transitions |
| `GetMouseFocus` | Polyfilled to wrap `GetMouseFoci()` (return first element) |
| Missing Blizzard APIs | `Mixin`, `GenerateClosure` are polyfilled in API.lua |

### 6.2 Zero-Taint Philosophy

**Rule:** No insecure code path may ever call a protected function, directly or indirectly.

How CPLight achieves this:
- **Secure boundary:** The `Driver` frame (`SecureHandlerStateTemplate`) and its child widgets (`SecureActionButtonTemplate`) handle all protected actions.
- **Insecure navigation:** All D-pad navigation, gauntlet rendering, and tooltip management run in **insecure context** via `PreClick` / `PostClick` scripts.
- **Combat lockdown:** `RegisterStateDriver(Driver, 'combat', '[combat] true; nil')` disables widgets via `_childupdate-combat`. Every mutation function guards with `InCombatLockdown()`.
- **Attribute-driven state switching:** Movement.lua uses `RegisterAttributeDriver` to change CVars — the secure handler framework reads the macro condition and fires `OnAttributeChanged` without taint.
- **No `RunAttribute` from insecure:** We never call `SetAttribute` on secure frames during combat. Widget setup and teardown are gated by `assert(not InCombatLockdown())`.

### 6.3 Memory Management

| Pattern | Implementation |
|---|---|
| Table reuse | `wipe()` used in `InvalidateGraph()` and ConsolePortNode's `ClearCache()` to clear tables in-place rather than creating new ones |
| Graph preservation | `DisableNavigation()` does NOT invalidate the graph — it's reused on next `EnableNavigation()` if frame set is unchanged |
| Hook closure control | `HookGeneration` counter invalidates stale hook closures without accumulating new ones (hooks are registered once per frame via `CPLight_HooksRegistered` guard) |
| NODE cache clearing | `InvalidateGraph()` calls `NODE.ClearCache()` to wipe the library's internal CACHE/RECTS tables |
| AceDB profiles | SavedVariables are schema-defaulted to prevent nil-chain errors |

### 6.4 Table Churn (Efficiency)

| Call site | Churn | Mitigation |
|---|---|---|
| `NavigateToBestCandidateV3` | Creates `{}` candidates table + vector tables per D-pad press | **Unavoidable** — inside external library. Lua 5.1 GC handles short-lived tables well. D-pad presses are human-rate (~10/sec max). |
| `GetCandidateVectorForCurrent` | Creates `{x, y, h, v, a, o}` table per navigation | Same as above — external library, low frequency. |
| `_CollectVisibleFrames` | Creates `activeFrames` + `frameNames` arrays on each rebuild check | Rebuild is debounced to at most once per 0.1s. Tables are small (~10-20 entries). |
| `_SetupSecureWidgets` | Creates closure per `trySetupWidget` call | Only runs on `EnableNavigation()` (infrequent — when frames open/close). |

### 6.5 Debouncing

| Mechanism | Location | Strategy |
|---|---|---|
| Graph rebuild | `RequestGraphRebuild()` | `C_Timer.After(0.1)` + `timerGeneration` counter. Multiple OnShow/OnHide events within 100ms collapse into one rebuild. Stale timer callbacks are discarded by comparing generation. |
| Bag content changes | `BAG_UPDATE_DELAYED` event | Blizzard's own debounced event (fires once after batch inventory changes). CPLight then calls `RefreshNavigation()`. |
| Button press dedup | `PreClick` with `down` check | Navigation only fires on button DOWN (`if down then`), preventing double-navigation on press+release. |
| Scroll repeat | `C_Timer.NewTicker(0.05)` | Continuous scroll while button held. Stopped on button UP + graph invalidated. |
| D-Pad binding | `isBackground=false` on PreClick | Only one direction processes at a time (Lua is single-threaded). |

---

## 7. Frame Registry & Addon Detection

### Registered Frames (FRAMES table in Hijack.lua)

The `FRAMES` array contains all frame names CPLight can navigate. Hooks are registered lazily — if a frame doesn't exist at startup, it's hooked the first time `_CollectVisibleFrames` finds it.

**Categories:** Player Info, Social/World, Interaction (Gossip, Quest, Merchant, Trainer, etc.), Inventory (ContainerFrame1–13), Management/Settings, Popups, Late-Loaded (TradeSkillFrame, InspectFrame).

### Third-Party Addon Support (ADDON_FRAMES)

```lua
ADDON_FRAMES = {
    Auctionator = { "AuctionFrameBid", "AuctionatorShoppingFrame", ... },
    Bagnon      = { "BagnonInventory1" },
    Baganator   = { "Baganator_CategoryViewBackpackViewFrameblizzard" },
}
```

Detection: `ADDON_LOADED` event (late arrivals) + `PLAYER_LOGIN` check (early birds via OptionalDeps).

---

## 8. Known Bugs

### BUG-001: ConsolePortNode nil `x` crash during navigation

**Status:** Mitigated (pcall guard in NavigateInDirection). Root cause in external library is unfixed.

**Error:**
```
Libs/ConsolePortNode/ConsolePortNode.lua:629: attempt to perform arithmetic on local 'x' (a nil value)
```

**Affected frames:** SettingsPanel, MerchantFrame, InterfaceOptionsFrame (frames with dynamic children).

**Root cause analysis:**

The crash occurs inside `GetCandidatesForVectorV2()` in ConsolePortNode.lua. Here is the exact failure path:

```
NavigateToBestCandidateV3(cur, key)
  └─ GetCandidatesForVectorV2(vector, comparator, candidates)
       │
       │  -- For the ORIGIN node:
       ├─ local x, y, w, h = GetHitRectScaled(node)     ← Can return nil
       ├─ GetOffsetPointInfo(w, h)                        ← CRASH if w,h are nil
       │
       │  -- For each CANDIDATE in CACHE:
       ├─ x, y, w, h = GetHitRectScaled(candidate)       ← Can return nil
       └─ destX, destY = x + div2(w), y + div2(h)        ← CRASH: x is nil
```

**Why `GetHitRectScaled` returns nil:**

```lua
function GetHitRectScaled(node)
    local x, y, w, h = GetRect(node)         -- GetRect returns nil for anchorless/hidden frames
    if issecretvalue(x) or not x then return end  -- Returns nil (no values)
    ...
end
```

**Critical context — `setfenv`:** ConsolePortNode uses `setfenv(1, GetFrameMetatable().__index)` to operate directly within the frame metatable's function environment. This means `GetRect`, `IsVisible`, `GetCenter`, etc. are called as bare functions (not methods). `GetRect(node)` returns nil when:
- The frame has no anchors set yet (freshly created child of a panel that's still layout-building)
- The frame is in the process of being hidden (anchor chain broken)
- The frame was removed from its parent (orphaned)

**Why the node is stale:** Between `NODE(...)` scanning (BuildGraph) and `NavigateToBestCandidateV3` being called (Navigate), frames like SettingsPanel dynamically show/hide child panels. A cached node may have been visible during the scan but lost its anchors by the time navigation occurs.

**Our mitigation (applied):**

In `NavigationGraph:NavigateInDirection()`, the call to `NODE.NavigateToBestCandidateV3` is now wrapped in `pcall`:

```lua
local ok, nextCacheItem, changed = pcall(NODE.NavigateToBestCandidateV3, currentCacheItem, direction)
if not ok then
    CPAPI.DebugLog('NODE navigation error (stale node): %s', tostring(nextCacheItem))
    return nil  -- Caller invalidates graph and triggers rebuild
end
```

The caller in `Hijack:Navigate()` already handles nil returns by invalidating the graph and calling `RequestGraphRebuild()`.

**Proper fix (requires library modification):**

Add nil guards inside `GetCandidatesForVectorV2` after each `GetHitRectScaled` call:

```lua
-- For origin node:
local x, y, w, h = GetHitRectScaled(node)
if not x then return candidates end  -- No valid origin, return empty

-- For each candidate:
x, y, w, h = GetHitRectScaled(candidate)
if x then  -- Only process candidates with valid geometry
    destX, destY = x + div2(w), y + div2(h)
    ...
end
```

### BUG-002: Planned Feature — Sell/Delete bag items with Y button (PAD4)

**Status:** Not implemented.

---

## 9. ConsolePortNode Deep Dive (For Debugging)

This section exists so any agent can trace bugs in the external library without re-reading 866 lines.

### Architecture

ConsolePortNode is a **LibStub library** (version 5). It uses a non-standard technique:

```lua
setfenv(1, GetFrameMetatable().__index)
```

This changes the global environment for ALL functions defined after this line to the frame metatable. This means:
- `GetRect(node)` ≡ `node:GetRect()`
- `IsVisible(node)` ≡ `node:IsVisible()`
- `GetChildren(node)` ≡ `node:GetChildren()`
- Standard Lua globals (`print`, `table`, etc.) are NOT available after this line — only frame API methods.
- Upvalued globals (`tinsert`, `tremove`, `pairs`, `ipairs`, `next`, `wipe`, `math.*`) are captured before `setfenv`.

### Function Reference (Key Functions)

| Function | Purpose |
|---|---|
| `NODE(...)` (\_\_call) | Entry point. `ClearCache()` → `Scan(nil, ...)` → `ScrubCache()` → return CACHE |
| `Scan(super, node, ...)` | Recursive. Tests `IsRelevant` → `IsDrawn` → `IsInteractive` → `CacheItem`. Recurses into children if `IsTree`. |
| `IsRelevant(node)` | Not forbidden, not anchor-restricted, is visible, not `nodeignore` |
| `IsDrawn(node, super)` | Center is within screen bounds. If super exists, checks `CheckClipping`. |
| `IsInteractive(node, object)` | Not ScrollFrame, is mouse-enabled, not `nodepass`, and is one of: Button/CheckButton/EditBox/Slider OR has OnEnter/OnMouseDown. |
| `CacheItem(node, obj, super, lvl)` | Inserts into CACHE (with priority) and RECTS. |
| `ScrubCache()` | Removes cached items that are occluded by higher-level RECTS. |
| `GetHitRectScaled(node)` | Returns `(x, y, w, h)` in UIParent-scaled coordinates. **Returns nil if `GetRect` returns nil.** |
| `GetCenterScaled(node)` | Returns `(x, y)` center in UIParent-scaled coordinates. **Returns nil if underlying GetRect is nil.** |
| `GetCandidatesForVectorV2(vector, cmp, candidates)` | Multi-point candidate selection. **THE crash site — no nil guard after GetHitRectScaled.** |
| `NavigateToBestCandidateV3(cur, key)` | Angle-weighted V2-style navigation with multi-point candidates. Used by CPLight. |
| `NavigateToArbitraryCandidate(cur, old, x, y)` | Fallback: returns first eligible node or closest to (x,y). |
| `GetScrollButtons(node)` | Walks up parent chain to find Slider for scroll buttons. |

### Node Attributes (Custom frame attributes)

| Attribute | Type | Effect |
|---|---|---|
| `nodeignore` | boolean | Skip this node entirely |
| `nodepriority` | number | Insert at this index in CACHE (higher = earlier) |
| `nodesingleton` | boolean | Don't recurse into children |
| `nodepass` | boolean | Skip this node but include its children |

### V3 Navigation Algorithm

1. Build origin vector from current node's scaled center position
2. Use `permissive` comparator (any node in correct direction qualifies)
3. For each candidate, generate multiple sample points along extreme-aspect-ratio edges
4. Compute angle between origin and each sample point
5. Weight distance by angle offset from optimal direction: `weight = 1 + (angleOffset / 15)`
6. Select candidate with smallest weighted Euclidean distance

---

## 10. Glossary

| Term | Definition |
|---|---|
| **Gauntlet** | The visual cursor (pointer/hand icon) that follows the focused node |
| **Node** | An interactive UI element (Button, CheckButton, EditBox, Slider) discovered by ConsolePortNode |
| **Graph** | The cached array of nodes + their spatial relationships |
| **Driver** | The secure state frame (`CPLightInputDriver`) that manages combat state and widget lifecycle |
| **Widget** | A `SecureActionButtonTemplate` frame bound to a controller button via `SetOverrideBindingClick` |
| **Super node** | A ScrollFrame or clip-children frame that acts as a clipping boundary for child nodes |
| **Cache item** | A table `{node, object, super, level}` stored in ConsolePortNode's CACHE array |
| **Taint** | WoW's security system. If insecure code touches a secure value, the value becomes "tainted" and protected actions using it will be blocked. |
| **Tank mode** | Combat movement: high strafe angle (180°), character doesn't turn toward movement direction |
| **Travel mode** | Out-of-combat movement: low strafe angle (45°), character turns freely |

---

## 11. Quick Reference for Common Tasks

### Adding a new navigable frame
1. Add the frame name string to the `FRAMES` table in Hijack.lua
2. If it's from a third-party addon, add to `ADDON_FRAMES` instead

### Adding a new controller binding
1. Create a widget via `Driver:GetWidget('BUTTON_ID', 'Owner')`
2. Call `SetOverrideBindingClick(widget, true, 'BUTTON_ID', widget:GetName(), mouseButton)`
3. Set up `PreClick`/`PostClick` handlers for insecure logic
4. Ensure modifier check: `if CVarManager:IsModifier(binding) then skip`

### Debugging navigation issues
1. Enable debug mode: `/run CPAPI.SetDebugMode(true)` and `/reload`
2. Check graph state: `/run local g = CPLightNavigationGraph:GetDebugInfo(); print(g.nodeCount, g.isDirty, g.age)`
3. Check cache stats: `/run local s = LibStub("AceAddon-3.0"):GetAddon("CPLight"):GetModule("Hijack").GraphCacheStats; print("Hits:", s.hits, "Misses:", s.misses)`

### Testing the pcall guard (BUG-001)
1. Open SettingsPanel and rapidly switch categories
2. If pcall catches: debug log shows `NODE navigation error (stale node): ...`
3. Graph auto-rebuilds on next D-pad press

---

*Document generated: 2026-02-15. Reflects codebase state with pcall mitigation applied.*
