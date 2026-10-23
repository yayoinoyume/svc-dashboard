# Magpie 监控 App（Android）

只读查看 Magpie 网关的用量、路由、额度和供应商状态。Flutter 原生客户端，代码在 `flutter_app/`。

数据直连网关公网 API，不需要在手机上跑任何服务。

## 首次使用

打开后填写两个值：

- **网关地址**：Magpie 的公网地址
- **访问密钥**：网关 `?k=` 后面的那串字符

密钥只保存在本机（SharedPreferences），不会上传，也不会写进安装包。地址默认为空，必须自己填。

保存前会先做一次连通性测试，失败会直接提示是密钥无效、无法连接还是超时。

## 页面

| 页面 | 内容 |
|---|---|
| 概览 | 周期切换、费用、Token/缓存/首字/解码速度、趋势图（可拖动查看单点）、模型与智能体排行 |
| 路由 | 实时流向图（客户端 → 网关 → 路由组/供应商）+ 请求流水；路由组与账号池 |
| 额度 | 健康度环、按最低剩余排序的额度窗口、重置时间 |
| 供应商 | 搜索、展开查看模型与并发/密钥状态 |
| 明细 | 会话 / 账号 / 调用方 / 密钥四个子页 |

### 实时流向图

三列：左边客户端、中间网关、右边目标（路由组或直连供应商）。

- 正在处理的链路高亮并带流动虚线，其余为灰色
- 节点小圆点在有请求时脉冲
- 只显示「正在处理」或「最近 15 秒内有请求」的节点；全部空闲时清空并提示「当前空闲」
- 点击任意节点可筛选下方流水

请求流水每行显示客户端、目标、耗时、会话短号、上下文大小，以及**输出速度**（tokens/秒 = 输出 token ÷ 流式时长）。展开可看候选账号池、实际选中项、首字延迟和费用。

## 数据说明

几个来自上游的限制，不是 App 的 bug：

- **客户端类型只有三种**：网关只上报 `pi` / `claude` / `other`，`other` 不带程序名，只能看到会话 ID
- **邮箱需要客户端二次脱敏**：`/api/usage` 的部分字段会返回真实邮箱，App 统一打码后再显示
- **实时接口是窗口数据**：一次返回最近约 60 条请求，长时间空闲后旧记录仍会留在流水里，但不会出现在流向图

## 构建

全部在 GitHub Actions 完成，本地不需要 Flutter SDK。

| 工作流 | 触发 | 产物 |
|---|---|---|
| `build-magpie-flutter-apk.yml` | 推送 `magpie-monitor-app` 分支 | Actions Artifact（开发用） |
| `release-magpie-flutter.yml` | 推送 `v*` 标签 | GitHub Release（正式发布） |

构建流程会临时用 `flutter create` 生成宿主工程，再替换 `lib/`、`pubspec.yaml` 和签名配置。

## 发布新版本

```bash
git tag v1.5.1
git push origin v1.5.1
```

推完自动构建并发布。下载链接固定为：

```
https://github.com/<owner>/<repo>/releases/latest/download/magpie-flutter-arm64.apk
```

两个 ABI 包：`arm64`（绝大多数手机）、`armv7`（老 32 位机型）。

## 签名

用独立的 release 密钥，不使用仓库里的 debug keystore。

- 密钥材料存放在 1Password 保险库 `Magpie` 的 `magpie-signing` 条目（`base64` / `password` / `alias` / `key_password`）
- GitHub 只保存一个 `OP_SERVICE_ACCOUNT_TOKEN`，构建时由 `1password/load-secrets-action` 读取
- `.github/scripts/configure-signing.py` 负责把密钥写进 Gradle 配置，并校验替换是否生效
- 密钥由 openssl 生成的 PKCS12（`magpie-release.p12`），Android 与 Gradle 均可直接使用

**密钥丢失 = 无法再发覆盖升级**，已安装用户只能卸载重装。1Password 和本机备份至少保留一份。

## 版本与升级

- `versionName` 取自标签（`v1.5.0` → `1.5.0`）
- `versionCode` 用 Actions 运行序号，单调递增，保证覆盖安装
- 签名变更后首次安装必须卸载旧版（不同签名不能覆盖）
