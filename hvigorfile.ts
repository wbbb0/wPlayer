import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { hvigor, HvigorPlugin } from '@ohos/hvigor';
import * as fs from 'fs';
import * as path from 'path';

const releaseSignedAppTaskName = 'assembleReleaseSignedApp';

const releaseSigningPlugin: HvigorPlugin = {
  pluginId: 'wplayer-release-signing',
  apply(node) {
    hvigor.nodesEvaluated(() => {
      node.registerTask({
        name: releaseSignedAppTaskName,
        dependencies: ['assembleApp'],
        run() {
          const buildProfilePath = path.resolve(__dirname, 'build-profile.json5');
          const buildProfile = JSON.parse(fs.readFileSync(buildProfilePath, 'utf8')) as {
            app?: {
              products?: Array<{ name?: string; signingConfig?: string }>;
              signingConfigs?: Array<{ name?: string }>;
            };
          };
          const product = buildProfile.app?.products?.find(item => item.name === 'default');
          const selectedSigningConfig = product?.signingConfig;
          const signingConfig = buildProfile.app?.signingConfigs?.find(
            item => item.name === selectedSigningConfig
          );
          if (selectedSigningConfig !== 'release' || signingConfig === undefined) {
            throw new Error(
              `${releaseSignedAppTaskName} requires build-profile.json5 product "default" ` +
              'to select a local signing configuration named "release"'
            );
          }
          const moduleProfilePath = path.resolve(
            __dirname,
            'entry/build/default/intermediates/package/default/module.json'
          );
          if (!fs.existsSync(moduleProfilePath)) {
            throw new Error(`Cannot verify release build metadata: ${moduleProfilePath} was not generated`);
          }
          const moduleProfile = JSON.parse(fs.readFileSync(moduleProfilePath, 'utf8')) as {
            app?: {
              buildMode?: string;
              debug?: boolean;
            };
          };
          if (moduleProfile.app?.buildMode !== 'release' || moduleProfile.app.debug !== false) {
            throw new Error(
              `${releaseSignedAppTaskName} requires Build Mode "release"; ` +
              `generated metadata is buildMode="${moduleProfile.app?.buildMode ?? 'unknown'}", ` +
              `debug=${String(moduleProfile.app?.debug)}`
            );
          }
          console.log('Release APP assembled with the local "release" signing configuration.');
        }
      });
    });
  }
};

export default {
  system: appTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: [releaseSigningPlugin]
}
