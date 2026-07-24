import { ComplianceDocumentPage, ComplianceSection } from './ComplianceDocumentPage';

const ABOUT_SECTIONS: Array<ComplianceSection> = [
  new ComplianceSection('关于 w播放器', [
    '英文名称：wPlayer',
    'w播放器是为希望获得干净、流畅且专注的本地音乐体验的用户而开发的播放器，以简洁设计、快速响应和高性能播放为目标。',
    '应用专注于管理和播放用户主动选择的本地音乐，不提供、下载或推荐任何音乐内容。'
  ]),
  new ComplianceSection('产品原则', [
    '保持纯粹：不含账号、广告、应用内购买、使用统计或与播放无关的内容。',
    '尊重数据：首版完全离线，音乐与播放数据保存在用户设备中，不会发送给开发者或第三方服务器。',
    '专注体验：围绕本地音乐的导入、整理和播放持续改进性能、稳定性与交互体验。'
  ]),
  new ComplianceSection('开发者与联系', [
    '开发者：韩旭龙',
    '联系邮箱：wbbb0@outlook.com',
    '开发者主页：https://github.com/wbbb0'
  ]),
  new ComplianceSection('开源项目', [
    'w播放器以 GNU General Public License version 3（GPL-3.0-only）发布。',
    '正式发布版本的对应源代码和构建文件将在项目仓库提供：https://github.com/wbbb0/wPlayer'
  ]),
  new ComplianceSection('版权声明', [
    'Copyright © 2026 韩旭龙',
    '音乐、封面及其他媒体内容的权利归各自权利人所有。w播放器仅处理用户主动选择并有权使用的本地文件。'
  ])
];

@Component
export struct AboutPage {
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();

  build() {
    ComplianceDocumentPage({
      sections: ABOUT_SECTIONS,
      topInset: this.topInset,
      bottomInset: this.bottomInset,
      scroller: this.scroller
    })
  }
}
