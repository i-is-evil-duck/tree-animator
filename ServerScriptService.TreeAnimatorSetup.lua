
--==============================================================
-- TREE ANIMATOR SETUP
-- ServerScriptService > TreeAnimatorSetup
--==============================================================

local TreesFolder = workspace:WaitForChild("Trees")

local TREE_TYPES = {
	Tree1 = true,
	Tree3 = true,
	Tree4 = true,
}

local initialized = {}

local function isActualTree(model)
	if not model:IsA("Model") then
		return false
	end

	if not TREE_TYPES[model.Name] then
		return false
	end

	local root = model:FindFirstChild("RootPart")

	return root ~= nil and root:IsA("BasePart")
end

local function setupTree(model)
	if not isActualTree(model) then
		return false
	end

	if initialized[model] then
		return true
	end

	local controller =
		model:FindFirstChildOfClass("AnimationController")

	if not controller then
		controller = Instance.new("AnimationController")
		controller.Name = "AnimationController"
		controller.Parent = model
	end

	local animator =
		controller:FindFirstChildOfClass("Animator")

	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end

	initialized[model] = true

	return true
end

-- Initial scan
local count = 0

for _, obj in ipairs(TreesFolder:GetDescendants()) do
	if setupTree(obj) then
		count += 1
	end
end

-- New trees
TreesFolder.DescendantAdded:Connect(function(obj)
	if not obj:IsA("Model") then
		return
	end

	if not TREE_TYPES[obj.Name] then
		return
	end

	task.spawn(function()
		local root = obj:FindFirstChild("RootPart")

		if not root then
			root = obj:WaitForChild("RootPart", 30)
		end

		if root and obj.Parent then
			if setupTree(obj) then
				print("[TreeAnimatorSetup] Added:", obj:GetFullName())
			end
		end
	end)
end)

TreesFolder.DescendantRemoving:Connect(function(obj)
	if obj:IsA("Model") then
		initialized[obj] = nil
	end
end)

print(
	"[TreeAnimatorSetup] Initialized",
	count,
	"tree animators"
)
