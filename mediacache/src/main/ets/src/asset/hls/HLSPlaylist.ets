import HLSDefines from "../../defines/HLSDefines";
import HLSParser from "./HLSParser";

export class HLSPlaylist implements HLSDefines.Playlist {
  get numberOfAllItems(): number {
    return this.allItems?.length ?? 0;
  }
  get numberOfSegments(): number {
    return this.segments?.length ?? 0;
  }
  allItems?: HLSDefines.Item[] | undefined;
  keys?: HLSDefines.KeyItem[] | undefined;
  initializations?: HLSDefines.InitializationItem[] | undefined;
  segments?: HLSDefines.SegmentItem[] | undefined;
  variantStream?: HLSDefines.VariantStreamItem | undefined;
  audioRendition?: HLSDefines.RenditionItem | undefined;
  videoRendition?: HLSDefines.RenditionItem | undefined;
  subtitlesRendition?: HLSDefines.RenditionItem | undefined;

  constructor(playlist: string) {
    const parsedItems: HLSDefines.Item[] = [];
    HLSParser.parse(playlist, parsedItems);

    parsedItems.forEach((item) => {
      switch (item.itemType) {
        case HLSDefines.ItemType.KEY: {
          if ( !this.keys ) this.keys = [];
          this.keys.push(item as HLSDefines.KeyItem);
        }
          break;
        case HLSDefines.ItemType.INITIALIZATION: {
          if ( !this.initializations ) this.initializations = [];
          this.initializations.push(item as HLSDefines.InitializationItem);
        }
          break;
        case HLSDefines.ItemType.SEGMENT: {
          if ( !this.segments ) this.segments = [];
          this.segments.push(item as HLSDefines.SegmentItem);
        }
          break;
        case HLSDefines.ItemType.VARIANT_STREAM: {
          if ( this.variantStream ) throw new Error(`Only one variant stream can be selected; multiple streams are not supported.`);
          this.variantStream = item as HLSDefines.VariantStreamItem;
        }
          break;
        case HLSDefines.ItemType.IFRAME_STREAM:
          throw new Error(`Unsupported iframe streams.`);
        case HLSDefines.ItemType.RENDITION: {
          const renditionItem = (item as HLSDefines.RenditionItem);
          switch (renditionItem.renditionType) {
            case HLSDefines.RenditionType.AUDIO: {
              if ( this.audioRendition ) throw new Error(`Only one Audio rendition can be selected; multiple renditions are not supported.`);
              this.audioRendition = renditionItem;
            }
              break;
            case HLSDefines.RenditionType.VIDEO: {
              if ( this.videoRendition ) throw new Error(`Only one Video rendition can be selected; multiple renditions are not supported.`);
              this.videoRendition = renditionItem;
            }
              break;
            case HLSDefines.RenditionType.SUBTITLES: {
              if ( this.subtitlesRendition ) throw new Error(`Only one Subtitles rendition can be selected; multiple renditions are not supported.`);
              this.subtitlesRendition = renditionItem;
            }
              break;
            default:
              throw new Error(`Unsupported rendition type: ${renditionItem.renditionType}`);
          }
        }
          break;
      }
    });

    this.allItems = parsedItems;
  }
}