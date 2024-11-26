import { MCLogModule } from '../defines/MCLogModule';

namespace MCLogger {
  export enum LogLevel {
    TRACE,
    DEBUG,
    INFO,
    WARN,
    ERROR,
  }

  /** 日志等级; */
  export let logLevel = LogLevel.DEBUG;

  /** 是否启用日志; */
  export let enabled = true;

  /** 禁止哪些模块的日志; */
  export let disabledModules: MCLogModule[] = [];

  export function log(module: MCLogModule, level: LogLevel, messageFn: () => string): void {
    if ( enabled && level >= logLevel && !disabledModules.includes(module) ) {
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

  export function trace(module: MCLogModule, messageFn: () => string): void {
    log(module, LogLevel.TRACE, messageFn);
  }

  export function debug(module: MCLogModule, messageFn: () => string): void {
    log(module, LogLevel.DEBUG, messageFn);
  }

  export function info(module: MCLogModule, messageFn: () => string): void {
    log(module, LogLevel.INFO, messageFn);
  }

  export function warn(module: MCLogModule, messageFn: () => string): void {
    log(module, LogLevel.WARN, messageFn);
  }

  export function error(module: MCLogModule, messageFn: () => string): void {
    log(module, LogLevel.ERROR, messageFn);
  }
};

export default MCLogger;