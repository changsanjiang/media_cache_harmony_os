import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { MCMediaContentNodeList } from '../main/ets/src/media/MCMediaContentNodeList';
import { IMCMediaContent } from '../main/ets/src/defines/IMCMediaContent';
import { MCLogLevel } from '../main/ets/src/defines/MCLogLevel';
import MCLogger from '../main/ets/src/utils/MCLogger';
import MCUtils from '../main/ets/src/utils/MCUtils';
import { HLSPlaylist } from '../main/ets/src/asset/hls/HLSPlaylist';
import HLSDefines from '../main/ets/src/asset/hls/HLSDefines';

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

function testParsePlaylist() {
  let playlist =
`#EXTM3U
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=2098852,RESOLUTION=1520x720,FRAME-RATE=24.000,CODECS="avc1.640020,mp4a.40.2"
index-v1-a1.m3u8
  `;

  const outputs: HLSDefines.Item[] = [];
  const trimmedPlaylist = HLSPlaylist.parse(playlist, outputs, true);

  outputs.forEach((item) => console.log(`content=${playlist.slice(item.positions.startPosition, item.positions.startPosition + item.positions.length)}, uri=${playlist.slice(item.positions.uriStartPosition, item.positions.uriStartPosition + (item.uri?.length ?? 0))},  item=${JSON.stringify(item)}`));
  trimmedPlaylist.split("\n").forEach((line) => console.log(line));
}

function testEnum() {
  console.log(`LEVEL_DEBUG=${MCLogLevel.DEBUG.toString()}`);
}

class TestMCMediaContent implements IMCMediaContent {
  contentOffset: number = 0;
  length: Promise<number> = Promise.resolve(0);

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

  lengthUnsafe: number = 0;

  readDataUnsafe(position: number, buffer: ArrayBuffer, length: number): Promise<number> {
    throw new Error('Method not implemented.');
  }

  closeReadUnsafe(): Promise<boolean> {
    throw new Error('Method not implemented.');
  }

  writeDataUnsafe(data: ArrayBuffer, length: number): Promise<number> {
    throw new Error('Method not implemented.');
  }

  closeWriteUnsafe(): Promise<boolean> {
    throw new Error('Method not implemented.');
  }

  destroyUnsafe(): Promise<boolean> {
    throw new Error('Method not implemented.');
  }

  readwriteCount: Promise<number> = Promise.resolve(0);

  readwriteRetain(): Promise<IMCMediaContent> {
    throw new Error('Method not implemented.');
  }

  readwriteRelease(): Promise<void> {
    throw new Error('Method not implemented.');
  }

  readwriteRetainUnsafe(): IMCMediaContent {
    throw new Error('Method not implemented.');
  }

  readwriteReleaseUnsafe(): void {
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
