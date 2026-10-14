# Watch 触控板真机验证

2026-10-14，Apple Watch Series 12 / watchOS 27.0.1，iPhone 16 / iOS 27.0.1。

## 实现

Watch 主界面改成固定蓝色触控区域，无外层滚动视图竞争手势。滑动输出相对 X/Y；轻点输出左键 1、0 两帧。触摸超过 5 点后判为滑动，0.35 秒以内且未滑动才视为轻点。设置与日志通过齿轮进入。

输入仍仅发送给已绑定 iPhone。队列保留蓝牙背压下未发送的报告，由 peripheral ready 回调继续发送；点击按下/释放原子入队，禁止只排入按下。目标离线不回退到 Mac、不积累未来点击。App inactive 时清除剩余输入并尝试释放；断开连接、停止服务或系统挂起不保证释放送达。

## 工程检查

- `just check` 通过：13 个 Swift 文件，SwiftFormat / SwiftLint 零问题。
- `just test` 通过：轻点/滑动区分、长按不点击、滑动返回起点不点击、大位移拆包、点击顺序、背压时队首保留、满队列拒绝整次点击、释放与清空。
- Watch 签名构建、真机安装和无参数启动通过，自动沿用上轮 iPhone 绑定。
- 真机启动会话 `0E3C302D-CA63-4031-9593-0820AD7F9FCF`，iPhone 订阅 Input Report，中立报告仅发送到目标手机。

证据：`artifacts/trackpad-check.log`、`trackpad-tests.log`、`trackpad-build.log`、`trackpad-install.json`、`trackpad-watch-console.log`。

截至日志快照 2026-10-14T09:40:09Z：已记录 1601 条非零位移报告和 8 次左键点击，所有点击按下后紧接零位移释放报告，所有输入目标均只有绑定 iPhone。出现 10 次蓝牙背压，后续均恢复报告发送。原始真机日志在 `artifacts/trackpad-watch-logs/`，断言汇总在 `artifacts/trackpad-evidence.json`。

用户本轮真机确认：“滑动和轻点都正常”。因此单手机相对移动与左键点击已同时完成协议日志和真实交互验收。未验证长按拖拽、滚轮、后台持续运行或跨重启恢复。
