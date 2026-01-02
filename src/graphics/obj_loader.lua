-- OBJ File Loader for LÖVE
-- Loads .obj files into mesh format compatible with renderer_dda

local obj_loader = {}

function obj_loader.load(filepath)
	local positions = {}
	local uvs = {}
	local vertices = {}
	local triangles = {}
	local vertexCache = {}  -- Cache v/vt combinations to avoid duplicates

	-- Read file using Love2D filesystem
	local content, err = love.filesystem.read(filepath)
	if not content then
		error("Could not load OBJ file: " .. filepath .. " - " .. (err or "unknown error"))
	end

	-- Parse each line
	for line in content:gmatch("[^\r\n]+") do
		-- Trim whitespace
		line = line:gsub("^%s+", ""):gsub("%s+$", "")

		-- Skip empty lines and comments
		if #line > 0 and line:sub(1, 1) ~= "#" then
			-- Vertex line (v x y z)
			if line:sub(1, 2) == "v " then
				local x, y, z = line:match("v%s+([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)")
				if x then
					table.insert(positions, {tonumber(x), tonumber(y), tonumber(z)})
				end

			-- Texture coordinate line (vt u v)
			elseif line:sub(1, 3) == "vt " then
				local u, v = line:match("vt%s+([%d%.%-]+)%s+([%d%.%-]+)")
				if u then
					-- Flip V coordinate (OBJ uses bottom-left origin)
					table.insert(uvs, {tonumber(u), 1.0 - tonumber(v)})
				end

			-- Face line (f v1/vt1/vn1 v2/vt2/vn2 v3/vt3/vn3)
			elseif line:sub(1, 2) == "f " then
				local face_data = {}
				for part in line:gmatch("%S+") do
					if part ~= "f" then
						table.insert(face_data, part)
					end
				end

				-- Parse vertex and UV indices, creating unique vertices
				local face_vertices = {}

				for _, part in ipairs(face_data) do
					local v_idx, vt_idx = part:match("(%d+)/(%d*)/")
					if not v_idx then
						v_idx, vt_idx = part:match("(%d+)/(%d+)")
					end
					if not v_idx then
						v_idx = part:match("(%d+)")
					end

					if v_idx then
						v_idx = tonumber(v_idx)
						vt_idx = vt_idx and vt_idx ~= "" and tonumber(vt_idx) or nil

						-- Create unique vertex for each v/vt combination
						local key = v_idx .. "/" .. (vt_idx or "none")
						local vertex_index = vertexCache[key]

						if not vertex_index then
							-- Create new vertex
							local pos = positions[v_idx]
							local uv = vt_idx and uvs[vt_idx] or {0, 0}

							vertex_index = #vertices + 1
							vertices[vertex_index] = {
								pos = {pos[1], pos[2], pos[3]},
								uv = {uv[1], uv[2]}
							}
							vertexCache[key] = vertex_index
						end

						table.insert(face_vertices, vertex_index)
					end
				end

				-- Triangulate faces (fan triangulation with inverted winding for CCW)
				if #face_vertices == 3 then
					table.insert(triangles, {face_vertices[1], face_vertices[3], face_vertices[2]})
				elseif #face_vertices == 4 then
					-- Quad: split into 2 triangles
					table.insert(triangles, {face_vertices[1], face_vertices[3], face_vertices[2]})
					table.insert(triangles, {face_vertices[1], face_vertices[4], face_vertices[3]})
				elseif #face_vertices > 4 then
					-- N-gon: fan from v1
					for i = 2, #face_vertices - 1 do
						table.insert(triangles, {face_vertices[1], face_vertices[i + 1], face_vertices[i]})
					end
				end
			end
		end
	end

	print(string.format("Loaded OBJ: %d vertices (%d unique), %d triangles", #positions, #vertices, #triangles))

	return {
		vertices = vertices,
		triangles = triangles
	}
end

return obj_loader
