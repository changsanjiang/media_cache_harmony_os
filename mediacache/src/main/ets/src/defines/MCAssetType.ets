export enum MCAssetType {
  FILE_BASED,
  /** HTTP Live Streaming; */
  HLS,
  /** */
  DASH,
}

export const MCAssetTypeValues = [MCAssetType.FILE_BASED, MCAssetType.HLS, MCAssetType.DASH];