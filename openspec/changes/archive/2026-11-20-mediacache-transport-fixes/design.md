## Decisions

### D1: `MCHttpReceiveBuffer`

按连接累积字节，找到 `\r\n\r\n` 后切出首条请求头文本交给 `parseRequest`；剩余字节留在缓冲（支持粘包）。

### D2: HEAD

`fetch` 在 HEAD 时于 `probe` 之后调用 `buildHeadOnlyResponse(request, metadata)`，经 `composeDataResponse` 与 GET 共用响应形状、_loaders 为空_。`MCHttpResponse.omitsResponseBody` 时 Handler 不 `consumeData`。

### D3: Pipeline

保持「新请求 abort 上一响应」；粘包通过 buffer 顺序解析，不在半包时误判 body。