
local element = require("graphics.element")
return function (args)
local e = element.new(args)
local DisplayBox, id = e.complete()
return DisplayBox, id
end
