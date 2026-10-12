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

- 本地结构化 JSON 存入 Application Support/LittleStride，原图编码保存，文件原子写入。
- 恢复前检查版本、唯一编号和引用关系，旧文件快照保留于 Application Support/LittleStride/Recovery。
- API Key 存于 `WhenUnlockedThisDeviceOnly` Keychain，备份无密钥，换机需重新输入。
- Responses 与 Chat Completions 分别构造图文请求；本轮使用非流式响应，返回 JSON 需结构校验。
- 当前只实现配置的文本及 JSON 检测，图片能力在实际识别中验证。服务商不兼容时显示错误，不静默切换。
- 不输出远端错误正文或密钥到日志。网络请求使用短生命周期 ephemeral session。
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

当前机器没有可用模拟器运行时，因此未验证启动界面、相机、打印机、通知、分享、实际 Keychain 和 iCloud 上传恢复；不要把编译通过当作这些系统功能已经实机验收。

## 后续开发范围

- 真机/模拟器 UI 验收与长题打印分页细节。
- 用户实际服务商的 AI 协议、图像与 JSON 兼容性联调。
- 自动 iCloud 同步、冲突处理和备份保留策略。
- 题目编辑历史、批量相似题检索、教材目录结构化映射。
- 通知内动态计划摘要（目前采用不会过期的“打开查看计划”提醒）。
- 更细的进步分析、分享徽章的本次/历史区分与奖励更正账本。
- 备份导入合并预览（首版为明确确认后的替换恢复）。
