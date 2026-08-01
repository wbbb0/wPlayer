import { common } from '@kit.AbilityKit';
import { describe, expect, it } from '@ohos/hypium';
import { MusicFileShareCoordinator } from
  '../main/ets/library/share/MusicFileShareCoordinator';
import {
  MusicFileShareDataKind,
  MusicFileShareError,
  MusicFileShareErrorKind,
  MusicFileSharePayload,
  MusicFileSharePresenter,
  MusicFileShareTrack,
  PickerUriAccessActivator,
  TrackShareSource
} from '../main/ets/library/share/MusicFileSharePorts';

const TEST_CONTEXT: common.UIAbilityContext = new Object() as common.UIAbilityContext;

function trackDetail(uri: string, displayName: string = '原始音乐.mp3',
  title: string = '原始音乐', artist: string = '测试艺术家'): MusicFileShareTrack {
  return {
    title: title,
    artistDisplay: artist,
    displayName: displayName,
    uri: uri
  };
}

class FakeTrackShareSource implements TrackShareSource {
  detail?: MusicFileShareTrack;
  fail: boolean = false;
  calls: number = 0;

  getShareTrack(_trackId: number): Promise<MusicFileShareTrack | undefined> {
    this.calls += 1;
    if (this.fail) {
      return Promise.reject(new Error('lookup failed'));
    }
    return Promise.resolve(this.detail);
  }
}

class FakeUriAccessActivator implements PickerUriAccessActivator {
  allowed: boolean = true;
  fail: boolean = false;
  uris: Array<string> = [];

  activate(uri: string): Promise<boolean> {
    this.uris.push(uri);
    if (this.fail) {
      return Promise.reject(new Error('permission failed'));
    }
    return Promise.resolve(this.allowed);
  }
}

class FakeMusicFileSharePresenter implements MusicFileSharePresenter {
  fail: boolean = false;
  payloads: Array<MusicFileSharePayload> = [];

  show(_context: common.UIAbilityContext, payload: MusicFileSharePayload): Promise<void> {
    this.payloads.push(payload);
    if (this.fail) {
      return Promise.reject(new Error('panel failed'));
    }
    return Promise.resolve();
  }
}

async function rejectedKind(promise: Promise<void>): Promise<MusicFileShareErrorKind> {
  try {
    await promise;
  } catch (error) {
    return (error as MusicFileShareError).kind;
  }
  throw new Error('Expected music-file sharing to reject');
}

export default function musicFileShareCoordinatorTest() {
  describe('Music-file share coordinator', () => {
    it('passes the exact authorized URI and audio payload to the presenter once', 0, async () => {
      const source = new FakeTrackShareSource();
      const access = new FakeUriAccessActivator();
      const presenter = new FakeMusicFileSharePresenter();
      const uri = 'file://media/Audio/测试 音乐.mp3?token=%20';
      source.detail = trackDetail(uri, '测试 音乐.mp3', '测试音乐', '');
      const coordinator = new MusicFileShareCoordinator(source, access, presenter);

      await coordinator.share(TEST_CONTEXT, 7);

      expect(source.calls).assertEqual(1);
      expect(access.uris.length).assertEqual(1);
      expect(access.uris[0]).assertEqual(uri);
      expect(presenter.payloads.length).assertEqual(1);
      expect(presenter.payloads[0].kind).assertEqual(MusicFileShareDataKind.AUDIO);
      expect(presenter.payloads[0].uri).assertEqual(uri);
      expect(presenter.payloads[0].title).assertEqual('测试 音乐.mp3');
      expect(presenter.payloads[0].description).assertEqual('');
    });

    it('falls back from a blank display name to the track title', 0, async () => {
      const source = new FakeTrackShareSource();
      const access = new FakeUriAccessActivator();
      const presenter = new FakeMusicFileSharePresenter();
      source.detail = trackDetail('file://media/audio/7', '   ', 'Unicode 标题');
      const coordinator = new MusicFileShareCoordinator(source, access, presenter);

      await coordinator.share(TEST_CONTEXT, 7);

      expect(presenter.payloads[0].title).assertEqual('Unicode 标题');
      expect(presenter.payloads[0].description).assertEqual('测试艺术家');
    });

    it('rejects missing and blank-uri tracks before requesting file access', 0, async () => {
      const source = new FakeTrackShareSource();
      const access = new FakeUriAccessActivator();
      const presenter = new FakeMusicFileSharePresenter();
      const coordinator = new MusicFileShareCoordinator(source, access, presenter);

      expect(await rejectedKind(coordinator.share(TEST_CONTEXT, 7)))
        .assertEqual(MusicFileShareErrorKind.TRACK_NOT_FOUND);
      source.detail = trackDetail('   ');
      expect(await rejectedKind(coordinator.share(TEST_CONTEXT, 7)))
        .assertEqual(MusicFileShareErrorKind.URI_MISSING);
      expect(access.uris.length).assertEqual(0);
      expect(presenter.payloads.length).assertEqual(0);
    });

    it('normalizes lookup and authorization failures without opening the panel', 0, async () => {
      const source = new FakeTrackShareSource();
      const access = new FakeUriAccessActivator();
      const presenter = new FakeMusicFileSharePresenter();
      const coordinator = new MusicFileShareCoordinator(source, access, presenter);
      source.fail = true;
      expect(await rejectedKind(coordinator.share(TEST_CONTEXT, 7)))
        .assertEqual(MusicFileShareErrorKind.TRACK_LOOKUP_FAILED);

      source.fail = false;
      source.detail = trackDetail('file://media/audio/7');
      access.allowed = false;
      expect(await rejectedKind(coordinator.share(TEST_CONTEXT, 7)))
        .assertEqual(MusicFileShareErrorKind.AUTHORIZATION_FAILED);
      access.fail = true;
      expect(await rejectedKind(coordinator.share(TEST_CONTEXT, 7)))
        .assertEqual(MusicFileShareErrorKind.AUTHORIZATION_FAILED);
      expect(presenter.payloads.length).assertEqual(0);
    });

    it('maps a system-panel failure after exactly one presentation attempt', 0, async () => {
      const source = new FakeTrackShareSource();
      const access = new FakeUriAccessActivator();
      const presenter = new FakeMusicFileSharePresenter();
      source.detail = trackDetail('file://media/audio/7');
      presenter.fail = true;
      const coordinator = new MusicFileShareCoordinator(source, access, presenter);

      expect(await rejectedKind(coordinator.share(TEST_CONTEXT, 7)))
        .assertEqual(MusicFileShareErrorKind.SHARE_PANEL_FAILED);
      expect(presenter.payloads.length).assertEqual(1);
    });
  });
}
