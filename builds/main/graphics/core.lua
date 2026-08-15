
local events  = require("graphics.events")
local flasher = require("graphics.flasher")
local core = {}
core.version = "2.4.12"
core.flasher = flasher
core.events = events
core.ALIGN = { LEFT = 1, CENTER = 2, RIGHT = 3 }
function core.border(width, color, even)
return { width = width, color = color, even = even or false }
end
function core.gframe(x, y, w, h)
return { x = x, y = y, w = w, h = h }
end
colors._INHERIT = 3
function core.cpair(a, b)
return {
color_a = a, color_b = b, blit_a = colors.toBlit(a), blit_b = colors.toBlit(b),
fgd = a, bkg = b, blit_fgd = colors.toBlit(a), blit_bkg = colors.toBlit(b)
}
end
function core.pipe(x1, y1, x2, y2, color, thin, align_tr)
return {
x1 = x1,
y1 = y1,
x2 = x2,
y2 = y2,
w = math.abs(x2 - x1) + 1,
h = math.abs(y2 - y1) + 1,
color = color,
thin = thin or false,
align_tr = align_tr or false
}
end
function core.extract_assert_msg(msg)
return string.sub(msg, (string.find(msg, "@") or 0) + 1)
end
function core.new_ifield(e, max_len, fg_bg, dis_fg_bg, align_right)
local self = {
frame_start = 1,
visible_text = e.value,
cursor_pos = string.len(e.value) + 1,
align_offset = 0,
selected_all = false
}
local function _update_visible()
self.visible_text = string.sub(e.value, self.frame_start, self.frame_start + math.min(string.len(e.value), e.frame.w) - 1)
end
local function _try_lshift()
if self.frame_start > 1 then
self.frame_start = self.frame_start - 1
return true
end
end
local function _try_rshift()
if (self.frame_start + e.frame.w - 1) <= string.len(e.value) then
self.frame_start = self.frame_start + 1
return true
end
end
local public = {}
function public.censor(censor)
if type(censor) == "string" and string.len(censor) == 1 then
self.censor = censor
else self.censor = nil end
public.show()
end
function public.show()
_update_visible()
if e.enabled then
e.w_set_bkg(fg_bg.bkg)
e.w_set_fgd(fg_bg.fgd)
elseif dis_fg_bg ~= nil then
e.w_set_bkg(dis_fg_bg.bkg)
e.w_set_fgd(dis_fg_bg.fgd)
end
e.w_set_cur(1, 1)
e.w_write(string.rep(" ", e.frame.w))
e.w_set_cur(1, 1)
local function _write(align_r)
if align_r and string.len(self.visible_text) <=e.frame.w then
self.align_offset = (e.frame.w - string.len(self.visible_text))
e.w_set_cur((e.frame.w - string.len(self.visible_text)) + 1, 1)
end
if self.censor then
e.w_write(string.rep(self.censor, string.len(self.visible_text)))
else
e.w_write(self.visible_text)
end
end
if e.is_focused() and e.enabled then
if self.selected_all then
e.w_set_bkg(fg_bg.fgd)
e.w_set_fgd(fg_bg.bkg)
_write()
elseif self.cursor_pos >= (string.len(self.visible_text) + 1) then
_write()
e.w_set_fgd(colors.lightGray)
e.w_write("_")
else
local a, b = "", ""
if self.cursor_pos <= string.len(self.visible_text) then
a = fg_bg.blit_bkg
b = fg_bg.blit_fgd
end
local b_fgd = string.rep(fg_bg.blit_fgd, self.cursor_pos - 1) .. a .. string.rep(fg_bg.blit_fgd, string.len(self.visible_text) - self.cursor_pos)
local b_bkg = string.rep(fg_bg.blit_bkg, self.cursor_pos - 1) .. b .. string.rep(fg_bg.blit_bkg, string.len(self.visible_text) - self.cursor_pos)
if self.censor then
e.w_blit(string.rep(self.censor, string.len(self.visible_text)), b_fgd, b_bkg)
else
e.w_blit(self.visible_text, b_fgd, b_bkg)
end
end
else
self.selected_all = false
_write(align_right)
end
end
function public.get_cursor_align_shift(x)
return math.max(0, x - self.align_offset)
end
function public.move_cursor(x)
self.selected_all = false
if x <= 0 then
self.cursor_pos = string.len(self.visible_text) + 1
else
self.cursor_pos = math.min(x, string.len(self.visible_text) + 1)
end
public.show()
end
function public.select_all()
self.selected_all = true
public.show()
end
function public.set_value(val)
e.value = string.sub(val, 1, math.min(max_len, string.len(val)))
public.nav_end()
end
function public.try_insert_char(char)
if string.len(e.value) >= max_len then return end
if self.selected_all then
self.selected_all = false
self.cursor_pos = 2
self.frame_start = 1
e.value = char
public.show()
else
e.value = string.sub(e.value, 1, self.frame_start + self.cursor_pos - 2) .. char .. string.sub(e.value, self.frame_start + self.cursor_pos - 1, string.len(e.value))
_update_visible()
public.nav_right()
end
end
function public.backspace()
if self.selected_all then
self.selected_all = false
e.value = ""
self.cursor_pos = 1
self.frame_start = 1
public.show()
else
if self.frame_start + self.cursor_pos > 2 then
e.value = string.sub(e.value, 1, self.frame_start + self.cursor_pos - 3) .. string.sub(e.value, self.frame_start + self.cursor_pos - 1, string.len(e.value))
if self.cursor_pos > 1 then
self.cursor_pos = self.cursor_pos - 1
public.show()
elseif _try_lshift() then public.show() end
end
end
end
function public.nav_left()
if self.cursor_pos > 1 then
self.cursor_pos = self.cursor_pos - 1
public.show()
elseif _try_lshift() then public.show() end
end
function public.nav_right()
if self.cursor_pos < math.min(string.len(self.visible_text) + 1, e.frame.w) then
self.cursor_pos = self.cursor_pos + 1
public.show()
elseif _try_rshift() then public.show() end
end
function public.nav_start()
self.cursor_pos = 1
self.frame_start = 1
public.show()
end
function public.nav_end()
self.frame_start = math.max(1, string.len(e.value) - e.frame.w + 2)
_update_visible()
self.cursor_pos = string.len(self.visible_text) + 1
public.show()
end
return public
end
return core
