
local tcd     = require("scada-common.tcd")
local core    = require("graphics.core")
local element = require("graphics.element")
local KEY_CLICK = core.events.KEY_CLICK
local MOUSE_CLICK = core.events.MOUSE_CLICK
return function (args)
args.can_focus = true
local e = element.new(args)
local scroll_frame = window.create(e.window, 1, 1, e.frame.w - 1, args.scroll_height, false)
e.content_window = scroll_frame
local list            = {}
local item_pad        = args.item_pad or 0
local scroll_offset   = 0
local content_height  = 0
local max_down_scroll = 0
local max_bar_height  = e.frame.h - 2
local bar_height      = 0
local bar_bounds      = { 0, 0 }
local bar_is_scaled   = false       -- if the scrollbar doesn't have a 1:1 ratio with lines
local holding_bar     = false
local bar_grip_pos    = 0
local mouse_last_y    = 0
local function draw_arrows(pressed_arrow)
local nav_fg_bg = args.nav_fg_bg or e.fg_bg
local active_fg_bg = args.nav_active or nav_fg_bg
if pressed_arrow == 1 then
e.w_set_fgd(active_fg_bg.fgd)
e.w_set_bkg(active_fg_bg.bkg)
e.w_set_cur(e.frame.w, 1)
e.w_write("\x1e")
e.w_set_fgd(nav_fg_bg.fgd)
e.w_set_bkg(nav_fg_bg.bkg)
e.w_set_cur(e.frame.w, e.frame.h)
e.w_write("\x1f")
elseif pressed_arrow == -1 then
e.w_set_fgd(nav_fg_bg.fgd)
e.w_set_bkg(nav_fg_bg.bkg)
e.w_set_cur(e.frame.w, 1)
e.w_write("\x1e")
e.w_set_fgd(active_fg_bg.fgd)
e.w_set_bkg(active_fg_bg.bkg)
e.w_set_cur(e.frame.w, e.frame.h)
e.w_write("\x1f")
else
e.w_set_fgd(nav_fg_bg.fgd)
e.w_set_bkg(nav_fg_bg.bkg)
e.w_set_cur(e.frame.w, 1)
e.w_write("\x1e")
e.w_set_cur(e.frame.w, e.frame.h)
e.w_write("\x1f")
end
e.w_set_fgd(e.fg_bg.fgd)
e.w_set_bkg(e.fg_bg.bkg)
end
local function draw_bar()
local offset = 2 + math.abs(scroll_offset)
bar_height = math.min(max_bar_height + max_down_scroll, max_bar_height)
if bar_height < 1 then
bar_is_scaled = true
local scroll_progress = scroll_offset / max_down_scroll
offset = 2 + math.floor(scroll_progress * (max_bar_height - 1))
bar_height = 1
else
bar_is_scaled = false
end
bar_bounds = { offset, (bar_height + offset) - 1 }
for i = 2, e.frame.h - 1 do
if (i >= offset and i < (bar_height + offset)) and (bar_height ~= max_bar_height) then
if args.nav_fg_bg ~= nil then
e.w_set_bkg(args.nav_fg_bg.fgd)
else
e.w_set_bkg(e.fg_bg.fgd)
end
else
if args.nav_fg_bg ~= nil then
e.w_set_bkg(args.nav_fg_bg.bkg)
else
e.w_set_bkg(e.fg_bg.bkg)
end
end
e.w_set_cur(e.frame.w, i)
if e.is_focused() then e.w_write("\x7f") else e.w_write(" ") end
end
e.w_set_bkg(e.fg_bg.bkg)
end
local function update_positions()
local next_y = 1
scroll_frame.setVisible(false)
scroll_frame.setBackgroundColor(e.fg_bg.bkg)
scroll_frame.setTextColor(e.fg_bg.fgd)
scroll_frame.clear()
for i = 1, #list do
local item = list[i]
item.y = next_y
next_y = next_y + item.h + item_pad
item.e.reposition(1, item.y)
item.e.show()
end
content_height = next_y
max_down_scroll = math.min(-1 * (content_height - (e.frame.h + 1 + item_pad)), 0)
if scroll_offset < max_down_scroll then scroll_offset = max_down_scroll end
scroll_frame.reposition(1, 1 + scroll_offset)
scroll_frame.setVisible(true)
e.mouse_window_shift.y = scroll_offset
draw_bar()
end
local function scaled_bar_scroll(direction)
local scroll_progress = scroll_offset / max_down_scroll
local bar_position = math.floor(scroll_progress * (max_bar_height - 1))
scroll_progress = (bar_position + direction) / (max_bar_height - 1)
return math.max(math.floor(scroll_progress * max_down_scroll), max_down_scroll)
end
local function scroll_down(scaled)
if scroll_offset > max_down_scroll then
if scaled then
scroll_offset = scaled_bar_scroll(1)
else
scroll_offset = scroll_offset - 1
end
update_positions()
end
end
local function scroll_up(scaled)
if scroll_offset < 0 then
if scaled then
scroll_offset = scaled_bar_scroll(-1)
else
scroll_offset = scroll_offset + 1
end
update_positions()
end
end
function e.on_added(id, child)
table.insert(list, { id = id, e = child, y = 0, h = child.get_height() })
update_positions()
end
function e.on_removed(id)
for idx, elem in ipairs(list) do
if elem.id == id then
table.remove(list, idx)
update_positions()
return
end
end
end
e.on_focused = draw_bar
e.on_unfocused = draw_bar
function e.on_child_focused(child)
for i = 1, #list do
local item = list[i]
if item.e == child then
if (item.y + scroll_offset) <= 0 then
scroll_offset = 1 - item.y
update_positions()
draw_bar()
elseif (item.y + scroll_offset) == 1 then
elseif ((item.h + item.y - 1) + scroll_offset) > e.frame.h then
scroll_offset = 1 - ((item.h + item.y) - e.frame.h)
update_positions()
draw_bar()
end
return
end
end
end
function e.handle_mouse(event)
if e.enabled then
if event.type == MOUSE_CLICK.TAP then
if event.current.x == e.frame.w then
if event.current.y == 1 or event.current.y < bar_bounds[1] then
scroll_up()
if event.current.y == 1 then
draw_arrows(1)
if args.nav_active ~= nil then tcd.dispatch(0.25, function () draw_arrows(0) end) end
end
elseif event.current.y == e.frame.h or event.current.y > bar_bounds[2] then
scroll_down()
if event.current.y == e.frame.h then
draw_arrows(-1)
if args.nav_active ~= nil then tcd.dispatch(0.25, function () draw_arrows(0) end) end
end
end
end
elseif event.type == MOUSE_CLICK.DOWN then
if event.current.x == e.frame.w then
if event.current.y == 1 or event.current.y < bar_bounds[1] then
scroll_up()
if event.current.y == 1 then draw_arrows(1) end
elseif event.current.y == e.frame.h or event.current.y > bar_bounds[2] then
scroll_down()
if event.current.y == e.frame.h then draw_arrows(-1) end
else
holding_bar = true
bar_grip_pos = event.current.y - bar_bounds[1]
mouse_last_y = event.current.y
end
end
elseif event.type == MOUSE_CLICK.UP then
holding_bar = false
draw_arrows(0)
elseif event.type == MOUSE_CLICK.DRAG then
if holding_bar then
if event.current.y > (1 + bar_grip_pos) and event.current.y <= ((e.frame.h - bar_height) + bar_grip_pos) then
if event.current.y < mouse_last_y then
scroll_up(bar_is_scaled)
elseif event.current.y > mouse_last_y then
scroll_down(bar_is_scaled)
end
mouse_last_y = event.current.y
end
end
elseif event.type == MOUSE_CLICK.SCROLL_DOWN then
scroll_down()
elseif event.type == MOUSE_CLICK.SCROLL_UP then
scroll_up()
end
end
end
function e.handle_key(event)
if event.type == KEY_CLICK.DOWN or event.type == KEY_CLICK.HELD then
if event.key == keys.up then
scroll_up()
elseif event.key == keys.down then
scroll_down()
elseif event.key == keys.home then
scroll_offset = 0
update_positions()
elseif event.key == keys["end"] then
scroll_offset = max_down_scroll
update_positions()
end
end
end
function e.redraw()
draw_arrows(0)
draw_bar()
end
local ListBox, id = e.complete(true)
return ListBox, id
end
