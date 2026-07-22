# w音乐（wPlayer）

w音乐是一款原生 HarmonyOS 本地音乐播放器，为希望获得干净、流畅且专注的本地音乐体验的用户而开发，以简洁设计、快速响应和高性能播放为目标。

> [!NOTE]
> 这是一个以开发者自用为主要目的的个人兴趣项目，按空闲时间维护，没有固定的开发计划、发布周期或响应时限。普通缺陷和功能建议可能不会及时处理，也可能不予实现；请不要将本项目视为提供持续支持的商业产品。

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

## 维护状态

项目仍在开发中，当前重点是离线本地音乐播放体验。维护取决于开发者的个人时间和使用需求：

- 不承诺回复一般咨询、普通缺陷或功能建议。
- 不承诺兼容所有设备、音频文件或系统版本。
- 影响数据安全、隐私或文件访问边界的问题会在时间允许时优先评估，但同样不提供响应时限。
- 项目没有商业支持、服务等级协议或可用性保证。

安全问题请不要公开披露，处理方式见[安全策略](.github/SECURITY.md)。

## 技术栈

- ArkTS / ArkUI
- Stage 应用模型
- Media Kit AVPlayer / AVMetadataExtractor
- AVSession Kit / Background Tasks Kit
- ArkData 关系型数据库

## 支持环境

- 最低兼容 HarmonyOS SDK 6.1.0，API 23
- 目标及编译 HarmonyOS SDK 6.1.1，API 24
- 设备类型：手机、平板和 2in1
- 开发环境：Windows、DevEco Studio、DevEco CLI

支持情况以开发者实际使用的设备和文件为准。未经过验证的音频格式或设备不应视为正式支持。

## 构建与运行

主要模块为 `entry`。完整环境准备、无签名构建、本地签名和设备安装步骤见[构建指南](docs/BUILDING.md)。

完成环境配置后，可执行：

```powershell
$env:WPLAYER_DISABLE_LOCAL_SIGNING='1'
devecocli build
Remove-Item Env:WPLAYER_DISABLE_LOCAL_SIGNING
```

本地签名信息必须保存在被 Git 忽略的 `signing.local.json` 中。不得提交密码、证书、私钥、Profile 或开发者机器路径。

## 项目文档

- [构建指南](docs/BUILDING.md)
- [隐私政策](PRIVACY.md)
- [安全策略](.github/SECURITY.md)
- [第三方软件使用清单](THIRD_PARTY_NOTICES.md)
- [版本记录](CHANGELOG.md)

## 联系

- 开发者：韩旭龙
- 邮箱：wbbb0@outlook.com
- 开发者主页：https://github.com/wbbb0

## 许可证

Copyright © 2026 韩旭龙

本项目依据 [GNU General Public License version 3](LICENSE) 的第 3 版（仅此版本，即 `GPL-3.0-only`）发布。GPL 允许包括商业用途在内的使用、修改和再分发；对外分发修改版或衍生作品时须遵守 GPL 的相应条款。

除非文件中另有明确说明，仓库中的原创源代码和项目文档均按 `GPL-3.0-only` 提供。第三方软件及材料遵循其各自的许可证。
