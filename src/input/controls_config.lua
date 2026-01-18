-- Controls Configuration
-- Defines all control mappings for keyboard and gamepad, plus prompt text
--
-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │                        CONTROL MAPPING TABLE                            │
-- ├─────────────────────┬──────────────────┬────────────────────────────────┤
-- │ Action              │ Keyboard         │ Gamepad (Xbox)                 │
-- ├─────────────────────┼──────────────────┼────────────────────────────────┤
-- │ FLIGHT CONTROLS     │                  │                                │
-- │ Thruster Front      │ W / I            │ Y button / Left Stick Up       │
-- │ Thruster Back       │ S / K            │ A button / Left Stick Down     │
-- │ Thruster Left       │ A / J            │ X button / Left Stick Left     │
-- │ Thruster Right      │ D / L            │ B button / Left Stick Right    │
-- │ All Thrusters       │ Space            │ RT (Right Trigger)             │
-- │ Left+Right          │ N                │ -                              │
-- │ Front+Back          │ M                │ -                              │
-- ├─────────────────────┼──────────────────┼────────────────────────────────┤
-- │ ROTATION            │                  │                                │
-- │ Yaw Left            │ Q                │ LB (Left Bumper)               │
-- │ Yaw Right           │ E                │ RB (Right Bumper)              │
-- │ Auto-Level          │ Shift            │ LT (Left Trigger)              │
-- ├─────────────────────┼──────────────────┼────────────────────────────────┤
-- │ CAMERA              │                  │                                │
-- │ Camera Up/Down/L/R  │ Arrow Keys       │ Right Stick                    │
-- │ Cycle Camera        │ F                │ D-Pad Right                    │
-- │ Cycle Target        │ T                │ D-Pad Left                     │
-- ├─────────────────────┼──────────────────┼────────────────────────────────┤
-- │ MENU/UI             │                  │                                │
-- │ Pause               │ Tab / Esc        │ Start                          │
-- │ Confirm             │ Enter / Space    │ A button                       │
-- │ Back                │ Esc / Backspace  │ B button                       │
-- │ Menu Navigate       │ Arrows / WASD    │ D-Pad / Left Stick             │
-- ├─────────────────────┼──────────────────┼────────────────────────────────┤
-- │ GAME ACTIONS        │                  │                                │
-- │ Restart             │ R                │ Y button                       │
-- │ Quit to Menu        │ Q                │ B button                       │
-- │ Toggle Controls     │ C                │ Select/Back                    │
-- │ Toggle Goals        │ G                │ D-Pad Up                       │
-- └─────────────────────┴──────────────────┴────────────────────────────────┘

local controls_config = {}

-- ===========================================
-- ACTION DEFINITIONS
-- Each action has keyboard keys, gamepad bindings, and display text
-- ===========================================

controls_config.actions = {
    -- Flight controls (thrusters)
    -- Xbox: Y/X/A/B buttons OR left stick for individual thrusters
    thruster_front = {
        keyboard = {"w", "i"},
        gamepad_button = {"y"},  -- Y button (Xbox)
        gamepad_axis = {axis = "lefty", direction = -1, threshold = 0.3},
        prompt_keyboard = "W",
        prompt_gamepad = "Y/LS",
        description = "Front thruster",
    },
    thruster_back = {
        keyboard = {"s", "k"},
        gamepad_button = {"a"},  -- A button (Xbox)
        gamepad_axis = {axis = "lefty", direction = 1, threshold = 0.3},
        prompt_keyboard = "S",
        prompt_gamepad = "A/LS",
        description = "Back thruster",
    },
    thruster_left = {
        keyboard = {"a", "j"},
        gamepad_button = {"x"},  -- X button (Xbox)
        gamepad_axis = {axis = "leftx", direction = -1, threshold = 0.3},
        prompt_keyboard = "A",
        prompt_gamepad = "X/LS",
        description = "Left thruster",
    },
    thruster_right = {
        keyboard = {"d", "l"},
        gamepad_button = {"b"},  -- B button (Xbox)
        gamepad_axis = {axis = "leftx", direction = 1, threshold = 0.3},
        prompt_keyboard = "D",
        prompt_gamepad = "B/LS",
        description = "Right thruster",
    },

    -- Arcade mode thruster combos
    thruster_all = {
        keyboard = {"space"},
        gamepad_button = nil,
        gamepad_axis = {axis = "triggerright", direction = 1, threshold = 0.3},  -- RT
        prompt_keyboard = "Space",
        prompt_gamepad = "RT",
        description = "All thrusters",
    },
    thruster_sides = {
        keyboard = {"n"},
        gamepad_button = nil,  -- Not mapped on gamepad
        prompt_keyboard = "N",
        prompt_gamepad = "",
        description = "Left+Right thrusters",
    },
    thruster_frontback = {
        keyboard = {"m"},
        gamepad_button = nil,  -- Not mapped on gamepad
        prompt_keyboard = "M",
        prompt_gamepad = "",
        description = "Front+Back thrusters",
    },

    -- Rotation controls
    yaw_left = {
        keyboard = {"q"},
        gamepad_button = {"leftshoulder"},  -- LB (Xbox)
        gamepad_axis = nil,
        prompt_keyboard = "Q",
        prompt_gamepad = "LB",
        description = "Yaw left",
    },
    yaw_right = {
        keyboard = {"e"},
        gamepad_button = {"rightshoulder"},  -- RB (Xbox)
        gamepad_axis = nil,
        prompt_keyboard = "E",
        prompt_gamepad = "RB",
        description = "Yaw right",
    },
    auto_level = {
        keyboard = {"lshift", "rshift"},
        gamepad_button = nil,
        gamepad_axis = {axis = "triggerleft", direction = 1, threshold = 0.3},  -- LT
        prompt_keyboard = "Shift",
        prompt_gamepad = "LT",
        description = "Auto-level",
    },

    -- Camera controls
    camera_up = {
        keyboard = {"up"},
        gamepad_button = nil,
        gamepad_axis = {axis = "righty", direction = -1, threshold = 0.3},
        prompt_keyboard = "Up",
        prompt_gamepad = "RS Up",
        description = "Camera up",
    },
    camera_down = {
        keyboard = {"down"},
        gamepad_button = nil,
        gamepad_axis = {axis = "righty", direction = 1, threshold = 0.3},
        prompt_keyboard = "Down",
        prompt_gamepad = "RS Down",
        description = "Camera down",
    },
    camera_left = {
        keyboard = {"left"},
        gamepad_button = nil,
        gamepad_axis = {axis = "rightx", direction = -1, threshold = 0.3},
        prompt_keyboard = "Left",
        prompt_gamepad = "RS Left",
        description = "Camera left",
    },
    camera_right = {
        keyboard = {"right"},
        gamepad_button = nil,
        gamepad_axis = {axis = "rightx", direction = 1, threshold = 0.3},
        prompt_keyboard = "Right",
        prompt_gamepad = "RS Right",
        description = "Camera right",
    },
    camera_cycle = {
        keyboard = {"f"},
        gamepad_button = {"dpright"},  -- D-Pad Right
        prompt_keyboard = "F",
        prompt_gamepad = "D-Right",
        description = "Cycle camera mode",
    },

    -- Menu/UI controls
    pause = {
        keyboard = {"tab", "escape"},
        gamepad_button = {"start"},
        prompt_keyboard = "Tab",
        prompt_gamepad = "Start",
        description = "Pause",
    },
    confirm = {
        keyboard = {"return", "space"},
        gamepad_button = {"a"},
        prompt_keyboard = "Enter",
        prompt_gamepad = "A",
        description = "Confirm",
    },
    back = {
        keyboard = {"escape", "backspace"},
        gamepad_button = {"b"},
        prompt_keyboard = "Esc",
        prompt_gamepad = "B",
        description = "Back",
    },
    menu_up = {
        keyboard = {"up", "w"},
        gamepad_button = {"dpup"},
        gamepad_axis = {axis = "lefty", direction = -1, threshold = 0.5},
        prompt_keyboard = "Up",
        prompt_gamepad = "D-Pad Up",
        description = "Menu up",
    },
    menu_down = {
        keyboard = {"down", "s"},
        gamepad_button = {"dpdown"},
        gamepad_axis = {axis = "lefty", direction = 1, threshold = 0.5},
        prompt_keyboard = "Down",
        prompt_gamepad = "D-Pad Down",
        description = "Menu down",
    },
    menu_left = {
        keyboard = {"left", "a"},
        gamepad_button = {"dpleft"},
        gamepad_axis = {axis = "leftx", direction = -1, threshold = 0.5},
        prompt_keyboard = "Left",
        prompt_gamepad = "D-Pad Left",
        description = "Menu left",
    },
    menu_right = {
        keyboard = {"right", "d"},
        gamepad_button = {"dpright"},
        gamepad_axis = {axis = "leftx", direction = 1, threshold = 0.5},
        prompt_keyboard = "Right",
        prompt_gamepad = "D-Pad Right",
        description = "Menu right",
    },

    -- Game actions
    restart = {
        keyboard = {"r"},
        gamepad_button = {"y"},
        prompt_keyboard = "R",
        prompt_gamepad = "Y",
        description = "Restart",
    },
    quit_to_menu = {
        keyboard = {"q"},
        gamepad_button = {"b"},
        prompt_keyboard = "Q",
        prompt_gamepad = "B",
        description = "Return to Menu",
    },
    toggle_controls = {
        keyboard = {"c"},
        gamepad_button = {"back"},  -- Select/View button
        prompt_keyboard = "C",
        prompt_gamepad = "Select",
        description = "Toggle controls",
    },
    toggle_goals = {
        keyboard = {"g"},
        gamepad_button = {"dpup"},  -- D-Pad Up
        prompt_keyboard = "G",
        prompt_gamepad = "D-Up",
        description = "Toggle goals",
    },
    target_cycle = {
        keyboard = {"t"},
        gamepad_button = {"dpleft"},  -- D-Pad Left
        prompt_keyboard = "T",
        prompt_gamepad = "D-Left",
        description = "Cycle target",
    },
}

-- ===========================================
-- PROMPT TEXT TEMPLATES
-- Used for on-screen control hints
-- ===========================================

controls_config.prompts = {
    -- Arcade mode control hints
    arcade_controls = {
        keyboard = {
            "CONTROLS:",
            "Space: All thrusters",
            "N:     Left+Right",
            "M:     Front+Back",
            "Shift: Auto-level",
        },
        gamepad = {
            "CONTROLS:",
            "RT: All thrusters",
            "Y/X/A/B: Individual",
            "LT: Auto-level",
        },
    },

    -- Simulation mode control hints
    simulation_controls = {
        keyboard = {
            "CONTROLS:",
            "W/A/S/D: Thrusters",
            "Manual flight!",
        },
        gamepad = {
            "CONTROLS:",
            "Y/X/A/B or LS: Thrust",
            "Manual flight!",
        },
    },

    -- Camera control hints
    camera_controls = {
        keyboard = {
            "CAMERA:",
            "Mouse: Drag to rotate",
            "Arrows: Rotate camera",
        },
        gamepad = {
            "CAMERA:",
            "Right Stick: Rotate",
        },
    },

    -- Pause menu
    pause_menu = {
        keyboard = {
            "[Tab] Resume",
            "[C] Hide/Show Controls",
            "[Q] Return to Menu",
        },
        gamepad = {
            "[Start] Resume",
            "[Select] Hide/Show Controls",
            "[B] Return to Menu",
        },
    },

    -- Death screen
    death_screen = {
        keyboard = {
            "[R] Restart",
            "[Q] Quit to Menu",
        },
        gamepad = {
            "[Y] Restart",
            "[B] Quit to Menu",
        },
    },

    -- Mission complete
    mission_complete = {
        keyboard = {
            "[Q] Return to Menu",
            "[R] Replay Mission",
        },
        gamepad = {
            "[B] Return to Menu",
            "[Y] Replay Mission",
        },
    },

    -- Race failed
    race_failed = {
        keyboard = {
            "[Q] Return to Menu",
            "[R] Try Again",
        },
        gamepad = {
            "[B] Return to Menu",
            "[Y] Try Again",
        },
    },

    -- Camera mode indicator
    camera_mode = {
        follow = {
            keyboard = "[F] CAM: FOLLOW",
            gamepad = "[D-Right] CAM: FOLLOW",
        },
        free = {
            keyboard = "[F] CAM: FREE",
            gamepad = "[D-Right] CAM: FREE",
        },
        focus = {
            keyboard = "[F] CAM: FOCUS",
            gamepad = "[D-Right] CAM: FOCUS",
        },
    },

    -- Combat target indicator
    target_cycle = {
        keyboard = "[T] Target",
        gamepad = "[D-Left] Target",
    },

    -- Toggle goals
    toggle_goals = {
        keyboard = "[G] Toggle Goals",
        gamepad = "[D-Up] Toggle Goals",
    },
}

-- ===========================================
-- THRUSTER INDICATOR LABELS
-- Labels shown above each thruster in the HUD
-- ===========================================

controls_config.thruster_labels = {
    keyboard = {"W", "A", "S", "D"},  -- Front, Left, Back, Right (matching thruster order: 3, 2, 4, 1)
    gamepad = {"Y", "X", "A", "B"},   -- Xbox face buttons: Y=Front, X=Left, A=Back, B=Right
}

-- Thruster label mapping: maps thruster index to label index
-- Thrusters: 1=Right(D), 2=Left(A), 3=Front(W), 4=Back(S)
-- Labels displayed as: W(top), A(left), S(bottom), D(right)
controls_config.thruster_label_map = {
    [1] = 4,  -- Thruster 1 (Right/D) -> Label index 4 (D)
    [2] = 2,  -- Thruster 2 (Left/A) -> Label index 2 (A)
    [3] = 1,  -- Thruster 3 (Front/W) -> Label index 1 (W)
    [4] = 3,  -- Thruster 4 (Back/S) -> Label index 3 (S)
}

return controls_config
