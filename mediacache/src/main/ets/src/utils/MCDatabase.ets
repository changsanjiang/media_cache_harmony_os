import { IMCMediaMetadata } from '../defines/IMCMediaMetadata';

namespace MCDatabase {
  // TODO: next 插入到数据库;
  const mData: Map<string, IMCMediaMetadata> = new Map();

  export async function queryMediaMetadata(mediaId: string): Promise<IMCMediaMetadata | undefined> {
    return mData.get(mediaId);
  }

  export async function saveMediaMetadata(mediaId: string, metadata: IMCMediaMetadata): Promise<void> {
    mData.set(mediaId, metadata);
  }
}

export default MCDatabase;