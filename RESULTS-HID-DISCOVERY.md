# 自定义发现 UUID 与原生 HID 真机验证

2026-10-14，北京时间。设备：Apple Watch Series 12 / Watch8,5，watchOS 27.0.1（24R365）；Mac：macOS 27.2（26B5091g）。

## 结论

**原生 HID 鼠标成功。** 加入自定义发现 UUID 后，Mac 通过 CoreBluetooth 发现并连接 Watch，macOS 原生 HID 栈自动订阅输入，系统新增 BLE 鼠标设备。Frank 确认每次点击手表“鼠标右移 20”均使 Mac 光标右移；退出 Mac 诊断程序后仍然右移。

Mac 诊断程序只负责发现、建立连接和读取属性，没有调用 `setNotifyValue`，没有合成系统鼠标事件。它不是输入转发器。没有增加硬件、越狱或修改蓝牙守护进程。

可以排除本组合上“系统无法接管 Watch HID”的假设。第一轮问题位于发现或连接建立阶段；不能仅凭这轮结果进一步认定旧扫描失败一定由 UUID 过滤、缓存、名称或前后台状态中的某一个因素造成。

## 改动

- HID 模式新增发现服务 `F753D410-8753-43CF-A613-19C364B377B0` 和身份特征 `F753D411-8753-43CF-A613-19C364B377B0`。
- 广播同时请求自定义发现 UUID 和标准 HID UUID 0x1812。
- Mac 按自定义 UUID 扫描，不再用名称筛选；读回非模拟器身份、Watch run 和 HID profile 后再检查 HID。
- Report Map 提取至 `Shared/HIDReport.swift`，Mac 对读回字节作完整匹配；同时读取 Report Reference、CCCD。
- 保留可选标准 UUID 扫描、自定义 UUID 单独广播和加密属性读取开关，供后续对照实验。默认成功路径不需要这些开关。

## 证据链

Watch run：`13195317-B388-411F-92EA-5098E70D35E5`。

Mac run：`75B0F251-5929-4995-94AD-DF91FE80A17F`。

| 北京时间 | 观察 | 证明范围 |
| --- | --- | --- |
| 16:41:28 | Watch 注册自定义发现、Device Information、Battery、HID 四个服务并启动广播 | 本地服务注册成功 |
| 16:41:38 | Mac 收到 connectable 广播；services 包含自定义 UUID 和 1812，localName=WBLEMouse，缓存 name=Apple Watch | 本轮实际扫描发现成功 |
| 16:41:39–40 | Mac 连接，读回真实 Watch 会话身份，枚举到 HID 1812 | 连接和服务可达 |
| 16:41:41–42 | Report Map 54 字节完全匹配；Report Reference 为 01 01；CCCD 读值为 1 | 输入结构可读，通知已启用 |
| 16:41:42 | Watch 收到 Report 2A4D 的 `notify.subscribed`；中性报告入队成功 | 存在真实订阅方 |
| 16:41:47 | Watch 发送一次 dx=20、buttons=0，accepted=true | 发送队列接受报告 |
| 16:42–44 | Frank 确认每次点击均右移；Mac 程序退出后再次确认仍右移 | 实际输入效果和无转发器运行成立 |

`hidutil list` 新增两条记录，VendorID=0xFFFF、ProductID=0x1、UsagePage=1、Usage=2，名称均为 Apple Watch，Transport 为 Bluetooth Low Energy：

- `IOHIDUserDevice`
- `AppleUserHIDEventService`，驱动 `AppleUserHIDEventDriver`

退出 Mac 诊断程序后两条记录仍存在，手表后续右移报告继续 accepted=true。没有把自写接收程序的订阅当作系统订阅；成功路径的诊断器 `readEncrypted=false`。

## 原始记录

- [Mac JSONL](artifacts/mac-hid-75B0F251-5929-4995-94AD-DF91FE80A17F.jsonl)
- [Watch JSONL](artifacts/discovery-watch-logs/watch-13195317-B388-411F-92EA-5098E70D35E5.jsonl)
- [Watch 实时控制台](artifacts/discovery-watch-console.log)
- [HID 枚举前](artifacts/discovery-hid-before.txt)、[枚举后](artifacts/discovery-hid-after.txt)、[退出 Mac 程序后](artifacts/discovery-hid-helper-exited.txt)
- [验收汇总](artifacts/discovery-evidence.json)：自动核对会话、报告内容、订阅、原生设备差异；人工光标观察单独标注来源。

## 检查与边界

真机开发签名构建、安装及运行成功；`just check` 9 个 Swift 文件零违规；`just build` 的 Watch 通用设备构建和 Mac 构建通过。没有新增单元测试，以真实设备交互验收本次协议变化。

验收后仅将 Mac 属性读取收窄至 HID 服务，避免顺带读取系统合并的其他 Watch 服务；该收窄经过最终构建和检查，未再次要求用户重复完整光标验收。Watch 验收实现未改变。

本轮证明这块 Watch 与这台 Mac 的前台运行路径。尚未验证全新未信任的主机、Windows/Android/iPhone、系统设置中独立配对、首次连接完全不启动 helper、熄屏后台保活，以及重启或系统升级后的可靠性。实验用厂商标识、固定电量和最小报告实现也尚未构成完整 HOGP 产品。

## 后续修复：手表从图标启动回到 GATT

用户截图显示，从手表图标重新打开 App 后标题变为“BLE GATT 探针”，移动按钮消失。原因是先前 HID profile 完全取决于 `--hid` 进程参数，正常图标启动不带该参数；这不能归因于手机配对失败。

修复后：HID/GATT 模式存入 UserDefaults；`--hid` / `--gatt` 显式指定并保存模式，无参数使用已保存模式。手表提供模式切换，停止后可以重新启动；清理旧服务、状态、订阅及过期回调。HID 页面新增四方向移动和订阅主机数，发送日志记录 central ID 和有符号 X/Y 位移。队列接受仍不代表 iPhone 光标已实际移动。

真机回归：使用 `--hid` 启动保存模式后，终止并以不带任何 profile 参数的方式重新启动；日志仍为 `probe.profile=hid`，四个服务注册及广播成功。证据：`artifacts/mode-fix-hid-console.log` 和 `artifacts/mode-fix-noargs-console.log`。开发签名构建与 `just check` 通过。本次尚未获得 iPhone 光标实际移动的确认。
