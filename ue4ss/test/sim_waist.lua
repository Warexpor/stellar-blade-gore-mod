-- The struggle after a waist cut (sim_struggle.lua with her death cutting her across the waist): her upper body, a
-- piece from Spine1 up with her left arm on it, fights on; no sitting up or pushing, which need her hips
WAIST_CUT = true
dofile(debug.getinfo(1, "S").source:sub(2):gsub("sim_waist%.lua$", "sim_struggle.lua"))
