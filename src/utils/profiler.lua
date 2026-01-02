-- Simple profiler for performance analysis

local profiler = {}

-- Storage for timing data
local timers = {}
local results = {}
local frameStart = 0
local totalFrameTime = 0
local frameAccumulators = {}  -- Accumulate time for substeps called multiple times per frame

-- Start timing a section
function profiler.start(name)
    timers[name] = love.timer.getTime()
end

-- Stop timing a section
function profiler.stop(name)
    if not timers[name] then
        print("Warning: profiler.stop('" .. name .. "') called without start")
        return
    end

    local elapsed = (love.timer.getTime() - timers[name]) * 1000 -- Convert to ms

    -- Accumulate time for this frame (for substeps called multiple times)
    if not frameAccumulators[name] then
        frameAccumulators[name] = 0
    end
    frameAccumulators[name] = frameAccumulators[name] + elapsed

    timers[name] = nil
end

-- Start frame timing
function profiler.startFrame()
    frameStart = love.timer.getTime()
    -- Reset accumulators for new frame
    frameAccumulators = {}
end

-- End frame timing
function profiler.endFrame()
    totalFrameTime = (love.timer.getTime() - frameStart) * 1000

    -- Move accumulated times to results for this frame
    for name, accumulated in pairs(frameAccumulators) do
        if not results[name] then
            results[name] = {
                time = 0,
                samples = {}
            }
        end

        results[name].time = accumulated

        -- Keep rolling average (last 60 samples)
        table.insert(results[name].samples, accumulated)
        if #results[name].samples > 60 then
            table.remove(results[name].samples, 1)
        end
    end
end

-- Get average time for a section
local function getAverage(name)
    if not results[name] then
        return 0
    end

    local samples = results[name].samples
    if #samples == 0 then
        return 0
    end

    local sum = 0
    for _, v in ipairs(samples) do
        sum = sum + v
    end

    return sum / #samples
end

-- Draw profiler info at a Y position, returns new Y position
function profiler.draw(name, x, y, color)
    x = x or 10
    y = y or 10
    color = color or {1, 1, 1}  -- Default white

    local TARGET_FRAME_TIME = 1000 / 60  -- 16.67ms for 60 FPS

    -- Save current color
    local r, g, b, a = love.graphics.getColor()
    love.graphics.setColor(color[1], color[2], color[3], 1)

    if name == "total" then
        -- Draw total frame time
        local fps = love.timer.getFPS()
        local percent = (totalFrameTime / TARGET_FRAME_TIME * 100)
        love.graphics.print(string.format("Frame: %.2fms (%.0f FPS) %.1f%%", totalFrameTime, fps, percent), x, y)
        love.graphics.setColor(r, g, b, a)
        return y + 20
    else
        -- Draw specific section
        if not results[name] then
            love.graphics.print(name .. ": No data", x, y)
            love.graphics.setColor(r, g, b, a)
            return y + 20
        end

        local avg = getAverage(name)
        local percent = (avg / TARGET_FRAME_TIME * 100)

        love.graphics.print(string.format("%s: %.2fms (%.1f%%)", name, avg, percent), x, y)
        love.graphics.setColor(r, g, b, a)
        return y + 20
    end
end

-- Draw all profiler results
function profiler.drawAll(x, y)
    x = x or 10
    y = y or 10

    -- Draw individual sections
    local sections = {}
    for name, _ in pairs(results) do
        table.insert(sections, name)
    end
    table.sort(sections)

    for _, name in ipairs(sections) do
        y = profiler.draw(name, x, y)
    end

    -- Draw total at the end
    y = y + 5
    y = profiler.draw("total", x, y)

    return y
end

-- Reset all profiler data
function profiler.reset()
    timers = {}
    results = {}
    totalFrameTime = 0
end

return profiler
