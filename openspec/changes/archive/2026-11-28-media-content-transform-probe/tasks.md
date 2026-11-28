## 1. Implementation

- [x] 1.1 合并 `MCMedia.probe`：`bytes=0-1` + 改写占位 metadata
- [x] 1.2 删除整包 probe / 死代码分支
- [x] 1.3 更新 `docs/ARCHITECTURE.md`
- [x] 1.4 移除 `checkContents`，`prepare` 在占位长度时默认清理 content
- [x] 1.5 `probe` 空资源识别（416 / length 0）

## 2. Verification

- [x] 2.1 记录手动验证项于 `VERIFICATION.md`