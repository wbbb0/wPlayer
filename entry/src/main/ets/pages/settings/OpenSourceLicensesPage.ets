import { ComplianceDocumentPage, ComplianceSection } from './ComplianceDocumentPage';

const LICENSE_SECTIONS: Array<ComplianceSection> = [
  new ComplianceSection('项目许可', [
    '项目：wPlayer',
    'Copyright © 2026 韩旭龙',
    '本项目依据 GNU General Public License version 3（仅此版本，GPL-3.0-only）授权。该许可证允许使用、研究、修改和再分发本项目，包括商业使用；对外分发修改版或衍生作品时须遵守 GPL 的相应条款。'
  ]),
  new ComplianceSection('许可证与对应源代码', [
    '完整许可证正文：https://www.gnu.org/licenses/gpl-3.0.html',
    '正式发布版本的对应源代码和构建文件将在以下项目仓库提供：https://github.com/wbbb0/wPlayer',
    '发布版本以仓库中的对应版本标签为准。签名证书、私钥、密码和开发者机器上的签名配置不属于对应源代码。'
  ]),
  new ComplianceSection('第三方软件', [
    '本应用随原生库分发 libwebp 1.6.0，用于将缩放后的封面缓存编码为有损 WebP 并保留透明度。libwebp 源码来自 WebM Project：https://chromium.googlesource.com/webm/libwebp/',
    'libwebp 依据 BSD 3-Clause 许可证提供，并包含附加专利授权。本应用对 libwebp 的使用不表示 Google 或其贡献者对 wPlayer 的认可或推广。',
    'HarmonyOS 系统组件和系统能力由设备系统提供，并遵循其各自的许可条款。'
  ]),
  new ComplianceSection('libwebp — Copyright and license', [
    'Copyright (c) 2010, Google Inc. All rights reserved.',
    'Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:',
    'Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.',
    'Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.',
    'Neither the name of Google nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.',
    'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.'
  ]),
  new ComplianceSection('libwebp — Additional IP Rights Grant (Patents)', [
    '"These implementations" means the copyrightable works that implement the WebM codecs distributed by Google as part of the WebM Project.',
    'Google hereby grants to you a perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable (except as stated in this section) patent license to make, have made, use, offer to sell, sell, import, transfer, and otherwise run, modify and propagate the contents of these implementations of WebM, where such license applies only to those patent claims, both currently owned by Google and acquired in the future, licensable by Google that are necessarily infringed by these implementations of WebM. This grant does not include claims that would be infringed only as a consequence of further modification of these implementations. If you or your agent or exclusive licensee institute or order or agree to the institution of patent litigation or any other patent enforcement activity against any entity (including a cross-claim or counterclaim in a lawsuit) alleging that any of these implementations of WebM or any code incorporated within any of these implementations of WebM constitutes direct or contributory patent infringement, or inducement of patent infringement, then any patent rights granted to you under this License for these implementations of WebM shall terminate as of the date such litigation is filed.'
  ]),
  new ComplianceSection('无担保声明', [
    '本项目按 GNU GPL 第 3 版所述方式提供，不附带任何明示或默示担保。完整权利与义务以许可证正文为准。'
  ])
];

@Component
export struct OpenSourceLicensesPage {
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();

  build() {
    ComplianceDocumentPage({
      sections: LICENSE_SECTIONS,
      topInset: this.topInset,
      bottomInset: this.bottomInset,
      scroller: this.scroller
    })
  }
}
