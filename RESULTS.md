# 2026-10-14 真机记录

> 本文件保留第一轮实验结果。后续加入自定义发现 UUID 后，原生 HID 鼠标已跑通，详见 [更新记录](RESULTS-HID-DISCOVERY.md)。

## 结论

Apple Watch Series 12（设备报告 Watch8,5）、watchOS 27.0.1（24R365）上，运行时绕过 SDK 构造接口限制，普通 BLE GATT 已完成从 Mac 到手表的连接、读、写、通知闭环。不能再将 SDK 不开放接口等同于真机完全没有 peripheral 能力。

HID 服务注册和广播回调成功，但尚未验证为 Mac 原生鼠标。本轮没有新增系统 HID 设备、没有鼠标输入报告订阅、没有成功鼠标报告或可归因的光标移动。

## 环境

- Xcode 27.0 / watchOS SDK 27。
- Mac：macOS 27.2（26B5091g）。
- 开发签名安装，无额外硬件，无系统配置或配对记录修改。
- 以下时间使用 UTC；北京时间加 8 小时。

## 分阶段证据

| 模式 | 观察 | 结论 |
| --- | --- | --- |
| 普通 GATT，default-init | 08:24:00，Mac 随机挑战写入确认、读回和通知全部通过 | 真机闭环通过 |
| 普通 GATT，runtime-init | 08:25:22，poweredOn、didAdd、advertising 成功；Mac 后续扫描超时 | 仅本地发布回调通过 |
| 最小 HID | 08:27:46，0x1812 注册及广播成功；08:28:27 有 central 读取 HID Information、Report Map | HID 属性可被读取，但未识别原生鼠标 |
| 补齐 Device Information、Battery、Boot Mouse 的 HID | 08:32:40，三个服务依次注册，广播成功；后续 Mac 诊断扫描无连接 | 原生鼠标仍未通过 |

普通 GATT 完整日志：

- [Mac 验证日志](artifacts/mac-4ED42CDE-763F-4F12-B9A2-18EA9D25D2F6.jsonl)，会话 `4ED42CDE-763F-4F12-B9A2-18EA9D25D2F6`。
- Watch 会话 `6C59CADF-5B0F-4CD2-8877-F58638D2E671`，保存在 `artifacts/watch-gatt-logs/` 和最终导出的 `artifacts/watch-final-logs/`。
- `gatt.verified` 的 `watchRun` 与该 Watch 会话相同；身份中 `simulated=false`，系统版本为 27.0.1。

HID 证据：

- `artifacts/watch-hid-console.log`：初始 HID，会话 `CDABD0CB-9E65-46A5-915B-769DB99742F7`，记录两种 HID 属性读取；central 的具体主机身份未独立确认。
- `artifacts/watch-hid-host-console.log`：完整 HID，会话 `CB574703-1CAE-4F21-BB71-DEF6DCD6C165`；手动按右移按钮记录 `hid.move.notReady`。
- `artifacts/mac-hid-*.jsonl`：Mac HID 扫描诊断。
- `artifacts/hid-before.txt`、`artifacts/hid-final.txt`：系统 HID 枚举；应忽略行顺序变化后比较。
- 本轮蓝牙设置 UI 未发现可识别为探针的设备，未对附近不相关设备尝试配对。

## 解释边界与下一步

HID 失败的确切层级尚未确定。后续普通 GATT 的再次发现也曾超时，手表日志多次切换 active/inactive；因此不能将所有扫描失败归因于 HID 被系统禁止。广播回调也不能证明请求的 UUID 和名字实际按原样出现在空中。

下一次优先在 HID 模式增加独立的自定义发现 UUID，先确定主机能连上并完整读到 HID 属性和描述符，再检查配对/加密、系统 HID 接管。应分别保留扫描发现、GATT 属性发现、原生 HID 枚举、报告订阅、实际光标响应的证据。当前实现不是完整 HOGP 合规实现或可交付鼠标产品。

## 交付验证

- `just check`：8 个 Swift 文件，SwiftFormat 与 SwiftLint strict 全部通过。
- `just build`：Watch 和 Mac 均 `BUILD SUCCEEDED`，含 Watch 通用设备构建。
- Watch 开发签名构建、安装、启动均成功；上述结果来自真实手表，非模拟器。
- 最后修改只修正 Mac UI 日志选择和诊断器旧回调/超时隔离，已编译检查；未重新宣称这些修改经过完整设备验收。
- 当前没有单元测试套件。验收依据为双端真实协议交互日志，不以编译成功代替功能成功。

编译和风格检查日志位于 `artifacts/final-build.log`、`artifacts/final-check.log`。
