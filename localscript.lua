-- 🌲 Universal Tree Animation Manager (Cluster-Aware, Circular + Debug)

-- 🎬 CONFIG
local treeAnimations = {
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
local ACTIVATION_RADIUS = 200 -- Distance for tree animation
local CHECK_INTERVAL = 1      -- Seconds per cluster update

local CLUSTER_SIZE = 75       -- Each cluster is 50x50 studs
local CLUSTER_RADIUS = 200    -- Circular radius for active clusters
local DEBUG_MODE = true       -- Show debug visualization
local DEBUG_HEIGHT = 60       -- Height of debug parts in the sky

-- ⚙️ Services
local Players = game:GetService("Players")

-- 🧩 State tables
local ManagedTrees = {}
local Clusters = {}
local DebugParts = {}

-- 🔢 Utility: Convert 3D position → cluster key
local function getClusterKey(pos)
	local x = math.floor(pos.X / CLUSTER_SIZE)
	local z = math.floor(pos.Z / CLUSTER_SIZE)
	return tostring(x) .. "_" .. tostring(z), x, z
end

-- 🧠 Utility: Get all player positions
local function getPlayerPositions()
	local positions = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char and char.PrimaryPart then
			table.insert(positions, char.PrimaryPart.Position)
		end
	end
	return positions
end

-- 🌿 Setup tree
local function setupTree(treeModel)
	if not treeModel:IsA("Model") then return end
	local animList = treeAnimations[treeModel.Name]
	if not animList then return end

	local controller = treeModel:FindFirstChildOfClass("AnimationController")
	if not controller then
		controller = Instance.new("AnimationController")
		controller.Parent = treeModel
	end

	local animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end

	local rootPart = treeModel.PrimaryPart or treeModel:FindFirstChildWhichIsA("BasePart")
	if not rootPart then return end

	local treeData = {
		Model = treeModel,
		RootPart = rootPart,
		Animator = animator,
		Animations = animList,
		IsActive = false,
		ActiveTrack = nil,
	}

	ManagedTrees[treeModel] = treeData

	local clusterKey = getClusterKey(rootPart.Position)
	Clusters[clusterKey] = Clusters[clusterKey] or {}
	table.insert(Clusters[clusterKey], treeData)
end

-- 🎞️ Animation logic
local function stopAnimation(treeData)
	if treeData.ActiveTrack then
		treeData.ActiveTrack:Stop(CROSSFADE_TIME)
		treeData.ActiveTrack = nil
	end
	treeData.IsActive = false
end

local function playRandomAnimation(treeData)
	if not treeData.IsActive then return end

	local animId = treeData.Animations[math.random(1, #treeData.Animations)]
	local animation = Instance.new("Animation")
	animation.AnimationId = animId

	local track = treeData.Animator:LoadAnimation(animation)
	treeData.ActiveTrack = track
	track.Looped = false

	local randomSpeed = math.random(80, 120) / 100
	track:AdjustSpeed(randomSpeed)
	track:Play()

	track.Stopped:Once(function()
		task.wait(math.random() * (MAX_DELAY - MIN_DELAY) + MIN_DELAY)
		playRandomAnimation(treeData)
	end)
end

-- 🧱 Debug visualization
local function createDebugPart(x, z)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Color = Color3.fromRGB(0, 255, 0)
	part.Transparency = 0.8
	part.Size = Vector3.new(CLUSTER_SIZE, 1, CLUSTER_SIZE)
	part.Position = Vector3.new(x * CLUSTER_SIZE + CLUSTER_SIZE / 2, DEBUG_HEIGHT, z * CLUSTER_SIZE + CLUSTER_SIZE / 2)
	part.Name = "ClusterDebug"
	part.Parent = workspace
	return part
end

local function clearDebugParts()
	for _, part in pairs(DebugParts) do
		part:Destroy()
	end
	DebugParts = {}
end

local function showDebugClusters(activeClusters)
	clearDebugParts()
	for key in pairs(activeClusters) do
		local split = string.split(key, "_")
		local x, z = tonumber(split[1]), tonumber(split[2])
		local part = createDebugPart(x, z)
		table.insert(DebugParts, part)
	end
end

-- 🔄 Global update loop (circular cluster activation)
task.spawn(function()
	while true do
		task.wait(CHECK_INTERVAL)
		local playerPositions = getPlayerPositions()
		if #playerPositions == 0 then
			if DEBUG_MODE then clearDebugParts() end
			continue
		end

		local activeClusters = {}

		for _, pos in ipairs(playerPositions) do
			local centerX = math.floor(pos.X / CLUSTER_SIZE)
			local centerZ = math.floor(pos.Z / CLUSTER_SIZE)
			local clusterRadiusCount = math.ceil(CLUSTER_RADIUS / CLUSTER_SIZE)

			for dx = -clusterRadiusCount, clusterRadiusCount do
				for dz = -clusterRadiusCount, clusterRadiusCount do
					local clusterCenterX = (centerX + dx) * CLUSTER_SIZE + CLUSTER_SIZE / 2
					local clusterCenterZ = (centerZ + dz) * CLUSTER_SIZE + CLUSTER_SIZE / 2

					local distance = math.sqrt((clusterCenterX - pos.X)^2 + (clusterCenterZ - pos.Z)^2)
					if distance <= CLUSTER_RADIUS then
						local key = tostring(centerX + dx) .. "_" .. tostring(centerZ + dz)
						activeClusters[key] = true
					end
				end
			end
		end

		-- 🟩 Debug visualization
		if DEBUG_MODE then
			showDebugClusters(activeClusters)
		end

		-- Activate/deactivate trees by cluster
		for clusterKey, trees in pairs(Clusters) do
			local isClusterActive = activeClusters[clusterKey]

			for i = #trees, 1, -1 do
				local tree = trees[i]
				local model = tree.Model
				if not model or not model.Parent then
					table.remove(trees, i)
					ManagedTrees[model] = nil
					continue
				end

				if isClusterActive then
					if not tree.IsActive then
						tree.IsActive = true
						playRandomAnimation(tree)
					end
				elseif tree.IsActive then
					stopAnimation(tree)
				end
			end
		end
	end
end)

-- 🌱 Initialize trees
for _, obj in ipairs(workspace:GetDescendants()) do
	if treeAnimations[obj.Name] then
		setupTree(obj)
	end
end

workspace.DescendantAdded:Connect(function(obj)
	if treeAnimations[obj.Name] then
		task.wait(0.25)
		setupTree(obj)
	end
end)
