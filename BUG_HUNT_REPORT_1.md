# CPLight Bug Hunt Report
**Investigation Date:** January 24, 2026  
**Target Build:** TBC Anniversary 2.5.5  
**Investigator:** AI Bug Hunter  

---

## Executive Summary

Investigation of 5 suspected bugs in the CPLight addon navigation system. This report provides detailed analysis, impact assessment, solution designs, and test cases for each bug.

**Key Findings:**
- Bug 1 (Unnecessary Graph Rebuilds): ✅ **ALREADY FIXED** - Smart caching implemented
- Bug 2 (Widget State Corruption): ⚠️ **PARTIALLY EXISTS** - Partial failure handling incomplete
- Bug 3 (Redundant NODE Calls): ☑️ **CONFIRMED** - UpdateGauntletPosition() doesn't use cache
- Bug 4 (Unvalidated Tooltip Ownership): ⚠️ **PARTIALLY EXISTS** - Limited owner validation
- Bug 5 (Duplicate Hook Registration): ✅ **ALREADY FIXED** - Guard flag present

---

## Bug 1: Unnecessary Graph Rebuilds (Performance Issue)

### Status
✅ **ALREADY FIXED** - Smart graph reuse mechanism implemented

### Location
**File:** [View/Hijack.lua](View/Hijack.lua)  
**Methods:** 
- `_CanReuseGraph()` (Lines 626-673)
- `EnableNavigation()` (Lines 831-890)
- `DisableNavigation()` (Lines 893-940)
- `RequestGraphRebuild()` (Lines 436-483)

### Code Analysis

#### Reuse Check Implementation (Lines 626-673)
```lua
function Hijack:_CanReuseGraph(currentFrameNames)
    -- Validate inputs
    if not currentFrameNames or #currentFrameNames == 0 then
        return false
    end
    
    -- Check if NavGraph is valid
    if not NavGraph or not NavGraph:IsValid() then
        return false
    end
    
    -- Check if we have previous state to compare against
    if not self.LastGraphState or not self.LastGraphState.frameNames or #self.LastGraphState.frameNames == 0 then
        return false
    end
    
    -- Compare frame counts first (fast check)
    if #currentFrameNames ~= #self.LastGraphState.frameNames then
        return false
    end
    
    -- Build lookup set from last build for O(n) comparison
    local lastFrameSet = {}
    for _, frameName in ipairs(self.LastGraphState.frameNames) do
        lastFrameSet[frameName] = true
    end
    
    -- Check if all current frames were in last build
    for _, frameName in ipairs(currentFrameNames) do
        if not lastFrameSet[frameName] then
            return false
        end
    end
    
    -- Verify node count hasn't changed (detects dynamic content changes)
    local currentNodeCount = NavGraph:GetNodeCount()
    if currentNodeCount ~= self.LastGraphState.nodeCount then
        return false
    end
    
    -- All checks passed: graph can be reused
    return true
end
```

#### Smart Rebuild Logic (Lines 860-870)
```lua
-- Step 2: Check if we can reuse existing graph (performance optimization)
local canReuseGraph = self:_CanReuseGraph(frameNames)

-- Step 3: Build/export graph only if needed
if not canReuseGraph then
    if not self:_BuildAndExportGraph(activeFrames, frameNames) then
        return
    end
else
    -- Log graph reuse for performance tracking
end
```

#### Graph Not Invalidated on Disable (Lines 933-940)
```lua
-- Note: Graph is NOT invalidated here to enable reuse on next enable
-- Graph will be invalidated only if:
--   1. Frame set changes (detected in _CanReuseGraph)
--   2. Node becomes invalid during navigation (_GetTargetNodeInDirection)
--   3. Current node becomes invisible (VisibilityChecker)
```

### Impact Assessment
**Severity:** N/A (Already Fixed)  
**Frequency:** N/A  
**User Impact:** Performance optimized - graph reuse prevents unnecessary rebuilds

### Root Cause Analysis
The suspected bug was based on the assumption that `DisableNavigation()` would invalidate the graph and `EnableNavigation()` would rebuild unconditionally. However, the actual implementation:

1. **Tracks graph state** via `LastGraphState` (frameNames, nodeCount)
2. **Compares before rebuilding** using `_CanReuseGraph()`
3. **Preserves graph** on disable to enable reuse
4. **Only rebuilds when necessary** (frame set changed or node count changed)

### Solution Design
✅ **ALREADY IMPLEMENTED** - The current implementation includes:
- Frame name tracking
- Node count tracking
- O(n) comparison using hash set
- Smart invalidation only when needed

### Test Cases

#### Test 1: Same Frame Reopen (Reuses Graph)
- **Setup:** CharacterFrame closed, no navigation active
- **Action:** 
  1. Open CharacterFrame → EnableNavigation() called
  2. Close CharacterFrame → DisableNavigation() called
  3. Immediately reopen CharacterFrame → EnableNavigation() called
- **Verify:** 
  - First enable: Graph built (logged)
  - Second enable: Graph reused (logged "Reusing existing graph")
  - Navigation works correctly both times

#### Test 2: Different Frame (Rebuilds)
- **Setup:** CharacterFrame open with active navigation
- **Action:**
  1. Close CharacterFrame → DisableNavigation()
  2. Open SpellBookFrame → EnableNavigation()
- **Verify:**
  - DisableNavigation: Graph NOT invalidated
  - EnableNavigation: `_CanReuseGraph()` returns false (different frames)
  - Graph rebuilt for SpellBookFrame

#### Test 3: Dynamic Content Change (Rebuilds)
- **Setup:** ContainerFrame1 open with 5 items (5 button nodes)
- **Action:**
  1. Add 20 items to bags (now 25 buttons)
  2. BAG_UPDATE event fires → RequestGraphRebuild()
- **Verify:**
  - Node count changed (5 → 25)
  - `_CanReuseGraph()` returns false
  - Graph rebuilt with new nodes

### Improvements Beyond Fix
The current implementation is solid, but could be enhanced:

1. **Cache Hit Metrics**: Track reuse rate for performance monitoring
   ```lua
   self.GraphCacheStats = {hits = 0, misses = 0}
   ```

2. **Timestamp Validation**: Check if graph is stale (>30 seconds old)
   ```lua
   local graphAge = GetTime() - self.LastGraphState.buildTime
   if graphAge > 30 then
       return false  -- Force rebuild for stale graphs
   end
   ```

3. **Partial Graph Updates**: For bag updates, only rebuild bag nodes
   ```lua
   if onlyBagsChanged then
       NavGraph:RebuildSubset(bagFrames)
   end
   ```

---

## Bug 2: Widget State Corruption on Enable Failure (Stability Issue)

### Status
⚠️ **PARTIALLY EXISTS** - EnableNavigation() has limited error recovery

### Location
**File:** [View/Hijack.lua](View/Hijack.lua)  
**Method:** `EnableNavigation()` (Lines 831-890)

### Code Snippet - Current Implementation
```lua
function Hijack:EnableNavigation()
    if InCombatLockdown() then
        return  -- ❌ Early return #1
    end
    
    if self.IsActive then
        return  -- ❌ Early return #2
    end
    
    -- Step 1: Collect visible frames
    local activeFrames, frameNames = self:_CollectVisibleFrames()
    if #activeFrames == 0 then
        return  -- ❌ Early return #3 - no cleanup needed (ok)
    end
    
    -- Step 2: Check if we can reuse existing graph
    local canReuseGraph = self:_CanReuseGraph(frameNames)
    
    -- Step 3: Build/export graph only if needed
    if not canReuseGraph then
        if not self:_BuildAndExportGraph(activeFrames, frameNames) then
            return  -- ❌ Early return #4 - no cleanup (ok, nothing set up yet)
        end
    end
    
    -- Step 4: Get first node to focus
    local firstIndex = NavGraph:GetFirstNodeIndex()
    if not firstIndex then
        return  -- ❌ Early return #5 - graph built but no nodes?
    end
    
    local firstNode = NavGraph:IndexToNode(firstIndex)
    if not firstNode then
        return  -- ❌ Early return #6 - index exists but node nil?
    end
    
    -- Step 5: Set up secure input widgets and bindings
    local widgets = self:_SetupSecureWidgets()
    if not widgets then
        return  -- ⚠️ Early return #7 - PROBLEM: Bindings might be partially set
    end
    
    -- Step 6: Set up navigation handlers
    self:_SetupNavigationHandlers(widgets)  -- ⚠️ No error check
    
    -- Step 7: Mark navigation as active AFTER all setup succeeds
    self.IsActive = true
    
    -- Step 8: Focus on first node
    self:SetFocus(firstNode)  -- ⚠️ No error check, but happens after IsActive = true
end
```

### Code Snippet - Widget Setup (Lines 716-772)
```lua
function Hijack:_SetupSecureWidgets()
    assert(not InCombatLockdown(), 'Cannot setup widgets during combat')

    local widgets = {}
    local widgetCount = 0
    
    -- Set up PAD1 (primary action)
    widgets.pad1 = Driver:GetWidget('PAD1', 'Hijack')
    if widgets.pad1 then
        SetOverrideBindingClick(widgets.pad1, true, 'PAD1', widgets.pad1:GetName(), 'LeftButton')
        widgetCount = widgetCount + 1
    else
        return nil  -- ⚠️ Returns nil if PAD1 fails, but what if PAD2/DPAD already set?
    end
    
    -- Set up PAD2 (right-click action)
    widgets.pad2 = Driver:GetWidget('PAD2', 'Hijack')
    if widgets.pad2 then
        SetOverrideBindingClick(widgets.pad2, true, 'PAD2', widgets.pad2:GetName(), 'RightButton')
        widgetCount = widgetCount + 1
    else
        return nil  -- ⚠️ Returns nil, PAD1 binding already set
    end
    
    -- Set up D-Pad navigation widgets (continues with similar pattern)
    -- ... more widget setup ...
    
    return widgets
end
```

### Impact Assessment
**Severity:** Medium  
**Frequency:** Rare (requires specific failure conditions)  
**User Impact:** 
- Bindings may remain active with no navigation state
- Pressing gamepad buttons might trigger incomplete actions
- Requires `/reload` or DisableNavigation() call to clean up
- Not a crash, but leaves addon in inconsistent state

### Root Cause Analysis

**The Issue:**
1. `_SetupSecureWidgets()` can fail mid-way through binding setup
2. If widget 1-3 succeed but widget 4 fails, function returns `nil`
3. Early return in `EnableNavigation()` leaves partial bindings active
4. `IsActive` flag never set, so `DisableNavigation()` won't auto-cleanup
5. Widgets remain in `Driver.Widgets` table with active bindings

**Failure Scenarios:**
- `GetWidget()` returns nil (rare, but possible)
- `SetOverrideBindingClick()` fails (combat starts mid-setup)
- `_SetupNavigationHandlers()` crashes (script error)
- `SetFocus()` fails but happens after `IsActive = true`

### Reproduction Steps

**Scenario 1: Widget Creation Failure**
1. Mock `Driver:GetWidget('PAD2', 'Hijack')` to return nil
2. Call `EnableNavigation()` with CharacterFrame visible
3. **Expected:** Clean state, no bindings
4. **Actual:** PAD1 binding active, IsActive = false, no cleanup

**Scenario 2: Combat During Setup**
1. Open CharacterFrame (navigation enables)
2. Inject combat state right after `_SetupSecureWidgets()` succeeds
3. `_SetupNavigationHandlers()` might fail due to taint
4. **Expected:** Rollback to safe state
5. **Actual:** IsActive = true, but handlers not set up

### Solution Design

#### Approach: Transaction-Style Setup with Rollback

**High-Level Strategy:**
1. Wrap entire setup in error handler (pcall)
2. Track each setup step that mutates state
3. On any failure, call cleanup function
4. Only set `IsActive = true` after ALL steps succeed
5. Log detailed error information for debugging

#### Pseudo-code
```lua
function Hijack:EnableNavigation()
    -- Pre-checks (no state mutation)
    if InCombatLockdown() then return false end
    if self.IsActive then return false end
    
    -- Collect frames and validate
    local activeFrames, frameNames = self:_CollectVisibleFrames()
    if #activeFrames == 0 then return false end
    
    -- Setup phase with error handling
    local success, errorMsg = pcall(function()
        -- Step 1: Build/export graph if needed
        local canReuseGraph = self:_CanReuseGraph(frameNames)
        if not canReuseGraph then
            local graphBuilt = self:_BuildAndExportGraph(activeFrames, frameNames)
            if not graphBuilt then
                error("Failed to build navigation graph")
            end
        end
        
        -- Step 2: Validate first node exists
        local firstIndex = NavGraph:GetFirstNodeIndex()
        if not firstIndex then
            error("Graph has no nodes")
        end
        
        local firstNode = NavGraph:IndexToNode(firstIndex)
        if not firstNode then
            error("First node index has no node reference")
        end
        
        -- Step 3: Set up widgets (atomic operation)
        local widgets = self:_SetupSecureWidgetsWithRollback()
        if not widgets then
            error("Widget setup failed")
        end
        
        -- Step 4: Set up handlers
        self:_SetupNavigationHandlers(widgets)
        
        -- Step 5: Mark as active (commit point)
        self.IsActive = true
        
        -- Step 6: Initial focus
        self:SetFocus(firstNode)
        
        return true
    end)
    
    if not success then
        -- Rollback on failure
        self:_RollbackEnableState()
        -- Log error
        print("|cFFFF0000CPLight EnableNavigation failed:|r", errorMsg)
        return false
    end
    
    return true
end

-- Helper: Setup widgets with partial cleanup
function Hijack:_SetupSecureWidgetsWithRollback()
    local widgets = {}
    local successfulBindings = {}
    
    -- Try to set up each widget, track successes
    local function trySetupWidget(id, binding, widgetTable)
        local widget = Driver:GetWidget(id, 'Hijack')
        if not widget then
            -- Cleanup on failure
            self:_ClearBindings(successfulBindings)
            return false
        end
        
        SetOverrideBindingClick(widget, true, binding, widget:GetName(), 'LeftButton')
        table.insert(successfulBindings, widget)
        widgetTable[id] = widget
        return true
    end
    
    -- Setup all widgets
    if not trySetupWidget('PAD1', 'PAD1', widgets) then return nil end
    if not trySetupWidget('PAD2', 'PAD2', widgets) then return nil end
    if not trySetupWidget('PADDUP', 'PADDUP', widgets) then return nil end
    if not trySetupWidget('PADDDOWN', 'PADDDOWN', widgets) then return nil end
    if not trySetupWidget('PADDLEFT', 'PADDLEFT', widgets) then return nil end
    if not trySetupWidget('PADDRIGHT', 'PADDRIGHT', widgets) then return nil end
    
    return widgets
end

-- Helper: Rollback partial enable state
function Hijack:_RollbackEnableState()
    -- Clear all bindings
    if Driver and Driver.Widgets then
        for id, widget in pairs(Driver.Widgets) do
            ClearOverrideBindings(widget)
        end
    end
    
    -- Release all widgets
    if Driver and Driver.ReleaseAll then
        Driver:ReleaseAll()
    end
    
    -- Ensure IsActive is false
    self.IsActive = false
    
    -- Clear current node
    self.CurrentNode = nil
    
    -- Hide visual elements
    if self.Gauntlet then
        self.Gauntlet:Hide()
    end
    
    -- Optionally invalidate graph if it was just built
    -- (prevents using potentially corrupt graph)
    if NavGraph then
        NavGraph:InvalidateGraph()
    end
end

-- Helper: Clear specific bindings
function Hijack:_ClearBindings(widgetList)
    for _, widget in ipairs(widgetList) do
        ClearOverrideBindings(widget)
    end
end
```

#### Implementation Steps
1. Add `_RollbackEnableState()` method to clean up partial state
2. Add `_ClearBindings()` helper for selective cleanup
3. Refactor `_SetupSecureWidgets()` to `_SetupSecureWidgetsWithRollback()`
4. Wrap `EnableNavigation()` main body in `pcall()`
5. Call rollback on any error
6. Add detailed error logging
7. Return success/failure boolean

### Test Cases

#### Test 1: Normal Enable (All Steps Succeed)
- **Setup:** CharacterFrame visible, no navigation active
- **Action:** Call `EnableNavigation()`
- **Verify:** 
  - Function returns `true`
  - `IsActive = true`
  - All bindings active
  - Gauntlet visible
  - No error logs

#### Test 2: Graph Build Failure (Early Failure)
- **Mock:** `NavGraph:BuildGraph()` returns false
- **Action:** Call `EnableNavigation()`
- **Verify:**
  - Function returns `false`
  - `IsActive = false`
  - No bindings set
  - Error logged
  - No widgets in memory

#### Test 3: Widget Setup Failure (Mid Failure)
- **Mock:** `Driver:GetWidget('PAD2')` returns nil
- **Action:** Call `EnableNavigation()`
- **Verify:**
  - Function returns `false`
  - `IsActive = false`
  - PAD1 binding cleared (rollback)
  - Error logged
  - Graph invalidated

#### Test 4: Handler Setup Failure (Late Failure)
- **Mock:** Inject error in `_SetupNavigationHandlers()`
- **Action:** Call `EnableNavigation()`
- **Verify:**
  - Function returns `false`
  - `IsActive = false`
  - All bindings cleared
  - All widgets released
  - Error logged with stack trace

#### Test 5: Combat Lockdown During Setup
- **Setup:** Open CharacterFrame
- **Action:** 
  1. Start `EnableNavigation()`
  2. Trigger combat after graph build but before widget setup
- **Verify:**
  - Function returns `false`
  - Partial state rolled back
  - No protected action violations
  - Navigation can retry after combat

### Edge Cases

#### Edge 1: Rapid Enable/Disable Calls
- **Scenario:** `EnableNavigation()` called twice rapidly
- **Handling:** 
  - First call checks `IsActive`, returns false if already active
  - Second call should not interfere
  - Add mutex/lock flag during setup

#### Edge 2: DisableNavigation During Enable
- **Scenario:** User closes UI while `EnableNavigation()` is in progress
- **Handling:**
  - Check `IsActive` at each step
  - Abort if disable was called
  - Rollback guarantees clean state

#### Edge 3: Lua Error in Node Code
- **Scenario:** `SetFocus()` triggers node's OnEnter script that errors
- **Handling:**
  - `SetFocus()` uses `pcall()` for OnEnter (already implemented)
  - Error caught, navigation still active
  - Node skipped, try next node

#### Edge 4: Memory Pressure
- **Scenario:** Low memory causes `CreateFrame()` to fail
- **Handling:**
  - GetWidget() returns nil
  - Rollback cleans up
  - Error logged with memory diagnostic

#### Edge 5: Graph Invalidation During Setup
- **Scenario:** Another module calls `NavGraph:InvalidateGraph()` during enable
- **Handling:**
  - `_CanReuseGraph()` returns false
  - Graph rebuilt
  - No corruption (graph is atomic)

### Alternative Solutions

#### Option A: Simple pcall Wrapper (Quick Fix)
- **Approach:** Wrap entire function in pcall, call DisableNavigation() on error
- **Pros:** 
  - Minimal code changes
  - Catches all errors
- **Cons:** 
  - Less granular error handling
  - DisableNavigation() might fail too
- **Recommendation:** ❌ Not Recommended (too coarse)

#### Option B: Transaction Pattern (Recommended)
- **Approach:** Track setup steps, rollback on failure
- **Pros:**
  - Precise cleanup
  - Clear error reporting
  - Testable
- **Cons:**
  - More complex implementation
  - Additional state tracking
- **Recommendation:** ⭐ **Recommended**

#### Option C: State Machine with Rollback Handlers
- **Approach:** States: Idle → GraphBuilding → WidgetSetup → Active
- **Pros:**
  - Very robust
  - Each state has enter/exit/rollback
  - Easy to add new states
- **Cons:**
  - Significant complexity
  - Over-engineered for this use case
- **Recommendation:** ❌ Not Recommended (overkill)

#### Option D: Optimistic Enable, Lazy Cleanup
- **Approach:** Set state immediately, validate on first use
- **Pros:**
  - Fast enable
  - Defers validation
- **Cons:**
  - Can navigate with broken state
  - Error surfaces later
- **Recommendation:** ❌ Not Recommended (unsafe)

### Improvements Beyond Fix

1. **Enable Result Callback**
   ```lua
   Hijack:RegisterCallback('EnableFailed', function(reason)
       print("Navigation enable failed:", reason)
   end)
   ```

2. **Health Check Method**
   ```lua
   function Hijack:HealthCheck()
       return {
           isActive = self.IsActive,
           graphValid = NavGraph:IsValid(),
           widgetCount = self:CountActiveWidgets(),
           bindingCount = self:CountActiveBindings(),
       }
   end
   ```

3. **Auto-Recovery on Next Frame**
   ```lua
   -- If enable failed, auto-retry on next frame visibility
   if lastEnableFailed and frameOpened then
       C_Timer.After(0.5, function()
           Hijack:EnableNavigation()
       end)
   end
   ```

---

## Bug 3: Redundant NODE Library Calls (Performance Issue)

### Status
☑️ **CONFIRMED** - UpdateGauntletPosition() always calls NODE.GetCenterScaled()

### Location
**File:** [View/Hijack.lua](View/Hijack.lua)  
**Method:** `UpdateGauntletPosition()` (Lines 389-399)

### Code Snippet - Current Implementation
```lua
function Hijack:UpdateGauntletPosition(node)
    if not self.Gauntlet or not node then return end
    
    -- ❌ PROBLEM: Calls NODE.GetCenterScaled() every time
    local x, y = NODE.GetCenterScaled(node)
    if not x or not y then return end
    
    self.Gauntlet:ClearAllPoints()
    -- Position using scaled coordinates from NODE library
    -- Offset to center the pointer finger (top-left of texture) on the node center
    self.Gauntlet:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x - 8, y + 8)
    self.Gauntlet:Show()
end
```

### Code Snippet - Cached Positions Available
**File:** [View/NavigationGraph.lua](View/NavigationGraph.lua)  
**Lines:** 154-168, 360-366

```lua
-- Navigation graph ALREADY CACHES positions during build:
function NavigationGraph:_BuildNodeArray(cache)
    -- ... validation ...
    for index, cacheItem in ipairs(cache) do
        local node = cacheItem.node
        -- Get node position FROM NODE LIBRARY
        local x, y = NODE.GetCenterScaled(node)  -- ✅ Called once during build
        
        -- STORE IN GRAPH
        graph.nodes[index] = {
            node = node,
            x = x,      -- ✅ Cached!
            y = y,      -- ✅ Cached!
            super = cacheItem.super,
        }
    end
end

-- Public API to retrieve cached positions:
function NavigationGraph:GetNodePosition(index)
    if graph.nodes[index] then
        return graph.nodes[index].x, graph.nodes[index].y  -- ✅ Returns cached!
    end
    return nil, nil
end
```

### Impact Assessment
**Severity:** Low to Medium  
**Frequency:** Always (every gauntlet update = every navigation)  
**User Impact:** 
- Minor performance hit per navigation
- `NODE.GetCenterScaled()` likely does frame calculations, scale adjustments
- Called on every D-pad press when navigating
- Not a major bottleneck, but unnecessary work

**Performance Analysis:**
- **Current:** NODE.GetCenterScaled() call per navigation (~1-5ms estimated)
- **Optimized:** Simple table lookup (~0.01ms estimated)
- **Improvement:** ~99% faster lookup (but absolute time is small)
- **User Perception:** Not noticeable for single navigation, but matters for rapid navigation

### Root Cause Analysis

**Why This Exists:**
1. `UpdateGauntletPosition()` was likely written before graph caching
2. NODE library provides convenient `GetCenterScaled()` method
3. Developer didn't realize positions were already cached
4. No performance testing caught this

**Why It's a Problem:**
1. Repeats work already done during graph build
2. NODE.GetCenterScaled() might do expensive calculations:
   - Get effective scale
   - Get frame absolute position
   - Calculate center point
   - Apply scale adjustments
3. Called frequently (every navigation action)
4. Cache exists but isn't used

### Reproduction Steps

**Test Setup:**
1. Enable navigation on CharacterFrame
2. Navigate between 10 buttons rapidly (press D-pad up/down repeatedly)
3. Profile NODE.GetCenterScaled() call count

**Expected Results:**
- **Before Fix:** NODE.GetCenterScaled() called 10 times (once per navigation)
- **After Fix:** NODE.GetCenterScaled() called 0 times (uses cache)

**Measurement:**
```lua
-- Add timing wrapper:
local nodeCallCount = 0
local originalGetCenter = NODE.GetCenterScaled
NODE.GetCenterScaled = function(...)
    nodeCallCount = nodeCallCount + 1
    return originalGetCenter(...)
end

-- After 10 navigations:
print("NODE.GetCenterScaled calls:", nodeCallCount)  -- Should be 0 after fix
```

### Solution Design

#### Approach: Use Cached Positions from NavigationGraph

**High-Level Strategy:**
1. Get node index from `NavGraph:NodeToIndex(node)`
2. Get cached position from `NavGraph:GetNodePosition(index)`
3. Use cached x/y for gauntlet positioning
4. Fallback to NODE library if node not in graph (safety)

#### Pseudo-code
```lua
function Hijack:UpdateGauntletPosition(node)
    if not self.Gauntlet or not node then
        return
    end
    
    -- Get node index from navigation graph
    local nodeIndex = NavGraph and NavGraph:NodeToIndex(node)
    
    local x, y
    if nodeIndex then
        -- ✅ Use cached position from graph (FAST)
        x, y = NavGraph:GetNodePosition(nodeIndex)
    end
    
    -- Fallback to NODE library if not in graph
    if not x or not y then
        -- ⚠️ This should rarely happen in normal operation
        x, y = NODE.GetCenterScaled(node)
    end
    
    -- Validate position
    if not x or not y then
        return
    end
    
    -- Position gauntlet
    self.Gauntlet:ClearAllPoints()
    self.Gauntlet:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x - 8, y + 8)
    self.Gauntlet:Show()
end
```

#### Implementation Steps
1. Modify `UpdateGauntletPosition()` to call `NavGraph:NodeToIndex(node)`
2. If index exists, call `NavGraph:GetNodePosition(index)`
3. Keep fallback to `NODE.GetCenterScaled()` for safety
4. Add debug logging when fallback is used (indicates potential issue)
5. Test navigation still works correctly
6. Profile to confirm NODE calls eliminated

### Test Cases

#### Test 1: Normal Navigation (Uses Cache)
- **Setup:** CharacterFrame open, navigation active
- **Action:** Navigate to first button, then second button
- **Verify:**
  - Gauntlet positioned correctly on both buttons
  - `NavGraph:GetNodePosition()` called (can add debug log)
  - `NODE.GetCenterScaled()` NOT called
  - Positions match cached graph values

#### Test 2: Node in Graph (Performance)
- **Setup:** Navigation active with 20 buttons
- **Action:** Rapidly navigate through all 20 buttons
- **Verify:**
  - All positions correct
  - No NODE library calls
  - Smooth visual feedback
  - Timing: <0.1ms per update

#### Test 3: Node Not in Graph (Fallback)
- **Setup:** Mock scenario where node exists but not in graph
- **Action:** 
  1. Create temporary button not in ALLOWED_FRAMES
  2. Call `UpdateGauntletPosition(tempButton)`
- **Verify:**
  - `NodeToIndex()` returns nil
  - Falls back to `NODE.GetCenterScaled()`
  - Gauntlet still positions correctly
  - Debug warning logged

#### Test 4: Graph Invalidated Mid-Navigation
- **Setup:** Navigation active
- **Action:**
  1. Navigate to button A
  2. Invalidate graph (mock: `NavGraph:InvalidateGraph()`)
  3. Navigate to button B
- **Verify:**
  - First navigation uses cache
  - After invalidation, fallback used OR graph rebuilt
  - No errors, smooth degradation

### Edge Cases

#### Edge 1: NavGraph is nil
- **Scenario:** NavigationGraph module failed to load
- **Handling:** Fallback to NODE.GetCenterScaled() always
- **Result:** Graceful degradation, no crash

#### Edge 2: Node Index Lookup Fails
- **Scenario:** Node exists but `NodeToIndex()` returns nil
- **Handling:** Use NODE fallback
- **Result:** Position still correct, slight performance hit

#### Edge 3: Cached Position Outdated
- **Scenario:** Frame moved after graph build (animated frame)
- **Handling:** 
  - Cache still used (minor offset acceptable)
  - Or: Detect movement, recache position
- **Decision:** Accept minor offset (simpler)

#### Edge 4: UI Scale Changed
- **Scenario:** User changes UI scale mid-session
- **Handling:**
  - Graph invalidated on scale change (separate issue)
  - New graph built with new scale
  - Cached positions correct for new scale

#### Edge 5: Node Position is (0, 0)
- **Scenario:** NODE returns valid (0, 0) position (top-left corner)
- **Handling:**
  - Don't treat as invalid
  - Check explicitly for nil, not falsy
- **Code:** `if not x or not y then` → `if x == nil or y == nil then`

### Alternative Solutions

#### Option A: Always Use Cached (Recommended)
- **Approach:** NodeToIndex → GetNodePosition → SetPoint, NODE fallback
- **Pros:** 
  - Fastest possible
  - Simple implementation
  - Uses existing cache
- **Cons:** 
  - Doesn't handle dynamic frames (acceptable)
- **Recommendation:** ⭐ **Recommended**

#### Option B: Cache with Movement Detection
- **Approach:** Compare cached vs current, recache if moved
- **Pros:** 
  - Handles animated frames
  - Still uses cache most of time
- **Cons:**
  - Adds comparison overhead
  - Complexity for rare edge case
- **Recommendation:** ❌ Not Recommended (over-engineering)

#### Option C: Lazy Per-Session Cache
- **Approach:** Cache first NODE call result, reuse for session
- **Pros:**
  - Doesn't depend on NavGraph
  - Simple local cache
- **Cons:**
  - Duplicates NavGraph's work
  - Doesn't detect frame changes
- **Recommendation:** ❌ Not Recommended (redundant)

#### Option D: Hybrid (Cache Primary, Refresh Timer)
- **Approach:** Use cache, refresh every 5 seconds from NODE
- **Pros:**
  - Handles slowly moving frames
  - Still mostly cached
- **Cons:**
  - Arbitrary refresh interval
  - Additional timer overhead
- **Recommendation:** ❌ Not Recommended (complexity)

### Improvements Beyond Fix

1. **Profile NODE Library Calls**
   ```lua
   -- Add diagnostic to track NODE usage
   function Hijack:GetNODECallStats()
       return {
           cacheHits = self.gauntletCacheHits or 0,
           cacheMisses = self.gauntletCacheMisses or 0,
           fallbackCount = self.gauntletFallbackCount or 0,
       }
   end
   ```

2. **Validate Cache Accuracy**
   ```lua
   -- Debug mode: Compare cached vs NODE result
   if DEBUG_MODE then
       local cachedX, cachedY = NavGraph:GetNodePosition(index)
       local nodeX, nodeY = NODE.GetCenterScaled(node)
       local diff = math.abs(cachedX - nodeX) + math.abs(cachedY - nodeY)
       if diff > 5 then
           print("WARNING: Cached position differs by", diff)
       end
   end
   ```

3. **Batch Position Updates**
   ```lua
   -- If updating multiple gauntlets/cursors, batch lookup
   function NavGraph:GetNodePositions(indices)
       local positions = {}
       for _, index in ipairs(indices) do
           positions[index] = {self:GetNodePosition(index)}
       end
       return positions
   end
   ```

---

## Bug 4: Unvalidated Tooltip Ownership (UX Issue)

### Status
⚠️ **PARTIALLY EXISTS** - Limited tooltip owner validation in DisableNavigation()

### Location
**File:** [View/Hijack.lua](View/Hijack.lua)  
**Methods:**
- `DisableNavigation()` (Lines 919-926) - Has PARTIAL validation
- `_UpdateVisualFeedback()` (Lines 318-328) - No validation

### Code Snippet - Disable Navigation (Lines 919-926)
```lua
-- Hide tooltip (improved cleanup)
if GameTooltip:IsShown() then
    -- ✅ PARTIAL VALIDATION: Checks CurrentNode and UIParent
    if not self.CurrentNode or GameTooltip:GetOwner() == self.CurrentNode or GameTooltip:IsOwned(UIParent) then
        GameTooltip:Hide()
    end
    -- ⚠️ PROBLEM: What if tooltip owner is something else?
end
```

### Code Snippet - Update Visual Feedback (Lines 318-328)
```lua
function Hijack:_UpdateVisualFeedback(node)
    -- Update gauntlet visual
    self:UpdateGauntletPosition(node)
    
    -- Hide previous tooltip before showing new one (memory leak fix)
    if GameTooltip:IsShown() then
        GameTooltip:Hide()  -- ❌ PROBLEM: No owner validation!
    end
    
    -- Show tooltip
    self:ShowNodeTooltip(node)
end
```

### Impact Assessment
**Severity:** Low to Medium  
**Frequency:** Rare (requires tooltip from another source during navigation)  
**User Impact:**
- Navigation hides tooltips from other addons
- User hovers item in bag, tooltip disappears when navigating
- Hovering spell in spellbook, tooltip hidden by D-pad press
- UX annoyance, not a critical bug

**User Scenarios:**
1. User hovers item in bag → Item tooltip shows
2. User presses D-pad → `_UpdateVisualFeedback()` hides tooltip unconditionally
3. Item tooltip disappears (bad UX)

### Root Cause Analysis

**Why This Exists:**
1. `_UpdateVisualFeedback()` called on every navigation
2. Always hides GameTooltip to "clean up" before showing new tooltip
3. No check if the tooltip belongs to navigation system
4. Assumption: GameTooltip is only used by navigation

**Why It's a Problem:**
1. GameTooltip is shared across entire UI and all addons
2. Other systems can show tooltips:
   - Item hover (bags, equipped items)
   - Spell hover (spellbook, action bars)
   - Talent hover
   - Other addon tooltips
3. Navigation shouldn't interfere with external tooltips
4. `GetOwner()` API available to check ownership

**Inconsistency:**
- `DisableNavigation()` DOES check owner (partial validation)
- `_UpdateVisualFeedback()` DOES NOT check owner
- Should be consistent

### Reproduction Steps

#### Scenario 1: Item Tooltip Hidden During Navigation
1. Open bags (ContainerFrame1)
2. Hover mouse over an item → Item tooltip appears
3. Press D-pad to navigate → `_UpdateVisualFeedback()` called
4. **Expected:** Item tooltip remains visible
5. **Actual:** Item tooltip hidden (Bug!)

#### Scenario 2: Spell Tooltip Hidden
1. Open SpellBookFrame
2. Hover mouse over spell icon → Spell tooltip appears
3. Navigate with D-pad
4. **Expected:** Spell tooltip remains (or shows nav tooltip)
5. **Actual:** Spell tooltip hidden immediately

#### Scenario 3: Own Tooltip Replaced (Correct Behavior)
1. Navigate to button A → Navigation tooltip shows
2. Navigate to button B → Previous tooltip hidden, new shown
3. **Expected:** Smooth transition between nav tooltips
4. **Actual:** ✅ Works correctly (this should keep working)

### Solution Design

#### Approach: Whitelist-Based Owner Validation

**High-Level Strategy:**
1. Before hiding tooltip, check `GameTooltip:GetOwner()`
2. Only hide if owner is:
   - `self.CurrentNode` (previous nav node)
   - `UIParent` (common ownership)
   - `nil` (no owner = safe to hide)
3. Do NOT hide if owner is something else
4. Apply consistently in both DisableNavigation() and _UpdateVisualFeedback()

#### Pseudo-code
```lua
-- Helper method for consistent tooltip ownership check
function Hijack:_CanHideTooltip()
    if not GameTooltip:IsShown() then
        return false  -- Already hidden
    end
    
    local owner = GameTooltip:GetOwner()
    
    -- Whitelist: Only hide if owner is one of these
    if owner == nil then
        return true  -- No owner = safe to hide
    end
    
    if owner == UIParent then
        return true  -- Generic owner = safe to hide
    end
    
    if self.CurrentNode and owner == self.CurrentNode then
        return true  -- Our previous node = safe to hide
    end
    
    -- Owner is something else (item, spell, another addon)
    return false  -- DON'T hide external tooltips
end

-- Updated _UpdateVisualFeedback with validation
function Hijack:_UpdateVisualFeedback(node)
    -- Update gauntlet visual
    self:UpdateGauntletPosition(node)
    
    -- ✅ FIXED: Check ownership before hiding
    if self:_CanHideTooltip() then
        GameTooltip:Hide()
    end
    
    -- Show new tooltip
    self:ShowNodeTooltip(node)
end

-- Updated DisableNavigation with consistent logic
function Hijack:DisableNavigation()
    -- ... other cleanup ...
    
    -- ✅ FIXED: Use consistent helper
    if self:_CanHideTooltip() then
        GameTooltip:Hide()
    end
    
    -- Clear state
    self.CurrentNode = nil
end
```

#### Implementation Steps
1. Add `_CanHideTooltip()` helper method with whitelist logic
2. Update `_UpdateVisualFeedback()` to call helper before hiding
3. Update `DisableNavigation()` to use same helper
4. Add debug logging when refusing to hide tooltip (DEBUG_MODE)
5. Test with item tooltips, spell tooltips, addon tooltips
6. Consider ItemRefTooltip and other tooltip frames (future)

### Test Cases

#### Test 1: Own Tooltip (Should Hide)
- **Setup:** Navigation active on CharacterFrame
- **Action:**
  1. Navigate to button A (nav tooltip shows)
  2. Navigate to button B
- **Verify:**
  - Button A tooltip hidden
  - Button B tooltip shown
  - Smooth transition

#### Test 2: Item Tooltip (Should NOT Hide)
- **Setup:** Bags open with navigation active
- **Action:**
  1. Hover mouse over item (item tooltip shows)
  2. Owner = bag button (not CurrentNode, not UIParent)
  3. Press D-pad to navigate
- **Verify:**
  - Item tooltip remains visible
  - Navigation tooltip may show alongside (or not, depending on design)
  - Item tooltip NOT hidden by navigation

#### Test 3: Spell Tooltip (Should NOT Hide)
- **Setup:** SpellBookFrame open with navigation
- **Action:**
  1. Hover spell icon (spell tooltip shows)
  2. Navigate with D-pad
- **Verify:**
  - Spell tooltip not hidden
  - Navigation works
  - No tooltip flicker

#### Test 4: No Owner Tooltip (Should Hide)
- **Setup:** Navigation active
- **Action:**
  1. Manually create tooltip with no owner:
     ```lua
     GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
     GameTooltip:SetText("Test")
     GameTooltip:Show()
     ```
  2. Navigate
- **Verify:**
  - Orphaned tooltip hidden (safe default)
  - Navigation tooltip shows

#### Test 5: UIParent Owner (Should Hide)
- **Setup:** Tooltip owned by UIParent
- **Action:** Navigate
- **Verify:**
  - Tooltip hidden (common generic ownership)
  - Navigation tooltip shows

#### Test 6: Rapid Navigation (No Flicker)
- **Setup:** Navigate rapidly through 5 buttons
- **Action:** Press D-pad up/down repeatedly
- **Verify:**
  - Tooltips transition smoothly
  - No orphaned tooltips
  - No visible flicker

### Edge Cases

#### Edge 1: ItemRefTooltip (Chat Links)
- **Scenario:** User clicks item link in chat → ItemRefTooltip shows
- **Handling:** 
  - Currently solution only checks GameTooltip
  - ItemRefTooltip is separate frame
  - Should extend solution to ItemRefTooltip
- **Future Enhancement:**
  ```lua
  function Hijack:_CanHideTooltip(tooltipFrame)
      tooltipFrame = tooltipFrame or GameTooltip
      -- Same logic for any tooltip frame
  end
  ```

#### Edge 2: Owner Frame Becomes Invalid
- **Scenario:** Tooltip owner is button that gets hidden/deleted
- **Handling:**
  - `GetOwner()` returns invalid frame reference
  - Check `owner:IsVisible()` before comparing
  - If owner invalid, safe to hide
- **Code:**
  ```lua
  if owner and owner.IsVisible and not owner:IsVisible() then
      return true  -- Owner gone, safe to hide
  end
  ```

#### Edge 3: Multiple Overlapping Tooltips
- **Scenario:** GameTooltip and ItemRefTooltip both shown
- **Handling:**
  - Check each independently
  - Don't assume only one tooltip active
  - Solution handles this (per-tooltip check)

#### Edge 4: Addon Custom Tooltips
- **Scenario:** Another addon uses GameTooltip with custom owner
- **Handling:**
  - Whitelist approach: won't hide unless owner matches
  - Conservative and safe
  - Addon's tooltip protected

#### Edge 5: Tooltip Owner is Target Node
- **Scenario:** Navigate to button, button already has tooltip from mouse hover
- **Handling:**
  - Owner = target node (button we're navigating TO)
  - Should we hide and replace? Or keep?
  - **Decision:** Hide and replace (user navigated to it, show our tooltip)
- **Code:**
  ```lua
  if owner == node then
      return true  -- Target node = replace with our tooltip
  end
  ```

### Alternative Solutions

#### Option A: Owner Whitelist (Recommended)
- **Approach:** Only hide if owner in whitelist [CurrentNode, UIParent, nil, targetNode]
- **Pros:**
  - Conservative and safe
  - Protects external tooltips
  - Easy to extend whitelist
- **Cons:**
  - Might leave orphaned tooltips in rare cases
- **Recommendation:** ⭐ **Recommended**

#### Option B: Owner Blacklist
- **Approach:** Hide unless owner is known external frame
- **Pros:**
  - More aggressive cleanup
  - Fewer orphaned tooltips
- **Cons:**
  - Hard to maintain blacklist
  - Risk of hiding wrong tooltip
  - Requires knowledge of all possible owners
- **Recommendation:** ❌ Not Recommended

#### Option C: Track Our Tooltips Explicitly
- **Approach:** Set flag when we show tooltip, only hide if flag set
- **Pros:**
  - Precise ownership tracking
  - No false positives
- **Cons:**
  - More state management
  - Flag could get out of sync
- **Recommendation:** ❌ Not Recommended (complexity)

#### Option D: Never Hide Tooltips
- **Approach:** Let tooltips stay visible, only show ours alongside
- **Pros:**
  - Zero risk of hiding wrong tooltip
  - Simplest implementation
- **Cons:**
  - Multiple tooltips overlap (bad UX)
  - Our tooltip might be invisible behind others
- **Recommendation:** ❌ Not Recommended (poor UX)

### Improvements Beyond Fix

1. **Support ItemRefTooltip**
   ```lua
   function Hijack:_HideOwnedTooltips()
       for _, tooltipFrame in ipairs({GameTooltip, ItemRefTooltip}) do
           if self:_CanHideTooltip(tooltipFrame) then
               tooltipFrame:Hide()
           end
       end
   end
   ```

2. **Debug Tooltip Ownership**
   ```lua
   function Hijack:_DebugTooltipOwner()
       if DEBUG_MODE and GameTooltip:IsShown() then
           local owner = GameTooltip:GetOwner()
           local ownerName = owner and owner:GetName() or "nil"
           print("Tooltip owner:", ownerName)
       end
   end
   ```

3. **Smart Tooltip Positioning**
   ```lua
   -- If external tooltip visible, position ours differently to avoid overlap
   function Hijack:_GetTooltipAnchor()
       if GameTooltip:IsShown() and not self:_CanHideTooltip() then
           return "ANCHOR_LEFT"  -- Show on opposite side
       else
           return "ANCHOR_RIGHT"  -- Default
       end
   end
   ```

---

## Bug 5: Duplicate Hook Registration (Memory Leak)

### Status
✅ **ALREADY FIXED** - Guard flag `hooksRegistered` prevents duplicates

### Location
**File:** [View/Hijack.lua](View/Hijack.lua)  
**Method:** `_RegisterVisibilityHooks()` (Lines 486-510)

### Code Snippet - Guard Flag Implementation
```lua
function Hijack:_RegisterVisibilityHooks()
    -- ✅ GUARD FLAG: Prevents duplicate registration
    if self.RebuildState.hooksRegistered then
        return  -- Early exit if already registered
    end
    
    -- Log registration attempt
    
    local hooksRegistered = 0
    for _, frameName in ipairs(ALLOWED_FRAMES) do
        local frame = _G[frameName]
        if frame then
            -- Use HookScript to avoid overwriting existing handlers
            frame:HookScript('OnShow', function()
                if not InCombatLockdown() then
                    RequestGraphRebuild()
                end
            end)
            
            frame:HookScript('OnHide', function()
                if not InCombatLockdown() then
                    RequestGraphRebuild()
                end
            end)
            
            hooksRegistered = hooksRegistered + 1
        end
    end
    
    -- ✅ SET FLAG: Mark hooks as registered
    self.RebuildState.hooksRegistered = true
    -- Log completion
end
```

### Code Snippet - Initialization (Lines 957-969)
```lua
function Hijack:OnEnable()
    self:CreateGauntlet()
    
    -- Register event-driven visibility detection
    self:_RegisterVisibilityHooks()  -- Called once on enable
    self:_RegisterLateLoadedFrameHooks()
    self:_RegisterGameEvents()
    
    -- Check if any frames are already open
    self:_CheckInitialVisibility()
    
    -- Start fallback polling (safety net)
    VisibilityChecker:Show()
end
```

### Impact Assessment
**Severity:** N/A (Already Fixed)  
**Frequency:** N/A  
**User Impact:** No memory leak - hooks registered once per addon lifecycle

### Root Cause Analysis

The suspected bug was based on the assumption that:
1. `RegisterVisibilityHooks()` would be called multiple times
2. Each call would create duplicate `HookScript()` registrations
3. Memory would leak with multiple hook callbacks

**However, the actual implementation:**
1. ✅ Checks `self.RebuildState.hooksRegistered` flag at start
2. ✅ Returns early if flag is `true`
3. ✅ Sets flag to `true` after successful registration
4. ✅ Only called once from `OnEnable()`
5. ✅ Uses `HookScript()` which is safe for multiple calls anyway

**HookScript Behavior:**
Even without the flag, `HookScript()` is designed to ADD handlers, not replace them. Multiple HookScript calls would add multiple callbacks, but this is by design and not a "leak" in the traditional sense. The flag prevents unnecessary duplicate callbacks.

### Solution Design
✅ **ALREADY IMPLEMENTED** - Current implementation is correct and complete:
- Guard flag prevents duplicate registration
- Called once per addon lifecycle
- Flag reset on `OnDisable()` (line 976)

### Test Cases

#### Test 1: Normal Registration (First Call)
- **Setup:** Addon loading, OnEnable() called
- **Action:** `_RegisterVisibilityHooks()` called
- **Verify:**
  - Flag starts as `false`
  - Hooks registered
  - Flag set to `true`
  - Log shows "Registering visibility hooks"

#### Test 2: Duplicate Prevention (Second Call)
- **Setup:** Hooks already registered from Test 1
- **Action:** Call `_RegisterVisibilityHooks()` manually again
- **Verify:**
  - Early return due to flag
  - No hooks registered
  - No errors
  - Log shows nothing (early exit)

#### Test 3: OnEnable Called Once
- **Setup:** Fresh addon load
- **Action:** Observe OnEnable() behavior
- **Verify:**
  - `_RegisterVisibilityHooks()` called once
  - All subsequent enables skip hook registration
  - Flag remains true

#### Test 4: /reload ui (Reset)
- **Setup:** Addon active with hooks registered
- **Action:** `/reload ui` command
- **Verify:**
  - Lua state cleared
  - OnEnable() called again
  - Flag starts false (new Lua state)
  - Hooks re-registered
  - No duplicates (old hooks gone with old state)

#### Test 5: OnDisable and Re-Enable
- **Setup:** Addon active
- **Action:**
  1. Call `OnDisable()` (line 976: `self.RebuildState.hooksRegistered = false`)
  2. Call `OnEnable()` again
- **Verify:**
  - Flag reset to `false` on disable
  - Hooks can be re-registered on enable
  - No memory leak

### Edge Cases

#### Edge 1: Frame Doesn't Exist at Registration
- **Scenario:** Frame in ALLOWED_FRAMES but not created yet
- **Handling:**
  - Loop skips frame (if frame then)
  - Flag still set to true
  - Late-loaded frames handled by `_RegisterLateLoadedFrameHooks()`
- **Result:** No issue, late frames covered

#### Edge 2: Manual Flag Reset
- **Scenario:** Code manually sets `hooksRegistered = false`
- **Handling:**
  - Next call will re-register hooks
  - HookScript adds callbacks (doesn't replace)
  - Could result in double callbacks
- **Mitigation:** Don't manually reset flag except in OnDisable()

#### Edge 3: Multiple Addon Instances (Impossible in WoW)
- **Scenario:** Two CPLight instances loaded
- **Handling:** 
  - Not possible in WoW addon system
  - Each addon loads once
  - No cross-instance concerns

#### Edge 4: HookScript Failure
- **Scenario:** frame:HookScript() fails (protected frame)
- **Handling:**
  - Flag not set until end of function
  - If error occurs, flag remains false
  - Next call will retry
- **Improvement:** Could wrap in pcall and set flag per-frame

#### Edge 5: Late-Loaded Frame Hooks
- **Scenario:** Blizzard_TalentUI loads mid-session
- **Handling:**
  - Separate `_RegisterLateLoadedFrameHooks()` handles these
  - Uses ADDON_LOADED event
  - Also has unregister logic to prevent memory leak
  - Well implemented (lines 513-548)

### Alternative Solutions

The current implementation is optimal. No alternative needed.

**If the bug existed, alternatives would be:**

#### Option A: Simple Boolean Flag (Current Implementation)
- ⭐ **Recommended** - Already implemented

#### Option B: Hook Table Tracking
- **Approach:** Track which frames have hooks in table
- **Pros:** Can unhook later, per-frame control
- **Cons:** More complexity
- **Not Needed:** Current solution sufficient

#### Option C: Once-Per-Session Global
- **Approach:** Use _G.CPLightHooksRegistered
- **Pros:** Persists across OnEnable/OnDisable cycles
- **Cons:** Can't re-register if needed
- **Not Needed:** Instance flag works fine

### Improvements Beyond Fix

The current implementation is complete, but minor enhancements:

1. **Per-Frame Hook Tracking (Overkill)**
   ```lua
   self.RegisteredHooks = {}
   for _, frameName in ipairs(ALLOWED_FRAMES) do
       if not self.RegisteredHooks[frameName] then
           -- Register and track
           self.RegisteredHooks[frameName] = true
       end
   end
   ```

2. **Hook Registration Metrics**
   ```lua
   function Hijack:GetHookStats()
       return {
           registered = self.RebuildState.hooksRegistered,
           count = self.RebuildState.hookCount or 0,
           lateLoadedCount = #lateLoadedAddons,
       }
   end
   ```

3. **Unhook on Disable (Not Necessary)**
   ```lua
   -- WoW doesn't provide Unhook API
   -- HookScript hooks persist until frame destroyed
   -- Flag prevents duplicate registration, which is sufficient
   ```

---

## Summary Table

| Bug | Status | Severity | Recommended Action |
|-----|--------|----------|-------------------|
| 1: Unnecessary Graph Rebuilds | ✅ Fixed | N/A | None - Monitor performance |
| 2: Widget State Corruption | ⚠️ Partial | Medium | Implement transaction rollback |
| 3: Redundant NODE Calls | ☑️ Confirmed | Low-Med | Use cached positions |
| 4: Unvalidated Tooltip Ownership | ⚠️ Partial | Low-Med | Add owner whitelist check |
| 5: Duplicate Hook Registration | ✅ Fixed | N/A | None - Already protected |

---

## Implementation Priority

### High Priority (Fix Soon)
1. **Bug 3:** Redundant NODE Calls - Simple fix, clear performance benefit
2. **Bug 4:** Tooltip Ownership - UX issue, straightforward solution

### Medium Priority (Consider for Future)
3. **Bug 2:** Widget State Corruption - Complex fix, rare occurrence

### No Action Needed
4. **Bug 1:** Already optimized with smart caching
5. **Bug 5:** Already protected with guard flag

---

## Conclusion

The CPLight codebase is generally well-architected with good practices:
- Smart graph caching (Bug 1)
- Guard flags for idempotency (Bug 5)
- Defensive programming patterns

Areas for improvement:
- Transaction-style error handling (Bug 2)
- Leveraging existing caches (Bug 3)
- Tooltip ownership validation (Bug 4)

All issues are fixable with minimal risk and clear benefits.

---

**End of Bug Hunt Report**
