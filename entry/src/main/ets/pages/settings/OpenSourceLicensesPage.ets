import { ComplianceDocumentPage, ComplianceSection } from './ComplianceDocumentPage';

const LICENSE_SECTIONS: Array<ComplianceSection> = [
  new ComplianceSection('项目许可', [
    '项目：w音乐（wPlayer）',
    'Copyright © 2026 韩旭龙',
    '本项目依据 GNU General Public License version 3（仅此版本，GPL-3.0-only）授权。该许可证允许使用、研究、修改和再分发本项目，包括商业使用；对外分发修改版或衍生作品时须遵守 GPL 的相应条款。'
  ]),
  new ComplianceSection('许可证与对应源代码', [
    '完整许可证正文：https://www.gnu.org/licenses/gpl-3.0.html',
    '正式发布版本的对应源代码和构建文件将在以下项目仓库提供：https://github.com/wbbb0/wPlayer',
    '发布版本以仓库中的对应版本标签为准。签名证书、私钥、密码和开发者机器上的签名配置不属于对应源代码。'
  ]),
  new ComplianceSection('第三方软件', [
    '依据当前应用模块的依赖和打包配置核查，本版本未随应用分发需要单独列示的第三方运行时开源组件。',
    'HarmonyOS 系统组件和系统能力由设备系统提供，并遵循其各自的许可条款。'
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
