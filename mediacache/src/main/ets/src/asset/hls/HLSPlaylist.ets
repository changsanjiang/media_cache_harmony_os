import { HLSDefines } from "../../defines/HLSDefines";
import MCArrayUtils from "../../utils/MCArrayUtils";
import HLSParser from "./HLSParser";

export class HLSPlaylist implements HLSDefines.Playlist {
  allItems?: HLSDefines.Item[] | undefined;
  keys?: HLSDefines.KeyItem[] | undefined;
  initializations?: HLSDefines.InitializationItem[] | undefined;
  segments?: HLSDefines.SegmentItem[] | undefined;
  variantStreams?: HLSDefines.VariantStreamItem[] | undefined;
  private renditionGroups?: Map<string, RenditionGroup> | undefined; // key:

  constructor(playlist: string) {
    const parsedItems = HLSParser.parse(playlist)[0];

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
          if ( !this.variantStreams ) this.variantStreams = [];
          this.variantStreams.push(item as HLSDefines.VariantStreamItem);
        }
          break;
        case HLSDefines.ItemType.IFRAME_STREAM:
          throw new Error(`Unsupported iframe streams.`);
        case HLSDefines.ItemType.RENDITION: {
          const renditionItem = (item as HLSDefines.RenditionItem);
          switch (renditionItem.renditionType) {
            case HLSDefines.RenditionType.AUDIO:
            case HLSDefines.RenditionType.VIDEO:
            case HLSDefines.RenditionType.SUBTITLES: {
              if ( !this.renditionGroups ) this.renditionGroups = new Map();
              const key = this.generateRenditionGroupKey(renditionItem.groupId, renditionItem.renditionType);
              let group = this.renditionGroups.get(key);
              if ( !group ) {
                group = new RenditionGroup(renditionItem.groupId, renditionItem.renditionType);
                this.renditionGroups.set(key, group);
              }
              group.renditions.push(renditionItem);
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

  getSubtitlesRenditions(): HLSDefines.RenditionItem[] | undefined {
    const variantStreams = this.variantStreams;
    if ( variantStreams ) {
      const subtitlesItems = MCArrayUtils.mapNotUndefined(variantStreams, (vs) => {
        const groupId = vs.subtitlesGroupID;
        if ( groupId ) {
          return this.getRenditionsBy(groupId, HLSDefines.RenditionType.SUBTITLES);
        }
        return undefined;
      }).flatMap(arr => arr);
      return subtitlesItems;
    }
    return undefined;
  }

  getAudioVideoRenditions(): HLSDefines.RenditionItem[] | undefined {
    const variantStreams = this.variantStreams;
    if ( variantStreams ) {
      const renditions: HLSDefines.RenditionItem[] = [];
      for ( const vs of variantStreams ) {
        const audioGroupId = vs.audioGroupID;
        const videoGroupId = vs.videoGroupID;
        if ( audioGroupId ) {
          const audios = this.getRenditionsBy(audioGroupId, HLSDefines.RenditionType.AUDIO);
          if ( audios ) {
            renditions.push(...audios);
          }
        }

        if ( videoGroupId ) {
          const videos = this.getRenditionsBy(videoGroupId, HLSDefines.RenditionType.VIDEO);
          if ( videos ) {
            renditions.push(...videos);
          }
        }
      }
      return renditions;
    }
    return undefined;
  }

  private getRenditionsBy(groupId: string, renditionType: HLSDefines.RenditionType): HLSDefines.RenditionItem[] | undefined {
    return this.renditionGroups?.get(this.generateRenditionGroupKey(groupId, renditionType))?.renditions;
  }

  private generateRenditionGroupKey(groupId: string, renditionType: HLSDefines.RenditionType): string {
    return `${groupId}_${renditionType}`;
  }
}

class RenditionGroup implements HLSDefines.RenditionGroup {
  constructor(groupId: string, renditionType: HLSDefines.RenditionType) {
    this.groupId = groupId;
    this.renditionType = renditionType;
  }

  groupId: string;
  renditionType: HLSDefines.RenditionType;
  renditions: HLSDefines.RenditionItem[] = [];
}