--
-- Configuration GUI
--

local log        = require("scada-common.log")
local ppm        = require("scada-common.ppm")
local tcd        = require("scada-common.tcd")
local types      = require("scada-common.types")
local util       = require("scada-common.util")

local facility   = require("coordinator.config.facility")
local hmi        = require("coordinator.config.hmi")
local system     = require("coordinator.config.system")

local core       = require("graphics.core")
local themes     = require("graphics.themes")

local DisplayBox = require("graphics.elements.DisplayBox")
local Div        = require("graphics.elements.Div")
local ListBox    = require("graphics.elements.ListBox")
local MultiPane  = require("graphics.elements.MultiPane")
local TextBox    = require("graphics.elements.TextBox")

local PushButton = require("graphics.elements.controls.PushButton")

local println = util.println
local tri = util.trinary

local cpair = core.cpair

local CENTER = core.ALIGN.CENTER

-- changes to the config data/format to let the user know
local changes = {
    { "v1.2.4", { "新增温度单位选项" } },
    { "v1.2.12", { "新增主 UI 主题", "新增前面板 UI 主题", "新增颜色无障碍模式" } },
    { "v1.3.3", { "新增关闭状态为黑色的标准颜色模式", "新增蓝色指示灯颜色模式" } },
    { "v1.5.1", { "新增能量单位选项" } },
    { "v1.6.13", { "新增 Po/Pu 燃料丸绿/青配色选项" } },
    { "v1.7.0", { "新增对有线通信调制解调器的支持", "新增允许 Pocket 连接的选项" } },
    { "v1.9.7", { "移除“禁用流程视图”选项" } }
}

---@class crd_configurator
local configurator = {}

local style = {}

style.root          = cpair(colors.black, colors.lightGray)
style.header        = cpair(colors.white, colors.gray)

style.colors        = themes.smooth_stone.colors

style.bw_fg_bg      = cpair(colors.black, colors.white)
style.g_lg_fg_bg    = cpair(colors.gray, colors.lightGray)
style.nav_fg_bg     = style.bw_fg_bg
style.btn_act_fg_bg = cpair(colors.white, colors.gray)
style.btn_dis_fg_bg = cpair(colors.lightGray,colors.white)

---@class _crd_cfg_tool_ctl
local tool_ctl = {
    sv_cool_conf = nil,       ---@type [ integer, integer ][] list of boiler & turbine counts

    launch_startup = false,
    start_fail = 0,
    fail_message = "",
    has_config = false,
    viewing_config = false,
    jumped_to_color = false,

    view_cfg = nil,           ---@type PushButton
    color_cfg = nil,          ---@type PushButton
    color_next = nil,         ---@type PushButton
    color_apply = nil,        ---@type PushButton
    settings_apply = nil,     ---@type PushButton

    gen_summary = nil,        ---@type function
    load_legacy = nil,        ---@type function

    -- settings elements from hmi
    s_vol = nil,              ---@type NumberField
    pellet_color = nil,       ---@type RadioButton
    clock_fmt = nil,          ---@type RadioButton
    temp_scale = nil,         ---@type RadioButton
    energy_scale = nil,       ---@type RadioButton

    -- settings elements and functions from facility
    num_units = nil,          ---@type NumberField
    init_sv_connect_ui = nil, ---@type function
    is_int_min_max = nil,     ---@type function

    update_mon_reqs = nil,    ---@type function

    gen_mon_list = function () end,
    gen_modem_list = function () end,

    dw_free_space = nil,      ---@type TextBox
    dw_log_size = nil,        ---@type TextBox
    dw_del_log_btn = nil,     ---@type PushButton
    dw_continue = nil         ---@type PushButton
}

---@class crd_config
local tmp_cfg = {
    UnitCount = 1,
    SpeakerVolume = 1.0,
    Time24Hour = true,
    GreenPuPellet = false,
    TempScale = 1,          ---@type TEMP_SCALE
    EnergyScale = 1,        ---@type ENERGY_SCALE
    MainDisplay = nil,      ---@type string
    FlowDisplay = nil,      ---@type string
    UnitDisplays = {},      ---@type string[]
    WirelessModem = true,
    WiredModem = false,     ---@type string|false
    PreferWireless = true,
    API_Enabled = true,
    SVR_Channel = nil,      ---@type integer
    CRD_Channel = nil,      ---@type integer
    PKT_Channel = nil,      ---@type integer
    SVR_Timeout = nil,      ---@type number
    API_Timeout = nil,      ---@type number
    TrustedRange = nil,     ---@type number
    AuthKey = nil,          ---@type string|nil
    LogMode = 0,            ---@type LOG_MODE
    LogPath = "",
    LogDebug = false,
    MainTheme = 1,          ---@type UI_THEME
    FrontPanelTheme = 1,    ---@type FP_THEME
    ColorMode = 1           ---@type COLOR_MODE
}

---@class crd_config
local ini_cfg = {}
---@class crd_config
local settings_cfg = {}

-- all settings fields, their nice names, and their default values
local fields = {
    { "UnitCount", "反应堆数量", 1 },
    { "MainDisplay", "主监视器", nil },
    { "FlowDisplay", "流程监视器", nil },
    { "UnitDisplays", "机组监视器", {} },
    { "SpeakerVolume", "扬声器音量", 1.0 },
    { "Time24Hour", "使用 24 小时时间格式", true },
    { "GreenPuPellet", "燃料丸颜色", false },
    { "TempScale", "温度单位", types.TEMP_SCALE.KELVIN },
    { "EnergyScale", "能量单位", types.ENERGY_SCALE.FE },
    { "WirelessModem", "无线/末影通信调制解调器", true },
    { "WiredModem", "有线通信调制解调器", false },
    { "PreferWireless", "优先使用无线调制解调器", true },
    { "API_Enabled", "Pocket API 连接", true },
    { "SVR_Channel", "SVR 频道", 16240 },
    { "CRD_Channel", "CRD 频道", 16243 },
    { "PKT_Channel", "PKT 频道", 16244 },
    { "SVR_Timeout", "上位机连接超时", 5 },
    { "API_Timeout", "API 连接超时", 5 },
    { "TrustedRange", "受信范围", 0 },
    { "AuthKey", "设施认证密钥" , ""},
    { "LogMode", "日志模式", log.MODE.APPEND },
    { "LogPath", "日志路径", "/log.txt" },
    { "LogDebug", "日志调试消息", false },
    { "MainTheme", "主 UI 主题", themes.UI_THEME.SMOOTH_STONE },
    { "FrontPanelTheme", "前面板主题", themes.FP_THEME.SANDSTONE },
    { "ColorMode", "颜色模式", themes.COLOR_MODE.STANDARD }
}

-- load tmp_cfg fields from ini_cfg fields for displays
local function preset_monitor_fields()
    tmp_cfg.MainDisplay = ini_cfg.MainDisplay
    tmp_cfg.FlowDisplay = ini_cfg.FlowDisplay
    for i = 1, ini_cfg.UnitCount do
        tmp_cfg.UnitDisplays[i] = ini_cfg.UnitDisplays[i]
    end
end

-- load data from the settings file
---@param target crd_config
---@param raw boolean? true to not use default values
local function load_settings(target, raw)
    for _, v in pairs(fields) do settings.unset(v[1]) end

    local loaded = settings.load("/coordinator.settings")

    for _, v in pairs(fields) do target[v[1]] = settings.get(v[1], tri(raw, nil, v[3])) end

    return loaded
end

-- create the config view
---@param display DisplayBox
local function config_view(display)
    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg
    local btn_dis_fg_bg = style.btn_dis_fg_bg

    local function exit() os.queueEvent("terminate") end

    TextBox{parent=display,y=1,text="协调器配置器",alignment=CENTER,fg_bg=style.header}

    local root_pane_div = Div{parent=display,y=2}

    local main_page = Div{parent=root_pane_div,y=1}
    local net_cfg = Div{parent=root_pane_div,y=1}
    local fac_cfg = Div{parent=root_pane_div,y=1}
    local mon_cfg = Div{parent=root_pane_div,y=1}
    local spkr_cfg = Div{parent=root_pane_div,y=1}
    local crd_cfg = Div{parent=root_pane_div,y=1}
    local log_cfg = Div{parent=root_pane_div,y=1}
    local clr_cfg = Div{parent=root_pane_div,y=1}
    local summary = Div{parent=root_pane_div,y=1}
    local changelog = Div{parent=root_pane_div,y=1}
    local disk_warn = Div{parent=root_pane_div,y=1}

    local main_pane = MultiPane{parent=root_pane_div,y=1,panes={main_page,net_cfg,fac_cfg,mon_cfg,spkr_cfg,crd_cfg,log_cfg,clr_cfg,summary,changelog,disk_warn}}

    local req_space = log.MIN_SPACE
    if fs.exists("/coordinator.settings") then
        req_space = math.max(0, req_space - fs.getSize("/coordinator.settings"))
    end

    -- show disk space warning if needed
    if fs.getFreeSpace("/") < req_space then main_pane.set_value(11) end

    --#region Main Page

    local y_start = 5

    TextBox{parent=main_page,x=2,y=2,height=2,text="欢迎使用协调器配置器！请选择以下选项之一。"}

    if tool_ctl.start_fail == 2 then
        local msg = util.c("提示：您的监视器配置存在问题。", tool_ctl.fail_message, " 请重新配置监视器或修正其尺寸。")
        TextBox{parent=main_page,x=2,y=y_start,height=4,width=49,text=msg,fg_bg=cpair(colors.red,colors.lightGray)}
        y_start = y_start + 5
    elseif tool_ctl.start_fail > 0 then
        TextBox{parent=main_page,x=2,y=y_start,height=4,width=49,text="提示：此设备未针对此版本的协调器进行配置。如果您之前有有效的配置，它并未丢失。您可能希望查看更新日志以了解发生了什么变化。",fg_bg=cpair(colors.red,colors.lightGray)}
        y_start = y_start + 5
    end

    local function view_config()
        tool_ctl.viewing_config = true
        tool_ctl.gen_summary(settings_cfg)
        tool_ctl.settings_apply.hide(true)
        main_pane.set_value(9)
    end

    if fs.exists("/coordinator/config.lua") then
        PushButton{parent=main_page,x=2,y=y_start,min_width=28,text="导入旧版 'config.lua'",callback=function()tool_ctl.load_legacy()end,fg_bg=cpair(colors.black,colors.cyan),active_fg_bg=btn_act_fg_bg}
        y_start = y_start + 2
    end

    PushButton{parent=main_page,x=2,y=y_start,min_width=18,text="配置系统",callback=function()main_pane.set_value(2)end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg}
    tool_ctl.view_cfg = PushButton{parent=main_page,x=2,y=y_start+2,min_width=20,text="查看配置",callback=view_config,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}

    local function jump_color()
        tool_ctl.jumped_to_color = true
        tool_ctl.color_next.hide(true)
        tool_ctl.color_apply.show()
        main_pane.set_value(8)
    end

    local function startup()
        tool_ctl.launch_startup = true
        exit()
    end

    tool_ctl.color_cfg = PushButton{parent=main_page,x=36,y=y_start,min_width=15,text="颜色选项",callback=jump_color,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,dis_fg_bg=cpair(colors.lightGray,colors.white)}
    PushButton{parent=main_page,x=39,y=y_start+2,min_width=12,text="更新日志",callback=function()main_pane.set_value(10)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    if tool_ctl.start_fail ~= 0 then
        PushButton{parent=main_page,x=2,y=17,min_width=6,text="退出",callback=exit,dis_fg_bg=btn_dis_fg_bg}.disable()
        PushButton{parent=main_page,x=35,y=17,min_width=16,text="继续启动",callback=exit,fg_bg=cpair(colors.black,colors.lightBlue),active_fg_bg=btn_act_fg_bg}
    else
        PushButton{parent=main_page,x=2,y=17,min_width=6,text="退出",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg}
        PushButton{parent=main_page,x=42,y=17,min_width=9,text="启动",callback=startup,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}
    end

    if not tool_ctl.has_config then
        tool_ctl.view_cfg.disable()
        tool_ctl.color_cfg.disable()
    end

    --#endregion

    -- #region Disk Space Warning

    TextBox{parent=disk_warn,y=2,text=" 磁盘空间不足",fg_bg=cpair(colors.white,colors.black)}

    local disk_page = Div{parent=disk_warn,x=2,y=4,width=49}

    local function delete_log()
        fs.delete(ini_cfg.LogPath)

        local space = fs.getFreeSpace("/")
        tool_ctl.dw_free_space.set_value("可用空间："..space.." 字节")

        if not fs.exists(ini_cfg.LogPath) then
            tool_ctl.dw_log_size.set_value("日志文件大小：0 字节")
            tool_ctl.dw_del_log_btn.disable()
        end

        if space >= req_space then tool_ctl.dw_continue.enable() end
    end

    TextBox{parent=disk_page,height=3,text="磁盘空间不足，无法安全配置此设备。保存配置可能失败并导致配置数据丢失。"}

    TextBox{parent=disk_page,y=5,height=1,text="容量：                  "..fs.getCapacity("/").." 字节",fg_bg=cpair(colors.gray,colors._INHERIT)}
    tool_ctl.dw_free_space = TextBox{parent=disk_page,height=1,text="可用空间：              "..fs.getFreeSpace("/").." 字节",fg_bg=cpair(colors.gray,colors._INHERIT)}
    TextBox{parent=disk_page,height=1,text="所需空间：              "..req_space.." 字节",fg_bg=cpair(colors.gray,colors._INHERIT)}

    if fs.exists(ini_cfg.LogPath) then
        TextBox{parent=disk_page,y=9,height=2,text="如果您的日志文件位于此电脑上而非外部磁盘，删除它可能会有所帮助。"}
        tool_ctl.dw_log_size = TextBox{parent=disk_page,y=12,height=1,text="日志文件大小："..fs.getSize(ini_cfg.LogPath).." 字节",fg_bg=cpair(colors.gray,colors._INHERIT)}

        tool_ctl.dw_del_log_btn = PushButton{parent=disk_page,x=33,y=12,min_width=17,text="删除日志文件",callback=delete_log,fg_bg=cpair(colors.black,colors.orange),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    else
        TextBox{parent=disk_page,y=9,height=4,text="未找到日志文件，因此您需要手动腾出空间。请删除您可能手动创建的任何与此应用无关的文件。"}
    end

    PushButton{parent=disk_page,y=14,min_width=6,text="退出",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=btn_act_fg_bg}
    tool_ctl.dw_continue = PushButton{parent=disk_page,x=40,y=14,min_width=10,text="继续",callback=function()main_pane.set_value(1)end,fg_bg=cpair(colors.black,colors.lightBlue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    tool_ctl.dw_continue.disable()

    -- #endregion

    local settings = { settings_cfg, ini_cfg, tmp_cfg, fields, load_settings }

    --#region Facility Configuration

    local fac_pane = facility.create(tool_ctl, main_pane, settings, fac_cfg, style)

    --#endregion

    --#region HMI Configuration

    local mon_pane = hmi.create(tool_ctl, main_pane, settings, { mon_cfg, spkr_cfg, crd_cfg }, style)

    --#endregion

    --#region System Configuration

    local divs = { net_cfg, log_cfg, clr_cfg, summary }
    local ext  = { fac_pane, mon_pane, preset_monitor_fields, startup, exit }

    system.create(tool_ctl, main_pane, settings, divs, ext, style)

    --#endregion

    --#region Config Change Log

    local cl = Div{parent=changelog,x=2,y=4,width=49}

    TextBox{parent=changelog,y=2,text=" 配置更新日志",fg_bg=bw_fg_bg}

    local c_log = ListBox{parent=cl,y=1,height=12,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    for _, change in ipairs(changes) do
        TextBox{parent=c_log,text=change[1],fg_bg=bw_fg_bg}
        for _, v in ipairs(change[2]) do
            local e = Div{parent=c_log,height=#util.strwrap(v,46)}
            TextBox{parent=e,y=1,text="- ",fg_bg=cpair(colors.gray,colors.white)}
            TextBox{parent=e,y=1,x=3,text=v,height=e.get_height(),fg_bg=cpair(colors.gray,colors.white)}
        end
    end

    PushButton{parent=cl,y=14,text="\x1b 返回",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion
end

-- reset terminal screen
local function reset_term()
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
end

-- run the coordinator configurator<br>
-- start_fail of 0 is OK (default if not provided), 1 is bad config, 2 is bad monitor config
---@param start_code? 0|1|2 indicate error state when called from the startup app
---@param message? any string message to display on a start_fail of 2
function configurator.configure(start_code, message)
    tool_ctl.start_fail = start_code or 0
    tool_ctl.fail_message = util.trinary(type(message) == "string", message, "")

    load_settings(settings_cfg, true)
    tool_ctl.has_config = load_settings(ini_cfg)

    -- copy in some important values to start with
    preset_monitor_fields()

    -- this needs to be initialized as it is used before being set
    tmp_cfg.WiredModem = ini_cfg.WiredModem

    reset_term()

    ppm.mount_all()

    -- set overridden colors
    for i = 1, #style.colors do
        term.setPaletteColor(style.colors[i].c, style.colors[i].hex)
    end

    local status, error = pcall(function ()
        local display = DisplayBox{window=term.current(),fg_bg=style.root}
        config_view(display)

        tool_ctl.gen_mon_list()
        tool_ctl.gen_modem_list()

        while true do
            local event, param1, param2, param3, param4, param5 = util.pull_event()

            -- handle event
            if event == "timer" then
                tcd.handle(param1)
            elseif event == "mouse_click" or event == "mouse_up" or event == "mouse_drag" or event == "mouse_scroll" or event == "double_click" then
                local m_e = core.events.new_mouse_event(event, param1, param2, param3)
                if m_e then display.handle_mouse(m_e) end
            elseif event == "char" or event == "key" or event == "key_up" then
                local k_e = core.events.new_key_event(event, param1, param2)
                if k_e then display.handle_key(k_e) end
            elseif event == "paste" then
                display.handle_paste(param1)
            elseif event == "peripheral_detach" then
---@diagnostic disable-next-line: discard-returns
                ppm.handle_unmount(param1)
                tool_ctl.gen_mon_list()
            elseif event == "peripheral" then
---@diagnostic disable-next-line: discard-returns
                ppm.mount(param1)
                tool_ctl.gen_mon_list()
                tool_ctl.gen_modem_list()
            elseif event == "monitor_resize" then
                tool_ctl.gen_mon_list()
                tool_ctl.gen_modem_list()
            elseif event == "modem_message" then
                facility.receive_sv(param1, param2, param3, param4, param5)
            end

            if event == "terminate" then return end
        end
    end)

    -- restore colors
    for i = 1, #style.colors do
        local r, g, b = term.nativePaletteColor(style.colors[i].c)
        term.setPaletteColor(style.colors[i].c, r, g, b)
    end

    reset_term()
    if not status then
        println("配置器错误：" .. error)
    end

    return status, error, tool_ctl.launch_startup
end

return configurator
