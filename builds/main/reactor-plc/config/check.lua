local comms      = require("scada-common.comms")
local network    = require("scada-common.network")
local ppm        = require("scada-common.ppm")
local tcd        = require("scada-common.tcd")
local util       = require("scada-common.util")
local plc        = require("reactor-plc.plc")
local core       = require("graphics.core")
local Div        = require("graphics.elements.Div")
local ListBox    = require("graphics.elements.ListBox")
local TextBox    = require("graphics.elements.TextBox")
local PushButton = require("graphics.elements.controls.PushButton")
local tri = util.trinary
local cpair = core.cpair
local PROTOCOL = comms.PROTOCOL
local DEVICE_TYPE = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local MGMT_TYPE = comms.MGMT_TYPE
local self = {
checking_wl = true,
wd_modem = nil,
wl_modem = nil,
nic = nil,
net_listen = false,
self_check_pass = true,
settings = nil,
run_test_btn = nil,
sc_log = nil,
self_check_msg = nil
}
local function check_complete()
TextBox{parent=self.sc_log,text="> 全部测试通过！",fg_bg=cpair(colors.blue,colors._INHERIT)}
TextBox{parent=self.sc_log,text=""}
local more = Div{parent=self.sc_log,height=3,fg_bg=cpair(colors.gray,colors._INHERIT)}
TextBox{parent=more,text="如果仍有问题："}
TextBox{parent=more,text="- 查看 GitHub 上的 wiki"}
TextBox{parent=more,text="- 在 GitHub discussions 或 Discord 上寻求帮助"}
end
local function send_sv(msg_type, msg)
local frame, mgmt = comms.scada_frame(), comms.mgmt_container()
mgmt.make(msg_type, msg)
frame.make(comms.BROADCAST, util.time_ms() * 10, PROTOCOL.SCADA_MGMT, mgmt.raw_packet())
self.nic.transmit(self.settings.SVR_Channel, self.settings.PLC_Channel, frame)
end
local function handle_packet(packet)
local error_msg = nil
if packet.scada_frame.local_channel() ~= self.settings.PLC_Channel then
error_msg = "错误：未知的接收频道"
elseif packet.scada_frame.remote_channel() == self.settings.SVR_Channel and packet.scada_frame.protocol() == PROTOCOL.SCADA_MGMT then
if packet.type == MGMT_TYPE.ESTABLISH then
if packet.length == 1 then
local est_ack = packet.data[1]
if est_ack== ESTABLISH_ACK.ALLOW then
elseif est_ack == ESTABLISH_ACK.DENY then
error_msg = "错误：监控端连接被拒绝"
elseif est_ack == ESTABLISH_ACK.COLLISION then
error_msg = "另一个反应堆 PLC 已使用此反应堆机组 ID 连接"
elseif est_ack == ESTABLISH_ACK.BAD_VERSION then
error_msg = "反应堆 PLC 通信版本与监控端通信版本不匹配，请确保两个设备均为最新版本（ccmsi update）"
else
error_msg = "错误：监控端回复无效"
end
else
error_msg = "错误：监控端回复长度无效"
end
else
error_msg = "错误：未收到监控端的建立连接回复"
end
end
self.net_listen = false
if error_msg then
self.self_check_msg(nil, false, error_msg)
else
self.self_check_msg(nil, true, "")
end
util.push_event("conn_test_complete", error_msg == nil)
end
local function handle_timeout()
self.net_listen = false
util.push_event("conn_test_complete", false)
end
local function self_check()
self.run_test_btn.disable()
self.sc_log.remove_all()
ppm.mount_all()
self.self_check_pass = true
local cfg = self.settings
self.wd_modem = ppm.get_modem(cfg.WiredModem)
self.wl_modem = ppm.get_wireless_modem()
local reactor = ppm.get_fission_reactor()
local valid_cfg = plc.validate_config(cfg)
if cfg.Networked then
if cfg.WiredModem then
self.self_check_msg("> 检查有线通信调制解调器是否已连接...", self.wd_modem, "请连接有线通信调制解调器 " .. cfg.WiredModem)
end
if cfg.WirelessModem then
self.self_check_msg("> 检查无线/末影调制解调器是否已连接...", self.wl_modem, "请连接末影或无线调制解调器以进行无线通信")
end
end
self.self_check_msg("> 检查裂变反应堆是否已连接...", reactor ~= nil, "请将反应堆 PLC 连接到反应堆的裂变反应堆逻辑适配器")
self.self_check_msg("> 检查裂变反应堆是否成型...")
self.self_check_msg(nil, reactor and reactor.isFormed(), "确保裂变反应堆多方块结构已成型")
self.self_check_msg("> 检查反应堆数量不超过一个...", #ppm.get_all_devices("fissionReactorLogicAdapter") <= 1, "连接的反应堆绝不能超过一个，因为 PLC 使用找到的第一个反应堆，且不一定是同一个")
self.self_check_msg("> 检查配置...", valid_cfg, "请进入系统配置并应用设置，以设置缺失的设置并修复损坏的设置")
if cfg.Networked and valid_cfg then
self.checking_wl = true
if cfg.WirelessModem and self.wl_modem then
self.self_check_msg("> 检查无线监控端连接...")
if cfg.AuthKey and string.len(cfg.AuthKey) >= 8 then
network.init_mac(cfg.AuthKey)
else
network.deinit_mac()
end
comms.set_trusted_range(cfg.TrustedRange)
self.nic = network.nic(self.wl_modem)
self.nic.closeAll()
self.nic.open(cfg.PLC_Channel)
self.net_listen = true
send_sv(MGMT_TYPE.ESTABLISH, { comms.version, comms.CONN_TEST_FWV, DEVICE_TYPE.PLC, cfg.UnitID })
tcd.dispatch_unique(8, handle_timeout)
elseif cfg.WiredModem and self.wd_modem then
util.push_event("conn_test_complete", true)
else
self.self_check_msg("> 无调制解调器，无法测试监控端连接", false)
end
else
if self.self_check_pass then check_complete() end
self.run_test_btn.enable()
end
end
local function exit_self_check(main_pane)
tcd.abort(handle_timeout)
self.net_listen = false
self.run_test_btn.enable()
self.sc_log.remove_all()
main_pane.set_value(1)
end
local check = {}
function check.create(main_pane, settings_cfg, check_sys, style)
local bw_fg_bg      = style.bw_fg_bg
local g_lg_fg_bg    = style.g_lg_fg_bg
local nav_fg_bg     = style.nav_fg_bg
local btn_act_fg_bg = style.btn_act_fg_bg
local btn_dis_fg_bg = style.btn_dis_fg_bg
self.settings = settings_cfg
local sc = Div{parent=check_sys,x=2,y=4,width=49}
TextBox{parent=check_sys,y=2,text=" 反应堆 PLC 自检",fg_bg=bw_fg_bg}
self.sc_log = ListBox{parent=sc,y=1,height=12,width=49,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}
local last_check = { nil, nil }
function self.self_check_msg(msg, success, fail_msg)
if type(msg) == "string" then
last_check[1] = Div{parent=self.sc_log,height=1}
local e = TextBox{parent=last_check[1],text=msg,fg_bg=bw_fg_bg}
last_check[2] = e.get_x()+string.len(msg)
end
if type(fail_msg) == "string" then
TextBox{parent=last_check[1],x=last_check[2],y=1,text=tri(success,"通过","失败"),fg_bg=tri(success,cpair(colors.green,colors._INHERIT),cpair(colors.red,colors._INHERIT))}
if not success then
local fail = Div{parent=self.sc_log,height=#util.strwrap(fail_msg, 46)}
TextBox{parent=fail,x=3,text=fail_msg,fg_bg=cpair(colors.gray,colors.white)}
end
self.self_check_pass = self.self_check_pass and success
end
end
PushButton{parent=sc,y=14,text="\x1b 返回",callback=function()exit_self_check(main_pane)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
self.run_test_btn = PushButton{parent=sc,x=40,y=14,min_width=10,text="运行测试",callback=function()self_check()end,fg_bg=cpair(colors.black,colors.blue),active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
end
function check.receive_sv(side, sender, reply_to, message, distance)
if self.nic ~= nil and self.net_listen then
local frame = self.nic.receive(side, sender, reply_to, message, distance)
if frame and frame.protocol() == PROTOCOL.SCADA_MGMT then
local pkt = comms.mgmt_container().decode(frame)
if pkt then
tcd.abort(handle_timeout)
handle_packet(pkt)
end
end
end
end
function check.conn_test_callback(pass)
local cfg = self.settings
if self.checking_wl then
if not pass then
self.self_check_msg(nil, false, "请确保监控端正在运行并监听无线接口、频道设置正确、可信范围设置正确（若启用）、设施密钥匹配（若设置），且如果您使用无线调制解调器而非末影调制解调器，请确保设备位于同一维度且距离较近")
end
if cfg.WiredModem and self.wd_modem then
self.checking_wl = false
self.self_check_msg("> 检查有线监控端连接...")
comms.set_trusted_range(0)
self.nic = network.nic(self.wd_modem)
self.nic.closeAll()
self.nic.open(cfg.PLC_Channel)
self.net_listen = true
send_sv(MGMT_TYPE.ESTABLISH, { comms.version, comms.CONN_TEST_FWV, DEVICE_TYPE.PLC, cfg.UnitID })
tcd.dispatch_unique(8, handle_timeout)
else
if self.self_check_pass then check_complete() end
self.run_test_btn.enable()
end
else
if not pass then
self.self_check_msg(nil, false, "请确保监控端正在运行并监听有线接口、线路完好且频道设置正确")
end
if self.self_check_pass then check_complete() end
self.run_test_btn.enable()
end
end
return check
