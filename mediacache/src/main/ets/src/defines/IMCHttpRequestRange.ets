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
    if ( this.suffixLength != undefined ) {
      return `bytes=-${this.suffixLength}`
    }
    if ( this.rangeStart != undefined && this.rangeEnd != undefined ) {
      return `bytes=${this.rangeStart}-${this.rangeEnd}`
    }
    return `bytes=${this.rangeStart}-`;
  }
}

export function parseRequestRange(rangeHeader: string): IMCHttpRequestRange {
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

  const matches = rangeHeader.match(/bytes=(\d+)?-(\d+)?/);
  if (!matches) {
    throw new Error('Invalid Range format. Expected format: bytes=<range-start>-<range-end>');
  }

  const first = matches[1] ? parseInt(matches[1], 10) : undefined;
  const second = matches[2] ? parseInt(matches[2], 10) : undefined;
  if (first === undefined && second === undefined) {
    throw new Error('Invalid Range format. At least one of range-start or range-end should be specified.');
  }

  const rangeStart = first;
  const rangeEnd = first !== undefined && second !== undefined ? second : undefined;
  const suffixLength = first === undefined && second !== undefined ? second : undefined;

  // 如果 rangeStart 大于 rangeEnd，则抛出错误
  if (rangeStart !== undefined && rangeEnd !== undefined && rangeStart > rangeEnd) {
    throw new Error('Invalid Range: rangeStart cannot be greater than rangeEnd.');
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

export function toRequestRangeHeader(rangeStart?: number, rangeEnd?: number, suffixLength?: number): string | undefined {
  if ( suffixLength != undefined ) {
    return `bytes=-${suffixLength}`
  }
  if ( rangeStart != undefined ) {
    return rangeEnd != undefined ? `bytes=${rangeStart}-${rangeEnd}` : `bytes=${rangeStart}-`;
  }
  return undefined;
}