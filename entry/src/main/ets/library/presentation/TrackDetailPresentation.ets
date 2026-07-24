import {
  AvailabilityState,
  TrackDetail,
  TrackRawTag
} from '../model/LibraryModels';

export enum DetailRenderer {
  TEXT = 0,
  URI = 1,
  MONOSPACE = 2,
  MULTI_VALUE = 3,
  LYRICS = 4
}

export enum DetailFormatter {
  TEXT = 0,
  UNKNOWN_TEXT = 1,
  URI = 2,
  FILE_SIZE = 3,
  DATE_TIME = 4,
  UPPERCASE = 5,
  DURATION = 6,
  SAMPLE_RATE = 7,
  CHANNEL_COUNT = 8,
  BIT_DEPTH = 9,
  BIT_RATE = 10,
  AVAILABILITY = 11,
  AUTHORIZATION = 12,
  LYRIC_LINE_COUNT = 13
}

export enum DetailAction {
  COPY_EXACT = 0
}

export interface DetailRowModel {
  id: string;
  sectionId: string;
  order: number;
  label: string;
  displayValue: string;
  copyValue: string;
  renderer: DetailRenderer;
  actions: Array<DetailAction>;
}

export interface DetailSectionModel {
  id: string;
  title: string;
  rows: Array<DetailRowModel>;
}

export interface DetailPageModel {
  sections: Array<DetailSectionModel>;
}

export interface DetailSectionRule {
  id: string;
  title: string;
  order: number;
  showsRowCount: boolean;
}

export interface TagPresentationRule {
  label: string;
  sectionId: string;
  order: number;
  renderer: DetailRenderer;
  formatter: DetailFormatter;
}

enum DetailFieldSource {
  FILE_NAME = 0,
  FILE_SIZE = 1,
  MODIFIED_AT = 2,
  FORMAT = 3,
  MIME = 4,
  DURATION = 5,
  SAMPLE_RATE = 6,
  CHANNEL_COUNT = 7,
  BIT_DEPTH = 8,
  BIT_RATE = 9,
  AVAILABILITY = 10,
  AUTHORIZATION = 11,
  URI = 12
}

enum DetailCollectionSource {
  RAW_TAGS = 0
}

interface DetailFieldRule {
  id: string;
  label: string;
  sectionId: string;
  order: number;
  source: DetailFieldSource;
  renderer: DetailRenderer;
  formatter: DetailFormatter;
}

interface DetailCollectionRule {
  id: string;
  sectionId: string;
  order: number;
  source: DetailCollectionSource;
}

export class TrackDetailPresenter {
  private static readonly BASIC_METADATA_SECTION = 'metadata-basic';
  private static readonly PEOPLE_METADATA_SECTION = 'metadata-people';
  private static readonly RELEASE_METADATA_SECTION = 'metadata-release';
  private static readonly CONTENT_METADATA_SECTION = 'metadata-content';
  private static readonly IDENTIFIER_METADATA_SECTION = 'metadata-identifiers';
  private static readonly TECHNICAL_METADATA_SECTION = 'metadata-technical';
  private static readonly OTHER_METADATA_SECTION = 'metadata-other';
  private static readonly FILE_SECTION = 'file';

  private static readonly SECTION_RULES: Array<DetailSectionRule> = [
    {
      id: TrackDetailPresenter.BASIC_METADATA_SECTION,
      title: '基础标签',
      order: 100,
      showsRowCount: false
    },
    {
      id: TrackDetailPresenter.PEOPLE_METADATA_SECTION,
      title: '人员信息',
      order: 200,
      showsRowCount: false
    },
    {
      id: TrackDetailPresenter.RELEASE_METADATA_SECTION,
      title: '发行信息',
      order: 300,
      showsRowCount: false
    },
    {
      id: TrackDetailPresenter.CONTENT_METADATA_SECTION,
      title: '内容信息',
      order: 400,
      showsRowCount: false
    },
    {
      id: TrackDetailPresenter.IDENTIFIER_METADATA_SECTION,
      title: '标识符',
      order: 500,
      showsRowCount: false
    },
    {
      id: TrackDetailPresenter.TECHNICAL_METADATA_SECTION,
      title: '编码与链接',
      order: 600,
      showsRowCount: false
    },
    {
      id: TrackDetailPresenter.OTHER_METADATA_SECTION,
      title: '其他标签',
      order: 700,
      showsRowCount: true
    },
    {
      id: TrackDetailPresenter.FILE_SECTION,
      title: '文件与音频',
      order: 800,
      showsRowCount: false
    }
  ];

  private static readonly FIELD_RULES: Array<DetailFieldRule> = [
    TrackDetailPresenter.fieldRule(
      'name', '文件名', TrackDetailPresenter.FILE_SECTION, 100,
      DetailFieldSource.FILE_NAME
    ),
    TrackDetailPresenter.fieldRule(
      'size', '文件大小', TrackDetailPresenter.FILE_SECTION, 200,
      DetailFieldSource.FILE_SIZE, DetailFormatter.FILE_SIZE
    ),
    TrackDetailPresenter.fieldRule(
      'modified', '修改时间', TrackDetailPresenter.FILE_SECTION, 300,
      DetailFieldSource.MODIFIED_AT, DetailFormatter.DATE_TIME
    ),
    TrackDetailPresenter.fieldRule(
      'format', '容器格式', TrackDetailPresenter.FILE_SECTION, 400,
      DetailFieldSource.FORMAT, DetailFormatter.UPPERCASE
    ),
    TrackDetailPresenter.fieldRule(
      'mime', 'MIME', TrackDetailPresenter.FILE_SECTION, 500,
      DetailFieldSource.MIME, DetailFormatter.UNKNOWN_TEXT
    ),
    TrackDetailPresenter.fieldRule(
      'duration', '时长', TrackDetailPresenter.FILE_SECTION, 600,
      DetailFieldSource.DURATION, DetailFormatter.DURATION
    ),
    TrackDetailPresenter.fieldRule(
      'sample-rate', '采样率', TrackDetailPresenter.FILE_SECTION, 700,
      DetailFieldSource.SAMPLE_RATE, DetailFormatter.SAMPLE_RATE
    ),
    TrackDetailPresenter.fieldRule(
      'channels', '声道', TrackDetailPresenter.FILE_SECTION, 800,
      DetailFieldSource.CHANNEL_COUNT, DetailFormatter.CHANNEL_COUNT
    ),
    TrackDetailPresenter.fieldRule(
      'bit-depth', '位深', TrackDetailPresenter.FILE_SECTION, 900,
      DetailFieldSource.BIT_DEPTH, DetailFormatter.BIT_DEPTH
    ),
    TrackDetailPresenter.fieldRule(
      'bit-rate', '码率', TrackDetailPresenter.FILE_SECTION, 1000,
      DetailFieldSource.BIT_RATE, DetailFormatter.BIT_RATE
    ),
    TrackDetailPresenter.fieldRule(
      'availability', '文件状态', TrackDetailPresenter.FILE_SECTION, 1100,
      DetailFieldSource.AVAILABILITY, DetailFormatter.AVAILABILITY
    ),
    TrackDetailPresenter.fieldRule(
      'authorization', '持久授权', TrackDetailPresenter.FILE_SECTION, 1200,
      DetailFieldSource.AUTHORIZATION, DetailFormatter.AUTHORIZATION
    ),
    TrackDetailPresenter.fieldRule(
      'uri', 'URI', TrackDetailPresenter.FILE_SECTION, 1300,
      DetailFieldSource.URI, DetailFormatter.URI, DetailRenderer.URI
    )
  ];

  private static readonly COLLECTION_RULES: Array<DetailCollectionRule> = [
    {
      id: 'raw-tags',
      sectionId: TrackDetailPresenter.OTHER_METADATA_SECTION,
      order: 100,
      source: DetailCollectionSource.RAW_TAGS
    }
  ];

  private static readonly TAG_RULES: Map<string, TagPresentationRule> =
    new Map<string, TagPresentationRule>([
      ['TITLE', TrackDetailPresenter.basicTagRule('标题')],
      ['TIT2', TrackDetailPresenter.basicTagRule('标题')],
      ['SORTTITLE', TrackDetailPresenter.basicTagRule('排序标题')],
      ['SORT_TITLE', TrackDetailPresenter.basicTagRule('排序标题')],
      ['TSOT', TrackDetailPresenter.basicTagRule('排序标题')],
      ['ALBUM', TrackDetailPresenter.basicTagRule('专辑')],
      ['TALB', TrackDetailPresenter.basicTagRule('专辑')],
      ['TRACKNUMBER', TrackDetailPresenter.basicTagRule('曲目')],
      ['TRACK_NUMBER', TrackDetailPresenter.basicTagRule('曲目')],
      ['TRCK', TrackDetailPresenter.basicTagRule('曲目')],
      ['DISCNUMBER', TrackDetailPresenter.basicTagRule('碟片')],
      ['DISC_NUMBER', TrackDetailPresenter.basicTagRule('碟片')],
      ['TPOS', TrackDetailPresenter.basicTagRule('碟片')],
      ['GENRE', TrackDetailPresenter.basicTagRule('流派', DetailRenderer.MULTI_VALUE)],
      ['TCON', TrackDetailPresenter.basicTagRule('流派', DetailRenderer.MULTI_VALUE)],
      ['BPM', TrackDetailPresenter.basicTagRule('BPM')],
      ['TBPM', TrackDetailPresenter.basicTagRule('BPM')],
      ['ARTIST', TrackDetailPresenter.peopleTagRule('艺人')],
      ['TPE1', TrackDetailPresenter.peopleTagRule('艺人')],
      ['ALBUMARTIST', TrackDetailPresenter.peopleTagRule('专辑艺人')],
      ['ALBUM_ARTIST', TrackDetailPresenter.peopleTagRule('专辑艺人')],
      ['TPE2', TrackDetailPresenter.peopleTagRule('专辑艺人')],
      ['COMPOSER', TrackDetailPresenter.peopleTagRule('作曲')],
      ['TCOM', TrackDetailPresenter.peopleTagRule('作曲')],
      ['LYRICIST', TrackDetailPresenter.peopleTagRule('作词')],
      ['TEXT', TrackDetailPresenter.peopleTagRule('作词')],
      ['CONDUCTOR', TrackDetailPresenter.peopleTagRule('指挥')],
      ['TPE3', TrackDetailPresenter.peopleTagRule('指挥')],
      ['PERFORMER', TrackDetailPresenter.peopleTagRule('演奏/表演')],
      ['TPE4', TrackDetailPresenter.peopleTagRule('演奏/表演')],
      ['DATE', TrackDetailPresenter.releaseTagRule('发行日期')],
      ['YEAR', TrackDetailPresenter.releaseTagRule('发行年份')],
      ['TDRC', TrackDetailPresenter.releaseTagRule('发行日期')],
      ['TYER', TrackDetailPresenter.releaseTagRule('发行年份')],
      ['ORIGINALDATE', TrackDetailPresenter.releaseTagRule('原始发行日期')],
      ['ORIGINAL_DATE', TrackDetailPresenter.releaseTagRule('原始发行日期')],
      ['TDOR', TrackDetailPresenter.releaseTagRule('原始发行日期')],
      ['TORY', TrackDetailPresenter.releaseTagRule('原始发行年份')],
      ['COPYRIGHT', TrackDetailPresenter.releaseTagRule('版权')],
      ['TCOP', TrackDetailPresenter.releaseTagRule('版权')],
      ['COMMENT', TrackDetailPresenter.contentTagRule('备注')],
      ['COMM', TrackDetailPresenter.contentTagRule('备注')],
      ['LYRICS', TrackDetailPresenter.lyricsTagRule()],
      ['UNSYNCEDLYRICS', TrackDetailPresenter.lyricsTagRule()],
      ['USLT', TrackDetailPresenter.lyricsTagRule()],
      ['ISRC', TrackDetailPresenter.identifierTagRule('ISRC')],
      ['TSRC', TrackDetailPresenter.identifierTagRule('ISRC')],
      ['MUSICBRAINZ_TRACKID',
        TrackDetailPresenter.identifierTagRule('MusicBrainz Track ID')],
      ['MUSICBRAINZ_ALBUMID',
        TrackDetailPresenter.identifierTagRule('MusicBrainz Album ID')],
      ['ENCODER', TrackDetailPresenter.technicalTagRule('编码器')],
      ['TENC', TrackDetailPresenter.technicalTagRule('编码器')],
      ['URI', TrackDetailPresenter.metadataTagRule(
        'URI',
        TrackDetailPresenter.TECHNICAL_METADATA_SECTION,
        DetailRenderer.URI,
        DetailFormatter.URI
      )],
      ['URL', TrackDetailPresenter.metadataTagRule(
        'URL',
        TrackDetailPresenter.TECHNICAL_METADATA_SECTION,
        DetailRenderer.URI,
        DetailFormatter.URI
      )]
    ]);

  static present(detail: TrackDetail): DetailPageModel {
    const rows: Array<DetailRowModel> = [];
    TrackDetailPresenter.FIELD_RULES.forEach((rule: DetailFieldRule) => {
      rows.push(TrackDetailPresenter.fieldRow(detail, rule));
    });
    TrackDetailPresenter.COLLECTION_RULES.forEach((rule: DetailCollectionRule) => {
      rows.push(...TrackDetailPresenter.collectionRows(detail, rule));
    });
    return {
      sections: TrackDetailPresenter.groupRows(rows)
    };
  }

  static normalizeTagKey(key: string): string {
    return key.normalize('NFKC').trim().toUpperCase();
  }

  static displayUri(uri: string): string {
    try {
      return decodeURI(uri);
    } catch (_) {
      return uri;
    }
  }

  static rawTagRow(tag: TrackRawTag): DetailRowModel | undefined {
    const sourceValue = tag.value.trim();
    if (sourceValue.length === 0) {
      return undefined;
    }
    const key = TrackDetailPresenter.normalizeTagKey(tag.key);
    const rule = TrackDetailPresenter.TAG_RULES.get(key);
    const sectionId = rule?.sectionId ?? TrackDetailPresenter.OTHER_METADATA_SECTION;
    const renderer = rule?.renderer ?? DetailRenderer.TEXT;
    const formatter = rule?.formatter ?? DetailFormatter.TEXT;
    const displayValue = TrackDetailPresenter.formatValue(sourceValue, formatter);
    return {
      id: `raw:${key}:${tag.key}:${tag.ordinal}`,
      sectionId: sectionId,
      order: (rule?.order ?? 10000) + tag.ordinal,
      label: rule?.label ?? tag.key,
      displayValue: displayValue,
      copyValue: tag.value,
      renderer: renderer,
      actions: renderer === DetailRenderer.URI ? [DetailAction.COPY_EXACT] : []
    };
  }

  static formatDuration(durationMs: number): string {
    const totalSeconds = Math.max(0, Math.floor(durationMs / 1000));
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    if (hours > 0) {
      return `${hours}:${TrackDetailPresenter.twoDigits(minutes)}:` +
        `${TrackDetailPresenter.twoDigits(seconds)}`;
    }
    return `${minutes}:${TrackDetailPresenter.twoDigits(seconds)}`;
  }

  static formatFileSize(bytes: number): string {
    if (bytes <= 0) {
      return '未知';
    }
    const units: Array<string> = ['B', 'KB', 'MB', 'GB'];
    let value = bytes;
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit += 1;
    }
    return `${value >= 10 || unit === 0 ? value.toFixed(0) : value.toFixed(1)} ${units[unit]}`;
  }

  static lyricLineCount(value: string): number {
    let count = 0;
    value.split(/\r\n|\r|\n/).forEach((line: string) => {
      if (line.trim().length > 0) {
        count += 1;
      }
    });
    return count;
  }

  private static fieldRule(
    id: string,
    label: string,
    sectionId: string,
    order: number,
    source: DetailFieldSource,
    formatter: DetailFormatter = DetailFormatter.TEXT,
    renderer: DetailRenderer = DetailRenderer.TEXT
  ): DetailFieldRule {
    return {
      id: id,
      label: label,
      sectionId: sectionId,
      order: order,
      source: source,
      renderer: renderer,
      formatter: formatter
    };
  }

  private static metadataTagRule(
    label: string,
    sectionId: string,
    renderer: DetailRenderer = DetailRenderer.TEXT,
    formatter: DetailFormatter = DetailFormatter.TEXT
  ): TagPresentationRule {
    return {
      label: label,
      sectionId: sectionId,
      order: 1000,
      renderer: renderer,
      formatter: formatter
    };
  }

  private static basicTagRule(
    label: string,
    renderer: DetailRenderer = DetailRenderer.TEXT
  ): TagPresentationRule {
    return TrackDetailPresenter.metadataTagRule(
      label,
      TrackDetailPresenter.BASIC_METADATA_SECTION,
      renderer
    );
  }

  private static peopleTagRule(label: string): TagPresentationRule {
    return TrackDetailPresenter.metadataTagRule(
      label,
      TrackDetailPresenter.PEOPLE_METADATA_SECTION
    );
  }

  private static releaseTagRule(label: string): TagPresentationRule {
    return TrackDetailPresenter.metadataTagRule(
      label,
      TrackDetailPresenter.RELEASE_METADATA_SECTION
    );
  }

  private static contentTagRule(label: string): TagPresentationRule {
    return TrackDetailPresenter.metadataTagRule(
      label,
      TrackDetailPresenter.CONTENT_METADATA_SECTION
    );
  }

  private static lyricsTagRule(): TagPresentationRule {
    return TrackDetailPresenter.metadataTagRule(
      '歌词',
      TrackDetailPresenter.CONTENT_METADATA_SECTION,
      DetailRenderer.LYRICS,
      DetailFormatter.LYRIC_LINE_COUNT
    );
  }

  private static identifierTagRule(label: string): TagPresentationRule {
    return TrackDetailPresenter.metadataTagRule(
      label,
      TrackDetailPresenter.IDENTIFIER_METADATA_SECTION,
      DetailRenderer.MONOSPACE
    );
  }

  private static technicalTagRule(label: string): TagPresentationRule {
    return TrackDetailPresenter.metadataTagRule(
      label,
      TrackDetailPresenter.TECHNICAL_METADATA_SECTION
    );
  }

  private static fieldRow(detail: TrackDetail, rule: DetailFieldRule): DetailRowModel {
    const sourceValue = TrackDetailPresenter.fieldSourceValue(detail, rule.source);
    const displayValue = TrackDetailPresenter.formatValue(sourceValue, rule.formatter);
    return {
      id: `${rule.sectionId}:${rule.id}`,
      sectionId: rule.sectionId,
      order: rule.order,
      label: rule.label,
      displayValue: displayValue,
      copyValue: rule.renderer === DetailRenderer.URI ? sourceValue : displayValue,
      renderer: rule.renderer,
      actions: rule.renderer === DetailRenderer.URI ? [DetailAction.COPY_EXACT] : []
    };
  }

  private static collectionRows(
    detail: TrackDetail,
    _rule: DetailCollectionRule
  ): Array<DetailRowModel> {
    return TrackDetailPresenter.rawTagRows(detail.rawTags);
  }

  private static rawTagRows(tags: Array<TrackRawTag>): Array<DetailRowModel> {
    const rows: Array<DetailRowModel> = [];
    tags.forEach((tag: TrackRawTag) => {
      const row = TrackDetailPresenter.rawTagRow(tag);
      if (row !== undefined) {
        rows.push(row);
      }
    });
    return rows;
  }

  private static groupRows(rows: Array<DetailRowModel>): Array<DetailSectionModel> {
    const grouped: Map<string, Array<DetailRowModel>> =
      new Map<string, Array<DetailRowModel>>();
    rows.forEach((row: DetailRowModel) => {
      const sectionRows = grouped.get(row.sectionId) ?? [];
      sectionRows.push(row);
      grouped.set(row.sectionId, sectionRows);
    });

    const sections: Array<DetailSectionModel> = [];
    const sectionRules = TrackDetailPresenter.SECTION_RULES.slice();
    sectionRules.sort((left: DetailSectionRule, right: DetailSectionRule) =>
      left.order - right.order);
    sectionRules.forEach((rule: DetailSectionRule) => {
      const sectionRows = grouped.get(rule.id) ?? [];
      if (sectionRows.length === 0) {
        return;
      }
      sectionRows.sort((left: DetailRowModel, right: DetailRowModel) => {
        const orderDifference = left.order - right.order;
        return orderDifference !== 0 ? orderDifference : left.id.localeCompare(right.id);
      });
      sections.push({
        id: rule.id,
        title: rule.showsRowCount ? `${rule.title}（${sectionRows.length}）` : rule.title,
        rows: sectionRows
      });
    });
    return sections;
  }

  private static fieldSourceValue(detail: TrackDetail, source: DetailFieldSource): string {
    if (source === DetailFieldSource.FILE_NAME) {
      return detail.displayName;
    }
    if (source === DetailFieldSource.FILE_SIZE) {
      return `${detail.fileSize}`;
    }
    if (source === DetailFieldSource.MODIFIED_AT) {
      return `${detail.modifiedAt}`;
    }
    if (source === DetailFieldSource.FORMAT) {
      return detail.format;
    }
    if (source === DetailFieldSource.MIME) {
      return detail.mimeType;
    }
    if (source === DetailFieldSource.DURATION) {
      return `${detail.durationMs}`;
    }
    if (source === DetailFieldSource.SAMPLE_RATE) {
      return `${detail.sampleRate}`;
    }
    if (source === DetailFieldSource.CHANNEL_COUNT) {
      return `${detail.channelCount}`;
    }
    if (source === DetailFieldSource.BIT_DEPTH) {
      return `${detail.bitsPerSample}`;
    }
    if (source === DetailFieldSource.BIT_RATE) {
      return `${detail.bitRate}`;
    }
    if (source === DetailFieldSource.AVAILABILITY) {
      return `${detail.availability}`;
    }
    if (source === DetailFieldSource.AUTHORIZATION) {
      return detail.authorizationPersisted ? '1' : '0';
    }
    return detail.uri.length > 0 ? detail.uri : '演示数据';
  }

  private static formatValue(value: string, formatter: DetailFormatter): string {
    if (formatter === DetailFormatter.UNKNOWN_TEXT) {
      return TrackDetailPresenter.valueOrUnknown(value);
    }
    if (formatter === DetailFormatter.URI) {
      return TrackDetailPresenter.displayUri(value);
    }
    if (formatter === DetailFormatter.FILE_SIZE) {
      return TrackDetailPresenter.formatFileSize(Number.parseInt(value, 10));
    }
    if (formatter === DetailFormatter.DATE_TIME) {
      return TrackDetailPresenter.dateTimeLabel(Number.parseInt(value, 10));
    }
    if (formatter === DetailFormatter.UPPERCASE) {
      return value.toUpperCase();
    }
    if (formatter === DetailFormatter.DURATION) {
      return TrackDetailPresenter.formatDuration(Number.parseInt(value, 10));
    }
    if (formatter === DetailFormatter.SAMPLE_RATE) {
      const sampleRate = Number.parseInt(value, 10);
      return sampleRate > 0 ? `${sampleRate} Hz` : '未知';
    }
    if (formatter === DetailFormatter.CHANNEL_COUNT) {
      return TrackDetailPresenter.channelLabel(Number.parseInt(value, 10));
    }
    if (formatter === DetailFormatter.BIT_DEPTH) {
      const bitDepth = Number.parseInt(value, 10);
      return bitDepth > 0 ? `${bitDepth} bit` : '未知';
    }
    if (formatter === DetailFormatter.BIT_RATE) {
      const bitRate = Number.parseInt(value, 10);
      return bitRate > 0 ? `${Math.round(bitRate / 1000)} kbps` : '未知';
    }
    if (formatter === DetailFormatter.AVAILABILITY) {
      return TrackDetailPresenter.availabilityLabel(
        Number.parseInt(value, 10) as AvailabilityState
      );
    }
    if (formatter === DetailFormatter.AUTHORIZATION) {
      return value === '1' ? '已保留' : '未保留';
    }
    if (formatter === DetailFormatter.LYRIC_LINE_COUNT) {
      return `${TrackDetailPresenter.lyricLineCount(value)} 行`;
    }
    return value;
  }

  private static twoDigits(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private static valueOrUnknown(value: string): string {
    return value.trim().length > 0 ? value : '未知';
  }

  private static dateTimeLabel(timestamp: number): string {
    return timestamp > 0 ? new Date(timestamp).toLocaleString() : '未知';
  }

  private static channelLabel(count: number): string {
    if (count === 1) {
      return '1（单声道）';
    }
    if (count === 2) {
      return '2（立体声）';
    }
    return count > 0 ? `${count}` : '未知';
  }

  private static availabilityLabel(value: AvailabilityState): string {
    if (value === AvailabilityState.AVAILABLE) {
      return '可用';
    }
    if (value === AvailabilityState.AUTHORIZATION_REVOKED) {
      return '文件授权已撤销';
    }
    if (value === AvailabilityState.CORRUPTED) {
      return '文件损坏';
    }
    return '文件不可用';
  }

}
