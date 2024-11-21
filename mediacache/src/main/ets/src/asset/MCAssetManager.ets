import { IMCDataReader } from '../common/IMCDataReader';
import { IMCHttpRequest } from '../common/IMCHttpRequest';

namespace MCAssetManager {
  export function createDataReader(request: IMCHttpRequest): IMCDataReader {
    throw new Error("Method not implemented.");
  }
}

export default MCAssetManager;

// @protocol MCSResponse <NSObject>
// @property (nonatomic, readonly) NSUInteger totalLength;
// @property (nonatomic, readonly) NSRange range; // 206请求时length不为0
// @property (nonatomic, copy, readonly) NSString *contentType; // default is "application/octet-stream"
// @end