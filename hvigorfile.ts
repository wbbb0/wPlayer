import { appTasks, OhosAppContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { getNode } from '@ohos/hvigor';
import * as fs from 'fs';
import * as path from 'path';

interface LocalSigningConfig {
  product: string;
  signingConfig: Record<string, object | string>;
}

const rootNode = getNode(__filename);
const localSigningPath = path.resolve(__dirname, 'signing.local.json');

rootNode.afterNodeEvaluate(node => {
  if (process.env.WPLAYER_DISABLE_LOCAL_SIGNING === '1' || !fs.existsSync(localSigningPath)) {
    return;
  }
  const localSigning = JSON.parse(fs.readFileSync(localSigningPath, 'utf8')) as LocalSigningConfig;
  if (localSigning.product.length === 0 || typeof localSigning.signingConfig.name !== 'string') {
    throw new Error('signing.local.json must define product and signingConfig.name');
  }
  const appContext = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
  const buildProfile = appContext.getBuildProfileOpt();
  buildProfile['app']['signingConfigs'] = [localSigning.signingConfig];
  const products = buildProfile['app']['products'] as Array<Record<string, string>>;
  const product = products.find(item => item.name === localSigning.product);
  if (product === undefined) {
    throw new Error(`Unknown signing product: ${localSigning.product}`);
  }
  product.signingConfig = localSigning.signingConfig.name as string;
  appContext.setBuildProfileOpt(buildProfile);
});

export default {
  system: appTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: []       /* Custom plugin to extend the functionality of Hvigor. */
}
