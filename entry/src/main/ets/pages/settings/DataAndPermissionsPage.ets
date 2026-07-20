import { ComplianceDocumentPage, ComplianceSection } from './ComplianceDocumentPage';

const DATA_SECTIONS: Array<ComplianceSection> = [
  new ComplianceSection('数据存储概览', [
    '本版本的音乐库、媒体缓存、播放数据和应用设置均保存在用户设备中，不会上传至开发者或第三方服务器。',
    '音乐库：所选文件的访问标识、文件名、音乐标签、时长及可用状态。',
    '媒体缓存：从本地音乐提取并缩放的封面及其主题颜色。',
    '播放数据：播放列表、当前队列、播放状态和用户启用的播放进度记录。',
    '应用设置：外观、播放行为、导航顺序及其他偏好。'
  ]),
  new ComplianceSection('文件持续访问权限', [
    '用途：保留对用户通过系统文件选择器主动选择的音乐文件的读取授权，使应用重启后仍可播放。',
    '应用不会借此扫描未选择的文件，也不会修改或删除原始音乐文件。',
    '清空音乐库时会请求撤销对应文件的持续读取授权。'
  ]),
  new ComplianceSection('后台运行权限', [
    '用途：仅在播放音乐需要时保持后台音频播放，并支持系统媒体控制。',
    '停止播放且不再需要后台播放时，应用会停止相应后台任务。'
  ]),
  new ComplianceSection('振动权限', [
    '用途：在部分交互达到操作阈值时提供轻微触感反馈。',
    '振动不用于识别用户或收集设备信息。'
  ]),
  new ComplianceSection('网络与备份', [
    '本版本不申请网络访问权限，也不与开发者或第三方服务器通信。',
    '本版本关闭应用数据的系统备份，音乐库、设置和缓存不会通过本应用参与系统备份。'
  ]),
  new ComplianceSection('用户控制', [
    '用户可以在“音乐库”页面清空音乐库。该操作会删除音乐记录和封面缓存、请求撤销对应文件授权，但保留原始音乐文件。',
    '用户可以在系统设置中撤销应用权限。撤销权限可能使相应功能无法使用。',
    '卸载应用会由系统删除应用的本地数据。'
  ])
];

@Component
export struct DataAndPermissionsPage {
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();

  build() {
    ComplianceDocumentPage({
      sections: DATA_SECTIONS,
      topInset: this.topInset,
      bottomInset: this.bottomInset,
      scroller: this.scroller
    })
  }
}
