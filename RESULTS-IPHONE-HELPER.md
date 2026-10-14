# iPhone GATT helper 真机结果

2026-10-14，iPhone 16 / iOS 27.0.1（24A446），Apple Watch Series 12 / watchOS 27.0.1（24R365）。时间均为北京时间；原始日志使用 UTC。

> 后续重启 Watch 后，iPhone 已原生订阅并响应真实指针移动；见 [RESULTS-IPHONE-HID.md](RESULTS-IPHONE-HID.md)。以下保留此前只读诊断的历史结果。

## 结论

Mac 蓝牙关闭期间，iPhone helper 成功发现并连接 Watch，验证会话身份，读回 HID 服务属性，包括要求加密读取的 Report 和 Boot Mouse Input。Report 的 CCCD 读值为 0；同一观察区间 Watch 没有输入订阅回调。因此已排除该会话中扫描、连接和 HID 属性读取失败，尚未观察到 iOS 原生 HID 栈启用输入通知。

不能由此断言 iOS 永远不支持该方案，也不能确定是主机策略、配对/服务缓存还是 HID 配置兼容性。加密读取成功只说明此次读取权限路径通过，不能替代通知订阅与真实指针验证。helper 没有订阅输入、写入特征或转发鼠标事件。

| 阶段 | 本轮结果 |
| --- | --- |
| 自定义发现 UUID | 收到广播，同时包含 1812 |
| BLE 连接 | 成功 |
| 自有 Watch 身份 | 非模拟器、HID 模式及会话 UUID 验证通过 |
| HID Information / Protocol Mode | 4 字节预期值 / 01 |
| Report Map | 54 字节，与共享描述符完全一致 |
| Report Reference | 01 01：Report ID 1、Input |
| Report / Boot Mouse Input | 分别读到 4 / 3 字节，均无错误 |
| Report CCCD | 0，读取时未启用通知 |
| Watch 输入订阅 | 隔离窗口内无订阅回调 |
| iPhone 原生鼠标 | 本轮未验证成功 |

## 会话与反例

1. 首轮 17:13:11，手机会话 `A1E32A78-4EE4-4904-B042-225949E8DA80` 读取基本 HID 属性成功；此时 Mac 未隔离，不能用来判定通知归属。
2. 17:13:17 关闭 Mac 蓝牙，Watch 记录已知 Mac central 退订。
3. 中间一次隔离重试 `E441CCC6-7CFC-4E99-B260-97174CB44F6B` 在 17:13:59 读取身份时返回 `CBATTErrorDomain Code=242`。不能把该次算通过，原因尚未确定；其前后发生 Watch 生命周期切换与重启。
4. Watch 重启后的有效会话为 `37A08372-C038-46B2-A09C-62137B8027BA`。手机会话 `D9A69715-E14E-42F8-8329-12CCB0763295` 在 17:14:49 发现并连接，17:14:50 完成上述全部读取。
5. Watch 同秒记录身份特征及全部 HID 特征读取，central 为 `8B8EF160-E38F-0E27-6DB2-787009C67A9C`，可与手机本次请求关联。不能据此追认此前其他 central 的设备身份。
6. 手机于 17:16:25 记录观察结束；Watch 在读取时处于 active，之后有数次 active/inactive 切换，不能声称全程亮屏。隔离结束快照仍显示 Mac 蓝牙 off、零连接。
7. 采集完成后恢复 Mac 蓝牙，系统读回 on，外接键盘与触控板重新连接。17:17:40 Watch 日志确认已知 Mac central 再次订阅，不能归因于 iPhone。

## 证据与工程检查

- `artifacts/iphone-helper-phone-logs/`、`artifacts/iphone-helper-watch-logs/`：两端从真机容器导出的 JSONL。
- `artifacts/iphone-helper-encrypted-console.log`：成功读取、CCCD 0 和观察结束。
- `artifacts/iphone-helper-isolated-console.log`：中间 ATT 242 失败。
- `artifacts/iphone-helper-watch-isolated-console.log`：Watch 读取请求、central 和订阅事件。
- `artifacts/iphone-helper-radio-off.json`、`iphone-helper-radio-off-end.json`、`iphone-helper-radio-restored.json`：Mac 隔离及恢复状态。
- `artifacts/iphone-helper-evidence.json`：从原始日志提取并断言的本轮结果。
- `just check`：SwiftFormat / SwiftLint 通过；`just build`：Watch、Mac、iPhone 三个目标构建通过；另有真机签名构建与安装记录。实测后仅修正手机开关初始值以对应命令行加密读取选项，再次通过 lint、iPhone 签名构建并安装；蓝牙诊断逻辑未改变。

后续应针对 iOS 原生 HID 接管检查主机日志及 HOGP 配置兼容性。当前 helper 的通过标准是属性可达性，不是鼠标功能验收。
