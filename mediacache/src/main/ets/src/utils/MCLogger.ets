namespace MCLogger {
  export enum LogLevel {
    DEBUG,
    INFO,
    WARN,
    ERROR,
  }

  export let logLevel = LogLevel.DEBUG;
  export let enabled = true;

  export function log(level: LogLevel, message: string): void {
    // log_level => info

    // 1. 打印
    // level => err
    // level > log_level

    // 2. 打印
    // level -> info
    // level == log_level

    // 3. 不打印
    // level => debug
    // level < log_level

    if ( enabled && level >= logLevel ) {
      switch (level) {
        case LogLevel.DEBUG: {
          console.debug(message);
          break;
        }
        case LogLevel.INFO: {
          console.info(message);
          break;
        }
        case LogLevel.WARN: {
          console.warn(message);
          break;
        }
        case LogLevel.ERROR: {
          console.error(message);
          break;
        }
      }
    }
  }
};

export default MCLogger;