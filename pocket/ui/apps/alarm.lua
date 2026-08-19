--
-- Alarm Test App
--

local ioctl          = require("pocket.ioctl")
local pocket         = require("pocket.pocket")

local core           = require("graphics.core")

local Div            = require("graphics.elements.Div")
local MultiPane      = require("graphics.elements.MultiPane")
local TextBox        = require("graphics.elements.TextBox")

local IndicatorLight = require("graphics.elements.indicators.IndicatorLight")

local Checkbox       = require("graphics.elements.controls.Checkbox")
local PushButton     = require("graphics.elements.controls.PushButton")
local SwitchButton   = require("graphics.elements.controls.SwitchButton")

local ALIGN = core.ALIGN
local cpair = core.cpair

local APP_ID = pocket.APP_ID

local c_wht_gray  = cpair(colors.white, colors.gray)
local c_red_gray  = cpair(colors.red, colors.gray)
local c_yel_gray  = cpair(colors.yellow, colors.gray)
local c_blue_gray = cpair(colors.blue, colors.gray)

-- create alarm test page view
---@param root Container parent
local function new_view(root)
    local db    = ioctl.get_db()
    local ps    = db.ps
    local ttest = db.diag.tone_test

    local frame = Div{parent=root,y=1}

    local app = db.nav.register_app(APP_ID.ALARMS, frame, nil, true)

    local main     = Div{parent=frame,y=1}
    local page_div = Div{parent=main,y=2,width=main.get_width()}

    --#region alarm testing

    local alarm_page = app.new_page(nil, 1)
    alarm_page.tasks = { db.diag.tone_test.get_tone_states }

    local alarms_div = Div{parent=page_div}

    TextBox{parent=alarms_div,text="警报发声器测试",alignment=ALIGN.CENTER}

    local alarm_ready_warn = TextBox{parent=alarms_div,y=2,text="",alignment=ALIGN.CENTER,fg_bg=cpair(colors.yellow,colors.black)}
    alarm_ready_warn.register(ps, "alarm_ready_warn", alarm_ready_warn.set_value)

    local alarm_page_states = Div{parent=alarms_div,x=2,y=3,height=5,width=8}

    TextBox{parent=alarm_page_states,text="状态",alignment=ALIGN.CENTER}
    local ta_1 = IndicatorLight{parent=alarm_page_states,label="1",colors=c_blue_gray}
    local ta_2 = IndicatorLight{parent=alarm_page_states,label="2",colors=c_blue_gray}
    local ta_3 = IndicatorLight{parent=alarm_page_states,label="3",colors=c_blue_gray}
    local ta_4 = IndicatorLight{parent=alarm_page_states,label="4",colors=c_blue_gray}
    local ta_5 = IndicatorLight{parent=alarm_page_states,x=6,y=2,label="5",colors=c_blue_gray}
    local ta_6 = IndicatorLight{parent=alarm_page_states,x=6,label="6",colors=c_blue_gray}
    local ta_7 = IndicatorLight{parent=alarm_page_states,x=6,label="7",colors=c_blue_gray}
    local ta_8 = IndicatorLight{parent=alarm_page_states,x=6,label="8",colors=c_blue_gray}

    local ta = { ta_1, ta_2, ta_3, ta_4, ta_5, ta_6, ta_7, ta_8 }

    for i = 1, #ta do
        ta[i].register(ps, "alarm_tone_" .. i, ta[i].update)
    end

    local alarms = Div{parent=alarms_div,x=11,y=3,height=15,fg_bg=cpair(colors.lightGray,colors.black)}

    TextBox{parent=alarms,text="警报 (\x13)",alignment=ALIGN.CENTER,fg_bg=alarms_div.get_fg_bg()}

    local alarm_btns = {}
    alarm_btns[1]  = Checkbox{parent=alarms,label="破裂",min_width=15,box_fg_bg=c_red_gray,callback=ttest.test_breach}
    alarm_btns[2]  = Checkbox{parent=alarms,label="辐射",min_width=15,box_fg_bg=c_red_gray,callback=ttest.test_rad}
    alarm_btns[3]  = Checkbox{parent=alarms,label="反应堆丢失",min_width=15,box_fg_bg=c_red_gray,callback=ttest.test_lost}
    alarm_btns[4]  = Checkbox{parent=alarms,label="严重损坏",min_width=15,box_fg_bg=c_red_gray,callback=ttest.test_crit}
    alarm_btns[5]  = Checkbox{parent=alarms,label="损坏",min_width=15,box_fg_bg=c_red_gray,callback=ttest.test_dmg}
    alarm_btns[6]  = Checkbox{parent=alarms,label="超温",min_width=15,box_fg_bg=c_red_gray,callback=ttest.test_overtemp}
    alarm_btns[7]  = Checkbox{parent=alarms,label="高温",min_width=15,box_fg_bg=c_yel_gray,callback=ttest.test_hightemp}
    alarm_btns[8]  = Checkbox{parent=alarms,label="废料泄漏",min_width=15,box_fg_bg=c_red_gray,callback=ttest.test_wasteleak}
    alarm_btns[9]  = Checkbox{parent=alarms,label="废料过多",min_width=15,box_fg_bg=c_yel_gray,callback=ttest.test_highwaste}
    alarm_btns[10] = Checkbox{parent=alarms,label="RPS 瞬态",min_width=15,box_fg_bg=c_yel_gray,callback=ttest.test_rps}
    alarm_btns[11] = Checkbox{parent=alarms,label="RCS 瞬态",min_width=15,box_fg_bg=c_yel_gray,callback=ttest.test_rcs}
    alarm_btns[12] = Checkbox{parent=alarms,label="涡轮机跳闸",min_width=15,box_fg_bg=c_red_gray,callback=ttest.test_turbinet}

    ttest.alarm_buttons = alarm_btns

    local function stop_all_alarms()
        for i = 1, #alarm_btns do alarm_btns[i].set_value(false) end
        ttest.stop_alarms()
    end

    PushButton{parent=alarms,x=3,y=15,text="停止 \x13",min_width=8,fg_bg=cpair(colors.black,colors.red),active_fg_bg=c_wht_gray,callback=stop_all_alarms}

    --#endregion

    --#region direct tone testing

    local tones_page = app.new_page(nil, 2)
    tones_page.tasks = { db.diag.tone_test.get_tone_states }

    local tones_div = Div{parent=page_div}

    TextBox{parent=tones_div,text="警报发声器测试",alignment=ALIGN.CENTER}

    local tone_ready_warn = TextBox{parent=tones_div,y=2,text="",alignment=ALIGN.CENTER,fg_bg=cpair(colors.yellow,colors.black)}
    tone_ready_warn.register(ps, "alarm_ready_warn", tone_ready_warn.set_value)

    local tone_page_states = Div{parent=tones_div,x=3,y=3,height=5,width=8}

    TextBox{parent=tone_page_states,text="状态",alignment=ALIGN.CENTER}
    local tt_1 = IndicatorLight{parent=tone_page_states,label="1",colors=c_blue_gray}
    local tt_2 = IndicatorLight{parent=tone_page_states,label="2",colors=c_blue_gray}
    local tt_3 = IndicatorLight{parent=tone_page_states,label="3",colors=c_blue_gray}
    local tt_4 = IndicatorLight{parent=tone_page_states,label="4",colors=c_blue_gray}
    local tt_5 = IndicatorLight{parent=tone_page_states,x=6,y=2,label="5",colors=c_blue_gray}
    local tt_6 = IndicatorLight{parent=tone_page_states,x=6,label="6",colors=c_blue_gray}
    local tt_7 = IndicatorLight{parent=tone_page_states,x=6,label="7",colors=c_blue_gray}
    local tt_8 = IndicatorLight{parent=tone_page_states,x=6,label="8",colors=c_blue_gray}

    local tt = { tt_1, tt_2, tt_3, tt_4, tt_5, tt_6, tt_7, tt_8 }

    for i = 1, #tt do
        tt[i].register(ps, "alarm_tone_" .. i, tt[i].update)
    end

    local tones = Div{parent=tones_div,x=14,y=3,height=10,width=8,fg_bg=cpair(colors.black,colors.yellow)}

    TextBox{parent=tones,text="音调",alignment=ALIGN.CENTER,fg_bg=tones_div.get_fg_bg()}

    local test_btns = {}
    test_btns[1] = SwitchButton{parent=tones,text="测试 1",min_width=8,active_fg_bg=c_wht_gray,callback=ttest.test_1}
    test_btns[2] = SwitchButton{parent=tones,text="测试 2",min_width=8,active_fg_bg=c_wht_gray,callback=ttest.test_2}
    test_btns[3] = SwitchButton{parent=tones,text="测试 3",min_width=8,active_fg_bg=c_wht_gray,callback=ttest.test_3}
    test_btns[4] = SwitchButton{parent=tones,text="测试 4",min_width=8,active_fg_bg=c_wht_gray,callback=ttest.test_4}
    test_btns[5] = SwitchButton{parent=tones,text="测试 5",min_width=8,active_fg_bg=c_wht_gray,callback=ttest.test_5}
    test_btns[6] = SwitchButton{parent=tones,text="测试 6",min_width=8,active_fg_bg=c_wht_gray,callback=ttest.test_6}
    test_btns[7] = SwitchButton{parent=tones,text="测试 7",min_width=8,active_fg_bg=c_wht_gray,callback=ttest.test_7}
    test_btns[8] = SwitchButton{parent=tones,text="测试 8",min_width=8,active_fg_bg=c_wht_gray,callback=ttest.test_8}

    ttest.tone_buttons = test_btns

    local function stop_all_tones()
        for i = 1, #test_btns do test_btns[i].set_value(false) end
        ttest.stop_tones()
    end

    PushButton{parent=tones,text="停止",min_width=8,active_fg_bg=c_wht_gray,fg_bg=cpair(colors.black,colors.red),callback=stop_all_tones}

    --#endregion

    --#region info page

    app.new_page(nil, 3)

    local info_div = Div{parent=page_div}

    TextBox{parent=info_div,x=2,y=1,text="此应用提供按警报和按音调（1-8）测试警报声音的工具。"}
    TextBox{parent=info_div,x=2,y=6,text="系统必须处于待机状态（所有机组停止且无警报激活）才能运行测试。"}
    TextBox{parent=info_div,x=2,y=12,text="除非你在监管端的配置中启用测试，否则测试将被拒绝。"}

    --#endregion

    -- setup multipane
    local u_pane = MultiPane{parent=page_div,y=1,panes={alarms_div,tones_div,info_div}}
    app.set_root_pane(u_pane)

    local list = {
        { label = " # ", tall = true, color = core.cpair(colors.black, colors.green), callback = db.nav.go_home },
        { label = " \x13 ", color = core.cpair(colors.black, colors.red), callback = function () app.switcher(1) end },
        { label = " \x0f ", color = core.cpair(colors.black, colors.yellow), callback = function () app.switcher(2) end },
        { label = " ? ", color = core.cpair(colors.black, colors.blue), callback = function () app.switcher(3) end }
    }

    app.set_sidebar(list)
end

return new_view
