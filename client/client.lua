local Core = exports.vorp_core:GetCore()
local progressbar = exports["feather-progressbar"]:initiate()

local rn = GetCurrentResourceName()
if rn ~= "PyThor_Gunpowder-Check" then
    print("Please rename the resource to the original name")
    StopResource(rn)
end

-- Events
RegisterNetEvent("GP:CheckJob")
RegisterNetEvent("GP:CheckJobResult")

-- Decorator
DecorRegister("HasShot", 2)

function Dev(...)
    if Config.DevMode then
        print(...)
    end
end

-- Globals
local IsLaw = false
local command = Config.Command
local cleanPrompt = nil

-- Animation preload
local animDict = "script_amb@stores@store_waist_stern_guy"
local animName = "base"
RequestAnimDict(animDict)
while not HasAnimDictLoaded(animDict) do Citizen.Wait(100) end

-- Whitelist weapon checker (uses config)
local function isWeaponWhitelist(weaponHash)
    for _, hash in ipairs(Config.WhitelistWeapons or {}) do
        if weaponHash == hash then
            return true
        end
    end
    return false
end

-- Setup job + prompt
Citizen.CreateThread(function()
    repeat Wait(5000) until LocalPlayer.state.IsInSession
    if not LocalPlayer.state.Character then
        repeat Wait(1000) until LocalPlayer.state.Character
    end

    TriggerServerEvent("GP:CheckJob")
    Wait(100)
    CreateCleanPrompt()
end)

AddEventHandler("GP:CheckJobResult", function(is_law)
    IsLaw = is_law
end)

-- Command for lawmen
RegisterCommand(command, function(_, args)
    local targetId = tonumber(args[1])
    if not IsLaw then
        Core.NotifyLeftRank("Access Denied", "You are not authorized to perform this check.", "menu_textures", "cross", 4000, "COLOR_RED")
        return
    end
    if not targetId then
        Dev("Usage: /gp [playerID]")
        return
    end

    local targetPed = (targetId == GetPlayerServerId(PlayerId()))
        and PlayerPedId()
        or GetPlayerPed(GetPlayerFromServerId(targetId))

    if targetPed and DoesEntityExist(targetPed) then
        TaskPlayAnim(PlayerPedId(), animDict, animName, 8.0, -8.0, 5000, 0, 0, false, false, false)
        progressbar.start("Checking gunpowder", 5000, function()
            if DecorExistOn(targetPed, "HasShot") and DecorGetBool(targetPed, "HasShot") then
                Core.NotifyLeftRank("Gunpowder Check", "They have recently fired a weapon.", "menu_textures", "menu_icon_alert", 5000, "COLOR_RED")
            else
                Core.NotifyLeftRank("Gunpowder Check", "They appear to be clean.", "menu_textures", "tick", 5000, "COLOR_GREEN")
            end
        end, 'innercircle')
    else
        Core.NotifyLeftRank("Gunpowder Check", "Player not found!", "menu_textures", "cross", 4000, "COLOR_RED")
    end
end, false)

-- Residue logic on weapon fire
Citizen.CreateThread(function()
    while true do
        Wait(0)
        local player = PlayerPedId()
        if IsPedShooting(player) then
            local _, weaponHash = GetCurrentPedWeapon(player, true)
            if not isWeaponWhitelist(weaponHash) then
                DecorSetBool(player, "HasShot", true)
                Core.NotifyLeftRank("Residue Detected", "You got gunpowder on your hands...", "generic_textures", "tick", 4000, "COLOR_YELLOW")

                local timeLeft = Config.TimeToExpire
                while timeLeft > 0 and not IsEntityInWater(player) do
                    Wait(1000)
                    timeLeft = timeLeft - 1000
                end

                if timeLeft <= 0 and not IsEntityInWater(player) then
                    DecorSetBool(player, "HasShot", false)
                    Core.NotifyLeftRank("Residue Worn Off", "The residue has faded over time.", "menu_textures", "tick", 4000, "COLOR_YELLOW")
                end
            end
        end
    end
end)

-- Prompt registration
function CreateCleanPrompt()
    if cleanPrompt ~= nil then return end

    local str = CreateVarString(10, 'LITERAL_STRING', "Clean Gunpowder Residue")
    cleanPrompt = PromptRegisterBegin()
    PromptSetControlAction(cleanPrompt, 0x760A9C6F) -- G key
    PromptSetText(cleanPrompt, str)
    PromptSetEnabled(cleanPrompt, false)
    PromptSetVisible(cleanPrompt, false)
    PromptSetStandardMode(cleanPrompt, true)
    PromptRegisterEnd(cleanPrompt)

    print("[DEBUG] Prompt registered.")
end

-- Load animation dict
local function LoadAnim(dict)
    RequestAnimDict(dict)
    local timeout = 10000
    local startTime = GetGameTimer()
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() - startTime > timeout then
            print('Failed to load anim dict:', dict)
            return
        end
        Wait(10)
    end
end

-- Prompt + progressbar + anim wash logic
Citizen.CreateThread(function()
    local washInProgress = false

    while true do
        Wait(0)

        local ped = PlayerPedId()
        local hasResidue = DecorExistOn(ped, "HasShot") and DecorGetBool(ped, "HasShot")
        local inWater = IsEntityInWater(ped) or IsPedSwimming(ped) or IsPedSwimmingUnderWater(ped)

        if hasResidue and inWater then
            PromptSetEnabled(cleanPrompt, true)
            PromptSetVisible(cleanPrompt, true)

            if PromptIsJustPressed(cleanPrompt) and not washInProgress then
                washInProgress = true
                print("[DEBUG] Prompt triggered - starting wash")

                local animDict = "amb_misc@world_human_wash_face_bucket@ground@male_a@idle_d"
                local animName = "idle_l"
                if not IsPedMale(ped) then
                    animDict = "amb_misc@world_human_wash_face_bucket@ground@female_a@idle_d"
                end
                LoadAnim(animDict)
                TaskPlayAnim(ped, animDict, animName, 1.0, 1.0, -1, 1, 0.0, false, false, false)

                progressbar.start("Washing residue...", Config.WashDuration or 10000, function()
                    ClearPedTasks(ped)
                    if IsEntityInWater(ped) then
                        print("[DEBUG] Wash complete: in water")
                        DecorSetBool(ped, "HasShot", false)
                        Core.NotifyLeftRank("Cleaned Up", "Residue washed away in the river.", "menu_textures", "menu_icon_alert", 4000, "COLOR_GREEN")
                    else
                        print("[DEBUG] Wash failed: left water")
                        Core.NotifyLeftRank("Failed to Wash", "You left the water too soon.", "menu_textures", "cross", 3000, "COLOR_RED")
                    end
                    washInProgress = false
                end, 'linear', '#ff9900', '20vw')
            end
        else
            PromptSetEnabled(cleanPrompt, false)
            PromptSetVisible(cleanPrompt, false)
            washInProgress = false
        end
    end
end)

-- Debug command to print current weapon hash
RegisterCommand("checkweaponhash", function()
    local ped = PlayerPedId()
    local weaponHash = Citizen.InvokeNative(0x8425C5F057012DAB, ped)
    print("[DEBUG] Current weapon hash: " .. tostring(weaponHash))
end, false)