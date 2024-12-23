export interface MCAssetAccessLog {
  firstAccessed: string;    // 首次读写时间
  lastAccessed: string      // 最后一次访问的时间
}

export interface MCAssetAccessLog2 {
  firstAccessed: number;    // 首次读写时间
  lastAccessed: number      // 最后一次访问的时间
}