# 第三方软件使用清单

适用范围：当前开发版本及后续公开版本

最后核对日期：2026 年 8 月 6 日

## 随应用分发的第三方组件

| 组件 | 版本 | 用途 | 分发方式 | 许可证 |
| --- | --- | --- | --- | --- |
| libwebp | 1.6.0 | 将应用缓存中的缩放封面编码为有损 WebP，并保留透明度 | 从源码静态链接到应用原生库 | BSD 3-Clause；另含附加专利授权 |

### libwebp

- 项目主页：https://chromium.googlesource.com/webm/libwebp/
- 本项目锁定版本：`v1.6.0`（commit `4fa21912338357f89e4fd51cf2368325b59e9bd9`）
- 本项目中的源码位置：`entry/src/main/cpp/third_party/libwebp`
- 上游许可文件：`COPYING`、`PATENTS`

以下许可与专利授权正文按上游文件原文保留。

#### Copyright and license

```text
Copyright (c) 2010, Google Inc. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

  * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the
    distribution.

  * Neither the name of Google nor the names of its contributors may
    be used to endorse or promote products derived from this software
    without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

#### Additional IP Rights Grant (Patents)

```text
"These implementations" means the copyrightable works that implement the WebM
codecs distributed by Google as part of the WebM Project.

Google hereby grants to you a perpetual, worldwide, non-exclusive, no-charge,
royalty-free, irrevocable (except as stated in this section) patent license to
make, have made, use, offer to sell, sell, import, transfer, and otherwise
run, modify and propagate the contents of these implementations of WebM, where
such license applies only to those patent claims, both currently owned by
Google and acquired in the future, licensable by Google that are necessarily
infringed by these implementations of WebM. This grant does not include claims
that would be infringed only as a consequence of further modification of these
implementations. If you or your agent or exclusive licensee institute or order
or agree to the institution of patent litigation or any other patent
enforcement activity against any entity (including a cross-claim or
counterclaim in a lawsuit) alleging that any of these implementations of WebM
or any code incorporated within any of these implementations of WebM
constitutes direct or contributory patent infringement, or inducement of
patent infringement, then any patent rights granted to you under this License
for these implementations of WebM shall terminate as of the date such
litigation is filed.
```

## 系统提供的能力

HarmonyOS SDK、ArkUI、Media Kit、AVSession Kit、Background Tasks Kit、ArkData 等能力由 HarmonyOS SDK 或设备系统提供，遵循其各自的许可条款，不作为本应用安装包内独立分发的第三方组件列入本清单。

## 仅用于开发和资源生成的工具

| 工具或依赖 | 用途 | 是否随应用分发 |
| --- | --- | --- |
| Hypium | 本地单元测试 | 否 |
| Hamock | 本地测试与模拟 | 否 |
| `tools/` 下的 Node.js 依赖 | 图标及资源生成 | 否 |

上述工具仍分别遵循其自身许可证。本清单不改变或替代其许可条款。

## 维护说明

添加或升级依赖、复制第三方源码、字体、图标或音频，引入原生静态库或动态库，或改变打包方式时，发布前必须重新核对安装包，并同步更新本清单和应用内“开源软件许可”页面。生成发布源码包时必须包含或能够取得对应版本的子模块源码及其许可文件。
