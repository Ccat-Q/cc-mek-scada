
local core         = require("graphics.core")
local style        = require("coordinator.ui.style")
local reactor_view = require("coordinator.ui.components.reactor")
local boiler_view  = require("coordinator.ui.components.boiler")
local turbine_view = require("coordinator.ui.components.turbine")
local Div          = require("graphics.elements.Div")
local PipeNetwork  = require("graphics.elements.PipeNetwork")
local TextBox      = require("graphics.elements.TextBox")
local ALIGN = core.ALIGN
local pipe = core.pipe
local function make(parent, x, y, unit)
local num_boilers = #unit.boiler_data_tbl
local num_turbines = #unit.turbine_data_tbl
assert(num_boilers  >= 0 and num_boilers  <= 2, "minimum 0 boilers, maximum 2 boilers")
assert(num_turbines >= 1 and num_turbines <= 3, "minimum 1 turbine, maximum 3 turbines")
local height = 25
if num_boilers == 0 and num_turbines == 1 then
height = 9
elseif num_boilers <= 1 and num_turbines <= 2 then
height = 17
end
assert(parent.get_height() >= (y + height), "main display not of sufficient vertical resolution (add an additional row of monitors)")
local root = Div{parent=parent,x=x,y=y,width=80,height=height}
TextBox{parent=root,text="Unit #"..unit.unit_id,alignment=ALIGN.CENTER,fg_bg=style.theme.header}
reactor_view(root, 1, 3, unit.unit_ps)
if num_boilers > 0 then
local coolant_pipes = {}
if num_boilers >= 2 then
table.insert(coolant_pipes, pipe(0, 0, 11, 12, colors.lightBlue))
end
table.insert(coolant_pipes, pipe(0, 0, 11, 3, colors.lightBlue))
table.insert(coolant_pipes, pipe(2, 0, 11, 2, colors.orange))
if num_boilers >= 2 then
table.insert(coolant_pipes, pipe(2, 0, 11, 11, colors.orange))
end
PipeNetwork{parent=root,x=4,y=10,pipes=coolant_pipes,bg=style.theme.bg}
end
if num_boilers >= 1 then boiler_view(root, 16, 11, unit.boiler_ps_tbl[1]) end
if num_boilers >= 2 then boiler_view(root, 16, 19, unit.boiler_ps_tbl[2]) end
local t_idx = 1
local no_boilers = num_boilers == 0
if (num_turbines >= 3) or no_boilers or (num_boilers == 1 and num_turbines >= 2) then
turbine_view(root, 58, 3, unit.turbine_ps_tbl[t_idx])
t_idx = t_idx + 1
end
if (num_turbines >= 1 and not no_boilers) or num_turbines >= 2 then
turbine_view(root, 58, 11, unit.turbine_ps_tbl[t_idx])
t_idx = t_idx + 1
end
if (num_turbines >= 2 and num_boilers >= 2) or num_turbines >= 3 then
turbine_view(root, 58, 19, unit.turbine_ps_tbl[t_idx])
end
local steam_pipes_b = {}
if no_boilers then
table.insert(steam_pipes_b, pipe(0, 1, 3, 1, colors.white))
table.insert(steam_pipes_b, pipe(0, 2, 3, 2, colors.blue))
if num_turbines >= 2 then
table.insert(steam_pipes_b, pipe(1, 2, 3, 9, colors.white))
table.insert(steam_pipes_b, pipe(2, 3, 3, 10, colors.blue))
end
if num_turbines >= 3 then
table.insert(steam_pipes_b, pipe(1, 9, 3, 17, colors.white))
table.insert(steam_pipes_b, pipe(2, 10, 3, 18, colors.blue))
end
else
local steam_pipes_a = {
pipe(0, 1, 6, 1, colors.white, false, true),
pipe(0, 2, 6, 2, colors.blue, false, true)
}
if num_boilers >= 2 then
table.insert(steam_pipes_a, pipe(0, 9, 6, 9, colors.white, false, true))
table.insert(steam_pipes_a, pipe(0, 10, 6, 10, colors.blue, false, true))
end
if num_turbines >= 3 or (num_boilers == 1 and num_turbines == 2) then
table.insert(steam_pipes_b, pipe(0, 9, 1, 2, colors.white, false, true))
table.insert(steam_pipes_b, pipe(1, 1, 3, 1, colors.white, false, false))
end
table.insert(steam_pipes_b, pipe(0, 9, 3, 9, colors.white, false, true))
if num_turbines >= 3 or (num_boilers == 1 and num_turbines == 2) then
table.insert(steam_pipes_b, pipe(0, 10, 2, 3, colors.blue, false, true))
table.insert(steam_pipes_b, pipe(2, 2, 3, 2, colors.blue, false, false))
end
table.insert(steam_pipes_b, pipe(0, 10, 3, 10, colors.blue, false, true))
if num_turbines >= 3 or (num_turbines >= 2 and num_boilers >= 2) then
if num_boilers >= 2 then
table.insert(steam_pipes_b, pipe(0, 17, 1, 9, colors.white, false, true))
table.insert(steam_pipes_b, pipe(0, 17, 3, 17, colors.white, false, true))
table.insert(steam_pipes_b, pipe(0, 18, 2, 10, colors.blue, false, true))
table.insert(steam_pipes_b, pipe(0, 18, 3, 18, colors.blue, false, true))
else
table.insert(steam_pipes_b, pipe(1, 17, 1, 9, colors.white, false, true))
table.insert(steam_pipes_b, pipe(1, 17, 3, 17, colors.white, false, true))
table.insert(steam_pipes_b, pipe(2, 18, 2, 10, colors.blue, false, true))
table.insert(steam_pipes_b, pipe(2, 18, 3, 18, colors.blue, false, true))
end
elseif num_turbines == 1 and num_boilers >= 2 then
table.insert(steam_pipes_b, pipe(0, 17, 1, 9, colors.white, false, true))
table.insert(steam_pipes_b, pipe(0, 17, 1, 17, colors.white, false, true))
table.insert(steam_pipes_b, pipe(0, 18, 2, 10, colors.blue, false, true))
table.insert(steam_pipes_b, pipe(0, 18, 2, 18, colors.blue, false, true))
end
PipeNetwork{parent=root,x=47,y=11,pipes=steam_pipes_a,bg=style.theme.bg}
end
PipeNetwork{parent=root,x=54,y=3,pipes=steam_pipes_b,bg=style.theme.bg}
return root
end
return make
