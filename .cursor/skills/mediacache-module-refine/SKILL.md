---
name: mediacache-module-refine
description: >-
  Refines a mediacache source directory (e.g. server/, media/, asset/) via SRP
  split, OpenSpec change, tests, docs, and log hygiene. Use when the user asks
  to optimize a module, improve single responsibility, rename classes for
  clarity, audit architecture of a folder, or continue domain-by-domain refactors
  after transport/architecture work.
---

# MediaCache 模块分域优化

在架构分层已稳定的前提下，**按目录逐个**做 SRP 收敛：先审计 → OpenSpec → 小步实现 → 归档 → 文档/日志，不改变对外 `MCMediaCache` API。

## 前置

1. 读 [docs/ARCHITECTURE.md](../../../docs/ARCHITECTURE.md) 中该目录职责与设计不变式。
2. 读该目录下全部 `.ets`（ArkTS：**避免** `Record<enum,T>` 计算属性名）。
3. 需要 OpenSpec 时复用同仓库技能：`openspec-propose` / `openspec-apply-change` / `openspec-archive-change`。

## 工作流（每次优化一个目录）

```
1. 审计 SRP     → 产出类/职责表 + 违规点 + 建议拆分（先对话，不大改）
2. OpenSpec     → openspec new change "<domain>-<topic>"
3. 实施         → 按 tasks.md；行为优先无回归
4. 日志         → withClient + 级别收敛（见下）
5. 测试         → 纯函数/解析器优先 hypium
6. 文档         → ARCHITECTURE 目录树 + VERIFICATION.md
7. 归档         → openspec archive -y（spec 措辞含 SHALL + Scenario）
8. 提交         → 仅用户明确要求时 git commit/push
```

## SRP 审计模板（写入 change 的 design.md 或对话）

| 单元 | 应有唯一职责 | 当前问题 | 建议动作 |
|------|-------------|----------|----------|
| `Foo` | … | 混合 A+B | 抽 `FooWire` / `FooRouter` |

**常见拆分模式（server 已验证）**

| 模式 | 命名示例 | 职责 |
|------|----------|------|
| 注册表 | `*Registry` | 多实例 Map，无业务 |
| 会话/连接 | `*Session` | 单连接生命周期 + I/O 泵 |
| 适配器 | `*Adapter` | 实现 `IMC*` 契约，委托下游 |
| 路由 | `*ProxyRouter` / `*Router` | 唯一依赖上层 Manager 的入口 |
| 线格式 | `*WireFormat` | 协议字节/字符串，无 I/O |
| 领域日志 | `*Log` namespace | `summarizeX()` 短文案 |

**禁止**：为实现 SRP 而改播放/预取/淘汰等**已归档 spec** 行为；Non-goals 写进 proposal。

## OpenSpec 最小集

- `proposal.md`：Why / What / Capabilities / Impact / Non-goals
- `design.md`：拆分决策 D1,D2…
- `specs/<capability>/spec.md`：Requirement 必须 **SHALL/MUST** + `#### Scenario:`
- `tasks.md`：可勾选清单
- 完成后：`openspec archive -y <change-name>` → 更新 `openspec/specs/`、`README.md` 规格链接

## 实施原则

1. **最小 diff**：先抽纯函数/新文件，再改调用方。
2. **依赖方向**：传输层 `server/` 业务路由集中在 Router；Adapter 不 import `asset/` / `media/`（若适用）。
3. **重命名**：类名与文件名一致；同步 `MCLogModule`、测试 import、`MCMediaCache`  wiring。
4. **不复用旧 OpenSpec 归档里的类名**作为事实标准，以代码 + `ARCHITECTURE.md` 为准。

## 日志规范（全模块适用）

在 `MCLogger` 使用：

- `MCLogger.withClient(clientId, msg)` → 统一 `[clientId:N]`
- 模块内 `*Log.summarize…()` → 禁止 `JSON.stringify` 大对象上 INFO
- **INFO**：连接/请求摘要、prepare 结果（status/chunked/eos）
- **DEBUG**：取消、半包等待、响应结束
- **TRACE**：每段 TCP、缓冲切分、逐块写出
- 高置信流水线噪音（如 `Request is cancelled`）→ **DEBUG**
- 删除：回调 register/off、serial task、逐 read 循环 DEBUG

新模块枚举加入 `defines/MCLogModule.ets`；示例白名单与根 `README.md` 保持一致。

## 测试

- 纯逻辑：`mediacache/src/test/<Module>.test.ets`，注册 `List.test.ets`
- 不做无意义的断言；Policy/解析/线格式优先

## VERIFICATION.md（归档目录内）

| 提案项 | 实现 | 状态 |
| 手工回归 | entry 播放器 / 相关单测 | checklist |

## 参考：server 域落地（2026-11-20）

详见 [reference.md](reference.md)。归档：`openspec/changes/archive/2026-11-20-mediacache-{transport-fixes,server-srp}/`。

## 其他目录提示（未做，仅方向）

| 目录 | 优先 SRP 点 |
|------|-------------|
| `media/` | 拆 `MCMedia`（probe/resolve/copy）；`composeDataResponse` 模式 |
| `virtual/` | 与 Session 对称的薄封装 |
| `prefetcher/` | 统一 drain 路径 vs `MCMediaDataFetcher` |
| `asset/` | 能力表已集中；DASH export 单开 change |

## 交付自检

- [ ] 提案与代码一致；tasks 全 [x]
- [ ] 无 `build-profile.json5` 等本地签名误提交
- [ ] `docs/ARCHITECTURE.md` 目录树与类名一致
- [ ] 用户未要求则不 commit