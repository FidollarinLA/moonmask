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

在开发机上一次完整运行大约 2 秒。程序会先打印在 GPT-2 词表上、对第一个 schema 的起始状态用前缀树算掩码的耗时。下面这一次是 4.041 微秒（词表 50257，`user.json` 起始状态，2 个 token 能接上；这个状态大部分 token 在第一个字节就走不通）。这只是记录，不是性能门槛，结果是：

| schema | masked valid | unmasked valid | avg tokens (masked) | DFA states |
| --- | --- | --- | --- | --- |
| examples/schemas/user.json | 100/100 | 0/100 | 36.79 | 500 |
| examples/schemas/order.json | 100/100 | 0/100 | 68.29 | 1401 |
| examples/schemas/tool_call.json | 100/100 | 0/100 | 34.7 | 1016 |

## 支持的 JSON Schema 子集

- `string`，可带 `minLength` / `maxLength`。长度按 JSON 解码后的码点数计算：`\n` 算 1，一个汉字或 emoji 也算 1，不按源码字节数，也不按字素簇（`e` 加组合音符算 2）。内容是可见 ASCII、常见转义 `\" \\ \/ \b \f \n \r \t`、`\uXXXX`（四位十六进制），以及 U+0080 到 U+10FFFF 的合法 UTF-8。`\uD800\uDC00` 这种代理对算 1 个码点。落单的代理项、不足四位、非十六进制，以及 `\u{...}` 会被拒绝，不会生成。过长编码、截断的 UTF-8 同样拒绝。`pattern` 是不锚定的 ASCII 安全子集：字面量、分组、选择、量词，以及只含原始 JSON 字符串字节的字符类（可见 ASCII，不含 `"` 和 `\`）。它可以和长度、转义、`\uXXXX`、原样 UTF-8 同时使用。`.`、锚点、`\s`、pattern 里的 `\u` / `\u{...}` / Unicode 属性，以及其他写不进这个子集的 pattern 会报错，不会被忽略。
- `integer`。为了让结果能被 JSON 解析器精确读入，位数最多 15 位，不含前导零。可带 `minimum` / `maximum`。`exclusiveMinimum` / `exclusiveMaximum` 必须是数字，表示开区间；同时写时取更紧的一侧。
- `number`。小数部分最多 15 位，指数最多 2 位。带数值范围时不再生成科学计数法，只生成落在区间内的整数，以及最多 15 位小数。
- `boolean`、`null`。
- `enum`、`const`。如果同时写了 `type`，会先按类型过滤候选值。
- `object`。按 `properties` 的声明顺序输出全部属性。`required` 里的名字必须都已声明。`additionalProperties` 只能是布尔值。
- `array`，必须有 `items`，可带 `minItems` / `maxItems`。
- `anyOf`，以及 `type` 写成类型数组。
- 注解键 `title`、`description`、`$schema`、`$id`、`$comment`、`examples`、`default` 会被忽略。
- 根 schema 上的 `$defs`。`$ref` 只能是 `#/$defs/名字`（名字按 JSON Pointer 转义，`~1` 表示 `/`），并在编译时展开。允许一串没有环的引用。`$ref` 旁边可以再写 `type`、`enum`、`const`、`minLength`、`maxLength`、`pattern`。这些关键字和被引用 schema 一起生效；没有交集就报错，不会生成空语言。被引用的 schema 自己如果也在 `$ref` 旁边写了同样这些关键字，多层一起取交集。长度仍按解码后的码点数，`pattern` 仍是不锚定的 ASCII 安全子集，写不进这个子集的 pattern 会报错。`minLength`、`maxLength`、`pattern` 只保留满足它们的字符串。被引用 schema 是字符串和其他类型的并集时，只留下这个字符串部分；如果引用根本给不出这样的字符串，就报错。别的关键字写在 `$ref` 旁边仍然报错。环、`$dynamicRef`、文档外的 URL、`#/definitions/`、指向 `$defs` 里面再往下的指针，以及写在根以外的 `$defs`，都会报错。
- 其余关键字，包括 `format`、`multipleOf`、`oneOf`，直接报错，不会静默忽略。draft-04 那种布尔值 `exclusiveMinimum` / `exclusiveMaximum` 同样报错。

## GBNF 子集

一条文法可以有多条规则，用 `::=` 分开。**第一条规则是入口。** 规则之间可以互相引用，编译时展开进现有的字节 DFA。成环会报错，包括间接引用，所以不支持递归规则。

支持双引号字面量（转义只有 `\\`、`\"`、`\n`、`\r`、`\t`）、选择 `|`、分组 `(...)`，以及量词 `*`、`+`、`?`、`{n}`、`{n,m}`、`{n,}`。`#` 到行尾是注释。

字符类只接受单字节：`[abc]`、`[a-z]`、`[^abc]`、`[^a-z]`。`[^...]` 是 0 到 255 里没被列进去的那些字节。类里面 `\]`、`\\`、`\-` 是字面量；`-` 放在类的开头或结尾、或者不能构成区间时，也是字面量。倒过来的区间会报错。类里还可以写 `\n`、`\r`、`\t`。

递归规则、名字后面紧跟 `(` 的带参数规则、以及 `\p{...}` / `\P{...}` 这类 Unicode 属性，都会报错，不会被忽略。词法优先级也不支持。

固定文法经 DFA 采样得到的字符串，必须被同一文法的简单解释器接受。解释器和 DFA 用的是同一棵已展开的语法树，采样只覆盖自动机能在长度上限内生成的串。

## 适用范围与限制

- 推理时每一步都要能拿到 logits，例如进程内推理或本地推理服务。只返回整段文本的云端 API 只能事后校验。
- 只生成紧凑 JSON，不含空白。
- 字符串接受合法 UTF-8 和 `\uXXXX`。落单代理项和 `\u{...}` 会报错。`pattern` 不能写非 ASCII，也不能写 `\u` 或 Unicode 属性。
- object 会输出每一个声明过的属性，不省略可选字段。
- 词表只支持 GPT-2 字节级 BPE。SentencePiece 的 `▁` 会在加载时拒绝。
- 数值边界本身最多 15 位整数和 15 位小数；超出这个范围会报错，而不是截断。带范围的 `number` 不生成指数。
- `$ref` 不能成环，也不能指向另一份文档。递归 schema、`$dynamicRef` 和根以外的 `$defs` 不支持。`$ref` 旁边除了 `type`、`enum`、`const`、`minLength`、`maxLength`、`pattern`，别的约束不会和引用一起生效。这些关键字可以沿一串无环引用逐层收窄。
- GBNF 子集不能递归，不能带参数，也不能写 Unicode 属性或非 ASCII 字符类。入口是第一条规则，不是名字叫 `root` 的那条。

## 设计

正则先解析成语法树，再用 Thompson 构造变成 NFA，然后做子集构造得到 DFA。到不了接受状态的状态会被剪掉，每个状态记下到最近接受状态的最短距离。掩码层按 DFA 状态缓存“token → 下一状态”。算这个集合时，词表先收成一棵字节前缀树：相同前缀只沿 DFA 走一次，某个前缀走不通就把整棵子树丢掉。收集到的 token 再按编号排序。排序后的结果和“每个 token 单独走一遍”相同，合法 token 集合不变。结束符仍然只在接受状态放行，空的特殊 token 仍然排除。采样器在预算内均匀选择合法 token；超出预算后只选让距离下降的 token，因此在词表覆盖单字节时一定能结束。

## 测试

```bash
moon test --deny-warn
```

- 正则与 `moonbitlang/regexp` 做差分，9000 次以上对照。
- Schema 自动机随机生成的字符串全部交给 `moonschema` 校验。
- 有限语言上，掩码允许的 token 与穷举得到的“存在合法补全的 token”一致。
- 前缀树算出的 token 集合与逐个扫描词表的结果相同：小词表上每个 DFA 状态都对照过，GPT-2 词表上对照过若干状态。
- 固定 GBNF 文法由 DFA 采样，采样结果全部被同一文法的解释器接受。

## 参考与许可证

方法参考 Outlines（Willard & Louf, 2023，Apache-2.0）、XGrammar（Apache-2.0）和 llguidance（MIT），不复制它们的代码。GPT-2 分词器文件为 MIT，由 `scripts/fetch-gpt2.sh` 下载，不放进仓库，也不进入发布包。

本项目使用 Apache-2.0。
