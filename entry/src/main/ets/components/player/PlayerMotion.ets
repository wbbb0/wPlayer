export interface PlayerFrame {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface PlayerPoint {
  x: number;
  y: number;
}

export enum PlayerGestureAxis {
  UNDECIDED,
  HORIZONTAL,
  VERTICAL
}

export enum PlayerMorphPhase {
  IDLE,
  OPEN_DRAGGING,
  CLOSE_DRAGGING,
  OPENING,
  OPEN,
  CLOSING,
  BACKGROUND_HANDOFF
}

export enum FullPlayerPage {
  QUEUE = 0,
  COVER = 1,
  LYRICS = 2
}

export const FULL_PLAYER_VERTICAL_GESTURE_HOST_ID: string = 'full_player_vertical_gesture_host';
export const FULL_PLAYER_HORIZONTAL_GESTURE_HOST_ID: string = 'full_player_horizontal_gesture_host';

export class FullPlayerPagerSpec {
  static readonly PAGE_COUNT: number = 3;
  static readonly SWIPE_COMPLETION_FRACTION: number = 0.12;
  static readonly SWIPE_COMPLETION_MAX_DISTANCE: number = 56;
  static readonly SIDE_PAGE_HANDOFF_FRACTION: number = 0.3;
  static readonly SIDE_PAGE_EXIT_DISTANCE_FRACTION: number = 0.06;
  static readonly PAGE_SETTLE_SPRING_RESPONSE: number = 0.42;
  static readonly PAGE_SETTLE_SPRING_DAMPING: number = 0.88;
  static readonly SIDE_PAGE_ARTWORK_FADE_END_PROGRESS: number = 0.6;

  static paneCount(width: number, height: number): number {
    return width > height ? 2 : 1;
  }

  static pageSpan(viewportWidth: number, paneCount: number): number {
    return viewportWidth / Math.max(1, paneCount);
  }

  static maximumPosition(paneCount: number): number {
    return Math.max(0, FullPlayerPagerSpec.PAGE_COUNT - Math.max(1, paneCount));
  }

  static clampPosition(position: number, paneCount: number): number {
    return Math.max(0, Math.min(FullPlayerPagerSpec.maximumPosition(paneCount), position));
  }

  static swipeCompletionDistance(pageSpan: number): number {
    return Math.min(
      Math.max(0, pageSpan) * FullPlayerPagerSpec.SWIPE_COMPLETION_FRACTION,
      FullPlayerPagerSpec.SWIPE_COMPLETION_MAX_DISTANCE
    );
  }

  static positionForPage(page: FullPlayerPage, paneCount: number): number {
    if (paneCount > 1) {
      return page === FullPlayerPage.QUEUE ? 0 : 1;
    }
    return page;
  }

  static nearestPage(position: number, paneCount: number): FullPlayerPage {
    if (paneCount > 1) {
      return position < 0.5 ? FullPlayerPage.QUEUE : FullPlayerPage.LYRICS;
    }
    return Math.round(FullPlayerPagerSpec.clampPosition(position, paneCount)) as FullPlayerPage;
  }

  static coverVisibility(position: number, paneCount: number, expandProgress: number): number {
    if (paneCount > 1) {
      return 1;
    }
    const visibleInPager = Math.max(0, 1 - Math.abs(position - FullPlayerPage.COVER));
    const transitionReveal = Math.max(0, Math.min(1,
      (1 - expandProgress) / FullPlayerPagerSpec.SIDE_PAGE_HANDOFF_FRACTION));
    return Math.max(visibleInPager, transitionReveal);
  }

  static sideHandoffReveal(expandProgress: number): number {
    return Math.max(0, Math.min(1,
      (1 - expandProgress) / FullPlayerPagerSpec.SIDE_PAGE_HANDOFF_FRACTION));
  }

  static sidePageExitDistance(pageSpan: number, expandProgress: number): number {
    const handoffProgress = Math.max(0, Math.min(1,
      (1 - expandProgress) / FullPlayerPagerSpec.SIDE_PAGE_HANDOFF_FRACTION));
    return pageSpan * FullPlayerPagerSpec.SIDE_PAGE_EXIT_DISTANCE_FRACTION * handoffProgress;
  }

  static artworkTargetX(layoutX: number, pagePosition: number, pageSpan: number): number {
    return layoutX - pagePosition * pageSpan;
  }

  static centeredArtworkTargetX(layoutX: number, pageSpan: number): number {
    return layoutX - FullPlayerPage.COVER * pageSpan;
  }

  static pagerArtworkTargetX(centeredX: number, pagePosition: number, pageSpan: number): number {
    return centeredX + (FullPlayerPage.COVER - pagePosition) * pageSpan;
  }

  static sidePageArtworkOpacity(expandProgress: number): number {
    return 1 - Math.max(0, Math.min(1,
      expandProgress / FullPlayerPagerSpec.SIDE_PAGE_ARTWORK_FADE_END_PROGRESS));
  }
}

export class PlayerMotionSpec {
  static readonly COLLAPSED_SURFACE_DARK: string = '#FF2B2B2B';
  static readonly COLLAPSED_SURFACE_LIGHT: string = '#FFFFFFFF';
  static readonly GESTURE_COMPLETION_FRACTION: number = 0.28;
  static readonly GESTURE_COMPLETION_MAX_DISTANCE: number = 120;
  static readonly OPEN_DURATION: number = 420;
  static readonly CLOSE_DURATION: number = 340;
  static readonly CANCEL_DURATION: number = 280;
  static readonly CLOSE_CANCEL_DURATION: number = 240;
  static readonly BACKGROUND_HANDOFF_DURATION: number = 140;
  static readonly OPEN_SPRING_RESPONSE: number = 0.48;
  static readonly OPEN_SPRING_DAMPING: number = 0.88;
  static readonly CLOSE_CURVE_X1: number = 0.2;
  static readonly CLOSE_CURVE_Y1: number = 0;
  static readonly CLOSE_CURVE_X2: number = 0.1;
  static readonly CLOSE_CURVE_Y2: number = 1;
  static readonly GESTURE_AXIS_LOCK_DISTANCE: number = 4;
  static readonly HORIZONTAL_SWIPE_RESISTANCE: number = 120;
  static readonly HORIZONTAL_HAPTIC_THRESHOLD: number = 48;
  static readonly FULL_CONTENT_COLLAPSE_FADE_START: number = 0.2;
  static readonly FULL_CONTENT_COLLAPSE_FADE_END: number = 0.8;
  static readonly MINI_CONTENT_FADE_START: number = 0.08;
  static readonly MINI_CONTENT_FADE_RATE: number = 4.2;
  static readonly MINI_CONTENT_VISIBLE_LIMIT: number = 0.32;
  static readonly FULL_ARTWORK_SHADOW_RADIUS: number = 52;
  static readonly FULL_ARTWORK_SHADOW_OFFSET_Y: number = 28;
  static readonly PAUSED_ARTWORK_SHADOW_RADIUS: number = 38;
  static readonly PAUSED_ARTWORK_SHADOW_OFFSET_Y: number = 20;
  static readonly PAUSED_ARTWORK_SCALE: number = 0.90;
  static readonly ARTWORK_STATE_SPRING_RESPONSE: number = 0.36;
  static readonly ARTWORK_STATE_SPRING_DAMPING: number = 0.72;
  static readonly LYRIC_FOCUS_DURATION: number = 100;

  static distanceFromRecognitionOrigin(offset: number): number {
    const magnitude = Math.max(0, Math.abs(offset) - PlayerMotionSpec.GESTURE_AXIS_LOCK_DISTANCE);
    return offset < 0 ? -magnitude : magnitude;
  }

  static fullContentOpacity(expandProgress: number): number {
    const normalizedExpandProgress = Math.max(0, Math.min(1, expandProgress));
    const collapseProgress = 1 - normalizedExpandProgress;
    const fadeProgress = (collapseProgress - PlayerMotionSpec.FULL_CONTENT_COLLAPSE_FADE_START) /
      (PlayerMotionSpec.FULL_CONTENT_COLLAPSE_FADE_END -
        PlayerMotionSpec.FULL_CONTENT_COLLAPSE_FADE_START);
    const opacity = 1 - Math.max(0, Math.min(1, fadeProgress));
    return Math.round(opacity * 1000000) / 1000000;
  }
}

export class PlayerLayoutSpec {
  static readonly DEFAULT_MINI_PLAYER_SIZE: number = 56;
  static readonly DEFAULT_ARTWORK_TARGET_X: number = 127;
  static readonly DEFAULT_ARTWORK_TARGET_Y: number = 180;
  static readonly MINI_ARTWORK_SIZE: number = 48;
  static readonly MINI_ARTWORK_RADIUS: number = 24;
  static readonly FULL_ARTWORK_SIZE: number = 286;
  static readonly FULL_ARTWORK_RADIUS: number = 10;
  static readonly MINI_ARTWORK_INSET: number = 4;
  static readonly FULL_PLAYER_HORIZONTAL_INSET: number = 28;
  static readonly FULL_PLAYER_NON_ARTWORK_HEIGHT: number = 310;
  static readonly FULL_PLAYER_TOP_INSET: number = 18;
  static readonly FULL_PLAYER_BOTTOM_INSET: number = 10;
  static readonly FULL_PLAYER_PAGE_HORIZONTAL_INSET: number = 20;
  static readonly FULL_PLAYER_LYRICS_HORIZONTAL_INSET: number = 28;
  static readonly FULL_PLAYER_PAGE_TOP_INSET: number = 12;
  static readonly FULL_PLAYER_CLOSE_BUTTON_SIZE: number = 52;
  static readonly FULL_PLAYER_CLOSE_ICON_SIZE: number =
    PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE * 0.45;
  static readonly FULL_PLAYER_HEADER_TEXT_GAP: number = 12;
  static readonly FULL_PLAYER_QUEUE_INDEX_WIDTH: number = 28;
  static readonly FULL_PLAYER_QUEUE_ARTWORK_SIZE: number = 52;
  static readonly FULL_PLAYER_QUEUE_ROW_VERTICAL_INSET: number = 8;
  static readonly FULL_PLAYER_QUEUE_DIVIDER_HEIGHT: number = 1;
  static readonly FULL_PLAYER_QUEUE_ITEM_HEIGHT: number =
    PlayerLayoutSpec.FULL_PLAYER_QUEUE_ARTWORK_SIZE +
      PlayerLayoutSpec.FULL_PLAYER_QUEUE_ROW_VERTICAL_INSET * 2 +
      PlayerLayoutSpec.FULL_PLAYER_QUEUE_DIVIDER_HEIGHT;
  static readonly FULL_PLAYER_QUEUE_SHADOW_CLEARANCE: number = 14;
  static readonly FULL_PLAYER_QUEUE_CONTENT_HORIZONTAL_INSET: number = 6;
  static readonly FULL_PLAYER_QUEUE_DIVIDER_OPACITY: number = 0.3;
  static readonly FULL_PLAYER_QUEUE_SHADOW_RADIUS: number = 14;
  static readonly FULL_PLAYER_QUEUE_SHADOW_OFFSET_Y: number = 4;
  static readonly FULL_PLAYER_TITLE_SIZE: number = 23;
  static readonly FULL_PLAYER_ARTIST_SIZE: number = 14;
  static readonly FULL_PLAYER_PROGRESS_TRACK_THICKNESS: number = 3;
  static readonly MORPH_SURFACE_RADIUS: number = 28;

  static fullArtworkSize(rootWidth: number, rootHeight: number,
    topInset: number, bottomInset: number): number {
    if (rootWidth <= 0 || rootHeight <= 0) {
      return PlayerLayoutSpec.FULL_ARTWORK_SIZE;
    }
    const widthLimit = rootWidth - PlayerLayoutSpec.FULL_PLAYER_HORIZONTAL_INSET * 2;
    const heightLimit = rootHeight - topInset - bottomInset -
      PlayerLayoutSpec.FULL_PLAYER_NON_ARTWORK_HEIGHT;
    return Math.max(1, Math.min(widthLimit, heightLimit));
  }
}
