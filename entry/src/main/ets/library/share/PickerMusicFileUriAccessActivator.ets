import { ensureReadPermission } from '../importer/MediaPickerService';
import { PickerUriAccessActivator } from './MusicFileSharePorts';

export class PickerMusicFileUriAccessActivator implements PickerUriAccessActivator {
  activate(uri: string): Promise<boolean> {
    return ensureReadPermission(uri);
  }
}
