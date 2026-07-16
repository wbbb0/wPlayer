import { LibraryEmptyState } from '../../components/library/LibraryEmptyState';
import { LibraryStore } from '../../library/store/LibraryStore';

@Component
export struct PlaylistsPage {
  @ObjectLink store: LibraryStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();

  build() {
    LibraryEmptyState({
      symbol: $r('sys.symbol.music_note_list_fill'),
      title: '还没有播放列表',
      description: '播放列表功能将在播放链路完成后接入',
      topInset: this.topInset,
      bottomInset: this.bottomInset,
      scroller: this.scroller
    })
  }
}
