if SERVER then
    include("vehicle_damage.lua")
end

if CLIENT then
    local function CreateVDGControls(panel)
        panel:ClearControls()

        local sliders = {}

        -- Utility to safely create sliders
        local function AddSlider(label, convar, min, max, decimals)
            local slider = panel:NumSlider(label, convar, min, max, decimals)
            sliders[convar] = slider
            return slider
        end

        -- Utility to safely create checkboxes
        local function AddCheckbox(label, convar)
            local checkbox = panel:CheckBox(label, convar)
            local cvar = GetConVar(convar)
            if cvar then
                checkbox:SetValue(cvar:GetBool())
            else
                checkbox:SetValue(false)
                MsgC(Color(255, 100, 100), "[VDG] Warning: ConVar '" .. convar .. "' not found on client.\n")
            end
            return checkbox
        end

        -- Add sliders
        AddSlider("Default Vehicle HP (Client)", "vdg_client_default_hp", 10, 500, 0)
        AddSlider("Default Vehicle HP (Server)", "vdg_global_default_hp", 10, 500, 0)
        AddSlider("Gib Lifetime (seconds)", "vdg_gib_lifetime", 1, 60, 0)
        AddSlider("Loot Chance (0 to 1)", "vdg_loot_chance", 0, 1, 2)
        AddSlider("Smoke Duration (seconds)", "vdgs_fx_smoketime", 1, 120, 0)
        AddSlider("Vehicle Health Threshold for Smoke", "vdgs_fx_smokethreshold", 0, 100, 0)
        AddSlider("Collision Damage Sensitivity", "vdg_collision_damage_sensitivity", 0.1, 5.0, 1)
        AddSlider("Collision Check Delay", "vdg_collision_think_delay", 0.05, 1.0, 2)

        -- Add checkboxes
        AddCheckbox("Enable Fire After Explosion", "vdg_enable_fire_after_explosion")
        AddCheckbox("Enable Blood Trail on Gibs", "vdg_enable_blood_trail")
        AddCheckbox("Enable Impact Effects (Particles & Sounds)", "vdg_enable_impact_fx")
        AddCheckbox("Disable Vehicle Darkening", "vdg_disable_darkening")
        AddCheckbox("Disable Skeleton Gibs", "vdg_disable_skeleton_gibs")
        AddCheckbox("Force Shared Gib Models for Unknown Models", "vdg_force_shared_gibs_for_unknown_models")
        AddCheckbox("Enable Smoke Effect on Damaged Vehicles", "vdgs_fx_smoke")
        AddCheckbox("Enable Collision Damage", "vdg_enable_collision_damage")

        -- Set initial slider values after ConVars are available
        timer.Simple(0, function()
            for convar, slider in pairs(sliders) do
                if IsValid(slider) then
                    local cvar = GetConVar(convar)
                    if cvar then
                        slider:SetValue(cvar:GetFloat())
                    else
                        MsgC(Color(255, 100, 100), "[VDG] Warning: ConVar '" .. convar .. "' not found on client.\n")
                    end
                end
            end
        end)

        -- Reset button
        local btn = panel:Button("Reset to Defaults")
        btn:SetToolTip("Resets all options to their default values")

        timer.Simple(0, function()
            if not IsValid(btn) then return end
            btn.DoClick = function()
                local defaults = {
                    vdg_client_default_hp = "100",
                    vdg_global_default_hp = "100",
                    vdg_gib_lifetime = "15",
                    vdg_loot_chance = "0.3",
                    vdg_enable_fire_after_explosion = "1",
                    vdg_enable_blood_trail = "1",
                    vdg_enable_impact_fx = "1",
                    vdg_disable_darkening = "0",
                    vdg_disable_skeleton_gibs = "0",
                    vdg_force_shared_gibs_for_unknown_models = "1",
                    vdgs_fx_smoke = "1",
                    vdgs_fx_smoketime = "20",
                    vdgs_fx_smokethreshold = "30",
                    vdg_enable_collision_damage = "1",
                    vdg_collision_damage_sensitivity = "0.30",
                    vdg_collision_think_delay = "0.1"
                }

                for cvar, val in pairs(defaults) do
                    RunConsoleCommand(cvar, val)
                end

                chat.AddText(Color(0, 255, 0), "[VDG] Settings reset to defaults.")

                timer.Simple(0.1, function()
                    if IsValid(panel) then
                        CreateVDGControls(panel)
                    end
                end)
            end
        end)
    end

    -- Add tool menu panel
    hook.Add("PopulateToolMenu", "VDG_OptionsMenu", function()
        spawnmenu.AddToolMenuOption("Utilities", "Vergi's Addons", "VehicleDamageGibbing", "Vehicle Damage Options", "", "", function(panel)
            CreateVDGControls(panel)
        end)
    end)
end
