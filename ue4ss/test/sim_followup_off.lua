-- sim_followup.lua with gore.followUpCuts off: one cut a swing
FOLLOW_UP = false
dofile(debug.getinfo(1, "S").source:sub(2):gsub("sim_followup_off%.lua$", "sim_followup.lua"))
