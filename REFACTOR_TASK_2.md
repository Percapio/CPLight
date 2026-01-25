# REFACTOR TASK 2: Code Quality, Stability & Module Separation

## 🎯 Objective
Improve code quality, stability, and maintainability by completing remaining refactor phases and properly separating concerns across three modules.

**Status:** Phase 1 Complete ✅  
**Approach:** Pragmatic insecure navigation (accepting PreClick taint risk for simplicity)

---

## ✅ PHASE 1 COMPLETE

- ✅ Pre-calculated navigation graph implemented
- ✅ NavigationGraph.lua module created with proper validation
- ✅ Graph built once on UI open, not on every navigation
- ✅ Node validation added to SetFocus()
- ✅ Tooltip memory leak fixed
- ✅ Combat lockdown checks added to binding management
- ✅ OnUpdate race condition mitigated with InCombatLockdown() check

---

## 🔧 REMAINING WORK

### Phase 2: Decouple Visual Feedback
**Goal:** Separate cosmetic updates from navigation logic for better maintainability and testability.

#### 2.1 Move Gauntlet Updates Out of Navigation Flow
**Current:** Gauntlet position updates happen inline in `SetFocus()`  
**Target:** Create dedicated visual update methods

**Changes needed:**
```lua
-- IN: Hijack.lua
-- Create visual update coordinator
function Hijack:UpdateVisualFeedback(node)
    if not node then return end
    self:UpdateGauntletPosition(node)
    self:ShowNodeTooltip(node)
end

-- Simplify SetFocus to focus on state management
function Hijack:SetFocus(node)
    -- Validation...
    self.CurrentNode = node
    self:_ConfigureWidgetsForNode(node)
    self:UpdateVisualFeedback(node)  -- Separated concern
end
```

#### 2.2 Centralize Tooltip Management
**Issue:** Tooltips shown in multiple places without consistent cleanup  
**Fix:** Create tooltip manager methods

```lua
function Hijack:ShowTooltipForNode(node)
    self:HideTooltip()  -- Always clear first
    -- Tooltip logic here
end

function Hijack:HideTooltip()
    if GameTooltip:IsShown() then
        GameTooltip:Hide()
    end
end
```

#### 2.3 Gauntlet State Machine
**Issue:** Gauntlet pressed/unpressed state scattered across PreClick/PostClick  
**Fix:** Centralize state management

```lua
function Hijack:SetGauntletState(state)
    -- state: 'hidden', 'pointing', 'pressing'
    if state == 'hidden' then
        self.Gauntlet:Hide()
    elseif state == 'pointing' then
        self.Gauntlet.tex:SetTexture("Interface\\CURSOR\\Point")
        self.Gauntlet:SetSize(32, 32)
        self.Gauntlet:Show()
    elseif state == 'pressing' then
        self.Gauntlet.tex:SetTexture("Interface\\CURSOR\\Interact")
        self.Gauntlet:SetSize(38, 38)
        self.Gauntlet:Show()
    end
end
```

---

### Phase 3: Combat Safety Enhancements
**Goal:** Ensure robust combat lockdown handling with no edge cases.

#### 3.1 Event-Driven Visibility Detection (Replace OnUpdate)
**Current:** VisibilityChecker uses OnUpdate polling every 0.1s  
**Target:** Event-driven approach for better performance

**Implementation:**
```lua
-- Hook frame show/hide for ALLOWED_FRAMES
local function OnFrameShow(frame)
    if not InCombatLockdown() then
        Hijack:OnUIFrameVisibilityChanged()
    end
end

local function OnFrameHide(frame)
    if not InCombatLockdown() then
        Hijack:OnUIFrameVisibilityChanged()
    end
end

function Hijack:RegisterVisibilityHooks()
    for _, frameName in ipairs(ALLOWED_FRAMES) do
        local frame = _G[frameName]
        if frame then
            frame:HookScript('OnShow', OnFrameShow)
            frame:HookScript('OnHide', OnFrameHide)
        end
    end
end

function Hijack:OnUIFrameVisibilityChanged()
    -- Check if any allowed frames visible
    local hasVisibleFrames = self:_HasVisibleAllowedFrames()
    
    if hasVisibleFrames and not self.IsActive then
        self:EnableNavigation()
    elseif not hasVisibleFrames and self.IsActive then
        self:DisableNavigation()
    end
end
```

**Fallback:** Keep OnUpdate as backup for frames without OnShow/OnHide events, but increase interval to 0.5s.

#### 3.2 Combat Transition Safety
**Issue:** Graph invalidation during combat can cause issues on combat exit  
**Fix:** Add combat state tracking

```lua
function Hijack:OnCombatStart()
    self.WasActiveBeforeCombat = self.IsActive
    if self.IsActive then
        self:DisableNavigation()
    end
end

function Hijack:OnCombatEnd()
    if self.WasActiveBeforeCombat then
        -- Re-enable if UI still visible
        if self:_HasVisibleAllowedFrames() then
            self:EnableNavigation()
        end
    end
    self.WasActiveBeforeCombat = false
end
```

#### 3.3 Binding Safety Audit
**Verify:** All SetOverrideBindingClick/ClearOverrideBindings wrapped in lockdown checks

**Checklist:**
- ✅ EnableNavigation - Already has check
- ✅ DisableNavigation - Already has check
- ❓ Widget release operations - Review needed
- ❓ Rapid enable/disable cycles - Test needed

---

### Phase 4: Module Separation & Cleanup
**Goal:** Clear separation of concerns across three modules with well-defined interfaces.

#### Module Architecture

```
┌─────────────────────────────────────────────────────────┐
│ NavigationGraph.lua (Graph Builder)                    │
│ - Scans UI frames using NODE library                   │
│ - Builds node array with positions                     │
│ - Pre-calculates directional edges                     │
│ - Exports graph to secure attributes                   │
│ - Validates graph integrity                            │
│                                                         │
│ Public API:                                             │
│   BuildGraph(frames) → boolean                          │
│   InvalidateGraph()                                     │
│   NodeToIndex(node) → index                             │
│   IndexToNode(index) → node                             │
│   GetNodeEdges(index) → {up,down,left,right}           │
│   GetNodeCount() → number                               │
│   IsValid() → boolean                                   │
└─────────────────────────────────────────────────────────┘
                         ↓ uses
┌─────────────────────────────────────────────────────────┐
│ Hijack.lua (Navigation Orchestrator)                   │
│ - Manages navigation lifecycle (enable/disable)        │
│ - Handles D-pad input (PreClick handlers)              │
│ - Manages focus state (CurrentNode)                    │
│ - Coordinates visual feedback (gauntlet/tooltips)      │
│ - Configures secure widgets for clicks                 │
│ - Detects UI frame visibility changes                  │
│                                                         │
│ Public API:                                             │
│   EnableNavigation()                                    │
│   DisableNavigation()                                   │
│   Navigate(direction)                                   │
│   SetFocus(node)                                        │
│   UpdateVisualFeedback(node)                            │
└─────────────────────────────────────────────────────────┘
                         ↓ delegates to
┌─────────────────────────────────────────────────────────┐
│ Actions.lua (Smart Click Handler)                      │
│ - Detects button types (spells, items, merchants)      │
│ - Handles context-specific interactions                │
│ - Manages inventory operations                         │
│ - Integrates with game systems (trade, banks, etc)     │
│                                                         │
│ Public API:                                             │
│   GetButtonType(button) → string                        │
│   PerformContextualAction(button) → boolean             │
│   GetContainerInfo(button) → table                      │
│                                                         │
│ FUTURE: Called by PAD1/PAD2 clicks for smart actions   │
└─────────────────────────────────────────────────────────┘
```

#### 4.1 NavigationGraph.lua - COMPLETE ✅
**Status:** Already well-separated, no changes needed.

**Responsibilities:**
- ✅ Graph building and validation
- ✅ NODE library integration
- ✅ Secure attribute export
- ✅ Node/index mapping
- ✅ Edge calculation

---

#### 4.2 Hijack.lua - NEEDS CLEANUP 🔧

**Current Issues:**
1. ❌ Still has unused GetActiveNodes stub references
2. ❌ Visual feedback mixed with navigation logic
3. ❌ PreClick handlers defined inline in EnableNavigation
4. ❌ Binding management spread across multiple methods
5. ❌ No clear method grouping/organization

**Refactor Structure:**
```lua
---------------------------------------------------------------
-- SECTION 1: Module Setup & Constants
---------------------------------------------------------------
-- Module declaration, NODE/NavGraph imports, ALLOWED_FRAMES

---------------------------------------------------------------
-- SECTION 2: Driver Frame & State Management
---------------------------------------------------------------
-- Driver frame creation, state driver setup, widget management

---------------------------------------------------------------
-- SECTION 3: Navigation Core
---------------------------------------------------------------
-- Navigate(), SetFocus(), graph traversal logic

---------------------------------------------------------------
-- SECTION 4: Widget & Binding Management
---------------------------------------------------------------
-- _CollectVisibleFrames()
-- _BuildAndExportGraph()
-- _SetupSecureWidgets()
-- _SetupNavigationHandlers()
-- EnableNavigation()
-- DisableNavigation()

---------------------------------------------------------------
-- SECTION 5: Visual Feedback (Gauntlet & Tooltips)
---------------------------------------------------------------
-- CreateGauntlet()
-- UpdateGauntletPosition()
-- SetGauntletState()
-- ShowTooltipForNode()
-- HideTooltip()
-- UpdateVisualFeedback()

---------------------------------------------------------------
-- SECTION 6: UI Frame Detection
---------------------------------------------------------------
-- VisibilityChecker (OnUpdate fallback)
-- RegisterVisibilityHooks() (event-driven)
-- OnUIFrameVisibilityChanged()
-- _HasVisibleAllowedFrames()

---------------------------------------------------------------
-- SECTION 7: Combat Safety
---------------------------------------------------------------
-- PLAYER_REGEN_DISABLED handler
-- PLAYER_REGEN_ENABLED handler
-- OnCombatStart()
-- OnCombatEnd()

---------------------------------------------------------------
-- SECTION 8: Module Lifecycle
---------------------------------------------------------------
-- OnEnable()
-- OnDisable()
```

**Cleanup Tasks:**
- ☐ Remove any dead code references
- ☐ Group methods by responsibility
- ☐ Extract inline PreClick handlers to named methods
- ☐ Add section comments for navigation
- ☐ Ensure all public methods documented with LuaDoc

---

#### 4.3 Actions.lua - NEEDS INTEGRATION 🚧

**Current Status:** Module exists but not integrated into navigation flow  
**Target:** Make Actions.lua the smart click handler

**Current Issues:**
1. ❌ Actions module enabled but never called
2. ❌ No integration with Hijack's PAD1/PAD2 clicks
3. ❌ Redundant context detection (MerchantOpen, TradeOpen tracked but unused)

**Integration Plan:**

**Step 1: Add Action Handler Hook**
```lua
-- IN: Hijack.lua (after SetFocus sets clickbutton)
function Hijack:_ConfigureWidgetsForNode(node)
    local clickWidget = Driver:GetWidget('PAD1', 'Hijack')
    if clickWidget then
        clickWidget:SetAttribute(CPAPI.ActionTypeRelease, 'click')
        clickWidget:SetAttribute('clickbutton', node)
        clickWidget:Show()
    end
    
    local rightWidget = Driver:GetWidget('PAD2', 'Hijack')
    if rightWidget then
        rightWidget:SetAttribute(CPAPI.ActionTypeRelease, 'click')
        rightWidget:SetAttribute('clickbutton', node)
        rightWidget:Show()
    end
    
    -- FUTURE: Add Actions module integration
    -- local buttonType = Actions:GetButtonType(node)
    -- Actions:PrepareAction(node, buttonType)
end
```

**Step 2: Refactor Actions.lua**
- Simplify button type detection
- Add logging for click actions
- Remove unused context tracking (or use it)
- Add public PrepareAction() method

**Step 3: Document Action Flow**
```
User presses PAD1 → Widget clicks node → Game handles click
                        ↓
                   (FUTURE: Actions.lua inspects context)
                   (FUTURE: Smart behaviors like "use item" vs "equip item")
```

**DECISION NEEDED:** Do we want smart action handling, or just pass-through clicks?
- **Option A (Current):** Pure pass-through, Actions.lua unused
- **Option B (Enhanced):** Actions.lua adds intelligence for context-aware clicks
- **Option C (Remove):** Delete Actions.lua if not needed

---

## 🐛 MISSED FIXES & EDGE CASES

### Fix 1: Graph Invalidation Timing
**Issue:** Graph invalidated on every DisableNavigation, even temporary closures  
**Impact:** Rebuilds graph unnecessarily when user rapidly opens/closes same frame

**Fix:** Smart invalidation
```lua
-- Track which frames graph was built from
Hijack.LastGraphFrames = {}

function Hijack:_ShouldRebuildGraph(currentFrames)
    -- Compare frame lists
    if #currentFrames ~= #self.LastGraphFrames then return true end
    
    -- Check if same frames
    local frameSet = {}
    for _, frame in ipairs(self.LastGraphFrames) do
        frameSet[frame] = true
    end
    
    for _, frame in ipairs(currentFrames) do
        if not frameSet[frame] then return true end
    end
    
    return false
end
```

### Fix 2: Widget Cleanup on Errors
**Issue:** If EnableNavigation fails partway through, widgets may be in invalid state  
**Fix:** Rollback on failure

```lua
function Hijack:EnableNavigation()
    -- Attempt enable...
    local success, err = pcall(function()
        -- All setup here
    end)
    
    if not success then
        CPAPI.Log('ERROR: Navigation enable failed: %s', err)
        self:DisableNavigation()  -- Cleanup
        return false
    end
end
```

### Fix 3: Node Position Caching
**Issue:** NODE.GetCenterScaled() called frequently for gauntlet updates  
**Fix:** Cache positions in NavigationGraph

```lua
-- Already stored in graph.nodes[index].x/y
-- Use NavGraph:GetNodePosition(index) instead of repeated NODE calls
```

### Fix 4: Tooltip Ownership Validation
**Issue:** GameTooltip:Hide() may hide unrelated tooltips  
**Fix:** Check ownership before hiding

```lua
function Hijack:HideTooltip()
    if GameTooltip:IsShown() then
        local owner = GameTooltip:GetOwner()
        if owner == self.CurrentNode or owner == UIParent then
            GameTooltip:Hide()
        end
    end
end
```

### Fix 5: Memory Leak - Frame Hooks
**Issue:** If RegisterVisibilityHooks() called multiple times, creates duplicate hooks  
**Fix:** Track hook state

```lua
Hijack.VisibilityHooksRegistered = false

function Hijack:RegisterVisibilityHooks()
    if self.VisibilityHooksRegistered then return end
    -- Hook frames...
    self.VisibilityHooksRegistered = true
end
```

---

## 📋 IMPLEMENTATION CHECKLIST

### Phase 3: Visual Feedback Decoupling
- ☐ Create UpdateVisualFeedback(node) coordinator
- ☐ Extract gauntlet logic to SetGauntletState(state)
- ☐ Centralize tooltip management (ShowTooltipForNode, HideTooltip)
- ☐ Update SetFocus() to use new visual methods
- ☐ Remove inline gauntlet updates from PreClick handlers

### Phase 4: Combat Safety
- ☐ Implement RegisterVisibilityHooks() with OnShow/OnHide
- ☐ Create OnUIFrameVisibilityChanged() event handler
- ☐ Add OnCombatStart/OnCombatEnd with state tracking
- ☐ Increase OnUpdate interval to 0.5s (fallback only)
- ☐ Test rapid combat transitions
- ☐ Test UI open → combat → UI close → combat end sequence

### Phase 5: Module Separation
- ☐ Reorganize Hijack.lua into 8 logical sections
- ☐ Extract inline PreClick handlers to named methods
- ☐ Add LuaDoc comments to all public methods
- ☐ Review Actions.lua integration (decide Option A/B/C)
- ☐ Remove dead code and unused imports

### Bug Fixes
- ☐ Implement smart graph invalidation (compare frame lists)
- ☐ Add rollback on EnableNavigation failure
- ☐ Use cached node positions from NavGraph
- ☐ Fix tooltip ownership validation
- ☐ Prevent duplicate visibility hook registration

---

## 🧪 TESTING PLAN

### Regression Tests
- ✅ Basic navigation (D-pad between buttons)
- ✅ Open character sheet → navigate → close
- ✅ Combat entry/exit while navigating
- ✅ Multiple frames open (bags + character)
- ✅ Dynamic UI changes (add items to bags)

### New Tests for Phase 3-5
- ☐ Rapid frame open/close (shouldn't rebuild graph every time)
- ☐ Navigation during loading screens
- ☐ Memory profiling (no leaks from tooltips/hooks)
- ☐ CPU profiling (OnUpdate shouldn't spike)
- ☐ Tooltip doesn't flicker or stick
- ☐ Gauntlet state transitions smoothly
- ☐ Widget cleanup on errors leaves no orphaned bindings

### Performance Benchmarks
- ☐ Graph build time: < 50ms for typical UI
- ☐ Navigation response: < 16ms (1 frame)
- ☐ OnUpdate CPU: < 1% when idle
- ☐ Memory growth: < 1MB per session

---

## 🎯 SUCCESS CRITERIA

### Code Quality
- ✅ All methods under 50 lines
- ✅ Clear separation of concerns across 3 modules
- ✅ No dead code or unused functions
- ✅ All public APIs documented
- ✅ Logical organization within files

### Stability
- ✅ No Lua errors under normal operation
- ✅ Graceful degradation on NODE library failures
- ✅ Safe combat transitions
- ✅ No memory leaks
- ✅ No combat lockdown errors

### Performance
- ✅ Graph builds once per UI session
- ✅ Navigation responds instantly
- ✅ Low CPU usage when idle
- ✅ Efficient frame visibility detection

### User Experience
- ✅ Smooth visual feedback (gauntlet, tooltips)
- ✅ Reliable navigation in all UI contexts
- ✅ No "Action has been blocked" errors (accepting PreClick taint)
- ✅ Works after UI reload without issues

---

## 📝 NEXT STEPS AFTER TASK 2

1. **Polish Pass:** Add configuration options for visual feedback
2. **Documentation:** Create user guide and API reference
3. **Testing:** Recruit testers for edge case discovery
4. **Optimization:** Profile and optimize hotspots
5. **Feature Expansion:** 
   - Custom frame whitelist (user-defined)
   - Navigation history (back button)
   - Smart Actions.lua integration (if Option B chosen)
   - Analog stick movement integration

---

## ⚠️ KNOWN LIMITATIONS (Accepted Trade-offs)

1. **PreClick Taint Risk:** D-pad navigation uses insecure PreClick handlers
   - **Risk:** Potential for taint-related "Action blocked" errors
   - **Mitigation:** Separate navigation from action execution
   - **Alternative:** Full secure snippet implementation (Phase 2 - skipped)

2. **OnUpdate Fallback:** Some frames lack OnShow/OnHide events
   - **Impact:** Can't be fully event-driven
   - **Mitigation:** 0.5s interval polling as fallback

3. **NODE Library Dependency:** Relies on external library for frame scanning
   - **Risk:** Library bugs affect our navigation
   - **Mitigation:** Defensive validation, fallback to simple frame list

4. **No Cross-Addon Navigation:** Only works with Blizzard UI frames
   - **Limitation:** Can't navigate custom addon UIs without explicit support
   - **Future:** Add API for addons to register navigable frames
