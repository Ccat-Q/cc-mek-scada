local comms       = require("scada-common.comms")
local log         = require("scada-common.log")
local util        = require("scada-common.util")
local types       = require("scada-common.types")

local themes      = require("graphics.themes")

local ioctl       = require("coordinator.ioctl")
local process     = require("coordinator.process")

local apisessions = require("coordinator.session.apisessions")

local PROTOCOL = comms.PROTOCOL
local DEVICE_TYPE = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local MGMT_TYPE = comms.MGMT_TYPE
local CRDN_TYPE = comms.CRDN_TYPE
local UNIT_COMMAND = comms.UNIT_COMMAND
local FAC_COMMAND = comms.FAC_COMMAND

local LINK_TIMEOUT = 60.0

-- wait 5 seconds after initializing a network switch request before being allowed to send more,
-- which avoids repeat duplicate requests
local FAILOVER_GRACE_PERIOD_MS = 5000

local coordinator = {}

---@type crd_config
---@diagnostic disable-next-line: missing-fields
local config = {}

coordinator.config = config

-- load the coordinator configuration
function coordinator.load_config()
    if not settings.load("/coordinator.settings") then return false end

    config.UnitCount = settings.get("UnitCount")
    config.SpeakerVolume = settings.get("SpeakerVolume")
    config.Time24Hour = settings.get("Time24Hour")
    config.GreenPuPellet = settings.get("GreenPuPellet")
    config.TempScale = settings.get("TempScale")
    config.EnergyScale = settings.get("EnergyScale")

    config.MainDisplay = settings.get("MainDisplay")
    config.FlowDisplay = settings.get("FlowDisplay")
    config.UnitDisplays = settings.get("UnitDisplays")

    config.WirelessModem = settings.get("WirelessModem")
    config.WiredModem = settings.get("WiredModem")
    config.PreferWireless = settings.get("PreferWireless")
    config.API_Enabled = settings.get("API_Enabled")
    config.SVR_Channel = settings.get("SVR_Channel")
    config.CRD_Channel = settings.get("CRD_Channel")
    config.PKT_Channel = settings.get("PKT_Channel")
    config.SVR_Timeout = settings.get("SVR_Timeout")
    config.API_Timeout = settings.get("API_Timeout")
    config.TrustedRange = settings.get("TrustedRange")
    config.AuthKey = settings.get("AuthKey")

    config.LogMode = settings.get("LogMode")
    config.LogPath = settings.get("LogPath")
    config.LogDebug = settings.get("LogDebug")

    config.MainTheme = settings.get("MainTheme")
    config.FrontPanelTheme = settings.get("FrontPanelTheme")
    config.ColorMode = settings.get("ColorMode")

    local cfv = util.new_validator()

    cfv.assert_type_int(config.UnitCount)
    cfv.assert_range(config.UnitCount, 1, 4)
    cfv.assert_type_bool(config.Time24Hour)
    cfv.assert_type_bool(config.GreenPuPellet)
    cfv.assert_type_int(config.TempScale)
    cfv.assert_range(config.TempScale, 1, 4)
    cfv.assert_type_int(config.EnergyScale)
    cfv.assert_range(config.EnergyScale, 1, 3)

    cfv.assert_type_table(config.UnitDisplays)

    cfv.assert_type_num(config.SpeakerVolume)
    cfv.assert_range(config.SpeakerVolume, 0, 3)

    cfv.assert_type_bool(config.WirelessModem)
    cfv.assert((config.WiredModem == false) or (type(config.WiredModem) == "string"))
    cfv.assert(config.WirelessModem or (type(config.WiredModem) == "string"))
    cfv.assert_type_bool(config.PreferWireless)

    cfv.assert_type_bool(config.API_Enabled)

    cfv.assert_channel(config.SVR_Channel)
    cfv.assert_channel(config.CRD_Channel)
    cfv.assert_channel(config.PKT_Channel)

    cfv.assert_type_num(config.SVR_Timeout)
    cfv.assert_min(config.SVR_Timeout, 2)
    cfv.assert_type_num(config.API_Timeout)
    cfv.assert_min(config.API_Timeout, 2)

    cfv.assert_type_num(config.TrustedRange)
    cfv.assert_min(config.TrustedRange, 0)
    cfv.assert_type_str(config.AuthKey)

    if type(config.AuthKey) == "string" then
        local len = string.len(config.AuthKey)
        cfv.assert(len == 0 or len >= 8)
    end

    cfv.assert_type_int(config.LogMode)
    cfv.assert_range(config.LogMode, 0, 1)
    cfv.assert_type_str(config.LogPath)
    cfv.assert_type_bool(config.LogDebug)

    cfv.assert_type_int(config.MainTheme)
    cfv.assert_range(config.MainTheme, 1, 2)
    cfv.assert_type_int(config.FrontPanelTheme)
    cfv.assert_range(config.FrontPanelTheme, 1, 2)
    cfv.assert_type_int(config.ColorMode)
    cfv.assert_range(config.ColorMode, 1, themes.COLOR_MODE.NUM_MODES)

    return cfv.valid()
end

-- dmesg print wrapper
---@param message string message
---@param dmesg_tag string tag
---@param working? boolean to use dmesg_working
---@return function? update, function? done
local function log_dmesg(message, dmesg_tag, working)
    local colors = {
        RENDER = colors.green,
        SYSTEM = colors.cyan,
        BOOT = colors.blue,
        COMMS = colors.purple,
        CRYPTO = colors.yellow
    }

    if working then
        return log.dmesg_working(message, dmesg_tag, colors[dmesg_tag])
    else
        log.dmesg(message, dmesg_tag, colors[dmesg_tag])
    end
end

function coordinator.log_render(message) log_dmesg(message, "RENDER") end
function coordinator.log_sys(message) log_dmesg(message, "SYSTEM") end
function coordinator.log_boot(message) log_dmesg(message, "BOOT") end
function coordinator.log_comms(message) log_dmesg(message, "COMMS") end
function coordinator.log_crypto(message) log_dmesg(message, "CRYPTO") end

-- log a message for communications connecting, providing access to progress indication control functions
---@nodiscard
---@param message string
---@return function update, function done
function coordinator.log_comms_connecting(message)
    local update, done = log_dmesg(message, "COMMS", true)
    ---@cast update function
    ---@cast done function
    return update, done
end

-- coordinator communications
---@nodiscard
---@param version string coordinator version
---@param backplane crd_backplane coordinator backplane
---@param sv_watchdog watchdog
function coordinator.comms(version, backplane, sv_watchdog)
    local self = {
        sv_linked = false,
        sv_addr = comms.BROADCAST,
        sv_seq_num = util.time_ms() * 10, -- unique per peer, restarting will not re-use seq nums due to message rate
        sv_r_seq_num = nil,               ---@type nil|integer
        sv_config_err = false,
        failover_init = 0,
        last_est_ack = ESTABLISH_ACK.ALLOW,
        last_api_est_acks = {},
        est_start = 0,
        est_last = 0,
        est_tick_waiting = nil,
        est_task_done = nil
    }

    local tx_nic = backplane.active_nic()
    local wl_nic = backplane.wireless_nic()

    if config.WirelessModem then
        comms.set_trusted_range(config.TrustedRange)
    end

    -- pass config to apisessions
    if config.API_Enabled and wl_nic then
        apisessions.init(wl_nic, config)
    end

    --#region PRIVATE FUNCTIONS --

    -- send a packet to the supervisor
    ---@param msg_type MGMT_TYPE|CRDN_TYPE
    ---@param msg table
    local function _send_sv(protocol, msg_type, msg)
        local frame = comms.scada_frame()
        local cntnr ---@type mgmt_container|crdn_container

        if protocol == PROTOCOL.SCADA_MGMT then
            cntnr = comms.mgmt_container()
        elseif protocol == PROTOCOL.SCADA_CRDN then
            cntnr = comms.crdn_container()
        else return end

        cntnr.make(msg_type, msg)
        frame.make(self.sv_addr, self.sv_seq_num, protocol, cntnr.raw_packet())

        tx_nic.transmit(config.SVR_Channel, config.CRD_Channel, frame)
        self.sv_seq_num = self.sv_seq_num + 1
    end

    -- send an API establish request response
    ---@param rx_frame scada_frame
    ---@param ack ESTABLISH_ACK
    ---@param data any?
    local function _send_api_establish_ack(rx_frame, ack, data)
        local tx_frame, mgmt = comms.scada_frame(), comms.mgmt_container()

        mgmt.make(MGMT_TYPE.ESTABLISH, { ack, data })
        tx_frame.make(rx_frame.src_addr(), rx_frame.seq_num() + 1, PROTOCOL.SCADA_MGMT, mgmt.raw_packet())

---@diagnostic disable-next-line: need-check-nil
        wl_nic.transmit(config.PKT_Channel, config.CRD_Channel, tx_frame)
        self.last_api_est_acks[rx_frame.src_addr()] = ack
    end

    -- send establish request
    ---@param nic nic nic to transmit on
    local function _send_establish(nic)
        local ini_nic = tx_nic
        tx_nic = nic

        self.sv_r_seq_num = nil
        _send_sv(PROTOCOL.SCADA_MGMT, MGMT_TYPE.ESTABLISH, { comms.version, version, DEVICE_TYPE.CRD })

        tx_nic = ini_nic
    end

    -- keep alive ack
    ---@param srv_time integer
    local function _send_keep_alive_ack(srv_time)
        _send_sv(PROTOCOL.SCADA_MGMT, MGMT_TYPE.KEEP_ALIVE, { srv_time, util.time() })
    end

    --#endregion

    --#region PUBLIC FUNCTIONS --

    ---@class coord_comms
    local public = {}

    -- switch the current active NIC
    ---@param new_nic nic
    function public.switch_nic(new_nic)
        if tx_nic.is_connected() then
            -- try to gracefully switch, we have an intact continuous connection
            log.info(util.c("正在将链路切换到已重连的接口 ", new_nic.phy_name(), "（原 ", tx_nic.phy_name(), "）"))

            tx_nic = new_nic
            _send_sv(PROTOCOL.SCADA_MGMT, MGMT_TYPE.SWITCH_NET, {})
        else
            -- can't gracefully switch, the other NIC was lost
            log.info(util.c("正在关闭 ", tx_nic.phy_name(), " 上的链路，切换到 ", new_nic.phy_name()))

            tx_nic = new_nic
            sv_watchdog.cancel()
            public.unlink()
        end
    end

    -- maintain the supervisor connection, which consists of establishing it and handling link failover
    ---@param abort boolean? true to print out cancel info if not linked (use on program terminate)
    ---@return boolean ok, boolean start_ui
    function public.manage_link(abort)
        local ok, start_ui = true, false

        if self.sv_linked then
            -- handle connection failover
            local act_nic = backplane.active_nic()
            if (act_nic ~= tx_nic) and act_nic.is_network_up() and ((util.time_ms() - self.failover_init) > FAILOVER_GRACE_PERIOD_MS) then
                log.info(util.c("主接口 ", act_nic.phy_name(), " 已恢复，正在请求切换链路"))

                tx_nic = act_nic
                _send_sv(PROTOCOL.SCADA_MGMT, MGMT_TYPE.SWITCH_NET, {})

                self.failover_init = util.time_ms()
            end

            -- handle UI
            if self.est_tick_waiting ~= nil then
                self.est_task_done(true)
                self.est_tick_waiting = nil
                self.est_task_done = nil
                start_ui = true
            end
        else
            local a_nic, s_nic = backplane.active_nic(), backplane.standby_nic()
            local e_nic = nil

            if a_nic.is_network_up() then
                e_nic = a_nic
            elseif s_nic and s_nic.is_network_up() then
                e_nic = s_nic
            end

            if self.est_tick_waiting == nil then
                self.est_start = os.clock()
                self.est_last = self.est_start

                self.est_tick_waiting, self.est_task_done =
                    coordinator.log_comms_connecting("正在尝试连接到已配置的上位机（频道 " .. config.SVR_Channel .. "）")

                if e_nic then _send_establish(e_nic) end
            else
                self.est_tick_waiting(math.max(0, LINK_TIMEOUT - (os.clock() - self.est_start)))
            end

            if abort or (os.clock() - self.est_start) >= LINK_TIMEOUT then
                self.est_task_done(false)

                if abort then
                    coordinator.log_comms("上位机连接尝试已被用户取消")
                elseif self.sv_config_err then
                    coordinator.log_comms("上位机机组数量与协调器机组数量不匹配，请检查配置")
                elseif not self.sv_linked then
                    if self.last_est_ack == ESTABLISH_ACK.DENY then
                        coordinator.log_comms("上位机连接尝试被拒绝")
                    elseif self.last_est_ack == ESTABLISH_ACK.COLLISION then
                        coordinator.log_comms("上位机连接因冲突而失败")
                    elseif self.last_est_ack == ESTABLISH_ACK.BAD_VERSION then
                        coordinator.log_comms("上位机连接因版本不匹配而失败")
                    else
                        coordinator.log_comms("上位机连接失败，无有效响应")
                    end
                end

                ok = false
            elseif self.sv_config_err then
                self.est_task_done(false)
                coordinator.log_comms("上位机机组数量与协调器机组数量不匹配，请检查配置")
                ok = false
            elseif (os.clock() - self.est_last) > 1.0 then
                if e_nic then _send_establish(e_nic) end
                self.est_last = os.clock()
            end
        end

        return ok, start_ui
    end

    -- unlink from the server
    function public.unlink()
        self.sv_addr = comms.BROADCAST
        self.sv_linked = false
        self.sv_r_seq_num = nil
        ioctl.fp_link_state(types.PANEL_LINK_STATE.DISCONNECTED)
    end

    -- close the connection to the server
    function public.close()
        sv_watchdog.cancel()
        _send_sv(PROTOCOL.SCADA_MGMT, MGMT_TYPE.CLOSE, {})
        public.unlink()
    end

    -- send the resume ready state to the supervisor
    ---@param settings auto_ctl_cfg auto control settings
    function public.send_ready(settings)
        _send_sv(PROTOCOL.SCADA_CRDN, CRDN_TYPE.PROCESS_READY, settings)
    end

    -- send a facility command
    ---@param cmd FAC_COMMAND command
    ---@param option any? optional option options for the optional options (like waste mode)
    function public.send_fac_command(cmd, option)
        _send_sv(PROTOCOL.SCADA_CRDN, CRDN_TYPE.FAC_CMD, { cmd, option })
    end

    -- send the auto process control configuration with a start command
    ---@param settings auto_ctl_cfg auto control settings
    function public.send_auto_start(settings)
        _send_sv(PROTOCOL.SCADA_CRDN, CRDN_TYPE.FAC_CMD, { FAC_COMMAND.START, table.unpack(settings) })
    end

    -- send a unit command
    ---@param cmd UNIT_COMMAND command
    ---@param unit integer unit ID
    ---@param option any? optional option options for the optional options (like burn rate)
    function public.send_unit_command(cmd, unit, option)
        _send_sv(PROTOCOL.SCADA_CRDN, CRDN_TYPE.UNIT_CMD, { cmd, unit, option })
    end

    -- parse a packet
    ---@param side string
    ---@param sender integer
    ---@param reply_to integer
    ---@param message any
    ---@param distance integer
    ---@return mgmt_packet|crdn_packet|nil packet
    function public.parse_packet(side, sender, reply_to, message, distance)
        local pkt, nic = nil, backplane.nics[side]

        if nic then
            local frame = nic.receive(side, sender, reply_to, message, distance)

            if frame then
                if frame.protocol() == PROTOCOL.SCADA_MGMT then
                    pkt = comms.mgmt_container().decode(frame)
                elseif frame.protocol() == PROTOCOL.SCADA_CRDN then
                    pkt = comms.crdn_container().decode(frame)
                else
                    log.debug("parse_packet(" .. side .. ")：尝试解析非法数据包类型 " .. frame.protocol(), true)
                end
            end
        else
            log.error("parse_packet(" .. side .. ")：从没有 nic 的接口收到数据包？")
        end

        return pkt
    end

    -- handle a packet
    ---@param packet mgmt_packet|crdn_packet|nil
    ---@return boolean close_ui
    function public.handle_packet(packet)
        local was_linked = self.sv_linked

        if packet ~= nil then
            local l_chan = packet.scada_frame.local_channel()
            local r_chan = packet.scada_frame.remote_channel()
            local src_addr = packet.scada_frame.src_addr()
            local protocol = packet.scada_frame.protocol()

            if l_chan ~= config.CRD_Channel then
                log.debug("在未配置的频道 " .. l_chan .. " 上收到数据包", true)
            elseif r_chan == config.PKT_Channel then
                if not config.API_Enabled then
                    -- log.debug("discarding pocket API packet due to the API being disabled")
                elseif not self.sv_linked then
                    log.debug("在连接到上位机之前丢弃 Pocket API 数据包")
                elseif protocol == PROTOCOL.SCADA_CRDN then
                    ---@cast packet crdn_packet
                    -- look for an associated session
                    local session = apisessions.find_session(src_addr)

                    -- coordinator packet
                    if session ~= nil then
                        -- pass the packet onto the session handler
                        session.in_queue.push_network(packet)
                    else
                        -- any other packet should be session related, discard it
                        log.debug("丢弃没有已知会话的 SCADA_CRDN 数据包")
                    end
                elseif protocol == PROTOCOL.SCADA_MGMT then
                    ---@cast packet mgmt_packet
                    -- look for an associated session
                    local session = apisessions.find_session(src_addr)

                    -- SCADA management packet
                    if session ~= nil then
                        -- pass the packet onto the session handler
                        session.in_queue.push_network(packet)
                    elseif packet.type == MGMT_TYPE.ESTABLISH then
                        -- establish a new session
                        -- validate packet and continue
                        if packet.length == 4 then
                            local comms_v = util.strval(packet.data[1])
                            local firmware_v = util.strval(packet.data[2])
                            local dev_type = packet.data[3]
                            local api_v = util.strval(packet.data[4])

                            if comms_v ~= comms.version then
                                if self.last_api_est_acks[src_addr] ~= ESTABLISH_ACK.BAD_VERSION then
                                    log.info(util.c("正在丢弃通信版本不正确的 API 建立数据包 v", comms_v, "（应为 v", comms.version, "）"))
                                end

                                _send_api_establish_ack(packet.scada_frame, ESTABLISH_ACK.BAD_VERSION)
                            elseif api_v ~= comms.api_version then
                                if self.last_api_est_acks[src_addr] ~= ESTABLISH_ACK.BAD_API_VERSION then
                                    log.info(util.c("正在丢弃 API 版本不正确的 API 建立数据包 v", api_v, "（应为 v", comms.api_version, "）"))
                                end

                                _send_api_establish_ack(packet.scada_frame, ESTABLISH_ACK.BAD_API_VERSION)
                            elseif dev_type == DEVICE_TYPE.PKT then
                                -- pocket linking request
                                local id = apisessions.establish_session(src_addr, packet.scada_frame.seq_num(), firmware_v)
                                coordinator.log_comms(util.c("API_ESTABLISH: Pocket（", firmware_v, "）[@", src_addr, "] 已连接，会话 ID ", id))

                                local conf = ioctl.get_db().facility.conf
                                _send_api_establish_ack(packet.scada_frame, ESTABLISH_ACK.ALLOW, { conf.num_units, conf.cooling, conf.com_waste, conf.ess })
                            else
                                log.debug(util.c("API_ESTABLISH: Pocket 频道上收到设备的非法建立数据包 ", dev_type))
                                _send_api_establish_ack(packet.scada_frame, ESTABLISH_ACK.DENY)
                            end
                        else
                            log.debug("无效的建立数据包（在 API 监听频道上）")
                            _send_api_establish_ack(packet.scada_frame, ESTABLISH_ACK.DENY)
                        end
                    else
                        -- any other packet should be session related, discard it
                        log.debug(util.c("丢弃来自电脑 ", src_addr, " 的无已知会话 Pocket SCADA_MGMT 数据包"))
                    end
                else
                    log.debug("Pocket 频道上的非法数据包类型 " .. protocol, true)
                end
            elseif r_chan == config.SVR_Channel then
                -- check sequence number
                if self.sv_r_seq_num == nil then
                    self.sv_r_seq_num = packet.scada_frame.seq_num() + 1
                elseif self.sv_r_seq_num ~= packet.scada_frame.seq_num() then
                    log.warning("序列乱序：期望 = " .. self.sv_r_seq_num .. "，实际 = " .. packet.scada_frame.seq_num())
                    return false
                elseif self.sv_linked and src_addr ~= self.sv_addr then
                    log.debug("在已连接时收到来自未知电脑 " .. src_addr .. " 的数据包；频道是否被其他系统占用？")
                    return false
                else
                    self.sv_r_seq_num = packet.scada_frame.seq_num() + 1
                end

                -- feed watchdog on valid sequence number
                sv_watchdog.feed()

                -- handle packet
                if protocol == PROTOCOL.SCADA_CRDN then
                    ---@cast packet crdn_packet
                    if self.sv_linked then
                        if packet.type == CRDN_TYPE.INITIAL_BUILDS then
                            if packet.length == 2 then
                                -- record builds
                                local fac_builds  = ioctl.record_facility_builds(packet.data[1])
                                local unit_builds = ioctl.record_unit_builds(packet.data[2])

                                if fac_builds and unit_builds then
                                    -- acknowledge receipt of builds
                                    _send_sv(PROTOCOL.SCADA_CRDN, CRDN_TYPE.INITIAL_BUILDS, {})
                                else
                                    log.debug("收到无效的 INITIAL_BUILDS 数据包")
                                end
                            else
                                log.debug("INITIAL_BUILDS 数据包长度不匹配")
                            end
                        elseif packet.type == CRDN_TYPE.FAC_BUILDS then
                            if packet.length == 1 then
                                -- record facility builds
                                if ioctl.record_facility_builds(packet.data[1]) then
                                    -- acknowledge receipt of builds
                                    _send_sv(PROTOCOL.SCADA_CRDN, CRDN_TYPE.FAC_BUILDS, {})
                                else
                                    log.debug("收到无效的 FAC_BUILDS 数据包")
                                end
                            else
                                log.debug("FAC_BUILDS 数据包长度不匹配")
                            end
                        elseif packet.type == CRDN_TYPE.FAC_STATUS then
                            -- update facility status
                            if not ioctl.update_facility_status(packet.data) then
                                log.debug("收到无效的 FAC_STATUS 数据包")
                            end
                        elseif packet.type == CRDN_TYPE.FAC_CMD then
                            -- facility command acknowledgement
                            if packet.length >= 2 then
                                local cmd = packet.data[1]
                                local ack = packet.data[2] == true

                                if cmd == FAC_COMMAND.SCRAM_ALL then
                                    process.fac_ack(cmd, ack)
                                elseif cmd == FAC_COMMAND.STOP then
                                    process.fac_ack(cmd, ack)
                                elseif cmd == FAC_COMMAND.START then
                                    if packet.length == 9 then
                                        process.start_ack_handle({ table.unpack(packet.data, 2) })
                                    else
                                        log.debug("SCADA_CRDN 工艺启动（带配置）确认回显数据包长度不匹配")
                                    end
                                elseif cmd == FAC_COMMAND.ACK_ALL_ALARMS then
                                    process.fac_ack(cmd, ack)
                                elseif cmd == FAC_COMMAND.SET_WASTE_MODE then
                                    process.waste_ack_handle(packet.data[2])
                                elseif cmd == FAC_COMMAND.SET_PU_FB then
                                    process.pu_fb_ack_handle(packet.data[2])
                                elseif cmd == FAC_COMMAND.SET_SPS_LP then
                                    process.sps_lp_ack_handle(packet.data[2])
                                else
                                    log.debug(util.c("收到未知命令 ", cmd, " 的设施命令确认"))
                                end
                            else
                                log.debug("SCADA_CRDN 设施命令确认数据包长度不匹配")
                            end
                        elseif packet.type == CRDN_TYPE.UNIT_BUILDS then
                            -- record builds
                            if packet.length == 1 then
                                if ioctl.record_unit_builds(packet.data[1]) then
                                    -- acknowledge receipt of builds
                                    _send_sv(PROTOCOL.SCADA_CRDN, CRDN_TYPE.UNIT_BUILDS, {})
                                else
                                    log.debug("收到无效的 UNIT_BUILDS 数据包")
                                end
                            else
                                log.debug("UNIT_BUILDS 数据包长度不匹配")
                            end
                        elseif packet.type == CRDN_TYPE.UNIT_STATUSES then
                            -- update statuses
                            if not ioctl.update_unit_statuses(packet.data) then
                                log.debug("收到无效的 UNIT_STATUSES 数据包")
                            end
                        elseif packet.type == CRDN_TYPE.UNIT_CMD then
                            -- unit command acknowledgement
                            if packet.length == 3 then
                                local cmd = packet.data[1]
                                local unit_id = packet.data[2]
                                local ack = packet.data[3] == true

                                local unit = ioctl.get_db().units[unit_id]

                                if unit ~= nil then
                                    if cmd == UNIT_COMMAND.SCRAM then
                                        process.unit_ack(unit_id, cmd, ack)
                                    elseif cmd == UNIT_COMMAND.START then
                                        process.unit_ack(unit_id, cmd, ack)
                                    elseif cmd == UNIT_COMMAND.RESET_RPS then
                                        process.unit_ack(unit_id, cmd, ack)
                                    elseif cmd == UNIT_COMMAND.ACK_ALL_ALARMS then
                                        process.unit_ack(unit_id, cmd, ack)
                                    else
                                        log.debug(util.c("收到命令 ", cmd, " 的不受支持的机组命令确认"))
                                    end
                                else
                                    log.debug(util.c("收到未知机组 ", unit_id, " 的机组命令确认"))
                                end
                            else
                                log.debug("SCADA_CRDN 机组命令确认数据包长度不匹配")
                            end
                        else
                            log.debug("收到未知 SCADA_CRDN 数据包类型 " .. packet.type)
                        end
                    else
                        log.debug("在连接之前丢弃 SCADA_CRDN 数据包")
                    end
                elseif protocol == PROTOCOL.SCADA_MGMT then
                    ---@cast packet mgmt_packet
                    if self.sv_linked then
                        if packet.type == MGMT_TYPE.KEEP_ALIVE then
                            -- keep alive request received, echo back
                            if packet.length == 1 then
                                local timestamp = packet.data[1]
                                local trip_time = util.time() - timestamp

                                if trip_time > 750 then
                                    log.warning("协调器 KEEP_ALIVE 往返时间 > 750ms（" .. trip_time .. "ms）")
                                end

                                -- log.debug("coordinator RTT = " .. trip_time .. "ms")

                                ioctl.get_db().facility.ps.publish("sv_ping", trip_time)

                                _send_keep_alive_ack(timestamp)
                            else
                                log.debug("SCADA 保活数据包长度不匹配")
                            end
                        elseif packet.type == MGMT_TYPE.CLOSE then
                            -- handle session close
                            sv_watchdog.cancel()
                            public.unlink()
                            log.info("服务器连接已被远程主机关闭")
                        else
                            log.debug("收到未知 SCADA_MGMT 数据包类型 " .. packet.type)
                        end
                    elseif packet.type == MGMT_TYPE.ESTABLISH then
                        -- connection with supervisor established
                        if packet.length == 2 then
                            local est_ack = packet.data[1]
                            local sv_config = packet.data[2]

                            if est_ack == ESTABLISH_ACK.ALLOW then
                                -- reset to disconnected before validating
                                ioctl.fp_link_state(types.PANEL_LINK_STATE.DISCONNECTED)

                                if type(sv_config) == "table" and #sv_config == 5 then
                                    -- get configuration

                                    ---@class facility_conf
                                    local conf = {
                                        num_units = sv_config[1], ---@type integer
                                        cooling = sv_config[2],   ---@type sv_cooling_conf
                                        com_waste = sv_config[4], ---@type boolean
                                        ess = sv_config[5]        ---@type ESS
                                    }

                                    if not ioctl.set_mek_config(sv_config[3]) then
                                        log.warning("收到无效的 Mekanism 配置表，建立失败")
                                    elseif conf.num_units == config.UnitCount then
                                        tx_nic = backplane.nics[packet.scada_frame.interface()]

                                        log.info(util.c("上位机建立请求已批准，已连接到 SV（CID#", src_addr, "），位于 ", tx_nic.phy_name()))

                                        -- init io controller
                                        ioctl.init(conf, public, config.TempScale, config.EnergyScale)

                                        self.sv_addr = src_addr
                                        self.sv_linked = true
                                        self.sv_config_err = false

                                        ioctl.fp_link_state(types.PANEL_LINK_STATE.LINKED)
                                    else
                                        self.sv_config_err = true
                                        log.warning("上位机配置的机组数量与协调器配置不匹配，建立失败")
                                    end
                                else
                                    log.debug("收到无效的上位机配置表，建立失败")
                                end
                            else
                                log.debug("不支持 SCADA_MGMT 建立数据包回复（长度 = 2）")
                            end

                            self.last_est_ack = est_ack
                        elseif packet.length == 1 then
                            local est_ack = packet.data[1]

                            if est_ack == ESTABLISH_ACK.DENY then
                                if self.last_est_ack ~= est_ack then
                                    ioctl.fp_link_state(types.PANEL_LINK_STATE.DENIED)
                                    log.info("上位机连接被拒绝")
                                end
                            elseif est_ack == ESTABLISH_ACK.COLLISION then
                                if self.last_est_ack ~= est_ack then
                                    ioctl.fp_link_state(types.PANEL_LINK_STATE.COLLISION)
                                    log.warning("上位机连接因冲突被拒绝")
                                end
                            elseif est_ack == ESTABLISH_ACK.BAD_VERSION then
                                if self.last_est_ack ~= est_ack then
                                    ioctl.fp_link_state(types.PANEL_LINK_STATE.BAD_VERSION)
                                    log.warning("上位机通信版本不匹配")
                                end
                            else
                                log.debug("不支持 SCADA_MGMT 建立数据包回复（长度 = 1）")
                            end

                            self.last_est_ack = est_ack
                        else
                            log.debug("SCADA_MGMT 建立数据包长度不匹配")
                        end
                    else
                        log.debug("在连接之前丢弃非链路 SCADA_MGMT 数据包")
                    end
                else
                    log.debug("上位机监听频道上的非法数据包类型 " .. protocol, true)
                end
            else
                log.debug("收到未知频道 " .. r_chan .. " 的数据包", true)
            end
        end

        return was_linked and not self.sv_linked
    end

    -- check if the coordinator is still linked to the supervisor
    ---@nodiscard
    function public.is_linked() return self.sv_linked end

    --#endregion

    return public
end

return coordinator
