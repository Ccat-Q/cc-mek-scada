--
-- Coordinator System Core Peripheral Backplane
--

local log         = require("scada-common.log")
local network     = require("scada-common.network")
local ppm         = require("scada-common.ppm")
local util        = require("scada-common.util")

local coordinator = require("coordinator.coordinator")
local ioctl       = require("coordinator.ioctl")
local sounder     = require("coordinator.sounder")

local println = util.println

local log_sys    = coordinator.log_sys
local log_boot   = coordinator.log_boot
local log_comms  = coordinator.log_comms

---@class crd_backplane
local backplane = {}

local _bp = {
    smem = nil,     ---@type crd_shared_memory

    wlan_pref = true,
    lan_iface = "",

    act_nic = nil,  ---@type nic
    wd_nic = nil,   ---@type nic|nil
    wl_nic = nil,   ---@type nic|nil
    nic_map = {},   ---@type nic[] connected nics

    speaker = nil,  ---@type Speaker|nil

    ---@class crd_displays
    displays = {
        main = nil,         ---@type Monitor|nil
        main_iface = "",
        flow = nil,         ---@type Monitor|nil
        flow_iface = "",
        unit_displays = {}, ---@type Monitor[]
        unit_ifaces = {}    ---@type string[]
    }
}

-- network interfaces indexed by peripheral names
backplane.nics = _bp.nic_map

-- initialize the display peripheral backplane
---@param config crd_config
---@return boolean success, string error_msg
function backplane.init_displays(config)
    local displays = _bp.displays

    local w, h, _

    log.info("BKPLN: DISPLAY INIT")

    -- monitor configuration verification

    local mon_cfv = util.new_validator()

    mon_cfv.assert_type_str(config.MainDisplay)
    mon_cfv.assert_type_str(config.FlowDisplay)

    mon_cfv.assert_eq(#config.UnitDisplays, config.UnitCount)
    for i = 1, #config.UnitDisplays do
        mon_cfv.assert_type_str(config.UnitDisplays[i])
    end

    if not mon_cfv.valid() then
        return false, "监视器配置无效。"
    end

    -- setup and check display peripherals

    -- main display

    local disp, iface = ppm.get_periph(config.MainDisplay), config.MainDisplay

    ---@cast disp Monitor
    displays.main = disp
    displays.main_iface = iface

    log.info("BKPLN: DISPLAY LINK_" .. util.trinary(disp, "UP", "DOWN") .. " MAIN/" .. iface)

    ioctl.fp_monitor_state("main", util.trinary(disp, 2, 1))

    if not disp then
        return false, "主监视器未连接。"
    end

    disp.setTextScale(0.5)
    w, _ = ppm.monitor_block_size(disp.getSize())
    if w ~= 8 then
        log.info("BKPLN: DISPLAY MAIN/" .. iface .. " BAD RESOLUTION")
        return false, util.c("主监视器宽度不正确（当前 ", w, "，必须为 8）。")
    end

    -- flow display

    disp, iface = ppm.get_periph(config.FlowDisplay), config.FlowDisplay

    ---@cast disp Monitor
    displays.flow = disp
    displays.flow_iface = iface

    log.info("BKPLN: DISPLAY LINK_" .. util.trinary(disp, "UP", "DOWN") .. " FLOW/" .. iface)

    ioctl.fp_monitor_state("flow", util.trinary(disp, 2, 1))

    if not disp then
        return false, "流程监视器未连接。"
    end

    disp.setTextScale(0.5)
    w, _ = ppm.monitor_block_size(disp.getSize())
    if w ~= 8 then
        log.info("BKPLN: DISPLAY FLOW/" .. iface .. " BAD RESOLUTION")
        return false, util.c("流程监视器宽度不正确（当前 ", w, "，必须为 8）。")
    end

    -- unit display(s)

    for i = 1, config.UnitCount do
        disp, iface = ppm.get_periph(config.UnitDisplays[i]), config.UnitDisplays[i]

        ---@cast disp Monitor
        displays.unit_displays[i] = disp
        displays.unit_ifaces[i] = iface

        log.info("BKPLN: DISPLAY LINK_" .. util.trinary(disp, "UP", "DOWN") .. " UNIT_" .. i .. "/" .. iface)

        ioctl.fp_monitor_state(i, util.trinary(disp, 2, 1))

        if not disp then
            return false, "机组 " .. i .. " 的监视器未连接。"
        end

        disp.setTextScale(0.5)
        w, h = ppm.monitor_block_size(disp.getSize())
        if w ~= 4 or h ~= 4 then
            log.info("BKPLN: DISPLAY UNIT_" .. i .. "/" .. iface .. " BAD RESOLUTION")
            return false, util.c("机组 ", i, " 的监视器尺寸不正确（当前为 ", w, " × ", h, "，必须为 4 × 4）。")
        end
    end

    log.info("BKPLN: DISPLAY INIT OK")

    return true, ""
end

-- initialize the system peripheral backplane
---@param config crd_config
---@param __shared_memory crd_shared_memory
---@return boolean success
function backplane.init(config, __shared_memory)
    _bp.smem      = __shared_memory
    _bp.wlan_pref = config.PreferWireless
    _bp.lan_iface = config.WiredModem

    -- Modem Init

    -- init wired NIC
    if type(_bp.lan_iface) == "string" then
        local modem  = ppm.get_modem(_bp.lan_iface)
        local wd_nic = network.nic(modem, config.SVR_Channel)

        log.info("BKPLN: WIRED PHY_" .. util.trinary(modem, "UP ", "DOWN ") .. _bp.lan_iface)
        log_comms("有线通信调制解调器 " .. util.trinary(modem, "已连接", "未找到"))

        _bp.wd_nic  = wd_nic
        _bp.act_nic = wd_nic -- set this as active for now
        _bp.nic_map[_bp.lan_iface] = wd_nic

        wd_nic.closeAll()
        wd_nic.open(config.CRD_Channel)

        ioctl.fp_has_wd_modem(modem ~= nil)
    end

    -- init wireless NIC(s)
    if config.WirelessModem then
        local modem, iface = ppm.get_wireless_modem()
        local wl_nic       = network.nic(modem, config.SVR_Channel)

        log.info("BKPLN: WIRELESS PHY_" .. util.trinary(modem, "UP ", "DOWN") .. (iface or ""))
        log_comms("无线通信调制解调器 " .. util.trinary(modem, "已连接", "未找到"))

        -- set this as active if connected or if both modems are disconnected and this is preferred
        if (modem and _bp.wlan_pref) or not (_bp.act_nic and _bp.act_nic.is_connected()) then
            _bp.act_nic = wl_nic
            log.info("BKPLN: 已将活动接口切换为优先无线")
        end

        _bp.wl_nic = wl_nic
        if iface then _bp.nic_map[iface] = wl_nic end

        wl_nic.closeAll()
        wl_nic.open(config.CRD_Channel)

        ioctl.fp_has_wl_modem(modem ~= nil)
    end

    -- at least one comms modem is required
    if not ((_bp.wd_nic and _bp.wd_nic.is_connected()) or (_bp.wl_nic and _bp.wl_nic.is_connected())) then
        log_comms("未找到通信调制解调器")
        println("startup> 未找到通信调制解调器")
        log.warning("BKPLN: 启动时未找到通信调制解调器")
        return false
    end

    -- Speaker Init

    local speaker = ppm.get_device("speaker")

    ---@cast speaker Speaker|nil
    _bp.speaker = speaker

    if not _bp.speaker then
        log_boot("未找到报警扬声器")

        println("startup> 未找到扬声器")
        log.fatal("BKPLN: 未找到报警扬声器")

        return false
    else
        log.info("BKPLN: SPEAKER LINK_UP " .. ppm.get_iface(_bp.speaker))
        log_boot("报警扬声器已连接")

        local sounder_start = util.time_ms()
        sounder.init(_bp.speaker, config.SpeakerVolume)

        log_boot("音调生成耗时 " .. (util.time_ms() - sounder_start) .. "ms")
        log_sys("报警器已配置")

        ioctl.fp_has_speaker(true)
    end

    return true
end

-- get the active NIC
function backplane.active_nic() return _bp.act_nic end

-- get the standby NIC
---@return nic|nil
function backplane.standby_nic() return util.trinary(_bp.act_nic == _bp.wl_nic, _bp.wd_nic, _bp.wl_nic) end

-- get the wireless NIC
function backplane.wireless_nic() return _bp.wl_nic end

-- get the configured displays
function backplane.displays() return _bp.displays end

-- periodic backplane peripheral tasks
function backplane.periodic()
    if _bp.wd_nic then ioctl.fp_has_wd_net(_bp.wd_nic.periodic()) end
    if _bp.wl_nic then ioctl.fp_has_wl_net(_bp.wl_nic.periodic()) end
end

-- handle a backplane peripheral attach
---@param type string
---@param device ppm_generic
---@param iface string
function backplane.attach(type, device, iface)
    local MQ__RENDER_DATA = _bp.smem.q_types.MQ__RENDER_DATA

    local wl_nic, wd_nic = _bp.wl_nic, _bp.wd_nic

    local comms = _bp.smem.crd_sys.coord_comms

    if type == "modem" then
        ---@cast device Modem

        local m_is_wl = device.isWireless()

        log.info(util.c("BKPLN: ", util.trinary(m_is_wl, "WIRELESS", "WIRED"), " PHY_ATTACH ", iface))

        if wd_nic and (_bp.lan_iface == iface) then
            -- connect this as the wired NIC
            wd_nic.connect(device)
            _bp.nic_map[iface] = wd_nic

            log.info("BKPLN: WIRED PHY_UP " .. iface)
            log_sys("有线通信调制解调器已重新连接")

            ioctl.fp_has_wd_modem(true)

            if (_bp.act_nic ~= wd_nic) and not _bp.wlan_pref then
                -- switch back to preferred wired
                _bp.act_nic = wd_nic

                comms.switch_nic(_bp.act_nic)
                log.info("BKPLN: 已将通信切换到有线调制解调器（优先）")
            end
        elseif wl_nic and (not wl_nic.is_connected()) and m_is_wl then
            -- connect this as the wireless NIC
            wl_nic.connect(device)
            _bp.nic_map[iface] = wl_nic

            log.info("BKPLN: WIRELESS PHY_UP " .. iface)
            log_sys("无线通信调制解调器已重新连接")

            ioctl.fp_has_wl_modem(true)

            if (_bp.act_nic ~= wl_nic) and _bp.wlan_pref then
                -- switch back to preferred wireless
                _bp.act_nic = wl_nic

                comms.switch_nic(_bp.act_nic)
                log.info("BKPLN: 已将通信切换到无线调制解调器（优先）")
            end
        elseif wl_nic and m_is_wl then
            -- the wireless NIC already has a modem
            device.closeAll()

            log_sys("备用无线调制解调器已连接")
            log.info("BKPLN: 备用无线调制解调器已连接")
        else
            device.closeAll()

            log_sys("未分配的调制解调器已连接")
            log.warning("BKPLN: 未分配的调制解调器已连接")
        end
    elseif type == "monitor" then
        ---@cast device Monitor

        local is_used = false

        log.info("BKPLN: DISPLAY LINK_UP " .. iface)

        if _bp.displays.main_iface == iface then
            is_used = true

            _bp.displays.main = device

            log.info("BKPLN: main display reconnected")
            ioctl.fp_monitor_state("main", 2)
        elseif _bp.displays.flow_iface == iface then
            is_used = true

            _bp.displays.flow = device

            log.info("BKPLN: flow display reconnected")
            ioctl.fp_monitor_state("flow", 2)
        else
            for idx, monitor in ipairs(_bp.displays.unit_ifaces) do
                if monitor == iface then
                    is_used = true

                    _bp.displays.unit_displays[idx] = device

                    log.info("BKPLN: unit " .. idx .. " display reconnected")
                    ioctl.fp_monitor_state(idx, 2)
                    break
                end
            end
        end

        -- notify renderer if it is using it
        if is_used then
            log_sys(util.c("已配置的监视器 ", iface, " 已重新连接"))
            _bp.smem.q.mq_render.push_data(MQ__RENDER_DATA.MON_CONNECT, iface)
        else
            log_sys(util.c("未使用的监视器 ", iface, " 已连接"))
        end
    elseif type == "speaker" then
        ---@cast device Speaker

        log.info("BKPLN: SPEAKER LINK_UP " .. iface)

        sounder.reconnect(device)

        log_sys("报警扬声器已重新连接")

        ioctl.fp_has_speaker(true)
    end
end

-- handle a backplane peripheral detach
---@param type string
---@param device ppm_generic
---@param iface string
function backplane.detach(type, device, iface)
    local MQ__RENDER_CMD  = _bp.smem.q_types.MQ__RENDER_CMD
    local MQ__RENDER_DATA = _bp.smem.q_types.MQ__RENDER_DATA

    local wl_nic, wd_nic = _bp.wl_nic, _bp.wd_nic

    local comms = _bp.smem.crd_sys.coord_comms

    if type == "modem" then
        ---@cast device Modem

        log.info(util.c("BKPLN: PHY_DETACH ", iface))

        _bp.nic_map[iface] = nil

        if wd_nic and wd_nic.is_modem(device) then
            wd_nic.disconnect()
            log.info("BKPLN: WIRED PHY_DOWN " .. iface)

            ioctl.fp_has_wd_modem(false)
        elseif wl_nic and wl_nic.is_modem(device) then
            wl_nic.disconnect()
            log.info("BKPLN: WIRELESS PHY_DOWN " .. iface)

            ioctl.fp_has_wl_modem(false)
        end

        -- we only care if this is our active comms modem
        if _bp.act_nic.is_modem(device) then
            log_sys("活动通信调制解调器已断开")
            log.warning("BKPLN: 活动通信调制解调器已断开")

            -- failover and try to find a new comms modem
            if _bp.act_nic == wl_nic then
                -- wireless active disconnected
                -- try to find another wireless modem, otherwise switch to wired
                local modem, m_iface = ppm.get_wireless_modem()
                if wl_nic and modem then
                    log_sys("找到另一个无线调制解调器，正在使用它进行通信")
                    log.info("BKPLN: 找到另一个无线调制解调器，正在使用它进行通信")

                    wl_nic.connect(modem)

                    log.info("BKPLN: WIRELESS PHY_UP " .. m_iface)

                    ioctl.fp_has_wl_modem(true)
                elseif wd_nic and wd_nic.is_connected() then
                    _bp.act_nic = wd_nic

                    _bp.smem.q.mq_render.push_command(MQ__RENDER_CMD.CLOSE_MAIN_UI)
                    comms.switch_nic(_bp.act_nic)
                    log.info("BKPLN: 已将通信切换到有线调制解调器")
                else
                    -- close out main UI
                    _bp.smem.q.mq_render.push_command(MQ__RENDER_CMD.CLOSE_MAIN_UI)
                    comms.close()

                    -- alert user to status
                    log_sys("等待通信调制解调器重新连接...")
                end
            elseif wl_nic and wl_nic.is_connected() then
                -- wired active disconnected, wireless available
                _bp.act_nic = wl_nic

                _bp.smem.q.mq_render.push_command(MQ__RENDER_CMD.CLOSE_MAIN_UI)
                comms.switch_nic(_bp.act_nic)
                log.info("BKPLN: 已将通信切换到无线调制解调器")
            else
                -- wired active disconnected, wireless unavailable
                _bp.smem.q.mq_render.push_command(MQ__RENDER_CMD.CLOSE_MAIN_UI)
                comms.close()
            end
        elseif wd_nic and wd_nic.is_modem(device) then
            -- wired, but not active
            log_sys("备用有线调制解调器已断开")
            log.info("BKPLN: 备用有线调制解调器已断开")
        elseif wl_nic and wl_nic.is_modem(device) then
            -- wireless, but not active
            log_sys("备用无线调制解调器已断开")
            log.info("BKPLN: 备用无线调制解调器已断开")
        else
            log_sys("未分配的调制解调器已断开")
            log.warning("BKPLN: 未分配的调制解调器已断开")
        end
    elseif type == "monitor" then
        ---@cast device Monitor

        local is_used = false

        log.info("BKPLN: DISPLAY LINK_DOWN " .. iface)

        if _bp.displays.main == device then
            is_used = true

            log.info("BKPLN: main display disconnected")
            ioctl.fp_monitor_state("main", 1)
        elseif _bp.displays.flow == device then
            is_used = true

            log.info("BKPLN: flow display disconnected")
            ioctl.fp_monitor_state("flow", 1)
        else
            for idx, monitor in pairs(_bp.displays.unit_displays) do
                if monitor == device then
                    is_used = true

                    log.info("BKPLN: unit " .. idx .. " display disconnected")
                    ioctl.fp_monitor_state(idx, 1)
                    break
                end
            end
        end

        -- notify renderer if it was using it
        if is_used then
            log_sys("丢失了一台已配置的监视器")
            _bp.smem.q.mq_render.push_data(MQ__RENDER_DATA.MON_DISCONNECT, iface)
        else
            log_sys("丢失了一台未使用的监视器")
        end
    elseif type == "speaker" then
        ---@cast device Speaker

        log.info("BKPLN: SPEAKER LINK_DOWN " .. iface)

        log_sys("报警扬声器已断开")

        ioctl.fp_has_speaker(false)
    end
end


return backplane
