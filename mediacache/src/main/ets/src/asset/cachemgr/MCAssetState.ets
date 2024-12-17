export interface MCAssetState {
  /** 标记资产是否"固定"在缓存中, 即使超出限制也不被删除; */
  isPinned: boolean;
}