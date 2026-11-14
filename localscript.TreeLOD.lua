--==============================================================
-- TREE LOD MANAGER
-- StarterPlayer > StarterPlayerScripts > TreeLOD
--
-- THREE LEVELS:
-- 1. Active 3D       - Animated trees
-- 2. Inactive 3D     - Static 3D trees
-- 3. Inactive 2D     - Billboard tree images
--
-- Random billboard variant is selected once per tree.
-- All LOD and visibility changes are client-side.
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
-- BILLBOARD IMAGE VARIANTS
--==============================================================

local BILLBOARD_IMAGES = {

	Tree1 = {
		"rbxassetid://972747577",
	},

	Tree3 = {
		"rbxassetid://972747577",
	},

	Tree4 = {
		"rbxassetid://972747577",
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

local BILLBOARD_DISTANCE = 400

local BILLBOARD_RETURN_DISTANCE = 360

local CHECK_INTERVAL = 0.5

local DISCOVERY_INTERVAL = 2

--==============================================================
-- BILLBOARD SETTINGS
--==============================================================

local BILLBOARD_ASPECT_RATIO = 0.55

-- BillboardGui MaxDistance = 0 means unlimited.
local BILLBOARD_MAX_DISTANCE = 0

-- Optional orange glow behind each billboard image.
local BILLBOARD_GLOW_ENABLED = true
local BILLBOARD_GLOW_COLOR = Color3.fromRGB(255, 170, 60)
local BILLBOARD_GLOW_TRANSPARENCY = 0.45
local BILLBOARD_GLOW_SCALE = 1.25

-- Tall orange marker makes billboard LOD placement easy to debug.
local BILLBOARD_DEBUG_MARKER_ENABLED = true
local BILLBOARD_DEBUG_MARKER_HEIGHT = 100

-- Billboards use world-space sizing (studs), never screen pixels.

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

-- Press semicolon (;) to toggle the HUD.
local DEBUG_UI_TOGGLE_KEY = Enum.KeyCode.Semicolon

local DEBUG_UI_UPDATE_INTERVAL = 0.5

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

local ClusterStates = {}

local PendingTrees = {}

local DebugParts = {}

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
	BillboardClusters = 0,

	PausedTrees = 0,
	BillboardTrees = 0,
	BillboardFallbacks = 0,
	BillboardFailures = 0,
	Candidates = 0,
	MissingRoot = 0,
	Pending = 0,

}

local BillboardFailureCount = 0
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
		{"Clusters", "Active: 0 | Static 3D: 0 | Billboard: 0"},
		{"Billboards", "Working billboards: 0 | Fallbacks: 0"},
		{"Failures", "Billboard creation failures: 0"},
		{"Distance", "Active: 0-200 | Billboard: 400+"},
		{"ToggleHelp", ";: HUD | L: lock/unlock cluster LOD"},

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
		"Active: %d | Static 3D: %d | Billboard: %d",
		LastStats.ActiveClusters,
		LastStats.Inactive3DClusters,
		LastStats.BillboardClusters
	)

	DebugLabels.Billboards.Text = string.format(
		"Working billboards: %d | Fallbacks: %d",
		LastStats.BillboardTrees,
		LastStats.BillboardFallbacks
	)

	DebugLabels.Failures.Text = string.format(
		"Billboard creation failures: %d",
		LastStats.BillboardFailures
	)

	DebugLabels.Distance.Text = string.format(
		"Active: 0-%d | Billboard: %d+ (return %d)",
		ACTIVE_RADIUS,
		BILLBOARD_DISTANCE,
		BILLBOARD_RETURN_DISTANCE
	)

end

createDebugUI()

--==============================================================
-- INPUT CONTROLS
--==============================================================

local UserInputService = game:GetService("UserInputService")

UserInputService.InputBegan:Connect(function(input, gameProcessed)

	if gameProcessed then
		return
	end

	-- L toggles cluster LOD lock.
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

	-- Semicolon toggles debug HUD.
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

	local screenPosition =
		camera:WorldToViewportPoint(worldCenter)

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

	local margin =
		CAMERA_SCREEN_MARGIN + projectedRadius

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
-- RANDOM BILLBOARD SELECTION
--==============================================================

local function chooseBillboardImage(treeType)

	local options = BILLBOARD_IMAGES[treeType]

	if not options or #options == 0 then
		return "rbxassetid://972747577"
	end

	return options[math.random(1, #options)]

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
-- CREATE BILLBOARD
--==============================================================

local function createBillboard(data)

	-- Reuse only a billboard that is still parented to this tree and has
	-- the correct Adornee. Rebuild stale or externally removed instances.
	if data.Billboard then

		if data.Billboard.Parent == data.Model and data.Billboard.Adornee == data.RootPart then
			return data.Billboard
		end

		pcall(function()
			data.Billboard:Destroy()
		end)

		data.Billboard = nil

	end

	if not data.Model or not data.Model.Parent then
		return nil
	end

	if not data.RootPart or not data.RootPart.Parent then
		return nil
	end

	if not data.BillboardImage then
		return nil
	end

	local billboard = Instance.new("BillboardGui")

	billboard.Name = "TreeLOD_Billboard"

	billboard.Adornee = data.RootPart

	billboard.AlwaysOnTop = false

	billboard.LightInfluence = 0

	billboard.MaxDistance = BILLBOARD_MAX_DISTANCE

	-- World-space dimensions in studs.
	-- Every billboard uses the height of the tree it replaces.
	local billboardWidth = data.TreeHeight * BILLBOARD_ASPECT_RATIO

	billboard.Size = UDim2.fromScale(
		billboardWidth,
		data.TreeHeight
	)

	-- Align billboard bottom with the original tree's base.
	billboard.StudsOffset = Vector3.new(
		0,
		data.TreeBottomOffset,
		0
	)

	billboard.Enabled = false

	-- Orange glow behind the image.
	if BILLBOARD_GLOW_ENABLED then

		local glow = Instance.new("ImageLabel")

		glow.Name = "TreeGlow"
		glow.BackgroundTransparency = 1
		glow.BorderSizePixel = 0
		glow.Size = UDim2.fromScale(
			BILLBOARD_GLOW_SCALE,
			BILLBOARD_GLOW_SCALE
		)

		glow.Position = UDim2.fromScale(
			(1 - BILLBOARD_GLOW_SCALE) / 2,
			(1 - BILLBOARD_GLOW_SCALE) / 2
		)

		glow.Image = data.BillboardImage
		glow.ImageColor3 = BILLBOARD_GLOW_COLOR
		glow.ImageTransparency = BILLBOARD_GLOW_TRANSPARENCY
		glow.ScaleType = Enum.ScaleType.Fit
		glow.ZIndex = 1
		glow.Parent = billboard

	end

	local image = Instance.new("ImageLabel")

	image.Name = "TreeImage"

	image.BackgroundTransparency = 1

	image.BorderSizePixel = 0

	image.Size = UDim2.fromScale(1, 1)

	image.Position = UDim2.fromScale(0, 0)

	image.Image = data.BillboardImage

	image.ScaleType = Enum.ScaleType.Fit

	image.ZIndex = 2

	image.Parent = billboard

	billboard.Parent = data.Model

	data.Billboard = billboard

	return billboard

end

--==============================================================
-- BILLBOARD SIZE
--
-- No distance-based resizing is needed. Each BillboardGui is assigned
-- its tree's measured height in studs when it is created.
--==============================================================

--==============================================================
-- BILLBOARD DEBUG MARKER
--==============================================================

local function createBillboardDebugMarker(data)

	if not BILLBOARD_DEBUG_MARKER_ENABLED or data.BillboardDebugMarker then
		return
	end

	if not data.RootPart or not data.RootPart.Parent then
		return
	end

	local marker = Instance.new("Part")

	marker.Name = "TreeLOD_BillboardDebugMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.CastShadow = false
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(255, 140, 35)
	marker.Transparency = 0.2

	marker.Size = Vector3.new(
		1,
		BILLBOARD_DEBUG_MARKER_HEIGHT,
		1
	)

	marker.CFrame = data.RootPart.CFrame * CFrame.new(
		0,
		BILLBOARD_DEBUG_MARKER_HEIGHT / 2,
		0
	)

	marker.Parent = workspace

	data.BillboardDebugMarker = marker

end

local function removeBillboardDebugMarker(data)

	if data.BillboardDebugMarker then
		data.BillboardDebugMarker:Destroy()
		data.BillboardDebugMarker = nil
	end

end

--==============================================================
-- APPLY TREE LOD
--==============================================================

local function setTreeLOD(data, newLOD)

	if newLOD == "Inactive2D" then

		-- Create and enable billboard before hiding the 3D tree.
		local success, billboard = pcall(function()
			return createBillboard(data)
		end)

		if not success or not billboard then

			BillboardFailureCount += 1

			data.BillboardFailed = true

			setTree3DVisible(data, true)

			if data.Billboard then
				data.Billboard.Enabled = false
			end

			data.LOD = "Inactive3D"

			return false

		end

		billboard.Enabled = true

		data.BillboardFailed = false

		createBillboardDebugMarker(data)

		setTree3DVisible(data, false)

		data.LOD = "Inactive2D"

		return true

	end

	-- Restore 3D before disabling billboard.
	removeBillboardDebugMarker(data)

	setTree3DVisible(data, true)

	if data.Billboard then
		data.Billboard.Enabled = false
	end

	data.BillboardFailed = false

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

	-- Measure the actual model bounding box.
	-- TreeHeight is stored in studs.
	-- TreeBottomOffset aligns billboard bottom with tree base.
	local treeHeight = 20
	local treeBottomOffset = 10

	local boundsSuccess, boundsCFrame, boundsSize = pcall(function()
		return model:GetBoundingBox()
	end)

	if boundsSuccess and boundsCFrame and boundsSize then

		treeHeight = math.max(boundsSize.Y, 1)

		treeBottomOffset =
			(boundsCFrame.Position.Y - root.Position.Y)
			+ (treeHeight / 2)

	else

		local extentsSuccess, extents = pcall(function()
			return model:GetExtentsSize()
		end)

		if extentsSuccess and extents then

			treeHeight = math.max(extents.Y, 1)

			treeBottomOffset = treeHeight / 2

		end

	end

	-- Select billboard ONCE for this tree.
	local selectedBillboard = chooseBillboardImage(model.Name)

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

		TreeBottomOffset = treeBottomOffset,

		BillboardImage = selectedBillboard,

		Billboard = nil,

		BillboardFailed = false,

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

	-- Choose random animation.
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

	if not model then
		return
	end

	local data = ManagedTrees[model]

	if not data then

		PendingTrees[model] = nil

		return

	end

	stopAnimation(data)

	removeBillboardDebugMarker(data)

	-- Restore original visibility.
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

			ClusterStates[data.ClusterKey] = nil

		end

	end

	ManagedTrees[model] = nil

	PendingTrees[model] = nil

end

--==============================================================
-- CLUSTER LOD CALCULATION
--==============================================================

local function getClusterLOD(distance, previousLOD)

	-- Active 3D takes priority.
	if distance <= ACTIVE_RADIUS then
		return "Active3D"
	end

	-- Hysteresis:
	-- A billboard cluster returns to 3D at 360 studs.
	if previousLOD == "Inactive2D" then

		if distance <= BILLBOARD_RETURN_DISTANCE then
			return "Inactive3D"
		end

		return "Inactive2D"

	end

	-- Enter billboard mode at 400 studs.
	if distance >= BILLBOARD_DISTANCE then
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

	if not DEBUG_MODE then
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

	local billboardClusterCount = 0

	local pausedCount = 0

	local billboardTreeCount = 0

	local billboardFallbackCount = 0

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

			clusterLOD = getClusterLOD(distance, previousLOD)

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

			billboardClusterCount += 1

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

					if data.Billboard and data.Billboard.Enabled then

						billboardTreeCount += 1

					else

						billboardFallbackCount += 1

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

	LastStats.BillboardClusters = billboardClusterCount

	LastStats.PausedTrees = pausedCount

	LastStats.BillboardTrees = billboardTreeCount

	LastStats.BillboardFallbacks = billboardFallbackCount

	LastStats.BillboardFailures = BillboardFailureCount

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
			"[TREELOD DISCOVERY]",
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

		removeBillboardDebugMarker(data)

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

	table.clear(ClusterStates)

	table.clear(PendingTrees)

	clearDebugClusters()

	if DebugUI then
		DebugUI:Destroy()
		DebugUI = nil
	end

end)
