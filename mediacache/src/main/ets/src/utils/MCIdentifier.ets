import { IMCHttpRequest } from '../common/IMCHttpRequest';

namespace MCIdentifier {
  export function generateMediaIdentifierBy(proxyRequest: IMCHttpRequest): string {
    return "123";
  }

  // 获取媒体缓存的根目录
  export function getMediaRootDir(mediaIdentifier: string): string {
    return "/path"
  }
}

export default MCIdentifier;