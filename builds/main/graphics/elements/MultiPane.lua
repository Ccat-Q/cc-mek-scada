
local element = require("graphics.element")
return function (args)
element.assert(type(args.panes) == "table", "panes is a required field")
local e = element.new(args)
e.value = 1
function e.redraw()
for i = 1, #args.panes do args.panes[i].hide() end
args.panes[e.value].show()
end
function e.set_value(value)
if (e.value ~= value) and (value > 0) and (value <= #args.panes) then
e.value = value
e.redraw()
end
end
local MultiPane, id = e.complete(true)
return MultiPane, id
end
