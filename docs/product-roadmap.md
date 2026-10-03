# 产品完成路线（2026-10-03）

当前定位：MoonBit 约束解码库，服务于能获取逐步 logits 的本地推理程序。成功标准是用户可安装、可运行、可判断完成与失败，并可复现工程证据；不能以结构合法代替语义正确。

## 状态与优先级

| 优先级 | 工作 | 完成条件 | 状态 |
| --- | --- | --- | --- |
| P0 | 发布闭环 | mooncakes实际发布，独立消费项目安装并运行最小例子 | 完成：远端PR #51已发布0.1.0，本轮独立下载安装/check/build/quickstart复核PASS |
| P0 | 构建/测试证据 | GitHub CI和Pages实际成功 | 完成：4e62b51的CI与Playground均success（10月3日查询）；本轮新提交待查 |
| P1 | 真实模型证据可查看 | 线上可比较3种模式、纯/收尾策略、失败案例及逐步trace | 页面及本地核验完成；本次部署由Actions确认 |
| P1 | 跨平台示例交付 | Windows/Linux同一命令构建Playground和轨迹页，浏览器实测 | 标准库Python构建完成，Windows实测；Linux由CI验证 |
| P2 | 真实接入成本 | 测量模型forward、IPC、掩码的独立耗时后优化传输 | 待做，不预先承诺速度提升 |
| P2 | 规模和失败边界 | 更大schema/词表的编译与内存证据、错误提示及限制说明 | 待做 |
| P2 | 更多模型/任务 | 固定模型版本、公开语料、语法/EOS/语义分别计分 | 已有4任务48次回归，待扩大 |

## 本轮执行清单

- [x] 读取交接、AGENTS、源码及未提交差异，保留既有修改。
- [x] 查询实际远程状态：CI https://github.com/FidollarinLA/moonmask/actions/runs/36821443336 ，Pages https://github.com/FidollarinLA/moonmask/actions/runs/36821443319 均success。
- [x] 生成可审阅的真实轨迹页；只读历史证据，不在浏览器运行模型，不上传用户输入。
- [x] 统一跨平台构建并加入CI；核实证据文件摘要和引用完整性。防篡改/评分过期等3个测试通过。
- [x] 本地浏览器检查：切换任务/策略/模式、EOS、失败语义、逐步导航。Playground限定测试10/10，check/info/fmt通过。
- [x] 完成文档与交接，按此前授权提交并同步GitHub。本次CI/部署须查看Actions实际结果，不沿用旧提交的通过状态。

## 完成的判断

工程核心已具备：JSON Schema/Regex/GBNF、字节词表与掩码、真实logits选择、EOS和显式收尾、错误与边界测试。现有本地核心88/88、Playground10/10、协议与评分10/10；不能把历史测试次数作为本轮新结果。

发布闭环已完成：本轮首次推送发现远端新增PR #51，安全合并后重新从mooncakes安装0.1.0到临时独立项目，check/build/quickstart均通过；本轮没有再次publish。其余验收结论见docs/acceptance.md，主办方裁定不能由工程检查替代。9月30日截止前推送未完成的历史保留；已于10月1日成功同步，不倒填时间。
