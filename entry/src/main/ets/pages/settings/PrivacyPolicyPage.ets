import { ComplianceDocumentPage, ComplianceSection } from './ComplianceDocumentPage';

const PRIVACY_SECTIONS: Array<ComplianceSection> = [
  new ComplianceSection('适用范围', [
    '生效日期：2026 年 7 月 20 日',
    '本政策适用于纯离线版本的 w播放器（英文名称 wPlayer）。开发者及运营者为韩旭龙，联系邮箱为 wbbb0@outlook.com。'
  ]),
  new ComplianceSection('设备本地处理的数据', [
    '当用户通过系统文件选择器添加音乐时，应用会在设备本地处理所选文件的访问标识、文件名、音乐标签、时长和内嵌封面。',
    '应用会在设备本地保存音乐库记录、播放列表、播放状态与进度，以及用户选择的应用设置。',
    '上述数据仅用于展示和管理本地音乐、恢复播放状态及提供用户启用的应用功能。相关处理在用户设备上完成，不代表开发者收集或持有这些数据。'
  ]),
  new ComplianceSection('网络与第三方传输', [
    '本版本不申请网络访问权限，不访问互联网，也不包含账号、广告、使用统计、崩溃上传、在线更新检查、在线歌词或在线封面功能。',
    '应用不会将音乐文件、音乐标签、封面、播放列表、播放记录或设置发送给开发者或第三方服务器，开发者无法访问这些数据。'
  ]),
  new ComplianceSection('文件访问', [
    '应用仅访问用户通过系统文件选择器主动选择的音频文件。为便于应用重启后继续播放，应用会申请保留对这些文件的读取授权。',
    '应用不会扫描全部存储空间，也不会因清空音乐库而删除原始音乐文件。文件被移动、删除或授权被撤销后，应用可能无法继续播放该文件。'
  ]),
  new ComplianceSection('保存与删除', [
    '音乐库、封面缓存、播放数据和设置保存在应用的本地存储中，通常保留至用户主动清除相应数据或卸载应用。',
    '清空音乐库会删除应用中的音乐记录和封面缓存，并请求撤销相应文件的持续读取授权，但不会删除原始音乐文件。',
    '本版本关闭应用数据的系统备份。卸载应用后，本地数据由系统删除。'
  ]),
  new ComplianceSection('未成年人', [
    'w播放器面向普通用户，不以未成年人为专门服务对象。未成年人应在监护人指导下使用本应用并选择本地文件。'
  ]),
  new ComplianceSection('变更与联系', [
    '如果未来版本增加联网或其他会实质改变信息处理范围的功能，我们会在功能启用前更新本政策并提供必要提示。',
    '如对本政策或本地数据处理有疑问，请联系：wbbb0@outlook.com。'
  ])
];

@Component
export struct PrivacyPolicyPage {
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();

  build() {
    ComplianceDocumentPage({
      sections: PRIVACY_SECTIONS,
      topInset: this.topInset,
      bottomInset: this.bottomInset,
      scroller: this.scroller
    })
  }
}
