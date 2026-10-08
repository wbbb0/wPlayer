# 构建 wPlayer

本文说明如何在新的 Windows 开发环境中构建 wPlayer。项目主要模块为 `entry`。当前
`build-profile.json5` 配置的最低兼容 SDK 为 HarmonyOS 6.1.0/API 23，两个产品的目标 SDK 均为
26.0.0；构建工具模型版本为 26.0.0。编译使用 DevEco Studio 26 配套的 Release SDK。

## 环境要求

- Windows 10 或 Windows 11
- Git
- 能够提供项目当前配置 API 的 DevEco Studio 和 HarmonyOS SDK
- Node.js 和 npm
- DevEco CLI
- 可选：已启用开发者模式的 HarmonyOS 设备及 HDC

API 26 新接口采用 `deviceInfo.sdkApiVersion >= 24 && deviceInfo.apiAvailable('26.0.0')` 保护；
API 23 不调用 `apiAvailable` 或新的材质、播控中心接口。HDS 导航和迷你栏继续使用 API 23 的
`MaterialType.ADAPTIVE` 和 `MaterialLevel.ADAPTIVE`。新旧设备上的渲染、系统控制和播放验证仍需分别执行。

### API 26 接入范围

- 原生菜单、对话框、Toast、索引气泡、设置开关和选择器、播放进度 Slider 使用 entry 模块已有的
  `ohos.arkui.UIMaterial.state = enable`。半模态通过 AppSystemMaterial 接入原生材质，在 API 23 或
  不支持该材质的设备上保留原样式。原生材质档位由系统决定，不在应用内固定高级档位。
- ArtworkView 和 QueueTrackRow 使用 AppShadowStyle，将“无阴影”转换为负半径，避免 API 26 将
  零半径与非零偏移解释为硬阴影。封面放大查看保留原图质量，显式关闭 Image 自动缩小。
- PlaybackSession 使用 `setMediaCenterControlType` 优先显示已注册的上一首、下一首控制。接口失败时
  保留系统默认布局，继续激活媒体会话；旧版本不调用新接口。
- 普通内容区域的自定义按钮、卡片不在新材质的生效范围内，保留现有视觉。新闪控窗的 FLOAT_VIEW
  权限仅对游戏直播和金融盯盘场景开放，因此封面小窗继续使用现有 PiP，不申请该受限权限。
- API 26 的 AVMetadataExtractor 新能力针对视频帧提取，不能替代 MP3/FLAC 标签补全或 sidecar LRC；
  保留现有元数据和歌词边界。FAST Kit 排序不能直接替换数据库持久化排序及分页边界。

将 `DEVECO_SDK_HOME` 指向 DevEco Studio 的 SDK 父目录，不要指向 `sdk\default`、`hms` 或 `openharmony` 子目录。例如：

```powershell
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
```

安装并验证 DevEco CLI：

```powershell
npm install -g @deveco/deveco-cli
devecocli --version
```

如果 PowerShell 因执行策略拒绝运行 `devecocli.ps1`，请修复当前用户的本地脚本策略，或使用 npm 生成的 `devecocli.cmd`。不要从项目脚本中降低受管理设备的安全策略。

## 获取源码

```powershell
git clone --recurse-submodules https://github.com/wbbb0/wPlayer.git
Set-Location wPlayer
```

已有检出在首次构建前初始化 libwebp 和 xxHash 子模块：

```powershell
git submodule update --init --recursive
```

## 无签名构建

公开仓库的 `build-profile.json5` 保持空签名基线，直接构建即可验证无签名路径：

```powershell
devecocli build
```

构建成功后，无签名 HAP 位于：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

无签名 HAP 主要用于验证项目同步、依赖、SDK、ArkTS 编译和资源打包，通常不能直接安装到普通设备。

## 本地签名构建

1. 为当前仓库启用受版本控制的提交钩子：

   ```powershell
   git config core.hooksPath .githooks
   ```

2. 在 DevEco Studio 的 Signing Configs 界面中创建或选择调试、发布签名。IDE 会把本机配置直接写入根目录 `build-profile.json5`。
3. 保持产品 `default` 选择 `default` 签名、产品 `release` 选择 `release` 签名；然后按对应产品执行构建。

`build-profile.json5` 是唯一签名配置源。本地签名存在时，该 tracked 文件会长期显示为已修改；不要使用 `assume-unchanged`、`skip-worktree` 或 `.gitignore` 隐藏它。

### 提交前清理签名

Git 中的便携基线必须同时满足：

- `app.signingConfigs` 为 `[]`；
- `app.products` 保留 `default → default`、`release → release` 的签名名称映射；
- 不包含密码、KeyStore、证书或 Profile 的路径和材料字段。

提交前先把本机文件备份到仓库外，清空上述字段后再暂存：

```powershell
$signingBackup = Join-Path $env:TEMP 'wplayer-build-profile.local.json5'
Copy-Item build-profile.json5 $signingBackup
# 在 build-profile.json5 中清空 signingConfigs，并保留两个产品的签名名称映射
git add build-profile.json5
./tools/check-signing-profile.ps1 -Staged
git commit
Copy-Item $signingBackup build-profile.json5 -Force
Remove-Item $signingBackup
```

`.githooks/pre-commit` 会检查暂存区，而不是工作区。即使误执行 `git add -A`，只要暂存版本包含签名材料，提交就会被拒绝；GitHub Actions 会对推送内容执行相同检查。

### 发布签名

发布构建使用产品 `release`、签名配置 `release` 和 release build mode。完整的发布身份、材料校验、构建
命令和提交前恢复流程见[发布与签名指南](RELEASING.md)。

不要让产品 `default` 临时选择发布签名；调试与发布产品应始终保持各自独立的签名映射。

## 安装与启动

Agent 优先使用用户环境中统一注册的 Harmony Agent Tools MCP：`harmony_inspect` 用于环境、目标与项目检查，
`harmony_project_run` 用于构建、测试和部署，`harmony_device_run`、`harmony_capture` 与 `harmony_logs` 用于
设备操作、截图和有界日志。该工具独立于 wPlayer 维护，仓库不再固定其版本。

MCP 不可用时，可将独立检出路径配置到 `HARMONY_AGENT_TOOLS_HOME`，再使用 JSON CLI：

```powershell
& "$env:HARMONY_AGENT_TOOLS_HOME\hdc-agent.cmd" doctor -ProjectRoot .
& "$env:HARMONY_AGENT_TOOLS_HOME\hdc-agent.cmd" emulators
& "$env:HARMONY_AGENT_TOOLS_HOME\hdc-agent.cmd" packages -ProjectRoot .
```

安装签名 HAP：

```powershell
& "$env:HARMONY_AGENT_TOOLS_HOME\hdc-agent.cmd" install -Target <target> `
  -PackagePath entry/build/default/outputs/default/entry-default-signed.hap
```

启动主 Ability：

```powershell
& "$env:HARMONY_AGENT_TOOLS_HOME\hdc-agent.cmd" start -Target <target> `
  -Bundle com.wabebabo.wplayer -Ability EntryAbility
```

封装输出 JSON，并在存在多个目标时要求显式指定 `-Target`。未覆盖的设备操作仍可使用原始 `hdc`。
如果设备中已安装使用不同签名身份的同包名应用，覆盖安装会失败。卸载应用会删除其本地数据，不应为了构建验证自动卸载。

## 测试

- 本地单元测试位于 `entry/src/test`。
- 设备测试位于 `entry/src/ohosTest`。
- 优先通过外部 MCP 的 `harmony_project_run` 执行 `test-local` 或 `test-device`；也可在 DevEco Studio 中运行
  对应测试目标。
- 提交代码前至少运行一次 `devecocli build`。

音频格式、后台播放、系统媒体控制、文件授权以及不同设备形态仍需要在真实目标设备上验证。构建成功不能替代实际播放测试。

## 常见问题

### 签名材料缺失 `00303107`

如果编译和 PackageHap 已完成、SignHap 报 `Invalid storeFile value`，检查当前本地签名所引用的
`.p12` 文件及相关证书、Profile 是否仍存在，并在 DevEco Studio 中恢复同一签名身份。不要自动重建
签名身份或卸载已有应用；设备覆盖安装必须继续使用原应用的签名。

### SDK 配置错误 `00303217`

确认 `DEVECO_SDK_HOME` 已设置，并指向包含目标 API 的 SDK 父目录。

### 构建结束后出现 Node.js `EPIPE`

如果外部工具过早终止了构建进程，CLI 输出管道可能产生二次 `EPIPE`。应给构建留出足够时间，并检查更早出现的实际同步或编译错误。

### 修改签名配置后构建仍使用旧配置

Hvigor daemon 可能仍保留启动时的环境。停止 daemon 后重新构建：

```powershell
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --stop-daemon
devecocli build
```

DevEco Studio 修改 `build-profile.json5` 后如果构建仍使用上一套配置，也应停止 daemon 再重新构建。
