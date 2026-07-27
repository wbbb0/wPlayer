import { describe, expect, it } from '@ohos/hypium';
import { PlaybackSourcePreparation } from '../main/ets/playback/engine/PlaybackSourcePreparation';

function resolved(): Promise<void> {
  return Promise.resolve();
}

export default function playbackSourcePreparationTest() {
  describe('PlaybackSourcePreparation', () => {
    it('discards a source when attachment fails before initialization', 0, async () => {
      const events: Array<string> = [];
      let rejected = false;
      const attachError = new Error('attach failed');
      let rejectInitialized: (error: Error) => void = (_error: Error): void => {};
      const initialized = new Promise<void>((_resolve, reject) => {
        rejectInitialized = reject;
      });

      try {
        await PlaybackSourcePreparation.run(
          initialized,
          (): void => {
            events.push('attach');
            throw attachError;
          },
          (): void => {
            events.push('configure');
          },
          (): Promise<void> => resolved(),
          (): void => {
            events.push('current');
          },
          async (): Promise<void> => {
            events.push('discard');
            rejectInitialized(new Error('source abandoned'));
          }
        );
      } catch (error) {
        rejected = error === attachError;
      }

      expect(rejected).assertTrue();
      expect(events.join(',')).assertEqual('attach,discard');
    });

    it('discards a source when initialization or prepare fails', 0, async () => {
      const initializationEvents: Array<string> = [];
      const initializationError = new Error('initialization failed');
      let caughtInitialization: Error | undefined;
      try {
        await PlaybackSourcePreparation.run(
          Promise.reject(initializationError),
          (): void => {
            initializationEvents.push('attach');
          },
          (): void => {
            initializationEvents.push('configure');
          },
          (): Promise<void> => resolved(),
          (): void => {
            initializationEvents.push('current');
          },
          async (): Promise<void> => {
            initializationEvents.push('discard');
          }
        );
      } catch (error) {
        if (error instanceof Error) {
          caughtInitialization = error;
        }
      }
      expect(initializationEvents.join(',')).assertEqual('attach,discard');
      expect(caughtInitialization === initializationError).assertTrue();

      const prepareEvents: Array<string> = [];
      const prepareError = new Error('prepare failed');
      let caughtPrepare: Error | undefined;
      try {
        await PlaybackSourcePreparation.run(
          resolved(),
          (): void => {
            prepareEvents.push('attach');
          },
          (): void => {
            prepareEvents.push('configure');
          },
          async (): Promise<void> => {
            prepareEvents.push('prepare');
            throw prepareError;
          },
          (): void => {
            prepareEvents.push('current');
          },
          async (): Promise<void> => {
            prepareEvents.push('discard');
          }
        );
      } catch (error) {
        if (error instanceof Error) {
          caughtPrepare = error;
        }
      }
      expect(prepareEvents.join(',')).assertEqual(
        'attach,current,configure,prepare,discard'
      );
      expect(caughtPrepare === prepareError).assertTrue();
    });

    it('preserves a superseded error and discards after prepare', 0, async () => {
      const superseded = new Error('superseded');
      let currentChecks = 0;
      let caught: Error | undefined;
      let discarded = false;

      try {
        await PlaybackSourcePreparation.run(
          resolved(),
          (): void => {},
          (): void => {},
          (): Promise<void> => resolved(),
          (): void => {
            currentChecks += 1;
            if (currentChecks === 2) {
              throw superseded;
            }
          },
          async (): Promise<void> => {
            discarded = true;
          }
        );
      } catch (error) {
        if (error instanceof Error) {
          caught = error;
        }
      }

      expect(discarded).assertTrue();
      expect(caught === superseded).assertTrue();
    });
  });
}
