-- Mission Scripts
-- Defines all mission scenarios
-- Ported from Picotron version

local LandingPads = require("landing_pads")
local Constants = require("constants")
local Weather = require("weather")

local Missions = {}

-- Reference to buildings (set externally from flight_scene.lua)
Missions.buildings = nil
Missions.building_configs = nil

-- Reference to Weather module (for mission-specific weather)
Missions.Weather = Weather

-- Mission definitions for menu display
Missions.MISSION_LIST = {
    {id = 1, name = "Engine Test", description = "Take off, hover, and land"},
    {id = 2, name = "Cargo Basics", description = "Pick up nearby cargo"},
    {id = 3, name = "Cargo Delivery", description = "Pick up and deliver cargo"},
    {id = 4, name = "Scientific Mission", description = "Rooftop pickup to crater"},
    {id = 5, name = "Ocean Rescue", description = "Rescue cargo from the ocean"},
    {id = 6, name = "Secret Weapon", description = "Retrieve classified cargo"},
    {id = 7, name = "Alien Invasion", description = "Defend against aliens"},
}

-- Mission 1: Engine Test
-- Simple tutorial - take off, hover for duration, and land back on the pad
function Missions.start_mission_1(Mission)
    local target_pad = LandingPads.get_pad(1)
    local pad_x = target_pad and target_pad.x or 0
    local pad_z = target_pad and target_pad.z or 0
    Mission.start_hover_mission(Mission.M1_HOVER_DURATION, pad_x, pad_z, 1)
    Mission.mission_name = "Engine Test"
    Mission.current_mission_num = 1
end

-- Mission 2: Cargo Basics (Tutorial)
-- Simple tutorial - pick up nearby cargo and deliver to landing pad
function Missions.start_mission_2(Mission)
    local target_pad = LandingPads.get_pad(1)
    local pad_x = target_pad and target_pad.x or 0
    local pad_z = target_pad and target_pad.z or 0

    -- Cargo very close to landing pad for easy tutorial
    local cargo_world_x = pad_x + Mission.M2_CARGO_DISTANCE_X
    local cargo_world_z = pad_z + Mission.M2_CARGO_DISTANCE_Z
    local cargo_aseprite_x, cargo_aseprite_z = Constants.world_to_aseprite(cargo_world_x, cargo_world_z)

    local cargo_list = {
        {aseprite_x = cargo_aseprite_x, aseprite_z = cargo_aseprite_z}
    }

    Mission.start_cargo_mission(cargo_list, pad_x, pad_z, 1)
    Mission.mission_name = "Cargo Basics"
    Mission.current_objectives[1] = "Pick up nearby cargo container"
    Mission.current_objectives[3] = "Deliver to Landing Pad A"
    Mission.current_mission_num = 2
end

-- Mission 3: Cargo Delivery
-- Pick up cargo at longer distance and deliver to landing pad
function Missions.start_mission_3(Mission)
    local target_pad = LandingPads.get_pad(1)
    local pad_x = target_pad and target_pad.x or 0
    local pad_z = target_pad and target_pad.z or 0

    -- Create cargo boxes (farther away than M2 tutorial)
    local cargo_list = {}
    for i = 1, Mission.M3_CARGO_COUNT do
        local cargo_world_x = pad_x + Mission.M3_CARGO_DISTANCE_X
        local cargo_world_z = pad_z + Mission.M3_CARGO_DISTANCE_Z
        local cargo_aseprite_x, cargo_aseprite_z = Constants.world_to_aseprite(cargo_world_x, cargo_world_z)
        table.insert(cargo_list, {aseprite_x = cargo_aseprite_x, aseprite_z = cargo_aseprite_z})
    end

    Mission.start_cargo_mission(cargo_list, pad_x, pad_z, 1)
    Mission.mission_name = "Cargo Delivery"
    Mission.current_mission_num = 3
end

-- Mission 4: Scientific Mission
-- Pick up scientists from Command Tower rooftop and deliver to Landing Pad D
function Missions.start_mission_4(Mission)
    local target_pad = LandingPads.get_pad(Mission.M4_LANDING_PAD_ID)
    local pad_x = target_pad and target_pad.x or 0
    local pad_z = target_pad and target_pad.z or 0

    -- Get Command Tower building position
    local building_config = Missions.building_configs and Missions.building_configs[Mission.M4_BUILDING_ID]
    local building = Missions.buildings and Missions.buildings[Mission.M4_BUILDING_ID]

    if not building_config or not building then
        -- Fallback position
        building_config = {x = 2, z = 20, height = 7}
        building = {x = 2, y = 0, z = 20}
    end

    -- Cargo on rooftop
    local rooftop_height = building.y + (building_config.height * 2)
    local cargo_world_x = building_config.x
    local cargo_world_z = building_config.z

    local cargo_list = {}
    for i = 1, Mission.M4_CARGO_COUNT do
        local cargo_aseprite_x, cargo_aseprite_z = Constants.world_to_aseprite(cargo_world_x, cargo_world_z)
        table.insert(cargo_list, {
            aseprite_x = cargo_aseprite_x,
            aseprite_z = cargo_aseprite_z,
            world_y = rooftop_height
        })
    end

    Mission.start_cargo_mission(cargo_list, pad_x, pad_z, Mission.M4_LANDING_PAD_ID)
    Mission.mission_name = "Scientific Mission"
    Mission.current_objectives[1] = "Pick up scientists from Command Tower"
    Mission.current_objectives[3] = "Deliver to Landing Pad D"
    Mission.current_mission_num = 4
end

-- Mission 5: Ocean Rescue
-- Pick up cargo from the ocean and deliver to Landing Pad B
function Missions.start_mission_5(Mission)
    local target_pad = LandingPads.get_pad(Mission.M5_LANDING_PAD_ID)
    local pad_x = target_pad and target_pad.x or 0
    local pad_z = target_pad and target_pad.z or 0

    local cargo_list = {}
    for i = 1, Mission.M5_CARGO_COUNT do
        table.insert(cargo_list, {
            aseprite_x = Mission.M5_CARGO_ASEPRITE_X,
            aseprite_z = Mission.M5_CARGO_ASEPRITE_Z,
            world_y = 0  -- Float at sea level
        })
    end

    Mission.start_cargo_mission(cargo_list, pad_x, pad_z, Mission.M5_LANDING_PAD_ID)
    Mission.mission_name = "Ocean Rescue"
    Mission.current_objectives[1] = "Rescue cargo from the ocean"
    Mission.current_objectives[3] = "Deliver to Landing Pad B"
    Mission.current_mission_num = 5
end

-- Mission 6: Secret Weapon
-- Pick up secret cargo and deliver to Landing Pad C
function Missions.start_mission_6(Mission)
    local target_pad = LandingPads.get_pad(Mission.M6_LANDING_PAD_ID)
    local pad_x = target_pad and target_pad.x or 0
    local pad_z = target_pad and target_pad.z or 0

    local cargo_list = {}
    for i = 1, Mission.M6_CARGO_COUNT do
        table.insert(cargo_list, {
            aseprite_x = Mission.M6_CARGO_ASEPRITE_X,
            aseprite_z = Mission.M6_CARGO_ASEPRITE_Z
        })
    end

    Mission.start_cargo_mission(cargo_list, pad_x, pad_z, Mission.M6_LANDING_PAD_ID)
    Mission.mission_name = "Secret Weapon"
    Mission.current_objectives[1] = "Retrieve classified cargo"
    Mission.current_objectives[3] = "Deliver to Landing Pad C"
    Mission.current_mission_num = 6

    -- Enable weather for this mission
    Weather.set_enabled(true)
    Weather.init()
end

-- Mission 7: Alien Invasion
-- Combat mission - defend against alien waves
function Missions.start_mission_7(Mission)
    Mission.mission_name = "Alien Invasion"
    Mission.active = true
    Mission.complete_flag = false
    Mission.current_objectives = {
        "Destroy all alien waves",
        "",
        ""
    }
    Mission.current_mission_num = 7
    -- Start countdown
    Mission.countdown = {
        active = true,
        timer = Mission.COUNTDOWN_DURATION,
    }

    -- Set landing pad for reference
    local target_pad = LandingPads.get_pad(1)
    if target_pad then
        Mission.landing_pad_pos = {x = target_pad.x, y = 0, z = target_pad.z}
        Mission.current_target = {x = target_pad.x, z = target_pad.z}
    end
end

-- Racing: Time Trial Track
-- Race through checkpoints around the map, 3 laps
-- Track 1: Island Circuit (day), Track 2: Canyon Run (day)
-- Track 3: Island Night, Track 4: Canyon Night
function Missions.start_race_track(track_num, Mission)
    Mission.mission_name = "Time Trial"
    Mission.active = true
    Mission.complete_flag = false
    Mission.type = "race"
    Mission.current_mission_num = nil  -- Racing is not a campaign mission

    -- Determine if this is a night track
    -- Tracks 3 and 4 are night versions of tracks 1 and 2
    local is_night = (track_num == 3 or track_num == 4)
    local base_track = track_num
    if track_num == 3 then base_track = 1 end  -- Island Night uses Island checkpoints
    if track_num == 4 then base_track = 2 end  -- Canyon Night uses Canyon checkpoints

    -- Store night mode flag for flight_scene to use
    Mission.night_mode = is_night

    -- Define checkpoints in ASEPRITE coordinates (easier to visualize on map)
    -- y = height above ground for checkpoint ring center
    -- Coordinates are converted to world coords below
    local checkpoints_aseprite

    if base_track == 2 then
        -- Track 2/4: Canyon Run (act2 map - 128x256 tiles)
        -- Aseprite origin (0,0) = top-left, map center = (64, 128)
        -- Spawn is at aseprite (41, 264)
        -- Note: altitude limit is 30 world units (300m displayed), keep checkpoints low
        checkpoints_aseprite = {
            {x = 41, z = 243, y = 12, time = 25, name = "Canyon Entrance"},
            {x = 67, z = 210, y = 12, time = 30, name = "East Ridge"},
            {x = 96, z = 202, y = 13, time = 30, name = "High Pass"},
            {x = 83, z = 173, y = 13, time = 30, name = "Summit"},
            {x = 46, z = 176, y = 12, time = 25, name = "West Descent"},
            {x = 77, z = 144, y = 12, time = 30, name = "Valley Floor"},
            {x = 93, z = 123, y = 11, time = 25, name = "Back Canyon"},
            {x = 68, z = 135, y = 12, time = 30, name = "Return 1"},
            {x = 33, z = 161, y = 12, time = 30, name = "Return 2"},
            {x = 72, z = 179, y = 12, time = 30, name = "Return 3"},
            {x = 121, z = 208, y = 13, time = 30, name = "Return 4"},
            {x = 68, z = 223, y = 12, time = 30, name = "Return 5"},
        }
        Mission.mission_name = is_night and "Canyon Night" or "Canyon Run"
    else
        -- Track 1/3: Island Circuit (act1 map - 128x128 tiles)
        -- Aseprite origin (0,0) = top-left, map center = (64, 64)
        checkpoints_aseprite = {
            {x = 44, z = 49, y = 10, time = 25, name = "Fuel Depot"},        -- Southwest
            {x = 34, z = 74, y = 8, time = 30, name = "Research Station"},   -- Northwest
            {x = 54, z = 94, y = 14, time = 35, name = "Mining Platform"},   -- North
            {x = 87, z = 89, y = 8, time = 25, name = "Relay Tower"},        -- Northeast
            {x = 99, z = 64, y = 5, time = 30, name = "Cargo Bay"},          -- East
            {x = 94, z = 39, y = 12, time = 25, name = "Power Station"},     -- Southeast
            {x = 64, z = 44, y = 6, time = 30, name = "Final Stretch"},      -- South
        }
        Mission.mission_name = is_night and "Island Night" or "Island Circuit"
    end

    -- Convert aseprite coordinates to world coordinates
    Mission.race_checkpoints = {}
    for _, cp in ipairs(checkpoints_aseprite) do
        local world_x, world_z = Constants.aseprite_to_world(cp.x, cp.z)
        table.insert(Mission.race_checkpoints, {
            x = world_x,
            z = world_z,
            y = cp.y,
            time = cp.time,
            name = cp.name
        })
    end

    -- Race state
    Mission.race = {
        current_checkpoint = 1,
        current_lap = 1,
        total_laps = 3,
        checkpoint_timer = Mission.race_checkpoints[1].time,
        total_time = 0,
        checkpoint_radius = 6,   -- Tighter detection radius (horizontal)
        checkpoint_height = 4,   -- Vertical detection range (+/- from ring center)
        checkpoint_flash = 0,    -- Visual feedback timer
        failed = false,
        -- Countdown state (3-2-1-GO!)
        countdown_timer = 4.0,   -- 4 seconds: 3, 2, 1, GO!
        countdown_active = true, -- Controls disabled until countdown finishes
    }

    -- Set first checkpoint as target
    local first_cp = Mission.race_checkpoints[1]
    Mission.current_target = {x = first_cp.x, z = first_cp.z}

    Mission.current_objectives = {
        "GET READY!",
        "",
        "Race starts in 3..."
    }
end

-- Start a mission by number
function Missions.start(mission_num, Mission)
    Mission.reset()

    -- Disable weather by default (Mission 6 Secret Weapon will re-enable it)
    Weather.set_enabled(false)

    if mission_num == 1 then
        Missions.start_mission_1(Mission)
    elseif mission_num == 2 then
        Missions.start_mission_2(Mission)
    elseif mission_num == 3 then
        Missions.start_mission_3(Mission)
    elseif mission_num == 4 then
        Missions.start_mission_4(Mission)
    elseif mission_num == 5 then
        Missions.start_mission_5(Mission)
    elseif mission_num == 6 then
        Missions.start_mission_6(Mission)
    elseif mission_num == 7 then
        Missions.start_mission_7(Mission)
    end
end

-- Get mission count
function Missions.get_count()
    return #Missions.MISSION_LIST
end

-- Get mission info by number
function Missions.get_info(mission_num)
    return Missions.MISSION_LIST[mission_num]
end

return Missions
