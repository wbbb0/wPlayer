export class M3uImportPolicy {
  static errorMessage(entryCount: number, matchedCount: number,
    replacingExisting: boolean, creatingPlaylist: boolean): string {
    if (entryCount === 0) {
      if (replacingExisting) {
        return '文件中没有可导入的歌曲条目，已保留原播放列表';
      }
      if (creatingPlaylist) {
        return '文件中没有可导入的歌曲条目，未创建播放列表';
      }
      return '';
    }
    if (matchedCount === 0 && replacingExisting) {
      return '文件中的歌曲均未在音乐库中匹配，已保留原播放列表';
    }
    if (matchedCount === 0 && creatingPlaylist) {
      return '文件中的歌曲均未在音乐库中匹配，未创建播放列表';
    }
    return '';
  }
}
