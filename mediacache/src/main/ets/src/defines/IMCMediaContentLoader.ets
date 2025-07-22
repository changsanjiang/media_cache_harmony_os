import { MCRange } from "../utils/MCRange";
import { MCMediaContentLoaderState } from "./MCMediaContentLoaderState";

/** 数据加载器; */

// /** 推模式; 目前发现内部的 while 太占用 cpu 了, 外部不能够灵活控制; */
// export interface IMCMediaContentLoader {
//   prepare(): Promise<void>;
//   abort(error?: Error): Promise<void>; // 取消加载;
//
//   on(event: 'dataLoad', callback: (loader: IMCMediaContentLoader, offset: number, data: ArrayBuffer) => void | Promise<void>): void;
//   off(event: 'dataLoad'): void;
//
//   on(event: 'dataEnd', callback: (loader: IMCMediaContentLoader) => void): void;
//   off(event: 'dataEnd'): void;
//
//   on(event: 'aborted', callback: (loader: IMCMediaContentLoader, error?: Error) => void): void;
//   off(event: 'aborted'): void;
// }

/** 拉模式; 外部可主动调用 read 或 seek 进行灵活操作; */
export interface IMCMediaContentLoader {
  /** 当前状态; */
  readonly state: MCMediaContentLoaderState;

  /** 数据加载的范围; state === Ready 时可获取;
   *
   *    readRange: [location, max);
   * */
  readonly range: MCRange;

  /** 当前读取到的位置; */
  readonly offset: number;

  /** 当前内部已加载的数据, 外部还未读取的数据量, 可通过 read 方法进行读取; */
  readonly readableLength: number;

  /** 处于 aborted 状态时有值; */
  readonly error?: Error;

  /** 开始准备; */
  prepare(): void;

  /**
   * read 操作专门为 reader 服务, 用来读取数据后返回给 socket 客户端;
   * seek 操作专门为 prefetch 服务, 预加载不需要读取数据, 只需要确定数据的缓存量, 直接通过 offset + readableLength 来跳过读取过程;
   *
   * 所以:
   * - reader 中不会使用 seek 操作;
   * - prefetch 中不会使用 read 操作;
   *
   * 由于 read 操作的异步性, reader 需要确保串行读取;
   * */

  /** 读取数据; 返回大小可能小于 capacity; 如果 state != ready 或当前没有可读数据时 readableLength == 0 返回 undefined; */
  read(capacity: number): Promise<ArrayBuffer | undefined>;

  /** 调整读取位置, state === ready 时可设置; offset 必须在 range 范围内, 如果指定的 offset 不在 range 内, 返回 false; */
  seek(offset: number): boolean;

  /** 取消内部的加载任务; */
  abort(error?: Error): void;

  /** 状态变更时回调; */
  on(event: 'stateChange', callback: (loader: IMCMediaContentLoader, state: MCMediaContentLoaderState) => void): void;
  /** 有新数据可读取时回调; */
  on(event: 'newDataReadable', callback: (loader: IMCMediaContentLoader) => void): void;

  off(event: 'stateChange'): void;
  off(event: 'newDataReadable'): void;
}