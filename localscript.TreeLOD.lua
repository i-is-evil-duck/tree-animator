
--==============================================================
-- 🌲 TREE LOD MANAGER
-- StarterPlayer > StarterPlayerScripts > TreeLOD
--
-- CLIENT-SIDE ANIMATION SYSTEM
-- Independent LOD for every player.
--==============================================================


--==============================================================
-- CONFIGURATION
--==============================================================

local TREE_ANIMATIONS = {

	Tree1 = {
		"rbxassetid://73003979189774",
		"rbxassetid://97264839801380",
		"rbxassetid://119473409039419",
	},

	Tree3 = {
		"rbxassetid://89584433046787",
	},

	Tree4 = {
		"rbxassetid://95456139043170",
		"rbxassetid://85156670867412",
	},

}

local MIN_DELAY = 0.5
local MAX_DELAY = 2.5

local CROSSFADE_TIME = 0.3

local MIN_SPEED = 0.8
local MAX_SPEED = 1.2

-- LOD
local CLUSTER_SIZE = 90
local CLUSTER_RADIUS = 200
local CHECK_INTERVAL = 0.5

-- Discovery
local DISCOVERY_INTERVAL = 2

-- Debug
local DEBUG_MODE = true
local DEBUG_HEIGHT = 60

local DEBUG_COLOR = Color3.fromRGB(0, 255, 0)
local DEBUG_TRANSPARENCY = 0.8

-- Print only the first successful animation.
local DEBUG_FIRST_ANIMATION = true


--==============================================================
-- SERVICES
--==============================================================

local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local TreesFolder = workspace:WaitForChild("Trees")


--==============================================================
-- STATE
--==============================================================

local ManagedTrees = {}
local Clusters = {}
local PendingTrees = {}

local DebugParts = {}
local ActiveClusters = {}

local Running = true

local LastStats = {
	Registered = 0,
	Active = 0,
	Playing = 0,
	Clusters = 0,
}

local firstAnimationReported = false


--==============================================================
-- UTILITIES
--==============================================================

local function getClusterCoordinates(position)

	local x = math.floor(position.X / CLUSTER_SIZE)
	local z = math.floor(position.Z / CLUSTER_SIZE)

	return x, z

end


local function getClusterKey(x, z)

	return tostring(x) .. "_" .. tostring(z)

end


local function getPlayerPosition()

	local character = LocalPlayer.Character

	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")

	if not root then
		return nil
	end

	return root.Position

end


--==============================================================
-- TREE IDENTIFICATION
--==============================================================

local function isActualTree(obj)

	if not obj:IsA("Model") then
		return false
	end

	if not TREE_ANIMATIONS[obj.Name] then
		return false
	end

	local root = obj:FindFirstChild("RootPart")

	return root ~= nil and root:IsA("BasePart")

end


--==============================================================
-- TREE REGISTRATION
--==============================================================

local function setupTree(model)

	if not model or not model.Parent then
		return false
	end

	if ManagedTrees[model] or PendingTrees[model] then
		return false
	end

	if not TREE_ANIMATIONS[model.Name] then
		return false
	end

	PendingTrees[model] = true

	-- Find RootPart.
	local root = model:FindFirstChild("RootPart")

	if not root then
		root = model:WaitForChild("RootPart", 20)
	end

	if not model.Parent then
		PendingTrees[model] = nil
		return false
	end

	if not root or not root:IsA("BasePart") then
		PendingTrees[model] = nil
		return false
	end

	-- Find server-created controller.
	local controller =
		model:FindFirstChildOfClass("AnimationController")

	if not controller then
		controller = model:WaitForChild(
			"AnimationController",
			20
		)
	end

	if not controller or not model.Parent then
		PendingTrees[model] = nil
		return false
	end

	-- Find replicated Animator.
	local animator =
		controller:FindFirstChildOfClass("Animator")

	if not animator then
		animator = controller:WaitForChild("Animator", 20)
	end

	if not animator or not model.Parent then
		PendingTrees[model] = nil
		return false
	end

	-- Create animation instances.
	local animations = {}

	for _, id in ipairs(TREE_ANIMATIONS[model.Name]) do

		local animation = Instance.new("Animation")

		animation.AnimationId = id

		table.insert(animations, animation)

	end

	-- Calculate cluster.
	local clusterX, clusterZ =
		getClusterCoordinates(root.Position)

	local clusterKey = getClusterKey(clusterX, clusterZ)

	-- Tree data.
	local data = {

		Model = model,

		RootPart = root,

		Animator = animator,

		Animations = animations,

		ClusterKey = clusterKey,

		IsActive = false,

		ActiveTrack = nil,

		PlayToken = 0,

	}

	ManagedTrees[model] = data

	PendingTrees[model] = nil

	-- Register cluster.
	Clusters[clusterKey] = Clusters[clusterKey] or {}

	table.insert(Clusters[clusterKey], data)

	return true

end


--==============================================================
-- STOP ANIMATION
--==============================================================

local function stopAnimation(data)

	data.IsActive = false

	data.PlayToken += 1

	if data.ActiveTrack then

		local track = data.ActiveTrack

		data.ActiveTrack = nil

		pcall(function()
			track:Stop(CROSSFADE_TIME)
			track:Destroy()
		end)

	end

end


--==============================================================
-- PLAY RANDOM ANIMATION
--==============================================================

local playRandomAnimation

playRandomAnimation = function(data)

	if not data.IsActive then
		return
	end

	if not data.Model or not data.Model.Parent then
		return
	end

	if not data.Animator or not data.Animator.Parent then
		return
	end

	if #data.Animations == 0 then
		return
	end

	-- Select random animation.
	local animation = data.Animations[
	math.random(1, #data.Animations)
	]

	-- Load animation.
	local success, track = pcall(function()

		return data.Animator:LoadAnimation(animation)

	end)

	if not success or not track then

		warn(
			"[TreeLOD] Failed to load:",
			animation.AnimationId,
			data.Model:GetFullName()
		)

		return

	end

	-- Unique playback token.
	data.PlayToken += 1

	local token = data.PlayToken

	data.ActiveTrack = track

	track.Looped = false

	local speed =
		MIN_SPEED
		+ math.random() * (MAX_SPEED - MIN_SPEED)

	track:AdjustSpeed(speed)

	-- Play locally.
	track:Play(CROSSFADE_TIME)

	if DEBUG_FIRST_ANIMATION and not firstAnimationReported then

		firstAnimationReported = true

		print(
			"[TreeLOD] First animation started:",
			data.Model:GetFullName(),
			animation.AnimationId
		)

	end

	-- When animation ends.
	track.Stopped:Once(function()

		if data.ActiveTrack == track then
			data.ActiveTrack = nil
		end

		if data.PlayToken ~= token then
			return
		end

		if not data.IsActive then
			return
		end

		task.wait(
			MIN_DELAY
				+ math.random() * (MAX_DELAY - MIN_DELAY)
		)

		if not data.IsActive then
			return
		end

		if data.PlayToken ~= token then
			return
		end

		if not data.Model or not data.Model.Parent then
			return
		end

		playRandomAnimation(data)

	end)

end


--==============================================================
-- REMOVE TREE
--==============================================================

local function removeTree(model)

	local data = ManagedTrees[model]

	if not data then
		PendingTrees[model] = nil
		return
	end

	stopAnimation(data)

	for _, animation in ipairs(data.Animations) do
		animation:Destroy()
	end

	local cluster = Clusters[data.ClusterKey]

	if cluster then

		for i = #cluster, 1, -1 do

			if cluster[i] == data then
				table.remove(cluster, i)
				break
			end

		end

		if #cluster == 0 then
			Clusters[data.ClusterKey] = nil
		end

	end

	ManagedTrees[model] = nil

	PendingTrees[model] = nil

end


--==============================================================
-- ACTIVE CLUSTER CALCULATION
--==============================================================

local function calculateActiveClusters(position)

	local active = {}

	local centerX, centerZ =
		getClusterCoordinates(position)

	local radiusCount = math.ceil(
		CLUSTER_RADIUS / CLUSTER_SIZE
	)

	for dx = -radiusCount, radiusCount do

		for dz = -radiusCount, radiusCount do

			local x = centerX + dx
			local z = centerZ + dz

			local clusterCenterX =
				x * CLUSTER_SIZE + CLUSTER_SIZE / 2

			local clusterCenterZ =
				z * CLUSTER_SIZE + CLUSTER_SIZE / 2

			local deltaX = clusterCenterX - position.X
			local deltaZ = clusterCenterZ - position.Z

			local distanceSquared =
				deltaX * deltaX + deltaZ * deltaZ

			if distanceSquared <= CLUSTER_RADIUS * CLUSTER_RADIUS then

				local key = getClusterKey(x, z)

				active[key] = true

			end

		end

	end

	return active

end


--==============================================================
-- DEBUG CLUSTER VISUALIZATION
-- Only creates/destroys parts when the cluster set changes.
--==============================================================

local function createDebugPart(key)

	local split = string.split(key, "_")

	local x = tonumber(split[1])
	local z = tonumber(split[2])

	if not x or not z then
		return
	end

	local part = Instance.new("Part")

	part.Name = "TreeLOD_ClusterDebug"

	part.Anchored = true

	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false

	part.CastShadow = false

	part.Material = Enum.Material.Neon

	part.Color = DEBUG_COLOR

	part.Transparency = DEBUG_TRANSPARENCY

	part.Size = Vector3.new(
		CLUSTER_SIZE,
		1,
		CLUSTER_SIZE
	)

	part.Position = Vector3.new(
		x * CLUSTER_SIZE + CLUSTER_SIZE / 2,
		DEBUG_HEIGHT,
		z * CLUSTER_SIZE + CLUSTER_SIZE / 2
	)

	part.Parent = workspace

	DebugParts[key] = part

end


local function updateDebugClusters(newClusters)

	if not DEBUG_MODE then
		return
	end

	-- Remove clusters no longer active.
	for key, part in pairs(DebugParts) do

		if not newClusters[key] then

			part:Destroy()

			DebugParts[key] = nil

		end

	end

	-- Create newly active clusters.
	for key in pairs(newClusters) do

		if not DebugParts[key] then
			createDebugPart(key)
		end

	end

end


local function clearDebugClusters()

	for key, part in pairs(DebugParts) do

		if part then
			part:Destroy()
		end

		DebugParts[key] = nil

	end

end


--==============================================================
-- UPDATE LOD
--==============================================================

local function updateLOD()

	local position = getPlayerPosition()

	if not position then

		-- Character unavailable: stop animations.
		for _, data in pairs(ManagedTrees) do

			if data.IsActive then
				stopAnimation(data)
			end

		end

		table.clear(ActiveClusters)

		clearDebugClusters()

		return

	end

	-- IMPORTANT:
	-- Recalculate from the player's CURRENT position
	-- every update. Never use the old character position.
	local newActiveClusters =
		calculateActiveClusters(position)

	-- Update visualization.
	updateDebugClusters(newActiveClusters)

	-- Store current clusters.
	ActiveClusters = newActiveClusters

	-- Statistics.
	local activeCount = 0
	local playingCount = 0
	local registeredCount = 0

	-- Activate/deactivate trees.
	for clusterKey, trees in pairs(Clusters) do

		local clusterActive = ActiveClusters[clusterKey] == true

		for i = #trees, 1, -1 do

			local data = trees[i]

			local model = data.Model

			if not model or not model.Parent then

				removeTree(model)

				continue

			end

			registeredCount += 1

			if clusterActive then

				activeCount += 1

				if not data.IsActive then

					data.IsActive = true

					playRandomAnimation(data)

				end

				if data.ActiveTrack then
					playingCount += 1
				end

			else

				if data.IsActive then
					stopAnimation(data)
				end

			end

		end

	end

	-- Save stats in a normal table.
	-- DO NOT use updateLOD.LastStats.
	LastStats.Registered = registeredCount
	LastStats.Active = activeCount
	LastStats.Playing = playingCount

	local clusterCount = 0

	for _ in pairs(ActiveClusters) do
		clusterCount += 1
	end

	LastStats.Clusters = clusterCount

end


--==============================================================
-- DISCOVERY
--==============================================================

local function scanForTrees()

	local candidates = 0
	local registered = 0
	local missingRoot = 0

	for _, obj in ipairs(TreesFolder:GetDescendants()) do

		if obj:IsA("Model") and TREE_ANIMATIONS[obj.Name] then

			candidates += 1

			local root = obj:FindFirstChild("RootPart")

			if root and root:IsA("BasePart") then

				if ManagedTrees[obj] then

					registered += 1

				elseif not PendingTrees[obj] then

					task.spawn(function()
						setupTree(obj)
					end)

				end

			else

				missingRoot += 1

			end

		end

	end

	return candidates, registered, missingRoot

end


--==============================================================
-- NEW TREES
--==============================================================

TreesFolder.DescendantAdded:Connect(function(obj)

	if not obj:IsA("Model") then
		return
	end

	if not TREE_ANIMATIONS[obj.Name] then
		return
	end

	task.spawn(function()

		local root = obj:FindFirstChild("RootPart")

		if not root then
			root = obj:WaitForChild("RootPart", 20)
		end

		if root and root:IsA("BasePart") and obj.Parent then
			setupTree(obj)
		end

	end)

end)


--==============================================================
-- REMOVED TREES
--==============================================================

TreesFolder.DescendantRemoving:Connect(function(obj)

	if ManagedTrees[obj] or PendingTrees[obj] then
		removeTree(obj)
	end

end)


--==============================================================
-- CHARACTER RESPAWN
--==============================================================

LocalPlayer.CharacterAdded:Connect(function()

	-- Wait for new HumanoidRootPart.
	task.wait(0.5)

	-- Next LOD update recalculates position automatically.
	updateLOD()

end)


--==============================================================
-- START DISCOVERY
--==============================================================

print("[TreeLOD] Initializing trees...")

task.spawn(function()

	while Running do

		local candidates, registered, missingRoot =
			scanForTrees()

		print(
			"[TreeLOD DISCOVERY] Candidates:",
			candidates,
			"| Registered:",
			registered,
			"| Missing RootPart:",
			missingRoot
		)

		task.wait(DISCOVERY_INTERVAL)

	end

end)


--==============================================================
-- MAIN LOD LOOP
--==============================================================

print("[TreeLOD] Client-side animation manager started!")

task.spawn(function()

	while Running do

		local success, err = pcall(updateLOD)

		if not success then

			warn(
				"[TreeLOD] LOD update error:",
				err
			)

		end

		task.wait(CHECK_INTERVAL)

	end

end)


--==============================================================
-- DEBUG STATISTICS
--==============================================================

task.spawn(function()

	while Running do

		task.wait(5)

		if DEBUG_MODE then

			print(
				"[TreeLOD STATS]",
				"Registered:", LastStats.Registered,
				"| Active:", LastStats.Active,
				"| Playing:", LastStats.Playing,
				"| Active Clusters:", LastStats.Clusters
			)

		end

	end

end)


--==============================================================
-- CLEANUP
--==============================================================

script.Destroying:Connect(function()

	Running = false

	for _, data in pairs(ManagedTrees) do
		stopAnimation(data)

		for _, animation in ipairs(data.Animations) do
			animation:Destroy()
		end
	end

	table.clear(ManagedTrees)
	table.clear(Clusters)

	clearDebugClusters()

end)
