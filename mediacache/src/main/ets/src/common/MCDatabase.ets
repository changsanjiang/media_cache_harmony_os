import { IMCMediaMetadata } from './IMCMediaMetadata';

namespace MCDatabase {
  export function queryMediaMetadata(mediaId: string): Promise<IMCMediaMetadata | undefined> {
    throw new Error("Method not implemented.");
  }

  export function saveMediaMetadata(mediaId: string, metadata: IMCMediaMetadata): Promise<void> {
    throw new Error("Method not implemented.");
  }
}

export default MCDatabase;