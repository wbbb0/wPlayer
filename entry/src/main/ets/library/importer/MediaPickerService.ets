import { common } from '@kit.AbilityKit';
import { fileShare, picker } from '@kit.CoreFileKit';
import { ImportConcurrencyPolicy } from './ImportConcurrencyPolicy';

const MAX_SELECT_NUMBER: number = 59160;
const PERSIST_BATCH_SIZE: number = 128;

export interface PersistPermissionResult {
  successfulUris: Array<string>;
  failedUris: Array<string>;
}

export interface ReadPermissionResult {
  successfulUris: Array<string>;
  failedUris: Array<string>;
  cancelled: boolean;
}

export interface ReadPermissionProgress {
  processed: number;
  total: number;
  batchDurationMs: number;
}

export type ReadPermissionProgressCallback = (progress: ReadPermissionProgress) => void;

export interface ReadPermissionBatchResult {
  successfulUris: Array<string>;
  failedUris: Array<string>;
}

export type ReadPermissionBatchCallback =
  (result: ReadPermissionBatchResult) => Promise<void>;

export interface ReadPermissionControl {
  shouldContinue?: () => boolean;
  onBatch?: ReadPermissionBatchCallback;
}

/**
 * Opens the system document picker for the audio formats supported by the
 * initial importer. Returned values remain opaque authorization-managed URIs.
 */
export async function selectAudioFiles(context: common.UIAbilityContext): Promise<Array<string>> {
  const options = new picker.DocumentSelectOptions();
  options.fileSuffixFilters = ['音频|.mp3,.flac'];
  options.maxSelectNumber = MAX_SELECT_NUMBER;
  const documentPicker = new picker.DocumentViewPicker(context);
  return documentPicker.select(options);
}

/**
 * Persists read access while the picker-granted temporary permission is still
 * active. A failed batch is retried item by item so one bad URI does not hide
 * successful authorizations for the rest of the selection.
 */
export async function persistReadPermissions(uris: Array<string>): Promise<PersistPermissionResult> {
  const successfulUris: Array<string> = [];
  const failedUris: Array<string> = [];
  const uniqueUris = uniqueNonEmptyUris(uris, failedUris);

  for (let offset = 0; offset < uniqueUris.length; offset += PERSIST_BATCH_SIZE) {
    const batch = uniqueUris.slice(offset, Math.min(offset + PERSIST_BATCH_SIZE, uniqueUris.length));
    const policies = createReadPolicies(batch);
    try {
      await fileShare.persistPermission(policies);
      successfulUris.push(...batch);
    } catch (_) {
      await persistIndividually(batch, successfulUris, failedUris);
    }
    await yieldToUi();
  }

  return {
    successfulUris: successfulUris,
    failedUris: failedUris
  };
}

/**
 * Activates a previously persisted read permission only when it is needed.
 * False means the URI must be re-authorized or the capability is unavailable.
 */
export async function ensureReadPermission(uri: string): Promise<boolean> {
  if (uri.length === 0) {
    return false;
  }
  const policy = createReadPolicy(uri);
  try {
    const persisted = await fileShare.checkPersistentPermission([policy]);
    if (persisted.length !== 1 || !persisted[0]) {
      return false;
    }
    await fileShare.activatePermission([policy]);
    return true;
  } catch (_) {
    return false;
  }
}

/** Checks and activates persisted permissions in batches for library maintenance. */
export async function ensureReadPermissions(uris: Array<string>,
  onProgress?: ReadPermissionProgressCallback,
  control?: ReadPermissionControl): Promise<ReadPermissionResult> {
  const successfulUris: Array<string> = [];
  const failedUris: Array<string> = [];
  const uniqueUris = uniqueNonEmptyUris(uris, failedUris);
  let cancelled = false;
  for (let offset = 0; offset < uniqueUris.length;
    offset += ImportConcurrencyPolicy.FILE_PERMISSION_BATCH_SIZE) {
    if (!shouldContinue(control)) {
      cancelled = true;
      break;
    }
    const batch = uniqueUris.slice(
      offset,
      Math.min(offset + ImportConcurrencyPolicy.FILE_PERMISSION_BATCH_SIZE, uniqueUris.length)
    );
    const batchSuccessful: Array<string> = [];
    const batchFailed: Array<string> = [];
    const startedAt = Date.now();
    await checkAndActivateBatch(
      batch,
      batchSuccessful,
      batchFailed,
      control?.shouldContinue
    );
    successfulUris.push(...batchSuccessful);
    failedUris.push(...batchFailed);
    if (batchSuccessful.length > 0 || batchFailed.length > 0) {
      await control?.onBatch?.({
        successfulUris: batchSuccessful,
        failedUris: batchFailed
      });
    }
    const processed = successfulUris.length + failedUris.length;
    onProgress?.({
      processed: processed,
      total: uniqueUris.length,
      batchDurationMs: Date.now() - startedAt
    });
    if (!shouldContinue(control)) {
      cancelled = true;
      break;
    }
    await yieldToUi();
  }
  return {
    successfulUris: successfulUris,
    failedUris: failedUris,
    cancelled: cancelled
  };
}

export async function revokeReadPermissions(uris: Array<string>): Promise<void> {
  const uniqueUris = uniqueNonEmptyUris(uris, []);
  for (let offset = 0; offset < uniqueUris.length; offset += PERSIST_BATCH_SIZE) {
    const batch = uniqueUris.slice(offset, Math.min(offset + PERSIST_BATCH_SIZE, uniqueUris.length));
    try {
      await fileShare.revokePermission(createReadPolicies(batch));
    } catch (_) {
      for (const uri of batch) {
        try {
          await fileShare.revokePermission([createReadPolicy(uri)]);
        } catch (_) {
          console.warn('Unable to revoke one unused persisted permission');
        }
      }
    }
    await yieldToUi();
  }
}

function createReadPolicy(uri: string): fileShare.PolicyInfo {
  return {
    uri: uri,
    operationMode: fileShare.OperationMode.READ_MODE
  };
}

function createReadPolicies(uris: Array<string>): Array<fileShare.PolicyInfo> {
  const policies: Array<fileShare.PolicyInfo> = [];
  for (const uri of uris) {
    policies.push(createReadPolicy(uri));
  }
  return policies;
}

async function persistIndividually(uris: Array<string>, successfulUris: Array<string>,
  failedUris: Array<string>): Promise<void> {
  for (const uri of uris) {
    try {
      await fileShare.persistPermission([createReadPolicy(uri)]);
      successfulUris.push(uri);
    } catch (_) {
      failedUris.push(uri);
    }
  }
}

async function checkAndActivateBatch(uris: Array<string>, successfulUris: Array<string>,
  failedUris: Array<string>, shouldContinue?: () => boolean): Promise<void> {
  if (uris.length === 0 || !canContinue(shouldContinue)) {
    return;
  }
  let persisted: Array<boolean>;
  try {
    persisted = await fileShare.checkPersistentPermission(createReadPolicies(uris));
  } catch (_) {
    if (!canContinue(shouldContinue)) {
      return;
    }
    if (uris.length === 1) {
      if (await ensureReadPermission(uris[0])) {
        if (canContinue(shouldContinue)) {
          successfulUris.push(uris[0]);
        }
      } else {
        if (canContinue(shouldContinue)) {
          failedUris.push(uris[0]);
        }
      }
      return;
    }
    const middle = Math.floor(uris.length / 2);
    await checkAndActivateBatch(
      uris.slice(0, middle), successfulUris, failedUris, shouldContinue
    );
    if (!canContinue(shouldContinue)) {
      return;
    }
    await yieldToUi();
    await checkAndActivateBatch(
      uris.slice(middle), successfulUris, failedUris, shouldContinue
    );
    return;
  }
  if (!canContinue(shouldContinue)) {
    return;
  }
  const activatableUris: Array<string> = [];
  for (let index = 0; index < uris.length; index += 1) {
    if (index < persisted.length && persisted[index]) {
      activatableUris.push(uris[index]);
    } else {
      failedUris.push(uris[index]);
    }
  }
  if (!canContinue(shouldContinue)) {
    return;
  }
  await yieldToUi();
  await activateBatchWithSplit(
    activatableUris, successfulUris, failedUris, shouldContinue
  );
}

async function activateBatchWithSplit(uris: Array<string>, successfulUris: Array<string>,
  failedUris: Array<string>, shouldContinue?: () => boolean): Promise<void> {
  if (uris.length === 0 || !canContinue(shouldContinue)) {
    return;
  }
  try {
    await fileShare.activatePermission(createReadPolicies(uris));
    if (canContinue(shouldContinue)) {
      successfulUris.push(...uris);
    }
  } catch (_) {
    if (!canContinue(shouldContinue)) {
      return;
    }
    if (uris.length === 1) {
      failedUris.push(uris[0]);
      return;
    }
    const middle = Math.floor(uris.length / 2);
    await activateBatchWithSplit(
      uris.slice(0, middle), successfulUris, failedUris, shouldContinue
    );
    if (!canContinue(shouldContinue)) {
      return;
    }
    await yieldToUi();
    await activateBatchWithSplit(
      uris.slice(middle), successfulUris, failedUris, shouldContinue
    );
  }
}

function shouldContinue(control?: ReadPermissionControl): boolean {
  return control?.shouldContinue === undefined || control.shouldContinue();
}

function canContinue(shouldContinue?: () => boolean): boolean {
  return shouldContinue === undefined || shouldContinue();
}

function uniqueNonEmptyUris(uris: Array<string>, failedUris: Array<string>): Array<string> {
  const uniqueUris: Array<string> = [];
  const seen: Set<string> = new Set<string>();
  for (const uri of uris) {
    if (uri.length === 0) {
      failedUris.push(uri);
    } else if (!seen.has(uri)) {
      seen.add(uri);
      uniqueUris.push(uri);
    }
  }
  return uniqueUris;
}

function yieldToUi(): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, 0);
  });
}
