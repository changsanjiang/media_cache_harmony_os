export interface IMCMediaContent {
  readonly contentOffset: number;   // 内容在文件中的偏移量; 读取数据时的 position 需要考虑这个偏移量, 如果读取范围不在 [contentOffset, contentOffset+length) 之间, 将不会返回数据;
  readonly length: number; // 内容长度;
  readonly isTemp: Boolean; // 是否是临时内容;

  createReader(): IMCMediaContentReader; // reader 可以创建多个, 可以读取数据;
  createWriter(): IMCMediaContentWriter; // writer 只能创建一个, 可以写入数据;

  destroy(): Promise<void>; // 销毁内容; 删除本地文件; 如果内容正在被读写时, 则会等待读写操作完成后才会销毁;

  // 有新的数据被写入后的回调;
  on(event: 'dataWritten', callback: (content: IMCMediaContent) => void): void;
  off(event: 'dataWritten'): void;

  // TODO() next ... media 关注写入关闭的回调...
  // 写入关闭后的回调;
  on(event: 'writeClose', callback: (content: IMCMediaContent) => void): void;
  off(event: 'writeClose'): void;
}

export interface IMCMediaContentReader {
  readonly isClosed: boolean;
  readData(position: number, buffer: ArrayBuffer, length: number): Promise<number>;
  close(error?: Error): Promise<void>;
}

export interface IMCMediaContentWriter {
  readonly isClosed: boolean;
  writeData(data: ArrayBuffer, length: number): Promise<number>;
  close(error?: Error): Promise<void>;
}