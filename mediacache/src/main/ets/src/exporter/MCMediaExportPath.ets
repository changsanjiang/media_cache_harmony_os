export namespace MCMediaExportPath {
  export function resolveMetadataDestPath(mediaId: string, mediaKind: number, destDir: string): string {
    return `${destDir}/mc_${mediaKind}_${mediaId}_metadata.json`;
  }

  export function resolveContentDestPath(mediaId: string, mediaKind: number, destDir: string): string {
    return `${destDir}/mc_${mediaKind}_${mediaId}_media`;
  }
}