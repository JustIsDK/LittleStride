# LittleStride iOS 开发与运行

## 运行工程

用 Xcode 打开仓库根目录 `LittleStride.xcodeproj`，选择 `LittleStride` scheme。最低 iOS 17，手机端 SwiftUI，无第三方依赖。原型仍保留在 `prototype/`。

本地已安装 Xcode 27。签名设置暂使用本机已有的开发团队，换机器请在 Signing & Capabilities 中选择自己的团队和唯一 Bundle Identifier。没有模拟器运行时的机器需在 Xcode Settings → Components 下载对应 iOS Simulator，或选择可用真机。

编译（不签名）：

```sh
xcodebuild -project LittleStride.xcodeproj -scheme LittleStride \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/LittleStride-build CODE_SIGNING_ALLOWED=NO build
```

## 首次使用

1. 右上角进入孩子档案，填写昵称、年级和各科教材。
2. AI 服务设置中填 Base URL、协议、准确模型 ID 与自己的 Key，保存后做文本及结构化连接检测。
3. 拍照页选作业或教材，选择照片并点击分析；照片此时发送给配置服务。
4. 核对题目、答案、知识点，关闭“仍需核实”并选择收录。AI 结果不会自动当成孩子已掌握。
5. 今日页按优先级和时间上限选题，生成练习单并打印，或保存 PDF。
6. 孩子完成后，从拍照页选择练习单，拍照批改或手动填写，核对帮助程度后保存。
7. 查看进展、奖励与成果图片；数据设置可导出包含照片的 JSON 备份。

没有 AI 服务也能手动录题、安排、打印和记录，首次启动不灌入虚构学习成绩。

## 数据与服务

- 本地结构化 JSON 存入 Application Support/LittleStride，处理后的照片编码保存，串行后台编码与原子写入。
- 恢复前检查版本、唯一编号和引用关系，旧文件快照保留于 Application Support/LittleStride/Recovery。
- API Key 存于 `WhenUnlockedThisDeviceOnly` Keychain，备份无密钥，换机需重新输入。
- 支持 Responses、Chat Completions 和 Anthropic Messages 图文请求；请求非流式输出，也兼容服务商返回的 SSE。返回 JSON 需结构校验。
- 当前只实现配置的文本及 JSON 检测，图片能力在实际识别中验证。服务商不兼容时显示错误，不静默切换。
- 不输出远端错误正文或密钥到日志。网络请求复用 ephemeral session，显示上传阶段和等待时间。
- 本轮没有调用实际 AI 服务，准确性、服务端收费及用户服务兼容性仍需联调。

## iCloud 的实际范围

首版实现 iCloud Drive 独立快照文件的备份与恢复代码，不是完整双向同步。默认工程不带 iCloud entitlement，必须先完成账户及容器授权。

在 Xcode Signing & Capabilities 添加 iCloud，启用 iCloud Documents，创建并选择 `iCloud.com.justisdk.LittleStride` 容器；若更换命名，同时更新 Info.plist 中 NSUbiquitousContainers。`LittleStride/Resources/LittleStride.entitlements.example` 为配置参考，不能只复制文件而忽略开发者账户注册及签名权限。

备份写入 iCloud 本地容器后由系统上传；界面不把本地写入成功当成远端已上传。恢复时文件尚未下载会发起下载并提示稍后重试。自动多设备合并、冲突解决、删除传播仍在后续范围。

## 验证记录

已通过 generic iOS Simulator Debug 编译。核心规则检查包含：每日上限、延期、同日不算跨日掌握、回录去重、积分去重、跨日掌握与 JSON 序列化。检查使用独立临时目录。

```sh
swiftc LittleStride/Sources/Models.swift LittleStride/Sources/Store.swift \
  Tests/CoreRulesCheck.swift -o /tmp/LittleStride-CoreRulesCheck
/tmp/LittleStride-CoreRulesCheck
```

已安装iOS 27运行时，并在iPhone 17e模拟器启动更新后的原生页面，检查首页浅色和深色显示。相机、打印机、通知、分享、实际Keychain与iCloud尚未完成全面验收；不要把编译和启动通过当作这些系统功能已经实机验收。

## 本次交互与速度调整

- 相机通过 AVFoundation 后台启动，拍摄后直接回到 App 预览。
- 照片在后台缩至最长边 1800 像素，修正 Retina 渲染尺寸放大，缓存 JPEG 以供发送。相册通过 ImageIO 缩略解码。
- 点击分析立即锁住发送按钮，居中弹窗显示 loading、上传阶段与等待秒数；失败显示原因并保留照片。
- 成功弹窗停留 2 秒，关闭后自动滚到结果；重复分析需要明确选择。仍需核对后保存。
- 按钮统一按压缩放、变暗与轻触反馈，AI 设置操作按钮整行可点击，有明确底色和短按高亮，保存后按钮显示“已保存”。
- Apple Vision 在本地识别文字，用户核对后可选择只发送文字；手写、竖式和图形仍可用图片模式。三个拍照用途分别保留草稿。
- 未实测端到端耗时；服务商排队和模型推理时间由远端决定。账号授权仍待实现，详见 [AI 接入说明](AI接入说明.md)。

## 后续开发范围

- 真机/模拟器 UI 验收与长题打印分页细节。
- 用户实际服务商的 AI 协议、图像与 JSON 兼容性联调。
- 自动 iCloud 同步、冲突处理和备份保留策略。
- 题目编辑历史、批量相似题检索、教材目录结构化映射。
- 通知内动态计划摘要（目前采用不会过期的“打开查看计划”提醒）。
- 更细的进步分析、分享徽章的本次/历史区分与奖励更正账本。
- 备份导入合并预览（首版为明确确认后的替换恢复）。
