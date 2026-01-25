---------------------------------------------------------------
-- CPLight Navigation Graph Builder
---------------------------------------------------------------
-- Builds a pre-calculated navigation graph out-of-combat
-- Stores node indices and their directional neighbors (up/down/left/right)
-- Designed for secure attribute storage: no direct node references in secure zone
--
-- Architecture:
-- - BuildGraph(frames) : Scans frames, builds node cache, computes neighbors
-- - InvalidateGraph() : Marks graph as stale, triggers rebuild on next access
-- - GetNodeEdges(index) : Returns {up, down, left, right} neighbor indices
-- - NodeToIndex(node) / IndexToNode(index) : Node <-> Index mapping
-- - GetGraph() : Returns current graph state
--
-- Key Design Principles:
-- 1. All graph building happens out-of-combat (PLAYER_REGEN_ENABLED)
-- 2. Uses ConsolePortNode library for frame scanning only (NODE, GetCenterScaled, IsDrawn, IsRelevant)
-- 3. Stores node indices, not direct frame references (secure-safe)
-- 4. Navigation algorithms pre-calculated and stored as edges
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
	nodes = {},              -- Array of {node, x, y} indexed by graph position
	nodeToIndex = {},        -- Map node -> index for quick lookup
	edges = {},              -- edges[index] = {up, down, left, right}
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
		CPAPI.Log('ERROR: No frames provided to build graph')
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
		CPAPI.Log('ERROR: No visible frames found from %d input frames', #frames)
		return nil
	end
	
	CPAPI.Log('Found %d visible frames from %d input frames', #frameObjects, #frames)
	return frameObjects
end

---Scan frame objects using NODE library and return cache
---@param frameObjects table Array of frame objects to scan
---@return table|nil cache NODE library cache array, or nil on failure
function NavigationGraph:_ScanNodesFromFrames(frameObjects)
	if not frameObjects or #frameObjects == 0 then
		CPAPI.Log('ERROR: No frame objects provided for scanning')
		return nil
	end
	
	-- Get NODE library
	local NODE = LibStub('ConsolePortNode')
	if not NODE then
		CPAPI.Log('ERROR: ConsolePortNode library not available')
		return nil
	end
	
	-- Use NODE() to scan all visible interactive elements
	-- NODE() returns cache: array of {node, super, object, level, ...}
	local cache = NODE(unpack(frameObjects))
	if not cache then
		CPAPI.Log('ERROR: NODE library returned nil cache')
		return nil
	end
	
	if type(cache) ~= 'table' or #cache == 0 then
		CPAPI.Log('ERROR: NODE library returned empty or invalid cache')
		return nil
	end
	
	CPAPI.Log('NODE library returned %d cache items', #cache)
	return cache
end

---Build node array with positions from NODE cache
---@param cache table NODE library cache array
---@return boolean success True if nodes built successfully
function NavigationGraph:_BuildNodeArray(cache)
	if not cache or #cache == 0 then
		CPAPI.Log('ERROR: No cache provided for node building')
		return false
	end
	
	local NODE = LibStub('ConsolePortNode')
	if not NODE then
		CPAPI.Log('ERROR: ConsolePortNode library not available for node building')
		return false
	end
	
	local nodeCount = 0
	
	-- Build node array with positions
	for index, cacheItem in ipairs(cache) do
		-- Validate cache item structure
		if not cacheItem then
			CPAPI.Log('WARNING: Cache item at index %d is nil, skipping', index)
		elseif type(cacheItem) ~= 'table' then
			CPAPI.Log('WARNING: Cache item at index %d is not a table, skipping', index)
		else
			local node = cacheItem.node
			
			-- Validate node exists
			if not node then
				CPAPI.Log('WARNING: Cache item at index %d has no node, skipping', index)
			else
				-- Validate node visibility and relevance
				local isDrawn = NODE.IsDrawn and NODE.IsDrawn(node, cacheItem.super)
				local isRelevant = NODE.IsRelevant and NODE.IsRelevant(node)
				
				if isDrawn and isRelevant then
					-- Get node position
					if NODE.GetCenterScaled then
						local x, y = NODE.GetCenterScaled(node)
						
						-- Validate position coordinates
						if x and y and type(x) == 'number' and type(y) == 'number' then
							graph.nodes[index] = {
								node = node,
								x = x,
								y = y,
								super = cacheItem.super,
							}
							graph.nodeToIndex[node] = index
							nodeCount = nodeCount + 1
						else
							CPAPI.Log('WARNING: Node at index %d has invalid position (x=%s, y=%s)', index, tostring(x), tostring(y))
						end
					else
						CPAPI.Log('WARNING: NODE.GetCenterScaled is not available')
					end
				end
			end
		end
	end
	
	if nodeCount == 0 then
		CPAPI.Log('ERROR: No valid nodes built from cache')
		return false
	end
	
	CPAPI.Log('Built %d nodes with valid positions', nodeCount)
	return true
end

---Build directional edges for all nodes in graph
---@return boolean success True if edges built successfully
function NavigationGraph:_BuildDirectionalEdges()
	if not graph.nodes or #graph.nodes == 0 then
		CPAPI.Log('ERROR: No nodes available for edge building')
		return false
	end
	
	local NODE = LibStub('ConsolePortNode')
	if not NODE then
		CPAPI.Log('ERROR: ConsolePortNode library not available for edge building')
		return false
	end
	
	if not NODE.NavigateToBestCandidateV3 then
		CPAPI.Log('ERROR: NODE.NavigateToBestCandidateV3 is not available')
		return false
	end
	
	local edgeCount = 0
	local directions = {'UP', 'DOWN', 'LEFT', 'RIGHT'}
	
	-- Build directional edges using NODE's navigation algorithm
	-- This pre-calculates neighbors in all 4 directions
	for index, nodeData in ipairs(graph.nodes) do
		-- Validate node data
		if not nodeData then
			CPAPI.Log('WARNING: Node data at index %d is nil, skipping edges', index)
		elseif type(nodeData) ~= 'table' then
			CPAPI.Log('WARNING: Node data at index %d is not a table, skipping edges', index)
		else
			-- Initialize edge entry for this node
			if not graph.edges[index] then
				graph.edges[index] = {
					up = nil,
					down = nil,
					left = nil,
					right = nil,
				}
			end
			
			-- Find best candidates in each direction using NODE library
			for _, dir in ipairs(directions) do
				-- Create a synthetic cache item for the current node
				local currentCacheItem = {
					node = nodeData.node,
					super = nodeData.super,
					x = nodeData.x,
					y = nodeData.y,
				}
				
				-- Use NODE's navigation algorithm to find neighbor
				local neighborCacheItem = NODE.NavigateToBestCandidateV3(currentCacheItem, dir)
				
				-- Validate neighbor result
				if neighborCacheItem and type(neighborCacheItem) == 'table' then
					local neighborNode = neighborCacheItem.node
					
					if neighborNode then
						-- Look up the index of the neighbor node
						local neighborIndex = graph.nodeToIndex[neighborNode]
						
						if neighborIndex and type(neighborIndex) == 'number' then
							local dirKey = dir:lower()
							graph.edges[index][dirKey] = neighborIndex
							edgeCount = edgeCount + 1
						end
					end
				end
			end
		end
	end
	
	CPAPI.Log('Calculated %d directional edges', edgeCount)
	return true
end

---Build navigation graph from visible frames
---Orchestrates the graph building process by calling helper methods
---@param frames table Array of UI frame names or frame objects
---@return boolean success True if graph built successfully
function NavigationGraph:BuildGraph(frames)
	CPAPI.Log('Building navigation graph from %d input frames', frames and #frames or 0)
	
	-- Clear old graph
	graph.nodes = {}
	graph.nodeToIndex = {}
	graph.edges = {}
	
	-- Step 1: Validate and convert frames to visible frame objects
	local frameObjects = self:_ValidateAndConvertFrames(frames)
	if not frameObjects then
		CPAPI.Log('ERROR: Failed to build graph - no valid frames')
		return false
	end
	
	-- Step 2: Scan frames using NODE library
	local cache = self:_ScanNodesFromFrames(frameObjects)
	if not cache then
		CPAPI.Log('ERROR: Failed to build graph - NODE scan failed')
		return false
	end
	
	-- Step 3: Build node array with positions
	if not self:_BuildNodeArray(cache) then
		CPAPI.Log('ERROR: Failed to build graph - node array building failed')
		return false
	end
	
	-- Step 4: Build directional edges
	if not self:_BuildDirectionalEdges() then
		CPAPI.Log('ERROR: Failed to build graph - edge building failed')
		return false
	end
	
	-- Mark graph as valid
	graph.isDirty = false
	graph.lastBuildTime = GetTime()
	
	CPAPI.Log('Graph built successfully: %d nodes, %d edges', #graph.nodes, self:_CountEdges())
	return true
end

---Mark graph as stale, will rebuild on next access
function NavigationGraph:InvalidateGraph()
	graph.isDirty = true
	CPAPI.Log('Graph invalidated, will rebuild on next access (had %d nodes)', #graph.nodes)
end

---Get current graph state (for testing/debugging)
---@return table Graph containing nodes and edges
function NavigationGraph:GetGraph()
	return graph
end

---Check if graph is valid and has nodes
---@return boolean True if graph has nodes and not dirty
function NavigationGraph:IsValid()
	return #graph.nodes > 0 and not graph.isDirty
end

---------------------------------------------------------------
-- Public API: Node Lookup
---------------------------------------------------------------

---Get directional neighbors for a node index
---@param index number Node index
---@return table {up, down, left, right} neighbor indices (or nil if no neighbor)
function NavigationGraph:GetNodeEdges(index)
	if not graph.edges[index] then
		return {up = nil, down = nil, left = nil, right = nil}
	end
	return graph.edges[index]
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
	if graph.nodes[index] then
		return graph.nodes[index].node
	end
	return nil
end

---Get position of a node by index
---@param index number Node index
---@return number|nil x Scaled center X coordinate, or nil if not found
---@return number|nil y Scaled center Y coordinate
function NavigationGraph:GetNodePosition(index)
	if graph.nodes[index] then
		return graph.nodes[index].x, graph.nodes[index].y
	end
	return nil, nil
end

---Get total node count in graph
---@return number Count of nodes
function NavigationGraph:GetNodeCount()
	return #graph.nodes
end

---Get the first (topmost) valid node index
---@return number|nil Index of first node, or nil if no nodes
function NavigationGraph:GetFirstNodeIndex()
	if #graph.nodes > 0 then
		return 1
	end
	return nil
end

---------------------------------------------------------------
-- Secure Attribute Export
---------------------------------------------------------------

---Export navigation graph to secure attributes on a frame
---Stores directional edges as secure attributes for snippet-based navigation
---@param frame table Secure frame to store attributes on (typically Driver)
---@return boolean success True if export succeeded
function NavigationGraph:ExportToSecureFrame(frame)
	if not frame then
		CPAPI.Log('ERROR: No frame provided for graph export')
		return false
	end
	
	if InCombatLockdown() then
		CPAPI.Log('ERROR: Cannot export graph during combat')
		return false
	end
	
	if #graph.nodes == 0 then
		CPAPI.Log('ERROR: Cannot export empty graph')
		return false
	end
	
	-- Store node count
	frame:SetAttribute('navGraphNodeCount', #graph.nodes)
	
	-- Store directional edges for each node
	-- Format: navGraphNode<index>Up/Down/Left/Right = <neighborIndex>
	for index, edges in pairs(graph.edges) do
		frame:SetAttribute(('navGraphNode%dUp'):format(index), edges.up)
		frame:SetAttribute(('navGraphNode%dDown'):format(index), edges.down)
		frame:SetAttribute(('navGraphNode%dLeft'):format(index), edges.left)
		frame:SetAttribute(('navGraphNode%dRight'):format(index), edges.right)
	end
	
	-- Store current node index (initialize to first node)
	frame:SetAttribute('navGraphCurrentIndex', 1)
	
	CPAPI.Log('Graph exported to secure frame: %d nodes', #graph.nodes)
	return true
end

---------------------------------------------------------------
-- Private Helpers
---------------------------------------------------------------

---Count total edges in graph (for logging)
---@return number Total edges
function NavigationGraph:_CountEdges()
	local count = 0
	for _, edges in pairs(graph.edges) do
		for _, neighbor in pairs(edges) do
			if neighbor then count = count + 1 end
		end
	end
	return count
end

---Validate graph structure (debug helper)
---@return boolean True if all edges point to valid nodes
---@return string|nil Error message if validation fails
function NavigationGraph:_ValidateGraph()
	for index, edges in pairs(graph.edges) do
		if not graph.nodes[index] then
			return false, ('Edge index %d has no node'):format(index)
		end
		for dir, neighborIndex in pairs(edges) do
			if neighborIndex and not graph.nodes[neighborIndex] then
				return false, ('Edge %d.%s points to invalid node %d'):format(index, dir, neighborIndex)
			end
		end
	end
	return true
end

---------------------------------------------------------------
-- Return public module
---------------------------------------------------------------
return NavigationGraph
