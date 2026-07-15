import { common } from '@kit.AbilityKit';
import { fileShare, picker } from '@kit.CoreFileKit';

const MAX_SELECT_NUMBER: number = 59160;
const PERSIST_BATCH_SIZE: number = 128;

export interface PersistPermissionResult {
  successfulUris: Array<string>;
  failedUris: Array<string>;
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

function uniqueNonEmptyUris(uris: Array<string>, failedUris: Array<string>): Array<string> {
  const uniqueUris: Array<string> = [];
  for (const uri of uris) {
    if (uri.length === 0) {
      failedUris.push(uri);
    } else if (uniqueUris.indexOf(uri) < 0) {
      uniqueUris.push(uri);
    }
  }
  return uniqueUris;
}
