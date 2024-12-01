import { IMCMediaContent } from "./IMCMediaContent";
import { IMCStopFlag } from "./IMCStopFlag";

export interface IMCMediaContentNode {
  readonly prev?: IMCMediaContentNode;
  readonly next?: IMCMediaContentNode;
  readonly placement: number;
  readonly numberOfContents: number;
  readonly longestContent?: IMCMediaContent;
  filterContents(predicate: (content: IMCMediaContent) => boolean): IMCMediaContent[];
  removeContent(content: IMCMediaContent): boolean;
}