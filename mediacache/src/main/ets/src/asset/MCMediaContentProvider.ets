import { IMCMediaContent } from "../common/IMCMediaContent";

export class MCMediaContentProvider {
  private mDir: string;
  private mPrefix: string; // file name prefix of content

  constructor(dir: string, prefix: string) {
    this.mDir = dir;
    this.mPrefix = prefix;
  }

  async prepare(): Promise<void> {
    // create dir
  }

  async loadContents(): Promise<IMCMediaContent[] | undefined> {
    throw new Error("Method not implemented.");
  }

  async createContent(contentOffset: number): Promise<IMCMediaContent> {


    // const exists = await fileIo.access(toPath, fileIo.AccessModeType.EXIST)
    throw new Error("Method not implemented.");
  }

  removeContentFile(content: IMCMediaContent) {

  }

  removeContentFiles(contents: IMCMediaContent[]) {

  }

  removeAllContentFiles(): void {

  }

  /*
- (nullable id<MCSAssetContent>)createContentAtOffset:(NSUInteger)offset pathExtension:(nullable NSString *)pathExtension error:(NSError **)errorPtr {
    NSError *error = nil;
    if ( ![NSFileManager.defaultManager fileExistsAtPath:_directory] ) {
        [NSFileManager.defaultManager createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:&error];
    }

    if ( error == nil ) {
        NSUInteger number = 0;
        do {
            NSString *filename = [self _filenameWithOffset:offset number:number pathExtension:pathExtension];
            NSString *filePath = [self _contentFilePathForFilename:filename];
            if ( ![NSFileManager.defaultManager fileExistsAtPath:filePath] ) {
                [NSFileManager.defaultManager createFileAtPath:filePath contents:nil attributes:nil];
                return [MCSAssetContent.alloc initWithFilePath:filePath position:offset];
            }
            number += 1;
        } while (true);
    }
    else {
        if ( errorPtr != NULL ) *errorPtr = error;
    }
    return nil;
}
   * */
}