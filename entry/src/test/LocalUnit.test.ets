import { describe, it, expect } from '@ohos/hypium';
import { MetadataFactory } from '../main/ets/library/metadata/MetadataFactory';
import { MetadataNormalizer } from '../main/ets/library/metadata/MetadataNormalizer';
import { MediaFormat } from '../main/ets/library/model/LibraryModels';

export default function localUnitTest() {
  describe('MetadataNormalizer', () => {
    it('splits common multi-value separators and removes duplicates', 0, () => {
      const values = MetadataNormalizer.splitValues(['Alice; Bob、alice / Carol']);
      expect(values.length).assertEqual(3);
      expect(values[0]).assertEqual('Alice');
      expect(values[1]).assertEqual('Bob');
      expect(values[2]).assertEqual('Carol');
    });

    it('groups albums by title and album artist only', 0, () => {
      const first = MetadataFactory.empty(MediaFormat.FLAC);
      first.album = 'Example';
      first.artists = ['Track Artist A'];
      const second = MetadataFactory.empty(MediaFormat.FLAC);
      second.album = 'Example';
      second.artists = ['Track Artist B'];
      expect(MetadataNormalizer.albumIdentity(first)).assertEqual(MetadataNormalizer.albumIdentity(second));

      second.albumArtists = ['Album Artist'];
      expect(MetadataNormalizer.albumIdentity(first) === MetadataNormalizer.albumIdentity(second)).assertFalse();
    });

    it('preserves date precision', 0, () => {
      const year = MetadataNormalizer.parseDate('2024');
      const day = MetadataNormalizer.parseDate('2024-07-15');
      expect(year.precision).assertEqual(1);
      expect(day.precision).assertEqual(3);
      expect(day.month).assertEqual(7);
      expect(day.day).assertEqual(15);
    });
  });
}
