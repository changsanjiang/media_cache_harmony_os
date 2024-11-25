import { rcp } from '@kit.RemoteCommunicationKit';

namespace MCConfigs {
  export let downloadSessionConfiguration: rcp.SessionConfiguration | undefined = undefined;
  export let proxyRequestIgnoredHeaders = ['host', "user-agent"]
}

export default MCConfigs;