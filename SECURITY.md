# Security Policy

DeskBox 仍处于早期开发阶段。

## 报告安全问题

请不要在公开 Issue 中发布：

- 密码
- API Key
- Apple 签名证书
- Provisioning Profile
- 私人文件内容
- 可直接利用的敏感漏洞细节

如果仓库启用了 GitHub Private Vulnerability Reporting，请优先使用该功能；否则请通过仓库维护者公开资料中提供的私密联系方式联系。

## 文件安全

DeskBox 会真实移动文件到：

```text
~/Documents/DeskBox/
```

涉及文件系统的贡献必须：

- 禁止无提示覆盖文件
- 禁止静默删除真实文件
- 对异常路径和权限错误安全失败
- 测试时使用临时文件而非用户真实文件

## 发布签名

官方开源测试版本当前采用免费 ad-hoc 签名，不包含 Apple Developer ID 公证。

用户应只运行来自本仓库 Releases 或自行从源码构建的版本。
