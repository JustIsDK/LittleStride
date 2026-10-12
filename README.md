# LittleStride · 小步学

面向家长的校内错题与短时复习管理 App。已有原生 iOS 第一版工程，交互原型作为产品参考保留。

## 项目内容

- [手机交互原型](prototype/index.html)：用浏览器直接打开，无需安装依赖。
- [功能逻辑与原型说明](prototype/功能逻辑与原型说明.md)：功能范围、状态规则、同步与迁移设计。
- [错题筛选规则](docs/错题筛选规则.md)：选题与复习原则。
- [Excel 模板及 Agent 填写说明](docs/错题管理模板/)：此前的结构化管理模板。

## 原生 iOS App

打开 [LittleStride.xcodeproj](LittleStride.xcodeproj)，选择 LittleStride scheme。最低 iOS 17，无第三方依赖。

已实现本地数据保存、孩子档案、能力观察、个人 AI 服务配置、图文分析及确认、题库、计划与延期、PDF 打印、结果回录、奖励、成果分享、通知和结构化备份。iCloud 首版提供需要容器配置的手动快照恢复代码，自动多设备同步尚未实现。

[开发、运行及验证说明](docs/iOS开发与运行.md)包含启动方法、AI 配置、iCloud 配置及未验收项。已编译通过并检查核心规则；当前机器缺少模拟器运行时，尚未实机验收或调用用户的 AI 服务。

## 版本管理

使用 Git，主分支为 `main`。远端仓库：https://github.com/JustIsDK/LittleStride.git。不要提交孩子的真实照片、学习数据、私密信息、账号密钥或构建产物。
