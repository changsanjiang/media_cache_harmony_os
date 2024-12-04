/**
 * https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Keep-Alive#directives
 * */
export interface IMCHttpKeepAlive {
  timeout: number;
  max: number;
}

export function parseKeepAlive(keepAliveHeader: string, defaultTimeout: number = 0, defaultMax: number = 0): IMCHttpKeepAlive {
  //
  // Keep-Alive: timeout=5
  // Keep-Alive: timeout=5, max=100
  const parts = keepAliveHeader.split(",");
  let timeout = defaultTimeout;
  let max = defaultMax;
  parts.forEach((part) => {
    const pair = part.trim().split(`=`);
    const key = pair[0];
    const value = parseInt(pair[1], 10);

    if      ( key === `timeout` ) {
      timeout = value;
    }
    else if ( key === `max` ) {
      max = value;
    }
  });

  const result: IMCHttpKeepAlive = {
    timeout: timeout,
    max: max
  };
  return result;
}