namespace MCLogger {
  export enum LogLevel {
    TRACE,
    DEBUG,
    INFO,
    WARN,
    ERROR,
  }

  export let logLevel = LogLevel.DEBUG;
  export let enabled = true;

  export function log(level: LogLevel, messageFn: () => string): void {
    if ( enabled && level >= logLevel ) {
      switch (level) {
        case LogLevel.TRACE:
        case LogLevel.DEBUG: {
          console.debug(messageFn());
          break;
        }
        case LogLevel.INFO: {
          console.info(messageFn());
          break;
        }
        case LogLevel.WARN: {
          console.warn(messageFn());
          break;
        }
        case LogLevel.ERROR: {
          console.error(messageFn());
          break;
        }
      }
    }
  }
};

export default MCLogger;