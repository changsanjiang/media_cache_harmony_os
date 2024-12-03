import { IMCReadwriteReference } from "./IMCReadwriteReference";

export interface IMCMediaContent extends IMCReadwriteReference<IMCMediaContent> {
  readonly contentOffset: number;   // 内容在文件中的偏移量; 读取数据时的 position 需要考虑这个偏移量, 如果读取范围不在 [contentOffset, contentOffset+length) 之间, 将不会返回数据;
  readonly length: number; // 内容长度;
  readonly isTemp: Boolean; // 是否是临时内容;

  readData(position: number, buffer: ArrayBuffer, length: number): Promise<number>; // 读取指定位置的数据, 返回已读取的数据长度; 在执行读取前请增加一次读写计数, 当不再需要读取时, 释放读写计数, 并记得关闭读取操作;): Promise<number>; // 读取指定位置的数据, 返回已读取的数据长度; 在执行读取前请增加一次读写计数, 当不再需要读取时, 释放读写计数, 并记得关闭读取操作;
  closeRead(): Promise<boolean>; // 尝试关闭读取操作; 读写计数为 0 时关闭并返回 true, 否则返回 false;

  writeData(data: ArrayBuffer, length: number): Promise<number>; // 写入数据; 在执行写入前请增加一次读写计数, 当不再需要写入时, 释放读写计数, 并记得关闭写入操作;
  closeWrite(): Promise<boolean>; // 尝试关闭写入操作; 读写计数为 0 时关闭并返回 true, 否则返回 false;

  destroy(): Promise<boolean>; // 销毁内容; 删除本地文件; 如果内容正在被读写时, 则无法删除;

  // 有新的数据被写入后的回调
  on(event: 'dataWritten', callback: (content: IMCMediaContent, length: number) => void): void;
  off(event: 'dataWritten'): void;
}