import MCUtils from "../utils/MCUtils";
import { MCAssetExportInfo } from "./MCAssetExportInfo";
import { JSON } from "@kit.ArkTS";
import { fileIo } from "@kit.CoreFileKit";
import { MCCopyFileConflictStrategy } from "../defines/MCCopyFileConflictStrategy";
import MCFileIOUtils from "../utils/MCFileIOUtils";
import { MCMediaKind } from "../defines/MCMediaKind";
import { MCProxyDirUtils } from "../utils/MCProxyDirUtils";
import { MCAssetType } from "../defines/MCAssetType";
import { MCProxyURLUtils } from "../utils/MCProxyURLUtils";

export namespace MCAssetExportUtils {
  // 代理指定目录返回代理地址;
  export async function generateAssetProxyUrl(targetDir: string, localServerPort: number): Promise<string> {
    const exportInfo = await loadExportInfo(targetDir);
    const assetId = exportInfo.assetId;
    const assetType = exportInfo.assetType;
    const mediaId = exportInfo.assetId;
    const mediaKind = exportInfo.assetType == MCAssetType.HLS ? MCMediaKind.PLAYLIST : MCMediaKind.FILE;
    const ext = assetType == MCAssetType.HLS ? 'm3u8' : '';
    return MCProxyDirUtils.generateProxyUrl(targetDir, assetId, assetType, mediaId, mediaKind, ext, localServerPort);
  }

  // 将代理内容转移到 dir;
  export async function transferProxy(proxyPath: string, targetDir: string): Promise<string> {
    const proxyInfo = MCProxyURLUtils.parseTarget(proxyPath);
    const assetId = proxyInfo.assetId;
    const assetType = proxyInfo.assetType;
    const mediaId = proxyInfo.mediaId;
    const mediaKind = proxyInfo.mediaKind;
    const ext = MCUtils.getFileExtension(proxyPath);
    return MCProxyDirUtils.generateProxyPath(targetDir, assetId, assetType, mediaId, mediaKind, ext);
  }

  /** 保存导出信息到指定目录 */
  export async function saveExportInfo(exportInfo: MCAssetExportInfo, targetDir: string, conflictStrategy?: MCCopyFileConflictStrategy): Promise<void> {
    const jsonStr = JSON.stringify(exportInfo);
    const checksum = await MCUtils.hash(jsonStr);
    const record: Record<string, string> = {
      'checksum': checksum,
      'data': jsonStr,
    };
    const content = JSON.stringify(record);
    const buffer = MCUtils.stringToBuffer(content);
    const filePath = resolveExportInfoFilePath(targetDir);
    await MCFileIOUtils.writeFile(buffer, filePath, conflictStrategy);
  }

  /** 从指定目录加载导出信息;
   *
   * 如果文件不存在或数据异常(被篡改/损坏)将会抛出异常;
   * */
  export async function loadExportInfo(targetDir: string): Promise<MCAssetExportInfo> {
    const filePath = resolveExportInfoFilePath(targetDir);
    if ( !(await fileIo.access(filePath, fileIo.AccessModeType.EXIST)) ) {
      throw new Error(`Export info file does not exist: "${targetDir}"`);
    }

    const content = await fileIo.readText(filePath, { encoding: 'utf-8' });
    const record = JSON.parse(content) as Record<string, string>;
    const checksum = record['checksum'];
    const data = record['data'];
    if (!checksum || !data) {
      throw new Error(`Malformed export info file: missing required fields (checksum/data) at "${filePath}"`);
    }

    const calculatedChecksum = await MCUtils.hash(data);
    if ( checksum !== calculatedChecksum ) {
      throw new Error(`Export info file integrity check failed (possible corruption or tampering) at "${filePath}"`);
    }
    return JSON.parse(data) as MCAssetExportInfo;
  }

  /** 获取导出信息文件路径; */
  function resolveExportInfoFilePath(targetDir: string): string {
    const fileName = 'mc_export_info.json';
    const filePath = `${targetDir}/${fileName}`;
    return filePath;
  }
}