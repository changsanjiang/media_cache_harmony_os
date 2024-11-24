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
}
