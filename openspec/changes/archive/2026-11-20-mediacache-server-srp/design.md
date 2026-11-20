## Decisions

### D1: WireFormat 为纯函数命名空间

交付名 `MCHttpWireFormat`：`IMCHttpResponseHeaders` → wire 字符串；`400`/`500`；chunked。

### D2: ProxyRouter 集中 Manager 依赖

交付名 `MCHttpProxyRouter`：唯一依赖 Asset/Export/Virtual。

### D3: Registry + Session

`MCHttpConnectionRegistry`（连接表）与 `MCHttpConnectionSession`（单连接状态机）分文件；响应适配 `MCHttpResponseAdapter`。