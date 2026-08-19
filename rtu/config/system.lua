local log         = require("scada-common.log")
local ppm         = require("scada-common.ppm")
local rsio        = require("scada-common.rsio")
local util        = require("scada-common.util")

local core        = require("graphics.core")
local themes      = require("graphics.themes")

local Div         = require("graphics.elements.Div")
local ListBox     = require("graphics.elements.ListBox")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")

local Checkbox    = require("graphics.elements.controls.Checkbox")
local PushButton  = require("graphics.elements.controls.PushButton")
local RadioButton = require("graphics.elements.controls.RadioButton")

local NumberField = require("graphics.elements.form.NumberField")
local TextField   = require("graphics.elements.form.TextField")

local IndLight    = require("graphics.elements.indicators.IndicatorLight")

local tri = util.trinary

local cpair = core.cpair

local RIGHT = core.ALIGN.RIGHT

local self = {
    importing_legacy = false,
    importing_any_dc = false,

    wireless = nil,         ---@type Checkbox
    wl_pref = nil,          ---@type Checkbox
    wired = nil,            ---@type Checkbox
    range = nil,            ---@type NumberField
    show_auth_key = nil,    ---@type function
    show_key_btn = nil,     ---@type PushButton
    auth_key_textbox = nil, ---@type TextBox
    auth_key_value = ""
}

local system = {}

-- create the system configuration view
---@param tool_ctl _rtu_cfg_tool_ctl
---@param main_pane MultiPane
---@param cfg_sys [ rtu_config, rtu_config, rtu_config, { [1]: string, [2]: string, [3]: any }[], function ]
---@param divs Div[]
---@param ext [ MultiPane, MultiPane, string[], function, function, function, function ]
---@param style { [string]: cpair }
function system.create(tool_ctl, main_pane, cfg_sys, divs, ext, style)
    local settings_cfg, ini_cfg, tmp_cfg, fields, load_settings = cfg_sys[1], cfg_sys[2], cfg_sys[3], cfg_sys[4], cfg_sys[5]
    local spkr_cfg, net_cfg, log_cfg, clr_cfg, summary = divs[1], divs[2], divs[3], divs[4], divs[5]
    local peri_pane, rs_pane, NEEDS_UNIT, show_peri_conns, show_rs_conns, startup, exit = ext[1], ext[2], ext[3], ext[4], ext[5], ext[6], ext[7]

    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg
    local btn_dis_fg_bg = style.btn_dis_fg_bg

    --#region Speakers

    local spkr_c = Div{parent=spkr_cfg,x=2,y=4,width=49}

    TextBox{parent=spkr_cfg,y=2,text=" 扬声器配置",fg_bg=cpair(colors.black,colors.cyan)}

    TextBox{parent=spkr_c,y=1,height=2,text="扬声器可以直接连接到此 RTU 网关，无需 RTU 机组配置条目。"}
    TextBox{parent=spkr_c,y=4,height=3,text="您可以更改扬声器音频音量。范围是 0.0 到 3.0，其中 1.0 为标准音量。"}

    local s_vol = NumberField{parent=spkr_c,y=8,width=9,max_chars=7,allow_decimal=true,default=ini_cfg.SpeakerVolume,min=0,max=3,fg_bg=bw_fg_bg}

    TextBox{parent=spkr_c,y=10,height=3,text="注意：警报正弦波为半幅，需要多个才能达到满幅。",fg_bg=g_lg_fg_bg}

    local s_vol_err = TextBox{parent=spkr_c,x=8,y=14,width=35,text="请设置音量。",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_vol()
        local vol = tonumber(s_vol.get_value())
        if vol ~= nil then
            s_vol_err.hide(true)
            tmp_cfg.SpeakerVolume = vol
            main_pane.set_value(3)
        else s_vol_err.show() end
    end

    PushButton{parent=spkr_c,y=14,text="\x1b 返回",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=spkr_c,x=44,y=14,text="下一步 \x1a",callback=submit_vol,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Network

    local net_c_1 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_2 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_3 = Div{parent=net_cfg,x=2,y=4,width=49}
    local net_c_4 = Div{parent=net_cfg,x=2,y=4,width=49}

    local net_pane = MultiPane{parent=net_cfg,y=4,panes={net_c_1,net_c_2,net_c_3,net_c_4}}

    TextBox{parent=net_cfg,y=2,text=" 网络配置",fg_bg=cpair(colors.black,colors.lightBlue)}

    TextBox{parent=net_c_1,y=1,text="请选择网络接口。"}

    local function en_dis_pref()
        if self.wireless.get_value() and self.wired.get_value() then
            self.wl_pref.enable()
        else
            self.wl_pref.set_value(self.wireless.get_value())
            self.wl_pref.disable()
        end
    end

    local function on_wired_change(_)
        en_dis_pref()
        tool_ctl.gen_modem_list()
    end

    self.wireless = Checkbox{parent=net_c_1,y=3,label="无线/末影调制解调器",default=ini_cfg.WirelessModem,box_fg_bg=cpair(colors.lightBlue,colors.black),callback=en_dis_pref}
    self.wl_pref = Checkbox{parent=net_c_1,x=30,y=3,label="优先无线",default=ini_cfg.PreferWireless,box_fg_bg=cpair(colors.lightBlue,colors.black),disable_fg_bg=g_lg_fg_bg}
    self.wired = Checkbox{parent=net_c_1,y=5,label="有线调制解调器",default=ini_cfg.WiredModem~=false,box_fg_bg=cpair(colors.lightBlue,colors.black),callback=on_wired_change}
    TextBox{parent=net_c_1,x=3,y=6,text="此接口只能连接 SCADA 计算机",fg_bg=cpair(colors.red,colors._INHERIT)}
    TextBox{parent=net_c_1,x=3,y=7,text="连接到外设会导致问题",fg_bg=g_lg_fg_bg}
    local modem_list = ListBox{parent=net_c_1,y=8,height=5,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local modem_err = TextBox{parent=net_c_1,x=8,y=14,width=35,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    en_dis_pref()

    local function submit_interfaces()
        tmp_cfg.WirelessModem = self.wireless.get_value()

        if tmp_cfg.WirelessModem and tmp_cfg.WiredModem then
            tmp_cfg.PreferWireless = self.wl_pref.get_value()
        else
            tmp_cfg.PreferWireless = tmp_cfg.WirelessModem
            self.wl_pref.set_value(tmp_cfg.PreferWireless)
        end

        if not self.wired.get_value() then
            tmp_cfg.WiredModem = false
            tool_ctl.gen_modem_list()
        end

        if not (self.wired.get_value() or self.wireless.get_value()) then
            modem_err.set_value("请选择调制解调器类型。")
            modem_err.show()
        elseif self.wired.get_value() and type(tmp_cfg.WiredModem) ~= "string" then
            modem_err.set_value("请选择有线调制解调器。")
            modem_err.show()
        else
            if tmp_cfg.WirelessModem then
                self.range.enable()
            else
                self.range.set_value(0)
                self.range.disable()
            end

            net_pane.set_value(2)
            modem_err.hide(true)
        end
    end

    PushButton{parent=net_c_1,y=14,text="\x1b 返回",callback=function()main_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_1,x=44,y=14,text="下一步 \x1a",callback=submit_interfaces,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_2,y=1,text="请在下方设置网络频道。"}
    TextBox{parent=net_c_2,y=3,height=4,text="此 SCADA 网络中每台设备的 5 个唯一命名频道（包括下方 2 个）必须相同。对于多人服务器，建议不要使用默认频道。",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_2,y=8,text="监管端频道"}
    local svr_chan = NumberField{parent=net_c_2,y=9,width=7,default=ini_cfg.SVR_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_2,x=9,y=9,height=4,text="[SVR_CHANNEL]",fg_bg=g_lg_fg_bg}
    TextBox{parent=net_c_2,y=11,text="RTU 频道"}
    local rtu_chan = NumberField{parent=net_c_2,y=12,width=7,default=ini_cfg.RTU_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_2,x=9,y=12,height=4,text="[RTU_CHANNEL]",fg_bg=g_lg_fg_bg}

    local chan_err = TextBox{parent=net_c_2,x=8,y=14,width=35,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_channels()
        local svr_c = tonumber(svr_chan.get_value())
        local rtu_c = tonumber(rtu_chan.get_value())
        if svr_c ~= nil and rtu_c ~= nil then
            tmp_cfg.SVR_Channel = svr_c
            tmp_cfg.RTU_Channel = rtu_c
            net_pane.set_value(3)
            chan_err.hide(true)
        elseif svr_c == nil then
            chan_err.set_value("请设置监管端频道。")
            chan_err.show()
        else
            chan_err.set_value("请设置 RTU 频道。")
            chan_err.show()
        end
    end

    PushButton{parent=net_c_2,y=14,text="\x1b 返回",callback=function()net_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_2,x=44,y=14,text="下一步 \x1a",callback=submit_channels,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_3,y=1,text="连接超时"}
    local timeout = NumberField{parent=net_c_3,y=2,width=7,default=ini_cfg.ConnTimeout,min=2,max=25,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_3,x=9,y=2,height=2,text="秒（默认 5）",fg_bg=g_lg_fg_bg}
    TextBox{parent=net_c_3,y=3,height=4,text="您通常不需要修改此设置。在慢速服务器上，可以增大此值，让系统在判定断线前等待更长时间。",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_3,y=8,text="信任范围（仅无线）"}
    self.range = NumberField{parent=net_c_3,y=9,width=10,default=ini_cfg.TrustedRange,min=0,max_chars=20,allow_decimal=true,fg_bg=bw_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}
    TextBox{parent=net_c_3,y=10,height=4,text="将此值设置为大于 0 可阻止与任意方向数米（方块）之外的设备进行无线连接。",fg_bg=g_lg_fg_bg}

    local n3_err = TextBox{parent=net_c_3,x=8,y=14,width=35,text="",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_ct_tr()
        local timeout_val = tonumber(timeout.get_value())
        local range_val = tonumber(self.range.get_value())

        if timeout_val == nil then
            n3_err.set_value("请设置连接超时。")
            n3_err.show()
        elseif tmp_cfg.WirelessModem and (range_val == nil) then
            n3_err.set_value("请设置信任范围。")
            n3_err.show()
        else
            tmp_cfg.ConnTimeout = timeout_val
            tmp_cfg.TrustedRange = tri(tmp_cfg.WirelessModem, range_val, 0)

            if tmp_cfg.WirelessModem then
                net_pane.set_value(4)
            else
                main_pane.set_value(4)
                tmp_cfg.AuthKey = ""
            end

            n3_err.hide(true)
        end
    end

    PushButton{parent=net_c_3,y=14,text="\x1b 返回",callback=function()net_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_3,x=44,y=14,text="下一步 \x1a",callback=submit_ct_tr,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_4,y=1,height=2,text="可选：请在下方设置设施认证密钥。请勿使用您的任何密码。"}
    TextBox{parent=net_c_4,y=4,height=6,text="这可以验证消息的真实性，因此用于多人服务器上的无线安全。如果任何设备设置了密钥，同一无线网络上的所有设备必须使用相同的密钥。这会产生一些额外计算（可能降低速度）。",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_4,y=11,text="认证密钥（仅无线，有线不使用）"}
    local key, _ = TextField{parent=net_c_4,y=12,max_len=64,value=ini_cfg.AuthKey,width=32,height=1,fg_bg=bw_fg_bg}

    local function censor_key(enable) key.censor(tri(enable, "*", nil)) end

    local hide_key = Checkbox{parent=net_c_4,x=34,y=12,label="隐藏",box_fg_bg=cpair(colors.lightBlue,colors.black),callback=censor_key}

    hide_key.set_value(true)
    censor_key(true)

    local key_err = TextBox{parent=net_c_4,x=8,y=14,width=35,text="密钥至少需要 8 个字符。",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_auth()
        local v = key.get_value()
        if string.len(v) == 0 or string.len(v) >= 8 then
            tmp_cfg.AuthKey = key.get_value()
            main_pane.set_value(4)
            key_err.hide(true)
        else key_err.show() end
    end

    PushButton{parent=net_c_4,y=14,text="\x1b 返回",callback=function()net_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_4,x=44,y=14,text="下一步 \x1a",callback=submit_auth,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Logging

    local log_c_1 = Div{parent=log_cfg,x=2,y=4,width=49}

    TextBox{parent=log_cfg,y=2,text=" 日志配置",fg_bg=cpair(colors.black,colors.pink)}

    TextBox{parent=log_c_1,y=1,text="请在下方配置日志。"}

    TextBox{parent=log_c_1,y=3,text="日志文件模式"}
    local mode = RadioButton{parent=log_c_1,y=4,default=ini_cfg.LogMode+1,options={"启动时追加","启动时替换"},radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.pink}

    TextBox{parent=log_c_1,y=7,text="日志文件路径"}
    local path = TextField{parent=log_c_1,y=8,width=49,height=1,value=ini_cfg.LogPath,max_len=128,fg_bg=bw_fg_bg}

    local en_dbg = Checkbox{parent=log_c_1,y=10,default=ini_cfg.LogDebug,label="启用日志调试消息",box_fg_bg=cpair(colors.pink,colors.black)}
    TextBox{parent=log_c_1,x=3,y=11,height=2,text="这会产生大得多的日志文件。最好仅在出现问题时使用。",fg_bg=g_lg_fg_bg}

    local path_err = TextBox{parent=log_c_1,x=8,y=14,width=35,text="请提供日志文件路径。",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_log()
        if path.get_value() ~= "" then
            path_err.hide(true)
            tmp_cfg.LogMode = mode.get_value() - 1
            tmp_cfg.LogPath = path.get_value()
            tmp_cfg.LogDebug = en_dbg.get_value()
            tool_ctl.color_apply.hide(true)
            tool_ctl.color_next.show()
            main_pane.set_value(5)
        else path_err.show() end
    end

    PushButton{parent=log_c_1,y=14,text="\x1b 返回",callback=function()main_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=log_c_1,x=44,y=14,text="下一步 \x1a",callback=submit_log,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Color Options

    local clr_c_1 = Div{parent=clr_cfg,x=2,y=4,width=49}
    local clr_c_2 = Div{parent=clr_cfg,x=2,y=4,width=49}
    local clr_c_3 = Div{parent=clr_cfg,x=2,y=4,width=49}
    local clr_c_4 = Div{parent=clr_cfg,x=2,y=4,width=49}

    local clr_pane = MultiPane{parent=clr_cfg,y=4,panes={clr_c_1,clr_c_2,clr_c_3,clr_c_4}}

    TextBox{parent=clr_cfg,y=2,text=" 颜色配置",fg_bg=cpair(colors.black,colors.magenta)}

    TextBox{parent=clr_c_1,y=1,height=2,text="您可以在此选择前面板的颜色主题。"}
    TextBox{parent=clr_c_1,y=4,height=2,text="点击下方的“辅助功能”以访问色盲辅助选项。",fg_bg=g_lg_fg_bg}

    TextBox{parent=clr_c_1,y=7,text="前面板主题"}
    local fp_theme = RadioButton{parent=clr_c_1,y=8,default=ini_cfg.FrontPanelTheme,options=themes.FP_THEME_NAMES,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.magenta}

    TextBox{parent=clr_c_2,y=1,height=6,text="本系统大量使用颜色来区分正常与异常，部分指示灯使用多种颜色。通过选择下方的模式，指示灯将按所示方式变化。对于非标准模式，多于两种颜色的指示灯将被拆分。"}

    TextBox{parent=clr_c_2,x=21,y=7,text="预览"}
    local _ = IndLight{parent=clr_c_2,x=21,y=8,label="正常",colors=cpair(colors.black,colors.green)}
    _ = IndLight{parent=clr_c_2,x=21,y=9,label="警告",colors=cpair(colors.black,colors.yellow)}
    _ = IndLight{parent=clr_c_2,x=21,y=10,label="故障",colors=cpair(colors.black,colors.red)}
    local b_off = IndLight{parent=clr_c_2,x=21,y=11,label="关闭",colors=cpair(colors.black,colors.black),hidden=true}
    local g_off = IndLight{parent=clr_c_2,x=21,y=11,label="关闭",colors=cpair(colors.gray,colors.gray),hidden=true}

    local function recolor(value)
        local c = themes.smooth_stone.color_modes[value]

        if value == themes.COLOR_MODE.STANDARD or value == themes.COLOR_MODE.BLUE_IND then
            b_off.hide()
            g_off.show()
        else
            g_off.hide()
            b_off.show()
        end

        if #c == 0 then
            for i = 1, #style.colors do term.setPaletteColor(style.colors[i].c, style.colors[i].hex) end
        else
            term.setPaletteColor(colors.green, c[1].hex)
            term.setPaletteColor(colors.yellow, c[2].hex)
            term.setPaletteColor(colors.red, c[3].hex)
        end
    end

    TextBox{parent=clr_c_2,y=7,width=10,text="颜色模式"}
    local c_mode = RadioButton{parent=clr_c_2,y=8,default=ini_cfg.ColorMode,options=themes.COLOR_MODE_NAMES,callback=recolor,radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.magenta}

    TextBox{parent=clr_c_2,x=21,y=13,height=2,width=18,text="注意：具体颜色随主题而异。",fg_bg=g_lg_fg_bg}

    PushButton{parent=clr_c_2,x=44,y=14,min_width=6,text="完成",callback=function()clr_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    local function back_from_colors()
        main_pane.set_value(tri(tool_ctl.jumped_to_color, 1, 4))
        tool_ctl.jumped_to_color = false
        recolor(1)
    end

    local function show_access()
        clr_pane.set_value(2)
        recolor(c_mode.get_value())
    end

    local function submit_colors()
        tmp_cfg.FrontPanelTheme = fp_theme.get_value()
        tmp_cfg.ColorMode = c_mode.get_value()

        if tool_ctl.jumped_to_color then
            settings.set("FrontPanelTheme", tmp_cfg.FrontPanelTheme)
            settings.set("ColorMode", tmp_cfg.ColorMode)

            if settings.save("/rtu.settings") then
                load_settings(settings_cfg, true)
                load_settings(ini_cfg)
                clr_pane.set_value(3)
            else
                clr_pane.set_value(4)
            end
        else
            tool_ctl.gen_summary(tmp_cfg)
            tool_ctl.viewing_config = false
            self.importing_legacy = false
            tool_ctl.settings_apply.show()
            tool_ctl.settings_confirm.hide(true)
            main_pane.set_value(6)
        end
    end

    PushButton{parent=clr_c_1,y=14,text="\x1b 返回",callback=back_from_colors,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=clr_c_1,x=8,y=14,min_width=15,text="辅助功能",callback=show_access,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    tool_ctl.color_next = PushButton{parent=clr_c_1,x=44,y=14,text="下一步 \x1a",callback=submit_colors,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    tool_ctl.color_apply = PushButton{parent=clr_c_1,x=43,y=14,min_width=7,text="应用",callback=submit_colors,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    tool_ctl.color_apply.hide(true)

    TextBox{parent=clr_c_3,y=1,text="设置已保存！"}
    PushButton{parent=clr_c_3,y=14,min_width=6,text="退出",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}
    PushButton{parent=clr_c_3,x=44,y=14,min_width=6,text="主页",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=clr_c_4,y=1,height=5,text="保存设置文件失败。\n\n可能是存储空间不足，或服务器文件权限禁止写入。"}
    PushButton{parent=clr_c_4,y=14,min_width=6,text="退出",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}
    PushButton{parent=clr_c_4,x=44,y=14,min_width=6,text="主页",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Summary and Saving

    local sum_c_1 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_2 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_3 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_4 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_5 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_6 = Div{parent=summary,x=2,y=4,width=49}
    local sum_c_7 = Div{parent=summary,x=2,y=4,width=49}

    local sum_pane = MultiPane{parent=summary,y=4,panes={sum_c_1,sum_c_2,sum_c_3,sum_c_4,sum_c_5,sum_c_6,sum_c_7}}

    TextBox{parent=summary,y=2,text=" 汇总",fg_bg=cpair(colors.black,colors.green)}

    local setting_list = ListBox{parent=sum_c_1,y=1,height=12,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function back_from_settings()
        if tool_ctl.viewing_config or self.importing_legacy then
            if self.importing_legacy and self.importing_any_dc then
                sum_pane.set_value(7)
            else
                self.importing_legacy = false
                tool_ctl.go_home()
            end

            tool_ctl.viewing_config = false
        else main_pane.set_value(5) end
    end

    ---@param element graphics_element
    ---@param data any
    local function try_set(element, data)
        if data ~= nil then element.set_value(data) end
    end

    ---@param exclude_conns boolean? true to exclude saving peripheral/redstone connections
    local function save_and_continue(exclude_conns)
        for _, field in ipairs(fields) do
            local k, v = field[1], tmp_cfg[field[1]]
            if not (exclude_conns and (k == "Peripherals" or k == "Redstone")) then
                if v == nil then settings.unset(k) else settings.set(k, v) end
            end
        end

        -- always set these if missing
        if settings.get("Peripherals") == nil then settings.set("Peripherals", {}) end
        if settings.get("Redstone") == nil then settings.set("Redstone", {}) end

        if settings.save("/rtu.settings") then
            load_settings(settings_cfg, true)
            load_settings(ini_cfg)

            try_set(s_vol, ini_cfg.SpeakerVolume)
            try_set(self.wireless, ini_cfg.WirelessModem)
            try_set(self.wired, ini_cfg.WiredModem ~= false)
            try_set(self.wl_pref, ini_cfg.PreferWireless)
            try_set(svr_chan, ini_cfg.SVR_Channel)
            try_set(rtu_chan, ini_cfg.RTU_Channel)
            try_set(timeout, ini_cfg.ConnTimeout)
            try_set(self.range, ini_cfg.TrustedRange)
            try_set(key, ini_cfg.AuthKey)
            try_set(mode, ini_cfg.LogMode)
            try_set(path, ini_cfg.LogPath)
            try_set(en_dbg, ini_cfg.LogDebug)
            try_set(fp_theme, ini_cfg.FrontPanelTheme)
            try_set(c_mode, ini_cfg.ColorMode)

            if not exclude_conns then
                tmp_cfg.Peripherals = tool_ctl.deep_copy_peri(ini_cfg.Peripherals)
                tmp_cfg.Redstone = tool_ctl.deep_copy_rs(ini_cfg.Redstone)

                tool_ctl.update_peri_list()
            end

            tool_ctl.dev_cfg.enable()
            tool_ctl.rs_cfg.enable()
            tool_ctl.view_gw_cfg.enable()

            if self.importing_legacy then
                self.importing_legacy = false
                sum_pane.set_value(5)
            else sum_pane.set_value(4) end
        else sum_pane.set_value(6) end
    end

    PushButton{parent=sum_c_1,y=14,text="\x1b 返回",callback=back_from_settings,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    self.show_key_btn = PushButton{parent=sum_c_1,x=8,y=14,min_width=17,text="显示认证密钥",callback=function()self.show_auth_key()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    tool_ctl.settings_apply = PushButton{parent=sum_c_1,x=43,y=14,min_width=7,text="应用",callback=function()save_and_continue(true)end,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}
    tool_ctl.settings_confirm = PushButton{parent=sum_c_1,x=41,y=14,min_width=9,text="确定",callback=function()sum_pane.set_value(2)end,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}
    tool_ctl.settings_confirm.hide()

    TextBox{parent=sum_c_2,y=1,text="将导入以下外设："}
    local peri_import_list = ListBox{parent=sum_c_2,y=3,height=10,width=49,scroll_height=1000,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    PushButton{parent=sum_c_2,y=14,text="\x1b 返回",callback=function()sum_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_2,x=41,y=14,min_width=9,text="确定",callback=function()sum_pane.set_value(3)end,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=sum_c_3,y=1,text="将导入以下红石条目："}
    local rs_import_list = ListBox{parent=sum_c_3,y=3,height=10,width=49,scroll_height=1000,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    PushButton{parent=sum_c_3,y=14,text="\x1b 返回",callback=function()sum_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_3,x=43,y=14,min_width=7,text="应用",callback=save_and_continue,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    local function jump_peri_conns()
        tool_ctl.go_home()
        show_peri_conns()
    end

    local function jump_rs_conns()
        tool_ctl.go_home()
        show_rs_conns()
    end

    TextBox{parent=sum_c_4,y=1,text="设置已保存！"}
    TextBox{parent=sum_c_4,y=3,height=4,text="如果您尚未配置连接到该 RTU 网关的任何外设或红石，或曾添加、移除或修改过它们，请记得进行配置。"}
    PushButton{parent=sum_c_4,y=8,min_width=24,text="外设连接",callback=jump_peri_conns,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_4,y=10,min_width=22,text="红石连接",callback=jump_rs_conns,fg_bg=cpair(colors.black,colors.yellow),active_fg_bg=btn_act_fg_bg}

    if tool_ctl.ask_config then
        PushButton{parent=sum_c_4,y=14,min_width=16,text="继续启动",callback=exit,fg_bg=cpair(colors.black,colors.lightBlue),active_fg_bg=btn_act_fg_bg}
    else
        PushButton{parent=sum_c_4,y=14,min_width=9,text="启动",callback=startup,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}
    end

    PushButton{parent=sum_c_4,x=44,y=14,min_width=6,text="主页",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=sum_c_5,y=1,height=2,text="旧版 config.lua 文件将被删除，然后配置程序将退出。"}

    local function delete_legacy()
        fs.delete("/rtu/config.lua")
        exit()
    end

    PushButton{parent=sum_c_5,y=14,min_width=8,text="取消",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_5,x=44,y=14,min_width=6,text="确定",callback=delete_legacy,fg_bg=cpair(colors.black,colors.green),active_fg_bg=cpair(colors.white,colors.gray)}

    TextBox{parent=sum_c_6,y=1,height=5,text="保存设置文件失败。\n\n可能是存储空间不足，或服务器文件权限禁止写入。"}
    PushButton{parent=sum_c_6,y=14,min_width=6,text="主页",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_6,x=44,y=14,min_width=6,text="退出",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    TextBox{parent=sum_c_7,y=1,height=8,text="警告！\n\n您旧配置文件中的部分设备当前未连接。如果设备未连接，则无法正确验证选项。请连接您的设备后重试，或在不验证这些条目设置的情况下完成导入。"}
    TextBox{parent=sum_c_7,y=10,height=3,text="之后，请（a）编辑并保存当前未连接设备的条目以正确配置，或（b）删除这些条目。"}
    PushButton{parent=sum_c_7,y=14,text="\x1b 返回",callback=function()tool_ctl.go_home()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_7,x=41,y=14,min_width=9,text="确定",callback=function()sum_pane.set_value(1)end,fg_bg=cpair(colors.black,colors.orange),active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Tool Functions

    -- load a legacy config file
    function tool_ctl.load_legacy()
        local config = require("rtu.config")

        self.importing_any_dc = false

        tmp_cfg.SpeakerVolume = config.SOUNDER_VOLUME or 1
        tmp_cfg.SVR_Channel = config.SVR_CHANNEL
        tmp_cfg.RTU_Channel = config.RTU_CHANNEL
        tmp_cfg.ConnTimeout = config.COMMS_TIMEOUT
        tmp_cfg.TrustedRange = config.TRUSTED_RANGE
        tmp_cfg.AuthKey = config.AUTH_KEY or ""
        tmp_cfg.LogMode = config.LOG_MODE
        tmp_cfg.LogPath = config.LOG_PATH
        tmp_cfg.LogDebug = config.LOG_DEBUG or false
        tmp_cfg.Peripherals = {}
        tmp_cfg.Redstone = {}

        local mounts = ppm.list_mounts()

        peri_import_list.remove_all()
        for _, entry in ipairs(config.RTU_DEVICES) do
            local for_facility = entry.for_reactor == 0
            local ini_unit = tri(for_facility, nil, entry.for_reactor)

            local def = { name = entry.name, unit = ini_unit, index = entry.index }
            local mount = mounts[def.name]

            local status = "  \x13 未连接，请稍后重新配置"
            local color = colors.orange

            if mount ~= nil then
                -- lets make sure things are valid
                local unit, index, err = nil, nil, false
                local u, idx = def.unit, def.index

                if util.table_contains(NEEDS_UNIT, mount.type) then
                    if (mount.type == "dynamicValve" or mount.type == "environmentDetector" or mount.type == "environment_detector") and for_facility then
                        -- skip
                    elseif not (util.is_int(u) and u > 0 and u < 5) then
                        err = true
                    else unit = u end
                end

                if mount.type == "boilerValve" then
                    if not (idx == 1 or idx == 2) then
                        err = true
                    else index = idx end
                elseif mount.type == "turbineValve" then
                    if not (idx == 1 or idx == 2 or idx == 3) then
                        err = true
                    else index = idx end
                elseif mount.type == "dynamicValve" and for_facility then
                    if not (util.is_int(idx) and idx > 0 and idx < 5) then
                        err = true
                    else index = idx end
                elseif mount.type == "dynamicValve" then
                    index = 1
                elseif mount.type == "environmentDetector" or mount.type == "environment_detector" then
                    if not (util.is_int(idx) and idx > 0) then
                        err = true
                    else index = idx end
                end

                if err then
                    status = "  \x13 无效，请稍后重新配置"
                else
                    def.index = index
                    def.unit = unit
                    status = "  \x04 已验证"
                    color = colors.green
                end
            else self.importing_any_dc = true end

            table.insert(tmp_cfg.Peripherals, def)

            local desc = "  \x1a "

            if type(def.index) == "number" then
                desc = desc .. "#" .. def.index .. " "
            end

            if type(def.unit) == "number" then
                desc = desc .. "用于机组 " .. def.unit
            else
                desc = desc .. "用于设施"
            end

            local line = Div{parent=peri_import_list,height=3}
            TextBox{parent=line,y=1,text="@ "..def.name,fg_bg=cpair(colors.black,colors.white)}
            TextBox{parent=line,y=2,text=status,fg_bg=cpair(color,colors.white)}
            TextBox{parent=line,y=3,text=desc,fg_bg=cpair(colors.gray,colors.white)}
        end

        rs_import_list.remove_all()
        for _, entry in ipairs(config.RTU_REDSTONE) do
            if entry.for_reactor == 0 then entry.for_reactor = nil end
            for _, io_entry in ipairs(entry.io) do
                local def = { unit = entry.for_reactor, port = io_entry.port, side = io_entry.side, color = io_entry.bundled_color }
                table.insert(tmp_cfg.Redstone, def)

                local name = rsio.to_string(def.port)
                local io_dir = tri(rsio.get_io_dir(def.port) == rsio.IO_DIR.IN, "\x1a", "\x1b")
                local conn = def.side
                local unit = "设施"

                if def.unit then unit = "机组 " .. def.unit end
                if def.color ~= nil then conn = def.side .. "/" .. rsio.color_name(def.color) end

                local line = Div{parent=rs_import_list,height=1}
                TextBox{parent=line,y=1,width=1,text=io_dir,fg_bg=cpair(colors.lightGray,colors.white)}
                TextBox{parent=line,x=2,y=1,width=14,text=name}
                TextBox{parent=line,x=18,y=1,width=string.len(conn),text=conn,fg_bg=cpair(colors.gray,colors.white)}
                TextBox{parent=line,x=40,y=1,text=unit,fg_bg=cpair(colors.gray,colors.white)}
            end
        end

        tool_ctl.gen_summary(tmp_cfg)
        if self.importing_any_dc then sum_pane.set_value(7) else sum_pane.set_value(1) end
        main_pane.set_value(6)
        tool_ctl.settings_apply.hide(true)
        tool_ctl.settings_confirm.show()
        self.importing_legacy = true
    end

    -- go back to the home page
    function tool_ctl.go_home()
        tool_ctl.viewing_config = false
        self.importing_legacy = false
        self.importing_any_dc = false

        main_pane.set_value(1)
        net_pane.set_value(1)
        clr_pane.set_value(1)
        sum_pane.set_value(1)
        peri_pane.set_value(1)
        rs_pane.set_value(1)
    end

    -- expose the auth key on the summary page
    function self.show_auth_key()
        self.show_key_btn.disable()
        self.auth_key_textbox.set_value(self.auth_key_value)
    end

    -- generate the summary list
    ---@param cfg rtu_config
    function tool_ctl.gen_summary(cfg)
        setting_list.remove_all()

        local alternate = false
        local inner_width = setting_list.get_width() - 1

        self.show_key_btn.enable()
        self.auth_key_value = cfg.AuthKey or "" -- to show auth key

        for i = 1, #fields do
            local f = fields[i]
            local height = 1
            local label_w = string.len(f[2])
            local val_max_w = (inner_width - label_w) + 1
            local raw = cfg[f[1]]
            local val = util.strval(raw)

            if f[1] == "AuthKey" then val = string.rep("*", string.len(val))
            elseif f[1] == "LogMode" then val = tri(raw == log.MODE.APPEND, "追加", "替换")
            elseif f[1] == "FrontPanelTheme" then
                val = util.strval(themes.fp_theme_name(raw))
            elseif f[1] == "ColorMode" then
                val = util.strval(themes.color_mode_name(raw))
            end

            if val == "nil" then val = "<未设置>" end

            local c = tri(alternate, g_lg_fg_bg, cpair(colors.gray,colors.white))
            alternate = not alternate

            if (string.len(val) > val_max_w) or string.find(val, "\n") then
                local lines = util.strwrap(val, inner_width)
                height = #lines + 1
            end

            local line = Div{parent=setting_list,height=height,fg_bg=c}
            TextBox{parent=line,text=f[2],width=string.len(f[2]),fg_bg=cpair(colors.black,line.get_fg_bg().bkg)}

            local textbox
            if height > 1 then
                textbox = TextBox{parent=line,y=2,text=val,height=height-1}
            else
                textbox = TextBox{parent=line,x=label_w+1,y=1,text=val,alignment=RIGHT}
            end

            if f[1] == "AuthKey" then self.auth_key_textbox = textbox end
        end
    end

    -- generate the list of available/assigned wired modems
    function tool_ctl.gen_modem_list()
        modem_list.remove_all()

        local enable = self.wired.get_value()

        local function select(iface)
            tmp_cfg.WiredModem = iface
            tool_ctl.gen_modem_list()
        end

        local modems  = ppm.get_wired_modem_list()
        local missing = { tmp = true, ini = true }

        for iface, _ in pairs(modems) do
            if ini_cfg.WiredModem == iface then missing.ini = false end
            if tmp_cfg.WiredModem == iface then missing.tmp = false end
        end

        if missing.tmp and tmp_cfg.WiredModem then
            local line = Div{parent=modem_list,y=1,height=1}

            TextBox{parent=line,y=1,width=4,text="使用中",fg_bg=cpair(tri(enable,colors.blue,colors.gray),colors.white)}
            PushButton{parent=line,x=6,y=1,min_width=8,height=1,text="选择",callback=function()end,fg_bg=cpair(colors.black,colors.lightBlue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=g_lg_fg_bg}.disable()
            TextBox{parent=line,x=15,y=1,text="[缺失]",fg_bg=cpair(colors.red,colors.white)}
            TextBox{parent=line,x=25,y=1,text=tmp_cfg.WiredModem}
        end

        if missing.ini and ini_cfg.WiredModem and (tmp_cfg.WiredModem ~= ini_cfg.WiredModem) then
            local line = Div{parent=modem_list,y=1,height=1}
            local used = tmp_cfg.WiredModem == ini_cfg.WiredModem

            TextBox{parent=line,y=1,width=4,text=tri(used,"使用中","----"),fg_bg=cpair(tri(used and enable,colors.blue,colors.gray),colors.white)}
            local select_btn = PushButton{parent=line,x=6,y=1,min_width=8,height=1,text="选择",callback=function()select(ini_cfg.WiredModem)end,fg_bg=cpair(colors.black,colors.lightBlue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=g_lg_fg_bg}
            TextBox{parent=line,x=15,y=1,text="[缺失]",fg_bg=cpair(colors.red,colors.white)}
            TextBox{parent=line,x=25,y=1,text=ini_cfg.WiredModem}

            if used or not enable then select_btn.disable() end
        end

        -- list wired modems
        for iface, _ in pairs(modems) do
            local line = Div{parent=modem_list,y=1,height=1}
            local used = tmp_cfg.WiredModem == iface

            TextBox{parent=line,y=1,width=4,text=tri(used,"使用中","----"),fg_bg=cpair(tri(used and enable,colors.blue,colors.gray),colors.white)}
            local select_btn = PushButton{parent=line,x=6,y=1,min_width=8,height=1,text="选择",callback=function()select(iface)end,fg_bg=cpair(colors.black,colors.lightBlue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=g_lg_fg_bg}
            TextBox{parent=line,x=15,y=1,text=iface}

            if used or not enable then select_btn.disable() end
        end
    end

    --#endregion
end

return system
