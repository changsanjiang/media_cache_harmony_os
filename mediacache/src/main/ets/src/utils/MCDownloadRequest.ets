import MCUtils from "./MCUtils";

export class MCDownloadRequest {
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

  // 'bytes=xxx-xxx'
  get rangeHeader(): string | undefined {
    return this.mHeaders?.['range'];
  }
}