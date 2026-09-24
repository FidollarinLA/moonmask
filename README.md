# moonmask

MoonBit 原生的大模型结构化输出约束引擎：把 JSON Schema 子集编译成按字节工作的自动机，在每一步采样前算出还能接上的 token。

English: a constrained decoder for LLMs. It compiles a JSON Schema subset to a byte-level automaton and masks tokens that cannot lead to a valid document.

## 为什么需要

常见做法是等模型把整段文本生成完，再做 JSON 校验，失败就重试。约束解码把检查提前到每一个 token：只保留“接上去之后仍可能得到合法结果”的 token，其余屏蔽掉。输出是否合法由确定性算法保证，不依赖模型自己改正。

## 快速开始

```moonbit
let tok = @tokenizer.from_file("assets/gpt2/tokenizer.json")
let vocab = @vocab.from_tokenizer(tok, eos_token="<|endoftext|>")
let guide = @mask.Guide::new(@schema.compile(schema), vocab)
let mut state = guide.start()
// Each decoding step: keep only guide.allowed(state), set every other logit to -inf,
// sample `token`, then:
match guide.advance(state, token) {
  Some(next) => state = next
  None => () // eos: the output is complete and valid
}
```

词表文件不在仓库里。先运行 `./scripts/fetch-gpt2.sh`，它会按固定版本下载 GPT-2 的 `tokenizer.json` 并校验 SHA-256。

## 猴子打字机实验

固定随机种子 `moonmask-monkey-typewriter-00042`，每个 schema 采样 100 次。加掩码的采样必须通过独立校验器 `moonbitstack/moonschema`；不加掩码的对照使用同一词表均匀抽 token。

```bash
./scripts/fetch-gpt2.sh
moon run cmd/main --target native -- assets/gpt2/tokenizer.json \
  examples/schemas/user.json examples/schemas/order.json examples/schemas/tool_call.json
```

在开发机上一次完整运行大约 1.8 秒，结果是：

| schema | masked valid | unmasked valid | avg tokens (masked) | DFA states |
| --- | --- | --- | --- | --- |
| examples/schemas/user.json | 100/100 | 0/100 | 36.42 | 104 |
| examples/schemas/order.json | 100/100 | 0/100 | 69.29 | 213 |
| examples/schemas/tool_call.json | 100/100 | 0/100 | 34.74 | 158 |

## 支持的 JSON Schema 子集

- `string`，可带 `minLength` / `maxLength`。内容是 ASCII 可见字符和常见转义 `\" \\ \/ \b \f \n \r \t`。
- `integer`。为了让结果能被 JSON 解析器精确读入，位数最多 15 位，不含前导零。可带 `minimum` / `maximum`。`exclusiveMinimum` / `exclusiveMaximum` 必须是数字，表示开区间；同时写时取更紧的一侧。
- `number`。小数部分最多 15 位，指数最多 2 位。带数值范围时不再生成科学计数法，只生成落在区间内的整数，以及最多 15 位小数。
- `boolean`、`null`。
- `enum`、`const`。如果同时写了 `type`，会先按类型过滤候选值。
- `object`。按 `properties` 的声明顺序输出全部属性。`required` 里的名字必须都已声明。`additionalProperties` 只能是布尔值。
- `array`，必须有 `items`，可带 `minItems` / `maxItems`。
- `anyOf`，以及 `type` 写成类型数组。
- 注解键 `title`、`description`、`$schema`、`$id`、`$comment`、`examples`、`default` 会被忽略。
- 其余关键字，包括 `pattern`、`format`、`multipleOf`、`oneOf`、`$ref`，直接报错，不会静默忽略。draft-04 那种布尔值 `exclusiveMinimum` / `exclusiveMaximum` 同样报错。

## 适用范围与限制

- 推理时每一步都要能拿到 logits，例如进程内推理或本地推理服务。只返回整段文本的云端 API 只能事后校验。
- 只生成紧凑 JSON，不含空白。
- 字符串内容限 ASCII 和上面列出的转义。
- object 会输出每一个声明过的属性，不省略可选字段。
- 词表只支持 GPT-2 字节级 BPE。SentencePiece 的 `▁` 会在加载时拒绝。
- 数值边界本身最多 15 位整数和 15 位小数；超出这个范围会报错，而不是截断。带范围的 `number` 不生成指数。
- 不支持 `$ref` 和递归结构。

## 设计

正则先解析成语法树，再用 Thompson 构造变成 NFA，然后做子集构造得到 DFA。到不了接受状态的状态会被剪掉，每个状态记下到最近接受状态的最短距离。掩码层按 DFA 状态缓存“token → 下一状态”。采样器在预算内均匀选择合法 token；超出预算后只选让距离下降的 token，因此在词表覆盖单字节时一定能结束。

## 测试

```bash
moon test --deny-warn
```

- 正则与 `moonbitlang/regexp` 做差分，9000 次以上对照。
- Schema 自动机随机生成的字符串全部交给 `moonschema` 校验。
- 有限语言上，掩码允许的 token 与穷举得到的“存在合法补全的 token”一致。

## 参考与许可证

方法参考 Outlines（Willard & Louf, 2023，Apache-2.0）、XGrammar（Apache-2.0）和 llguidance（MIT），不复制它们的代码。GPT-2 分词器文件为 MIT，由 `scripts/fetch-gpt2.sh` 下载，不放进仓库，也不进入发布包。

本项目使用 Apache-2.0。
