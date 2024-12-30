import { MCAbortSignal } from './MCAbortController';
import { rcp } from '@kit.RemoteCommunicationKit';
import MCConfigs from './MCConfigs';
import MCUtils from './MCUtils';
import { MCDownloadResponseHeaders } from './MCDownloadResponseHeaders';
import { MCDownloadRequest } from './MCDownloadRequest';

namespace MCDownload {
  export interface Options {
    headersReceive?: (headers: MCDownloadResponseHeaders) => void;
    dataReceive?: (data: ArrayBuffer) => void | Promise<void>;
    dataEnd?: () => void;
    signal?: MCAbortSignal;
  }

  export interface Response {
    readonly statusCode: number;
    readonly requestUrl: string;
    readonly currentUrl: string;
    readonly headers: MCDownloadResponseHeaders;
    readonly body?: ArrayBuffer;
  }

  export let requestHandler: ((request: MCDownloadRequest) => void) | undefined = undefined;

  const session = rcp.createSession(MCConfigs.sessionConfiguration);

  export function probe(request: MCDownloadRequest, signal?: MCAbortSignal): Promise<Response> {
    const req = new rcp.Request(request.url, 'HEAD', request.headers, undefined, request.cookies, undefined, undefined);
    signal?.addEventListener('aborted', () => session.cancel(req))
    return session.fetch(req)
      .then((res: rcp.Response) => toResponse(res));
  }

  export function download(request: MCDownloadRequest, options: Options): Promise<Response> {
    const config: rcp.Configuration = {
      tracing: {
        httpEventsHandler: {
          onHeaderReceive: options.headersReceive,
          onDataReceive: options.dataReceive,
          onDataEnd: options.dataEnd,
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
      headers: rcpResponse.headers as Record<string, string>,
      body: rcpResponse.body,
    };
  }
}

export default MCDownload;