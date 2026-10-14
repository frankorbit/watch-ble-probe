# 默认 iPhone 单目标

2026-10-14。Mac 仅保留诊断用途；Watch 输入默认发送给本轮已验证的 iPhone。

## 实现

- 用开发启动参数 `--target-central` 配置已验证的 iPhone central UUID，保存为 `hidPhoneCentralID`。设备 ID 不写入源码。
- 无参数重启读取已保存目标。新安装默认 HID；未绑定时不发送。
- 移动报告与订阅时的中立报告均使用显式 `[targetCentral]`，不向所有订阅者广播。
- 非目标主机的 Protocol Mode / Control Point 写入被拒绝，避免影响手机的协议模式或暂停状态。
- 目标离线时不回退到其他订阅主机。Watch 页面只显示绑定 iPhone 的连接状态。

这不是自动获取 Watch 系统配对手机身份的实现；当前绑定来源于前两轮真机校验。标识变化或更换手机后需重新验证并绑定。其他主机仍可能建立蓝牙连接和读取服务，但不能接收探针输入报告。

## 验证

`just check` 通过，Watch 签名构建与真机安装通过。配置目标后的会话 `FFEDC687-A55F-482F-B1CA-F472507852DB` 中，iPhone 和已知 Mac central 均订阅 `2A4D`；仅向 iPhone 发送中立报告，Mac 记录 `hid.subscription.ignoredHost`。

原始文件：`artifacts/phone-target-bind-console.log`、`phone-target-persist-console.log`、`phone-target-build.log`、`phone-target-check.log`、`phone-target-install.json`。无参数重启会话 `49861B1F-0E1B-4DC5-82BC-FB9F11A1776A` 自动读回同一 iPhone 目标，iPhone 和 Mac 均订阅，Mac 被忽略。该会话采集到 4 次移动报告，目标均只有 iPhone。用户确认“只有 iPhone 移动”，Mac 光标不动。汇总断言见 `artifacts/phone-target-evidence.json`，完整真机日志见 `artifacts/phone-target-watch-logs/`。

未单独执行手机离线/标识变化的真机回归；这些情况下不发送的行为目前由发送前的目标匹配 guard 保证。未改变 Mac 蓝牙开关或系统配对。
