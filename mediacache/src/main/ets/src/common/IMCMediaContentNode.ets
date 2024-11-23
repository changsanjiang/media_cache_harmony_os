import { IMCMediaContent } from "./IMCMediaContent";
import { IMCStopFlag } from "./IMCStopFlag";

export interface IMCMediaContentNode {
  readonly prev?: IMCMediaContentNode;
  readonly next?: IMCMediaContentNode;
  readonly placement: number;
  readonly numberOfContents: number;
  readonly longestContent?: IMCMediaContent;
  readonly idleContent?: IMCMediaContent; // 当前未读写并且长度最长的content
  trimExcessContentsWithTest(predicate: (content: IMCMediaContent, stop: IMCStopFlag) => boolean): void;
  removeContent(content: IMCMediaContent): void;
}