-- Profiler module (ported from Picotron's abledbody profiler v1.1)
-- Shows CPU % of 60fps frame budget, averaged over multiple frames

local function do_nothing() end

-- Metatable to make profile() callable
local profile_meta = {__call = do_nothing}
local profile = {draw = do_nothing}
setmetatable(profile, profile_meta)

local running = {}   -- Incomplete profiles (currently timing)
local profiles = {}  -- Complete profiles for current frame
local averages = {}  -- Rolling averages for each profile
local AVERAGE_FRAMES = 10  -- Number of frames to average over

-- High-resolution timer for profiling
local function get_time()
    return love.timer.getTime()
end

-- Start profiling a section
local function start_profile(name)
    running[name] = get_time()
end

-- Stop and record a profile
local function stop_profile(name, delta)
    local existing = profiles[name]
    if existing then
        existing.time = delta + existing.time
    else
        profiles[name] = {
            time = delta,
            name = name,
        }
        table.insert(profiles, profiles[name])
    end
end

-- Main profile function (called as profile("name") to start/stop)
local function _profile(_, name)
    local t = get_time()
    local start_time = running[name]
    if start_time then
        local delta = t - start_time
        stop_profile(name, delta)
        running[name] = nil
    else
        start_profile(name)
    end
end

-- Update rolling averages at end of frame
local function update_averages()
    for _, prof in ipairs(profiles) do
        local avg = averages[prof.name]
        if not avg then
            avg = {samples = {}, index = 1, sum = 0}
            averages[prof.name] = avg
        end

        -- Remove old sample from sum
        local old_sample = avg.samples[avg.index] or 0
        avg.sum = avg.sum - old_sample

        -- Add new sample
        avg.samples[avg.index] = prof.time
        avg.sum = avg.sum + prof.time

        -- Advance ring buffer index
        avg.index = (avg.index % AVERAGE_FRAMES) + 1
    end

    -- Clear profiles for next frame
    profiles = {}
end

-- Y offset for profiler display
local profiler_y_offset = 10

-- Draw CPU usage header
local function draw_cpu()
    local fps = love.timer.getFPS()
    local dt = love.timer.getAverageDelta()
    local cpu_percent = (dt / (1/60)) * 100

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.print(string.format("FPS:%d CPU:%.1f%%", fps, cpu_percent), 2, profiler_y_offset + 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format("FPS:%d CPU:%.1f%%", fps, cpu_percent), 1, profiler_y_offset)

    -- Reset color to white
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw detailed profile breakdown
local function display_profiles()
    update_averages()

    local y = profiler_y_offset + 12
    local frame_budget = 1/60

    -- Sort profiles by name for consistent display
    local sorted_names = {}
    for name, _ in pairs(averages) do
        table.insert(sorted_names, name)
    end
    table.sort(sorted_names)

    -- Calculate total and draw each profile's average
    local total_time = 0
    for _, name in ipairs(sorted_names) do
        local avg = averages[name]
        local sample_count = math.min(#avg.samples, AVERAGE_FRAMES)
        if sample_count > 0 then
            local avg_time = avg.sum / sample_count
            total_time = total_time + avg_time
            local cpu_percent = (avg_time / frame_budget) * 100
            local text = string.format("%s: %.1f%%", name, cpu_percent)

            -- Check if this is a sub-item (starts with space)
            local is_sub = name:sub(1, 1) == " "

            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.print(text, 2, y + 1)
            if is_sub then
                -- Dark blue for sub-items
                love.graphics.setColor(0.4, 0.6, 1.0, 1)
            else
                -- White for main items
                love.graphics.setColor(1, 1, 1, 1)
            end
            love.graphics.print(text, 1, y)
            y = y + 12
        end
    end

    -- Draw total
    local total_percent = (total_time / frame_budget) * 100
    local total_text = string.format("TOTAL: %.1f%%", total_percent)
    y = y + 4
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.print(total_text, 2, y + 1)
    love.graphics.setColor(1, 1, 0, 1)  -- Yellow for total
    love.graphics.print(total_text, 1, y)

    -- Draw renderer stats
    y = y + 16
    local renderer = require("renderer")
    local stats = renderer.getStats()

    -- Triangle and draw call counts
    local drawCalls = stats.drawCalls or 0
    local countText = string.format("Tris: %d  Draws: %d", stats.trianglesDrawn, drawCalls)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.print(countText, 2, y + 1)
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    love.graphics.print(countText, 1, y)

    -- Transform vs Rasterize timing breakdown
    y = y + 12
    local transformMs = stats.timeTransform * 1000
    local rasterMs = stats.timeRasterize * 1000
    local transformPct = (stats.timeTransform / frame_budget) * 100
    local rasterPct = (stats.timeRasterize / frame_budget) * 100
    local timeText = string.format("Xform: %.1f%% Raster: %.1f%%", transformPct, rasterPct)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.print(timeText, 2, y + 1)
    love.graphics.setColor(0.6, 0.8, 0.6, 1)  -- Light green
    love.graphics.print(timeText, 1, y)

    -- Reset color to white to prevent tinting other draws
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw both CPU and detailed profiles
local function display_both()
    draw_cpu()
    display_profiles()
end

-- Enable/disable profiling
function profile.enabled(detailed, cpu)
    profile_meta.__call = detailed and _profile or do_nothing
    profile.draw = detailed and (cpu and display_both or display_profiles)
        or (cpu and draw_cpu or do_nothing)
end

-- Toggle profiling on/off
local profiler_enabled = false
function profile.toggle()
    profiler_enabled = not profiler_enabled
    profile.enabled(profiler_enabled, profiler_enabled)
    -- Clear averages when toggling
    averages = {}
    return profiler_enabled
end

-- Check if profiler is enabled
function profile.is_enabled()
    return profiler_enabled
end

-- Reset all profiler data
function profile.reset()
    running = {}
    profiles = {}
    averages = {}
end

-- Get profiler data as clipboard-friendly text
function profile.getClipboardData()
    local lines = {}
    local fps = love.timer.getFPS()
    local dt = love.timer.getAverageDelta()
    local cpu_percent = (dt / (1/60)) * 100
    local frame_budget = 1/60

    table.insert(lines, string.format("=== Tom Lander Profiler ==="))
    table.insert(lines, string.format("FPS: %d  CPU: %.1f%%", fps, cpu_percent))
    table.insert(lines, "")

    -- Sort profiles by name
    local sorted_names = {}
    for name, _ in pairs(averages) do
        table.insert(sorted_names, name)
    end
    table.sort(sorted_names)

    -- Profile breakdown
    local total_time = 0
    for _, name in ipairs(sorted_names) do
        local avg = averages[name]
        local sample_count = math.min(#avg.samples, AVERAGE_FRAMES)
        if sample_count > 0 then
            local avg_time = avg.sum / sample_count
            total_time = total_time + avg_time
            local pct = (avg_time / frame_budget) * 100
            table.insert(lines, string.format("%-20s %.1f%% (%.2fms)", name, pct, avg_time * 1000))
        end
    end

    table.insert(lines, "")
    local total_pct = (total_time / frame_budget) * 100
    table.insert(lines, string.format("TOTAL: %.1f%% (%.2fms)", total_pct, total_time * 1000))

    -- Renderer stats
    local renderer = require("renderer")
    local stats = renderer.getStats()
    table.insert(lines, "")
    local drawCalls = stats.drawCalls or 0
    table.insert(lines, string.format("Triangles: %d  Draw calls: %d", stats.trianglesDrawn, drawCalls))
    local config = require("config")
    if config.USE_GPU_RENDERER then
        -- GPU renderer: timeRasterize = GPU submit overhead (not actual rasterization)
        local submitPct = (stats.timeRasterize / frame_budget) * 100
        table.insert(lines, string.format("GPU Submit: %.1f%% (CPU overhead)", submitPct))
    else
        -- Software renderer: actual CPU transform and rasterize time
        local transformPct = (stats.timeTransform / frame_budget) * 100
        local rasterPct = (stats.timeRasterize / frame_budget) * 100
        table.insert(lines, string.format("Transform: %.1f%%  Rasterize: %.1f%%", transformPct, rasterPct))
    end

    return table.concat(lines, "\n")
end

return profile
