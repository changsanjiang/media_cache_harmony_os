import { MCRange } from '../utils/MCRange';

/**
 * - https://datatracker.ietf.org/doc/html/rfc9110#name-range-requests
 * - https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Range#syntax
 Range: <unit>=<range-start>-
 Range: <unit>=<range-start>-<range-end>
 Range: <unit>=<range-start>-<range-end>, <range-start>-<range-end>, …    // unsupported
 Range: <unit>=-<suffix-length>
 * */
export interface IMCHttpRequestRange {
  rangeStart?: number;
  rangeEnd?: number;
  suffixLength?: number;

  // 'bytes=xxx-xxx'
  toRangeHeader(): string;

  toRange(totalLength: number): MCRange;
}

class MCHttpRequestRange implements IMCHttpRequestRange {
  rangeStart?: number;
  rangeEnd?: number;
  suffixLength?: number;
  constructor(rangeStart?: number, rangeEnd?: number, suffixLength?: number) {
    this.rangeStart = rangeStart;
    this.rangeEnd = rangeEnd;
    this.suffixLength = suffixLength;
  }

  toRangeHeader(): string {
    if ( this.rangeStart != undefined ) {
      if ( this.rangeEnd != undefined ) {
        return `bytes=${this.rangeStart}-${this.rangeEnd}`;
      }
      return `bytes=${this.rangeStart}-`;
    }

    if ( this.suffixLength != undefined ) {
      return `bytes=-${this.suffixLength}`
    }

    // 其他情况非法
    throw new Error(`Invalid range: neither range-start nor suffix-length specified. header: ${JSON.stringify(this)}`);
  }

  toRange(totalLength: number): MCRange {
    if ( totalLength <= 0 ) {
      throw new Error(`The total length must be greater than 0.`);
    }

    const requestRangeStart = this.rangeStart;
    let requestRangeEnd = this.rangeEnd;
    let requestSuffixLength = this.suffixLength;

    // 情况一：显式起始位置
    if ( requestRangeStart != undefined ) {
      if ( requestRangeStart < 0 ) {
        throw new Error( `Invalid range: range-start must be >= 0. header: ${JSON.stringify(this)}`);
      }

      if ( requestRangeStart >= totalLength ) {
        throw new Error(`Invalid range: range-start (${requestRangeStart}) >= total length (${totalLength}). header: ${JSON.stringify(this)}`);
      }

      if ( requestRangeEnd != undefined ) {
        if ( requestRangeEnd < requestRangeStart ) {
          throw new Error(`Invalid range: range-end (${requestRangeEnd}) < range-start (${requestRangeStart}). header: ${JSON.stringify(this)}`);
        }

        if ( requestRangeEnd >= totalLength ) {
          requestRangeEnd = totalLength - 1; // 裁剪
        }
      }
      else {
        requestRangeEnd = totalLength - 1; // 未指定则到末尾
      }

      const location = requestRangeStart;
      const length = requestRangeEnd - requestRangeStart + 1;
      return new MCRange(location, length);
    }

    // 情况二：后缀范围
    if ( requestSuffixLength != undefined ) {
      if ( requestSuffixLength <= 0 ) {
        throw new Error(`Invalid range: suffix-length must be > 0. header: ${JSON.stringify(this)}`);
      }

      if ( requestSuffixLength > totalLength ) {
        requestSuffixLength = totalLength; // 裁剪
      }

      const location = totalLength - requestSuffixLength;
      const length = requestSuffixLength;
      return new MCRange(location, length);
    }

    // 其他情况非法
    throw new Error(`Invalid range: neither range-start nor suffix-length specified. header: ${JSON.stringify(this)}`);
  }
}

export function parseRequestRange(rangeHeader: string): IMCHttpRequestRange {
  if (!rangeHeader) {
    throw new Error("Missing range header in the request.");
  }

  /** https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Range#syntax
   Range: <unit>=<range-start>-
   Range: <unit>=<range-start>-<range-end>
   Range: <unit>=<range-start>-<range-end>, <range-start>-<range-end>, …  // @note: Multi-range requests are not supported;
   Range: <unit>=-<suffix-length>
   * */
  if (!rangeHeader.startsWith('bytes=')) {
    throw new Error('Unsupported Range unit: Only "bytes" unit is supported');
  }

  if (rangeHeader.includes(',')) {
    throw new Error('Multi-range requests are not supported. Only single-range requests are allowed.');
  }

  const matches = rangeHeader.match(/^bytes=(\d*)-(\d*)$/);
  if (!matches) {
    throw new Error('Invalid Range format. Expected format: bytes=<range-start>-<range-end>');
  }

  let rangeStart: number | undefined;
  let rangeEnd: number | undefined;
  let suffixLength: number | undefined;

  if ( matches[1] !== "" ) {
    rangeStart = parseInt(matches[1], 10);
  }

  if ( matches[2] !== "" ) {
    if ( rangeStart !== undefined ) {
      rangeEnd = parseInt(matches[2], 10);
    }
    else {
      suffixLength = parseInt(matches[2], 10);
    }
  }

  // 情况一：显式起始位置
  if ( rangeStart != undefined ) {
    if ( rangeStart < 0 ) {
      throw new Error( `Invalid range: range-start must be >= 0. header: ${rangeHeader}`);
    }

    if ( rangeEnd != undefined ) {
      if ( rangeEnd < rangeStart ) {
        throw new Error(`Invalid range: range-end (${rangeEnd}) < range-start (${rangeStart}). header: ${rangeHeader}`);
      }
    }
  }
  // 情况二：后缀范围
  else if ( suffixLength != undefined ) {
    if ( suffixLength <= 0 ) {
      throw new Error(`Invalid range: suffix-length must be > 0. header: ${rangeHeader}`);
    }
  }
  // 其他情况非法
  else {
    throw new Error(`Invalid range: neither range-start nor suffix-length specified. header: ${rangeHeader}`);
  }

  return new MCHttpRequestRange(
    rangeStart,
    rangeEnd,
    suffixLength
  );
}

export function parseRequestRangeIfDefined(rangeHeader?: string): IMCHttpRequestRange | undefined {
  return rangeHeader ? parseRequestRange(rangeHeader) : undefined;
}

export function toRequestRange(range: MCRange): IMCHttpRequestRange {
  return new MCHttpRequestRange(range.location, range.max - 1, undefined);
}