import { appTasks, OhosAppContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { getNode, hvigor, HvigorPlugin } from '@ohos/hvigor';
import * as fs from 'fs';
import * as path from 'path';

interface LocalSigningEntry {
  id: string;
  signingConfig: Record<string, object | string>;
}

interface LocalSigningConfig {
  product: string;
  defaultConfiguration: string;
  configurations: LocalSigningEntry[];
}

const rootNode = getNode(__filename);
const localSigningPath = path.resolve(__dirname, 'signing.local.json');
const releaseSignedAppTaskName = 'assembleReleaseSignedApp';

rootNode.afterNodeEvaluate(node => {
  const releaseSignedAppRequested = hvigor.isCommandEntryTask(releaseSignedAppTaskName);
  if (!releaseSignedAppRequested && process.env.WPLAYER_DISABLE_LOCAL_SIGNING === '1') {
    return;
  }
  if (!fs.existsSync(localSigningPath)) {
    if (releaseSignedAppRequested) {
      throw new Error(
        `${releaseSignedAppTaskName} requires signing.local.json with a "release" configuration`
      );
    }
    return;
  }
  const localSigning = JSON.parse(fs.readFileSync(localSigningPath, 'utf8')) as LocalSigningConfig;
  if (typeof localSigning.product !== 'string' || localSigning.product.length === 0) {
    throw new Error('signing.local.json must define a non-empty product');
  }
  if (typeof localSigning.defaultConfiguration !== 'string' ||
    localSigning.defaultConfiguration.length === 0) {
    throw new Error('signing.local.json must define a non-empty defaultConfiguration');
  }
  if (!Array.isArray(localSigning.configurations) || localSigning.configurations.length === 0) {
    throw new Error('signing.local.json must define at least one configurations entry');
  }
  const configurationIds = localSigning.configurations.map(configuration => configuration.id);
  if (configurationIds.some(id => typeof id !== 'string' || id.length === 0)) {
    throw new Error('Every signing.local.json configurations entry must define a non-empty id');
  }
  if (new Set(configurationIds).size !== configurationIds.length) {
    throw new Error('signing.local.json configuration ids must be unique');
  }
  if (localSigning.configurations.some(
    configuration => typeof configuration.signingConfig?.name !== 'string' ||
      configuration.signingConfig.name.length === 0
  )) {
    throw new Error('Every signing.local.json configuration must define signingConfig.name');
  }
  const requestedSigningConfig = process.env.WPLAYER_SIGNING_CONFIG?.trim();
  const selectedConfigurationId = releaseSignedAppRequested
    ? 'release'
    : requestedSigningConfig === undefined || requestedSigningConfig.length === 0
      ? localSigning.defaultConfiguration
      : requestedSigningConfig;
  const selectedConfiguration = localSigning.configurations.find(
    configuration => configuration.id === selectedConfigurationId
  );
  if (selectedConfiguration === undefined) {
    throw new Error(`Unknown local signing configuration: ${selectedConfigurationId}`);
  }
  const selectedSigningConfig = selectedConfiguration.signingConfig;
  const selectedSigningConfigName = selectedSigningConfig.name as string;
  const appContext = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
  const buildProfile = appContext.getBuildProfileOpt();
  buildProfile['app']['signingConfigs'] = [selectedSigningConfig];
  const products = buildProfile['app']['products'] as Array<Record<string, string>>;
  const product = products.find(item => item.name === localSigning.product);
  if (product === undefined) {
    throw new Error(`Unknown signing product: ${localSigning.product}`);
  }
  product.signingConfig = selectedSigningConfigName;
  appContext.setBuildProfileOpt(buildProfile);
});

const releaseSigningPlugin: HvigorPlugin = {
  pluginId: 'wplayer-release-signing',
  apply(node) {
    hvigor.nodesEvaluated(() => {
      node.registerTask({
        name: releaseSignedAppTaskName,
        dependencies: ['assembleApp'],
        run() {
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
