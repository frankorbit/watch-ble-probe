# iPhone HID 输入订阅隔离验证

2026-10-14，北京时间。使用现有 HID 探针，无协议或固件改动。

## 已确认的结果

- Mac 的 `system_profiler SPBluetoothDataType` 显示 Apple Watch 处于 connected，类型 Mouse，服务 HID BLE。`hidutil` 未列出设备不足以证明蓝牙连接已断开。
- `IOBluetoothDevice.closeConnection` 返回成功，但该接口事前就报告未连接，之后蓝牙诊断仍显示 BLE 连接，故没有把这个返回值作为隔离成功证据。
- 用户明确同意临时关闭 Mac 蓝牙，接受外接蓝牙键鼠暂时断开，并要求测试后恢复。
- 关闭后，设置开关为 off，系统诊断为 `controller_state=attrib_off`，连接设备列表为空。
- 17:04:49，Watch 收到 `38885F2F-960E-DA68-EEBB-786C8C1AE2AE` 对输入 Report 2A4D 的退订。这个事件确认此前唯一的订阅来自 Mac。
- 用户在 iPhone 单独测试时报告手表显示“0 台”。截至当前导出日志的 17:05:09，退订之后没有新的 HID 属性读取或输入订阅。

本轮尚未观察到 iPhone 接管探针输入，因此不能把手机界面的“Apple Watch 已连接”等同于这个 App 的 HID 服务已连接，更不能归因为指针样式或隐藏设置。这里只证明本轮未观察到订阅，不证明 iPhone 永久不支持此实现。

## 原始记录

- `artifacts/iphone-isolation-bluetooth-before.json`：Mac 原始 BLE 连接状态。
- `artifacts/iphone-isolation-disconnect.log`、`artifacts/iphone-isolation-bluetooth-after.json`：单设备断开未生效。
- `artifacts/iphone-isolation-radio-off.json`：Mac 蓝牙关闭，零连接。
- `artifacts/iphone-isolation-watch.jsonl`：Watch 退订及后续观察。
- `artifacts/iphone-isolation-evidence.json`：会话、退订 central、观察区间和用户报告的订阅数。

下一层诊断需要确认 iPhone 是否连到了本探针的自定义发现服务；如系统设置路径仍无输入订阅，可在 iPhone 上运行只做发现、身份读取和连接的 helper，分开验证 GATT 可达与系统 HID 接管。

## 第二轮及恢复

用户提供 17:05:56 的 iPhone 截图，辅助触控蓝牙设备页确实显示 Apple Watch 已连接。17:06:59 Watch 再次出现原 Mac central 的订阅；检查发现 Mac 蓝牙已重新开启，不能把这一段作为独立 iPhone 观察。

17:07:04–05，另一个 central `B197CBE4-13DD-7BEB-677A-0552E44B9974` 读取了厂商、PnP、HID Information 和 Report Map，未订阅输入。它可能与手机操作有关，但未通过身份握手确认，不能直接标记为 iPhone。

再次关闭 Mac 蓝牙后，17:07:59 原 Mac central 退订。用户第二次文字报告 0 台；截至导出日志的 17:08:40 没有新的输入订阅。第二轮开始和结束的系统诊断均确认 Mac 蓝牙 off。证据：`artifacts/iphone-isolation-radio-off-2.json`、`artifacts/iphone-isolation-radio-off-2-end.json`、`artifacts/iphone-isolation-watch-final.jsonl`、`artifacts/iphone-isolation-evidence-final.json`。

测试结束后已通过 Mac 设置将蓝牙恢复为 on。下一步应使用 iPhone 端 GATT helper 读取自定义身份和 HID 属性，确认手机请求到底到达哪一层，避免继续依据设备名称或“已连接”文字推断 HID 已接管。

后续已使用 iPhone GATT helper 完成隔离读取验证，见 [RESULTS-IPHONE-HELPER.md](RESULTS-IPHONE-HELPER.md)。
