import { rcp } from '@kit.RemoteCommunicationKit';
import { IMCDataRequest } from '../defines/IMCDataRequest';
import { MCAssetType } from '../defines/MCAssetType';
import { MCDownloadRequest } from './MCDownloadRequest';

namespace MCConfigs {
  export let resolveAssetType: ((resUrl: string) => MCAssetType | Promise<MCAssetType>) | undefined = undefined;
  export let resolveAssetIdentifier: ((resUrl: string) => string | Promise<string>) | undefined = undefined;

  export let sessionConfiguration: rcp.SessionConfiguration | undefined = undefined;
  export let ignoredHeaders = ['host', "user-agent"];

  /** 发送给客户端的数据块大小; */
  export let socketDataBufferSize = 512 * 1024;
  /** 发送给客户端数据块时等待的超时时间; */
  export let socketDataSendTimeoutInterval = 5000;

  export const context: Context = getContext('');

  /**
   * 媒体文件的数据一致性校验; 在调试阶段可以对返回给客户端的数据做一层校验, 判断本地缓存是否与媒体数据一致;
   *
   * @param offset 数据偏移量, 在媒体文件中的偏移量;
   * @param data 数据内容, 将要发送给客户端的数据;
   * @returns 返回校验结果, true 表示一致;
   */
  export let dataValidator: ((request: IMCDataRequest, offset: number, data: ArrayBuffer) => boolean | Promise<boolean>) | undefined = undefined;

  /**
   * 媒体文件数据解密; 针对加密文件, 当发送给客户端需要解密时设置;
   *
   * @param offset 数据偏移量, 在媒体文件中的偏移量;
   * @param data 数据内容, 将要发送给客户端的数据;
   *
   * */
  export let dataDecryptHandler: ((request: IMCDataRequest, offset: number, data: ArrayBuffer) => Promise<void>) | undefined = undefined;

  /** 媒体文件数据加密; 当保存本地缓存需要加密时设置;
   *
   * @param offset 数据偏移量, 在媒体文件中的偏移量;
   * @param data 数据内容, 将要保存到缓存中的数据;
   * */
  export let dataEncryptHandler: ((request: MCDownloadRequest, offset: number, data: ArrayBuffer) => Promise<void>) | undefined = undefined;
}

export default MCConfigs;