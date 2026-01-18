-- Controls Module
-- Abstracts input handling between keyboard and gamepad
-- Automatically switches based on last input device used

local controls_config = require("input.controls_config")

local controls = {}

-- ===========================================
-- STATE
-- ===========================================

-- Current input mode: "keyboard" or "gamepad"
local input_mode = "keyboard"

-- Active gamepad (if any)
local active_gamepad = nil

-- Track last input time for each device type
local last_keyboard_input = 0
local last_gamepad_input = 0

-- Debounce for discrete button presses (prevents rapid repeat)
local button_cooldowns = {}
local BUTTON_COOLDOWN = 0.2  -- seconds

-- ===========================================
-- INITIALIZATION
-- ===========================================

function controls.init()
    -- Check for connected gamepads
    local joysticks = love.joystick.getJoysticks()
    for _, joystick in ipairs(joysticks) do
        if joystick:isGamepad() then
            active_gamepad = joystick
            print("[CONTROLS] Gamepad detected: " .. joystick:getName())
            break
        end
    end

    if not active_gamepad then
        print("[CONTROLS] No gamepad detected, using keyboard")
    end
end

-- ===========================================
-- INPUT MODE MANAGEMENT
-- ===========================================

-- Get current input mode
function controls.get_mode()
    return input_mode
end

-- Check if using keyboard
function controls.is_keyboard()
    return input_mode == "keyboard"
end

-- Check if using gamepad
function controls.is_gamepad()
    return input_mode == "gamepad"
end

-- Force input mode (for testing/debugging)
function controls.set_mode(mode)
    if mode == "keyboard" or mode == "gamepad" then
        input_mode = mode
        print("[CONTROLS] Input mode set to: " .. mode)
    end
end

-- Update input mode based on recent input
local function update_input_mode()
    if last_gamepad_input > last_keyboard_input then
        if input_mode ~= "gamepad" then
            input_mode = "gamepad"
            -- print("[CONTROLS] Switched to gamepad")
        end
    else
        if input_mode ~= "keyboard" then
            input_mode = "keyboard"
            -- print("[CONTROLS] Switched to keyboard")
        end
    end
end

-- ===========================================
-- GAMEPAD CALLBACKS
-- ===========================================

function controls.gamepadpressed(joystick, button)
    if joystick:isGamepad() then
        active_gamepad = joystick
        last_gamepad_input = love.timer.getTime()
        update_input_mode()
    end
end

function controls.gamepadreleased(joystick, button)
    -- Nothing special needed
end

function controls.gamepadaxis(joystick, axis, value)
    if joystick:isGamepad() and math.abs(value) > 0.2 then
        active_gamepad = joystick
        last_gamepad_input = love.timer.getTime()
        update_input_mode()
    end
end

function controls.joystickadded(joystick)
    if joystick:isGamepad() and not active_gamepad then
        active_gamepad = joystick
        print("[CONTROLS] Gamepad connected: " .. joystick:getName())
    end
end

function controls.joystickremoved(joystick)
    if joystick == active_gamepad then
        active_gamepad = nil
        input_mode = "keyboard"
        print("[CONTROLS] Gamepad disconnected, switching to keyboard")

        -- Check for other gamepads
        local joysticks = love.joystick.getJoysticks()
        for _, j in ipairs(joysticks) do
            if j:isGamepad() then
                active_gamepad = j
                print("[CONTROLS] Found another gamepad: " .. j:getName())
                break
            end
        end
    end
end

-- ===========================================
-- KEYBOARD TRACKING
-- ===========================================

function controls.keypressed(key)
    last_keyboard_input = love.timer.getTime()
    update_input_mode()
end

function controls.keyreleased(key)
    -- Nothing special needed
end

-- ===========================================
-- INPUT CHECKING
-- ===========================================

-- Check if any key in a list is down
local function any_key_down(keys)
    if not keys then return false end
    for _, key in ipairs(keys) do
        if love.keyboard.isDown(key) then
            return true
        end
    end
    return false
end

-- Check if any gamepad button in a list is down
local function any_gamepad_button_down(buttons)
    if not buttons or not active_gamepad then return false end
    for _, button in ipairs(buttons) do
        if active_gamepad:isGamepadDown(button) then
            return true
        end
    end
    return false
end

-- Check gamepad axis against threshold
local function check_gamepad_axis(axis_config)
    if not axis_config or not active_gamepad then return false end

    local value = active_gamepad:getGamepadAxis(axis_config.axis)
    local threshold = axis_config.threshold or 0.3
    local direction = axis_config.direction or 1

    if direction > 0 then
        return value > threshold
    else
        return value < -threshold
    end
end

-- Check if an action is currently held down (continuous input)
function controls.is_down(action_name)
    local action = controls_config.actions[action_name]
    if not action then
        print("[CONTROLS] Warning: Unknown action '" .. tostring(action_name) .. "'")
        return false
    end

    -- Check keyboard
    if any_key_down(action.keyboard) then
        last_keyboard_input = love.timer.getTime()
        update_input_mode()
        return true
    end

    -- Check gamepad button
    if any_gamepad_button_down(action.gamepad_button) then
        last_gamepad_input = love.timer.getTime()
        update_input_mode()
        return true
    end

    -- Check gamepad axis
    if check_gamepad_axis(action.gamepad_axis) then
        last_gamepad_input = love.timer.getTime()
        update_input_mode()
        return true
    end

    return false
end

-- Check if an action was just pressed (discrete input with cooldown)
function controls.just_pressed(action_name)
    local action = controls_config.actions[action_name]
    if not action then
        print("[CONTROLS] Warning: Unknown action '" .. tostring(action_name) .. "'")
        return false
    end

    -- Check cooldown
    local now = love.timer.getTime()
    local cooldown = button_cooldowns[action_name] or 0
    if now < cooldown then
        return false
    end

    -- Check if pressed
    if controls.is_down(action_name) then
        button_cooldowns[action_name] = now + BUTTON_COOLDOWN
        return true
    end

    return false
end

-- Get analog value for an action (0-1 range)
-- Useful for triggers and analog stick movement
function controls.get_axis(action_name)
    local action = controls_config.actions[action_name]
    if not action then return 0 end

    -- Keyboard returns binary (0 or 1)
    if any_key_down(action.keyboard) then
        return 1.0
    end

    -- Gamepad button returns binary
    if any_gamepad_button_down(action.gamepad_button) then
        return 1.0
    end

    -- Gamepad axis returns analog value
    if action.gamepad_axis and active_gamepad then
        local value = active_gamepad:getGamepadAxis(action.gamepad_axis.axis)
        local direction = action.gamepad_axis.direction or 1
        local threshold = action.gamepad_axis.threshold or 0.1

        -- Apply direction
        value = value * direction

        -- Dead zone
        if value < threshold then
            return 0
        end

        -- Normalize to 0-1 range after dead zone
        return (value - threshold) / (1.0 - threshold)
    end

    return 0
end

-- ===========================================
-- PROMPT TEXT
-- ===========================================

-- Get prompt text for an action
function controls.get_prompt(action_name)
    local action = controls_config.actions[action_name]
    if not action then return "?" end

    if input_mode == "gamepad" and action.prompt_gamepad and action.prompt_gamepad ~= "" then
        return action.prompt_gamepad
    end
    return action.prompt_keyboard or "?"
end

-- Get prompt text with brackets [X]
function controls.get_prompt_bracketed(action_name)
    return "[" .. controls.get_prompt(action_name) .. "]"
end

-- Get prompt lines for a specific context
function controls.get_prompts(context_name)
    local prompts = controls_config.prompts[context_name]
    if not prompts then return {} end

    if input_mode == "gamepad" and prompts.gamepad then
        return prompts.gamepad
    end
    return prompts.keyboard or {}
end

-- Get camera mode prompt text
function controls.get_camera_mode_prompt(mode)
    local prompts = controls_config.prompts.camera_mode
    if not prompts or not prompts[mode] then return "" end

    if input_mode == "gamepad" then
        return prompts[mode].gamepad or prompts[mode].keyboard
    end
    return prompts[mode].keyboard
end

-- Get thruster label for a thruster index
function controls.get_thruster_label(thruster_index)
    local label_index = controls_config.thruster_label_map[thruster_index]
    if not label_index then return "?" end

    local labels = controls_config.thruster_labels
    if input_mode == "gamepad" and labels.gamepad then
        return labels.gamepad[label_index] or "?"
    end
    return labels.keyboard[label_index] or "?"
end

-- Get all thruster labels
function controls.get_thruster_labels()
    local labels = controls_config.thruster_labels
    if input_mode == "gamepad" and labels.gamepad then
        return labels.gamepad
    end
    return labels.keyboard
end

-- ===========================================
-- UTILITY
-- ===========================================

-- Update function (call each frame)
function controls.update(dt)
    -- Currently nothing needed per-frame
    -- Could add input buffering or other features here
end

-- Check if a gamepad is connected
function controls.has_gamepad()
    return active_gamepad ~= nil
end

-- Get gamepad name
function controls.get_gamepad_name()
    if active_gamepad then
        return active_gamepad:getName()
    end
    return nil
end

-- Reset button cooldowns (useful when switching scenes)
function controls.reset_cooldowns()
    button_cooldowns = {}
end

return controls
