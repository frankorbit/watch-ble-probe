# iPhone 原生 BLE HID 鼠标真机验证

2026-10-14，北京时间；原始日志使用 UTC。设备为 iPhone 16 / iOS 27.0.1 和 Apple Watch Series 12 / watchOS 27.0.1。

## 已确认结果

Mac 蓝牙关闭期间，Watch 收到已在上轮与 iPhone 请求关联的 central 的 HID Input 订阅，发送移动报告成功，用户确认 iPhone 圆形指针随手表左右按钮移动。iPhone 原生鼠标路径已验证成功，无额外硬件，无鼠标事件转发。

## 时间线与因果边界

- 17:24:21：重启同一已安装 Watch HID 探针，未修改其 HID 服务配置。新会话 `A1D43B2E-7D93-44FD-B381-CF760E94987E`。
- 17:24:21–22：central `8B8EF160-E38F-0E27-6DB2-787009C67A9C` 读取 Manufacturer、PnP ID、HID Information 和 Report Map。
- 17:24:22：该 central 订阅 `2A4D`，Watch 记录 `notify.subscribed` 和中立报告入队。
- 17:24:31：Watch 两次发送左移报告，入队成功，目标为同一 central。
- 17:24:32：独立 AccessorySetupKit 探针才首次启动。会话激活成功，自动展示选择器返回 `ASErrorDomain 550 / Application is not in foreground`。
- 用户文字确认：“指针随点击移动”。此前和随后系统诊断均记录 Mac 蓝牙 off、零连接。

**不能把成功归因于 AccessorySetupKit**：订阅早于它首次启动 10 秒。也不能证明单纯重启必然解决问题；此前已有连接、GATT 读取和设置页交互，尚未区分缓存刷新、系统时序和用户操作的影响。这里证明的是当前设备组合可行，不是首次配对流程稳定。

## 退出 helper 后复测

通过 devicectl 终止手机上的 GATT Helper 和 HID Setup，随后进程列表确认两者均不在运行；该时刻 Mac 蓝牙快照仍为 off。用户再次文字确认“仍然移动”。Watch 在 17:26:54 的两次移动报告只发给 iPhone central，且均成功入队。

17:27:24 已知 Mac central 才重新订阅，之后移动报告同时发往 iPhone 和 Mac。最终检查发现 Mac 蓝牙已处于 on，因此没有再切换开关。不要把后续两台订阅解释成两台 iPhone；当前探针会向所有订阅主机发送，尚无目标选择 UI。该描述属于本轮历史版本；后续已按用户要求改为默认单手机目标，见 [RESULTS-PHONE-TARGET.md](RESULTS-PHONE-TARGET.md)。

## 诊断实现与边界

新增 `PhoneHIDSetup` 独立目标，使用系统公开的 `.bluetoothHID` / `.bluetoothPairingLE` 选项、自定义发现 UUID 和广播名称。独立目标保留原只读 helper 作为对照。前台竞态已通过取消自动展示入口修正，选择器改为用户手动点击；完整配件授权流程未验收，也不需要为本次鼠标成功补做授权。

尝试通过 `log collect --device-udid` 获取手机蓝牙/HID 系统日志失败，工具要求 root。没有获得该日志，不能声称已确认 iOS 内部接管原因。

## 证据

- `artifacts/iphone-setup-watch-console.log`、`artifacts/iphone-native-watch-logs/`：Watch 服务注册、订阅与发送。
- `artifacts/iphone-setup-console.log`：系统设置探针启动时间和选择器失败。
- `artifacts/iphone-setup-radio-before.json`、`iphone-native-radio-off.json`、`iphone-native-radio-off-after-stop.json`：Mac 隔离快照。
- `artifacts/iphone-native-processes-after.json`：两个手机诊断进程退出后的进程列表。
- `artifacts/iphone-native-evidence.json`、`iphone-native-watch-final/`：汇总断言、退出 helper 后发送、Mac 随后重连。
- `artifacts/iphone-native-radio-off-final.json`：文件名沿用 off-final，但内容实际为 on；以内容为准。`iphone-native-radio-restored.json` 确认最终蓝牙状态。
- `artifacts/iphone-setup-final-check.log`、`iphone-setup-final-build.log`：格式检查及新增目标签名构建。

尚未验证后台保活、熄屏连续输入、跨重启可靠重连及首次配对复现。当前按钮仅发送相对位移，尚未实现点击与拖拽交互。
