-- 🌲 Universal Tree Animation Manager
-- Handles all tree models and loops random animations for each type
-- Trees only animate when players are nearby (radius-based optimization)

-- 🎬 CONFIGURATION SECTION (easy to edit)
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

-- 🔁 Animation behavior
local MIN_DELAY = 0.5
local MAX_DELAY = 2.5
local CROSSFADE_TIME = 0.3

-- 🎯 Optimization: only animate within this radius (in studs)
local ACTIVATION_RADIUS = 200

-- ⚙️ Service references
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- 🎥 Core animation logic
local function setupTree(treeModel)
	if not treeModel:IsA("Model") then return end
	local animList = treeAnimations[treeModel.Name]
	if not animList then return end

	-- Ensure AnimationController & Animator exist
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

	-- Helper: get a position to measure distance from
	local rootPart = treeModel:FindFirstChild("PrimaryPart") or treeModel:FindFirstChildWhichIsA("BasePart")
	if not rootPart then return end

	local activeTrack = nil
	local isActive = false

	local function stopAnimation()
		if activeTrack then
			activeTrack:Stop(CROSSFADE_TIME)
			activeTrack = nil
		end
		isActive = false
	end

	local function playRandomAnimation()
		if not isActive then return end
		local animId = animList[math.random(1, #animList)]
		local animation = Instance.new("Animation")
		animation.AnimationId = animId

		local track = animator:LoadAnimation(animation)
		activeTrack = track
		track.Looped = false
		track:Play()

		track.Stopped:Connect(function()
			task.wait(math.random() * (MAX_DELAY - MIN_DELAY) + MIN_DELAY)
			playRandomAnimation()
		end)
	end

	-- Main loop: check if any player is near
	RunService.Heartbeat:Connect(function()
		local nearestPlayerDist = math.huge
		for _, player in pairs(Players:GetPlayers()) do
			if player.Character and player.Character.PrimaryPart then
				local dist = (player.Character.PrimaryPart.Position - rootPart.Position).Magnitude
				if dist < nearestPlayerDist then
					nearestPlayerDist = dist
				end
			end
		end

		if nearestPlayerDist <= ACTIVATION_RADIUS then
			-- Activate animation if not already active
			if not isActive then
				isActive = true
				playRandomAnimation()
			end
		else
			-- Deactivate animation when no player nearby
			if isActive then
				stopAnimation()
			end
		end
	end)
end

-- 🌿 Initialize for existing trees
for _, obj in pairs(workspace:GetDescendants()) do
	if treeAnimations[obj.Name] then
		setupTree(obj)
	end
end

-- 🌱 Handle newly spawned trees
workspace.DescendantAdded:Connect(function(obj)
	if treeAnimations[obj.Name] then
		task.wait(0.5)
		setupTree(obj)
	end
end)
