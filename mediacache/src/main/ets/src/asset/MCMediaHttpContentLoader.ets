import { IMCMediaContent } from "../common/IMCMediaContent";
import { MCRange } from "../utils/MCRange";
import { MCMediaContentLoader } from "./MCMediaContentLoader";

export interface IMCMediaHttpContentRequest {
  readonly url: string;
  readonly headers: Record<string, string>;
}

export class MCMediaHttpContentLoader extends MCMediaContentLoader {
  private request: IMCMediaHttpContentRequest;
  private content?: IMCMediaContent;

  constructor(request: IMCMediaHttpContentRequest, content?: IMCMediaContent) {
    super();
    this.request = request;
    this.content = content;
  }

  // protected onPrepare(): Promise<void> {
  //
  // }
}