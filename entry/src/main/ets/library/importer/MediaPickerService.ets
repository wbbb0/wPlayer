import { common } from '@kit.AbilityKit';
import { fileShare, picker } from '@kit.CoreFileKit';

const MAX_SELECT_NUMBER: number = 59160;
const PERSIST_BATCH_SIZE: number = 128;

export interface PersistPermissionResult {
  successfulUris: Array<string>;
  failedUris: Array<string>;
}

export interface ReadPermissionResult {
  successfulUris: Array<string>;
  failedUris: Array<string>;
}

export interface ReadPermissionProgress {
  processed: number;
  total: number;
  batchDurationMs: number;
}

export type ReadPermissionProgressCallback = (progress: ReadPermissionProgress) => void;

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
  onProgress?: ReadPermissionProgressCallback): Promise<ReadPermissionResult> {
  const successfulUris: Array<string> = [];
  const failedUris: Array<string> = [];
  const uniqueUris = uniqueNonEmptyUris(uris, failedUris);
  let processed = 0;
  for (let offset = 0; offset < uniqueUris.length; offset += PERSIST_BATCH_SIZE) {
    const batch = uniqueUris.slice(offset, Math.min(offset + PERSIST_BATCH_SIZE, uniqueUris.length));
    const startedAt = Date.now();
    await checkAndActivateBatch(batch, successfulUris, failedUris);
    processed += batch.length;
    onProgress?.({
      processed: processed,
      total: uniqueUris.length,
      batchDurationMs: Date.now() - startedAt
    });
    await yieldToUi();
  }
  return {
    successfulUris: successfulUris,
    failedUris: failedUris
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
  failedUris: Array<string>): Promise<void> {
  if (uris.length === 0) {
    return;
  }
  let persisted: Array<boolean>;
  try {
    persisted = await fileShare.checkPersistentPermission(createReadPolicies(uris));
  } catch (_) {
    if (uris.length === 1) {
      if (await ensureReadPermission(uris[0])) {
        successfulUris.push(uris[0]);
      } else {
        failedUris.push(uris[0]);
      }
      return;
    }
    const middle = Math.floor(uris.length / 2);
    await checkAndActivateBatch(uris.slice(0, middle), successfulUris, failedUris);
    await checkAndActivateBatch(uris.slice(middle), successfulUris, failedUris);
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
  await activateBatchWithSplit(activatableUris, successfulUris, failedUris);
}

async function activateBatchWithSplit(uris: Array<string>, successfulUris: Array<string>,
  failedUris: Array<string>): Promise<void> {
  if (uris.length === 0) {
    return;
  }
  try {
    await fileShare.activatePermission(createReadPolicies(uris));
    successfulUris.push(...uris);
  } catch (_) {
    if (uris.length === 1) {
      failedUris.push(uris[0]);
      return;
    }
    const middle = Math.floor(uris.length / 2);
    await activateBatchWithSplit(uris.slice(0, middle), successfulUris, failedUris);
    await activateBatchWithSplit(uris.slice(middle), successfulUris, failedUris);
  }
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
