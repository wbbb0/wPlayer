export class DynamicBackgroundV3Spec {
  /**
   * 普通背景运动的实际提交帧率。越低越省 GPU，但纹理旋转和漂移会更有跳帧感。
   * 不会限制 ArkUI、歌词走马灯或应用其他动画的帧率。
   */
  static readonly FRAME_RATE: number = 10;

  /**
   * 切换封面时交叉渐变的临时提交帧率。渐变结束后自动恢复 FRAME_RATE。
   * 提高可让切歌过渡更顺滑，但会在 ARTWORK_TRANSITION_DURATION_SECONDS 期间增加 GPU 负载。
   */
  static readonly TRANSITION_FRAME_RATE: number = 60;

  /** 新旧封面背景完成交叉渐变所需的秒数；越大过渡越慢、越柔和。 */
  static readonly ARTWORK_TRANSITION_DURATION_SECONDS: number = 1;

  /**
   * 第一张背景从透明到完全显示的时长，相对于 ARTWORK_TRANSITION_DURATION_SECONDS 的比例。
   * 0.5 表示首次淡入只使用切歌渐变一半的时间；淡入期间使用 TRANSITION_FRAME_RATE。
   */
  static readonly INITIAL_REVEAL_DURATION_RATIO: number = 0.5;

  /**
   * 相对参考网页的离屏渲染比例，是影响 GPU 像素量最大的参数。
   * 越低越省电、画面越柔和；越高细节越多、模糊成本越高。原生端允许的最低值为 0.05。
   */
  static readonly HTML_RENDER_SCALE: number = 0.5;

  /**
   * 计算原生缓冲区尺寸时允许使用的最大设备像素比。
   * 用于避免高密度屏幕按完整物理分辨率渲染；越低通常越省 GPU。
   */
  static readonly MAX_DEVICE_PIXEL_RATIO: number = 1.5;

  /** 页面首次打开时的纹理运动速度倍率；1 表示 aadishv/html-music 参考实现的原速。 */
  static readonly DEFAULT_SPEED: number = 1;

  /**
   * 中心扭曲的旋转角度，单位为弧度；负值和正值代表相反的旋转方向。
   * 当前原生 shader 使用同名硬编码值，单独修改此处不会改变画面。
   */
  static readonly TWIST_ANGLE_RADIANS: number = -3.25;

  /**
   * 扭曲影响的归一化半径；越大，画面更靠外的区域也会参与扭曲。
   * 当前原生 shader 使用同名硬编码值，单独修改此处不会改变画面。
   */
  static readonly TWIST_RADIUS: number = 0.90;

  /**
   * 最终页面物理像素中的目标 Kawase 模糊半径。
   * 原生端会乘以 NativeWindow 的实际缓冲缩放比例，换算成离屏缓冲像素；
   * 因此只修改 HTML_RENDER_SCALE 时无需再同步调整此值。
   * 越大色块越柔和、细节越少，0 表示仅保留每次 pass 的最小采样偏移。
   */
  static readonly BLUR_RADIUS: number = 128;

  /**
   * Kawase 模糊迭代次数；每增加一次都会多一次全屏离屏绘制。
   * 当前原生 renderer 使用同名硬编码值，单独修改此处不会改变画面。
   */
  static readonly BLUR_PASSES: number = 9;

  /**
   * 最终颜色饱和度；1 为原色，大于 1 会强化颜色，小于 1 会趋向灰色。
   * 当前原生 shader 使用同名硬编码值，单独修改此处不会改变画面。
   */
  static readonly SATURATION: number = 2.75;

  /**
   * 最终颜色对比度；1 不改变对比度，增大后亮暗分离更明显。
   * 当前原生 shader 使用同名硬编码值，单独修改此处不会改变画面。
   */
  static readonly CONTRAST: number = 1.12;

  /**
   * 最终整体亮度倍率；1 保持原亮度，小于 1 会压暗背景。
   * 当前原生 shader 使用同名硬编码值，单独修改此处不会改变画面。
   */
  static readonly BRIGHTNESS: number = 0.90;

  /**
   * 后三层纹理覆盖前一层时的混合强度；越大层间色彩变化越明显。
   * 当前原生 shader 使用同名硬编码值，单独修改此处不会改变画面。
   */
  static readonly MIX_STRENGTH: number = 0.84;

  /**
   * 模拟网页 canvas n% 尺寸的过扫描倍率，用于把模糊后的边缘裁到屏幕外。
   * 1 表示不裁切；数值越大，看到的区域越靠近背景中心。
   * 此值作为 shader uniform 传入，只改变采样坐标，不增加采样次数，性能影响可忽略。
   */
  static readonly OVERSCAN: number = 1.5;

  /**
   * 上传给原生 renderer 前采用的方形工作纹理边长。
   * 此值会同时传给原生重采样器，并用于限制 ArkTS 解码尺寸。
   * 它只改变输入纹理清晰度和内存占用，不改变四层纹理的几何大小。
   */
  static readonly WORK_TEXTURE_SIZE: number = 256;

  /** 调试参数面板的最大宽度，仅影响页面布局，不影响背景渲染。 */
  static readonly CONTROL_PANEL_MAX_WIDTH: number = 560;

  /** 调试参数面板与页面边缘的间距，仅影响页面布局。 */
  static readonly CONTROL_PANEL_MARGIN: number = 18;

  /**
   * 把网页的 renderScale 和 capped DPR 换算为 NativeWindow 相对物理尺寸的缩放值。
   * 例如高密度屏会先把 DPR 限制到 MAX_DEVICE_PIXEL_RATIO，再应用 HTML_RENDER_SCALE。
   */
  static nativeRenderScale(density: number): number {
    if (density <= 0) {
      return DynamicBackgroundV3Spec.HTML_RENDER_SCALE;
    }
    return DynamicBackgroundV3Spec.HTML_RENDER_SCALE *
      Math.min(density, DynamicBackgroundV3Spec.MAX_DEVICE_PIXEL_RATIO) / density;
  }
}
