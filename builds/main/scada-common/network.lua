
local comms  = require("scada-common.comms")
local log    = require("scada-common.log")
local ppm    = require("scada-common.ppm")
local util   = require("scada-common.util")
local md5    = require("lockbox.digest.md5")
local sha1   = require("lockbox.digest.sha1")
local pbkdf2 = require("lockbox.kdf.pbkdf2")
local hmac   = require("lockbox.mac.hmac")
local stream = require("lockbox.util.stream")
local array  = require("lockbox.util.array")
local LINK_TIMEOUT_MS          = 5000
local DISCOVERY_PERIOD_UP_MS   = 3000
local DISCOVERY_PERIOD_DOWN_MS = 500
local network = {}
local _crypt = {
key = nil,
hmac = nil
}
function network.init_mac(passkey)
local start = util.time_ms()
local key_deriv = pbkdf2()
key_deriv.setPRF(hmac().setBlockSize(64).setDigest(sha1))
key_deriv.setBlockLen(20)
key_deriv.setDKeyLen(20)
key_deriv.setIterations(256)
key_deriv.setSalt("pepper")
key_deriv.setPassword(passkey)
key_deriv.finish()
_crypt.key = array.fromHex(key_deriv.asHex())
_crypt.hmac = hmac()
_crypt.hmac.setBlockSize(64)
_crypt.hmac.setDigest(md5)
_crypt.hmac.setKey(_crypt.key)
local init_time = util.time_ms() - start
log.info("NET: network.init_mac() 用时 " .. init_time .. "ms 完成")
return init_time
end
function network.deinit_mac()
_crypt.key, _crypt.hmac = nil, nil
end
local function compute_hmac(message)
_crypt.hmac.init()
_crypt.hmac.update(stream.fromString(message))
_crypt.hmac.finish()
local hash = _crypt.hmac.asHex()
return hash
end
function network.nic(modem, lld_tx_chan)
local self = {
iface = "?",
name = "?",
use_hash = false,
phy_up = false,
link_up = false,
last_lld_rx = 0,
last_lld_tx = 0,
channels = {}
}
local function _send_ll_discovery_frame(dest_addr, r_chan, l_chan, ack)
if not self.phy_up then return end
local reply = comms.lld_frame()
reply.make(dest_addr, ack)
modem.transmit(r_chan, l_chan, reply.raw_frame())
end
local public = {}
function public.phy_name() return self.name end
function public.is_connected() return self.phy_up end
function public.is_network_up() return self.link_up end
function public.connect(reconnected_modem)
modem = reconnected_modem
self.iface    = ppm.get_iface(modem)
self.name     = util.c(util.trinary(modem.isWireless(), "WLAN_PHY", "ETH_PHY"), "{", self.iface, "}")
self.use_hash = _crypt.hmac and modem.isWireless()
self.phy_up   = true
self.link_up  = false
modem.closeAll()
for _, channel in ipairs(self.channels) do
modem.open(channel)
end
for key, func in pairs(modem) do
if key ~= "transmit" and key ~= "open" and key ~= "close" and key ~= "closeAll" then public[key] = func end
end
end
function public.disconnect()
self.phy_up  = false
self.link_up = false
end
function public.is_modem(device) return device == modem end
if modem then public.connect(modem) end
function public.open(channel)
if modem then modem.open(channel) end
local already_open = false
for i = 1, #self.channels do
if self.channels[i] == channel then
already_open = true
break
end
end
if not already_open then
table.insert(self.channels, channel)
end
end
function public.close(channel)
if modem then modem.close(channel) end
for i = 1, #self.channels do
if self.channels[i] == channel then
table.remove(self.channels, i)
return
end
end
end
function public.closeAll()
if modem then modem.closeAll() end
self.channels = {}
end
function public.transmit(dest_channel, local_channel, frame)
if self.phy_up then
local tx_frame = frame
if self.use_hash then
tx_frame = comms.authd_frame()
tx_frame.make(frame, compute_hmac)
end
modem.transmit(dest_channel, local_channel, tx_frame.raw_frame())
else
log.debug("NET: " .. self.name ..".transmit() 发送被丢弃，物理链路已断开")
end
end
function public.receive(side, sender, reply_to, message, distance)
local frame = nil
if self.phy_up and side == self.iface then
local s_frame = comms.scada_frame()
if self.use_hash then
local a_frame = comms.authd_frame()
if a_frame.receive(side, sender, reply_to, message, distance) then
if s_frame.receive(side, sender, reply_to, a_frame.data(), distance) then
local computed_hmac = compute_hmac(textutils.serialize(s_frame.raw_header(), { allow_repetitions = true, compact = true }))
if a_frame.mac() == computed_hmac then
s_frame.stamp_authenticated()
else
end
end
end
else
s_frame.receive(side, sender, reply_to, message, distance)
end
if s_frame.is_valid() then
self.link_up     = true
self.last_lld_rx = util.time_ms()
frame = s_frame
else
local l_frame = comms.lld_frame()
if l_frame.receive(side, sender, reply_to, message, distance) then
self.link_up     = true
self.last_lld_rx = util.time_ms()
if not l_frame.is_ack() then
_send_ll_discovery_frame(l_frame.src_addr(), l_frame.remote_channel(), l_frame.local_channel(), true)
end
end
end
end
return frame
end
function public.periodic()
local now = util.time_ms()
if now >= (self.last_lld_rx + LINK_TIMEOUT_MS) then
if self.link_up then log.debug("NET: " .. self.name ..".periodic(): 链路超时") end
self.link_up = false
end
if lld_tx_chan and self.phy_up then
if (now - self.last_lld_tx) > util.trinary(self.link_up, DISCOVERY_PERIOD_UP_MS, DISCOVERY_PERIOD_DOWN_MS) then
self.last_lld_tx = now
for _, channel in ipairs(self.channels) do
_send_ll_discovery_frame(comms.BROADCAST, lld_tx_chan, channel, false)
end
end
end
return self.link_up
end
return public
end
return network
