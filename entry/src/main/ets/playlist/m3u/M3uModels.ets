export enum M3uEncodingConfidence {
  CERTAIN = 'certain',
  LIKELY = 'likely',
  UNDETERMINED = 'undetermined'
}

export interface M3uEncodingDecision {
  label: string;
  bomLength: number;
  confidence: M3uEncodingConfidence;
  canDecodeDirectly: boolean;
  fallbackLabels: Array<string>;
}

export interface M3uEntry {
  resource: string;
  durationSeconds: number | null;
  displayTitle: string | null;
  artist: string | null;
  title: string | null;
  firstCompletedAt: number | null;
  lastCompletedAt: number | null;
  duplicateOfIndex: number | null;
  sourceLine: number;
}

export enum M3uIssueKind {
  INVALID_RESOURCE = 'invalid-resource',
  INVALID_EXTINF = 'invalid-extinf',
  INVALID_TIMESTAMP = 'invalid-timestamp'
}

export interface M3uParseIssue {
  line: number;
  kind: M3uIssueKind;
}

export interface M3uParseResult {
  entries: Array<M3uEntry>;
  issues: Array<M3uParseIssue>;
  hadHeader: boolean;
  duplicateCount: number;
  ignoredCommentCount: number;
}

export interface M3uExportEntry {
  resource: string;
  durationSeconds?: number | null;
  displayTitle?: string | null;
  artist?: string | null;
  title?: string | null;
  firstCompletedAt?: number | null;
  lastCompletedAt?: number | null;
}

export interface M3uSerializeOptions {
  lineEnding?: string;
}
