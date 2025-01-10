import { fileIo } from '@kit.CoreFileKit';

namespace FileMgr {
  /**
   * Options to control the behavior of the file copy operation.
   */
  export interface CopyBehaviorOptions {
    /**
     * Whether to overwrite the target file if it already exists.
     * Defaults to `false`.
     */
    overwrite?: boolean;

    /**
     * Whether to check if the target file already exists before copying.
     * Defaults to `true`.
     */
    checkExistence?: boolean;

    /**
     * Whether to directly resolve without doing anything if the target file exists.
     * Defaults to `false`.
     */
    returnIfExists?: boolean;
  }

  /**
   * Copies a raw file from the resource manager to a specified path on the file system.
   *
   * @param context - The context object containing the resource manager for retrieving raw file content.
   * @param rawFileName - The name of the raw file to be copied.
   * @param toPath - The target file path where the raw file should be copied.
   * @param options - Settings for controlling the copy behavior, defined in the `CopyBehaviorOptions` interface.
   *
   * @returns A promise that resolves when the file is successfully copied, directly resolves if `returnIfExists` is `true`
   * and the file exists, or rejects with an error if the operation fails.
   *
   * ### Errors
   * - If `checkExistence` is `true` and the file already exists while `overwrite` is `false`, the promise rejects with a "file already exists" error.
   * - If the file system access check fails (e.g., due to permissions issues), the promise rejects with an error.
   * - If the raw file cannot be retrieved (e.g., file not found in the resource manager), the promise rejects with a corresponding error.
   * - If writing to the target file fails (e.g., due to insufficient disk space or permissions), the promise rejects with an error.
   *
   * ### Usage Examples
   * #### Copy without overwriting:
   * ```typescript
   * await copyRawFileToPath(context, 'example.txt', '/path/to/target.txt');
   * ```
   * If the file already exists, an error will be thrown.
   *
   * #### Copy with overwriting:
   * ```typescript
   * await copyRawFileToPath(context, 'example.txt', '/path/to/target.txt', { overwrite: true });
   * ```
   * The file will be overwritten if it exists.
   *
   * #### Skip existence check:
   * ```typescript
   * await copyRawFileToPath(context, 'example.txt', '/path/to/target.txt', { checkExistence: false });
   * ```
   * No existence check is performed; the method will attempt to write directly to the target path.
   *
   * #### Return if file exists:
   * ```typescript
   * await copyRawFileToPath(context, 'example.txt', '/path/to/target.txt', { checkExistence: true, returnIfExists: true });
   * ```
   * If the file exists, the function will resolve without copying the file.
   */
  export function copyRawFileToPath(context: Context, rawFileName: string, toPath: string, options?: CopyBehaviorOptions): Promise<void> {
    return new Promise<void>(async (resolve, reject) => {
      try {
        const overwrite = options?.overwrite ? options?.overwrite : false;
        const checkExistence = options?.checkExistence ? options?.checkExistence : true;
        if ( !overwrite && checkExistence ) {
          // 检查目标路径是否已经存在该文件
          let exists: boolean = false;
          try {
            exists = await fileIo.access(toPath, fileIo.AccessModeType.EXIST);
          } catch (err) {
            throw new Error(`File copy failed: Unable to check existence of target file at path "${toPath}". Error: ${(err as Error).message}`);
          }

          if (exists) {
            const returnIfExists = options?.returnIfExists ? options?.returnIfExists : false;
            // 如果文件存在且设置了 returnIfExists，则直接返回
            if ( returnIfExists ) {
              resolve();
              return;
            }
            throw new Error(`File copy failed: The target file already exists at path "${toPath}".`);
          }
        }

        // 获取原始文件内容
        let data: Uint8Array | undefined;
        try {
          data = await context.resourceManager.getRawFileContent(rawFileName);
        } catch (err) {
          throw new Error(`File copy failed: Unable to retrieve raw file "${rawFileName}". Error: ${(err as Error).message}`);
        }

        // 写入文件到目标路径
        try {
          const buffer: ArrayBufferLike = data.buffer;
          const file = fileIo.openSync(toPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | (overwrite ? fileIo.OpenMode.TRUNC : 0));
          fileIo.writeSync(file.fd, buffer);
          fileIo.closeSync(file);
        } catch (err) {
          throw new Error(`File copy failed: Unable to write to path "${toPath}". Error: ${(err as Error).message}`);
        }
        resolve();
      }
      catch (e) {
        reject(e);
      }
    })
  }
}

export default FileMgr;