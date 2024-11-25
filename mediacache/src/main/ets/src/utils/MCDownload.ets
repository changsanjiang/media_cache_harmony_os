import { http } from '@kit.NetworkKit';
import { MCAbortSignal } from './MCAbortController';
import { rcp } from '@kit.RemoteCommunicationKit';
import MCConfigs from './MCConfigs';

namespace MCDownload {
  export interface Options {
    headers?: Record<string, string>,
    headersReceive?: Callback<Object>,
    dataReceive: Callback<ArrayBuffer>,

    priority?: number, // 可选，默认为1
    connectTimeout?: number, // 可选，默认为60000ms
    readTimeout?: number, // 可选，默认为60000ms。若传输的数据较大，需要较长的时间，建议增大该参数以保证数据传输正常终止
    signal?: MCAbortSignal,
  }

  const session = rcp.createSession(MCConfigs.downloadSessionConfiguration);

  export function download2(url: string, options: Options): Promise<void> {

    session.fetch()

    // export type RequestHeaders = {
    //   [k: string]: string | string[] | undefined;
    //   'authorization'?: string;
    //   'accept'?: ContentType | ContentType[];
    //   'accept-charset'?: string | string[];
    //   'accept-encoding'?: ContentCoding | ContentCoding[];
    //   'accept-language'?: string | string[];
    //   'cache-control'?: string | string[];
    //   'cookie'?: string | string[];
    //   'range'?: string | string[];
    //   'upgrade'?: string | string[];
    //   'user-agent'?: string;
    //   'content-type'?: ContentType;
    // };
  }

  export function download(url: string, options: Options): Promise<void> {
    // 每一个httpRequest对应一个HTTP请求任务，不可复用
    let httpRequest = http.createHttp();

    options.signal?.addEventListener("aborted", () => httpRequest.destroy());

    // 用于订阅HTTP响应头事件
    httpRequest.on('headersReceive', (header: Object) => {
      options.headersReceive?.(header);
    });

    // 用于订阅HTTP流式响应数据接收事件
    httpRequest.on('dataReceive', (data: ArrayBuffer) => {
      options.dataReceive(data);
    });

    let streamInfo: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,  // 可选，默认为http.RequestMethod.GET
      header: options.headers, // 开发者根据自身业务需要添加header字段
      expectDataType:  http.HttpDataType.STRING,// 可选，指定返回数据的类型
      priority: options?.priority ? options?.priority : 1, // 可选，默认为1
      connectTimeout: options?.connectTimeout ? options?.connectTimeout : 60000, // 可选，默认为60000ms
      readTimeout: options?.readTimeout ? options?.readTimeout : 60000, // 可选，默认为60000ms。若传输的数据较大，需要较长的时间，建议增大该参数以保证数据传输正常终止
      usingProtocol: http.HttpProtocol.HTTP1_1 // 可选，协议类型默认值由系统自动指定
    }

    // 填写HTTP请求的URL地址，可以带参数也可以不带参数。URL地址需要开发者自定义。请求的参数可以在extraData中指定
    return httpRequest.requestInStream(url, streamInfo).then((httpCode: number) => {
      // console.info("requestInStream OK!");
      // console.info('ResponseCode :' + JSON.stringify(httpCode));
      // 取消订阅HTTP响应头事件
      httpRequest.off('headersReceive');
      // 取消订阅HTTP流式响应数据接收事件
      httpRequest.off('dataReceive');
    }).finally(() => httpRequest.destroy());
  }
}

export default MCDownload;