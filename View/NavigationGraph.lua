---------------------------------------------------------------
-- CPLight Navigation Graph Builder
---------------------------------------------------------------
-- Builds and caches navigation graph using ConsolePortNode library
-- Stores NODE's cache and uses NavigateToBestCandidateV3 for real-time navigation
--
-- Architecture:
-- - BuildGraph(frames): Calls NODE() to scan frames and caches the result
-- - NavigateInDirection(cacheItem, direction): Uses NODE.NavigateToBestCandidateV3
-- - InvalidateGraph(): Marks cache as stale, triggers rebuild on next access
-- - NodeToIndex(node) / IndexToNode(index): Node <-> Index mapping
-- - GetCacheItem(index): Returns NODE cache item for a given index
--
-- Key Design Principles:
-- 1. All graph building happens out-of-combat (PLAYER_REGEN_ENABLED)
-- 2. Uses NODE library for scanning, validation, and navigation
-- 3. Caches NODE's result until invalidation (visibility, scroll, bag changes)
-- 4. Navigation is real-time using NODE.NavigateToBestCandidateV3 (angle-based, V3)
-- 5. Testable: Pure functions with clear inputs/outputs

local ADDON_NAME, addon = ...

-- Create the NavigationGraph module object
local NavigationGraph = {}

-- Expose globally for other modules to access
_G.CPLightNavigationGraph = NavigationGraph

---------------------------------------------------------------
-- Module State
---------------------------------------------------------------
local graph = {
	nodeCache = {},          -- NODE library's CACHE array (cache items with .node, .object, .super, .level)
	nodeToIndex = {},        -- Map node -> index for quick lookup
	isDirty = false,         -- Mark stale, rebuild on next access
	lastBuildTime = 0,       -- Timestamp of last build
}

---------------------------------------------------------------
-- Public API: Graph Building
---------------------------------------------------------------

---Validate and convert frame inputs to visible frame objects
---@param frames table Array of UI frame names or frame objects
---@return table|nil frameObjects Array of visible frame objects, or nil on failure
function NavigationGraph:_ValidateAndConvertFrames(frames)
	if not frames or #frames == 0 then
		return nil
	end
	
	local frameObjects = {}
	for _, frame in ipairs(frames) do
		-- Convert string names to frame objects
		local frameObj = type(frame) == 'string' and _G[frame] or frame
		
		-- Validate frame exists and is visible
		if frameObj and type(frameObj) == 'table' and frameObj.IsVisible and frameObj.GetAlpha then
			if frameObj:IsVisible() and frameObj:GetAlpha() > 0 then
				table.insert(frameObjects, frameObj)
			end
		end
	end
	
	if #frameObjects == 0 then
		return nil
	end
	
	return frameObjects
end

---Build navigation graph from visible frames using NODE library
---Calls NODE() to scan frames and stores the resulting cache
---@param frames table Array of UI frame names or frame objects
---@return boolean success True if graph built successfully
function NavigationGraph:BuildGraph(frames)
	-- Clear old graph
	graph.nodeCache = {}
	graph.nodeToIndex = {}
	
	-- Validate and convert frames to visible frame objects
	local frameObjects = self:_ValidateAndConvertFrames(frames)
	if not frameObjects then
		return false
	end
	
	-- Get NODE library
	local NODE = LibStub('ConsolePortNode')
	if not NODE then
		return false
	end
	
	-- Call NODE to scan frames and build cache
	-- NODE() returns CACHE array with {node, object, super, level} items
	local cache = NODE(unpack(frameObjects))
	if not cache or type(cache) ~= 'table' or #cache == 0 then
		return false
	end
	
	-- Store NODE's cache and build index mapping
	graph.nodeCache = cache
	for index, cacheItem in ipairs(cache) do
		if cacheItem and cacheItem.node then
			graph.nodeToIndex[cacheItem.node] = index
		end
	end
	
	-- Mark graph as valid
	graph.isDirty = false
	graph.lastBuildTime = GetTime()
	
	return true
end

---Mark graph as stale, will rebuild on next access
function NavigationGraph:InvalidateGraph()
	-- Clear NODE library's internal cache to prevent memory leak
	local NODE = LibStub('ConsolePortNode')
	if NODE and NODE.ClearCache then
		NODE.ClearCache()
	end
	
	-- Clear all graph data using wipe() for proper cleanup
	wipe(graph.nodeCache)
	wipe(graph.nodeToIndex)
	
	graph.isDirty = true
end

---Get current graph state (for testing/debugging)
---@return table Graph containing nodes and edges
function NavigationGraph:GetGraph()
	return graph
end

---Check if graph is valid and has nodes
---@return boolean True if graph has nodes and not dirty
function NavigationGraph:IsValid()
	return #graph.nodeCache > 0 and not graph.isDirty
end

---------------------------------------------------------------
-- Public API: Node Lookup
---------------------------------------------------------------

---Validate that a node is still navigable using NODE library
---@param node userdata Frame object
---@param cacheItem table NODE cache item reference (optional)
---@return boolean valid True if node is still valid
function NavigationGraph:ValidateNode(node, cacheItem)
	if not node then return false end
	
	-- Use NODE library for all validation
	local NODE = LibStub('ConsolePortNode')
	if not NODE then return false end
	
	-- Trust NODE's validation completely
	if not NODE.IsRelevant(node) then return false end
	
	-- Check if drawn (with super node if available)
	if cacheItem and cacheItem.super then
		if not NODE.IsDrawn(node, cacheItem.super) then return false end
	else
		-- No cache item, do basic drawn check
		local super = node.GetParent and node:GetParent()
		if super then
			if not NODE.IsDrawn(node, super) then return false end
		end
	end
	
	return true
end

---Navigate from current cache item to best candidate in direction using NODE library
---@param currentCacheItem table NODE cache item for current node
---@param direction string Direction ("UP", "DOWN", "LEFT", "RIGHT")
---@return table|nil nextCacheItem The cache item for the next node, or nil if no candidate
function NavigationGraph:NavigateInDirection(currentCacheItem, direction)
	if not currentCacheItem or not currentCacheItem.node then
		return nil
	end
	
	-- Get NODE library
	local NODE = LibStub('ConsolePortNode')
	if not NODE or not NODE.NavigateToBestCandidateV3 then
		return nil
	end
	
	-- Use NODE's V3 navigation (angle-based with multiple points per candidate)
	-- pcall guard: ConsolePortNode's GetCandidatesForVectorV2 can crash with
	-- "attempt to perform arithmetic on local 'x' (a nil value)" when a cached
	-- node becomes stale (GetRect returns nil). Wrapping in pcall lets the caller
	-- detect nil and trigger a graph rebuild instead of propagating the error.
	local ok, nextCacheItem, changed = pcall(NODE.NavigateToBestCandidateV3, currentCacheItem, direction)
	if not ok then
		CPAPI.DebugLog('NODE navigation error (stale node): %s', tostring(nextCacheItem))
		return nil
	end
	
	return nextCacheItem
end

---Convert node reference to graph index
---@param node userdata Frame object
---@return number|nil Index in graph, or nil if not found
function NavigationGraph:NodeToIndex(node)
	return graph.nodeToIndex[node]
end

---Convert graph index to node reference
---@param index number Node index
---@return userdata|nil Frame object, or nil if not found
function NavigationGraph:IndexToNode(index)
	local cacheItem = graph.nodeCache[index]
	if cacheItem then
		return cacheItem.node
	end
	return nil
end

---Get cache item by index
---@param index number Node index
---@return table|nil cacheItem NODE cache item, or nil if not found
function NavigationGraph:GetCacheItem(index)
	return graph.nodeCache[index]
end

---Get position of a node by index using NODE library
---@param index number Node index
---@return number|nil x Scaled center X coordinate, or nil if not found
---@return number|nil y Scaled center Y coordinate
function NavigationGraph:GetNodePosition(index)
	local cacheItem = graph.nodeCache[index]
	if not cacheItem or not cacheItem.node then
		return nil, nil
	end
	
	-- Get position from NODE library (real-time)
	local NODE = LibStub('ConsolePortNode')
	if not NODE or not NODE.GetCenterScaled then
		return nil, nil
	end
	
	return NODE.GetCenterScaled(cacheItem.node)
end

---Get total node count in graph
---@return number Count of nodes
function NavigationGraph:GetNodeCount()
	return #graph.nodeCache
end

---Get the first (topmost) valid node index
---@return number|nil Index of first node, or nil if no nodes
function NavigationGraph:GetFirstNodeIndex()
	if #graph.nodeCache > 0 then
		return 1
	end
	return nil
end

---Find the closest node to a target position using NODE library
---@param targetX number Target X coordinate (scaled)
---@param targetY number Target Y coordinate (scaled)
---@return number|nil closestIndex Index of closest node, or nil if no nodes
function NavigationGraph:GetClosestNodeToPosition(targetX, targetY)
	if not targetX or not targetY then
		return nil
	end
	
	if #graph.nodeCache == 0 then
		return nil
	end
	
	-- Get NODE library
	local NODE = LibStub('ConsolePortNode')
	if not NODE or not NODE.GetCenterScaled then
		return nil
	end
	
	local closestIndex = nil
	local minDistanceSquared = math.huge
	
	-- Iterate through all cached nodes and find the closest one
	for index, cacheItem in ipairs(graph.nodeCache) do
		if cacheItem and cacheItem.node then
			-- Validate node is still visible using NODE library
			if self:ValidateNode(cacheItem.node, cacheItem) then
				-- Get position from NODE library (real-time)
				local nodeX, nodeY = NODE.GetCenterScaled(cacheItem.node)
				
				if nodeX and nodeY then
					-- Calculate distance squared (no need for sqrt, just comparing)
					local dx = targetX - nodeX
					local dy = targetY - nodeY
					local distSquared = (dx * dx) + (dy * dy)
					
					if distSquared < minDistanceSquared then
						minDistanceSquared = distSquared
						closestIndex = index
					end
				end
			end
		end
	end
	
	return closestIndex
end
---------------------------------------------------------------
-- Navigation using NODE Library
---------------------------------------------------------------
-- Navigation is now handled real-time by NODE.NavigateToBestCandidateV3
-- No secure attribute export needed - navigation is fully insecure

---------------------------------------------------------------
-- Debug Helpers
---------------------------------------------------------------

---Get debug info about the current graph state
---@return table Debug information
function NavigationGraph:GetDebugInfo()
	return {
		nodeCount = #graph.nodeCache,
		isDirty = graph.isDirty,
		lastBuildTime = graph.lastBuildTime,
		age = GetTime and graph.lastBuildTime and (GetTime() - graph.lastBuildTime) or 0
	}
end

---------------------------------------------------------------
-- Return public module
---------------------------------------------------------------
return NavigationGraph
