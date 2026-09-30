# 真实逐步 logits 演示记录

本轮在用户确认“已通过验收”后继续开发。目标是验证真实模型与 MoonBit 约束引擎的逐步接入，而不是补交申报表或宣称模型质量提升。

## 已实现的链路

`DistilGPT-2.forward → 完整 logits → MoonBit Guide::greedy → token/state → 下一次模型 forward`。

模型推理使用 Python/PyTorch，MoonBit 负责 schema 编译、GPT-2 字节词表、候选选择、DFA 状态、EOS 以及 moonschema 校验。两者通过本地 Node 子进程的 JSON-lines 通信，没有网络解码服务。Python 的 `jsonschema` 再对最终原始 UTF-8 字节独立校验。

库新增 `Guide::greedy(state, logits, finish=false)` 和 `LogitsError`。验证完整向量尺寸、状态、EOS、NaN/+∞，允许用 −∞ 禁用 token，并列分数取最小 ID。`None` 表示没有候选，不能当作完成。`finish=true` 是显式的严格距离下降策略，接受状态仅考虑 EOS；它仍尊重 −∞ 禁用，不保证稀疏词表必能完成。

## 固定条件

- 模型：[distilbert/distilgpt2](https://huggingface.co/distilbert/distilgpt2/tree/2290a62682d06624634c1f46a6ad5be0f47f38aa)，revision `2290a62682d06624634c1f46a6ad5be0f47f38aa`。权重约 353 MB，没有进入 Git。
- 权重 SHA-256：`e1ff18884359fe8beb795a5f414feb85a6ce3d929ad019c0d958c039d2b94a1b`，已与固定版本的 Hugging Face LFS 元数据核对。
- tokenizer SHA-256：`8414cab924d8b9b33013f0d221c5862f365ee9be39c5c2bfae8a5a9e970478a6`；实际词表与 MoonBit 输入逐 ID 对齐，50,257 tokens，EOS 50,256。
- Windows x86_64、Python 3.12、Node 24.19.0；Moon 0.1.20260920、moonc v0.10.14；PyTorch 2.13.0+cpu、Transformers 4.57.6。其余版本在 JSON 记录中。
- CPU float32、2 threads、eager attention、eval / inference mode、deterministic algorithms、KV cache。固定 seed 42；采用 greedy，不执行随机采样。
- 同一份[提示词](../examples/logits/prompt.txt)与[情感分类 schema](../examples/logits/schema.json)，同一硬上限 64 tokens（含 EOS）。Schema 对答案格式施加约束，没有预填输出答案。

## 实际结果

### 四任务回归（2026-09-30）

新增 [suite.py](../examples/logits/suite.py) 和固定的 [corpus.json](../examples/logits/corpus.json)：负面评价分类、含 `$ref` / `const` 的嵌套工具调用、有序双元素数组、空数组加布尔字段。条件沿用下述固定 CPU 模型环境。每个任务跑两种策略、三个模式、各重复两次，共 48 次生成；每组计分只用首次运行，分母是四个任务。

| 策略 / 模式 | schema 合法 | 合法且 EOS | 预期值匹配 | 匹配且 EOS |
| --- | --- | --- | --- | --- |
| 纯 greedy / 紧凑 | 4/4 | 4/4 | 2/4 | 2/4 |
| 纯 greedy / 空白 | 4/4 | 0/4 | 2/4 | 0/4 |
| 显式收尾 / 紧凑 | 4/4 | 4/4 | 2/4 | 2/4 |
| 显式收尾 / 空白 | 4/4 | 4/4 | 2/4 | 2/4 |
| 无掩码（两策略相同） | 0/4 | 0/4 | 0/4 | 0/4 |

所有配置硬上限均为 64 tokens；显式策略从第 32 步开始收尾。预期值匹配比较完整解析结果，不抽取子串、不修复。工具请求 Tokyo 实际输出 Paris；数组预期 `["blue","red"]` 实际输出 `["red","blue"]`。这两项结构合法但答案错误，不能把结构成功称作任务成功。负面分类与空容器样例匹配预期；空容器的空数组本身由 schema 强制约束，不能据此宣称模型学会了该任务。

48 次生成的重复 token、分数、排名、状态及输出均一致（不比较耗时）。完整 [汇总](../examples/logits/evidence/suite/summary.json)、16 份原始报告和 [SHA-256 清单](../examples/logits/evidence/suite/sha256.json) 已保存。该语料仅用于集成回归，不是通用准确率或性能基准。评分与子进程测试合计 10/10；CI 新增评分测试配置，尚未推送执行远程 CI。本轮没有改库接口，`moon info` / `moon fmt` 后接口保持上一轮状态。

复现：使用示例环境运行 `python examples/logits/suite.py --model-dir _local/models/distilgpt2`。默认写入 `_local/logits-suite`，下载模式和其他参数见[运行说明](../examples/logits/README.md#multi-case-regression)。

### 首个单样例（上一轮）

| 策略 | 模式 | tokens | JSON/schema 合法 | EOS | 完整成功 |
| --- | --- | --- | --- | --- | --- |
| 纯 greedy | 紧凑 | 11 | 是 | 是 | 是 |
| 纯 greedy | 空白 | 64 | 是 | 否，达到上限 | 否 |
| 纯 greedy | 无掩码 | 64 | 否 | 否，达到上限 | 否 |
| 第 32 步起显式收尾 | 紧凑 | 11 | 是 | 是 | 是 |
| 第 32 步起显式收尾 | 空白 | 33 | 是 | 是 | 是 |
| 相同 64-token 上限 | 无掩码 | 64 | 否 | 否，达到上限 | 否 |

紧凑输出为 `{"sentiment":"positive","confidence":"high"}`。空白输出在这份对象后持续生成换行；纯 greedy 下虽然语法合法，却未结束，因此报告 `complete_valid=false`。显式收尾组仅在最后一步启用了收尾策略并选择 EOS。无掩码输出继续生成 `Review: ... JSON: ...`，完整字节串不是单个 JSON，未进行截取、修补或忽略尾部文本。

两个配置各重复运行一次，逐步 token、原始/选中 logit、排名、状态和结束结果完全一致。该事实仅覆盖这台机器和这些版本，不保证跨硬件/浮点实现逐位一致。

## 可检查的证据

- [纯 greedy 完整记录](../examples/logits/evidence/pure.json)
- [显式收尾完整记录](../examples/logits/evidence/completion.json)
- [一键运行与协议说明](../examples/logits/README.md)
- [库级回归测试](../mask/logits_test.mbt)
- [真实子进程协议测试](../examples/logits/test_protocol.py)

记录包含 prompt/token IDs/schema、模型/config/tokenizer/引擎文件哈希、运行版本和每一步真实分数、选择及状态。`raw_allowed` 反映该步实际前缀的掩码；无掩码路径进入死状态后，它持续为 false，不应作为同前缀的因果对照。`token_display` 是便于阅读的单 token 解码，完整验证使用累计原始字节。

目前通过：库默认 wasm、native、JS 各 **88/88**；真实进程协议 **6/6**。CI 已新增 JS 检查/构建及 Windows、Linux 协议测试配置；没有推送，因此不声称线上 CI 已跑过新增配置。模型测试需要独立下载权重，普通 CI 不下载它们。

## 范围与后续

这是一份提示词与一个 schema 的接入验证，不是广泛准确率评测。显式收尾改变采样策略，不能把它的完成率全部归因于 mask；时长包括模型计算、JSON 序列化和进程通信，不是性能基准。

接下来可增加多提示词、多 schema 与更强模型，并按“语法合法、完整结束、语义评分、耗时”分别记录；再补批量 logits / 更低开销绑定。当前接口不提供温度、top-p 或批量解码，Playground 仍是随机采样演示。
