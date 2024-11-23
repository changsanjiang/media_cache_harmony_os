namespace MCDatabase {
  export interface IMCMediaMetadata {
    readonly contentType: string;
    readonly totalLength: number;
    readonly byteRangeAccessSupported: boolean;
  }

  export function queryMediaMetadata(mediaId: string): Promise<IMCMediaMetadata | undefined> {
    throw new Error("Method not implemented.");
  }

  export function saveMediaMetadata(mediaId: string, metadata: IMCMediaMetadata): Promise<void> {
    throw new Error("Method not implemented.");
  }
}

export default MCDatabase;