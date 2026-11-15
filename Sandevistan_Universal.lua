-- KHASTIFY SANDEVISTAN V3
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
local MAX_GHOSTS = 28
local GHOST_LIFETIME = 0.72
local screenGui, flash, vignette, hudText, streakLayer
local lastPos = nil
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
    local period = 24
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

local function buildScreen()
    local pg = player:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("KhastifySandyV3")
    if old then old:Destroy() end
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "KhastifySandyV3"
    screenGui.IgnoreGuiInset = true
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 100
    screenGui.Parent = pg
    flash = Instance.new("Frame")
    flash.Size = UDim2.fromScale(1,1)
    flash.BorderSizePixel = 0
    flash.BackgroundColor3 = Color3.fromRGB(130,245,255)
    flash.BackgroundTransparency = 1
    flash.Parent = screenGui
    vignette = {}
    for _, edge in ipairs({"Top","Bottom","Left","Right"}) do
        local f = Instance.new("Frame")
        f.Name = edge
        f.BorderSizePixel = 0
        f.BackgroundColor3 = Color3.fromRGB(60,130,255)
        f.BackgroundTransparency = 1
        if edge == "Top" or edge == "Bottom" then
            f.Size = UDim2.fromScale(1,0.18)
            f.Position = UDim2.fromScale(0,edge == "Top" and 0 or 0.82)
        else
            f.Size = UDim2.fromScale(0.12,1)
            f.Position = UDim2.fromScale(edge == "Left" and 0 or 0.88,0)
        end
        local grad = Instance.new("UIGradient")
        grad.Rotation = ({Top=90,Bottom=270,Left=0,Right=180})[edge]
        grad.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0,0),
            NumberSequenceKeypoint.new(1,1)
        })
        grad.Parent = f
        f.Parent = screenGui
        table.insert(vignette,f)
    end
    hudText = Instance.new("TextLabel")
    hudText.Size = UDim2.fromOffset(310,38)
    hudText.Position = UDim2.new(0,18,1,-62)
    hudText.BackgroundTransparency = 1
    hudText.Font = Enum.Font.GothamBold
    hudText.TextSize = 17
    hudText.TextXAlignment = Enum.TextXAlignment.Left
    hudText.TextStrokeTransparency = 0.7
    hudText.TextTransparency = 1
    hudText.Text = "◈  SANDEVISTAN // ACTIVE"
    hudText.Parent = screenGui
    streakLayer = Instance.new("Frame")
    streakLayer.BackgroundTransparency = 1
    streakLayer.Size = UDim2.fromScale(1,1)
    streakLayer.Parent = screenGui
end
buildScreen()

local function flashScreen(tint)
    flash.BackgroundColor3 = tint
    flash.BackgroundTransparency = 0.26
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
            clone.Transparency = 0.43
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
                    meshClone.Transparency = 0.43
                    meshClone.Parent = model
                end
            end
        end
    end
    model.Parent = ghostFolder
    -- A second, transparent highlight layer gives each ghost a luminous rim.
    local light = Instance.new("Highlight")
    light.Name = "EnergyRim"
    light.Adornee = model
    light.FillColor = tint
    light.OutlineColor = tint:Lerp(Color3.new(1,1,1),0.55)
    light.FillTransparency = 0.82
    light.OutlineTransparency = 0.28
    light.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    light.Parent = model
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
        flashScreen(Color3.fromRGB(155,245,255))
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
        flashScreen(Color3.fromRGB(255,75,125))
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
        if age >= GHOST_LIFETIME then
            g.model:Destroy()
            table.remove(ghosts, i)
        else
            local transparency = 0.43 + (age / GHOST_LIFETIME) * 0.57
            local highlight = g.model:FindFirstChild("EnergyRim")
            if highlight then
                highlight.OutlineTransparency = 0.28 + 0.72 * (age/GHOST_LIFETIME)
                highlight.FillTransparency = 0.82 + 0.18 * (age/GHOST_LIFETIME)
            end
            for _, part in ipairs(g.model:GetChildren()) do
                if part:IsA("BasePart") then part.Transparency = transparency end
            end
        end
    end
    if flash then flash.BackgroundTransparency = math.min(1,flash.BackgroundTransparency + dt*3.6) end
    local tint = colorAt(elapsed)
    if vignette then
        for _, edge in ipairs(vignette) do
            edge.BackgroundColor3 = tint
            local target = active and (0.73 + math.sin(os.clock()*2.8)*0.035) or 1
            edge.BackgroundTransparency += (target-edge.BackgroundTransparency)*math.min(1,dt*5)
        end
    end
    if hudText then
        hudText.TextColor3 = tint
        local target = active and 0.08 or 1
        hudText.TextTransparency += (target-hudText.TextTransparency)*math.min(1,dt*7)
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
    tint = colorAt(elapsed)
    cc.TintColor = Color3.new(1,1,1):Lerp(tint, 0.12)
    if humanoid.MoveDirection.Magnitude > 0.1 then
        spawnClock += dt
        local interval = burst and 0.028 or 0.05
        if spawnClock >= interval then
            spawnClock = 0
            ghost(character, tint)
            -- Short-lived HUD streaks reinforce velocity without obscuring the view.
            if math.random() < (burst and 0.65 or 0.27) then
                local line = Instance.new("Frame")
                line.BorderSizePixel = 0
                line.BackgroundColor3 = tint
                line.BackgroundTransparency = 0.32
                line.AnchorPoint = Vector2.new(0.5,0.5)
                line.Rotation = math.random(-22,22)
                line.Size = UDim2.fromOffset(math.random(65,170),math.random(1,3))
                line.Position = UDim2.fromScale(math.random(8,92)/100,math.random(15,85)/100)
                line.Parent = streakLayer
                local tween = game:GetService("TweenService"):Create(line,TweenInfo.new(0.18),{
                    BackgroundTransparency=1,
                    Size=UDim2.fromOffset(260,1)
                })
                tween:Play()
                Debris:AddItem(line,0.21)
            end
        end
    end
end)
print("KHASTIFY'S SANDEVISTAN loaded. X = toggle")
