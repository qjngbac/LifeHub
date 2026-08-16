# 贡献指南

感谢你帮助改进 LifeHub。项目当前只维护 Android 版本，提交改动前请先确认问题能够在当前 `main` 分支复现。

## 报告问题

请优先使用仓库提供的 Issue 模板，并尽量包含：

- LifeHub 版本和 Android 版本；
- 手机品牌、型号和屏幕尺寸；
- 可重复的操作步骤、预期结果和实际结果；
- 去除个人信息后的截图或日志。

不要上传真实健康资料、精确位置、完整备份、签名密钥、密码或其他隐私数据。

## 本地开发

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

## 提交代码

1. 从 `main` 创建功能或修复分支。
2. 保持改动聚焦，不混入无关格式化或生成文件。
3. 为可测试的逻辑补充测试。
4. 提交前运行 `flutter analyze` 和 `flutter test`。
5. Pull Request 使用中文说明改动原因、用户影响和验证方式。

## 内容库贡献

急救、药品和生活知识的补充必须注明可靠来源，并避免诊断、处方或保证性表述。药品内容应使用通用名，明确常见风险和需要就医或咨询药师的情况。
