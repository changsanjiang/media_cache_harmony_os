import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { MCMediaContentNodeList } from '../main/ets/src/media/MCMediaContentNodeList';
import { IMCMediaContent } from '../main/ets/src/defines/IMCMediaContent';
import { MCLogLevel } from '../main/ets/src/defines/MCLogLevel';
import MCLogger from '../main/ets/src/utils/MCLogger';
import MCUtils from '../main/ets/src/utils/MCUtils';
import { HLSPlaylist } from '../main/ets/src/asset/hls/HLSPlaylist';
import HLSDefines from '../main/ets/src/defines/HLSDefines';
import { buffer, util } from '@kit.ArkTS';
import HLSParser from '../main/ets/src/asset/hls/HLSParser';

export default function nodeListUnitTest() {
  describe('nodeListUnitTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    });
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    });
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    });
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    });
    it('assertContain', 0, async () => {
      // testAdd();
      // testFind();
      // testEnum();
      testParsePlaylist();
    });
  });
}

async function testParsePlaylist() {
  let playlist =
`#EXTM3U
#EXT-X-TARGETDURATION:10
#EXT-X-ALLOW-CACHE:YES
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-VERSION:6
#EXT-X-MEDIA-SEQUENCE:1
#EXT-X-MAP:URI="init-v1-a1.mp4"
#EXTINF:10.417,
seg-1-v1-a1.m4s
#EXTINF:10.417,
seg-2-v1-a1.m4s
#EXTINF:10.417,
seg-3-v1-a1.m4s
  `;

  const originalUrl = "http://www.baidu.com";
  const currentUrl = "http://www.lwz.com";
  const proxyPlaylist = await HLSParser.proxy("abcd", playlist, originalUrl, currentUrl);
  proxyPlaylist.split("\n").forEach((line) => console.log(line));
}

function testEnum() {
  console.log(`LEVEL_DEBUG=${MCLogLevel.DEBUG.toString()}`);
}

class TestMCMediaContent implements IMCMediaContent {
  isTemp = false;
  contentOffset = 0;
  length = 0;

  readData(position: number, buffer: ArrayBuffer, length: number): Promise<number> {
    throw new Error('Method not implemented.');
  }

  closeRead(): Promise<boolean> {
    throw new Error('Method not implemented.');
  }

  writeData(data: ArrayBuffer, length: number): Promise<number> {
    throw new Error('Method not implemented.');
  }

  closeWrite(): Promise<boolean> {
    throw new Error('Method not implemented.');
  }

  destroy(): Promise<boolean> {
    throw new Error('Method not implemented.');
  }

  on(event: 'dataWritten', callback: (content: IMCMediaContent, length: number) => void): Promise<void> {
    throw new Error('Method not implemented.');
  }

  off(event: 'dataWritten', callback: (content: IMCMediaContent, length: number) => void): Promise<void> {
    throw new Error('Method not implemented.');
  }

  readwriteCount = 0;

  readwriteRetain(): IMCMediaContent {
    throw new Error('Method not implemented.');
  }

  readwriteRelease(): void {
    throw new Error('Method not implemented.');
  }
}

function testAdd() {
  const nodeList = new MCMediaContentNodeList();
  const content = new TestMCMediaContent();

  nodeList.upsertNode(5, content);
  nodeList.printNodes();
  nodeList.upsertNode(3, content);
  nodeList.printNodes();
  nodeList.upsertNode(0, content);
  nodeList.printNodes();
  nodeList.upsertNode(14, content);
  nodeList.printNodes();
  nodeList.upsertNode(6, content);
  nodeList.printNodes();
  nodeList.upsertNode(10, content);
  nodeList.printNodes();
  nodeList.upsertNode(2, content);
  nodeList.printNodes();
  nodeList.upsertNode(20, content);
  nodeList.printNodes();
  nodeList.upsertNode(1, content);
  nodeList.printNodes();
  nodeList.upsertNode(21, content);
  nodeList.printNodes();
  nodeList.upsertNode(4, content);
  nodeList.printNodes();
};
function testDelete() {
  const nodeList = new MCMediaContentNodeList();
  const content = new TestMCMediaContent();

  let idx = 20;
  while (idx >= 0) {
    nodeList.upsertNode(idx, content);
    idx -= 1;
  }
  nodeList.printNodes();

  console.log("======================delete start");

  console.log("删掉中间节点");
  nodeList.removeNode(nodeList.getNodeBy(10)!);
  nodeList.printNodes();

  console.log("删掉头结点");
  nodeList.removeNode(nodeList.getNodeBy(0)!);
  nodeList.printNodes();

  console.log("删掉尾结点");
  nodeList.removeNode(nodeList.getNodeBy(20)!);
  nodeList.printNodes();

  console.log("删掉左侧节点");
  nodeList.removeNode(nodeList.getNodeBy(2)!);
  nodeList.printNodes();

  console.log("删掉左侧节点");
  nodeList.removeNode(nodeList.getNodeBy(3)!);
  nodeList.printNodes();

  console.log("删掉右侧节点");
  nodeList.removeNode(nodeList.getNodeBy(13)!);
  nodeList.printNodes();

  console.log("删掉右侧节点");
  nodeList.removeNode(nodeList.getNodeBy(14)!);
  nodeList.printNodes();
}
function testDelete2() {
  const nodeList = new MCMediaContentNodeList();
  const content = new TestMCMediaContent();

  let idx = 4;
  while (idx > 0) {
    nodeList.upsertNode(idx, content);
    idx -= 1;
  }
  nodeList.printNodes();

  console.log("======================delete start");
  nodeList.removeNode(nodeList.getNodeBy(4)!);
  nodeList.printNodes();
  nodeList.removeNode(nodeList.getNodeBy(3)!);
  nodeList.printNodes();
  nodeList.removeNode(nodeList.getNodeBy(2)!);
  nodeList.printNodes();
  nodeList.removeNode(nodeList.getNodeBy(1)!);
  nodeList.printNodes();
}
function testDelete3() {
  const nodeList = new MCMediaContentNodeList();
  const content = new TestMCMediaContent();

  let idx = 4;
  while (idx > 0) {
    nodeList.upsertNode(idx, content);
    idx -= 1;
  }
  nodeList.printNodes();

  console.log("======================delete start");
  nodeList.removeNode(nodeList.getNodeBy(1)!);
  nodeList.printNodes();
  nodeList.removeNode(nodeList.getNodeBy(2)!);
  nodeList.printNodes();
  nodeList.removeNode(nodeList.getNodeBy(3)!);
  nodeList.printNodes();
  nodeList.removeNode(nodeList.getNodeBy(4)!);
  nodeList.printNodes();
}
function testFind() {
  const nodeList = new MCMediaContentNodeList();
  const content = new TestMCMediaContent();

  let idx = 20;
  while (idx > 0) {
    nodeList.upsertNode(idx, content);
    idx -= 2;
  }
  nodeList.printNodes();

  idx = 1;
  while (idx < 25) {
    console.log(`${idx}.closest ==> ${nodeList.findClosestLeftNode(idx)?.placement}`);
    idx += 2;
  }
}
