
local audio = require("scada-common.audio")
local log   = require("scada-common.log")
local util  = require("scada-common.util")
local sounder = {}
local alarm_ctl = {
speaker = nil,
speaker_iface = nil,
volume = 0.5,
stream = audio.new_stream(),
err_log_at = 0
}
local function log_failure(msg)
if util.time() >= alarm_ctl.err_log_at then
log.warning(msg)
alarm_ctl.err_log_at = util.time() + 30000
end
end
local function play()
if not alarm_ctl.playing then
alarm_ctl.playing = true
return sounder.continue()
else return true end
end
function sounder.init(speaker, iface, volume)
alarm_ctl.speaker = speaker
alarm_ctl.speaker_iface = iface
alarm_ctl.volume = volume
alarm_ctl.err_log_at = 0
if speaker ~= nil then speaker.stop() end
alarm_ctl.stream.stop()
audio.generate_tones()
end
function sounder.reconnect(speaker, iface)
alarm_ctl.speaker = speaker
alarm_ctl.speaker_iface = iface
alarm_ctl.playing = false
alarm_ctl.stream.stop()
end
function sounder.detach()
alarm_ctl.speaker = nil
alarm_ctl.speaker_iface = nil
alarm_ctl.playing = false
alarm_ctl.stream.stop()
end
function sounder.set(states)
for id = 1, #states do alarm_ctl.stream.set_active(id, states[id]) end
if alarm_ctl.stream.is_recompute_needed() then alarm_ctl.stream.compute_buffer() end
if alarm_ctl.stream.any_active() then play() else sounder.stop() end
end
function sounder.stop()
alarm_ctl.playing = false
if alarm_ctl.speaker ~= nil then alarm_ctl.speaker.stop() end
alarm_ctl.stream.stop()
end
function sounder.continue(event_iface)
local success = false
if alarm_ctl.playing and
(event_iface == nil or alarm_ctl.speaker_iface == nil or event_iface == alarm_ctl.speaker_iface) then
local speaker = alarm_ctl.speaker
if speaker ~= nil and alarm_ctl.stream.has_next_block() then
local block = alarm_ctl.stream.peek_next_block()
success = speaker.playAudio(block, alarm_ctl.volume)
if success then
alarm_ctl.stream.advance_next_block()
else
log_failure("SOUNDER: 音频播放失败，等待下一次播放事件重试")
if alarm_ctl.speaker_iface ~= nil and not peripheral.isPresent(alarm_ctl.speaker_iface) then
sounder.detach()
end
end
end
end
return success
end
return sounder
