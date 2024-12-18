export class MCAssetCacheConfig {
  /** Asset 个数限制; 0 表示不限制; */
  assetCountLimit: number = 0;

  /** Asset 保存时长限制(单位: 毫秒); 0 表示不限制; */
  assetMaxDiskAge: number = 0;

  /** 所有缓存占用的磁盘空间限制(单位: 字节); 0 表示不限制; */
  allAssetsMaxDiskSize: number = 0;

  /** 磁盘空间预警阈值(单位: 字节); */
  diskSpaceWarningThreshold: number = 1024 * 1024 * 1024; // 默认 1G;
}