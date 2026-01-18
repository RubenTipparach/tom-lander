-- Controls Configuration
-- Defines all control mappings for keyboard and gamepad, plus prompt text

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
        gamepad_button = nil,
        gamepad_axis = nil,  -- Yaw not mapped on gamepad
        prompt_keyboard = "Q",
        prompt_gamepad = "",
        description = "Yaw left",
    },
    yaw_right = {
        keyboard = {"e"},
        gamepad_button = nil,
        gamepad_axis = nil,  -- Yaw not mapped on gamepad
        prompt_keyboard = "E",
        prompt_gamepad = "",
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
        gamepad_button = {"leftshoulder"},  -- LB (Xbox)
        prompt_keyboard = "F",
        prompt_gamepad = "LB",
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
        gamepad_button = nil,
        prompt_keyboard = "G",
        prompt_gamepad = "",
        description = "Toggle goals",
    },
    target_cycle = {
        keyboard = {"t"},
        gamepad_button = {"rightshoulder"},  -- RB (Xbox)
        prompt_keyboard = "T",
        prompt_gamepad = "RB",
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
            gamepad = "[LB] CAM: FOLLOW",
        },
        free = {
            keyboard = "[F] CAM: FREE",
            gamepad = "[LB] CAM: FREE",
        },
        focus = {
            keyboard = "[F] CAM: FOCUS",
            gamepad = "[LB] CAM: FOCUS",
        },
    },

    -- Combat target indicator
    target_cycle = {
        keyboard = "[T] Target",
        gamepad = "[RB] Target",
    },

    -- Toggle goals
    toggle_goals = {
        keyboard = "[G] Toggle Goals",
        gamepad = "",
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
