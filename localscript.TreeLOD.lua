--==============================================================
-- TREE LOD MANAGER
-- StarterPlayer > StarterPlayerScripts > TreeLOD
--
-- THREE LEVELS:
-- 1. Active 3D       - Animated trees
-- 2. Inactive 3D     - Static 3D trees
-- 3. Inactive 2D     - Orange mesh-plane impostors
--
-- No BillboardGui code is used.
-- The replacement plane faces the camera and matches the
-- original tree's measured width and height.
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

--==============================================================
-- ANIMATION SETTINGS
--==============================================================

local MIN_DELAY = 0.5
local MAX_DELAY = 2.5

local CROSSFADE_TIME = 0.3

local MIN_SPEED = 0.8
local MAX_SPEED = 1.2

--==============================================================
-- LOD SETTINGS
--==============================================================

local CLUSTER_SIZE = 90

local ACTIVE_RADIUS = 200

local PLANE_DISTANCE = 400

local PLANE_RETURN_DISTANCE = 360

local CHECK_INTERVAL = 0.5

local DISCOVERY_INTERVAL = 2

--==============================================================
-- MESH PLANE IMPOSTOR SETTINGS
--
-- For now, the script creates an orange plane.
--
-- Later, put your Blender-created MeshPart in:
-- ReplicatedStorage > TreeImpostorPlane
--
-- The MeshPart should be upright, with:
-- Local X = width
-- Local Y = height
--
-- The script will resize it to match each tree.
--==============================================================

local PLANE_TEMPLATE_NAME = "TreeImpostorPlane"

-- nil means use the measured width of each tree.
local PLANE_ASPECT_RATIO = nil

local PLANE_THICKNESS = 0.05

-- Orange tree-height debug markers are toggled with K.
local PLANE_DEBUG_MARKER_ENABLED = true
local PLANE_MARKERS_VISIBLE = false

--==============================================================
-- CAMERA CULLING
--==============================================================

local CAMERA_CULLING_ENABLED = true

local CAMERA_SCREEN_MARGIN = 100

--==============================================================
-- DEBUG SETTINGS
--==============================================================

local DEBUG_MODE = true

local DEBUG_HEIGHT = 60

local DEBUG_COLOR = Color3.fromRGB(0, 255, 0)

local DEBUG_TRANSPARENCY = 0.8

local DEBUG_FIRST_ANIMATION = true

-- Debug HUD settings.
local DEBUG_UI_ENABLED = true
local DEBUG_UI_DEFAULT_VISIBLE = true
local DEBUG_UI_TOGGLE_KEY = Enum.KeyCode.Semicolon
local DEBUG_UI_UPDATE_INTERVAL = 0.5

--==============================================================
-- SERVICES
--==============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local TreesFolder = workspace:WaitForChild("Trees")

--==============================================================
-- STATE
--==============================================================

local ManagedTrees = {}
local Clusters = {}
local ClusterStates = {}
local PendingTrees = {}

local DebugParts = {}
local ClusterVisualizationEnabled = true

local ActivePlanes = {}

local LODLocked = false
local LockedClusterStates = {}

local Running = true
local firstAnimationReported = false

local LastStats = {

	Registered = 0,
	Active = 0,
	Playing = 0,

	ActiveClusters = 0,
	Inactive3DClusters = 0,
	PlaneClusters = 0,

	PausedTrees = 0,
	PlaneTrees = 0,
	PlaneFallbacks = 0,
	PlaneFailures = 0,

	Candidates = 0,
	MissingRoot = 0,
	Pending = 0,

}

local PlaneFailureCount = 0

local DebugUI = nil
local DebugPanel = nil
local DebugToggleButton = nil
local DebugLabels = {}

local DebugUIVisible = DEBUG_UI_DEFAULT_VISIBLE
local LastDebugUIUpdate = 0

--==============================================================
-- DEBUG HUD
--==============================================================

local function createDebugLabel(parent, name, y, height, text, textSize, color)

	local label = Instance.new("TextLabel")

	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0

	label.Position = UDim2.fromOffset(10, y)
	label.Size = UDim2.new(1, -20, 0, height)

	label.Font = Enum.Font.Code
	label.Text = text

	label.TextColor3 = color or Color3.fromRGB(225, 235, 245)
	label.TextSize = textSize or 13

	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center

	label.Parent = parent

	return label

end

local function setDebugUIVisible(visible)

	DebugUIVisible = visible

	if DebugPanel then
		DebugPanel.Visible = visible
	end

	if DebugToggleButton then
		DebugToggleButton.Text = visible and "Hide Tree HUD [;]" or "Show Tree HUD [;]"
	end

end

local function createDebugUI()

	if not DEBUG_UI_ENABLED then
		return
	end

	local playerGui = LocalPlayer:WaitForChild("PlayerGui")

	local oldGui = playerGui:FindFirstChild("TreeLOD_DebugUI")

	if oldGui then
		oldGui:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")

	screenGui.Name = "TreeLOD_DebugUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 20

	screenGui.Parent = playerGui

	DebugUI = screenGui

	local toggle = Instance.new("TextButton")

	toggle.Name = "ToggleButton"
	toggle.Position = UDim2.fromOffset(10, 8)
	toggle.Size = UDim2.fromOffset(170, 28)

	toggle.BackgroundColor3 = Color3.fromRGB(28, 35, 45)
	toggle.BackgroundTransparency = 0.08
	toggle.BorderSizePixel = 0

	toggle.Font = Enum.Font.Code
	toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
	toggle.TextSize = 12

	toggle.Parent = screenGui

	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, 5)
	toggleCorner.Parent = toggle

	DebugToggleButton = toggle

	toggle.Activated:Connect(function()
		setDebugUIVisible(not DebugUIVisible)
	end)

	local panel = Instance.new("Frame")

	panel.Name = "StatsPanel"
	panel.Position = UDim2.fromOffset(10, 42)
	panel.Size = UDim2.fromOffset(310, 310)

	panel.BackgroundColor3 = Color3.fromRGB(15, 20, 28)
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0

	panel.Parent = screenGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 6)
	panelCorner.Parent = panel

	DebugPanel = panel

	createDebugLabel(
		panel,
		"Title",
		7,
		22,
		"TREE LOD DEBUG",
		15,
		Color3.fromRGB(100, 220, 140)
	)

	local divider = Instance.new("Frame")

	divider.Position = UDim2.fromOffset(10, 32)
	divider.Size = UDim2.new(1, -20, 0, 1)

	divider.BackgroundColor3 = Color3.fromRGB(75, 90, 105)
	divider.BorderSizePixel = 0

	divider.Parent = panel

	local rows = {

		{"Registration", "Registered: 0 | Candidates: 0"},
		{"Discovery", "Pending: 0 | Missing RootPart: 0"},
		{"ActiveTrees", "Active trees: 0 | Playing: 0"},
		{"Paused", "Camera-paused animations: 0"},
		{"Clusters", "Active: 0 | Static 3D: 0 | Plane LOD: 0"},
		{"Planes", "Mesh planes: 0 | Fallbacks: 0"},
		{"Failures", "Mesh plane failures: 0"},
		{"Distance", "Active: 0-200 | Plane: 400+"},
		{"ToggleHelp", ";: HUD | ': clusters | K: markers | L: lock"},

	}

	for index, row in ipairs(rows) do

		local y = 40 + (index - 1) * 28

		DebugLabels[row[1]] = createDebugLabel(
			panel,
			row[1],
			y,
			25,
			row[2],
			index == #rows and 11 or 12,
			index == #rows and Color3.fromRGB(160, 175, 190) or nil
		)

	end

	setDebugUIVisible(DEBUG_UI_DEFAULT_VISIBLE)

end

local function updateDebugUI(force)

	if not DEBUG_UI_ENABLED or not DebugLabels.Registration then
		return
	end

	local now = os.clock()

	if not force and now - LastDebugUIUpdate < DEBUG_UI_UPDATE_INTERVAL then
		return
	end

	LastDebugUIUpdate = now

	DebugLabels.Registration.Text = string.format(
		"Registered: %d | Candidates: %d",
		LastStats.Registered,
		LastStats.Candidates
	)

	DebugLabels.Discovery.Text = string.format(
		"Pending: %d | Missing RootPart: %d",
		LastStats.Pending,
		LastStats.MissingRoot
	)

	DebugLabels.ActiveTrees.Text = string.format(
		"Active trees: %d | Playing: %d",
		LastStats.Active,
		LastStats.Playing
	)

	DebugLabels.Paused.Text = string.format(
		"Camera-paused animations: %d",
		LastStats.PausedTrees
	)

	DebugLabels.Clusters.Text = string.format(
		"Active: %d | Static 3D: %d | Plane LOD: %d",
		LastStats.ActiveClusters,
		LastStats.Inactive3DClusters,
		LastStats.PlaneClusters
	)

	DebugLabels.Planes.Text = string.format(
		"Mesh planes: %d | Fallbacks: %d",
		LastStats.PlaneTrees,
		LastStats.PlaneFallbacks
	)

	DebugLabels.Failures.Text = string.format(
		"Mesh plane failures: %d",
		LastStats.PlaneFailures
	)

	DebugLabels.Distance.Text = string.format(
		"Active: 0-%d | Plane: %d+ (return %d)",
		ACTIVE_RADIUS,
		PLANE_DISTANCE,
		PLANE_RETURN_DISTANCE
	)

end

createDebugUI()

local clearDebugClusters
local createPlaneDebugMarker
local removePlaneDebugMarker

--==============================================================
-- KEYBOARD CONTROLS
--==============================================================

UserInputService.InputBegan:Connect(function(input, gameProcessed)

	if gameProcessed then
		return
	end

	-- L locks/unlocks the current cluster LOD states.
	if input.KeyCode == Enum.KeyCode.L then

		LODLocked = not LODLocked

		if LODLocked then

			table.clear(LockedClusterStates)

			for key, lod in pairs(ClusterStates) do
				LockedClusterStates[key] = lod
			end

			print("[TreeLOD] Cluster LOD locked. Press L to unlock.")

		else

			table.clear(LockedClusterStates)

			print("[TreeLOD] Cluster LOD unlocked.")

		end

		return

	end

	-- Apostrophe toggles cluster visualization.
	if input.KeyCode == Enum.KeyCode.Quote then

		ClusterVisualizationEnabled = not ClusterVisualizationEnabled

		if not ClusterVisualizationEnabled then
			clearDebugClusters()
		end

		print(
			"[TreeLOD] Cluster visualization:",
			ClusterVisualizationEnabled and "ON" or "OFF"
		)

		return

	end

	-- K toggles orange tree-height markers.
	if input.KeyCode == Enum.KeyCode.K then

		PLANE_MARKERS_VISIBLE = not PLANE_MARKERS_VISIBLE

		for _, data in pairs(ManagedTrees) do

			if PLANE_MARKERS_VISIBLE and data.LOD == "Inactive2D" then
				createPlaneDebugMarker(data)
			elseif not PLANE_MARKERS_VISIBLE then
				removePlaneDebugMarker(data)
			end

		end

		print(
			"[TreeLOD] Plane markers:",
			PLANE_MARKERS_VISIBLE and "ON" or "OFF"
		)

		return

	end

	-- Semicolon toggles the debug HUD.
	if DEBUG_UI_ENABLED and input.KeyCode == DEBUG_UI_TOGGLE_KEY then
		setDebugUIVisible(not DebugUIVisible)
	end

end)

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

local function getClusterDistance(key, position)

	local center = getClusterCenter(key)

	local dx = center.X - position.X
	local dz = center.Z - position.Z

	return math.sqrt(dx * dx + dz * dz)

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

	local clusterRadius = math.sqrt(
		(CLUSTER_SIZE / 2) ^ 2
			+ (CLUSTER_SIZE / 2) ^ 2
	)

	local worldCenter = Vector3.new(
		center.X,
		DEBUG_HEIGHT,
		center.Z
	)

	local screenPosition = camera:WorldToViewportPoint(worldCenter)

	local depth = screenPosition.Z

	if depth <= -clusterRadius then
		return false
	end

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

	return
		screenPosition.X >= -margin
		and screenPosition.X <= viewport.X + margin
		and screenPosition.Y >= -margin
		and screenPosition.Y <= viewport.Y + margin

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
-- TREE VISIBILITY
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
-- CREATE MESH PLANE IMPOSTOR
--==============================================================

local PlaneTemplate = ReplicatedStorage:FindFirstChild(PLANE_TEMPLATE_NAME)

if PlaneTemplate and not PlaneTemplate:IsA("BasePart") then

	warn(
		"[TreeLOD] ReplicatedStorage/"
			.. PLANE_TEMPLATE_NAME
			.. " must be a BasePart or MeshPart. Using an orange Part placeholder instead."
	)

	PlaneTemplate = nil

end

local function createTreePlane(data)

	if data.Plane and data.Plane.Parent then
		return data.Plane
	end

	if not data.Model
		or not data.Model.Parent
		or not data.RootPart
		or not data.RootPart.Parent then

		return nil

	end

	-- Use the Blender MeshPart template when present.
	-- Otherwise create an orange Part placeholder.
	local plane

	if PlaneTemplate and PlaneTemplate.Parent then

		plane = PlaneTemplate:Clone()

	else

		plane = Instance.new("Part")
		plane.Shape = Enum.PartType.Block

	end

	plane.Name = "TreeLOD_MeshPlane"

	plane.Anchored = true

	plane.CanCollide = false
	plane.CanTouch = false
	plane.CanQuery = false

	plane.CastShadow = false
	plane.Massless = true

	-- Match the tree's measured width and height.
	local planeWidth = data.TreeWidth

	if PLANE_ASPECT_RATIO and PLANE_ASPECT_RATIO > 0 then
		planeWidth = data.TreeHeight * PLANE_ASPECT_RATIO
	end

	plane.Size = Vector3.new(
		math.max(planeWidth, 0.1),
		math.max(data.TreeHeight, 0.1),
		PLANE_THICKNESS
	)

	-- Orange placeholder appearance.
	plane.Color = Color3.fromRGB(255, 140, 35)
	plane.Material = Enum.Material.Neon
	plane.Transparency = 0

	plane.Parent = workspace

	data.Plane = plane
	ActivePlanes[data] = true

	return plane

end

local function removeTreePlane(data)

	ActivePlanes[data] = nil

	if data.Plane then
		data.Plane:Destroy()
		data.Plane = nil
	end

end

--==============================================================
-- MESH PLANE POSITION + PLAYER-FACING ROTATION
--==============================================================

local function updateTreePlanes()

	local camera = workspace.CurrentCamera

	if not camera then
		return
	end

	local cameraPosition = camera.CFrame.Position

	for data in pairs(ActivePlanes) do

		local plane = data.Plane

		if not plane
			or not plane.Parent
			or not data.RootPart
			or not data.RootPart.Parent then

			ActivePlanes[data] = nil
			continue

		end

		-- Keep the plane centered on the original tree's bounding box.
		local center = data.RootPart.Position + Vector3.new(
			0,
			data.TreeBottomOffset + (data.TreeHeight / 2),
			0
		)

		-- Rotate horizontally toward the camera.
		-- The plane remains upright and only changes its Y rotation.
		local direction = Vector3.new(
			cameraPosition.X - center.X,
			0,
			cameraPosition.Z - center.Z
		)

		if direction.Magnitude < 0.001 then
			direction = Vector3.new(0, 0, -1)
		end

		plane.CFrame = CFrame.lookAt(
			center,
			center + direction.Unit
		)

	end

end

RunService.RenderStepped:Connect(updateTreePlanes)

--==============================================================
-- PLANE-LOD DEBUG MARKER
--
-- The orange marker now uses the exact measured tree height.
-- Its center is positioned using the tree's bounding-box center.
--==============================================================

createPlaneDebugMarker = function(data)

	if not PLANE_DEBUG_MARKER_ENABLED
		or not PLANE_MARKERS_VISIBLE
		or data.PlaneDebugMarker then

		return

	end

	if not data.RootPart or not data.RootPart.Parent then
		return
	end

	local marker = Instance.new("Part")

	marker.Name = "TreeLOD_PlaneDebugMarker"

	marker.Anchored = true

	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false

	marker.CastShadow = false

	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(255, 140, 35)
	marker.Transparency = 0.2

	-- Marker height matches the tree it replaces.
	marker.Size = Vector3.new(
		1,
		math.max(data.TreeHeight, 0.1),
		1
	)

	local markerCenter = data.RootPart.Position + Vector3.new(
		0,
		data.TreeBottomOffset + (data.TreeHeight / 2),
		0
	)

	marker.CFrame = CFrame.new(markerCenter)
	marker.Parent = workspace

	data.PlaneDebugMarker = marker

end

removePlaneDebugMarker = function(data)

	if data.PlaneDebugMarker then
		data.PlaneDebugMarker:Destroy()
		data.PlaneDebugMarker = nil
	end

end

--==============================================================
-- APPLY TREE LOD
--==============================================================

local function setTreeLOD(data, newLOD)

	if newLOD == "Inactive2D" then

		-- Create the replacement plane before hiding the original tree.
		local success, plane = pcall(function()
			return createTreePlane(data)
		end)

		if not success or not plane then

			if not data.PlaneFailed then
				PlaneFailureCount += 1
			end

			data.PlaneFailed = true

			removeTreePlane(data)
			removePlaneDebugMarker(data)

			setTree3DVisible(data, true)

			data.LOD = "Inactive3D"

			return false

		end

		data.PlaneFailed = false

		createPlaneDebugMarker(data)

		setTree3DVisible(data, false)

		data.LOD = "Inactive2D"

		return true

	end

	-- Restore the original tree before removing its replacement plane.
	setTree3DVisible(data, true)

	removeTreePlane(data)
	removePlaneDebugMarker(data)

	data.PlaneFailed = false
	data.LOD = newLOD

	return true

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
	local controller = model:FindFirstChildOfClass("AnimationController")

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
	local animator = controller:FindFirstChildOfClass("Animator")

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

	-- Cache model parts and their original local transparency.
	local parts = {}
	local originalTransparency = {}

	for _, obj in ipairs(model:GetDescendants()) do

		if obj:IsA("BasePart") then

			table.insert(parts, obj)

			originalTransparency[obj] =
				obj.LocalTransparencyModifier

		end

	end

	-- Measure the actual model bounds.
	-- TreeBottomOffset is the distance from RootPart.Position
	-- to the bottom of the tree's bounding box.
	local treeHeight = 20
	local treeWidth = 10
	local treeBottomOffset = 0

	local boundsSuccess, boundsCFrame, boundsSize = pcall(function()
		return model:GetBoundingBox()
	end)

	if boundsSuccess and boundsCFrame and boundsSize then

		treeHeight = math.max(boundsSize.Y, 1)

		treeWidth = math.max(
			boundsSize.X,
			boundsSize.Z,
			1
		)

		treeBottomOffset =
			(boundsCFrame.Position.Y - root.Position.Y)
		- (treeHeight / 2)

	else

		local extentsSuccess, extents = pcall(function()
			return model:GetExtentsSize()
		end)

		if extentsSuccess and extents then

			treeHeight = math.max(extents.Y, 1)

			treeWidth = math.max(
				extents.X,
				extents.Z,
				1
			)

			treeBottomOffset = 0

		end

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

		TreeWidth = treeWidth,

		TreeBottomOffset = treeBottomOffset,

		Plane = nil,

		PlaneDebugMarker = nil,

		PlaneFailed = false,

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
-- PAUSE ANIMATION
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

		track:AdjustSpeed(0)

		data.Paused = true

	end)

end

--==============================================================
-- RESUME ANIMATION
--==============================================================

local function resumeAnimation(data)

	if not data.IsActive then
		return
	end

	if not data.Paused then
		return
	end

	if not data.ActiveTrack then
		return
	end

	local track = data.ActiveTrack

	pcall(function()

		track:AdjustSpeed(data.SavedAnimationSpeed)

		data.Paused = false

	end)

end

--==============================================================
-- PLAY RANDOM ANIMATION
--==============================================================

local function playRandomAnimation(data)

	if not data or not data.Animator then
		return
	end

	if not data.IsActive then
		return
	end

	if #data.Animations == 0 then
		return
	end

	data.PlayToken += 1

	local token = data.PlayToken

	task.spawn(function()

		while Running
			and data.IsActive
			and data.PlayToken == token do

			local animation =
				data.Animations[math.random(1, #data.Animations)]

			local success, track = pcall(function()

				local loadedTrack =
					data.Animator:LoadAnimation(animation)

				loadedTrack.Looped = false

				return loadedTrack

			end)

			if success and track then

				data.ActiveTrack = track

				local speed = MIN_SPEED
					+ math.random()
					* (MAX_SPEED - MIN_SPEED)

				data.SavedAnimationSpeed = speed

				pcall(function()
					track:AdjustSpeed(speed)
					track:Play(CROSSFADE_TIME)
				end)

				if DEBUG_FIRST_ANIMATION and not firstAnimationReported then

					firstAnimationReported = true

					print(
						"[TreeLOD] First tree animation started:",
						data.Model.Name,
						animation.AnimationId
					)

				end

				local length = track.Length

				if length <= 0 then
					length = 3
				end

				local startTime = os.clock()

				while Running
					and data.IsActive
					and data.PlayToken == token
					and track.IsPlaying
					and os.clock() - startTime < length + 1 do

					task.wait(0.1)

				end

				if data.ActiveTrack == track then
					data.ActiveTrack = nil
				end

				pcall(function()
					track:Stop(CROSSFADE_TIME)
					track:Destroy()
				end)

			else

				warn(
					"[TreeLOD] Failed to load animation for",
					data.Model.Name,
					track
				)

			end

			if not data.IsActive or data.PlayToken ~= token then
				break
			end

			task.wait(
				MIN_DELAY
					+ math.random()
					* (MAX_DELAY - MIN_DELAY)
			)

		end

	end)

end

--==============================================================
-- REMOVE TREE
--==============================================================

local function removeTree(model)

	if not model then
		return
	end

	local data = ManagedTrees[model]

	if not data then
		PendingTrees[model] = nil
		return
	end

	stopAnimation(data)

	removeTreePlane(data)
	removePlaneDebugMarker(data)

	setTree3DVisible(data, true)

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
			ClusterStates[data.ClusterKey] = nil
			LockedClusterStates[data.ClusterKey] = nil
		end

	end

	ManagedTrees[model] = nil
	PendingTrees[model] = nil

end

--==============================================================
-- LOD CALCULATION
--==============================================================

local function getClusterLOD(distance, previousLOD)

	-- Active 3D takes priority.
	if distance <= ACTIVE_RADIUS then
		return "Active3D"
	end

	-- Hysteresis:
	-- A plane cluster returns to 3D at PLANE_RETURN_DISTANCE.
	if previousLOD == "Inactive2D" then

		if distance <= PLANE_RETURN_DISTANCE then
			return "Inactive3D"
		end

		return "Inactive2D"

	end

	-- Enter plane mode at PLANE_DISTANCE.
	if distance >= PLANE_DISTANCE then
		return "Inactive2D"
	end

	return "Inactive3D"

end

--==============================================================
-- DEBUG CLUSTER VISUALIZATION
--==============================================================

local function getClusterDebugColor(lod)

	if lod == "Active3D" then
		return Color3.fromRGB(40, 220, 90)
	elseif lod == "Inactive3D" then
		return Color3.fromRGB(55, 145, 255)
	elseif lod == "Inactive2D" then
		return Color3.fromRGB(255, 145, 35)
	end

	return DEBUG_COLOR

end

local function createDebugPart(key, lod)

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

	part.Color = getClusterDebugColor(lod)

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

local function updateDebugClusters(clusterStates)

	if not DEBUG_MODE or not ClusterVisualizationEnabled then
		return
	end

	for key, part in pairs(DebugParts) do

		if clusterStates[key] == nil then

			part:Destroy()
			DebugParts[key] = nil

		end

	end

	for key, lod in pairs(clusterStates) do

		local part = DebugParts[key]

		if not part then

			createDebugPart(key, lod)

		else

			part.Color = getClusterDebugColor(lod)

		end

	end

end

clearDebugClusters = function()

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

		-- Character unavailable.
		for _, data in pairs(ManagedTrees) do

			if data.IsActive then
				stopAnimation(data)
			end

			if data.LOD == "Inactive2D" then
				setTreeLOD(data, "Inactive3D")
			end

		end

		table.clear(ClusterStates)

		clearDebugClusters()

		updateDebugUI(true)

		return

	end

	-- Statistics.
	local activeCount = 0
	local playingCount = 0
	local registeredCount = 0

	local activeClusterCount = 0
	local inactive3DCount = 0
	local planeClusterCount = 0

	local pausedCount = 0
	local planeTreeCount = 0
	local planeFallbackCount = 0

	local clusterDebugStates = {}

	-- Process all registered clusters.
	for clusterKey, trees in pairs(Clusters) do

		if #trees == 0 then
			continue
		end

		local distance =
			getClusterDistance(clusterKey, position)

		local previousLOD =
			ClusterStates[clusterKey]

		local clusterLOD

		if LODLocked then

			clusterLOD =
				LockedClusterStates[clusterKey]
				or previousLOD
				or "Inactive3D"

		else

			clusterLOD = getClusterLOD(
				distance,
				previousLOD
			)

		end

		ClusterStates[clusterKey] = clusterLOD

		clusterDebugStates[clusterKey] = clusterLOD

		-- Camera culling only affects active clusters.
		local cameraVisible = true

		if clusterLOD == "Active3D" and camera then
			cameraVisible = isClusterOnScreen(clusterKey)
		end

		-- Count cluster LOD levels.
		if clusterLOD == "Active3D" then

			activeClusterCount += 1

		elseif clusterLOD == "Inactive3D" then

			inactive3DCount += 1

		elseif clusterLOD == "Inactive2D" then

			planeClusterCount += 1

		end

		-- Update each tree in the cluster.
		for i = #trees, 1, -1 do

			local data = trees[i]

			local model = data.Model

			if not model or not model.Parent then

				removeTree(model)

				continue

			end

			registeredCount += 1

			-- Apply visual LOD.
			setTreeLOD(data, clusterLOD)

			if clusterLOD == "Active3D" then

				activeCount += 1

				-- Start animation when becoming active.
				if not data.IsActive then

					data.IsActive = true

					data.Paused = false

					playRandomAnimation(data)

				end

				-- Camera culling.
				if cameraVisible then

					resumeAnimation(data)

				else

					pauseAnimation(data)

				end

				if data.Paused then
					pausedCount += 1
				end

				if data.ActiveTrack then
					playingCount += 1
				end

			else

				-- Stop animation outside active radius.
				if data.IsActive then
					stopAnimation(data)
				end

				if clusterLOD == "Inactive2D" then

					if data.Plane and data.Plane.Parent then
						planeTreeCount += 1
					else
						planeFallbackCount += 1
					end

				end

			end

		end

	end

	-- Update debug cluster visualization.
	updateDebugClusters(clusterDebugStates)

	-- Save statistics.
	LastStats.Registered = registeredCount

	LastStats.Active = activeCount

	LastStats.Playing = playingCount

	LastStats.ActiveClusters = activeClusterCount

	LastStats.Inactive3DClusters = inactive3DCount

	LastStats.PlaneClusters = planeClusterCount

	LastStats.PausedTrees = pausedCount

	LastStats.PlaneTrees = planeTreeCount

	LastStats.PlaneFallbacks = planeFallbackCount

	LastStats.PlaneFailures = PlaneFailureCount

	LastStats.Pending = 0

	for _ in pairs(PendingTrees) do
		LastStats.Pending += 1
	end

	updateDebugUI()

end

--==============================================================
-- TREE DISCOVERY
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

	LastStats.Candidates = candidates

	LastStats.MissingRoot = missingRoot

	LastStats.Pending = 0

	for _ in pairs(PendingTrees) do
		LastStats.Pending += 1
	end

	updateDebugUI(true)

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
				"| Plane Clusters:", LastStats.PlaneClusters,

				"| Paused Trees:", LastStats.PausedTrees,
				"| Plane Trees:", LastStats.PlaneTrees
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

		removePlaneDebugMarker(data)

		-- Restore original 3D visibility.
		setTree3DVisible(data, true)

		removeTreePlane(data)

		for _, animation in ipairs(data.Animations) do
			animation:Destroy()
		end

	end

	table.clear(ManagedTrees)

	table.clear(Clusters)

	table.clear(ClusterStates)

	table.clear(PendingTrees)

	clearDebugClusters()

	if DebugUI then
		DebugUI:Destroy()
		DebugUI = nil
	end

end)
