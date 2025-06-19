-- Vehicle Damage and Gibbing System with Options
local activeVehicles = {} --all valid vehicles

for _, ent in ipairs(ents.GetAll()) do
    if IsValid(ent) and allowedVehicles[ent:GetClass()] then
        activeVehicles[ent:EntIndex()] = ent
        local entIndex = ent:EntIndex()
        vehicleHealths[entIndex] = GetConVar("vdg_global_default_hp"):GetInt()
        previousPositions[entIndex] = ent:GetPos()
        previousVelocities[entIndex] = Vector(0, 0, 0)
        hasExploded[entIndex] = false
        hasSparked[entIndex] = false
        lastZapTime[entIndex] = 0
        activeVehicles[ent:EntIndex()] = ent -- Add to our list
    end
end
local vehicleHealths = {}
local previousPositions = {}
local previousVelocities = {}
local hasExploded = {}
local hasSparked = {}
local lastZapTime = {}
local activeFires = {}

local allowedVehicles = {
    ["prop_vehicle_jeep"] = true,
    ["prop_vehicle_airboat"] = true,
    ["prop_vehicle_jalopy"] = true
}

local defaultVehicleHealth = {
    ["prop_vehicle_jeep"] = 100,
    ["prop_vehicle_airboat"] = 80,
    ["prop_vehicle_jalopy"] = 120
}

local vehicleModels = {
    ["jalopy"] = "models/vehicle.mdl",
    ["jeep"] = "models/buggy.mdl"
}

local function IsJalopy(ent)
    return ent:GetModel() == vehicleModels["jalopy"]
end

local function IsBuggy(ent)
    return ent:GetModel() == vehicleModels["jeep"]
end

CreateConVar("vdgs_fx_smokethreshold", "30", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Vehicle health threshold to trigger smoke effect")

local function ApplyHandlingDegradation(vehicle, health)
    if not IsValid(vehicle) or not allowedVehicles[vehicle:GetClass()] then return end
    if not GetConVar("vdg_enable_physics_degradation"):GetBool() then return end

    local phys = vehicle:GetPhysicsObject()
    if not IsValid(phys) then return end

    local maxHealth = GetConVar("vdg_global_default_hp"):GetInt()
    local healthRatio = math.Clamp(health / maxHealth, 0, 1)

    -- Handling degradation: simulate clunky mass and drag
    local baseMass = 1200
    local degradedMass = math.max(baseMass * healthRatio, baseMass * 0.3)
    local damping = 2 + (1 - healthRatio) * 6

    phys:SetMass(degradedMass)
    phys:SetDamping(damping, damping * 2)

    -- Optional jittering or instability
    if healthRatio < 0.4 and math.random() < 0.05 then
        local jitter = VectorRand() * (1 - healthRatio) * 200
        phys:ApplyForceCenter(jitter)
        vehicle:EmitSound("ambient/machines/machine_zap"..math.random(1,2)..".wav", 70, 100, 0.4)
    elseif healthRatio < 0.2 and math.random() < 0.08 then
        vehicle:EmitSound("vehicles/v8/vehicle_impact_medium"..math.random(1,3)..".wav", 75, 90, 0.6)
    end
end


hook.Add("OnEntityCreated", "InitializeVehicleHealth", function(ent)
    if IsValid(ent) and allowedVehicles[ent:GetClass()] then
        local entIndex = ent:EntIndex()
        vehicleHealths[entIndex] = GetConVar("vdg_global_default_hp"):GetInt()
        previousPositions[entIndex] = ent:GetPos()
        previousVelocities[entIndex] = Vector(0, 0, 0)
        hasExploded[entIndex] = false
        hasSparked[entIndex] = false
        lastZapTime[entIndex] = 0
        activeVehicles[ent:EntIndex()] = ent -- Add to our list
    end
end)

hook.Add("EntityRemoved", "CleanupVehicle", function(ent)
    if IsValid(ent) and allowedVehicles[ent:GetClass()] then
        local entIndex = ent:EntIndex()
        if activeVehicles[entIndex] then
            activeVehicles[entIndex] = nil -- Remove from our list
            -- Also clean up other tables to prevent memory leaks
            vehicleHealths[entIndex] = nil
            previousVelocities[entIndex] = nil
            -- ... etc.
        end
    end
end)

hook.Add("EntityTakeDamage", "VehicleDamageHandler", function(target, dmginfo)
    if IsValid(target) and allowedVehicles[target:GetClass()] then
        local entIndex = target:EntIndex()
        local damage = dmginfo:GetDamage()
        local currentHealth = vehicleHealths[entIndex] or GetConVar("vdg_global_default_hp"):GetInt()
        local newHealth = math.max(currentHealth - damage, 0)

        vehicleHealths[entIndex] = newHealth
        UpdateVehicleAppearance(target, newHealth)

        if newHealth <= 25 and not target:IsOnFire() then
            target:Ignite(30, 0)
        elseif newHealth > 25 and target:IsOnFire() then
            target:Extinguish()
        end

        if newHealth <= 0 and not hasExploded[entIndex] then
            hasExploded[entIndex] = true
            ExplodeVehicle(target)
        elseif newHealth <= 25 and not hasSparked[entIndex] and GetConVar("vdg_enable_impact_fx"):GetBool() then
            hasSparked[entIndex] = true
            local effect = EffectData()
            effect:SetOrigin(target:GetPos() + Vector(0, 0, 30))
            util.Effect("cball_explode", effect)

            if CurTime() - lastZapTime[entIndex] >= 0.25 then
                target:EmitSound("npc/roller/mine/rmine_blades_out1.wav", 75, 100, 0.5)
                lastZapTime[entIndex] = CurTime()
            end
        end

if newHealth <= 25 and not target:IsOnFire() then
    target:Ignite(30, 0)
    local decalPos = target:GetPos() + Vector(0, 0, -32)
    util.Decal("BeerSplash", decalPos, decalPos + Vector(0, 0, -32), target)
elseif newHealth > 25 and target:IsOnFire() then
    target:Extinguish()
end

    end
end)

hook.Add("Think", "VehicleCollisionDamageThink", function()
    if not GetConVar("vdg_enable_collision_damage"):GetBool() then return end

    for entIndex, ent in pairs(activeVehicles) do
        if not IsValid(ent) then continue end
        if not allowedVehicles[ent:GetClass()] then continue end

        local phys = ent:GetPhysicsObject()
        if not IsValid(phys) then continue end

        local entIndex = ent:EntIndex()
        local currentVelocity = phys:GetVelocity()
        local prevVelocity = previousVelocities[entIndex] or currentVelocity
        local deltaV = (currentVelocity - prevVelocity):Length()
        previousVelocities[entIndex] = currentVelocity

        local sensitivity = GetConVar("vdg_collision_damage_sensitivity"):GetFloat()
        deltaV = deltaV * sensitivity

        local currentHealth = vehicleHealths[entIndex] or GetConVar("vdg_global_default_hp"):GetInt()

        if deltaV > 100 then
            local damage = 0

            if deltaV > 200 then
                -- Heavy hit
                damage = math.Clamp((deltaV - 200) * 0.4, 5, 50) 
            else
                -- Light hit
                damage = math.Clamp((deltaV - 100) * 0.1, 1, 5)
            end

            local newHealth = math.max(currentHealth - damage, 0)
            vehicleHealths[entIndex] = newHealth
            UpdateVehicleAppearance(ent, newHealth)

            if deltaV > 200 then
                local heavySounds = {
                    "physics/metal/metal_barrel_impact_hard3.wav",
                    "physics/metal/metal_box_break1.wav",
                    "physics/metal/metal_box_break2.wav"
                }
                ent:EmitSound(table.Random(heavySounds), 75, math.random(95, 105), math.Clamp(damage / 50, 0.5, 1))
            else
                local lightSounds = {
                    "physics/metal/metal_barrel_impact_hard1.wav",
                    "physics/metal/metal_canister_impact_soft1.wav"
                }
                ent:EmitSound(table.Random(lightSounds), 60, math.random(95, 105), 0.4)
            end

            if GetConVar("vdg_enable_impact_fx"):GetBool() and deltaV > 150 then
                local edata = EffectData()
                edata:SetOrigin(ent:GetPos() + Vector(0, 0, 30))
                util.Effect("ManhackSparks", edata)
            end

            for _, ply in ipairs(player.GetAll()) do
                if ply:GetPos():Distance(ent:GetPos()) < 500 then
                    util.ScreenShake(ent:GetPos(), 5, 100, 0.5, 250)
                end
            end

            local fireThreshold = GetConVar("vdg_fire_threshold_percent"):GetFloat() or 25
            if newHealth <= (GetConVar("vdg_global_default_hp"):GetInt() * (fireThreshold / 100)) then
                if not ent.VDG_IsOnFire then
                    ent:Ignite(15)
                    ent.VDG_IsOnFire = true
                end
            end

            if newHealth <= 0 and not hasExploded[entIndex] then
                hasExploded[entIndex] = true
                ExplodeVehicle(ent)
            end
        end
    end
end)


hook.Add("PhysicsCollide", "VehiclePropCollisionDamage", function(data, physobj)
    if not GetConVar("vdg_enable_collision_damage"):GetBool() then return end

    local vehicle = data.HitEntity
    local prop = physobj:GetEntity()

    if not IsValid(vehicle) or not IsValid(prop) then return end
    if vehicle == prop or not allowedVehicles[vehicle:GetClass()] then return end

    local speed = data.OurOldVelocity:Length()
    local sensitivity = GetConVar("vdg_collision_damage_sensitivity"):GetFloat()
    speed = speed * sensitivity
    if speed <= 100 then return end

    local entIndex = vehicle:EntIndex()
    local defaultHP = GetConVar("vdg_global_default_hp"):GetInt()
    local impactFXEnabled = GetConVar("vdg_enable_impact_fx"):GetBool()

    -- Initialize health if needed
    vehicleHealths[entIndex] = vehicleHealths[entIndex] or defaultHP
    if vehicleHealths[entIndex] <= 0 then return end

    -- Calculate damage
    local damage = math.Clamp((speed - 100) * 0.01, 0, 10)
    vehicleHealths[entIndex] = math.max(vehicleHealths[entIndex] - damage, 0)

    UpdateVehicleAppearance(vehicle, vehicleHealths[entIndex])

    -- Impact sound
    vehicle:EmitSound("physics/metal/metal_box_impact_soft" .. math.random(1, 3) .. ".wav", 70)

    -- Optional visual effect
    if impactFXEnabled then
        local edata = EffectData()
        edata:SetOrigin(data.HitPos)
        edata:SetNormal(data.HitNormal)
        util.Effect("cball_explode", edata, true, true)
    end

    -- Trigger explosion
    if vehicleHealths[entIndex] <= 0 and not hasExploded[entIndex] then
        hasExploded[entIndex] = true
        ExplodeVehicle(vehicle)
    end
end)


function UpdateVehicleAppearance(vehicle, health)
    if GetConVar("vdg_disable_darkening"):GetBool() then return end

    local maxHealth = GetConVar("vdg_global_default_hp"):GetInt()
    local damageRatio = 1 - math.Clamp(health / maxHealth, 0, 1)

    vehicle:SetRenderMode(RENDERMODE_TRANSALPHA)
    local originalColor = vehicle.VDG_OriginalColor or vehicle:GetColor()
    vehicle.VDG_OriginalColor = originalColor

    local newColor = Color(
        math.max(math.floor(originalColor.r * (1 - damageRatio)), 40),
        math.max(math.floor(originalColor.g * (1 - damageRatio)), 40),
        math.max(math.floor(originalColor.b * (1 - damageRatio)), 40),
        originalColor.a
    )
    vehicle:SetColor(newColor)

end


function GetGibModels(vehicle)
    local universalScrap = "models/props_junk/metal_paintcan001a.mdl"
    local sharedGibs = {
        "models/Items/car_battery01.mdl",
        "models/props_c17/tools_wrench01a.mdl",
        "models/props_junk/metalgascan.mdl"
    }
    local genericGibs = {
        "models/Items/car_battery01.mdl",
        "models/props_c17/tools_wrench01a.mdl",
        "models/props_junk/metalgascan.mdl",
        "models/buggy_steering.mdl",
        "models/nova/jeep_seat.mdl",
        "models/buggy_front_wheel.mdl",
        "models/buggy_rear_wheel.mdl",
        universalScrap
    }

    local models = {
        ["prop_vehicle_jeep"] = {
            "models/buggy_base.mdl", "models/buggy_front.mdl",
            "models/buggy_front_wheel.mdl", "models/buggy_meter.mdl", "models/buggy_rear_wheel.mdl",
            "models/buggy_roof.mdl", "models/buggy_steering.mdl", "models/nova/jeep_seat.mdl",
            universalScrap
        },
        ["prop_vehicle_airboat"] = {
            "models/airboat_base.mdl", "models/airboat_cab.mdl", "models/airboat_fanbase.mdl",
            "models/airboat_frame.mdl", "models/airboat_nose.mdl", "models/airboat_pontoon.mdl",
            "models/airboat_propeller.mdl", "models/airboat_rudder.mdl", "models/airboat_steering.mdl",
            "models/nova/airboat_seat.mdl", universalScrap
        },
        ["prop_vehicle_jalopy"] = {
            "models/vehicle/vehicle_engine_block.mdl", "models/jalopy/baggage.mdl", "models/jalopy/body_front.mdl",
            "models/jalopy/body_jalopy.mdl", "models/nova/jalopy_seat.mdl", "models/jalopy/bumper_back.mdl",
            "models/jalopy/extaus.mdl", "models/jalopy/front_bumper.mdl", "models/jalopy/roof_jalopy.mdl",
            "models/jalopy/st_wheel.mdl", "models/jalopy/wheel front.mdl", "models/jalopy/wheel_right.mdl",
            universalScrap
        }
    }

    for _, shared in ipairs(sharedGibs) do
        for _, list in pairs(models) do
            table.insert(list, shared)
        end
    end

    if vehicle:GetClass() == "prop_vehicle_jeep" then
        if IsJalopy(vehicle) then
            return models["prop_vehicle_jalopy"]
        elseif not IsBuggy(vehicle) then
            if GetConVar("vdg_force_shared_gibs_for_unknown_models"):GetBool() then
                return genericGibs
            end
        end
    elseif vehicle:GetClass() == "prop_vehicle_airboat" and vehicle:GetModel() ~= "models/airboat.mdl" then
        if GetConVar("vdg_force_shared_gibs_for_unknown_models"):GetBool() then
            return genericGibs
        end
    end

    return models[vehicle:GetClass()] or {universalScrap}
end

local function ApplyForceAndAutoRemove(ent)
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        local forceOrigin = ent:GetPos()
        local forceDir = (ent:GetPos() - forceOrigin + VectorRand() * 50 + Vector(0,0,30)):GetNormalized()
        local mass = phys:GetMass()
        phys:ApplyForceCenter(forceDir * mass * 600)
    end

    if GetConVar("vdg_enable_blood_trail"):GetBool() and ent:IsValid() then
        local trail = util.SpriteTrail(ent, 0, Color(200, 0, 0, 200), false, 8, 50, 1, 1 / (8 + 50) * 0.5, "trails/blood.vmt")
        ent.BloodTrail = trail
    end

    ent:EmitSound("physics/flesh/flesh_impact_bullet3.wav")

    timer.Simple(GetConVar("vdg_gib_lifetime"):GetFloat(), function()
        if IsValid(ent) then
            if ent.BloodTrail then ent.BloodTrail:Remove() end
            ent:Remove()
        end
    end)
end

function SpawnSkeletalRemains(pos, vehicle)
    local skeletonParts = {
        "models/Gibs/HGIBS.mdl",
        "models/Gibs/HGIBS_spine.mdl",
        "models/Gibs/HGIBS_scapula.mdl",
        "models/Gibs/HGIBS_rib.mdl",
        "models/Gibs/Antlion_gib_small_2.mdl"
    }

    for _, model in ipairs(skeletonParts) do
        local gib = ents.Create("prop_physics")
        if not IsValid(gib) then continue end
        gib:SetModel(model)
        gib:SetPos(pos + VectorRand() * 16)
        gib:SetAngles(AngleRand())
        gib:Spawn()
        ApplyForceAndAutoRemove(gib)
        gib:EmitSound("physics/flesh/flesh_impact_bullet1.wav")
        util.Decal("Blood", gib:GetPos(), gib:GetPos() - Vector(0, 0, 32), gib)
    end
end
function ExplodeVehicle(vehicle)
    if not IsValid(vehicle) then return end
    local pos = vehicle:GetPos()
    local gibs = GetGibModels(vehicle)

    -- Spawn gibs
    for _, model in ipairs(gibs) do
        local gib = ents.Create("prop_physics")
        if not IsValid(gib) then continue end
        gib:SetModel(model)
        local spawnPos = pos + VectorRand() * 40 + Vector(0, 0, 30)
        local tr = util.TraceHull({
            start = spawnPos,
            endpos = spawnPos,
            mins = gib:OBBMins(),
            maxs = gib:OBBMaxs(),
            mask = MASK_SOLID_BRUSHONLY
        })
        if tr.Hit then
            spawnPos = spawnPos + Vector(0, 0, 50)
        end
        gib:SetPos(spawnPos)
        gib:SetAngles(AngleRand())
        gib:Spawn()
        ApplyForceAndAutoRemove(gib)
    end

    -- Spawn loot
    local lootChance = GetConVar("vdg_loot_chance"):GetFloat()
    if math.random() < lootChance then
        local lootTable = {
            "item_battery",
            "item_ammo_smg1",
            "item_ammo_pistol",
            "item_healthkit"
        }
        local lootClass = lootTable[math.random(#lootTable)]
        local lootEnt = ents.Create(lootClass)
        if IsValid(lootEnt) then
            lootEnt:SetPos(pos + VectorRand() * 40 + Vector(0, 0, 20))
            lootEnt:Spawn()
            local phys = lootEnt:GetPhysicsObject()
            if IsValid(phys) then
                phys:ApplyForceCenter(VectorRand() * 300 + Vector(0, 0, 300))
            end
        end
    end

    -- Stronger explosion
    local explosion = ents.Create("env_explosion")
    if IsValid(explosion) then
        explosion:SetPos(pos)
        explosion:SetOwner(vehicle)
        explosion:Spawn()
        explosion:SetKeyValue("iMagnitude", "200") -- more powerful
        explosion:SetKeyValue("spawnflags", "1")   -- no damage decals
        explosion:Fire("Explode", 0, 0)
    end

    -- Smoke effect always spawns first
    if GetConVar("vdgs_fx_smoke"):GetBool() then
        local smoke = ents.Create("env_smokestack")
        if IsValid(smoke) then
            smoke:SetPos(pos)
            smoke:SetKeyValue("InitialState", "1")
            smoke:SetKeyValue("WindAngle", "0 0 0")
            smoke:SetKeyValue("WindSpeed", "0")
            smoke:SetKeyValue("rendercolor", "50 50 50")
            smoke:SetKeyValue("renderamt", "170")
            smoke:SetKeyValue("SmokeMaterial", "particle/SmokeStack.vmt")
            smoke:SetKeyValue("BaseSpread", "20")
            smoke:SetKeyValue("SpreadSpeed", "10")
            smoke:SetKeyValue("Speed", "20")
            smoke:SetKeyValue("StartSize", "40")
            smoke:SetKeyValue("EndSize", "100")
            smoke:SetKeyValue("roll", "10")
            smoke:SetKeyValue("Rate", "20")
            smoke:SetKeyValue("JetLength", "100")
            smoke:SetKeyValue("twist", "5")
            smoke:SetParent(vehicle)
            smoke:Spawn()
            smoke:Activate()
            smoke:Fire("TurnOn", "", 0)

            timer.Simple(GetConVar("vdgs_fx_smoketime"):GetFloat(), function()
                if IsValid(smoke) then smoke:Remove() end
            end)
        end
    end

    -- Fire effect, extinguish after 10 seconds
    if GetConVar("vdg_enable_vehicle_fire"):GetBool() then
        local fire = ents.Create("env_fire")
        if IsValid(fire) then
            fire:SetPos(pos)
            fire:SetKeyValue("spawnflags", "1")
            fire:SetKeyValue("firesize", "128")
            fire:SetKeyValue("health", "100")
            fire:SetKeyValue("firetype", "0")
            fire:Spawn()
            fire:Activate()
            fire:Fire("StartFire", "", 0)
            vehicle.VDG_IsOnFire = true

            timer.Simple(10, function()
                if IsValid(fire) then
                    fire:Fire("Extinguish", "", 0)
                    fire:Remove()
                end
            end)
        end
    end

    -- Driver death and gibs
    local driver = vehicle:GetDriver()
    if IsValid(driver) and driver:IsPlayer() then
        driver:Kill()
        if not GetConVar("vdg_disable_skeleton_gibs"):GetBool() then
            SpawnSkeletalRemains(driver:GetPos())
            local decalPos = pos + Vector(0, 0, 5)
            util.Decal("Blood", decalPos, decalPos - Vector(0, 0, 64), vehicle)
            sound.Play("physics/flesh/flesh_squishy_impact_hard1.wav", pos, 75, 100, 1)
        end
    end

    -- Bigger screen shake
    util.ScreenShake(pos, 100, 250, 2.5, 1500)

    -- Additional explosion effect
    local explosionFX = EffectData()
    explosionFX:SetOrigin(pos)
    util.Effect("Explosion", explosionFX)

    -- Remove vehicle
    timer.Simple(0.1, function()
        if IsValid(vehicle) then vehicle:Remove() end
    end)
end


if SERVER then
    CreateConVar("vdg_client_default_hp", "100", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Default vehicle HP")
    CreateConVar("vdg_global_default_hp", "100", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Default vehicle HP")
    CreateConVar("vdg_enable_impact_fx", "1", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Enable vehicle impact effects")
    CreateConVar("vdg_enable_vehicle_fire", "1", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Enable vehicle fire after explosion")
    CreateConVar("vdg_disable_darkening", "0", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Disable vehicle color darkening on damage")
    CreateConVar("vdg_disable_skeleton_gibs", "0", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Disable the skeleton gibs from showing")
    CreateConVar("vdg_gib_lifetime", "20", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Lifetime in seconds for vehicle gibs")
    CreateConVar("vdg_enable_blood_trail", "1", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Enable blood trails on gibs")
    CreateConVar("vdg_loot_chance", "0.25", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Chance to spawn loot on explosion")
    CreateConVar("vdg_force_shared_gibs_for_unknown_models", "1", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Force shared gibs for unknown vehicle models")
    CreateConVar("vdg_fire_threshold_percent", "25", FCVAR_ARCHIVE, "Vehicle fire starts at this percent of health remaining.")
    CreateConVar("vdg_enable_physics_degradation", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Enable vehicle physics degradation based on health.")
    CreateConVar("vdgs_fx_smoke", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Enable smoke effects on damaged vehicles")
    CreateConVar("vdgs_fx_smoketime", "20", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Duration of smoke effect in seconds")
    CreateConVar("vdg_enable_collision_damage", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Enable or disable crash and prop collision damage")
    CreateConVar("vdg_collision_damage_sensitivity", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Controls how sensitive vehicle collisions are to damage")
end
