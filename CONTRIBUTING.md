# Contributing to DeskBox

感谢你参与 DeskBox。

DeskBox 是一个原生 macOS 桌面整理工具。项目当前最重要的原则是：**任何功能都不能以牺牲用户文件安全为代价。**

## 开始之前

1. 先搜索已有 Issue 和 Pull Request。
2. 对大型功能、数据模型变更或拖拽架构变更，建议先开 Issue 讨论。
3. 一个 Pull Request 尽量只解决一个明确问题。
4. UI 变化请提供截图，但务必去除私人文件名和个人信息。

## 开发环境

- macOS 14+
- Xcode 27
- Swift 6

打开项目：

```bash
open DeskBox.xcodeproj
```

Debug 构建：

```bash
xcodebuild \
  -project DeskBox.xcodeproj \
  -scheme DeskBox \
  -configuration Debug \
  -derivedDataPath .build \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 文件安全原则

DeskBox 文件分区对应真实目录：

```text
~/Documents/DeskBox/<分区名称>/
```

修改文件移动相关代码时必须遵守：

- 不覆盖同名文件
- 不在测试中使用用户真实文件
- 优先使用一次性临时文件测试
- 删除分区前必须确保文件已安全处理
- 配置恢复不得删除真实文件
- 工作区切换只改变可见性和元数据，不移动真实文件

## Pull Request 检查项

- [ ] Debug 构建成功
- [ ] 文件分区拖入 / 拖出 / 跨分区移动正常
- [ ] 分区内部排序正常
- [ ] 多选没有回归
- [ ] `⌘Z` 文件移动撤销正常
- [ ] 工作区切换正常
- [ ] 便签 / 待办 / 快捷入口正常
- [ ] 没有提交个人文件、证书、密钥或构建产物
- [ ] 用户可见变更已更新文档
- [ ] UI 变更附带去隐私截图

## 代码风格

优先使用系统框架和原生能力：

- SwiftUI
- AppKit
- Foundation
- QuickLook
- ServiceManagement

避免为了小功能引入大型第三方依赖。

## Release

本项目默认采用免费开源发布方式，不要求贡献者拥有 Apple Developer Program。

`./scripts/build-release.sh` 会生成 Universal、ad-hoc signed 的 ZIP 和 DMG。
