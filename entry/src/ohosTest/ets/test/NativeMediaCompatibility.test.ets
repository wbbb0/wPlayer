import { describe, it, expect } from '@ohos/hypium';
import { fileIo as fs } from '@kit.CoreFileKit';
import {
  flattenArtworkPixels,
  probeMediaFile,
  readArtworkBytesAsync
} from '../../../main/ets/library/metadata/MediaFileTasks';
import { flattenArtworkPixels as flattenArtworkPixelsNative } from 'libwplayermedia.so';
import { ArtworkPictureType, MediaFormat } from
  '../../../main/ets/library/model/LibraryModels';

const TEST_DIRECTORY = '/data/storage/el2/base/files';

function ascii(value: string): Uint8Array {
  const bytes = new Uint8Array(value.length);
  for (let index = 0; index < value.length; index += 1) {
    bytes[index] = value.charCodeAt(index);
  }
  return bytes;
}

function concat(parts: Array<Uint8Array>): Uint8Array {
  let length = 0;
  parts.forEach((part: Uint8Array) => {
    length += part.length;
  });
  const output = new Uint8Array(length);
  let offset = 0;
  parts.forEach((part: Uint8Array) => {
    output.set(part, offset);
    offset += part.length;
  });
  return output;
}

function syncSafe32(value: number): Uint8Array {
  return new Uint8Array([
    (value >> 21) & 0x7F,
    (value >> 14) & 0x7F,
    (value >> 7) & 0x7F,
    value & 0x7F
  ]);
}

function uint32BE(value: number): Uint8Array {
  return new Uint8Array([
    (value >>> 24) & 0xFF,
    (value >>> 16) & 0xFF,
    (value >>> 8) & 0xFF,
    value & 0xFF
  ]);
}

function uint32LE(value: number): Uint8Array {
  return new Uint8Array([
    value & 0xFF,
    (value >>> 8) & 0xFF,
    (value >>> 16) & 0xFF,
    (value >>> 24) & 0xFF
  ]);
}

function id3v24Frame(id: string, payload: Uint8Array, formatFlags: number = 0): Uint8Array {
  return concat([
    ascii(id),
    syncSafe32(payload.length),
    new Uint8Array([0, formatFlags]),
    payload
  ]);
}

function id3v23Frame(id: string, payload: Uint8Array, formatFlags: number = 0): Uint8Array {
  return concat([
    ascii(id),
    uint32BE(payload.length),
    new Uint8Array([0, formatFlags]),
    payload
  ]);
}

function id3v22Frame(id: string, payload: Uint8Array): Uint8Array {
  return concat([
    ascii(id),
    new Uint8Array([
      (payload.length >>> 16) & 0xFF,
      (payload.length >>> 8) & 0xFF,
      payload.length & 0xFF
    ]),
    payload
  ]);
}

function id3File(version: number, flags: number, frames: Uint8Array): Uint8Array {
  return concat([
    ascii('ID3'),
    new Uint8Array([version, 0, flags]),
    syncSafe32(frames.length),
    frames,
    new Uint8Array([0xFF, 0xFB, 0x90, 0x64])
  ]);
}

function mp3Fixture(): Uint8Array {
  const title = id3v24Frame('TIT2', concat([new Uint8Array([3]), ascii('Native title')]));
  const artist = id3v24Frame('TPE1', concat([new Uint8Array([3]), ascii('Artist; Guest')]));
  const track = id3v24Frame('TRCK', concat([new Uint8Array([3]), ascii('2/9')]));
  const artworkPayload = concat([
    new Uint8Array([0]),
    ascii('image/jpeg'),
    new Uint8Array([0, ArtworkPictureType.FRONT_COVER]),
    ascii('front'),
    new Uint8Array([0, 0xFF, 0x00, 0xE1, 0x01])
  ]);
  const artwork = id3v24Frame('APIC', artworkPayload, 0x02);
  const frames = concat([title, artist, track, artwork]);
  return id3File(4, 0, frames);
}

function id3v22Fixture(): Uint8Array {
  const title = id3v22Frame('TT2', concat([new Uint8Array([0]), ascii('V22 title')]));
  const imageBytes = new Uint8Array(5000);
  imageBytes[0] = 1;
  imageBytes[imageBytes.length - 1] = 3;
  const picture = id3v22Frame('PIC', concat([
    new Uint8Array([0]),
    ascii('PNG'),
    new Uint8Array([ArtworkPictureType.FRONT_COVER]),
    ascii('v22'),
    new Uint8Array([0]),
    imageBytes
  ]));
  return id3File(2, 0, concat([title, picture]));
}

function id3v23EncodingFixture(): Uint8Array {
  const latin1 = id3v23Frame('TIT2', new Uint8Array([
    0, 0xC9, 0, 0x58
  ]));
  const utf8Values = id3v23Frame('TPE1', concat([
    new Uint8Array([3]),
    ascii('First'),
    new Uint8Array([0]),
    ascii('Second')
  ]));
  const utf16Bom = id3v23Frame('TSOT', new Uint8Array([
    1, 0xFF, 0xFE, 0x53, 0, 0x6F, 0, 0x72, 0, 0x74, 0
  ]));
  const utf16Be = id3v23Frame('TALB', new Uint8Array([
    2, 0, 0x42, 0, 0x45
  ]));
  const lyrics = id3v23Frame('USLT', concat([
    new Uint8Array([3]),
    ascii('eng'),
    ascii('note'),
    new Uint8Array([0]),
    ascii('line one'),
    new Uint8Array([0, 0])
  ]));
  const truncatedThreeByteUtf8 = id3v23Frame('TCOM', new Uint8Array([
    3, 0xE2, 0x82
  ]));
  const truncatedFourByteUtf8 = id3v23Frame('TCOM', new Uint8Array([
    3, 0xF0, 0x9F, 0x92
  ]));
  const interruptedThreeByteUtf8 = id3v23Frame('TCOM', new Uint8Array([
    3, 0xE2, 0x82, 0x41
  ]));
  const interruptedFourByteUtf8 = id3v23Frame('TCOM', new Uint8Array([
    3, 0xF0, 0x9F, 0x92, 0x41
  ]));
  const truncatedUtf16Le = id3v23Frame('TCOM', new Uint8Array([
    1, 0xFF, 0xFE, 0x00, 0xD8, 0x41
  ]));
  const truncatedUtf16Be = id3v23Frame('TCOM', new Uint8Array([
    2, 0xD8, 0x00, 0x41
  ]));
  const groupedTitle = id3v23Frame('TCON', concat([
    new Uint8Array([7, 3]),
    ascii('Rock')
  ]), 0x20);
  return id3File(3, 0, concat([
    latin1,
    utf8Values,
    utf16Bom,
    utf16Be,
    lyrics,
    truncatedThreeByteUtf8,
    truncatedFourByteUtf8,
    interruptedThreeByteUtf8,
    interruptedFourByteUtf8,
    truncatedUtf16Le,
    truncatedUtf16Be,
    groupedTitle
  ]));
}

function id3v1Fixture(): Uint8Array {
  const bytes = new Uint8Array(256);
  bytes[0] = 0xFF;
  bytes[1] = 0xFB;
  bytes.set(ascii('TAG'), 128);
  bytes.set(ascii('ID3v1 title'), 131);
  bytes.set(ascii('ID3v1 artist'), 161);
  bytes.set(ascii('ID3v1 album'), 191);
  bytes.set(ascii('1999'), 221);
  bytes[253] = 0;
  bytes[254] = 5;
  return bytes;
}

function flacBlock(type: number, isLast: boolean, payload: Uint8Array): Uint8Array {
  return concat([
    new Uint8Array([
      (isLast ? 0x80 : 0) | type,
      (payload.length >>> 16) & 0xFF,
      (payload.length >>> 8) & 0xFF,
      payload.length & 0xFF
    ]),
    payload
  ]);
}

function flacStreamInfo(): Uint8Array {
  const bytes = new Uint8Array(34);
  const sampleRate = 44100;
  const channelsMinusOne = 1;
  const bitsPerSampleMinusOne = 15;
  const totalSamples = 44100;
  bytes[10] = (sampleRate >>> 12) & 0xFF;
  bytes[11] = (sampleRate >>> 4) & 0xFF;
  bytes[12] = ((sampleRate & 0x0F) << 4) |
    ((channelsMinusOne & 0x07) << 1) |
    ((bitsPerSampleMinusOne >>> 4) & 0x01);
  bytes[13] = ((bitsPerSampleMinusOne & 0x0F) << 4) |
    ((totalSamples / 0x100000000) & 0x0F);
  bytes[14] = (totalSamples >>> 24) & 0xFF;
  bytes[15] = (totalSamples >>> 16) & 0xFF;
  bytes[16] = (totalSamples >>> 8) & 0xFF;
  bytes[17] = totalSamples & 0xFF;
  return bytes;
}

function vorbisComment(vendor: string, comments: Array<string>): Uint8Array {
  const parts: Array<Uint8Array> = [uint32LE(vendor.length), ascii(vendor), uint32LE(comments.length)];
  comments.forEach((comment: string) => {
    parts.push(uint32LE(comment.length));
    parts.push(ascii(comment));
  });
  return concat(parts);
}

function flacPicture(): Uint8Array {
  const imageBytes = new Uint8Array([0x89, 0x50, 0x4E, 0x47]);
  const mime = ascii('image/png');
  const description = ascii('cover');
  return concat([
    uint32BE(ArtworkPictureType.FRONT_COVER),
    uint32BE(mime.length),
    mime,
    uint32BE(description.length),
    description,
    uint32BE(640),
    uint32BE(480),
    uint32BE(24),
    uint32BE(0),
    uint32BE(imageBytes.length),
    imageBytes
  ]);
}

function flacFixture(): Uint8Array {
  return concat([
    ascii('fLaC'),
    flacBlock(0, false, flacStreamInfo()),
    flacBlock(4, false, vorbisComment('wPlayer', [
      'TITLE=FLAC title',
      'ARTIST=First; Second',
      'TRACKNUMBER=3/11',
      'DATE=2024-05-06'
    ])),
    flacBlock(6, true, flacPicture())
  ]);
}

function writeFixture(path: string, bytes: Uint8Array): void {
  let file: fs.File | undefined;
  try {
    file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, bytes.buffer);
  } catch (error) {
    const message = error instanceof Error ? error.message : `${error}`;
    throw new Error(`Unable to write native media fixture: ${message}`);
  } finally {
    if (file !== undefined) {
      try {
        fs.closeSync(file);
      } catch (_) {
      }
    }
  }
}

function removeFixture(path: string): void {
  try {
    fs.unlinkSync(path);
  } catch (_) {
  }
}

export default function nativeMediaCompatibilityTest() {
  describe('NativeMediaCompatibility', () => {
    it('preservesId3v24TagsArtworkAndUnsynchronization', 0, async () => {
      const path = `${TEST_DIRECTORY}/native-media-id3.mp3`;
      writeFixture(path, mp3Fixture());
      try {
        const probe = await probeMediaFile(path);
        expect(probe.metadata.format).assertEqual(MediaFormat.MP3);
        expect(probe.metadata.title).assertEqual('Native title');
        expect(probe.metadata.artists.length).assertEqual(2);
        expect(probe.metadata.artists[0]).assertEqual('Artist');
        expect(probe.metadata.artists[1]).assertEqual('Guest');
        expect(probe.metadata.trackNumber.value).assertEqual(2);
        expect(probe.metadata.trackNumber.total).assertEqual(9);
        expect(probe.metadata.artworks.length).assertEqual(1);
        const artwork = probe.metadata.artworks[0];
        expect(artwork.pictureType).assertEqual(ArtworkPictureType.FRONT_COVER);
        expect(artwork.mimeType).assertEqual('image/jpeg');
        expect(artwork.description).assertEqual('front');
        expect(artwork.unsynchronized).assertTrue();
        expect(artwork.byteOffset).assertEqual(81);
        expect(artwork.byteLength).assertEqual(23);
        expect(artwork.payloadOffset).assertEqual(19);
        const bytes = new Uint8Array(await readArtworkBytesAsync(
          path,
          artwork.byteOffset,
          artwork.byteLength,
          artwork.payloadOffset,
          artwork.unsynchronized
        ));
        expect(bytes.length).assertEqual(3);
        expect(bytes[0]).assertEqual(0xFF);
        expect(bytes[1]).assertEqual(0xE1);
        expect(bytes[2]).assertEqual(0x01);
      } finally {
        removeFixture(path);
      }
    });

    it('preservesId3v22MappingsAndPicOffsets', 0, async () => {
      const path = `${TEST_DIRECTORY}/native-media-id3v22.mp3`;
      writeFixture(path, id3v22Fixture());
      try {
        const probe = await probeMediaFile(path);
        expect(probe.metadata.title).assertEqual('V22 title');
        expect(probe.metadata.artworks.length).assertEqual(1);
        const artwork = probe.metadata.artworks[0];
        expect(artwork.mimeType).assertEqual('image/png');
        expect(artwork.description).assertEqual('v22');
        expect(artwork.ordinal).assertEqual(0);
        const bytes = new Uint8Array(await readArtworkBytesAsync(
          path, artwork.byteOffset, artwork.byteLength, artwork.payloadOffset, false
        ));
        expect(bytes.length).assertEqual(5000);
        expect(bytes[0]).assertEqual(1);
        expect(bytes[bytes.length - 1]).assertEqual(3);
      } finally {
        removeFixture(path);
      }
    });

    it('preservesId3TextEncodingsLyricsAndGroupingPrefix', 0, async () => {
      const path = `${TEST_DIRECTORY}/native-media-id3v23.mp3`;
      writeFixture(path, id3v23EncodingFixture());
      try {
        const metadata = (await probeMediaFile(path)).metadata;
        expect(metadata.title).assertEqual('É');
        expect(metadata.artists.length).assertEqual(2);
        expect(metadata.artists[0]).assertEqual('First');
        expect(metadata.artists[1]).assertEqual('Second');
        expect(metadata.sortTitle).assertEqual('Sort');
        expect(metadata.album).assertEqual('BE');
        expect(metadata.lyrics).assertEqual('line one');
        expect(metadata.composers.length).assertEqual(2);
        expect(metadata.composers[0]).assertEqual('\uFFFD');
        expect(metadata.composers[1]).assertEqual('\uFFFDA');
        const composerTags = metadata.rawTags.get('TCOM') ?? [];
        expect(composerTags.length).assertEqual(6);
        expect(composerTags[0]).assertEqual('\uFFFD');
        expect(composerTags[1]).assertEqual('\uFFFD');
        expect(composerTags[2]).assertEqual('\uFFFDA');
        expect(composerTags[3]).assertEqual('\uFFFDA');
        expect(composerTags[4]).assertEqual('\uFFFD');
        expect(composerTags[5]).assertEqual('\uFFFD');
        expect(metadata.genres.length).assertEqual(1);
        expect(metadata.genres[0]).assertEqual('Rock');
      } finally {
        removeFixture(path);
      }
    });

    it('preservesId3v1FallbackWithoutId3v2Header', 0, async () => {
      const path = `${TEST_DIRECTORY}/native-media-id3v1.mp3`;
      writeFixture(path, id3v1Fixture());
      try {
        const metadata = (await probeMediaFile(path)).metadata;
        expect(metadata.title).assertEqual('ID3v1 title');
        expect(metadata.artists[0]).assertEqual('ID3v1 artist');
        expect(metadata.album).assertEqual('ID3v1 album');
        expect(metadata.releaseDate.year).assertEqual(1999);
        expect(metadata.trackNumber.value).assertEqual(5);
      } finally {
        removeFixture(path);
      }
    });

    it('preservesFlacStreamInfoTagsAndPictureOffsets', 0, async () => {
      const path = `${TEST_DIRECTORY}/native-media-tags.flac`;
      writeFixture(path, flacFixture());
      try {
        const probe = await probeMediaFile(path);
        expect(probe.metadata.format).assertEqual(MediaFormat.FLAC);
        expect(probe.metadata.title).assertEqual('FLAC title');
        expect(probe.metadata.artists.length).assertEqual(2);
        expect(probe.metadata.trackNumber.value).assertEqual(3);
        expect(probe.metadata.trackNumber.total).assertEqual(11);
        expect(probe.metadata.releaseDate.precision).assertEqual(3);
        expect(probe.metadata.sampleRate).assertEqual(44100);
        expect(probe.metadata.channelCount).assertEqual(2);
        expect(probe.metadata.bitsPerSample).assertEqual(16);
        expect(probe.metadata.durationMs).assertEqual(1000);
        expect(probe.metadata.artworks.length).assertEqual(1);
        const artwork = probe.metadata.artworks[0];
        expect(artwork.mimeType).assertEqual('image/png');
        expect(artwork.width).assertEqual(640);
        expect(artwork.height).assertEqual(480);
        const bytes = new Uint8Array(await readArtworkBytesAsync(
          path,
          artwork.byteOffset,
          artwork.byteLength,
          artwork.payloadOffset,
          artwork.unsynchronized
        ));
        expect(bytes.length).assertEqual(4);
        expect(bytes[0]).assertEqual(0x89);
        expect(bytes[1]).assertEqual(0x50);
        expect(bytes[2]).assertEqual(0x4E);
        expect(bytes[3]).assertEqual(0x47);
      } finally {
        removeFixture(path);
      }
    });

    it('preservesStraightAndPremultipliedWhiteFlattening', 0, async () => {
      const source = new Uint8Array([
        10, 20, 30, 128,
        90, 80, 70, 0
      ]);
      const straightInput = source.buffer.slice(0);
      const straightOriginal = new Uint8Array(straightInput.slice(0));
      const straight = new Uint8Array(flattenArtworkPixelsNative(
        straightInput, 2, 1, false
      ));
      expect(straight[0]).assertEqual(142);
      expect(straight[1]).assertEqual(137);
      expect(straight[2]).assertEqual(132);
      expect(straight[3]).assertEqual(255);
      expect(straight[4]).assertEqual(255);
      expect(straight[5]).assertEqual(255);
      expect(straight[6]).assertEqual(255);
      expect(straight[7]).assertEqual(255);
      const straightAfter = new Uint8Array(straightInput);
      expect(straightAfter[0]).assertEqual(straightOriginal[0]);
      expect(straightAfter[1]).assertEqual(straightOriginal[1]);
      expect(straightAfter[2]).assertEqual(straightOriginal[2]);
      expect(straightAfter[3]).assertEqual(straightOriginal[3]);

      const premultipliedInput = source.buffer.slice(0);
      const premultipliedOriginal = new Uint8Array(premultipliedInput.slice(0));
      const premultiplied = new Uint8Array(flattenArtworkPixelsNative(
        premultipliedInput, 2, 1, true
      ));
      expect(premultiplied[0]).assertEqual(157);
      expect(premultiplied[1]).assertEqual(147);
      expect(premultiplied[2]).assertEqual(137);
      expect(premultiplied[3]).assertEqual(255);
      const premultipliedAfter = new Uint8Array(premultipliedInput);
      expect(premultipliedAfter[0]).assertEqual(premultipliedOriginal[0]);
      expect(premultipliedAfter[1]).assertEqual(premultipliedOriginal[1]);
      expect(premultipliedAfter[2]).assertEqual(premultipliedOriginal[2]);
      expect(premultipliedAfter[3]).assertEqual(premultipliedOriginal[3]);
    });

    it('preservesUnconditionalId3UnsynchronizationRemoval', 0, async () => {
      const path = `${TEST_DIRECTORY}/native-media-unsync.bin`;
      writeFixture(path, new Uint8Array([
        0xFF, 0x00, 0x00,
        0xFF, 0x00, 0xE1
      ]));
      try {
        const bytes = new Uint8Array(await readArtworkBytesAsync(path, 0, 6, 0, true));
        expect(bytes.length).assertEqual(4);
        expect(bytes[0]).assertEqual(0xFF);
        expect(bytes[1]).assertEqual(0x00);
        expect(bytes[2]).assertEqual(0xFF);
        expect(bytes[3]).assertEqual(0xE1);
      } finally {
        removeFixture(path);
      }
    });

    it('rejectsOversizedArtworkRangesBeforeAllocation', 0, async () => {
      const path = `${TEST_DIRECTORY}/native-media-small-artwork.bin`;
      writeFixture(path, new Uint8Array([1, 2, 3, 4]));
      try {
        let oversizedRejected = false;
        try {
          await readArtworkBytesAsync(path, 0, 65 * 1024 * 1024, 0, false);
        } catch (_) {
          oversizedRejected = true;
        }
        expect(oversizedRejected).assertTrue();

        let outOfRangeRejected = false;
        try {
          await readArtworkBytesAsync(path, 2, 4, 0, false);
        } catch (_) {
          outOfRangeRejected = true;
        }
        expect(outOfRangeRejected).assertTrue();
      } finally {
        removeFixture(path);
      }
    });

    it('rejectsPixelBuffersWhoseDimensionsDoNotMatch', 0, async () => {
      let rejected = false;
      try {
        await flattenArtworkPixels(new ArrayBuffer(4), 2, 1, false);
      } catch (_) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });

    it('rejectsTruncatedMetadataInsteadOfReadingPastTheFile', 0, async () => {
      const id3Path = `${TEST_DIRECTORY}/native-media-truncated.mp3`;
      const flacPath = `${TEST_DIRECTORY}/native-media-truncated.flac`;
      writeFixture(id3Path, new Uint8Array([
        0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 1, 0
      ]));
      writeFixture(flacPath, new Uint8Array([
        0x66, 0x4C, 0x61, 0x43, 0x80, 0, 0, 34
      ]));
      try {
        let id3Rejected = false;
        let flacRejected = false;
        try {
          await probeMediaFile(id3Path);
        } catch (_) {
          id3Rejected = true;
        }
        try {
          await probeMediaFile(flacPath);
        } catch (_) {
          flacRejected = true;
        }
        expect(id3Rejected).assertTrue();
        expect(flacRejected).assertTrue();
      } finally {
        removeFixture(id3Path);
        removeFixture(flacPath);
      }
    });
  });
}
