# Watch BLE 真机探针

验证 watchOS 上运行时调用 `CBPeripheralManager` 是否能发布普通 GATT 服务，再独立尝试 HID over GATT 鼠标。普通 GATT、Mac 原生 HID 鼠标和 iPhone 原生 HID 鼠标均已真机跑通。iPhone 最新证据见 [iPhone HID 验证记录](RESULTS-IPHONE-HID.md)。最新证据见 [HID 发现验证记录](RESULTS-HID-DISCOVERY.md)，第一轮记录见 [RESULTS.md](RESULTS.md)。

## 工程结构与边界

- `Watch/ProbeBridge.m`：Objective-C runtime 调用 SDK 限制的构造方法，检查类和 selector，并把 Objective-C 异常转换成 Swift Error。
- `Watch/PeripheralProbe.swift`：普通服务发布、读写、通知以及分阶段日志。
- `Watch/HIDProbe.swift`：HID 服务与单手机报告队列，处理蓝牙背压和点击释放。
- `Watch/PointerInput.swift`：触控手势增量、点击判定和可独立验证的输入缓冲。
- `Mac/CentralVerifier.swift`：独立 BLE central，验证随机挑战读回及通知，检查 Watch 会话与非模拟器身份。
- `Host/HIDHostProbe.swift`：Mac/iPhone 共用的只读 HID 服务诊断；系统 HID 接管另行检查。
- `iPhone/PhoneApp.swift`：iPhone 真机 helper，显示阶段结果与日志，支持额外加密读取。
- `iPhoneSetup/SetupApp.swift`：独立 AccessorySetupKit 系统设置探针，不参与鼠标事件接收或转发。
- `Shared/ProbeLog.swift`：JSONL 同时写控制台和 Documents，记录时间与会话 ID。

仅绕过编译期 API 可用性限制，仍需系统蓝牙权限。没有越狱、额外硬件、私有 entitlement、蓝牙守护进程修改或配对记录重置。Mac 验证程序不合成系统鼠标事件。

## 构建

需要 Xcode、XcodeGen、just、SwiftFormat、SwiftLint。部署目标为 watchOS 11 / macOS 14 / iOS 17，但目前只实测下述设备，最低部署目标不代表其他系统已验证。

```sh
just generate
just fix
just check
just test
just build
```

`just build` 编译 Watch、Mac、iPhone GATT helper 和独立 HID Setup 四个未签名产物，不能直接安装未签名 Watch App。真机需要 Developer Mode、配对可用的开发设备、开发团队签名。用实际团队和设备替换以下变量：

```sh
export WATCH_UDID='your-watch-udid'
export WATCH_TEAM='your-team-id'
xcodebuild -project WatchBLEProbe.xcodeproj -scheme WatchBLEProbe \
  -destination "id=$WATCH_UDID" -derivedDataPath build-device \
  DEVELOPMENT_TEAM="$WATCH_TEAM" -allowProvisioningUpdates build
xcrun devicectl device install app --device "$WATCH_UDID" \
  build-device/Build/Products/Debug-watchos/WatchBLEProbe.app
xcodebuild -project WatchBLEProbe.xcodeproj -scheme MacBLEVerifier \
  -destination 'platform=macOS' -derivedDataPath build build
```

## 普通 GATT 验证

先启动 Mac 扫描，再启动手表 App，并让手表保持前台亮屏。首次蓝牙权限提示需在相应设备上允许。

```sh
open -n build/Build/Products/Debug/MacBLEVerifier.app --args --auto-start
xcrun devicectl device process launch --device "$WATCH_UDID" \
  --terminate-existing --console dev.frank.watchbleprobe.watch
```

如上次使用过 HID，普通 GATT 启动命令应追加 `--gatt`。默认管理器路径是 `[[CBPeripheralManager alloc] init]` 后设置 delegate。另一条路径在启动参数追加 `--runtime-init`，通过 `objc_msgSend` 调用 `initWithDelegate:queue:options:`。每条路径独立启动、独立记录，不混用结果。

普通服务 UUID 为 `F753D401-8753-43CF-A613-19C364B377B0`，identity、echo、notify 特征分别以 `D402`、`D403`、`D404` 结尾。Mac 使用本次随机 16 字节挑战，依次验证身份、通知订阅、写入响应、原文读回、`notify:` 加挑战的通知。

唯一完整通过标志是 Mac 日志 `gatt.verified`，其中 `watchRun` 必须对应手表日志。`didAdd` 和 `isAdvertising=true` 只是中间证据。身份检查用于实验溯源，不是密码学设备认证。

Mac 扫描每次最多 60 秒；若授权期间或前台操作时已超时，重新点击 Mac“开始验证”。Watch“停止”后可再次点击“启动探针”，或使用页面上的模式切换按钮。HID/GATT 模式会持久化；从图标重新打开沿用上次模式。命令行 `--hid` / `--gatt` 显式覆盖并保存模式；全新安装默认为 HID，但未绑定手机时不发送输入。

## HID 尝试

```sh
hidutil list > artifacts/hid-before.txt
xcrun devicectl device process launch --device "$WATCH_UDID" \
  --terminate-existing --console dev.frank.watchbleprobe.watch --hid
```

HID 模式发布 0x1812、0x180A、0x180F，以及自定义发现服务 `F753D410-8753-43CF-A613-19C364B377B0`；其中 `D411` 特征提供真实 Watch 会话身份。默认同时广播自定义 UUID 和短 UUID 0x1812，名称为 `WBLEMouse`。包含 HID Information、Report Map、Report、Report Reference、Control Point、Protocol Mode、Boot Mouse Input；54 字节报告描述符提供三个按钮、相对 X/Y 和滚轮，Report ID 为 1。设备信息使用实验标识，电量 100 为固定测试值。

用 `hidutil list` 对比系统输入设备。系统订阅后，手表主界面是固定触控板：滑动按相对增量移动，轻点发送左键按下和释放；滑动结束不点击。可选 `--hid-auto-move` 在目标手机首次订阅 5 秒后尝试一次向右 20 单位移动；默认不自动移动。Watch 显示已绑定 iPhone 的连接状态和发送队列结果；其他主机的订阅仅保留在诊断日志，不作为操作目标。

额外的诊断程序：

```sh
open -n build/Build/Products/Debug/MacBLEVerifier.app --args --hid-connect
```

先启动上述 Mac 程序，再启动 Watch HID 模式并保持亮屏。Mac 通过自定义 UUID 扫描连接，读回 Watch 会话身份后枚举服务，读取 HID Report Map、Report Reference、CCCD 等属性，不主动订阅输入。历史版本已实测连接建立后系统自动接管为 BLE 鼠标；退出 Mac 程序仍可移动光标。当前版本默认只向绑定 iPhone 发送输入，Mac 验证端仅保留作诊断。

Mac 可选 `--hid-standard-scan` 改用 0x1812 扫描（仍要求发现结果包含自定义 UUID，避免连接不相关键鼠），`--hid-read-encrypted` 增加加密输入特征读取。Watch 可选 `--hid-custom-only` 仅广播自定义 UUID，仍注册完整 HID 服务。这些可选对照路径尚未完成本轮真机验收。诊断每轮等待约 90 秒，App Nap 可能使结束回调延迟。

原生鼠标通过条件：主机原生 HID 栈识别设备、订阅输入，随后真实光标响应 Watch 报告。单纯读取 Report Map、发送队列接受或自写接收端转换事件均不算通过。

## iPhone GATT helper

最小 iPhone helper 已完成真机验证，结果见 [iPhone GATT 验证记录](RESULTS-IPHONE-HELPER.md)。它只发现、连接并读取属性，不调用输入通知订阅，不写入鼠标事件，也不转发到系统。GATT 验证通过不代表 iPhone 已接管为鼠标。

```sh
export PHONE_UDID='your-iphone-udid'
xcodebuild -project WatchBLEProbe.xcodeproj -scheme PhoneGATTHelper \
  -destination 'generic/platform=iOS' -derivedDataPath build-device \
  DEVELOPMENT_TEAM="$WATCH_TEAM" -allowProvisioningUpdates build
xcrun devicectl device install app --device "$PHONE_UDID" \
  build-device/Build/Products/Debug-iphoneos/PhoneGATTHelper.app
xcrun devicectl device process launch --device "$PHONE_UDID" \
  --terminate-existing --console dev.frank.watchbleprobe.iphone --auto-start --hid-read-encrypted
```

首次在手机上允许蓝牙权限；手表保持 HID 模式前台，手机 helper 保持前台。也可从图标打开，选择是否额外读取加密输入特征后点击“开始验证”。每轮观察约 90 秒后断开 helper 的连接，不停止 Watch 服务。

步骤包括自定义 UUID 发现（或检索已连接设备）、Watch 身份与会话校验、HID 服务枚举、HID Information / Report Map / Protocol Mode / Report Reference 读取与比对；额外读取开启时，还读取 Report 和 Boot Mouse Input。`hid.gatt.verified` 的加密读取通过标志检查 Report 成功，Boot 读取结果独立记录。CCCD 读取值和 Watch 的订阅回调独立用于判断通知状态，不计入 GATT 属性通过条件。

隔离测试需避免 Mac 自动订阅干扰。临时关闭 Mac 蓝牙会断开外接蓝牙输入设备，应准备内置键盘/触控板，并在测试后恢复。手机日志导出：

```sh
xcrun devicectl device copy from --device "$PHONE_UDID" \
  --domain-type appDataContainer --domain-identifier dev.frank.watchbleprobe.iphone \
  --source Documents/WatchBLEProbe --destination artifacts/iphone-logs
```

## 手表触控板

蓝色区域支持单指相对移动和轻点左键。默认灵敏度为每屏幕点 1.8 个 HID 相对单位，实际速度还受 iPhone 指针设置影响。触摸位移达到 5 点后判定为滑动；未达到阈值且持续不超过 0.35 秒才判定轻点。发生过滑动后，即使回到起点也不触发点击。尚未实现长按拖拽、滚轮和双指手势。

主触控区域没有外层 ScrollView，设置和诊断日志移到齿轮按钮的弹出页。模式切换、启动/停止仍在该页。App 进入 inactive 时清除待发位移并尝试释放按钮。

发送队列仅面向绑定 iPhone。相邻位移可合并，每轴按 Report Map 的 -127…127 范围拆包；待发累计位移每轴限制在 2048，操作队列限制为 64。点击的按下/释放成对排队，蓝牙 `updateValue` 返回 false 时保留队首，由 ready 回调重试；不会把只排入按下当成成功点击。`hid.input.enqueued` 记录实际被 CoreBluetooth 接受的报告，不代表远端已执行。

`just test` 在 Mac 上验证纯手势/队列逻辑，不能替代 BLE 真机效果。真机结果见 [触控板验证记录](RESULTS-TRACKPAD.md)。

## 默认只控制当前 iPhone

用户已确定 Mac 仅作验证，不是产品操作目标。当前 Watch 通过已验证的 iPhone `CBCentral.identifier` 绑定单一手机，保存到本地设置；冷启动沿用绑定。移动报告、中立报告均显式指定该手机 central，其他主机的 Protocol Mode / Control Point 写入不影响手机状态。手机离线、未绑定或标识变化时停止发送，不回退到 Mac 或第一个订阅者。

这是当前真机的明确绑定，不等同于自动读取 Watch 系统配对关系。换手机、重置配对或系统导致 central 标识变化后，需要重新验证并绑定；不在源码中硬编码设备 ID，也不按设备名称猜测身份。绑定命令仅供开发调试，当前手机已经配置：

```sh
export PHONE_CENTRAL_UUID='verified-central-uuid-from-watch-log'
xcrun devicectl device process launch --device "$WATCH_UDID" \
  --terminate-existing --console dev.frank.watchbleprobe.watch \
  --hid --target-central "$PHONE_CENTRAL_UUID"
```

后续直接从 Watch 图标打开即可。Mac 仍可能在蓝牙层订阅 HID，但不会收到本探针的输入通知；尚未主动移除其系统配对。验证结果见 [单手机目标记录](RESULTS-PHONE-TARGET.md)。

## 可选系统配件设置探针

`PhoneHIDSetup` 是独立 App（iOS 18.4+），保留原 GATT helper 作为对照。它按照 [Apple 文档](https://developer.apple.com/documentation/accessorysetupkit/asaccessorysession) 设置 `.bluetoothHID` 和 `.bluetoothPairingLE`，使用自定义发现 UUID 加广播名称 `WBLEMouse` 匹配，然后由用户点击“配置 Watch 鼠标”打开系统选择器。它不创建 CBCentralManager、不订阅输入、不转发鼠标事件，也不删除已有配对。

本轮已完成构建、安装和会话激活；初版启动即弹选择器遇到前台竞态 `ASErrorDomain 550`，已改为只允许手动点击。**系统配件授权完整流程尚未验收，且不是本轮 iPhone 鼠标成功的必要步骤：iPhone 输入订阅发生在这个 App 首次启动之前。**

```sh
xcodebuild -project WatchBLEProbe.xcodeproj -scheme PhoneHIDSetup \
  -destination 'generic/platform=iOS' -derivedDataPath build-device \
  DEVELOPMENT_TEAM="$WATCH_TEAM" -allowProvisioningUpdates build
xcrun devicectl device install app --device "$PHONE_UDID" \
  build-device/Build/Products/Debug-iphoneos/PhoneHIDSetup.app
```

## 日志与限制

Mac 日志位于 `~/Documents/WatchBLEProbe/`；手表日志位于 App 容器同名 Documents 子目录：

```sh
xcrun devicectl device copy from --device "$WATCH_UDID" \
  --domain-type appDataContainer --domain-identifier dev.frank.watchbleprobe.watch \
  --source Documents/WatchBLEProbe --destination artifacts/watch-logs
```

日志可能含设备标识和测试现场的蓝牙名称，`artifacts/` 已列入忽略规则。探针用于前台短时实验，未实现后台保活、蓝牙重置后的恢复、多客户端 HID 协调。输入队列支持同一连接中的蓝牙背压重试，断线后会丢弃旧输入；断线、停止服务或系统挂起期间无法保证最后的释放报告送达。运行时可用不代表公开支持或系统升级后稳定。
