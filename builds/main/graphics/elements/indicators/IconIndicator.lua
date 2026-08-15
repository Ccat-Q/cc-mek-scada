
local element = require("graphics.element")
return function (args)
element.assert(type(args.label) == "string", "label is a required field")
element.assert(type(args.states) == "table", "states is a required field")
args.height = 1
args.width = math.max(args.min_label_width or 1, string.len(args.label)) + 4
local e = element.new(args)
e.value = args.value or 1
if e.value == true then e.value = 2 end
local state_blit_cmds = {}
for i = 1, #args.states do
local sym_color = args.states[i]
table.insert(state_blit_cmds, {
text = " " .. sym_color.symbol .. " ",
fgd = string.rep(sym_color.color.blit_fgd, 3),
bkg = string.rep(sym_color.color.blit_bkg, 3)
})
end
function e.on_update(new_state)
new_state = new_state or 1
if new_state == true then new_state = 2 end
local blit_cmd = state_blit_cmds[new_state]
e.value = new_state
e.w_set_cur(1, 1)
e.w_blit(blit_cmd.text, blit_cmd.fgd, blit_cmd.bkg)
end
function e.set_value(val) e.on_update(val) end
function e.redraw()
e.w_set_cur(5, 1)
e.w_write(args.label)
e.on_update(e.value)
end
local IconIndicator, id = e.complete(true)
return IconIndicator, id
end
