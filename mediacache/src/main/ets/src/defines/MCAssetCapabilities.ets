/**
 * 某一 Asset 类型在库内支持的能力（与产品矩阵、README 一致）。
 *
 * 新增 MCAssetType 时需同步更新 {@link MCAssetCapabilityRegistry}。
 */
export interface MCAssetCapabilityFlags {
  /** 边播边缓存：经本地代理 `/mc_proxy` 播放 */
  readonly remotePlay: boolean;
  /** `MCMediaCache.prefetch` */
  readonly prefetch: boolean;
  /** `MCMediaCache.exportToDirectory` */
  readonly export: boolean;
  /** 导出目录经 `/mc_dir_proxy` 播放 */
  readonly localDirPlay: boolean;
}