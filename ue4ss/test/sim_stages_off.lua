-- sim_stages.lua with the budget 0: a stage a frame, as before
STAGE_BUDGET = 0
dofile(debug.getinfo(1, "S").source:sub(2):gsub("sim_stages_off%.lua$", "sim_stages.lua"))
