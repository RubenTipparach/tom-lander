-- Save Data Module: Persistent storage for game progress
-- Uses Love2D's filesystem to save/load JSON data

local json = require("json")  -- Simple JSON library in src/lib/

local SaveData = {}

-- File path for save data (in Love2D's save directory)
local SAVE_FILE = "mission_progress.json"

-- Default progress state
local default_progress = {
    story_played = false,
    mission_1 = true,   -- Always unlocked
    mission_2 = false,
    mission_3 = false,
    mission_4 = false,
    mission_5 = false,
    mission_6 = false
}

-- Current mission progress (loaded on init)
SaveData.mission_progress = nil

-- Initialize save data system
function SaveData.init()
    SaveData.mission_progress = SaveData.load()
end

-- Load mission progress from file
function SaveData.load()
    local progress = {}

    -- Copy defaults first
    for k, v in pairs(default_progress) do
        progress[k] = v
    end

    -- Try to load from file
    if love.filesystem.getInfo(SAVE_FILE) then
        local contents, err = love.filesystem.read(SAVE_FILE)
        if contents then
            local success, data = pcall(json.decode, contents)
            if success and data then
                -- Merge loaded data with defaults (in case new fields were added)
                for k, v in pairs(data) do
                    progress[k] = v
                end
                -- Mission 1 is always unlocked
                progress.mission_1 = true
                print("SaveData: Loaded mission progress from " .. SAVE_FILE)
            else
                print("SaveData: Failed to parse save file, using defaults")
            end
        else
            print("SaveData: Failed to read save file: " .. tostring(err))
        end
    else
        print("SaveData: No save file found, using defaults")
    end

    return progress
end

-- Save mission progress to file
function SaveData.save()
    if not SaveData.mission_progress then
        print("SaveData: No progress to save")
        return false
    end

    local success, encoded = pcall(json.encode, SaveData.mission_progress)
    if not success then
        print("SaveData: Failed to encode progress: " .. tostring(encoded))
        return false
    end

    local ok, err = love.filesystem.write(SAVE_FILE, encoded)
    if ok then
        print("SaveData: Saved mission progress to " .. SAVE_FILE)
        return true
    else
        print("SaveData: Failed to write save file: " .. tostring(err))
        return false
    end
end

-- Unlock a specific mission
function SaveData.unlock_mission(mission_num)
    if not SaveData.mission_progress then
        SaveData.init()
    end

    local key = "mission_" .. mission_num
    if SaveData.mission_progress[key] ~= nil then
        SaveData.mission_progress[key] = true
        SaveData.save()
        print("SaveData: Unlocked mission " .. mission_num)
        return true
    end
    return false
end

-- Check if a mission is unlocked
function SaveData.is_mission_unlocked(mission_num)
    if not SaveData.mission_progress then
        SaveData.init()
    end

    local key = "mission_" .. mission_num
    return SaveData.mission_progress[key] == true
end

-- Mark story as played
function SaveData.mark_story_played()
    if not SaveData.mission_progress then
        SaveData.init()
    end

    SaveData.mission_progress.story_played = true
    SaveData.save()
end

-- Check if story has been played
function SaveData.is_story_played()
    if not SaveData.mission_progress then
        SaveData.init()
    end

    return SaveData.mission_progress.story_played == true
end

-- Reset all progress to defaults
function SaveData.reset()
    SaveData.mission_progress = {}
    for k, v in pairs(default_progress) do
        SaveData.mission_progress[k] = v
    end
    SaveData.save()
    print("SaveData: Progress reset to defaults")
end

-- Get the full progress table (for menu display)
function SaveData.get_progress()
    if not SaveData.mission_progress then
        SaveData.init()
    end
    return SaveData.mission_progress
end

return SaveData
