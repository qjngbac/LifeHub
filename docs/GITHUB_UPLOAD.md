# GitHub 上传范围与操作说明

本说明针对仓库根目录 `lifehub/`。只上传此目录中的项目文件，不上传其父目录的 SDK、下载缓存、历史项目、临时目录和安装包集合。当前远程地址为 `https://github.com/qjngbac/LifeHub.git`。

仓库仅维护当前项目文件。内部设计说明 `docs/superpowers/specs/2026-09-07-match-schedule-module-design.md` 已取消跟踪，本地文件保持原样；内部工作记录不再随当前源码上传。2026-10-16 的发布使用已有 V1.10.29 安装包，没有重新打包。

## 上传到源码仓库

| 内容 | 选择与原因 |
| --- | --- |
| `lib/` | 全部当前业务源码，包括比赛、财务、生命选品等模块；保留数据库 `app_database.g.dart` |
| `android/` | 原生宿主、通知、组件、白噪音宿主、测试和 Gradle 配置；遵循其 `.gitignore`，保留公开签名示例 |
| `assets/` | 应用随包使用的离线内容、图标与音频，避免克隆后缺资源 |
| `test/`、`integration_test/` | 测试与回归用例 |
| `third_party/` | 当前依赖覆盖的源码、说明和许可证；不可漏掉 `workmanager_android` |
| `tool/` | 仓库维护、内容生成和稳定性检查脚本 |
| `.github/` | Issue 与 Pull Request 模板 |
| 公开文档与配置 | README、贡献/隐私/安全说明、更新日志、许可证、安装说明、版本说明、图标宣传图，以及 `pubspec.yaml`、`pubspec.lock`、`.metadata`、分析和代码生成配置 |

保留现有 GPL-3.0 许可证及中文参考译文，不在本轮变更授权方式。第三方依赖继续保留自己的许可证。发布者还应核对离线内容与音频的来源及分发权限，不补写未经确认的作者或素材授权。

## 不上传到源码仓库

- `build/`、`.dart_tool/`、IDE 状态、日志、分析转储和设备捕获。
- 真实 `key.properties`、密钥库、私钥、口令与 `.env` 本机环境文件。
- 用户数据库、备份、导出、附件和聊天截图；问题示例只能使用人工构造或已脱敏的数据。
- `.superpowers/` 的本地会话状态、`AGENTS.md` 中的本机工作约定、内部交接与融合分析文档。
- `legacy_source/`、根目录旧 `features/` 和内部规划/验收文件；不要与 `lib/features/` 混淆。
- APK 与历史归档压缩包。

`.gitignore` 已补充上述本地排除项。已跟踪的旧内部设计说明已通过 `git rm --cached` 移出索引，本地文件没有删除。旧提交中仍会保留它的历史，本次不重写 Git 历史。

忽略规则不会自动清除曾经提交的敏感内容。若发现历史泄露，先处理凭据与历史，再推送；不要直接公开泄露内容。

## 源码上传前检查

在仓库根目录执行，先查看再提交：

```bash
git status --short
git diff --stat
git diff --check
git ls-files --others --exclude-standard
```

确认新功能的未跟踪源码、资源和测试都在候选文件中。不要因为它们显示为 `??` 就丢掉这些模块。

核对文件后才进行暂存、检查和提交，下面是后续维护时的操作参考：

```bash
git add -- .github .gitignore .metadata android assets lib test integration_test third_party tool docs
git add -- README.md CONTRIBUTING.md SECURITY.md PRIVACY.md CHANGELOG.md LICENSE LICENSE.zh-CN
git add -- pubspec.yaml pubspec.lock analysis_options.yaml build.yaml
git diff --cached --stat
git diff --cached --check
```

提交与推送前再确认目标分支、远程仓库和候选文件。不使用强制推送，也不要把“全部同步本地文件夹”当成源码上传方式。必要时先在新的克隆目录中验证依赖和构建，不改动本机私有签名。

## APK 放在 Releases

源码提交与 APK 发布是两个独立操作。已有本地安装包不需要为了上传文档重新构建；当前包的信息见 [V1.10.29 说明](releases/V1.10.29.md)。

发布时上传带版本号的 `LifeHub-V1.10.29-arm64.apk`，使用对应版本说明。通用 `LifeHub-release.apk` 是本地便捷副本，同版本两者应有相同 SHA-256。不要把 APK 提交进 Git 源码历史。

如果之后明确要求重新打包，按工作区约定递增版本号，同时生成通用包和版本归档包，并更新本地 `AI_HANDOVER.md`；本轮没有执行这些操作。
