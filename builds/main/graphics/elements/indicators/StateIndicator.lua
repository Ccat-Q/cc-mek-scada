
local util    = require("scada-common.util")
local element = require("graphics.element")
return function (args)
element.assert(type(args.states) == "table", "states is a required field")
if util.is_int(args.height) then
element.assert(args.height % 2 == 1, "height should be an odd number")
else args.height = 1 end
args.width = args.min_width or 1
local state_blit_cmds = {}
for i = 1, #args.states do
local state_def = args.states[i]
if string.len(state_def.text) > args.width then
args.width = string.len(state_def.text)
end
local text = util.pad(state_def.text, args.width)
table.insert(state_blit_cmds, {
text = text,
fgd = string.rep(state_def.color.blit_fgd, string.len(text)),
bkg = string.rep(state_def.color.blit_bkg, string.len(text))
})
end
local e = element.new(args)
e.value = args.value or 1
function e.redraw()
local blit_cmd = state_blit_cmds[e.value]
e.w_set_cur(1, 1)
e.w_blit(blit_cmd.text, blit_cmd.fgd, blit_cmd.bkg)
end
function e.on_update(new_state)
e.value = new_state
e.redraw()
end
function e.set_value(val) e.on_update(val) end
local StateIndicator, id = e.complete(true)
return StateIndicator, id
end
