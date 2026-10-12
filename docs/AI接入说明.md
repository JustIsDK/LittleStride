# AI 接入说明

## API Key 接入

孩子档案 → AI 服务设置 → API Key。选择服务商后点击“填入该服务商的推荐参数”，再填写准确模型 ID 与该服务的 Key。选择服务商本身不会覆盖当前参数。

| 服务 | Base URL | 协议 | 认证 |
| --- | --- | --- | --- |
| OpenAI / GPT | `https://api.openai.com/v1` | Responses | Authorization + Bearer |
| Claude 官方 | `https://api.anthropic.com/v1` | Anthropic Messages | x-api-key，不加 Bearer |
| DeepSeek | `https://api.deepseek.com/v1` | Chat Completions | Authorization + Bearer |
| 千问：中国内地 | `https://dashscope.aliyuncs.com/compatible-mode/v1` | Chat Completions | Authorization + Bearer |
| 智谱 / GLM | `https://open.bigmodel.cn/api/paas/v4` | Chat Completions | Authorization + Bearer |
| 自定义 / 中转 | 按服务商文档保留完整基础前缀 | 按服务商文档 | 按服务商文档 |

模型 ID 留给用户从当前服务商模型列表复制，照片分析必须支持图片。DeepSeek 等服务的文本检测通过，不代表可以分析照片。千问的地址、模型和密钥必须对应同一地域。

获取参数的入口：

- [OpenAI API Keys](https://platform.openai.com/api-keys)：创建密钥，检查项目额度、模型权限。
- [Claude API Keys](https://platform.claude.com/settings/keys)：创建密钥，复制 API 文档的模型 ID。
- [DeepSeek API Keys](https://platform.deepseek.com/api_keys)：创建密钥，核实图片能力。
- [阿里云百炼](https://bailian.console.aliyun.com/)：开通模型服务、创建密钥、复制视觉模型 ID。
- [智谱开放平台](https://open.bigmodel.cn/)：创建密钥并查看视觉模型文档。

Base URL 不附加 `/responses`、`/chat/completions` 或 `/messages`，App 按协议追加。Key 只填密钥本身，Bearer 由 App 添加。保存后可检测文本和 JSON，检测会真实调用服务并可能计费；图片能力在照片分析时验证。

Key 按服务基础地址分别保存在本机 Keychain，不进入备份。更换地址不会复用其他地址的 Key。旧版本单个 Key 在首次打开设置时迁移到当时的地址。

## Codex 配置如何对应

| Codex 字段 | App 字段 |
| --- | --- |
| 当前有效的 `model` | 模型 ID |
| 当前 provider 的 `base_url` | Base URL |
| `wire_api = "responses"` | Responses 协议 |
| `env_key = "PP_API_KEY"` | 填环境变量 PP_API_KEY 的实际密钥值 |
| `model_reasoning_effort = "medium"` | 高级设置 → 思考强度 → 中（支持此参数的 Responses 模型） |
| provider 的 name / 标识 | 只用于区分服务，不是密钥或模型 ID |

用户截图的自定义服务可填：

- 服务商：自定义 / 中转。
- 地址：`https://api.hai-lab.cn/v1`。
- 模型：如果当前有效配置选它，填 `gpt-6.1-sol`；仍需确认该服务允许调用和图片输入。
- 协议：完整配置若 `wire_api = "responses"`，选择 Responses。截图未显示该字段，不能只凭模型名确定协议。
- 认证：服务商若要求常见 Bearer 认证，填写 Authorization 并开启 Bearer；Key 填 PP_API_KEY 的实际值。
- 思考强度：中，或先用服务默认。

截图同时包含多个 model/provider 配置，应以客户端当前生效的一组为准。上下文窗口、压缩阈值等 Codex 会话参数不对应照片分析设置。

## ChatGPT / 服务商账号授权

**当前 App 账号授权尚未接入。** 界面提供状态说明和控制台入口，登录控制台只是获取 API Key，不能视为 App 已获得模型调用授权。

截图的 `auth_mode = "chatgpt"`、`OPENAI_API_KEY = null` 及 tokens 属于 Codex 的账号登录凭据。`access_token`、`refresh_token`、`id_token` 和 account_id 都不能直接当作自定义服务的 API Key。App 不导入 auth.json，也不把其中令牌发送给中转服务。

OpenAI 已提供第三方开源客户端的 [ChatGPT 账号授权官方流程](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)。需要客户端注册、PKCE、回调、身份与权限校验、令牌安全存储及刷新；文档要求 HTTP loopback 回调，iOS 适用性仍需核实和实现。不能直接沿用 Codex 客户端身份或复制登录令牌完成接入。其他服务的账号授权同样需独立核实。

## 分析反馈与速度

相机后台启动，拍摄后直接进入预览；相册缩略解码，JPEG 最长边 1800 像素并缓存，避免在发送时再次处理。本地 JSON 编码在串行后台队列执行，网络连接复用。

分析时显示居中 loading 弹窗、上传阶段与等待秒数，可取消。成功显示结果概要，停留 2 秒后关闭，自动滚到结果；失败保留照片并显示原因。成功后锁住同一照片的重复发送，重新分析需明确点击。AI 结果仍要核对并保存。

尚未实际测量相机启动或端到端分析耗时。网络上传、服务商排队及模型推理可能仍需等待。取消已发送请求不保证服务商停止计费。

## 本地 OCR 与独立草稿

选择照片后，Apple Vision 在后台进行中文和英文文字识别，无须上传照片或调用云端 OCR。图片最长边仍保留 1800 像素，JPEG 超过约 900 KB 时逐级调整质量（最低约 0.45；不保证所有图片均低于 900 KB）。

可打开“只发送本地识别文字”，编辑识别内容并勾选已核对后再分析。此模式不携带图片。作业、教材和练习回录均提供该方式；OCR 失败或内容不足时仍可用图片模式。手写答案、竖式、图形与批改标记可能无法可靠识别，不自动把 OCR 文字视作完整作答证据。

默认保持图片模式，用户明确核对后选择文字模式。OCR 需要额外本地准备时间，尚未实测对具体照片的总耗时收益。服务端排队和模型思考仍可能使文字分析等待较久；支持时可在 AI 高级设置将思考强度调低。

拍照录入三个用途各自保留照片与结果草稿，不会把作业照片带入教材页。切回原用途可继续自己的草稿，练习回录按练习单保留各自内容。

AI 设置操作按钮具有整行底色和至少 56 点高度，显式绑定按压样式；短按松手后高亮停留约 180 毫秒，保存成功按钮显示勾选和“已保存”约 2 秒。
