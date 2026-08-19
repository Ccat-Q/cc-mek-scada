--
-- Alarm Sounder
--

local audio = require("scada-common.audio")
local log   = require("scada-common.log")
local util  = require("scada-common.util")

---@class sounder
local sounder = {}

local alarm_ctl = {
    speaker = nil,       ---@type Speaker|nil
    speaker_iface = nil, ---@type string|nil
    volume = 0.5,
    stream = audio.new_stream(),
    err_log_at = 0       ---@type number 下一次记录失败日志的时间（毫秒时间戳）
}

-- 限频记录失败日志，避免刷爆日志文件（CC 电脑磁盘只有 1MB）
---@param msg string 要记录的消息
local function log_failure(msg)
    if util.time() >= alarm_ctl.err_log_at then
        log.warning(msg)
        alarm_ctl.err_log_at = util.time() + 30000
    end
end

-- start audio or continue audio on buffer empty
---@return boolean success successfully added buffer to audio output
local function play()
    if not alarm_ctl.playing then
        alarm_ctl.playing = true
        return sounder.continue()
    else return true end
end

-- initialize the annunciator alarm system
---@param speaker Speaker speaker peripheral
---@param iface string speaker peripheral interface
---@param volume number speaker volume
function sounder.init(speaker, iface, volume)
    alarm_ctl.speaker = speaker
    alarm_ctl.speaker_iface = iface
    alarm_ctl.volume = volume
    alarm_ctl.err_log_at = 0

    if speaker ~= nil then speaker.stop() end
    alarm_ctl.stream.stop()

    audio.generate_tones()
end

-- reconnect the speaker peripheral
---@param speaker Speaker speaker peripheral
---@param iface string speaker peripheral interface
function sounder.reconnect(speaker, iface)
    alarm_ctl.speaker = speaker
    alarm_ctl.speaker_iface = iface
    alarm_ctl.playing = false
    alarm_ctl.stream.stop()
end

-- handle the speaker being disconnected
function sounder.detach()
    alarm_ctl.speaker = nil
    alarm_ctl.speaker_iface = nil
    alarm_ctl.playing = false
    alarm_ctl.stream.stop()
end

-- set alarm tones
---@param states { [TONE]: boolean } alarm tone commands from supervisor
function sounder.set(states)
    -- set tone states
    for id = 1, #states do alarm_ctl.stream.set_active(id, states[id]) end

    -- re-compute output if needed, then play audio if available
    if alarm_ctl.stream.is_recompute_needed() then alarm_ctl.stream.compute_buffer() end
    if alarm_ctl.stream.any_active() then play() else sounder.stop() end
end

-- stop all audio and clear output buffer
function sounder.stop()
    alarm_ctl.playing = false
    if alarm_ctl.speaker ~= nil then alarm_ctl.speaker.stop() end
    alarm_ctl.stream.stop()
end

-- continue audio on buffer empty
---@param event_iface? string 触发事件的扬声器接口名
---@return boolean success successfully added buffer to audio output
function sounder.continue(event_iface)
    local success = false

    -- 仅当事件来自本机报警扬声器时才继续供音；
    -- 事件来源未知或本机扬声器接口未知时放行，避免因命名差异导致报警音停摆
    if alarm_ctl.playing and
       (event_iface == nil or alarm_ctl.speaker_iface == nil or event_iface == alarm_ctl.speaker_iface) then
        local speaker = alarm_ctl.speaker

        if speaker ~= nil and alarm_ctl.stream.has_next_block() then
            local block = alarm_ctl.stream.peek_next_block()

            success = speaker.playAudio(block, alarm_ctl.volume)

            if success then
                alarm_ctl.stream.advance_next_block()
            else
                -- 播放失败：上一个音频块可能仍在排队（CC:Tweaked 的扬声器同一时间只缓冲一个块），
                -- 或扬声器已断开。不要推进音频块指针，等待下一次 speaker_audio_empty 事件重试。
                log_failure("SOUNDER: 音频播放失败，等待下一次播放事件重试")

                -- 若扬声器已不存在，停止播放直到其重新连接
                if alarm_ctl.speaker_iface ~= nil and not peripheral.isPresent(alarm_ctl.speaker_iface) then
                    sounder.detach()
                end
            end
        end
    end

    return success
end

return sounder
