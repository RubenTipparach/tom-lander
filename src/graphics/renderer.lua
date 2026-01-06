-- Unified Renderer Loader
-- Returns either GPU or software renderer based on config

local config = require("config")

if config.USE_GPU_RENDERER then
    print("Using GPU renderer")
    return require("renderer_gpu")
else
    print("Using software DDA renderer")
    return require("renderer_dda")
end
