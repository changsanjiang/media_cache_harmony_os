import { MCAbortSignal } from './MCAbortController';
import { rcp } from '@kit.RemoteCommunicationKit';
import MCConfigs from './MCConfigs';
import MCUtils from './MCUtils';
import { MCDownloadResponseHeaders } from './MCDownloadResponseHeaders';

namespace MCDownload {
  export class Request {
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
    dataReceive: (data: ArrayBuffer) => void | Promise<void>;
    signal?: MCAbortSignal;
  }

  export interface Response {
    readonly statusCode: number;
    readonly requestUrl: string;
    readonly currentUrl: string;
    readonly headers: MCDownloadResponseHeaders;
  }

  export let requestHandler: ((request: Request) => void) | undefined = undefined;

  const session = rcp.createSession(MCConfigs.sessionConfiguration);

  export function probe(request: Request, signal?: MCAbortSignal): Promise<Response> {
    const req = new rcp.Request(request.url, 'HEAD', request.headers, undefined, request.cookies, undefined, undefined);
    signal?.addEventListener('aborted', () => session.cancel(req))
    return session.fetch(req)
      .then((res: rcp.Response) => toResponse(res));
  }

  export function download(request: Request, options: Options): Promise<Response> {
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
    return session.fetch(req)
      .then((res: rcp.Response) => toResponse(res));
  }

  function toResponse(rcpResponse: rcp.Response): Response {
    const requestUrl = rcpResponse.request.url.toString();
    return {
      statusCode: rcpResponse.statusCode,
      requestUrl: requestUrl,
      currentUrl: rcpResponse.effectiveUrl?.toString() ?? requestUrl,
      headers: rcpResponse.headers as Record<string, string>
    };
  }
}

export default MCDownload;