# w音乐（wPlayer）

w音乐是一款原生 HarmonyOS 本地音乐播放器，为希望获得干净、流畅且专注的本地音乐体验的用户而开发，以简洁设计、快速响应和高性能播放为目标。

## 设计目标

- **保持纯粹**：专注本地音乐的导入、整理和播放，不加入账号、广告或与播放无关的内容。
- **尊重数据**：首版完全离线，音乐与播放数据保存在用户设备中。
- **原生体验**：使用 ArkTS、ArkUI 及 HarmonyOS 媒体能力构建，并适配手机、平板和 2in1 设备。
- **性能优先**：持续优化大音乐库浏览、封面处理、播放稳定性和交互响应。

## 当前版本

首个公开版本定位为纯离线播放器：

- 音乐仅来自用户通过系统文件选择器主动选择的本地文件。
- 应用不提供、下载或推荐音乐内容。
- 不包含账号、广告、应用内购买、使用统计、崩溃上传或在线更新检查。
- 不申请网络访问权限，不连接开发者或第三方服务器。
- 音乐库、播放列表、播放状态和设置保存在设备本地。
- 清空音乐库会移除应用内记录和缓存、请求撤销相应文件授权，但不会删除原始音乐文件。
- 应用数据不参与系统备份。

详细信息请参阅[隐私政策](PRIVACY.md)和[第三方软件使用清单](THIRD_PARTY_NOTICES.md)。

## 技术栈

- ArkTS / ArkUI
- Stage 应用模型
- Media Kit AVPlayer / AVMetadataExtractor
- AVSession Kit / Background Tasks Kit
- ArkData 关系型数据库

## 构建

主要模块为 `entry`。请使用项目所需版本的 DevEco Studio 和 HarmonyOS SDK 构建：

```powershell
devecocli build
```

本地签名信息应保存在被 Git 忽略的 `signing.local.json` 中；不得提交密码、证书、私钥、Profile 或开发者机器路径。

## 联系

- 开发者：韩旭龙
- 邮箱：wbbb0@outlook.com
- 开发者主页：https://github.com/wbbb0

## 许可证

Copyright © 2026 韩旭龙

本项目依据 [GNU General Public License version 3](LICENSE) 的第 3 版（仅此版本，即 `GPL-3.0-only`）发布。GPL 允许包括商业用途在内的使用、修改和再分发；对外分发修改版或衍生作品时须遵守 GPL 的相应条款。
