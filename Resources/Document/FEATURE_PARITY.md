# Asspp 原生端：账户备份与本地 IPA

参考项目：[mymolasses/Asspp](https://github.com/mymolasses/Asspp)、[mymolasses/AssppWeb](https://github.com/mymolasses/AssppWeb)。

## 代码分析与改动

原生端使用 SwiftUI，`AppStore` 管理 Keychain 账户与登录，`Downloads` 管理下载队列，`PackageManifest` 记录安装包，安装与分享入口位于 `PackageView`。Web 端相应功能在账户备份设置、`UploadIpa`、`DownloadList` 和 IPA 签名资料服务中。

| 原有差异 | 本次实现 |
| --- | --- |
| 原生端没有账户备份入口 | 账户页、账户详情和设置页支持加密导出；账户页、设置页支持导入 |
| Web 使用 `cookies`，Swift 使用 `cookie` | 转换完整字段，保留账户密码、令牌、Cookie、设备标识与 pod |
| Web 账户各自保存 GUID，原生端使用全局 GUID | `UserAccount` 增加可选设备标识；ApplePackage 用 TaskLocal 为每个请求隔离 GUID，刷新登录同样使用原账户 GUID |
| 重复账户可能覆盖现有登录 | 导入先完整校验并预览数量，邮箱忽略大小写去重；明确选择保留或替换已有账户 |
| 本地 IPA 无法进入包列表 | 从系统文件选择器导入，无需 Apple ID；在后台复制并解析文件，复用详情、安装、分享、内容查看与删除 |
| Web 支持自定义上传包名称 | 导入时或详情页修改显示名称，最长 120 字符；不修改 IPA 内部名称、签名或文件内容 |
| 缺少本地包来源与签名资料 | 显示原始文件名、版本、构建号、大小、描述文件类型、团队、到期日期、设备数量与证书名称；支持重新检查 |
| 下载列表定位和整理不便 | 新增关键词搜索、来源/状态/账户/地区筛选、最新/名称排序及持久化的列表/卡片视图；地区按规范化国家代码合并 |
| 空页面与操作反馈不足 | 增加直接导入入口、无搜索结果提示、会话状态、导入错误提示、分享入口与删除确认；补充中英文文案 |
| 下载记录将整个账户写入普通配置文件 | 记录仅保存邮箱和地区，不再包含账户密码、令牌或 Cookie；旧记录自动兼容读取并按新格式保存 |

继续使用现有状态管理方式，避免为此功能重写已有下载队列或登录实现。

## 使用入口

- **导入账户**：账户页工具栏 → 账户备份 → 导入账户，或设置 → 账户备份；选择 Web 导出的文件，输入备份密码，确认保留或替换重复账户。
- **导出账户**：同一菜单导出全部账户；账户详情可以单独导出。输入并确认备份密码，通过系统文件导出器保存。
- **导入 IPA**：下载页右上角“+” → 导入本地 IPA，或使用空列表中的导入按钮；可以填写自定义显示名称。
- **安装与分享**：导入成功后自动打开包详情；安装复用原有设备安装流程，分享通过系统分享菜单或 AirDrop。

## 备份兼容性

新备份使用 Web 修改版的 `asspp.accounts` / version `1` 信封格式；读取时也接受旧版本的账户数组。

加密格式与参考项目的 `frontend/src/utils/crypto.ts` 一致：

```
Base64(salt[16] + nonce[12] + AES-GCM ciphertext + tag[16])
PBKDF2-HMAC-SHA256 / 100,000 iterations / AES-256-GCM
```

备份大小限制为 16 MiB，按块读取，避免错误选取大文件时一次载入全部内容。所有账户先通过字段验证，再修改账户存储。导入的会话初始标记为“尚未验证”，实际使用时沿用现有会话校验和重新登录流程。

旧 Keychain 账户缺少设备标识时继续使用原生端配置的全局 GUID；导出时写入该 GUID。已有下载记录的嵌套账户字段保留兼容，但写回时只留下归属信息。这不清理磁盘历史备份或此前产生的损坏备份文件。

## 本地 IPA 的处理边界

- 本地安装清单使用 [`CFBundleVersion`](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion) 构建号，列表保留 `CFBundleShortVersionString` 展示版本，避免两种版本号不一致时产生安装信息错误。
- 原始文件保持不变，导入副本按 UUID 保存，避免相同版本重复导入相互覆盖，也避免元数据影响存储路径。
- 主应用必须位于 `Payload/<name>.app/Info.plist`，接受 XML 和二进制 plist；要求仅有一个主应用，嵌套扩展不会被误认成主应用。
- 仅读取必要元数据；Info.plist 上限 2 MiB、描述文件上限 8 MiB，校验解压长度和 CRC，避免整体解压。
- 描述文件资料仅供安装判断参考，**不验证 Mach-O/CMS 的密码学签名、证书吊销状态或设备实际授权**。保留原始签名不意味着能够安装；本次不提供重新签名或授权绕过。
- macOS 设备安装后的账户关联只保存归属信息；本地包不加入 App Store 账户的更新列表。用本地包替换已跟踪应用时移除旧的更新关联。
- Web 端的上传改为原生端本地导入，文件保存在应用沙盒内，不需要 Web 服务上传。

## 验证方式

运行：

```sh
bash Resources/Scripts/test.features.sh
```

需要 Xcode、Python 3 与支持 Web Crypto 的 Node.js。可以用 `ASSPP_NODE_BIN=/path/to/node` 指定 Node；`ASSPP_FEATURE_BUILD_DIR` 可指定 SwiftPM 编译缓存。

测试从生产目录复制实际功能源码，使用临时目录与内存账户宿主；不调用应用单例、不读取真实 Keychain、不访问 Apple 账户 API。Web Crypto 独立实现用于验证 Web → Swift 和 Swift → Web 的互通，而非只测试同一实现的加密解密。

覆盖备份版本、旧数组、Unicode 密码、错误密码、GCM 篡改、设备标识校验、重复账户、刷新冲突、并发 GUID 隔离、旧存储迁移、IPA 原始字节、重复导入、重命名、非法元数据、路径隔离和删除源文件保护。

## 当前验证与构建

- 71 项功能回归检查通过；独立 Web Crypto 成功解密原生导出文件，并逐字段核对账户资料，包含新增的手机号备份检查。
- 27 项登录、下载及历史协议检查通过，iOS 工作区编译、链接通过。
- 本地 SAP 已升级为 ipatool 2.7.0 源码并新增 kbsync；详见 [对齐说明](IPATOOL_2_7_ALIGNMENT.md)。
- 未签名 Release IPA 通过下述 GitHub Actions 构建；真实 Apple ID 登录、2FA 和真机安装仍需设备验收。

## 构建依赖

### GitHub Actions 测试包

推送 `main` 分支会自动触发 **Local SAP iOS App**；也可以手动运行该工作流。工作流先运行功能回归，再构建并测试 SAP 静态库，随后编译 Release IPA，检查 arm64 架构和 ZIP 完整性，并上传：

- `Asspp-ios-<提交 SHA>`：未签名 IPA 与 SHA-256 校验文件，供侧载工具签名/安装。
- `LocalSAP-ios-arm64-<提交 SHA>`：可复用的设备静态库与 C 头文件。

产物保留 14 天。工作流使用固定版本的 Go 与 CMake；不需要 Apple ID 或开发者签名证书，也不发布 Release。打包脚本不会执行 Git 清理或覆盖已有的 `Developer.xcconfig`。

### 本地构建

当前 main 分支使用本地 SAP 登录，`Configuration/Base.xcconfig` 链接 `libasspp-sap.a` 和 `libunicorn.a`。源码归档不包含这两个生成库。它们由 `Experiments/LocalSAP/build.sh` 构建，通过 `LOCAL_SAP_LIBRARY_DIR` 提供；现有 `.github/workflows/local-sap-app.yml` 包含相应步骤。

没有这些库时，Xcode 可以进行 Swift 编译检查，但最终链接无法生成可安装包。真实 Apple 登录、2FA 与设备安装还需在包含这些库的构建中验证。
