import { DashAsset } from './dash/DashAsset';
import { FILEAsset } from './filebased/FILEAsset';
import { HLSAsset } from './hls/HLSAsset';
import { MCAssetCapabilityFlags } from '../defines/MCAssetCapabilities';
import { MCAssetExportOptions } from '../defines/MCAssetExportOptions';
import { MCAssetPrefetchOptions } from '../defines/MCAssetPrefetchOptions';
import { MCAssetType } from '../defines/MCAssetType';
import { IMCAsset } from '../defines/IMCAsset';
import { DashAssetPrefetcher } from '../prefetcher/DashAssetPrefetcher';
import { FILEAssetPrefetcher } from '../prefetcher/FILEAssetPrefetcher';
import { HLSAssetPrefetcher } from '../prefetcher/HLSAssetPrefetcher';
import { FILEAssetExporter } from '../exporter/FILEAssetExporter';
import { HLSAssetExporter } from '../exporter/HLSAssetExporter';

/**
 * 按 Asset 类型查询能力，并统一分发预取/导出实现。
 *
 * 播放、预取、导出不再各自维护 `switch (asset.type)`，避免能力矩阵不一致（例如 DASH 预取）。
 */
export namespace MCAssetCapabilityRegistry {
  function fullRemoteCapabilities(): MCAssetCapabilityFlags {
    return {
      remotePlay: true,
      prefetch: true,
      export: true,
      localDirPlay: true,
    };
  }

  /**
   * 返回类型能力；使用 switch 而非枚举键对象字面量，以符合 ArkTS（arkts-identifiers-as-prop-names）。
   */
  function capabilitiesFor(assetType: MCAssetType): MCAssetCapabilityFlags {
    switch (assetType) {
      case MCAssetType.FILE_BASED:
      case MCAssetType.HLS:
        return fullRemoteCapabilities();
      case MCAssetType.DASH:
        return {
          remotePlay: true,
          prefetch: true,
          export: false,
          localDirPlay: false,
        };
      default:
        throw new Error(`Unknown asset type: ${assetType}`);
    }
  }

  /** 查询能力矩阵，供文档与 UI 展示。 */
  export function getCapabilities(assetType: MCAssetType): MCAssetCapabilityFlags {
    return capabilitiesFor(assetType);
  }

  /** 不支持时抛出明确错误（调用方无需再判断布尔值）。 */
  export function assertPrefetchSupported(assetType: MCAssetType): void {
    if ( !capabilitiesFor(assetType).prefetch ) {
      throw new Error(`Prefetch is not supported for asset type: ${MCAssetType[assetType]}.`);
    }
  }

  /** 不支持时抛出明确错误。 */
  export function assertExportSupported(assetType: MCAssetType): void {
    if ( !capabilitiesFor(assetType).export ) {
      throw new Error(`Export is not supported for asset type: ${MCAssetType[assetType]}.`);
    }
  }

  /** 用于 `mc_dir_proxy` 本地资源；DASH 当前未实现。 */
  export function assertLocalDirPlaySupported(assetType: MCAssetType): void {
    if ( !capabilitiesFor(assetType).localDirPlay ) {
      throw new Error(`Local directory play is not supported for asset type: ${MCAssetType[assetType]}.`);
    }
  }

  /**
   * 预取入口；调用前应由 {@link MCRequestScope} 持有 Asset 引用。
   *
   * @param proxyPath 根媒体代理路径（与 `MCAssetProxyUtils.generateAssetProxyPath` 一致）
   */
  export async function prefetchAsset(
    asset: IMCAsset,
    proxyPath: string,
    options?: MCAssetPrefetchOptions
  ): Promise<void> {
    assertPrefetchSupported(asset.type);
    switch (asset.type) {
      case MCAssetType.FILE_BASED:
        await new FILEAssetPrefetcher().prefetch(asset as FILEAsset, proxyPath, options);
        break;
      case MCAssetType.HLS:
        await new HLSAssetPrefetcher().prefetch(asset as HLSAsset, proxyPath, options);
        break;
      case MCAssetType.DASH:
        await new DashAssetPrefetcher().prefetch(asset as DashAsset, proxyPath, options);
        break;
    }
  }

  /**
   * 导出入口；调用前应由 {@link MCRequestScope} 持有 Asset 引用。
   */
  export async function exportAsset(
    asset: IMCAsset,
    proxyPath: string,
    targetDir: string,
    options?: MCAssetExportOptions
  ): Promise<void> {
    assertExportSupported(asset.type);
    switch (asset.type) {
      case MCAssetType.FILE_BASED:
        await new FILEAssetExporter().export(asset as FILEAsset, proxyPath, targetDir, options);
        break;
      case MCAssetType.HLS:
        await new HLSAssetExporter().export(asset as HLSAsset, proxyPath, targetDir, options);
        break;
    }
  }
}