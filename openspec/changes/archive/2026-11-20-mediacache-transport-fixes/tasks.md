## 1. Buffer & parse

- [x] 1.1 Add `MCHttpReceiveBuffer`
- [x] 1.2 Wire buffer in `MCHttpConnectionSession`（原 Handler，现 Session）
- [x] 1.3 Adjust `parseRequest` body / Content-Length rules

## 2. HEAD

- [x] 2.1 Extend `IMCDataRequest` with method
- [x] 2.2 `MCMedia` head-only response path
- [x] 2.3 Virtual session HEAD + `MCHttpResponse.omitsResponseBody`

## 3. Tests & docs

- [x] 3.1 Unit test for receive buffer
- [x] 3.2 Update `docs/ARCHITECTURE.md` transport section
- [x] 3.3 `composeDataResponse` 收敛 GET/HEAD；`VERIFICATION.md`