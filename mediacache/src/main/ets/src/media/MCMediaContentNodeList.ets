import { IMCMediaContent } from "../defines/IMCMediaContent";
import { IMCMediaContentNode } from "../defines/IMCMediaContentNode";
import { IMCStopFlag } from "../defines/IMCStopFlag";
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

  upsertNode(placement: number, content: IMCMediaContent): void {
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

    // 如果链表为空，直接设置头尾节点
    if (!this.mHead) {
      this.mHead = curNode;
      this.mTail = curNode;
      this.mMiddle = curNode;
      return;
    }

    // 中间节点在 List 为偶数个节点时, 它的位置处于中间靠后的位置, 当有奇数个节点时, 就正好处于中间位置;
    // 例如 [1, 2] 两个节点, 中间节点会被设置为 2; [1, 2, 3] 三个节点时, 中间节点会被设置为 2; [1, 2, 3, 4] 四个节点时, 会被设置为 3;

    // Restructure nodes in the linked list to insert the new node;
    //
    // Ensure that prevNode.placement < curNode.placement < nextNode.placement;
    //
    // 如果新节点位置比头节点小直接插入头部
    if ( placement < this.mHead.placement ) {
      curNode.next = this.mHead;
      this.mHead.prev = curNode;
      this.mHead = curNode;
      // 如果节点总数为奇数，中间节点需要向前移动
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
      // 如果节点总数为偶数，中间节点需要向后移动
      if (this.mNodes.size % 2 === 0) {
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
        this.mMiddle = this.mMiddle!.prev;
      }
    }
    else {
      // 插入到中间节点之后
      let nextNode: MCMediaContentNode | undefined = this.mMiddle;
      while (nextNode && nextNode.placement < placement) {
        nextNode = nextNode.next;
      }
      this.insertBetween(curNode, nextNode?.prev, nextNode);

      // 如果节点总数为偶数，中间节点需要向后移动
      if (this.mNodes.size % 2 === 0) {
        this.mMiddle = this.mMiddle!.next;
      }
    }

    if ( this.mHead && this.mMiddle === undefined ) {
      throw new Error(`Inconsistent state detected: 'mHead' is not null, but 'mMiddle' is undefined. This indicates an unexpected behavior in the node management logic.`)
    }
  }

  private insertBetween(newNode: MCMediaContentNode, prevNode?: MCMediaContentNode, nextNode?: MCMediaContentNode): void {
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

  removeNode(n: IMCMediaContentNode): void {
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
    // 如果前面的节点被删除了
    else if ( node.placement < this.mMiddle!.placement ) {
      if ( this.mNodes.size % 2 === 0 ) this.mMiddle = this.mMiddle?.next;
    }
    // 后面的节点被删除了
    else {
      if ( this.mNodes.size % 2 !== 0 ) this.mMiddle = this.mMiddle?.prev;
    }

    if ( this.mHead && this.mMiddle === undefined ) {
      throw new Error(`Inconsistent state detected: 'mHead' is not null, but 'mMiddle' is undefined. This indicates an unexpected behavior in the node management logic.`)
    }
  }

  removeAllNodes(): void {
    this.mHead = undefined;
    this.mMiddle = undefined;
    this.mTail = undefined;
    this.mNodes.clear();
  }

  enumerateNodesUsingBlock(block: (node: IMCMediaContentNode, stop: IMCStopFlag) => void): void {
    const stop: IMCStopFlag = { value: false };
    let cur = this.mHead;
    while ( cur != undefined ) {
      block(cur, stop);
      cur = cur.next;
      if ( stop.value ) break;
    }
  }

  /** 查找左侧最近节点; */
  findClosestLeftNode(placement: number): IMCMediaContentNode | undefined {
    if (!this.mMiddle) {
      return undefined;
    }

    if (placement <= this.mHead!.placement) {
      return undefined;
    }

    if (placement > this.mTail!.placement) {
      return this.mTail;
    }

    let closestLeftNode: MCMediaContentNode | undefined = placement < this.mMiddle.placement ? this.mMiddle : this.mTail;
    while (closestLeftNode && closestLeftNode.placement > placement) {
      closestLeftNode = closestLeftNode.prev;
    }
    return closestLeftNode;
  }

  getNodeBy(placement: number): IMCMediaContentNode | undefined {
    let cur = this.mHead;
    while (cur) {
      if ( cur.placement === placement ) break;
      cur = cur.next;
    }
    return cur;
  }

  // printNodes() {
  //   console.log('===========');
  //   console.log(`nodes=${this.mNodes.size}`)
  //   console.log(`head.placement=${this.mHead?.placement}`)
  //   console.log(`middle.placement=${this.mMiddle?.placement}`)
  //   console.log(`tail.placement=${this.mTail?.placement}`)
  //   let cur = this.mHead;
  //   while (cur) {
  //     console.log(`placement=${cur.placement}`);
  //     cur = cur.next;
  //   }
  // }
}