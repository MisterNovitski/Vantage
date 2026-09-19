local prev_unload = getgenv().__v_ctx_unload
if type(prev_unload) == "function" then pcall(prev_unload) end

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
        local cache_buster = (string.find(url, "?", 1, true) and "&" or "?") .. "nocache=" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 99999))
        local ok, content = pcall(function() return game:HttpGet(url .. cache_buster) end)
        if not ok or not content or #content == 0 then
            ok, content = pcall(function() return game:HttpGet(url) end)
        end
        if ok and content and #content > 0 then
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
    { "Library.luau", "main.luau", "workspace/Library.luau", "Vantage/Library.luau", "workspace/main.luau" },
    repo .. "main.luau",
    function(lib) return lib and lib.CreateWindow end
)
local theme_mgr = load_mod({ "addons/ThemeManager.luau", "addons/theme.luau", "workspace/addons/ThemeManager.luau", "workspace/addons/theme.luau", "ThemeManager.luau" }, repo .. "addons/theme.luau")
local save_mgr = load_mod({ "addons/SaveManager.luau", "addons/manager.luau", "workspace/addons/SaveManager.luau", "workspace/addons/manager.luau", "SaveManager.luau" }, repo .. "addons/manager.luau")

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
local stats = cloneref(game:GetService("Stats"))
local replicated_storage = cloneref(game:GetService("ReplicatedStorage"))
local core_gui = cloneref(game:GetService("CoreGui"))
local local_player = players.LocalPlayer
local camera = workspace.CurrentCamera

local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_clamp = math.clamp
local math_huge = math.huge
local math_abs = math.abs
local math_cos = math.cos
local math_sin = math.sin
local math_rad = math.rad
local Vector2_new = Vector2.new
local Vector3_new = Vector3.new
local Vector3_zero = Vector3.zero
local Color3_fromRGB = Color3.fromRGB
local Color3_fromHex = Color3.fromHex
local task_wait = task.wait
local task_spawn = task.spawn
local string_lower = string.lower
local string_find = string.find
local string_match = string.match
local table_insert = table.insert
local table_sort = table.sort

local baseline = {
    fov = camera and camera.FieldOfView or 70,
    ambient = lighting.Ambient,
    outdoor = lighting.OutdoorAmbient,
    fog_color = lighting.FogColor,
    fog_start = lighting.FogStart,
    fog_end = lighting.FogEnd,
    clock_time = lighting.ClockTime,
    exposure = lighting.ExposureCompensation,
    speed = 16,
    jump = 50
}

local ctx = {
    running = true,
    conns = {},
    hooks = {},
    drawings = {},
    chams = {},
    tracers = {},
    instances = {}
}

local cfg = {
    silent_enabled = false, silent_fov = 120, silent_hitbox = "Head", target_filter = "All", wall_check = true, ignore_knocked = true, ignore_friends = false,
    aimbot_enabled = false, aimbot_smooth = 1, aimbot_key = "MouseButton2",
    infinite_ammo = false, no_recoil = false, no_spread = false, rapid_fire = false, no_reload = false,
    speed_enabled = false, speed_val = 24, jump_enabled = false, jump_val = 70, noclip_enabled = false, fly_enabled = false, fly_speed = 50,
    esp_enabled = false, team_check = false, box_enabled = false, box_mode = "2D", box_color = Color3_fromRGB(255, 255, 255),
    skeleton_enabled = false, skeleton_color = Color3_fromRGB(255, 255, 255), skeleton_thick = 1.5, skeleton_trans = 1,
    health_enabled = false, names_enabled = false, name_mode = "Display Name", names_color = Color3_fromRGB(255, 255, 255),
    show_weapon = false, dist_enabled = false, dist_color = Color3_fromRGB(255, 220, 100), max_dist = 1000,
    friend_esp = true, friend_color = Color3_fromRGB(0, 255, 200), npc_esp = false, npc_color = Color3_fromRGB(255, 170, 0),
    chams_enabled = false, chams_mode = "Highlight", chams_material = "forcefield 2", chams_color = Color3_fromHex("#474747"), chams_outline_color = Color3_fromRGB(255, 255, 255), chams_outline_trans = 1, chams_fill_trans = 0.5,
    chromatic_speed = 0.6, chromatic_scale = 1.012, chromatic_trans = 0.025, chromatic_refl = 0.12,
    weapon_chams_enabled = false, weapon_chams_type = "Neon", weapon_chams_color = Color3_fromRGB(180, 100, 255), weapon_chams_trans = 0,
    bullet_tracer = false, tracer_color = Color3_fromRGB(140, 230, 255), tracer_duration = 0.75, tracer_width = 0.15,
    particles_enabled = false, particles_color = Color3_fromRGB(220, 170, 255), particles_count = 23, particles_size = 0.45, particles_trans = 0.1, particle_texture = "snowflake", particle_flight = "wind", particle_collide = false,
    ambient_enabled = false, ambient_color = Color3_fromHex("#919090"), outdoor_color = Color3_fromHex("#5a3782"), clock_time = 0, fog_color = Color3_fromHex("#3c1e5f"), fog_start = 60, fog_end = 600,
    ambient_bloom = 0.75, ambient_brightness = 0.05, ambient_contrast = 0.15, ambient_saturation = 0.25,
    china_hat_enabled = false, china_hat_color = Color3_fromHex("#b464ff"), china_hat_trans = 0.4, china_hat_radius = 0.9, china_hat_height = 0.45, china_hat_speed = 2.0,
    self_chams_enabled = false, self_chams_mode = "Forcefield 2", self_chams_color = Color3_fromHex("#b464ff"), self_chams_trans = 0.6,
    backtrack_enabled = false, backtrack_color = Color3_fromRGB(130, 90, 230), backtrack_trans = 0.4,
    custom_fov_enabled = false, custom_fov = 90, skybox_enabled = false, skybox_preset = "Anime Sky",
    auto_deposit = false, box_farm = false, lumber_farm = false, mining_farm = false, scrap_farm = false, casino_auto_spin = false, casino_auto_steal = false
}

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
        if gethui then
            gui.Parent = gethui()
        elseif local_player:FindFirstChild("PlayerGui") then
            gui.Parent = local_player.PlayerGui
        end
    end)
end

local friend_cache = {}
local known_friends = {}

local function is_friend(player)
    if not player then return false end
    if type(player) == "number" and known_friends[player] == true then return true end
    if type(player) == "string" and known_friends[string_lower(player)] == true then return true end
    if typeof(player) == "Instance" and player:IsA("Player") then
        if known_friends[player.UserId] == true or known_friends[string_lower(player.Name)] == true then return true end
    end
    if friend_cache[player] ~= nil then return friend_cache[player] end

    local plr = player
    if typeof(player) ~= "Instance" or not player:IsA("Player") then
        plr = players:FindFirstChild(tostring(player))
    end
    if not plr or plr == local_player then return false end

    local id = plr.UserId
    if not id or id <= 0 then return false end

    local is_fr = false
    local ok = pcall(function() is_fr = local_player:IsFriendsWith(id) end)
    if ok and is_fr then
        friend_cache[id] = true
        friend_cache[plr] = true
        known_friends[id] = true
        return true
    end
    friend_cache[id] = false
    friend_cache[plr] = false
    return false
end

task_spawn(function()
    pcall(function()
        if local_player and local_player.UserId and local_player.UserId > 0 then
            local pages = players:GetFriendsAsync(local_player.UserId)
            while true do
                for _, item in ipairs(pages:GetCurrentPage()) do
                    known_friends[item.Id] = true
                    if item.Username then known_friends[string_lower(item.Username)] = true end
                end
                if pages.IsFinished then break end
                pages:AdvanceToNextPageAsync()
            end
        end
    end)
end)

local function is_teammate(player)
    return cfg.team_check and local_player.Team and player.Team == local_player.Team
end

local function is_knocked(player)
    local char = player and player.Character
    if not char then return false end
    if char:GetAttribute("Downed") or char:GetAttribute("Knocked") then return true end
    if char:FindFirstChild("Knocked") or char:FindFirstChild("Downed") then return true end
    return false
end

local window = library:CreateWindow({
    Title = "vantage",
    Footer = "by pseudonym1639, agenttes",
    Size = UDim2.fromOffset(740, 530),
    CornerRadius = 20,
    AutoShow = true,
    DisableSearch = true
})

local tabs = {
    combat = window:AddTab({ Name = "combat", Icon = "crosshair" }),
    movement = window:AddTab({ Name = "movement", Icon = "footprints" }),
    farm = window:AddTab({ Name = "farm", Icon = "zap" }),
    teleport = window:AddTab({ Name = "teleport", Icon = "map-pin" }),
    shop = window:AddTab({ Name = "shop", Icon = "shopping-cart" }),
    casino = window:AddTab({ Name = "casino", Icon = "dices" }),
    misc = window:AddTab({ Name = "misc", Icon = "sliders" }),
    visuals = window:AddTab({ Name = "visuals", Icon = "eye" }),
    config = window:AddTab({ Name = "config", Icon = "file-text" })
}

-- =========================================================================
-- [[ MODULE 1: COMBAT & WEAPON MODS ]]
-- =========================================================================
do
    local silent_box = tabs.combat:AddGroupbox({ Side = 1, Name = "silent aim", DisableCollapsing = true })
    local mods_box = tabs.combat:AddGroupbox({ Side = 2, Name = "weapon mods", DisableCollapsing = true })

    silent_box:AddToggle("silent_enabled", { Text = "enabled", Default = false, Callback = function(v) cfg.silent_enabled = v end })
    silent_box:AddSlider("silent_fov", { Text = "fov", Default = 120, Min = 10, Max = 360, Suffix = "°", Callback = function(v) cfg.silent_fov = v end })
    silent_box:AddDropdown("silent_hitbox", { Text = "hitbox", Values = { "Head", "HumanoidRootPart" }, Default = 1, Callback = function(v) cfg.silent_hitbox = v end })
    silent_box:AddDropdown("target_filter", { Text = "target filter", Values = { "All", "Players Only", "NPCs Only" }, Default = 1, Callback = function(v) cfg.target_filter = v end })
    silent_box:AddToggle("wall_check", { Text = "wall check", Default = true, Callback = function(v) cfg.wall_check = v end })
    silent_box:AddToggle("ignore_knocked", { Text = "ignore knocked", Default = true, Callback = function(v) cfg.ignore_knocked = v end })
    silent_box:AddToggle("ignore_friends", { Text = "ignore friends", Default = false, Callback = function(v) cfg.ignore_friends = v end })

    mods_box:AddToggle("infinite_ammo", { Text = "infinite ammo", Default = false, Callback = function(v) cfg.infinite_ammo = v end })
    mods_box:AddToggle("no_recoil", { Text = "no recoil", Default = false, Callback = function(v) cfg.no_recoil = v end })
    mods_box:AddToggle("no_spread", { Text = "no spread", Default = false, Callback = function(v) cfg.no_spread = v end })
    mods_box:AddToggle("rapid_fire", { Text = "rapid fire", Default = false, Callback = function(v) cfg.rapid_fire = v end })
    mods_box:AddToggle("no_reload", { Text = "no reload", Default = false, Callback = function(v) cfg.no_reload = v end })

    local fov_circle = Drawing.new("Circle")
    fov_circle.Thickness = 1
    fov_circle.NumSides = 36
    fov_circle.Color = Color3_fromRGB(255, 255, 255)
    fov_circle.Transparency = 1
    fov_circle.Filled = false
    fov_circle.Visible = false
    table_insert(ctx.drawings, fov_circle)

    local function is_target_visible(target_part)
        if not target_part then return false end
        if not (cfg.wall_check or (toggles.wall_check and toggles.wall_check.Value)) then return true end

        local origin = camera.CFrame.Position
        local dest = target_part.Position
        local dir = dest - origin
        local dist = dir.Magnitude
        if dist < 0.1 then return true end

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local filter = { camera }
        if local_player.Character then table_insert(filter, local_player.Character) end
        if target_part.Parent then table_insert(filter, target_part.Parent) end
        params.FilterDescendantsInstances = filter

        local result = workspace:Raycast(origin, dir.Unit * (dist - 0.2), params)
        if result and result.Instance then
            local inst = result.Instance
            if inst.CanCollide and inst.Transparency < 0.95 then
                return false
            end
        end
        return true
    end

    local function get_best_silent_target()
        if not cfg.silent_enabled then return nil end
        local best_target = nil
        local shortest_dist = cfg.silent_fov or 120
        local viewport_center = Vector2_new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
        local filter = cfg.target_filter or "All"

        if filter == "All" or filter == "Players Only" then
            for _, p in ipairs(players:GetPlayers()) do
                if p ~= local_player and not is_teammate(p) then
                    if not (cfg.ignore_friends and is_friend(p)) and not (cfg.ignore_knocked and is_knocked(p)) then
                        local char = p.Character
                        local part = char and char:FindFirstChild(cfg.silent_hitbox or "Head")
                        local hum = char and char:FindFirstChildOfClass("Humanoid")
                        if part and hum and hum.Health > 0 then
                            local screen_pos, on_screen = camera:WorldToViewportPoint(part.Position)
                            if on_screen and screen_pos.Z > 0 then
                                local dist = (Vector2_new(screen_pos.X, screen_pos.Y) - viewport_center).Magnitude
                                if dist < shortest_dist then
                                    if is_target_visible(part) then
                                        shortest_dist = dist
                                        best_target = part
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        return best_target
    end

    local function is_camera_script()
        if typeof(getcallingscript) == "function" then
            local s = getcallingscript()
            if s and typeof(s) == "Instance" then
                local name = string_lower(s.Name)
                if string_find(name, "camera") or string_find(name, "popper") or string_find(name, "control") or string_find(name, "zoom") or string_find(name, "player") then
                    return true
                end
            end
        end
        return false
    end

    local old_namecall
    old_namecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = { ... }

        if not checkcaller() and cfg.silent_enabled then
            if is_camera_script() then
                return old_namecall(self, ...)
            end

            if method == "Raycast" and self == workspace then
                local origin = args[1]
                local dir = args[2]
                if typeof(origin) == "Vector3" and typeof(dir) == "Vector3" then
                    local look = camera and camera.CFrame.LookVector
                    if look and dir.Unit:Dot(look) < 0.1 then
                        return old_namecall(self, ...)
                    end
                    if camera and (origin - camera.CFrame.Position).Magnitude < 2 and not user_input_service:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                        return old_namecall(self, ...)
                    end

                    local target = get_best_silent_target()
                    if target then
                        args[2] = (target.Position - origin).Unit * 1000
                        return old_namecall(self, table.unpack(args))
                    end
                end
            elseif method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" or method == "FindPartOnRay" then
                local ray = args[1]
                if typeof(ray) == "Ray" then
                    local look = camera and camera.CFrame.LookVector
                    if look and ray.Direction.Unit:Dot(look) < 0.1 then
                        return old_namecall(self, ...)
                    end
                    if camera and (ray.Origin - camera.CFrame.Position).Magnitude < 2 and not user_input_service:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                        return old_namecall(self, ...)
                    end

                    local target = get_best_silent_target()
                    if target then
                        args[1] = Ray.new(ray.Origin, (target.Position - ray.Origin).Unit * 1000)
                        return old_namecall(self, table.unpack(args))
                    end
                end
            elseif method == "FireServer" or method == "InvokeServer" then
                local name = string_lower(tostring(self))
                if string_find(name, "shoot") or string_find(name, "fire") or string_find(name, "hit") or string_find(name, "bullet") then
                    local target = get_best_silent_target()
                    if target then
                        for i = 1, #args do
                            if typeof(args[i]) == "Vector3" then
                                args[i] = target.Position
                                break
                            elseif typeof(args[i]) == "CFrame" then
                                args[i] = CFrame.new(target.Position)
                                break
                            end
                        end
                        return old_namecall(self, table.unpack(args))
                    end
                end
            end
        end
        return old_namecall(self, ...)
    end))
    setstackhidden(old_namecall, true)
    ctx.hooks.namecall = old_namecall

    local mouse = local_player:GetMouse()
    local old_index
    old_index = hookmetamethod(game, "__index", newcclosure(function(self, prop)
        if not checkcaller() and cfg.silent_enabled and self == mouse then
            if not is_camera_script() then
                if prop == "Hit" or prop == "cframe" then
                    local target = get_best_silent_target()
                    if target then return target.CFrame end
                elseif prop == "Target" or prop == "target" then
                    local target = get_best_silent_target()
                    if target then return target end
                end
            end
        end
        return old_index(self, prop)
    end))
    setstackhidden(old_index, true)
    ctx.hooks.index = old_index

    table_insert(ctx.conns, run_service.RenderStepped:Connect(function()
        if cfg.silent_enabled then
            fov_circle.Position = Vector2_new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
            fov_circle.Radius = cfg.silent_fov or 120
            fov_circle.Visible = true
        else
            fov_circle.Visible = false
        end
    end))
end

-- =========================================================================
-- [[ MODULE 2: MOVEMENT & UTILITY ]]
-- =========================================================================
do
    local move_box = tabs.movement:AddGroupbox({ Side = 1, Name = "movement", DisableCollapsing = true })

    move_box:AddToggle("speed_enabled", {
        Text = "walk speed",
        Default = false,
        Callback = function(enabled)
            cfg.speed_enabled = enabled
            local char = local_player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then hum.WalkSpeed = enabled and (cfg.speed_val or 24) or baseline.speed end
        end
    })
    move_box:AddSlider("speed_val", {
        Text = "speed value",
        Default = 24, Min = 16, Max = 120, Suffix = " studs/s",
        Callback = function(v)
            cfg.speed_val = v
            if cfg.speed_enabled then
                local char = local_player.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum then hum.WalkSpeed = v end
            end
        end
    })

    move_box:AddToggle("jump_enabled", {
        Text = "jump power",
        Default = false,
        Callback = function(enabled)
            cfg.jump_enabled = enabled
            local char = local_player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then hum.UseJumpPower = true; hum.JumpPower = enabled and (cfg.jump_val or 70) or baseline.jump end
        end
    })
    move_box:AddSlider("jump_val", {
        Text = "jump value",
        Default = 70, Min = 50, Max = 250,
        Callback = function(v)
            cfg.jump_val = v
            if cfg.jump_enabled then
                local char = local_player.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum then hum.UseJumpPower = true; hum.JumpPower = v end
            end
        end
    })

    move_box:AddToggle("noclip_enabled", { Text = "noclip", Default = false, Callback = function(v) cfg.noclip_enabled = v end })

    table_insert(ctx.conns, run_service.Stepped:Connect(function()
        if cfg.noclip_enabled and local_player.Character then
            for _, p in ipairs(local_player.Character:GetDescendants()) do
                if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
            end
        end
    end))
end

-- =========================================================================
-- [[ MODULE 3: FULL VISUALS SUITE ]]
-- =========================================================================
local update_esp_rendering
local chromatic_chams = { gui = nil, viewport = nil, cam = nil, model = nil, parts = {}, bulk_parts = {}, bulk_cframes = {}, _last_scan = 0 }
local weapon_chams = { orig = {}, last_vm = nil, cached = {} }
local particles = { part = nil, emitter = nil, gen = 0, asset = nil, folder = nil, simulated = {}, ray_params = nil }
local world = { cc = nil, bloom = nil }
local self_chams = { orig = {}, last_char = nil, highlight = nil }
local china_hat = { part = nil, mesh = nil, rotation = 0 }
local backtrack = { history = {}, clone = nil, max_history_time = 1.0, min_dist = 0.25 }
local skybox_presets = {
    ["anime sky"] = 72835926026092,
    ["pastel anime"] = 159068040,
    ["city sky"] = 1012842
}
local skybox = { current = nil, orig = (function() local s = lighting:FindFirstChildOfClass("Sky") return s and s:Clone() or nil end)(), cache = {}, loading = {}, req_id = 0 }

function skybox:clear()
    if self.current then pcall(function() self.current:Destroy() end); self.current = nil end
end

function skybox:remove_others()
    for _, obj in ipairs(lighting:GetChildren()) do
        if obj:IsA("Sky") and obj ~= self.current then pcall(function() obj:Destroy() end) end
    end
end

function skybox:reset()
    self:clear()
    if self.orig and not lighting:FindFirstChildOfClass("Sky") then
        local res = self.orig:Clone()
        res.Name = "Sky"
        res.Parent = lighting
    end
end

function skybox:apply()
    self.req_id = self.req_id + 1
    local cur_req = self.req_id
    if not cfg.skybox_enabled then self:reset(); return end

    local key = string_lower(cfg.skybox_preset or "anime sky")
    local id = skybox_presets[key] or skybox_presets["anime sky"]
    if self.cache[id] then
        self:clear(); self:remove_others()
        self.current = self.cache[id]:Clone()
        self.current.Name = "Sky"; self.current.Parent = lighting
        return
    end

    if self.loading[id] then return end
    self.loading[id] = true

    task_spawn(function()
        local ok, objs = pcall(function() return game:GetObjects("rbxassetid://" .. tostring(id)) end)
        local found_sky = nil
        if ok and type(objs) == "table" then
            for _, o in ipairs(objs) do
                if o:IsA("Sky") then found_sky = o; break end
                local sub = o:FindFirstChildWhichIsA("Sky", true)
                if sub then found_sky = sub; break end
            end
        end
        if found_sky then
            self.cache[id] = found_sky:Clone()
        else
            local fallback = Instance.new("Sky")
            if key == "anime sky" then
                fallback.SkyboxBk = "rbxassetid://6444884314"
                fallback.SkyboxDn = "rbxassetid://6444884785"
                fallback.SkyboxFt = "rbxassetid://6444884314"
                fallback.SkyboxLf = "rbxassetid://6444884605"
                fallback.SkyboxRt = "rbxassetid://6444884314"
                fallback.SkyboxUp = "rbxassetid://6444884940"
            elseif key == "pastel anime" then
                fallback.SkyboxBk = "rbxassetid://159068520"
                fallback.SkyboxDn = "rbxassetid://159067604"
                fallback.SkyboxFt = "rbxassetid://159068602"
                fallback.SkyboxLf = "rbxassetid://159068307"
                fallback.SkyboxRt = "rbxassetid://159068378"
                fallback.SkyboxUp = "rbxassetid://159068477"
            else
                fallback.SkyboxBk = "rbxassetid://1012840"
                fallback.SkyboxDn = "rbxassetid://1012841"
                fallback.SkyboxFt = "rbxassetid://1012842"
                fallback.SkyboxLf = "rbxassetid://1012843"
                fallback.SkyboxRt = "rbxassetid://1012844"
                fallback.SkyboxUp = "rbxassetid://1012845"
            end
            self.cache[id] = fallback
        end

        if type(objs) == "table" then for _, o in ipairs(objs) do pcall(function() o:Destroy() end) end end
        self.loading[id] = nil

        if cur_req ~= self.req_id or not cfg.skybox_enabled or not self.cache[id] then return end
        self:clear(); self:remove_others()
        self.current = self.cache[id]:Clone()
        self.current.Name = "Sky"; self.current.Parent = lighting
    end)
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

local r6_bones = {
    { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
    { "Torso", "Left Leg" }, { "Torso", "Right Leg" }
}
local r15_bones = {
    { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" }
}

local function get_char_bounds(char)
    local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    if not root then return {} end
    local cf = root.CFrame
    local size = Vector3_new(4, 5, 2)
    local extents = size * 0.5

    return {
        (cf * CFrame.new(-extents.X, extents.Y, -extents.Z)).Position,
        (cf * CFrame.new(extents.X, extents.Y, -extents.Z)).Position,
        (cf * CFrame.new(-extents.X, -extents.Y, -extents.Z)).Position,
        (cf * CFrame.new(extents.X, -extents.Y, -extents.Z)).Position,
        (cf * CFrame.new(-extents.X, extents.Y, extents.Z)).Position,
        (cf * CFrame.new(extents.X, extents.Y, extents.Z)).Position,
        (cf * CFrame.new(-extents.X, -extents.Y, extents.Z)).Position,
        (cf * CFrame.new(extents.X, -extents.Y, extents.Z)).Position
    }
end

local function get_drawings(player)
    local set = ctx.drawings[player]
    if not set then
        local box = Drawing.new("Square"); box.Thickness = 1; box.Filled = false; box.Visible = false
        local name = Drawing.new("Text"); name.Size = 13; name.Center = true; name.Outline = true; name.Visible = false
        local distance = Drawing.new("Text"); distance.Size = 12; distance.Center = true; distance.Outline = true; distance.Visible = false
        local weapon = Drawing.new("Text"); weapon.Size = 12; weapon.Center = true; weapon.Outline = true; weapon.Visible = false
        local health = Drawing.new("Line"); health.Thickness = 2; health.Visible = false

        local corners = {}
        for i = 1, 8 do
            local line = Drawing.new("Line"); line.Thickness = 1; line.Visible = false
            table_insert(corners, line)
        end

        local skeleton = {}
        for i = 1, 15 do
            local line = Drawing.new("Line"); line.Thickness = 1.5; line.Visible = false
            table_insert(skeleton, line)
        end

        set = { box = box, name = name, distance = distance, weapon = weapon, health = health, corners = corners, skeleton = skeleton, visible = false }
        ctx.drawings[player] = set
    end
    return set
end

local function hide_drawings(d)
    if not d or not d.visible then return end
    d.visible = false; d.box.Visible = false; d.name.Visible = false; d.distance.Visible = false; d.weapon.Visible = false; d.health.Visible = false
    for _, line in ipairs(d.corners) do line.Visible = false end
    for _, line in ipairs(d.skeleton) do line.Visible = false end
end

update_esp_rendering = function()
    if not cfg.esp_enabled then
        for _, d in pairs(ctx.drawings) do hide_drawings(d) end
        return
    end

    local cur_cam = workspace.CurrentCamera
    if not cur_cam then return end
    local cam_pos = cur_cam.CFrame.Position

    for _, player in ipairs(players:GetPlayers()) do
        if player == local_player or is_teammate(player) then
            if ctx.drawings[player] then hide_drawings(ctx.drawings[player]) end
        else
            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")

            if not char or not root or not hum or hum.Health <= 0 then
                if ctx.drawings[player] then hide_drawings(ctx.drawings[player]) end
            else
                local root_pos = root.Position
                local dist = (cam_pos - root_pos).Magnitude
                if dist > (cfg.max_dist or 1000) then
                    if ctx.drawings[player] then hide_drawings(ctx.drawings[player]) end
                else
                    local root_scr, _ = cur_cam:WorldToViewportPoint(root_pos)
                    if root_scr.Z <= 0 then
                        if ctx.drawings[player] then hide_drawings(ctx.drawings[player]) end
                    else
                        local corners_3d = get_char_bounds(char)
                        local min_x, min_y = math_huge, math_huge
                        local max_x, max_y = -math_huge, -math_huge
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
                            if ctx.drawings[player] then hide_drawings(ctx.drawings[player]) end
                        else
                            local d = get_drawings(player)
                            d.visible = true

                            local is_fr = is_friend(player)
                            local primary_col = (is_fr and cfg.friend_esp) and (cfg.friend_color or Color3_fromRGB(0, 255, 200)) or nil

                            local raw_w = math_max(max_x - min_x, 1)
                            local h = math_floor(max_y - min_y)
                            local center_x = math_floor(min_x + raw_w / 2)
                            local target_w = math_clamp(h * 0.48, math_min(6, raw_w), math_max(6, raw_w))
                            local w = math_floor(target_w)
                            local box_x = math_floor(center_x - w / 2)
                            local box_y = math_floor(min_y)

                            if cfg.box_enabled then
                                local box_col = primary_col or cfg.box_color
                                if cfg.box_mode == "2D" then
                                    d.box.Size = Vector2_new(w, h)
                                    d.box.Position = Vector2_new(box_x, box_y)
                                    d.box.Color = box_col
                                    d.box.Visible = true
                                    for _, l in ipairs(d.corners) do l.Visible = false end
                                else
                                    d.box.Visible = false
                                    local cl = math_clamp(math_floor(math_min(w, h) * 0.25), 3, 15)
                                    local c = d.corners
                                    c[1].From, c[1].To = Vector2_new(box_x, box_y), Vector2_new(box_x + cl, box_y)
                                    c[2].From, c[2].To = Vector2_new(box_x, box_y), Vector2_new(box_x, box_y + cl)
                                    c[3].From, c[3].To = Vector2_new(box_x + w, box_y), Vector2_new(box_x + w - cl, box_y)
                                    c[4].From, c[4].To = Vector2_new(box_x + w, box_y), Vector2_new(box_x + w, box_y + cl)
                                    c[5].From, c[5].To = Vector2_new(box_x, box_y + h), Vector2_new(box_x + cl, box_y + h)
                                    c[6].From, c[6].To = Vector2_new(box_x, box_y + h), Vector2_new(box_x, box_y + h - cl)
                                    c[7].From, c[7].To = Vector2_new(box_x + w, box_y + h), Vector2_new(box_x + w - cl, box_y + h)
                                    c[8].From, c[8].To = Vector2_new(box_x + w, box_y + h), Vector2_new(box_x + w, box_y + h - cl)
                                    for i = 1, 8 do c[i].Color = box_col; c[i].Visible = true end
                                end
                            else
                                d.box.Visible = false
                                for _, l in ipairs(d.corners) do l.Visible = false end
                            end

                            if cfg.skeleton_enabled then
                                local skel_col = primary_col or cfg.skeleton_color
                                local bones = hum.RigType == Enum.HumanoidRigType.R15 and r15_bones or r6_bones
                                local bone_idx = 1
                                for _, pair in ipairs(bones) do
                                    local p_a = char:FindFirstChild(pair[1])
                                    local p_b = char:FindFirstChild(pair[2])
                                    local line = d.skeleton[bone_idx]
                                    if line and p_a and p_b then
                                        local pos_a, vis_a = cur_cam:WorldToViewportPoint(p_a.Position)
                                        local pos_b, vis_b = cur_cam:WorldToViewportPoint(p_b.Position)
                                        if pos_a.Z > 0 and pos_b.Z > 0 and (vis_a or vis_b) then
                                            line.From = Vector2_new(pos_a.X, pos_a.Y)
                                            line.To = Vector2_new(pos_b.X, pos_b.Y)
                                            line.Color = skel_col
                                            line.Thickness = cfg.skeleton_thick or 1.5
                                            line.Transparency = cfg.skeleton_trans or 1
                                            line.Visible = true
                                        else line.Visible = false end
                                    elseif line then line.Visible = false end
                                    bone_idx = bone_idx + 1
                                end
                                for i = bone_idx, #d.skeleton do d.skeleton[i].Visible = false end
                            else
                                for _, l in ipairs(d.skeleton) do l.Visible = false end
                            end

                            if cfg.names_enabled then
                                local name_col = primary_col or cfg.names_color
                                d.name.Text = (cfg.name_mode == "User Name" and player.Name)
                                    or (cfg.name_mode == "Both" and player.DisplayName .. " (@" .. player.Name .. ")")
                                    or player.DisplayName
                                d.name.Position = Vector2_new(center_x, box_y - 16)
                                d.name.Color = name_col
                                d.name.Visible = true
                            else d.name.Visible = false end

                            local bottom_offset = 2
                            if cfg.dist_enabled then
                                d.distance.Text = math_floor(dist) .. " studs"
                                d.distance.Position = Vector2_new(center_x, box_y + h + bottom_offset)
                                d.distance.Color = primary_col or cfg.dist_color
                                d.distance.Visible = true
                                bottom_offset = bottom_offset + 14
                            else d.distance.Visible = false end

                            if cfg.show_weapon then
                                local tool = char:FindFirstChildOfClass("Tool")
                                if tool then
                                    d.weapon.Text = tool.Name
                                    d.weapon.Position = Vector2_new(center_x, box_y + h + bottom_offset)
                                    d.weapon.Color = Color3_fromRGB(200, 200, 200)
                                    d.weapon.Visible = true
                                else d.weapon.Visible = false end
                            else d.weapon.Visible = false end

                            if cfg.health_enabled then
                                local bottom = box_y + h
                                local ratio = math_clamp(hum.Health / math_max(hum.MaxHealth, 1), 0, 1)
                                d.health.From = Vector2_new(box_x - 5, bottom)
                                d.health.To = Vector2_new(box_x - 5, bottom - math_floor(h * ratio))
                                d.health.Color = Color3_fromRGB(80, 255, 100)
                                d.health.Visible = true
                            else d.health.Visible = false end
                        end
                    end
                end
            end
        end
    end
end

-- UI Building for Visuals
do
    local esp_group = tabs.visuals:AddLeftGroupbox("esp")
    local chams_group = tabs.visuals:AddLeftGroupbox("player chams")
    local weapon_group = tabs.visuals:AddLeftGroupbox("weapon chams")
    local tracers_group = tabs.visuals:AddLeftGroupbox("bullet tracers")

    local ambient_group = tabs.visuals:AddRightGroupbox("ambient")
    local self_group = tabs.visuals:AddRightGroupbox("self visuals")
    local skybox_group = tabs.visuals:AddRightGroupbox("skybox")
    local camera_group = tabs.visuals:AddRightGroupbox("camera")

    if library.AddESPPreview then
        library:AddESPPreview(tabs.visuals, {
            Title = "esp preview", Icon = "eye",
            box_enabled = cfg.box_enabled, box_mode = cfg.box_mode, box_color = cfg.box_color,
            skeleton_enabled = cfg.skeleton_enabled, skeleton_color = cfg.skeleton_color, skeleton_thick = cfg.skeleton_thick,
            health_enabled = cfg.health_enabled, health_color = Color3_fromRGB(0, 255, 128),
            name_enabled = cfg.names_enabled, name_text = "Player", name_mode = cfg.name_mode, name_color = cfg.names_color,
            weapon_enabled = cfg.show_weapon, weapon_text = "AK-47", weapon_color = Color3_fromRGB(220, 220, 220),
            distance_enabled = cfg.dist_enabled, distance_text = "42 studs", distance_color = cfg.dist_color
        })
    end

    local esp_toggle = esp_group:AddToggle("esp_master", { Text = "enabled", Default = false, Callback = function(v) cfg.esp_enabled = v end })
    esp_toggle:AddSettings(function(s)
        s:AddToggle("esp_team", { Text = "team check", Default = false, Callback = function(v) cfg.team_check = v end })
        s:AddToggle("friend_esp", { Text = "friend highlight", Default = true, Callback = function(v) cfg.friend_esp = v end })
            :AddColorPicker("friend_col", { Default = Color3_fromRGB(0, 255, 200), Title = "friend color", Callback = function(v) cfg.friend_color = v end })
        s:AddSlider("max_dist", { Text = "max distance", Default = 1000, Min = 100, Max = 3000, Rounding = 0, Suffix = " studs", Callback = function(v) cfg.max_dist = v end })
    end)

    local box_toggle = esp_group:AddToggle("esp_boxes", { Text = "boxes", Default = false, Callback = function(v) cfg.box_enabled = v end })
    box_toggle:AddColorPicker("box_col", { Default = Color3_fromRGB(255, 255, 255), Title = "box color", Callback = function(v) cfg.box_color = v end })
    box_toggle:AddSettings(function(s)
        s:AddDropdown("box_mode", { Text = "box mode", Values = { "2D", "Corner" }, Default = 1, Callback = function(v) cfg.box_mode = v end })
    end)

    local skel_toggle = esp_group:AddToggle("esp_skeleton", { Text = "skeleton", Default = false, Callback = function(v) cfg.skeleton_enabled = v end })
    skel_toggle:AddColorPicker("skel_col", { Default = Color3_fromRGB(255, 255, 255), Title = "skeleton color", Callback = function(v) cfg.skeleton_color = v end })
    skel_toggle:AddSettings(function(s)
        s:AddSlider("skel_thick", { Text = "skeleton thickness", Default = 1.5, Min = 1, Max = 4, Rounding = 1, Callback = function(v) cfg.skeleton_thick = v end })
    end)

    esp_group:AddToggle("esp_health", { Text = "health bar", Default = false, Callback = function(v) cfg.health_enabled = v end })

    local names_toggle = esp_group:AddToggle("esp_names", { Text = "names", Default = false, Callback = function(v) cfg.names_enabled = v end })
    names_toggle:AddColorPicker("name_col", { Default = Color3_fromRGB(255, 255, 255), Title = "names color", Callback = function(v) cfg.names_color = v end })
    names_toggle:AddSettings(function(s)
        s:AddDropdown("name_mode", { Text = "name mode", Values = { "Display Name", "User Name", "Both" }, Default = 1, Callback = function(v) cfg.name_mode = v end })
    end)

    esp_group:AddToggle("esp_weapon", { Text = "equipped weapon", Default = false, Callback = function(v) cfg.show_weapon = v end })
    esp_group:AddToggle("esp_dist", { Text = "distance", Default = false, Callback = function(v) cfg.dist_enabled = v end })
        :AddColorPicker("dist_col", { Default = Color3_fromRGB(255, 220, 100), Title = "distance color", Callback = function(v) cfg.dist_color = v end })

    local chams_toggle = chams_group:AddToggle("chams_toggle", { Text = "enabled", Default = false, Callback = function(v) cfg.chams_enabled = v end })
    chams_toggle:AddColorPicker("chams_col", { Default = Color3_fromHex("#474747"), Title = "chams color", Callback = function(v) cfg.chams_color = v end })
    chams_toggle:AddSettings(function(s)
        s:AddDropdown("chams_mode", { Text = "mode", Values = { "Highlight", "Material" }, Default = 1, Callback = function(v) cfg.chams_mode = v end })
        s:AddSlider("chams_fill_trans", { Text = "fill transparency", Default = 0.5, Min = 0, Max = 1, Rounding = 2, Callback = function(v) cfg.chams_fill_trans = v end })
    end)

    local weapon_toggle = weapon_group:AddToggle("weapon_chams_toggle", { Text = "enabled", Default = false, Callback = function(v) cfg.weapon_chams_enabled = v; if not v then weapon_chams:clear() end end })
    weapon_toggle:AddColorPicker("weapon_col", { Default = Color3_fromRGB(180, 100, 255), Title = "weapon color", Callback = function(v) cfg.weapon_chams_color = v end })
    weapon_toggle:AddSettings(function(s)
        s:AddDropdown("weapon_mat", { Text = "material", Values = { "Neon", "ForceField", "Glass" }, Default = 1, Callback = function(v) cfg.weapon_chams_type = v end })
        s:AddSlider("weapon_trans", { Text = "transparency", Default = 0, Min = 0, Max = 1, Rounding = 2, Callback = function(v) cfg.weapon_chams_trans = v end })
    end)

    local tracer_toggle = tracers_group:AddToggle("bullet_tracer", { Text = "enabled", Default = false })
    tracer_toggle:AddColorPicker("tracer_col", { Default = Color3_fromRGB(140, 230, 255), Title = "tracer color" })
    tracer_toggle:AddSettings(function(s)
        s:AddSlider("tracer_dur", { Text = "duration", Default = 0.75, Min = 0.1, Max = 2, Rounding = 2, Suffix = "s" })
        s:AddSlider("tracer_w", { Text = "width", Default = 0.15, Min = 0.05, Max = 0.6, Rounding = 2 })
    end)

    local ambient_toggle = ambient_group:AddToggle("ambient_toggle", { Text = "enabled", Default = false, Callback = function(v) cfg.ambient_enabled = v; world:apply() end })
    ambient_toggle:AddColorPicker("amb_col", { Default = Color3_fromHex("#919090"), Title = "ambient color", Callback = function(v) cfg.ambient_color = v; world:apply() end })
    ambient_toggle:AddSettings(function(s)
        s:AddLabel("outdoor color"):AddColorPicker("out_col", { Default = Color3_fromHex("#5e5e5e"), Title = "outdoor color", Callback = function(v) cfg.outdoor_color = v; world:apply() end })
        s:AddSlider("clock_time", { Text = "clock time", Default = 3, Min = 0, Max = 24, Rounding = 1, Callback = function(v) cfg.clock_time = v; world:apply() end })
    end)

    local particle_toggle = ambient_group:AddToggle("particles_toggle", { Text = "ambient particles", Default = false, Callback = function(v) cfg.particles_enabled = v; particles:init() end })
    particle_toggle:AddColorPicker("part_col", { Default = Color3_fromRGB(220, 170, 255), Title = "particles color", Callback = function(v) cfg.particles_color = v; particles:update_colors() end })
    particle_toggle:AddSettings(function(s)
        s:AddDropdown("part_tex", { Text = "texture", Values = { "snowflake", "star", "sparkle", "dollar", "cash" }, Default = 1, Callback = function(v) cfg.particle_texture = v; particles:init() end })
        s:AddDropdown("part_flight", { Text = "flight mode", Values = { "wind", "down", "up", "up/down", "random" }, Default = 1, Callback = function(v) cfg.particle_flight = v; particles:update_flight() end })
        s:AddToggle("part_collide", { Text = "collisions", Default = false, Callback = function(v) cfg.particle_collide = v; particles:init() end })
        s:AddSlider("part_amount", { Text = "amount", Default = 23, Min = 5, Max = 80, Rounding = 0, Callback = function(v) cfg.particles_count = v; particles:update_rate() end })
    end)

    local self_chams_toggle = self_group:AddToggle("self_chams_toggle", { Text = "self chams", Default = false, Callback = function(v) cfg.self_chams_enabled = v; if not v then self_chams:reset() end end })
    self_chams_toggle:AddColorPicker("self_chams_col", { Default = Color3_fromHex("#b464ff"), Title = "self chams color", Callback = function(v) cfg.self_chams_color = v end })
    self_chams_toggle:AddSettings(function(s)
        s:AddDropdown("self_chams_mode", { Text = "mode", Values = { "Forcefield 2", "Forcefield", "Highlight" }, Default = 1, Callback = function(v) cfg.self_chams_mode = v end })
        s:AddSlider("self_chams_trans", { Text = "transparency", Default = 0.6, Min = 0, Max = 1, Rounding = 2, Callback = function(v) cfg.self_chams_trans = v end })
    end)

    local china_hat_toggle = self_group:AddToggle("china_hat_toggle", { Text = "china hat", Default = false, Callback = function(v) cfg.china_hat_enabled = v; if not v then china_hat:hide() end end })
    china_hat_toggle:AddColorPicker("china_hat_col", { Default = Color3_fromHex("#b464ff"), Title = "china hat color", Callback = function(v) cfg.china_hat_color = v end })
    china_hat_toggle:AddSettings(function(s)
        s:AddSlider("china_hat_radius", { Text = "radius", Default = 2.2, Min = 0.5, Max = 4.0, Rounding = 1, Callback = function(v) cfg.china_hat_radius = v end })
        s:AddSlider("china_hat_height", { Text = "height", Default = 0.65, Min = 0.1, Max = 2.0, Rounding = 2, Callback = function(v) cfg.china_hat_height = v end })
        s:AddSlider("china_hat_trans", { Text = "transparency", Default = 0.4, Min = 0.1, Max = 1.0, Rounding = 2, Callback = function(v) cfg.china_hat_trans = v end })
        s:AddSlider("china_hat_speed", { Text = "rotation speed", Default = 2.0, Min = 0, Max = 6.0, Rounding = 1, Callback = function(v) cfg.china_hat_speed = v end })
    end)

    local backtrack_toggle = self_group:AddToggle("backtrack_enabled", { Text = "backtrack", Default = false, Callback = function(v) cfg.backtrack_enabled = v; if not v then backtrack:clear() end end })
    backtrack_toggle:AddColorPicker("backtrack_col", { Default = Color3_fromRGB(130, 90, 230), Title = "backtrack color", Callback = function(v) cfg.backtrack_color = v end })
    backtrack_toggle:AddSettings(function(s)
        s:AddSlider("backtrack_trans", { Text = "transparency", Default = 0.4, Min = 0.1, Max = 1, Rounding = 2, Callback = function(v) cfg.backtrack_trans = v end })
    end)

    skybox_group:AddToggle("skybox_toggle", { Text = "enabled", Default = false, Callback = function(v) cfg.skybox_enabled = v; skybox:apply() end })
    skybox_group:AddDropdown("skybox_preset", { Text = "preset", Values = { "Anime Sky", "Pastel Anime", "City Sky" }, Default = 1, Callback = function(v) cfg.skybox_preset = v; skybox:apply() end })

    camera_group:AddToggle("custom_fov", {
        Text = "custom fov",
        Default = false,
        Callback = function(enabled)
            if not enabled then camera.FieldOfView = baseline.fov end
        end
    })
    camera_group:AddSlider("fov_val", {
        Text = "fov value",
        Default = 90, Min = 60, Max = 120,
        Callback = function(val)
            if toggles.custom_fov and toggles.custom_fov.Value then camera.FieldOfView = val end
        end
    })
end

-- Bullet Tracers & Weapon Chams & Self Chams Implementations
local function get_barrel_pos()
    local char = local_player.Character
    if not char then return nil end
    local tool = char:FindFirstChildOfClass("Tool")
    if tool then
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
    if not from_pos then from_pos = get_barrel_pos() end
    if not to_pos then to_pos = get_tracer_end_pos() end
    if not from_pos or not to_pos then return end

    local color = (options.tracer_col and options.tracer_col.Value) or Color3_fromRGB(140, 230, 255)
    local duration = (options.tracer_dur and options.tracer_dur.Value) or 0.75
    local width = (options.tracer_w and options.tracer_w.Value) or 0.15

    local dist = (to_pos - from_pos).Magnitude
    if dist < 0.05 then return end

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
    beam.Width0 = width * 2
    beam.Width1 = width * 2
    beam.FaceCamera = true
    beam.Segments = math_clamp(math_floor(dist / 4), 10, 30)
    beam.Texture = "rbxassetid://13712004045"
    beam.TextureMode = Enum.TextureMode.Static
    beam.TextureLength = 15
    beam.TextureSpeed = 40
    beam.Transparency = NumberSequence.new(0.12)
    beam.Parent = workspace.Terrain

    local ref = { beam = beam, a0 = a0, a1 = a1 }
    ctx.tracers[ref] = true

    task_spawn(function()
        local t0 = os.clock()
        while ctx.running do
            local dt = os.clock() - t0
            if dt >= duration then break end
            local alpha = dt / duration
            local trans = math_clamp(alpha * alpha, 0, 1)
            beam.Transparency = NumberSequence.new(math_clamp(0.12 + trans, 0, 1))
            run_service.RenderStepped:Wait()
        end
        ctx.tracers[ref] = nil
        pcall(function() beam:Destroy() end)
        pcall(function() a0:Destroy() end)
        pcall(function() a1:Destroy() end)
    end)
end

local last_shot_time = 0
local function trigger_shot_tracer()
    local now = os.clock()
    if now - last_shot_time < 0.03 then return end
    last_shot_time = now
    if toggles.bullet_tracer and toggles.bullet_tracer.Value then
        task.defer(make_tracer)
    end
end

local monitored_tools = {}
local function setup_tool_ammo_listener(tool)
    if not tool or not tool:IsA("Tool") or monitored_tools[tool] then return end
    monitored_tools[tool] = true

    local ammo_names = { Mag = true, Ammo = true, Clip = true, CurrentAmmo = true }
    local function watch_ammo_obj(obj)
        if (obj:IsA("IntValue") or obj:IsA("NumberValue")) and ammo_names[obj.Name] then
            local last_val = obj.Value
            table_insert(ctx.conns, obj:GetPropertyChangedSignal("Value"):Connect(function()
                local new_val = obj.Value
                if new_val < last_val then trigger_shot_tracer() end
                last_val = new_val
            end))
        end
    end

    for _, desc in ipairs(tool:GetDescendants()) do watch_ammo_obj(desc) end
    table_insert(ctx.conns, tool.DescendantAdded:Connect(watch_ammo_obj))
end

if local_player.Character then
    for _, item in ipairs(local_player.Character:GetChildren()) do
        if item:IsA("Tool") then setup_tool_ammo_listener(item) end
    end
    table_insert(ctx.conns, local_player.Character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then setup_tool_ammo_listener(child) end
    end))
end

table_insert(ctx.conns, local_player.CharacterAdded:Connect(function(char)
    table_insert(ctx.conns, char.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then setup_tool_ammo_listener(child) end
    end))
end))

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

    local my_vm = local_player.Character and local_player.Character:FindFirstChildOfClass("Tool")
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
            if (p:IsA("MeshPart") or p:IsA("BasePart")) and p.Transparency < 1 and not p.Name:find("HumanoidRootPart") then
                table_insert(list, p)
                self.orig[p] = { Material = p.Material, Color = p.Color, Transparency = p.Transparency }
            end
        end
        self.cached = list
    end

    local mat = Enum.Material.Neon
    local name = cfg.weapon_chams_type or "Neon"
    if name == "ForceField" or name:find("Forcefield") then mat = Enum.Material.ForceField
    elseif name == "Glass" then mat = Enum.Material.Glass end

    for _, p in ipairs(self.cached) do
        if p and p.Parent then
            p.Material = mat
            p.Color = cfg.weapon_chams_color or Color3_fromRGB(180, 100, 255)
            p.Transparency = cfg.weapon_chams_trans or 0
        end
    end
end

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
end

function self_chams:render()
    if not cfg.self_chams_enabled then
        if next(self.orig) ~= nil or self.highlight ~= nil then self:reset() end
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

    local mode = string_lower(tostring(cfg.self_chams_mode or "forcefield 2"))
    local color = cfg.self_chams_color or Color3_fromHex("#b464ff")
    local trans = cfg.self_chams_trans or 0.6

    local needs_highlight = (mode == "forcefield 2" or mode == "highlight")
    if needs_highlight then
        if not self.highlight or self.highlight.Parent ~= char then
            if self.highlight then pcall(function() self.highlight:Destroy() end) end
            local h = Instance.new("Highlight")
            h.Name = "VantageSelfChams"
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.Parent = char
            self.highlight = h
        end
        self.highlight.FillColor = color
        self.highlight.OutlineColor = color
        self.highlight.FillTransparency = (mode == "highlight") and 0.5 or math_clamp(trans, 0.1, 0.9)
        self.highlight.OutlineTransparency = 0
        self.highlight.Enabled = true

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
        if self.highlight then
            pcall(function() self.highlight:Destroy() end)
            self.highlight = nil
        end
    end

    local modifies_parts = (mode == "forcefield" or mode == "forcefield 2")
    if modifies_parts then
        local target_mat = Enum.Material.ForceField
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and not part:FindFirstAncestorOfClass("Tool") then
                if not self.orig[part] then
                    self.orig[part] = { Material = part.Material, Color = part.Color, Transparency = part.Transparency }
                end
                if part.Material ~= target_mat then part.Material = target_mat end
                if part.Color ~= color then part.Color = color end
                if part.Transparency ~= trans then part.Transparency = trans end
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

function china_hat:get_part()
    local cur_cam = workspace.CurrentCamera
    if not cur_cam then return nil end

    if self.part and self.part.Parent == cur_cam then return self.part end
    if self.part and self.part.Parent ~= cur_cam then
        pcall(function() self.part:Destroy() end)
        self.part = nil; self.mesh = nil
    end

    local existing = cur_cam:FindFirstChild("Visuals_ChinaHat")
    if existing and existing:IsA("BasePart") then
        self.part = existing
        self.mesh = existing:FindFirstChildOfClass("SpecialMesh")
        return self.part
    end

    local radius = cfg.china_hat_radius or 2.2
    local cone_h = math_clamp(radius * 0.28, 0.35, 1.2)

    local part = Instance.new("Part")
    part.Name = "Visuals_ChinaHat"
    part.Anchored = true; part.CanCollide = false; part.CanTouch = false; part.CanQuery = false; part.CastShadow = false
    part.Material = Enum.Material.SmoothPlastic
    part.Color = cfg.china_hat_color or Color3_fromHex("#b464ff")
    part.Transparency = cfg.china_hat_trans or 0.4
    part.Size = Vector3_new(radius * 2, cone_h, radius * 2)
    part.Parent = cur_cam

    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = "rbxassetid://1033714"
    mesh.TextureId = ""
    mesh.VertexColor = Vector3_new(1, 1, 1)
    mesh.Scale = Vector3_new(radius * 2, cone_h * 2, radius * 2)
    mesh.Parent = part

    self.part = part; self.mesh = mesh
    return part
end

function china_hat:hide()
    if self.part then self.part.Transparency = 1 end
end

function china_hat:render(dt)
    if not cfg.china_hat_enabled then self:hide(); return end

    local cur_cam = workspace.CurrentCamera
    local char = local_player.Character
    local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not head or not cur_cam or (hum and hum.Health <= 0) then self:hide(); return end

    local part = self:get_part()
    if not part then return end

    local dist_to_cam = (cur_cam.CFrame.Position - head.Position).Magnitude
    if dist_to_cam < 1.4 then self:hide(); return end

    local radius = cfg.china_hat_radius or 2.2
    local h_offset = cfg.china_hat_height or 0.65
    local trans = cfg.china_hat_trans or 0.4
    local speed = cfg.china_hat_speed or 2.0
    local color = cfg.china_hat_color or Color3_fromHex("#b464ff")
    local cone_h = math_clamp(radius * 0.28, 0.35, 1.2)

    local step = (type(dt) == "number" and dt > 0 and dt < 0.2) and dt or (1 / 60)
    self.rotation = (self.rotation + (speed * 45 * step)) % 360

    local head_top = head.Position + Vector3_new(0, (head.Size.Y * 0.5) + h_offset, 0)
    part.CFrame = CFrame.new(head_top) * CFrame.Angles(0, math_rad(self.rotation), 0)
    part.Size = Vector3_new(radius * 2, cone_h, radius * 2)
    part.Color = color
    part.Transparency = trans
    if self.mesh then
        self.mesh.Scale = Vector3_new(radius * 2, cone_h * 2, radius * 2)
    end
end

local function make_forcefield_ghost(model, ghost_color, transparency)
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() hum:Destroy() end) end
    local anim = model:FindFirstChildOfClass("AnimationController")
    if anim then pcall(function() anim:Destroy() end) end

    for _, item in ipairs(model:GetDescendants()) do
        if item:IsA("Script") or item:IsA("LocalScript") or item:IsA("ModuleScript") or item:IsA("Animator") then
            pcall(function() item:Destroy() end)
        elseif item:IsA("UIComponent") or item:IsA("ScreenGui") or item:IsA("BillboardGui") or item:IsA("Decal") or item:IsA("Texture") or item:IsA("Clothing") or item:IsA("Shirt") or item:IsA("Pants") or item:IsA("ShirtGraphic") or item:IsA("CharacterMesh") or item:IsA("SurfaceAppearance") then
            pcall(function() item:Destroy() end)
        elseif item:IsA("SpecialMesh") then
            pcall(function() item.TextureId = "" end)
        elseif item:IsA("MeshPart") then
            pcall(function() item.TextureID = "" end)
            item.Anchored = true; item.CanCollide = false; item.CanTouch = false; item.CanQuery = false; item.CastShadow = false; item.Massless = true
            item.Material = Enum.Material.ForceField; item.Color = ghost_color; item.Transparency = transparency or 0.4
        elseif item:IsA("BasePart") then
            item.Anchored = true; item.CanCollide = false; item.CanTouch = false; item.CanQuery = false; item.CastShadow = false; item.Massless = true
            if item.Name == "HumanoidRootPart" then item.Transparency = 1
            else item.Material = Enum.Material.ForceField; item.Color = ghost_color; item.Transparency = transparency or 0.4 end
        end
    end
end

function backtrack:clear()
    if self.clone then
        pcall(function() self.clone:Destroy() end)
        self.clone = nil
    end
    table.clear(self.history)
end

function backtrack:render()
    if not cfg.backtrack_enabled or not local_player.Character then
        if self.clone then pcall(function() self.clone:Destroy() end); self.clone = nil end
        return
    end

    local char = local_player.Character
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then
        if self.clone then pcall(function() self.clone:Destroy() end); self.clone = nil end
        return
    end

    local now = os.clock()
    table_insert(self.history, { time = now, cframe = hrp.CFrame })
    while #self.history > 0 and (now - self.history[1].time) > self.max_history_time do
        table.remove(self.history, 1)
    end

    local target_cframe = self.history[1] and self.history[1].cframe or hrp.CFrame
    if not self.clone or not self.clone.Parent then
        local was_arch = char.Archivable
        char.Archivable = true
        local clone = nil
        pcall(function() clone = char:Clone() end)
        char.Archivable = was_arch
        if clone then
            make_forcefield_ghost(clone, cfg.backtrack_color or Color3_fromRGB(130, 90, 230), cfg.backtrack_trans or 0.4)
            clone.Name = "LocalBacktrackGhost"
            clone.Parent = workspace
            self.clone = clone
        end
    end

    local clone = self.clone
    if clone then
        local offset = target_cframe * hrp.CFrame:Inverse()
        for _, part in ipairs(clone:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
                local orig_part = char:FindFirstChild(part.Name, true)
                if orig_part and orig_part:IsA("BasePart") then
                    part.CFrame = offset * orig_part.CFrame
                end
            end
        end
    end
end

function world:apply()
    if not cfg.ambient_enabled then self:reset(); return end
    lighting.Ambient = cfg.ambient_color or Color3_fromHex("#919090")
    lighting.OutdoorAmbient = cfg.outdoor_color or Color3_fromHex("#5a3782")
    lighting.ClockTime = cfg.clock_time or 0
    if not self.cc then
        local cc = Instance.new("ColorCorrectionEffect")
        cc.Name = "_v_ambient_cc"; cc.Parent = lighting; self.cc = cc
    end
    self.cc.Brightness = cfg.ambient_brightness or 0.05
    self.cc.Contrast = cfg.ambient_contrast or 0.15
    self.cc.Saturation = cfg.ambient_saturation or 0.25
end

function world:reset()
    lighting.Ambient = baseline.ambient
    lighting.OutdoorAmbient = baseline.outdoor
    lighting.ClockTime = baseline.clock_time
    if self.cc then pcall(function() self.cc:Destroy() end); self.cc = nil end
end

function particles:clear()
    self.gen = self.gen + 1
    if self.part then pcall(function() self.part:Destroy() end); self.part = nil; self.emitter = nil end
    if self.folder then pcall(function() self.folder:Destroy() end); self.folder = nil end
    self.simulated = {}
end

function particles:update_colors()
    if self.emitter then self.emitter.Color = ColorSequence.new(cfg.particles_color) end
end

function particles:update_flight() end
function particles:update_rate() if self.emitter then self.emitter.Rate = (cfg.particles_count or 23) * 1.6 end end

function particles:init()
    self:clear()
    if not cfg.particles_enabled then return end
    local p = Instance.new("Part")
    p.Size = Vector3_new(150, 40, 150)
    p.Transparency = 1; p.Anchored = true; p.CanCollide = false; p.Parent = workspace.Terrain
    self.part = p

    local em = Instance.new("ParticleEmitter")
    em.Texture = "https://img.icons8.com/ios-filled/250/ffffff/snowflake.png"
    em.Lifetime = NumberRange.new(7.0, 11.0)
    em.Rate = (cfg.particles_count or 23) * 1.6
    em.Parent = p
    self.emitter = em
    self:update_colors()
end

function particles:render()
    if not cfg.particles_enabled or not self.part then return end
    local char = local_player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root then self.part.CFrame = CFrame.new(root.Position.X, root.Position.Y + 15, root.Position.Z) end
end

-- =========================================================================
-- [[ MODULE 4: TELEPORTS & MAP OBJECTS ]]
-- =========================================================================
local MapLocations = {
    ["bank"] = Vector3_new(-512, 12, 134),
    ["casino"] = Vector3_new(320, 14, -410),
    ["warehouse"] = Vector3_new(-120, 8, 520),
    ["doug's gun shop"] = Vector3_new(-210, 10, -150),
    ["mountain gun shop"] = Vector3_new(640, 45, 310),
    ["hospital"] = Vector3_new(-340, 12, 45)
}

local function TeleportToPosition(pos, name)
    local hrp = local_player.Character and local_player.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        hrp.CFrame = CFrame.new(pos + Vector3_new(0, 3, 0))
        library:Notify("teleported to " .. (name or "location") .. "!", 3)
    end
end

local function GetCurrentlySpawnedMapItems()
    local items = {}
    local map = workspace:FindFirstChild("Map") or workspace
    for _, desc in ipairs(map:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Parent and desc.Parent:IsA("BasePart") then
            local n = string_lower(desc.ObjectText ~= "" and desc.ObjectText or desc.Parent.Name)
            if not table.find(items, n) then table_insert(items, n) end
        end
    end
    if #items == 0 then table_insert(items, "none available") end
    table_sort(items)
    return items
end

do
    local loc_group = tabs.teleport:AddGroupbox({ Side = 1, Name = "location teleports", DisableCollapsing = true })
    local obj_group = tabs.teleport:AddGroupbox({ Side = 2, Name = "objects", DisableCollapsing = true })

    local loc_names = {}
    for k in pairs(MapLocations) do table_insert(loc_names, k) end
    table_sort(loc_names)

    loc_group:AddDropdown("location_dropdown", { Values = loc_names, Default = 1, Text = "select location" })
    loc_group:AddButton({
        Text = "teleport to location",
        Func = function()
            local sel = options.location_dropdown and options.location_dropdown.Value
            if sel and MapLocations[sel] then TeleportToPosition(MapLocations[sel], sel) end
        end
    })
    loc_group:AddDivider()
    loc_group:AddButton({ Text = "teleport to bank", Func = function() TeleportToPosition(MapLocations["bank"], "bank") end })
    loc_group:AddButton({ Text = "teleport to casino", Func = function() TeleportToPosition(MapLocations["casino"], "casino") end })
    loc_group:AddButton({ Text = "teleport to doug's gun shop", Func = function() TeleportToPosition(MapLocations["doug's gun shop"], "doug's gun shop") end })

    obj_group:AddDropdown("map_item_dropdown", { Values = GetCurrentlySpawnedMapItems(), Default = 1, Text = "select item to collect" })
    obj_group:AddDropdown("player_tp_dropdown", { SpecialType = "Player", ExcludeLocalPlayer = true, EnablePlayerImages = true, Text = "select target player" })
    obj_group:AddButton({
        Text = "teleport to player",
        Func = function()
            local sel = options.player_tp_dropdown and options.player_tp_dropdown.Value
            local target_player = sel and players:FindFirstChild(tostring(sel))
            local target_hrp = target_player and target_player.Character and target_player.Character:FindFirstChild("HumanoidRootPart")
            local my_hrp = local_player.Character and local_player.Character:FindFirstChild("HumanoidRootPart")
            if target_hrp and my_hrp then
                my_hrp.CFrame = target_hrp.CFrame * CFrame.new(0, 0, 3)
                library:Notify("teleported to " .. string_lower(target_player.DisplayName) .. "!", 3)
            end
        end
    })
end

-- =========================================================================
-- [[ MODULE 5: AUTO FARM & CASINO ]]
-- =========================================================================
do
    local farm_group = tabs.farm:AddGroupbox({ Side = 1, Name = "auto farm", DisableCollapsing = true })
    local casino_group = tabs.casino:AddGroupbox({ Side = 1, Name = "casino", DisableCollapsing = true })

    farm_group:AddToggle("box_farm", { Text = "auto box farm", Default = false, Callback = function(v) cfg.box_farm = v end })
    farm_group:AddToggle("lumber_farm", { Text = "auto lumber farm", Default = false, Callback = function(v) cfg.lumber_farm = v end })
    farm_group:AddToggle("mining_farm", { Text = "auto mining farm", Default = false, Callback = function(v) cfg.mining_farm = v end })
    farm_group:AddToggle("scrap_farm", { Text = "auto scrap farm", Default = false, Callback = function(v) cfg.scrap_farm = v end })
    farm_group:AddToggle("auto_deposit", { Text = "auto deposit cash", Default = false, Callback = function(v) cfg.auto_deposit = v end })

    casino_group:AddToggle("casino_auto_spin", { Text = "auto spin wheel", Default = false, Callback = function(v) cfg.casino_auto_spin = v end })
    casino_group:AddToggle("casino_auto_steal", { Text = "auto steal cashier", Default = false, Callback = function(v) cfg.casino_auto_steal = v end })
end

-- =========================================================================
-- [[ MODULE 6: SHOP & ATM PURCHASES ]]
-- =========================================================================
do
    local GunsCatalog = {
        { "boxed hunting sniper ($3877)", 3877, "hunting sniper" },
        { "boxed marksman rifle ($2450)", 2450, "marksman rifle" },
        { "boxed hunting rifle ($1449)", 1449, "hunting rifle" },
        { "boxed semi carbine ($1250)", 1250, "semi carbine" },
        { "boxed compact rifle ($1220)", 1220, "compact rifle" },
        { "boxed heavy pistol ($890)", 890, "heavy pistol" },
        { "boxed semi sten ($890)", 890, "semi sten" },
        { "boxed old rifle ($862)", 862, "old rifle" },
        { "boxed smg ($865)", 865, "smg" },
        { "boxed heavy revolver ($787)", 787, "heavy revolver" },
        { "boxed defense shotgun ($644)", 644, "defense shotgun" },
        { "boxed micro smg ($750)", 750, "micro smg" },
        { "boxed combat shotgun ($736)", 736, "combat shotgun" },
        { "boxed auto pistol ($725)", 725, "auto pistol" },
        { "boxed revolver ($650)", 650, "revolver" },
        { "boxed suppressed pistol ($575)", 575, "suppressed" },
        { "boxed enforcement pistol ($555)", 555, "enforcement pistol" },
        { "boxed combat pistol ($520)", 520, "combat pistol" },
        { "boxed compact revolver ($420)", 420, "compact revolver" },
        { "boxed semi mac ($482)", 482, "semi mac" },
        { "boxed compact pistol ($349)", 349, "compact pistol" },
        { "boxed air rifle ($63)", 63, "air rifle" },
        { "boxed air pistol ($48)", 48, "air pistol" },
        { "dynamite ($175)", 175, "dynamite" },
        { "f1 grenade ($90)", 90, "f1 grenade" },
        { "molotov ($120)", 120, "molotov" }
    }

    local MedCatalog = {
        { "bandages ($15)", 15, "bandages" },
        { "pepper spray ($60)", 60, "pepper spray" },
        { "bottled water ($7)", 7, "bottled water" },
        { "2l bottled cola ($14)", 14, "2l bottled cola" },
        { "cola ($8)", 8, "cola" },
        { "root beer ($16)", 16, "root beer" }
    }

    local FoodCatalog = {
        { "cereal ($13)", 13, "cereal" },
        { "noodles ($11)", 11, "noodles" },
        { "potato chips ($11)", 11, "potato chips" },
        { "pepperoni slice ($11)", 11, "pepperoni slice" },
        { "chocolate bar ($10)", 10, "chocolate bar" },
        { "taco ($10)", 10, "taco" },
        { "ice cream ($7)", 7, "ice cream" }
    }

    local MeleeCatalog = {
        { "pickaxe ($92)", 92, "pickaxe" },
        { "axe ($60)", 60, "axe" },
        { "pocket knife ($55)", 55, "pocket knife" },
        { "hunting knife ($35)", 35, "hunting knife" },
        { "lockpick ($49)", 49, "lockpick" },
        { "lighter ($42)", 42, "lighter" },
        { "lantern ($37)", 37, "lantern" },
        { "spray paint ($35)", 35, "spray paint" }
    }

    local function ExtractNames(list)
        local names = {}
        for _, item in ipairs(list) do table_insert(names, item[1]) end
        return names
    end

    local is_buying_debounce = false
    local function WithdrawForPurchase(price)
        local leaderstats = local_player:FindFirstChild("leaderstats")
        local cashVal = leaderstats and leaderstats:FindFirstChild("Cash")
        local currentCash = cashVal and cashVal.Value or 0
        if currentCash >= price then return true end

        local bankData = local_player:FindFirstChild("BankData")
        local depositedVal = bankData and bankData:FindFirstChild("DepositedValue")
        local currentBank = depositedVal and depositedVal.Value or 0
        if (currentCash + currentBank) < price then return false end

        local atmEv = replicated_storage:FindFirstChild("ATMEvent")
        if atmEv and currentBank > 0 then
            atmEv:FireServer(price - currentCash, "withdraw")
            local start = tick()
            while tick() - start < 1.5 do
                task_wait(0.05)
                if cashVal and cashVal.Value >= price then break end
            end
            return (cashVal and cashVal.Value >= price)
        end
        return false
    end

    local function BuyWeaponByMatch(matchName, cost, fullName)
        if is_buying_debounce then return end
        is_buying_debounce = true

        pcall(function()
            local hrp = local_player.Character and local_player.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then return end

            local bestPrompt, bestPriceDiff = nil, math_huge
            local targetMatchLower = string_lower(matchName)

            for _, prompt in ipairs(workspace:GetDescendants()) do
                if prompt:IsA("ProximityPrompt") and prompt.Parent and prompt.Parent:IsA("BasePart") then
                    local objText = string_lower(prompt.ObjectText or "")
                    local actText = string_lower(prompt.ActionText or "")
                    local pName = string_lower(prompt.Parent.Name)

                    local isMatch = false
                    if objText == targetMatchLower or pName == targetMatchLower then
                        isMatch = true
                    elseif string_find(objText, targetMatchLower, 1, true) or string_find(pName, targetMatchLower, 1, true) then
                        isMatch = true
                    end

                    if isMatch then
                        local promptPrice = tonumber(string_match(actText, "%((%d+)%)") or string_match(actText, "(%d+)"))
                        if promptPrice then
                            local diff = math_abs(promptPrice - cost)
                            if diff < bestPriceDiff then bestPriceDiff, bestPrompt = diff, prompt end
                        elseif not bestPrompt then
                            bestPrompt = prompt
                        end
                    end
                end
            end

            if bestPrompt and bestPrompt.Parent then
                local actText = string_lower(bestPrompt.ActionText or "")
                local actualPrice = tonumber(string_match(actText, "%((%d+)%)") or string_match(actText, "(%d+)")) or cost

                if not WithdrawForPurchase(actualPrice) then
                    library:Notify("not enough money for " .. (fullName or matchName) .. "!", 3)
                    return
                end
                task_wait(0.15)

                local savedCF = hrp.CFrame
                local origHold, origDist = bestPrompt.HoldDuration, bestPrompt.MaxActivationDistance
                pcall(function() bestPrompt.HoldDuration, bestPrompt.MaxActivationDistance = 0, 1000 end)

                local pPart = bestPrompt.Parent
                if pPart and pPart:IsA("BasePart") then
                    hrp.CFrame = pPart.CFrame * CFrame.new(0, 0, 2.5)
                    hrp.AssemblyLinearVelocity = Vector3_zero
                end
                task_wait(0.15)

                if fireproximityprompt then
                    pcall(function() fireproximityprompt(bestPrompt, 0, true) end)
                    pcall(function() fireproximityprompt(bestPrompt, 0) end)
                    pcall(function() fireproximityprompt(bestPrompt) end)
                end
                pcall(function()
                    bestPrompt:InputHoldBegan()
                    task_wait(0.05)
                    bestPrompt:InputHoldEnded()
                end)
                task_wait(0.25)

                pcall(function() bestPrompt.HoldDuration, bestPrompt.MaxActivationDistance = origHold, origDist end)
                hrp.CFrame = savedCF
                library:Notify("purchased 1x " .. (fullName or matchName) .. " ($" .. actualPrice .. ")!", 3)
            else
                library:Notify("item prompt for " .. matchName .. " not found nearby!", 3)
            end
        end)

        task_wait(0.2)
        is_buying_debounce = false
    end

    local function BuyCatalogItem(catalog, selectedText)
        for _, item in ipairs(catalog) do
            if item[1] == selectedText then
                BuyWeaponByMatch(item[3], item[2], item[1])
                break
            end
        end
    end

    local ShopGunsGroup = tabs.shop:AddGroupbox({ Side = 1, Name = "guns", DisableCollapsing = true })
    local ShopMedGroup = tabs.shop:AddGroupbox({ Side = 2, Name = "medical", DisableCollapsing = true })
    local ShopFoodGroup = tabs.shop:AddGroupbox({ Side = 1, Name = "food", DisableCollapsing = true })
    local ShopMeleeGroup = tabs.shop:AddGroupbox({ Side = 2, Name = "misc", DisableCollapsing = true })

    ShopGunsGroup:AddDropdown("selected_gun", { Values = ExtractNames(GunsCatalog), Default = 1, Text = "select weapon" })
    ShopMedGroup:AddDropdown("selected_med", { Values = ExtractNames(MedCatalog), Default = 1, Text = "select medical" })
    ShopFoodGroup:AddDropdown("selected_food", { Values = ExtractNames(FoodCatalog), Default = 1, Text = "select food" })
    ShopMeleeGroup:AddDropdown("selected_melee", { Values = ExtractNames(MeleeCatalog), Default = 1, Text = "select misc" })

    ShopGunsGroup:AddButton({ Text = "buy selected", Func = function() BuyCatalogItem(GunsCatalog, options.selected_gun and options.selected_gun.Value) end })
    ShopMedGroup:AddButton({ Text = "buy selected", Func = function() BuyCatalogItem(MedCatalog, options.selected_med and options.selected_med.Value) end })
    ShopFoodGroup:AddButton({ Text = "buy selected", Func = function() BuyCatalogItem(FoodCatalog, options.selected_food and options.selected_food.Value) end })
    ShopMeleeGroup:AddButton({ Text = "buy selected", Func = function() BuyCatalogItem(MeleeCatalog, options.selected_melee and options.selected_melee.Value) end })
end

-- =========================================================================
-- [[ MODULE 7: MISC & STATS ]]
-- =========================================================================
do
    local bank_group = tabs.misc:AddGroupbox({ Side = 1, Name = "atm actions", DisableCollapsing = true })
    bank_group:AddButton({
        Text = "withdraw all",
        Func = function()
            local bankData = local_player:FindFirstChild("BankData")
            local depositedVal = bankData and bankData:FindFirstChild("DepositedValue")
            local deposited = depositedVal and depositedVal.Value or 0
            local atmEv = replicated_storage:FindFirstChild("ATMEvent")
            if atmEv and deposited > 0 then
                atmEv:FireServer(deposited, "withdraw")
                library:Notify("withdrew $" .. deposited .. " from bank!", 3)
            end
        end
    })
    bank_group:AddButton({
        Text = "deposit all",
        Func = function()
            local leaderstats = local_player:FindFirstChild("leaderstats")
            local cashVal = leaderstats and leaderstats:FindFirstChild("Cash")
            local cash = cashVal and cashVal.Value or 0
            local atmEv = replicated_storage:FindFirstChild("ATMEvent")
            if atmEv and cash > 0 then
                atmEv:FireServer(cash, "deposit")
                library:Notify("deposited $" .. cash .. " into bank!", 3)
            end
        end
    })
end

-- =========================================================================
-- [[ MODULE 8: CANONICAL CONFIG TAB ]]
-- =========================================================================
local function unload()
    ctx.running = false

    for _, conn in ipairs(ctx.conns) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(ctx.conns)

    if ctx.hooks.namecall then pcall(function() restorefunction(ctx.hooks.namecall) end) end
    if ctx.hooks.index then pcall(function() restorefunction(ctx.hooks.index) end) end

    for _, draw in ipairs(ctx.drawings) do pcall(function() draw:Remove() end) end
    table.clear(ctx.drawings)

    pcall(function() self_chams:reset() end)
    pcall(function() china_hat:hide() end)
    pcall(function() particles:clear() end)
    pcall(function() weapon_chams:clear() end)
    pcall(function() skybox:reset() end)
    pcall(function() world:reset() end)
    pcall(function() backtrack:clear() end)

    pcall(function() camera.FieldOfView = baseline.fov end)
    local hum = local_player.Character and local_player.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function() hum.WalkSpeed = baseline.speed end)
        pcall(function() hum.JumpPower = baseline.jump end)
    end

    pcall(function() library:Unload() end)
    getgenv().__v_ctx_unload = nil
end

getgenv().__v_ctx_unload = unload

do
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
        Default = 50, Min = 0, Max = 100, Suffix = "%",
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

    menu_group:AddLabel("menu bind"):AddKeyPicker("menu_bind", { Default = "RightShift", NoUI = true, Text = "menu keybind" })
    library.ToggleKeybind = options.menu_bind

    menu_group:AddButton({
        Text = "unload",
        Func = function() unload() end
    })

    theme_mgr:SetLibrary(library)
    theme_mgr:SetFolder("vantage/assets")
    theme_mgr:ApplyTheme("vantage")

    save_mgr:SetLibrary(library)
    save_mgr:IgnoreThemeSettings()
    save_mgr:SetIgnoreIndexes({ "menu_bind" })
    save_mgr:SetFolder("vantage/assets")
    save_mgr:SetSubFolder("config")

    save_mgr:BuildConfigSection(tabs.config)
    theme_mgr:ApplyToTab(tabs.config)
    save_mgr:LoadAutoloadConfig()

    library:OnUnload(function()
        unload()
    end)
end

-- =========================================================================
-- [[ MODULE 9: MAIN LOOP & RENDER ]]
-- =========================================================================
table_insert(ctx.conns, run_service.RenderStepped:Connect(function(dt)
    if not ctx.running then return end
    update_esp_rendering()
    particles:render()
    china_hat:render(dt)
    self_chams:render()
    weapon_chams:render()
    backtrack:render()
end))

task_spawn(function()
    while ctx.running do
        task_wait(0.5)

        -- Auto Deposit Cash
        if cfg.auto_deposit then
            pcall(function()
                local leaderstats = local_player:FindFirstChild("leaderstats")
                local cashVal = leaderstats and leaderstats:FindFirstChild("Cash")
                local cash = cashVal and cashVal.Value or 0
                local atmEv = replicated_storage:FindFirstChild("ATMEvent")
                if atmEv and cash > 0 then
                    atmEv:FireServer(cash, "deposit")
                end
            end)
        end

        -- Auto Box Farm (Delivery Job)
        if cfg.box_farm then
            pcall(function()
                local hrp = local_player.Character and local_player.Character:FindFirstChild("HumanoidRootPart")
                local bj = workspace:FindFirstChild("Box Job") or workspace:FindFirstChild("BoxJob")
                if hrp and bj then
                    local cargos = { "cargo", "cargo2", "cargo3", "cargo4", "cargo5", "cargo6", "cargo7", "HitBox" }
                    local delivs = { "BloxmartDeliv", "PizzaDeliv", "ForestDeliv", "StockNGoDelivery" }

                    for _, cName in ipairs(cargos) do
                        if not cfg.box_farm or not ctx.running then break end
                        local cargoPart = bj:FindFirstChild(cName)
                        if cargoPart then
                            local targetPart = cargoPart:IsA("BasePart") and cargoPart or cargoPart:FindFirstChildOfClass("BasePart")
                            if targetPart then
                                hrp.CFrame = targetPart.CFrame + Vector3_new(0, 2, 0)
                                task_wait(0.12)
                                if firetouchinterest then
                                    firetouchinterest(hrp, targetPart, 0)
                                    task_wait(0.05)
                                    firetouchinterest(hrp, targetPart, 1)
                                end
                                local child1 = cargoPart:FindFirstChild("1")
                                if child1 and child1:IsA("BasePart") and firetouchinterest then
                                    firetouchinterest(hrp, child1, 0)
                                    task_wait(0.05)
                                    firetouchinterest(hrp, child1, 1)
                                end
                            end
                        end
                    end

                    task_wait(0.2)

                    for _, dName in ipairs(delivs) do
                        if not cfg.box_farm or not ctx.running then break end
                        local delivPart = bj:FindFirstChild(dName)
                        if delivPart then
                            local targetPart = delivPart:IsA("BasePart") and delivPart or delivPart:FindFirstChildOfClass("BasePart")
                            if targetPart then
                                hrp.CFrame = targetPart.CFrame + Vector3_new(0, 2, 0)
                                task_wait(0.12)
                                if firetouchinterest then
                                    firetouchinterest(hrp, targetPart, 0)
                                    task_wait(0.05)
                                    firetouchinterest(hrp, targetPart, 1)
                                end
                            end
                        end
                    end
                end
            end)
        end

        -- Auto Scrap Farm
        if cfg.scrap_farm then
            pcall(function()
                local hrp = local_player.Character and local_player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local scrapPrompts = {}
                    for _, desc in ipairs(workspace:GetDescendants()) do
                        if desc:IsA("ProximityPrompt") then
                            local txt = string_lower((desc.ObjectText or "") .. " " .. (desc.ActionText or "") .. " " .. (desc.Parent and desc.Parent.Name or ""))
                            if string_find(txt, "scrap") or string_find(txt, "junk") then
                                table_insert(scrapPrompts, desc)
                            end
                        end
                    end

                    for _, prompt in ipairs(scrapPrompts) do
                        if not cfg.scrap_farm or not ctx.running then break end
                        local part = prompt.Parent and prompt.Parent:IsA("BasePart") and prompt.Parent
                        if part then
                            hrp.CFrame = part.CFrame + Vector3_new(0, 2, 0)
                            task_wait(0.15)
                            if fireproximityprompt then
                                fireproximityprompt(prompt, 0, true)
                                fireproximityprompt(prompt, 0)
                                fireproximityprompt(prompt)
                            end
                            task_wait(0.15)
                        end
                    end

                    local wade = workspace:FindFirstChild("NPC") and workspace.NPC:FindFirstChild("Wade Cruz")
                    local wadePrompt = wade and wade:FindFirstChildWhichIsA("ProximityPrompt", true)
                    if wadePrompt and wadePrompt.Parent and wadePrompt.Parent:IsA("BasePart") then
                        hrp.CFrame = wadePrompt.Parent.CFrame + Vector3_new(0, 2, 0)
                        task_wait(0.15)
                        if fireproximityprompt then
                            fireproximityprompt(wadePrompt, 0, true)
                            fireproximityprompt(wadePrompt, 0)
                            fireproximityprompt(wadePrompt)
                        end
                    end
                end
            end)
        end

        -- Auto Mining Farm
        if cfg.mining_farm then
            pcall(function()
                local hrp = local_player.Character and local_player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local oreSell = workspace.Map.Nature.Structures.OreNPIckShack:FindFirstChild("ore sell")
                    local prompt = oreSell and oreSell:FindFirstChildOfClass("ProximityPrompt")
                    if prompt and prompt.Parent and prompt.Parent:IsA("BasePart") then
                        hrp.CFrame = prompt.Parent.CFrame + Vector3_new(0, 2, 0)
                        task_wait(0.15)
                        if fireproximityprompt then
                            fireproximityprompt(prompt, 0, true)
                            fireproximityprompt(prompt, 0)
                            fireproximityprompt(prompt)
                        end
                    end
                end
            end)
        end

        -- Auto Lumber Farm
        if cfg.lumber_farm then
            pcall(function()
                local hrp = local_player.Character and local_player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local woodSell = workspace.Map.Newbury.Buildings.lumberJackShack:FindFirstChild("SellWoods")
                    local prompt = woodSell and woodSell:FindFirstChildOfClass("ProximityPrompt")
                    if prompt and prompt.Parent and prompt.Parent:IsA("BasePart") then
                        hrp.CFrame = prompt.Parent.CFrame + Vector3_new(0, 2, 0)
                        task_wait(0.15)
                        if fireproximityprompt then
                            fireproximityprompt(prompt, 0, true)
                            fireproximityprompt(prompt, 0)
                            fireproximityprompt(prompt)
                        end
                    end
                end
            end)
        end

        -- Auto Casino Spin
        if cfg.casino_auto_spin then
            pcall(function()
                local hrp = local_player.Character and local_player.Character:FindFirstChild("HumanoidRootPart")
                local gambling = workspace.Map.Newbury.Buildings.Gamblingplace.Machines
                for _, machine in ipairs(gambling:GetChildren()) do
                    if not cfg.casino_auto_spin or not ctx.running then break end
                    local btn = machine:FindFirstChild("Button")
                    local prompt = btn and btn:FindFirstChildOfClass("ProximityPrompt")
                    if prompt and prompt.Parent and prompt.Parent:IsA("BasePart") then
                        if hrp then hrp.CFrame = prompt.Parent.CFrame + Vector3_new(0, 2, 0) end
                        task_wait(0.15)
                        if fireproximityprompt then
                            fireproximityprompt(prompt, 0, true)
                            fireproximityprompt(prompt, 0)
                            fireproximityprompt(prompt)
                        end
                    end
                end
            end)
        end
    end
end)
