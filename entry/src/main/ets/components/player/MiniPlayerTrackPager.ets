import { PlayerStore, QueueEntry } from '../../playback/model/PlaybackModels';
import { LayoutLength } from '../layout/LayoutLength';
import { MiniPlayerBinding } from './MiniPlayerBinding';
import { PlayerTrackMarquee } from './PlayerTrackMarquee';

@Component
export struct MiniPlayerTrackPager {
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink binding: MiniPlayerBinding;
  @Prop marqueeActive: boolean = true;
  @Prop followsSwipeOffset: boolean = true;

  private currentArtistLabel(): string {
    return this.playerStore.currentTrack?.artistDisplay || '选择一首音乐';
  }

  private pageWidth(): number {
    return Math.max(1, this.binding.trackPagerViewportWidth);
  }

  private recordViewportWidth(newValue: Area): void {
    const width = LayoutLength.toNumber(newValue.width, this.binding.trackPagerViewportWidth);
    if (width > 0 && Math.abs(width - this.binding.trackPagerViewportWidth) >= 0.5) {
      this.binding.trackPagerViewportWidth = width;
    }
  }

  @Builder
  private CurrentTrack() {
    Column({ space: 2 }) {
      PlayerTrackMarquee({
        playerStore: this.playerStore,
        active: this.marqueeActive,
        titleColor: $r('app.color.text_primary'),
        titleSize: 15,
        titleWeight: FontWeight.Medium
      })

      Text(this.currentArtistLabel())
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
  }

  @Builder
  private FrozenTrack(entry: QueueEntry | undefined) {
    Column({ space: 2 }) {
      if (entry !== undefined) {
        Text(entry.track.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(entry.track.artistDisplay || '未知艺术家')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .width(this.pageWidth())
    .height('100%')
  }

  @Builder
  private FrozenPages() {
    Row({ space: 0 }) {
      this.FrozenTrack(this.binding.trackPagerPrevious)
      this.FrozenTrack(this.binding.trackPagerCurrent)
      this.FrozenTrack(this.binding.trackPagerNext)
    }
    .width(this.pageWidth() * 3)
    .height('100%')
    .translate({
      x: (this.followsSwipeOffset ? this.binding.offsetX : 0) - this.pageWidth()
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.binding.trackPagerActive) {
        this.FrozenPages()
      } else {
        this.CurrentTrack()
      }
    }
    .width('100%')
    .height(48)
    .clip(true)
    .onAreaChange((_oldValue: Area, newValue: Area) => this.recordViewportWidth(newValue))
  }
}
