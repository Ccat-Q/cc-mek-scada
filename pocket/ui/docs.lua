--
-- All the text documentation used in the Guide app is defined in this file.
--

local const = require("scada-common.constants")

local docs = {}

---@enum DOC_ITEM_TYPE
local DOC_ITEM_TYPE = {
    SECTION = 1,
    SUBSECTION = 2,
    TEXT = 3,
    NOTE = 4,
    TIP = 5,
    LIST = 6
}

---@enum DOC_LIST_TYPE
local DOC_LIST_TYPE = {
    BULLET = 1,
    NUMBERED = 2,
    INDICATOR = 3,
    LED = 4
}

docs.DOC_ITEM_TYPE = DOC_ITEM_TYPE
docs.DOC_LIST_TYPE = DOC_LIST_TYPE

local target

local function sect(name)
    ---@class pocket_doc_sect
    local item = { type = DOC_ITEM_TYPE.SECTION, name = name }
    table.insert(target, item)
end

---@param key string item identifier for linking
---@param name string item name for display
---@param text_a string text body, or the subtitle/note if text_b is specified
---@param text_b? string text body if subtitle/note was specified
local function doc(key, name, text_a, text_b)
    if text_b == nil then
        text_b = text_a
---@diagnostic disable-next-line: cast-local-type
        text_a = nil
    end

    ---@class pocket_doc_subsect
    local item = { type = DOC_ITEM_TYPE.SUBSECTION, key = key, name = name, subtitle = text_a, body = text_b }
    table.insert(target, item)
end

local function text(body)
    ---@class pocket_doc_text
    local item = { type = DOC_ITEM_TYPE.TEXT, text = body }
    table.insert(target, item)
end

local function note(body)
    ---@class pocket_doc_note
    local item = { type = DOC_ITEM_TYPE.NOTE, text = body }
    table.insert(target, item)
end

local function tip(body)
    ---@class pocket_doc_tip
    local item = { type = DOC_ITEM_TYPE.TIP, text = body }
    table.insert(target, item)
end

---@param type DOC_LIST_TYPE
---@param items string[]
---@param colors color[]|nil colors for indicators or nil for normal lists
local function list(type, items, colors)
    ---@class pocket_doc_list
    local list_def = { type = DOC_ITEM_TYPE.LIST, list_type = type, items = items, colors = colors }
    table.insert(target, list_def)
end

--#region System Usage

docs.usage = {
    conn = {}, config = {}, manual = {}, auto = {}, waste = {}
}

target = docs.usage.conn
sect("概述")
tip("为获得最佳设置体验，请参阅 GitHub 上的 Wiki 或 YouTube 频道！此应用并未包含全部信息。")
text("Mekanism 设备连接到构成 SCADA 控制系统的 ComputerCraft 电脑上。")
sect("Mekanism 连接")
text("多方块结构和单方块设备都通过直接接触电脑或通过有线调制解调器连接到电脑。")
doc("usage_conn_mb", "多方块结构", "对于多方块结构，如果该结构存在逻辑适配器则使用逻辑适配器，否则使用阀门或端口方块。")
text("只有当你右键点击方块并看到红色边框、且在聊天中看到包含外设名称的消息时，有线调制解调器才会连接到该方块。")
tip("不要将系统中所有外设连接到同一条网线上，因为反应堆 PLC 会抓取它找到的第一个反应堆，你可能会意外重复 RTU。")
sect("电脑连接")
tip("使用本系统前熟悉 ComputerCraft 如何管理外设会有所帮助，但并非必需。")
doc("usage_conn_network", "网络", "系统中所有电脑通过有线、无线和/或末影调制解调器相互通信。由于末影调制解调器距离无限，优于无线。")
text("系统使用五个不同的网络频道，每个名称在所有设备上必须具有相同的值。")
text("例如，监管频道 SVR_CHANNEL 必须在系统中所有设备上设置为相同的频道。两个不同名称的频道不应共享相同的值（例如 SVR_CHANNEL 与 CRD_CHANNEL）。")
doc("usage_conn_peri", "外设", "显示器、扬声器等 ComputerCraft 外设需要接触电脑或通过有线调制解调器连接。")

target = docs.usage.config
sect("概述")
tip("为获得最佳设置体验，请参阅 GitHub 上的 Wiki 或 YouTube 频道！此应用并未包含全部信息。")
text("所有设备都有一个配置程序，你可以通过运行 'configure' 命令启动。")
sect("网络")
doc("usage_cfg_id", "电脑 ID", "电脑 ID 绝不能在不同设备之间相同，这只有在复制电脑时才会发生（例如在创造模式下中键点击它并再次放置）。")
doc("usage_cfg_chan", "频道", "频道用于电脑之间的通信，在连接指南章节中说明。同名的频道在系统中所有设备上必须具有相同的值，不同名称的频道不能重叠。")
doc("usage_cfg_to", "连接超时", "超过此时间后，设备将关闭连接并假定另一设备无响应。")
doc("usage_cfg_tr", "信任范围", "距离超过此方块距离的设备发送的任何网络流量都将被此设备拒绝。")
doc("usage_cfg_auth", "认证", "为提供一定级别的安全性，你可以通过设置密钥来启用全设施认证，密钥在所有设备上必须相同（且已设置）。这会增加每次网络传输的计算时间，因此只有在多人服务器上需要时才应启用。")
sect("日志")
text("日志会自动保存到电脑根目录下的 log.txt 文件中。你可以更改其路径、是否包含详细调试消息，以及每次程序运行时是追加还是覆盖。")
text("如果你希望共享日志，应保持为追加模式。")
doc("usage_cfg_log_upload", "共享日志", "要共享日志，请运行 'pastebin put log.txt'，然后分享生成的代码。")
sect("反应堆 PLC")
text("反应堆 PLC 必须连接到一个由其管理的裂变反应堆。使用配置程序选择其是否以联网模式运行。")
tip("反应堆 PLC 应始终与反应堆位于同一区块内，以确保在服务器启动和/或区块加载时能够保护它。")
doc("usage_cfg_plc_nonet", "非联网", "这让你可以将此设备用作高级独立安全系统，而不是基本的红石断路开关，以便更轻松地进行安全保护。")
doc("usage_cfg_plc_net", "联网", "这是最常用的模式。反应堆 PLC 需要连接到监管端才能运行，并通过该连接提供更高级的功能。")
doc("usage_cfg_plc_unit", "机组 ID", "联网时，你可以设置 1 到 4 之间的任何机组 ID。多个反应堆 PLC 不能共享相同的机组 ID。")
sect("RTU 网关")
text("RTU 网关允许将多个 RTU 接口连接到 SCADA 系统。这些接口可以是外部外设或红石。")
text("除裂变反应堆外，所有设备都必须通过 RTU 网关连接。")
sect("监管端")
text("监管端配置是整个系统的核心。如果你更改系统的内容（例如冷却设备或反应堆数量），必须在此更新。")
text("此配置包含许多在配置程序中说明更详细的设置，因此此处不再赘述。")
doc("usage_cfg_sv_tanks", "动态储罐", "动态储罐可用于为系统提供应急冷却剂（和/或辅助冷却剂）。通过混合使用设施储罐（连接到 1 个以上机组）和机组储罐（仅连接一个机组），可支持多种布局。")
doc("usage_cfg_sv_aux", "辅助冷却剂", "此冷却剂在反应堆启动时启用，以防止涡轮机升速期间反应堆或锅炉水位下降。它可以连接到动态储罐、水槽或任何其他水源。")
sect("协调器")
text("协调器配置主要围绕设置显示器。这最好在所有其他配置完成后进行。有关显示器尺寸的详细信息，请参阅 GitHub 上的 Wiki。")
tip("更改监管端上的机组数量时，也必须更新协调器。")
doc("usage_cfg_crd_main", "主显示器", "主显示器包含主界面和总览。它始终为 8 方块宽，高度根据机组数量而变化。")
doc("usage_cfg_crd_flow", "流量显示器", "流量显示器包含废料和冷却剂流量示意图。它始终为 8 方块宽，高度根据机组数量而变化。")
doc("usage_cfg_crd_unit", "机组显示器", "每个反应堆需要一个机组显示器，它始终是 4x4 的显示器。")
text("显示器可以通过直接接触或通过有线调制解调器连接。")
text("有多种单位和颜色选项可用于自定义显示器。使用 RF 以外的能量单位可能会影响与功率相关的自动控制设定值的精度，因为内部始终使用 RF。")
sect("Pocket")
text("你已经在这里了，没什么可说的！")
sect("自检")
text("大多数应用配置程序提供自检功能，用于检查配置和网络连接的有效性。如果该设备出现问题，你应该运行此功能。")
sect("配置变更")
text("当更新添加、删除或以其他方式修改配置要求时，系统会提醒你需要重新配置。你不会丢失任何先前数据，因为更新会保留配置，你只需重新按照说明逐步添加或更改新数据。")

target = docs.usage.manual
sect("概述")
text("手动反应堆控制仍包含安全检查与监控，但燃烧速率不会被自动控制。")
text("当机组显示器上选择 AUTO CTRL 选项为手动时，机组处于手动控制之下。")
note("此处不讨论具体界面。如需界面帮助，请参阅操作员界面 > 协调器界面 > 机组显示器。")
sect("手动控制")
text("协调器上的机组显示器用于运行手动控制。你也可以通过裂变反应堆的 Mekanism 界面启动/停止并设置燃烧速率。")
tip("如果机组显示器上某些控件显示为灰色，则表示该操作当前不可用，例如反应堆已启动或处于自动控制之下。")
text("手动控制通过 START 按钮启动，并按旁边的指令燃烧速率运行；可在启动前或启动后通过选择数值并按 SET 修改。")
text("反应堆可通过 SCRAM 停止，之后需要通过 RESET 重置 RPS。")

target = docs.usage.auto
sect("概述")
text("本系统的主要功能之一是支持多种受管控制模式的自动反应堆控制。")
tip("如果你不熟悉这些界面，在继续之前应先查看操作员界面 > 协调器下的主显示器和机组显示器文档。")
sect("配置")
note("自动控制激活期间无法修改配置。")
doc("usage_auto_assign", "机组分配", "自动控制仅适用于设置为手动以外模式的机组。为了优先使用某些机组或仅使用必要的最少数量，使用优先级组来分配所需的燃烧速率。")
text("将优先使用主机组，其次是次级机组，依此类推。如果多个机组分配到同一组，燃烧速率将在它们之间平均分配。")
text("只有当前优先级组无法满足该时刻自动控制所需的总燃烧速率时，才会使用下一优先级组。")
doc("usage_auto_setpoints", "设定值", "三种基于设定值的自动控制模式各有一个设定值微调输入。系统将尽力满足请求的值，当前值显示在输入下方。")
doc("usage_auto_limits", "机组限值", "每个机组都可以限制为最大自动控制燃烧速率，以防止超过你所知的任何安全水平。")
doc("usage_auto_states", "机组状态", "任何分配机组必须显示为就绪且未降级才能使用自动控制。有关更多信息，请参阅操作员界面 > 协调器 > 主显示器。")
sect("运行模式")
text("有五种自动控制模式可用，其功能基于主显示器上设置的配置。除监视最大燃烧和充能区间外，所有模式都会尽量只使用主机组，直到其无法跟上，然后再使用次级机组，依此类推。")
note("任何机组的燃烧速率都不会被设置为高于其限值。")
doc("usage_op_mon_max", "监视最大燃烧", "此模式以机组限值燃烧速率运行所有分配给自动控制的机组，无论优先级组如何。")
doc("usage_op_com_rate", "总燃烧速率", "分配机组将被命令满足燃烧目标设定值。")
doc("usage_op_chg_range", "充能区间", "如果充能百分比降至起始阈值，此模式将以机组限值燃烧速率运行所有分配给自动控制的机组，直到达到停止阈值，将其保持在该区间内。")
doc("usage_op_chg_level", "充能水平", "分配机组将被命令将能量存储系统充能提升至请求的充能目标。")
doc("usage_op_gen_rate", "生产效率", "分配机组将被命令维持请求的发电目标。")
note("所使用的速率是进入能量存储系统的输入速率，因此使用其他发电来源可能会干扰此控制模式。")
sect("启动与停止")
text("文本框用于显示系统状态。它还会提供系统暂停控制或启动失败的原因信息。")
text("在所有分配机组的所有设备均已连接且正常运行、且反应堆的 RPS 未跳闸之前，无法启动自动控制。")
doc("usage_op_save", "保存", "保存将保存配置而不启动控制。")
doc("usage_op_start", "启动", "启动将尝试启动自动控制，其中包括先保存配置。")
doc("usage_op_stop", "停止", "停止将停止所有分配给自动控制的反应堆。")

target = docs.usage.waste
sect("概述")
text("当连接'阀门'用于输送废料时，本系统可以管理生产哪种废料产品。流量显示器显示阀门应如何连接的示意图。")
text("共有三种废料产品，下面列出并附带通常与之关联的颜色。")
list(DOC_LIST_TYPE.LED, { "Pu - 钚", "Po - 钋", "AM - 反物质" }, { colors.cyan, colors.green, colors.purple })
note("在较旧版本的 Mekanism 中，Po 和 Pu 的颜色互换。")
sect("机组废料")
text("可以通过机组显示器右下角的按钮将机组设置为特定的废料产品。")
note("详细信息请参阅操作员界面 > 协调器界面 > 机组显示器。")
text("如果选择'自动'而不是废料产品，该机组的废料将按照设施废料控制进行处理。")
sect("设施废料")
text("设施废料控制通过自动控制为废料处理增加额外功能。")
text("主显示器上的废料控制界面允许你设置目标废料类型，以及可根据情况更改目标的选项。")
note("有关显示器和控制界面的信息，请参阅操作员界面 > 协调器界面 > 主显示器。")
doc("usage_waste_fallback", "钚备用", "当 SNA 无法跟上时（例如夜间），此选项将设施废料控制切换到钚。")
doc("usage_waste_sps_lc", "低充能 SPS", "此选项防止设施废料控制在能量存储系统充能较低（< 10%，达到 15% 后恢复）时停止反物质生产。")
text("启用该选项后，反物质生产将继续。禁用时，如果设置为反物质且充能较低，将切换为钋。")
note("钚备用具有优先权，无论低充能 SPS 设置如何，都会在适当时切换到钚。")

--#endregion

--#region Operator UIs

--#region Alarms

docs.alarms = {}

target = docs.alarms
doc("ContainmentBreach", "安全壳破裂", "反应堆断开连接或在损坏达到或超过 100% 时显示为未成形；假定已发生爆炸。")
doc("ContainmentRadiation", "安全壳辐射", "分配给该机组的环境探测器观察到高水平辐射。")
doc("ReactorLost", "反应堆丢失", "反应堆 PLC 已停止与监管端通信。")
doc("CriticalDamage", "损坏严重", "反应堆损坏已达到或超过 100%，随时可能爆炸。")
doc("ReactorDamage", "反应堆损坏", "反应堆温度导致反应堆外壳损坏持续增加。")
doc("ReactorOverTemp", "反应堆超温", "反应堆温度已达到或超过最高安全温度，因此正在受到损坏。")
doc("ReactorHighTemp", "反应堆温度偏高", "反应堆温度高于预期运行水平，可能很快超过最高安全温度。")
doc("ReactorWasteLeak", "反应堆废料泄漏", "反应堆已充满乏燃料，如果继续产生废料将释放辐射。")
doc("ReactorHighWaste", "反应堆废料过多", "反应堆废料水平较高，可能很快泄漏。")
doc("RPSTransient", "RPS 瞬态", "反应堆保护系统已激活。")
doc("RCSTransient", "RCS 瞬态", "反应堆冷却系统出现问题，请检查 RCS 指示灯以了解详情。")
doc("TurbineTripAlarm", "涡轮机跳闸", "涡轮机停止旋转，可能是由于能量存储已满。这将阻止冷却，因此在使用该机组之前必须解决此问题。")


--#endregion

--#region Annunciators

docs.annunc = {
    unit = {
        main_section = {}, rps_section = {}, rcs_section = {}
    },
    facility = {
        main_section = {}
    }
}

target = docs.annunc.unit.main_section
sect("机组状态")
doc("PLCOnline", "PLC 在线", "指示裂变反应堆 PLC 是否已连接。如果未连接，请检查你的 PLC 是否已开启并配置正确。")
doc("PLCHeartbeat", "PLC 心跳", "状态数据实时的指示器。每当从 PLC 收到状态消息时，此灯会亮起和熄灭。如果它卡住，说明监管端已停止接收数据或某个屏幕已冻结。")
doc("RadiationMonitor", "辐射监测器", "当至少一个环境探测器已连接并分配给此机组时亮起。")
doc("AutoControl", "自动控制", "当反应堆处于某一种自动控制模式的控制之下时亮起。")
sect("安全状态")
doc("ReactorSCRAM", "反应堆急停", "当反应堆保护系统正在保持反应堆急停状态时亮起。")
doc("ManualReactorSCRAM", "手动反应堆急停", "当操作员（你）发起急停时亮起。")
doc("AutoReactorSCRAM", "自动反应堆急停", "当自动控制系统发起急停时亮起。主视图屏幕的警报器将指示原因。")
doc("RadiationWarning", "辐射警告", "当辐射水平高于正常水平时亮起。可能某处存在泄漏，应查明并修复。建议穿戴防护服。")
doc("RCPTrip", "RCP 跳闸", "反应堆冷却剂泵跳闸。这是一个不直接对应 Mekanism 的技术概念。此处表示存在受热冷却剂过多或冷却冷却剂过少导致 RPS 跳闸。如果发生这种情况，请检查冷却剂系统。")
doc("RCSFlowLow", "RCS 流量低", "指示反应堆冷却系统流量是否偏低。当反应堆中冷却冷却剂液位下降时可观察到。这可能发生在涡轮机加速期间，但如果持续存在，请检查冷却系统是否正常运行。使用较小的锅炉或使用管道且容量不足时可能发生。")
doc("CoolantLevelLow", "冷却剂液位低", "当反应堆冷却剂液位低于应有水平时亮起。请检查冷却剂系统。")
doc("ReactorTempHigh", "反应堆温度高", "当反应堆温度高于预期的最高运行温度时亮起。这还不会造成损坏，但应予以关注。请检查冷却剂系统。")
doc("ReactorHighDeltaT", "反应堆温差高", "当反应堆温度快速上升时亮起。反应堆启动时可能发生，但如果发生在燃烧速率未增加时则值得关注。")
doc("FuelInputRateLow", "燃料输入速率低", "当反应堆中裂变燃料液位下降或非常低时亮起。燃料最大燃烧速率限制启用时也会激活。确保燃料持续稳定地进入反应堆。")
doc("WasteLineOcclusion", "废料管线堵塞", "反应堆中废料水平正在上升。确保你的废料处理系统以足够匹配燃烧速率的速率运行。")
doc("HighStartupRate", "启动速率过高", "这是对你的燃烧速率是否足以在启动时导致冷却剂流失的粗略计算。高于此值的燃烧速率很可能导致该问题，但根据你的设置（例如管道、供水系统和锅炉储罐），它也可能在更高甚至更低的速率下发生。")

target = docs.annunc.unit.rps_section
doc("rps_tripped", "RPS 跳闸", "指示反应堆保护系统是否已导致急停。")
doc("manual", "手动反应堆急停", "指示操作员（你）是否通过按下 SCRAM 触发 RPS。")
doc("automatic", "自动反应堆急停", "指示自动控制系统是否触发 RPS。")
doc("timeout", "连接超时", "指示 RPS 是否因与监管电脑失去连接而跳闸。请检查你的 PLC 和监管端是否保持区块加载。")
doc("fault", "PLC 硬件故障", "指示 RPS 是否因外设访问故障而跳闸。与反应堆交互时出现问题，请尝试重启 PLC。")
doc("sys_fail", "反应堆系统故障", "指示 RPS 是否因反应堆未成形而跳闸。请确保多方块结构已成形。")
doc("high_dmg", "损伤水平高", "指示 RPS 是否因反应堆严重损坏而跳闸。请等待损伤水平降低。")
doc("high_temp", "堆芯温度高", "指示 RPS 是否因达到损伤性温度而跳闸。请等待损伤水平降低。")
doc("ex_waste", "废料过多", "指示 RPS 是否因废料水平过高而跳闸。请确保废料处理系统能跟上。")
doc("low_cool", "冷却剂液位极低", "指示 RPS 是否因冷却剂液位极低导致温度失控上升而跳闸。请确保冷却系统能够提供足够的冷却冷却剂流量。")
doc("ex_hcool", "受热冷却剂过多", "指示 RPS 是否因受热冷却剂水平过高而跳闸。请检查冷却系统能否跟上受热冷却剂流量。")

target = docs.annunc.unit.rcs_section
doc("RCSFault", "RCS 硬件故障", "指示一个或多个 RCS 设备是否发生外设故障。请检查你的机器是否已成形。如果持续存在，请尝试重启受影响的 RTU。")
doc("EmergencyCoolant", "应急冷却剂", "未配置应急冷却剂红石时为熄灭，已配置但未使用时为白色，激活时为绿色/蓝色。这基于为机组配置了红石应急冷却剂输出的 RTU。")
doc("CoolantFeedMismatch", "冷却剂供给不匹配", "冷却系统正在积累受热冷却剂或流失冷却冷却剂，很可能是由于其中一台机器无法满足反应堆的需求。流量显示器可以帮助查明问题所在。")
doc("BoilRateMismatch", "沸腾速率不匹配", "反应堆的总加热速率超过涡轮机蒸汽输入速率的容差；对于钠冷却配置，锅炉沸腾速率超过涡轮机蒸汽输入速率的容差。流量显示器可以帮助查明问题所在。")
doc("SteamFeedMismatch", "蒸汽供给不匹配", "涡轮机流量与蒸汽输入速率之间存在超出容差的差异，或反应堆/锅炉在增加蒸汽或流失水。流量显示器可以帮助查明问题所在。")
doc("MaxWaterReturnFeed", "最大回水供给", "涡轮机正按结构构建所允许的最大速率冷凝水。如果回水不足，请为涡轮机添加更多饱和冷凝器。")
doc("WaterLevelLow", "水位低", "锅炉中的水位偏低。更大的锅炉水箱可能会有帮助，或者你可以从其他地方向锅炉补充水。")
doc("HeatingRateLow", "加热速率低", "锅炉温度不足以烧开水，但它正在接收受热冷却剂。这几乎从来不是安全问题。")
doc("SteamDumpOpen", "蒸汽泄压阀打开", "如果涡轮机设置为排放多余蒸汽，此灯变为黄色；如果设置为排放[全部]，则变为红色。此处的'泄压阀'是指允许排放蒸汽的设置。你绝不应将其设置为排放[全部]。监管端触发的应急冷却剂会自动将其设置为排放多余蒸汽，以确保加水时不会积压蒸汽。")
doc("TurbineOverSpeed", "涡轮机超速", "涡轮机已达到蒸汽容量，但未跳闸。如果它们跟不上，你可能需要更多涡轮机。")
doc("GeneratorTrip", "发电机跳闸", "涡轮机因能量无处可去而不再输出电力。很可能是能量存储已满。如果不处理，将导致涡轮机跳闸。")
doc("TurbineTrip", "涡轮机跳闸", "涡轮机已达到最大能量充能并停止旋转，因此停止了将蒸汽冷却为水。确保涡轮机有输出电力的地方，这是反应堆熔毁最常见的原因。不过，在本系统下发生熔毁的可能性要低得多，尤其是在涡轮机跳闸时有应急冷却剂帮助的情况下。")

target = docs.annunc.facility.main_section
sect("连接状态")
doc("all_sys_ok", "机组系统在线", "所有机组系统（反应堆、锅炉和涡轮机）均已连接。")
doc("rad_computed_status", "辐射监测器", "至少一个设施辐射监测器已连接。")
doc("ess_computed_status", "能量存储系统", "能量存储系统（感应矩阵或能量核心）已连接。")
doc("sps_computed_status", "SPS 已连接", "指示超临界移相器是否已连接。")
sect("自动控制")
doc("auto_ready", "已配置机组就绪", "所有分配给自动控制的机组都已准备好运行自动控制。")
doc("auto_active", "工艺运行中", "自动工艺控制处于激活状态。")
doc("auto_ramping", "工艺升速中", "自动工艺控制正在对反应堆进行初始升速，以便之后进行 PID 控制（生产模式和充能模式）。")
doc("auto_saturated", "最小/最大燃烧速率", "自动控制已命令 0 mB/t 或（来自分配机组的）最大总燃烧速率。")
sect("自动急停")
doc("auto_scram", "自动急停", "自动控制系统因安全危害而急停了分配的反应堆，如下方指示灯所示。")
doc("as_ess_fault", "ESS 硬件故障", "由于能量存储连接丢失、未成形或发生故障而触发自动急停。")
doc("as_ess_fill", "ESS 充能过高", "由于能量存储充能超过可接受限值而触发自动急停。")
doc("as_crit_alarm", "机组严重警报", "由于机组严重级别的警报而触发自动急停。")
doc("as_radiation", "设施辐射过高", "由于设施辐射水平过高而触发自动急停。")
doc("as_gen_fault", "发电控制故障", "由于生产模式下分配机组降级/不再就绪而触发自动急停。问题解决后，系统将自动恢复（从初始升速开始）。")

--#endregion

--#region Coordinator UI

docs.c_ui = {
    main = {}, flow = {}, unit = {}
}

target = docs.c_ui.main
sect("设施示意图")
text("设施总览图由机组示意图组成，显示反应堆、锅炉（如果存在）和涡轮机。其中包括各种关键统计数据（如温度）以及显示每个多方块结构中储罐填充百分比的条形图。")
text("锅炉显示在反应堆下方，按索引顺序排列（下面的 #1 然后 #2）。涡轮机显示在右侧，也按索引顺序排列（索引按机组划分，在 RTU 网关配置中设置）。")
text("管道连接以颜色编码的线条可视化，主要用于指示连接，因为并非所有设施都使用管道。")
note("如果你拥有的组件没有显示，请确保监管端已针对你的实际冷却配置进行配置。")
sect("设施状态")
note("此处的警报器在操作员界面 > 警报器中说明。")
doc("ui_fac_scram", "设施急停", "此按钮急停设施中的所有机组。")
doc("ui_fac_ack", "ACK \x13", "此按钮确认（静音）设施中所有机组的全部警报。")
doc("ui_fac_rad", "辐射", "设施辐射，即所有已连接设施辐射监测器（不包括机组监测器）的当前最大值。")
doc("ui_fac_linked", "已连接 RTU", "已连接的 RTU 网关数量。")
sect("自动控制")
text("此界面用于管理自动设施控制，仅适用于通过机组显示器设置为自动控制的机组。其中包括设定值、状态、配置和控制。")
doc("ui_fac_auto_alt", "\x12T/\x12R", "充能目标/充能区间旁边的这个选择器让你在充能目标控制和充能区间控制之间切换。")
doc("ui_fac_auto_bt", "燃烧目标", "当设置为总燃烧速率模式时，分配机组将升速以达到此总目标。")
doc("ui_fac_auto_cr", "充能区间", "当设置为充能区间模式时，一旦能量存储系统充能百分比降至起始阈值，分配机组将运行，直到达到停止阈值，将其保持在该区间内。")
doc("ui_fac_auto_ct", "充能目标", "当设置为充能水平模式时，分配机组将运行以达到并维持此能量存储系统充能水平。")
doc("ui_fac_auto_gt", "发电目标", "当设置为生产效率模式时，分配机组将运行以达到并维持此持续电力输出，即分配机组涡轮机生产效率之和。")
doc("ui_fac_save", "保存", "此按钮保存你的配置而不启动控制。")
doc("ui_fac_start", "启动", "此按钮启动已配置的自动控制。")
tip("启动也包含保存操作。")
doc("ui_fac_stop", "停止", "此按钮终止自动控制，停止分配机组。")
text("共有四种自动控制模式，详见系统使用 > 自动控制。")
doc("ui_fac_auto_mmb", "监视最大燃烧", "此模式以最大配置速率运行所有分配机组。")
doc("ui_fac_auto_cbr", "总燃烧速率", "此模式运行分配机组以达到目标总速率。")
doc("ui_fac_auto_cl", "充能水平", "此模式运行分配机组以维持能量存储系统充能水平。")
doc("ui_fac_auto_gr", "生产效率", "此模式运行分配机组以达到目标分配机组涡轮机总生产效率。")
doc("ui_fac_auto_lim", "机组限值", "每个机组都可以设置自动控制永远不会超过的限值。")
doc("ui_fac_unit_ready", "机组状态就绪", "只有所有多方块结构均已成形、在线且收到数据、且没有 RPS 跳闸时，机组才准备好进行自动控制。")
doc("ui_fac_unit_degraded", "机组状态降级", "如果反应堆、锅炉和/或涡轮机发生故障或未连接，机组即为降级。")
sect("废料控制")
text("机组状态上方是机组废料状态，显示哪些机组设置为自动废料模式以及该机组当前的实际废料产量。")
text("设施自动废料控制界面被棕色边框包围，让你可以配置该系统，从请求的废料产品开始。")
doc("ui_fac_waste_pu_fall_act", "备用激活", "当系统在 SNA 无法跟上时回退到钚生产。")
doc("ui_fac_waste_sps_lc_act", "SPS 低充能禁用", "当能量存储系统充能降至 10% 以下且尚未达到 15% 时，系统回退到钋生产以防止 SPS 耗尽所有电力。")
doc("ui_fac_waste_pu_fall", "钚备用", "当 SNA 无法跟上时（例如夜间）从 Po 或反物质切换。")
doc("ui_fac_waste_sps_lc", "低充能 SPS", "即使在能量存储系统充能水平较低（<10%）时也继续运行反物质生产。")
sect("感应矩阵")
text("感应矩阵统计数据显示在右下角，包括 FILL、I（输入速率）和 O（输出速率）的填充条。")
text("平均值由系统计算，而其他数据直接来自设备。")
doc("ui_fac_im_charge", "充能中", "充能正在增加（输入多于输出）。")
doc("ui_fac_im_discharge", "放电中", "充能正在减少（输出多于输入）。")
doc("ui_fac_im_maxio", "最大 I/O 速率", "感应供电器正处于最大速率。")
doc("ui_fac_im_eta", "ETA", "ETA 基于较长时间的平均值，可能需要一分钟才能稳定，但会给出充能/放电时间的粗略估计。")
sect("能量核心")
text("能量核心统计数据显示在右下角，包括 FILL 的填充条。")
text("平均值由系统计算，而其他数据直接来自设备。")
doc("ui_fac_ec_charge", "充能中", "充能正在增加（输入多于输出）。")
doc("ui_fac_ec_discharge", "放电中", "充能正在减少（输出多于输入）。")
doc("ui_fac_ec_eta", "ETA", "ETA 基于较长时间的平均值，可能需要一分钟才能稳定，但会给出充能/放电时间的粗略估计。")

target = docs.c_ui.flow
sect("流量示意图")
text("冷却剂和废料流量显示器是一个大型 P&ID（工艺和仪表图），显示这些流量的总览。")
text("使用颜色编码的管道显示连接，阀门符号 \x10\x11 用于显示阀门（红石控制的管道）。")
doc("ui_flow_rates", "流量速率", "流量速率始终显示在相应管道下方，并尽可能直接来自设备。废料流量基于反应堆燃烧速率，SNA 下游的所有流量基于 SNA 生产效率。")
doc("ui_flow_valves", "标准阀门", "阀门命名（PV00-XX）基于 P&ID 命名约定。这些阀门在整个设施中递增编号，并使用末尾的标签增加清晰度。")
note("当关联的红石 RTU 连接时，标签旁边的指示灯会亮起。")
list(DOC_LIST_TYPE.BULLET, { "PU: 钚", "PO: 钋", "PL: 钋粒", "AM: 反物质", "EMC: 应急冷却剂", "AUX: 辅助冷却剂" })
doc("ui_flow_valve_open", "开启", "指示相应的阀门是否被命令开启。")
doc("ui_flow_prv", "PRV", "泄压阀（PRV）用于显示每台涡轮机的蒸汽排放状态。")
list(DOC_LIST_TYPE.LED, { "未排放", "排放多余", "排放" }, { colors.gray, colors.yellow, colors.red })
sect("SNA")
text("由于支持大量变量，太阳能中子激活器在流量示意图中显示为组合方块。")
tip("SNA 消耗的废料是其反物质产量的 10 倍，因此在连接过多 SNA 之前请考虑这一点。")
doc("ui_flow_sna_act", "运行中", "SNA 具有非零总流量。")
doc("ui_flow_sna_cnt", "CNT", "分配给该机组的 SNA 数量。")
doc("ui_flow_sna_peak_o", "PEAK\x1a", "SNA 在完全日照下可以达到的理论峰值输出总和。")
doc("ui_flow_sna_max_o", "MAX \x1a", "SNA 当前的最大输出速率总和（基于当前日照）。")
doc("ui_flow_sna_max_i", "\x1aMAX", "计算得出的最大输入速率总和（输出速率的 10 倍）。")
doc("ui_flow_sna_in", "\x1aIN", "进入 SNA 的当前输入速率。")
sect("动态储罐")
text("为系统配置的动态储罐列在左侧。标题可能以 U（机组储罐）或 F（设施储罐）开头。")
text("填充信息和水位显示在状态标签下方。")
doc("ui_flow_dyn_fill", "填充", "如果储罐模式（通过 Mekanism 界面）启用了填充。")
doc("ui_flow_dyn_empty", "排空", "如果储罐模式（通过 Mekanism 界面）启用了排空。")
sect("SPS")
doc("ui_flow_sps_in", "输入速率", "进入 SPS 的钋速率。")
doc("ui_flow_sps_prod", "生产效率", "SPS 生产反物质的速率。")
sect("统计")
text("所有机组废料速率统计的总和显示在 SPS 方块下方。这些是合并的当前速率，不是长期总和。")
doc("ui_flow_stat_raw", "原始废料", "反应堆在加工前产生的原始废料的总速率。")
doc("ui_flow_stat_proc", "加工废料", "不同废料产品生产速率的总和。Pu 是钚，Po 是钋，PoPl 是钋粒。反物质显示在 SPS 方块中。")
doc("ui_flow_stat_spent", "乏燃料", "加工后产生的乏燃料的总速率。")
sect("其他方块")
text("其他方块（例如离心机）对应不打算连接和/或作为标签的设备。")

target = docs.c_ui.unit
sect("数据显示")
text("机组显示器包含大量数据信息，包括操作员界面部分中相关章节描述的警报器和警报显示。")
doc("ui_unit_core", "堆芯图", "右上角显示堆芯图，按堆芯温度着色。布局基于多方块结构尺寸。")
list(DOC_LIST_TYPE.BULLET, { "灰 <= 300\xb0C", "蓝 <= 350\xb0C", "绿 < 600\xb0C", "黄 < 100\xb0C", "橙 < 1200\xb0C", "红 < 1300\xb0C", "粉 >= 1300\xb0C" })
text("内部储罐（燃料、冷却冷却剂、受热冷却剂和废料）显示在堆芯图下方，分别标记为 F、C、H 和 W。")
doc("ui_unit_rad", "辐射", "机组辐射，即分配给此机组的所有已连接辐射监测器的当前最大值。")
text("还显示许多其他数据值，但它们应该不言自明。")
sect("控制")
text("一组按钮和燃烧速率输入用于手动反应堆控制。在自动模式下，不可用的控件会被禁用。燃烧速率仅在按下 SET 后生效。")
doc("ui_unit_start", "启动", "此按钮按请求的燃烧速率启动反应堆。")
doc("ui_unit_scram", "急停", "此按钮急停反应堆。")
doc("ui_unit_ack", "ACK \x13", "此按钮确认此机组上的警报。")
doc("ui_unit_reset", "重置", "此按钮重置此机组的 RPS。")
sect("自动控制")
text("要将此机组置于自动控制之下，请选择手动以外的选项。你必须按 SET 应用此设置，但在自动控制激活期间无法更改。可用的优先级在系统使用 > 自动控制中说明。")
doc("ui_unit_prio", "优先级组", "显示机组的自动控制优先级组。")
doc("ui_unit_ready", "就绪", "指示机组是否准备好进行自动控制。只有所有多方块结构均已成形、在线且收到数据、且没有 RPS 跳闸时，机组才准备好进行自动控制。")
doc("ui_unit_standby", "待机", "指示机组是否设置为自动控制且处于激活状态，但自动控制当前不需要此反应堆运行，因此它处于待机状态。")
sect("废料处理")
text("可以通过这些按钮设置机组的废料输出配置。自动将使此机组受设施废料控制管理，否则系统将始终为此机组命令所请求的选项。")

--#endregion

--#endregion

--#region Front Panels

docs.fp = {
    common = {}, r_plc = {}, rtu_gw = {}, supervisor = {}, coordinator = {}
}

target = docs.fp.common
sect("核心状态")
doc("fp_status", "STATUS", "此灯始终点亮，反应堆 PLC 除外（参见反应堆 PLC 章节）。")
doc("fp_heartbeat", "HEARTBEAT", "此灯随着设备上主循环的运行在点亮和熄灭之间交替。如果它冻结，则说明出了问题，日志会指示原因。")
sect("硬件与网络")
doc("fp_modem", "MODEM", "如果你只有一个调制解调器，此灯指示通信调制解调器的状态。如果你有两个，它们将命名为 WD/WL MODEM。")
list(DOC_LIST_TYPE.LED, { "已断开", "链路断开", "链路已连接" }, { colors.gray, colors.yellow, colors.green })
doc("fp_modem", "WD MODEM", "此灯指示有线通信调制解调器的状态。")
list(DOC_LIST_TYPE.LED, { "已断开", "链路断开", "链路已连接" }, { colors.gray, colors.yellow, colors.green })
doc("fp_modem", "WL MODEM", "此灯指示无线/末影通信调制解调器的状态。")
list(DOC_LIST_TYPE.LED, { "已断开", "链路断开", "链路已连接" }, { colors.gray, colors.yellow, colors.green })
doc("fp_network", "NETWORK", "在标准颜色模式下存在，使用多种颜色指示网络状态。")
list(DOC_LIST_TYPE.LED, { "未连接", "已连接", "连接被拒绝", "通信版本错误", "重复 PLC" }, { colors.gray, colors.green, colors.red, colors.orange, colors.yellow })
text("你可以通过确保所有设备都是最新版本来修复\"通信版本错误\"，因为这表示通信协议版本不匹配。请注意，黄色是反应堆 PLC 特有的，表示正在使用重复的机组 ID。")
doc("fp_nt_linked", "NT LINKED", "（仅限颜色无障碍模式）", "指示设备是否已与监管端连接。")
doc("fp_nt_version", "NT VERSION", "（仅限颜色无障碍模式）", "指示监管端与本设备的通信版本不匹配。确保所有内容都是最新版本。")
sect("硬件标签")
doc("fp_fw", "FW", "此设备的固件应用版本。")
doc("fp_nt", "NT", "此设备拥有的网络（通信）版本。设备之间必须匹配才能连接。")
doc("fp_sn", "SN", "设备\"序列号\"，由电脑 ID（显示在监管端、协调器和 Pocket 连接列表中）和设备类型组成。")

target = docs.fp.r_plc
sect("概述")
text("反应堆 PLC 特有的前面板项目文档如下。未在本节中涵盖的项目请参阅'通用项目'。")
sect("核心状态")
doc("fp_status", "STATUS", "PLC 初始化且正常（拥有所有外设）时为绿色，如果出现问题则为红色，此时应查看其他指示灯（REACTOR 和 MODEM）。")
sect("硬件与网络")
doc("fp_rplc_reactor", "REACTOR", "指示已连接反应堆外设的状态。")
list(DOC_LIST_TYPE.LED, { "已断开", "未成形", "正常" }, { colors.red, colors.yellow, colors.green })
doc("fp_nt_collision", "NT COLLISION", "（仅限颜色无障碍模式）", "指示反应堆 PLC 的机组 ID 与另一个已连接的反应堆 PLC 重复。")
sect("协程状态")
doc("fp_rplc_rt_main", "RT MAIN", "只要设备的主循环协程在运行，此灯就会点亮，只要 STATUS 为绿色就应该点亮。")
doc("fp_rplc_rt_rps", "RT RPS", "如果连接了反应堆，此灯应始终点亮，因为它指示 RPS 协程正在运行，否则安全检查将不会运行。")
doc("fp_rplc_rt_ctx", "RT COMMS TX", "如果反应堆 PLC 未以独立模式运行，此灯应始终点亮，因为它指示通信传输协程正在运行。")
doc("fp_rplc_rt_crx", "RT COMMS RX", "如果反应堆 PLC 未以独立模式运行，此灯应始终点亮，因为它指示通信接收/处理协程正在运行。")
doc("fp_rplc_rt_spctl", "RT SPCTL", "如果反应堆 PLC 未以独立模式运行，此灯应始终点亮，因为它指示工艺设定值控制器协程正在运行。")
sect("状态")
doc("fp_rct_active", "RCT 运行中", "反应堆正在运行（运行中）。")
doc("fp_emer_cool", "应急冷却剂", "仅当该设备配置了 PLC 控制的应急冷却剂时才存在。点亮时表示它已被激活。")
doc("fp_rps_trip", "RPS 跳闸", "当 RPS 因安全跳闸而急停反应堆时闪烁。")
sect("RPS 条件")
doc("fp_rps_man", "手动", "RPS 被手动触发（用户急停，而不是通过 Mekanism 反应堆界面）。")
doc("fp_rps_auto", "自动", "RPS 被监管端自动触发。")
doc("fp_rps_to", "超时", "RPS 因失去监管端连接而跳闸。")
doc("fp_rps_pflt", "PLC 故障", "RPS 因外设错误而跳闸。")
doc("fp_rps_rflt", "反应堆故障", "RPS 因反应堆未成形而跳闸。")
doc("fp_rps_temp", "高损伤", "RPS 因损坏 >= " .. const.RPS_LIMITS.MAX_DAMAGE_PERCENT .. "% 而跳闸。")
doc("fp_rps_temp", "高温", "RPS 因反应堆温度过高（>= " .. const.RPS_LIMITS.MAX_DAMAGE_TEMPERATURE .. "K）而跳闸。")
doc("fp_rps_waste", "高废料", "RPS 因废料水平过高（>" .. (const.RPS_LIMITS.MAX_WASTE_FILL * 100) .. "%）而跳闸。")
doc("fp_rps_ccool", "冷却剂不足", "RPS 因冷却冷却剂水平过低（<" .. (const.RPS_LIMITS.MIN_COOLANT_FILL * 100) .. "%）而跳闸。")
doc("fp_rps_ccool", "受热冷却剂过多", "RPS 因受热冷却剂水平过高（>" .. (const.RPS_LIMITS.MAX_HEATED_COOLANT_FILL * 100) .. "%）而跳闸。")

target = docs.fp.rtu_gw
sect("概述")
text("RTU 网关特有的前面板项目文档如下。未在本节中涵盖的项目请参阅'通用项目'。")
doc("fp_rtu_spkr", "扬声器", "连接到此 RTU 网关的扬声器外设数量。")
sect("协程状态")
doc("fp_rtu_rt_main", "RT MAIN", "指示设备的主循环协程是否在运行。")
doc("fp_rtu_rt_comms", "RT COMMS", "指示通信处理协程是否在运行。")
sect("设备列表")
doc("fp_rtu_rt", "RT", "在每个 RTU 条目行中，RT 灯指示该 RTU 机组的协程是否在运行。红石机组从不点亮。")
doc("fp_rtu_rt", "设备状态", "在每个 RTU 条目行中，设备名称左侧的灯指示其外设状态。")
list(DOC_LIST_TYPE.LED, { "已断开", "故障", "未成形", "正常" }, { colors.red, colors.orange, colors.yellow, colors.green })
text("请注意，已断开的设备缺少详细信息，并且在重新连接之前无法在配置中修改。")
doc("fp_rtu_rt", "设备分配", "在每个 RTU 条目行中，设备标识位于状态灯右侧。它以设备类型及其索引开头，后跟 \x1a 之后的分配，即机组或设施（FACIL）。机组 1 的第 3 台涡轮机将显示为'TURBINE 3 \x1a UNIT 1'。")

target = docs.fp.supervisor
sect("往返时间")
doc("fp_sv_rtt", "RTT", "每个连接都有往返时间（RTT）。由于监管端以 150ms 的速率更新，约 150ms 至 300ms 的 RTT 是典型的。较高的 RTT 表示延迟，如果达到数千毫秒将会出现性能问题。")
list(DOC_LIST_TYPE.BULLET, { "绿色: <=300ms", "黄色: <=500ms ", "红色: >500ms" })
sect("SVR 选项卡")
text("此选项卡包含有关监管端的信息，涵盖于'通用项目'中。")
sect("PLC 选项卡")
text("此选项卡根据已配置机组的数量列出预期的 PLC 连接。连接时显示每个连接的状态信息。")
doc("fp_sv_link", "LINK", "指示反应堆 PLC 是否已连接。")
doc("fp_sv_p_cmpid", "PLC 电脑 ID", "显示反应堆 PLC 的电脑 ID，如果断开则显示 ---。")
doc("fp_sv_p_fw", "PLC FW", "显示反应堆 PLC 的固件版本。")
sect("RTU 选项卡")
text("当 RTU 网关连接到监管端时，它们会连同一些信息显示在此处。")
doc("fp_sv_r_cmpid", "RTU 电脑 ID", "条目开头是 @ 符号，后跟 RTU 网关的电脑 ID。")
doc("fp_sv_r_units", "UNITS", "这是 RTU 网关上配置的 RTU 数量计数（RTU 网关前面板上的每一行）。")
doc("fp_sv_r_fw", "RTU FW", "显示 RTU 网关的固件版本。")
sect("PKT 选项卡")
text("当口袋电脑连接到监管端时，它们会连同一些信息显示在此处。列出的属性与 RTU 网关相同（UNITS 除外），因此此处不再赘述。")
sect("DEV 选项卡")
text("如果没有连接任何设备，此选项卡将列出所有未找到的预期 RTU 设备。如果一切连接和配置正确，此页面应为空白。否则，它将列出某些类型的可检测问题。")
doc("fp_sv_d_miss", "缺失", "这些条目列出缺失的设备，以及应在 RTU 配置中使用的详细信息。")
doc("fp_sv_d_oor", "索引错误", "如果某个配置条目的索引超出监管端配置的最大设备数量，将显示此处指示哪个条目不正确。例如，如果你指定一个机组有 2 台涡轮机并连接了 #3，它将在此处显示为超出范围。")
doc("fp_sv_d_dupe", "重复", "如果某个设备尝试连接但其配置与另一设备相同，它将被拒绝并显示在此处。如果你尝试为机组连接两台 #1 涡轮机，将失败，其中一台会出现在此处。")
sect("INF 选项卡")
text("此选项卡提供有关其他选项卡的信息，以及 DEV 选项卡的额外详情。")

target = docs.fp.coordinator
sect("往返时间")
doc("fp_crd_rtt", "RTT", "每个连接都有往返时间（RTT）。由于协调器以 500ms 的速率更新，约 500ms 至 1000ms 的 RTT 是典型的。较高的 RTT 表示延迟，会导致性能问题。")
list(DOC_LIST_TYPE.BULLET, { "绿色: <=1000ms", "黄色: <=1500ms ", "红色: >1500ms" })
sect("CRD 选项卡")
text("此选项卡包含有关协调器的信息，部分涵盖于'通用项目'中。")
doc("fp_crd_rt_main", "RT MAIN", "指示设备的主循环协程是否在运行。")
doc("fp_crd_rt_render", "RT RENDER", "指示协调器图形渲染器协程是否在运行。")
doc("fp_crd_spkr", "扬声器", "指示扬声器是否已连接。")
doc("fp_crd_mon_main", "主显示器", "主显示器的状态。")
list(DOC_LIST_TYPE.LED, { "已断开", "视图未加载", "视图已加载" }, { colors.gray, colors.red, colors.green })
doc("fp_crd_mon_flow", "流量显示器", "冷却剂和废料流量显示器的状态。")
list(DOC_LIST_TYPE.LED, { "已断开", "视图未加载", "视图已加载" }, { colors.gray, colors.red, colors.green })
doc("fp_crd_mon_unit", "机组 X 显示器", "与给定机组关联的显示器的状态。")
list(DOC_LIST_TYPE.LED, { "已断开", "视图未加载", "视图已加载" }, { colors.gray, colors.red, colors.green })
sect("API 选项卡")
text("此选项卡列出已连接的口袋电脑。有关字段的详细信息，请参阅监管端 PKT 选项卡文档。")

--#endregion

--#region Glossary

docs.glossary = {
    abbvs = {}, terms = {}
}

target = docs.glossary.abbvs
doc("G_ACK", "ACK", "警报确认。按下此按钮表示你确认已发生警报并希望停止音频提示音。")
doc("G_Auto", "自动", "自动的。")
doc("G_CRD", "CRD", "协调器。协调器电脑的缩写。")
doc("G_ESS", "ESS", "能量存储系统。")
doc("G_FP", "FP", "前面板。")
doc("G_Hi", "Hi", "高。")
doc("G_Lo", "Lo", "低。")
doc("G_PID", "PID", "比例积分微分（PID）闭环控制器。")
doc("G_PKT", "PKT", "Pocket。口袋电脑的缩写。")
doc("G_PLC", "PLC", "可编程逻辑控制器。不仅能报告数据和控制输出，还能自行做出决策的设备。")
doc("G_PPM", "PPM", "受保护外设管理器。为本项目创建的抽象层，可防止外设调用导致应用程序崩溃。")
doc("G_RCP", "RCP", "反应堆冷却剂泵。这来自水冷（沸水堆和压水堆）反应堆的真实术语，但在本系统中它仅反映反应堆冷却剂流量的运行情况。有关更多信息，请参阅相关警报器页面。")
doc("G_RCS", "RCS", "反应堆冷却系统。用于冷却反应堆的所有机器（涡轮机、锅炉、动态储罐）的组合。")
doc("G_RPS", "RPS", "反应堆保护系统。反应堆 PLC 中负责保证反应堆安全的组件。")
doc("G_RTU", "RT", "协程。用于在前面板上标识核心 Lua 协程的状态。")
doc("G_RTU", "RTU", "远程终端单元。为 SCADA 系统提供监控和基本输出，与各种类型的设备/接口交互。")
doc("G_SCADA", "SCADA", "监控与数据采集。广泛用于各种工艺控制应用的控制系统架构。")
doc("G_SVR", "SVR", "监管端。监管电脑的缩写。")
doc("G_UI", "UI", "用户界面。")

target = docs.glossary.terms
doc("G_AssignedUnit", "分配机组", "分配给自动控制组（而非手动）的机组。")
doc("G_AuxCoolant", "辅助冷却剂", "在初始升速期间向反应堆或锅炉补充涡轮机回水的独立进水。")
doc("G_EmerCoolant", "应急冷却剂", "当反应堆或锅炉没有足够的水来阻止反应堆失控过热时使用的动态储罐或其他水源。")
doc("G_EnergyStorage", "能量存储系统", "用于存储能量的系统，例如感应矩阵或能量核心。")
doc("G_Fault", "故障", "出现问题且/或无法正常工作。")
doc("G_FrontPanel", "前面板", "设备正面的基本界面，用于查看有时修改其状态。这就是你查看运行 SCADA 应用程序之一的电脑时看到的内容。")
doc("G_HighHigh", "极高", "非常高。")
doc("G_LowLow", "极低", "非常低。")
doc("G_Nominal", "正常", "正常运行。一切按预期运行。")
doc("G_Ringback", "回铃", "表示警报曾经触发但不再满足其触发条件。这是为了让你知道它发生过。")
doc("G_SCRAM", "SCRAM", "[紧急]通过停止裂变来关闭反应堆。在 Mekanism 和本系统中，它并不总是用于紧急情况。")
doc("G_Transient", "瞬态", "偏离正常运行的临时状态变化。冷却剂液位下降或堆芯温度高于正常值是瞬态的示例。")
doc("G_Trip", "跳闸", "已发生检查条件，参见'已跳闸'。")
doc("G_Tripped", "已跳闸", "警报条件已满足且仍满足。")
doc("G_Tripping", "跳闸中", "警报条件已满足，但尚未达到将其视为问题的最短时间。")
doc("G_TurbineTrip", "涡轮机跳闸", "涡轮机停止，阻止受热冷却剂被冷却。在 Mekanism 中，当涡轮机因缓冲区已满且没有任何剩余能量容量可输出而无法再产生能量时会发生这种情况。")

--#endregion

return docs
