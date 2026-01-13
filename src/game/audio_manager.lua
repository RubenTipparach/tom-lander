-- Audio Manager Module for Love2D
-- Centralized system for managing music and sound effects
-- Ported from Picotron version

local AudioManager = {}

-- Sound effect definitions (mapped from Picotron sfx IDs)
-- Picotron: sfx(0) = shoot, sfx(1) = thruster, sfx(3) = explosion, sfx(8) = collide
AudioManager.sfx_files = {
    [0] = { name = "shoot", file = "assets/sounds/shoot.wav", source = nil },
    [1] = { name = "thruster", file = "assets/sounds/thruster.wav", source = nil, looping = true },
    [3] = { name = "explosion", file = "assets/sounds/explosion.wav", source = nil },
    [8] = { name = "collide", file = "assets/sounds/collide.wav", source = nil },
}

-- Music definitions
AudioManager.music_files = {
    menu = { file = "assets/sounds/menu_music.wav", source = nil },
    -- More tracks coming soon:
    -- level1 = { file = "assets/sounds/level1_music.wav", source = nil },
    -- level2 = { file = "assets/sounds/level2_music.wav", source = nil },
}

-- Audio state
AudioManager.current_music = nil
AudioManager.music_volume = 0.5
AudioManager.sfx_volume = 0.7
AudioManager.initialized = false

-- Thruster state (for continuous looping sound)
AudioManager.thruster_playing = false
AudioManager.thruster_source = nil

-- Initialize audio system - load all sound files
function AudioManager.init()
    if AudioManager.initialized then return end

    print("[Audio] Initializing audio system...")

    -- Load sound effects
    for id, sfx in pairs(AudioManager.sfx_files) do
        local success, result = pcall(function()
            return love.audio.newSource(sfx.file, "static")
        end)

        if success and result then
            sfx.source = result
            sfx.source:setVolume(AudioManager.sfx_volume)
            if sfx.looping then
                sfx.source:setLooping(true)
            end
            print("[Audio] Loaded SFX: " .. sfx.name .. " (id " .. id .. ")")
        else
            print("[Audio] Failed to load SFX: " .. sfx.file)
        end
    end

    -- Load music tracks
    for name, music in pairs(AudioManager.music_files) do
        local success, result = pcall(function()
            return love.audio.newSource(music.file, "stream")
        end)

        if success and result then
            music.source = result
            music.source:setVolume(AudioManager.music_volume)
            music.source:setLooping(true)
            print("[Audio] Loaded music: " .. name)
        else
            print("[Audio] Failed to load music: " .. music.file)
        end
    end

    AudioManager.initialized = true
    print("[Audio] Audio system initialized")
end

-- Play a sound effect by ID (matching Picotron sfx IDs)
function AudioManager.play_sfx(sfx_id, volume)
    local sfx = AudioManager.sfx_files[sfx_id]
    if not sfx or not sfx.source then
        return
    end

    -- For non-looping sounds, clone the source so multiple can play
    if not sfx.looping then
        local clone = sfx.source:clone()
        clone:setVolume(volume or AudioManager.sfx_volume)
        clone:play()
    else
        -- For looping sounds (thruster), just play the original
        sfx.source:setVolume(volume or AudioManager.sfx_volume)
        if not sfx.source:isPlaying() then
            sfx.source:play()
        end
    end
end

-- Stop a sound effect by ID
function AudioManager.stop_sfx(sfx_id)
    local sfx = AudioManager.sfx_files[sfx_id]
    if sfx and sfx.source then
        sfx.source:stop()
    end
end

-- Start thruster sound (looping)
function AudioManager.start_thruster()
    if not AudioManager.thruster_playing then
        AudioManager.play_sfx(1)  -- sfx ID 1 = thruster
        AudioManager.thruster_playing = true
    end
end

-- Stop thruster sound
function AudioManager.stop_thruster()
    if AudioManager.thruster_playing then
        AudioManager.stop_sfx(1)
        AudioManager.thruster_playing = false
    end
end

-- Set thruster volume based on thrust intensity (0-1)
function AudioManager.set_thruster_volume(intensity)
    local sfx = AudioManager.sfx_files[1]
    if sfx and sfx.source then
        local vol = math.max(0, math.min(1, intensity)) * AudioManager.sfx_volume
        sfx.source:setVolume(vol)
    end
end

-- Play music by name
function AudioManager.play_music(music_name, volume)
    local music = AudioManager.music_files[music_name]
    if not music or not music.source then
        print("[Audio] Music not found: " .. tostring(music_name))
        return
    end

    -- Stop current music if different
    if AudioManager.current_music and AudioManager.current_music ~= music_name then
        AudioManager.stop_music()
    end

    -- Set volume and play
    music.source:setVolume(volume or AudioManager.music_volume)
    if not music.source:isPlaying() then
        music.source:play()
    end

    AudioManager.current_music = music_name
    print("[Audio] Playing music: " .. music_name)
end

-- Stop current music
function AudioManager.stop_music()
    if AudioManager.current_music then
        local music = AudioManager.music_files[AudioManager.current_music]
        if music and music.source then
            music.source:stop()
        end
        AudioManager.current_music = nil
    end
end

-- Pause current music
function AudioManager.pause_music()
    if AudioManager.current_music then
        local music = AudioManager.music_files[AudioManager.current_music]
        if music and music.source then
            music.source:pause()
        end
    end
end

-- Resume current music
function AudioManager.resume_music()
    if AudioManager.current_music then
        local music = AudioManager.music_files[AudioManager.current_music]
        if music and music.source then
            music.source:play()
        end
    end
end

-- High-level functions for different game states

function AudioManager.start_menu_music()
    AudioManager.play_music("menu", AudioManager.music_volume)
end

-- Mission to music mapping (matching Picotron audio_manager)
AudioManager.mission_music = {
    [1] = "level1",      -- Mission 1-2: level1 music
    [2] = "level1",
    [3] = "tom_lander",  -- Mission 3: tom_lander
    [4] = "level2",      -- Mission 4: level2
    [5] = "hyperlevel",  -- Mission 5: hyperlevel (weather)
    [6] = "lastday",     -- Mission 6+: lastday (combat)
    [7] = "menu",        -- Racing mode: menu music for now
}

function AudioManager.start_level_music(mission_num)
    -- Stop current music first
    AudioManager.stop_music()

    -- Get music for this mission (default to menu if not mapped)
    local music_name = AudioManager.mission_music[mission_num] or "menu"

    -- For missions 6+, use lastday (combat music)
    if mission_num and mission_num >= 6 and not AudioManager.mission_music[mission_num] then
        music_name = "lastday"
    end

    -- Check if the music track exists, fall back to menu if not
    if not AudioManager.music_files[music_name] or not AudioManager.music_files[music_name].source then
        print("[Audio] Track '" .. music_name .. "' not available, using menu music")
        music_name = "menu"
    end

    -- Play at lower volume during gameplay
    AudioManager.play_music(music_name, AudioManager.music_volume * 0.5)
end

-- Stop all audio
function AudioManager.stop_all()
    AudioManager.stop_music()
    AudioManager.stop_thruster()

    -- Stop all SFX
    for _, sfx in pairs(AudioManager.sfx_files) do
        if sfx.source then
            sfx.source:stop()
        end
    end
end

-- Set master SFX volume (0-1)
function AudioManager.set_sfx_volume(volume)
    AudioManager.sfx_volume = math.max(0, math.min(1, volume))
end

-- Set master music volume (0-1)
function AudioManager.set_music_volume(volume)
    AudioManager.music_volume = math.max(0, math.min(1, volume))

    -- Update current music volume if playing
    if AudioManager.current_music then
        local music = AudioManager.music_files[AudioManager.current_music]
        if music and music.source then
            music.source:setVolume(AudioManager.music_volume)
        end
    end
end

return AudioManager
