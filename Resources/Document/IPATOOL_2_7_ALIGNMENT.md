# ipatool 2.7.0 登录与下载对齐

基线：[ipatool v2.7.0](https://github.com/majd/ipatool/releases/tag/v2.7.0)，固定提交 `4484b55d366e177ae6c89758c61588712c572fad`。

本次对齐范围是原生 iOS IPA 工作流使用的 SAP、账户登录及下载协议。保留现有 SwiftUI 界面、ApplePackage 与 Digger；未移植 ipatool CLI、MCP 服务、Mac 安装包解密或新增 watchOS/tvOS 产品界面。

## 本地 SAP / kbsync

- 构建脚本使用上述固定提交的资源、Mach-O 加载与模拟执行源码；继续使用固定 Naville/Unicorn TCI 解释器和静态 cgo 适配，不引入远程签名服务或 JIT。
- `AssppSAPSign` 增加 `kbsync` 操作，在设备内调用上游 `machine.GenerateKBSync`，要求六字节 GUID 和非零 UInt64 DSID。
- StoreAgent 初始化在解释器下比桌面 JIT 慢；仅为一次性 kbsync 运行时设置每次执行最多 5 分钟、整体最多 10 分钟的预算，受上下文剩余时间约束。普通登录 SAP 会话保留原执行上限。
- 资源和 StoreAgent 仍从 Apple 下载并校验哈希，缓存路径由 Swift 沙盒传入。
- kbsync 只在请求及返回的 App/版本验证通过后缓存；按 DSID/GUID 隔离，内存缓存和本机 Keychain 配合。不会加入账户导出、下载记录或日志。
- 缓存遭拒后绕过旧值重新生成一次；新值失败后进入传统下载回退，不无限循环。取消任务不会继续发下载请求。

## 手机号与登录

- 与上游一致识别中国大陆及印度手机号格式，添加对应 storefront 路由头，不重写发给 Apple 的账号文本。
- 账号输入支持邮箱/手机号；账户模型、刷新、加密备份保留原来的字段，导入验证增加支持的手机号。
- 2FA 保留前导零、移除 Unicode 空白及匹配的终端粘贴包裹，要求六位 ASCII 数字；错误或未完成验证返回可由界面处理的错误类型。
- 登录重定向保留当前认证尝试的原始请求体，不再在第二次认证后重置 `attempt`；每次网络发送重新生成 SAP 签名，保留 Cookie 与同一 SAP 会话。
- 限制认证次数、重定向次数和每个网络请求时长；只重试可恢复的超时、连接断开及未包含 Apple 业务错误的临时 HTTP 响应，遵守有上限的 Retry-After。
- finance 登录端点规范化结尾斜杠，保留可信 bag 的主机和查询；原生端点保持自己的路径。拒绝不支持的重定向目的地。

## 下载恢复

1. 有可信 bag 端点和本地生成器时，优先使用 `ent/download`：固定外部版本 ID、kbsync、设备序列数据、storefront 与 X-Token。
2. 该路径不可用时回退 `volumeStore`。
3. 空结果、特定 No Longer Available 或兼容的 5002 结果，通过 bag 的 `redownload` 重试，并固定 iOS 版本。
4. redownload 空 HTTP 500 或相同可用性错误时，使用 bag 的 `updateProduct`；修正该端点的 `appExtVrsId` 参数名。

所有尝试复用同一账号、GUID 和 Cookie；不在回退途中重新读取或登录其他账号。ent/download 禁止跟随重定向，X-Token 不会发到重定向目的地。传统下载重定向也限制在允许的 Apple 主机/路径。

当前版本查询增加 iPhone/iPad 消费者目录和公共 App Store 目录后备，保留账户国家并验证平台与 App 身份。版本固定的下载检查返回 App ID、Bundle ID、外部版本 ID；文件落盘前再次检查 IPA 主应用的 Bundle ID 与 iPhoneOS 平台，防止回退得到 tvOS 等错误包。兼容没有 sinf 的包。

## 检查

```sh
swift test --package-path Vendor/ApplePackage --filter 'HistoricalDateTests|Protocol270Tests|StoreDownloadEndpointTests'
bash Resources/Scripts/test.features.sh
python3 Tests/Scripts/test_release_packaging.py
```

Swift 协议测试采用注入的响应，不使用实际账号、Keychain 或 Apple 网络；功能测试增加中印手机号备份往返检查。构建脚本另外运行上游 Go 单元测试、桥接输入检查、实际 SAP 握手和虚拟账号标识的 kbsync 解释器测试。后两者会访问 Apple 资源/握手服务，但不使用真实 Apple ID 凭据。

main 推送自动运行 Local SAP iOS App，测试与构建并行，全部通过后提供未签名 IPA。版本 `5.1.0 (18)` 仍需通过侧载工具签名并进行真实账号登录、2FA 和下载的真机验收。
