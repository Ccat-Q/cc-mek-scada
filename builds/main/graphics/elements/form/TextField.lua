
local core    = require("graphics.core")
local element = require("graphics.element")
local KEY_CLICK = core.events.KEY_CLICK
local MOUSE_CLICK = core.events.MOUSE_CLICK
return function (args)
args.height = 1
args.can_focus = true
local e = element.new(args)
e.value = args.value or ""
local ifield = core.new_ifield(e, args.max_len or e.frame.w, args.fg_bg, args.dis_fg_bg)
ifield.censor(args.censor)
function e.handle_mouse(event)
if e.enabled and e.in_frame_bounds(event.current.x, event.current.y) then
if core.events.was_clicked(event.type) then
e.take_focus()
if event.type == MOUSE_CLICK.UP then
ifield.move_cursor(event.current.x)
end
elseif event.type == MOUSE_CLICK.DOUBLE_CLICK then
ifield.select_all()
end
end
end
function e.handle_key(event)
if event.type == KEY_CLICK.CHAR then
ifield.try_insert_char(event.name)
elseif event.type == KEY_CLICK.DOWN or event.type == KEY_CLICK.HELD then
if (event.key == keys.backspace or event.key == keys.delete) then
ifield.backspace()
elseif event.key == keys.left then
ifield.nav_left()
elseif event.key == keys.right then
ifield.nav_right()
elseif event.key == keys.a and event.ctrl then
ifield.select_all()
elseif event.key == keys.home or event.key == keys.up then
ifield.nav_start()
elseif event.key == keys["end"] or event.key == keys.down then
ifield.nav_end()
end
end
end
e.set_value = ifield.set_value
e.handle_paste = ifield.set_value
function e.on_unfocused()
ifield.show()
if type(args.on_unfocus) == "function" then args.on_unfocus(e.value) end
end
e.on_focused = ifield.show
e.on_enabled = ifield.show
e.on_disabled = ifield.show
e.redraw = ifield.show
local TextField, id = e.complete(true)
TextField.censor = ifield.censor
return TextField, id
end
