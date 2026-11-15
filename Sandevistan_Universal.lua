-- KHASTIFY SANDEVISTAN V14 - 30-FIGURE SEAMLESS RAINBOW + FIREBASE
-- Client-side cinematic effects for standard Roblox humanoid avatars.
-- X: toggle; K: settings menu. No Shift speed boost.
-- Other players will not necessarily see these local effects.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local active = false
local elapsed = 0
local spawnClock = 0
local originalSpeed = nil
local originalFov = nil
local selectedMultiplier = 3.2
local MIN_MULTIPLIER = 1
local MAX_MULTIPLIER = 40
local menuOpen = false
local idleClock = 0
local MAX_GHOSTS = 320 -- Performance safeguard: oldest snapshots are removed if this limit is reached.
local ghostSequences = {} -- Separate color progression for each player
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
    local period = 20
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
    local old = pg:FindFirstChild("KhastifySandyV4")
    if old then old:Destroy() end
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "KhastifySandyV4"
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

local function clearGhosts(ownerId)
    for i = #ghosts, 1, -1 do
        local g = ghosts[i]
        if ownerId == nil or g.ownerId == ownerId then
            if g.model then g.model:Destroy() end
            table.remove(ghosts, i)
        end
    end
end

-- Each solid-color snapshot keeps its own fixed shade. Traverse the requested sequence
-- GREEN -> BLUE -> PURPLE -> RED -> ORANGE -> YELLOW -> GREEN, then repeat.
local RAINBOW_STOPS = {
    Color3.fromRGB(30, 255, 75), -- green (always first)
    Color3.fromRGB(25, 110, 255), -- blue
    Color3.fromRGB(155, 50, 255), -- purple
    Color3.fromRGB(255, 45, 70), -- red
    Color3.fromRGB(255, 135, 30), -- orange
    Color3.fromRGB(255, 240, 45), -- yellow
    Color3.fromRGB(30, 255, 75), -- back to green
}
local SHADES_PER_TRANSITION = 5 -- 6 transitions x 5 snapshots = 30 unique colors per loop
local function nextGhostColor(ownerId)
    local sequence = ghostSequences[ownerId] or 0
    ghostSequences[ownerId] = sequence + 1
    local total = 30 -- Figure 1 is green; figure 30 blends toward green; figure 31 is green again.
    local step = sequence % total
    local index = math.floor(step / SHADES_PER_TRANSITION) + 1
    local alpha = (step % SHADES_PER_TRANSITION) / SHADES_PER_TRANSITION
    return RAINBOW_STOPS[index]:Lerp(RAINBOW_STOPS[index + 1], alpha)
end

local function ghost(character, ownerId)
    local tint = nextGhostColor(ownerId)
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
            clone.Material = Enum.Material.SmoothPlastic
            clone.Color = tint
            clone.Transparency = 0.12
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
                    meshClone.Material = Enum.Material.SmoothPlastic
                    meshClone.Color = tint
                    meshClone.TextureID = ""
                    meshClone.Transparency = 0.12
                    meshClone.Parent = model
                end
            end
        end
    end
    model.Parent = ghostFolder
    -- Keep only a faint same-color outline: the colored body is the effect.
    local light = Instance.new("Highlight")
    light.Name = "EnergyRim"
    light.Adornee = model
    light.FillColor = tint
    light.OutlineColor = tint
    light.FillTransparency = 1
    light.OutlineTransparency = 0.75
    light.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    light.Parent = model
    table.insert(ghosts, {model=model, ownerId=ownerId})
    if #ghosts > MAX_GHOSTS then
        local oldest = table.remove(ghosts,1)
        oldest.model:Destroy()
    end
end

local function setActive(on)
    active = on
    local _, humanoid = characterParts()
    if on then
        -- Always restart the snapshot gradient at green on activation.
        ghostSequences[player.UserId] = 0
        clearGhosts(player.UserId)
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
        clearGhosts(player.UserId)
        ghostSequences[player.UserId] = nil
        if humanoid and originalSpeed then humanoid.WalkSpeed = originalSpeed end
        cc.Enabled = false
        blur.Size = 0
        if workspace.CurrentCamera and originalFov then
            workspace.CurrentCamera.FieldOfView = originalFov
        end
        flashScreen(Color3.fromRGB(255,75,125))
    end
end

-- KHAS V8: optional Firebase synchronization. Only participants running V8 see remote ghosts.
-- Set the Firebase Web API key from Project Settings > Your apps > Web app > apiKey.
-- This key identifies the Firebase project; it is NOT a service-account secret.
local FIREBASE_DATABASE = "https://khas-relay-default-rtdb.firebaseio.com"
local FIREBASE_API_KEY = "AIzaSyDra6gVAscHi15iq5kfDNYWfQZBOnNfaKA"
local remoteActive = {}
local remoteClocks = {}
local firebaseReady = false
local authToken, authUid, tokenExpires = nil, nil, 0
local requestFunction = (syn and syn.request) or (http and http.request) or http_request or request
local lastHttpWarning = {}
local function httpError(label, detail)
    local now = os.clock()
    if not lastHttpWarning[label] or now - lastHttpWarning[label] >= 15 then
        lastHttpWarning[label] = now
        warn("KHAS Firebase " .. label .. ": " .. tostring(detail))
    end
end
local function httpJson(method, url, payload)
    if type(requestFunction) ~= "function" then return nil, "HTTP request unavailable" end
    local options = {
        Url = url, Method = method,
        Headers = { ["Content-Type"] = "application/json", ["Accept"] = "application/json" }
    }
    if payload ~= nil then options.Body = HttpService:JSONEncode(payload) end
    local ok, response = pcall(requestFunction, options)
    if not ok then return nil, "Request failed: " .. tostring(response) end
    if type(response) ~= "table" then
        return nil, "Unexpected response type " .. type(response) .. " (" .. tostring(response):sub(1, 180) .. ")"
    end
    local code = tonumber(response.StatusCode or response.Status or response.status_code)
    local body = response.Body or response.body or response.ResponseBody
    if type(body) ~= "string" then
        return nil, "Missing/non-string response body (HTTP " .. tostring(code) .. "; body type " .. type(body) .. ")"
    end
    if code and (code < 200 or code >= 300) then
        return nil, "HTTP " .. tostring(code) .. " body=" .. body:sub(1, 200)
    end
    if body == "" then
        return nil, "Empty response body (HTTP " .. tostring(code) .. ")"
    end
    local decodedOk, decoded = pcall(function() return HttpService:JSONDecode(body) end)
    if not decodedOk then
        return nil, "Invalid JSON (HTTP " .. tostring(code) .. "; body=" .. body:sub(1, 180) .. ")"
    end
    return decoded, nil
end
local function authenticate()
    if authToken and os.time() < tokenExpires then return true end
    if FIREBASE_API_KEY == "PASTE_FIREBASE_WEB_API_KEY_HERE" then
        return false, "Set FIREBASE_API_KEY before running multiplayer"
    end
    -- Sign up anonymously. Reauthenticate after expiry; old records age out automatically.
    local result, err = httpJson("POST",
        "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" .. FIREBASE_API_KEY,
        {returnSecureToken = true})
    if not result or not result.idToken or not result.localId then return false, err end
    authToken, authUid = result.idToken, result.localId
    tokenExpires = os.time() + (tonumber(result.expiresIn) or 3600) - 120
    return true
end
local function sessionPath()
    -- JobId separates individual Roblox servers, including different places.
    return "/sessions/" .. tostring(game.PlaceId) .. "_" .. tostring(game.JobId):gsub("[^%w_-]", "_")
end
local function recordUrl(uid)
    return FIREBASE_DATABASE .. sessionPath() .. "/" .. uid .. ".json?auth=" .. authToken
end
local function publishStatus()
    if not firebaseReady then return end
    local ok = authenticate()
    if not ok then return end
    local _, err = httpJson("PUT", recordUrl(authUid), {
        active = active, playerId = player.UserId, updatedAt = os.time()
    })
    if err then httpError("write", err) end
end
local function pollRemote()
    if not firebaseReady then return end
    local ok = authenticate()
    if not ok then return end
    local result, err = httpJson("GET", FIREBASE_DATABASE .. sessionPath() .. ".json?auth=" .. authToken)
    if err then httpError("read", err); return end
    local nextActive = {}
    if type(result) == "table" then
        for uid, state in pairs(result) do
            if uid ~= authUid and type(state) == "table" and state.active == true
                and type(state.playerId) == "number" and type(state.updatedAt) == "number"
                and math.abs(os.time() - state.updatedAt) <= 12 then
                local other = Players:GetPlayerByUserId(state.playerId)
                if other and other ~= player then nextActive[state.playerId] = true end
            end
        end
    end
    for userId in pairs(remoteActive) do
        if not nextActive[userId] then
            clearGhosts(userId)
            ghostSequences[userId] = nil
        end
    end
    remoteActive = nextActive
end
-- HTTP operations run outside RenderStepped, so network latency does not stall rendering.
task.spawn(function()
    if type(requestFunction) ~= "function" then
        warn("KHAS Firebase: executor does not expose a compatible request function")
        return
    end
    local ok, err = authenticate()
    if not ok then httpError("auth", tostring(err)); return end
    firebaseReady = true
    publishStatus()
    while screenGui and screenGui.Parent do
        publishStatus()
        pollRemote()
        task.wait(2)
    end
end)
local remoteTime = 0
RunService.RenderStepped:Connect(function(dt)
    remoteTime += dt
    if remoteTime < 0.11 then return end
    remoteTime = 0
    for userId in pairs(remoteActive) do
        local other = Players:GetPlayerByUserId(userId)
        local char = other and other.Character
        if char then
            remoteClocks[userId] = (remoteClocks[userId] or 0) + 0.11
            ghost(char, userId)
        end
    end
end)

-- Compact draggable-free settings panel, opened and closed with K.
local menu = Instance.new("Frame")
menu.Name = "Settings"
menu.Size = UDim2.fromOffset(330, 174)
menu.Position = UDim2.new(0.5, -165, 0.5, -87)
menu.BackgroundColor3 = Color3.fromRGB(17, 15, 23)
menu.BorderSizePixel = 0
menu.Visible = false
menu.Parent = screenGui
local corner = Instance.new("UICorner", menu)
corner.CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", menu)
stroke.Color = Color3.fromRGB(255, 62, 105)
stroke.Thickness = 2
local title = Instance.new("TextLabel", menu)
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(16, 12)
title.Size = UDim2.fromOffset(298, 32)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 100, 140)
title.Text = "KHASTIFY // SANDEVISTAN"
local caption = Instance.new("TextLabel", menu)
caption.BackgroundTransparency = 1
caption.Position = UDim2.fromOffset(16, 49)
caption.Size = UDim2.fromOffset(298, 23)
caption.Font = Enum.Font.Gotham
caption.TextSize = 14
caption.TextXAlignment = Enum.TextXAlignment.Left
caption.TextColor3 = Color3.fromRGB(230, 230, 240)
local track = Instance.new("Frame", menu)
track.Position = UDim2.fromOffset(20, 93)
track.Size = UDim2.fromOffset(290, 9)
track.BackgroundColor3 = Color3.fromRGB(65, 61, 76)
track.BorderSizePixel = 0
Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
local fill = Instance.new("Frame", track)
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Color3.fromRGB(255, 70, 110)
fill.BorderSizePixel = 0
Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
local handle = Instance.new("TextButton", track)
handle.Size = UDim2.fromOffset(20, 20)
handle.AnchorPoint = Vector2.new(0.5, 0.5)
handle.Position = UDim2.fromScale(0, 0.5)
handle.BackgroundColor3 = Color3.fromRGB(255, 155, 175)
handle.Text = ""
handle.BorderSizePixel = 0
Instance.new("UICorner", handle).CornerRadius = UDim.new(1, 0)
local hint = Instance.new("TextLabel", menu)
hint.BackgroundTransparency = 1
hint.Position = UDim2.fromOffset(16, 122)
hint.Size = UDim2.fromOffset(298, 35)
hint.Font = Enum.Font.Gotham
hint.TextSize = 12
hint.TextColor3 = Color3.fromRGB(170, 165, 185)
hint.Text = "X: Activate / Deactivate     K: Hide Menu"
local dragging = false
local function updateSlider(x)
    local ratio = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
    selectedMultiplier = math.floor((MIN_MULTIPLIER * (MAX_MULTIPLIER / MIN_MULTIPLIER) ^ ratio) * 10 + 0.5) / 10
    caption.Text = string.format("SANDEVISTAN SPEED: %.1fx (base %d)", selectedMultiplier, originalSpeed or 16)
    fill.Size = UDim2.fromScale(ratio, 1)
    handle.Position = UDim2.fromScale(ratio, 0.5)
end
local function refreshSlider()
    local ratio = math.log(selectedMultiplier / MIN_MULTIPLIER) / math.log(MAX_MULTIPLIER / MIN_MULTIPLIER)
    caption.Text = string.format("SANDEVISTAN SPEED: %.1fx (base %d)", selectedMultiplier, originalSpeed or 16)
    fill.Size = UDim2.fromScale(ratio, 1)
    handle.Position = UDim2.fromScale(ratio, 0.5)
end
refreshSlider()
handle.MouseButton1Down:Connect(function() dragging = true end)
track.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        updateSlider(input.Position.X)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        updateSlider(input.Position.X)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
end)
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.X then
        setActive(not active)
        task.spawn(publishStatus)
    elseif input.KeyCode == Enum.KeyCode.K then
        menuOpen = not menuOpen
        menu.Visible = menuOpen
    end
end)
player.CharacterAdded:Connect(function()
    active = false
    clearGhosts(player.UserId)
    ghostSequences[player.UserId] = nil
    task.spawn(publishStatus)
    originalSpeed = nil
    cc.Enabled = false
    blur.Size = 0
end)

RunService.RenderStepped:Connect(function(dt)
    -- Persistent snapshots do not fade. They remain until their owner deactivates.
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
    local target = (originalSpeed or 16) * selectedMultiplier
    caption.Text = string.format("SANDEVISTAN SPEED: %.1fx (base %d)", selectedMultiplier, originalSpeed or 16)
    humanoid.WalkSpeed += (target - humanoid.WalkSpeed) * math.min(dt * 7, 1)
    local cam = workspace.CurrentCamera
    if cam then
        local fov = (originalFov or 70) + 12
        cam.FieldOfView += (fov - cam.FieldOfView) * math.min(dt * 6, 1)
    end
    blur.Size = math.max(0, blur.Size - dt * 26)
    tint = colorAt(elapsed)
    cc.TintColor = Color3.new(1,1,1):Lerp(tint, 0.12)
    if humanoid.MoveDirection.Magnitude <= 0.1 then
        idleClock += dt
        if idleClock >= 0.15 then
            idleClock = 0
            ghost(character, player.UserId)
        end
    else
        idleClock = 0
    end
    if humanoid.MoveDirection.Magnitude > 0.1 then
        spawnClock += dt
        local interval = 0.045
        if spawnClock >= interval then
            spawnClock = 0
            ghost(character, player.UserId)
            -- Short-lived HUD streaks reinforce velocity without obscuring the view.
            if math.random() < 0.35 then
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
print("KHASTIFY SANDEVISTAN V13 vivid rainbow trails loaded. X = toggle, K = settings menu.")
