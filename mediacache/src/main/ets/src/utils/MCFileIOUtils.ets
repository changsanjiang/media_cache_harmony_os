import { fileIo, statfs } from "@kit.CoreFileKit";
import { BusinessError } from "@kit.BasicServicesKit";

namespace MCFileIOUtils {
  export async function calculateTotalBytes(path: string): Promise<number> {
    try {
      const info = await fileIo.stat(path);
      if ( !info.isDirectory() ) {
        return info.size;
      }
    }
    catch (error) {
      if ( (error as BusinessError).code === 13900002 ) { // 13900002 - No such file or directory
        return 0;
      }
      throw error as Error;
    }

    const fileNames = await fileIo.listFile(path);
    if ( fileNames.length === 0 ) {
      return 0;
    }

    const promises = fileNames.map((fileName) => calculateTotalBytes(`${path}/${fileName}`));
    const values = await Promise.all(promises);
    return values.reduce((prev, size) => prev + size, 0);
  }

  export function getFreeSize(path: string): Promise<number> {
    return statfs.getFreeSize(path);
  }

  export async function deleteAllFiles(path: string): Promise<void> {
    try {
      const info = await fileIo.stat(path);
      if ( !info.isDirectory() ) {
        await fileIo.unlink(path);
        return;
      }

      const fileNames = await fileIo.listFile(path);
      if ( fileNames.length === 0 ) {
        await fileIo.unlink(path);
        return;
      }

      // TODO() next  删除文件...
    }
    catch (error) {
      if ( (error as BusinessError).code === 13900002 ) { // 13900002 - No such file or directory
        return;
      }
      throw error as Error;
    }
  }
}

export default MCFileIOUtils;