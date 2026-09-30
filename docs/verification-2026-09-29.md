# 2026-09-29 本地验证：可选 JSON 空白

基线为 GitHub `52b1aae`，本轮改动尚未提交。旧电脑的未提交源码与交接文件没有迁移；本轮按用户交接重新实现，不能视为恢复了原草稿。

## 环境

- Windows x86_64；Moon `0.1.20260920 (914d7da)`，moonc `v0.10.14+7d59c7ec9`。
- native C 编译器：LLVM-MinGW `20260922`，Clang `23.1.2`，UCRT x86_64。
- 本机便携工具链的 Clang target 配置加入 `-D_CRT_RAND_S`，使 MoonBit Windows runtime 使用的 `rand_s` 在 MinGW 头文件中可见；未改项目 C 源码、系统 PATH 或 Git 配置。
- tokenizer：GPT-2，50,257 tokens，Hugging Face revision `607a30d783dfa663caf39e06633721c8d4cfcd7e`，SHA-256 `8414cab924d8b9b33013f0d221c5862f365ee9be39c5c2bfae8a5a9e970478a6`。
- 工具链、下载包及原始命令日志保存在忽略的 `_local/`；它们不进入 Git。

## 检查结果

| 检查 | 结果 |
| --- | --- |
| `moon check --deny-warn` | 通过 |
| `moon test --deny-warn`（默认 wasm） | 83/83 |
| `moon test --target native --deny-warn` | 83/83 |
| Playground `moon check --deny-warn` | 通过 |
| Playground `moon test --target js -p FidollarinLA/moonmask-playground/app` | 8/8 |
| Playground `moon build --target js --release` | 通过 |
| 两模块 `moon info`、`moon fmt` | 通过；公开接口仅新增 compile/to_regex 的可选 whitespace 参数 |

浏览器在本地 release 构建上验证：默认紧凑模式；开启空白后 toy 词表初始允许 token 从 2 个变为 6 个，新增 SP/TAB/CR/LF；点击换行后仍未接受；空白模式 user 预设实验为 masked 30/30、unmasked 0/30；切回紧凑模式重置输出、token 数及实验结果。线上网站未部署本轮改动。

## native 随机采样

种子为 `moonmask-monkey-typewriter-00042`；每个 schema 分别重置 RNG，masked/unmasked 在该 schema 内顺序共享 RNG，因此两模式下的原始随机序列消费位置不同。每组 100 次。masked 的软预算是 256，随后按接受距离强制收尾，另有 `4 * budget + 64` 硬上限；unmasked 最多 64 tokens。masked 计数要求 `finished` 且 JSON 解析及 moonschema 校验成功；当前 CLI 的 unmasked 计数检查 JSON 解析和校验，不要求采到 EOS（本次全部为零）。

| 模式 | schema | masked valid | unmasked valid | masked 平均 tokens（含 EOS） | DFA states |
| --- | --- | --- | --- | --- | --- |
| 紧凑 | user | 100/100 | 0/100 | 36.79 | 500 |
| 紧凑 | order | 100/100 | 0/100 | 68.29 | 1401 |
| 紧凑 | tool_call | 100/100 | 0/100 | 34.70 | 1016 |
| 空白 | user | 100/100 | 0/100 | 57.99 | 500 |
| 空白 | order | 100/100 | 0/100 | 93.08 | 1401 |
| 空白 | tool_call | 100/100 | 0/100 | 53.78 | 1016 |

空白模式允许更多合法序列，随机生成的 token 均值更高。两种模式本次状态数相同。没有加载语言模型，不能从以上数据推导真实模型质量、语义正确性、推理吞吐或延迟提升；两组预算也不适合做效率比较。CLI 的单次起始状态掩码耗时仅是运行诊断，不作为性能基准。

## 复现

准备 MoonBit 与 C 编译器 PATH、运行 `moon update`，再通过 `scripts/fetch-gpt2.sh` 下载固定 tokenizer 并校验哈希。在项目根目录执行：

```bash
moon check --deny-warn
moon test --deny-warn
moon test --target native --deny-warn
moon run cmd/main --target native -- assets/gpt2/tokenizer.json examples/schemas/user.json examples/schemas/order.json examples/schemas/tool_call.json
moon run cmd/main --target native -- --whitespace assets/gpt2/tokenizer.json examples/schemas/user.json examples/schemas/order.json examples/schemas/tool_call.json
moon info && moon fmt
```

Playground 必须限定 app 包：

```bash
cd playground
moon check --deny-warn
moon test --target js -p FidollarinLA/moonmask-playground/app
moon build --target js --release
moon info && moon fmt
```

本地原始日志 SHA-256（用于核对，不代替重跑）：

- compact：`824b5b964606ebc1fae1de4cd7793536a518b258072e626207f75cae7edfccb9`
- whitespace：`c816a139cfcb49a9e2375718d6a284216464a93f2dd509106c8f787c882b4645`
