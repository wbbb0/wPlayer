import {
  LyricsAvailability
} from '../../playback/model/PlaybackModels';
import { ArtworkLayout } from '../artwork/ArtworkLayout';
import {
  FullPlayerPage,
  FullPlayerPagerSpec,
  PlayerFrame,
  PlayerMorphPhase
} from './PlayerMotion';

export enum FullPlayerImmersivePhase {
  NORMAL,
  ENTERING,
  IMMERSIVE,
  EXITING
}

export class FullPlayerArtworkStagePolicy {
  static readonly IMMERSIVE_DURATION: number = 420;
  static readonly IMMERSIVE_SPRING_RESPONSE: number = 0.42;
  static readonly IMMERSIVE_SPRING_DAMPING: number = 0.86;
  static readonly IMMERSIVE_ARTWORK_INSET: number = 20;

  static immersiveFrame(rootFrame: PlayerFrame, topInset: number, bottomInset: number,
    sourceWidth: number, sourceHeight: number): PlayerFrame {
    return FullPlayerArtworkStagePolicy.immersiveFrameInViewport(
      rootFrame, topInset, bottomInset, sourceWidth, sourceHeight
    );
  }

  static immersiveFrameInViewport(viewportFrame: PlayerFrame, topInset: number,
    bottomInset: number, sourceWidth: number, sourceHeight: number): PlayerFrame {
    const inset = FullPlayerArtworkStagePolicy.IMMERSIVE_ARTWORK_INSET;
    const availableX = viewportFrame.x + inset;
    const availableY = viewportFrame.y + topInset + inset;
    const availableWidth = Math.max(1, viewportFrame.width - inset * 2);
    const availableHeight = Math.max(
      1,
      viewportFrame.height - topInset - bottomInset - inset * 2
    );
    const size = ArtworkLayout.containedSizeWithSquareFallback(
      sourceWidth,
      sourceHeight,
      availableWidth,
      availableHeight
    );
    return {
      x: availableX + (availableWidth - size.width) / 2,
      y: availableY + (availableHeight - size.height) / 2,
      width: size.width,
      height: size.height
    };
  }

  static normalFrame(viewportFrame: PlayerFrame, sourceWidth: number,
    sourceHeight: number): PlayerFrame {
    const size = ArtworkLayout.containedSizeWithSquareFallback(
      sourceWidth,
      sourceHeight,
      viewportFrame.width,
      viewportFrame.height
    );
    return {
      x: viewportFrame.x + (viewportFrame.width - size.width) / 2,
      y: viewportFrame.y + (viewportFrame.height - size.height) / 2,
      width: size.width,
      height: size.height
    };
  }

  static interpolateFrame(normalFrame: PlayerFrame, immersiveFrame: PlayerFrame,
    progress: number): PlayerFrame {
    const value = Math.max(0, Math.min(1, progress));
    return {
      x: normalFrame.x + (immersiveFrame.x - normalFrame.x) * value,
      y: normalFrame.y + (immersiveFrame.y - normalFrame.y) * value,
      width: normalFrame.width + (immersiveFrame.width - normalFrame.width) * value,
      height: normalFrame.height + (immersiveFrame.height - normalFrame.height) * value
    };
  }

  static scaledFrame(frame: PlayerFrame, scale: number): PlayerFrame {
    const value = Math.max(0, scale);
    const width = frame.width * value;
    const height = frame.height * value;
    return {
      x: frame.x + (frame.width - width) / 2,
      y: frame.y + (frame.height - height) / 2,
      width: width,
      height: height
    };
  }

  static shouldShowPager(phase: PlayerMorphPhase, pagerReady: boolean,
    closeHandoffActive: boolean, closeActorReady: boolean): boolean {
    if (!pagerReady) {
      return false;
    }
    if (phase === PlayerMorphPhase.OPEN) {
      return true;
    }
    return closeHandoffActive && !closeActorReady;
  }

  static shadowSafePagerFrame(viewportFrame: PlayerFrame, shadowRadius: number,
    shadowOffsetY: number): PlayerFrame {
    const radius = Math.max(0, shadowRadius);
    const topOverflow = radius + Math.max(0, -shadowOffsetY);
    const bottomOverflow = radius + Math.max(0, shadowOffsetY);
    return {
      x: viewportFrame.x,
      y: viewportFrame.y - topOverflow,
      width: viewportFrame.width,
      height: viewportFrame.height + topOverflow + bottomOverflow
    };
  }

  static chromeTranslation(rootHeight: number, progress: number): number {
    return Math.max(0, rootHeight) * Math.max(0, Math.min(1, progress));
  }
}

export class FullPlayerImmersiveLayoutPolicy {
  static splitTarget(paneCount: number, availability: LyricsAvailability,
    resolvedProgress: number, wideLyricsEnabled: boolean = true): number {
    if (!wideLyricsEnabled) {
      return 0;
    }
    if (availability === LyricsAvailability.LOADING) {
      return Math.max(0, Math.min(1, resolvedProgress));
    }
    return paneCount > 1 && availability === LyricsAvailability.AVAILABLE ? 1 : 0;
  }

  static entryPagePosition(currentPosition: number, paneCount: number,
    availability: LyricsAvailability, resolvedSplitProgress: number,
    wideLyricsEnabled: boolean = true): number {
    if (!wideLyricsEnabled) {
      return currentPosition;
    }
    const preservesResolvedLyrics = availability === LyricsAvailability.LOADING &&
      resolvedSplitProgress >= 0.5;
    if (paneCount > 1 &&
      (availability === LyricsAvailability.AVAILABLE || preservesResolvedLyrics)) {
      return FullPlayerPagerSpec.positionForPage(FullPlayerPage.LYRICS, paneCount);
    }
    return currentPosition;
  }
}
