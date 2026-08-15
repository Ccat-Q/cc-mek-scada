
local element = require("graphics.element")
return function (args)
local e = element.new(args)
local Div, id = e.complete()
return Div, id
end
