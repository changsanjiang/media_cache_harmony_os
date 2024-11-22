import { IMCReadwriteReference } from "./IMCReadwriteReference";

export interface IMCMediaContent extends IMCReadwriteReference<IMCMediaContent> {
  readData(position: number, capacity: number): Promise<ArrayBuffer>; // 读取指定位置的数据; 在执行读取前请增加一次读写计数, 当不再需要读取时, 释放读写计数, 并记得关闭读取操作;
  closeRead(): Promise<boolean>; // 尝试关闭读取操作; 读写计数为 0 时关闭并返回 true, 否则返回 false;

  writeData(data: ArrayBuffer): Promise<void>; // 写入数据; 在执行写入前请增加一次读写计数, 当不再需要写入时, 释放读写计数, 并记得关闭写入操作;
  closeWrite(): Promise<boolean>; // 尝试关闭写入操作; 读写计数为 0 时关闭并返回 true, 否则返回 false;

  // 有新的数据被写入后的回调
  on(event: 'dataWritten', callback: (content: IMCMediaContent) => void): Promise<void>;
  off(event: 'dataWritten'): Promise<void>;
}