import { IMCMediaMetadata } from '../defines/IMCMediaMetadata';
import { ArkTSUtils } from '@kit.ArkTS';

namespace MCDatabase {
  const mLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock();
  // TODO: next 插入到数据库;
  const mData: Map<string, IMCMediaMetadata> = new Map();

  export function queryMediaMetadata(mediaId: string): Promise<IMCMediaMetadata | undefined> {
    return mLock.lockAsync(() => mData.get(mediaId));
  }

  export function saveMediaMetadata(mediaId: string, metadata: IMCMediaMetadata): Promise<void> {
    return mLock.lockAsync(() => { mData.set(mediaId, metadata) });
  }
}

export default MCDatabase;