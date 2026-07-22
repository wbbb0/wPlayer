# 构建 w音乐

本文说明如何在新的 Windows 开发环境中构建 w音乐。项目主要模块为 `entry`，最低兼容 HarmonyOS SDK 为 6.1.0/API 23，目标及编译 SDK 为 6.1.1/API 24。

## 环境要求

- Windows 10 或 Windows 11
- Git
- 能够提供目标及编译用 HarmonyOS SDK 6.1.1/API 24 的 DevEco Studio；生成的应用最低兼容 API 23
- Node.js 和 npm
- DevEco CLI
- 可选：已启用开发者模式的 HarmonyOS 设备及 HDC

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
git clone https://github.com/wbbb0/wPlayer.git
Set-Location wPlayer
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

发布构建必须在 `build-profile.json5` 中保留名为 `release` 的本机签名配置，并让产品 `default` 选择它，同时使用 release build mode：

```powershell
devecocli build --build-mode release
```

也可以在 DevEco Studio 的 Hvigor 任务面板中，将顶部 **Build Mode** 切换为
**Release**，然后运行根项目“其他/Customize”分组下的
`assembleReleaseSignedApp`。该任务会确认产品选择了名为 `release` 的配置，并在打包后核对模块元数据；只有 `buildMode: release` 且 `debug: false` 才会成功。

签名构建产物通常位于：

```text
entry/build/default/outputs/default/entry-default-signed.hap
```

## 安装与启动

确认设备连接：

```powershell
hdc list targets -v
```

安装签名 HAP：

```powershell
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

启动主 Ability：

```powershell
hdc shell aa start -a EntryAbility -b com.wabebabo.wplayer
```

如果设备中已安装使用不同签名身份的同包名应用，覆盖安装会失败。卸载应用会删除其本地数据，不应为了构建验证自动卸载。

## 测试

- 本地单元测试位于 `entry/src/test`。
- 设备测试位于 `entry/src/ohosTest`。
- 可在 DevEco Studio 中运行对应测试目标。
- 提交代码前至少运行一次 `devecocli build`。

音频格式、后台播放、系统媒体控制、文件授权以及不同设备形态仍需要在真实目标设备上验证。构建成功不能替代实际播放测试。

## 常见问题

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
