export enum MCCopyFileConflictStrategy {
  /** 如果存在同名文件则跳过 */
  Skip,
  /** 如果存在同名文件则覆盖 */
  Overwrite,
  /** 如果存在同名文件则报错 */
  Throw
}