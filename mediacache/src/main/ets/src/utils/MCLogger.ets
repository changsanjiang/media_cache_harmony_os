import { MCLogLevel } from '../defines/MCLogLevel';
import { MCLogModule } from '../defines/MCLogModule';

namespace MCLogger {
  /** 日志等级; */
  export let logLevel = MCLogLevel.DEBUG;

  /** 是否启用日志; */
  export let enabled = false;

  /** 禁止哪些模块的日志; */
  export let blacklist: MCLogModule[] | undefined = undefined;
  /** 允许哪些模块的日志; */
  export let whitelist: MCLogModule[] | undefined = undefined;

  export function log(module: MCLogModule, level: MCLogLevel, messageFn: () => string): void {
    if ( enabled && level >= logLevel ) {
      if ( blacklist && blacklist.includes(module) ) return;
      if ( whitelist && !whitelist.includes(module) ) return;

      const message = `[${module}] ${messageFn()}`;
      switch (level) {
        case MCLogLevel.TRACE:
        case MCLogLevel.DEBUG: {
          console.debug(message);
          break;
        }
        case MCLogLevel.INFO: {
          console.info(message);
          break;
        }
        case MCLogLevel.WARN: {
          console.warn(message);
          break;
        }
        case MCLogLevel.ERROR: {
          console.error(message);
          break;
        }
      }
    }
  }

  export function trace(module: MCLogModule, messageFn: () => string): void {
    log(module, MCLogLevel.TRACE, messageFn);
  }

  export function debug(module: MCLogModule, messageFn: () => string): void {
    log(module, MCLogLevel.DEBUG, messageFn);
  }

  export function info(module: MCLogModule, messageFn: () => string): void {
    log(module, MCLogLevel.INFO, messageFn);
  }

  export function warn(module: MCLogModule, messageFn: () => string): void {
    log(module, MCLogLevel.WARN, messageFn);
  }

  export function error(module: MCLogModule, messageFn: () => string): void {
    log(module, MCLogLevel.ERROR, messageFn);
  }
};

export default MCLogger;