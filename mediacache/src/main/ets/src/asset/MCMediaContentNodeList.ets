import { IMCMediaContent } from "../common/IMCMediaContent";
import { IMCMediaContentNode } from "../common/IMCMediaContentNode";
import { IMCStopFlag } from "../common/IMCStopFlag";
import { MCMediaContentNode } from "./MCMediaContentNode";

export class MCMediaContentNodeList {
  private mHead?: MCMediaContentNode = undefined;
  private mMiddle?: MCMediaContentNode = undefined;
  private mTail?: MCMediaContentNode = undefined;
  private mNodes: Map<number, MCMediaContentNode> = new Map();

  get count(): number {
    return this.mNodes.size;
  }

  get head(): IMCMediaContentNode | undefined {
    return this.mHead;
  }

  get tail(): IMCMediaContentNode | undefined {
    return this.mTail;
  }

  upsertNode(placement: number, content: IMCMediaContent) {
    const curNodeKey = placement;
    let curNode = this.mNodes.get(curNodeKey);
    if (curNode != undefined) {
      // 如果当前节点已存在，直接添加内容到节点中
      curNode.addContent(content);
      return;
    }

    // 创建新节点并添加内容
    curNode = new MCMediaContentNode(placement);
    curNode.addContent(content);
    this.mNodes.set(curNodeKey, curNode);

    // 如果链表为空，直接设置为头和尾节点
    if (!this.mHead || !this.mTail) {
      this.mHead = curNode;
      this.mTail = curNode;
      this.mMiddle = curNode;
      return;
    }

    // Restructure nodes in the linked list to insert the new node;
    //
    // Ensure that prevNode.placement < curNode.placement < nextNode.placement;
    //
    // 如果新节点位置比头节点小直接插入头部
    if ( placement < this.mHead.placement ) {
      curNode.next = this.mHead;
      this.mHead.prev = curNode;
      this.mHead = curNode;
      if (this.mNodes.size % 2 !== 0) {
        this.mMiddle = this.mMiddle!.prev;
      }
      return;
    }

    // 如果新节点位置比尾节点大直接插入尾部
    if ( placement > this.mTail!.placement ) {
      curNode.prev = this.mTail;
      this.mTail!.next = curNode;
      this.mTail = curNode;
      if (this.mNodes.size % 2 !== 0) {
        this.mMiddle = this.mMiddle!.next;
      }
      return;
    }

    // 插入节点到链表
    // 寻找合适的前后节点
    // 决定遍历起点
    // 动态选择插入方向
    if (placement < this.mMiddle!.placement) {
      // 插入到中间节点之前
      let prevNode: MCMediaContentNode | undefined = this.mMiddle;
      while (prevNode && prevNode.placement > placement) {
        prevNode = prevNode.prev;
      }
      this.insertBetween(curNode, prevNode, prevNode?.next);

      // 如果节点总数为奇数，中间节点需要向前移动
      if (this.mNodes.size % 2 !== 0) {
        this.mMiddle = this.mMiddle!.prev ?? this.mMiddle;
      }
    }
    else {
      // 插入到中间节点之后
      let nextNode: MCMediaContentNode | undefined = this.mMiddle;
      while (nextNode && nextNode.placement < placement) {
        nextNode = nextNode.next;
      }
      this.insertBetween(curNode, nextNode?.prev, nextNode);

      // 如果节点总数为奇数，中间节点需要向后移动
      if (this.mNodes.size % 2 !== 0) {
        this.mMiddle = this.mMiddle!.next ?? this.mMiddle;
      }
    }
  }

  private insertBetween(newNode: MCMediaContentNode, prevNode?: MCMediaContentNode, nextNode?: MCMediaContentNode) {
    if (prevNode) {
      prevNode.next = newNode;
      newNode.prev = prevNode;
    }
    else {
      this.mHead = newNode; // 新节点是新的头节点
    }

    if (nextNode) {
      nextNode.prev = newNode;
      newNode.next = nextNode;
    }
    else {
      this.mTail = newNode; // 新节点是新的尾节点
    }
  }

  removeNode(n: IMCMediaContentNode) {
    const node = n as MCMediaContentNode;
    if (!this.mNodes.has(node.placement)) {
      return;
    }

    const prevNode = node.prev;
    const nextNode = node.next;
    node.prev = undefined;
    node.next = undefined;

    if ( nextNode != undefined ) nextNode.prev = prevNode;
    if ( prevNode != undefined ) prevNode.next = nextNode;

    if ( this.mHead == node ) this.mHead = nextNode;
    if ( this.mTail == node ) this.mTail = prevNode;

    const nodeKey = node.placement;
    this.mNodes.delete(nodeKey);

    if ( this.mNodes.size === 0 ) {
      this.mMiddle = undefined;
      return;
    }

    // 更新中间节点
    // 判断删除的是否是中间节点
    const wasMiddle = this.mMiddle === node;
    // 如果中间节点被删除，重新设置
    if (wasMiddle) {
      this.mMiddle = nextNode || prevNode;
    }
    // 如果总数为奇数，移动中间节点
    else if (this.mNodes.size % 2 !== 0) {
      this.mMiddle = node.placement < this.mMiddle!.placement ? this.mMiddle!.prev : this.mMiddle!.next;
    }
  }

  detachAllNodes() {
    this.mNodes.clear();
    this.mHead = undefined;
    this.mMiddle = undefined;
    this.mTail = undefined;
  }

  enumerateNodesUsingBlock(block: (node: IMCMediaContentNode, stop: IMCStopFlag) => void) {
    const stop: IMCStopFlag = { value: false };
    let cur = this.mHead;
    while ( cur != undefined ) {
      block(cur, stop);
      cur = cur.next;
      if ( stop.value ) break;
    }
  }
}