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
        "",
        "[TAB] Menu  [C] Show Controls"
    }
    Mission.current_mission_num = 7

    -- Set landing pad for reference
    local target_pad = LandingPads.get_pad(1)
    if target_pad then
        Mission.landing_pad_pos = {x = target_pad.x, y = 0, z = target_pad.z}
        Mission.current_target = {x = target_pad.x, z = target_pad.z}
    end
end

-- Racing: Time Trial Track
-- Race through checkpoints around the map, 3 laps
function Missions.start_race_track(track_num, Mission)
    Mission.mission_name = "Time Trial"
    Mission.active = true
    Mission.complete_flag = false
    Mission.type = "race"
    Mission.current_mission_num = nil  -- Racing is not a campaign mission

    -- Define checkpoints (world coordinates)
    -- Map is 128x128 tiles at 4 units per tile = 512x512 world units centered at 0,0
    -- So valid coords are roughly -256 to +256
    Mission.race_checkpoints = {
        {x = 0, z = 0, time = 30, name = "Start/Finish"},           -- Landing Pad A (center)
        {x = -80, z = -60, time = 25, name = "Fuel Depot"},         -- Southwest
        {x = -120, z = 40, time = 30, name = "Research Station"},   -- Northwest
        {x = -40, z = 120, time = 35, name = "Mining Platform"},    -- North
        {x = 80, z = 100, time = 25, name = "Relay Tower"},         -- Northeast
        {x = 140, z = 0, time = 30, name = "Cargo Bay"},            -- East
        {x = 80, z = -100, time = 25, name = "Power Station"},      -- Southeast
        {x = 0, z = -80, time = 30, name = "Final Stretch"},        -- South, back to start
    }

    -- Race state
    Mission.race = {
        current_checkpoint = 1,
        current_lap = 1,
        total_laps = 3,
        checkpoint_timer = Mission.race_checkpoints[1].time,
        total_time = 0,
        checkpoint_radius = 12,  -- Detection radius
        checkpoint_flash = 0,    -- Visual feedback timer
        failed = false,
    }

    -- Set first checkpoint as target
    local first_cp = Mission.race_checkpoints[1]
    Mission.current_target = {x = first_cp.x, z = first_cp.z}

    Mission.current_objectives = {
        "LAP 1/3 - Checkpoint 1/" .. #Mission.race_checkpoints,
        "Time: " .. Mission.race.checkpoint_timer .. "s",
        "Fly through the checkpoints!",
        "[TAB] Menu  [C] Show Controls"
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
