
local util = require("scada-common.util")
local core = require("graphics.core")
local events = core.events
local element = {}
function element.assert(condition, msg, callstack_offset)
callstack_offset = callstack_offset or 0
local caller = debug.getinfo(3 + callstack_offset)
assert(condition, util.c(caller.source, ":", caller.currentline, "{", debug.getinfo(2 + callstack_offset).name, "}: ", msg))
end
function element.new(args, constraint, child_offset_x, child_offset_y)
local self = {
id = nil,
is_root = args.parent == nil,
elem_type = debug.getinfo(2).name,
define_completed = false,
p_window = nil,
position = events.new_coord_2d(1, 1),
bounds = { x1 = 1, y1 = 1, x2 = 1, y2 = 1 },
offset_x = 0,
offset_y = 0,
next_y = 1,
next_id = 1,
subscriptions = {},
button_down = { events.new_coord_2d(-1, -1), events.new_coord_2d(-1, -1), events.new_coord_2d(-1, -1) },
focused = false,
mt = {}
}
local protected = {
enabled = true,
value = nil,
window = nil,
content_window = nil,
mouse_window_shift = { x = 0, y = 0 },
fg_bg = core.cpair(colors.white, colors.black),
frame = core.gframe(1, 1, 1, 1),
children = {},
child_id_map = {}
}
function self.mt.__tostring()
return util.c("graphics.element{", self.elem_type, "} @ ", self)
end
local public = {}
setmetatable(public, self.mt)
local function _tab_focusable(reverse)
local first_f = nil
local prev_f = nil
local cur_f = nil
local done = false
local function handle_element(elem)
if elem.is_visible() and elem.is_focusable() and elem.is_enabled() then
if first_f == nil then first_f = elem end
if cur_f == nil then
if elem.is_focused() then
cur_f = elem
if (not done) and (reverse and prev_f ~= nil) then
cur_f.unfocus()
prev_f.focus()
done = true
end
end
else
if elem.is_focused() then
elem.unfocus()
elseif not (reverse or done) then
cur_f.unfocus()
elem.focus()
done = true
end
end
prev_f = elem
end
end
local function traverse(children)
for i = 1, #children do
local child = children[i]
handle_element(child.get())
if child.get().is_visible() then traverse(child.children) end
end
end
traverse(protected.children)
if first_f ~= nil and not done then
if reverse then
if cur_f ~= nil then cur_f.unfocus() end
if prev_f ~= nil then prev_f.focus() end
else
if cur_f ~= nil then cur_f.unfocus() end
first_f.focus()
end
end
end
function protected.prepare_template(offset_x, offset_y, next_y)
next_y = util.trinary(args.height == nil and constraint == nil, 1, next_y)
self.offset_x = offset_x
self.offset_y = offset_y
if args.gframe ~= nil then
protected.frame.x = args.gframe.x
protected.frame.y = args.gframe.y
protected.frame.w = args.gframe.w
protected.frame.h = args.gframe.h
else
local w, h = self.p_window.getSize()
protected.frame.x = args.x or 1
protected.frame.y = args.y or next_y
protected.frame.w = args.width or w
protected.frame.h = args.height or h
end
local f = protected.frame
if args.parent ~= nil then
local w, h = self.p_window.getSize()
f.w = math.min(f.w, w - (f.x - 1))
f.h = math.min(f.h, h - (f.y - 1))
if type(constraint) == "function" then
w, h = constraint(f)
f.w = math.min(f.w, w)
f.h = math.min(f.h, h)
end
end
element.assert(f.x >= 1, "frame x not >= 1", 3)
element.assert(f.y >= 1, "frame y not >= 1", 3)
element.assert(f.w >= 1, "frame width not >= 1", 3)
element.assert(f.h >= 1, "frame height not >= 1", 3)
protected.window = window.create(self.p_window, f.x, f.y, f.w, f.h, args.hidden ~= true)
if args.fg_bg ~= nil then
protected.fg_bg = core.cpair(args.fg_bg.fgd, args.fg_bg.bkg)
end
if args.parent ~= nil then
local p_fg_bg = args.parent.get_fg_bg()
if args.fg_bg == nil then
protected.fg_bg = core.cpair(p_fg_bg.fgd, p_fg_bg.bkg)
else
if protected.fg_bg.fgd == colors._INHERIT then protected.fg_bg = core.cpair(p_fg_bg.fgd, protected.fg_bg.bkg) end
if protected.fg_bg.bkg == colors._INHERIT then protected.fg_bg = core.cpair(protected.fg_bg.fgd, p_fg_bg.bkg) end
end
end
element.assert(protected.fg_bg.fgd ~= colors._INHERIT, "could not determine foreground color to inherit")
element.assert(protected.fg_bg.bkg ~= colors._INHERIT, "could not determine background color to inherit")
protected.window.setBackgroundColor(protected.fg_bg.bkg)
protected.window.setTextColor(protected.fg_bg.fgd)
protected.window.clear()
self.position.x, self.position.y = protected.window.getPosition()
self.position.x = self.position.x + offset_x
self.position.y = self.position.y + offset_y
self.bounds.x1 = self.position.x
self.bounds.x2 = self.position.x + f.w - 1
self.bounds.y1 = self.position.y
self.bounds.y2 = self.position.y + f.h - 1
function protected.w_set_cur(x, y) protected.window.setCursorPos(x, y) end
function protected.w_set_bkg(c) protected.window.setBackgroundColor(c) end
function protected.w_set_fgd(c) protected.window.setTextColor(c) end
function protected.w_write(str) protected.window.write(str) end
function protected.w_blit(str, fg, bg) protected.window.blit(str, fg, bg) end
end
function protected.in_window_bounds(x, y)
local in_x = x >= self.bounds.x1 and x <= self.bounds.x2
local in_y = y >= self.bounds.y1 and y <= self.bounds.y2
return in_x and in_y
end
function protected.in_frame_bounds(x, y)
local in_x = x >= 1 and x <= protected.frame.w
local in_y = y >= 1 and y <= protected.frame.h
return in_x and in_y
end
function protected.get() return public, self.id end
function protected.complete(redraw)
if redraw then protected.redraw() end
if args.parent ~= nil then args.parent.__child_ready(self.id, public) end
return public, self.id
end
function protected.is_focused() return self.focused end
function protected.defocus() public.unfocus_all() end
function protected.take_focus() args.parent.__focus_child(public) end
function protected.on_added(id, child) end
function protected.on_removed(id) end
function protected.on_enabled() end
function protected.on_disabled() end
function protected.on_focused() end
function protected.on_unfocused() end
function protected.on_child_focused(child) end
function protected.on_shown() end
function protected.on_hidden() end
function protected.handle_mouse(event) end
function protected.handle_key(event) end
function protected.handle_paste(text) end
function protected.on_update(...) end
function protected.get_value() return protected.value end
function protected.set_value(value) end
function protected.set_min(min) end
function protected.set_max(max) end
function protected.recolor(...) end
function protected.resize(...) end
function protected.redraw() end
function protected.start_anim() end
function protected.stop_anim() end
self.p_window = args.window
if self.p_window == nil and args.parent ~= nil then
self.p_window = args.parent.window()
end
element.assert(self.p_window, "no parent window provided", 1)
if args.parent == nil then
self.id = args.id or "__ROOT__"
protected.prepare_template(0, 0, 1)
else
self.id = args.parent.__add_child(args.id, protected)
end
function public.window() return protected.content_window or protected.window end
function public.delete()
local fg_bg = protected.fg_bg
if args.parent ~= nil then
fg_bg = args.parent.get_fg_bg()
end
protected.window.setBackgroundColor(fg_bg.bkg)
protected.window.setTextColor(fg_bg.fgd)
protected.window.clear()
public.hide()
for i = 1, #self.subscriptions do
local s = self.subscriptions[i]
s.ps.unsubscribe(s.key, s.func)
end
for k, v in pairs(protected.children) do
v.get().delete()
protected.children[k] = nil
end
if args.parent ~= nil then
args.parent.__remove_child(self.id)
end
end
function public.__add_child(key, child)
child.prepare_template(child_offset_x or 0, child_offset_y or 0, self.next_y)
self.next_y = child.frame.y + child.frame.h
local id = key
if id == nil then
id = self.next_id
self.next_id = self.next_id + 1
end
protected.child_id_map[id] = #protected.children + 1
table.insert(protected.children, child)
return id
end
function public.__remove_child(id)
local index = protected.child_id_map[id]
if protected.children[index] ~= nil then
protected.on_removed(id)
protected.children[index] = nil
protected.child_id_map[id] = nil
end
end
function public.__child_ready(key, child) protected.on_added(key, child) end
function public.__focus_child(child)
if self.is_root then
public.unfocus_all()
child.focus()
else args.parent.__focus_child(child) end
end
function public.__child_focused(child)
protected.on_child_focused(child)
if not self.is_root then args.parent.__child_focused(public) end
end
function public.get_child(id) return ({ protected.children[protected.child_id_map[id]].get() })[1] end
function public.get_children()
local list = {}
for k, v in pairs(protected.children) do list[k] = v.get() end
return list
end
function public.remove(id)
local index = protected.child_id_map[id]
if protected.children[index] ~= nil then
protected.children[index].get().delete()
protected.on_removed(id)
protected.children[index] = nil
protected.child_id_map[id] = nil
end
end
function public.remove_all()
for i = 1, #protected.children do
local child = protected.children[i].get()
child.delete()
protected.on_removed(child.get_id())
end
self.next_y = 1
protected.children = {}
protected.child_id_map = {}
end
function public.get_element_by_id(id)
local index = protected.child_id_map[id]
if protected.children[index] == nil then
for _, child in pairs(protected.children) do
local elem = child.get().get_element_by_id(id)
if elem ~= nil then return elem end
end
else return ({ protected.children[index].get() })[1] end
end
function public.line_break()
self.next_y = self.next_y + 1
end
function public.get_id() return self.id end
function public.get_x() return protected.frame.x end
function public.get_y() return protected.frame.y end
function public.get_width() return protected.frame.w end
function public.get_height() return protected.frame.h end
function public.get_fg_bg() return protected.fg_bg end
function public.get_value() return protected.get_value() end
function public.set_value(value) protected.set_value(value) end
function public.set_min(min) protected.set_min(min) end
function public.set_max(max) protected.set_max(max) end
function public.is_enabled() return protected.enabled end
function public.enable()
if not protected.enabled then
protected.enabled = true
protected.on_enabled()
end
end
function public.disable()
if protected.enabled then
protected.enabled = false
protected.on_disabled()
public.unfocus_all()
end
end
function public.is_focusable() return args.can_focus end
function public.is_focused() return self.focused end
function public.focus()
if args.can_focus and protected.enabled and not self.focused then
self.focused = true
protected.on_focused()
if not self.is_root then args.parent.__child_focused(public) end
end
end
function public.unfocus()
if args.can_focus and self.focused then
self.focused = false
protected.on_unfocused()
end
end
function public.unfocus_all()
public.unfocus()
for _, child in pairs(protected.children) do child.get().unfocus_all() end
end
function public.recolor(...) protected.recolor(...) end
function public.resize(...) protected.resize(...) end
function public.reposition(x, y)
protected.window.reposition(x, y)
self.position.x, self.position.y = protected.window.getPosition()
self.position.x = self.position.x + self.offset_x
self.position.y = self.position.y + self.offset_y
self.bounds.x1 = self.position.x
self.bounds.x2 = self.position.x + protected.frame.w - 1
self.bounds.y1 = self.position.y
self.bounds.y2 = self.position.y + protected.frame.h - 1
end
function public.handle_mouse(event)
if protected.window.isVisible() then
local x_ini, y_ini = event.initial.x, event.initial.y
local ini_in = protected.in_window_bounds(x_ini, y_ini)
if ini_in then
if event.type == events.MOUSE_CLICK.UP or event.type == events.MOUSE_CLICK.DRAG then
if (event.initial.x ~= self.button_down[event.button].x) or (event.initial.y ~= self.button_down[event.button].y) then
return
end
elseif event.type == events.MOUSE_CLICK.DOWN then
self.button_down[event.button] = event.initial
end
local event_T = events.mouse_transposed(event, self.position.x, self.position.y)
protected.handle_mouse(event_T)
local c_event_T = events.mouse_transposed(event_T, protected.mouse_window_shift.x + 1, protected.mouse_window_shift.y + 1)
for _, child in pairs(protected.children) do child.get().handle_mouse(c_event_T) end
elseif event.type == events.MOUSE_CLICK.DOWN or event.type == events.MOUSE_CLICK.TAP then
public.unfocus_all()
end
else
self.button_down[event.button] = events.new_coord_2d(-1, -1)
end
end
function public.handle_key(event)
if protected.window.isVisible() then
if self.is_root and (event.type == events.KEY_CLICK.DOWN) and (event.key == keys.tab) then
_tab_focusable(event.shift)
else
if self.focused then protected.handle_key(event) end
for _, child in pairs(protected.children) do child.get().handle_key(event) end
end
end
end
function public.handle_paste(text)
if protected.window.isVisible() then
if self.focused then protected.handle_paste(text) end
for _, child in pairs(protected.children) do child.get().handle_paste(text) end
end
end
function public.update(...) protected.on_update(...) end
function public.register(ps, key, func)
table.insert(self.subscriptions, { ps = ps, key = key, func = func })
ps.subscribe(key, func)
end
function public.is_visible() return protected.window.isVisible() end
function public.show(animate)
protected.window.setVisible(true)
if animate ~= false then public.animate_all() end
end
function public.hide(clear)
public.freeze_all()
public.unfocus_all()
protected.window.setVisible(false)
if clear and args.parent then args.parent.redraw() end
end
function public.animate() protected.start_anim() end
function public.animate_all()
if protected.window.isVisible() then
public.animate()
for _, child in pairs(protected.children) do child.get().animate_all() end
end
end
function public.freeze() protected.stop_anim() end
function public.freeze_all()
public.freeze()
for _, child in pairs(protected.children) do child.get().freeze_all() end
end
function public.redraw()
local bg, fg = protected.window.getBackgroundColor(), protected.window.getTextColor()
protected.window.setBackgroundColor(protected.fg_bg.bkg)
protected.window.setTextColor(protected.fg_bg.fgd)
protected.window.clear()
protected.window.setBackgroundColor(bg)
protected.window.setTextColor(fg)
protected.redraw()
for _, child in pairs(protected.children) do child.get().redraw() end
end
function public.content_redraw()
if protected.content_window ~= nil then
protected.content_window.clear()
for _, child in pairs(protected.children) do child.get().redraw() end
end
end
return protected
end
return element
