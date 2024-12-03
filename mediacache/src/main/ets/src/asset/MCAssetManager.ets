import { IMCAsset } from '../defines/IMCAsset';
import { MCAssetType } from '../defines/MCAssetType';
import { FILEAsset } from './filebased/FILEAsset';
import { HLSAsset } from './hls/HLSAsset';
import { fileIo } from '@kit.CoreFileKit';
import { MCSerialQueue } from '../utils/MCSerialQueue';
import MCURL from '../utils/MCURL';

namespace MCAssetManager {
  const mMap: Map<string, IMCAsset> = new Map();
  const mQueue = new MCSerialQueue();

  // asset readwrite retained, should release after;
  export async function getAssetBy(requestTarget: string): Promise<IMCAsset> {
    return mQueue.enqueue(async () => {
      const targetInfo = MCURL.parse(requestTarget);
      const assetId = targetInfo.assetId;
      let asset = mMap.get(assetId);
      if ( !asset ) {
        const rootDir = await getRootDir();
        const dir = `${rootDir}/${assetId}`;
        asset = targetInfo.assetType === MCAssetType.FILE_BASED ? new FILEAsset(assetId, dir) : new HLSAsset(assetId, dir);
        await asset.prepare();
        mMap.set(assetId, asset);
      }
      return asset.readwriteRetain();
    });
  }

  const mRootDir = getContext(mMap).filesDir + '/mc_media_cache';
  let mRootDirExists = false;
  async function getRootDir(): Promise<string> {
    if ( !mRootDirExists ) {
      if ( !(await fileIo.access(mRootDir, fileIo.AccessModeType.EXIST)) ) {
        await fileIo.mkdir(mRootDir);
      }
      mRootDirExists = true;
    }
    return mRootDir;
  }
}

export default MCAssetManager;

// namespace MCAssetManager {
//   const mMap: Map<string, IMCAsset> = new Map();
//   const mLockMap: Map<string, Promise<void>> = new Map(); // 用于存储每个 assetId 的锁
//
//   // asset readwrite retained, should release after;
//   export async function getAssetBy(requestTarget: string): Promise<IMCAsset> {
//     const targetInfo = MCURL.parse(requestTarget);
//     const assetId = targetInfo.assetId;
//     let asset = mMap.get(assetId);
//
//     if (!asset) {
//       // 检查是否已有初始化过程进行中，如果有则等待
//       if (!mLockMap.has(assetId)) {
//         mLockMap.set(assetId, initializeAsset(assetId, targetInfo)); // 在没有初始化操作时开始初始化
//       }
//
//       await mLockMap.get(assetId);
//       asset = mMap.get(assetId);
//     }
//
//     return asset!.readwriteRetain();
//   }
//
//   // 初始化资产资源的逻辑
//   async function initializeAsset(assetId: string, targetInfo: any): Promise<void> {
//     const rootDir = await getRootDir();
//     const dir = `${rootDir}/${assetId}`;
//     let asset: IMCAsset;
//
//     // 根据 assetType 初始化
//     if (targetInfo.assetType === MCAssetType.FILE_BASED) {
//       asset = new FILEAsset(assetId, dir);
//     } else {
//       asset = new HLSAsset(assetId, dir);
//     }
//
//     // 调用 prepare 方法进行准备
//     await asset.prepare();
//
//     // 保存资产到 mMap
//     mMap.set(assetId, asset);
//
//     // 操作完成，释放锁
//     mLockMap.delete(assetId); // 初始化完成后移除锁
//   }
//
//   const mRootDir = getContext(mMap).filesDir + '/mc_media_cache';
//   let mRootDirExists = false;
//
//   async function getRootDir(): Promise<string> {
//     if (!mRootDirExists) {
//       if (!(await fileIo.access(mRootDir, fileIo.AccessModeType.EXIST))) {
//         await fileIo.mkdir(mRootDir);
//       }
//       mRootDirExists = true;
//     }
//     return mRootDir;
//   }
// }
//
// export default MCAssetManager;
