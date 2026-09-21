local prev_unload = getgenv().__v_ctx_unload
if type(prev_unload) == "function" then pcall(prev_unload) end
getgenv().__v_ctx_unload = nil
getgenv().__v_ctx = nil

pcall(function()
    local safe_parents = {}
    if typeof(gethui) == "function" then
        local ok, h = pcall(gethui)
        if ok and h then table.insert(safe_parents, h) end
    end
    pcall(function()
        local cg = (cloneref and cloneref(game:GetService("CoreGui"))) or game:GetService("CoreGui")
        if cg then
            table.insert(safe_parents, cg)
            local rg = cg:FindFirstChild("RobloxGui")
            if rg then table.insert(safe_parents, rg) end
        end
    end)
    local lp = (cloneref and cloneref(game:GetService("Players")).LocalPlayer) or game:GetService("Players").LocalPlayer
    if lp then
        local ok, pg = pcall(function() return lp:FindFirstChildOfClass("PlayerGui") end)
        if ok and pg then table.insert(safe_parents, pg) end
    end
    for _, parent in ipairs(safe_parents) do
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("ScreenGui") then
                local should_destroy = (child.Name == "CoreProvider"
                    or child.Name == "CoreFloatProvider"
                    or child.Name == "Vantage"
                    or child.Name == "VantageFloatGui"
                    or child.Name == "VantageAmbientOverlay"
                    or child.Name == "CoreAmbientOverlay"
                    or child.Name == "AnimCatalogWindow"
                    or child.Name == "EmoteCatalogWindow"
                    or child.Name == "ESPPreviewWindow"
                    or child:GetAttribute("__v_core") == true
                    or child:GetAttribute("IsVantageGui") == true
                    or child:FindFirstChild("AnimCatalogWindow", true) ~= nil
                    or child:FindFirstChild("EmoteCatalogWindow", true) ~= nil
                    or child:FindFirstChild("ESPPreviewWindow", true) ~= nil)
                if should_destroy then
                    pcall(function()
                        child.Enabled = false
                        child.Parent = nil
                        child:ClearAllChildren()
                        child:Destroy()
                    end)
                end
            end
        end
    end
end)

local repo = "https://raw.githubusercontent.com/MisterNovitski/Vantage/refs/heads/main/"

local function load_mod(paths, url, validator)
    if type(paths) == "string" then paths = { paths } end
    local function check_res(res)
        if not res then return false end
        if validator and not validator(res) then return false end
        return true
    end

    if typeof(readfile) == "function" and typeof(isfile) == "function" then
        for _, p in ipairs(paths) do
            if isfile(p) then
                local ok, content = pcall(readfile, p)
                if ok and content and #content > 0 then
                    local fn = loadstring(content, p)
                    if fn then
                        local ok2, res = pcall(fn)
                        if ok2 and check_res(res) then return res end
                    end
                end
            end
        end
    end
    if typeof(loadfile) == "function" and typeof(isfile) == "function" then
        for _, p in ipairs(paths) do
            if isfile(p) then
                local ok, fn = pcall(loadfile, p)
                if ok and typeof(fn) == "function" then
                    local ok2, res = pcall(fn)
                    if ok2 and check_res(res) then return res end
                end
            end
        end
    end
    if url then
        local cache_file = nil
        if typeof(writefile) == "function" and typeof(makefolder) == "function" then
            pcall(function()
                if typeof(isfolder) == "function" and not isfolder("vantage") then makefolder("vantage") end
                if typeof(isfolder) == "function" and not isfolder("vantage/cache") then makefolder("vantage/cache") end
            end)
            local fname = url:match("([^/]+)$")
            if fname then cache_file = "vantage/cache/" .. fname end
        end

        local ok, content = pcall(function() return game:HttpGet(url) end)
        if ok and content and #content > 0 then
            if cache_file and typeof(writefile) == "function" then
                pcall(writefile, cache_file, content)
            end
            local fn = loadstring(content)
            if fn then
                local ok2, res = pcall(fn)
                if ok2 and check_res(res) then return res end
            end
        end
    end
    return nil
end

local library = load_mod(
    { "vantage/cache/main.luau", "Library.luau", "main.luau", "workspace/Library.luau", "Vantage/Library.luau", "workspace/main.luau" },
    repo .. "main.luau",
    function(lib) return lib and lib.CreateWindow end
)
local theme_mgr = load_mod(
    { "vantage/cache/theme.luau", "addons/ThemeManager.luau", "addons/theme.luau", "workspace/addons/ThemeManager.luau", "workspace/addons/theme.luau", "ThemeManager.luau" },
    repo .. "addons/theme.luau"
)
local save_mgr = load_mod(
    { "vantage/cache/manager.luau", "addons/SaveManager.luau", "addons/manager.luau", "workspace/addons/SaveManager.luau", "workspace/addons/manager.luau", "SaveManager.luau" },
    repo .. "addons/manager.luau"
)

local options = library.Options
local toggles = library.Toggles

local cloneref = cloneref or function(x) return x end
local players = cloneref(game:GetService("Players"))
local run_service = cloneref(game:GetService("RunService"))
local workspace = cloneref(game:GetService("Workspace"))
local lighting = cloneref(game:GetService("Lighting"))
local http_service = cloneref(game:GetService("HttpService"))
local user_input_service = cloneref(game:GetService("UserInputService"))
local tween_service = cloneref(game:GetService("TweenService"))
local TweenService = tween_service
local stats = cloneref(game:GetService("Stats"))
local local_player = players.LocalPlayer
local camera = workspace.CurrentCamera

if not getgenv().__v_baseline_lighting then
    getgenv().__v_baseline_lighting = {
        fov = camera and camera.FieldOfView or 70,
        ambient = lighting.Ambient,
        outdoor = lighting.OutdoorAmbient,
        fog_color = lighting.FogColor,
        fog_start = lighting.FogStart,
        fog_end = lighting.FogEnd,
        clock_time = lighting.ClockTime,
        exposure = lighting.ExposureCompensation,
        brightness = lighting.Brightness,
        global_shadows = lighting.GlobalShadows,
        color_shift_bottom = lighting.ColorShift_Bottom,
        color_shift_top = lighting.ColorShift_Top,
    }
end
local baseline = getgenv().__v_baseline_lighting

local ambient_overlay = nil
local originalLightingState = nil
local originalAtmospheres = {}
local nightCCInstance = nil
local nightModeConnection = nil
local restoreOriginalLighting = nil

local arrow_raw do
    local b64 = "iVBORw0KGgoAAAANSUhEUgAAAB0AAAAdCAMAAABhTZc9AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAPUExURQAAAP///wwMDP39/QAAAJn0DigAAAAFdFJOU/////8A+7YOUwAAAAlwSFlzAABLlgAAS5YBPIKNxAAAABh0RVh0U29mdHdhcmUAUGFpbnQuTkVUIDUuMS4y+7wDtgAAALZlWElmSUkqAAgAAAAFABoBBQABAAAASgAAABsBBQABAAAAUgAAACgBAwABAAAAAgAAADEBAgAQAAAAWgAAAGmHBAABAAAAagAAAAAAAAD7fwcA6AMAAPt/BwDoAwAAUGFpbnQuTkVUIDUuMS4yAAMAAJAHAAQAAAAwMjMwAaADAAEAAAABAAAABaAEAAEAAACUAAAAAAAAAAIAAQACAAQAAABSOTgAAgAHAAQAAAAwMTAwAAAAAFgdiCkiK10LAAAAZ0lEQVQ4T+XT0QqAMAgF0Gv5/9/cdJrXPYweopeEoe5MGKOgHMDSR/aAiPSNyBaGnT9S4Oi3pnqOtuEqE5kfaiHxG8pYTJoHrMzdzFu1h0qt57oLH58a/YhFfUU/4s967tT/Iv4mVS+LEAmXjonxPAAAAABJRU5ErkJggg=="
    local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local t = {}
    for i = 1, #b64chars do t[b64chars:sub(i,i)] = i - 1 end
    local out, oi = {}, 0
    local acc, bits = 0, 0
    for i = 1, #b64 do
        local c = b64:sub(i,i)
        local v = t[c]
        if v then
            acc = acc * 64 + v
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                local div = 2^bits
                local byte = math.floor(acc / div)
                acc = acc - byte * div
                oi = oi + 1
                out[oi] = string.char(byte % 256)
            end
        end
    end
    arrow_raw = table.concat(out)
end

local unload
local main_screen_gui
local esp_preview = nil
local anim_catalog = nil
local emote_catalog = nil
local ctx = {
    running = true,
    conns = {},
    drawings = {},
    chams = {},
    tracers = {},
    hooks = {},
    esp_miss = {},
    esp_bones = {},
    hidden_names = {},
    roster = {}
}

local function rebuild_roster()
    table.clear(ctx.roster)
    for _, p in ipairs(players:GetPlayers()) do
        ctx.roster[#ctx.roster + 1] = p
    end
end

local hook_muzzle_flash = nil
local hook_gun_shoot = nil

local function protect_gui(gui)
    if not gui then return end
    pcall(function()
        if typeof(protectgui) == "function" then
            protectgui(gui)
        elseif typeof(syn) == "table" and typeof(syn.protect_gui) == "function" then
            syn.protect_gui(gui)
        end
    end)
    pcall(function()
        gui.ResetOnSpawn = false
        local parent = nil
        if typeof(gethui) == "function" then
            local ok, h = pcall(gethui)
            if ok and h then parent = h end
        end
        if not parent then
            local lp = local_player or (players and players.LocalPlayer)
            parent = lp and lp:FindFirstChildOfClass("PlayerGui")
        end
        if parent then
            gui.Parent = parent
        end
    end)
end

if setfpscap and type(setfpscap) == "function" then
    pcall(function()
        if getfpscap and getfpscap() <= 60 then setfpscap(0) end
    end)
end

task.spawn(function()
    local key = getgenv().SCRIPT_KEY
    if not key or key == "" then return end
    local req = (type(syn) == "table" and type(syn.request) == "function" and syn.request)
        or (type(request) == "function" and request)
        or (type(http_request) == "function" and http_request)
    if not req then return end
    pcall(function()
        local resp = req({
            Url = "https://api.jnkie.com/api/v2/keys?key=" .. key,
            Method = "GET",
            Headers = { ["Authorization"] = "Bearer 384f8c7f-987a-441d-a0c8-a5de48bb103e", ["Accept"] = "application/json" }
        })
        if resp and resp.StatusCode == 200 and resp.Body then
            local data = http_service:JSONDecode(resp.Body)
            if data and data.keys and data.keys[1] and data.keys[1].expires_at then
                local exp = data.keys[1].expires_at
                if library.SetKeyExpires then library:SetKeyExpires(exp) end
            end
        end
    end)
end)

local window = library:CreateWindow({
    Title = "vantage",
    Footer = "by pseudonym1639, agenttes",
    Size = UDim2.fromOffset(740, 530),
    CornerRadius = 20,
    AutoShow = true,
    DisableSearch = true
})

local tabs = {
    visuals = window:AddTab({ Name = "visuals", Icon = "eye" }),
    config = window:AddTab({ Name = "config", Icon = "file-text" })
}
tabs["UI Settings"] = tabs.config

pcall(function()
    local function find_sg_from_table(tbl)
        if type(tbl) ~= "table" then return nil end
        for _, v in pairs(tbl) do
            if typeof(v) == "Instance" then
                local found = v:IsA("ScreenGui") and v or v:FindFirstAncestorOfClass("ScreenGui")
                if found then return found end
            end
        end
        return nil
    end

    main_screen_gui = find_sg_from_table(library)
        or find_sg_from_table(window)
    if not main_screen_gui and tabs then
        for _, tab in pairs(tabs) do
            main_screen_gui = find_sg_from_table(tab)
            if main_screen_gui then break end
        end
    end

    if main_screen_gui then
        pcall(function() main_screen_gui:SetAttribute("__v_core", true) end)
        pcall(function() main_screen_gui:SetAttribute("IsVantageGui", true) end)
        ctx.main_gui = main_screen_gui
        if getgenv then
            getgenv().__v_ctx_gui = main_screen_gui
        end
    end
end)

local cfg = {
    esp_enabled = false, team_check = false, box_enabled = false, box_mode = "2D", box_color = Color3.fromRGB(255, 255, 255),
    box_outline = true, box_outline_color = Color3.fromRGB(0, 0, 0), box_outline_mode = "Color", box_outline_gradient = false, box_sync_gradient = false,
    box_gradient = false, box_gradient_color = Color3.fromRGB(255, 255, 255), box_gradient_trans = 0.85,
    skeleton_enabled = false, skeleton_color = Color3.fromRGB(255, 255, 255), skeleton_thick = 1.5, skeleton_trans = 1,
    health_enabled = false, health_color = Color3.fromRGB(0, 255, 128),
    health_gradient = false, health_gradient_color = Color3.fromRGB(105, 205, 255), health_gradient_trans = 0,
    names_enabled = false, name_mode = "Display Name", names_color = Color3.fromRGB(255, 255, 255), name_size = 13, hide_names = false,
    name_gradient = false, name_gradient_color = Color3.fromRGB(105, 205, 255), name_gradient_trans = 0,
    show_weapon = false, dist_enabled = false, dist_color = Color3.fromRGB(255, 255, 255), max_dist = 1000,
    chams_enabled = false, chams_mode = "Highlight", chams_material = "forcefield 2", chams_color = Color3.fromHex("#474747"), chams_outline_color = Color3.fromRGB(255, 255, 255), chams_outline_trans = 1, chams_fill_trans = 0.5,
    chams_acc_mat = "ForceField",
    chromatic_speed = 0.6, chromatic_scale = 1.012, chromatic_trans = 0, chromatic_refl = 0.12, chromatic_material = "Foil",
    weapon_chams_enabled = false, weapon_chams_type = "ForceField", weapon_chams_color = Color3.fromRGB(180, 100, 255), weapon_chams_trans = 0,
    fake_korblox = false, fake_headless = false,
    particles_enabled = false, particles_color = Color3.fromRGB(220, 170, 255), particles_count = 23, particles_size = 0.45, particles_trans = 0.1, particle_texture = "snowflake", particle_flight = "wind", particle_wind = 1, particle_collide = false,
    ambient_enabled = false, ambient_color = Color3.fromHex("#919090"), outdoor_color = Color3.fromHex("#5a3782"), clock_time = 0, fog_color = Color3.fromHex("#3c1e5f"), fog_start = 60, fog_end = 600,
    ambient_bloom = 0.75, ambient_brightness = 0.05, ambient_contrast = 0.15, ambient_saturation = 0.25,
    ambient_overlay_color = Color3.fromHex("#6e4696"), ambient_opacity = 0.12,
    china_hat_enabled = false, china_hat_color = Color3.fromHex("#b464ff"), china_hat_trans = 0.4, china_hat_radius = 0.9, china_hat_height = 0.45, china_hat_speed = 2.0,
    self_chams_enabled = false, self_chams_mode = "Forcefield 2", self_chams_color = Color3.fromHex("#b464ff"), self_chams_trans = 0.6,
    backtrack_enabled = false, backtrack_color = Color3.fromRGB(130, 90, 230), backtrack_trans = 0.4,
    custom_anims_enabled = false, custom_anim_pack = "Zombie", custom_anim_slot = "all", active_anim_slots = {},
    custom_fov_enabled = false, custom_fov = 90, skybox_enabled = false, skybox_preset = "anime sky",
    china_hat_mode = "3D",
    shaders_enabled = false, shaders_preset = "morning", shaders_brightness = 1.0, shaders_exposure = 0.0,
    auras_enabled = false, aura_type = "angel", aura_color = Color3.fromRGB(133, 220, 255),
    show_roles = false, role_colors_enabled = false, role_filter = "all",
    role_color_murderer = Color3.fromRGB(255, 60, 60), role_color_sheriff = Color3.fromRGB(0, 153, 255), role_color_innocent = Color3.fromRGB(255, 255, 255),
    arrows_enabled = false, arrow_size = 22, arrow_distance = 180, arrow_outline = true,
    arrow_color_murderer = Color3.fromRGB(255, 60, 60), arrow_color_sheriff = Color3.fromRGB(0, 153, 255), arrow_color_innocent = Color3.fromRGB(255, 255, 255)
}

local function is_teammate(player)
    return cfg.team_check and local_player.Team and player.Team == local_player.Team
end

local round_client_mod = nil
local function get_round_module()
    if not round_client_mod then
        pcall(function()
            local rs = cloneref(game:GetService("ReplicatedStorage"))
            local mods = rs:WaitForChild("Modules", 2)
            round_client_mod = mods and require(mods:WaitForChild("CurrentRoundClient", 2))
        end)
    end
    return round_client_mod
end

local function get_player_role(player)
    if not player then return "innocent" end
    local rmod = get_round_module()
    local data = rmod and rmod.PlayerData
    if type(data) == "table" and data[player.Name] and data[player.Name].Role then
        local r = string.lower(tostring(data[player.Name].Role))
        if r == "hero" or r == "sheriff" then return "sheriff" end
        if r == "murderer" then return "murderer" end
        return "innocent"
    end
    local char = player.Character
    if char then
        if char:FindFirstChild("Knife") then return "murderer" end
        if char:FindFirstChild("Gun") then return "sheriff" end
    end
    local bp = player:FindFirstChildOfClass("Backpack")
    if bp then
        if bp:FindFirstChild("Knife") then return "murderer" end
        if bp:FindFirstChild("Gun") then return "sheriff" end
    end
    local attr = player:GetAttribute("Role")
    if attr then
        local r = string.lower(tostring(attr))
        if r == "murderer" or r == "sheriff" or r == "hero" then
            return r == "hero" and "sheriff" or r
        end
    end
    return "innocent"
end

local function get_role_color(role)
    if role == "murderer" then return cfg.role_color_murderer or Color3.fromRGB(255, 60, 60) end
    if role == "sheriff" then return cfg.role_color_sheriff or Color3.fromRGB(0, 153, 255) end
    return cfg.role_color_innocent or Color3.fromRGB(255, 255, 255)
end

local player_chams_orig = {}

local function restore_player_parts(player)
    local orig_data = player_chams_orig[player]
    if orig_data then
        for part, data in pairs(orig_data) do
            if part and part.Parent then
                pcall(function()
                    part.Material = data.Material
                    part.Color = data.Color
                    part.Transparency = data.Transparency
                end)
            end
        end
        player_chams_orig[player] = nil
    end
    local char = player and player.Character
    if char then
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") then
                local thl = child:FindFirstChild("VantageToolNoHighlight")
                if thl then pcall(function() thl:Destroy() end) end
            end
        end
    end
end

local function clear_chams(player)
    if ctx.chams[player] then
        pcall(function() ctx.chams[player]:Destroy() end)
        ctx.chams[player] = nil
    end
    restore_player_parts(player)
end

local function is_gun_tool(tool)
    if not tool or not tool:IsA("Tool") then return false end
    local name = string.lower(tool.Name)

    -- Melee and common non-firearm exclusions
    if name:find("knife") or name:find("sword") or name:find("blade") or name:find("dagger")
        or name:find("axe") or name:find("bat") or name:find("katana") or name:find("hammer")
        or name:find("scythe") or name:find("melee") or name:find("fist") or name:find("punch")
        or name:find("claw") or name:find("spear") or name:find("shield") or name:find("staff")
        or name:find("toy") or name:find("pizza") or name:find("drink") or name:find("radio")
        or name:find("medkit") or name:find("bandage") or name:find("bomb") or name:find("potion") then
        return false
    end

    if tool:FindFirstChild("KnifeScript") or tool:FindFirstChild("KnifeLocal") or tool:FindFirstChild("Throw") then
        return false
    end

    -- Explicit firearm matches
    if name:find("gun") or name:find("pistol") or name:find("revolver") or name:find("rifle")
        or name:find("shotgun") or name:find("sniper") or name:find("smg") or name:find("blaster")
        or name:find("firearm") or name:find("bow") or name:find("laser") then
        return true
    end

    if tool:FindFirstChild("Muzzle") or tool:FindFirstChild("_muzzle") or tool:FindFirstChild("MuzzleFlash")
        or tool:FindFirstChild("GunScript") or tool:FindFirstChild("GunLocal") or tool:FindFirstChild("Ammo") then
        return true
    end

    return false
end

local function get_barrel_pos()
    local char = local_player.Character
    if not char then return nil end

    local vms = workspace:FindFirstChild("ViewModels")
    local fp = vms and vms:FindFirstChild("FirstPerson")
    local my_vm = nil
    if fp then
        for _, c in ipairs(fp:GetChildren()) do
            if c.Name:find(local_player.Name) then my_vm = c; break end
        end
    end
    if not my_vm and vms then
        for _, c in ipairs(vms:GetChildren()) do
            if c ~= fp and c.Name:find(local_player.Name) then my_vm = c; break end
        end
    end

    if my_vm then
        if typeof(my_vm.GetMuzzleAttachment) == "function" then
            local ok, muzzle = pcall(my_vm.GetMuzzleAttachment, my_vm)
            if ok and muzzle and muzzle:IsA("Attachment") then return muzzle.WorldPosition end
        end
        local muzzle_att = my_vm:FindFirstChild("_muzzle", true) or my_vm:FindFirstChild("Muzzle", true)
        if muzzle_att and muzzle_att:IsA("Attachment") then return muzzle_att.WorldPosition end
    end

    local tool = char:FindFirstChildOfClass("Tool")
    if tool and is_gun_tool(tool) then
        local muzzle = tool:FindFirstChild("_muzzle", true) or tool:FindFirstChild("Muzzle", true) or tool:FindFirstChild("MuzzleFlash", true)
        if muzzle then
            if muzzle:IsA("Attachment") then return muzzle.WorldPosition end
            if muzzle:IsA("BasePart") then return muzzle.Position end
        end
        local handle = tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart")
        if handle then return handle.Position end
    end

    local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
    if hand then return hand.Position end

    return camera and camera.CFrame.Position
end

local function get_tracer_end_pos()
    if not camera then return nil end
    local mouse_pos = user_input_service:GetMouseLocation()
    local unit_ray = camera:ViewportPointToRay(mouse_pos.X, mouse_pos.Y)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = local_player.Character and { local_player.Character } or {}
    local hit = workspace:Raycast(unit_ray.Origin, unit_ray.Direction * 1000, params)
    return hit and hit.Position or (unit_ray.Origin + unit_ray.Direction * 1000)
end

local function make_tracer(from_pos, to_pos)
    if not (toggles.bullet_tracer and toggles.bullet_tracer.Value) then return end
    local char = local_player.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not from_pos and tool and not is_gun_tool(tool) then return end
    if not from_pos then from_pos = get_barrel_pos() end
    if not to_pos then to_pos = get_tracer_end_pos() end
    if not from_pos or not to_pos then return end

    local color = (options.tracer_color and options.tracer_color.Value) or Color3.fromRGB(140, 230, 255)
    local duration = (options.tracer_duration and options.tracer_duration.Value) or 0.75
    local width = (options.tracer_width and options.tracer_width.Value) or 0.15
    local mode = "beam"
    if options.tracer_mode and options.tracer_mode.Value then
        mode = string.lower(tostring(options.tracer_mode.Value))
    end

    local dist = (to_pos - from_pos).Magnitude
    if dist < 0.05 then return end

    local beam_w = width * 2
    local beam_tex = "rbxassetid://13712004045"
    local beam_segs = math.clamp(math.floor(dist / 4), 10, 30)
    local base_trans = 0.12
    local curved = true
    if mode == "line" then
        beam_w = width * 0.75
        beam_tex = ""
        beam_segs = 1
        base_trans = 0.05
        curved = false
    end

    local a0 = Instance.new("Attachment")
    a0.WorldPosition = from_pos
    a0.Parent = workspace.Terrain

    local a1 = Instance.new("Attachment")
    a1.WorldPosition = to_pos
    a1.Parent = workspace.Terrain

    local beam = Instance.new("Beam")
    beam.Attachment0 = a0
    beam.Attachment1 = a1
    beam.Color = ColorSequence.new(color)
    beam.LightEmission = 1
    beam.LightInfluence = 0
    beam.Width0 = beam_w
    beam.Width1 = beam_w
    beam.FaceCamera = true
    beam.Segments = beam_segs
    beam.Texture = beam_tex
    beam.TextureMode = Enum.TextureMode.Static
    beam.TextureLength = 15
    beam.TextureSpeed = 40
    if curved then
        beam.CurveSize0 = (math.random() - 0.5) * math.min(dist * 0.08, 5)
        beam.CurveSize1 = (math.random() - 0.5) * math.min(dist * 0.08, 5)
    else
        beam.CurveSize0 = 0
        beam.CurveSize1 = 0
    end
    beam.Transparency = NumberSequence.new(base_trans)
    beam.Parent = workspace.Terrain

    local ref = { beam = beam, a0 = a0, a1 = a1 }
    ctx.tracers[ref] = true

    task.spawn(function()
        local t0 = os.clock()
        while ctx.running do
            local dt = os.clock() - t0
            if dt >= duration then break end
            local alpha = dt / duration
            local trans = math.clamp(alpha * alpha, 0, 1)
            beam.Transparency = NumberSequence.new(math.clamp(base_trans + trans, 0, 1))
            run_service.RenderStepped:Wait()
        end
        ctx.tracers[ref] = nil
        pcall(function() beam:Destroy() end)
        pcall(function() a0:Destroy() end)
        pcall(function() a1:Destroy() end)
    end)
end

local function tracer_pos_value(v)
    if typeof(v) == "Vector3" then return v end
    if typeof(v) == "Instance" then
        if v:IsA("BasePart") then return v.Position end
        if v:IsA("Attachment") then
            local ok, wp = pcall(function() return v.WorldPosition end)
            if ok and typeof(wp) == "Vector3" then return wp end
        end
    end
    return nil
end

local last_tracer_time = 0
local function trigger_bullet_tracer(from_pos, to_pos)
    if not (toggles.bullet_tracer and toggles.bullet_tracer.Value) then return end
    local now = os.clock()
    if (now - last_tracer_time) < 0.03 then return end
    last_tracer_time = now
    task.defer(make_tracer, from_pos, to_pos)
end

table.insert(ctx.conns, user_input_service.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if not (toggles.bullet_tracer and toggles.bullet_tracer.Value) then return end
        local char = local_player.Character
        local tool = char and char:FindFirstChildOfClass("Tool")
        if tool and is_gun_tool(tool) then
            trigger_bullet_tracer()
        end
    end
end))

local function hook_tool_tracer(tool)
    if not tool or not tool:IsA("Tool") or not is_gun_tool(tool) then return end
    table.insert(ctx.conns, tool.Activated:Connect(function()
        if toggles.bullet_tracer and toggles.bullet_tracer.Value then
            trigger_bullet_tracer()
        end
    end))
end

if local_player.Character then
    for _, item in ipairs(local_player.Character:GetChildren()) do
        if item:IsA("Tool") then hook_tool_tracer(item) end
    end
    table.insert(ctx.conns, local_player.Character.ChildAdded:Connect(function(c)
        if c:IsA("Tool") then hook_tool_tracer(c) end
    end))
end

table.insert(ctx.conns, local_player.CharacterAdded:Connect(function(char)
    table.insert(ctx.conns, char.ChildAdded:Connect(function(c)
        if c:IsA("Tool") then hook_tool_tracer(c) end
    end))
end))

pcall(function()
    local rs = cloneref(game:GetService("ReplicatedStorage"))
    local we = rs:FindFirstChild("WeaponEvents")
    local gun_beam = we and we:FindFirstChild("GunBeam")
    if gun_beam and gun_beam:IsA("RemoteEvent") then
        table.insert(ctx.conns, gun_beam.OnClientEvent:Connect(function(...)
            local from_pos, to_pos = nil, nil
            for _, a in ipairs({ ... }) do
                local vec = tracer_pos_value(a)
                if vec then
                    if not from_pos then from_pos = vec
                    elseif not to_pos then to_pos = vec break end
                end
            end
            trigger_bullet_tracer(from_pos, to_pos)
        end))
    end

    local cs = rs:FindFirstChild("ClientServices")
    local ws = cs and cs:FindFirstChild("WeaponService")
    local gf = ws and ws:FindFirstChild("GunFired")
    if gf and gf:IsA("RemoteEvent") then
        table.insert(ctx.conns, gf.OnClientEvent:Connect(function(player, hit_pos)
            if player == local_player or player == local_player.Name or player == nil then
                local to_pos = tracer_pos_value(hit_pos)
                trigger_bullet_tracer(nil, to_pos)
            end
        end))
    end
end)

pcall(function()
    local ps = local_player:FindFirstChild("PlayerScripts")
    if not ps then return end

    local client_vm_mod = ps:FindFirstChild("ClientViewModel", true)
    if client_vm_mod then
        local client_vm = require(client_vm_mod)
        if client_vm and type(client_vm.MuzzleFlash) == "function" and not hook_muzzle_flash then
            local orig_mf = client_vm.MuzzleFlash
            hook_muzzle_flash = orig_mf
            client_vm.MuzzleFlash = function(self, ...)
                local item = self and self.ClientItem
                local owner = item and item.ClientFighter
                if toggles.bullet_tracer and toggles.bullet_tracer.Value and owner and owner.IsLocalPlayer == true then
                    return
                end
                return orig_mf(self, ...)
            end
        end
    end

    local item_gun_mod = ps:FindFirstChild("ItemTypeGun", true)
    if item_gun_mod then
        local item_gun = require(item_gun_mod)
        if item_gun and type(item_gun.StartShooting) == "function" and not hook_gun_shoot then
            local orig_shoot = item_gun.StartShooting
            hook_gun_shoot = orig_shoot
            item_gun.StartShooting = function(self, ...)
                local res = table.pack(orig_shoot(self, ...))
                if toggles.bullet_tracer and toggles.bullet_tracer.Value then
                    trigger_bullet_tracer()
                end
                return table.unpack(res, 1, res.n)
            end
        end
    end
end)

local weapon_chams = {
    orig = {},
    last_vm = nil,
    cached = {}
}

function weapon_chams:clear()
    for part, data in pairs(self.orig) do
        if part and part.Parent then
            pcall(function()
                part.Material = data.Material
                part.Color = data.Color
                part.Transparency = data.Transparency
            end)
        end
    end
    self.orig = {}
    self.cached = {}
    self.last_vm = nil
end

function weapon_chams:render()
    if not cfg.weapon_chams_enabled then
        if next(self.orig) ~= nil then self:clear() end
        return
    end

    local vms = workspace:FindFirstChild("ViewModels")
    local fp = vms and vms:FindFirstChild("FirstPerson")
    local my_vm = nil

    if fp then
        for _, c in ipairs(fp:GetChildren()) do
            if c.Name:find(local_player.Name) then
                my_vm = c
                break
            end
        end
    end
    if not my_vm and vms then
        for _, c in ipairs(vms:GetChildren()) do
            if c ~= fp and c.Name:find(local_player.Name) then
                my_vm = c
                break
            end
        end
    end
    if not my_vm and local_player.Character then
        my_vm = local_player.Character:FindFirstChildOfClass("Tool")
    end

    if not my_vm then
        if self.last_vm then self:clear() end
        return
    end

    local iv = my_vm:FindFirstChild("ItemVisual") or my_vm
    if iv ~= self.last_vm then
        self:clear()
        self.last_vm = iv
        local list = {}
        for _, p in ipairs(iv:GetDescendants()) do
            if (p:IsA("MeshPart") or p:IsA("BasePart")) and p.Transparency < 1 and not p.Name:find("Reload") and not p.Name:find("Camera") and not p.Name:find("Primary") and not p.Name:find("Item$") and not p.Name:find("HumanoidRootPart") then
                table.insert(list, p)
                self.orig[p] = { Material = p.Material, Color = p.Color, Transparency = p.Transparency }
            end
        end
        self.cached = list
    end

    local mat = Enum.Material.ForceField
    local name = tostring(cfg.weapon_chams_type or "ForceField")
    if name == "Glass" or name:find("Glass") then
        mat = Enum.Material.Glass
    elseif name == "ForceField" or name:find("Forcefield") or name:find("ForceField") then
        mat = Enum.Material.ForceField
    end

    for _, p in ipairs(self.cached) do
        if p and p.Parent then
            p.Material = mat
            p.Color = cfg.weapon_chams_color or Color3.fromRGB(180, 100, 255)
            p.Transparency = cfg.weapon_chams_trans or 0
        end
    end
end

local fe_cosmetics = {
    orig_parts = {},
    orig_decals = {},
    orig_meshes = {},
    r15_korblox = {
        rul = "http://www.roblox.com/asset/?id=902942093",
        texture = "http://www.roblox.com/asset/?id=902843398"
    },
    r6_korblox = {
        mesh = "rbxassetid://902942096",
        texture = "rbxassetid://902843398"
    },
    headless_mesh = "rbxassetid://134079402"
}

function fe_cosmetics:clean_stale()
    for part in pairs(self.orig_meshes) do
        if not part or not part.Parent then self.orig_meshes[part] = nil end
    end
    for part in pairs(self.orig_parts) do
        if not part or not part.Parent then self.orig_parts[part] = nil end
    end
    for decal in pairs(self.orig_decals) do
        if not decal or not decal.Parent then self.orig_decals[decal] = nil end
    end
end

function fe_cosmetics:apply_korblox(target_char)
    local char = target_char or (local_player and local_player.Character)
    if not char then return end

    local rul = char:FindFirstChild("RightUpperLeg")
    local rll = char:FindFirstChild("RightLowerLeg")
    local rf = char:FindFirstChild("RightFoot")

    if rul and rul:IsA("MeshPart") then
        if not self.orig_meshes[rul] and rul.MeshId ~= self.r15_korblox.rul then
            self.orig_meshes[rul] = { MeshId = rul.MeshId, TextureID = rul.TextureID, Transparency = rul.Transparency }
        end
        if rul.MeshId ~= self.r15_korblox.rul then rul.MeshId = self.r15_korblox.rul end
        if rul.TextureID ~= self.r15_korblox.texture then rul.TextureID = self.r15_korblox.texture end
        if rul.Transparency ~= 0 then rul.Transparency = 0 end
    end
    if rll and rll:IsA("BasePart") then
        if self.orig_parts[rll] == nil and rll.Transparency ~= 1 then
            self.orig_parts[rll] = rll.Transparency
        end
        if rll.Transparency ~= 1 then rll.Transparency = 1 end
    end
    if rf and rf:IsA("BasePart") then
        if self.orig_parts[rf] == nil and rf.Transparency ~= 1 then
            self.orig_parts[rf] = rf.Transparency
        end
        if rf.Transparency ~= 1 then rf.Transparency = 1 end
    end

    local r6_leg = char:FindFirstChild("Right Leg")
    if r6_leg and r6_leg:IsA("BasePart") then
        local sm = r6_leg:FindFirstChildOfClass("SpecialMesh")
        if not sm then
            sm = Instance.new("SpecialMesh")
            sm.Name = "KorbloxMesh"
            sm.Parent = r6_leg
        end
        if not self.orig_meshes[sm] and sm.MeshId ~= self.r6_korblox.mesh then
            self.orig_meshes[sm] = { MeshId = sm.MeshId, TextureId = sm.TextureId, Transparency = r6_leg.Transparency }
        end
        if sm.MeshId ~= self.r6_korblox.mesh then sm.MeshId = self.r6_korblox.mesh end
        if sm.TextureId ~= self.r6_korblox.texture then sm.TextureId = self.r6_korblox.texture end
        if r6_leg.Transparency ~= 0 then r6_leg.Transparency = 0 end
    end
end

function fe_cosmetics:revert_korblox(target_char)
    local char = target_char or (local_player and local_player.Character)
    if not char then return end
    for part, data in pairs(self.orig_meshes) do
        if part and part.Parent and (not target_char or part:IsDescendantOf(target_char)) then
            pcall(function()
                if part:IsA("MeshPart") then
                    part.MeshId = data.MeshId
                    part.TextureID = data.TextureID
                    if data.Transparency ~= nil then part.Transparency = data.Transparency end
                elseif part:IsA("SpecialMesh") then
                    if part.Name == "KorbloxMesh" then
                        part:Destroy()
                    else
                        part.MeshId = data.MeshId
                        part.TextureId = data.TextureId
                    end
                    if part.Parent and part.Parent:IsA("BasePart") and data.Transparency ~= nil then
                        part.Parent.Transparency = data.Transparency
                    end
                end
            end)
        end
    end
    for part, trans in pairs(self.orig_parts) do
        if part and part.Parent and (part.Name == "RightUpperLeg" or part.Name == "RightLowerLeg" or part.Name == "RightFoot" or part.Name == "Right Leg") and (not target_char or part:IsDescendantOf(target_char)) then
            pcall(function() part.Transparency = trans end)
            self.orig_parts[part] = nil
        end
    end
    local rll = char:FindFirstChild("RightLowerLeg")
    if rll then
        local lhl = rll:FindFirstChild("VantageKorbloxNoHl")
        if lhl then pcall(function() lhl:Destroy() end) end
    end
    local rf = char:FindFirstChild("RightFoot")
    if rf then
        local fhl = rf:FindFirstChild("VantageKorbloxNoHl")
        if fhl then pcall(function() fhl:Destroy() end) end
    end
end

function fe_cosmetics:apply_headless(target_char)
    local char = target_char or (local_player and local_player.Character)
    if not char then return end
    local head = char:FindFirstChild("Head")
    if head and head:IsA("BasePart") then
        if self.orig_parts[head] == nil and head.Transparency ~= 1 then
            self.orig_parts[head] = head.Transparency
        end
        if head.Transparency ~= 1 then head.Transparency = 1 end
        local sm = head:FindFirstChildOfClass("SpecialMesh")
        if sm then
            if not self.orig_meshes[sm] and sm.Scale ~= Vector3.zero then
                self.orig_meshes[sm] = { Scale = sm.Scale, MeshId = sm.MeshId }
            end
            if sm.Scale ~= Vector3.zero then sm.Scale = Vector3.zero end
        end
        for _, d in ipairs(head:GetChildren()) do
            if d:IsA("Decal") then
                if self.orig_decals[d] == nil and d.Transparency ~= 1 then
                    self.orig_decals[d] = d.Transparency
                end
                if d.Transparency ~= 1 then d.Transparency = 1 end
            end
        end
    end
end

function fe_cosmetics:revert_headless(target_char)
    local char = target_char or (local_player and local_player.Character)
    if not char then return end
    local head = char:FindFirstChild("Head")
    if head and head:IsA("BasePart") then
        if self.orig_parts[head] ~= nil then
            pcall(function() head.Transparency = self.orig_parts[head] end)
            self.orig_parts[head] = nil
        else
            head.Transparency = 0
        end
        if self.orig_meshes[head] then
            pcall(function()
                head.MeshId = self.orig_meshes[head].MeshId
                head.TextureID = self.orig_meshes[head].TextureID
            end)
            self.orig_meshes[head] = nil
        end
        local sm = head:FindFirstChildOfClass("SpecialMesh")
        if sm and self.orig_meshes[sm] then
            pcall(function()
                sm.Scale = self.orig_meshes[sm].Scale
                sm.MeshId = self.orig_meshes[sm].MeshId
            end)
            self.orig_meshes[sm] = nil
        elseif sm and sm.Scale == Vector3.zero then
            sm.Scale = Vector3.new(1.25, 1.25, 1.25)
        end
    end
    for decal, trans in pairs(self.orig_decals) do
        if decal and decal.Parent and (not target_char or decal:IsDescendantOf(target_char)) then
            pcall(function() decal.Transparency = trans end)
            self.orig_decals[decal] = nil
        end
    end
end

function fe_cosmetics:update(target_char)
    local char = target_char or (local_player and local_player.Character)
    if not char then return end
    if cfg.fake_korblox then
        self:apply_korblox(char)
    else
        self:revert_korblox(char)
    end
    if cfg.fake_headless then
        self:apply_headless(char)
    else
        self:revert_headless(char)
    end
end

local valid_parts = {
    Head = true, UpperTorso = true, LowerTorso = true,
    LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
    RightUpperArm = true, RightLowerArm = true, RightHand = true,
    LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
    RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
    Torso = true, ["Left Arm"] = true, ["Right Arm"] = true,
    ["Left Leg"] = true, ["Right Leg"] = true
}

local clothing_types = {}
for _, name in ipairs({ "Jacket", "Sweater", "Pants", "Shorts", "Shoes", "Dress", "Shirt", "Coat", "TShirtAttachment" }) do
    pcall(function()
        local enum_val = Enum.AccessoryType[name]
        if enum_val then clothing_types[enum_val] = true end
    end)
end

-- Material Chams: Optimized ViewportFrame chams using BulkMoveTo and frustum culling.
local chromatic_chams = {
    gui = nil,
    viewport = nil,
    cam = nil,
    model = nil,
    parts = {},
    bulk_parts = {},
    bulk_cframes = {},
    _last_scan = 0
}

function chromatic_chams:init()
    if self.gui and self.gui.Parent then return end

    local sg = Instance.new("ScreenGui")
    sg.Name = "VantageMaterialChams"
    sg.IgnoreGuiInset = true
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 2147483647
    protect_gui(sg)
    self.gui = sg

    local vpf = Instance.new("ViewportFrame")
    vpf.Name = "ChamsViewport"
    vpf.Size = UDim2.new(1, 0, 1, 0)
    vpf.BackgroundTransparency = 1
    vpf.ImageTransparency = 0
    vpf.Ambient = Color3.new(1, 1, 1)
    vpf.LightColor = Color3.new(1, 1, 1)
    vpf.LightDirection = Vector3.new(-1, -1, -1)
    vpf.Active = false
    pcall(function() vpf.Interactable = false end)
    vpf.Parent = sg
    self.viewport = vpf

    local sky = lighting:FindFirstChildOfClass("Sky")
    if sky then
        pcall(function() sky:Clone().Parent = vpf end)
    end

    local vpf_cam = Instance.new("Camera")
    vpf.CurrentCamera = vpf_cam
    vpf_cam.Parent = vpf
    self.cam = vpf_cam

    local mdl = Instance.new("WorldModel")
    mdl.Name = "WorldModel"
    mdl.Parent = vpf
    self.model = mdl
end

function chromatic_chams:remove_player(p)
    local data = self.parts[p]
    if not data then return end
    if data.desc_conn then
        pcall(function() data.desc_conn:Disconnect() end)
    end
    for _, pair in ipairs(data.synced) do
        if pair.clone and pair.clone.Parent then
            pcall(function() pair.clone:Destroy() end)
        end
    end
    self.parts[p] = nil
end

function chromatic_chams:clear()
    for p in pairs(self.parts) do self:remove_player(p) end
    self.parts = {}
    table.clear(self.bulk_parts)
    table.clear(self.bulk_cframes)
    if self.model then self.model:ClearAllChildren() end
    if self.gui then
        pcall(function() self.gui:Destroy() end)
        self.gui = nil; self.viewport = nil; self.cam = nil; self.model = nil
    end
end

function chromatic_chams:update_colors()
    local col = cfg.chams_color
    local mat_name = string.lower(tostring(cfg.chams_material or ""))
    local is_foil = (mat_name == "foil")
    local trans = is_foil and 0 or (cfg.chams_fill_trans or 0)
    for _, data in pairs(self.parts) do
        for _, pair in ipairs(data.synced) do
            if pair.clone and pair.clone.Parent then
                pair.clone.Color = col
                pair.clone.Transparency = trans
            end
        end
    end
end

function chromatic_chams:update_material()
    local mat_name = string.lower(tostring(cfg.chams_material or "forcefield 2"))
    local is_foil = (mat_name == "foil")
    local is_ff = (mat_name == "forcefield 2" or mat_name == "forcefield")
    local mat_enum = is_ff and Enum.Material.ForceField or Enum.Material.Foil
    local refl = is_foil and 0.12 or 0
    local trans = is_foil and 0.025 or (cfg.chams_fill_trans or 0)
    for _, data in pairs(self.parts) do
        for _, pair in ipairs(data.synced) do
            if pair.clone and pair.clone.Parent then
                pair.clone.Material = mat_enum
                pair.clone.Reflectance = refl
                pair.clone.Transparency = trans
            end
        end
    end
end

local CHAMS_BODY = {
    Head = true, UpperTorso = true, LowerTorso = true, Torso = true,
    LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
    RightUpperArm = true, RightLowerArm = true, RightHand = true,
    LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
    RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
    ["Left Arm"] = true, ["Right Arm"] = true,
    ["Left Leg"] = true, ["Right Leg"] = true
}

local function chams_deformable(p)
    if p:FindFirstChildWhichIsA("WrapLayer") then return true end
    if CHAMS_BODY[p.Name] then return false end
    if p:FindFirstChildWhichIsA("Bone") then return true end
    local ok, skinned = pcall(function() return p.HasSkinnedMesh end)
    return ok and skinned == true
end

function chromatic_chams:build_player(player)
    local char = player.Character
    if not char or not char.Parent then return end
    self:remove_player(player)
    if not self.model or not self.model.Parent or not self.gui or not self.gui.Parent then self:init() end

    local synced = {}
    local added_parts = {}

    local mat_name = cfg.chams_material or "forcefield 2"
    local is_foil = (string.lower(mat_name) == "foil")
    local is_ff = (string.lower(mat_name) == "forcefield 2" or string.lower(mat_name) == "forcefield")
    local mat_enum = is_ff and Enum.Material.ForceField or Enum.Material.Foil
    local refl = is_foil and 0.12 or 0

    local function add_part(part)
        if not part:IsA("BasePart") or added_parts[part] then return end
        if part.Name == "HumanoidRootPart" or part.Transparency >= 0.95 then return end
        if chams_deformable(part) then return end
        added_parts[part] = true

        local arch = part.Archivable
        if not arch then pcall(function() part.Archivable = true end) end
        local ok, cloned = pcall(part.Clone, part)
        if not arch then pcall(function() part.Archivable = arch end) end
        if ok and cloned then
            for _, child in ipairs(cloned:GetChildren()) do
                if not child:IsA("DataModelMesh") then
                    pcall(function() child:Destroy() end)
                end
            end
            local mesh = cloned:FindFirstChildWhichIsA("DataModelMesh")
            local scale = cfg.chromatic_scale or 1.012
            if mesh then
                pcall(function() mesh.Scale = mesh.Scale * scale end)
                pcall(function() mesh.TextureId = "" end)
            else
                cloned.Size = cloned.Size * scale
            end
            pcall(function() cloned.TextureID = "" end)
            pcall(function() cloned.MaterialVariant = "" end)

            cloned.Anchored = true
            cloned.CanCollide = false
            cloned.CanTouch = false
            cloned.CanQuery = false
            cloned.CastShadow = false
            cloned.Massless = true
            cloned.Material = mat_enum
            cloned.Color = cfg.chams_color or Color3.fromRGB(255, 255, 255)
            cloned.Transparency = is_foil and 0.025 or (cfg.chams_fill_trans or 0)
            cloned.Reflectance = refl
            cloned.LocalTransparencyModifier = 0
            cloned.CFrame = part.CFrame
            cloned.Parent = self.model
            table.insert(synced, { orig = part, clone = cloned })
        end
    end

    for _, desc in ipairs(char:GetDescendants()) do
        if desc:IsA("BasePart") then
            add_part(desc)
        end
    end

    local desc_conn = char.DescendantAdded:Connect(function(desc)
        if not char or not char.Parent then return end
        if desc:IsA("BasePart") then
            task.wait(0.05)
            if char and char.Parent and not added_parts[desc] then
                add_part(desc)
            end
        end
    end)

    self.parts[player] = { char = char, synced = synced, desc_conn = desc_conn, is_visible = true }
end

function chromatic_chams:render(dt)
    if not cfg.chams_enabled or (cfg.chams_mode or "Highlight") ~= "Material" then
        if self.gui and self.gui.Enabled then self.gui.Enabled = false end
        return
    end

    if not self.gui or not self.gui.Parent then self:init() end
    if not self.gui.Enabled then self.gui.Enabled = true end

    local cur_cam = workspace.CurrentCamera
    if not cur_cam then return end

    if self.cam then
        self.cam.CFrame = cur_cam.CFrame
        self.cam.FieldOfView = cur_cam.FieldOfView
    end

    local now = os.clock()
    if (now - self._last_scan) >= 0.5 then
        self._last_scan = now
        for _, p in ipairs(ctx.roster) do
            if p ~= local_player and p.Character and p.Character.Parent and not is_teammate(p) then
                local data = self.parts[p]
                if not data or data.char ~= p.Character or #data.synced == 0 then
                    self:build_player(p)
                end
            elseif self.parts[p] then
                self:remove_player(p)
            end
        end
    end

    table.clear(self.bulk_parts)
    table.clear(self.bulk_cframes)
    local bulk_count = 0
    local cam_pos = cur_cam.CFrame.Position
    local max_dist = cfg.max_dist or 1000

    for player, data in pairs(self.parts) do
        local char = data.char
        if not char or not char.Parent or is_teammate(player) then
            self:remove_player(player)
            continue
        end

        local hum = char:FindFirstChildOfClass("Humanoid")
        local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
        if not hum or hum.Health <= 0 or not root then
            if data.is_visible then
                data.is_visible = false
                for _, pair in ipairs(data.synced) do
                    if pair.clone and pair.clone.Parent then
                        bulk_count = bulk_count + 1
                        self.bulk_parts[bulk_count] = pair.clone
                        self.bulk_cframes[bulk_count] = CFrame.new(0, -99999, 0)
                    end
                end
            end
            continue
        end

        local root_pos = root.Position
        local dist = (cam_pos - root_pos).Magnitude
        if dist > max_dist then
            if data.is_visible then
                data.is_visible = false
                for _, pair in ipairs(data.synced) do
                    if pair.clone and pair.clone.Parent then
                        bulk_count = bulk_count + 1
                        self.bulk_parts[bulk_count] = pair.clone
                        self.bulk_cframes[bulk_count] = CFrame.new(0, -99999, 0)
                    end
                end
            end
            continue
        end

        data.is_visible = true

        for _, pair in ipairs(data.synced) do
            local orig, clone = pair.orig, pair.clone
            if orig and orig.Parent and clone and clone.Parent then
                bulk_count = bulk_count + 1
                self.bulk_parts[bulk_count] = clone
                self.bulk_cframes[bulk_count] = orig.CFrame
                if is_foil then
                    local hidden = math.max(orig.Transparency, orig.LocalTransparencyModifier) >= 1
                    local target_trans = hidden and 1 or 0.025
                    if clone.Transparency ~= target_trans then
                        clone.Transparency = target_trans
                    end
                end
            end
        end
    end

    if bulk_count > 0 then
        workspace:BulkMoveTo(self.bulk_parts, self.bulk_cframes, Enum.BulkMoveMode.FireCFrameChanged)
    end
end

local particle_urls = {
    snowflake = "https://img.icons8.com/ios-filled/250/ffffff/snowflake.png",
    star = "https://img.icons8.com/ios-filled/250/ffffff/star.png",
    sparkle = "https://img.icons8.com/ios-filled/250/ffffff/sparkling.png",
    dollar = "https://img.icons8.com/ios-filled/250/ffffff/us-dollar.png",
    cash = "https://img.icons8.com/ios-filled/250/ffffff/banknotes.png",
    sakura = "rbxasset://textures/particles/smoke_main.dds"
}

local particles = {
    part = nil,
    emitter = nil,
    gen = 0,
    asset = nil,
    folder = nil,
    simulated = {},
    ray_params = nil
}

function particles:clear()
    self.gen = self.gen + 1
    if self.part then
        pcall(function() self.part:Destroy() end)
        self.part = nil
        self.emitter = nil
    end
    if self.folder then
        pcall(function() self.folder:Destroy() end)
        self.folder = nil
    end
    self.simulated = {}
    for _, child in ipairs(workspace.Terrain:GetChildren()) do
        if child:IsA("BasePart") and child.Transparency == 1 and child:FindFirstChildOfClass("ParticleEmitter") then
            pcall(function() child:Destroy() end)
        end
    end
end

function particles:update_colors()
    if self.emitter then
        self.emitter.Color = ColorSequence.new(cfg.particles_color)
    end
    for _, p in ipairs(self.simulated) do
        if p.image and p.image.Parent then p.image.ImageColor3 = cfg.particles_color end
    end
end

function particles:update_size()
    if self.emitter then
        local sz = cfg.particles_size
        self.emitter.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, sz * 0.55),
            NumberSequenceKeypoint.new(0.15, sz),
            NumberSequenceKeypoint.new(0.85, sz),
            NumberSequenceKeypoint.new(1, sz * 0.4)
        })
    end
    local sz = (cfg.particles_size or 0.45) * 2.8
    for _, p in ipairs(self.simulated) do
        if p.gui and p.gui.Parent then p.gui.Size = UDim2.fromScale(sz, sz) end
    end
end

function particles:update_trans()
    if self.emitter then
        local a = cfg.particles_trans
        self.emitter.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.06, a),
            NumberSequenceKeypoint.new(0.88, a),
            NumberSequenceKeypoint.new(1, 1)
        })
    end
    for _, p in ipairs(self.simulated) do
        if p.image and p.image.Parent then p.image.ImageTransparency = cfg.particles_trans end
    end
end

function particles:update_rate()
    if self.emitter then self.emitter.Rate = cfg.particles_count * 1.6 end
end

function particles:update_flight()
    if not self.emitter then return end
    local mode = string.lower(cfg.particle_flight or "wind")
    if mode == "wind" then
        self.emitter.Speed = NumberRange.new(1.8, 4.2)
        self.emitter.SpreadAngle = Vector2.new(12, 12)
        self.emitter.Drag = 0.4
    elseif mode == "down" then
        self.emitter.Speed = NumberRange.new(3, 7)
        self.emitter.SpreadAngle = Vector2.new(6, 6)
        self.emitter.Drag = 0.2
        self.emitter.Acceleration = Vector3.new(0, -6, 0)
    elseif mode == "up" then
        self.emitter.Speed = NumberRange.new(2.5, 6)
        self.emitter.SpreadAngle = Vector2.new(8, 8)
        self.emitter.Drag = 0.3
        self.emitter.Acceleration = Vector3.new(0, 4.5, 0)
    elseif mode == "up/down" then
        self.emitter.Speed = NumberRange.new(1.5, 4)
        self.emitter.SpreadAngle = Vector2.new(20, 20)
        self.emitter.Drag = 0.5
        self.emitter.Acceleration = Vector3.zero
    elseif mode == "random" then
        self.emitter.Speed = NumberRange.new(1, 5)
        self.emitter.SpreadAngle = Vector2.new(45, 45)
        self.emitter.Drag = 0.6
        self.emitter.Acceleration = Vector3.zero
    elseif mode == "rain" then
        self.emitter.Speed = NumberRange.new(16, 24)
        self.emitter.SpreadAngle = Vector2.new(4, 4)
        self.emitter.Drag = 0
        self.emitter.Acceleration = Vector3.new(0, -25, 0)
    end
end

function particles:create_collision_particle(center, is_initial)
    local cur_gen = self.gen
    local angle = math.random() * math.pi * 2
    local r = 5 + math.random() * 55
    local x = center.X + math.cos(angle) * r
    local z = center.Z + math.sin(angle) * r
    local y = center.Y + (is_initial and math.random(5, 45) or math.random(35, 60))

    local bb = Instance.new("BillboardGui")
    bb.AlwaysOnTop = false
    local sz = (cfg.particles_size or 0.45) * 2.8
    bb.Size = UDim2.fromScale(sz, sz)
    bb.Adornee = nil

    local img = Instance.new("ImageLabel")
    img.BackgroundTransparency = 1
    img.Size = UDim2.fromScale(1, 1)
    local cur_tex = string.lower(cfg.particle_texture or "snowflake")
    img.Image = (cur_tex == "sakura") and "rbxasset://textures/particles/smoke_main.dds" or (self.asset or particle_urls[cur_tex] or particle_urls.snowflake)
    img.ImageColor3 = cfg.particles_color
    img.ImageTransparency = cfg.particles_trans
    img.Parent = bb
    bb.Parent = self.folder

    local data = {
        gui = bb,
        image = img,
        pos = Vector3.new(x, y, z),
        vel = Vector3.new(math.random(-2, 2), -((string.lower(cfg.particle_flight or "") == "rain") and math.random(22, 30) or math.random(3, 7)), math.random(-2, 2)),
        bouncing = false,
        spawn_time = os.clock() + math.random() * 2
    }
    table.insert(self.simulated, data)
end

function particles:init_collision()
    self.simulated = {}
    if self.folder then pcall(function() self.folder:Destroy() end) end
    local f = Instance.new("Folder")
    f.Parent = workspace.Terrain
    self.folder = f

    local cam = workspace.CurrentCamera
    local center = cam and cam.CFrame.Position or Vector3.zero
    for i = 1, math.min(cfg.particles_count, 60) do
        self:create_collision_particle(center, true)
    end
end

function particles:init()
    self:clear()
    if not cfg.particles_enabled then return end

    local tex_key = string.lower(cfg.particle_texture or "snowflake")
    if tex_key == "sakura" then
        self.asset = "rbxasset://textures/particles/smoke_main.dds"
    else
        local url = particle_urls[tex_key] or particle_urls.snowflake
        if typeof(makefolder) == "function" and typeof(isfolder) == "function" then
            if not isfolder("vantage") then pcall(makefolder, "vantage") end
            if not isfolder("vantage/assets") then pcall(makefolder, "vantage/assets") end
        end
        local fn = "vantage/assets/particle_" .. tex_key .. ".png"
        if typeof(isfile) == "function" and isfile(fn) and typeof(getcustomasset) == "function" then
            self.asset = getcustomasset(fn)
        else
            task.spawn(function()
                local ok, body = pcall(game.HttpGet, game, url)
                if ok and body and typeof(writefile) == "function" and typeof(getcustomasset) == "function" then
                    writefile(fn, body)
                    self.asset = getcustomasset(fn)
                    if self.emitter and string.lower(cfg.particle_texture or "") ~= "sakura" then
                        self.emitter.Texture = self.asset
                    end
                    for _, p in ipairs(self.simulated) do
                        if p.image and p.image.Parent then p.image.Image = self.asset end
                    end
                end
            end)
        end
    end

    if not cfg.particle_collide then
        local p = Instance.new("Part")
        p.Size = Vector3.new(150, 40, 150)
        p.Transparency = 1
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.CastShadow = false
        p.Parent = workspace.Terrain
        self.part = p

        local em = Instance.new("ParticleEmitter")
        local is_sak = (tex_key == "sakura")
        em.Texture = is_sak and "rbxasset://textures/particles/smoke_main.dds" or (self.asset or url)
        em.Lifetime = is_sak and NumberRange.new(5.0, 7.0) or NumberRange.new(7.0, 11.0)
        em.Rate = cfg.particles_count * 1.6
        em.RotSpeed = NumberRange.new(-35, 35)
        em.Rotation = NumberRange.new(0, 360)
        em.EmissionDirection = Enum.NormalId.Bottom
        em.Shape = Enum.ParticleEmitterShape.Box
        em.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
        em.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
        em.VelocitySpread = 18
        em.ShapePartial = 1
        em.LightEmission = 0.8
        em.LightInfluence = 0
        em.Orientation = Enum.ParticleOrientation.FacingCamera
        em.Parent = p
        self.emitter = em

        if is_sak then
            pcall(function() em.Squash = NumberSequence.new(1.4) end)
            em.RotSpeed = NumberRange.new(-80, 80)
            em.Speed = NumberRange.new(5, 10)
            em.Acceleration = Vector3.new(4, -5, 2)
            em.SpreadAngle = Vector2.new(40, 40)
        end
        self:update_colors()
        self:update_size()
        self:update_trans()
        self:update_flight()
    else
        self:init_collision()
    end
end

function particles:render()
    if not cfg.particles_enabled then return end
    local char = local_player.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    local cur_cam = workspace.CurrentCamera
    local target_pos = root and root.Position or (cur_cam and cur_cam.CFrame.Position)
    if not target_pos then return end

    if not cfg.particle_collide then
        if not self.part or not self.part.Parent or not self.emitter then return end
        local mode = string.lower(cfg.particle_flight or "wind")
        local y_off = (mode == "up") and 0 or 15
        self.part.CFrame = CFrame.new(target_pos.X, target_pos.Y + y_off, target_pos.Z)

        local t = os.clock()
        local wind_s = cfg.particle_wind or 1
        if mode == "up/down" then
            self.emitter.Acceleration = Vector3.new(0, math.sin(t * 1.3) * 1.6, 0)
        elseif mode == "rain" then
            local wx = (math.sin(t * 0.45) * 2.4 + math.cos(t * 0.18) * 1.2) * wind_s
            local wz = (math.cos(t * 0.38) * 2.4 + math.sin(t * 0.22) * 1.2) * wind_s
            self.emitter.Acceleration = Vector3.new(wx, -25, wz)
        elseif mode == "wind" or mode == "random" then
            local wx = (math.sin(t * 0.45) * 2.4 + math.cos(t * 0.18) * 1.2) * wind_s
            local wz = (math.cos(t * 0.38) * 2.4 + math.sin(t * 0.22) * 1.2) * wind_s
            local wy = -0.4 + math.sin(t * 0.65) * 1.2
            self.emitter.Acceleration = Vector3.new(wx, wy, wz)
        end
    else
        if not self.simulated or not self.folder or not self.folder.Parent then
            self:init_collision()
            return
        end

        local dt = 0.016
        local now = os.clock()

        if not self.ray_params then
            self.ray_params = RaycastParams.new()
            self.ray_params.FilterType = Enum.RaycastFilterType.Exclude
        end
        local filter = { self.folder, workspace.CurrentCamera }
        if char then table.insert(filter, char) end
        self.ray_params.FilterDescendantsInstances = filter

        local mode = string.lower(cfg.particle_flight or "wind")
        local wind_s = cfg.particle_wind or 1
        local is_wind = (mode == "wind" or mode == "random")
        local wind = Vector3.zero
        if is_wind then
            local t = now
            local sway = (t * 0.15) % (math.pi * 2)
            local str = (2.5 + math.sin(t * 0.4) * 1.5) * wind_s
            wind = Vector3.new(math.cos(sway) * str + math.sin(t * 0.8) * wind_s, math.sin(t * 0.95) * 0.8, math.sin(sway) * str + math.cos(t * 0.7) * wind_s)
        end

        for _, p in ipairs(self.simulated) do
            if not p.bouncing then
                local cur_vel = p.vel + wind
                local delta = cur_vel * dt
                local move_dist = delta.Magnitude
                local move_dir = move_dist > 1e-4 and (delta / move_dist) or Vector3.new(0, -1, 0)
                local cast_dist = math.max(move_dist + 0.5, 0.75)

                local hit = workspace:Raycast(p.pos, move_dir * cast_dist, self.ray_params)
                if not hit then
                    hit = workspace:Raycast(p.pos, Vector3.new(0, -0.75, 0), self.ray_params)
                end

                local is_hit = false
                if hit and hit.Instance then
                    local inst = hit.Instance
                    if inst:IsA("Terrain") or inst.CanCollide then
                        is_hit = true
                    elseif inst:IsA("BasePart") and inst.Transparency < 0.98 and inst.Size.Magnitude > 0.3 then
                        is_hit = true
                    end
                end

                if is_hit then
                    local normal = hit.Normal
                    p.pos = hit.Position + normal * 0.15
                    local normal_dot = cur_vel:Dot(normal)
                    local tangent = cur_vel - normal_dot * normal
                    local bounce_speed = math.max(-normal_dot * 0.6, 2.6)
                    local bounce_vel = tangent * 0.9 + normal * bounce_speed

                    if tangent.Magnitude < 0.5 then
                        local sc = Vector3.new(math.random(-10, 10), 0, math.random(-10, 10))
                        if sc.Magnitude > 0 then bounce_vel = bounce_vel + sc.Unit * 1.5 end
                    end

                    p.vel = bounce_vel
                    p.bouncing = true
                    task.delay(0.08, function() p.bouncing = false end)
                else
                    p.pos = p.pos + delta
                    p.vel = p.vel + Vector3.new(0, -9.8 * dt * 0.45, 0)
                end

                local cam = workspace.CurrentCamera
                local cam_pos = cam and cam.CFrame.Position or Vector3.zero
                if (p.pos - cam_pos).Magnitude > 75 or (p.pos.Y - cam_pos.Y) < -35 then
                    local angle = math.random() * math.pi * 2
                    local r = 5 + math.random() * 55
                    p.pos = Vector3.new(cam_pos.X + math.cos(angle) * r, cam_pos.Y + math.random(30, 55), cam_pos.Z + math.sin(angle) * r)
                    p.vel = Vector3.new(math.random(-2, 2), -((mode == "rain") and math.random(22, 30) or math.random(3, 7)), math.random(-2, 2))
                end

                if p.gui and p.gui.Parent then
                    p.gui.CFrame = CFrame.new(p.pos)
                end
            end
        end
    end
end

local world = {
    cc = nil,
    bloom = nil
}
function world:apply()
    if not cfg.ambient_enabled then
        self:reset()
        return
    end
    lighting.Ambient = cfg.ambient_color
    lighting.OutdoorAmbient = cfg.outdoor_color
    lighting.ClockTime = cfg.clock_time
    lighting.FogColor = cfg.fog_color
    lighting.FogStart = cfg.fog_start
    lighting.FogEnd = cfg.fog_end
    lighting.ExposureCompensation = 0.2

    if not self.cc then
        local cc = Instance.new("ColorCorrectionEffect")
        cc.Name = "_v_ambient_cc"
        cc.Parent = lighting
        self.cc = cc
    end
    self.cc.Brightness = cfg.ambient_brightness or 0.05
    self.cc.Contrast = cfg.ambient_contrast or 0.15
    self.cc.Saturation = cfg.ambient_saturation or 0.25
    self.cc.TintColor = cfg.ambient_color:Lerp(Color3.fromRGB(255, 255, 255), 0.75)

    if not self.bloom then
        local b = Instance.new("BloomEffect")
        b.Name = "_v_ambient_bloom"
        b.Parent = lighting
        self.bloom = b
    end
    self.bloom.Intensity = cfg.ambient_bloom or 0.75
    self.bloom.Size = 24
    self.bloom.Threshold = 1.1
end

function world:reset()
    pcall(function()
        lighting.Ambient = baseline.ambient
        lighting.OutdoorAmbient = baseline.outdoor
        lighting.FogColor = baseline.fog_color
        lighting.FogStart = baseline.fog_start
        lighting.FogEnd = baseline.fog_end
        lighting.ClockTime = baseline.clock_time
        lighting.ExposureCompensation = baseline.exposure or 0
        if baseline.brightness then lighting.Brightness = baseline.brightness end
        if baseline.global_shadows ~= nil then lighting.GlobalShadows = baseline.global_shadows end
        if baseline.color_shift_bottom then lighting.ColorShift_Bottom = baseline.color_shift_bottom end
        if baseline.color_shift_top then lighting.ColorShift_Top = baseline.color_shift_top end
    end)
    if self.cc then
        pcall(function() self.cc:Destroy() end)
        self.cc = nil
    end
    if self.bloom then
        pcall(function() self.bloom:Destroy() end)
        self.bloom = nil
    end
    for _, child in ipairs(lighting:GetChildren()) do
        if child.Name == "_v_ambient_cc" or child.Name == "_v_ambient_bloom" or child.Name == "VantageNightCC" then
            pcall(function() child:Destroy() end)
        end
    end
    if ambient_overlay and ambient_overlay.frame then
        ambient_overlay.frame.Visible = false
    end
end

local shaders = {
    color_cor = nil,
    bloom = nil,
    blur = nil,
    depth = nil,
    atmosphere = nil,
    cloud = nil,
    last_tick = 0,
    presets = {
        morning = {
            Ambient = Color3.fromRGB(10, 10, 10),
            Brightness = 1.5,
            ClockTime = 7.5,
            ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
            ColorShift_Top = Color3.fromRGB(200, 200, 200),
            EnvironmentDiffuseScale = 0.1,
            EnvironmentSpecularScale = 0.1,
            OutdoorAmbient = Color3.fromRGB(10, 10, 10),
            GeographicLatitude = 44,
            ExposureCompensation = 0.3,
            GlobalShadows = true,
            ColorCorrection = { Brightness = -0.02, Contrast = 0.8, Saturation = -0.5, TintColor = Color3.fromRGB(100, 150, 200) },
            Bloom = { Intensity = 0.2, Size = 5, Threshold = 0.8 },
            Blur = { Size = 2 },
            DepthOfField = { FarIntensity = 0.5, FocusDistance = 15, InFocusRadius = 5, NearIntensity = 0.5 },
            Atmosphere = { Density = 0.2, Offset = 0.5, Color = Color3.fromRGB(70, 120, 170), Decay = Color3.fromRGB(10, 50, 100), Glare = 0.3, Haze = 1 },
            Clouds = { Cover = 0.6, Density = 0.36, Color = Color3.fromRGB(255, 255, 255) }
        },
        midday = {
            Ambient = Color3.fromRGB(30, 30, 30),
            Brightness = 2.0,
            ClockTime = 14,
            ColorShift_Bottom = Color3.fromRGB(10, 10, 10),
            ColorShift_Top = Color3.fromRGB(255, 255, 255),
            EnvironmentDiffuseScale = 0.3,
            EnvironmentSpecularScale = 0.3,
            OutdoorAmbient = Color3.fromRGB(40, 40, 40),
            GeographicLatitude = 44,
            ExposureCompensation = 0.1,
            GlobalShadows = true,
            ColorCorrection = { Brightness = 0, Contrast = 0.4, Saturation = -0.1, TintColor = Color3.fromRGB(255, 250, 240) },
            Bloom = { Intensity = 0.15, Size = 4, Threshold = 0.85 },
            Blur = { Size = 1 },
            DepthOfField = { FarIntensity = 0.3, FocusDistance = 25, InFocusRadius = 10, NearIntensity = 0.2 },
            Atmosphere = { Density = 0.15, Offset = 0.25, Color = Color3.fromRGB(200, 210, 225), Decay = Color3.fromRGB(106, 112, 125), Glare = 0.2, Haze = 0.5 },
            Clouds = { Cover = 0.4, Density = 0.2, Color = Color3.fromRGB(255, 255, 255) }
        },
        evening = {
            Ambient = Color3.fromRGB(20, 15, 10),
            Brightness = 1.0,
            ClockTime = 17.8,
            ColorShift_Bottom = Color3.fromRGB(5, 5, 5),
            ColorShift_Top = Color3.fromRGB(255, 150, 80),
            EnvironmentDiffuseScale = 0.15,
            EnvironmentSpecularScale = 0.15,
            OutdoorAmbient = Color3.fromRGB(25, 18, 12),
            GeographicLatitude = 44,
            ExposureCompensation = 0.2,
            GlobalShadows = true,
            ColorCorrection = { Brightness = -0.05, Contrast = 0.6, Saturation = 0.1, TintColor = Color3.fromRGB(255, 180, 120) },
            Bloom = { Intensity = 0.3, Size = 7, Threshold = 0.75 },
            Blur = { Size = 2 },
            DepthOfField = { FarIntensity = 0.6, FocusDistance = 12, InFocusRadius = 4, NearIntensity = 0.4 },
            Atmosphere = { Density = 0.3, Offset = 0.4, Color = Color3.fromRGB(255, 140, 60), Decay = Color3.fromRGB(180, 60, 20), Glare = 0.5, Haze = 1.5 },
            Clouds = { Cover = 0.7, Density = 0.45, Color = Color3.fromRGB(255, 160, 100) }
        },
        night = {
            Ambient = Color3.fromRGB(5, 5, 8),
            Brightness = 0.3,
            ClockTime = 0,
            ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
            ColorShift_Top = Color3.fromRGB(40, 50, 80),
            EnvironmentDiffuseScale = 0.05,
            EnvironmentSpecularScale = 0.05,
            OutdoorAmbient = Color3.fromRGB(5, 5, 10),
            GeographicLatitude = 44,
            ExposureCompensation = -0.1,
            GlobalShadows = true,
            ColorCorrection = { Brightness = -0.1, Contrast = 0.5, Saturation = -0.4, TintColor = Color3.fromRGB(120, 140, 200) },
            Bloom = { Intensity = 0.1, Size = 3, Threshold = 0.9 },
            Blur = { Size = 1 },
            DepthOfField = { FarIntensity = 0.7, FocusDistance = 10, InFocusRadius = 3, NearIntensity = 0.6 },
            Atmosphere = { Density = 0.25, Offset = 0.2, Color = Color3.fromRGB(15, 20, 40), Decay = Color3.fromRGB(5, 10, 25), Glare = 0, Haze = 2 },
            Clouds = { Cover = 0.5, Density = 0.3, Color = Color3.fromRGB(40, 45, 60) }
        }
    }
}

function shaders:ensure_effects()
    if not self.color_cor or not self.color_cor.Parent then
        self.color_cor = lighting:FindFirstChild("_v_shader_cc") or Instance.new("ColorCorrectionEffect")
        self.color_cor.Name = "_v_shader_cc"
        self.color_cor.Parent = lighting
    end
    if not self.bloom or not self.bloom.Parent then
        self.bloom = lighting:FindFirstChild("_v_shader_bloom") or Instance.new("BloomEffect")
        self.bloom.Name = "_v_shader_bloom"
        self.bloom.Parent = lighting
    end
    if not self.blur or not self.blur.Parent then
        self.blur = lighting:FindFirstChild("_v_shader_blur") or Instance.new("BlurEffect")
        self.blur.Name = "_v_shader_blur"
        self.blur.Parent = lighting
    end
    if not self.depth or not self.depth.Parent then
        self.depth = lighting:FindFirstChild("_v_shader_dof") or Instance.new("DepthOfFieldEffect")
        self.depth.Name = "_v_shader_dof"
        self.depth.Parent = lighting
    end
    if not self.atmosphere or not self.atmosphere.Parent then
        self.atmosphere = lighting:FindFirstChild("_v_shader_atmo") or Instance.new("Atmosphere")
        self.atmosphere.Name = "_v_shader_atmo"
        self.atmosphere.Parent = lighting
    end
    local terrain = workspace.Terrain or workspace:FindFirstChildOfClass("Terrain")
    if terrain and (not self.cloud or not self.cloud.Parent) then
        self.cloud = terrain:FindFirstChild("_v_shader_cloud") or Instance.new("Clouds")
        self.cloud.Name = "_v_shader_cloud"
        self.cloud.Parent = terrain
    end
end

function shaders:apply(preset_name)
    local d = self.presets[preset_name]
    if not d then return end
    self:ensure_effects()

    local b_mult = cfg.shaders_brightness or 1.0
    local exp_add = cfg.shaders_exposure or 0.0

    lighting.Ambient = Color3.new(
        math.clamp(d.Ambient.R * b_mult, 0, 1),
        math.clamp(d.Ambient.G * b_mult, 0, 1),
        math.clamp(d.Ambient.B * b_mult, 0, 1)
    )
    lighting.Brightness = math.clamp(d.Brightness * b_mult, 0, 10)
    lighting.ClockTime = d.ClockTime
    lighting.ColorShift_Bottom = d.ColorShift_Bottom
    lighting.ColorShift_Top = d.ColorShift_Top
    lighting.EnvironmentDiffuseScale = d.EnvironmentDiffuseScale
    lighting.EnvironmentSpecularScale = d.EnvironmentSpecularScale
    lighting.OutdoorAmbient = Color3.new(
        math.clamp(d.OutdoorAmbient.R * b_mult, 0, 1),
        math.clamp(d.OutdoorAmbient.G * b_mult, 0, 1),
        math.clamp(d.OutdoorAmbient.B * b_mult, 0, 1)
    )
    lighting.GeographicLatitude = d.GeographicLatitude
    lighting.ExposureCompensation = d.ExposureCompensation + exp_add
    lighting.GlobalShadows = d.GlobalShadows
    if lighting.FogEnd ~= math.huge then lighting.FogEnd = math.huge end
    if lighting.FogStart ~= math.huge then lighting.FogStart = math.huge end
    if lighting.FogColor ~= Color3.fromRGB(255, 255, 255) then lighting.FogColor = Color3.fromRGB(255, 255, 255) end

    if self.color_cor and d.ColorCorrection then
        self.color_cor.Brightness = math.clamp(d.ColorCorrection.Brightness + (b_mult - 1.0) * 0.15, -1, 1)
        self.color_cor.Contrast = d.ColorCorrection.Contrast
        self.color_cor.Saturation = d.ColorCorrection.Saturation
        self.color_cor.TintColor = d.ColorCorrection.TintColor
        self.color_cor.Enabled = true
    end

    if self.bloom and d.Bloom then
        self.bloom.Intensity = d.Bloom.Intensity
        self.bloom.Size = d.Bloom.Size
        self.bloom.Threshold = d.Bloom.Threshold
        self.bloom.Enabled = true
    end

    if self.blur and d.Blur then
        self.blur.Size = d.Blur.Size
        self.blur.Enabled = false
    end

    if self.depth and d.DepthOfField then
        self.depth.FarIntensity = d.DepthOfField.FarIntensity
        self.depth.FocusDistance = d.DepthOfField.FocusDistance
        self.depth.InFocusRadius = d.DepthOfField.InFocusRadius
        self.depth.NearIntensity = d.DepthOfField.NearIntensity
        self.depth.Enabled = true
    end

    if self.atmosphere and d.Atmosphere then
        self.atmosphere.Density = d.Atmosphere.Density
        self.atmosphere.Offset = d.Atmosphere.Offset
        self.atmosphere.Color = d.Atmosphere.Color
        self.atmosphere.Decay = d.Atmosphere.Decay
        self.atmosphere.Glare = d.Atmosphere.Glare
        self.atmosphere.Haze = d.Atmosphere.Haze
    end

    if self.cloud and d.Clouds then
        self.cloud.Cover = d.Clouds.Cover
        self.cloud.Density = d.Clouds.Density
        self.cloud.Color = d.Clouds.Color
    end
end

function shaders:reset()
    if self.color_cor then self.color_cor.Enabled = false end
    if self.bloom then self.bloom.Enabled = false end
    if self.blur then self.blur.Enabled = false end
    if self.depth then self.depth.Enabled = false end

    pcall(function()
        lighting.Ambient = baseline.ambient
        lighting.OutdoorAmbient = baseline.outdoor
        lighting.Brightness = baseline.brightness or 1
        lighting.FogColor = baseline.fog_color
        lighting.FogStart = baseline.fog_start
        lighting.FogEnd = baseline.fog_end
        lighting.GlobalShadows = baseline.global_shadows ~= nil and baseline.global_shadows or true
        lighting.ClockTime = baseline.clock_time
        if baseline.color_shift_bottom then lighting.ColorShift_Bottom = baseline.color_shift_bottom end
        if baseline.color_shift_top then lighting.ColorShift_Top = baseline.color_shift_top end
        lighting.ExposureCompensation = baseline.exposure or 0
    end)
end

local self_chams = {
    orig = {},
    last_char = nil,
    highlight = nil
}

function self_chams:reset()
    if self.highlight then
        pcall(function() self.highlight:Destroy() end)
        self.highlight = nil
    end
    if self.last_char then
        for _, tool in ipairs(self.last_char:GetChildren()) do
            if tool:IsA("Tool") then
                local hl = tool:FindFirstChild("VantageToolNoHighlight")
                if hl then pcall(function() hl:Destroy() end) end
            end
        end
        local head = self.last_char:FindFirstChild("Head")
        if head then
            local hhl = head:FindFirstChild("VantageHeadlessNoHl")
            if hhl then pcall(function() hhl:Destroy() end) end
        end
        local rll = self.last_char:FindFirstChild("RightLowerLeg")
        if rll then
            local lhl = rll:FindFirstChild("VantageKorbloxNoHl")
            if lhl then pcall(function() lhl:Destroy() end) end
        end
        local rf = self.last_char:FindFirstChild("RightFoot")
        if rf then
            local fhl = rf:FindFirstChild("VantageKorbloxNoHl")
            if fhl then pcall(function() fhl:Destroy() end) end
        end
    end
    for part, data in pairs(self.orig) do
        if part and part.Parent then
            pcall(function()
                part.Material = data.Material
                part.Color = data.Color
                part.Transparency = data.Transparency
            end)
        end
    end
    self.orig = {}
    self.last_char = nil
    self.hl_state = nil
    self.parts_list = nil
    self.parts_char = nil
    self.parts_scan = 0
    self.tool_scan = 0
end

function self_chams:render()
    if not cfg.self_chams_enabled then
        if next(self.orig) ~= nil or self.highlight ~= nil then
            self:reset()
        end
        return
    end

    local char = local_player.Character
    if not char or not char.Parent then
        if self.last_char then self:reset() end
        return
    end

    if char ~= self.last_char then
        self:reset()
        self.last_char = char
    end

    local mode = string.lower(tostring(cfg.self_chams_mode or "forcefield 2"))
    local color = cfg.self_chams_color or Color3.fromHex("#b464ff")
    local trans = cfg.self_chams_trans or 0.6
    local now = os.clock()

    local needs_highlight = (mode == "forcefield 2" or mode == "highlight")
    if needs_highlight then
        if not self.highlight or self.highlight.Parent ~= char then
            if self.highlight then pcall(function() self.highlight:Destroy() end) end
            local h = Instance.new("Highlight")
            h.Name = "VantageSelfChams"
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.Parent = char
            self.highlight = h
            self.hl_state = nil
        end
        local fill_t = (mode == "highlight") and 0.5 or math.clamp(trans, 0.1, 0.9)
        local hs = self.hl_state
        if not hs or hs.color ~= color or hs.fill ~= fill_t or hs.mode ~= mode then
            self.highlight.FillColor = color
            self.highlight.OutlineColor = color
            self.highlight.FillTransparency = fill_t
            self.highlight.OutlineTransparency = 0
            self.highlight.Enabled = true
            self.hl_state = { color = color, fill = fill_t, mode = mode }
        end

        if (now - (self.tool_scan or 0)) > 0.5 then
            self.tool_scan = now
            for _, child in ipairs(char:GetChildren()) do
                if child:IsA("Tool") then
                    if not child:FindFirstChild("VantageToolNoHighlight") then
                        local thl = Instance.new("Highlight")
                        thl.Name = "VantageToolNoHighlight"
                        thl.FillTransparency = 1
                        thl.OutlineTransparency = 1
                        thl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        thl.Parent = child
                    end
                end
            end
        end

        local head = char:FindFirstChild("Head")
        if cfg.fake_headless and head then
            if not head:FindFirstChild("VantageHeadlessNoHl") then
                local hhl = Instance.new("Highlight")
                hhl.Name = "VantageHeadlessNoHl"
                hhl.FillTransparency = 1
                hhl.OutlineTransparency = 1
                hhl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hhl.Parent = head
            end
        elseif head and head:FindFirstChild("VantageHeadlessNoHl") then
            pcall(function() head.VantageHeadlessNoHl:Destroy() end)
        end

        local rll = char:FindFirstChild("RightLowerLeg")
        local rf = char:FindFirstChild("RightFoot")
        if cfg.fake_korblox then
            if rll and not rll:FindFirstChild("VantageKorbloxNoHl") then
                local lhl = Instance.new("Highlight")
                lhl.Name = "VantageKorbloxNoHl"
                lhl.FillTransparency = 1
                lhl.OutlineTransparency = 1
                lhl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                lhl.Parent = rll
            end
            if rf and not rf:FindFirstChild("VantageKorbloxNoHl") then
                local fhl = Instance.new("Highlight")
                fhl.Name = "VantageKorbloxNoHl"
                fhl.FillTransparency = 1
                fhl.OutlineTransparency = 1
                fhl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                fhl.Parent = rf
            end
        else
            if rll and rll:FindFirstChild("VantageKorbloxNoHl") then
                pcall(function() rll.VantageKorbloxNoHl:Destroy() end)
            end
            if rf and rf:FindFirstChild("VantageKorbloxNoHl") then
                pcall(function() rf.VantageKorbloxNoHl:Destroy() end)
            end
        end
    else
        if self.highlight then
            pcall(function() self.highlight:Destroy() end)
            self.highlight = nil
        end
    end

    local modifies_parts = (mode == "forcefield" or mode == "forcefield 2")
    if modifies_parts then
        local target_mat = Enum.Material.ForceField
        if char ~= self.parts_char or (now - (self.parts_scan or 0)) > 0.5 then
            self.parts_char = char
            self.parts_scan = now
            local list = {}
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and not part:FindFirstAncestorOfClass("Tool") then
                    list[#list + 1] = part
                end
            end
            self.parts_list = list
        end
        local head_inst = char:FindFirstChild("Head")
        for _, part in ipairs(self.parts_list or {}) do
            if part and part.Parent then
                local pName = part.Name
                local is_head_part = (pName == "Head" or (head_inst and part:IsDescendantOf(head_inst)))
                local is_korblox_hidden = cfg.fake_korblox and (pName == "RightLowerLeg" or pName == "RightFoot")
                local is_korblox_rul = cfg.fake_korblox and (pName == "RightUpperLeg" or pName == "Right Leg")

                if cfg.fake_headless and is_head_part then
                    if part.Transparency ~= 1 then part.Transparency = 1 end
                elseif is_korblox_hidden then
                    if part.Transparency ~= 1 then part.Transparency = 1 end
                elseif is_korblox_rul then
                    -- Preserve Korblox authentic upper leg mesh and texture
                else
                    if not self.orig[part] then
                        self.orig[part] = { Material = part.Material, Color = part.Color, Transparency = part.Transparency }
                    end
                    if part.Material ~= target_mat then part.Material = target_mat end
                    if part.Color ~= color then part.Color = color end
                    if part.Transparency ~= trans then part.Transparency = trans end
                end
            end
        end
    else
        if next(self.orig) ~= nil then
            for part, data in pairs(self.orig) do
                if part and part.Parent then
                    pcall(function()
                        part.Material = data.Material
                        part.Color = data.Color
                        part.Transparency = data.Transparency
                    end)
                end
            end
            self.orig = {}
        end
    end
end

local CH_SEGMENTS = 48
local CH_TAU = math.pi * 2
local CH_MAX_ROWS = 220

local ch_2d = {
    rows = {},
    px = table.create(CH_SEGMENTS + 1),
    py = table.create(CH_SEGMENTS + 1),
    cos = table.create(CH_SEGMENTS),
    sin = table.create(CH_SEGMENTS),
    ord = table.create(CH_SEGMENTS + 1),
    stack = table.create(CH_SEGMENTS + 2),
    shown = {},
    cpos = {},
    csize = {},
    ccol = {},
    white = Color3.new(1, 1, 1),
    black = Color3.new(0, 0, 0),
    eps = 0.75,
    cached = {},
    built_radius = nil
}

local function ch_2d_rebuild_trig(radius)
    if ch_2d.built_radius == radius then return end
    ch_2d.built_radius = radius
    for i = 1, CH_SEGMENTS do
        local angle = (i - 1) / CH_SEGMENTS * CH_TAU
        ch_2d.cos[i] = math.cos(angle) * radius
        ch_2d.sin[i] = math.sin(angle) * radius
    end
end
ch_2d_rebuild_trig(cfg.china_hat_radius or 1.55)

local function ch_2d_order(i, j)
    local px, py = ch_2d.px, ch_2d.py
    local ax, bx = px[i], px[j]
    return ax == bx and py[i] < py[j] or ax < bx
end

local function ch_2d_hull(n)
    local px, py, ord, st = ch_2d.px, ch_2d.py, ch_2d.ord, ch_2d.stack
    for i = 1, n do ord[i] = i end
    table.sort(ord, ch_2d_order)
    local m = 0
    for k = 1, n do
        local i = ord[k]
        local x, y = px[i], py[i]
        while m >= 2 do
            local o, a = st[m - 1], st[m]
            local ox, oy = px[o], py[o]
            if (px[a] - ox) * (y - oy) - (py[a] - oy) * (x - ox) > 0 then break end
            m = m - 1
        end
        m = m + 1
        st[m] = i
    end
    local lower = m
    for k = n - 1, 1, -1 do
        local i = ord[k]
        local x, y = px[i], py[i]
        while m > lower do
            local o, a = st[m - 1], st[m]
            local ox, oy = px[o], py[o]
            if (px[a] - ox) * (y - oy) - (py[a] - oy) * (x - ox) > 0 then break end
            m = m - 1
        end
        m = m + 1
        st[m] = i
    end
    return m - 1
end

local function ch_2d_get_row(index, alpha)
    local rows = ch_2d.rows
    local row = rows[index]
    if row then
        row.Transparency = alpha
        return row
    end
    row = Drawing.new("Square")
    row.Filled = true
    row.Thickness = 0
    row.Transparency = alpha
    row.Visible = false
    row.ZIndex = 1
    rows[index] = row
    ch_2d.shown[index] = false
    return row
end

local china_hat = {
    part = nil,
    mesh = nil,
    rotation = 0
}

function china_hat:clear_2d()
    for _, r in ipairs(ch_2d.rows) do
        pcall(function() r:Remove() end)
    end
    table.clear(ch_2d.rows)
    table.clear(ch_2d.shown)
    table.clear(ch_2d.cpos)
    table.clear(ch_2d.csize)
    table.clear(ch_2d.ccol)
    table.clear(ch_2d.cached)
    ch_2d.built_radius = nil
end

function china_hat:hide_2d()
    for i = 1, #ch_2d.rows do
        if ch_2d.shown[i] then
            ch_2d.rows[i].Visible = false
            ch_2d.shown[i] = false
        end
    end
end

function china_hat:render_2d(cur_cam, head)
    if not head or not cur_cam then
        self:hide_2d()
        return
    end

    local radius = cfg.china_hat_radius or 1.55
    local height_val = cfg.china_hat_height or 0.82
    local drop_val = cfg.china_hat_drop or 0.02
    local alpha_val = 1 - (cfg.china_hat_trans or 0.28)
    ch_2d_rebuild_trig(radius)

    local head_pos = head.Position
    local cam_cf = cur_cam.CFrame
    local fov = cur_cam.FieldOfView
    local view = cur_cam.ViewportSize
    local view_x, view_y = view.X, view.Y
    local col = cfg.china_hat_color or Color3.fromHex("#b464ff")

    local c = ch_2d.cached
    if c.head == head and c.pos == head_pos and c.cf == cam_cf
        and c.fov == fov and c.vx == view_x and c.vy == view_y and c.col == col
        and c.radius == radius and c.height == height_val and c.alpha == alpha_val then
        return
    end
    c.head, c.pos, c.cf = head, head_pos, cam_cf
    c.fov, c.vx, c.vy, c.col = fov, view_x, view_y, col
    c.radius, c.height, c.alpha = radius, height_val, alpha_val

    local base_y = head_pos.Y + head.Size.Y * 0.5 - drop_val
    local center = Vector3.new(head_pos.X, base_y, head_pos.Z)
    local apex = cur_cam:WorldToViewportPoint(center + Vector3.new(0, height_val, 0))
    if apex.Z <= 0 then
        self:hide_2d()
        return
    end

    local probe = cur_cam:WorldToViewportPoint(center + Vector3.new(ch_2d.cos[1], 0, ch_2d.sin[1]))
    if probe.Z <= 0 then
        self:hide_2d()
        return
    end

    local px, py, cos_t, sin_t = ch_2d.px, ch_2d.py, ch_2d.cos, ch_2d.sin
    px[1], py[1] = apex.X, apex.Y
    px[2], py[2] = probe.X, probe.Y

    local cam_pos = cam_cf.Position
    local rv, uv, lv = cam_cf.RightVector, cam_cf.UpVector, cam_cf.LookVector
    local ox, oy, oz = center.X - cam_pos.X, center.Y - cam_pos.Y, center.Z - cam_pos.Z
    local base_r = ox * rv.X + oy * rv.Y + oz * rv.Z
    local base_u = ox * uv.X + oy * uv.Y + oz * uv.Z
    local base_d = ox * lv.X + oy * lv.Y + oz * lv.Z
    local rvx, rvz, uvx, uvz, lvx, lvz = rv.X, rv.Z, uv.X, uv.Z, lv.X, lv.Z
    local scale = view_y * 0.5 / math.tan(math.rad(fov * 0.5))
    local mid_x, mid_y = view_x * 0.5, view_y * 0.5
    local eps = ch_2d.eps
    local exact = false

    local dep = base_d + height_val * lv.Y
    if dep > 0 then
        local inv = scale / dep
        if math.abs(mid_x + (base_r + height_val * rv.Y) * inv - apex.X) <= eps
            and math.abs(mid_y - (base_u + height_val * uv.Y) * inv - apex.Y) <= eps then
            local c1, s1 = cos_t[1], sin_t[1]
            dep = base_d + c1 * lvx + s1 * lvz
            if dep > 0 then
                inv = scale / dep
                if math.abs(mid_x + (base_r + c1 * rvx + s1 * rvz) * inv - probe.X) <= eps
                    and math.abs(mid_y - (base_u + c1 * uvx + s1 * uvz) * inv - probe.Y) <= eps then
                    exact = true
                end
            end
        end
    end

    if exact then
        for i = 2, CH_SEGMENTS do
            local cv, sv = cos_t[i], sin_t[i]
            local d = base_d + cv * lvx + sv * lvz
            if d <= 0 then
                self:hide_2d()
                return
            end
            local inv = scale / d
            px[i + 1] = mid_x + (base_r + cv * rvx + sv * rvz) * inv
            py[i + 1] = mid_y - (base_u + cv * uvx + sv * uvz) * inv
        end
    else
        for i = 2, CH_SEGMENTS do
            local point = cur_cam:WorldToViewportPoint(center + Vector3.new(cos_t[i], 0, sin_t[i]))
            if point.Z <= 0 then
                self:hide_2d()
                return
            end
            px[i + 1] = point.X
            py[i + 1] = point.Y
        end
    end

    local hn = ch_2d_hull(CH_SEGMENTS + 1)
    if hn < 3 then
        self:hide_2d()
        return
    end

    local st = ch_2d.stack
    local min_y, max_y = math.huge, -math.huge
    for i = 1, hn do
        local y = py[st[i]]
        if y < min_y then min_y = y end
        if y > max_y then max_y = y end
    end

    local first_y = math.max(0, math.floor(min_y))
    local last_y = math.min(view_y, math.ceil(max_y))
    if last_y - first_y < 2 then
        self:hide_2d()
        return
    end

    local step = math.max(1, math.ceil((last_y - first_y) / CH_MAX_ROWS))
    local span = math.max(1, max_y - min_y)
    local rows, shown = ch_2d.rows, ch_2d.shown
    local cpos, csize, ccol = ch_2d.cpos, ch_2d.csize, ch_2d.ccol
    local white, black = ch_2d.white, ch_2d.black
    local used = 0

    for y0 = first_y, last_y - 1, step do
        local height = math.min(step, last_y - y0)
        local y = y0 + height * 0.5
        local left, right = math.huge, -math.huge
        local ax, ay = px[st[hn]], py[st[hn]]
        for i = 1, hn do
            local ix = st[i]
            local bx, by = px[ix], py[ix]
            if (ay <= y and by > y) or (by <= y and ay > y) then
                local x = ax + (y - ay) * (bx - ax) / (by - ay)
                if x < left then left = x end
                if x > right then right = x end
            end
            ax, ay = bx, by
        end

        local width = right - left
        if width >= 2.5 then
            used = used + 1
            local row = ch_2d_get_row(used, alpha_val)
            local t = (y - min_y) / span
            local light = math.max(0, 1 - t * 1.35)
            local dark = math.max(0, (t - 0.58) / 0.42)
            local row_col = col:Lerp(white, light * 0.26):Lerp(black, dark * 0.1)
            local pos = Vector2.new(left, y0)
            local size = Vector2.new(width, height)

            if cpos[used] ~= pos then
                row.Position = pos
                cpos[used] = pos
            end
            if csize[used] ~= size then
                row.Size = size
                csize[used] = size
            end
            if ccol[used] ~= row_col then
                row.Color = row_col
                ccol[used] = row_col
            end
            if not shown[used] then
                row.Visible = true
                shown[used] = true
            end
        end
    end

    for i = used + 1, #rows do
        if shown[i] then
            rows[i].Visible = false
            shown[i] = false
        end
    end
end

function china_hat:get_part()
    local cur_cam = workspace.CurrentCamera
    if not cur_cam then return nil end

    if self.part and self.part.Parent == cur_cam then
        return self.part
    end

    if self.part then
        pcall(function() self.part:Destroy() end)
        self.part = nil
        self.mesh = nil
    end

    local part = Instance.new("Part")
    part.Name = "ChinaHatCone"
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Material = Enum.Material.SmoothPlastic
    local radius = cfg.china_hat_radius or 2.2
    local cone_h = math.clamp(radius * 0.28, 0.35, 1.2)
    part.Size = Vector3.new(radius * 2, cone_h, radius * 2)

    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = "rbxassetid://1033714"
    mesh.Scale = Vector3.new(radius * 2, cone_h * 2, radius * 2)
    mesh.Parent = part
    self.mesh = mesh

    part.Color = cfg.china_hat_color or Color3.fromHex("#b464ff")
    part.Transparency = cfg.china_hat_trans or 0.4
    part.Parent = cur_cam
    self.part = part
    return part
end

function china_hat:init()
    self:get_part()
end

function china_hat:clear()
    self:clear_2d()
    if self.part then
        pcall(function() self.part:Destroy() end)
        self.part = nil
        self.mesh = nil
    end
end

function china_hat:hide()
    if self.part then
        self.part.Transparency = 1
        self.part.CFrame = CFrame.new(0, -9999, 0)
    end
    local old_l = self.part and self.part:FindFirstChild("HatFillLight")
    if old_l then pcall(function() old_l:Destroy() end) end
    local old_hl = self.part and self.part:FindFirstChild("HatHighlight")
    if old_hl then pcall(function() old_hl:Destroy() end) end
end

function china_hat:render(dt)
    if not cfg.china_hat_enabled then
        self:hide()
        self:hide_2d()
        return
    end

    local cur_cam = workspace.CurrentCamera
    local char = local_player.Character
    local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not head or not cur_cam or (hum and hum.Health <= 0) then
        self:hide()
        self:hide_2d()
        return
    end

    local dist_to_cam = (cur_cam.CFrame.Position - head.Position).Magnitude
    local is_first_person = dist_to_cam < 1.4 or (head:IsA("BasePart") and head.LocalTransparencyModifier > 0.5)

    if is_first_person then
        self:hide()
        self:hide_2d()
        return
    end

    local mode = cfg.china_hat_mode or "3D"
    if mode == "2D" or mode == "2D Drawing" then
        self:hide()
        self:render_2d(cur_cam, head)
        return
    else
        self:hide_2d()
    end

    local part = self:get_part()
    if not part then return end

    local radius = cfg.china_hat_radius or 2.2
    local h_offset = cfg.china_hat_height or 0.65
    local trans = cfg.china_hat_trans or 0.4
    local speed = cfg.china_hat_speed or 2.0
    local color = cfg.china_hat_color or Color3.fromHex("#b464ff")
    local cone_h = math.clamp(radius * 0.28, 0.35, 1.2)

    local step = (type(dt) == "number" and dt > 0 and dt < 0.2) and dt or (1 / 60)
    self.rotation = (self.rotation + (speed * 45 * step)) % 360

    local head_top = head.Position + Vector3.new(0, (head.Size.Y * 0.5) + h_offset, 0)

    part.Material = Enum.Material.SmoothPlastic
    part.CFrame = CFrame.new(head_top) * CFrame.Angles(0, math.rad(self.rotation), 0)
    part.Size = Vector3.new(radius * 2, cone_h, radius * 2)
    part.Color = color
    part.Transparency = trans

    if self.mesh then
        self.mesh.Scale = Vector3.new(radius * 2, cone_h * 2, radius * 2)
        self.mesh.VertexColor = Vector3.new(1, 1, 1)
    end

    local old_l = part:FindFirstChild("HatFillLight")
    if old_l then pcall(function() old_l:Destroy() end) end
    local old_hl = part:FindFirstChild("HatHighlight")
    if old_hl then pcall(function() old_hl:Destroy() end) end
end

local AURA_GROUPS = {
    head = { "Head" },
    torso = { "Torso", "UpperTorso", "LowerTorso", "HumanoidRootPart", "Root" },
    larm = { "Left Arm", "LeftUpperArm", "LeftLowerArm", "LeftHand" },
    rarm = { "Right Arm", "RightUpperArm", "RightLowerArm", "RightHand" },
    lleg = { "Left Leg", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" },
    rleg = { "Right Leg", "RightUpperLeg", "RightLowerLeg", "RightFoot" },
}

local aura_group_map = {}
for grp, names in pairs(AURA_GROUPS) do
    for _, name in ipairs(names) do
        aura_group_map[name] = grp
    end
end

local auras = {
    cache = {},
    particles = {},
    host = nil,
    list = { "angel", "starlight", "heavenly", "ribbon", "sakura", "wind", "flow", "star" },
    ids = {
        angel = "97658130917593",
        starlight = "134645216613107",
        heavenly = "139300897520961",
        ribbon = "132069507632161",
        sakura = "81755778619404",
        wind = "80694081850877",
        flow = "119913533725648",
        star = "73754563740680"
    }
}

local function aura_center(host)
    local primary = host.PrimaryPart
    if primary and primary:IsA("BasePart") then return primary end
    local pick, best = nil, -1
    for _, d in ipairs(host:GetDescendants()) do
        if d:IsA("BasePart") then
            local size = d.Size
            local vol = size.X * size.Y * size.Z
            if vol > best then pick, best = d, vol end
        end
    end
    return pick
end

local function aura_slot(host, name, center)
    local direct = host:FindFirstChild(name, true)
    if direct and direct:IsA("BasePart") then return direct end
    local group = aura_group_map[name]
    if group then
        local names = AURA_GROUPS[group]
        for i = 1, #names do
            local part = host:FindFirstChild(names[i], true)
            if part and part:IsA("BasePart") then return part end
        end
    end
    return center
end

local function color_aura_model(model, col)
    local seq = ColorSequence.new(col)
    for _, obj in ipairs(model:GetDescendants()) do
        if obj:IsA("PointLight") then
            pcall(function() obj.Color = col end)
        elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
            pcall(function() obj.Color = seq end)
        end
    end
end

function auras:load_model(name)
    if self.cache[name] then return self.cache[name] end
    local id = self.ids[name]
    if not id then return nil end

    local ok, objs = pcall(function() return game:GetObjects("rbxassetid://" .. id) end)
    if not ok or type(objs) ~= "table" then return nil end

    local model = nil
    for _, o in ipairs(objs) do
        if o:IsA("Model") then model = o break end
    end
    if not model and objs[1] then
        model = objs[1]
    end
    if not model then return nil end

    color_aura_model(model, cfg.aura_color or Color3.fromRGB(133, 220, 255))
    self.cache[name] = model
    return model
end

function auras:clear()
    for i = #self.particles, 1, -1 do
        pcall(function() self.particles[i]:Destroy() end)
        self.particles[i] = nil
    end
    table.clear(self.particles)
    
    local function clean_model(model)
        if not model then return end
        for _, part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") then
                for _, child in ipairs(part:GetChildren()) do
                    if child:IsA("ParticleEmitter") or child:IsA("Beam") or child:IsA("Trail") or child:IsA("PointLight") then
                        local is_aura = false
                        for aura_name, _ in pairs(self.ids) do
                            if child.Name:lower():find(aura_name) or child.Name:find("Aura") or child.Name:find("Effect") then
                                is_aura = true
                                break
                            end
                        end
                        if is_aura then
                            pcall(function() child:Destroy() end)
                        end
                    end
                end
            end
        end
    end

    local char = local_player.Character
    if char then clean_model(char) end
    self.host = nil
end

function auras:set_color(col)
    for _, m in pairs(self.cache) do
        color_aura_model(m, col)
    end
    local seq = ColorSequence.new(col)
    for _, p in ipairs(self.particles) do
        if p:IsA("PointLight") then
            pcall(function() p.Color = col end)
        elseif p:IsA("ParticleEmitter") or p:IsA("Trail") or p:IsA("Beam") then
            pcall(function() p.Color = seq end)
        end
    end
end

function auras:apply()
    self:clear()
    local char = local_player.Character
    if not char or not char.Parent then return end

    local src = self:load_model(cfg.aura_type or "angel")
    if not src then return end
    color_aura_model(src, cfg.aura_color or Color3.fromRGB(133, 220, 255))

    local center = aura_center(char)
    local cloned = src:Clone()
    for _, part in ipairs(cloned:GetChildren()) do
        local target = aura_slot(char, part.Name, center)
        if target and target:IsA("BasePart") then
            for _, child in ipairs(part:GetChildren()) do
                child.Parent = target
                self.particles[#self.particles + 1] = child
            end
        end
    end
    cloned:Destroy()
    self.host = char
end

function auras:render()
    if not cfg.auras_enabled then
        if self.host then self:clear() end
        return
    end

    local char = local_player.Character
    if char ~= self.host then
        self:apply()
        return
    end
    if not char then return end

    local first = self.particles[1]
    if first and not first.Parent then
        self:apply()
    end
end

local backtrack = {
    history = {},
    clone = nil,
    max_history_time = 1.0,
    min_dist = 0.25,
    orig_map = nil,
    map_char = nil,
    ping_cache = 0.15,
    ping_t = 0,
}

local function get_real_ping_seconds()
    local ping = 0.15
    pcall(function()
        local pingItem = stats.Network.ServerStatsItem:FindFirstChild("Data Ping")
        if pingItem then
            ping = pingItem:GetValue() / 1000
        end
    end)
    return math.clamp(ping, 0.05, 0.8)
end

local function make_forcefield_ghost(model, ghost_color, transparency)
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() hum:Destroy() end) end
    local anim = model:FindFirstChildOfClass("AnimationController")
    if anim then pcall(function() anim:Destroy() end) end

    for _, item in ipairs(model:GetDescendants()) do
        if item:IsA("Script") or item:IsA("LocalScript") or item:IsA("ModuleScript") or item:IsA("Animator") then
            pcall(function() item:Destroy() end)
        elseif item:IsA("UIComponent") or item:IsA("ScreenGui") or item:IsA("BillboardGui") then
            pcall(function() item:Destroy() end)
        elseif item:IsA("BasePart") then
            item.Anchored = true
            item.CanCollide = false
            item.CanTouch = false
            item.CanQuery = false
            item.CastShadow = false
            item.Massless = true
            if item.Name == "HumanoidRootPart" then
                item.Transparency = 1
            elseif cfg.fake_headless and (item.Name == "Head" or (model:FindFirstChild("Head") and item:IsDescendantOf(model.Head))) then
                item.Transparency = 1
            elseif cfg.fake_korblox and (item.Name == "RightLowerLeg" or item.Name == "RightFoot") then
                item.Transparency = 1
            else
                item.Material = Enum.Material.ForceField
                item.Color = ghost_color
                item.Transparency = transparency or 0.4
            end
        end
    end
end

function backtrack:clear()
    if self.clone then
        pcall(function() self.clone:Destroy() end)
        self.clone = nil
    end
    self.part_pairs = nil
    self.map_clone = nil
    self.map_char = nil
    table.clear(self.history)
end

function backtrack:render()
    if not cfg.backtrack_enabled or not local_player.Character then
        if self.clone then
            pcall(function() self.clone:Destroy() end)
            self.clone = nil
        end
        return
    end

    local char = local_player.Character
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then
        if self.clone then
            pcall(function() self.clone:Destroy() end)
            self.clone = nil
        end
        return
    end

    local now = os.clock()
    table.insert(self.history, { time = now, cframe = hrp.CFrame })

    while #self.history > 0 and (now - self.history[1].time) > self.max_history_time do
        table.remove(self.history, 1)
    end

    local real_ping = backtrack.ping_cache or 0.15
    if (now - (backtrack.ping_t or 0)) > 1 then
        real_ping = get_real_ping_seconds()
        backtrack.ping_cache = real_ping
        backtrack.ping_t = now
    end
    local target_time = now - real_ping * 0.5
    local target_cframe = hrp.CFrame
    for i = #self.history, 1, -1 do
        local e = self.history[i]
        if e.time <= target_time then
            local nxt = self.history[i + 1]
            if nxt then
                local span = nxt.time - e.time
                local a = (span > 0) and ((target_time - e.time) / span) or 0
                target_cframe = e.cframe:Lerp(nxt.cframe, math.clamp(a, 0, 1))
            else
                target_cframe = e.cframe
            end
            break
        end
    end

    local dist = (target_cframe.Position - hrp.Position).Magnitude
    local is_overlapping = (dist < self.min_dist)

    if not self.clone or not self.clone.Parent then
        local was_arch = char.Archivable
        char.Archivable = true
        local clone = nil
        pcall(function() clone = char:Clone() end)
        char.Archivable = was_arch
        if clone then
            if fe_cosmetics then
                fe_cosmetics:update(clone)
            end
            make_forcefield_ghost(clone, cfg.backtrack_color, cfg.backtrack_trans)
            clone.Name = "LocalBacktrackGhost"
            clone.Parent = workspace
            self.clone = clone
        end
    end

    local clone = self.clone
    if clone then
        local offset = target_cframe * hrp.CFrame:Inverse()
        if self.map_char ~= char or self.map_clone ~= clone then
            self.map_char = char
            self.map_clone = clone
            local pairs_list = {}
            for _, cp in ipairs(clone:GetDescendants()) do
                if cp:IsA("BasePart") then
                    local orig = nil
                    if cp.Parent and cp.Parent:IsA("Accessory") then
                        local orig_acc = char:FindFirstChild(cp.Parent.Name)
                        if orig_acc then
                            orig = orig_acc:FindFirstChild(cp.Name)
                        end
                    else
                        orig = char:FindFirstChild(cp.Name, true)
                    end
                    if orig and orig:IsA("BasePart") then
                        pairs_list[#pairs_list + 1] = { clone_part = cp, orig_part = orig }
                    end
                end
            end
            self.part_pairs = pairs_list
        end

        local ghost_trans = is_overlapping and 1 or (cfg.backtrack_trans or 0.4)
        for _, pair in ipairs(self.part_pairs or {}) do
            local part = pair.clone_part
            local orig = pair.orig_part
            if part and part.Parent and orig and orig.Parent then
                part.CFrame = offset * orig.CFrame
                if part.Name ~= "HumanoidRootPart" then
                    local is_invisible = false
                    if cfg.fake_headless and part.Name == "Head" then
                        is_invisible = true
                    elseif cfg.fake_korblox and (part.Name == "RightLowerLeg" or part.Name == "RightFoot") then
                        is_invisible = true
                    end

                    if is_invisible then
                        if part.Transparency ~= 1 then part.Transparency = 1 end
                    else
                        if part.Material ~= Enum.Material.ForceField then part.Material = Enum.Material.ForceField end
                        if part.Color ~= cfg.backtrack_color then part.Color = cfg.backtrack_color end
                        if part.Transparency ~= ghost_trans then part.Transparency = ghost_trans end
                    end
                end
            end
        end
    end
end

local resolved_anim_cache = {
    ["754636298"] = "rbxassetid://10921152678",
    ["754637456"] = "rbxassetid://10921144709",
    ["754635032"] = "rbxassetid://10921148209",
    ["754637084"] = "rbxassetid://10921149743",
    ["754636589"] = "rbxassetid://10921148939",
    ["754639239"] = "rbxassetid://10921143404",
    ["754638471"] = "rbxassetid://10921150788",
    ["10921152678"] = "rbxassetid://10921152678",
    ["10921144709"] = "rbxassetid://10921144709",
    ["10921148209"] = "rbxassetid://10921148209",
    ["10921149743"] = "rbxassetid://10921149743",
    ["10921148939"] = "rbxassetid://10921148939",
    ["10921143404"] = "rbxassetid://10921143404",
    ["10921150788"] = "rbxassetid://10921150788",
    -- Popular Emote IDs pre-mapped
    ["10714340543"] = "rbxassetid://10714340277",
    ["10714340277"] = "rbxassetid://10714340277",
    ["3696757129"] = "rbxassetid://3696756852",
    ["3696756852"] = "rbxassetid://3696756852",
    ["3360686498"] = "rbxassetid://3360686498",
    ["3360689775"] = "rbxassetid://3360689775",
    ["507770677"] = "rbxassetid://507770677",
    ["507770818"] = "rbxassetid://507770818",
    ["507771019"] = "rbxassetid://507771019",
    ["507776720"] = "rbxassetid://507776720",
    ["507777268"] = "rbxassetid://507777268",
    ["3360692915"] = "rbxassetid://3360692915",
    ["3360690950"] = "rbxassetid://3360690950",
    ["3576686446"] = "rbxassetid://3576686446",
    ["4841405708"] = "rbxassetid://4841399916",
    ["4841399916"] = "rbxassetid://4841399916",
    ["3333136415"] = "rbxassetid://3333136005",
    ["3333136005"] = "rbxassetid://3333136005",
    ["4049037665"] = "rbxassetid://4049037412",
    ["4049037412"] = "rbxassetid://4049037412",
    ["3994184654"] = "rbxassetid://3994184402",
    ["3994184402"] = "rbxassetid://3994184402",
    ["3333331310"] = "rbxassetid://3333330954",
    ["3333330954"] = "rbxassetid://3333330954",
    ["3333432454"] = "rbxassetid://3333432135",
    ["3333432135"] = "rbxassetid://3333432135",
    ["4553805315"] = "rbxassetid://4553805068",
    ["4553805068"] = "rbxassetid://4553805068",
    ["4841397984"] = "rbxassetid://4841397726",
    ["4841397726"] = "rbxassetid://4841397726",
    ["4349242221"] = "rbxassetid://4349241968",
    ["4349241968"] = "rbxassetid://4349241968",
    ["3333387824"] = "rbxassetid://3333387532",
    ["3333387532"] = "rbxassetid://3333387532",
    ["4841402244"] = "rbxassetid://4841402008",
    ["4841402008"] = "rbxassetid://4841402008",
    ["4841399234"] = "rbxassetid://4841398977",
    ["4841398977"] = "rbxassetid://4841398977",
    ["5757758336"] = "rbxassetid://5757758112",
    ["5757758112"] = "rbxassetid://5757758112",
    ["3707834219"] = "rbxassetid://3707833973",
    ["3707833973"] = "rbxassetid://3707833973",
    ["5918726674"] = "rbxassetid://5918726456",
    ["5918726456"] = "rbxassetid://5918726456",
    ["4212455378"] = "rbxassetid://4212455122",
    ["4212455122"] = "rbxassetid://4212455122",
    ["4212458421"] = "rbxassetid://4212458156",
    ["4212458156"] = "rbxassetid://4212458156",
}
local resolving_in_flight = {}
local function resolve_playable_anim_id(rawId, callback)
    if not rawId then return "" end
    local s = tostring(rawId):gsub("^%s*(.-)%s*$", "%1")
    local numId = s:match("%d+")
    if not numId or numId == "0" then return s end
    if resolved_anim_cache[numId] then
        if callback then
            task.defer(callback, resolved_anim_cache[numId])
        end
        return resolved_anim_cache[numId]
    end

    local finalId = "rbxassetid://" .. numId

    if resolving_in_flight[numId] then
        if callback then
            table.insert(resolving_in_flight[numId], callback)
        end
        return finalId
    end
    resolving_in_flight[numId] = callback and { callback } or {}

    task.spawn(function()
        local resolved = nil
        pcall(function()
            if typeof(game.GetObjects) == "function" then
                local objs = game:GetObjects("rbxassetid://" .. numId)
                if objs and #objs > 0 then
                    for _, obj in ipairs(objs) do
                        if obj:IsA("Animation") and obj.AnimationId and #obj.AnimationId > 0 then
                            resolved = obj.AnimationId
                            break
                        end
                        local anim = obj:FindFirstChildWhichIsA("Animation", true)
                        if anim and anim.AnimationId and #anim.AnimationId > 0 then
                            resolved = anim.AnimationId
                            break
                        end
                    end
                    for _, obj in ipairs(objs) do
                        pcall(function() obj:Destroy() end)
                    end
                end
            end
        end)

        if not resolved then
            pcall(function()
                if typeof(game.HttpGet) == "function" then
                    local raw = game:HttpGet("https://assetdelivery.roblox.com/v1/asset/?id=" .. numId)
                    if raw and raw ~= "" then
                        local found = raw:match("asset/%?id=(%d+)") or raw:match("assetid://(%d+)")
                        if found and found ~= numId then
                            resolved = "rbxassetid://" .. found
                        end
                    end
                end
            end)
        end

        local res = resolved or finalId
        resolved_anim_cache[numId] = res
        local cbs = resolving_in_flight[numId]
        resolving_in_flight[numId] = nil
        if cbs then
            for _, cb in ipairs(cbs) do
                pcall(cb, res)
            end
        end
    end)

    return finalId
end

local function load_verified_track(animator, numId, is_valid, done)
    if not is_valid() then return end
    local num = tostring(numId):match("%d+")
    if not num or num == "0" then return end
    local directId = resolved_anim_cache[num] or ("rbxassetid://" .. num)
    local anim = Instance.new("Animation")
    anim.AnimationId = directId
    local ok, track = pcall(animator.LoadAnimation, animator, anim)
    if ok and track and is_valid() then
        done(track)
    elseif track then
        pcall(function() track:Destroy() end)
    end
end

local anim_manager = {
    original = {},
    has_saved = false,
    clean_defaults = {},
    active_slots = {},
    fallback_defaults = {
        idle1 = "http://www.roblox.com/asset/?id=507766388",
        idle2 = "http://www.roblox.com/asset/?id=507766666",
        walk = "http://www.roblox.com/asset/?id=540798782",
        run = "http://www.roblox.com/asset/?id=507767714",
        jump = "http://www.roblox.com/asset/?id=507765000",
        fall = "http://www.roblox.com/asset/?id=507767968",
        climb = "http://www.roblox.com/asset/?id=507765644",
        swim = "http://www.roblox.com/asset/?id=507784897",
        swimidle = "http://www.roblox.com/asset/?id=481825862"
    },
    fallback_defaults_r6 = {
        idle1 = "http://www.roblox.com/asset/?id=180435571",
        idle2 = "http://www.roblox.com/asset/?id=180435571",
        walk = "http://www.roblox.com/asset/?id=180426354",
        run = "http://www.roblox.com/asset/?id=180426354",
        jump = "http://www.roblox.com/asset/?id=125750702",
        fall = "http://www.roblox.com/asset/?id=180436148",
        climb = "http://www.roblox.com/asset/?id=180436334",
        swim = "http://www.roblox.com/asset/?id=507784897",
        swimidle = "http://www.roblox.com/asset/?id=481825862"
    },
    custom_ids = {},
    clean_id_set = {},
    packs = {
        { name = "Zombie", bundle_id = 63, category = "pack", idle = { 616158929, 616158929 }, walk = 616168032, run = 616163682, jump = 616161997, fall = 616157476, climb = 616156119, swim = 616165109 },
        { name = "Ninja", bundle_id = 67, category = "pack", idle = { 656117400, 656118341 }, walk = 656121766, run = 656118852, jump = 656117878, fall = 656115606, climb = 656114359, swim = 656120797 },
        { name = "Mage", bundle_id = 71, category = "pack", idle = { 10921144709, 10921144709 }, walk = 10921152678, run = 10921148209, jump = 10921149743, fall = 10921148939, climb = 10921143404, swim = 10921150788 },
        { name = "Levitation", bundle_id = 82, category = "pack", idle = { 616006778, 616008087 }, walk = 616013216, run = 616010382, jump = 616008987, fall = 616005863, climb = 616003713, swim = 616011509 },
        { name = "Vampire", bundle_id = 83, category = "pack", idle = { 1083445855, 1083450166 }, walk = 1083473930, run = 1083462077, jump = 1083455352, fall = 1083443587, climb = 1083439238, swim = 1083466989 },
        { name = "Superhero", bundle_id = 84, category = "pack", idle = { 616111295, 616111295 }, walk = 616122287, run = 616117076, jump = 616115533, fall = 616108001, climb = 616104706, swim = 616119139 },
        { name = "Cartoony", bundle_id = 73, category = "pack", idle = { 742637544, 742638445 }, walk = 742640026, run = 742638842, jump = 742637942, fall = 742636889, climb = 742636889, swim = 742639534 },
        { name = "Elder", bundle_id = 85, category = "pack", idle = { 845397899, 845400520 }, walk = 845403856, run = 845386501, jump = 845398858, fall = 845396048, climb = 845392038, swim = 845401742 },
        { name = "Toy", bundle_id = 69, category = "pack", idle = { 782841498, 782841498 }, walk = 782843345, run = 782842708, jump = 782847883, fall = 782846423, climb = 782843869, swim = 782847020 },
        { name = "Knight", bundle_id = 80, category = "pack", idle = { 657595757, 657568135 }, walk = 657552124, run = 657564596, jump = 657587419, fall = 657600338, climb = 658360781, swim = 657579017 },
        { name = "Robot", bundle_id = 65, category = "pack", idle = { 616088211, 616089559 }, walk = 616095330, run = 616091570, jump = 616090535, fall = 616087089, climb = 616086039, swim = 616092998 },
        { name = "Werewolf", bundle_id = 86, category = "pack", idle = { 1083195517, 1083195517 }, walk = 1083178339, run = 1083216690, jump = 1083218792, fall = 1083189019, climb = 1083182000, swim = 1083220790 },
        { name = "Astronaut", bundle_id = 77, category = "pack", idle = { 891621366, 891633237 }, walk = 891667138, run = 891636393, jump = 891627522, fall = 891617961, climb = 891609353, swim = 891653297 },
        { name = "Bubbly", bundle_id = 88, category = "pack", idle = { 910001910, 910009958 }, walk = 910034870, run = 910025107, jump = 910016857, fall = 910003837, climb = 909998797, swim = 910028158 },
        { name = "Sneaky", bundle_id = 95, category = "pack", idle = { 1132473842, 1132473842 }, walk = 1132510133, run = 1132494274, jump = 1132487136, fall = 1132469004, climb = 1132461372, swim = 1132500634 },
        { name = "Stylish", bundle_id = 79, category = "pack", idle = { 616136790, 616138447 }, walk = 616146177, run = 616140816, jump = 616139451, fall = 616134815, climb = 616133594, swim = 616143378 },
        { name = "Oldschool", bundle_id = 89, category = "pack", idle = { 5319828216, 5319831086 }, walk = 5319847204, run = 5319844329, jump = 5319841935, fall = 5319834732, climb = 5319816685, swim = 5319852613 },
        { name = "Popstar", bundle_id = 92, category = "pack", idle = { 1212900985, 1150842221 }, walk = 1212980338, run = 1212980348, jump = 1212954642, fall = 1212900995, climb = 1213044953, swim = 1212852603 },
        { name = "Princess", bundle_id = 94, category = "pack", idle = { 941003647, 941013098 }, walk = 941028902, run = 941015281, jump = 941008832, fall = 941000007, climb = 940996062, swim = 941018893 },
        { name = "Ghost", bundle_id = 623, category = "pack", idle = { 616006778, 616008087 }, walk = 616013216, run = 616010382, jump = 616008987, fall = 616005863, climb = 616003713, swim = 616011509 },
        { name = "Rthro", bundle_id = 373, category = "rthro", idle = { 2510196951, 2510197257 }, walk = 2510202577, run = 2510198475, jump = 2510197830, fall = 2510195892, climb = 2510192778, swim = 2510199791 },
        { name = "Bold", bundle_id = 374, category = "rthro", idle = { 16738333868, 16738334710 }, walk = 16738340646, run = 16738337225, jump = 16738336650, fall = 16738333171, climb = 16738332169, swim = 16738339158 },
        { name = "Energetic", bundle_id = 375, category = "rthro", idle = { 17172918855, 17173014241 }, walk = 11600249883, run = 11600211410, jump = 11600210487, fall = 11600206437, climb = 11600205519, swim = 11600212676 },
        { name = "Patrol", bundle_id = 96, category = "pack", idle = { 1149612882, 1150842221 }, walk = 1150967949, run = 1150967949, jump = 1150944216, fall = 1148863382, climb = 1148811837, swim = 1151204998 },
        { name = "Pirate", bundle_id = 75, category = "pack", idle = { 750781874, 750782770 }, walk = 750785693, run = 750783738, jump = 750782230, fall = 750780242, climb = 750779899, swim = 750784579 },
        { name = "Feisty", bundle_id = 93, category = "pack", idle = { 1212900985, 1150842221 }, walk = 1212980338, run = 1212980348, jump = 1212954642, fall = 1212900995, climb = 1213044953, swim = 1212852603 },
        { name = "Cowboy", bundle_id = 81, category = "pack", idle = { 1014390418, 1014398616 }, walk = 1014421541, run = 1014401683, jump = 1014394726, fall = 1014384571, climb = 1014380606, swim = 1014406523 },
        { name = "Confident", bundle_id = 376, category = "rthro", idle = { 1069977950, 1069987858 }, walk = 1070001516, run = 1070001516, jump = 1069984524, fall = 1069973677, climb = 1069946257, swim = 1070009914 },
        { name = "Cowgirl", bundle_id = 87, category = "pack", idle = { 1014390418, 1014398616 }, walk = 1014421541, run = 1014401683, jump = 1014394726, fall = 1014384571, climb = 1014380606, swim = 1014406523 },
        { name = "Fashion", bundle_id = 377, category = "rthro", idle = { 616136790, 616136790 }, walk = 616146177, run = 616140816, jump = 616139451, fall = 616134815, climb = 616133594, swim = 616143378 },
        { name = "Formal", bundle_id = 378, category = "rthro", idle = { 913367814, 913373430 }, walk = 913402848, run = 913376220, jump = 913370268, fall = 913365531, climb = 913362637, swim = 913384386 },
        { name = "Heroic", bundle_id = 379, category = "rthro", idle = { 616111295, 616111295 }, walk = 616122287, run = 616117076, jump = 616115533, fall = 616108001, climb = 616104706, swim = 616119139 },
        { name = "Default", bundle_id = 0, category = "classic", idle = {}, walk = 0, run = 0, jump = 0, fall = 0, climb = 0, swim = 0 }
    }
}

anim_manager.pack_names = {}
anim_manager.custom_ids = {}
local default_user_thumb = "rbxthumb://type=Avatar&id=" .. tostring(local_player and local_player.UserId or 1) .. "&w=150&h=150"
for _, p in ipairs(anim_manager.packs) do
    table.insert(anim_manager.pack_names, p.name)
    p.thumbnail = default_user_thumb
    if p.name ~= "Default" then
        if p.idle then
            for _, id in ipairs(p.idle) do
                local num = tostring(id):match("%d+")
                if num and num ~= "0" then
                    resolved_anim_cache[num] = "rbxassetid://" .. num
                    anim_manager.custom_ids[num] = true
                end
            end
        end
        for _, key in ipairs({ "walk", "run", "jump", "fall", "climb", "swim" }) do
            local id = p[key]
            if id then
                local num = tostring(id):match("%d+")
                if num and num ~= "0" then
                    resolved_anim_cache[num] = "rbxassetid://" .. num
                    anim_manager.custom_ids[num] = true
                end
            end
        end
    end
end

function anim_manager:save_original(animate)
    if not animate then return end
    local char = animate.Parent
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local is_r6 = hum and (hum.RigType == Enum.HumanoidRigType.R6)
    local fallbacks = is_r6 and self.fallback_defaults_r6 or self.fallback_defaults

    local function get_id(folder, child)
        local f = animate:FindFirstChild(folder)
        if not f then return nil end
        local c = f:FindFirstChild(child)
        if not c then
            for _, ch in ipairs(f:GetChildren()) do
                if ch:IsA("Animation") then
                    c = ch
                    break
                end
            end
        end
        return (c and c:IsA("Animation")) and c.AnimationId or nil
    end

    local captured = {
        idle1 = get_id("idle", "Animation1"),
        idle2 = get_id("idle", "Animation2"),
        walk = get_id("walk", "WalkAnim"),
        run = get_id("run", "RunAnim"),
        jump = get_id("jump", "JumpAnim"),
        fall = get_id("fall", "FallAnim"),
        climb = get_id("climb", "ClimbAnim"),
        swim = get_id("swim", "Swim"),
        swimidle = get_id("swimidle", "SwimIdle")
    }

    if not self.has_saved then
        self.clean_defaults = {}
        self.clean_id_set = {}
        for k, fallback_val in pairs(fallbacks) do
            local cap = captured[k]
            local num = cap and tostring(cap):match("%d+")
            local is_custom = num and self.custom_ids[num]
            local valid_id = (cap and cap ~= "" and not is_custom) and cap or fallback_val
            self.clean_defaults[k] = valid_id
            local valid_num = tostring(valid_id):match("%d+")
            if valid_num then self.clean_id_set[valid_num] = true end
        end
        for _, fb in pairs(fallbacks) do
            local fb_num = tostring(fb):match("%d+")
            if fb_num then self.clean_id_set[fb_num] = true end
        end
        self.original = table.clone(self.clean_defaults)
        self.has_saved = true
    end
end

function anim_manager:register_pack(pack)
    if not pack or not pack.name then return end
    if pack.name ~= "Default" then
        if pack.idle then
            for _, id in ipairs(pack.idle) do
                local num = tostring(id):match("%d+")
                if num and num ~= "0" then self.custom_ids[num] = true end
            end
        end
        for _, key in ipairs({ "walk", "run", "jump", "fall", "climb", "swim" }) do
            local id = pack[key]
            if id then
                local num = tostring(id):match("%d+")
                if num and num ~= "0" then self.custom_ids[num] = true end
            end
        end
    end
    for i, p in ipairs(self.packs) do
        if p.name == pack.name then
            self.packs[i] = pack
            return
        end
    end
    table.insert(self.packs, pack)
    table.insert(self.pack_names, pack.name)
end

function anim_manager:apply(pack_name, target_slot, is_reapply, skip_track_stop)
    local char = local_player.Character
    if not char then return end
    local animate = char:FindFirstChild("Animate")
    local hum = char:FindFirstChildOfClass("Humanoid")
    local animator = hum and (hum:FindFirstChildOfClass("Animator") or hum)

    target_slot = string.lower(target_slot or "all")

    if pack_name == "Default" then
        self:revert(target_slot, skip_track_stop)
        return
    end

    local pack = nil
    if typeof(pack_name) == "table" then
        pack = pack_name
        self:register_pack(pack)
    else
        for _, p in ipairs(self.packs) do
            if p.name == pack_name then pack = p; break end
        end
        if not pack and tostring(pack_name):match("%d+") then
            local numId = tonumber(tostring(pack_name):match("%d+"))
            pack = { name = pack_name, idle = { numId }, walk = numId, run = numId, jump = numId, fall = numId, climb = numId, swim = numId }
            self:register_pack(pack)
        end
    end
    if not pack then return end
    cfg.custom_anim_pack = pack.name

    if not is_reapply then
        if target_slot == "all" then
            for _, s in ipairs({ "idle", "walk", "run", "jump", "fall", "climb", "swim" }) do
                self.active_slots[s] = pack.name
                cfg.active_anim_slots[s] = pack.name
            end
        else
            self.active_slots[target_slot] = pack.name
            cfg.active_anim_slots[target_slot] = pack.name
        end
    end

    if animate then
        self:save_original(animate)

        local function set_anim_id(folder_name, child_name, id)
            if not id or id == 0 then return end
            local f = animate:FindFirstChild(folder_name)
            if not f then
                f = Instance.new("StringValue")
                f.Name = folder_name
                f.Parent = animate
            end
            local num = tostring(id):match("%d+")
            local playable = resolve_playable_anim_id(num)
            local a = f:FindFirstChild(child_name)
            if not a then
                for _, c in ipairs(f:GetChildren()) do
                    if c:IsA("Animation") then
                        a = c
                        break
                    end
                end
            end
            if not a then
                a = Instance.new("Animation")
                a.Name = child_name
                a.Parent = f
            end
            if a.AnimationId ~= playable then
                a.AnimationId = playable
            end
            for _, c in ipairs(f:GetChildren()) do
                if c:IsA("Animation") and c ~= a and folder_name ~= "idle" then
                    if c.AnimationId ~= playable then
                        c.AnimationId = playable
                    end
                end
            end
        end

        local idle1 = pack.idle and pack.idle[1]
        local idle2 = pack.idle and (pack.idle[2] or pack.idle[1])
        local generic_id = idle1 or pack.walk or pack.run or pack.jump

        if target_slot == "all" or target_slot == "idle" then
            local id1 = idle1 or generic_id
            local id2 = idle2 or generic_id
            if id1 then set_anim_id("idle", "Animation1", id1) end
            if id2 then set_anim_id("idle", "Animation2", id2) end
        end
        if target_slot == "all" or target_slot == "walk" then
            local wid = pack.walk or pack.run or generic_id
            if wid then set_anim_id("walk", "WalkAnim", wid) end
            if target_slot == "walk" and (self.active_slots["run"] == nil or self.active_slots["run"] == "Default") then
                local rid = pack.run or wid
                if rid then set_anim_id("run", "RunAnim", rid) end
            end
        end
        if target_slot == "all" or target_slot == "run" then
            local rid = pack.run or pack.walk or generic_id
            if rid then set_anim_id("run", "RunAnim", rid) end
            if target_slot == "run" and (self.active_slots["walk"] == nil or self.active_slots["walk"] == "Default") then
                local wid = pack.walk or rid
                if wid then set_anim_id("walk", "WalkAnim", wid) end
            end
        end
        if target_slot == "all" or target_slot == "jump" then
            local jid = pack.jump or generic_id
            if jid then set_anim_id("jump", "JumpAnim", jid) end
        end
        if target_slot == "all" or target_slot == "fall" then
            local fid = pack.fall or generic_id
            if fid then set_anim_id("fall", "FallAnim", fid) end
        end
        if target_slot == "all" or target_slot == "climb" then
            local cid = pack.climb or generic_id
            if cid then set_anim_id("climb", "ClimbAnim", cid) end
        end
        if target_slot == "all" or target_slot == "swim" then
            local sid = pack.swim or generic_id
            if sid then
                set_anim_id("swim", "Swim", sid)
                set_anim_id("swimidle", "SwimIdle", sid)
            end
        end
    end

    if not skip_track_stop and (hum or animator) then
        local obj = animator or hum
        for _, track in ipairs(obj:GetPlayingAnimationTracks()) do
            local animObj = track.Animation
            local pName = animObj and animObj.Parent and animObj.Parent.Name:lower()
            local aName = (animObj and animObj.Name:lower()) or ""
            local tName = track.Name:lower()
            local should_stop = false

            if target_slot == "all" then
                should_stop = true
            elseif target_slot == "idle" then
                should_stop = (pName == "idle") or tName:find("idle") or aName:find("idle") or tName:find("animation1") or tName:find("animation2")
            elseif target_slot == "walk" or target_slot == "run" then
                should_stop = (pName == "walk" or pName == "run") or tName:find("walk") or tName:find("run") or aName:find("walk") or aName:find("run")
            elseif target_slot == "jump" then
                should_stop = (pName == "jump") or tName:find("jump") or aName:find("jump")
            elseif target_slot == "fall" then
                should_stop = (pName == "fall") or tName:find("fall") or aName:find("fall")
            elseif target_slot == "climb" then
                should_stop = (pName == "climb") or tName:find("climb") or aName:find("climb")
            elseif target_slot == "swim" then
                should_stop = (pName == "swim" or pName == "swimidle") or tName:find("swim") or aName:find("swim")
            end

            if should_stop then
                pcall(function() track:Stop(0.1) end)
            end
        end
    end

    local gets = (typeof(getsenv) == "function") and animate and getsenv(animate)
    if gets then
        if gets.configureAnimationSet then
            if target_slot == "all" then
                for _, s in ipairs({ "idle", "walk", "run", "jump", "fall", "climb", "swim", "swimidle" }) do
                    pcall(gets.configureAnimationSet, s, {})
                end
            else
                pcall(gets.configureAnimationSet, target_slot, {})
                if target_slot == "walk" or target_slot == "run" then
                    pcall(gets.configureAnimationSet, "walk", {})
                    pcall(gets.configureAnimationSet, "run", {})
                elseif target_slot == "swim" then
                    pcall(gets.configureAnimationSet, "swim", {})
                    pcall(gets.configureAnimationSet, "swimidle", {})
                end
            end
        end
        if not skip_track_stop then
            if gets.stopAllAnimations then
                pcall(gets.stopAllAnimations)
            end
            local spd = (hum and hum.MoveDirection.Magnitude * (hum.WalkSpeed or 16)) or 0
            if gets.onRunning then
                pcall(gets.onRunning, spd)
            elseif gets.playAnimation and hum then
                pcall(gets.playAnimation, spd > 0.75 and "run" or "idle", 0.1, hum)
            end
        end
    end
end

function anim_manager:revert(target_slot, skip_track_stop)
    local char = local_player.Character
    local animate = char and char:FindFirstChild("Animate")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local animator = hum and (hum:FindFirstChildOfClass("Animator") or hum)
    if not animate then return end

    target_slot = string.lower(target_slot or "all")

    if target_slot == "all" then
        for _, s in ipairs({ "idle", "walk", "run", "jump", "fall", "climb", "swim" }) do
            self.active_slots[s] = "Default"
            cfg.active_anim_slots[s] = "Default"
        end
        cfg.custom_anim_pack = "Default"
    else
        self.active_slots[target_slot] = "Default"
        cfg.active_anim_slots[target_slot] = "Default"
    end

    local is_r6 = hum and (hum.RigType == Enum.HumanoidRigType.R6)
    local fallbacks = is_r6 and self.fallback_defaults_r6 or self.fallback_defaults

    local function restore_id(folder_name, child_name, default_key)
        local saved_id = (self.clean_defaults and self.clean_defaults[default_key]) or (fallbacks and fallbacks[default_key])
        if not saved_id or saved_id == "" then return end
        local f = animate:FindFirstChild(folder_name)
        if f then
            local c = f:FindFirstChild(child_name)
            if not c then
                for _, child in ipairs(f:GetChildren()) do
                    if child:IsA("Animation") then
                        c = child
                        break
                    end
                end
            end
            if not c then
                c = Instance.new("Animation")
                c.Name = child_name
                c.Parent = f
            end
            if c:IsA("Animation") and c.AnimationId ~= saved_id then
                c.AnimationId = saved_id
            end
            for _, child in ipairs(f:GetChildren()) do
                if child:IsA("Animation") and child ~= c and folder_name ~= "idle" then
                    if child.AnimationId ~= saved_id then
                        child.AnimationId = saved_id
                    end
                end
            end
        end
    end

    if target_slot == "all" or target_slot == "idle" then
        restore_id("idle", "Animation1", "idle1")
        restore_id("idle", "Animation2", "idle2")
    end
    if target_slot == "all" or target_slot == "walk" then
        restore_id("walk", "WalkAnim", "walk")
        if target_slot == "walk" and (self.active_slots["run"] == nil or self.active_slots["run"] == "Default") then
            restore_id("run", "RunAnim", "run")
        end
    end
    if target_slot == "all" or target_slot == "run" then
        restore_id("run", "RunAnim", "run")
        if target_slot == "run" and (self.active_slots["walk"] == nil or self.active_slots["walk"] == "Default") then
            restore_id("walk", "WalkAnim", "walk")
        end
    end
    if target_slot == "all" or target_slot == "jump" then
        restore_id("jump", "JumpAnim", "jump")
    end
    if target_slot == "all" or target_slot == "fall" then
        restore_id("fall", "FallAnim", "fall")
    end
    if target_slot == "all" or target_slot == "climb" then
        restore_id("climb", "ClimbAnim", "climb")
    end
    if target_slot == "all" or target_slot == "swim" then
        restore_id("swim", "Swim", "swim")
        restore_id("swimidle", "SwimIdle", "swimidle")
    end

    if not skip_track_stop and (hum or animator) then
        local obj = animator or hum
        for _, track in ipairs(obj:GetPlayingAnimationTracks()) do
            local animObj = track.Animation
            local pName = animObj and animObj.Parent and animObj.Parent.Name:lower()
            local aName = (animObj and animObj.Name:lower()) or ""
            local tName = track.Name:lower()
            local should_stop = false

            if target_slot == "all" then
                should_stop = true
            elseif target_slot == "idle" then
                should_stop = (pName == "idle") or tName:find("idle") or aName:find("idle") or tName:find("animation1") or tName:find("animation2")
            elseif target_slot == "walk" or target_slot == "run" then
                should_stop = (pName == "walk" or pName == "run") or tName:find("walk") or tName:find("run") or aName:find("walk") or aName:find("run")
            elseif target_slot == "jump" then
                should_stop = (pName == "jump") or tName:find("jump") or aName:find("jump")
            elseif target_slot == "fall" then
                should_stop = (pName == "fall") or tName:find("fall") or aName:find("fall")
            elseif target_slot == "climb" then
                should_stop = (pName == "climb") or tName:find("climb") or aName:find("climb")
            elseif target_slot == "swim" then
                should_stop = (pName == "swim" or pName == "swimidle") or tName:find("swim") or aName:find("swim")
            end

            if should_stop then
                pcall(function() track:Stop(0.1) end)
            end
        end
    end

    local gets = (typeof(getsenv) == "function") and getsenv(animate)
    if gets then
        if gets.configureAnimationSet then
            if target_slot == "all" then
                for _, s in ipairs({ "idle", "walk", "run", "jump", "fall", "climb", "swim", "swimidle" }) do
                    pcall(gets.configureAnimationSet, s, {})
                end
            else
                pcall(gets.configureAnimationSet, target_slot, {})
                if target_slot == "walk" or target_slot == "run" then
                    pcall(gets.configureAnimationSet, "walk", {})
                    pcall(gets.configureAnimationSet, "run", {})
                elseif target_slot == "swim" then
                    pcall(gets.configureAnimationSet, "swim", {})
                    pcall(gets.configureAnimationSet, "swimidle", {})
                end
            end
        end
        if not skip_track_stop then
            if gets.stopAllAnimations then
                pcall(gets.stopAllAnimations)
            end
            local spd = (hum and hum.MoveDirection.Magnitude * (hum.WalkSpeed or 16)) or 0
            if gets.onRunning then
                pcall(gets.onRunning, spd)
            elseif gets.playAnimation and hum then
                pcall(gets.playAnimation, spd > 0.75 and "run" or "idle", 0.1, hum)
            end
        end
    end
end

function anim_manager:reapply_all(skip_track_stop)
    local char = local_player.Character
    if not char then return end
    local animate = char:FindFirstChild("Animate")
    if not animate then return end

    if not cfg.custom_anims_enabled then
        self:revert("all", skip_track_stop)
        return
    end

    self:save_original(animate)

    local count = 0
    for slot, pack in pairs(self.active_slots) do
        if pack and pack ~= "Default" then
            count = count + 1
            self:apply(pack, slot, true, true)
        else
            self:revert(slot, true)
        end
    end

    if count == 0 and cfg.custom_anim_pack and cfg.custom_anim_pack ~= "Default" then
        self:apply(cfg.custom_anim_pack, cfg.custom_anim_slot or "all", true, true)
    end

    if not skip_track_stop then
        local hum = char:FindFirstChildOfClass("Humanoid")
        local animator = hum and (hum:FindFirstChildOfClass("Animator") or hum)
        if animator then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                pcall(function() track:Stop(0.1) end)
            end
        end
        local gets = (typeof(getsenv) == "function") and getsenv(animate)
        if gets then
            if gets.stopAllAnimations then pcall(gets.stopAllAnimations) end
            local spd = (hum and hum.MoveDirection.Magnitude * (hum.WalkSpeed or 16)) or 0
            if gets.onRunning then pcall(gets.onRunning, spd) end
        end
    end
end

local function resolve_float_parent()
    if library and library.Floats and library.Floats.Parent then return library.Floats end
    local mf = (window and window.MainFrame) or (library and library.MainFrame)
    if mf and mf.Parent then return mf.Parent end
    if library and library.ScreenGui and library.ScreenGui.Parent then return library.ScreenGui end
    if getgenv and getgenv().__v_ctx_gui and getgenv().__v_ctx_gui.Parent then
        local fl = getgenv().__v_ctx_gui:FindFirstChild("Floats", true)
        if fl then return fl end
        return getgenv().__v_ctx_gui
    end
    if getgenv and getgenv()._VantageActiveGui and getgenv()._VantageActiveGui.Parent then return getgenv()._VantageActiveGui end
    local parent = nil
    if typeof(gethui) == "function" then
        pcall(function() parent = gethui() end)
    end
    if not parent then
        local lp = local_player or (players and players.LocalPlayer)
        pcall(function() parent = lp and lp:FindFirstChildOfClass("PlayerGui") end)
    end
    if parent then
        local floatGui = parent:FindFirstChild("CoreFloatProvider") or parent:FindFirstChild("VantageFloatGui")
        if not floatGui then
            floatGui = Instance.new("ScreenGui")
            floatGui.Name = "CoreFloatProvider"
            floatGui:SetAttribute("__v_core", true)
            floatGui.ResetOnSpawn = false
            floatGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            floatGui.IgnoreGuiInset = true
            floatGui.DisplayOrder = 999
            floatGui.Parent = parent
        else
            floatGui.IgnoreGuiInset = true
        end
        return floatGui
    end
    return nil
end

local function get_docked_position(winWidth, winHeight, targetParent)
    local vpSize = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1920, 1080)
    local mf = (window and window.MainFrame) or (library and library.MainFrame) or (library and library.ScreenGui and library.ScreenGui:FindFirstChild("Main", true))

    local mfWidth = 740
    local mfHeight = 530
    if mf then
        if mf.AbsoluteSize and mf.AbsoluteSize.X > 50 then
            mfWidth = mf.AbsoluteSize.X
            mfHeight = mf.AbsoluteSize.Y
        elseif mf.Size and mf.Size.X.Offset > 50 then
            mfWidth = mf.Size.X.Offset
            mfHeight = mf.Size.Y.Offset
        end
    end

    local sameSpace = false
    if mf and targetParent then
        local mfGui = mf:FindFirstAncestorWhichIsA("ScreenGui") or mf.Parent
        local targetGui = (targetParent:IsA("ScreenGui") and targetParent) or targetParent:FindFirstAncestorWhichIsA("ScreenGui") or targetParent
        if mfGui and targetGui and mfGui == targetGui then
            sameSpace = true
        end
    end

    if mf and mf.Position and (sameSpace or not targetParent) then
        return UDim2.new(
            mf.Position.X.Scale,
            mf.Position.X.Offset + mfWidth + 12,
            mf.Position.Y.Scale,
            mf.Position.Y.Offset
        )
    end

    local targetScreenX = math.floor((vpSize.X - mfWidth) / 2) + mfWidth + 12
    local targetScreenY = math.floor((vpSize.Y - mfHeight) / 2)

    if mf then
        if mf.AbsolutePosition and (mf.AbsolutePosition.X > 0 or mf.AbsolutePosition.Y > 0) then
            targetScreenX = mf.AbsolutePosition.X + mfWidth + 12
            targetScreenY = mf.AbsolutePosition.Y
        elseif mf.Position then
            targetScreenX = math.floor(mf.Position.X.Scale * vpSize.X + mf.Position.X.Offset) + mfWidth + 12
            targetScreenY = math.floor(mf.Position.Y.Scale * vpSize.Y + mf.Position.Y.Offset)
        end
    end

    if targetParent then
        pcall(function()
            if targetParent:IsA("GuiObject") then
                targetScreenX = targetScreenX - targetParent.AbsolutePosition.X
                targetScreenY = targetScreenY - targetParent.AbsolutePosition.Y
            elseif targetParent:IsA("ScreenGui") and not targetParent.IgnoreGuiInset then
                local gs = cloneref and cloneref(game:GetService("GuiService")) or game:GetService("GuiService")
                local inset = gs:GetGuiInset()
                targetScreenY = targetScreenY - inset.Y
            end
        end)
    end

    return UDim2.fromOffset(math.floor(targetScreenX), math.floor(targetScreenY))
end

local function get_theme_color(name, fallback)
    if library and library.Scheme and library.Scheme[name] then
        return library.Scheme[name]
    end
    local defaults = {
        BackgroundColor = Color3.fromRGB(18, 18, 22),
        MainColor = Color3.fromRGB(24, 24, 30),
        AccentColor = Color3.fromRGB(180, 100, 255),
        OutlineColor = Color3.fromRGB(45, 45, 55),
        FontColor = Color3.fromRGB(240, 240, 245),
    }
    return defaults[name] or fallback or Color3.fromRGB(255, 255, 255)
end

local function get_theme_font()
    if library and library.Font then return library.Font end
    return Enum.Font.Code
end

local function make_ui_draggable(frame, dragHandle)
    if library and library.MakeDraggable then
        pcall(function() library:MakeDraggable(frame, dragHandle, true) end)
        return
    end
    local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    user_input_service.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

local master_clean_dummy_template = nil

local function clean_dummy_instance(dummy)
    if not dummy then return end
    pcall(function()
        dummy.Name = "PreviewAvatar"
        for _, desc in ipairs(dummy:GetDescendants()) do
            if desc:IsA("LuaSourceContainer") or desc:IsA("Sound") or desc:IsA("ParticleEmitter")
                or desc:IsA("Beam") or desc:IsA("Trail") or desc:IsA("Tool")
                or desc:IsA("Highlight") or desc:IsA("BillboardGui") or desc:IsA("SurfaceGui") then
                pcall(function() desc:Destroy() end)
            elseif desc:IsA("BasePart") then
                desc.CanCollide = false
                desc.CanTouch = false
                desc.CanQuery = false
                desc.Anchored = (desc.Name == "HumanoidRootPart")
                if desc.Material == Enum.Material.ForceField then
                    desc.Material = Enum.Material.SmoothPlastic
                end
                if desc.Name ~= "HumanoidRootPart" and desc.Transparency > 0.8 then
                    desc.Transparency = 0
                end
            end
        end

        local hum = dummy:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
            local animator = hum:FindFirstChildOfClass("Animator")
            if not animator then
                animator = Instance.new("Animator", hum)
            end
        end

        local hrp = dummy:FindFirstChild("HumanoidRootPart") or dummy:FindFirstChildWhichIsA("BasePart")
        if hrp then
            dummy.PrimaryPart = hrp
        end
    end)
end

local function build_fallback_dummy()
    local dummy = Instance.new("Model")
    dummy.Name = "PreviewAvatar"
    dummy:SetAttribute("__is_fallback", true)
    local hum = Instance.new("Humanoid")
    hum.RigType = Enum.HumanoidRigType.R15
    hum.Parent = dummy

    local hrp = Instance.new("Part")
    hrp.Name = "HumanoidRootPart"
    hrp.Size = Vector3.new(2, 2, 1)
    hrp.Transparency = 1
    hrp.CanCollide = false
    hrp.Anchored = true
    hrp.Parent = dummy
    dummy.PrimaryPart = hrp

    local r15_parts = {
        Head = { size = Vector3.new(1.2, 1.2, 1.2), pos = Vector3.new(0, 1.5, 0) },
        UpperTorso = { size = Vector3.new(1.6, 1.1, 0.8), pos = Vector3.new(0, 0.5, 0) },
        LowerTorso = { size = Vector3.new(1.4, 0.6, 0.7), pos = Vector3.new(0, -0.3, 0) },
        LeftUpperArm = { size = Vector3.new(0.7, 0.9, 0.7), pos = Vector3.new(-1.2, 0.6, 0) },
        LeftLowerArm = { size = Vector3.new(0.6, 0.8, 0.6), pos = Vector3.new(-1.2, -0.2, 0) },
        LeftHand = { size = Vector3.new(0.6, 0.5, 0.6), pos = Vector3.new(-1.2, -0.8, 0) },
        RightUpperArm = { size = Vector3.new(0.7, 0.9, 0.7), pos = Vector3.new(1.2, 0.6, 0) },
        RightLowerArm = { size = Vector3.new(0.6, 0.8, 0.6), pos = Vector3.new(1.2, -0.2, 0) },
        RightHand = { size = Vector3.new(0.6, 0.5, 0.6), pos = Vector3.new(1.2, -0.8, 0) },
        LeftUpperLeg = { size = Vector3.new(0.7, 1.0, 0.7), pos = Vector3.new(-0.4, -1.0, 0) },
        LeftLowerLeg = { size = Vector3.new(0.6, 0.9, 0.6), pos = Vector3.new(-0.4, -1.9, 0) },
        LeftFoot = { size = Vector3.new(0.6, 0.5, 0.7), pos = Vector3.new(-0.4, -2.5, 0.1) },
        RightUpperLeg = { size = Vector3.new(0.7, 1.0, 0.7), pos = Vector3.new(0.4, -1.0, 0) },
        RightLowerLeg = { size = Vector3.new(0.6, 0.9, 0.6), pos = Vector3.new(0.4, -1.9, 0) },
        RightFoot = { size = Vector3.new(0.6, 0.5, 0.7), pos = Vector3.new(0.4, -2.5, 0.1) },
    }
    for pName, pData in pairs(r15_parts) do
        local p = Instance.new("Part")
        p.Name = pName
        p.Size = pData.size
        p.CFrame = CFrame.new(pData.pos)
        p.Color = Color3.fromRGB(180, 180, 190)
        p.Material = Enum.Material.SmoothPlastic
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.Anchored = false
        p.Parent = dummy
    end

    local function make_motor(name, p0, p1, c0, c1)
        local m = Instance.new("Motor6D")
        m.Name = name
        m.Part0 = dummy:FindFirstChild(p0)
        m.Part1 = dummy:FindFirstChild(p1)
        m.C0 = c0 or CFrame.new()
        m.C1 = c1 or CFrame.new()
        m.Parent = m.Part0 or dummy
    end
    make_motor("Root", "HumanoidRootPart", "LowerTorso", CFrame.new(0, 0, 0), CFrame.new(0, 0.3, 0))
    make_motor("Waist", "LowerTorso", "UpperTorso", CFrame.new(0, 0.3, 0), CFrame.new(0, -0.5, 0))
    make_motor("Neck", "UpperTorso", "Head", CFrame.new(0, 0.6, 0), CFrame.new(0, -0.6, 0))
    make_motor("LeftShoulder", "UpperTorso", "LeftUpperArm", CFrame.new(-1.0, 0.3, 0), CFrame.new(0.2, 0.4, 0))
    make_motor("LeftElbow", "LeftUpperArm", "LeftLowerArm", CFrame.new(0, -0.4, 0), CFrame.new(0, 0.4, 0))
    make_motor("LeftWrist", "LeftLowerArm", "LeftHand", CFrame.new(0, -0.4, 0), CFrame.new(0, 0.2, 0))
    make_motor("RightShoulder", "UpperTorso", "RightUpperArm", CFrame.new(1.0, 0.3, 0), CFrame.new(-0.2, 0.4, 0))
    make_motor("RightElbow", "RightUpperArm", "RightLowerArm", CFrame.new(0, -0.4, 0), CFrame.new(0, 0.4, 0))
    make_motor("RightWrist", "RightLowerArm", "RightHand", CFrame.new(0, -0.4, 0), CFrame.new(0, 0.2, 0))
    make_motor("LeftHip", "LowerTorso", "LeftUpperLeg", CFrame.new(-0.4, -0.3, 0), CFrame.new(0, 0.5, 0))
    make_motor("LeftKnee", "LeftUpperLeg", "LeftLowerLeg", CFrame.new(0, -0.5, 0), CFrame.new(0, 0.45, 0))
    make_motor("LeftAnkle", "LeftLowerLeg", "LeftFoot", CFrame.new(0, -0.45, 0), CFrame.new(0, 0.25, 0))
    make_motor("RightHip", "LowerTorso", "RightUpperLeg", CFrame.new(0.4, -0.3, 0), CFrame.new(0, 0.5, 0))
    make_motor("RightKnee", "RightUpperLeg", "RightLowerLeg", CFrame.new(0, -0.5, 0), CFrame.new(0, 0.45, 0))
    make_motor("RightAnkle", "RightLowerLeg", "RightFoot", CFrame.new(0, -0.45, 0), CFrame.new(0, 0.25, 0))

    clean_dummy_instance(dummy)
    return dummy
end

local function build_master_dummy_template(force_refresh)
    local char = local_player and local_player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local char_ready = (char and hum and #char:GetChildren() > 0)

    if not force_refresh and master_clean_dummy_template and master_clean_dummy_template:FindFirstChildOfClass("Humanoid") then
        if not master_clean_dummy_template:GetAttribute("__is_fallback") then
            return master_clean_dummy_template
        end
        if not char_ready then
            return master_clean_dummy_template
        end
        pcall(function() master_clean_dummy_template:Destroy() end)
        master_clean_dummy_template = nil
    end

    local dummy = nil

    if hum and players and typeof(players.CreateHumanoidModelFromDescription) == "function" then
        pcall(function()
            local desc = hum:GetAppliedDescription()
            if desc then
                dummy = players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
            end
        end)
    end

    if (not dummy or not dummy:FindFirstChildOfClass("Humanoid")) and local_player and local_player.UserId and local_player.UserId > 0 and players and typeof(players.GetHumanoidDescriptionFromUserId) == "function" and typeof(players.CreateHumanoidModelFromDescription) == "function" then
        pcall(function()
            local desc = players:GetHumanoidDescriptionFromUserId(local_player.UserId)
            if desc then
                dummy = players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
            end
        end)
    end

    if (not dummy or not dummy:FindFirstChildOfClass("Humanoid")) and char_ready then
        local oldArch = {}
        for _, d in ipairs(char:GetDescendants()) do
            oldArch[d] = d.Archivable
            d.Archivable = true
        end
        local wasArch = char.Archivable
        char.Archivable = true
        pcall(function() dummy = char:Clone() end)
        char.Archivable = wasArch
        for d, s in pairs(oldArch) do
            if d and d.Parent then d.Archivable = s end
        end
    end

    if not dummy or not dummy:FindFirstChildOfClass("Humanoid") then
        if dummy then pcall(function() dummy:Destroy() end) end
        dummy = build_fallback_dummy()
    else
        dummy:SetAttribute("__is_fallback", nil)
        clean_dummy_instance(dummy)
    end

    dummy.Archivable = true
    master_clean_dummy_template = dummy
    return master_clean_dummy_template
end

if local_player then
    local function on_character_refresh()
        if master_clean_dummy_template then
            pcall(function() master_clean_dummy_template:Destroy() end)
            master_clean_dummy_template = nil
        end
    end
    pcall(function() local_player.CharacterAdded:Connect(on_character_refresh) end)
    pcall(function() local_player.CharacterAppearanceLoaded:Connect(on_character_refresh) end)
end

local function create_clean_dummy(angle)
    angle = angle or math.rad(165)
    local template = build_master_dummy_template()
    if not template then return nil end
    local ok, clone = pcall(template.Clone, template)
    if not ok or not clone then return nil end
    clone.Name = "PreviewAvatar"
    if fe_cosmetics then
        pcall(function() fe_cosmetics:update(clone) end)
    end
    pcall(function()
        local hrp = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart
        if hrp then
            clone.PrimaryPart = hrp
            clone:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, angle, 0))
        end
    end)
    return clone
end

local default_emotes_list = {}

local emote_manager = {
    active_track = nil,
    move_conn = nil,
    current_emote = nil,
    last_id = nil,
    last_name = nil,
    is_playing = false,
    looped = true,
    emotes = default_emotes_list
}

function emote_manager:setup_movement_listener(hum)
    if self.move_conn then
        pcall(function() self.move_conn:Disconnect() end)
        self.move_conn = nil
    end
    if not hum or self.looped then return end

    local function check_move()
        if not self.is_playing or self.looped then return end
        if hum and hum.MoveDirection.Magnitude > 0.05 then
            self:stop()
        end
    end

    local conns = {}
    local ok1, c1 = pcall(function()
        return hum:GetPropertyChangedSignal("MoveDirection"):Connect(check_move)
    end)
    if ok1 and c1 then table.insert(conns, c1) end

    local ok2, c2 = pcall(function()
        return hum.Running:Connect(function(speed)
            if speed > 0.5 then check_move() end
        end)
    end)
    if ok2 and c2 then table.insert(conns, c2) end

    self.move_conn = {
        Disconnect = function()
            for _, c in ipairs(conns) do
                pcall(function() c:Disconnect() end)
            end
        end
    }
end

function emote_manager:register_emote(emote)
    if not emote or not emote.name then return end
    for i, e in ipairs(self.emotes) do
        if e.name == emote.name or (e.id and emote.id and tostring(e.id) == tostring(emote.id)) then
            self.emotes[i] = emote
            return
        end
    end
    table.insert(self.emotes, emote)
end

function emote_manager:set_looped(val)
    self.looped = (val == true)
    if self.active_track then
        pcall(function()
            self.active_track.Looped = self.looped
            if self.looped and self.is_playing and not self.active_track.IsPlaying then
                self.active_track:Play(0.05)
            end
        end)
    end
    local char = local_player and local_player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not self.looped then
        if hum and hum.MoveDirection.Magnitude > 0.05 then
            self:stop()
        elseif hum and self.is_playing then
            self:setup_movement_listener(hum)
        end
    else
        if self.move_conn then
            pcall(function() self.move_conn:Disconnect() end)
            self.move_conn = nil
        end
    end
end

function emote_manager:stop()
    self.is_playing = false
    self.current_emote = nil
    if self.move_conn then
        pcall(function() self.move_conn:Disconnect() end)
        self.move_conn = nil
    end
    if self.active_track then
        pcall(function()
            self.active_track:Stop(0.15)
            self.active_track:Destroy()
        end)
        self.active_track = nil
    end
end

function emote_manager:play(animIdOrDirect, name)
    self:stop()
    local numId = tostring(animIdOrDirect):match("%d+")
    if not numId then return end
    local targetEmoteName = name or tostring(animIdOrDirect)
    self.last_id = animIdOrDirect
    self.last_name = targetEmoteName
    self.current_emote = targetEmoteName
    self.is_playing = true

    task.spawn(function()
        local char = local_player and local_player.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local animator = hum and (hum:FindFirstChildOfClass("Animator") or hum)
        if not animator then return end

        local function play_track_with_id(directId)
            if not self.is_playing or self.current_emote ~= targetEmoteName then return end
            if not directId or directId == "" then return end

            local anim = Instance.new("Animation")
            anim.AnimationId = directId

            local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
            if ok and track and self.is_playing and self.current_emote == targetEmoteName then
                track.Priority = Enum.AnimationPriority.Action
                track.Looped = self.looped
                track:Play(0.15)
                self.active_track = track

                if not self.looped and hum then
                    self:setup_movement_listener(hum)
                    track.Stopped:Connect(function()
                        if self.is_playing and self.active_track == track then
                            self:stop()
                        end
                    end)
                end
            end
        end

        local cached = resolved_anim_cache[numId]
        if cached then
            play_track_with_id(cached)
        else
            resolve_playable_anim_id(numId, function(resolvedId)
                play_track_with_id(resolvedId)
            end)
        end
    end)
end

if local_player then
    pcall(function()
        table.insert(ctx.conns, local_player.CharacterAdded:Connect(function(char)
            local resume = emote_manager.looped and emote_manager.is_playing and emote_manager.last_id ~= nil
            local resume_id = emote_manager.last_id
            local resume_name = emote_manager.last_name
            emote_manager:stop()
            if resume then
                task.spawn(function()
                    local hum = char:WaitForChild("Humanoid", 5)
                    if not hum then return end
                    hum:WaitForChild("Animator", 5)
                    task.wait(0.2)
                    if local_player.Character ~= char then return end
                    if not emote_manager.looped then return end
                    emote_manager:play(resume_id, resume_name)
                end)
            end
        end))
    end)
end

local anim_ui = nil
local emote_ui = nil

-- ============================================================================
-- ANIMATION CATALOG IMPLEMENTATION (STANDALONE & VERIFIED RIVALS RIG)
-- ============================================================================
local function build_animation_catalog(lib, Config)
    Config = Config or {}
    local packs = Config.Packs or anim_manager.packs or {}
    local selectedPack = Config.Selected or (packs[1] and packs[1].name) or "Zombie"
    local onSelect = Config.OnSelect or function() end

    local floatParent = resolve_float_parent()
    local existingWindow = nil
    pcall(function()
        existingWindow = floatParent and floatParent:FindFirstChild("AnimCatalogWindow")
    end)
    if existingWindow then
        pcall(function() existingWindow:Destroy() end)
    end

    local CatalogWindow = Instance.new("CanvasGroup")
    CatalogWindow.Name = "AnimCatalogWindow"
    CatalogWindow.BackgroundColor3 = get_theme_color("BackgroundColor")
    CatalogWindow.BorderSizePixel = 0
    CatalogWindow.Position = Config.Position or get_docked_position(480, 510)
    CatalogWindow.Size = UDim2.fromOffset(480, 510)
    CatalogWindow.Visible = false
    CatalogWindow.Active = true
    CatalogWindow.GroupTransparency = 1
    CatalogWindow.ZIndex = 120
    CatalogWindow.Parent = floatParent
    if getgenv then getgenv().__v_ctx_anims = CatalogWindow end

    local winScale = Instance.new("UIScale")
    winScale.Scale = 1
    winScale.Parent = CatalogWindow

    local winCorner = Instance.new("UICorner")
    winCorner.CornerRadius = UDim.new(0, 10)
    winCorner.Parent = CatalogWindow

    local winStroke = Instance.new("UIStroke")
    winStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    winStroke.Color = get_theme_color("OutlineColor")
    winStroke.Thickness = 1
    winStroke.Parent = CatalogWindow

    local ts = TweenService or tween_service or cloneref(game:GetService("TweenService"))
    local is_open = false
    local isClosing = false
    local heartbeat_conn = nil

    local function smoothOpen()
        is_open = true
        isClosing = false
        CatalogWindow.Position = get_docked_position(CatalogWindow.Size.X.Offset, CatalogWindow.Size.Y.Offset, CatalogWindow.Parent)
        CatalogWindow.Visible = true
        winScale.Scale = 0.96
        CatalogWindow.GroupTransparency = 1
        winStroke.Transparency = 1
        local ok = false
        if ts and typeof(ts.Create) == "function" then
            local p_ok = pcall(function()
                ts:Create(CatalogWindow, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 0 }):Play()
                ts:Create(winScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
                ts:Create(winStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 0 }):Play()
            end)
            ok = p_ok
        end
        if not ok then
            CatalogWindow.GroupTransparency = 0
            winStroke.Transparency = 0
            winScale.Scale = 1
        end
    end

    local function smoothClose()
        if not is_open and not CatalogWindow.Visible then return end
        is_open = false
        isClosing = true
        if heartbeat_conn then
            pcall(function() heartbeat_conn:Disconnect() end)
            heartbeat_conn = nil
        end
        local ok = false
        if ts and typeof(ts.Create) == "function" then
            local p_ok = pcall(function()
                ts:Create(CatalogWindow, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 1 }):Play()
                ts:Create(winScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 0.96 }):Play()
                ts:Create(winStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
            end)
            ok = p_ok
        end
        if not ok then
            CatalogWindow.Visible = false
            CatalogWindow.GroupTransparency = 1
            winStroke.Transparency = 1
            winScale.Scale = 1
            isClosing = false
            return
        end
        task.delay(0.2, function()
            if not is_open then
                CatalogWindow.Visible = false
                CatalogWindow.GroupTransparency = 1
                winStroke.Transparency = 1
                winScale.Scale = 1
                isClosing = false
            end
        end)
    end

    local Header = Instance.new("Frame")
    Header.BackgroundTransparency = 1
    Header.Size = UDim2.new(1, 0, 0, 34)
    Header.ZIndex = 121
    Header.Parent = CatalogWindow

    local HeaderIcon = Instance.new("ImageLabel")
    HeaderIcon.BackgroundTransparency = 1
    HeaderIcon.Position = UDim2.new(0, 10, 0.5, -7)
    HeaderIcon.Size = UDim2.fromOffset(14, 14)
    HeaderIcon.ImageColor3 = get_theme_color("AccentColor")
    HeaderIcon.Image = "rbxassetid://6034684937"
    HeaderIcon.ZIndex = 122
    HeaderIcon.Parent = Header

    local HeaderTitle = Instance.new("TextLabel")
    HeaderTitle.BackgroundTransparency = 1
    HeaderTitle.Font = get_theme_font()
    HeaderTitle.Position = UDim2.new(0, 30, 0, 0)
    HeaderTitle.Size = UDim2.new(1, -110, 1, 0)
    HeaderTitle.Text = string.lower(Config.Title or "animations")
    HeaderTitle.TextColor3 = get_theme_color("FontColor")
    HeaderTitle.TextSize = 13
    HeaderTitle.TextXAlignment = Enum.TextXAlignment.Left
    HeaderTitle.ZIndex = 122
    HeaderTitle.Parent = Header

    local CounterLabel = Instance.new("TextLabel")
    CounterLabel.BackgroundTransparency = 1
    CounterLabel.Font = get_theme_font()
    CounterLabel.AnchorPoint = Vector2.new(1, 0.5)
    CounterLabel.Position = UDim2.new(1, -34, 0.5, 0)
    CounterLabel.Size = UDim2.fromOffset(60, 18)
    CounterLabel.Text = string.format("0/%d", #packs)
    CounterLabel.TextColor3 = get_theme_color("FontColor")
    CounterLabel.TextTransparency = 0.4
    CounterLabel.TextSize = 11
    CounterLabel.TextXAlignment = Enum.TextXAlignment.Right
    CounterLabel.ZIndex = 122
    CounterLabel.Parent = Header

    local CloseButton = Instance.new("TextButton")
    CloseButton.Name = "CloseButton"
    CloseButton.BackgroundTransparency = 1
    CloseButton.BorderSizePixel = 0
    CloseButton.AnchorPoint = Vector2.new(1, 0.5)
    CloseButton.Position = UDim2.new(1, -6, 0.5, 0)
    CloseButton.Size = UDim2.fromOffset(18, 18)
    CloseButton.AutoButtonColor = false
    CloseButton.Font = Enum.Font.SourceSans
    CloseButton.Text = "×"
    CloseButton.TextColor3 = get_theme_color("FontColor")
    CloseButton.TextSize = 16
    CloseButton.TextTransparency = 0.4
    CloseButton.ZIndex = 123
    CloseButton.Parent = Header

    CloseButton.MouseEnter:Connect(function()
        CloseButton.TextTransparency = 0
        CloseButton.TextColor3 = get_theme_color("RedColor", Color3.fromRGB(255, 65, 65))
    end)
    CloseButton.MouseLeave:Connect(function()
        CloseButton.TextTransparency = 0.4
        CloseButton.TextColor3 = get_theme_color("FontColor")
    end)
    CloseButton.MouseButton1Click:Connect(function()
        smoothClose()
    end)

    make_ui_draggable(CatalogWindow, Header)

    local HeaderDivider = Instance.new("Frame")
    HeaderDivider.BackgroundColor3 = get_theme_color("OutlineColor")
    HeaderDivider.BorderSizePixel = 0
    HeaderDivider.Position = UDim2.new(0, 0, 0, 34)
    HeaderDivider.Size = UDim2.new(1, 0, 0, 1)
    HeaderDivider.ZIndex = 121
    HeaderDivider.Parent = CatalogWindow

    -- Preview Holder
    local PreviewHolder = Instance.new("Frame")
    PreviewHolder.BackgroundColor3 = get_theme_color("MainColor")
    PreviewHolder.BorderSizePixel = 0
    PreviewHolder.Position = UDim2.new(0, 10, 0, 38)
    PreviewHolder.Size = UDim2.new(1, -20, 0, 160)
    PreviewHolder.ClipsDescendants = true
    PreviewHolder.ZIndex = 122
    PreviewHolder.Parent = CatalogWindow

    local prevCorner = Instance.new("UICorner")
    prevCorner.CornerRadius = UDim.new(0, 8)
    prevCorner.Parent = PreviewHolder

    local prevStroke = Instance.new("UIStroke")
    prevStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    prevStroke.Color = get_theme_color("OutlineColor")
    prevStroke.Thickness = 1
    prevStroke.Parent = PreviewHolder

    local current_preview_mode = "run"
    local current_preview_pack = nil
    local currentDummyAngle = math.rad(165)
    local isDraggingPreview = false
    local dragStartX = 0
    local dragStartAngle = currentDummyAngle

    local Viewport = Instance.new("ViewportFrame")
    Viewport.BackgroundTransparency = 1
    Viewport.Size = UDim2.new(1, 0, 1, -26)
    Viewport.Position = UDim2.new(0, 0, 0, 0)
    Viewport.ZIndex = 123
    Viewport.Ambient = Color3.fromRGB(220, 220, 220)
    Viewport.LightColor = Color3.fromRGB(255, 255, 255)
    Viewport.LightDirection = Vector3.new(-1, -1.2, -1)
    Viewport.Parent = PreviewHolder

    local WorldModel = Instance.new("WorldModel")
    WorldModel.Parent = Viewport

    local ViewportCam = Instance.new("Camera")
    ViewportCam.FieldOfView = 31
    ViewportCam.CFrame = CFrame.new(Vector3.new(0, 0.1, 9.8), Vector3.new(0, 0.1, 0))
    ViewportCam.Parent = Viewport
    Viewport.CurrentCamera = ViewportCam

    local PreviewBar = Instance.new("Frame")
    PreviewBar.Name = "PreviewBar"
    PreviewBar.BackgroundTransparency = 1
    PreviewBar.Position = UDim2.new(0, 0, 1, -26)
    PreviewBar.Size = UDim2.new(1, 0, 0, 26)
    PreviewBar.ZIndex = 124
    PreviewBar.Parent = PreviewHolder

    local selected_slot = "all"
    local slotOptions = { "All", "Idle", "Walk", "Run", "Jump", "Fall", "Climb", "Swim" }

    local PreviewLabel = Instance.new("TextLabel")
    PreviewLabel.Name = "PreviewLabel"
    PreviewLabel.BackgroundTransparency = 1
    PreviewLabel.Font = get_theme_font()
    PreviewLabel.Position = UDim2.new(0, 8, 0, 0)
    PreviewLabel.Size = UDim2.new(1, -260, 1, 0)
    PreviewLabel.Text = "running: " .. tostring(selectedPack)
    PreviewLabel.TextColor3 = get_theme_color("FontColor")
    PreviewLabel.TextTransparency = 0.2
    PreviewLabel.TextSize = 11
    PreviewLabel.TextXAlignment = Enum.TextXAlignment.Left
    PreviewLabel.ZIndex = 125
    PreviewLabel.Parent = PreviewBar

    local ModeContainer = Instance.new("Frame")
    ModeContainer.Name = "ModeContainer"
    ModeContainer.BackgroundTransparency = 1
    ModeContainer.Position = UDim2.new(1, -254, 0.5, -10)
    ModeContainer.Size = UDim2.fromOffset(248, 20)
    ModeContainer.ZIndex = 125
    ModeContainer.Parent = PreviewBar

    local modeLayout = Instance.new("UIListLayout")
    modeLayout.FillDirection = Enum.FillDirection.Horizontal
    modeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    modeLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    modeLayout.Padding = UDim.new(0, 4)
    modeLayout.Parent = ModeContainer

    local modeButtons = {}
    local modesList = { "run", "idle", "walk" }

    local populate_pack_card_fn = nil
    local stop_pack_card_fn = nil
    local play_pack_card_fn = nil

    local activeTrack = nil
    local previewDummy = nil
    local is_creating_dummy = false
    local currentAnimToken = 0
    local cachedTracks = {}
    local cardButtons = {}

    local function refresh_dummy()
        if is_creating_dummy then return previewDummy end
        local char = local_player and local_player.Character
        local char_ready = (char and char:FindFirstChildOfClass("Humanoid") and #char:GetChildren() > 0)
        if previewDummy and previewDummy.Parent == WorldModel and previewDummy:FindFirstChildOfClass("Humanoid") then
            if not previewDummy:GetAttribute("__is_fallback") then
                return previewDummy
            end
            if not char_ready then
                return previewDummy
            end
        end
        is_creating_dummy = true
        if previewDummy then
            pcall(function() previewDummy:Destroy() end)
            previewDummy = nil
            activeTrack = nil
        end
        table.clear(cachedTracks)
        WorldModel:ClearAllChildren()
        local ok, dummy = pcall(create_clean_dummy, currentDummyAngle)
        is_creating_dummy = false
        if ok and dummy then
            previewDummy = dummy
            dummy.Parent = WorldModel
        end
        return previewDummy
    end

    local function get_pack_by_name(name)
        if typeof(name) == "table" then return name end
        for _, p in ipairs(packs) do
            if p.name == name then return p end
        end
        local numId = tonumber(tostring(name):match("%d+"))
        if numId and numId > 1000 then
            return { name = "ID " .. tostring(numId), run = numId, walk = numId, idle = { numId } }
        end
        return nil
    end

    local function get_pack_anim_id(pack, mode)
        mode = mode or current_preview_mode
        if not pack then return nil end
        if pack.name == "Default" or pack.bundle_id == 0 then
            local defs = anim_manager and (anim_manager.clean_defaults or anim_manager.fallback_defaults)
            local fallbacks = anim_manager and anim_manager.fallback_defaults
            if mode == "idle" then
                return (defs and defs.idle1) or (fallbacks and fallbacks.idle1) or 507766388
            elseif mode == "walk" then
                return (defs and defs.walk) or (fallbacks and fallbacks.walk) or 540798782
            elseif mode == "run" then
                return (defs and defs.run) or (fallbacks and fallbacks.run) or 507767714
            elseif mode == "jump" then
                return (defs and defs.jump) or (fallbacks and fallbacks.jump) or 507765000
            elseif mode == "fall" then
                return (defs and defs.fall) or (fallbacks and fallbacks.fall) or 507767968
            elseif mode == "climb" then
                return (defs and defs.climb) or (fallbacks and fallbacks.climb) or 507765644
            elseif mode == "swim" then
                return (defs and defs.swim) or (fallbacks and fallbacks.swim) or 507784897
            end
        end
        if mode == "run" then
            return pack.run or pack.walk or (pack.idle and pack.idle[1])
        elseif mode == "idle" then
            return (pack.idle and pack.idle[1]) or pack.run or pack.walk
        elseif mode == "walk" then
            return pack.walk or pack.run or (pack.idle and pack.idle[1])
        end
        return pack.run or pack.walk or (pack.idle and pack.idle[1])
    end

    local play_preview = nil
    play_preview = function(packOrName, mode)
        currentAnimToken = currentAnimToken + 1
        local myToken = currentAnimToken

        mode = mode or current_preview_mode
        local pack = get_pack_by_name(packOrName)
        if not pack then return end
        current_preview_pack = pack

        local modePrefix = (mode == "idle" and "idle: ") or (mode == "walk" and "walking: ") or "running: "
        PreviewLabel.Text = modePrefix .. tostring(pack.name)

        local dummy = previewDummy
        if not dummy or not dummy.Parent or not dummy:FindFirstChildOfClass("Humanoid") then
            dummy = refresh_dummy()
        end
        if not dummy then return end

        local hum = dummy:FindFirstChildOfClass("Humanoid")
        local animator = hum and (hum:FindFirstChildOfClass("Animator") or hum)
        if not animator then return end

        local rawAnimId = get_pack_anim_id(pack, mode)
        local numId = rawAnimId and tostring(rawAnimId):match("%d+")
        if not numId or numId == "0" then
            if activeTrack then
                pcall(function() activeTrack:Stop(0.05) end)
                activeTrack = nil
            end
            return
        end

        local trackKey = tostring(pack.name) .. "_" .. tostring(mode) .. "_" .. tostring(numId)
        local track = cachedTracks[trackKey]
        if track and track.Parent then
            if activeTrack and activeTrack ~= track then
                pcall(function() activeTrack:Stop(0.05) end)
            end
            track.Priority = Enum.AnimationPriority.Action
            track.Looped = true
            track:Play(0.05)
            activeTrack = track
            return
        end

        local function load_and_play_preview(playableId)
            if myToken ~= currentAnimToken then return end
            if not dummy or not dummy.Parent then return end
            local curHum = dummy:FindFirstChildOfClass("Humanoid")
            local curAnimator = curHum and (curHum:FindFirstChildOfClass("Animator") or curHum)
            if not curAnimator or not playableId or playableId == "" then return end

            local anim = Instance.new("Animation")
            anim.AnimationId = playableId
            local ok, newTrack = pcall(curAnimator.LoadAnimation, curAnimator, anim)
            if ok and newTrack and myToken == currentAnimToken and dummy and dummy.Parent then
                cachedTracks[trackKey] = newTrack
                newTrack.Priority = Enum.AnimationPriority.Action
                newTrack.Looped = true
                if activeTrack and activeTrack ~= newTrack then
                    pcall(function() activeTrack:Stop(0.05) end)
                end
                newTrack:Play(0.05)
                activeTrack = newTrack
            elseif newTrack then
                pcall(function() newTrack:Destroy() end)
            end
        end

        local cached = resolved_anim_cache[numId]
        if cached then
            load_and_play_preview(cached)
        else
            resolve_playable_anim_id(numId, function(resolvedId)
                load_and_play_preview(resolvedId)
            end)
        end
    end

    local function update_mode_buttons()
        local accent = get_theme_color("AccentColor") or Color3.fromRGB(255, 255, 255)
        local lum = 0.299 * accent.R + 0.587 * accent.G + 0.114 * accent.B
        local activeTextColor = (lum > 0.55) and Color3.fromRGB(18, 18, 22) or Color3.fromRGB(255, 255, 255)

        for m, btn in pairs(modeButtons) do
            local isAct = (m == current_preview_mode)
            btn.BackgroundColor3 = isAct and accent or Color3.fromRGB(30, 30, 38)
            btn.TextColor3 = isAct and activeTextColor or get_theme_color("FontColor")
            btn.TextTransparency = isAct and 0 or 0.4
        end
    end

    for _, m in ipairs(modesList) do
        local btn = Instance.new("TextButton")
        btn.Name = m
        btn.AutoButtonColor = false
        btn.Font = get_theme_font()
        btn.Size = UDim2.fromOffset(32, 18)
        btn.Text = m:sub(1, 1):upper() .. m:sub(2)
        btn.TextSize = 10
        btn.ZIndex = 126
        btn.Parent = ModeContainer

        local bCorn = Instance.new("UICorner")
        bCorn.CornerRadius = UDim.new(0, 4)
        bCorn.Parent = btn

        modeButtons[m] = btn
        btn.MouseButton1Click:Connect(function()
            current_preview_mode = m
            update_mode_buttons()
            local targetPack = current_preview_pack or get_pack_by_name(selectedPack)
            if targetPack then
                play_preview(targetPack, m)
            end
            for _, c in pairs(cardButtons) do
                if c.Frame and c.Frame.Visible then
                    task.defer(play_pack_card_fn, c, m)
                elseif c.Track then
                    stop_pack_card_fn(c)
                end
            end
        end)
    end
    update_mode_buttons()

    local SlotDropdownBtn = Instance.new("TextButton")
    SlotDropdownBtn.Name = "SlotDropdownBtn"
    SlotDropdownBtn.AutoButtonColor = false
    SlotDropdownBtn.Font = get_theme_font()
    SlotDropdownBtn.Size = UDim2.fromOffset(56, 18)
    SlotDropdownBtn.Text = "All ▾"
    SlotDropdownBtn.TextSize = 10
    SlotDropdownBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    SlotDropdownBtn.TextColor3 = get_theme_color("FontColor")
    SlotDropdownBtn.TextTransparency = 0.2
    SlotDropdownBtn.ZIndex = 126
    SlotDropdownBtn.Parent = ModeContainer

    local slotDropCorner = Instance.new("UICorner")
    slotDropCorner.CornerRadius = UDim.new(0, 4)
    slotDropCorner.Parent = SlotDropdownBtn

    local slotDropStroke = Instance.new("UIStroke")
    slotDropStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    slotDropStroke.Color = get_theme_color("OutlineColor")
    slotDropStroke.Thickness = 1
    slotDropStroke.Parent = SlotDropdownBtn

    local ApplyBtn = Instance.new("TextButton")
    ApplyBtn.Name = "ApplyBtn"
    ApplyBtn.AutoButtonColor = false
    ApplyBtn.Font = get_theme_font()
    ApplyBtn.Size = UDim2.fromOffset(44, 18)
    ApplyBtn.Text = "Apply"
    ApplyBtn.TextSize = 10
    local applyAccent = get_theme_color("AccentColor") or Color3.fromRGB(255, 255, 255)
    local applyLum = 0.299 * applyAccent.R + 0.587 * applyAccent.G + 0.114 * applyAccent.B
    ApplyBtn.BackgroundColor3 = applyAccent
    ApplyBtn.TextColor3 = (applyLum > 0.55) and Color3.fromRGB(18, 18, 22) or Color3.fromRGB(255, 255, 255)
    ApplyBtn.ZIndex = 126
    ApplyBtn.Parent = ModeContainer

    local applyCorner = Instance.new("UICorner")
    applyCorner.CornerRadius = UDim.new(0, 4)
    applyCorner.Parent = ApplyBtn

    local SlotDropdownList = Instance.new("Frame")
    SlotDropdownList.Name = "SlotDropdownList"
    SlotDropdownList.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    SlotDropdownList.BorderSizePixel = 0
    SlotDropdownList.Position = UDim2.new(1, -114, 0, 196)
    SlotDropdownList.Size = UDim2.fromOffset(58, 150)
    SlotDropdownList.Visible = false
    SlotDropdownList.ZIndex = 160
    SlotDropdownList.Parent = CatalogWindow

    local dropListCorner = Instance.new("UICorner")
    dropListCorner.CornerRadius = UDim.new(0, 6)
    dropListCorner.Parent = SlotDropdownList

    local dropListStroke = Instance.new("UIStroke")
    dropListStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    dropListStroke.Color = get_theme_color("OutlineColor")
    dropListStroke.Thickness = 1
    dropListStroke.Parent = SlotDropdownList

    local dropListPad = Instance.new("UIPadding")
    dropListPad.PaddingTop = UDim.new(0, 2)
    dropListPad.PaddingBottom = UDim.new(0, 2)
    dropListPad.PaddingLeft = UDim.new(0, 2)
    dropListPad.PaddingRight = UDim.new(0, 2)
    dropListPad.Parent = SlotDropdownList

    local dropListLayout = Instance.new("UIListLayout")
    dropListLayout.FillDirection = Enum.FillDirection.Vertical
    dropListLayout.Padding = UDim.new(0, 1)
    dropListLayout.Parent = SlotDropdownList

    for _, opt in ipairs(slotOptions) do
        local optBtn = Instance.new("TextButton")
        optBtn.Name = opt
        optBtn.Size = UDim2.new(1, 0, 0, 17)
        optBtn.BackgroundTransparency = 1
        optBtn.BackgroundColor3 = Color3.fromRGB(34, 34, 44)
        optBtn.Text = opt
        optBtn.Font = get_theme_font()
        optBtn.TextSize = 10
        optBtn.TextColor3 = get_theme_color("FontColor")
        optBtn.TextTransparency = 0.2
        optBtn.AutoButtonColor = false
        optBtn.ZIndex = 161
        optBtn.Parent = SlotDropdownList

        local optCorn = Instance.new("UICorner")
        optCorn.CornerRadius = UDim.new(0, 3)
        optCorn.Parent = optBtn

        optBtn.MouseEnter:Connect(function()
            optBtn.BackgroundTransparency = 0
            optBtn.TextTransparency = 0
        end)
        optBtn.MouseLeave:Connect(function()
            optBtn.BackgroundTransparency = 1
            optBtn.TextTransparency = (selected_slot == opt:lower()) and 0 or 0.2
        end)
        optBtn.MouseButton1Click:Connect(function()
            selected_slot = opt:lower()
            SlotDropdownBtn.Text = opt .. " ▾"
            SlotDropdownList.Visible = false
        end)
    end

    SlotDropdownBtn.MouseButton1Click:Connect(function()
        SlotDropdownList.Visible = not SlotDropdownList.Visible
    end)

    ApplyBtn.MouseButton1Click:Connect(function()
        local targetPack = current_preview_pack or get_pack_by_name(selectedPack)
        if targetPack then
            if toggles.custom_anims_toggle and not toggles.custom_anims_toggle.Value then
                pcall(function() toggles.custom_anims_toggle:SetValue(true) end)
            end
            anim_manager:apply(targetPack.name or targetPack, selected_slot)
            if onSelect then
                onSelect(targetPack, selected_slot)
            end
        end
    end)

    -- Interactive 3D rotation in main preview
    Viewport.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDraggingPreview = true
            dragStartX = input.Position.X
            dragStartAngle = currentDummyAngle
        end
    end)
    Viewport.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDraggingPreview = false
        end
    end)
    user_input_service.InputChanged:Connect(function(input)
        if isDraggingPreview and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local deltaX = input.Position.X - dragStartX
            currentDummyAngle = dragStartAngle - deltaX * 0.015
            if previewDummy and previewDummy.PrimaryPart then
                previewDummy:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, currentDummyAngle, 0))
            end
        end
    end)

    -- Search Container
    local SearchContainer = Instance.new("Frame")
    SearchContainer.BackgroundColor3 = get_theme_color("MainColor")
    SearchContainer.BorderSizePixel = 0
    SearchContainer.Position = UDim2.new(0, 10, 0, 204)
    SearchContainer.Size = UDim2.new(1, -20, 0, 26)
    SearchContainer.ZIndex = 122
    SearchContainer.Parent = CatalogWindow

    local searchCorner = Instance.new("UICorner")
    searchCorner.CornerRadius = UDim.new(0, 6)
    searchCorner.Parent = SearchContainer

    local searchStroke = Instance.new("UIStroke")
    searchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    searchStroke.Color = get_theme_color("OutlineColor")
    searchStroke.Thickness = 1
    searchStroke.Parent = SearchContainer

    local SearchIcon = Instance.new("ImageLabel")
    SearchIcon.BackgroundTransparency = 1
    SearchIcon.Position = UDim2.new(0, 6, 0.5, -6)
    SearchIcon.Size = UDim2.fromOffset(12, 12)
    SearchIcon.ImageColor3 = get_theme_color("FontColor")
    SearchIcon.ImageTransparency = 0.5
    SearchIcon.Image = "rbxassetid://6031154871"
    SearchIcon.ZIndex = 123
    SearchIcon.Parent = SearchContainer

    local SearchBox = Instance.new("TextBox")
    SearchBox.BackgroundTransparency = 1
    SearchBox.ClearTextOnFocus = false
    SearchBox.Font = get_theme_font()
    SearchBox.PlaceholderColor3 = Color3.fromRGB(130, 130, 140)
    SearchBox.PlaceholderText = "search marketplace animations..."
    SearchBox.Position = UDim2.new(0, 24, 0, 0)
    SearchBox.Size = UDim2.new(1, -30, 1, 0)
    SearchBox.Text = ""
    SearchBox.TextColor3 = get_theme_color("FontColor")
    SearchBox.TextSize = 11
    SearchBox.TextXAlignment = Enum.TextXAlignment.Left
    SearchBox.ZIndex = 123
    SearchBox.Parent = SearchContainer

    -- 3-Column Grid Frame
    local GridFrame = Instance.new("ScrollingFrame")
    GridFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    GridFrame.BackgroundTransparency = 1
    GridFrame.BorderSizePixel = 0
    GridFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    GridFrame.ElasticBehavior = Enum.ElasticBehavior.Never
    GridFrame.Position = UDim2.new(0, 10, 0, 236)
    GridFrame.ScrollBarThickness = 3
    GridFrame.ScrollingDirection = Enum.ScrollingDirection.Y
    GridFrame.Size = UDim2.new(1, -20, 1, -242)
    GridFrame.ZIndex = 122
    GridFrame.Parent = CatalogWindow

    local GridLayout = Instance.new("UIGridLayout")
    GridLayout.CellPadding = UDim2.fromOffset(6, 6)
    GridLayout.CellSize = UDim2.fromOffset(140, 96)
    GridLayout.FillDirectionMaxCells = 3
    GridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    GridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    GridLayout.Parent = GridFrame

    local gridPad = Instance.new("UIPadding")
    gridPad.PaddingBottom = UDim.new(0, 6)
    gridPad.PaddingLeft = UDim.new(0, 2)
    gridPad.PaddingRight = UDim.new(0, 2)
    gridPad.PaddingTop = UDim.new(0, 2)
    gridPad.Parent = GridFrame

    local function update_selection(name)
        selectedPack = name
        local foundPack = nil
        local foundCard = nil
        for pName, card in pairs(cardButtons) do
            local isSel = (pName == name)
            if card.Stroke then
                card.Stroke.Color = isSel and get_theme_color("AccentColor") or get_theme_color("OutlineColor")
                card.Stroke.Thickness = isSel and 1.5 or 1
            end
            if card.Label then
                card.Label.TextColor3 = isSel and get_theme_color("AccentColor") or get_theme_color("FontColor")
            end
            if isSel then
                foundPack = card.Pack
                foundCard = card
            end
        end
        if foundCard then
            play_pack_card_fn(foundCard, current_preview_mode)
        end
        if foundPack then
            play_preview(foundPack, current_preview_mode)
        end
    end

    local hoveredCardName = nil

    local function restore_selected_preview()
        hoveredCardName = nil
        for pName, c in pairs(cardButtons) do
            if pName ~= selectedPack and c.Frame then
                c.Frame.BackgroundColor3 = get_theme_color("MainColor")
            end
        end
        local curPack = get_pack_by_name(selectedPack)
        if curPack then
            local selCard = cardButtons[selectedPack]
            if selCard then
                play_pack_card_fn(selCard, current_preview_mode)
            end
            play_preview(curPack, current_preview_mode)
        end
    end

    local function get_dummy_template()
        return build_master_dummy_template()
    end

    local pack_card_angle = math.rad(165)

    local function populate_pack_card(card)
        if not card or not card.Holder or not card.Holder.Parent then return end
        local char = local_player and local_player.Character
        local char_ready = (char and char:FindFirstChildOfClass("Humanoid") and #char:GetChildren() > 0)
        if card.Dummy and card.Dummy.Parent == card.World then
            if not card.Dummy:GetAttribute("__is_fallback") or not char_ready then
                return
            end
        end
        if card.Dummy then
            pcall(function() card.Dummy:Destroy() end)
            card.Dummy = nil
        end
        if card.Tracks then
            for _, track in pairs(card.Tracks) do
                pcall(function() track:Stop() track:Destroy() end)
            end
            table.clear(card.Tracks)
        end
        card.Track = nil
        local template = get_dummy_template()
        if not template then return end
        local ok, clone = pcall(template.Clone, template)
        if not ok or not clone then return end
        clone.Name = "PreviewAvatar"
        pcall(function()
            local hrp = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart
            if hrp then
                clone.PrimaryPart = hrp
                clone:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, pack_card_angle, 0))
            end
        end)
        clone.Parent = card.World
        card.Dummy = clone
    end

    local function stop_pack_card(card)
        if not card then return end
        card.Seq = (card.Seq or 0) + 1
        if card.Track then
            pcall(function() card.Track:Stop(0.1) end)
        end
    end

    local function play_pack_card(card, mode)
        if not card or not card.Pack then return end
        mode = mode or current_preview_mode
        card.Seq = (card.Seq or 0) + 1
        local seq = card.Seq
        local raw = get_pack_anim_id(card.Pack, mode)
        local num = raw and tostring(raw):match("%d+")
        if not num or num == "0" then
            if card.Track then
                pcall(function() card.Track:Stop(0.05) end)
                card.Track = nil
            end
            return
        end
        if card.Track and card.TrackMode == mode then
            local playing = false
            pcall(function() playing = card.Track.IsPlaying end)
            if playing then return end
        end
        if not card.Dummy or not card.Dummy.Parent then
            populate_pack_card(card)
        end
        local dummy = card.Dummy
        if not dummy then return end
        local hum = dummy:FindFirstChildOfClass("Humanoid")
        local animator = hum and (hum:FindFirstChildOfClass("Animator") or hum)
        if not animator then return end
        local key = tostring(mode) .. "_" .. tostring(num)
        local known = card.Tracks and card.Tracks[key]
        if known and known.Parent then
            if card.Track and card.Track ~= known then
                pcall(function() card.Track:Stop(0.05) end)
            end
            known.Priority = Enum.AnimationPriority.Action
            known.Looped = true
            known:Play(0.05)
            card.Track = known
            card.TrackMode = mode
            return
        end

        local directId = resolved_anim_cache[num] or resolve_playable_anim_id(num)
        if not directId or directId == "" then return end
        local anim = Instance.new("Animation")
        anim.AnimationId = directId
        local ok, track = pcall(animator.LoadAnimation, animator, anim)
        if ok and track then
            if seq ~= card.Seq or not card.Dummy or not card.Dummy.Parent then
                pcall(function() track:Destroy() end)
                return
            end
            if card.Tracks then card.Tracks[key] = track end
            if card.Track and card.Track ~= track then
                pcall(function() card.Track:Stop(0.05) end)
            end
            card.Track = track
            card.TrackMode = mode
            track.Priority = Enum.AnimationPriority.Action
            track.Looped = true
            track:Play(0.05)
        end
    end

    populate_pack_card_fn = populate_pack_card
    stop_pack_card_fn = stop_pack_card
    play_pack_card_fn = play_pack_card

    local function pack_card_in_view(card)
        local f = card and card.Frame
        if not f or not f.Visible or not CatalogWindow.Visible then return false end
        local gs = GridFrame.AbsoluteSize
        local cs = f.AbsoluteSize
        if gs.Y <= 0 or cs.Y <= 0 then return false end
        local gy = GridFrame.AbsolutePosition.Y
        local cy = f.AbsolutePosition.Y
        return (cy + cs.Y > gy - 10) and (cy < gy + gs.Y + 10)
    end

    local is_updating_visible = false
    local function update_visible_cards()
        if not CatalogWindow.Visible then
            for _, c in pairs(cardButtons) do
                if c.Track then
                    pcall(function() c.Track:Stop(0.05) end)
                end
            end
            return
        end
        if is_updating_visible then return end
        is_updating_visible = true
        task.defer(function()
            is_updating_visible = false
            if not CatalogWindow.Visible then return end
            local active_count = 0
            local max_active = 6
            for _, c in pairs(cardButtons) do
                if c.Frame and c.Frame.Visible and pack_card_in_view(c) then
                    if active_count < max_active then
                        active_count = active_count + 1
                        local card = c
                        local delay_time = (active_count - 1) * 0.04
                        task.delay(delay_time, function()
                            if CatalogWindow.Visible and card.Frame and card.Frame.Visible and pack_card_in_view(card) then
                                play_pack_card(card, current_preview_mode)
                            end
                        end)
                    else
                        if c.Track then
                            pcall(function() c.Track:Stop(0.05) end)
                        end
                    end
                else
                    if c.Track then
                        pcall(function() c.Track:Stop(0.05) end)
                    end
                end
            end
        end)
    end

    local function add_pack_card(pack, order)
        local pName = pack.name or ("Pack " .. tostring(order or 1))
        if cardButtons[pName] then
            local existing = cardButtons[pName]
            existing.Pack = pack
            if existing.Tracks then
                for _, track in pairs(existing.Tracks) do
                    pcall(function() track:Stop() track:Destroy() end)
                end
                table.clear(existing.Tracks)
            end
            existing.Track = nil
            return existing
        end

        local Card = Instance.new("TextButton")
        Card.Name = pName
        Card.BackgroundColor3 = get_theme_color("MainColor")
        Card.BorderSizePixel = 0
        Card.LayoutOrder = order or (#packs + 10)
        Card.Size = UDim2.fromOffset(140, 96)
        Card.Text = ""
        Card.AutoButtonColor = false
        Card.ZIndex = 123
        Card.Parent = GridFrame

        local cCorn = Instance.new("UICorner")
        cCorn.CornerRadius = UDim.new(0, 8)
        cCorn.Parent = Card

        local Stroke = Instance.new("UIStroke")
        Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        Stroke.Color = (pName == selectedPack) and get_theme_color("AccentColor") or get_theme_color("OutlineColor")
        Stroke.Thickness = (pName == selectedPack) and 1.5 or 1
        Stroke.Parent = Card

        local ImgHolder = Instance.new("Frame")
        ImgHolder.BackgroundColor3 = get_theme_color("BackgroundColor")
        ImgHolder.BorderSizePixel = 0
        ImgHolder.Position = UDim2.new(0, 4, 0, 4)
        ImgHolder.Size = UDim2.new(1, -8, 0, 68)
        ImgHolder.ClipsDescendants = true
        ImgHolder.ZIndex = 124
        ImgHolder.Parent = Card

        local ihCorn = Instance.new("UICorner")
        ihCorn.CornerRadius = UDim.new(0, 6)
        ihCorn.Parent = ImgHolder

        local CardView = Instance.new("ViewportFrame")
        CardView.Name = "AnimViewport"
        CardView.BackgroundTransparency = 1
        CardView.Size = UDim2.fromScale(1, 1)
        CardView.ZIndex = 124
        CardView.Ambient = Color3.fromRGB(220, 220, 220)
        CardView.LightColor = Color3.fromRGB(255, 255, 255)
        CardView.LightDirection = Vector3.new(-1, -1.2, -1)
        CardView.Parent = ImgHolder

        local CardWorld = Instance.new("WorldModel")
        CardWorld.Parent = CardView

        local CardCam = Instance.new("Camera")
        CardCam.FieldOfView = 28
        CardCam.CFrame = CFrame.new(Vector3.new(0, 1.4, 8.4), Vector3.new(0, 0.7, 0))
        CardCam.Parent = CardView
        CardView.CurrentCamera = CardCam

        local NameLabel = Instance.new("TextLabel")
        NameLabel.BackgroundTransparency = 1
        NameLabel.Font = get_theme_font()
        NameLabel.Position = UDim2.new(0, 4, 1, -22)
        NameLabel.Size = UDim2.new(1, -8, 0, 18)
        NameLabel.Text = pName
        NameLabel.TextColor3 = (pName == selectedPack) and get_theme_color("AccentColor") or get_theme_color("FontColor")
        NameLabel.TextSize = 11
        NameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        NameLabel.ZIndex = 124
        NameLabel.Parent = Card

        local cardData = {
            Frame = Card,
            Stroke = Stroke,
            Label = NameLabel,
            Pack = pack,
            Holder = ImgHolder,
            Viewport = CardView,
            World = CardWorld,
            Cam = CardCam,
            Dummy = nil,
            Tracks = {},
            Track = nil,
            TrackMode = nil,
            Seq = 0,
        }
        cardButtons[pName] = cardData

        Card.MouseEnter:Connect(function()
            hoveredCardName = pName
            for otherName, c in pairs(cardButtons) do
                if otherName ~= selectedPack and otherName ~= pName and c.Frame then
                    c.Frame.BackgroundColor3 = get_theme_color("MainColor")
                end
            end
            if selectedPack ~= pName then
                Card.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
            end
            play_pack_card(cardData, current_preview_mode)
            play_preview(pack, current_preview_mode)
        end)
        Card.MouseLeave:Connect(function()
            if selectedPack ~= pName then
                Card.BackgroundColor3 = get_theme_color("MainColor")
            end
            if hoveredCardName == pName then
                hoveredCardName = nil
                task.delay(0.04, function()
                    if not hoveredCardName then
                        restore_selected_preview()
                    end
                end)
            end
        end)

        Card.MouseButton1Click:Connect(function()
            update_selection(pName)
            if toggles.custom_anims_toggle and not toggles.custom_anims_toggle.Value then
                pcall(function() toggles.custom_anims_toggle:SetValue(true) end)
            end
            anim_manager:apply(pack, selected_slot)
            if onSelect then
                onSelect(pack, selected_slot)
            end
        end)

        return cardData
    end

    for i, pack in ipairs(packs) do
        add_pack_card(pack, i)
    end

    local customCard = nil
    local function filter_cards(query)
        query = string.lower(query or "")
        local matchCount = 0
        local numId = tonumber(query)

        for pName, card in pairs(cardButtons) do
            local match = (query == "") or (string.find(string.lower(pName), query, 1, true) ~= nil)
            card.Frame.Visible = match
            if match then
                matchCount = matchCount + 1
            elseif card.Track then
                stop_pack_card(card)
            end
        end

        if numId and numId > 1000 then
            task.spawn(function()
                local resolved = resolve_playable_anim_id(numId)
                local targetId = tonumber(resolved:match("%d+")) or numId
                local customPack = { name = "ID " .. tostring(numId), run = targetId, walk = targetId, idle = { targetId } }
                anim_manager:register_pack(customPack)
                local card = add_pack_card(customPack, 0)
                if card and card.Frame then
                    card.Frame.Visible = true
                end
                update_visible_cards()
            end)
            matchCount = matchCount + 1
        end

        CounterLabel.Text = string.format("%d/%d", matchCount, #packs)
    end

    local bundle_cache = {}
    local catalogSearchToken = 0
    local function search_marketplace_bundles(query)
        catalogSearchToken = catalogSearchToken + 1
        local myToken = catalogSearchToken
        if #query < 2 then return end

        task.spawn(function()
            if myToken ~= catalogSearchToken then return end
            local aes = cloneref(game:GetService("AvatarEditorService"))
            local as = cloneref(game:GetService("AssetService"))
            local p = CatalogSearchParams.new()
            p.BundleTypes = { Enum.BundleType.Animations }
            p.SearchKeyword = query

            local ok, pages = pcall(function() return aes:SearchCatalogAsync(p) end)
            if not ok or not pages or typeof(pages) ~= "Instance" or not pages:IsA("Pages") or myToken ~= catalogSearchToken then return end

            local ok_page, page = pcall(function() return pages:GetCurrentPage() end)
            if not ok_page or not page or type(page) ~= "table" then return end
            local processed = 0
            for i, item in ipairs(page) do
                if myToken ~= catalogSearchToken or processed >= 6 then break end
                local bName = item.Name
                if not cardButtons[bName] then
                    local details = bundle_cache[item.Id]
                    if not details then
                        local ok2, res = pcall(function() return as:GetBundleDetailsAsync(item.Id) end)
                        if ok2 and res then
                            details = res
                            bundle_cache[item.Id] = res
                        end
                        task.wait(0.02)
                    end
                    if details and myToken == catalogSearchToken then
                        local newPack = { name = bName, bundle_id = item.Id, idle = {} }
                        for _, it in ipairs(details.Items or {}) do
                            local n = it.Name:lower()
                            local targetNum = it.Id
                            if n:find("idle") then table.insert(newPack.idle, targetNum)
                            elseif n:find("walk") then newPack.walk = targetNum
                            elseif n:find("run") then newPack.run = targetNum
                            elseif n:find("jump") then newPack.jump = targetNum
                            elseif n:find("fall") then newPack.fall = targetNum
                            elseif n:find("climb") then newPack.climb = targetNum
                            elseif n:find("swim") then newPack.swim = targetNum
                            end
                        end
                        if #newPack.idle == 0 and newPack.walk then newPack.idle = { newPack.walk } end
                        if newPack.walk or newPack.run or #newPack.idle > 0 then
                            anim_manager:register_pack(newPack)
                            local cardObj = add_pack_card(newPack, #packs + i)
                            if cardObj and cardObj.Frame then
                                cardObj.Frame.Visible = true
                            end
                            processed = processed + 1
                        end
                    end
                else
                    cardButtons[bName].Frame.Visible = true
                    processed = processed + 1
                end
            end
            if myToken == catalogSearchToken then
                update_visible_cards()
            end
        end)
    end

    local search_debounce_token = 0
    local function on_search_changed()
        local q = SearchBox.Text:gsub("^%s*(.-)%s*$", "%1")
        filter_cards(q)
        update_visible_cards()

        search_debounce_token = search_debounce_token + 1
        local curDeb = search_debounce_token
        if #q >= 2 and not tonumber(q) then
            task.delay(0.4, function()
                if curDeb == search_debounce_token and CatalogWindow.Visible then
                    search_marketplace_bundles(q)
                end
            end)
        end
    end

    SearchBox:GetPropertyChangedSignal("Text"):Connect(on_search_changed)
    SearchBox.FocusLost:Connect(function()
        local q = SearchBox.Text:gsub("^%s*(.-)%s*$", "%1")
        filter_cards(q)
        update_visible_cards()
        if #q >= 2 and not tonumber(q) then
            search_marketplace_bundles(q)
        end
    end)

    GridFrame.MouseLeave:Connect(function()
        task.delay(0.04, function()
            if not hoveredCardName then
                restore_selected_preview()
            end
        end)
    end)

    CatalogWindow.MouseLeave:Connect(function()
        restore_selected_preview()
    end)

    local moveConn = user_input_service.InputChanged:Connect(function(input)
        if not CatalogWindow.Visible then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            if hoveredCardName then
                local mPos = input.Position
                local wPos = CatalogWindow.AbsolutePosition
                local wSize = CatalogWindow.AbsoluteSize
                if mPos.X < wPos.X or mPos.X > wPos.X + wSize.X or mPos.Y < wPos.Y or mPos.Y > wPos.Y + wSize.Y then
                    restore_selected_preview()
                end
            end
        end
    end)

    CatalogWindow:GetPropertyChangedSignal("Visible"):Connect(function()
        if not CatalogWindow.Visible then
            for _, c in pairs(cardButtons) do
                if c.Track then
                    pcall(function() c.Track:Stop() end)
                end
            end
        else
            task.delay(0.15, update_visible_cards)
        end
    end)

    local scroll_deb = 0
    GridFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        scroll_deb = scroll_deb + 1
        local cur = scroll_deb
        task.delay(0.1, function()
            if cur ~= scroll_deb then return end
            if not CatalogWindow.Visible then return end
            update_visible_cards()
        end)
    end)

    pcall(refresh_dummy)
    pcall(function() update_selection(selectedPack) end)
    pcall(function() filter_cards("") end)
    task.delay(0.15, update_visible_cards)

    local lastOpenTime = 0

    local function check_parent_liveness()
        if not CatalogWindow.Visible then
            if heartbeat_conn then heartbeat_conn:Disconnect() heartbeat_conn = nil end
            return
        end
        local is_open = true
        if library and library.Toggled ~= nil then
            if not library.Toggled then is_open = false end
        end
        local mf = (lib and lib.MainFrame) or (library and library.MainFrame) or (window and window.MainFrame) or (library and library.ScreenGui and library.ScreenGui:FindFirstChild("Main", true))
        if mf then
            if not mf.Visible or (mf:IsA("CanvasGroup") and mf.GroupTransparency >= 0.75) then
                is_open = false
            end
        end
        if not is_open then
            smoothClose()
        end
    end

    local outsideConn = user_input_service.InputBegan:Connect(function(input)
        if not CatalogWindow.Visible or isClosing then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if SlotDropdownList and SlotDropdownList.Visible then
                local mPos = input.Position
                local dPos = SlotDropdownList.AbsolutePosition
                local dSize = SlotDropdownList.AbsoluteSize
                local inDrop = (mPos.X >= dPos.X and mPos.X <= dPos.X + dSize.X and mPos.Y >= dPos.Y and mPos.Y <= dPos.Y + dSize.Y)
                local bPos = SlotDropdownBtn.AbsolutePosition
                local bSize = SlotDropdownBtn.AbsoluteSize
                local inBtn = (mPos.X >= bPos.X and mPos.X <= bPos.X + bSize.X and mPos.Y >= bPos.Y and mPos.Y <= bPos.Y + bSize.Y)
                if not inDrop and not inBtn then
                    SlotDropdownList.Visible = false
                end
            end

            if os.clock() - lastOpenTime < 0.25 then return end
            local mousePos = input.Position
            local winPos = CatalogWindow.AbsolutePosition
            local winSize = CatalogWindow.AbsoluteSize
            local inWin = (mousePos.X >= winPos.X and mousePos.X <= winPos.X + winSize.X and mousePos.Y >= winPos.Y and mousePos.Y <= winPos.Y + winSize.Y)
            if inWin then return end

            local mf = (lib and lib.MainFrame) or (library and library.MainFrame) or (window and window.MainFrame) or (library and library.ScreenGui and library.ScreenGui:FindFirstChild("Main", true))
            if mf and mf.Visible then
                local mfPos = mf.AbsolutePosition
                local mfSize = mf.AbsoluteSize
                local inMf = (mousePos.X >= mfPos.X and mousePos.X <= mfPos.X + mfSize.X and mousePos.Y >= mfPos.Y and mousePos.Y <= mfPos.Y + mfSize.Y)
                if inMf then return end -- Do NOT close if clicking inside the main menu!
            end

            smoothClose()
        end
    end)

    local CatalogApi = {
        Frame = CatalogWindow,
        Open = function(self)
            lastOpenTime = os.clock()
            local espWin = (library and library.ESPPreviewFrame) or (lib and lib.ESPPreviewFrame)
            if not espWin then
                local cg = cloneref(game:GetService("CoreGui"))
                local pg = local_player and local_player:FindFirstChildOfClass("PlayerGui")
                espWin = (cg and cg:FindFirstChild("ESPPreviewWindow", true)) or (pg and pg:FindFirstChild("ESPPreviewWindow", true))
            end
            if espWin then
                if library and library.ESPPreview and library.ESPPreview.Close then
                    pcall(function() library.ESPPreview:Close() end)
                elseif lib and lib.ESPPreview and lib.ESPPreview.Close then
                    pcall(function() lib.ESPPreview:Close() end)
                else
                    pcall(function() espWin.Visible = false end)
                end
            end

            local emoteWin = (library and library.EmoteCatalogFrame) or (lib and lib.EmoteCatalogFrame)
            if not emoteWin then
                local cg = cloneref(game:GetService("CoreGui"))
                local pg = local_player and local_player:FindFirstChildOfClass("PlayerGui")
                emoteWin = (cg and cg:FindFirstChild("EmoteCatalogWindow", true)) or (pg and pg:FindFirstChild("EmoteCatalogWindow", true))
            end
            if emoteWin then
                if library and library.EmoteCatalog and library.EmoteCatalog.Close then
                    pcall(function() library.EmoteCatalog:Close() end)
                elseif emote_ui and emote_ui.close then
                    pcall(function() emote_ui:close() end)
                else
                    pcall(function() emoteWin.Visible = false end)
                end
            end
            local p = resolve_float_parent()
            if p and CatalogWindow.Parent ~= p then
                CatalogWindow.Parent = p
            end
            CatalogWindow.Position = get_docked_position(480, 510, CatalogWindow.Parent)
            CatalogWindow.ZIndex = 120
            smoothOpen()
            if not heartbeat_conn then
                heartbeat_conn = run_service.Heartbeat:Connect(check_parent_liveness)
            end
            if not previewDummy or not previewDummy.Parent or previewDummy:GetAttribute("__is_fallback") then
                pcall(refresh_dummy)
            end
            task.delay(0.15, update_visible_cards)
            local curPack = get_pack_by_name(selectedPack)
            if curPack then
                pcall(function()
                    play_preview(curPack, current_preview_mode)
                end)
            end
        end,
        Close = function(self)
            if SlotDropdownList then SlotDropdownList.Visible = false end
            for _, c in pairs(cardButtons) do
                if c.Track then
                    pcall(function() c.Track:Stop() end)
                end
            end
            smoothClose()
        end,
        Toggle = function(self)
            if is_open or (CatalogWindow.Visible and not isClosing) then
                self:Close()
            else
                self:Open()
            end
        end,
        toggle = function(self) self:Toggle() end,
        open = function(self) self:Open() end,
        close = function(self) self:Close() end,
        SetVisible = function(self, val)
            if val then self:Open() else self:Close() end
        end,
        Select = function(self, packName)
            update_selection(packName)
        end,
        GetSelected = function(self)
            return selectedPack
        end,
        GetSelectedSlot = function(self)
            return selected_slot
        end,
        SetSelectedSlot = function(self, slot)
            slot = slot or "all"
            selected_slot = slot:lower()
            local cap = selected_slot:sub(1, 1):upper() .. selected_slot:sub(2)
            if SlotDropdownBtn then SlotDropdownBtn.Text = cap .. " ▾" end
        end,
        Filter = function(self, q)
            SearchBox.Text = q or ""
            filter_cards(q or "")
        end,
        Destroy = function(self)
            if heartbeat_conn then pcall(function() heartbeat_conn:Disconnect() end) heartbeat_conn = nil end
            if outsideConn then pcall(function() outsideConn:Disconnect() end) outsideConn = nil end
            if moveConn then pcall(function() moveConn:Disconnect() end) moveConn = nil end
            if SlotDropdownList then pcall(function() SlotDropdownList:Destroy() end) end
            for _, c in pairs(cardButtons) do
                if c.Tracks then
                    for _, track in pairs(c.Tracks) do
                        pcall(function() track:Stop() track:Destroy() end)
                    end
                    table.clear(c.Tracks)
                end
                if c.Track then pcall(function() c.Track:Stop() c.Track:Destroy() end) end
                if c.Viewport then
                    pcall(function() c.Viewport:Destroy() end)
                elseif c.Dummy then
                    pcall(function() c.Dummy:Destroy() end)
                end
            end
            if previewDummy then pcall(function() previewDummy:Destroy() end) end
            if CatalogWindow then pcall(function() CatalogWindow:Destroy() end) end
        end,
        destroy = function(self)
            self:Destroy()
        end
    }

    if lib then
        lib.AnimCatalog = CatalogApi
        lib.AnimCatalogFrame = CatalogWindow
    end
    if library then
        library.AnimCatalog = CatalogApi
        library.AnimCatalogFrame = CatalogWindow
    end
    return CatalogApi
end

-- ============================================================================
-- EMOTE CATALOG IMPLEMENTATION (STANDALONE & 3D DUMMY PREVIEW)
-- ============================================================================
local function build_emote_catalog(lib, Config)
    Config = Config or {}
    local emotes = Config.Emotes or (emote_manager and emote_manager.emotes) or {}
    local selectedEmote = Config.Selected or emotes[1] or nil
    local onSelect = Config.OnSelect or function() end

    local floatParent = resolve_float_parent()
    local existingWindow = nil
    pcall(function()
        existingWindow = floatParent and floatParent:FindFirstChild("EmoteCatalogWindow")
    end)
    if existingWindow then
        pcall(function() existingWindow:Destroy() end)
    end

    local CatalogWindow = Instance.new("CanvasGroup")
    CatalogWindow.Name = "EmoteCatalogWindow"
    CatalogWindow.BackgroundColor3 = get_theme_color("BackgroundColor")
    CatalogWindow.BorderSizePixel = 0
    CatalogWindow.Position = Config.Position or get_docked_position(480, 510)
    CatalogWindow.Size = UDim2.fromOffset(480, 510)
    CatalogWindow.Visible = false
    CatalogWindow.Active = true
    CatalogWindow.GroupTransparency = 1
    CatalogWindow.ZIndex = 120
    CatalogWindow.Parent = floatParent
    if getgenv then getgenv().__v_ctx_emotes = CatalogWindow end

    local winScale = Instance.new("UIScale")
    winScale.Scale = 1
    winScale.Parent = CatalogWindow

    local winCorner = Instance.new("UICorner")
    winCorner.CornerRadius = UDim.new(0, 10)
    winCorner.Parent = CatalogWindow

    local winStroke = Instance.new("UIStroke")
    winStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    winStroke.Color = get_theme_color("OutlineColor")
    winStroke.Thickness = 1
    winStroke.Parent = CatalogWindow

    local ts = TweenService or tween_service or cloneref(game:GetService("TweenService"))
    local is_open = false
    local isClosing = false
    local heartbeat_conn = nil

    local function smoothOpen()
        is_open = true
        isClosing = false
        CatalogWindow.Position = get_docked_position(CatalogWindow.Size.X.Offset, CatalogWindow.Size.Y.Offset, CatalogWindow.Parent)
        CatalogWindow.Visible = true
        winScale.Scale = 0.96
        CatalogWindow.GroupTransparency = 1
        winStroke.Transparency = 1
        local ok = false
        if ts and typeof(ts.Create) == "function" then
            local p_ok = pcall(function()
                ts:Create(CatalogWindow, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 0 }):Play()
                ts:Create(winScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
                ts:Create(winStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 0 }):Play()
            end)
            ok = p_ok
        end
        if not ok then
            CatalogWindow.GroupTransparency = 0
            winStroke.Transparency = 0
            winScale.Scale = 1
        end
    end

    local function smoothClose()
        if not is_open and not CatalogWindow.Visible then return end
        is_open = false
        isClosing = true
        if heartbeat_conn then
            pcall(function() heartbeat_conn:Disconnect() end)
            heartbeat_conn = nil
        end
        local ok = false
        if ts and typeof(ts.Create) == "function" then
            local p_ok = pcall(function()
                ts:Create(CatalogWindow, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 1 }):Play()
                ts:Create(winScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 0.96 }):Play()
                ts:Create(winStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
            end)
            ok = p_ok
        end
        if not ok then
            CatalogWindow.Visible = false
            CatalogWindow.GroupTransparency = 1
            winStroke.Transparency = 1
            winScale.Scale = 1
            isClosing = false
            return
        end
        task.delay(0.2, function()
            if not is_open then
                CatalogWindow.Visible = false
                CatalogWindow.GroupTransparency = 1
                winStroke.Transparency = 1
                winScale.Scale = 1
                isClosing = false
            end
        end)
    end

    local Header = Instance.new("Frame")
    Header.BackgroundTransparency = 1
    Header.Size = UDim2.new(1, 0, 0, 34)
    Header.ZIndex = 121
    Header.Parent = CatalogWindow

    local HeaderIcon = Instance.new("ImageLabel")
    HeaderIcon.BackgroundTransparency = 1
    HeaderIcon.Position = UDim2.new(0, 10, 0.5, -7)
    HeaderIcon.Size = UDim2.fromOffset(14, 14)
    HeaderIcon.ImageColor3 = get_theme_color("AccentColor")
    HeaderIcon.Image = "rbxassetid://6034684937"
    HeaderIcon.ZIndex = 122
    HeaderIcon.Parent = Header

    local HeaderTitle = Instance.new("TextLabel")
    HeaderTitle.BackgroundTransparency = 1
    HeaderTitle.Font = get_theme_font()
    HeaderTitle.Position = UDim2.new(0, 30, 0, 0)
    HeaderTitle.Size = UDim2.new(1, -110, 1, 0)
    HeaderTitle.Text = string.lower(Config.Title or "emotes")
    HeaderTitle.TextColor3 = get_theme_color("FontColor")
    HeaderTitle.TextSize = 13
    HeaderTitle.TextXAlignment = Enum.TextXAlignment.Left
    HeaderTitle.ZIndex = 122
    HeaderTitle.Parent = Header

    local CounterLabel = Instance.new("TextLabel")
    CounterLabel.BackgroundTransparency = 1
    CounterLabel.Font = get_theme_font()
    CounterLabel.AnchorPoint = Vector2.new(1, 0.5)
    CounterLabel.Position = UDim2.new(1, -34, 0.5, 0)
    CounterLabel.Size = UDim2.fromOffset(60, 18)
    CounterLabel.Text = "0/0"
    CounterLabel.TextColor3 = get_theme_color("FontColor")
    CounterLabel.TextTransparency = 0.4
    CounterLabel.TextSize = 11
    CounterLabel.TextXAlignment = Enum.TextXAlignment.Right
    CounterLabel.ZIndex = 122
    CounterLabel.Parent = Header

    local CloseButton = Instance.new("TextButton")
    CloseButton.Name = "CloseButton"
    CloseButton.BackgroundTransparency = 1
    CloseButton.BorderSizePixel = 0
    CloseButton.AnchorPoint = Vector2.new(1, 0.5)
    CloseButton.Position = UDim2.new(1, -6, 0.5, 0)
    CloseButton.Size = UDim2.fromOffset(18, 18)
    CloseButton.AutoButtonColor = false
    CloseButton.Font = Enum.Font.SourceSans
    CloseButton.Text = "×"
    CloseButton.TextColor3 = get_theme_color("FontColor")
    CloseButton.TextSize = 16
    CloseButton.TextTransparency = 0.4
    CloseButton.ZIndex = 123
    CloseButton.Parent = Header

    CloseButton.MouseEnter:Connect(function()
        CloseButton.TextTransparency = 0
        CloseButton.TextColor3 = get_theme_color("RedColor", Color3.fromRGB(255, 65, 65))
    end)
    CloseButton.MouseLeave:Connect(function()
        CloseButton.TextTransparency = 0.4
        CloseButton.TextColor3 = get_theme_color("FontColor")
    end)
    CloseButton.MouseButton1Click:Connect(function()
        smoothClose()
    end)

    make_ui_draggable(CatalogWindow, Header)

    local HeaderDivider = Instance.new("Frame")
    HeaderDivider.BackgroundColor3 = get_theme_color("OutlineColor")
    HeaderDivider.BorderSizePixel = 0
    HeaderDivider.Position = UDim2.new(0, 0, 0, 34)
    HeaderDivider.Size = UDim2.new(1, 0, 0, 1)
    HeaderDivider.ZIndex = 121
    HeaderDivider.Parent = CatalogWindow

    -- Preview Holder (Top 3D Viewport)
    local PreviewHolder = Instance.new("Frame")
    PreviewHolder.BackgroundColor3 = get_theme_color("MainColor")
    PreviewHolder.BorderSizePixel = 0
    PreviewHolder.Position = UDim2.new(0, 10, 0, 38)
    PreviewHolder.Size = UDim2.new(1, -20, 0, 160)
    PreviewHolder.ClipsDescendants = true
    PreviewHolder.ZIndex = 122
    PreviewHolder.Parent = CatalogWindow

    local prevCorner = Instance.new("UICorner")
    prevCorner.CornerRadius = UDim.new(0, 8)
    prevCorner.Parent = PreviewHolder

    local prevStroke = Instance.new("UIStroke")
    prevStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    prevStroke.Color = get_theme_color("OutlineColor")
    prevStroke.Thickness = 1
    prevStroke.Parent = PreviewHolder

    local currentDummyAngle = math.rad(165)
    local isDraggingPreview = false
    local dragStartX = 0
    local dragStartAngle = currentDummyAngle

    local Viewport = Instance.new("ViewportFrame")
    Viewport.BackgroundTransparency = 1
    Viewport.Size = UDim2.new(1, 0, 1, -26)
    Viewport.Position = UDim2.new(0, 0, 0, 0)
    Viewport.ZIndex = 123
    Viewport.Ambient = Color3.fromRGB(220, 220, 220)
    Viewport.LightColor = Color3.fromRGB(255, 255, 255)
    Viewport.LightDirection = Vector3.new(-1, -1.2, -1)
    Viewport.Parent = PreviewHolder

    local WorldModel = Instance.new("WorldModel")
    WorldModel.Parent = Viewport

    local ViewportCam = Instance.new("Camera")
    ViewportCam.FieldOfView = 31
    ViewportCam.CFrame = CFrame.new(Vector3.new(0, 0.1, 9.8), Vector3.new(0, 0.1, 0))
    ViewportCam.Parent = Viewport
    Viewport.CurrentCamera = ViewportCam

    local PreviewBar = Instance.new("Frame")
    PreviewBar.Name = "PreviewBar"
    PreviewBar.BackgroundTransparency = 1
    PreviewBar.Position = UDim2.new(0, 0, 1, -26)
    PreviewBar.Size = UDim2.new(1, 0, 0, 26)
    PreviewBar.ZIndex = 124
    PreviewBar.Parent = PreviewHolder

    local PreviewLabel = Instance.new("TextLabel")
    PreviewLabel.Name = "PreviewLabel"
    PreviewLabel.BackgroundTransparency = 1
    PreviewLabel.Font = get_theme_font()
    PreviewLabel.Position = UDim2.new(0, 8, 0, 0)
    PreviewLabel.Size = UDim2.new(1, -200, 1, 0)
    PreviewLabel.Text = selectedEmote and ("emote: " .. tostring(selectedEmote.name or selectedEmote)) or "search for an emote"
    PreviewLabel.TextColor3 = get_theme_color("FontColor")
    PreviewLabel.TextTransparency = 0.2
    PreviewLabel.TextSize = 11
    PreviewLabel.TextXAlignment = Enum.TextXAlignment.Left
    PreviewLabel.ZIndex = 125
    PreviewLabel.Parent = PreviewBar

    local ActionContainer = Instance.new("Frame")
    ActionContainer.Name = "ActionContainer"
    ActionContainer.BackgroundTransparency = 1
    ActionContainer.Position = UDim2.new(1, -192, 0.5, -10)
    ActionContainer.Size = UDim2.fromOffset(186, 20)
    ActionContainer.ZIndex = 125
    ActionContainer.Parent = PreviewBar

    local actionLayout = Instance.new("UIListLayout")
    actionLayout.FillDirection = Enum.FillDirection.Horizontal
    actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    actionLayout.Padding = UDim.new(0, 4)
    actionLayout.Parent = ActionContainer

    local playCharBtn = Instance.new("TextButton")
    playCharBtn.Name = "PlayBtn"
    playCharBtn.AutoButtonColor = false
    playCharBtn.Font = get_theme_font()
    playCharBtn.Size = UDim2.fromOffset(48, 18)
    playCharBtn.Text = "Start"
    playCharBtn.TextSize = 10
    playCharBtn.BackgroundColor3 = get_theme_color("AccentColor")
    playCharBtn.TextColor3 = Color3.fromRGB(18, 18, 22)
    playCharBtn.ZIndex = 126
    playCharBtn.Parent = ActionContainer

    local pbCorn = Instance.new("UICorner")
    pbCorn.CornerRadius = UDim.new(0, 4)
    pbCorn.Parent = playCharBtn

    local stopCharBtn = Instance.new("TextButton")
    stopCharBtn.Name = "StopBtn"
    stopCharBtn.AutoButtonColor = false
    stopCharBtn.Font = get_theme_font()
    stopCharBtn.Size = UDim2.fromOffset(48, 18)
    stopCharBtn.Text = "Stop"
    stopCharBtn.TextSize = 10
    stopCharBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    stopCharBtn.TextColor3 = get_theme_color("FontColor")
    stopCharBtn.TextTransparency = 0.3
    stopCharBtn.ZIndex = 126
    stopCharBtn.Parent = ActionContainer

    local sbCorn = Instance.new("UICorner")
    sbCorn.CornerRadius = UDim.new(0, 4)
    sbCorn.Parent = stopCharBtn

    local loopCharBtn = Instance.new("TextButton")
    loopCharBtn.Name = "LoopBtn"
    loopCharBtn.AutoButtonColor = false
    loopCharBtn.Font = get_theme_font()
    loopCharBtn.Size = UDim2.fromOffset(68, 18)
    loopCharBtn.Text = (emote_manager.looped and "Loop: ON") or "Loop: OFF"
    loopCharBtn.TextSize = 10
    loopCharBtn.BackgroundColor3 = emote_manager.looped and get_theme_color("AccentColor") or Color3.fromRGB(30, 30, 38)
    loopCharBtn.TextColor3 = emote_manager.looped and Color3.fromRGB(18, 18, 22) or get_theme_color("FontColor")
    loopCharBtn.TextTransparency = emote_manager.looped and 0 or 0.3
    loopCharBtn.ZIndex = 126
    loopCharBtn.Parent = ActionContainer

    local lbCorn = Instance.new("UICorner")
    lbCorn.CornerRadius = UDim.new(0, 4)
    lbCorn.Parent = loopCharBtn

    local activeTrack = nil
    local previewDummy = nil
    local is_creating_dummy = false
    local currentAnimToken = 0
    local cachedTracks = {}
    local cardButtons = {}
    local current_preview_emote = selectedEmote

    local function refresh_dummy()
        if is_creating_dummy then return previewDummy end
        local char = local_player and local_player.Character
        local char_ready = (char and char:FindFirstChildOfClass("Humanoid") and #char:GetChildren() > 0)
        if previewDummy and previewDummy.Parent == WorldModel and previewDummy:FindFirstChildOfClass("Humanoid") then
            if not previewDummy:GetAttribute("__is_fallback") then
                return previewDummy
            end
            if not char_ready then
                return previewDummy
            end
        end
        is_creating_dummy = true
        if previewDummy then
            pcall(function() previewDummy:Destroy() end)
            previewDummy = nil
            activeTrack = nil
        end
        table.clear(cachedTracks)
        WorldModel:ClearAllChildren()
        local ok, dummy = pcall(create_clean_dummy, currentDummyAngle)
        is_creating_dummy = false
        if ok and dummy then
            previewDummy = dummy
            dummy.Parent = WorldModel
        end
        return previewDummy
    end

    local function get_emote_by_name(name)
        if typeof(name) == "table" then return name end
        for _, e in ipairs(emotes) do
            if e.name == name then return e end
        end
        local numId = tonumber(tostring(name):match("%d+"))
        if numId and numId > 1000 then
            return { name = "ID " .. tostring(numId), id = numId }
        end
        return nil
    end

    local play_preview = nil
    play_preview = function(emoteOrName)
        currentAnimToken = currentAnimToken + 1
        local myToken = currentAnimToken

        local emote = get_emote_by_name(emoteOrName)
        if not emote then return end
        current_preview_emote = emote
        PreviewLabel.Text = "emote: " .. tostring(emote.name)

        local dummy = previewDummy
        if not dummy or not dummy.Parent or not dummy:FindFirstChildOfClass("Humanoid") then
            dummy = refresh_dummy()
        end
        if not dummy then return end

        local hum = dummy:FindFirstChildOfClass("Humanoid")
        local animator = hum and (hum:FindFirstChildOfClass("Animator") or hum)
        if not animator then return end

        local numId = emote.id and tostring(emote.id):match("%d+")
        if not numId or numId == "0" then
            if activeTrack then
                pcall(function() activeTrack:Stop(0.05) end)
                activeTrack = nil
            end
            return
        end

        local trackKey = "emote_" .. tostring(numId)
        local track = cachedTracks[trackKey]
        if track and track.Parent then
            if activeTrack and activeTrack ~= track then
                pcall(function() activeTrack:Stop(0.05) end)
            end
            track.Priority = Enum.AnimationPriority.Action
            track.Looped = true
            track:Play(0.05)
            activeTrack = track
            return
        end

        local function load_and_play_preview(playableId)
            if myToken ~= currentAnimToken then return end
            if not dummy or not dummy.Parent then return end
            local curHum = dummy:FindFirstChildOfClass("Humanoid")
            local animator = curHum and (curHum:FindFirstChildOfClass("Animator") or curHum)
            if not animator or not playableId or playableId == "" then return end

            local anim = Instance.new("Animation")
            anim.AnimationId = playableId
            local ok, newTrack = pcall(animator.LoadAnimation, animator, anim)
            if ok and newTrack and myToken == currentAnimToken and dummy and dummy.Parent then
                cachedTracks[trackKey] = newTrack
                newTrack.Priority = Enum.AnimationPriority.Action
                newTrack.Looped = true
                if activeTrack and activeTrack ~= newTrack then
                    pcall(function() activeTrack:Stop(0.05) end)
                end
                newTrack:Play(0.05)
                activeTrack = newTrack
            elseif newTrack then
                pcall(function() newTrack:Destroy() end)
            end
        end

        local cached = resolved_anim_cache[numId]
        if cached then
            load_and_play_preview(cached)
        else
            resolve_playable_anim_id(numId, function(resolvedId)
                load_and_play_preview(resolvedId)
            end)
        end
    end

    playCharBtn.MouseButton1Click:Connect(function()
        local cur = current_preview_emote or get_emote_by_name(selectedEmote)
        if cur and cur.id then
            emote_manager:play(cur.id, cur.name)
        end
    end)

    stopCharBtn.MouseButton1Click:Connect(function()
        emote_manager:stop()
    end)

    loopCharBtn.MouseButton1Click:Connect(function()
        emote_manager:set_looped(not emote_manager.looped)
        local isL = emote_manager.looped
        loopCharBtn.Text = isL and "Loop: ON" or "Loop: OFF"
        loopCharBtn.BackgroundColor3 = isL and get_theme_color("AccentColor") or Color3.fromRGB(30, 30, 38)
        loopCharBtn.TextColor3 = isL and Color3.fromRGB(18, 18, 22) or get_theme_color("FontColor")
        loopCharBtn.TextTransparency = isL and 0 or 0.3
    end)

    -- Interactive 3D rotation in main preview
    Viewport.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDraggingPreview = true
            dragStartX = input.Position.X
            dragStartAngle = currentDummyAngle
        end
    end)
    Viewport.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDraggingPreview = false
        end
    end)
    user_input_service.InputChanged:Connect(function(input)
        if isDraggingPreview and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local deltaX = input.Position.X - dragStartX
            currentDummyAngle = dragStartAngle - deltaX * 0.015
            if previewDummy and previewDummy.PrimaryPart then
                previewDummy:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, currentDummyAngle, 0))
            end
        end
    end)

    -- Search Container
    local SearchContainer = Instance.new("Frame")
    SearchContainer.BackgroundColor3 = get_theme_color("MainColor")
    SearchContainer.BorderSizePixel = 0
    SearchContainer.Position = UDim2.new(0, 10, 0, 204)
    SearchContainer.Size = UDim2.new(1, -20, 0, 26)
    SearchContainer.ZIndex = 122
    SearchContainer.Parent = CatalogWindow

    local searchCorner = Instance.new("UICorner")
    searchCorner.CornerRadius = UDim.new(0, 6)
    searchCorner.Parent = SearchContainer

    local searchStroke = Instance.new("UIStroke")
    searchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    searchStroke.Color = get_theme_color("OutlineColor")
    searchStroke.Thickness = 1
    searchStroke.Parent = SearchContainer

    local SearchIcon = Instance.new("ImageLabel")
    SearchIcon.BackgroundTransparency = 1
    SearchIcon.Position = UDim2.new(0, 6, 0.5, -6)
    SearchIcon.Size = UDim2.fromOffset(12, 12)
    SearchIcon.ImageColor3 = get_theme_color("FontColor")
    SearchIcon.ImageTransparency = 0.5
    SearchIcon.Image = "rbxassetid://6031154871"
    SearchIcon.ZIndex = 123
    SearchIcon.Parent = SearchContainer

    local SearchBox = Instance.new("TextBox")
    SearchBox.BackgroundTransparency = 1
    SearchBox.ClearTextOnFocus = false
    SearchBox.Font = get_theme_font()
    SearchBox.PlaceholderColor3 = Color3.fromRGB(130, 130, 140)
    SearchBox.PlaceholderText = "search marketplace emotes..."
    SearchBox.Position = UDim2.new(0, 24, 0, 0)
    SearchBox.Size = UDim2.new(1, -30, 1, 0)
    SearchBox.Text = ""
    SearchBox.TextColor3 = get_theme_color("FontColor")
    SearchBox.TextSize = 11
    SearchBox.TextXAlignment = Enum.TextXAlignment.Left
    SearchBox.ZIndex = 123
    SearchBox.Parent = SearchContainer

    -- 3-Column Grid Frame
    local GridFrame = Instance.new("ScrollingFrame")
    GridFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    GridFrame.BackgroundTransparency = 1
    GridFrame.BorderSizePixel = 0
    GridFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    GridFrame.ElasticBehavior = Enum.ElasticBehavior.Never
    GridFrame.Position = UDim2.new(0, 10, 0, 236)
    GridFrame.ScrollBarThickness = 3
    GridFrame.ScrollingDirection = Enum.ScrollingDirection.Y
    GridFrame.Size = UDim2.new(1, -20, 1, -242)
    GridFrame.ZIndex = 122
    GridFrame.Parent = CatalogWindow

    local GridLayout = Instance.new("UIGridLayout")
    GridLayout.CellPadding = UDim2.fromOffset(6, 6)
    GridLayout.CellSize = UDim2.fromOffset(124, 96)
    GridLayout.FillDirectionMaxCells = 3
    GridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    GridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    GridLayout.Parent = GridFrame

    local gridPad = Instance.new("UIPadding")
    gridPad.PaddingBottom = UDim.new(0, 6)
    gridPad.PaddingLeft = UDim.new(0, 2)
    gridPad.PaddingRight = UDim.new(0, 2)
    gridPad.PaddingTop = UDim.new(0, 2)
    gridPad.Parent = GridFrame

    local selectedEmoteName = (typeof(selectedEmote) == "table" and selectedEmote.name) or (selectedEmote and tostring(selectedEmote)) or nil

    local populate_card_dummy_fn = nil
    local stop_card_emote_fn = nil
    local play_card_emote_fn = nil

    local function update_selection(name)
        selectedEmoteName = name
        local foundEmote = nil
        local foundCard = nil
        for eName, card in pairs(cardButtons) do
            local isSel = (eName == name)
            if card.Stroke then
                card.Stroke.Color = isSel and get_theme_color("AccentColor") or get_theme_color("OutlineColor")
                card.Stroke.Thickness = isSel and 1.5 or 1
            end
            if card.Label then
                card.Label.TextColor3 = isSel and get_theme_color("AccentColor") or get_theme_color("FontColor")
            end
            if isSel then
                foundEmote = card.Emote
                foundCard = card
            end
        end
        if foundCard then
            play_card_emote_fn(foundCard)
        end
        if foundEmote then
            play_preview(foundEmote)
        end
    end

    local hoveredCardName = nil

    local function restore_selected_preview()
        hoveredCardName = nil
        for eName, c in pairs(cardButtons) do
            if eName ~= selectedEmoteName and c.Frame then
                c.Frame.BackgroundColor3 = get_theme_color("MainColor")
            end
        end
        local cur = get_emote_by_name(selectedEmoteName)
        if cur then
            local selCard = cardButtons[selectedEmoteName]
            if selCard then
                play_card_emote_fn(selCard)
            end
            play_preview(cur)
        end
    end

    local function get_dummy_template()
        return build_master_dummy_template()
    end

    local card_angle = math.rad(165)

    local function populate_card_dummy(card)
        if not card or not card.Holder or not card.Holder.Parent then return end
        local char = local_player and local_player.Character
        local char_ready = (char and char:FindFirstChildOfClass("Humanoid") and #char:GetChildren() > 0)
        if card.Dummy and card.Dummy.Parent == card.World then
            if not card.Dummy:GetAttribute("__is_fallback") or not char_ready then
                return
            end
        end
        if card.Dummy then
            pcall(function() card.Dummy:Destroy() end)
            card.Dummy = nil
        end
        if card.Track then
            pcall(function() card.Track:Stop() card.Track:Destroy() end)
            card.Track = nil
        end
        local template = get_dummy_template()
        if not template then return end
        local ok, clone = pcall(template.Clone, template)
        if not ok or not clone then return end
        clone.Name = "PreviewAvatar"
        pcall(function()
            local hrp = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart
            if hrp then
                clone.PrimaryPart = hrp
                clone:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, card_angle, 0))
            end
        end)
        clone.Parent = card.World
        card.Dummy = clone
    end

    local function stop_card_emote(card)
        if not card then return end
        card.Seq = (card.Seq or 0) + 1
        if card.Track then
            pcall(function() card.Track:Stop(0.1) end)
        end
    end

    local function play_card_emote(card)
        if not card or not card.Emote then return end
        card.Seq = (card.Seq or 0) + 1
        local seq = card.Seq
        local num = card.Emote.id and tostring(card.Emote.id):match("%d+")
        if not num or num == "0" then return end
        if card.Track then
            local playing = false
            pcall(function() playing = card.Track.IsPlaying end)
            if playing then return end
        end
        if not card.Dummy or not card.Dummy.Parent then
            populate_card_dummy(card)
        end
        if card.Track and card.Track.Parent then
            card.Track.Priority = Enum.AnimationPriority.Action
            card.Track.Looped = true
            card.Track:Play(0.05)
            return
        end

        local function load_and_play_card(playableId)
            if seq ~= card.Seq or not card.Dummy or not card.Dummy.Parent then return end
            local hum = card.Dummy and card.Dummy:FindFirstChildOfClass("Humanoid")
            local animator = hum and (hum:FindFirstChildOfClass("Animator") or hum)
            if not animator or not playableId or playableId == "" then return end

            local anim = Instance.new("Animation")
            anim.AnimationId = playableId
            local ok, track = pcall(animator.LoadAnimation, animator, anim)
            if ok and track and seq == card.Seq and card.Dummy and card.Dummy.Parent then
                card.Track = track
                track.Priority = Enum.AnimationPriority.Action
                track.Looped = true
                track:Play(0.05)
            elseif track then
                pcall(function() track:Destroy() end)
            end
        end

        local cached = resolved_anim_cache[num]
        if cached then
            load_and_play_card(cached)
        else
            resolve_playable_anim_id(num, function(resolvedId)
                load_and_play_card(resolvedId)
            end)
        end
    end

    populate_card_dummy_fn = populate_card_dummy
    stop_card_emote_fn = stop_card_emote
    play_card_emote_fn = play_card_emote

    local function emote_card_in_view(card)
        local f = card and card.Frame
        if not f or not f.Visible or not CatalogWindow.Visible then return false end
        local gs = GridFrame.AbsoluteSize
        local cs = f.AbsoluteSize
        if gs.Y <= 0 or cs.Y <= 0 then return false end
        local gy = GridFrame.AbsolutePosition.Y
        local cy = f.AbsolutePosition.Y
        return (cy + cs.Y > gy - 10) and (cy < gy + gs.Y + 10)
    end

    local is_updating_visible = false
    local function update_visible_cards()
        if not CatalogWindow.Visible then
            for _, c in pairs(cardButtons) do
                if c.Track then
                    pcall(function() c.Track:Stop(0.05) end)
                end
            end
            return
        end
        if is_updating_visible then return end
        is_updating_visible = true
        task.defer(function()
            is_updating_visible = false
            if not CatalogWindow.Visible then return end
            local active_count = 0
            local max_active = 6
            for _, c in pairs(cardButtons) do
                if c.Frame and c.Frame.Visible and emote_card_in_view(c) then
                    if active_count < max_active then
                        active_count = active_count + 1
                        local card = c
                        local delay_time = (active_count - 1) * 0.04
                        task.delay(delay_time, function()
                            if CatalogWindow.Visible and card.Frame and card.Frame.Visible and emote_card_in_view(card) then
                                play_card_emote(card)
                            end
                        end)
                    else
                        if c.Track then
                            pcall(function() c.Track:Stop(0.05) end)
                        end
                    end
                else
                    if c.Track then
                        pcall(function() c.Track:Stop(0.05) end)
                    end
                end
            end
        end)
    end

    local function add_emote_card(emote, order)
        local eName = emote.name or ("Emote " .. tostring(order or 1))
        if cardButtons[eName] then
            local existing = cardButtons[eName]
            existing.Emote = emote
            if existing.Track then
                pcall(function() existing.Track:Stop() existing.Track:Destroy() end)
                existing.Track = nil
            end
            return existing
        end

        local Card = Instance.new("TextButton")
        Card.Name = eName
        Card.BackgroundColor3 = get_theme_color("MainColor")
        Card.BorderSizePixel = 0
        Card.LayoutOrder = order or (#emotes + 10)
        Card.Size = UDim2.fromOffset(124, 96)
        Card.Text = ""
        Card.AutoButtonColor = false
        Card.ZIndex = 123
        Card.Parent = GridFrame

        local cCorn = Instance.new("UICorner")
        cCorn.CornerRadius = UDim.new(0, 8)
        cCorn.Parent = Card

        local Stroke = Instance.new("UIStroke")
        Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        Stroke.Color = (eName == selectedEmoteName) and get_theme_color("AccentColor") or get_theme_color("OutlineColor")
        Stroke.Thickness = (eName == selectedEmoteName) and 1.5 or 1
        Stroke.Parent = Card

        local ImgHolder = Instance.new("Frame")
        ImgHolder.BackgroundColor3 = get_theme_color("BackgroundColor")
        ImgHolder.BorderSizePixel = 0
        ImgHolder.Position = UDim2.new(0, 4, 0, 4)
        ImgHolder.Size = UDim2.new(1, -8, 0, 68)
        ImgHolder.ClipsDescendants = true
        ImgHolder.ZIndex = 124
        ImgHolder.Parent = Card

        local ihCorn = Instance.new("UICorner")
        ihCorn.CornerRadius = UDim.new(0, 6)
        ihCorn.Parent = ImgHolder

        local CardView = Instance.new("ViewportFrame")
        CardView.Name = "EmoteViewport"
        CardView.BackgroundTransparency = 1
        CardView.Size = UDim2.fromScale(1, 1)
        CardView.ZIndex = 124
        CardView.Ambient = Color3.fromRGB(220, 220, 220)
        CardView.LightColor = Color3.fromRGB(255, 255, 255)
        CardView.LightDirection = Vector3.new(-1, -1.2, -1)
        CardView.Parent = ImgHolder

        local CardWorld = Instance.new("WorldModel")
        CardWorld.Parent = CardView

        local CardCam = Instance.new("Camera")
        CardCam.FieldOfView = 28
        CardCam.CFrame = CFrame.new(Vector3.new(0, 1.4, 8.4), Vector3.new(0, 0.7, 0))
        CardCam.Parent = CardView
        CardView.CurrentCamera = CardCam

        local NameLabel = Instance.new("TextLabel")
        NameLabel.BackgroundTransparency = 1
        NameLabel.Font = get_theme_font()
        NameLabel.Position = UDim2.new(0, 4, 1, -22)
        NameLabel.Size = UDim2.new(1, -8, 0, 18)
        NameLabel.Text = eName
        NameLabel.TextColor3 = (eName == selectedEmoteName) and get_theme_color("AccentColor") or get_theme_color("FontColor")
        NameLabel.TextSize = 11
        NameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        NameLabel.ZIndex = 124
        NameLabel.Parent = Card

        local cardData = {
            Frame = Card,
            Stroke = Stroke,
            Label = NameLabel,
            Emote = emote,
            Holder = ImgHolder,
            Viewport = CardView,
            World = CardWorld,
            Cam = CardCam,
            Dummy = nil,
            Track = nil,
            Seq = 0,
        }
        cardButtons[eName] = cardData

        Card.MouseEnter:Connect(function()
            hoveredCardName = eName
            for otherName, c in pairs(cardButtons) do
                if otherName ~= selectedEmoteName and otherName ~= eName and c.Frame then
                    c.Frame.BackgroundColor3 = get_theme_color("MainColor")
                end
            end
            if selectedEmoteName ~= eName then
                Card.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
            end
            play_card_emote(cardData)
            play_preview(emote)
        end)
        Card.MouseLeave:Connect(function()
            if selectedEmoteName ~= eName then
                Card.BackgroundColor3 = get_theme_color("MainColor")
            end
            if hoveredCardName == eName then
                hoveredCardName = nil
                task.delay(0.04, function()
                    if not hoveredCardName then
                        restore_selected_preview()
                    end
                end)
            end
        end)

        Card.MouseButton1Click:Connect(function()
            update_selection(eName)
            if emote and emote.id then
                emote_manager:play(emote.id, emote.name)
            end
            if onSelect then
                onSelect(emote)
            end
        end)
        return cardData
    end

    local function filter_cards(query)
        local rawQuery = string.lower(query or "")
        local trimmed = rawQuery:match("^%s*(.-)%s*$") or ""
        local matchCount = 0

        for eName, card in pairs(cardButtons) do
            local match = (trimmed == "") or (string.find(string.lower(eName), trimmed, 1, true) ~= nil)
            card.Frame.Visible = match
            if match then
                matchCount = matchCount + 1
            elseif card.Track then
                stop_card_emote(card)
            end
        end

        local total = 0
        for _ in pairs(cardButtons) do total = total + 1 end

        CounterLabel.Text = string.format("%d/%d", matchCount, total)
    end

    local catalogSearchToken = 0
    local function search_marketplace_emotes(query)
        catalogSearchToken = catalogSearchToken + 1
        local myToken = catalogSearchToken
        local rawQuery = string.lower(query or "")
        local trimmed = rawQuery:match("^%s*(.-)%s*$") or ""
        if #trimmed < 2 or tonumber(trimmed) then return end

        task.spawn(function()
            if myToken ~= catalogSearchToken then return end
            local aes = cloneref(game:GetService("AvatarEditorService"))
            local p = CatalogSearchParams.new()
            p.AssetTypes = { Enum.AvatarAssetType.EmoteAnimation }
            p.SearchKeyword = trimmed

            local ok, pages = pcall(function() return aes:SearchCatalogAsync(p) end)
            if not ok or not pages or typeof(pages) ~= "Instance" or not pages:IsA("Pages") or myToken ~= catalogSearchToken then return end

            local ok_page, page = pcall(function() return pages:GetCurrentPage() end)
            if not ok_page or not page or type(page) ~= "table" then return end
            for i, item in ipairs(page) do
                if myToken ~= catalogSearchToken or i > 12 then break end
                local eName = item.Name
                local eId = item.Id
                local newEmote = { name = eName, id = eId, assetId = eId }
                emote_manager:register_emote(newEmote)
                local cardObj = add_emote_card(newEmote, #emotes + i)
                if cardObj and cardObj.Frame then
                    cardObj.Frame.Visible = true
                end
            end
            if myToken == catalogSearchToken then
                filter_cards(trimmed)
                update_visible_cards()
                if #page > 0 and (not selectedEmoteName or selectedEmoteName == "" or (current_preview_emote and tostring(current_preview_emote.name):find("^ID "))) then
                    local firstItem = page[1]
                    local firstEmote = { name = firstItem.Name, id = firstItem.Id, assetId = firstItem.Id }
                    update_selection(firstEmote.name)
                end
            end
        end)
    end

    local search_debounce_token = 0
    local function on_search_changed()
        local q = SearchBox.Text:gsub("^%s*(.-)%s*$", "%1")
        local num_id = tonumber(q)
        if num_id and num_id > 1000 then
            local custom_emote = { name = "ID " .. tostring(num_id), id = num_id, assetId = num_id }
            emote_manager:register_emote(custom_emote)
            local card = add_emote_card(custom_emote, 0)
            if card and card.Frame then
                card.Frame.Visible = true
            end
            update_selection(custom_emote.name)
        end
        filter_cards(q)
        update_visible_cards()

        search_debounce_token = search_debounce_token + 1
        local curDeb = search_debounce_token
        if #q >= 2 and not num_id then
            task.delay(0.35, function()
                if curDeb == search_debounce_token and CatalogWindow.Visible then
                    search_marketplace_emotes(q)
                end
            end)
        end
    end

    SearchBox:GetPropertyChangedSignal("Text"):Connect(on_search_changed)
    SearchBox.FocusLost:Connect(function()
        local q = SearchBox.Text:gsub("^%s*(.-)%s*$", "%1")
        local num_id = tonumber(q)
        if num_id and num_id > 1000 then
            local custom_emote = { name = "ID " .. tostring(num_id), id = num_id, assetId = num_id }
            emote_manager:register_emote(custom_emote)
            local card = add_emote_card(custom_emote, 0)
            if card and card.Frame then
                card.Frame.Visible = true
            end
            update_selection(custom_emote.name)
        end
        filter_cards(q)
        update_visible_cards()
        if #q >= 2 and not num_id then
            search_marketplace_emotes(q)
        end
    end)

    GridFrame.MouseLeave:Connect(function()
        task.delay(0.04, function()
            if not hoveredCardName then
                restore_selected_preview()
            end
        end)
    end)

    CatalogWindow.MouseLeave:Connect(function()
        restore_selected_preview()
    end)

    local moveConn = user_input_service.InputChanged:Connect(function(input)
        if not CatalogWindow.Visible then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            if hoveredCardName then
                local mPos = input.Position
                local wPos = CatalogWindow.AbsolutePosition
                local wSize = CatalogWindow.AbsoluteSize
                if mPos.X < wPos.X or mPos.X > wPos.X + wSize.X or mPos.Y < wPos.Y or mPos.Y > wPos.Y + wSize.Y then
                    restore_selected_preview()
                end
            end
        end
    end)

    CatalogWindow:GetPropertyChangedSignal("Visible"):Connect(function()
        if not CatalogWindow.Visible then
            for _, c in pairs(cardButtons) do
                if c.Track then
                    pcall(function() c.Track:Stop() end)
                end
            end
        else
            task.delay(0.15, update_visible_cards)
        end
    end)

    local scroll_deb = 0
    GridFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        scroll_deb = scroll_deb + 1
        local cur = scroll_deb
        task.delay(0.1, function()
            if cur ~= scroll_deb then return end
            if not CatalogWindow.Visible then return end
            update_visible_cards()
        end)
    end)

    pcall(refresh_dummy)
    pcall(function() update_selection(selectedEmoteName) end)
    pcall(function() filter_cards("") end)
    task.delay(0.15, update_visible_cards)

    local lastOpenTime = 0

    local function check_parent_liveness()
        if not CatalogWindow.Visible then
            if heartbeat_conn then heartbeat_conn:Disconnect() heartbeat_conn = nil end
            return
        end
        local is_open = true
        if library and library.Toggled ~= nil then
            if not library.Toggled then is_open = false end
        end
        local mf = (lib and lib.MainFrame) or (library and library.MainFrame) or (window and window.MainFrame) or (library and library.ScreenGui and library.ScreenGui:FindFirstChild("Main", true))
        if mf then
            if not mf.Visible or (mf:IsA("CanvasGroup") and mf.GroupTransparency >= 0.75) then
                is_open = false
            end
        end
        if not is_open then
            smoothClose()
        end
    end

    local outsideConn = user_input_service.InputBegan:Connect(function(input)
        if not CatalogWindow.Visible or isClosing then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if os.clock() - lastOpenTime < 0.25 then return end
            local mousePos = input.Position
            local winPos = CatalogWindow.AbsolutePosition
            local winSize = CatalogWindow.AbsoluteSize
            local inWin = (mousePos.X >= winPos.X and mousePos.X <= winPos.X + winSize.X and mousePos.Y >= winPos.Y and mousePos.Y <= winPos.Y + winSize.Y)
            if inWin then return end

            local mf = (lib and lib.MainFrame) or (library and library.MainFrame) or (window and window.MainFrame) or (library and library.ScreenGui and library.ScreenGui:FindFirstChild("Main", true))
            if mf and mf.Visible then
                local mfPos = mf.AbsolutePosition
                local mfSize = mf.AbsoluteSize
                local inMf = (mousePos.X >= mfPos.X and mousePos.X <= mfPos.X + mfSize.X and mousePos.Y >= mfPos.Y and mousePos.Y <= mfPos.Y + mfSize.Y)
                if inMf then return end
            end

            smoothClose()
        end
    end)

    local CatalogApi = {
        Frame = CatalogWindow,
        Open = function(self)
            lastOpenTime = os.clock()
            local animWin = (library and library.AnimCatalogFrame) or (lib and lib.AnimCatalogFrame)
            if not animWin then
                local cg = cloneref(game:GetService("CoreGui"))
                local pg = local_player and local_player:FindFirstChildOfClass("PlayerGui")
                animWin = (cg and cg:FindFirstChild("AnimCatalogWindow", true)) or (pg and pg:FindFirstChild("AnimCatalogWindow", true))
            end
            if animWin then
                if library and library.AnimCatalog and library.AnimCatalog.Close then
                    pcall(function() library.AnimCatalog:Close() end)
                elseif anim_ui and anim_ui.close then
                    pcall(function() anim_ui:close() end)
                else
                    pcall(function() animWin.Visible = false end)
                end
            end

            local espWin = (library and library.ESPPreviewFrame) or (lib and lib.ESPPreviewFrame)
            if not espWin then
                local cg = cloneref(game:GetService("CoreGui"))
                local pg = local_player and local_player:FindFirstChildOfClass("PlayerGui")
                espWin = (cg and cg:FindFirstChild("ESPPreviewWindow", true)) or (pg and pg:FindFirstChild("ESPPreviewWindow", true))
            end
            if espWin then
                if library and library.ESPPreview and library.ESPPreview.Close then
                    pcall(function() library.ESPPreview:Close() end)
                elseif lib and lib.ESPPreview and lib.ESPPreview.Close then
                    pcall(function() lib.ESPPreview:Close() end)
                else
                    pcall(function() espWin.Visible = false end)
                end
            end

            local p = resolve_float_parent()
            if p and CatalogWindow.Parent ~= p then
                CatalogWindow.Parent = p
            end
            CatalogWindow.Position = get_docked_position(480, 510, CatalogWindow.Parent)
            CatalogWindow.ZIndex = 120
            smoothOpen()
            if not heartbeat_conn then
                heartbeat_conn = run_service.Heartbeat:Connect(check_parent_liveness)
            end
            if not previewDummy or not previewDummy.Parent or previewDummy:GetAttribute("__is_fallback") then
                pcall(refresh_dummy)
            end
            task.delay(0.15, update_visible_cards)
            local cur = get_emote_by_name(selectedEmoteName)
            if cur then
                pcall(function()
                    play_preview(cur)
                end)
            end
        end,
        Close = function(self)
            for _, c in pairs(cardButtons) do
                if c.Track then
                    pcall(function() c.Track:Stop() end)
                end
            end
            smoothClose()
        end,
        Toggle = function(self)
            if is_open or (CatalogWindow.Visible and not isClosing) then
                self:Close()
            else
                self:Open()
            end
        end,
        toggle = function(self) self:Toggle() end,
        open = function(self) self:Open() end,
        close = function(self) self:Close() end,
        SetVisible = function(self, val)
            if val then self:Open() else self:Close() end
        end,
        Select = function(self, emoteName)
            update_selection(emoteName)
        end,
        GetSelected = function(self)
            return selectedEmoteName
        end,
        Filter = function(self, q)
            SearchBox.Text = q or ""
            filter_cards(q or "")
        end,
        Destroy = function(self)
            if heartbeat_conn then pcall(function() heartbeat_conn:Disconnect() end) heartbeat_conn = nil end
            if outsideConn then pcall(function() outsideConn:Disconnect() end) outsideConn = nil end
            if moveConn then pcall(function() moveConn:Disconnect() end) moveConn = nil end
            for _, c in pairs(cardButtons) do
                if c.Track then pcall(function() c.Track:Stop() c.Track:Destroy() end) end
                if c.Viewport then
                    pcall(function() c.Viewport:Destroy() end)
                elseif c.Dummy then
                    pcall(function() c.Dummy:Destroy() end)
                end
            end
            if previewDummy then pcall(function() previewDummy:Destroy() end) end
            if CatalogWindow then pcall(function() CatalogWindow:Destroy() end) end
        end,
        destroy = function(self)
            self:Destroy()
        end
    }

    if lib then
        lib.EmoteCatalog = CatalogApi
        lib.EmoteCatalogFrame = CatalogWindow
    end
    if library then
        library.EmoteCatalog = CatalogApi
        library.EmoteCatalogFrame = CatalogWindow
    end
    return CatalogApi
end

local BOX_GRADIENT_B64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAABkCAYAAABHLFpgAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAABTSURBVChTdU/LDsAwCGJu1/3/59rUC5HAhaA8bNHdfwF4LrwbagN3wgakwMVc4ttCTLhxmKjOIma5S5VfiC0TE180R8aRIAJvuJfGGHcsoHoZ6gCUSgTCpTUDpwAAAABJRU5ErkJggg=="
local HEALTH_GRADIENT_B64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAACACAYAAADK+QP0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAACUSURBVChTbVHRFQMhDFLjEA7T/ecqoXBRe3woJIjm2dZanwH0XLABIyLEDLJdls+ypYznmCxkB2Q22GUMa+wmAUPcLr1gy+JbA9gZfWQV5RoujWhnCrtjzDnVsLkWvpRRnPeyUNZslLooxSMvVvIKUCggn3HdoQFL5v4LBd7yCDUqwGcrhVCe8efzw6+U3WKcX9H7F7u/BOHzO9gQAAAAAElFTkSuQmCC"

local function safe_base64_decode(data)
    if typeof(base64_decode) == "function" then
        local ok, res = pcall(base64_decode, data)
        if ok and res and #res > 0 then return res end
    end
    if typeof(crypt) == "table" and typeof(crypt.base64decode) == "function" then
        local ok, res = pcall(crypt.base64decode, data)
        if ok and res and #res > 0 then return res end
    end
    if typeof(crypt) == "table" and typeof(crypt.base64_decode) == "function" then
        local ok, res = pcall(crypt.base64_decode, data)
        if ok and res and #res > 0 then return res end
    end
    if bit32 then
        local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
        data = string.gsub(data, '[^'..b..'=]', '')
        return (data:gsub('....', function(four)
            local t = {}
            for i = 1, 4 do
                local byte = four:byte(i)
                if byte >= 65 and byte <= 90 then t[i] = byte - 65
                elseif byte >= 97 and byte <= 122 then t[i] = byte - 71
                elseif byte >= 48 and byte <= 57 then t[i] = byte + 4
                elseif byte == 43 then t[i] = 62
                elseif byte == 47 then t[i] = 63
                elseif byte == 61 then t[i] = 0
                else t[i] = 0
                end
            end
            local n = bit32.lshift(t[1], 18) + bit32.lshift(t[2], 12) + bit32.lshift(t[3], 6) + t[4]
            local out = string.char(bit32.band(bit32.rshift(n, 16), 255))
            if four:sub(3, 3) ~= '=' then
                out = out .. string.char(bit32.band(bit32.rshift(n, 8), 255))
            end
            if four:sub(4, 4) ~= '=' then
                out = out .. string.char(bit32.band(n, 255))
            end
            return out
        end))
    end
    return ""
end

local box_gradient_raw = safe_base64_decode(BOX_GRADIENT_B64)
local health_gradient_raw = safe_base64_decode(HEALTH_GRADIENT_B64)

local box_gradient_asset = ""
local health_gradient_asset = ""
pcall(function()
    if not isfolder("vantage") then makefolder("vantage") end
    if not isfolder("vantage/assets") then makefolder("vantage/assets") end
    writefile("vantage/assets/box_gradient.png", box_gradient_raw)
    writefile("vantage/assets/health_gradient.png", health_gradient_raw)
    if typeof(getcustomasset) == "function" then
        box_gradient_asset = getcustomasset("vantage/assets/box_gradient.png")
        health_gradient_asset = getcustomasset("vantage/assets/health_gradient.png")
    end
end)

-- ============================================================================
-- ESP PREVIEW IMPLEMENTATION (STANDALONE & DOCKED)
-- ============================================================================
local function build_esp_preview(lib, Config)
    Config = Config or {}
    local PreviewWindow = Instance.new("CanvasGroup")
    PreviewWindow.Name = "ESPPreviewWindow"
    PreviewWindow.BackgroundColor3 = get_theme_color("BackgroundColor")
    PreviewWindow.BorderSizePixel = 0
    PreviewWindow.Position = Config.Position or get_docked_position(230, 385)
    PreviewWindow.Size = UDim2.fromOffset(230, 385)
    PreviewWindow.Visible = false
    PreviewWindow.Active = true
    PreviewWindow.GroupTransparency = 1
    PreviewWindow.ZIndex = 120
    PreviewWindow.Parent = resolve_float_parent()

    local winScale = Instance.new("UIScale")
    winScale.Scale = 1
    winScale.Parent = PreviewWindow

    local winCorner = Instance.new("UICorner")
    winCorner.CornerRadius = UDim.new(0, 12)
    winCorner.Parent = PreviewWindow

    local winStroke = Instance.new("UIStroke")
    winStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    winStroke.Color = get_theme_color("OutlineColor")
    winStroke.Thickness = 1
    winStroke.Parent = PreviewWindow

    local ts = TweenService or tween_service or cloneref(game:GetService("TweenService"))
    local is_open = false
    local isClosing = false
    local heartbeat_conn = nil

    local function smoothOpen()
        is_open = true
        isClosing = false
        PreviewWindow.Position = get_docked_position(PreviewWindow.Size.X.Offset, PreviewWindow.Size.Y.Offset, PreviewWindow.Parent)
        PreviewWindow.Visible = true
        winScale.Scale = 0.96
        PreviewWindow.GroupTransparency = 1
        winStroke.Transparency = 1
        local ok = false
        if ts and typeof(ts.Create) == "function" then
            local p_ok = pcall(function()
                ts:Create(PreviewWindow, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 0 }):Play()
                ts:Create(winScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
                ts:Create(winStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 0 }):Play()
            end)
            ok = p_ok
        end
        if not ok then
            PreviewWindow.GroupTransparency = 0
            winStroke.Transparency = 0
            winScale.Scale = 1
        end
    end

    local function smoothClose()
        if not is_open and not PreviewWindow.Visible then return end
        is_open = false
        isClosing = true
        if heartbeat_conn then
            pcall(function() heartbeat_conn:Disconnect() end)
            heartbeat_conn = nil
        end
        local ok = false
        if ts and typeof(ts.Create) == "function" then
            local p_ok = pcall(function()
                ts:Create(PreviewWindow, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 1 }):Play()
                ts:Create(winScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 0.96 }):Play()
                ts:Create(winStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
            end)
            ok = p_ok
        end
        if not ok then
            PreviewWindow.Visible = false
            PreviewWindow.GroupTransparency = 1
            winStroke.Transparency = 1
            winScale.Scale = 1
            isClosing = false
            return
        end
        task.delay(0.2, function()
            if not is_open then
                PreviewWindow.Visible = false
                PreviewWindow.GroupTransparency = 1
                winStroke.Transparency = 1
                winScale.Scale = 1
                isClosing = false
            end
        end)
    end

    local Header = Instance.new("Frame")
    Header.BackgroundTransparency = 1
    Header.Size = UDim2.new(1, 0, 0, 34)
    Header.ZIndex = 121
    Header.Parent = PreviewWindow

    local HeaderIcon = Instance.new("ImageLabel")
    HeaderIcon.BackgroundTransparency = 1
    HeaderIcon.Position = UDim2.new(0, 10, 0.5, -7)
    HeaderIcon.Size = UDim2.fromOffset(14, 14)
    HeaderIcon.ImageColor3 = get_theme_color("AccentColor")
    HeaderIcon.Image = "rbxassetid://6034684937"
    HeaderIcon.ZIndex = 122
    HeaderIcon.Parent = Header

    local HeaderTitle = Instance.new("TextLabel")
    HeaderTitle.BackgroundTransparency = 1
    HeaderTitle.Font = get_theme_font()
    HeaderTitle.Position = UDim2.new(0, 30, 0, 0)
    HeaderTitle.Size = UDim2.new(1, -64, 1, 0)
    HeaderTitle.Text = string.lower(Config.Title or "esp preview")
    HeaderTitle.TextColor3 = get_theme_color("FontColor")
    HeaderTitle.TextSize = 13
    HeaderTitle.TextXAlignment = Enum.TextXAlignment.Left
    HeaderTitle.ZIndex = 122
    HeaderTitle.Parent = Header

    local CloseButton = Instance.new("TextButton")
    CloseButton.Name = "CloseButton"
    CloseButton.BackgroundTransparency = 1
    CloseButton.BorderSizePixel = 0
    CloseButton.AnchorPoint = Vector2.new(1, 0.5)
    CloseButton.Position = UDim2.new(1, -8, 0.5, 0)
    CloseButton.Size = UDim2.fromOffset(18, 18)
    CloseButton.AutoButtonColor = false
    CloseButton.Font = get_theme_font()
    CloseButton.Text = "×"
    CloseButton.TextColor3 = get_theme_color("FontColor")
    CloseButton.TextSize = 18
    CloseButton.TextTransparency = 0.4
    CloseButton.ZIndex = 123
    CloseButton.Parent = Header

    CloseButton.MouseEnter:Connect(function()
        CloseButton.TextTransparency = 0
        CloseButton.TextColor3 = get_theme_color("RedColor", Color3.fromRGB(255, 65, 65))
    end)
    CloseButton.MouseLeave:Connect(function()
        CloseButton.TextTransparency = 0.4
        CloseButton.TextColor3 = get_theme_color("FontColor")
    end)
    CloseButton.MouseButton1Click:Connect(function()
        smoothClose()
    end)

    make_ui_draggable(PreviewWindow, Header)

    local HeaderDivider = Instance.new("Frame")
    HeaderDivider.BackgroundColor3 = get_theme_color("OutlineColor")
    HeaderDivider.BorderSizePixel = 0
    HeaderDivider.Position = UDim2.new(0, 0, 0, 34)
    HeaderDivider.Size = UDim2.new(1, 0, 0, 1)
    HeaderDivider.ZIndex = 121
    HeaderDivider.Parent = PreviewWindow

    local Canvas = Instance.new("Frame")
    Canvas.BackgroundColor3 = get_theme_color("MainColor")
    Canvas.BorderSizePixel = 0
    Canvas.Position = UDim2.new(0, 10, 0, 42)
    Canvas.Size = UDim2.new(1, -20, 1, -50)
    Canvas.ClipsDescendants = true
    Canvas.ZIndex = 122
    Canvas.Parent = PreviewWindow

    local canCorner = Instance.new("UICorner")
    canCorner.CornerRadius = UDim.new(0, 8)
    canCorner.Parent = Canvas

    local canStroke = Instance.new("UIStroke")
    canStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    canStroke.Color = get_theme_color("OutlineColor")
    canStroke.Thickness = 1
    canStroke.Parent = Canvas

    local Viewport = Instance.new("ViewportFrame")
    Viewport.BackgroundTransparency = 1
    Viewport.Size = UDim2.new(1, 0, 1, 0)
    Viewport.Position = UDim2.new(0, 0, 0, 0)
    Viewport.ZIndex = 123
    Viewport.Ambient = Color3.fromRGB(220, 220, 220)
    Viewport.LightColor = Color3.fromRGB(255, 255, 255)
    Viewport.LightDirection = Vector3.new(-1, -1.2, -1)
    Viewport.Parent = Canvas

    local WorldModel = Instance.new("WorldModel")
    WorldModel.Parent = Viewport

    local ViewportCam = Instance.new("Camera")
    ViewportCam.FieldOfView = 36
    ViewportCam.CFrame = CFrame.new(Vector3.new(0, -0.48, 11.2), Vector3.new(0, -0.48, 0))
    ViewportCam.Parent = Viewport
    Viewport.CurrentCamera = ViewportCam

    local previewDummy = nil
    local original_parts_data = {}
    local original_clothing_data = {}

    local function create_esp_dummy()
        local dummy = nil
        pcall(function()
            local desc = players:GetHumanoidDescriptionFromUserId(local_player.UserId)
            dummy = players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
        end)
        if not dummy or not dummy:FindFirstChildOfClass("Humanoid") then
            if dummy then pcall(function() dummy:Destroy() end) dummy = nil end
            local char = local_player.Character
            if char and #char:GetChildren() > 0 then
                local wasArch = char.Archivable
                char.Archivable = true
                pcall(function() dummy = char:Clone() end)
                char.Archivable = wasArch
            end
        end
        if not dummy or not dummy:FindFirstChildOfClass("Humanoid") then
            if dummy then pcall(function() dummy:Destroy() end) end
            dummy = Instance.new("Model")
            dummy.Name = "PreviewAvatar"
            local hum = Instance.new("Humanoid", dummy)
            hum.RigType = Enum.HumanoidRigType.R15
            local hrp = Instance.new("Part")
            hrp.Name = "HumanoidRootPart"
            hrp.Size = Vector3.new(2, 2, 1)
            hrp.Parent = dummy
            dummy.PrimaryPart = hrp
        end

        dummy.Name = "PreviewAvatar"
        original_parts_data = {}
        original_clothing_data = {}

        pcall(function()
            for _, desc in ipairs(dummy:GetDescendants()) do
                if desc:IsA("LuaSourceContainer") or desc:IsA("Sound") or desc:IsA("ParticleEmitter")
                    or desc:IsA("Beam") or desc:IsA("Trail") or desc:IsA("Tool")
                    or desc:IsA("Highlight") or desc:IsA("BillboardGui") or desc:IsA("SurfaceGui") then
                    desc:Destroy()
                elseif desc:IsA("BasePart") then
                    desc.CanCollide = false
                    desc.CanTouch = false
                    desc.CanQuery = false
                    desc.Anchored = (desc.Name == "HumanoidRootPart")
                    table.insert(original_parts_data, {
                        part = desc,
                        color = desc.Color,
                        material = desc.Material,
                        transparency = desc.Transparency
                    })
                elseif desc:IsA("Shirt") then
                    table.insert(original_clothing_data, { instance = desc, prop = "ShirtTemplate", val = desc.ShirtTemplate })
                elseif desc:IsA("Pants") then
                    table.insert(original_clothing_data, { instance = desc, prop = "PantsTemplate", val = desc.PantsTemplate })
                elseif desc:IsA("ShirtGraphic") then
                    table.insert(original_clothing_data, { instance = desc, prop = "Graphic", val = desc.Graphic })
                elseif desc:IsA("Decal") then
                    table.insert(original_clothing_data, { instance = desc, prop = "Transparency", val = desc.Transparency })
                end
            end

            local hum = dummy:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
                hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
                local animator = hum:FindFirstChildOfClass("Animator")
                if not animator then
                    animator = Instance.new("Animator", hum)
                end
                pcall(function()
                    local a = Instance.new("Animation")
                    a.AnimationId = "rbxassetid://507766388"
                    local track = animator:LoadAnimation(a)
                    track.Looped = true
                    track:Play()
                end)
            end

            local hrp = dummy:FindFirstChild("HumanoidRootPart") or dummy:FindFirstChildWhichIsA("BasePart")
            if hrp then
                dummy.PrimaryPart = hrp
                dummy:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.pi, 0))
            end
        end)

        WorldModel:ClearAllChildren()
        dummy.Parent = WorldModel
        previewDummy = dummy
        return dummy
    end

    pcall(create_esp_dummy)

    local OverlayContainer = Instance.new("Frame")
    OverlayContainer.BackgroundTransparency = 1
    OverlayContainer.Position = UDim2.new(0.2, 0, 0.05, 0)
    OverlayContainer.Size = UDim2.new(0.6, 0, 0.9, 0)
    OverlayContainer.ZIndex = 125
    OverlayContainer.Parent = Canvas

    local BoundingBox = Instance.new("Frame")
    BoundingBox.BackgroundTransparency = 1
    BoundingBox.Size = UDim2.fromScale(1, 1)
    BoundingBox.ZIndex = 126
    BoundingBox.Parent = OverlayContainer

    local BoxGradient = Instance.new("ImageLabel")
    BoxGradient.Name = "BoxGradient"
    BoxGradient.BackgroundTransparency = 1
    BoxGradient.BorderSizePixel = 0
    BoxGradient.Size = UDim2.fromScale(1, 1)
    BoxGradient.Position = UDim2.new(0, 0, 0, 0)
    BoxGradient.ZIndex = 126
    BoxGradient.Image = box_gradient_asset or ""
    BoxGradient.Visible = false
    BoxGradient.Parent = BoundingBox

    local BoxStroke = Instance.new("UIStroke")
    BoxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    BoxStroke.Color = Config.box_color or Color3.fromRGB(255, 255, 255)
    BoxStroke.Thickness = 1
    BoxStroke.Parent = BoundingBox

    local BoxOutline = Instance.new("Frame")
    BoxOutline.Name = "BoxOutline"
    BoxOutline.BackgroundTransparency = 1
    BoxOutline.Position = UDim2.new(0, -1, 0, -1)
    BoxOutline.Size = UDim2.new(1, 2, 1, 2)
    BoxOutline.ZIndex = 125
    BoxOutline.Visible = false
    BoxOutline.Parent = OverlayContainer

    local BoxOutlineStroke = Instance.new("UIStroke")
    BoxOutlineStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    BoxOutlineStroke.Color = Config.box_outline_color or Color3.fromRGB(0, 0, 0)
    BoxOutlineStroke.Thickness = 1
    BoxOutlineStroke.Parent = BoxOutline

    local BoxOutlineGradient = Instance.new("UIGradient")
    BoxOutlineGradient.Name = "BoxOutlineGradient"
    BoxOutlineGradient.Rotation = 90
    BoxOutlineGradient.Enabled = false
    BoxOutlineGradient.Parent = BoxOutlineStroke

    local CornerHolders = {}
    local CornerOutlineHolders = {}
    local function createCorners()
        local corners = {
            { Pos = UDim2.new(0, 0, 0, 0), SizeX = UDim2.new(0, 10, 0, 1.5), SizeY = UDim2.new(0, 1.5, 0, 10) },
            { Pos = UDim2.new(1, -10, 0, 0), SizeX = UDim2.new(0, 10, 0, 1.5), SizeY = UDim2.new(0, 1.5, 0, 10), PosY = UDim2.new(1, -1.5, 0, 0) },
            { Pos = UDim2.new(0, 0, 1, -1.5), SizeX = UDim2.new(0, 10, 0, 1.5), SizeY = UDim2.new(0, 1.5, 0, 10), PosY = UDim2.new(0, 0, 1, -10) },
            { Pos = UDim2.new(1, -10, 1, -1.5), SizeX = UDim2.new(0, 10, 0, 1.5), SizeY = UDim2.new(0, 1.5, 0, 10), PosY = UDim2.new(1, -1.5, 1, -10) },
        }
        for _, c in ipairs(corners) do
            local lx_out = Instance.new("Frame")
            lx_out.BackgroundColor3 = Config.box_outline_color or Color3.fromRGB(0, 0, 0)
            lx_out.BorderSizePixel = 0
            lx_out.Position = UDim2.new(c.Pos.X.Scale, c.Pos.X.Offset - 1, c.Pos.Y.Scale, c.Pos.Y.Offset - 1)
            lx_out.Size = UDim2.new(c.SizeX.X.Scale, c.SizeX.X.Offset + 2, c.SizeX.Y.Scale, c.SizeX.Y.Offset + 2)
            lx_out.ZIndex = 126
            lx_out.Parent = OverlayContainer

            local ly_out = Instance.new("Frame")
            ly_out.BackgroundColor3 = Config.box_outline_color or Color3.fromRGB(0, 0, 0)
            ly_out.BorderSizePixel = 0
            local posY = c.PosY or c.Pos
            ly_out.Position = UDim2.new(posY.X.Scale, posY.X.Offset - 1, posY.Y.Scale, posY.Y.Offset - 1)
            ly_out.Size = UDim2.new(c.SizeY.X.Scale, c.SizeY.X.Offset + 2, c.SizeY.Y.Scale, c.SizeY.Y.Offset + 2)
            ly_out.ZIndex = 126
            ly_out.Parent = OverlayContainer

            table.insert(CornerOutlineHolders, lx_out)
            table.insert(CornerOutlineHolders, ly_out)

            local lx = Instance.new("Frame")
            lx.BackgroundColor3 = Config.box_color or Color3.fromRGB(255, 255, 255)
            lx.BorderSizePixel = 0
            lx.Position = c.Pos
            lx.Size = c.SizeX
            lx.ZIndex = 127
            lx.Parent = OverlayContainer

            local ly = Instance.new("Frame")
            ly.BackgroundColor3 = Config.box_color or Color3.fromRGB(255, 255, 255)
            ly.BorderSizePixel = 0
            ly.Position = c.PosY or c.Pos
            ly.Size = c.SizeY
            ly.ZIndex = 127
            ly.Parent = OverlayContainer

            table.insert(CornerHolders, lx)
            table.insert(CornerHolders, ly)
        end
    end
    createCorners()

    local HealthBarBg = Instance.new("Frame")
    HealthBarBg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    HealthBarBg.BorderSizePixel = 0
    HealthBarBg.Position = UDim2.new(0, -6, 0, 0)
    HealthBarBg.Size = UDim2.new(0, 2.5, 1, 0)
    HealthBarBg.Visible = Config.health_enabled or false
    HealthBarBg.ZIndex = 126
    HealthBarBg.Parent = OverlayContainer

    local hbStroke = Instance.new("UIStroke")
    hbStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    hbStroke.Color = Color3.fromRGB(0, 0, 0)
    hbStroke.Thickness = 1
    hbStroke.Parent = HealthBarBg

    local HealthBarFill = Instance.new("Frame")
    HealthBarFill.BackgroundColor3 = Config.health_color or Color3.fromRGB(0, 255, 128)
    HealthBarFill.BorderSizePixel = 0
    HealthBarFill.AnchorPoint = Vector2.new(0, 1)
    HealthBarFill.Position = UDim2.new(0, 0, 1, 0)
    HealthBarFill.Size = UDim2.new(1, 0, 0.85, 0)
    HealthBarFill.ZIndex = 127
    HealthBarFill.Parent = HealthBarBg

    local HealthBarGradient = Instance.new("ImageLabel")
    HealthBarGradient.Name = "HealthBarGradient"
    HealthBarGradient.BackgroundTransparency = 1
    HealthBarGradient.BorderSizePixel = 0
    HealthBarGradient.Size = UDim2.fromScale(1, 1)
    HealthBarGradient.Position = UDim2.new(0, 0, 0, 0)
    HealthBarGradient.ZIndex = 128
    HealthBarGradient.Image = health_gradient_asset or ""
    HealthBarGradient.Visible = false
    HealthBarGradient.Parent = HealthBarFill

    local SkeletonLines = {}
    for i = 1, 16 do
        local line = Instance.new("Frame")
        line.BackgroundColor3 = Config.skeleton_color or Color3.fromRGB(255, 255, 255)
        line.BorderSizePixel = 0
        line.AnchorPoint = Vector2.new(0.5, 0.5)
        line.Size = UDim2.fromOffset(0, Config.skeleton_thick or 1.5)
        line.Visible = false
        line.ZIndex = 128
        line.Parent = Canvas
        table.insert(SkeletonLines, line)
    end

    local playerName = (local_player and (local_player.DisplayName or local_player.Name)) or Config.name_text or "Player"
    local NameLabel = Instance.new("TextLabel")
    NameLabel.BackgroundTransparency = 1
    NameLabel.Font = get_theme_font()
    NameLabel.AnchorPoint = Vector2.new(0.5, 1)
    NameLabel.Position = UDim2.new(0.5, 0, 0, -2)
    NameLabel.AutomaticSize = Enum.AutomaticSize.X
    NameLabel.Size = UDim2.new(0, 0, 0, 13)
    NameLabel.Text = playerName
    NameLabel.TextColor3 = Config.name_color or Color3.fromRGB(255, 255, 255)
    NameLabel.TextSize = 11
    NameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    NameLabel.TextStrokeTransparency = 0
    NameLabel.TextXAlignment = Enum.TextXAlignment.Center
    NameLabel.Visible = Config.name_enabled or false
    NameLabel.ZIndex = 126
    NameLabel.Parent = OverlayContainer

    local NameGradient = Instance.new("UIGradient")
    NameGradient.Name = "NameGradient"
    NameGradient.Enabled = false
    NameGradient.Parent = NameLabel

    local WeaponLabel = Instance.new("TextLabel")
    WeaponLabel.BackgroundTransparency = 1
    WeaponLabel.Font = get_theme_font()
    WeaponLabel.Position = UDim2.new(0, -20, 1, 3)
    WeaponLabel.Size = UDim2.new(1, 40, 0, 12)
    WeaponLabel.Text = Config.weapon_text or "AK-47"
    WeaponLabel.TextColor3 = Config.weapon_color or Color3.fromRGB(220, 220, 220)
    WeaponLabel.TextSize = 10
    WeaponLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    WeaponLabel.TextStrokeTransparency = 0
    WeaponLabel.TextXAlignment = Enum.TextXAlignment.Center
    WeaponLabel.Visible = Config.weapon_enabled or false
    WeaponLabel.ZIndex = 126
    WeaponLabel.Parent = OverlayContainer

    local DistLabel = Instance.new("TextLabel")
    DistLabel.BackgroundTransparency = 1
    DistLabel.Font = get_theme_font()
    DistLabel.Position = UDim2.new(0, -20, 1, 15)
    DistLabel.Size = UDim2.new(1, 40, 0, 12)
    DistLabel.Text = Config.distance_text or "[24m]"
    DistLabel.TextColor3 = Config.distance_color or Color3.fromRGB(255, 255, 255)
    DistLabel.TextSize = 10
    DistLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    DistLabel.TextStrokeTransparency = 0
    DistLabel.TextXAlignment = Enum.TextXAlignment.Center
    DistLabel.Visible = Config.distance_enabled or false
    DistLabel.ZIndex = 126
    DistLabel.Parent = OverlayContainer

    local state = {
        box_enabled = Config.box_enabled or false,
        box_mode = Config.box_mode or "2D",
        box_color = Config.box_color or Color3.fromRGB(255, 255, 255),
        box_outline = (Config.box_outline ~= false),
        box_outline_color = Config.box_outline_color or Color3.fromRGB(0, 0, 0),
        box_outline_mode = Config.box_outline_mode or "Color",
        box_outline_gradient = Config.box_outline_gradient or false,
        box_gradient = Config.box_gradient or false,
        box_gradient_color = Config.box_gradient_color or Color3.fromRGB(255, 255, 255),
        box_gradient_trans = Config.box_gradient_trans or 0.85,
        skeleton_enabled = Config.skeleton_enabled or false,
        skeleton_color = Config.skeleton_color or Color3.fromRGB(255, 255, 255),
        skeleton_thick = Config.skeleton_thick or 1.5,
        health_enabled = Config.health_enabled or false,
        health_color = Config.health_color or Color3.fromRGB(0, 255, 128),
        health_gradient = Config.health_gradient or false,
        health_gradient_color = Config.health_gradient_color or Color3.fromRGB(105, 205, 255),
        health_gradient_trans = Config.health_gradient_trans or 0,
        name_enabled = Config.name_enabled or false,
        name_color = Config.name_color or Color3.fromRGB(255, 255, 255),
        name_gradient = Config.name_gradient or (cfg and cfg.name_gradient) or false,
        name_gradient_color = Config.name_gradient_color or (cfg and cfg.name_gradient_color) or Color3.fromRGB(105, 205, 255),
        name_gradient_trans = Config.name_gradient_trans or (cfg and cfg.name_gradient_trans) or 0,
        name_mode = Config.name_mode or (cfg and cfg.name_mode) or "Display Name",
        weapon_enabled = Config.weapon_enabled or false,
        distance_enabled = Config.distance_enabled or false,
        distance_color = Config.distance_color or Color3.fromRGB(255, 255, 255),
        chams_enabled = Config.chams_enabled or false,
        chams_color = Config.chams_color or Color3.fromRGB(180, 100, 255),
        chams_outline_color = Config.chams_outline_color or Color3.fromRGB(255, 255, 255),
    }

    local function update_esp_projections()
        if not PreviewWindow.Visible or not previewDummy or not previewDummy.Parent then return end
        local canvasSize = Canvas.AbsoluteSize
        if canvasSize.X <= 0 or canvasSize.Y <= 0 then return end

        local head = previewDummy:FindFirstChild("Head")
        local uTorso = previewDummy:FindFirstChild("UpperTorso") or previewDummy:FindFirstChild("Torso")
        local lTorso = previewDummy:FindFirstChild("LowerTorso") or uTorso
        local lArm = previewDummy:FindFirstChild("LeftUpperArm") or previewDummy:FindFirstChild("Left Arm")
        local lLowArm = previewDummy:FindFirstChild("LeftLowerArm") or lArm
        local lHand = previewDummy:FindFirstChild("LeftHand") or lLowArm
        local rArm = previewDummy:FindFirstChild("RightUpperArm") or previewDummy:FindFirstChild("Right Arm")
        local rLowArm = previewDummy:FindFirstChild("RightLowerArm") or rArm
        local rHand = previewDummy:FindFirstChild("RightHand") or rLowArm
        local lLeg = previewDummy:FindFirstChild("LeftUpperLeg") or previewDummy:FindFirstChild("Left Leg")
        local lLowLeg = previewDummy:FindFirstChild("LeftLowerLeg") or lLeg
        local lFoot = previewDummy:FindFirstChild("LeftFoot") or lLowLeg
        local rLeg = previewDummy:FindFirstChild("RightUpperLeg") or previewDummy:FindFirstChild("Right Leg")
        local rLowLeg = previewDummy:FindFirstChild("RightLowerLeg") or rLeg
        local rFoot = previewDummy:FindFirstChild("RightFoot") or rLowLeg

        -- 1. Bounding box calculation from 3D corner extents of all parts
        local minX, maxX = 1e9, -1e9
        local minY, maxY = 1e9, -1e9

        local tracked = { head, uTorso, lTorso, lArm, lLowArm, lHand, rArm, rLowArm, rHand, lLeg, lLowLeg, lFoot, rLeg, rLowLeg, rFoot }
        for _, p in ipairs(tracked) do
            if p and p:IsA("BasePart") then
                local cf = p.CFrame
                local hs = p.Size * 0.5
                local corners = {
                    cf * Vector3.new(-hs.X, -hs.Y, -hs.Z),
                    cf * Vector3.new(hs.X, -hs.Y, -hs.Z),
                    cf * Vector3.new(-hs.X, hs.Y, -hs.Z),
                    cf * Vector3.new(hs.X, hs.Y, -hs.Z),
                    cf * Vector3.new(-hs.X, -hs.Y, hs.Z),
                    cf * Vector3.new(hs.X, -hs.Y, hs.Z),
                    cf * Vector3.new(-hs.X, hs.Y, hs.Z),
                    cf * Vector3.new(hs.X, hs.Y, hs.Z),
                }
                for _, c in ipairs(corners) do
                    local p2d = ViewportCam:WorldToViewportPoint(c)
                    if p2d.X < minX then minX = p2d.X end
                    if p2d.X > maxX then maxX = p2d.X end
                    if p2d.Y < minY then minY = p2d.Y end
                    if p2d.Y > maxY then maxY = p2d.Y end
                end
            end
        end

        if minX < maxX and minY < maxY then
            local pLeft = math.floor(minX * canvasSize.X) - 2
            local pTop = math.floor(minY * canvasSize.Y) - 2
            local pW = math.ceil((maxX - minX) * canvasSize.X) + 4
            local pH = math.ceil((maxY - minY) * canvasSize.Y) + 4

            OverlayContainer.Position = UDim2.fromOffset(pLeft, pTop)
            OverlayContainer.Size = UDim2.fromOffset(pW, pH)
        end

        -- 2. Skeleton lines
        if state.skeleton_enabled then
            local pairsList = {}
            if previewDummy:FindFirstChild("UpperTorso") then
                pairsList = {
                    { head, uTorso },
                    { uTorso, lTorso },
                    { uTorso, lArm },
                    { lArm, lLowArm },
                    { lLowArm, lHand },
                    { uTorso, rArm },
                    { rArm, rLowArm },
                    { rLowArm, rHand },
                    { lTorso, lLeg },
                    { lLeg, lLowLeg },
                    { lLowLeg, lFoot },
                    { lTorso, rLeg },
                    { rLeg, rLowLeg },
                    { rLowLeg, rFoot },
                }
            else
                pairsList = {
                    { head, uTorso },
                    { uTorso, lArm },
                    { uTorso, rArm },
                    { uTorso, lLeg },
                    { uTorso, rLeg },
                }
            end

            for idx, bones in ipairs(pairsList) do
                local pA, pB = bones[1], bones[2]
                local line = SkeletonLines[idx]
                if pA and pB and line then
                    local vA = ViewportCam:WorldToViewportPoint(pA.Position)
                    local vB = ViewportCam:WorldToViewportPoint(pB.Position)
                    local x1 = vA.X * canvasSize.X
                    local y1 = vA.Y * canvasSize.Y
                    local x2 = vB.X * canvasSize.X
                    local y2 = vB.Y * canvasSize.Y

                    local midX = (x1 + x2) * 0.5
                    local midY = (y1 + y2) * 0.5
                    local dx = x2 - x1
                    local dy = y2 - y1
                    local dist = math.sqrt(dx * dx + dy * dy)
                    local angle = math.deg(math.atan2(dy, dx))

                    line.AnchorPoint = Vector2.new(0.5, 0.5)
                    line.Position = UDim2.fromOffset(midX, midY)
                    line.Size = UDim2.fromOffset(dist, state.skeleton_thick or 1.5)
                    line.Rotation = angle
                    line.Visible = true
                elseif line then
                    line.Visible = false
                end
            end
            for i = #pairsList + 1, #SkeletonLines do
                SkeletonLines[i].Visible = false
            end
        else
            for _, line in ipairs(SkeletonLines) do
                line.Visible = false
            end
        end

        -- 3. Dynamic Health & Distance oscillation (100 -> 0 -> 100 every 2 seconds)
        local cycle = (os.clock() % 2)
        local alpha = (cycle < 1) and (1 - cycle) or (cycle - 1)

        if state.health_enabled then
            HealthBarFill.Size = UDim2.new(1, 0, alpha, 0)
        end

        if state.distance_enabled then
            local distVal = math.floor(alpha * 100)
            DistLabel.Text = string.format("[%dm]", distVal)
        end

        local isOutlineGrad = (state.box_outline_mode == "Gradient" or state.box_outline_gradient == true or state.box_sync_gradient == true)
        if isOutlineGrad and state.box_enabled then
            local gradCycle = (math.sin(os.clock() * 2.5) + 1) / 2
            local col1 = state.box_color or Color3.fromRGB(255, 255, 255)
            local col2 = state.box_gradient_color or Color3.fromRGB(255, 255, 255)
            local currentOutlineCol = col1:Lerp(col2, gradCycle)
            if BoxOutline.Visible then
                BoxOutlineStroke.Color = currentOutlineCol
                BoxOutlineGradient.Enabled = false
            end
            if state.box_mode == "Corner" then
                for _, c in ipairs(CornerOutlineHolders) do
                    if c.Visible then c.BackgroundColor3 = currentOutlineCol end
                end
            end
        end
    end

    local function applyState()
        local is2D = (state.box_mode == "2D")
        BoundingBox.Visible = state.box_enabled and is2D
        BoxStroke.Color = state.box_color
        local isOutlineGrad = (state.box_outline_mode == "Gradient" or state.box_outline_gradient == true or state.box_sync_gradient == true)
        BoxOutline.Visible = state.box_enabled and is2D and (state.box_outline ~= false)
        if isOutlineGrad then
            local gradCycle = (math.sin(os.clock() * 2.5) + 1) / 2
            local col1 = state.box_color or Color3.fromRGB(255, 255, 255)
            local col2 = state.box_gradient_color or Color3.fromRGB(255, 255, 255)
            local currentOutlineCol = col1:Lerp(col2, gradCycle)
            BoxOutlineGradient.Enabled = false
            BoxOutlineStroke.Color = currentOutlineCol
        else
            BoxOutlineGradient.Enabled = false
            BoxOutlineStroke.Color = state.box_outline_color or Color3.fromRGB(0, 0, 0)
        end
        if BoxGradient.Image == "" and box_gradient_asset then BoxGradient.Image = box_gradient_asset end
        BoxGradient.Visible = state.box_enabled and (state.box_gradient == true)
        BoxGradient.ImageColor3 = state.box_gradient_color or Color3.fromRGB(255, 255, 255)
        BoxGradient.ImageTransparency = state.box_gradient_trans or 0.85

        local isCorner = (state.box_mode == "Corner")
        for _, c in ipairs(CornerHolders) do
            c.Visible = state.box_enabled and isCorner
            c.BackgroundColor3 = state.box_color
        end
        for i, c in ipairs(CornerOutlineHolders) do
            c.Visible = state.box_enabled and isCorner and (state.box_outline ~= false)
            if isOutlineGrad then
                local gradCycle = (math.sin(os.clock() * 2.5) + 1) / 2
                local col1 = state.box_color or Color3.fromRGB(255, 255, 255)
                local col2 = state.box_gradient_color or Color3.fromRGB(255, 255, 255)
                c.BackgroundColor3 = col1:Lerp(col2, gradCycle)
            else
                c.BackgroundColor3 = state.box_outline_color or Color3.fromRGB(0, 0, 0)
            end
        end

        for _, line in ipairs(SkeletonLines) do
            line.BackgroundColor3 = state.skeleton_color
        end

        HealthBarBg.Visible = state.health_enabled
        HealthBarFill.BackgroundColor3 = state.health_color
        if HealthBarGradient.Image == "" and health_gradient_asset then HealthBarGradient.Image = health_gradient_asset end
        HealthBarGradient.Visible = state.health_enabled and (state.health_gradient == true)
        HealthBarGradient.ImageColor3 = state.health_gradient_color or Color3.fromRGB(105, 205, 255)
        HealthBarGradient.ImageTransparency = state.health_gradient_trans or 0

        NameLabel.Visible = state.name_enabled

        local isNameGrad = (state.name_gradient == true)
        NameGradient.Enabled = isNameGrad
        if isNameGrad then
            NameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            local nCol1 = state.name_color or Color3.fromRGB(255, 255, 255)
            local nCol2 = state.name_gradient_color or Color3.fromRGB(105, 205, 255)
            NameGradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, nCol1),
                ColorSequenceKeypoint.new(1, nCol2)
            })
            local nTrans = math.clamp(state.name_gradient_trans or 0, 0, 1)
            NameGradient.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, nTrans)
            })
        else
            NameLabel.TextColor3 = state.name_color or Color3.fromRGB(255, 255, 255)
        end

        local dName = (local_player and local_player.DisplayName) or "Player"
        local uName = (local_player and local_player.Name) or "Player"
        if state.name_mode == "User Name" then
            NameLabel.Text = uName
        elseif state.name_mode == "Both" then
            NameLabel.Text = dName .. " (@" .. uName .. ")"
        else
            NameLabel.Text = dName
        end

        WeaponLabel.Visible = state.weapon_enabled
        DistLabel.Visible = state.distance_enabled
        DistLabel.TextColor3 = state.distance_color

        -- Chams application on dummy
        if state.chams_enabled then
            for _, d in ipairs(original_parts_data) do
                if d.part and d.part.Parent then
                    d.part.Color = state.chams_color
                    d.part.Material = Enum.Material.Neon
                    d.part.Transparency = 0.25
                end
            end
            for _, obj in ipairs(original_clothing_data) do
                if obj.instance and obj.instance.Parent then
                    if obj.instance:IsA("Shirt") then
                        obj.instance.ShirtTemplate = ""
                    elseif obj.instance:IsA("Pants") then
                        obj.instance.PantsTemplate = ""
                    elseif obj.instance:IsA("ShirtGraphic") then
                        pcall(function() obj.instance.Graphic = "" end)
                    elseif obj.instance:IsA("Decal") then
                        obj.instance.Transparency = 1
                    end
                end
            end
        else
            for _, d in ipairs(original_parts_data) do
                if d.part and d.part.Parent then
                    d.part.Color = d.color
                    d.part.Material = d.material
                    d.part.Transparency = d.transparency
                end
            end
            for _, obj in ipairs(original_clothing_data) do
                if obj.instance and obj.instance.Parent then
                    if obj.instance:IsA("Shirt") then
                        obj.instance.ShirtTemplate = obj.val or ""
                    elseif obj.instance:IsA("Pants") then
                        obj.instance.PantsTemplate = obj.val or ""
                    elseif obj.instance:IsA("ShirtGraphic") then
                        pcall(function() obj.instance.Graphic = obj.val or "" end)
                    elseif obj.instance:IsA("Decal") then
                        obj.instance.Transparency = obj.val or 0
                    end
                end
            end
        end

        pcall(update_esp_projections)
    end

    applyState()

    local function check_parent_liveness()
        if not PreviewWindow.Visible then
            if heartbeat_conn then heartbeat_conn:Disconnect() heartbeat_conn = nil end
            return
        end
        local is_open = true
        if library and library.Toggled ~= nil then
            if not library.Toggled then is_open = false end
        end
        local mf = (lib and lib.MainFrame) or (library and library.MainFrame) or (window and window.MainFrame) or (library and library.ScreenGui and library.ScreenGui:FindFirstChild("Main", true))
        if mf then
            if not mf.Visible or (mf:IsA("CanvasGroup") and mf.GroupTransparency >= 0.75) then
                is_open = false
            end
        end
        if not is_open then
            smoothClose()
        end
    end

    local function on_heartbeat()
        check_parent_liveness()
        pcall(update_esp_projections)
    end

    local PreviewApi = {
        Frame = PreviewWindow,
        Open = function(self)
            local animWin = (library and library.AnimCatalogFrame) or (lib and lib.AnimCatalogFrame)
            if not animWin then
                local cg = cloneref(game:GetService("CoreGui"))
                local pg = local_player and local_player:FindFirstChildOfClass("PlayerGui")
                animWin = (cg and cg:FindFirstChild("AnimCatalogWindow", true)) or (pg and pg:FindFirstChild("AnimCatalogWindow", true))
            end
            if animWin then
                if library and library.AnimCatalog and library.AnimCatalog.Close then
                    pcall(function() library.AnimCatalog:Close() end)
                elseif anim_ui and anim_ui.close then
                    pcall(function() anim_ui:close() end)
                else
                    pcall(function() animWin.Visible = false end)
                end
            end

            local emoteWin = (library and library.EmoteCatalogFrame) or (lib and lib.EmoteCatalogFrame)
            if not emoteWin then
                local cg = cloneref(game:GetService("CoreGui"))
                local pg = local_player and local_player:FindFirstChildOfClass("PlayerGui")
                emoteWin = (cg and cg:FindFirstChild("EmoteCatalogWindow", true)) or (pg and pg:FindFirstChild("EmoteCatalogWindow", true))
            end
            if emoteWin then
                if library and library.EmoteCatalog and library.EmoteCatalog.Close then
                    pcall(function() library.EmoteCatalog:Close() end)
                elseif emote_ui and emote_ui.close then
                    pcall(function() emote_ui:close() end)
                else
                    pcall(function() emoteWin.Visible = false end)
                end
            end

            local p = resolve_float_parent()
            if p and PreviewWindow.Parent ~= p then
                PreviewWindow.Parent = p
            end
            PreviewWindow.Position = get_docked_position(230, 385, PreviewWindow.Parent)
            PreviewWindow.ZIndex = 120
            smoothOpen()
            if not heartbeat_conn then
                heartbeat_conn = run_service.Heartbeat:Connect(on_heartbeat)
            end
            if not previewDummy or not previewDummy.Parent then
                pcall(create_esp_dummy)
            end
            pcall(applyState)
        end,
        Close = function(self)
            for _, c in pairs(cardButtons) do
                if c.Track then
                    pcall(function() c.Track:Stop() end)
                end
            end
            smoothClose()
        end,
        Toggle = function(self)
            if is_open or (PreviewWindow.Visible and not isClosing) then
                self:Close()
            else
                self:Open()
            end
        end,
        toggle = function(self) self:Toggle() end,
        open = function(self) self:Open() end,
        close = function(self) self:Close() end,
        SetVisible = function(self, val)
            if val then self:Open() else self:Close() end
        end,
        Update = function(self, newProps)
            if typeof(newProps) == "table" then
                for k, v in pairs(newProps) do
                    state[k] = v
                end
                pcall(applyState)
            end
        end,
        Destroy = function(self)
            if heartbeat_conn then pcall(function() heartbeat_conn:Disconnect() end) heartbeat_conn = nil end
            if previewDummy then pcall(function() previewDummy:Destroy() end) end
            if PreviewWindow then pcall(function() PreviewWindow:Destroy() end) end
        end
    }

    if lib then
        lib.ESPPreview = PreviewApi
        lib.ESPPreviewFrame = PreviewWindow
    end
    if library then
        library.ESPPreview = PreviewApi
        library.ESPPreviewFrame = PreviewWindow
    end
    return PreviewApi
end

-- Inject into library directly
if library then
    library.AddAnimCatalog = function(self, conf)
        return build_animation_catalog(self, conf)
    end
    library.AddEmoteCatalog = function(self, conf)
        return build_emote_catalog(self, conf)
    end
    library.AddESPPreview = function(self, conf)
        return build_esp_preview(self, conf)
    end
end

anim_catalog = nil
local anim_tab_catalog = nil
anim_ui = {
    init = function(self)
        if not anim_catalog then
            anim_catalog = build_animation_catalog(library, {
                Title = "animations",
                Icon = "film",
                Selected = cfg.custom_anim_pack,
                Packs = anim_manager.packs,
                OnSelect = function(pack, slot)
                    slot = slot or "all"
                    cfg.custom_anim_pack = pack.name
                    cfg.custom_anim_slot = slot
                    if options.custom_anim_pack then
                        pcall(function() options.custom_anim_pack:SetValue(pack.name, slot) end)
                    end
                    if options.custom_anims_tab_pack then
                        pcall(function() options.custom_anims_tab_pack:SetValue(pack.name, slot) end)
                    end
                    if toggles.custom_anims_toggle and not toggles.custom_anims_toggle.Value then
                        pcall(function() toggles.custom_anims_toggle:SetValue(true) end)
                    else
                        anim_manager:apply(pack.name, slot)
                    end
                    if anim_tab_catalog and anim_tab_catalog.Select then
                        pcall(function() anim_tab_catalog:Select(pack.name) end)
                    end
                end,
            })
        end
        return anim_catalog
    end,
    set_visible = function(self, state)
        local cat = self:init()
        if cat and cat.SetVisible then
            cat:SetVisible(state)
        elseif cat and cat.Open and cat.Close then
            if state then cat:Open() else cat:Close() end
        end
    end,
    open = function(self)
        local cat = self:init()
        if cat and cat.Open then
            cat:Open()
        elseif cat and cat.Toggle then
            cat:Toggle()
        end
    end,
    close = function(self)
        if anim_catalog and anim_catalog.Close then
            anim_catalog:Close()
        end
    end,
    toggle = function(self)
        local cat = self:init()
        if cat and cat.Toggle then
            cat:Toggle()
        elseif cat and cat.Open then
            cat:Open()
        end
    end,
    update_state = function(self)
        local cat = self:init()
        if cat and cat.Select then
            pcall(function() cat:Select(cfg.custom_anim_pack) end)
        end
        if anim_tab_catalog and anim_tab_catalog.Select then
            pcall(function() anim_tab_catalog:Select(cfg.custom_anim_pack) end)
        end
    end,
    destroy = function(self)
        if anim_catalog and anim_catalog.Destroy then
            pcall(function() anim_catalog:Destroy() end)
        end
        anim_catalog = nil
    end
}

emote_catalog = nil
emote_ui = {
    init = function(self)
        if not emote_catalog then
            emote_catalog = build_emote_catalog(library, {
                Title = "emotes",
                OnSelect = function(emote)
                    if emote and emote.id then
                        emote_manager:play(emote.id, emote.name)
                    end
                end,
            })
        end
        return emote_catalog
    end,
    set_visible = function(self, state)
        local cat = self:init()
        if cat and cat.SetVisible then
            cat:SetVisible(state)
        elseif cat and cat.Open and cat.Close then
            if state then cat:Open() else cat:Close() end
        end
    end,
    open = function(self)
        local cat = self:init()
        if cat and cat.Open then
            cat:Open()
        elseif cat and cat.Toggle then
            cat:Toggle()
        end
    end,
    close = function(self)
        if emote_catalog and emote_catalog.Close then
            emote_catalog:Close()
        end
    end,
    toggle = function(self)
        local cat = self:init()
        if cat and cat.Toggle then
            cat:Toggle()
        elseif cat and cat.Open then
            cat:Open()
        end
    end,
    destroy = function(self)
        if emote_catalog and emote_catalog.Destroy then
            pcall(function() emote_catalog:Destroy() end)
        end
        emote_catalog = nil
    end
}

local skyboxes = {
    ["Jungle"] = {
        SkyboxBk = "http://www.roblox.com/asset/?id=214399891",
        SkyboxDn = "http://www.roblox.com/asset/?id=214399887",
        SkyboxFt = "http://www.roblox.com/asset/?id=214399894",
        SkyboxLf = "http://www.roblox.com/asset/?id=214405668",
        SkyboxRt = "http://www.roblox.com/asset/?id=214399899",
        SkyboxUp = "http://www.roblox.com/asset/?id=214399889"
    },
    ["Blossom"] = {
        SkyboxBk = "http://www.roblox.com/asset/?id=271042516",
        SkyboxDn = "http://www.roblox.com/asset/?id=271077243",
        SkyboxFt = "http://www.roblox.com/asset/?id=271042556",
        SkyboxLf = "http://www.roblox.com/asset/?id=271042310",
        SkyboxRt = "http://www.roblox.com/asset/?id=271042467",
        SkyboxUp = "http://www.roblox.com/asset/?id=271077958"
    },
    ["Red night"] = {
        SkyboxBk = "http://www.roblox.com/Asset/?ID=401664839",
        SkyboxDn = "http://www.roblox.com/Asset/?ID=401664862",
        SkyboxFt = "http://www.roblox.com/Asset/?ID=401664960",
        SkyboxLf = "http://www.roblox.com/Asset/?ID=401664881",
        SkyboxRt = "http://www.roblox.com/Asset/?ID=401664901",
        SkyboxUp = "http://www.roblox.com/Asset/?ID=401664936"
    },
    ["Purple default"] = {
        SkyboxBk = "http://www.roblox.com/asset/?id=13694952867",
        SkyboxDn = "http://www.roblox.com/asset/?id=13694968325",
        SkyboxFt = "http://www.roblox.com/asset/?id=13694980654",
        SkyboxLf = "http://www.roblox.com/asset/?id=13694998113",
        SkyboxRt = "http://www.roblox.com/asset/?id=13695002700",
        SkyboxUp = "http://www.roblox.com/asset/?id=13695007103"
    },
    ["Foggy"] = {
        SkyboxBk = "rbxassetid://1370717244",
        SkyboxDn = "rbxassetid://1370717336",
        SkyboxFt = "rbxassetid://1370717438",
        SkyboxLf = "rbxassetid://1370717567",
        SkyboxRt = "rbxassetid://1370717698",
        SkyboxUp = "rbxassetid://1370717782"
    }
}

local sky_assets = {
    ["Galaxy"] = 15983996673,
    ["Anime"] = 13107361022,
    ["Minecraft"] = 2758029221,
    ["Anime Sky"] = 72835926026092,
    ["Pastel Anime"] = 159068040,
    ["City Sky"] = 11521606412
}

local skybox = {
    created = nil,
    orig = nil,
    orig_parent = nil,
    cache = {},
    req_id = 0
}

function skybox:detach_original()
    if self.orig then return end
    local existing = lighting:FindFirstChildOfClass("Sky")
    if existing and existing ~= self.created then
        self.orig = existing
        self.orig_parent = existing.Parent
        pcall(function() existing.Parent = nil end)
    end
end

function skybox:clear_created()
    if self.created then
        pcall(function() self.created:Destroy() end)
        self.created = nil
    end
end

function skybox:apply_textures(data)
    self:detach_original()
    self:clear_created()
    local sky = Instance.new("Sky")
    sky.Name = "_v_sky"
    for k, v in pairs(data) do
        pcall(function() sky[k] = v end)
    end
    sky.Parent = lighting
    self.created = sky
end

function skybox:apply_asset(id)
    self.req_id = self.req_id + 1
    local cur_req = self.req_id
    if self.cache[id] then
        self:detach_original()
        self:clear_created()
        local s = self.cache[id]:Clone()
        s.Name = "_v_sky"
        s.Parent = lighting
        self.created = s
        return
    end

    task.spawn(function()
        local ok, objs = pcall(function() return game:GetObjects("rbxassetid://" .. tostring(id)) end)
        if not ok or type(objs) ~= "table" then return end
        local found = nil
        for _, o in ipairs(objs) do
            if o:IsA("Sky") then found = o break end
            local s = o:FindFirstChildWhichIsA("Sky", true)
            if s then found = s break end
        end
        if not found or not cfg.skybox_enabled or cur_req ~= self.req_id then return end
        self.cache[id] = found:Clone()
        self:detach_original()
        self:clear_created()
        found.Name = "_v_sky"
        found.Parent = lighting
        self.created = found
    end)
end

function skybox:apply()
    if not cfg.skybox_enabled then
        self:reset()
        return
    end
    local name = cfg.skybox_preset or "Jungle"
    if skyboxes[name] then
        self:apply_textures(skyboxes[name])
    elseif sky_assets[name] then
        self:apply_asset(sky_assets[name])
    else
        for k, v in pairs(skyboxes) do
            if string.lower(k) == string.lower(name) then
                self:apply_textures(v)
                return
            end
        end
        for k, v in pairs(sky_assets) do
            if string.lower(k) == string.lower(name) then
                self:apply_asset(v)
                return
            end
        end
        self:apply_textures(skyboxes["Jungle"])
    end
end

function skybox:reset()
    self.req_id = self.req_id + 1
    self:clear_created()
    if self.orig then
        pcall(function() self.orig.Parent = self.orig_parent or lighting end)
        self.orig = nil
        self.orig_parent = nil
    end
end

local function is_ff2_chams()
    if (cfg.chams_mode or "Highlight") ~= "Material" then return false end
    local mat = string.lower(tostring(cfg.chams_material or ""))
    return mat == "forcefield 2" or mat == "forcefield"
end

local function apply_player_chams(p)
    if p == local_player then return end
    clear_chams(p)
    if not cfg.chams_enabled or is_teammate(p) then
        chromatic_chams:remove_player(p)
        return
    end

    local char = p.Character
    if not char or not char.Parent then
        chromatic_chams:remove_player(p)
        return
    end

    local mode = cfg.chams_mode or "Highlight"
    if mode == "Material" then
        local mat_name = string.lower(tostring(cfg.chams_material or ""))
        if mat_name == "forcefield 2" or mat_name == "forcefield" then
            chromatic_chams:remove_player(p)
            local orig_data = {}
            local target_color = cfg.chams_color or Color3.fromHex("#474747")
            local target_trans = math.clamp(cfg.self_chams_trans or 0.6, 0.1, 0.9)
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and not part:FindFirstAncestorOfClass("Tool") then
                    orig_data[part] = { Material = part.Material, Color = part.Color, Transparency = part.Transparency }
                    part.Material = Enum.Material.ForceField
                    part.Color = target_color
                    part.Transparency = target_trans
                end
            end
            player_chams_orig[p] = orig_data

            local h = Instance.new("Highlight")
            h.Name = "VantagePlayerChamsFF2"
            h.Adornee = char
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.FillColor = target_color
            h.OutlineColor = target_color
            h.FillTransparency = target_trans
            h.OutlineTransparency = 0
            h.Parent = char
            ctx.chams[p] = h

            for _, child in ipairs(char:GetChildren()) do
                if child:IsA("Tool") then
                    if not child:FindFirstChild("VantageToolNoHighlight") then
                        local thl = Instance.new("Highlight")
                        thl.Name = "VantageToolNoHighlight"
                        thl.FillTransparency = 1
                        thl.OutlineTransparency = 1
                        thl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        thl.Parent = child
                    end
                end
            end
        else
            restore_player_parts(p)
            chromatic_chams:remove_player(p)
            chromatic_chams:build_player(p)
        end
    else
        restore_player_parts(p)
        chromatic_chams:remove_player(p)
        local h = Instance.new("Highlight")
        h.Adornee = char
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.FillColor = cfg.chams_color
        h.OutlineColor = cfg.chams_outline_color
        h.FillTransparency = cfg.chams_fill_trans
        h.OutlineTransparency = cfg.chams_outline_trans
        h.Parent = char
        ctx.chams[p] = h
    end
end

local function refresh_chams()
    if not cfg.chams_enabled then
        for _, p in ipairs(players:GetPlayers()) do clear_chams(p) end
        chromatic_chams:clear()
        return
    end

    local mode = cfg.chams_mode or "Highlight"
    if mode == "Material" then
        for _, p in ipairs(players:GetPlayers()) do clear_chams(p) end
        chromatic_chams:init()
        for _, p in ipairs(players:GetPlayers()) do
            apply_player_chams(p)
        end
    else
        chromatic_chams:clear()
        for _, p in ipairs(players:GetPlayers()) do
            apply_player_chams(p)
        end
    end
end

local r15_bones = {
    { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" }
}
local r6_bones = {
    { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" }, { "Torso", "Left Leg" }, { "Torso", "Right Leg" }
}

local function make_draw(kind)
    local d = Drawing.new(kind)
    d.Visible = false
    return d
end

local function get_char_bounds(char)
    local min_v = Vector3.new(math.huge, math.huge, math.huge)
    local max_v = Vector3.new(-math.huge, -math.huge, -math.huge)
    local count = 0

    for _, part in ipairs(char:GetChildren()) do
        if part:IsA("BasePart") and (valid_parts[part.Name] or part.Name == "HumanoidRootPart") then
            local cf = part.CFrame
            local sz = part.Size * 0.5
            local c1 = cf * Vector3.new(-sz.X, -sz.Y, -sz.Z)
            local c2 = cf * Vector3.new(sz.X, -sz.Y, -sz.Z)
            local c3 = cf * Vector3.new(-sz.X, sz.Y, -sz.Z)
            local c4 = cf * Vector3.new(sz.X, sz.Y, -sz.Z)
            local c5 = cf * Vector3.new(-sz.X, -sz.Y, sz.Z)
            local c6 = cf * Vector3.new(sz.X, -sz.Y, sz.Z)
            local c7 = cf * Vector3.new(-sz.X, sz.Y, sz.Z)
            local c8 = cf * Vector3.new(sz.X, sz.Y, sz.Z)
            for _, c in ipairs({ c1, c2, c3, c4, c5, c6, c7, c8 }) do
                min_v = Vector3.new(math.min(min_v.X, c.X), math.min(min_v.Y, c.Y), math.min(min_v.Z, c.Z))
                max_v = Vector3.new(math.max(max_v.X, c.X), math.max(max_v.Y, c.Y), math.max(max_v.Z, c.Z))
            end
            count = count + 1
        end
    end

    if count == 0 then
        local cf, size = char:GetBoundingBox()
        local sz = size * 0.5
        local c1 = cf * Vector3.new(-sz.X, -sz.Y, -sz.Z)
        local c2 = cf * Vector3.new(sz.X, -sz.Y, -sz.Z)
        local c3 = cf * Vector3.new(-sz.X, sz.Y, -sz.Z)
        local c4 = cf * Vector3.new(sz.X, sz.Y, -sz.Z)
        local c5 = cf * Vector3.new(-sz.X, -sz.Y, sz.Z)
        local c6 = cf * Vector3.new(sz.X, -sz.Y, sz.Z)
        local c7 = cf * Vector3.new(-sz.X, sz.Y, sz.Z)
        local c8 = cf * Vector3.new(sz.X, sz.Y, sz.Z)
        return { c1, c2, c3, c4, c5, c6, c7, c8 }
    end

    local c1 = Vector3.new(min_v.X, min_v.Y, min_v.Z)
    local c2 = Vector3.new(max_v.X, min_v.Y, min_v.Z)
    local c3 = Vector3.new(min_v.X, max_v.Y, min_v.Z)
    local c4 = Vector3.new(max_v.X, max_v.Y, min_v.Z)
    local c5 = Vector3.new(min_v.X, min_v.Y, max_v.Z)
    local c6 = Vector3.new(max_v.X, min_v.Y, max_v.Z)
    local c7 = Vector3.new(min_v.X, max_v.Y, max_v.Z)
    local c8 = Vector3.new(max_v.X, max_v.Y, max_v.Z)
    return { c1, c2, c3, c4, c5, c6, c7, c8 }
end

local function get_drawings(player)
    if ctx.drawings[player] then return ctx.drawings[player] end
    local d = {
        box = make_draw("Square"),
        box_outline = make_draw("Square"),
        box_outline_in = make_draw("Square"),
        box_gradient = make_draw("Image"),
        name = make_draw("Text"),
        name_chars = {},
        distance = make_draw("Text"),
        weapon = make_draw("Text"),
        health = make_draw("Line"),
        health_outline = make_draw("Square"),
        health_bar = make_draw("Square"),
        health_gradient = make_draw("Image"),
        corners = {},
        corner_outlines = {},
        skeleton = {},
        visible = false,
        arrow = make_draw("Image"),
        arrow_outline = make_draw("Image"),
    }
    for i = 1, 8 do
        d.corner_outlines[i] = make_draw("Line")
        d.corner_outlines[i].Thickness = 3
        d.corner_outlines[i].ZIndex = 2
        d.corners[i] = make_draw("Line")
        d.corners[i].Thickness = 1
        d.corners[i].ZIndex = 3
    end
    for i = 1, 14 do
        local l = make_draw("Line")
        l.Thickness = cfg.skeleton_thick or 1.5
        l.Color = cfg.skeleton_color
        d.skeleton[i] = l
    end
    d.box.Filled = false
    d.box.Thickness = 1
    d.box.ZIndex = 3

    d.box_outline.Filled = false
    d.box_outline.Thickness = 1
    d.box_outline.ZIndex = 2

    d.box_outline_in.Filled = false
    d.box_outline_in.Thickness = 1
    d.box_outline_in.ZIndex = 2

    pcall(function()
        d.box_gradient.Data = box_gradient_raw
        d.box_gradient.Color = cfg.box_gradient_color
        d.box_gradient.Transparency = 1 - (cfg.box_gradient_trans or 0.85)
        d.box_gradient.ZIndex = 1
    end)

    d.health_outline.Filled = true
    d.health_outline.Color = Color3.fromRGB(0, 0, 0)
    d.health_outline.Thickness = 1
    d.health_outline.ZIndex = 2

    d.health_bar.Filled = true
    d.health_bar.ZIndex = 3

    pcall(function()
        d.health_gradient.Data = health_gradient_raw
        d.health_gradient.ZIndex = 4
    end)

    for _, key in ipairs({ "name", "distance", "weapon" }) do
        d[key].Center = true
        d[key].Outline = true
        d[key].Size = 13
    end
    d.name.Size = cfg.name_size or 13
    d.health.Thickness = 2
    pcall(function()
        d.arrow.Data = arrow_raw
        d.arrow.ZIndex = 5
        d.arrow.Visible = false
        d.arrow_outline.Data = arrow_raw
        d.arrow_outline.ZIndex = 4
        d.arrow_outline.Color = Color3.fromRGB(0, 0, 0)
        d.arrow_outline.Visible = false
    end)
    ctx.drawings[player] = d
    return d
end

local function hide_drawings(d)
    if not d or not d.visible then return end
    d.visible = false
    d.box.Visible = false
    if d.box_outline then d.box_outline.Visible = false end
    if d.box_outline_in then d.box_outline_in.Visible = false end
    if d.box_gradient then d.box_gradient.Visible = false end
    d.name.Visible = false
    if d.name_chars then
        for _, c in ipairs(d.name_chars) do c.Visible = false end
    end
    d.distance.Visible = false
    d.weapon.Visible = false
    d.health.Visible = false
    if d.health_outline then d.health_outline.Visible = false end
    if d.health_bar then d.health_bar.Visible = false end
    if d.health_gradient then d.health_gradient.Visible = false end
    d.health_gradient_state = nil
    for _, line in ipairs(d.corners) do line.Visible = false end
    if d.corner_outlines then
        for _, line in ipairs(d.corner_outlines) do line.Visible = false end
    end
    for _, line in ipairs(d.skeleton) do line.Visible = false end
    if d.arrow then d.arrow.Visible = false end
    if d.arrow_outline then d.arrow_outline.Visible = false end
end

local function sync_grad_img(d, key, pos, size, color, trans, show)
    local img = d[key]
    if not img then return end
    local skey = key .. "_state"
    local st = d[skey]
    if not st then
        st = {}
        d[skey] = st
    end
    if show then
        if st.pos ~= pos then
            img.Position = pos
            st.pos = pos
        end
        if st.size ~= size then
            img.Size = size
            st.size = size
        end
        if st.color ~= color then
            img.Color = color
            st.color = color
        end
        if st.trans ~= trans then
            img.Transparency = trans
            st.trans = trans
        end
        if st.vis ~= true then
            img.Visible = true
            st.vis = true
        end
    else
        if st.vis ~= false then
            img.Visible = false
            st.vis = false
        end
    end
end

local function sync_box_grad(d, box_x, box_y, w, h, show)
    local img = d.box_gradient
    if not img then return end
    if show then
        img.Position = Vector2.new(box_x, box_y)
        img.Size = Vector2.new(w, h)
        img.Visible = true
    else
        img.Visible = false
    end
end

local function apply_hidden_names()
    for _, p in ipairs(ctx.roster) do
        local char = p.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local saved = ctx.hidden_names[p]
        if cfg.hide_names then
            if hum then
                if not saved or saved.hum ~= hum then
                    ctx.hidden_names[p] = { hum = hum, display = hum.DisplayDistanceType }
                end
                if hum.DisplayDistanceType ~= Enum.HumanoidDisplayDistanceType.None then
                    hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
                end
            end
        elseif saved then
            pcall(function()
                if saved.hum and saved.hum.Parent then
                    saved.hum.DisplayDistanceType = saved.display
                end
            end)
            ctx.hidden_names[p] = nil
        end
    end
end

local function hide_debounced(player)
    ctx.esp_miss = ctx.esp_miss or {}
    local n = (ctx.esp_miss[player] or 0) + 1
    ctx.esp_miss[player] = n
    if n >= 3 then
        local d = ctx.drawings[player]
        if d then hide_drawings(d) end
    end
end

local function clear_player_drawings(player)
    local set = ctx.drawings[player]
    if not set then return end
    if set.name_chars then
        for _, c in ipairs(set.name_chars) do
            pcall(function() c:Remove() end)
        end
        table.clear(set.name_chars)
    end
    for key, item in pairs(set) do
        if key == "corners" or key == "skeleton" or key == "corner_outlines" then
            if type(item) == "table" then
                for _, line in ipairs(item) do
                    pcall(function() line:Remove() end)
                end
            end
        elseif key ~= "visible" and key ~= "name_chars" and key ~= "name_layout" and key ~= "health_gradient_state" and item then
            pcall(function() item:Remove() end)
        end
    end
    ctx.drawings[player] = nil
end

do
    local esp_group = tabs.visuals:AddLeftGroupbox("esp")
    local chams_group = tabs.visuals:AddLeftGroupbox("player chams")
    local weapon_group = tabs.visuals:AddLeftGroupbox("weapon chams")
    local tracers_group = tabs.visuals:AddLeftGroupbox("bullet tracers")

    local ambient_group = tabs.visuals:AddRightGroupbox("ambient")
    local skybox_group = tabs.visuals:AddRightGroupbox("skybox")
    local camera_group = tabs.visuals:AddRightGroupbox("camera")

    esp_preview = nil
    if build_esp_preview then
        esp_preview = build_esp_preview(library, {
            Title = "esp preview",
            Icon = "eye",
            box_enabled = cfg.box_enabled,
            box_mode = cfg.box_mode,
            box_color = cfg.box_color,
            box_outline = cfg.box_outline,
            box_outline_color = cfg.box_outline_color,
            box_outline_mode = cfg.box_outline_mode,
            box_outline_gradient = cfg.box_outline_gradient,
            box_gradient = cfg.box_gradient,
            box_gradient_color = cfg.box_gradient_color,
            box_gradient_trans = cfg.box_gradient_trans,
            skeleton_enabled = cfg.skeleton_enabled,
            skeleton_color = cfg.skeleton_color,
            skeleton_thick = cfg.skeleton_thick,
            health_enabled = cfg.health_enabled,
            health_color = cfg.health_color or Color3.fromRGB(0, 255, 128),
            health_gradient = cfg.health_gradient,
            health_gradient_color = cfg.health_gradient_color,
            health_gradient_trans = cfg.health_gradient_trans,
            name_enabled = cfg.names_enabled,
            name_text = "Player",
            name_mode = cfg.name_mode,
            name_color = cfg.names_color,
            name_gradient = cfg.name_gradient,
            name_gradient_color = cfg.name_gradient_color,
            name_gradient_trans = cfg.name_gradient_trans,
            weapon_enabled = cfg.show_weapon,
            weapon_text = "AK-47",
            weapon_color = Color3.fromRGB(220, 220, 220),
            distance_enabled = cfg.dist_enabled,
            distance_text = "[24m]",
            distance_color = cfg.dist_color,
            chams_enabled = cfg.chams_enabled,
            chams_color = cfg.chams_color,
            chams_outline_color = cfg.chams_outline_color,
        })
    elseif library and library.AddESPPreview then
        esp_preview = library:AddESPPreview({
            Title = "esp preview",
            Icon = "eye",
            box_enabled = cfg.box_enabled,
            box_mode = cfg.box_mode,
            box_color = cfg.box_color,
            box_gradient = cfg.box_gradient,
            box_gradient_color = cfg.box_gradient_color,
            box_gradient_trans = cfg.box_gradient_trans,
            skeleton_enabled = cfg.skeleton_enabled,
            skeleton_color = cfg.skeleton_color,
            skeleton_thick = cfg.skeleton_thick,
            health_enabled = cfg.health_enabled,
            health_color = cfg.health_color or Color3.fromRGB(0, 255, 128),
            health_gradient = cfg.health_gradient,
            health_gradient_color = cfg.health_gradient_color,
            health_gradient_trans = cfg.health_gradient_trans,
            name_enabled = cfg.names_enabled,
            name_text = "Player",
            name_mode = cfg.name_mode,
            name_color = cfg.names_color,
            name_gradient = cfg.name_gradient,
            name_gradient_color = cfg.name_gradient_color,
            name_gradient_trans = cfg.name_gradient_trans,
            weapon_enabled = cfg.show_weapon,
            weapon_text = "AK-47",
            weapon_color = Color3.fromRGB(220, 220, 220),
            distance_enabled = cfg.dist_enabled,
            distance_text = "[24m]",
            distance_color = cfg.dist_color,
            chams_enabled = cfg.chams_enabled,
            chams_color = cfg.chams_color,
            chams_outline_color = cfg.chams_outline_color,
        })
    end

    local esp_toggle = esp_group:AddToggle("esp_master", {
        Text = "enabled",
        Default = false,
        Callback = function(v)
            cfg.esp_enabled = v
            if not v then
                for _, d in pairs(ctx.drawings) do hide_drawings(d) end
            end
        end
    })
    esp_toggle:AddSettings(function(s)
        s:AddSlider("max_dist", {
            Text = "render distance",
            Default = 1000,
            Min = 100,
            Max = 3000,
            Rounding = 0,
            Suffix = " studs",
            Callback = function(v) cfg.max_dist = v end
        })
        s:AddToggle("show_roles", {
            Text = "show roles",
            Default = false,
            Callback = function(v) cfg.show_roles = v end
        })
        s:AddToggle("role_colors", {
            Text = "role colors",
            Default = false,
            Callback = function(v) cfg.role_colors_enabled = v end
        })
        s:AddDropdown("role_filter", {
            Text = "role filter",
            Values = { "all", "murderer only", "sheriff only", "roles only" },
            Default = 1,
            Callback = function(v) cfg.role_filter = v end
        })
        s:AddLabel("murderer color"):AddColorPicker("role_col_murd", {
            Default = Color3.fromRGB(255, 60, 60),
            Title = "murderer color",
            Callback = function(v) cfg.role_color_murderer = v end
        })
        s:AddLabel("sheriff color"):AddColorPicker("role_col_sher", {
            Default = Color3.fromRGB(0, 153, 255),
            Title = "sheriff color",
            Callback = function(v) cfg.role_color_sheriff = v end
        })
        s:AddLabel("innocent color"):AddColorPicker("role_col_inno", {
            Default = Color3.fromRGB(255, 255, 255),
            Title = "innocent color",
            Callback = function(v) cfg.role_color_innocent = v end
        })
    end)

    local box_toggle = esp_group:AddToggle("box_toggle", {
        Text = "boxes",
        Default = false,
        Callback = function(v)
            cfg.box_enabled = v
            if esp_preview then esp_preview:Update({ box_enabled = v }) end
        end
    })
    box_toggle:AddColorPicker("box_color", {
        Default = Color3.fromRGB(255, 255, 255),
        Title = "box color",
        Callback = function(v)
            cfg.box_color = v
            if esp_preview then esp_preview:Update({ box_color = v }) end
        end
    })
    box_toggle:AddColorPicker("box_outline_color", {
        Default = Color3.fromRGB(0, 0, 0),
        Title = "outline color",
        Callback = function(v)
            cfg.box_outline_color = v
            if esp_preview then esp_preview:Update({ box_outline_color = v }) end
        end
    })
    box_toggle:AddSettings(function(s)
        s:AddDropdown("box_mode", {
            Text = "box mode",
            Values = { "2D", "Corner" },
            Default = 1,
            Callback = function(v)
                cfg.box_mode = v
                if esp_preview then esp_preview:Update({ box_mode = v }) end
            end
        })
        s:AddDropdown("box_outline_mode", {
            Text = "outline",
            Values = { "Color", "Gradient" },
            Default = 1,
            Callback = function(v)
                cfg.box_outline_mode = v
                local isGrad = (v == "Gradient")
                cfg.box_outline_gradient = isGrad
                if esp_preview then esp_preview:Update({ box_outline_mode = v, box_outline_gradient = isGrad }) end
            end
        })
        s:AddLabel("outline color"):AddColorPicker("box_outline_color_picker", {
            Default = Color3.fromRGB(0, 0, 0),
            Title = "outline color",
            Callback = function(v)
                cfg.box_outline_color = v
                if options.box_outline_color and options.box_outline_color.SetValue then
                    pcall(function() options.box_outline_color:SetValue(v) end)
                end
                if esp_preview then esp_preview:Update({ box_outline_color = v }) end
            end
        })
        local box_grad_toggle = s:AddToggle("box_gradient", {
            Text = "gradient fill",
            Default = false,
            Callback = function(v)
                cfg.box_gradient = v
                if esp_preview then esp_preview:Update({ box_gradient = v }) end
            end
        })
        box_grad_toggle:AddColorPicker("box_gradient_color", {
            Default = Color3.fromRGB(255, 255, 255),
            Title = "gradient color",
            Callback = function(v)
                cfg.box_gradient_color = v
                for _, d in pairs(ctx.drawings) do
                    local img = d.box_gradient
                    if img then pcall(function() img.Color = v end) end
                end
                if esp_preview then esp_preview:Update({ box_gradient_color = v }) end
            end
        })
        s:AddSlider("box_gradient_trans", {
            Text = "gradient transparency",
            Default = 0.85,
            Min = 0,
            Max = 1,
            Rounding = 2,
            Callback = function(v)
                cfg.box_gradient_trans = v
                for _, d in pairs(ctx.drawings) do
                    local img = d.box_gradient
                    if img then pcall(function() img.Transparency = 1 - v end) end
                end
                if esp_preview then esp_preview:Update({ box_gradient_trans = v }) end
            end
        })
    end)

    local skeleton_toggle = esp_group:AddToggle("skeleton_toggle", {
        Text = "skeleton",
        Default = false,
        Callback = function(v)
            cfg.skeleton_enabled = v
            if esp_preview then esp_preview:Update({ skeleton_enabled = v }) end
        end
    })
    skeleton_toggle:AddColorPicker("skeleton_color", {
        Default = Color3.fromRGB(255, 255, 255),
        Title = "skeleton color",
        Callback = function(v)
            cfg.skeleton_color = v
            if esp_preview then esp_preview:Update({ skeleton_color = v }) end
        end
    })
    skeleton_toggle:AddSettings(function(s)
        s:AddSlider("skeleton_thick", {
            Text = "skeleton thickness",
            Default = 1.5,
            Min = 1,
            Max = 4,
            Rounding = 1,
            Callback = function(v)
                cfg.skeleton_thick = v
                if esp_preview then esp_preview:Update({ skeleton_thick = v }) end
            end
        })
    end)

    local health_toggle = esp_group:AddToggle("health_toggle", {
        Text = "health bar",
        Default = false,
        Callback = function(v)
            cfg.health_enabled = v
            if esp_preview then esp_preview:Update({ health_enabled = v }) end
        end
    })
    health_toggle:AddColorPicker("health_color", {
        Default = Color3.fromRGB(0, 255, 128),
        Title = "health color",
        Callback = function(v)
            cfg.health_color = v
            if esp_preview then esp_preview:Update({ health_color = v }) end
        end
    })
    health_toggle:AddSettings(function(s)
        local health_grad_toggle = s:AddToggle("health_gradient", {
            Text = "gradient",
            Default = false,
            Callback = function(v)
                cfg.health_gradient = v
                if esp_preview then esp_preview:Update({ health_gradient = v }) end
            end
        })
        health_grad_toggle:AddColorPicker("health_gradient_color", {
            Default = Color3.fromRGB(105, 205, 255),
            Title = "gradient color",
            Callback = function(v)
                cfg.health_gradient_color = v
                if esp_preview then esp_preview:Update({ health_gradient_color = v }) end
            end
        })
        s:AddSlider("health_gradient_trans", {
            Text = "gradient transparency",
            Default = 0,
            Min = 0,
            Max = 1,
            Rounding = 2,
            Callback = function(v)
                cfg.health_gradient_trans = v
                if esp_preview then esp_preview:Update({ health_gradient_trans = v }) end
            end
        })
    end)

    local names_toggle = esp_group:AddToggle("names_toggle", {
        Text = "names",
        Default = false,
        Callback = function(v)
            cfg.names_enabled = v
            if esp_preview then esp_preview:Update({ name_enabled = v }) end
        end
    })
    names_toggle:AddColorPicker("names_color", {
        Default = Color3.fromRGB(255, 255, 255),
        Title = "names color",
        Callback = function(v)
            cfg.names_color = v
            if esp_preview then esp_preview:Update({ name_color = v }) end
        end
    })
    names_toggle:AddSettings(function(s)
        s:AddDropdown("name_mode", {
            Text = "name mode",
            Values = { "Display Name", "User Name", "Both" },
            Default = 1,
            Callback = function(v)
                cfg.name_mode = v
                if esp_preview then esp_preview:Update({ name_mode = v }) end
            end
        })
        local name_grad_toggle = s:AddToggle("name_gradient", {
            Text = "gradient",
            Default = false,
            Callback = function(v)
                cfg.name_gradient = v
                if esp_preview then esp_preview:Update({ name_gradient = v }) end
            end
        })
        name_grad_toggle:AddColorPicker("name_gradient_color", {
            Default = Color3.fromRGB(105, 205, 255),
            Title = "gradient color",
            Callback = function(v)
                cfg.name_gradient_color = v
                if esp_preview then esp_preview:Update({ name_gradient_color = v }) end
            end
        })
        s:AddSlider("name_gradient_trans", {
            Text = "gradient transparency",
            Default = 0,
            Min = 0,
            Max = 1,
            Rounding = 2,
            Callback = function(v)
                cfg.name_gradient_trans = v
                if esp_preview then esp_preview:Update({ name_gradient_trans = v }) end
            end
        })
        s:AddSlider("name_size", {
            Text = "text size",
            Default = 13,
            Min = 8,
            Max = 24,
            Rounding = 0,
            Callback = function(v)
                cfg.name_size = v
                for _, d in pairs(ctx.drawings) do
                    d.name.Size = v
                    if d.name_chars then
                        for _, c in ipairs(d.name_chars) do c.Size = v end
                    end
                    d.name_layout = nil
                end
            end
        })
        s:AddToggle("hide_roblox_names", {
            Text = "hide roblox names",
            Default = false,
            Callback = function(v)
                cfg.hide_names = v
                pcall(apply_hidden_names)
            end
        })
    end)

    esp_group:AddToggle("esp_weapon", {
        Text = "equipped weapon",
        Default = false,
        Callback = function(v)
            cfg.show_weapon = v
            if esp_preview then esp_preview:Update({ weapon_enabled = v }) end
        end
    })

    esp_group:AddToggle("distance_toggle", {
        Text = "distance",
        Default = false,
        Callback = function(v)
            cfg.dist_enabled = v
            if esp_preview then esp_preview:Update({ distance_enabled = v }) end
        end
    }):AddColorPicker("dist_color", {
        Default = Color3.fromRGB(255, 255, 255),
        Title = "distance color",
        Callback = function(v)
            cfg.dist_color = v
            if esp_preview then esp_preview:Update({ dist_color = v }) end
        end
    })

    local arrows_tog = esp_group:AddToggle("arrows_enabled", {
        Text = "off-screen arrows",
        Default = false,
        Callback = function(v)
            cfg.arrows_enabled = v
        end
    })
    arrows_tog:AddColorPicker("arrow_color_innocent", {
        Default = Color3.fromRGB(255, 255, 255),
        Title = "innocent color",
        Callback = function(v) cfg.arrow_color_innocent = v end
    })
    arrows_tog:AddColorPicker("arrow_color_murderer", {
        Default = Color3.fromRGB(255, 60, 60),
        Title = "murderer color",
        Callback = function(v) cfg.arrow_color_murderer = v end
    })
    arrows_tog:AddColorPicker("arrow_color_sheriff", {
        Default = Color3.fromRGB(0, 153, 255),
        Title = "sheriff color",
        Callback = function(v) cfg.arrow_color_sheriff = v end
    })
    esp_group:AddSlider("arrow_size", {
        Text = "arrow size",
        Min = 10,
        Max = 60,
        Default = 22,
        Rounding = 0,
        Callback = function(v) cfg.arrow_size = v end
    })
    esp_group:AddSlider("arrow_distance", {
        Text = "arrow distance",
        Min = 60,
        Max = 360,
        Default = 180,
        Rounding = 0,
        Callback = function(v) cfg.arrow_distance = v end
    })
    esp_group:AddToggle("arrow_outline_tog", {
        Text = "arrow outline",
        Default = true,
        Callback = function(v) cfg.arrow_outline = v end
    })

    esp_group:AddButton({
        Text = "open esp preview",
        Func = function()
            if not esp_preview then
                if build_esp_preview then
                    esp_preview = build_esp_preview(library, {
                        Title = "esp preview",
                        Icon = "eye",
                        box_enabled = cfg.box_enabled,
                        box_mode = cfg.box_mode,
                        box_color = cfg.box_color,
                        box_outline = cfg.box_outline,
                        box_outline_color = cfg.box_outline_color,
                        box_outline_mode = cfg.box_outline_mode,
                        box_outline_gradient = cfg.box_outline_gradient,
                        box_gradient = cfg.box_gradient,
                        box_gradient_color = cfg.box_gradient_color,
                        box_gradient_trans = cfg.box_gradient_trans,
                        skeleton_enabled = cfg.skeleton_enabled,
                        skeleton_color = cfg.skeleton_color,
                        skeleton_thick = cfg.skeleton_thick,
                        health_enabled = cfg.health_enabled,
                        health_color = cfg.health_color or Color3.fromRGB(0, 255, 128),
                        health_gradient = cfg.health_gradient,
                        health_gradient_color = cfg.health_gradient_color,
                        health_gradient_trans = cfg.health_gradient_trans,
                        name_enabled = cfg.names_enabled,
                        name_text = "Player",
                        name_mode = cfg.name_mode,
                        name_color = cfg.names_color,
                        name_gradient = cfg.name_gradient,
                        name_gradient_color = cfg.name_gradient_color,
                        name_gradient_trans = cfg.name_gradient_trans,
                        weapon_enabled = cfg.show_weapon,
                        weapon_text = "AK-47",
                        weapon_color = Color3.fromRGB(220, 220, 220),
                        distance_enabled = cfg.dist_enabled,
                        distance_text = "[24m]",
                        distance_color = cfg.dist_color,
                        chams_enabled = cfg.chams_enabled,
                        chams_color = cfg.chams_color,
                        chams_outline_color = cfg.chams_outline_color,
                    })
                elseif library and library.AddESPPreview then
                    pcall(function()
                        esp_preview = library:AddESPPreview({
                            Title = "esp preview",
                            Icon = "eye",
                            box_enabled = cfg.box_enabled,
                            box_mode = cfg.box_mode,
                            box_color = cfg.box_color,
                            box_gradient = cfg.box_gradient,
                            box_gradient_color = cfg.box_gradient_color,
                            box_gradient_trans = cfg.box_gradient_trans,
                            skeleton_enabled = cfg.skeleton_enabled,
                            skeleton_color = cfg.skeleton_color,
                            skeleton_thick = cfg.skeleton_thick,
                            health_enabled = cfg.health_enabled,
                            health_color = cfg.health_color or Color3.fromRGB(0, 255, 128),
                            health_gradient = cfg.health_gradient,
                            health_gradient_color = cfg.health_gradient_color,
                            health_gradient_trans = cfg.health_gradient_trans,
                            name_enabled = cfg.names_enabled,
                            name_text = "Player",
                            name_mode = cfg.name_mode,
                            name_color = cfg.names_color,
                            name_gradient = cfg.name_gradient,
                            name_gradient_color = cfg.name_gradient_color,
                            name_gradient_trans = cfg.name_gradient_trans,
                            weapon_enabled = cfg.show_weapon,
                            weapon_text = "AK-47",
                            weapon_color = Color3.fromRGB(220, 220, 220),
                            distance_enabled = cfg.dist_enabled,
                            distance_text = "[24m]",
                            distance_color = cfg.dist_color,
                            chams_enabled = cfg.chams_enabled,
                            chams_color = cfg.chams_color,
                            chams_outline_color = cfg.chams_outline_color,
                        })
                    end)
                end
            end
            if esp_preview and esp_preview.Toggle then
                esp_preview:Toggle()
            elseif esp_preview and esp_preview.Open then
                esp_preview:Open()
            elseif library and library.ESPPreview and library.ESPPreview.Toggle then
                library.ESPPreview:Toggle()
            elseif library and library.ESPPreview and library.ESPPreview.Open then
                library.ESPPreview:Open()
            end
        end
    })

    local chams_toggle = chams_group:AddToggle("chams_toggle", {
        Text = "enabled",
        Default = false,
        Callback = function(v)
            cfg.chams_enabled = v
            refresh_chams()
            if esp_preview then esp_preview:Update({ chams_enabled = v }) end
        end
    })
    chams_toggle:AddColorPicker("chams_fill", {
        Default = Color3.fromHex("#474747"),
        Title = "chams fill",
        Callback = function(v)
            cfg.chams_color = v
            chromatic_chams:update_colors()
            for _, data in pairs(player_chams_orig) do
                for part in pairs(data) do
                    if part and part.Parent then part.Color = v end
                end
            end
            for _, h in pairs(ctx.chams) do
                if h then
                    h.FillColor = v
                    if (cfg.chams_mode == "Material" and (string.lower(cfg.chams_material or "") == "forcefield 2" or string.lower(cfg.chams_material or "") == "forcefield")) then
                        h.OutlineColor = v
                    end
                end
            end
            if esp_preview then esp_preview:Update({ chams_color = v }) end
        end
    })
    chams_toggle:AddSettings(function(s)
        local mat_dropdown = nil
        local outline_label = nil
        local outline_picker = nil
        local outline_trans_slider = nil
        local fill_trans_slider = nil
        local function update_ff2_visibility()
            local hide = is_ff2_chams()
            pcall(function()
                if outline_label and outline_label.SetVisible then outline_label:SetVisible(not hide) end
                if outline_picker and outline_picker.SetVisible then outline_picker:SetVisible(not hide) end
                if outline_trans_slider and outline_trans_slider.SetVisible then outline_trans_slider:SetVisible(not hide) end
                if fill_trans_slider and fill_trans_slider.SetVisible then fill_trans_slider:SetVisible(not hide) end
            end)
        end
        s:AddDropdown("chams_mode", {
            Text = "mode",
            Values = { "Highlight", "Material" },
            Default = (cfg.chams_mode == "Material") and 2 or 1,
            Callback = function(v)
                cfg.chams_mode = v
                if mat_dropdown and mat_dropdown.SetVisible then
                    mat_dropdown:SetVisible(v == "Material")
                end
                refresh_chams()
                update_ff2_visibility()
            end
        })
        mat_dropdown = s:AddDropdown("chams_material", {
            Text = "material",
            Values = { "forcefield 2", "Foil" },
            Default = (string.lower(tostring(cfg.chams_material or "")) == "foil") and 2 or 1,
            Callback = function(v)
                cfg.chams_material = v
                chromatic_chams:update_material()
                refresh_chams()
                update_ff2_visibility()
            end
        })
        if mat_dropdown and mat_dropdown.SetVisible then
            mat_dropdown:SetVisible(cfg.chams_mode == "Material")
        end
        outline_label = s:AddLabel("outline color")
        outline_picker = outline_label:AddColorPicker("chams_outline", {
            Default = Color3.fromRGB(255, 255, 255),
            Title = "chams outline",
            Callback = function(v)
                cfg.chams_outline_color = v
                if is_ff2_chams() then return end
                for _, h in pairs(ctx.chams) do if h then h.OutlineColor = v end end
            end
        })
        outline_trans_slider = s:AddSlider("chams_outline_trans", {
            Text = "outline transparency",
            Default = 1,
            Min = 0,
            Max = 1,
            Rounding = 2,
            Callback = function(v)
                cfg.chams_outline_trans = v
                if is_ff2_chams() then return end
                for _, h in pairs(ctx.chams) do if h then h.OutlineTransparency = v end end
            end
        })
        fill_trans_slider = s:AddSlider("chams_fill_trans", {
            Text = "fill transparency",
            Default = 0.5,
            Min = 0,
            Max = 1,
            Rounding = 2,
            Callback = function(v)
                cfg.chams_fill_trans = v
                if is_ff2_chams() then return end
                for _, data in pairs(player_chams_orig) do
                    for part in pairs(data) do
                        if part and part.Parent then part.Transparency = v end
                    end
                end
                for _, h in pairs(ctx.chams) do if h then h.FillTransparency = v end end
                chromatic_chams:update_colors()
            end
        })
        update_ff2_visibility()
    end)

    local weapon_chams_toggle = weapon_group:AddToggle("weapon_chams_toggle", {
        Text = "enabled",
        Default = false,
        Callback = function(v)
            cfg.weapon_chams_enabled = v
            if not v then weapon_chams:clear() end
        end
    })
    weapon_chams_toggle:AddColorPicker("weapon_color", {
        Default = Color3.fromRGB(180, 100, 255),
        Title = "weapon color",
        Callback = function(v) cfg.weapon_chams_color = v end
    })
    weapon_chams_toggle:AddSettings(function(s)
        s:AddDropdown("weapon_chams_type", {
            Text = "material",
            Values = { "ForceField", "Glass" },
            Default = 1,
            Callback = function(v) cfg.weapon_chams_type = v end
        })
        s:AddSlider("weapon_trans", {
            Text = "transparency",
            Default = 0,
            Min = 0,
            Max = 1,
            Rounding = 2,
            Callback = function(v) cfg.weapon_chams_trans = v end
        })
    end)

    local tracer_toggle = tracers_group:AddToggle("bullet_tracer", {
        Text = "enabled",
        Default = false
    })
    tracer_toggle:AddColorPicker("tracer_color", {
        Default = Color3.fromRGB(140, 230, 255),
        Title = "tracer color"
    })
    tracer_toggle:AddSettings(function(s)
        s:AddDropdown("tracer_mode", {
            Text = "mode",
            Values = { "beam", "line" },
            Default = 1
        })
        s:AddSlider("tracer_duration", {
            Text = "duration",
            Default = 0.75,
            Min = 0.1,
            Max = 2,
            Rounding = 2,
            Suffix = "s"
        })
        s:AddSlider("tracer_width", {
            Text = "width",
            Default = 0.15,
            Min = 0.05,
            Max = 0.6,
            Rounding = 2
        })
    end)

    ambient_overlay = nil
    local function updateAmbientOverlay()
        local col = (options and options.AmbientColor and options.AmbientColor.Value) or cfg.ambient_overlay_color or Color3.fromRGB(120, 60, 200)
        local op = (options and options.AmbientOpacity and options.AmbientOpacity.Value) or cfg.ambient_opacity or 0.12
        if not ambient_overlay then
            local sg = Instance.new("ScreenGui")
            sg.Name = "VantageAmbientOverlay"
            sg.DisplayOrder = -100
            sg.IgnoreGuiInset = true
            sg.ResetOnSpawn = false
            protect_gui(sg)

            local f = Instance.new("Frame")
            f.Name = "Overlay"
            f.Size = UDim2.fromScale(1, 1)
            f.Position = UDim2.new(0, 0, 0, 0)
            f.BorderSizePixel = 0
            f.Parent = sg
            ambient_overlay = { gui = sg, frame = f }
        end
        ambient_overlay.frame.BackgroundColor3 = col
        ambient_overlay.frame.BackgroundTransparency = 1 - op
        ambient_overlay.frame.Visible = (cfg.ambient_enabled == true) and (op > 0)
    end

    -- ============================================================================
    -- NIGHT MODE LOGIC
    -- ============================================================================
    originalLightingState = nil
    originalAtmospheres = {}
    nightCCInstance = nil
    nightModeConnection = nil

    local function saveOriginalLighting()
        if originalLightingState then return end
        originalLightingState = {
            ClockTime = baseline.clock_time,
            Ambient = baseline.ambient,
            OutdoorAmbient = baseline.outdoor,
            Brightness = baseline.brightness,
            FogColor = baseline.fog_color,
            FogEnd = baseline.fog_end,
            FogStart = baseline.fog_start,
            GlobalShadows = baseline.global_shadows,
        }
        originalAtmospheres = {}
        for _, child in ipairs(lighting:GetChildren()) do
            if child:IsA("Atmosphere") then
                table.insert(originalAtmospheres, { item = child, density = child.Density })
            end
        end
    end

    restoreOriginalLighting = function()
        if nightModeConnection then
            pcall(function() nightModeConnection:Disconnect() end)
            nightModeConnection = nil
        end
        if not originalLightingState then return end
        pcall(function()
            lighting.ClockTime = originalLightingState.ClockTime
            lighting.Ambient = originalLightingState.Ambient
            lighting.OutdoorAmbient = originalLightingState.OutdoorAmbient
            lighting.Brightness = originalLightingState.Brightness
            lighting.FogColor = originalLightingState.FogColor
            lighting.FogEnd = originalLightingState.FogEnd
            lighting.FogStart = originalLightingState.FogStart
            lighting.GlobalShadows = originalLightingState.GlobalShadows
        end)
        for _, data in ipairs(originalAtmospheres) do
            if data.item and data.item.Parent then
                pcall(function() data.item.Density = data.density end)
            end
        end
        originalAtmospheres = {}
        if nightCCInstance then
            pcall(function() nightCCInstance:Destroy() end)
            nightCCInstance = nil
        end
        originalLightingState = nil
    end

    local function applyNightModeSettings()
        local Toggles = toggles or library.Toggles
        local Options = options or library.Options
        if not (Toggles.NightMode and Toggles.NightMode.Value) then return end
        if not cfg.ambient_enabled then return end

        lighting.ClockTime = 2.8
        lighting.Brightness = 1.0
        lighting.GlobalShadows = false
        lighting.Ambient = Color3.fromRGB(110, 110, 150)
        lighting.OutdoorAmbient = Color3.fromRGB(90, 90, 130)

        for _, child in ipairs(lighting:GetChildren()) do
            if child:IsA("Atmosphere") then
                pcall(function() child.Density = 0 end)
            end
        end

        local fogColor = Options.NightFogColor and Options.NightFogColor.Value or Color3.fromRGB(10, 10, 25)
        local fogEnd = Options.NightFogEnd and Options.NightFogEnd.Value or 1500
        lighting.FogColor = fogColor
        lighting.FogEnd = fogEnd
        lighting.FogStart = 0

        if not nightCCInstance or nightCCInstance.Parent ~= lighting then
            if nightCCInstance then pcall(function() nightCCInstance:Destroy() end) end
            nightCCInstance = Instance.new("ColorCorrectionEffect")
            nightCCInstance.Name = "VantageNightCC"
            nightCCInstance.Parent = lighting
        end

        local sat = Options.NightSaturation and Options.NightSaturation.Value or -0.5
        local con = Options.NightContrast and Options.NightContrast.Value or 0.02

        nightCCInstance.TintColor = Color3.fromRGB(220, 230, 255)
        nightCCInstance.Saturation = sat
        nightCCInstance.Contrast = con
        nightCCInstance.Enabled = true
    end

    local updateNightMode
    updateNightMode = function()
        local Toggles = toggles or library.Toggles
        if not (Toggles.NightMode and Toggles.NightMode.Value) or not cfg.ambient_enabled then
            restoreOriginalLighting()
            if cfg.ambient_enabled then
                world:apply()
            end
            return
        end

        saveOriginalLighting()
        applyNightModeSettings()

        if not nightModeConnection then
            nightModeConnection = run_service.Heartbeat:Connect(function()
                local Toggles = toggles or library.Toggles
                if Toggles.NightMode and Toggles.NightMode.Value and cfg.ambient_enabled then
                    applyNightModeSettings()
                else
                    restoreOriginalLighting()
                end
            end)
            table.insert(ctx.conns, nightModeConnection)
        end
    end

    destroyBacktrackGhost = function() end

    local shaders_toggle = ambient_group:AddToggle("shaders_toggle", {
        Text = "shaders",
        Default = false,
        Callback = function(v)
            cfg.shaders_enabled = v
            if v then
                shaders:apply(cfg.shaders_preset or "morning")
            else
                shaders:reset()
            end
        end
    })
    shaders_toggle:AddSettings(function(s)
        s:AddDropdown("shaders_preset", {
            Text = "preset",
            Values = { "morning", "midday", "evening", "night" },
            Default = 1,
            Callback = function(v)
                cfg.shaders_preset = v
                if cfg.shaders_enabled then
                    shaders:apply(v)
                end
            end
        })
        s:AddSlider("shaders_brightness", {
            Text = "brightness",
            Default = 1.0,
            Min = 0.5,
            Max = 3.0,
            Rounding = 2,
            Callback = function(v)
                cfg.shaders_brightness = v
                if cfg.shaders_enabled then
                    shaders:apply(cfg.shaders_preset or "morning")
                end
            end
        })
        s:AddSlider("shaders_exposure", {
            Text = "exposure compensation",
            Default = 0.0,
            Min = -1.0,
            Max = 2.0,
            Rounding = 2,
            Callback = function(v)
                cfg.shaders_exposure = v
                if cfg.shaders_enabled then
                    shaders:apply(cfg.shaders_preset or "morning")
                end
            end
        })
    end)

    local ambient_toggle = ambient_group:AddToggle("ambient_toggle", {
        Text = "ambient",
        Default = false,
        Callback = function(v)
            cfg.ambient_enabled = v
            if v then
                world:apply()
                updateAmbientOverlay()
                updateNightMode()
            else
                updateNightMode()
                world:apply()
                updateAmbientOverlay()
            end
        end
    })
    ambient_toggle:AddColorPicker("ambient_col", {
        Default = Color3.fromHex("#919090"),
        Title = "ambient color",
        Callback = function(v)
            cfg.ambient_color = v
            world:apply()
        end
    })
    ambient_toggle:AddSettings(function(s)
        -- Night Mode
        local night_toggle = s:AddToggle("NightMode", {
            Text = "night mode",
            Default = true,
            Callback = function(v)
                updateNightMode()
            end
        })
        night_toggle:AddColorPicker("NightFogColor", {
            Default = Color3.fromRGB(10, 10, 25),
            Title = "night fog color",
            Callback = function(v)
                updateNightMode()
            end
        })
        s:AddSlider("NightFogEnd", {
            Text = "fog end",
            Default = 600,
            Min = 200,
            Max = 5000,
            Rounding = 0,
            Callback = function(v)
                updateNightMode()
            end
        })
        s:AddSlider("NightSaturation", {
            Text = "night saturation",
            Default = -0.5,
            Min = -1.0,
            Max = 1.0,
            Rounding = 2,
            Callback = function(v)
                updateNightMode()
            end
        })
        s:AddSlider("NightContrast", {
            Text = "night contrast",
            Default = 0.02,
            Min = -0.5,
            Max = 0.5,
            Rounding = 2,
            Callback = function(v)
                updateNightMode()
            end
        })
        pcall(updateNightMode)

        -- Ambient Overlay
        s:AddLabel("overlay color"):AddColorPicker("AmbientColor", {
            Default = Color3.fromHex("#6e4696"),
            Title = "overlay color",
            Callback = function(v)
                updateAmbientOverlay()
            end
        })
        s:AddSlider("AmbientOpacity", {
            Text = "overlay opacity",
            Default = 0.12,
            Min = 0.02,
            Max = 0.45,
            Rounding = 2,
            Compact = false,
            Callback = function(v)
                updateAmbientOverlay()
            end
        })

        -- World Lighting
        s:AddLabel("outdoor color"):AddColorPicker("outdoor_col", {
            Default = Color3.fromHex("#5a3782"),
            Title = "outdoor color",
            Callback = function(v)
                cfg.outdoor_color = v
                world:apply()
            end
        })
        s:AddSlider("clock_time", {
            Text = "clock time",
            Default = 0,
            Min = 0,
            Max = 24,
            Rounding = 1,
            Callback = function(v)
                cfg.clock_time = v
                world:apply()
            end
        })
        s:AddLabel("fog color"):AddColorPicker("ambient_fog_col", {
            Default = Color3.fromHex("#3c1e5f"),
            Title = "fog color",
            Callback = function(v)
                cfg.fog_color = v
                world:apply()
            end
        })
        s:AddSlider("ambient_bloom_sl", {
            Text = "bloom intensity",
            Default = 0.75,
            Min = 0,
            Max = 2.0,
            Rounding = 2,
            Callback = function(v)
                cfg.ambient_bloom = v
                world:apply()
            end
        })
        s:AddSlider("ambient_sat_sl", {
            Text = "saturation",
            Default = 0.25,
            Min = -0.5,
            Max = 1.0,
            Rounding = 2,
            Callback = function(v)
                cfg.ambient_saturation = v
                world:apply()
            end
        })
    end)

    local particles_toggle = ambient_group:AddToggle("particles_toggle", {
        Text = "particles",
        Default = false,
        Callback = function(v)
            cfg.particles_enabled = v
            particles:init()
        end
    })
    particles_toggle:AddColorPicker("particles_col", {
        Default = Color3.fromRGB(220, 170, 255),
        Title = "particles color",
        Callback = function(v)
            cfg.particles_color = v
            particles:update_colors()
        end
    })
    particles_toggle:AddSettings(function(s)
        s:AddDropdown("particle_texture", {
            Text = "texture",
            Values = { "snowflake", "star", "sparkle", "dollar", "cash", "sakura" },
            Default = 1,
            Callback = function(v)
                cfg.particle_texture = v
                particles:init()
            end
        })
        s:AddDropdown("particle_flight", {
            Text = "flight mode",
            Values = { "wind", "down", "up", "up/down", "random", "rain" },
            Default = 1,
            Callback = function(v)
                cfg.particle_flight = v
                particles:update_flight()
            end
        })
        s:AddSlider("particle_wind", {
            Text = "wind strength",
            Default = 1,
            Min = 0,
            Max = 5,
            Rounding = 1,
            Callback = function(v)
                cfg.particle_wind = v
            end
        })
        s:AddToggle("particle_collide", {
            Text = "collisions",
            Default = false,
            Callback = function(v)
                cfg.particle_collide = v
                particles:init()
            end
        })
        s:AddSlider("particles_amount", {
            Text = "amount",
            Default = 23,
            Min = 5,
            Max = 80,
            Rounding = 0,
            Callback = function(v)
                cfg.particles_count = v
                particles:update_rate()
            end
        })
        s:AddSlider("particles_size", {
            Text = "size",
            Default = 0.45,
            Min = 0.1,
            Max = 1.5,
            Rounding = 2,
            Callback = function(v)
                cfg.particles_size = v
                particles:update_size()
            end
        })
        s:AddSlider("particles_trans", {
            Text = "transparency",
            Default = 0.1,
            Min = 0,
            Max = 1,
            Rounding = 2,
            Callback = function(v)
                cfg.particles_trans = v
                particles:update_trans()
            end
        })
    end)

    local skybox_toggle = skybox_group:AddToggle("skybox_toggle", {
        Text = "enabled",
        Default = false,
        Callback = function(v)
            cfg.skybox_enabled = v
            skybox:apply()
        end
    })
    skybox_toggle:AddSettings(function(s)
        s:AddDropdown("skybox_preset", {
            Text = "preset",
            Values = { "Jungle", "Blossom", "Red night", "Purple default", "Foggy", "Galaxy", "Anime", "Minecraft", "Anime Sky", "Pastel Anime", "City Sky" },
            Default = 1,
            Callback = function(v)
                cfg.skybox_preset = v
                skybox:apply()
            end
        })
    end)

    local camera_toggle = camera_group:AddToggle("custom_fov_toggle", {
        Text = "custom fov",
        Default = false,
        Callback = function(v)
            cfg.custom_fov_enabled = v
            if not v then
                camera.FieldOfView = baseline.fov
            else
                camera.FieldOfView = cfg.custom_fov
            end
        end
    })
    camera_toggle:AddSettings(function(s)
        s:AddSlider("custom_fov_slider", {
            Text = "field of view",
            Default = 90,
            Min = 60,
            Max = 120,
            Rounding = 0,
            Callback = function(v)
                cfg.custom_fov = v
                if cfg.custom_fov_enabled then
                    camera.FieldOfView = v
                end
            end
        })
    end)

    local self_group = tabs.visuals:AddRightGroupbox("self visuals")

    local self_chams_toggle = self_group:AddToggle("self_chams_toggle", {
        Text = "self chams",
        Default = false,
        Callback = function(v)
            cfg.self_chams_enabled = v
            if not v then self_chams:reset() end
        end
    })
    self_chams_toggle:AddColorPicker("self_chams_col", {
        Default = Color3.fromHex("#b464ff"),
        Title = "self chams color",
        Callback = function(v) cfg.self_chams_color = v end
    })
    self_chams_toggle:AddSettings(function(s)
        s:AddDropdown("self_chams_mode", {
            Text = "mode",
            Values = { "Forcefield 2", "Forcefield", "Highlight" },
            Default = 1,
            Callback = function(v) cfg.self_chams_mode = v end
        })
        s:AddSlider("self_chams_trans", {
            Text = "transparency",
            Default = 0.6,
            Min = 0,
            Max = 1,
            Rounding = 2,
            Callback = function(v)
                cfg.self_chams_trans = v
                if is_ff2_chams() then refresh_chams() end
            end
        })
    end)

    local china_hat_toggle = self_group:AddToggle("china_hat_toggle", {
        Text = "china hat",
        Default = false,
        Callback = function(v)
            cfg.china_hat_enabled = v
            if not v then china_hat:hide() end
        end
    })
    china_hat_toggle:AddColorPicker("china_hat_col", {
        Default = Color3.fromHex("#b464ff"),
        Title = "china hat color",
        Callback = function(v) cfg.china_hat_color = v end
    })
    china_hat_toggle:AddSettings(function(s)
        local ch_speed_slider, ch_drop_slider

        local function update_ch_mode_visibility(mode)
            local is_3d = (mode == "3D")
            pcall(function()
                if ch_speed_slider and ch_speed_slider.SetVisible then
                    ch_speed_slider:SetVisible(is_3d)
                end
                if ch_drop_slider and ch_drop_slider.SetVisible then
                    ch_drop_slider:SetVisible(not is_3d)
                end
            end)
        end

        s:AddDropdown("china_hat_mode", {
            Text = "mode",
            Values = { "3D", "2D" },
            Default = 1,
            Callback = function(v)
                cfg.china_hat_mode = v
                if v == "3D" then
                    china_hat:hide_2d()
                else
                    china_hat:hide()
                end
                update_ch_mode_visibility(v)
            end
        })
        s:AddSlider("china_hat_radius", {
            Text = "radius",
            Default = 1.55,
            Min = 0.5,
            Max = 4.0,
            Rounding = 2,
            Callback = function(v)
                cfg.china_hat_radius = v
                ch_2d_rebuild_trig(v)
            end
        })
        s:AddSlider("china_hat_height", {
            Text = "height",
            Default = 0.82,
            Min = 0.1,
            Max = 3.0,
            Rounding = 2,
            Callback = function(v) cfg.china_hat_height = v end
        })
        ch_drop_slider = s:AddSlider("china_hat_drop", {
            Text = "drop",
            Default = 0.02,
            Min = -0.5,
            Max = 1.0,
            Rounding = 2,
            Callback = function(v) cfg.china_hat_drop = v end
        })
        s:AddSlider("china_hat_trans", {
            Text = "transparency",
            Default = 0.4,
            Min = 0.0,
            Max = 1.0,
            Rounding = 2,
            Callback = function(v) cfg.china_hat_trans = v end
        })
        ch_speed_slider = s:AddSlider("china_hat_speed", {
            Text = "rotation speed",
            Default = 2.0,
            Min = 0,
            Max = 6.0,
            Rounding = 1,
            Callback = function(v) cfg.china_hat_speed = v end
        })

        update_ch_mode_visibility(cfg.china_hat_mode or "3D")
    end)

    local auras_toggle = self_group:AddToggle("auras_toggle", {
        Text = "auras",
        Default = false,
        Callback = function(v)
            cfg.auras_enabled = v
            if v then
                auras:apply()
            else
                auras:clear()
            end
        end
    })
    auras_toggle:AddColorPicker("auras_col", {
        Default = Color3.fromRGB(133, 220, 255),
        Title = "aura color",
        Callback = function(v)
            cfg.aura_color = v
            auras:set_color(v)
        end
    })
    auras_toggle:AddSettings(function(s)
        s:AddDropdown("aura_type", {
            Text = "style",
            Values = auras.list,
            Default = 1,
            Callback = function(v)
                cfg.aura_type = v
                if cfg.auras_enabled then
                    auras:apply()
                end
            end
        })
    end)

    local anim_toggle = self_group:AddToggle("custom_anims_toggle", {
        Text = "custom animations",
        Default = false,
        Callback = function(v)
            cfg.custom_anims_enabled = v
            if v then
                anim_manager:reapply_all()
            else
                anim_manager:revert("all")
            end
            anim_ui:update_state()
        end
    })
    options.custom_anim_pack = {
        Value = cfg.custom_anim_pack,
        SetValue = function(self, val, slot)
            cfg.custom_anim_pack = val
            self.Value = val
            if slot then cfg.custom_anim_slot = slot end
            if cfg.custom_anims_enabled then
                anim_manager:apply(val, cfg.custom_anim_slot or "all")
            end
            anim_ui:update_state()
        end
    }
    local backtrack_toggle = self_group:AddToggle("backtrack_enabled", {
        Text = "backtrack",
        Default = false,
        Callback = function(v)
            cfg.backtrack_enabled = v
            if not v and backtrack then
                backtrack:clear()
            end
        end
    })
    backtrack_toggle:AddColorPicker("backtrack_color", {
        Default = Color3.fromRGB(130, 90, 230),
        Title = "backtrack color",
        Callback = function(v)
            cfg.backtrack_color = v
        end
    })
    backtrack_toggle:AddSettings(function(s)
        s:AddSlider("backtrack_trans", {
            Text = "transparency",
            Default = 0.4,
            Min = 0.1,
            Max = 0.9,
            Rounding = 2,
            Callback = function(v)
                cfg.backtrack_trans = v
            end
        })
    end)

    self_group:AddButton({
        Text = "open animation catalog",
        Func = function()
            anim_ui:toggle()
        end
    })
    self_group:AddButton({
        Text = "open emote catalog",
        Func = function()
            emote_ui:toggle()
        end
    })
    self_group:AddButton({
        Text = "stop emote",
        Func = function()
            emote_manager:stop()
        end
    })

    self_group:AddDivider()
    self_group:AddLabel("fake")

    local fake_korblox_toggle = self_group:AddToggle("fake_korblox", {
        Text = "fake korblox",
        Default = false,
        Callback = function(v)
            cfg.fake_korblox = v
            fe_cosmetics:update()
            if backtrack then pcall(function() backtrack:clear() end) end
            master_clean_dummy_template = nil
            if anim_ui and anim_ui.update_state then pcall(function() anim_ui:update_state() end) end
            if emote_ui and emote_ui.init then
                local cat = emote_ui:init()
                if cat and cat.RefreshPreview then pcall(cat.RefreshPreview, cat) end
            end
        end
    })

    local fake_headless_toggle = self_group:AddToggle("fake_headless", {
        Text = "fake headless",
        Default = false,
        Callback = function(v)
            cfg.fake_headless = v
            fe_cosmetics:update()
            if backtrack then pcall(function() backtrack:clear() end) end
            master_clean_dummy_template = nil
            if anim_ui and anim_ui.update_state then pcall(function() anim_ui:update_state() end) end
            if emote_ui and emote_ui.init then
                local cat = emote_ui:init()
                if cat and cat.RefreshPreview then pcall(cat.RefreshPreview, cat) end
            end
        end
    })

    local menu_group = tabs.config:AddGroupbox({ Side = 1, Name = "menu settings", DisableCollapsing = true })
    menu_group:AddToggle("keybind_menu", {
        Text = "open keybind menu",
        Default = library.KeybindFrame.Visible,
        Callback = function(v) library.KeybindFrame.Visible = v end
    })
    menu_group:AddDropdown("notif_side", {
        Text = "notification side",
        Values = { "left", "right" },
        Default = "right",
        Callback = function(v) library:SetNotifySide(v) end
    })
    menu_group:AddToggle("click_sounds", {
        Text = "click sounds",
        Default = true,
        Callback = function(v) library.ClickSoundsEnabled = v end
    })
    menu_group:AddSlider("click_volume", {
        Text = "click volume",
        Default = 50,
        Min = 0,
        Max = 100,
        Suffix = "%",
        Callback = function(v) library.ClickSoundVolume = v / 100 end
    })
    menu_group:AddToggle("watermark", {
        Text = "watermark",
        Default = true,
        Callback = function(v) library:SetWatermarkVisibility(v) end
    })
    menu_group:AddDropdown("watermark_pos", {
        Text = "watermark position",
        Values = { "top-left", "top-right", "top-center", "bottom-left", "bottom-right" },
        Default = "top-center",
        Callback = function(v) library:SetWatermarkPosition(v) end
    })
    menu_group:AddDropdown("watermark_items", {
        Text = "watermark info",
        Values = { "executor", "name", "fps", "ping", "game" },
        Multi = true,
        Default = { executor = true, name = true, fps = true, ping = true, game = false },
        Callback = function(v) library:SetWatermarkOptions(v) end
    })

    local name_protect_input
    menu_group:AddToggle("name_protect", {
        Text = "name protect",
        Default = false,
        Callback = function(v)
            library:SetNameProtect(v, (options.name_protect_text and options.name_protect_text.Value) or "vantage")
            if name_protect_input then name_protect_input:SetVisible(v) end
        end
    })
    name_protect_input = menu_group:AddInput("name_protect_text", {
        Text = "protected name",
        Default = "vantage",
        Visible = false,
        Callback = function(v)
            if toggles.name_protect and toggles.name_protect.Value then
                library:SetNameProtect(true, v)
            end
        end
    })

    menu_group:AddLabel("menu bind"):AddKeyPicker("menu_bind", {
        Default = "RightShift",
        NoUI = true,
        Text = "menu keybind"
    })
    library.ToggleKeybind = options.menu_bind

    menu_group:AddButton({
        Text = "unload",
        Func = function()
            task.spawn(function()
                if unload then unload() end
            end)
        end
    })

    local watermark_conn = run_service.RenderStepped:Connect(function()
        if not ctx.running then return end
        pcall(function()
            if typeof(library.SetWatermark) == "function" then
                local fps = math.floor(workspace:GetRealPhysicsFPS())
                local ping = 0
                pcall(function() ping = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()) end)
                library:SetWatermark(string.format("vantage | fps: %d | ping: %dms", fps, ping))
            end
        end)
    end)
    table.insert(ctx.conns, watermark_conn)
end

table.insert(ctx.conns, players.PlayerRemoving:Connect(function(player)
    clear_chams(player)
    chromatic_chams:remove_player(player)
    clear_player_drawings(player)
    if ctx.esp_miss then ctx.esp_miss[player] = nil end
    if ctx.esp_bones then ctx.esp_bones[player] = nil end
    if ctx.hidden_names then ctx.hidden_names[player] = nil end
    rebuild_roster()
end))

local function on_character_added(p, char)
    if p == local_player or not cfg.chams_enabled then return end
    task.spawn(function()
        pcall(function() char:WaitForChild("HumanoidRootPart", 5) end)
        task.wait(0.1)
        if not ctx.running or not cfg.chams_enabled then return end
        if p.Character == char then
            apply_player_chams(p)
        end
    end)
end

table.insert(ctx.conns, players.PlayerAdded:Connect(function(player)
    rebuild_roster()
    table.insert(ctx.conns, player.CharacterAdded:Connect(function(char)
        on_character_added(player, char)
    end))
end))

for _, p in ipairs(players:GetPlayers()) do
    if p ~= local_player then
        table.insert(ctx.conns, p.CharacterAdded:Connect(function(char)
            on_character_added(p, char)
        end))
    end
end
rebuild_roster()

local anim_watchdog = {
    last_check = 0,
    no_tracks_counter = 0,
}

local function check_and_recover_animations(now)
    if (now - anim_watchdog.last_check) < 0.35 then return end
    anim_watchdog.last_check = now

    local char = local_player and local_player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end

    if fe_cosmetics and (cfg.fake_korblox or cfg.fake_headless) then
        pcall(function() fe_cosmetics:update(char) end)
    end

    local animate = char:FindFirstChild("Animate")
    if not animate then return end

    if not animate.Enabled then
        pcall(function() animate.Enabled = true end)
    end

    if emote_manager and emote_manager.is_playing then
        if not emote_manager.looped and hum.MoveDirection.Magnitude > 0.05 then
            emote_manager:stop()
        end
        return
    end

    if cfg.custom_anims_enabled and anim_manager and next(anim_manager.active_slots) then
        local needs_reapply = false
        for slot, pack_name in pairs(anim_manager.active_slots) do
            if pack_name and pack_name ~= "Default" then
                local fName = (slot == "idle" and "idle") or (slot == "walk" and "walk") or (slot == "run" and "run") or (slot == "jump" and "jump") or (slot == "fall" and "fall") or (slot == "climb" and "climb") or (slot == "swim" and "swim")
                local f = fName and animate:FindFirstChild(fName)
                local a = f and f:FindFirstChildOfClass("Animation")
                if a and a.AnimationId ~= "" then
                    local num = tostring(a.AnimationId):match("%d+")
                    if num and anim_manager.clean_id_set and anim_manager.clean_id_set[num] then
                        needs_reapply = true
                        break
                    end
                end
            end
        end
        if needs_reapply then
            anim_manager:reapply_all(true)
        end
    end
end

local function setup_character_animations(char)
    if not char then return end
    if backtrack then
        pcall(function() backtrack:clear() end)
    end
    if fe_cosmetics then
        pcall(function()
            fe_cosmetics:clean_stale()
            fe_cosmetics:update(char)
        end)
    end

    local cosmetic_parts = {
        Head = true,
        RightUpperLeg = true,
        RightLowerLeg = true,
        RightFoot = true,
        ["Right Leg"] = true
    }

    local function try_apply(skip_track_stop)
        local hum = char:FindFirstChildOfClass("Humanoid")
        local animate = char:FindFirstChild("Animate")
        if not hum or not animate or hum.Health <= 0 then return false end
        local idle = animate:FindFirstChild("idle")
        local run = animate:FindFirstChild("run")
        if not idle or not run then return false end
        if fe_cosmetics and char == local_player.Character then
            pcall(function() fe_cosmetics:update(char) end)
        end
        anim_manager:save_original(animate)
        if cfg.custom_anims_enabled and char == local_player.Character then
            anim_manager:reapply_all(skip_track_stop)
        end
        return true
    end

    local function check_part_cosmetic(p)
        if cosmetic_parts[p.Name] and (cfg.fake_korblox or cfg.fake_headless) then
            pcall(function() fe_cosmetics:update(char) end)
        end
    end

    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("BasePart") then check_part_cosmetic(child) end
    end

    task.spawn(function()
        local hum = char:WaitForChild("Humanoid", 15)
        local animate = char:WaitForChild("Animate", 15)
        if not hum or not animate then return end

        animate:WaitForChild("idle", 10)
        animate:WaitForChild("run", 10)
        task.wait(0.15)

        anim_manager:save_original(animate)
        try_apply(false)

        task.delay(0.4, function()
            if char == local_player.Character and hum.Health > 0 then try_apply(true) end
        end)
        task.delay(1.0, function()
            if char == local_player.Character and hum.Health > 0 then try_apply(true) end
        end)
        task.delay(1.8, function()
            if char == local_player.Character and hum.Health > 0 then try_apply(true) end
        end)

        table.insert(ctx.conns, hum.Running:Connect(function()
            if cfg.custom_anims_enabled then
                check_and_recover_animations(os.clock() + 2)
            end
        end))

        table.insert(ctx.conns, hum.AnimationPlayed:Connect(function(track)
            if not cfg.custom_anims_enabled then return end
            local name = track.Name:lower()
            local animName = track.Animation and track.Animation.Name:lower() or ""
            local parentName = track.Animation and track.Animation.Parent and track.Animation.Parent.Name:lower() or ""
            if name:find("idle") or animName:find("idle") or parentName == "idle" then
                track.Looped = true
            end
        end))
    end)

    table.insert(ctx.conns, char.DescendantAdded:Connect(function(child)
        if child:IsA("BasePart") and cosmetic_parts[child.Name] then
            task.defer(function()
                if char.Parent and (cfg.fake_korblox or cfg.fake_headless) then
                    pcall(function() fe_cosmetics:update(char) end)
                end
            end)
        elseif child:IsA("Decal") and child.Parent and child.Parent.Name == "Head" then
            if cfg.fake_headless then
                child.Transparency = 1
            end
        elseif child.Name == "Animate" then
            task.wait(0.15)
            try_apply(true)
        elseif child:IsA("Tool") then
            task.delay(0.12, function()
                if cfg.custom_anims_enabled then
                    check_and_recover_animations(os.clock() + 2)
                end
            end)
        end
    end))

    table.insert(ctx.conns, char.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") then
            task.delay(0.12, function()
                if cfg.custom_anims_enabled then
                    check_and_recover_animations(os.clock() + 2)
                end
            end)
        end
    end))
end

table.insert(ctx.conns, local_player.CharacterAdded:Connect(function(char)
    setup_character_animations(char)
    if cfg.shaders_enabled and shaders then
        task.defer(function()
            shaders:apply(cfg.shaders_preset or "morning")
        end)
    end
    if cfg.auras_enabled and auras then
        task.defer(function()
            auras:apply()
        end)
    end
end))
if local_player.CharacterAppearanceLoaded then
    table.insert(ctx.conns, local_player.CharacterAppearanceLoaded:Connect(function(char)
        if char == local_player.Character then
            if fe_cosmetics then pcall(function() fe_cosmetics:update(char) end) end
            if cfg.custom_anims_enabled then
                anim_manager:reapply_all(true)
            end
        end
    end))
end
if local_player.Character then
    setup_character_animations(local_player.Character)
end

table.insert(ctx.conns, run_service.RenderStepped:Connect(function(dt)
    if not ctx.running then return end

    pcall(function() weapon_chams:render() end)
    pcall(function() chromatic_chams:render(dt) end)
    pcall(function() self_chams:render() end)
    pcall(function() china_hat:render(dt) end)
    pcall(function() auras:render() end)
    pcall(function() backtrack:render() end)
    pcall(function() particles:render() end)

    if cfg.shaders_enabled then
        local now = os.clock()
        if now - shaders.last_tick >= 1.0 then
            shaders.last_tick = now
            pcall(function() shaders:apply(cfg.shaders_preset or "morning") end)
        end
    end

    if cfg.hide_names then
        local names_now = os.clock()
        if (names_now - (ctx.names_t or 0)) > 1 then
            ctx.names_t = names_now
            pcall(apply_hidden_names)
        end
    end

    pcall(check_and_recover_animations, os.clock())

    if not cfg.esp_enabled then
        for _, d in pairs(ctx.drawings) do hide_drawings(d) end
        return
    end

    local cur_cam = workspace.CurrentCamera
    if not cur_cam then return end
    local cam_pos = cur_cam.CFrame.Position

    for _, player in ipairs(ctx.roster) do
        if player == local_player then
            if ctx.drawings[player] then hide_drawings(ctx.drawings[player]) end
        else
            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local head = char and char:FindFirstChild("Head")

            local assembled = false
            if char and root and hum and head and hum.Health > 0 then
                local parts = 0
                for _, c in ipairs(char:GetChildren()) do
                    if c:IsA("BasePart") then
                        parts = parts + 1
                        if parts >= 6 then break end
                    end
                end
                assembled = parts >= 6
            end

            if not assembled then
                hide_debounced(player)
            else
                local p_role = get_player_role(player)
                local p_role_col = get_role_color(p_role)

                local filter_mode = cfg.role_filter or "all"
                local pass_filter = true
                if filter_mode == "murderer only" and p_role ~= "murderer" then
                    pass_filter = false
                elseif filter_mode == "sheriff only" and p_role ~= "sheriff" then
                    pass_filter = false
                elseif filter_mode == "roles only" and p_role == "innocent" then
                    pass_filter = false
                end

                local dist = (cam_pos - root.Position).Magnitude
                if dist > cfg.max_dist or not pass_filter then
                    hide_debounced(player)
                else
                    local corners_3d = get_char_bounds(char)
                    local min_x, min_y = math.huge, math.huge
                    local max_x, max_y = -math.huge, -math.huge
                    local any_on_screen = false

                    for _, corner in ipairs(corners_3d) do
                        local pos, on_screen = cur_cam:WorldToViewportPoint(corner)
                        if pos.Z > 0 then
                            if pos.X < min_x then min_x = pos.X end
                            if pos.X > max_x then max_x = pos.X end
                            if pos.Y < min_y then min_y = pos.Y end
                            if pos.Y > max_y then max_y = pos.Y end
                            if on_screen then any_on_screen = true end
                        end
                    end

                    if not any_on_screen or min_x >= max_x or min_y >= max_y then
                        -- off-screen: draw arrow indicator if enabled
                        if cfg.arrows_enabled and cfg.esp_enabled then
                            local d = get_drawings(player)
                            if d.arrow then
                                local vp = cur_cam.ViewportSize
                                local cx, cy = vp.X * 0.5, vp.Y * 0.5
                                local proj = cur_cam:WorldToViewportPoint(root.Position)
                                local dx = proj.X - cx
                                local dy = proj.Y - cy
                                if proj.Z < 0 then dx, dy = -dx, -dy end
                                local len = math.sqrt(dx * dx + dy * dy)
                                if len < 0.001 then len = 0.001 end
                                local nx, ny = dx / len, dy / len

                                local dist_px = cfg.arrow_distance or 180
                                local margin = 24
                                local sx = math.clamp(cx + nx * dist_px, margin, vp.X - margin)
                                local sy = math.clamp(cy + ny * dist_px, margin, vp.Y - margin)

                                -- Image Drawing uses Rotation in degrees; arrow PNG points right (0°)
                                -- atan2 gives radians from +X axis, convert to degrees
                                local angle_deg = math.deg(math.atan2(ny, nx))
                                local sz = cfg.arrow_size or 22

                                local p_role = get_player_role(player)
                                local arrow_col
                                if cfg.role_colors_enabled then
                                    arrow_col = get_role_color(p_role)
                                elseif p_role == "murderer" then
                                    arrow_col = cfg.arrow_color_murderer
                                elseif p_role == "sheriff" then
                                    arrow_col = cfg.arrow_color_sheriff
                                else
                                    arrow_col = cfg.arrow_color_innocent
                                end

                                pcall(function()
                                    if cfg.arrow_outline and d.arrow_outline then
                                        local osz = sz + 4
                                        d.arrow_outline.Size = Vector2.new(osz, osz)
                                        d.arrow_outline.Position = Vector2.new(sx - osz * 0.5, sy - osz * 0.5)
                                        d.arrow_outline.Rotation = angle_deg
                                        d.arrow_outline.Visible = true
                                    else
                                        if d.arrow_outline then d.arrow_outline.Visible = false end
                                    end

                                    d.arrow.Size = Vector2.new(sz, sz)
                                    d.arrow.Position = Vector2.new(sx - sz * 0.5, sy - sz * 0.5)
                                    d.arrow.Rotation = angle_deg
                                    d.arrow.Color = arrow_col
                                    d.arrow.Visible = true
                                end)
                            end
                        else
                            local d = ctx.drawings[player]
                            if d and d.arrow then d.arrow.Visible = false end
                            if d and d.arrow_outline then d.arrow_outline.Visible = false end
                        end
                        hide_debounced(player)
                    else
                        local d = get_drawings(player)
                        ctx.esp_miss = ctx.esp_miss or {}
                        ctx.esp_miss[player] = 0
                        d.visible = true
                        -- hide off-screen arrows when player is visible
                        if d.arrow then d.arrow.Visible = false end
                        if d.arrow_outline then d.arrow_outline.Visible = false end

                        local raw_w = math.max(max_x - min_x, 1)
                        local h = math.floor(max_y - min_y)
                        local center_x = math.floor(min_x + raw_w / 2)
                        local target_w = math.clamp(h * 0.48, math.min(6, raw_w), math.max(6, raw_w))
                        local w = math.floor(target_w)
                        local box_x = math.floor(center_x - w / 2)
                        local box_y = math.floor(min_y)

                        if cfg.box_enabled then
                            local isOutlineGrad = (cfg.box_outline_mode == "Gradient" or cfg.box_outline_gradient == true)
                            local outlineCol = cfg.box_outline_color or Color3.fromRGB(0, 0, 0)
                            if isOutlineGrad then
                                local gradCol = cfg.box_gradient_color or Color3.fromRGB(255, 255, 255)
                                outlineCol = cfg.box_color:Lerp(gradCol, 0.5)
                            end
                            local showOutline = (cfg.box_outline ~= false)

                            local active_box_col = cfg.role_colors_enabled and p_role_col or cfg.box_color
                            if cfg.box_mode == "2D" then
                                d.box.Size = Vector2.new(w, h)
                                d.box.Position = Vector2.new(box_x, box_y)
                                d.box.Color = active_box_col
                                d.box.Visible = true

                                if showOutline and d.box_outline then
                                    d.box_outline.Position = Vector2.new(box_x - 1, box_y - 1)
                                    d.box_outline.Size = Vector2.new(w + 2, h + 2)
                                    d.box_outline.Color = outlineCol
                                    d.box_outline.Visible = true

                                    if w >= 6 and h >= 6 and d.box_outline_in then
                                        d.box_outline_in.Position = Vector2.new(box_x + 1, box_y + 1)
                                        d.box_outline_in.Size = Vector2.new(w - 2, h - 2)
                                        d.box_outline_in.Color = outlineCol
                                        d.box_outline_in.Visible = true
                                    elseif d.box_outline_in then
                                        d.box_outline_in.Visible = false
                                    end
                                else
                                    if d.box_outline then d.box_outline.Visible = false end
                                    if d.box_outline_in then d.box_outline_in.Visible = false end
                                end

                                for _, l in ipairs(d.corners) do l.Visible = false end
                                if d.corner_outlines then
                                    for _, l in ipairs(d.corner_outlines) do l.Visible = false end
                                end

                                sync_box_grad(d, box_x, box_y, w, h, cfg.box_gradient == true)
                            else
                                d.box.Visible = false
                                if d.box_outline then d.box_outline.Visible = false end
                                if d.box_outline_in then d.box_outline_in.Visible = false end

                                sync_box_grad(d, box_x, box_y, w, h, cfg.box_gradient == true)

                                local cl = math.clamp(math.floor(math.min(w, h) * 0.25), 3, 15)
                                local c = d.corners
                                local co = d.corner_outlines
                                local col = active_box_col

                                local fromTo = {
                                    { Vector2.new(box_x, box_y), Vector2.new(box_x + cl, box_y) },
                                    { Vector2.new(box_x, box_y), Vector2.new(box_x, box_y + cl) },
                                    { Vector2.new(box_x + w, box_y), Vector2.new(box_x + w - cl, box_y) },
                                    { Vector2.new(box_x + w, box_y), Vector2.new(box_x + w, box_y + cl) },
                                    { Vector2.new(box_x, box_y + h), Vector2.new(box_x + cl, box_y + h) },
                                    { Vector2.new(box_x, box_y + h), Vector2.new(box_x, box_y + h - cl) },
                                    { Vector2.new(box_x + w, box_y + h), Vector2.new(box_x + w - cl, box_y + h) },
                                    { Vector2.new(box_x + w, box_y + h), Vector2.new(box_x + w, box_y + h - cl) },
                                }

                                for i = 1, 8 do
                                    c[i].From = fromTo[i][1]
                                    c[i].To = fromTo[i][2]
                                    c[i].Color = col
                                    c[i].Visible = true

                                    if showOutline and co and co[i] then
                                        co[i].From = fromTo[i][1]
                                        co[i].To = fromTo[i][2]
                                        co[i].Color = outlineCol
                                        co[i].Visible = true
                                    elseif co and co[i] then
                                        co[i].Visible = false
                                    end
                                end
                            end
                        else
                            d.box.Visible = false
                            if d.box_outline then d.box_outline.Visible = false end
                            if d.box_outline_in then d.box_outline_in.Visible = false end
                            sync_box_grad(d, 0, 0, 0, 0, false)
                            for _, l in ipairs(d.corners) do l.Visible = false end
                            if d.corner_outlines then
                                for _, l in ipairs(d.corner_outlines) do l.Visible = false end
                            end
                        end

                        if cfg.skeleton_enabled then
                            local bones = hum.RigType == Enum.HumanoidRigType.R15 and r15_bones or r6_bones
                            local bc = ctx.esp_bones[player]
                            local bones_ok = bc and bc.char == char
                            if bones_ok then
                                for _, be in ipairs(bc.list) do
                                    local ba, bb = be[1], be[2]
                                    if ba == nil or bb == nil or ba.Parent == nil or bb.Parent == nil then
                                        bones_ok = false
                                        break
                                    end
                                end
                            end
                            if not bones_ok then
                                bc = { char = char, list = {} }
                                for _, pair in ipairs(bones) do
                                    bc.list[#bc.list + 1] = { char:FindFirstChild(pair[1]), char:FindFirstChild(pair[2]) }
                                end
                                ctx.esp_bones[player] = bc
                            end
                            local bone_idx = 1
                            for _, be in ipairs(bc.list) do
                                local p_a, p_b = be[1], be[2]
                                local line = d.skeleton[bone_idx]
                                if line and p_a and p_b then
                                    local pos_a, vis_a = cur_cam:WorldToViewportPoint(p_a.Position)
                                    local pos_b, vis_b = cur_cam:WorldToViewportPoint(p_b.Position)
                                    if pos_a.Z > 0 and pos_b.Z > 0 and (vis_a or vis_b) then
                                        line.From = Vector2.new(pos_a.X, pos_a.Y)
                                        line.To = Vector2.new(pos_b.X, pos_b.Y)
                                        line.Color = cfg.skeleton_color
                                        line.Thickness = cfg.skeleton_thick
                                        line.Transparency = cfg.skeleton_trans
                                        line.Visible = true
                                    else
                                        line.Visible = false
                                    end
                                elseif line then
                                    line.Visible = false
                                end
                                bone_idx = bone_idx + 1
                            end
                            for i = bone_idx, #d.skeleton do d.skeleton[i].Visible = false end
                        else
                            for _, l in ipairs(d.skeleton) do l.Visible = false end
                        end

                        if cfg.names_enabled then
                            local name_str = (cfg.name_mode == "User Name" and player.Name)
                                or (cfg.name_mode == "Both" and player.DisplayName .. " (@" .. player.Name .. ")")
                                or player.DisplayName
                            if cfg.show_roles then
                                name_str = name_str .. " [" .. p_role:sub(1, 1):upper() .. p_role:sub(2) .. "]"
                            end
                            local y_pos = box_y - (cfg.name_size or 13) - 3

                            if not cfg.name_gradient then
                                if d.name_chars then
                                    for _, c in ipairs(d.name_chars) do c.Visible = false end
                                end
                                if d.name.Text ~= name_str then d.name.Text = name_str end
                                local ns = cfg.name_size or 13
                                if d.name.Size ~= ns then d.name.Size = ns end
                                d.name.Position = Vector2.new(center_x, y_pos)
                                d.name.Color = cfg.role_colors_enabled and p_role_col or cfg.names_color
                                d.name.Transparency = 1
                                d.name.Visible = true
                            else
                                d.name.Visible = false
                                d.name_chars = d.name_chars or {}

                                local len = #name_str
                                local now = os.clock()
                                local col1 = cfg.names_color or Color3.fromRGB(255, 255, 255)
                                local col2 = cfg.name_gradient_color or Color3.fromRGB(105, 205, 255)
                                local trans = 1 - math.clamp(cfg.name_gradient_trans or 0, 0, 1)

                                local layout = d.name_layout
                                local name_size = cfg.name_size or 13
                                if not layout or layout.str ~= name_str or layout.size ~= name_size then
                                    layout = { str = name_str, size = name_size, widths = {}, total = 0 }
                                    for i = 1, len do
                                        local ch = name_str:sub(i, i)
                                        local cdraw = d.name_chars[i]
                                        if not cdraw then
                                            cdraw = make_draw("Text")
                                            cdraw.Center = false
                                            cdraw.Outline = true
                                            d.name_chars[i] = cdraw
                                        end
                                        cdraw.Size = name_size
                                        cdraw.Text = ch
                                        local w = cdraw.TextBounds.X
                                        layout.widths[i] = w
                                        layout.total = layout.total + w
                                    end
                                    d.name_layout = layout
                                end

                                for i = len + 1, #d.name_chars do
                                    d.name_chars[i].Visible = false
                                end

                                local curr_x = math.floor(center_x - (layout.total / 2))

                                for i = 1, len do
                                    local cdraw = d.name_chars[i]
                                    if cdraw then
                                        cdraw.Position = Vector2.new(curr_x, y_pos)

                                    local progress = (len > 1) and ((i - 1) / (len - 1)) or 0
                                    local wave = (math.sin(now * 3.0 + progress * math.pi * 1.5) + 1) / 2
                                    local letterColor = col1:Lerp(col2, wave)

                                        cdraw.Color = letterColor
                                        cdraw.Transparency = trans
                                        cdraw.Visible = true

                                        curr_x = curr_x + (layout.widths[i] or 0)
                                    end
                                end
                            end
                        else
                            d.name.Visible = false
                            if d.name_chars then
                                for _, c in ipairs(d.name_chars) do c.Visible = false end
                            end
                        end

                        local bottom_offset = 2
                        if cfg.dist_enabled then
                            local dist_str = math.floor(dist) .. " studs"
                            if d.distance.Text ~= dist_str then d.distance.Text = dist_str end
                            d.distance.Position = Vector2.new(center_x, box_y + h + bottom_offset)
                            d.distance.Color = cfg.dist_color
                            d.distance.Visible = true
                            bottom_offset = bottom_offset + 14
                        else
                            d.distance.Visible = false
                        end

                        if cfg.show_weapon then
                            local tool = char:FindFirstChildOfClass("Tool")
                            if tool then
                                if d.weapon.Text ~= tool.Name then d.weapon.Text = tool.Name end
                                d.weapon.Position = Vector2.new(center_x, box_y + h + bottom_offset)
                                d.weapon.Color = Color3.fromRGB(200, 200, 200)
                                d.weapon.Visible = true
                            else
                                d.weapon.Visible = false
                            end
                        else
                            d.weapon.Visible = false
                        end

                        if cfg.health_enabled then
                            d.health.Visible = false
                            local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                            local bar_h = math.floor(h * ratio)

                            if d.health_outline then
                                d.health_outline.Position = Vector2.new(box_x - 6, box_y - 1)
                                d.health_outline.Size = Vector2.new(4, h + 2)
                                d.health_outline.Visible = true
                            end

                            if d.health_bar then
                                d.health_bar.Position = Vector2.new(box_x - 5, box_y + h - bar_h)
                                d.health_bar.Size = Vector2.new(2, bar_h)
                                d.health_bar.Color = cfg.health_color
                                d.health_bar.Visible = (bar_h > 0)
                            end

                            sync_grad_img(d, "health_gradient", Vector2.new(box_x - 5, box_y + h - bar_h - 1), Vector2.new(2, bar_h + 1), cfg.health_gradient_color, 1 - cfg.health_gradient_trans, cfg.health_gradient == true and bar_h > 0)
                        else
                            d.health.Visible = false
                            if d.health_outline then d.health_outline.Visible = false end
                            if d.health_bar then d.health_bar.Visible = false end
                            if d.health_gradient then d.health_gradient.Visible = false end
                            d.health_gradient_state = nil
                        end
                    end
                end
            end
        end
    end
end))

local is_unloading = false
unload = function()
    if is_unloading then return end
    is_unloading = true
    ctx.running = false

    -- 1. Disconnect all tracked connections
    pcall(function()
        for _, c in ipairs(ctx.conns) do
            pcall(function() c:Disconnect() end)
        end
        table.clear(ctx.conns)
    end)

    -- 2. Restore weapon and client hooks
    pcall(function()
        if hook_muzzle_flash then
            local ps = local_player:FindFirstChild("PlayerScripts")
            local mod = ps and ps:FindFirstChild("ClientViewModel", true)
            if mod then require(mod).MuzzleFlash = hook_muzzle_flash end
        end
    end)
    pcall(function()
        if hook_gun_shoot then
            local ps = local_player:FindFirstChild("PlayerScripts")
            local mod = ps and ps:FindFirstChild("ItemTypeGun", true)
            if mod then require(mod).StartShooting = hook_gun_shoot end
        end
    end)

    -- 3. Restore player visuals & materials
    pcall(function()
        for p in pairs(player_chams_orig) do
            pcall(function() restore_player_parts(p) end)
        end
        table.clear(player_chams_orig)
    end)

    pcall(function() if weapon_chams and weapon_chams.clear then weapon_chams:clear() end end)
    pcall(function() if particles and particles.clear then particles:clear() end end)
    pcall(function() if chromatic_chams and chromatic_chams.clear then chromatic_chams:clear() end end)
    pcall(function() if self_chams and self_chams.reset then self_chams:reset() end end)
    pcall(function() if china_hat and china_hat.clear then china_hat:clear() end end)
    pcall(function() if china_hat and china_hat.clear_2d then china_hat:clear_2d() end end)
    pcall(function() if anim_manager and anim_manager.revert then anim_manager:revert("all") end end)
    pcall(function()
        if fe_cosmetics then
            local char = local_player and local_player.Character
            if char then
                pcall(function() fe_cosmetics:revert_korblox(char) end)
                pcall(function() fe_cosmetics:revert_headless(char) end)
            end
        end
    end)

    -- 4. Destroy catalog and preview windows
    pcall(function()
        if anim_catalog and anim_catalog.Destroy then
            pcall(function() anim_catalog:Destroy() end)
        end
        anim_catalog = nil
    end)
    pcall(function()
        if anim_ui then
            if anim_ui.destroy then pcall(function() anim_ui:destroy() end) end
            if anim_ui.Destroy then pcall(function() anim_ui:Destroy() end) end
            anim_ui = nil
        end
    end)
    pcall(function() if emote_manager and emote_manager.stop then emote_manager:stop() end end)
    pcall(function()
        if emote_catalog and emote_catalog.Destroy then
            pcall(function() emote_catalog:Destroy() end)
        end
        emote_catalog = nil
    end)
    pcall(function()
        if emote_ui then
            if emote_ui.destroy then pcall(function() emote_ui:destroy() end) end
            if emote_ui.Destroy then pcall(function() emote_ui:Destroy() end) end
            emote_ui = nil
        end
    end)
    pcall(function()
        if esp_preview then
            if esp_preview.Destroy then pcall(function() esp_preview:Destroy() end) end
            if esp_preview.destroy then pcall(function() esp_preview:destroy() end) end
            esp_preview = nil
        end
    end)
    pcall(function()
        if library and library.ESPPreviewFrame then
            library.ESPPreviewFrame:Destroy()
            library.ESPPreviewFrame = nil
            library.ESPPreview = nil
        end
    end)

    -- 5. Lighting & World restoration
    pcall(function()
        if nightModeConnection then
            nightModeConnection:Disconnect()
            nightModeConnection = nil
        end
    end)
    pcall(function()
        if restoreOriginalLighting then restoreOriginalLighting() end
    end)
    pcall(function() if world and world.reset then world:reset() end end)
    pcall(function() if skybox and skybox.reset then skybox:reset() end end)

    pcall(function()
        if baseline then
            if baseline.ambient then lighting.Ambient = baseline.ambient end
            if baseline.outdoor then lighting.OutdoorAmbient = baseline.outdoor end
            if baseline.fog_color then lighting.FogColor = baseline.fog_color end
            if baseline.fog_start then lighting.FogStart = baseline.fog_start end
            if baseline.fog_end then lighting.FogEnd = baseline.fog_end end
            if baseline.clock_time then lighting.ClockTime = baseline.clock_time end
            lighting.ExposureCompensation = baseline.exposure or 0
            if baseline.brightness then lighting.Brightness = baseline.brightness end
            if baseline.global_shadows ~= nil then lighting.GlobalShadows = baseline.global_shadows end
            if baseline.color_shift_bottom then lighting.ColorShift_Bottom = baseline.color_shift_bottom end
            if baseline.color_shift_top then lighting.ColorShift_Top = baseline.color_shift_top end
        end
    end)

    pcall(function()
        for _, child in ipairs(lighting:GetChildren()) do
            if child:IsA("Atmosphere") and baseline and baseline.atmosphere_density then
                pcall(function() child.Density = baseline.atmosphere_density end)
            end
            if child.Name == "VantageNightCC" or child.Name == "_v_ambient_cc" or child.Name == "_v_ambient_bloom" or child.Name == "VantageMenuBlur" or child.Name == "CoreMenuBlur" then
                pcall(function() child:Destroy() end)
            end
        end
    end)

    -- 6. Ambient overlay
    pcall(function()
        if ambient_overlay and ambient_overlay.gui then
            ambient_overlay.gui:Destroy()
            ambient_overlay = nil
        end
    end)

    -- 7. ESP drawings, tracers, backtrack, shaders, auras
    pcall(function()
        if workspace.CurrentCamera then
            local hat = workspace.CurrentCamera:FindFirstChild("Visuals_ChinaHat")
            if hat then hat:Destroy() end
        end
        local hat_ws = workspace:FindFirstChild("Visuals_ChinaHat")
        if hat_ws then hat_ws:Destroy() end
        if shaders and shaders.reset then shaders:reset() end
        if auras and auras.clear then auras:clear() end
    end)

    pcall(function()
        if camera and baseline and baseline.fov then camera.FieldOfView = baseline.fov end
    end)

    pcall(function()
        for p, h in pairs(ctx.chams) do
            if h then pcall(function() h:Destroy() end) end
            ctx.chams[p] = nil
        end
    end)

    pcall(function()
        for p, saved in pairs(ctx.hidden_names) do
            pcall(function()
                if saved.hum and saved.hum.Parent then
                    saved.hum.DisplayDistanceType = saved.display
                end
            end)
            ctx.hidden_names[p] = nil
        end
    end)

    pcall(function()
        for p in pairs(ctx.drawings) do
            clear_player_drawings(p)
        end
        table.clear(ctx.drawings)
    end)

    pcall(function()
        for tracer in pairs(ctx.tracers) do
            pcall(function() tracer.beam:Destroy() end)
            pcall(function() tracer.a0:Destroy() end)
            pcall(function() tracer.a1:Destroy() end)
        end
        table.clear(ctx.tracers)
    end)

    pcall(function()
        if backtrack and backtrack.clear then backtrack:clear() end
    end)

    -- 8. Linoria library unload (runs safely in protected call)
    if library and not library.Unloaded then
        pcall(function() library:Unload() end)
    end

    -- 9. Post-library cleanup: Main Linoria Frames & ScreenGuis
    local target_sg = main_screen_gui
        or (ctx and ctx.main_gui)
        or (library and library.ProfilePanel and library.ProfilePanel:FindFirstAncestorOfClass("ScreenGui"))
        or (library and library.ScreenGui)
        or (function()
            local function find_sg(tbl)
                if type(tbl) ~= "table" then return nil end
                for _, v in pairs(tbl) do
                    if typeof(v) == "Instance" then
                        local found = v:IsA("ScreenGui") and v or v:FindFirstAncestorOfClass("ScreenGui")
                        if found then return found end
                    end
                end
                return nil
            end
            return find_sg(library) or find_sg(window) or (tabs and find_sg(tabs.visuals))
        end)()
        or (getgenv and (getgenv().__v_ctx_gui or getgenv()._VantageActiveGui))

    pcall(function()
        if window and window.MainFrame then
            window.MainFrame.Visible = false
            window.MainFrame:Destroy()
            window.MainFrame = nil
        end
    end)

    pcall(function()
        if library then
            if library.MainFrame then
                library.MainFrame.Visible = false
                library.MainFrame:Destroy()
                library.MainFrame = nil
            end
            if library.Window and library.Window.MainFrame then
                library.Window.MainFrame.Visible = false
                library.Window.MainFrame:Destroy()
                library.Window.MainFrame = nil
            end
            if library.ActiveLoading then
                library.ActiveLoading:Destroy()
                library.ActiveLoading = nil
            end
            if library.RainScreenGui then
                library.RainScreenGui:Destroy()
                library.RainScreenGui = nil
            end
            if library.ESPPreviewFrame then
                library.ESPPreviewFrame:Destroy()
                library.ESPPreviewFrame = nil
                library.ESPPreview = nil
            end
            if library.AnimCatalogFrame then
                library.AnimCatalogFrame:Destroy()
                library.AnimCatalogFrame = nil
                library.AnimCatalog = nil
            end
            if library.EmoteCatalogFrame then
                library.EmoteCatalogFrame:Destroy()
                library.EmoteCatalogFrame = nil
                library.EmoteCatalog = nil
            end
            if library.KeybindFrame then
                library.KeybindFrame:Destroy()
                library.KeybindFrame = nil
            end
            if library.WatermarkFrame then
                library.WatermarkFrame:Destroy()
                library.WatermarkFrame = nil
            end
        end
    end)

    if target_sg and typeof(target_sg) == "Instance" then
        pcall(function()
            target_sg.Enabled = false
            target_sg.Parent = nil
            target_sg:ClearAllChildren()
            target_sg:Destroy()
        end)
    end

    -- 10. Purge ALL Vantage ScreenGuis across all safe parents
    pcall(function()
        local safe_parents = {}
        if typeof(gethui) == "function" then
            pcall(function()
                local h = gethui()
                if h then table.insert(safe_parents, h) end
            end)
        end
        pcall(function()
            local cg = (cloneref and cloneref(game:GetService("CoreGui"))) or game:GetService("CoreGui")
            if cg then
                table.insert(safe_parents, cg)
                pcall(function()
                    local rg = cg:FindFirstChild("RobloxGui")
                    if rg then table.insert(safe_parents, rg) end
                end)
            end
        end)
        pcall(function()
            local lp = (cloneref and cloneref(game:GetService("Players")).LocalPlayer) or game:GetService("Players").LocalPlayer
            local pg = lp and (lp:FindFirstChildOfClass("PlayerGui") or lp:FindFirstChild("PlayerGui"))
            if pg then table.insert(safe_parents, pg) end
        end)

        for _, parent in ipairs(safe_parents) do
            pcall(function()
                for _, name in ipairs({ "CoreAmbientOverlay", "VantageAmbientOverlay", "AnimCatalogWindow", "EmoteCatalogWindow", "ESPPreviewWindow", "MaterialChams", "VantageMaterialChams", "CoreFloatProvider", "VantageFloatGui" }) do
                    local found = parent:FindFirstChild(name)
                    while found do
                        if found:IsA("GuiObject") then found.Visible = false end
                        found.Parent = nil
                        found:Destroy()
                        found = parent:FindFirstChild(name)
                    end
                end
                for _, child in ipairs(parent:GetChildren()) do
                    pcall(function()
                        local should_destroy = false
                        if child == target_sg or child == main_screen_gui then
                            should_destroy = true
                        elseif child:IsA("ScreenGui") then
                            if child:GetAttribute("__v_core") == true or child:GetAttribute("IsVantageGui") == true then
                                should_destroy = true
                            elseif child.Name == "CoreProvider"
                                or child.Name == "CoreFloatProvider"
                                or child.Name == "Vantage"
                                or child.Name == "VantageFloatGui"
                                or child.Name == "VantageAmbientOverlay"
                                or child.Name == "CoreAmbientOverlay"
                                or child.Name == "AnimCatalogWindow"
                                or child.Name == "EmoteCatalogWindow"
                                or child.Name == "ESPPreviewWindow"
                                or child:FindFirstChild("AnimCatalogWindow", true) ~= nil
                                or child:FindFirstChild("EmoteCatalogWindow", true) ~= nil
                                or child:FindFirstChild("ESPPreviewWindow", true) ~= nil then
                                should_destroy = true
                            end
                        elseif child.Name == "AnimCatalogWindow" or child.Name == "EmoteCatalogWindow" or child.Name == "ESPPreviewWindow" then
                            should_destroy = true
                        end

                        if should_destroy then
                            pcall(function()
                                if child:IsA("GuiObject") then child.Visible = false end
                                child.Parent = nil
                                child:ClearAllChildren()
                                child:Destroy()
                            end)
                        end
                    end)
                end
            end)
        end
    end)

    -- 11. Clear getgenv references
    if getgenv then
        pcall(function()
            if getgenv().__v_ctx_gui and typeof(getgenv().__v_ctx_gui) == "Instance" then
                pcall(function()
                    getgenv().__v_ctx_gui.Enabled = false
                    getgenv().__v_ctx_gui.Parent = nil
                    getgenv().__v_ctx_gui:ClearAllChildren()
                    getgenv().__v_ctx_gui:Destroy()
                end)
            end
            if getgenv()._VantageActiveGui and typeof(getgenv()._VantageActiveGui) == "Instance" then
                pcall(function()
                    getgenv()._VantageActiveGui.Enabled = false
                    getgenv()._VantageActiveGui.Parent = nil
                    getgenv()._VantageActiveGui:ClearAllChildren()
                    getgenv()._VantageActiveGui:Destroy()
                end)
            end
            getgenv().__v_ctx_gui = nil
            getgenv().__v_ctx_loading = nil
            getgenv().__v_ctx_anims = nil
            getgenv().__v_ctx_emotes = nil
            getgenv().__v_ctx_unload = nil
            getgenv().__v_ctx = nil
            getgenv().__v_baseline_lighting = nil
            getgenv()._VantageActiveGui = nil
            getgenv()._VantageLoadingGui = nil
            getgenv()._VantageAnimCatalog = nil
            getgenv()._VantageEmoteCatalog = nil
        end)
    end

    is_unloading = false
end

getgenv().__v_ctx_unload = unload
ctx.cfg = cfg
ctx.library = library
ctx.china_hat = china_hat
ctx.self_chams = self_chams
ctx.backtrack = backtrack
ctx.anim_manager = anim_manager
ctx.anim_ui = anim_ui
ctx.emote_manager = emote_manager
ctx.emote_ui = emote_ui
ctx.unload = unload
getgenv().__v_ctx = ctx

theme_mgr:SetLibrary(library)
theme_mgr:SetFolder("vantage/assets")
theme_mgr:ApplyTheme("vantage")

save_mgr:SetLibrary(library)
save_mgr:IgnoreThemeSettings()
save_mgr:SetIgnoreIndexes({ "menu_bind" })
save_mgr:SetFolder("vantage/assets")
save_mgr:SetSubFolder("config")

save_mgr:BuildConfigSection(tabs.config)
save_mgr:LoadAutoloadConfig()

library:OnUnload(function()
    unload()
end)

return {
    make_tracer = make_tracer,
    weapon_chams = weapon_chams,
    chromatic_chams = chromatic_chams,
    self_chams = self_chams,
    china_hat = china_hat,
    backtrack = backtrack,
    anim_manager = anim_manager,
    anim_ui = anim_ui,
    emote_manager = emote_manager,
    emote_ui = emote_ui,
    particles = particles,
    shaders = shaders,
    auras = auras,
    cfg = cfg,
    unload = unload
}
