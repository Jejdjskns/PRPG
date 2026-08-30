-- Load Orion
local OrionLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/Qanuir/orion-ui/refs/heads/main/source.lua"))()

-- Core
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInput = game:GetService("VirtualInputManager")
local player = Players.LocalPlayer

-- ===== CONFIG =====
local MINING_KEY = Enum.KeyCode.E
local ATTACK_KEY = Enum.KeyCode.E
local ORE_OFFSET = -7
local MOB_OFFSET = -6
local CHEST_OFFSET = -5
local OIL_OFFSET = -5
local WOOD_OFFSET = -5
local PICKAXE_SLOT = 6
local SWORD_SLOT = 8
local AXE_SLOT = 9
local BUCKET_SLOT = 4
local SUMMON_SLOT = 9
local CLICK_DELAY = 0.05
local SEARCH_COOLDOWN = 0.2
-- ===================

-- Preset lists
local PRESET_ORES = {"cobalt", "neo vermite", "mythril", "titanium"}
local PRESET_VERMITE_STEEL = {"vermite", "steel"}
local PRESET_GOLD_IRON = {"gold", "iron"}
local PRESET_GRASS = {"grass monster", "overgrown grass monster", "giant grass monster"}
local PRESET_ZOMBIE_STONE = {"zombie miner", "stone creature", "strong stone creature"}

-- State
local miningEnabled = false
local farmingEnabled = false
local chestEnabled = false
local oilEnabled = false
local woodEnabled = false
local bossFarmingEnabled = false
local presetMiningEnabled = false
local presetVermiteSteelEnabled = false
local presetGoldIronEnabled = false
local presetGrassEnabled = false
local presetZombieStoneEnabled = false
local selectedOre = nil
local selectedMob = nil
local miningLoop = nil
local farmingLoop = nil
local chestLoop = nil
local oilLoop = nil
local woodLoop = nil
local bossLoop = nil
local bodyPosition = nil
local bodyGyro = nil
local noclipConnection = nil
local currentTarget = nil
local currentTargetModel = nil
local lastSearchTime = 0
local character, humanoid, rootPart
local lowestPartCache = {}
local currentlyEquippedSlot = nil
local safePosition = nil
local bossSummonCooldown = 0

local function refreshChar()
    character = player.Character or player.CharacterAdded:Wait()
    humanoid = character:WaitForChild("Humanoid")
    rootPart = character:WaitForChild("HumanoidRootPart")
    currentlyEquippedSlot = nil
end
refreshChar()

-- ===== NOCLIP =====
local function startNoclipLoop()
    if noclipConnection then return end
    noclipConnection = RunService.Heartbeat:Connect(function()
        if not character then return end
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function stopNoclipLoop()
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
end

local function anyModeActive()
    return miningEnabled or farmingEnabled or chestEnabled or oilEnabled or woodEnabled or bossFarmingEnabled
end

-- ===== UTILITY FUNCTIONS =====
function getOreList()
    local spawners = workspace:FindFirstChild("Ores") and workspace.Ores:FindFirstChild("SpawnedOres")
    if not spawners then return {} end
    local seen = {}
    local names = {}
    for _, ore in ipairs(spawners:GetChildren()) do
        local name = ore.Name:lower()
        if name ~= "oil" then
            if not seen[name] then
                seen[name] = true
                table.insert(names, name)
            end
        end
    end
    table.sort(names)
    return names
end

function getMobList()
    local folder = workspace:FindFirstChild("EnemiesSpawned")
    if not folder then return {} end
    local seen = {}
    local names = {}
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Model") and child.Name ~= "AttackingDummy" then
            local name = child.Name
            if not seen[name] then
                seen[name] = true
                table.insert(names, name)
            end
        end
    end
    table.sort(names)
    return names
end

local function findOre(oreNames)
    if not oreNames or type(oreNames) ~= "table" or #oreNames == 0 then return nil end
    local spawners = workspace:FindFirstChild("Ores") and workspace.Ores:FindFirstChild("SpawnedOres")
    if not spawners then return nil end
    local nearest, minDist = nil, math.huge
    for _, ore in ipairs(spawners:GetChildren()) do
        local oreNameLow = ore.Name:lower()
        for _, target in ipairs(oreNames) do
            if target and oreNameLow:find(target:lower()) then
                local part = ore:IsA("BasePart") and ore or ore:FindFirstChildWhichIsA("BasePart", true)
                if part then
                    local dist = (rootPart.Position - part.Position).Magnitude
                    if dist < minDist then
                        minDist = dist
                        nearest = part
                    end
                end
                break
            end
        end
    end
    return nearest
end

local function findOil()
    local spawners = workspace:FindFirstChild("Ores") and workspace.Ores:FindFirstChild("SpawnedOres")
    if not spawners then return nil end
    local nearest, minDist = nil, math.huge
    for _, ore in ipairs(spawners:GetChildren()) do
        if ore.Name:lower() == "oil" then
            local part = ore:IsA("BasePart") and ore or ore:FindFirstChildWhichIsA("BasePart", true)
            if part then
                local dist = (rootPart.Position - part.Position).Magnitude
                if dist < minDist then
                    minDist = dist
                    nearest = part
                end
            end
        end
    end
    return nearest
end

local function findTree()
    local treesFolder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Trees")
    if not treesFolder then return nil end
    local nearest, minDist = nil, math.huge
    for _, tree in ipairs(treesFolder:GetChildren()) do
        local part = tree:IsA("BasePart") and tree or tree:FindFirstChildWhichIsA("BasePart", true)
        if part then
            local dist = (rootPart.Position - part.Position).Magnitude
            if dist < minDist then
                minDist = dist
                nearest = part
            end
        end
    end
    return nearest
end

local function findMob(mobNames)
    if not mobNames or type(mobNames) ~= "table" or #mobNames == 0 then return nil end
    local folder = workspace:FindFirstChild("EnemiesSpawned")
    if not folder then return nil end
    local nearest, minDist = nil, math.huge
    for _, mob in ipairs(folder:GetChildren()) do
        if mob:IsA("Model") then
            local mobNameLow = mob.Name:lower()
            for _, target in ipairs(mobNames) do
                if target and mobNameLow:find(target:lower()) then
                    local h = mob:FindFirstChild("Humanoid")
                    if h and h.Health > 0 then
                        local root = mob:FindFirstChild("HumanoidRootPart")
                        if root then
                            local dist = (rootPart.Position - root.Position).Magnitude
                            if dist < minDist then
                                minDist = dist
                                nearest = root
                            end
                        end
                    end
                    break
                end
            end
        end
    end
    return nearest
end

local function findChest()
    local folder = workspace:FindFirstChild("Chests")
    if not folder then return nil end
    local nearest, minDist = nil, math.huge
    for _, chest in ipairs(folder:GetChildren()) do
        local part = chest:IsA("BasePart") and chest or chest:FindFirstChildWhichIsA("BasePart", true)
        if part then
            local dist = (rootPart.Position - part.Position).Magnitude
            if dist < minDist then
                minDist = dist
                nearest = part
            end
        end
    end
    return nearest
end

function getLowestPart(model)
    if not model then return nil end
    if lowestPartCache[model] then
        return lowestPartCache[model]
    end
    local lowest = nil
    local minY = math.huge
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            local y = part.Position.Y
            if y < minY then
                minY = y
                lowest = part
            end
        end
    end
    if lowest then
        lowestPartCache[model] = lowest
    end
    return lowest
end

-- ===== EQUIP SLOT =====
function equipSlot(slot)
    if slot == currentlyEquippedSlot then return end
    local key = Enum.KeyCode.Seven
    if slot == 1 then key = Enum.KeyCode.One
    elseif slot == 2 then key = Enum.KeyCode.Two
    elseif slot == 3 then key = Enum.KeyCode.Three
    elseif slot == 4 then key = Enum.KeyCode.Four
    elseif slot == 5 then key = Enum.KeyCode.Five
    elseif slot == 6 then key = Enum.KeyCode.Six
    elseif slot == 7 then key = Enum.KeyCode.Seven
    elseif slot == 8 then key = Enum.KeyCode.Eight
    elseif slot == 9 then key = Enum.KeyCode.Nine
    end
    pcall(function()
        VirtualInput:SendKeyEvent(true, key, false, game)
        task.wait(0.05)
        VirtualInput:SendKeyEvent(false, key, false, game)
    end)
    currentlyEquippedSlot = slot
    task.wait(0.1)
end

-- ===== REUSABLE PHYSICS =====
function ensurePhysics()
    if not bodyPosition then
        bodyPosition = Instance.new("BodyPosition")
        bodyPosition.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        bodyPosition.P = 5000
        bodyPosition.D = 1000
        bodyPosition.Parent = rootPart
    end
    if not bodyGyro then
        bodyGyro = Instance.new("BodyGyro")
        bodyGyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
        bodyGyro.P = 5000
        bodyGyro.D = 1000
        bodyGyro.Parent = rootPart
    end
end

function destroyPhysics()
    if bodyPosition then bodyPosition:Destroy() end
    bodyPosition = nil
    if bodyGyro then bodyGyro:Destroy() end
    bodyGyro = nil
end

function positionUnderTarget(targetPart, targetModel, offset)
    if not targetPart then return end
    local basePart = targetPart
    if targetModel and targetModel:IsA("Model") then
        local legs = getLowestPart(targetModel)
        if legs then basePart = legs end
    end
    local targetPos = basePart.Position + Vector3.new(0, offset, 0)
    rootPart.CFrame = CFrame.new(targetPos, basePart.Position)
    rootPart.Velocity = Vector3.new(0,0,0)
    rootPart.RotVelocity = Vector3.new(0,0,0)

    humanoid.AutoRotate = false
    humanoid.PlatformStand = true

    ensurePhysics()
    bodyPosition.Position = targetPos
    bodyGyro.CFrame = CFrame.new(rootPart.Position, basePart.Position)
end

local function clickAtCorner()
    local screenSize = workspace.CurrentCamera.ViewportSize
    local cornerX = screenSize.X - 20
    local cornerY = 20
    pcall(function()
        VirtualInput:SendMouseMovement(cornerX, cornerY, 0)
    end)
    task.wait(CLICK_DELAY)
    pcall(function()
        VirtualInput:SendMouseButtonEvent(Enum.UserInputType.MouseButton1, 0, true, game)
        task.wait(0.03)
        VirtualInput:SendMouseButtonEvent(Enum.UserInputType.MouseButton1, 0, false, game)
    end)
end

local function rightClick()
    pcall(function()
        VirtualInput:SendMouseButtonEvent(Enum.UserInputType.MouseButton2, 0, true, game)
        task.wait(0.05)
        VirtualInput:SendMouseButtonEvent(Enum.UserInputType.MouseButton2, 0, false, game)
    end)
end

-- ===== BOSS FINDER =====
local function findBoss()
    local folder = workspace:FindFirstChild("EnemiesSpawned")
    if folder then
        local boss = folder:FindFirstChild("Prime Soul")
        if boss and boss:IsA("Model") then
            local root = boss:FindFirstChild("HumanoidRootPart")
            if root then
                local h = boss:FindFirstChild("Humanoid")
                if h and h.Health > 0 then
                    return root
                end
            end
        end
    end
    return nil
end

-- ===== TARGET LISTS =====
local function getTargetOres()
    local targetOres = {}
    if presetMiningEnabled then
        for _, ore in ipairs(PRESET_ORES) do table.insert(targetOres, ore) end
    end
    if presetVermiteSteelEnabled then
        for _, ore in ipairs(PRESET_VERMITE_STEEL) do table.insert(targetOres, ore) end
    end
    if presetGoldIronEnabled then
        for _, ore in ipairs(PRESET_GOLD_IRON) do table.insert(targetOres, ore) end
    end
    if #targetOres == 0 and selectedOre then
        targetOres = {selectedOre}
    end
    return targetOres
end

local function getTargetMobs()
    local mobs = {}
    if presetGrassEnabled then
        for _, m in ipairs(PRESET_GRASS) do table.insert(mobs, m) end
    end
    if presetZombieStoneEnabled then
        for _, m in ipairs(PRESET_ZOMBIE_STONE) do table.insert(mobs, m) end
    end
    if #mobs == 0 and selectedMob then
        mobs = {selectedMob}
    end
    return mobs
end

-- ===== ACTIONS =====
local function mineAction()
    if presetVermiteSteelEnabled then
        local oilPart = findOil()
        if oilPart then
            if not currentTarget or currentTarget ~= oilPart or not currentTarget.Parent then
                currentTarget = oilPart
                equipSlot(BUCKET_SLOT)
                positionUnderTarget(oilPart, nil, OIL_OFFSET)
            end
            clickAtCorner()
            if not findOil() then
                currentTarget = nil
                equipSlot(PICKAXE_SLOT)
            end
            return
        end
    end

    local targetOres = getTargetOres()
    if #targetOres == 0 then return end

    local now = tick()
    if (not currentTarget or not currentTarget.Parent) and now - lastSearchTime >= SEARCH_COOLDOWN then
        currentTarget = findOre(targetOres)
        lastSearchTime = now
        if currentTarget then
            equipSlot(PICKAXE_SLOT)
            positionUnderTarget(currentTarget, nil, ORE_OFFSET)
        else
            return
        end
    end
    if not currentTarget or not currentTarget.Parent then return end
    clickAtCorner()
    pcall(function()
        VirtualInput:SendKeyEvent(true, MINING_KEY, false, game)
        task.wait(0.03)
        VirtualInput:SendKeyEvent(false, MINING_KEY, false, game)
    end)
end

local function oilAction()
    local now = tick()
    if (not currentTarget or not currentTarget.Parent) and now - lastSearchTime >= SEARCH_COOLDOWN then
        currentTarget = findOil()
        lastSearchTime = now
        if currentTarget then
            equipSlot(BUCKET_SLOT)
            positionUnderTarget(currentTarget, nil, OIL_OFFSET)
        else
            return
        end
    end
    if not currentTarget or not currentTarget.Parent then return end
    clickAtCorner()
end

local function woodAction()
    local now = tick()
    if (not currentTarget or not currentTarget.Parent) and now - lastSearchTime >= SEARCH_COOLDOWN then
        currentTarget = findTree()
        lastSearchTime = now
        if currentTarget then
            equipSlot(AXE_SLOT)
            positionUnderTarget(currentTarget, nil, WOOD_OFFSET)
        else
            return
        end
    end
    if not currentTarget or not currentTarget.Parent then return end
    clickAtCorner()
end

local function farmAction()
    local targetMobs = getTargetMobs()
    if #targetMobs == 0 then return end

    local now = tick()
    local needSearch = not currentTarget or not currentTarget.Parent

    if needSearch and now - lastSearchTime >= SEARCH_COOLDOWN then
        local found = findMob(targetMobs)
        if found then
            currentTarget = found
            currentTargetModel = currentTarget.Parent
            equipSlot(SWORD_SLOT)
            positionUnderTarget(currentTarget, currentTargetModel, MOB_OFFSET)
            lastSearchTime = now
        else
            lastSearchTime = now
            return
        end
    end

    if not currentTarget or not currentTarget.Parent then return end

    local mob = currentTarget.Parent
    if not mob or not mob:IsA("Model") then
        currentTarget = nil
        return
    end
    local h = mob:FindFirstChild("Humanoid")
    if not h or h.Health <= 0 then
        currentTarget = nil
        return
    end

    positionUnderTarget(currentTarget, mob, MOB_OFFSET)
    clickAtCorner()
    pcall(function()
        VirtualInput:SendKeyEvent(true, ATTACK_KEY, false, game)
        task.wait(0.03)
        VirtualInput:SendKeyEvent(false, ATTACK_KEY, false, game)
    end)
end

local function chestAction()
    local now = tick()
    if (not currentTarget or not currentTarget.Parent) and now - lastSearchTime >= SEARCH_COOLDOWN then
        currentTarget = findChest()
        lastSearchTime = now
        if currentTarget then
            positionUnderTarget(currentTarget, nil, CHEST_OFFSET)
        else
            return
        end
    end
    if not currentTarget or not currentTarget.Parent then return end
    clickAtCorner()
    local nextChest = findChest()
    if nextChest and nextChest ~= currentTarget then
        currentTarget = nextChest
        positionUnderTarget(currentTarget, nil, CHEST_OFFSET)
    elseif not nextChest then
        currentTarget = nil
    end
end

-- ===== BOSS LOOP (Follow + Face) =====
function startBossLoop()
    if bossLoop then bossLoop:Disconnect() end
    bossLoop = RunService.Heartbeat:Connect(function()
        if not bossFarmingEnabled then return end
        if not character or not character.Parent or not humanoid or humanoid.Health <= 0 then
            player.CharacterAdded:Wait()
            refreshChar()
            startNoclipLoop()
            return
        end

        local bossPart = findBoss()

        if bossPart then
            -- Boss exists – equip sword once, then attack
            if not currentTarget or currentTarget ~= bossPart or not currentTarget.Parent then
                currentTarget = bossPart
                currentTargetModel = bossPart.Parent
                equipSlot(SWORD_SLOT)
            end
            -- ✅ Always reposition under the boss (follow and face)
            positionUnderTarget(bossPart, currentTargetModel, MOB_OFFSET)
            -- Attack
            clickAtCorner()
            pcall(function()
                VirtualInput:SendKeyEvent(true, ATTACK_KEY, false, game)
                task.wait(0.03)
                VirtualInput:SendKeyEvent(false, ATTACK_KEY, false, game)
            end)
        else
            -- No boss – return to safe spot and summon
            if safePosition and (rootPart.Position - safePosition).Magnitude > 1 then
                rootPart.CFrame = CFrame.new(safePosition)
                rootPart.Velocity = Vector3.new(0,0,0)
                rootPart.RotVelocity = Vector3.new(0,0,0)
            end
            if tick() - bossSummonCooldown >= 1.0 then
                currentlyEquippedSlot = nil
                equipSlot(SUMMON_SLOT)
                rightClick()
                bossSummonCooldown = tick()
                print("🔄 Summoning Prime Soul...")
            end
            if currentTarget then
                currentTarget = nil
                currentTargetModel = nil
            end
        end
    end)
end

-- ===== LOOPS =====
function startMiningLoop()
    if miningLoop then miningLoop:Disconnect() end
    miningLoop = RunService.Heartbeat:Connect(function()
        if not miningEnabled then return end
        if not character or not character.Parent or not humanoid or humanoid.Health <= 0 then
            player.CharacterAdded:Wait()
            refreshChar()
            equipSlot(PICKAXE_SLOT)
            return
        end
        mineAction()
    end)
end

function startFarmingLoop()
    if farmingLoop then farmingLoop:Disconnect() end
    farmingLoop = RunService.Heartbeat:Connect(function()
        if not farmingEnabled then return end
        if not character or not character.Parent or not humanoid or humanoid.Health <= 0 then
            player.CharacterAdded:Wait()
            refreshChar()
            equipSlot(SWORD_SLOT)
            return
        end
        farmAction()
    end)
end

function startChestLoop()
    if chestLoop then chestLoop:Disconnect() end
    chestLoop = RunService.Heartbeat:Connect(function()
        if not chestEnabled then return end
        if not character or not character.Parent or not humanoid or humanoid.Health <= 0 then
            player.CharacterAdded:Wait()
            refreshChar()
            return
        end
        chestAction()
    end)
end

function startOilLoop()
    if oilLoop then oilLoop:Disconnect() end
    oilLoop = RunService.Heartbeat:Connect(function()
        if not oilEnabled then return end
        if not character or not character.Parent or not humanoid or humanoid.Health <= 0 then
            player.CharacterAdded:Wait()
            refreshChar()
            equipSlot(BUCKET_SLOT)
            return
        end
        oilAction()
    end)
end

function startWoodLoop()
    if woodLoop then woodLoop:Disconnect() end
    woodLoop = RunService.Heartbeat:Connect(function()
        if not woodEnabled then return end
        if not character or not character.Parent or not humanoid or humanoid.Health <= 0 then
            player.CharacterAdded:Wait()
            refreshChar()
            equipSlot(AXE_SLOT)
            return
        end
        woodAction()
    end)
end

-- ===== TOGGLES =====
function toggleMining(state)
    miningEnabled = state
    if miningEnabled then
        farmingEnabled = false; chestEnabled = false; oilEnabled = false; woodEnabled = false; bossFarmingEnabled = false
        if farmingLoop then farmingLoop:Disconnect() farmingLoop = nil end
        if chestLoop then chestLoop:Disconnect() chestLoop = nil end
        if oilLoop then oilLoop:Disconnect() oilLoop = nil end
        if woodLoop then woodLoop:Disconnect() woodLoop = nil end
        if bossLoop then bossLoop:Disconnect() bossLoop = nil end
        if #getTargetOres() == 0 then warn("Enable a preset or select an ore.") miningEnabled = false return end
        startNoclipLoop()
        equipSlot(PICKAXE_SLOT)
        currentTarget = nil
        startMiningLoop()
    else
        if miningLoop then miningLoop:Disconnect() miningLoop = nil end
        destroyPhysics()
        humanoid.AutoRotate = true; humanoid.PlatformStand = false
        if not anyModeActive() then stopNoclipLoop() end
        currentTarget = nil
    end
end

function toggleFarming(state)
    farmingEnabled = state
    if farmingEnabled then
        miningEnabled = false; chestEnabled = false; oilEnabled = false; woodEnabled = false; bossFarmingEnabled = false
        if miningLoop then miningLoop:Disconnect() miningLoop = nil end
        if chestLoop then chestLoop:Disconnect() chestLoop = nil end
        if oilLoop then oilLoop:Disconnect() oilLoop = nil end
        if woodLoop then woodLoop:Disconnect() woodLoop = nil end
        if bossLoop then bossLoop:Disconnect() bossLoop = nil end

        local targetMobs = getTargetMobs()
        if #targetMobs == 0 then
            warn("⚠️ Select a mob or enable a preset.")
            farmingEnabled = false
            return
        end
        print("🟢 Farming enabled, targeting:", table.concat(targetMobs, ", "))
        startNoclipLoop()
        equipSlot(SWORD_SLOT)
        currentTarget = nil
        lastSearchTime = 0
        startFarmingLoop()
    else
        if farmingLoop then farmingLoop:Disconnect() farmingLoop = nil end
        destroyPhysics()
        humanoid.AutoRotate = true; humanoid.PlatformStand = false
        if not anyModeActive() then stopNoclipLoop() end
        currentTarget = nil
        print("🔴 Farming disabled.")
    end
end

function toggleChest(state)
    chestEnabled = state
    if chestEnabled then
        miningEnabled = false; farmingEnabled = false; oilEnabled = false; woodEnabled = false; bossFarmingEnabled = false
        if miningLoop then miningLoop:Disconnect() miningLoop = nil end
        if farmingLoop then farmingLoop:Disconnect() farmingLoop = nil end
        if oilLoop then oilLoop:Disconnect() oilLoop = nil end
        if woodLoop then woodLoop:Disconnect() woodLoop = nil end
        if bossLoop then bossLoop:Disconnect() bossLoop = nil end
        startNoclipLoop()
        currentTarget = nil
        startChestLoop()
    else
        if chestLoop then chestLoop:Disconnect() chestLoop = nil end
        destroyPhysics()
        humanoid.AutoRotate = true; humanoid.PlatformStand = false
        if not anyModeActive() then stopNoclipLoop() end
        currentTarget = nil
    end
end

function toggleOil(state)
    oilEnabled = state
    if oilEnabled then
        miningEnabled = false; farmingEnabled = false; chestEnabled = false; woodEnabled = false; bossFarmingEnabled = false
        if miningLoop then miningLoop:Disconnect() miningLoop = nil end
        if farmingLoop then farmingLoop:Disconnect() farmingLoop = nil end
        if chestLoop then chestLoop:Disconnect() chestLoop = nil end
        if woodLoop then woodLoop:Disconnect() woodLoop = nil end
        if bossLoop then bossLoop:Disconnect() bossLoop = nil end
        startNoclipLoop()
        equipSlot(BUCKET_SLOT)
        currentTarget = nil
        startOilLoop()
    else
        if oilLoop then oilLoop:Disconnect() oilLoop = nil end
        destroyPhysics()
        humanoid.AutoRotate = true; humanoid.PlatformStand = false
        if not anyModeActive() then stopNoclipLoop() end
        currentTarget = nil
    end
end

function toggleWood(state)
    woodEnabled = state
    if woodEnabled then
        miningEnabled = false; farmingEnabled = false; chestEnabled = false; oilEnabled = false; bossFarmingEnabled = false
        if miningLoop then miningLoop:Disconnect() miningLoop = nil end
        if farmingLoop then farmingLoop:Disconnect() farmingLoop = nil end
        if chestLoop then chestLoop:Disconnect() chestLoop = nil end
        if oilLoop then oilLoop:Disconnect() oilLoop = nil end
        if bossLoop then bossLoop:Disconnect() bossLoop = nil end
        startNoclipLoop()
        equipSlot(AXE_SLOT)
        currentTarget = nil
        startWoodLoop()
    else
        if woodLoop then woodLoop:Disconnect() woodLoop = nil end
        destroyPhysics()
        humanoid.AutoRotate = true; humanoid.PlatformStand = false
        if not anyModeActive() then stopNoclipLoop() end
        currentTarget = nil
    end
end

function toggleBossFarming(state)
    bossFarmingEnabled = state
    if bossFarmingEnabled then
        miningEnabled = false; farmingEnabled = false; chestEnabled = false; oilEnabled = false; woodEnabled = false
        if miningLoop then miningLoop:Disconnect() miningLoop = nil end
        if farmingLoop then farmingLoop:Disconnect() farmingLoop = nil end
        if chestLoop then chestLoop:Disconnect() chestLoop = nil end
        if oilLoop then oilLoop:Disconnect() oilLoop = nil end
        if woodLoop then woodLoop:Disconnect() woodLoop = nil end

        safePosition = rootPart.Position
        startNoclipLoop()
        currentTarget = nil
        currentTargetModel = nil
        bossSummonCooldown = 0
        startBossLoop()
        print("🟢 Boss farming started. Safe position saved.")
    else
        if bossLoop then bossLoop:Disconnect() bossLoop = nil end
        destroyPhysics()
        humanoid.AutoRotate = true; humanoid.PlatformStand = false
        if not anyModeActive() then stopNoclipLoop() end
        currentTarget = nil
        print("🔴 Boss farming stopped.")
    end
end

-- ===== PRESET TOGGLES =====
function togglePresetMining(state)
    presetMiningEnabled = state
    if miningEnabled then
        toggleMining(false)
        task.wait(0.1)
        toggleMining(true)
    end
end

function togglePresetVermiteSteel(state)
    presetVermiteSteelEnabled = state
    if miningEnabled then
        toggleMining(false)
        task.wait(0.1)
        toggleMining(true)
    end
end

function togglePresetGoldIron(state)
    presetGoldIronEnabled = state
    if miningEnabled then
        toggleMining(false)
        task.wait(0.1)
        toggleMining(true)
    end
end

function togglePresetGrass(state)
    presetGrassEnabled = state
    if farmingEnabled then
        toggleFarming(false)
        task.wait(0.1)
        toggleFarming(true)
    end
end

function togglePresetZombieStone(state)
    presetZombieStoneEnabled = state
    if farmingEnabled then
        toggleFarming(false)
        task.wait(0.1)
        toggleFarming(true)
    end
end

-- ===== UI =====
if OrionLib then
    local Window = OrionLib:MakeWindow({
        Name = "Xeroc - Providence RPG",
        HidePremium = false,
        SaveConfig = true,
        ConfigFolder = "AutoFarm"
    })

    -- MINING TAB
    local MiningTab = Window:MakeTab({ Name = "Mining", Icon = "rbxassetid://4483345998" })
    local MineSection = MiningTab:AddSection({ Name = "Ore Selection" })
    local oreOptions = getOreList()
    local DropdownOre = MineSection:AddDropdown({
        Name = "Select Ore (single)",
        Options = oreOptions,
        Callback = function(v) selectedOre = v end
    })
    local PresetToggle = MineSection:AddToggle({
        Name = "Preset 1: Cobalt, Neo Vermite, Mythril, Titanium",
        Default = false,
        Callback = function(v) togglePresetMining(v) end
    })
    local PresetToggle2 = MineSection:AddToggle({
        Name = "Preset 2: Vermite, Steel (collects oil first)",
        Default = false,
        Callback = function(v) togglePresetVermiteSteel(v) end
    })
    local PresetToggle3 = MineSection:AddToggle({
        Name = "Preset 3: Gold, Iron",
        Default = false,
        Callback = function(v) togglePresetGoldIron(v) end
    })
    local ToggleMine = MineSection:AddToggle({
        Name = "Auto-Mine",
        Default = false,
        Callback = function(v) toggleMining(v) end
    })
    local StatusMine = MiningTab:AddSection({ Name = "Status" })
    local MineStatus = StatusMine:AddLabel("Idle")
    local oldMineToggle = ToggleMine.Set
    ToggleMine.Set = function(self, v)
        oldMineToggle(self, v)
        local oreList = "None"
        if presetMiningEnabled and presetVermiteSteelEnabled and presetGoldIronEnabled then
            oreList = "All Presets"
        elseif presetMiningEnabled and presetVermiteSteelEnabled then
            oreList = "Preset 1 + 2 (with oil)"
        elseif presetMiningEnabled and presetGoldIronEnabled then
            oreList = "Preset 1 + 3"
        elseif presetVermiteSteelEnabled and presetGoldIronEnabled then
            oreList = "Preset 2 + 3 (oil with 2)"
        elseif presetMiningEnabled then
            oreList = "Preset 1 (Cobalt, Neo Vermite, Mythril, Titanium)"
        elseif presetVermiteSteelEnabled then
            oreList = "Preset 2 (Vermite, Steel + oil first)"
        elseif presetGoldIronEnabled then
            oreList = "Preset 3 (Gold, Iron)"
        elseif selectedOre then
            oreList = selectedOre:upper()
        end
        MineStatus:Set("Status: " .. (v and "Mining: " .. oreList or "Idle"))
    end

    -- FARMING TAB
    local FarmTab = Window:MakeTab({ Name = "Farming", Icon = "rbxassetid://4483345998" })
    local FarmSection = FarmTab:AddSection({ Name = "Mob Selection" })
    local mobOptions = getMobList()
    local DropdownMob = FarmSection:AddDropdown({
        Name = "Select Mob",
        Options = mobOptions,
        Callback = function(v) selectedMob = v end
    })

    local GrassPresetToggle = FarmSection:AddToggle({
        Name = "🌿 Farm Grass Mobs (Grass, Overgrown, Giant)",
        Default = false,
        Callback = function(v) togglePresetGrass(v) end
    })

    local ZombieStonePresetToggle = FarmSection:AddToggle({
        Name = "🪨 Zombie Miners & Stone Creatures",
        Default = false,
        Callback = function(v) togglePresetZombieStone(v) end
    })

    local ToggleFarm = FarmSection:AddToggle({
        Name = "Auto-Farm (follows mob)",
        Default = false,
        Callback = function(v) toggleFarming(v) end
    })
    local StatusFarm = FarmTab:AddSection({ Name = "Status" })
    local FarmStatus = StatusFarm:AddLabel("Idle")
    local oldFarmToggle = ToggleFarm.Set
    ToggleFarm.Set = function(self, v)
        oldFarmToggle(self, v)
        local mobList = "None"
        if presetGrassEnabled and presetZombieStoneEnabled then
            mobList = "Grass + Zombie/Stone"
        elseif presetGrassEnabled then
            mobList = "Grass Mobs"
        elseif presetZombieStoneEnabled then
            mobList = "Zombie Miners & Stone Creatures"
        elseif selectedMob then
            mobList = selectedMob:upper()
        end
        FarmStatus:Set("Status: " .. (v and "Farming: " .. mobList or "Idle"))
    end

    -- CHESTS TAB
    local ChestTab = Window:MakeTab({ Name = "Chests", Icon = "rbxassetid://4483345998" })
    local ChestSection = ChestTab:AddSection({ Name = "Auto-Collect" })
    local ToggleChest = ChestSection:AddToggle({
        Name = "Auto-Chest",
        Default = false,
        Callback = function(v) toggleChest(v) end
    })
    local StatusChest = ChestTab:AddSection({ Name = "Status" })
    local ChestStatus = StatusChest:AddLabel("Idle")
    local oldChestToggle = ToggleChest.Set
    ToggleChest.Set = function(self, v)
        oldChestToggle(self, v)
        ChestStatus:Set("Status: " .. (v and "Collecting chests" or "Idle"))
    end

    -- OIL TAB
    local OilTab = Window:MakeTab({ Name = "Oil", Icon = "rbxassetid://4483345998" })
    local OilSection = OilTab:AddSection({ Name = "Oil Collection" })
    local ToggleOil = OilSection:AddToggle({
        Name = "Collect Oil (equips bucket, clicks oil)",
        Default = false,
        Callback = function(v) toggleOil(v) end
    })
    local StatusOil = OilTab:AddSection({ Name = "Status" })
    local OilStatus = StatusOil:AddLabel("Idle")
    local oldOilToggle = ToggleOil.Set
    ToggleOil.Set = function(self, v)
        oldOilToggle(self, v)
        OilStatus:Set("Status: " .. (v and "Collecting oil" or "Idle"))
    end

    -- WOOD TAB
    local WoodTab = Window:MakeTab({ Name = "Wood", Icon = "rbxassetid://4483345998" })
    local WoodSection = WoodTab:AddSection({ Name = "Tree Chopping" })
    local ToggleWood = WoodSection:AddToggle({
        Name = "Chop Wood (equips axe, clicks tree)",
        Default = false,
        Callback = function(v) toggleWood(v) end
    })
    local StatusWood = WoodTab:AddSection({ Name = "Status" })
    local WoodStatus = StatusWood:AddLabel("Idle")
    local oldWoodToggle = ToggleWood.Set
    ToggleWood.Set = function(self, v)
        oldWoodToggle(self, v)
        WoodStatus:Set("Status: " .. (v and "Chopping wood" or "Idle"))
    end

    -- BOSS TAB
    local BossTab = Window:MakeTab({ Name = "Bosses", Icon = "rbxassetid://4483345998" })
    local BossSection = BossTab:AddSection({ Name = "Prime Soul" })
    local ToggleBoss = BossSection:AddToggle({
        Name = "⚔️ Farm Prime Soul (summon with slot 9, right-click)",
        Default = false,
        Callback = function(v) toggleBossFarming(v) end
    })
    local StatusBoss = BossTab:AddSection({ Name = "Status" })
    local BossStatus = StatusBoss:AddLabel("Idle")
    local oldBossToggle = ToggleBoss.Set
    ToggleBoss.Set = function(self, v)
        oldBossToggle(self, v)
        BossStatus:Set("Status: " .. (v and "Farming Prime Soul" or "Idle"))
    end

    OrionLib:MakeNotification({
        Name = "Auto-Farm Loaded",
        Content = "Boss now follows and faces you – like grass monsters.",
        Image = "rbxassetid://4483345998",
        Time = 5
    })
else
    print("Orion not loaded – script logic still works.")
end

print("✅ Script loaded – boss follows and faces target.")
