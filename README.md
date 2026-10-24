# Magpie 监控 App

在安卓手机上查看 Magpie 网关的用量、路由、额度、供应商和隐私掩码统计。

Flutter 原生实现，深色 Material 3，数据直连网关，不需要在手机上跑任何服务。

[下载最新版](https://github.com/yayoinoyume/svc-dashboard/releases/latest) · [完整说明](docs/magpie-app.md)

## 下载

固定地址（arm64，绝大多数手机）：

```
https://github.com/yayoinoyume/svc-dashboard/releases/latest/download/magpie-flutter-arm64.apk
```

老 32 位机型用 `magpie-flutter-armv7.apk`。

首次打开需要填两个值：

- **网关地址**：Magpie 的公网地址
- **访问密钥**：网关 `?k=` 后面的那串字符

密钥只保存在这台手机上，不会上传，也不会写进安装包。保存前会先做一次连通性测试，失败会直接告诉你是密钥无效、连不上还是超时。

## 功能

| 页面 | 内容 |
|---|---|
| 概览 | 费用、Token、缓存、首字与解码速度、趋势图（可拖动查看单点）、模型与智能体排行 |
| 路由 | 实时流向图 + 请求流水；路由组与账号池 |
| 额度 | 健康度环、按最低剩余排序的额度窗口、重置时间 |
| 供应商 | 搜索、展开查看模型与并发/密钥状态 |
| 明细 | 会话 / 账号 / 调用方 / 密钥 / 隐私 |

### 实时流向

三列：客户端 → 网关 → 目标（路由组或直连供应商）。

- 客户端名按 magpie 上报的**原名**显示，同一个名字永远是同一个颜色
- 默认只画请求最多的 3 个，其余合并成「其他 N 种」，右上角可以展开全部
- 正在处理的链路有流动光点和呼吸光晕，空闲链路是淡灰实线
- 只显示正在处理或最近 15 秒内有请求的节点，全部空闲时清空

### 隐私

「明细 → 隐私」展示网关的掩码统计，和 magpie 设置里的隐私页同源。

- 掩码总数、按类型排行、按发现方式的比例
- 7 天 / 30 天切换，每日柱状图可点选
- 逐条记录可展开，查看供应商看到的原文片段
- 打码值默认不可读，**点一下才向网关请求原文**；原文只存在网关内存，重启后查不到

### 检查更新

设置页底部显示当前版本，可手动检查更新。启动时也会静默检查一次（缓存 24 小时），有新版本时设置齿轮显示小红点。下载跳系统浏览器，App 不申请存储权限。

## 数据说明

几个来自上游的限制，不是 App 的 bug：

- **客户端名来自 User-Agent**：magpie 能识别的给 ID（`claude`、`codex` 等），认不出的保留产品名（`curl`、`Go-http-client`），完全无标识的记为 `other`
- **邮箱需要客户端二次脱敏**：`/api/usage` 的部分字段会返回真实邮箱，App 统一打码后再显示
- **实时接口是窗口数据**：一次返回最近约 60 条请求，长时间空闲后旧记录仍留在流水里，但不会出现在流向图
- **隐私原文不落盘**：网关只为当前进程保留占位符与原文的对应关系

## 构建

全部在 GitHub Actions 完成，本地不需要 Flutter SDK。

| 工作流 | 触发 | 产物 |
|---|---|---|
| `build-magpie-flutter-apk.yml` | 推送 `magpie-monitor-app` 分支 | Actions Artifact（开发用） |
| `release-magpie-flutter.yml` | 推送 `v*` 标签 | GitHub Release（正式发布） |

构建时临时用 `flutter create` 生成宿主工程，再替换 `lib/`、`pubspec.yaml` 和签名配置。

签名使用独立 release 密钥，存放在 1Password，由 `1password/load-secrets-action` 在构建时下发，不落仓库。

## 发布新版本

```bash
git tag -a v1.7.0 -m "本次更新内容"
git push origin v1.7.0
```

推完自动构建并发布。发布说明优先读取 `docs/releases/<tag>.md`。

## 仓库里还有什么

`svcdash/`、`static/` 和 `dashboard.py` 属于上游项目 **svc-dashboard**：一个零依赖的 Python 服务面板，用来查看本机监听端口、系统负载、定时任务等。

这部分保持上游实现，与本 App 相互独立，互不影响。

- 上游仓库：https://github.com/iamcheyan/svc-dashboard

## 许可证

MIT
