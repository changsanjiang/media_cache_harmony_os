import { fileIo, statfs } from "@kit.CoreFileKit";
import { BusinessError } from "@kit.BasicServicesKit";
import { MCCopyFileConflictStrategy } from "../defines/MCCopyFileConflictStrategy";

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
    }
    catch (error) {
      if ( (error as BusinessError).code === 13900002 ) { // 13900002 - No such file or directory
        return;
      }
      throw error as Error;
    }

    const fileNames = await fileIo.listFile(path);
    if ( fileNames.length !== 0 ) {
      const promises = fileNames.map((fileName) => deleteAllFiles(`${path}/${fileName}`));
      await Promise.all(promises);
    }
    await fileIo.rmdir(path);
  }

  /**
   * 复制文件
   * @param srcPath 源文件路径
   * @param toPath 目标文件路径
   * @param options 冲突处理策略
   */
  export async function copyFile(
    srcPath: string,
    toPath: string,
    conflictStrategy?: MCCopyFileConflictStrategy
  ): Promise<void> {
    // 检查源文件是否存在
    let srcExists = false;
    try {
      srcExists = await fileIo.access(srcPath, fileIo.AccessModeType.EXIST);
    }
    catch (err) {
      throw new Error(`Unable to check existence of source file "${srcPath}": ${(err as Error).message}`);
    }

    if ( !srcExists ) {
      throw new Error(`Source file does not exist: "${srcPath}"`);
    }

    // 检查目标文件是否存在
    let exists = false;
    try {
      exists = await fileIo.access(toPath, fileIo.AccessModeType.EXIST);
    }
    catch (err) {
      if ( (err as BusinessError).code !== 13900002 ) { // 13900002 - No such file or directory
        throw new Error(`Unable to check existence of target file "${toPath}": ${(err as Error).message}`);
      }
    }

    const strategy = conflictStrategy ?? MCCopyFileConflictStrategy.Throw;
    if ( exists ) {
      if ( strategy === MCCopyFileConflictStrategy.Skip ) {
        return; // 直接跳过
      }

      if ( strategy === MCCopyFileConflictStrategy.Throw ) {
        throw new Error(`File copy failed: Target file already exists at "${toPath}".`);
      }
      // strategy === Overwrite 时继续执行
    }

    // 使用临时文件确保复制原子性
    const tempPath = `${toPath}.tmp`;
    try {
      await fileIo.copyFile(srcPath, tempPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);

      // 如果要覆盖，先删除旧文件
      if ( exists && strategy === MCCopyFileConflictStrategy.Overwrite ) {
        await fileIo.unlink(toPath);
      }

      // 重命名临时文件为目标文件
      await fileIo.rename(tempPath, toPath);
    }
    catch (err) {
      // 清理临时文件
      try { await fileIo.unlink(tempPath); } catch {}
      throw err as Error;
    }
  }

  // `/path/to/file.txt` => file.txt
  export function getFileName(path: string): string {
    return path.split('/').pop() ?? '';
  }
}

export default MCFileIOUtils;