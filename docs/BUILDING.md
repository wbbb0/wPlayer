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

公开仓库不包含任何签名材料。首次构建建议显式关闭本地签名注入：

```powershell
$env:WPLAYER_DISABLE_LOCAL_SIGNING = '1'
devecocli build
Remove-Item Env:WPLAYER_DISABLE_LOCAL_SIGNING
```

构建成功后，无签名 HAP 位于：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

无签名 HAP 主要用于验证项目同步、依赖、SDK、ArkTS 编译和资源打包，通常不能直接安装到普通设备。

## 本地签名构建

1. 在 DevEco Studio 中分别创建或选择调试签名和发布签名配置。
2. 复制 `signing.local.example.json` 为 `signing.local.json`。
3. 将 DevEco Studio 生成的两套签名对象原样填写到对应 configuration 的 `signingConfig`，不要修改对象内部的 `name` 或加密密码字段。
4. 确认 `signing.local.json` 被 Git 忽略且未被跟踪。
5. 正常执行 `devecocli build`，默认使用 `defaultConfiguration` 指定的 `debug` 配置。

根目录 `hvigorfile.ts` 会在本地文件存在时只注入当前选中的签名配置。不要把签名配置写回受版本控制的 `build-profile.json5`。

发布构建必须显式选择 `release` 签名，并同时指定 release build mode：

```powershell
$env:WPLAYER_SIGNING_CONFIG = 'release'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --stop-daemon
devecocli build --build-mode release
Remove-Item Env:WPLAYER_SIGNING_CONFIG
```

签名配置与 build mode 是两个独立维度。`WPLAYER_SIGNING_CONFIG` 选择证书和 Profile，`--build-mode release` 选择发布编译模式；发布包必须同时正确设置两者。

也可以在 DevEco Studio 的 Hvigor 任务面板中，将顶部 **Build Mode** 切换为
**Release**，然后运行根项目“其他/Customize”分组下的
`assembleReleaseSignedApp`。该任务会固定选择 `signing.local.json` 中 id 为
`release` 的签名配置，再执行 `assembleApp`；无需设置
`WPLAYER_SIGNING_CONFIG`。如果 Build Mode 不是 Release、缺少本地签名文件或
缺少 `release` 配置，任务会报错。任务还会在打包后核对实际生成的模块元数据，
只有 `buildMode: release` 且 `debug: false` 才会成功；失败的任务及其产物不能
作为发布包使用。

`signing.local.json` 由 Hvigor hook 在构建时读取，不是 DevEco Studio Project Structure 界面管理的配置源。IDE 的 Signing Configs 页面不会可靠地列出或切换这两套本地配置；请通过 `defaultConfiguration` 或 `WPLAYER_SIGNING_CONFIG` 选择。若在 IDE 中编辑签名，IDE 可能把签名材料重新写入受版本控制的 `build-profile.json5`，提交前必须迁回 `signing.local.json` 并清理 tracked 文件。

检查签名文件是否未被跟踪：

```powershell
git check-ignore signing.local.json
git ls-files signing.local.json
```

第一条命令应显示该文件，第二条命令不应输出任何内容。

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

### 清除环境变量后仍只生成无签名 HAP

Hvigor daemon 可能仍保留启动时的环境。停止 daemon 后重新构建：

```powershell
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --stop-daemon
devecocli build
```

切换 `WPLAYER_SIGNING_CONFIG` 后如果构建仍使用上一套签名，也应停止 daemon 再重新构建。
