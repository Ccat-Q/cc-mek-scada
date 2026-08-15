
local element = require("graphics.element")
return function (args)
local bkg = "008877FFCCEE114455DD9933BBAA2266"
local spaces = string.rep(" ", 32)
args.width = 32
args.height = 1
local e = element.new(args)
function e.redraw()
e.w_set_cur(1, 1)
e.w_blit(spaces, bkg, bkg)
end
local ColorMap, id = e.complete(true)
return ColorMap, id
end
