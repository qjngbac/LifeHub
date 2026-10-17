# LifeHub

> 本地优先、离线可用的 Android 个人生活管理应用。

LifeHub 使用 Flutter 开发，把任务、日程、课程表、财务收支、比赛日程、便签、旅行和生活知识放在同一个应用中。核心数据默认保存在手机本地，不需要注册账号，也不依赖配套云端服务器才能使用。

- 当前源码版本：**V1.10.29（构建号 51）**，以 [`pubspec.yaml`](pubspec.yaml) 为准
- 支持平台：**Android 7.0（API 24）及以上**
- 安装包架构：**arm64-v8a**

[查看 GitHub Releases](https://github.com/qjngbac/LifeHub/releases) · [安装与使用](docs/安装与使用.md) · [贡献指南](.github/CONTRIBUTING.md)

[下载 V1.10.29 Android ARM64 安装包](https://github.com/qjngbac/LifeHub/releases/download/v1.10.29/LifeHub-V1.10.29-arm64.apk)

源码版本与已上传的安装包可能不同，请以 Releases 中实际列出的版本为准。

V1.10.29 的发布前测试未全部通过，包含急救卡编辑弹窗的已知问题；具体结果见 [Release 说明](https://github.com/qjngbac/LifeHub/releases/tag/v1.10.29)。

## 主要功能

### 计划与执行

- 任务、子任务、项目、清单和习惯
- 日、周、月日程视图，以及 ICS 导入导出
- 比赛日程、结果补录与赛事档案；支持文本、剪贴板和本机截图 OCR 导入，识别后可预览、编辑与检查重复
- 课程表、学期周次、单双周、连堂课程和 Android 桌面组件
- 长期目标、里程碑、关联进度、专注与计时、周/月复盘
- 收件箱、晚间规划、本地自动化和统一关联中心

### 生活记录

- 心情日历、关系空间、纪念日
- 旅行计划、地点、旅行账单和附件
- 家庭物品与保修、证件到期、用药提醒与本地急救卡
- 财务收支、多账户、预算、转账、退款、报销和账单导入
- 快递取件、阅读进度和影视进度

### 资料与离线知识

- 支持富文本便签、标签、图片和文件附件的本地资料库
- 按地区整理的野外急救与求生知识
- 日用品选购知识库和常见药品信息库
- 生命选品：按人生阶段整理日用品、食品、水果与居家环境指南
- 专注计时与内置白噪音
- 笑话与故事支持模块内搜索、收藏、屏蔽和稍后阅读
- 全局搜索只收录适合全局查找的重要数据；娱乐内容和影视记录仅在模块内搜索

### 数据管理

- JSON 完整备份或仅数据备份
- 使用 Argon2id 与 AES-256-GCM 的密码加密备份
- 合并恢复、替换恢复、恢复前检查和数据健康检查
- 归档与最近删除分离
- 数据页模块排序、固定、隐藏和恢复默认布局
- 本地二级密码保护私密内容的查看入口；它不等同于数据库整库加密

## 离线与联网边界

LifeHub 的任务、日程、课程表、资料、知识库、搜索、备份等核心功能均可离线使用。

以下功能需要网络或系统能力：

- 天气：定位由 Android 系统提供，天气与空气质量由 Open-Meteo 获取；断网时保留上次成功缓存。
- 通知和提醒：依赖 Android 通知、精确提醒、后台运行及电池策略。
- 桌面组件：由 Android 桌面启动器提供，系统可能根据省电策略延后刷新。

应用不会要求登录，也没有配套云端服务器。详细说明见[隐私说明](docs/隐私说明.md)。

## 安装

1. 在 [Releases](https://github.com/qjngbac/LifeHub/releases) 选择已发布版本，下载相应的 `LifeHub-V<版本>-arm64.apk`。
2. 在 Android 文件管理器中打开 APK。
3. 如系统拦截，请仅为当前文件管理器临时允许“安装未知应用”。
4. 首次打开后，按需要授予通知和定位权限。

升级或卸载前，建议先在“我的”中导出密码加密备份。卸载应用或清除应用数据会删除手机上的 LifeHub 本地数据。

更完整的手机设置说明见[安装与使用](docs/安装与使用.md)。

## 权限用途

| 权限或系统能力 | 用途 | 是否影响核心离线功能 |
| --- | --- | --- |
| 通知 | 任务、习惯、课程、用药和证件提醒 | 拒绝后仅不提醒 |
| 定位 | 获取当前位置并查询当地天气 | 拒绝后可使用已保存地区或天气缓存 |
| 网络 | 刷新天气和空气质量 | 断网时其他功能可继续使用 |
| 后台运行/开机恢复 | 恢复提醒、自动备份和桌面组件 | 受系统省电策略影响 |

## 本地开发

### 环境要求

- Flutter 3.44.0 或更高的兼容版本
- Dart 3.12.x（项目约束为 `>=3.12.0 <4.0.0`，随 Flutter SDK 提供）
- JDK 17
- Android SDK；当前构建使用 API 36，实际 SDK/NDK 版本由 Flutter Gradle 配置决定
- arm64 Android 真机或相应开发设备

### 获取依赖与生成代码

```bash
flutter pub get
```

项目保留 `pubspec.lock`、数据库生成文件和经过兼容修正的 `third_party/workmanager_android`。修改数据库声明后，再按[贡献指南](.github/CONTRIBUTING.md)生成代码并验证迁移。

### 运行与检查

```bash
flutter run
flutter analyze
flutter test
```

### 构建 Android APK

```bash
flutter build apk --release --target-platform android-arm64
```

发布签名配置不在仓库中。可复制 [`android/key.properties.example`](android/key.properties.example) 为 `android/key.properties`，填写自己的密钥路径和签名信息。缺少配置时 release 构建会失败，不会退回调试签名。不要提交真实的 `key.properties`、`.jks`、`.keystore` 或口令。

从源码自行构建的应用使用你自己的签名，通常不能直接覆盖原作者签名的正式版；更换安装包前先导出备份。

## 目录结构

```text
lifehub/
├─ .github/                  问题反馈、贡献指南与安全说明
├─ android/                  Android 原生代码、通知与桌面组件
├─ assets/                   图标、音频和离线知识库内容
├─ docs/                     安装使用、隐私说明与更新日志
├─ integration_test/         集成测试
├─ lib/                      Flutter 应用源码
│  ├─ app/                   路由、主题与主界面
│  ├─ core/                  数据库、备份、通知等基础能力
│  ├─ features/              各业务模块
│  └─ shared/                公共组件和工具
├─ test/                     单元测试与组件测试
├─ third_party/              仓库内兼容依赖及其许可证
└─ tool/                     内容生成和稳定性检查脚本
```

## 项目状态

当前维护 Android 1.x 系列。各功能随真实设备反馈持续调整；通知、后台任务和桌面组件会受到系统省电策略影响。安装其他签名或旧测试包前请先导出备份。

版本记录见[更新日志](docs/更新日志.md)，安装包和发布说明统一放在 [Releases](https://github.com/qjngbac/LifeHub/releases)。

## 参与贡献

提交问题前请阅读[贡献指南](.github/CONTRIBUTING.md)。安全问题请按[安全说明](.github/SECURITY.md)私下报告，不要在公开 Issue 中附带真实健康信息、位置、备份文件或签名材料。后续提交说明统一使用中文。

## 免责声明

急救、药品、天气和生活知识仅用于信息整理与应急参考，不能替代医生、药师、急救人员或当地主管部门的专业判断。发生紧急情况时，应优先联系当地急救和救援机构。

## 许可证

LifeHub 使用 [GNU General Public License v3.0](LICENSE) 发布，另有[许可证中文参考](docs/许可证中文参考.md)。第三方依赖继续遵循各自许可证。
