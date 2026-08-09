import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageScrollBehavior, PageScrollContentBehavior } from '../../components/layout/PageScrollBehavior';
import {
  SettingsLinkItem,
  SettingsSelectItem,
  SettingsToggleItem
} from '../../components/settings/SettingsItem';
import { AppSettingsStore } from '../../settings/AppSettingsStore';
import {
  ThumbnailBenchmarkMethod,
  ThumbnailBenchmarkOptions,
  ThumbnailBenchmarkPolicy
} from '../../library/artwork/ThumbnailBenchmarkPolicy';
import {
  ThumbnailBenchmarkMethodResult,
  ThumbnailBenchmarkProgress,
  ThumbnailBenchmarkReport
} from '../../library/artwork/ThumbnailBenchmarkRunner';

@Component
export struct DebugPage {
  @ObjectLink settingsStore: AppSettingsStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  onDemoLibraryChange: (value: boolean) => void = (_value: boolean): void => {};
  onOpenThumbnailBenchmark: () => void = (): void => {};

  build() {
    Scroll(this.scroller) {
      Column({ space: 20 }) {
        Column() {
          Text('数据')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ left: 6, bottom: 8 })
          Column() {
            SettingsToggleItem({
              symbol: $r('sys.symbol.opticaldisc'),
              title: '演示音乐库',
              description: '显示截图用虚构歌曲、播放列表、歌词和播放队列',
              isOn: this.settingsStore.demoLibraryEnabled,
              onChange: this.onDemoLibraryChange
            })
          }
          .width('100%')
          .borderRadius(20)
          .backgroundColor($r('app.color.glass_surface'))
        }
        .width('100%')
        Column() {
          Text('性能测试')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ left: 6, bottom: 8 })
          Column() {
            SettingsLinkItem({
              symbol: $r('sys.symbol.info_circle'),
              title: 'Thumbnail 生成速度测试',
              description: '对比系统 JPEG 与 C++ WebP 编码性能',
              onActivate: this.onOpenThumbnailBenchmark
            })
          }
          .width('100%')
          .borderRadius(20)
          .backgroundColor($r('app.color.glass_surface'))
        }
        .width('100%')
      }
      .width('100%')
      .padding({
        left: 24,
        right: 24,
        top: PageLayoutSpec.primaryContentStart(this.topInset),
        bottom: PageLayoutSpec.contentEnd(this.bottomInset)
      })
      .attributeModifier(new PageScrollContentBehavior())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .attributeModifier(new PageScrollBehavior())
  }
}

@Component
export struct ThumbnailBenchmarkPage {
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  onRunThumbnailBenchmark: (
    options: ThumbnailBenchmarkOptions,
    onProgress: (progress: ThumbnailBenchmarkProgress) => void
  ) => Promise<ThumbnailBenchmarkReport> = (
    _options: ThumbnailBenchmarkOptions,
    _onProgress: (progress: ThumbnailBenchmarkProgress) => void
  ): Promise<ThumbnailBenchmarkReport> => Promise.reject(new Error('Benchmark runner unavailable'));
  @State systemJpegSelected: boolean = true;
  @State cppWebPSelected: boolean = true;
  @State resolutionIndex: number = 0;
  @State sampleCountText: string = `${ThumbnailBenchmarkPolicy.DEFAULT_SAMPLE_COUNT}`;
  @State benchmarkRunning: boolean = false;
  @State benchmarkStatus: string = '';
  @State benchmarkError: string = '';
  @State benchmarkReport?: ThumbnailBenchmarkReport = undefined;

  @Builder
  private SectionTitle(title: string) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ left: 6, bottom: 8 })
  }

  @Builder
  private MethodCheckbox(method: ThumbnailBenchmarkMethod, title: string, description: string) {
    Row({ space: 14 }) {
      Checkbox({ name: title, group: 'thumbnail_benchmark_methods' })
        .select(method === ThumbnailBenchmarkMethod.SYSTEM_JPEG ?
          this.systemJpegSelected : this.cppWebPSelected)
        .selectedColor($r('app.color.theme_accent'))
        .enabled(!this.benchmarkRunning)
        .onChange((value: boolean): void => {
          if (method === ThumbnailBenchmarkMethod.SYSTEM_JPEG) {
            this.systemJpegSelected = value;
          } else {
            this.cppWebPSelected = value;
          }
        })
      Column({ space: 3 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(description)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .constraintSize({ minHeight: 68 })
    .padding({ left: 18, right: 18, top: 10, bottom: 10 })
  }

  private selectedMethods(): Array<ThumbnailBenchmarkMethod> {
    const methods: Array<ThumbnailBenchmarkMethod> = [];
    if (this.systemJpegSelected) {
      methods.push(ThumbnailBenchmarkMethod.SYSTEM_JPEG);
    }
    if (this.cppWebPSelected) {
      methods.push(ThumbnailBenchmarkMethod.CPP_WEBP);
    }
    return methods;
  }

  private async runThumbnailBenchmark(): Promise<void> {
    const methods = this.selectedMethods();
    if (methods.length === 0) {
      this.benchmarkError = '请至少勾选一种 thumbnail 类型';
      return;
    }
    const sampleCount = ThumbnailBenchmarkPolicy.normalizeSampleCount(Number(this.sampleCountText));
    this.sampleCountText = `${sampleCount}`;
    this.benchmarkRunning = true;
    this.benchmarkError = '';
    this.benchmarkReport = undefined;
    this.benchmarkStatus = '正在准备随机歌曲样本…';
    try {
      this.benchmarkReport = await this.onRunThumbnailBenchmark({
        methods: methods,
        maxEdge: ThumbnailBenchmarkPolicy.RESOLUTIONS[this.resolutionIndex],
        sampleCount: sampleCount
      }, (progress: ThumbnailBenchmarkProgress): void => {
        this.benchmarkStatus = `${this.methodName(progress.method)} · ` +
          `${progress.completed}/${progress.total}`;
      });
      this.benchmarkStatus = '测试完成';
    } catch (error) {
      this.benchmarkError = error instanceof Error ? error.message : `${error}`;
      this.benchmarkStatus = '';
    } finally {
      this.benchmarkRunning = false;
    }
  }

  private methodName(method: ThumbnailBenchmarkMethod): string {
    return method === ThumbnailBenchmarkMethod.SYSTEM_JPEG ? '系统 JPEG' : 'C++ WebP';
  }

  private duration(value: number): string {
    return `${value.toFixed(2)} ms`;
  }

  @Builder
  private BenchmarkResults() {
    if (this.benchmarkReport !== undefined) {
      Column({ space: 10 }) {
        Text(`最长边 ${this.benchmarkReport.maxEdge}px · 随机样本 ` +
          `${this.benchmarkReport.sampledCount}/${this.benchmarkReport.requestedCount}`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Column({ space: 5 }) {
          Text('共享准备阶段')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(`读取平均 ${this.duration(this.benchmarkReport.averageReadMs)} · ` +
            `解码平均 ${this.duration(this.benchmarkReport.averageDecodeMs)}`)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
          Text(`缩放平均 ${this.duration(this.benchmarkReport.averageScaleMs)} · ` +
            `准备合计平均 ${this.duration(this.benchmarkReport.averagePreparationMs)}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(14)
        .borderRadius(14)
        .backgroundColor($r('app.color.glass_surface'))
        ForEach(this.benchmarkReport.results, (result: ThumbnailBenchmarkMethodResult) => {
          Column({ space: 5 }) {
            Text(this.methodName(result.method))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text(`编码平均 ${this.duration(result.averageEncodingMs)}`)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            Text(`准备+编码平均 ${this.duration(result.averageTotalMs)} · ` +
              `成功 ${result.successCount} · 失败 ${result.failureCount}`)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(14)
          .borderRadius(14)
          .backgroundColor($r('app.color.glass_surface'))
        }, (result: ThumbnailBenchmarkMethodResult): string => result.method)
      }
      .width('100%')
      .margin({ top: 12 })
    }
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 20 }) {
        Column() {
          this.SectionTitle('Thumbnail 生成速度')
          Column() {
            this.MethodCheckbox(
              ThumbnailBenchmarkMethod.SYSTEM_JPEG,
              '系统 JPEG 编码器',
              'Image Kit ImagePacker，质量 84'
            )
            Divider().color($r('app.color.text_tertiary')).opacity(0.3)
            this.MethodCheckbox(
              ThumbnailBenchmarkMethod.CPP_WEBP,
              'C++ WebP 编码器',
              '当前封面缓存使用的 libwebp，质量 84'
            )
            Divider().color($r('app.color.text_tertiary')).opacity(0.3)
            SettingsSelectItem({
              title: 'Thumbnail 分辨率',
              description: '按原比例缩放后的最长边',
              options: ThumbnailBenchmarkPolicy.RESOLUTIONS.map((value: number): string => `${value}`),
              selected: this.resolutionIndex,
              value: `${ThumbnailBenchmarkPolicy.RESOLUTIONS[this.resolutionIndex]} px`,
              onSelect: (index: number): void => {
                this.resolutionIndex = index;
              }
            })
            Divider().color($r('app.color.text_tertiary')).opacity(0.3)
            Row({ space: 14 }) {
              Column({ space: 3 }) {
                Text('随机歌曲数量')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text(`范围 1–${ThumbnailBenchmarkPolicy.MAX_SAMPLE_COUNT}；缺少封面会计入失败`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              TextInput({ text: this.sampleCountText })
                .type(InputType.Number)
                .width(92)
                .enabled(!this.benchmarkRunning)
                .onChange((value: string): void => {
                  this.sampleCountText = value;
                })
            }
            .width('100%')
            .constraintSize({ minHeight: 76 })
            .padding({ left: 18, right: 14, top: 12, bottom: 12 })
          }
          .width('100%')
          .borderRadius(20)
          .backgroundColor($r('app.color.glass_surface'))
          Button(this.benchmarkRunning ? '正在测试…' : '开始测试')
            .width('100%')
            .margin({ top: 14 })
            .enabled(!this.benchmarkRunning)
            .onClick((): void => {
              this.runThumbnailBenchmark();
            })
          if (this.benchmarkStatus.length > 0) {
            Text(this.benchmarkStatus)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .margin({ top: 10 })
          }
          if (this.benchmarkError.length > 0) {
            Text(this.benchmarkError)
              .fontSize(13)
              .fontColor(Color.Red)
              .width('100%')
              .margin({ top: 10 })
          }
          this.BenchmarkResults()
        }
        .width('100%')
      }
      .width('100%')
      .padding({
        left: 24,
        right: 24,
        top: PageLayoutSpec.primaryContentStart(this.topInset),
        bottom: PageLayoutSpec.contentEnd(this.bottomInset)
      })
      .attributeModifier(new PageScrollContentBehavior())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .attributeModifier(new PageScrollBehavior())
  }
}
