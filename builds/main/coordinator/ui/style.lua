
local util        = require("scada-common.util")
local core        = require("graphics.core")
local themes      = require("graphics.themes")
local coordinator = require("coordinator.coordinator")
local style = {}
local cpair = core.cpair
local config = coordinator.config
style.fp_theme = themes.sandstone
style.fp = themes.get_fp_style(style.fp_theme)
style.led_grn = cpair(colors.green, colors.green_off)
local smooth_stone = {
text = colors.black,
text_inv = colors.white,
label = colors.gray,
label_dark = colors.gray,
disabled = colors.lightGray,
bg = colors.lightGray,
checkbox_bg = colors.black,
accent_light = colors.white,
accent_dark = colors.gray,
fuel_color = colors.black,
header = cpair(colors.white, colors.gray),
text_fg = cpair(colors.black, colors._INHERIT),
label_fg = cpair(colors.gray, colors._INHERIT),
disabled_fg = cpair(colors.lightGray, colors._INHERIT),
highlight_box = cpair(colors.black, colors.white),
highlight_box_bright = cpair(colors.black, colors.white),
field_box = cpair(colors.black, colors.white),
colors = themes.smooth_stone.colors,
color_modes = themes.smooth_stone.color_modes
}
local deepslate = {
text = colors.white,
text_inv = colors.black,
label = colors.lightGray,
label_dark = colors.gray,
disabled = colors.gray,
bg = colors.black,
checkbox_bg = colors.gray,
accent_light = colors.gray,
accent_dark = colors.lightGray,
fuel_color = colors.lightGray,
header = cpair(colors.white, colors.gray),
text_fg = cpair(colors.white, colors._INHERIT),
label_fg = cpair(colors.lightGray, colors._INHERIT),
disabled_fg = cpair(colors.gray, colors._INHERIT),
highlight_box = cpair(colors.white, colors.gray),
highlight_box_bright = cpair(colors.black, colors.lightGray),
field_box = cpair(colors.white, colors.gray),
colors = themes.deepslate.colors,
color_modes = themes.deepslate.color_modes
}
style.theme = smooth_stone
function style.set_themes(main, fp, color_mode)
local colorblind = color_mode ~= themes.COLOR_MODE.STANDARD and color_mode ~= themes.COLOR_MODE.STD_ON_BLACK
local gray_ind_off = color_mode == themes.COLOR_MODE.STANDARD or color_mode == themes.COLOR_MODE.BLUE_IND
style.ind_bkg = colors.gray
style.fp_ind_bkg = util.trinary(gray_ind_off, colors.gray, colors.black)
style.ind_hi_box_bg = util.trinary(gray_ind_off, colors.gray, colors.black)
if main == themes.UI_THEME.SMOOTH_STONE then
style.theme = smooth_stone
style.ind_bkg = util.trinary(gray_ind_off, colors.gray, colors.black)
elseif main == themes.UI_THEME.DEEPSLATE then
style.theme = deepslate
style.ind_hi_box_bg = util.trinary(gray_ind_off, colors.lightGray, colors.black)
end
style.colorblind = colorblind
style.root = cpair(style.theme.text, style.theme.bg)
style.label = cpair(style.theme.label, style.theme.bg)
style.hc_text = cpair(style.theme.text, style.theme.text_inv)
style.text_colors = cpair(style.theme.text, style.theme.bg)
style.lu_colors = cpair(style.theme.label, style.theme.label)
style.lu_colors_dark = cpair(style.theme.label_dark, style.theme.label_dark)
style.ind_grn = cpair(util.trinary(colorblind, colors.blue, colors.green), style.ind_bkg)
style.ind_yel = cpair(colors.yellow, style.ind_bkg)
style.ind_red = cpair(colors.red, style.ind_bkg)
style.ind_wht = cpair(colors.white, style.ind_bkg)
if fp == themes.FP_THEME.SANDSTONE then
style.fp_theme = themes.sandstone
elseif fp == themes.FP_THEME.BASALT then
style.fp_theme = themes.basalt
end
style.fp = themes.get_fp_style(style.fp_theme)
end
style.wh_gray = cpair(colors.white, colors.gray)
style.bw_fg_bg = cpair(colors.black, colors.white)
style.hzd_fg_bg  = style.wh_gray
style.dis_colors = cpair(colors.white, colors.lightGray)
style.lg_gray = cpair(colors.lightGray, colors.gray)
style.lg_white = cpair(colors.lightGray, colors.white)
style.gray_white = cpair(colors.gray, colors.white)
style.reactor = {
states = {
{ color = cpair(colors.black, colors.yellow), text = "PLC 离线" },
{ color = cpair(colors.black, colors.orange), text = "未成形" },
{ color = cpair(colors.black, colors.orange), text = "PLC 故障" },
{ color = cpair(colors.white, colors.gray),   text = "已禁用" },
{ color = cpair(colors.black, colors.green),  text = "运行中" },
{ color = cpair(colors.black, colors.red),    text = "已急停" },
{ color = cpair(colors.black, colors.red),    text = "强制禁用" }
}
}
style.boiler = {
states = {
{ color = cpair(colors.black, colors.yellow), text = "离线" },
{ color = cpair(colors.black, colors.orange), text = "未成形" },
{ color = cpair(colors.black, colors.orange), text = "RTU 故障" },
{ color = cpair(colors.white, colors.gray),   text = "待机" },
{ color = cpair(colors.black, colors.green),  text = "运行中" }
}
}
style.turbine = {
states = {
{ color = cpair(colors.black, colors.yellow), text = "离线" },
{ color = cpair(colors.black, colors.orange), text = "未成形" },
{ color = cpair(colors.black, colors.orange), text = "RTU 故障" },
{ color = cpair(colors.white, colors.gray),   text = "待机" },
{ color = cpair(colors.black, colors.green),  text = "运行中" },
{ color = cpair(colors.black, colors.red),    text = "跳闸" }
}
}
style.dtank = {
states = {
{ color = cpair(colors.black, colors.yellow), text = "离线" },
{ color = cpair(colors.black, colors.orange), text = "未成形" },
{ color = cpair(colors.black, colors.orange), text = "RTU 故障" },
{ color = cpair(colors.black, colors.green),  text = "在线" },
{ color = cpair(colors.black, colors.yellow), text = "低液位" },
{ color = cpair(colors.black, colors.green),  text = "已注满" }
}
}
style.ess = {
states = {
{ color = cpair(colors.black, colors.yellow), text = "离线" },
{ color = cpair(colors.black, colors.orange), text = "未成形" },
{ color = cpair(colors.black, colors.orange), text = "RTU 故障" },
{ color = cpair(colors.black, colors.green),  text = "在线" },
{ color = cpair(colors.black, colors.yellow), text = "低充能" },
{ color = cpair(colors.black, colors.yellow), text = "高充能" }
}
}
style.sps = {
states = {
{ color = cpair(colors.black, colors.yellow), text = "离线" },
{ color = cpair(colors.black, colors.orange), text = "未成形" },
{ color = cpair(colors.black, colors.orange), text = "RTU 故障" },
{ color = cpair(colors.white, colors.gray),   text = "待机" },
{ color = cpair(colors.black, colors.green),  text = "运行中" }
}
}
function style.get_waste()
local pu_color = util.trinary(config.GreenPuPellet, colors.green, colors.cyan)
local po_color = util.trinary(config.GreenPuPellet, colors.cyan, colors.green)
return {
states = {
{ color = cpair(colors.black, pu_color),      text = "钚" },
{ color = cpair(colors.black, po_color),      text = "钋" },
{ color = cpair(colors.black, colors.purple), text = "反物质" }
},
states_abbrv = {
{ color = cpair(colors.black, pu_color),      text = "Pu" },
{ color = cpair(colors.black, po_color),      text = "Po" },
{ color = cpair(colors.black, colors.purple), text = "AM" }
},
options = { "钚", "钋", "反物质" },
unit_opts = {
{ text = "自动", fg_bg = cpair(colors.black, colors.lightGray), active_fg_bg = cpair(colors.white, colors.gray) },
{ text = "Pu", fg_bg = cpair(colors.black, colors.lightGray), active_fg_bg = cpair(colors.black, pu_color) },
{ text = "Po", fg_bg = cpair(colors.black, colors.lightGray), active_fg_bg = cpair(colors.black, po_color) },
{ text = "AM", fg_bg = cpair(colors.black, colors.lightGray), active_fg_bg = cpair(colors.black, colors.purple) }
}
}
end
return style
