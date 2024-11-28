import { MCAbortSignal } from './MCAbortController';
import { rcp } from '@kit.RemoteCommunicationKit';
import MCConfigs from './MCConfigs';
import MCUtils from './MCUtils';
import { MCDownloadResponseHeaders } from './MCDownloadResponseHeaders';

namespace MCDownload {
  export class DownloadRequest {
    private mHeaders?: Record<string, string>;
    private mCookies?: Record<string, string>;

    constructor(url: string, headers?: Record<string, string>, cookies?: Record<string, string>) {
      this.url = url;
      this.mHeaders = headers;
      this.mCookies = cookies;
    }

    readonly url: string;

    get headers(): Record<string, string> | undefined {
      return this.mHeaders;
    }

    get cookies(): Record<string, string> | undefined {
      return this.mCookies;
    }

    setHeader(key: string, value?: string): void {
      this.mHeaders = MCUtils.modifyRecord(this.mHeaders ? this.mHeaders : {}, key, value);
    }

    setCookie(key: string, value?: string): void {
      this.mCookies = MCUtils.modifyRecord(this.mCookies ? this.mCookies : {}, key, value);
    }
  }

  export interface Options {
    headersReceive: (headers: MCDownloadResponseHeaders) => void | Promise<void>;
    dataReceive: (data: ArrayBuffer) => number | void | Promise<void>;
    signal?: MCAbortSignal;
  }

  export interface DownloadResponse {
    readonly statusCode: number;
    readonly originalUrl: string;
    readonly currentUrl: string;
  }

  export let requestHandler: ((request: DownloadRequest) => void) | undefined = undefined;

  const session = rcp.createSession(MCConfigs.downloadSessionConfiguration);

  export function download(request: DownloadRequest, options: Options): Promise<DownloadResponse> {
    const config: rcp.Configuration = {
      tracing: {
        httpEventsHandler: {
          onHeaderReceive: options.headersReceive,
          onDataReceive: options.dataReceive
        }
      }
    };
    requestHandler?.(request);
    const req = new rcp.Request(request.url, 'GET', request.headers, undefined, request.cookies, undefined, config);
    options.signal?.addEventListener('aborted', () => session.cancel(req));
    return session.fetch(req).then((_: rcp.Response) => { });
  }
}

export default MCDownload;