import { rcp } from '@kit.RemoteCommunicationKit';
import { MCAssetType } from '../defines/MCAssetType';

namespace MCConfigs {
  export let resolveAssetType: ((resUrl: string) => MCAssetType | Promise<MCAssetType>) | undefined = undefined;
  export let resolveAssetIdentifier: ((resUrl: string) => string | Promise<string>) | undefined = undefined;

  export let sessionConfiguration: rcp.SessionConfiguration | undefined = undefined;
  export let ignoredHeaders = ['host', "user-agent"]
}

export default MCConfigs;