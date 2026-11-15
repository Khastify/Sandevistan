-- KHASTIFY SANDEVISTAN V2
-- Client-side cinematic effects for standard Roblox humanoid avatars.
-- X: toggle; LeftShift: burst while active.
-- Other players will not necessarily see these local effects.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local player = Players.LocalPlayer
local active = false
local elapsed = 0
local spawnClock = 0
local originalSpeed = nil
local originalFov = nil
local burst = false
local MAX_GHOSTS = 22
local ghosts = {}
local ghostFolder = workspace:FindFirstChild("KhastifySandyGhosts")
if ghostFolder then ghostFolder:Destroy() end
ghostFolder = Instance.new("Folder")
ghostFolder.Name = "KhastifySandyGhosts"
ghostFolder.Parent = workspace
local cc = Instance.new("ColorCorrectionEffect")
cc.Name = "KhastifySandyColor"
cc.Enabled = false
cc.Parent = Lighting
local blur = Instance.new("BlurEffect")
blur.Name = "KhastifySandyBlur"
blur.Size = 0
blur.Parent = Lighting

local function colorAt(t)
    -- Slowly cycle through a palette with smooth interpolation.
    local palette = {
        Color3.fromRGB(45,235,255),
        Color3.fromRGB(25,105,255),
        Color3.fromRGB(125,50,255),
        Color3.fromRGB(235,45,215),
        Color3.fromRGB(255,35,75),
        Color3.fromRGB(255,95,45),
        Color3.fromRGB(45,235,255)
    }
    local period = 18
    local position = ((t % period) / period) * (#palette - 1)
    local i = math.floor(position) + 1
    return palette[i]:Lerp(palette[math.min(i+1,#palette)], position - math.floor(position))
end

local function characterParts()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return character, humanoid, root
end

local function ghost(character, tint)
    local model = Instance.new("Model")
    model.Name = "SandyAfterimage"
    -- Capture each visible part's current world pose. This avoids moving
    -- a complete character model, which could accidentally run scripts.
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart"
            and part.Transparency < 0.95 then
            local clone = Instance.new("Part")
            clone.Name = part.Name
            clone.Size = part.Size
            clone.CFrame = part.CFrame
            clone.Anchored = true
            clone.CanCollide = false
            clone.CanTouch = false
            clone.CanQuery = false
            clone.CastShadow = false
            clone.Material = Enum.Material.Neon
            clone.Color = tint
            clone.Transparency = 0.48
            clone.Parent = model
            local mesh = part:FindFirstChildOfClass("SpecialMesh")
            if mesh then
                mesh:Clone().Parent = clone
            elseif part:IsA("MeshPart") then
                -- MeshPart geometry needs a MeshPart clone; remove descendants.
                clone:Destroy()
                local ok, meshClone = pcall(function() return part:Clone() end)
                if ok and meshClone then
                    for _, child in ipairs(meshClone:GetChildren()) do child:Destroy() end
                    meshClone.Anchored = true
                    meshClone.CanCollide = false
                    meshClone.CanTouch = false
                    meshClone.CanQuery = false
                    meshClone.CastShadow = false
                    meshClone.Material = Enum.Material.Neon
                    meshClone.Color = tint
                    meshClone.TextureID = ""
                    meshClone.Transparency = 0.48
                    meshClone.Parent = model
                end
            end
        end
    end
    model.Parent = ghostFolder
    table.insert(ghosts, {model=model, born=os.clock()})
    if #ghosts > MAX_GHOSTS then
        local oldest = table.remove(ghosts,1)
        oldest.model:Destroy()
    end
end

local function setActive(on)
    active = on
    local _, humanoid = characterParts()
    if on then
        elapsed = 0
        spawnClock = 0
        originalFov = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70
        if humanoid then originalSpeed = humanoid.WalkSpeed end
        cc.Enabled = true
        cc.TintColor = Color3.fromRGB(175,235,255)
        cc.Contrast = 0.12
        cc.Saturation = 0.1
        blur.Size = 10
    else
        if humanoid and originalSpeed then humanoid.WalkSpeed = originalSpeed end
        cc.Enabled = false
        blur.Size = 0
        if workspace.CurrentCamera and originalFov then
            workspace.CurrentCamera.FieldOfView = originalFov
        end
        burst = false
    end
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.X then
        setActive(not active)
    elseif input.KeyCode == Enum.KeyCode.LeftShift then
        burst = true
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.LeftShift then burst = false end
end)
player.CharacterAdded:Connect(function()
    active = false
    originalSpeed = nil
    cc.Enabled = false
    blur.Size = 0
end)

RunService.RenderStepped:Connect(function(dt)
    local now = os.clock()
    for i = #ghosts, 1, -1 do
        local g = ghosts[i]
        local age = now - g.born
        if age >= 0.55 then
            g.model:Destroy()
            table.remove(ghosts, i)
        else
            local transparency = 0.48 + (age / 0.55) * 0.52
            for _, part in ipairs(g.model:GetChildren()) do
                if part:IsA("BasePart") then part.Transparency = transparency end
            end
        end
    end
    if not active then return end
    elapsed += dt
    local character, humanoid, root = characterParts()
    if not character or not humanoid or not root then return end
    local target = (originalSpeed or 16) * (burst and 5 or 3.2)
    humanoid.WalkSpeed += (target - humanoid.WalkSpeed) * math.min(dt * 7, 1)
    local cam = workspace.CurrentCamera
    if cam then
        local fov = (originalFov or 70) + (burst and 22 or 12)
        cam.FieldOfView += (fov - cam.FieldOfView) * math.min(dt * 6, 1)
    end
    blur.Size = math.max(0, blur.Size - dt * 26)
    local tint = colorAt(elapsed)
    cc.TintColor = Color3.new(1,1,1):Lerp(tint, 0.12)
    if humanoid.MoveDirection.Magnitude > 0.1 then
        spawnClock += dt
        local interval = burst and 0.025 or 0.045
        if spawnClock >= interval then
            spawnClock = 0
            ghost(character, tint)
        end
    end
end)
print("KHASTIFY SANDEVISTAN V2 loaded. X = toggle, LeftShift = burst.")
