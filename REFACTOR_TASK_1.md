# REFACTOR TASK 1: Fix Input Interception Security Violations

## 🎯 Objective
Rebuild the gamepad input interception system to meet TBC Anniversary 2.5.5 strict secure/insecure boundary requirements.

---

## 🔴 CRITICAL SECURITY VIOLATIONS (Ordered Most → Least Critical)

### 1. **PreClick Taint Vector - D-Pad Navigation**
**Severity:** 🔴 BLOCKER  
**Location:** [View/Hijack.lua](View/Hijack.lua)

**Problem:**
```lua
upWidget:SetScript('PreClick', function(self, button, down)
    if down then Hijack:Navigate('UP') end  -- INSECURE FUNCTION DURING SECURE EVENT
end)
```
- PreClick handlers call insecure `Hijack:Navigate()` during secure button events
- Creates taint vector that violates 2.5.5 protected action system
- Can cause "Action has been blocked" errors

**Required Fix:**
- Implement **pre-calculated navigation graph** stored as secure attributes
- Use secure `_onattributechanged` snippets to traverse the graph
- Never call insecure Lua during button events

---

### 2. **PreClick Taint Vector - Visual Feedback**
**Severity:** 🔴 BLOCKER  
**Location:** [View/Hijack.lua](View/Hijack.lua)

**Problem:**
```lua
padWidget:SetScript('PreClick', function(self, button, down)
    if down then Hijack:SetGauntletPressed(true) end  -- INSECURE FRAME UPDATE
end)
```
- Triggers insecure gauntlet frame updates during secure button press
- Violates secure/insecure boundary

**Required Fix:**
- Move visual feedback to PostClick (after secure action completes)
- OR use secure frame state drivers for visual changes
- Separate cosmetic updates from action logic

---

### 3. **OnUpdate Race Condition with Combat Lockdown**
**Severity:** 🟠 HIGH  
**Location:** [View/Hijack.lua](View/Hijack.lua)

**Problem:**
```lua
VisibilityChecker:SetScript("OnUpdate", function(self, elapsed)
    -- Can fire during combat transitions
    if visible and not Hijack.IsActive then
        Hijack:EnableNavigation()  -- Sets secure bindings
    end
end)
```
- OnUpdate can fire during combat state transitions
- Attempts to modify secure bindings via `SetOverrideBindingClick`
- Potential for combat lockdown errors

**Required Fix:**
- Add combat lockdown check before any binding modifications
- Use event-driven approach instead of polling (PLAYER_REGEN_ENABLED/DISABLED)
- Ensure all binding changes happen outside combat only

---

### 4. **Insecure Node Scanning During Active Navigation**
**Severity:** 🟠 HIGH  
**Location:** [View/Hijack.lua](View/Hijack.lua)

**Problem:**
```lua
function Hijack:Navigate(direction)
    local activeFrames = {}
    -- Rescans UI every navigation call
    local cache = NODE(unpack(activeFrames))  -- EXPENSIVE + INSECURE
end
```
- Rebuilds entire NODE cache on every navigation call
- Calls insecure ConsolePortNode library functions
- Performance bottleneck

**Required Fix:**
- Build navigation graph once when UI opens (out of combat)
- Store as secure attributes on Driver frame
- Navigation operates on pre-calculated graph only

---

### 5. **Missing NODE Return Value Validation**
**Severity:** 🟡 MEDIUM  
**Location:** [View/Hijack.lua](View/Hijack.lua)

**Problem:**
```lua
local targetCacheItem = NODE.NavigateToBestCandidateV3(currentCacheItem, direction)
-- No validation if returned node is still visible
if targetCacheItem and targetCacheItem.node ~= self.CurrentNode then
    self:SetFocus(targetCacheItem.node)  -- Could be invalid
end
```

**Required Fix:**
- Validate `node:IsVisible()` before `SetFocus()`
- Handle nil returns gracefully

---

### 6. **Tooltip Memory Leak**
**Severity:** 🟡 MEDIUM  
**Location:** [View/Hijack.lua](View/Hijack.lua)

**Problem:**
```lua
function Hijack:SetFocus(node)
    -- Shows new tooltip without clearing previous
    self:ShowNodeTooltip(node)
end
```

**Required Fix:**
- Call `GameTooltip:Hide()` before showing new tooltip in `SetFocus()`

---

## 📐 ARCHITECTURAL REQUIREMENTS

### Core Principle: Strict Secure/Insecure Separation

**Insecure Zone (Lua):**
- UI frame scanning (out of combat)
- Navigation graph building (out of combat)
- Visual updates (gauntlet, tooltips)
- Logging/debugging

**Secure Zone (Attributes + Snippets):**
- All button event handling
- Navigation graph traversal
- Node focus changes
- Click execution

**Boundary:**
- Insecure → Secure: Only via `SetAttribute()` (out of combat)
- Secure → Insecure: Only via state drivers with `_onstate-` handlers

---

## 🔧 IMPLEMENTATION STEPS

### Phase 1: Pre-Calculated Navigation Graph
1. Create `View/NavigationGraph.lua` module
2. Build navigation graph out-of-combat using NODE library
3. Store graph as secure attributes (nodeUp, nodeDown, nodeLeft, nodeRight per node)
4. Invalidate and rebuild when UI changes detected

### Phase 2: Secure Navigation Snippets  
1. Convert D-Pad widgets to use `_onattributechanged` handlers
2. Implement secure graph traversal in Lua snippets
3. Update `currentNode` attribute on navigation
4. Trigger visual updates via state drivers

### Phase 3: Decouple Visual Feedback
1. Move gauntlet updates to insecure state change handlers
2. Use `_onstate-currentnode` to trigger cosmetic updates
3. Move tooltip logic to post-action handlers

### Phase 4: Combat Safety
1. Replace OnUpdate polling with event-driven visibility checking
2. Add combat lockdown guards to all binding modifications
3. Disable navigation on combat entry, rebuild on combat exit

### Phase 5: Cleanup & Optimization
1. Trim ConsolePortNode's integration in our project to only used functions (scan + position + validation)
2. Add comprehensive error handling
3. Implement debug logging system

---

## 🧪 TESTING REQUIREMENTS

- ✅ Open/close UI windows rapidly → No taint errors
- ✅ Navigate while entering combat → Graceful degradation
- ✅ Navigate between 2 different open windows → Uses distance fallback
- ✅ Dynamic UI changes (bag slots fill) → Graph updates correctly
- ✅ Spam navigation inputs → No performance degradation
- ✅ Use secured actions (cast spell, use item) → No "action blocked" errors

---

## 📚 REFERENCE MATERIALS

**WoW 2.5.5 Secure System:**
- Blizzard_SecureTemplates.lua
- SecureHandlers documentation (WoWWiki)
- RegisterStateDriver behavior

**ConsolePortNode:**
- Only use: `NODE()` scanner, `GetCenterScaled()`, `IsDrawn()`, `IsRelevant()`
- DO NOT use navigation algorithms directly in secure contexts

---

## ⚠️ CRITICAL WARNINGS

1. **Never** call insecure Lua functions from PreClick/PostClick handlers
2. **Never** modify secure attributes during combat
3. **Never** use SetOverrideBindingClick in OnUpdate without combat checks
4. **Always** separate visual updates from action logic
5. **Always** validate node state before focus changes
