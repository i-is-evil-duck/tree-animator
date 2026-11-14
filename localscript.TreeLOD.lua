
--==============================================================
-- TREE LOD MANAGER
-- StarterPlayer > StarterPlayerScripts > TreeLOD
--
-- THREE LEVELS:
-- 1. Active 3D       - Full trees + animations
-- 2. Inactive 3D     - Full trees, no animations
-- 3. Inactive 2D     - Billboard impostors, original trees hidden
--
-- Camera culling:
-- Active clusters behind camera have their animations paused.
--
-- All visual changes are LOCAL to each player.
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

-- Animation settings
local MIN_DELAY = 0.5
local MAX_DELAY = 2.5

local CROSSFADE_TIME = 0.3

local MIN_SPEED = 0.8
local MAX_SPEED = 1.2

-- Cluster settings
local CLUSTER_SIZE = 90

-- Active 3D distance
local ACTIVE_RADIUS = 200

-- Switch from inactive 3D to 2D
local BILLBOARD_DISTANCE = 400

-- Switch back from 2D to 3D
-- This hysteresis prevents flickering.
local BILLBOARD_RETURN_DISTANCE = 360

local CHECK_INTERVAL = 0.5
local DISCOVERY_INTERVAL = 2

-- Billboard settings
local BILLBOARD_IMAGE = "rbxassetid://14145202403"

-- Approximate image width / height.
local BILLBOARD_ASPECT_RATIO = 0.55

-- Billboard height limits in screen pixels.
local BILLBOARD_MIN_HEIGHT = 2
local BILLBOARD_MAX_HEIGHT = 180

-- Maximum distance at which billboards are displayed.
local BILLBOARD_MAX_DISTANCE = 1200

-- Camera culling
local CAMERA_CULLING_ENABLED = true

-- Extra margin around the viewport.
local CAMERA_SCREEN_MARGIN = 100

-- Debug
local DEBUG_MODE = true
local DEBUG_HEIGHT = 60

local DEBUG_COLOR = Color3.fromRGB(0, 255, 0)
local DEBUG_TRANSPARENCY = 0.8

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

local Running = true

local LastStats = {
	Registered = 0,
	Active = 0,
	Playing = 0,

	ActiveClusters = 0,
	Inactive3DClusters = 0,
	BillboardClusters = 0,

	PausedTrees = 0,
	BillboardTrees = 0,
}

local firstAnimationReported = false


--==============================================================
-- CLUSTER UTILITIES
--==============================================================

local function getClusterCoordinates(position)

	local x = math.floor(position.X / CLUSTER_SIZE)
	local z = math.floor(position.Z / CLUSTER_SIZE)

	return x, z

end


local function getClusterKey(x, z)

	return tostring(x) .. "_" .. tostring(z)

end


local function getClusterCenter(key)

	local split = string.split(key, "_")

	local x = tonumber(split[1])
	local z = tonumber(split[2])

	if not x or not z then
		return Vector3.zero
	end

	return Vector3.new(
		x * CLUSTER_SIZE + CLUSTER_SIZE / 2,
		0,
		z * CLUSTER_SIZE + CLUSTER_SIZE / 2
	)

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


local function getClusterDistance(key, position)

	local center = getClusterCenter(key)

	local dx = center.X - position.X
	local dz = center.Z - position.Z

	return math.sqrt(dx * dx + dz * dz)

end


--==============================================================
-- CAMERA VISIBILITY
--==============================================================

local function isClusterOnScreen(key)

	if not CAMERA_CULLING_ENABLED then
		return true
	end

	local camera = workspace.CurrentCamera

	if not camera then
		return true
	end

	local center = getClusterCenter(key)

	-- Approximate the cluster as a sphere.
	local clusterRadius = math.sqrt(
		(CLUSTER_SIZE / 2) ^ 2
			+ (CLUSTER_SIZE / 2) ^ 2
	)

	local worldCenter = Vector3.new(
		center.X,
		DEBUG_HEIGHT,
		center.Z
	)

	local screenPosition, onScreen =
		camera:WorldToViewportPoint(worldCenter)

	local depth = screenPosition.Z

	-- Behind camera.
	if depth <= -clusterRadius then
		return false
	end

	-- If the center is behind the camera but the cluster
	-- could still overlap the camera, avoid incorrectly
	-- culling it.
	if depth <= 0 then
		return true
	end

	local viewport = camera.ViewportSize

	local focalLength =
		viewport.Y / (
			2 * math.tan(math.rad(camera.FieldOfView / 2))
		)

	local projectedRadius =
		(focalLength * clusterRadius)
		/ math.max(depth - clusterRadius, 1)

	local margin = CAMERA_SCREEN_MARGIN + projectedRadius

	local visible =
		screenPosition.X >= -margin
		and screenPosition.X <= viewport.X + margin
		and screenPosition.Y >= -margin
		and screenPosition.Y <= viewport.Y + margin

	return visible

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
-- LOCAL TREE VISIBILITY
--==============================================================

local function setTree3DVisible(data, visible)

	for _, part in ipairs(data.Parts) do

		if part and part.Parent then

			if visible then

				part.LocalTransparencyModifier =
					data.OriginalTransparency[part] or 0

			else

				part.LocalTransparencyModifier = 1

			end

		end

	end

end


--==============================================================
-- BILLBOARD CREATION
--==============================================================

local function createBillboard(data)

	if data.Billboard then
		return data.Billboard
	end

	local billboard = Instance.new("BillboardGui")

	billboard.Name = "TreeLOD_Billboard"

	billboard.Adornee = data.RootPart

	billboard.AlwaysOnTop = false

	billboard.LightInfluence = 0

	billboard.MaxDistance = BILLBOARD_MAX_DISTANCE

	billboard.Size = UDim2.fromOffset(40, 80)

	billboard.StudsOffset = Vector3.new(
		0,
		data.TreeHeight / 2,
		0
	)

	billboard.Enabled = false

	local image = Instance.new("ImageLabel")

	image.Name = "TreeImage"

	image.BackgroundTransparency = 1

	image.BorderSizePixel = 0

	image.Size = UDim2.fromScale(1, 1)

	image.Position = UDim2.fromScale(0, 0)

	image.Image = BILLBOARD_IMAGE

	image.ScaleType = Enum.ScaleType.Fit

	image.ResampleMode = Enum.ResamplerMode.Default

	image.Parent = billboard

	billboard.Parent = data.Model

	data.Billboard = billboard

	return billboard

end


--==============================================================
-- BILLBOARD SCREEN SIZE
--==============================================================

local function updateBillboardSize(data, camera)

	if not data.Billboard or not data.Billboard.Enabled then
		return
	end

	local distance =
		(camera.CFrame.Position - data.RootPart.Position).Magnitude

	if distance <= 0 then
		return
	end

	if distance > BILLBOARD_MAX_DISTANCE then
		data.Billboard.Enabled = false
		return
	end

	local viewport = camera.ViewportSize

	local focalLength =
		viewport.Y / (
			2 * math.tan(math.rad(camera.FieldOfView / 2))
		)

	-- Estimate the screen height of the original tree.
	local pixelHeight =
		(data.TreeHeight * focalLength) / distance

	pixelHeight = math.clamp(
		pixelHeight,
		BILLBOARD_MIN_HEIGHT,
		BILLBOARD_MAX_HEIGHT
	)

	local pixelWidth =
		pixelHeight * BILLBOARD_ASPECT_RATIO

	data.Billboard.Size = UDim2.fromOffset(
		pixelWidth,
		pixelHeight
	)

end


--==============================================================
-- TREE LOD TRANSITIONS
--==============================================================

local function setTreeLOD(data, newLOD)

	if data.LOD == newLOD then
		return
	end

	data.LOD = newLOD

	if newLOD == "Active3D" then

		-- Restore the original 3D tree.
		setTree3DVisible(data, true)

		if data.Billboard then
			data.Billboard.Enabled = false
		end

	elseif newLOD == "Inactive3D" then

		-- Keep the 3D tree visible but stop animations.
		setTree3DVisible(data, true)

		if data.Billboard then
			data.Billboard.Enabled = false
		end

	elseif newLOD == "Inactive2D" then

		-- Hide the original 3D tree locally.
		setTree3DVisible(data, false)

		-- Create the billboard once, then reuse it.
		local billboard = createBillboard(data)

		billboard.Enabled = true

	end

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

	-- Find server-created AnimationController.
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

	-- Find Animator.
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

	-- Get original model parts and transparency values.
	local parts = {}
	local originalTransparency = {}

	for _, obj in ipairs(model:GetDescendants()) do

		if obj:IsA("BasePart") then

			table.insert(parts, obj)

			originalTransparency[obj] =
				obj.LocalTransparencyModifier

		end

	end

	-- Estimate tree height.
	local success, extents = pcall(function()
		return model:GetExtentsSize()
	end)

	local treeHeight = 20

	if success and extents then
		treeHeight = math.max(extents.Y, 1)
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

		Paused = false,

		SavedAnimationSpeed = 1,

		LOD = "Inactive3D",

		Parts = parts,

		OriginalTransparency = originalTransparency,

		TreeHeight = treeHeight,

		Billboard = nil,

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

	data.Paused = false

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
-- PAUSE / RESUME ANIMATION
--==============================================================

local function pauseAnimation(data)

	if not data.IsActive then
		return
	end

	if data.Paused then
		return
	end

	if not data.ActiveTrack then
		return
	end

	local track = data.ActiveTrack

	pcall(function()

		data.SavedAnimationSpeed = track.Speed

		track:AdjustSpeed(0)

		data.Paused = true

	end)

end


local function resumeAnimation(data)

	if not data.IsActive then
		return
	end

	if not data.Paused then
		return
	end

	if not data.ActiveTrack then
		data.Paused = false
		return
	end

	local track = data.ActiveTrack

	pcall(function()

		track:AdjustSpeed(
			data.SavedAnimationSpeed or 1
		)

		data.Paused = false

	end)

end


--==============================================================
-- PLAY RANDOM ANIMATION
--==============================================================

local playRandomAnimation

playRandomAnimation = function(data)

	if not data.IsActive then
		return
	end

	if data.Paused then
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

	data.SavedAnimationSpeed = speed

	track:AdjustSpeed(speed)

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

		if data.Paused then
			return
		end

		task.wait(
			MIN_DELAY
				+ math.random() * (MAX_DELAY - MIN_DELAY)
		)

		if not data.IsActive then
			return
		end

		if data.Paused then
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

	-- Restore original tree visibility.
	setTree3DVisible(data, true)

	if data.Billboard then
		data.Billboard:Destroy()
		data.Billboard = nil
	end

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
-- CLUSTER DISTANCE STATE
--==============================================================

local function getClusterLOD(clusterKey, distance, previousLOD)

	-- Active 3D always takes priority.
	if distance <= ACTIVE_RADIUS then
		return "Active3D"
	end

	-- Hysteresis for clusters already using billboards.
	if previousLOD == "Inactive2D" then

		if distance <= BILLBOARD_RETURN_DISTANCE then
			return "Inactive3D"
		end

		return "Inactive2D"

	end

	-- Switch to billboard mode at the far distance.
	if distance >= BILLBOARD_DISTANCE then
		return "Inactive2D"
	end

	return "Inactive3D"

end


--==============================================================
-- DEBUG CLUSTER VISUALIZATION
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

	local camera = workspace.CurrentCamera

	if not position then

		-- Character unavailable: stop animations.
		for _, data in pairs(ManagedTrees) do

			if data.IsActive then
				stopAnimation(data)
			end

			if data.LOD == "Inactive2D" then
				setTreeLOD(data, "Inactive3D")
			end

		end

		clearDebugClusters()

		return

	end

	local activeClusters = {}

	local activeCount = 0
	local playingCount = 0
	local registeredCount = 0

	local activeClusterCount = 0
	local inactive3DCount = 0
	local billboardClusterCount = 0

	local pausedCount = 0
	local billboardTreeCount = 0

	-- Process every registered cluster.
	for clusterKey, trees in pairs(Clusters) do

		local distance =
			getClusterDistance(clusterKey, position)

		local previousLOD = trees[1] and trees[1].ClusterLOD

		local clusterLOD = getClusterLOD(
			clusterKey,
			distance,
			previousLOD
		)

		-- Determine whether the cluster is visible to the camera.
		local cameraVisible = true

		if clusterLOD == "Active3D" and camera then
			cameraVisible = isClusterOnScreen(clusterKey)
		end

		if clusterLOD == "Active3D" then

			activeClusterCount += 1

			activeClusters[clusterKey] = true

		elseif clusterLOD == "Inactive3D" then

			inactive3DCount += 1

		elseif clusterLOD == "Inactive2D" then

			billboardClusterCount += 1

		end

		-- Apply the cluster state to every tree.
		for i = #trees, 1, -1 do

			local data = trees[i]

			local model = data.Model

			if not model or not model.Parent then

				removeTree(model)

				continue

			end

			registeredCount += 1

			data.ClusterLOD = clusterLOD

			setTreeLOD(data, clusterLOD)

			if clusterLOD == "Active3D" then

				activeCount += 1

				if not data.IsActive then

					data.IsActive = true

					data.Paused = false

					playRandomAnimation(data)

				end

				if cameraVisible then

					-- Resume animations when visible.
					resumeAnimation(data)

				else

					-- Pause animations behind the camera.
					pauseAnimation(data)

				end

				if data.Paused then
					pausedCount += 1
				end

				if data.ActiveTrack then
					playingCount += 1
				end

			else

				-- Inactive clusters do not animate.
				if data.IsActive then
					stopAnimation(data)
				end

				if clusterLOD == "Inactive2D" then
					billboardTreeCount += 1
				end

			end

		end

	end

	-- Update debug visualization.
	updateDebugClusters(activeClusters)

	-- Update billboard screen sizes.
	if camera then

		for _, data in pairs(ManagedTrees) do

			if data.LOD == "Inactive2D" then

				if data.Billboard then

					data.Billboard.Enabled = true

					updateBillboardSize(data, camera)

				end

			end

		end

	end

	-- Save stats.
	LastStats.Registered = registeredCount
	LastStats.Active = activeCount
	LastStats.Playing = playingCount

	LastStats.ActiveClusters = activeClusterCount
	LastStats.Inactive3DClusters = inactive3DCount
	LastStats.BillboardClusters = billboardClusterCount

	LastStats.PausedTrees = pausedCount
	LastStats.BillboardTrees = billboardTreeCount

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

	task.wait(0.5)

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
			"[TreeLOD DISCOVERY]",
			"Candidates:", candidates,
			"| Registered:", registered,
			"| Missing RootPart:", missingRoot
		)

		task.wait(DISCOVERY_INTERVAL)

	end

end)


--==============================================================
-- MAIN LOD LOOP
--==============================================================

print("[TreeLOD] Three-level LOD manager started!")

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

				"| Active Clusters:", LastStats.ActiveClusters,
				"| Inactive 3D:", LastStats.Inactive3DClusters,
				"| Billboard Clusters:", LastStats.BillboardClusters,

				"| Paused Trees:", LastStats.PausedTrees,
				"| Billboard Trees:", LastStats.BillboardTrees
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

		-- Restore original 3D visibility.
		setTree3DVisible(data, true)

		if data.Billboard then
			data.Billboard:Destroy()
		end

		for _, animation in ipairs(data.Animations) do
			animation:Destroy()
		end

	end

	table.clear(ManagedTrees)
	table.clear(Clusters)
	table.clear(PendingTrees)

	clearDebugClusters()

end)
