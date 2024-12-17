namespace MCAssetCacheConfig {
  /** Asset 个数限制; */
  export let assetCountLimit: number = 0;

  /** Asset 保存时长限制(单位: 毫秒); */
  export let assetMaxDiskAge: number = 0;

  /** 所有缓存占用的磁盘空间限制(单位: 字节); */
  export let allAssetsMaxDiskSize: number = 0;

  /** 磁盘空间预警阈值(单位: 字节); */
  export let diskSpaceWarningThreshold: number = 1024 * 1024 * 1024; // 默认 1G;
}

export default MCAssetCacheConfig;