export enum MCAssetType {
  FILE_BASED,
  /** HTTP Live Streaming; */
  HLS,
  /** MPEG-DASH */
  DASH,
}

export const MCAssetTypeValues = [MCAssetType.FILE_BASED, MCAssetType.HLS, MCAssetType.DASH];