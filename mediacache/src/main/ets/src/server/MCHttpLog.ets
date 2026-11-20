import { IMCHttpRequest } from '../defines/IMCHttpRequest';

/** HTTP server 层日志文案辅助（不写盘、不拼模块名，由 MCLogger 统一前缀）。 */
export namespace MCHttpLog {
  export function summarizeRequest(request: IMCHttpRequest): string {
    const range = request.headers['range'];
    return range ? `${request.method} ${request.requestTarget} Range:${range}` : `${request.method} ${request.requestTarget}`;
  }
}