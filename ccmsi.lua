--[[
CC-MEK-SCADA Installer Utility

Copyright (c) 2023 - 2026 Mikayla Fischler

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]--

local ccs = require("cc.strings")

local CCMSI_VERSION = "2.3"

local IS_PKT = pocket ~= nil -- luacheck: ignore pocket

local INSTALL_DIR = "/.install-cache"
-- download sources: primary is direct raw.githubusercontent.com (always
-- fresh), fallback is gh-proxy accelerated (may serve stale CDN cache)
local DEPLOY_DIR = "https://raw.githubusercontent.com/Ccat-Q/cc-mek-scada/"
local PROXY_DIR = "https://gh-proxy.org/https://raw.githubusercontent.com/Ccat-Q/cc-mek-scada/"

local OPTS = { ... }

local mode, app, target, build_url, manifest_url

local out_w, out_h = term.getSize()

local function tsc(c) term.setTextColor(c) end
local function tbc(c) term.setBackgroundColor(c) end

local function red() tsc(colors.red) end
local function orange() tsc(colors.orange) end
local function yellow() tsc(colors.yellow) end
local function green() tsc(colors.green) end
local function cyan() tsc(colors.cyan) end
local function blue() tsc(colors.blue) end
local function purple() tsc(colors.purple) end
local function white() tsc(colors.white) end
local function lgray() tsc(colors.lightGray) end

local function pln(msg) print(tostring(msg)) end

-- stripped down & modified copy of log.dmesg
local function print(msg)
	msg = tostring(msg)

	local cur_x, cur_y = term.getCursorPos()

	if cur_x == out_w then
		-- jump to next line
		cur_x = 1
		if cur_y == out_h then
			term.scroll(1)
			term.setCursorPos(1, cur_y)
		else
			term.setCursorPos(1, cur_y + 1)
		end
	end

	local lines, remaining, s_start, s_end, ln = {}, true, 1, out_w + 1 - cur_x, 1
	while remaining do
		local line = string.sub(msg, s_start, s_end)

		if line == "" then
			remaining = false
		else
			lines[ln] = line
			s_start = s_end + 1
			s_end = s_end + out_w
			ln = ln + 1
		end
	end

	for i = 1, #lines do
		cur_x, cur_y = term.getCursorPos()
		if i > 1 and cur_x > 1 then
			if cur_y == out_h then
				term.scroll(1)
				term.setCursorPos(1, cur_y)
			else term.setCursorPos(1, cur_y + 1) end
		end
		term.write(lines[i])
	end
end

-- reset cursor to before a print of s occurred
local function print_reset(s)
	local _, y = term.getCursorPos()
	for i = 1, #ccs.wrap(s, out_w) do
		term.setCursorPos(1, y - i);term.clearLine()
	end
end

-- show progress and percentage at the bottom of the screen
local function show_progress(p)
	local _, y = term.getCursorPos()
	term.setCursorPos(1, out_h)

	print(string.format("%3.0f%% ", p*100))
	local pb = math.floor(p*(out_w-6))

	tbc(colors.lightBlue);tsc(colors.black)
	print(string.rep("\x80", pb))
	tbc(colors.black)

	term.setCursorPos(1, y);lgray()
end

-- get command line option in list
local function get_opt(opt, options)
	for _, v in pairs(options) do if opt == v then return v end end
	return nil
end

-- wait for any key press
local function any_key() os.pullEvent("key_up") end

-- ask the user yes or no
local function ask_y_n(question, default)
	print(question)
	if default == true then print(" (Y/n)? ") else print(" (y/N)? ") end
	white()
	local r = read();any_key()
	if r == "" then return default
	elseif r == "Y" or r == "y" then return true
	elseif r == "N" or r == "n" then return false
	else return nil end
end

-- get major, minor, patch version numbers
local function v_nums(v)
	local a, b, c = v:match("^[vV]?(%d+)%.(%d+)%.?(%d*)$")
	return tonumber(a), tonumber(b), tonumber(c) or 0
end

-- 1 = update, 0 = same, -1 = downgrade
local function is_update(v)
	local l1, l2, l3 = v_nums(v.v_local)
	local r1, r2, r3 = v_nums(v.v_remote)

	if r1 ~= l1 then return (r1 > l1 and 1) or -1 end
	if r2 ~= l2 then return (r2 > l2 and 1) or -1 end
	if r3 ~= l3 then return (r3 > l3 and 1) or -1 end
	return 0
end

-- package version message
local function pkg_v_msg(n, m, va, vb)
	purple();print("["..n.."] ");white();print(m.." ");blue()
	if vb then print(va);white();print(" \x1a ");blue();pln(vb) else pln(va) end
	white()
end

-- package info/warn message
local function pkg_msg(n, m, w)
	purple();print("["..n.."] ")
	if w then yellow() else white() end
	pln(m.." ")
end

-- indicate actions to be taken based on package differences for installs/updates
local function show_pkg_change(name, v)
	if v.v_local then
		local is_up = is_update(v)
		if is_up ~= 0 then
			local updn = (is_up > 0) and "正在更新" or "正在降级"
			pkg_v_msg(name, updn, v.v_local, v.v_remote)
		elseif mode == "install" then
			pkg_v_msg(name, "重新安装", v.v_local)
		end
	else pkg_v_msg(name, "全新安装", v.v_remote) end

	return v.v_local ~= v.v_remote
end

-- read the local manifest file
local function read_local_manifest()
	local ok, manifest, f = false, {}, fs.open("install_manifest.json", "r")
	if f ~= nil then
		ok, manifest = pcall(function () return textutils.unserializeJSON(f.readAll()) end)
		f.close()
	end
	return ok, manifest
end

-- read the manifest from GitHub (direct first, then gh-proxy fallback)
local function read_remote_manifest()
	local resp = http.get(manifest_url)

	-- gh-proxy may serve a stale cached manifest; fall back to direct if the proxy returned it
	if resp ~= nil then
		local ok, manifest = pcall(function () return textutils.unserializeJSON(resp.readAll()) end)
		if ok then return true, manifest end
	end

	-- fallback: try the alternate source (swap proxy <-> direct prefix)
	local alt_url = string.gsub(manifest_url, PROXY_DIR, DEPLOY_DIR, 1)
	if alt_url == manifest_url then
		-- wrap gsub in parens so only the string (not the replacement count) is passed to http.get
		resp = http.get((string.gsub(manifest_url, DEPLOY_DIR, PROXY_DIR, 1)))
	else
		resp = http.get(alt_url)
	end
	if resp == nil then
		orange();pln("无法从 GitHub 读取安装清单，无法更新或安装。")
		red();pln("HTTP 错误，请查看控制台输出");white()
		return false, {}
	end

	local ok, manifest = pcall(function () return textutils.unserializeJSON(resp.readAll()) end)
	if not ok then red();pln("解析远程安装清单时出错");white() end

	return ok, manifest
end

-- record the local installation manifest
local function write_install_manifest(manifest, deps)
	local versions = {}
	for k, v in pairs(manifest.versions) do
		local is_dep = false
		for _, dep in pairs(deps) do
			if (k == "bootloader" and dep == "system") or k == dep then
				is_dep = true;break
			end
		end
		if k == app or k == "comms" or is_dep then versions[k] = v end
	end

	manifest.versions = versions

	local f = fs.open("install_manifest.json", "w")
	f.write(textutils.serializeJSON(manifest));f.close()
end

-- try at most 3 times to download a file from the repository and write into w_path base directory
---@return 0|1|2|3 success 0: ok, 1: download fail, 2: file open fail, 3: out of space
local function http_get_file(file, w_path)
	for i = 1, 3 do
		local dl, err = http.get(build_url..file)

		-- if the proxy served a stale file, retry from the direct source
		if dl == nil then
			if string.find(build_url, PROXY_DIR, 1, true) ~= nil then
				dl, err = http.get(string.gsub(build_url, PROXY_DIR, DEPLOY_DIR, 1)..file)
			else
				dl, err = http.get(string.gsub(build_url, DEPLOY_DIR, PROXY_DIR, 1)..file)
			end
		end

		if dl then
			if i > 1 then green();pln("成功！");lgray() end

			local f = fs.open(w_path..file, "w")
			if not f then return 2 end

			local ok, msg = pcall(function() f.write(dl.readAll()) end)
			f.close()
			if not ok then
				if string.find(msg or "", "Out of space") ~= nil then
					red();pln("[空间不足]");lgray()
					return 3
				else return 2 end
			end
			break
		else
			red();pln("HTTP 错误："..err)
			if i < 3 then
				lgray();print("> 正在重试...")
				os.sleep(i/3)
			else return 1 end
		end
	end
	return 0
end

-- recursively build a tree out of the file manifest
local function gen_tree(manifest, log)
	local function _tree_add(tree, split)
		if #split > 1 then
			local name = table.remove(split, 1)
			if tree[name] == nil then tree[name] = {} end
			table.insert(tree[name], _tree_add(tree[name], split))
		else return split[1] end
		return nil
	end

	local list, tree = { log }, {}

	for _, files in pairs(manifest.files) do for i = 1, #files do table.insert(list, files[i]) end end

	for i = 1, #list do
		local split = {}
		string.gsub(list[i], "([^/]+)", function(c) split[#split + 1] = c end)
		if #split == 1 then table.insert(tree, list[i])
		else table.insert(tree, _tree_add(tree, split)) end
	end

	return tree
end

local function _in_array(val, array)
	for _, v in pairs(array) do if v == val then return true end end
	return false
end

local function _clean_dir(dir, tree)
	if tree == nil then tree = {} end
	local ls = fs.list(dir)
	for _, l in pairs(ls) do
		local path = dir.."/"..l
		if fs.isDir(path) then
			_clean_dir(path, tree[l])
			if #fs.list(path) == 0 then fs.delete(path);pln("已删除 "..path) end
		elseif (not _in_array(l, tree)) and l ~= "config.lua" then
			fs.delete(path);pln("已删除 "..path)
		end
	end
end

-- go through app/common directories to delete unused files
local function clean(manifest)
	local log, cfg = nil, app..".settings"
	if fs.exists(cfg) and settings.load(cfg) then
		log = settings.get("LogPath")
		if type(log) == "string" and log:sub(1, 1) == "/" then log = log:sub(2) end
	end

	local tree = gen_tree(manifest, log or "")

	table.insert(tree, "install_manifest.json")
	table.insert(tree, "ccmsi.lua")

	local ls = fs.list("/")
	for _, val in pairs(ls) do
		if fs.isDriveRoot(val) then
			yellow();pln("已跳过挂载点 '"..val.."'")
		elseif fs.isDir(val) then
			if tree[val] ~= nil then lgray();_clean_dir("/"..val, tree[val])
			else white(); if ask_y_n("删除未使用的目录 '"..val.."'") then lgray();_clean_dir("/"..val) end end
			if #fs.list(val) == 0 then fs.delete(val);lgray();pln("已删除空目录 '"..val.."'") end
		elseif not _in_array(val, tree) and (string.find(val, ".settings") == nil) then
			white();if ask_y_n("删除未使用的文件 '"..val.."'") then fs.delete(val);lgray();pln("已删除 "..val) end
		end
	end

	white()
end

-- startup header

tsc(colors.magenta)
if IS_PKT then pln("- SCADA 安装器 v"..CCMSI_VERSION.." -")
else pln("-- ComputerCraft Mekanism SCADA 安装器 v"..CCMSI_VERSION.." --") end
white()

-- handle command line options

if #OPTS == 0 or OPTS[1] == "help" then
	pln("用法：ccmsi <mode> <app> <branch>")

	blue();pln("<mode>")
	if IS_PKT then
		lgray();pln(" check - 检查最新\n install - 全新安装\n update - 更新应用\n uninstall - 卸载应用")
		blue();pln("<app>")
		lgray();pln(" pocket\n installer（仅更新）")
		blue();pln("<branch>")
	else
		lgray();pln(" check       - 检查可用的最新版本")
		yellow();pln("               ccmsi check <branch> (skip <app>)")
		lgray();pln(" install     - 全新安装\n update      - 更新文件\n uninstall   - 删除文件，包括配置/日志")
		blue();print("<app>");cyan();pln(" 省略时自动检测已安装的应用")
		lgray();pln(" reactor-plc - 裂变反应堆 PLC 固件\n rtu         - RTU 网关固件\n supervisor  - 监控端服务器应用\n coordinator - 协调器应用\n pocket      - 口袋电脑应用\n sim         - PLC/RTU 模拟器应用\n installer   - CCMSI 安装器（仅更新）")
		blue();print("<branch>");cyan();pln(" 省略时默认为 'main'")
	end
	lgray();pln(" main（默认） | devel");white()

	return
else
	mode = get_opt(OPTS[1], { "check", "install", "update", "uninstall" })
	if mode == nil then
		red();pln("无效的模式。");white()
		return
	end

	local next_opt = 3
	local apps = { "reactor-plc", "rtu", "supervisor", "coordinator", "pocket", "sim", "installer" }
	app = get_opt(OPTS[2], apps)
	if app == nil then
		for _, a in pairs(apps) do
			if fs.isDir(a) then app, next_opt = a, 2 end
		end
	end

	if app == nil and mode ~= "check" then
		red();pln("无效的应用。");white()
		return
	elseif mode == "check" then
		next_opt = 2
	elseif app == "installer" and mode ~= "update" then
		red();pln("安装器仅支持 'update'。");white()
		return
	end

	target = OPTS[next_opt] or "main"
	if target ~= "main" and target ~= "devel" then
		red();pln("无效的分支目标。");white()
		return
	end

	-- raw.githubusercontent.com URLs include the branch name, so prepend it
	manifest_url = DEPLOY_DIR..target.."/manifests/"..target.."/install_manifest.json"
	build_url = DEPLOY_DIR..target.."/builds/"..target.."/"
end

-- main operation

local ok, r_manifest, l_manifest

if mode == "check" then
	ok, r_manifest = read_remote_manifest()
	if not ok then return end

	ok, l_manifest = read_local_manifest()
	if not ok then
		yellow();pln("无法加载本地安装信息");white()
		l_manifest = { versions = { installer = CCMSI_VERSION } }
	else
		l_manifest.versions.installer = CCMSI_VERSION
	end

	if not IS_PKT then pln("") end

	-- list all versions
	for k, v in pairs(r_manifest.versions) do
		purple()
		local tag = string.format("%-14s", "["..k.."]")
		if not IS_PKT then print(tag) end
		if k == "installer" or (ok and (l_manifest.versions[k] ~= nil)) then
			if IS_PKT then pln(tag) end
			blue();print(l_manifest.versions[k])
			if v ~= l_manifest.versions[k] then
				white();print(" (");cyan();print(v);white();pln(" 可用)")
			else green();pln("（已是最新）") end
		elseif not IS_PKT then
			lgray();print("未安装");white();print("（最新 ");cyan();print(v);white();pln("）")
		end
	end

	if r_manifest.versions.installer ~= l_manifest.versions.installer and not IS_PKT then
		yellow();pln("\n安装器有新版本可用，强烈建议更新（使用 'ccmsi update installer'）。");white()
	end
elseif mode == "install" or mode == "update" then
	local update_installer = app == "installer"

	ok, r_manifest = read_remote_manifest()
	if not ok then return end

	local ver = {
		app = { v_local = nil, v_remote = nil, changed = false },
		boot = { v_local = nil, v_remote = nil, changed = false },
		comms = { v_local = nil, v_remote = nil, changed = false },
		common = { v_local = nil, v_remote = nil, changed = false },
		graphics = { v_local = nil, v_remote = nil, changed = false },
		lockbox = { v_local = nil, v_remote = nil, changed = false }
	}

	-- try to load local versions
	ok, l_manifest = read_local_manifest()
	if ok then
		ver.boot.v_local = l_manifest.versions.bootloader
		ver.app.v_local = l_manifest.versions[app]
		ver.comms.v_local = l_manifest.versions.comms
		ver.common.v_local = l_manifest.versions.common
		ver.graphics.v_local = l_manifest.versions.graphics
		ver.lockbox.v_local = l_manifest.versions.lockbox

		if l_manifest.versions[app] == nil then
			red();pln("已安装其他应用，请先卸载它再安装新应用。");white()
			return
		end
	elseif mode == "update" and not update_installer then
		red();pln("无法加载本地安装信息，无法更新。");white()
		return
	end

	-- installer update handling
	if r_manifest.versions.installer ~= CCMSI_VERSION then
		if not update_installer then yellow();pln("安装器有新版本可用，强烈建议更新到该版本。");white() end
		if update_installer or ask_y_n("是否现在更新它", true) then
			lgray();pln("GET ccmsi.lua")
			local dl, err = http.get(build_url.."ccmsi.lua")

			if dl == nil then
				red();pln("HTTP 错误："..err)
				pln("安装器下载失败。")
			else
				local f = fs.open(debug.getinfo(1, "S").source:sub(2), "w") -- this file
				f.write(dl.readAll());f.close()
				green();pln("安装器更新成功。")
			end

			white()
			return
		end
	elseif update_installer then
		green();pln("安装器已是最新版本。");white()
		return
	end

	ver.boot.v_remote = r_manifest.versions.bootloader
	ver.app.v_remote = r_manifest.versions[app]
	ver.comms.v_remote = r_manifest.versions.comms
	ver.common.v_remote = r_manifest.versions.common
	ver.graphics.v_remote = r_manifest.versions.graphics
	ver.lockbox.v_remote = r_manifest.versions.lockbox

	green()
	if mode == "install" then print("正在安装 ") else print("正在更新 ") end
	pln(app.." 文件...");white()

	ver.boot.changed = show_pkg_change("bootldr", ver.boot)
	ver.common.changed = show_pkg_change("common", ver.common)
	ver.comms.changed = show_pkg_change("comms", ver.comms)
	if ver.comms.changed and ver.comms.v_local ~= nil then
		pkg_msg("comms", "所有联网设备必须同步更新", true)
	end
	ver.app.changed = show_pkg_change(app, ver.app)
	ver.graphics.changed = show_pkg_change("graphics", ver.graphics)
	ver.lockbox.changed = show_pkg_change("lockbox", ver.lockbox)

	-- start install/update

	local space_req = r_manifest.sizes.manifest
	local space_avail = fs.getFreeSpace("/")

	local file_list, size_list = r_manifest.files, r_manifest.sizes
	local deps, sf_deps = r_manifest.depends[app], {}

	table.insert(deps, app)

	-- helper function to check if a dependency is unchanged
	local function unchanged(dep)
		if dep == "system" then return not ver.boot.changed
		elseif dep == "graphics" then return not ver.graphics.changed
		elseif dep == "lockbox" then return not ver.lockbox.changed
		elseif dep == "common" then return not (ver.common.changed or ver.comms.changed)
		elseif dep == app then return not ver.app.changed
		else return true end
	end

	local any_change = false

	for _, dep in pairs(deps) do
		table.insert(sf_deps, dep)
		local size = size_list[dep]
		space_req = space_req + size
		any_change = any_change or not unchanged(dep)
	end

	if mode == "update" and not any_change then
		yellow();pln("无需操作，所有内容都已是最新！");white()
		return
	end

	-- ask for confirmation
	if not ask_y_n("继续", false) then return end

	local single_file_mode = space_avail < space_req

	local success = true

	-- delete a file if the capitalization changes so that things work on Windows
	---@param path string
	local function mitigate_case(path)
		local dir, file = fs.getDir(path), fs.getName(path)
		if not fs.isDir(dir) then return end
		for _, p in ipairs(fs.list(dir)) do
			if string.lower(p) == string.lower(file) then
				if p ~= file then fs.delete(path) end
				return
			end
		end
	end

	---@param dl_stat 1|2|3 download status
	---@param file string file name
	---@param attempt integer recursive attempt #
	---@param sf_install function installer function for recursion
	local function handle_dl_fail(dl_stat, file, attempt, sf_install)
		red()
		if dl_stat == 1 then
			pln("下载失败 "..file)
		elseif dl_stat > 1 then
			if dl_stat == 2 then pln("文件系统错误："..file) else pln("空间不足，无法下载 "..file) end
			if attempt == 1 then
				orange();pln("正在重新尝试操作...");white()
				sf_install(2)
			elseif attempt == 2 then
				yellow()
				if dl_stat == 2 then pln("写入文件时出错。") else pln("可用空间不足。") end
				lgray()
				if dl_stat == 2 then
					pln("这可能是由于可用空间不足或文件权限问题。安装器现在可以尝试删除 SCADA 系统未使用的文件。")
				else pln("安装器现在可以尝试删除 SCADA 系统未使用的文件。") end
				white()
				if not ask_y_n("继续", false) then
					success = false
					return
				end
				clean(r_manifest)
				sf_install(3)
			elseif attempt == 3 then
				yellow()
				if dl_stat == 2 then pln("写入文件时再次出错。") else pln("可用空间不足。") end
				lgray()
				if dl_stat == 2 then
					pln("这可能是由于可用空间不足或文件权限问题。请删除此电脑上未使用的文件后重试。除非您想重新配置，否则不要删除 "..app..".settings 文件。")
				else pln("请删除此电脑上未使用的文件后重试。除非您想重新配置，否则不要删除 "..app..".settings 文件。") end
				white()
				success = false
			end
		end
	end

	-- single file update routine: go through all files and replace one by one
	---@param attempt integer recursive attempt #
	local function sf_install(attempt)
		if attempt > 1 then os.sleep(2.0) end

		local abort_attempt = false
		success = true

		for k, dep in pairs(sf_deps) do
			if mode == "update" and unchanged(dep) then
				pkg_msg(dep, "跳过未变更包的安装", true)
				sf_deps[k] = nil
			else
				pkg_msg(dep, "正在安装包...")
				lgray()

				-- beginning on the second try, delete the directory before starting
				if attempt >= 2 then
					if dep == "common" then
						if fs.exists("/scada-common") then
							fs.delete("/scada-common");pln("已删除 /scada-common")
						end
					elseif dep ~= "system" then
						if fs.exists("/"..dep) then
							fs.delete("/"..dep);pln("已删除 /"..dep)
						end
					end
				end

				local files, n = file_list[dep], 1
				for _, file in pairs(files) do
					local s = "GET "..file
					pln(s)
					mitigate_case(file)
					local dl_stat = http_get_file(file, "/")
					if dl_stat ~= 0 then
						abort_attempt = true
---@diagnostic disable-next-line: param-type-mismatch
						handle_dl_fail(dl_stat, file, attempt, sf_install)
						break
					end
					show_progress(n/#files)
					n = n + 1
					print_reset(s)
				end

				if not abort_attempt then pkg_msg(dep, "安装完成！");sf_deps[k] = nil end
				term.clearLine()
			end
			if abort_attempt or not success then break end
		end
	end

	-- handle update/install
	if single_file_mode then sf_install(1)
	else
		if fs.exists(INSTALL_DIR) then fs.delete(INSTALL_DIR);fs.makeDir(INSTALL_DIR) end

		-- download all dependencies
		for _, dep in pairs(deps) do
			if mode == "update" and unchanged(dep) then
				pkg_msg(dep, "跳过未变更包的下载", true)
			else
				pkg_msg(dep, "正在下载包...")
				lgray()

				local files, n = file_list[dep], 1
				for _, file in pairs(files) do
					local s = "GET "..file
					pln(s)
					local dl_stat = http_get_file(file, INSTALL_DIR.."/")
					success = dl_stat == 0
					if dl_stat == 1 then
						red();pln("下载失败 "..file)
						break
					elseif dl_stat == 2 then
						red();pln("文件系统错误："..file)
						break
					elseif dl_stat == 3 then
						-- this shouldn't occur in this mode
						red();pln("空间不足，无法下载 "..file)
						break
					end
					show_progress(n/#files)
					n = n + 1
					print_reset(s)
				end

				if success then pkg_msg(dep, "下载完成！") end
				term.clearLine()
			end
			if not success then break end
		end

		-- copy in downloaded files (installation)
		if success then
			for _, dep in pairs(deps) do
				if mode == "update" and unchanged(dep) then
					pkg_msg(dep, "跳过未变更包的安装", true)
				else
					pkg_msg(dep, "正在安装包...")
					lgray()

					local files = file_list[dep]
					for _, file in pairs(files) do
						local temp_file = INSTALL_DIR.."/"..file
						mitigate_case(file)
						if fs.exists(file) then fs.delete(file) end
						fs.move(temp_file, file)
					end

					pkg_msg(dep, "安装完成！")
				end
			end
		end

		fs.delete(INSTALL_DIR)
	end

	if success then
		write_install_manifest(r_manifest, deps)
		green()
		if mode == "install" then print("安装") else print("更新") end
		pln(" 已成功完成。")
		white();pln("准备清理未使用的文件，按任意键继续...")
		any_key();clean(r_manifest)
		white();pln("完成。")
	else
		red()
		if single_file_mode then
			if mode == "install" then print("安装") else print("更新") end
			pln(" 失败，可能有文件被跳过。")
		else
			if mode == "install" then pln("安装失败。")
			else orange();pln("更新失败，现有文件未改动。") end
		end
	end
elseif mode == "uninstall" then
	ok, l_manifest = read_local_manifest()
	if not ok then
		red();pln("解析本地安装清单时出错。");white()
		return
	end

	if l_manifest.versions[app] == nil then
		red();pln("错误：'"..app.."' 未安装。")
		return
	end

	orange();pln("正在卸载 "..app.." 的所有文件...");white()

	-- ask for confirmation
	if not ask_y_n("继续", false) then return end

	-- delete unused files first
	clean(l_manifest)

	local file_list = l_manifest.files
	local deps = l_manifest.depends[app]

	table.insert(deps, app)

	-- delete all installed files
	lgray()
	for _, dep in pairs(deps) do
		local files = file_list[dep]
		for _, file in pairs(files) do
			if fs.exists(file) then fs.delete(file);pln("已删除 "..file) end
		end

		local folder = files[1]
		while true do
			local dir = fs.getDir(folder)
			if dir == "" or dir == ".." then break else folder = dir end
		end

		if fs.isDir(folder) then
			fs.delete(folder);pln("已删除目录 "..folder)
		end
	end

	-- delete log file
	local log_deleted, cfg = false, app..".settings"
	if fs.exists(cfg) and settings.load(cfg) then
		local log = settings.get("LogPath")
		if log ~= nil then
			log_deleted = true
			if fs.exists(log) then
				fs.delete(log);pln("已删除日志文件 "..log)
			end
		end
	end

	if not log_deleted then
		red();pln("无法删除日志文件（它可能不存在）。");lgray()
	end

	if fs.exists(cfg) then
		fs.delete(cfg);pln("已删除 "..cfg)
	end

	fs.delete("install_manifest.json")
	pln("已删除 install_manifest.json")

	green();pln("完成！")
end

white()
