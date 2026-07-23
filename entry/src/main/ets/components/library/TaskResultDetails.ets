import { LibraryPagingPolicy } from '../../library/store/LibraryPagingPolicy';

export enum TaskResultTone {
  NORMAL = 'normal',
  SUCCESS = 'success',
  ERROR = 'error'
}

export interface TaskResultDetailItem {
  key: string;
  status: string;
  title: string;
  reason: string;
  uri: string;
  secondaryUri?: string;
  recordLabel?: string;
  tone: TaskResultTone;
}

export interface TaskResultDetailSection {
  key: string;
  title: string;
  emptyText: string;
  items: Array<TaskResultDetailItem>;
  tone: TaskResultTone;
}

@Reusable
@Component
struct TaskResultDetailListItem {
  @Prop item: TaskResultDetailItem;

  private readableUri(uri: string): string {
    try {
      return decodeURIComponent(uri);
    } catch (_error) {
      return uri;
    }
  }

  private toneColor(tone: TaskResultTone): Resource {
    if (tone === TaskResultTone.ERROR) {
      return $r('app.color.message_error');
    }
    if (tone === TaskResultTone.SUCCESS) {
      return $r('app.color.message_success');
    }
    return $r('app.color.text_secondary');
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        Text(this.item.status)
          .fontSize(12)
          .fontColor(this.toneColor(this.item.tone))
        Text(this.readableUri(this.item.title))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      if (this.item.reason.length > 0) {
        Text(this.item.reason)
          .fontSize(12)
          .fontColor(this.item.tone === TaskResultTone.ERROR ?
            $r('app.color.message_error') : $r('app.color.text_secondary'))
          .width('100%')
      }
      Text(`文件 URI：${this.readableUri(this.item.uri)}`)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .maxLines(4)
      if (this.item.secondaryUri !== undefined) {
        Text(`已有文件 URI：${this.readableUri(this.item.secondaryUri)}`)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .maxLines(4)
      }
      if (this.item.recordLabel !== undefined) {
        Text(this.item.recordLabel)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.glass_surface'))
  }
}

@Component
export struct TaskResultDetails {
  @Prop title: string = '';
  @Prop emptyText: string = '';
  @Prop sections: Array<TaskResultDetailSection> = [];
  @State expandedKey: string = '';

  private totalCount(): number {
    let count = 0;
    for (let index = 0; index < this.sections.length; index += 1) {
      count += this.sections[index].items.length;
    }
    return count;
  }

  private toggleSection(key: string): void {
    this.expandedKey = this.expandedKey === key ? '' : key;
  }

  private sectionColor(section: TaskResultDetailSection): Resource {
    if (section.tone === TaskResultTone.ERROR) {
      return $r('app.color.message_error');
    }
    if (section.tone === TaskResultTone.SUCCESS) {
      return $r('app.color.message_success');
    }
    return $r('app.color.text_primary');
  }

  @Builder
  private SectionHeader(section: TaskResultDetailSection) {
    Button() {
      Row({ space: 12 }) {
        Text(section.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.sectionColor(section))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
        Text(`${section.items.length}`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .fontFeature('tnum')
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.text_tertiary')])
          .rotate({ angle: this.expandedKey === section.key ? 90 : 0 })
      }
      .width('100%')
      .height(48)
      .padding({ left: 14, right: 14 })
    }
    .width('100%')
    .height(48)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .backgroundColor($r('app.color.glass_surface'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, {
      adaptiveColor: AdaptiveColor.AVERAGE,
      policy: BlurStyleActivePolicy.ALWAYS_ACTIVE,
      scale: 1
    })
    .borderRadius(16)
    .accessibilityText(`${section.title}，${section.items.length} 项`)
    .onClick(() => this.toggleSection(section.key))
  }

  build() {
    Column({ space: 10 }) {
      if (this.totalCount() > 0) {
        if (this.title.length > 0) {
          Text(this.title)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
        }
        List({ space: 10 }) {
          ForEach(this.sections, (section: TaskResultDetailSection) => {
            if (section.items.length > 0) {
              ListItemGroup({ header: this.SectionHeader(section) }) {
                if (this.expandedKey === section.key) {
                  ForEach(section.items, (item: TaskResultDetailItem) => {
                    ListItem() {
                      TaskResultDetailListItem({ item: item })
                        .reuseId('task_result_detail')
                    }
                  }, (item: TaskResultDetailItem) => item.key)
                }
              }
            }
          }, (section: TaskResultDetailSection) => section.key)
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .sticky(StickyStyle.Header)
        .cachedCount(LibraryPagingPolicy.TRACK_PAGE_SIZE, true)
      } else if (this.emptyText.length > 0) {
        Text(this.emptyText)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
    }
    .width('100%')
  }
}
