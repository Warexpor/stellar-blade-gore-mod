-- The struggle when she dies falling (sim_struggle.lua with AIR_FALL set): it and her post-death movement wait for her
-- to land, then run as on the floor (a seed of its own: on 10 the later start left time for one whole act)
AIR_FALL = true
STRUGGLE_SEED = 11
dofile(debug.getinfo(1, "S").source:sub(2):gsub("sim_struggle_air%.lua$", "sim_struggle.lua"))
