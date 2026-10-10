# DeskBox

DeskBox 是一个原生 macOS 桌面整理工具，用 Swift / SwiftUI / AppKit 开发。

它把桌面上的文件分区、便签、待办清单、快捷入口和工作区组织在一起，目标是做一个轻量、透明、可自由组合的桌面工作空间。

> 当前版本：**0.1.1**
>
> DeskBox 仍处于早期开发阶段，欢迎试用、提交 Issue 和 Pull Request。

## 功能

- 文件分区
  - 把桌面文件或文件夹拖入分区进行收纳
  - 分区之间拖拽移动
  - 分区内部手动排序
  - 多选、Quick Look、Finder 中显示
  - 文件移动历史与 `⌘Z` 撤销
- 桌面组件
  - 便签
  - 待办清单
  - 网站 / 文件夹 / App 快捷入口
- 工作区
  - 多工作区切换
  - 组件跨工作区移动
  - 布局锁定
  - 保存 / 恢复布局
- 数据安全
  - 文件移动历史
  - 配置导出 / 恢复
  - 异常退出恢复快照
  - 配置损坏隔离
  - 分区文件夹丢失保护
- macOS 原生体验
  - 菜单栏常驻
  - 原生文件图标
  - Quick Look
  - 玻璃质感界面
  - Apple Silicon / Intel Universal 构建

## 重要：文件是如何存储的

DeskBox 的“文件分区”不是快捷方式列表。

文件被拖入分区时，会**真实移动**到：

```text
~/Documents/DeskBox/<分区名称>/
```

例如：

```text
~/Documents/DeskBox/临时文件/
~/Documents/DeskBox/正在处理/
```

DeskBox 不会在重名时覆盖文件，而会生成类似 `文件 2.ext`、`文件 3.ext` 的名称。

便签、待办、快捷入口和工作区归属属于配置数据，不会移动对应的原文件。

## 系统要求

- macOS 14.0 或更高版本
- Apple Silicon 或 Intel Mac

从源码构建建议使用：

- Xcode 27
- Swift 6

## 下载与安装

未来发布版本会放在 GitHub Releases 中，并提供：

- `DeskBox-v0.1.1-macOS-universal.zip`
- `DeskBox-v0.1.1-macOS-universal.dmg`

DeskBox 当前是免费开源练习项目，没有购买 Apple Developer Program，因此 Release 使用 **ad-hoc 签名**，没有 Apple Developer ID 公证。

首次打开时 macOS 可能提示无法验证开发者。可以：

1. 把 DeskBox 拖入“应用程序”。
2. 在 Finder 中右键 DeskBox。
3. 选择“打开”。
4. 再次确认“打开”。

如果系统仍阻止，可前往：

`系统设置 → 隐私与安全性 → 仍要打开`

只建议运行从本仓库 Releases 下载或自行从源码构建的版本。

## 从源码构建

```bash
git clone https://github.com/403528287/DeskBox.git
cd DeskBox
open DeskBox.xcodeproj
```

也可以直接用命令行：

```bash
xcodebuild \
  -project DeskBox.xcodeproj \
  -scheme DeskBox \
  -configuration Debug \
  -derivedDataPath .build \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 生成本地 Release 安装包

仓库提供免费 Release 脚本：

```bash
./scripts/build-release.sh
```

脚本会：

- 构建 arm64 + x86_64 Universal App
- 做本地 ad-hoc 签名
- 验证 App Bundle
- 生成 ZIP
- 生成带 Applications 快捷入口的 DMG

输出位于：

```text
dist/
```

这不会进行 Apple Developer ID 签名或公证。

## 配置备份

DeskBox 设置中可以导出 JSON 配置备份。

备份包含：

- 工作区
- 分区布局
- 便签
- 待办
- 快捷入口
- 布局快照与锁定状态

**配置备份不包含真实文件。**

## 隐私

DeskBox 当前没有账号系统、云同步或遥测上传。

文件整理与配置数据均在本机完成。

## 开发方向

0.1.x 阶段优先保证：

- 文件安全
- 拖拽稳定性
- 配置恢复
- macOS 原生体验

欢迎通过 Issue 讨论新功能，但大型功能建议先讨论设计再提交代码。

## Contributing

欢迎贡献代码、文档、Bug 报告和设计建议。

请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

## Security

请不要在公开 Issue 中提交密码、API Key、Apple 证书、真实桌面文件或其他私人数据。

详见 [SECURITY.md](SECURITY.md)。

## License

MIT License，见 [LICENSE](LICENSE)。
