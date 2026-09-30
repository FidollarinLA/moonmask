# 设计与测试

[← 返回 README](../README.md)

## 从约束到自动机

1. **统一成正则。** JSON Schema 子集由 `schema::to_regex` 翻译成一条按字节写的正则；GBNF 规则展开成同一种语法树；正则直接解析。
2. **Thompson NFA。** 语法树按 Thompson 构造变成 NFA，字符类以字节区间表示。
3. **子集构造。** NFA 确定化成 DFA，转移表按 256 个字节展开。
4. **剪枝与距离。** 从接受状态反向做 BFS：到不了接受状态的状态直接删掉，所以 `Dfa::step` 返回 `-1` 就意味着这条路已经死了；每个状态同时记下到最近接受状态的最短字节数，即 `Dfa::distance`。

## 从自动机到 token 掩码

模型的输出单位是 token，一个 token 是一串字节。`Guide` 负责把“字节级 DFA”翻译成“token 级掩码”：

- 词表先收成一棵**字节前缀树**。算某个状态的合法 token 时，从这个状态出发沿前缀树走：相同前缀只沿 DFA 走一次，某个前缀走不通就把整棵子树丢掉。
- 结果按 DFA 状态缓存为 `token → 下一状态`。收集到的 token 按编号排序，排序后和“每个 token 单独走一遍”完全相同，合法集合不变。
- 结束符（eos）只在接受状态放行；空的特殊 token 始终排除。

在 GPT-2 词表（50,257 个 token）上，`user.json` 起始状态的掩码用前缀树算一次约 4 微秒：只有 `{` 和 `{"` 两个 token 能接上，绝大多数 token 在第一个字节就走不通，整棵子树被一次剪掉。

## 采样器为什么一定能结束

`mask::monkey_step` 在预算内均匀选择合法 token（在接受状态时 eos 也是候选）。超出预算后只选能让 `distance` 严格下降的 token；若已在接受状态，立即选 eos。词表覆盖每个单字节 token 时，可以沿最短路径完成。`mask::monkey` 反复调用它，但还有 `max_tokens * 4 + 64` 的硬上限；超过硬上限或词表无法提供下降路径时返回 `finished=false`。因此 `max_tokens` 是开始强制收尾的软预算，并非输出长度上限；调用者必须检查 `finished`。

## JSON 空白策略

`schema::compile` / `to_regex` 默认 `whitespace=false`。开启时，内部 `Context` 携带根 schema 和 `[ \\t\\r\\n]*` 策略；容器、分隔符和文档首尾插入该规则，标量内部规则不变。`enum` / `const` 的规范 JSON 文本仅在字符串外的结构标点旁插入空白，跟踪反斜线转义以免误改字符串内容；引用过滤仍以紧凑序列化值检查约束交集。

空白可能形成自环；预算后的严格距离下降排除无进展的空白循环，接受状态直接输出 eos。字节掩码本身仍允许合法的尾部空白，结束选择由采样策略负责。稀疏词表不保证 token 层可完成，测试明确验证其停滞返回值。

## 测试

真实模型可调用 `Guide::greedy(state, logits)`。它不修改输入数组，只在 `allowed(state)` 中选取最高分；相同分数选择最小 token ID。NaN、正无穷和错误维度报错，负无穷表示候选被上游禁用。默认不强制收尾；可显式传 `finish=true` 排除非下降路径，在接受状态只考虑 EOS。没有可用候选时返回 `None`，与 EOS 不同。集成与真实逐步记录见 [logits-demo.md](logits-demo.md)。

```bash
moon test --deny-warn
```

- 正则与 `moonbitlang/regexp` 做差分，9000 次以上对照。
- Schema 自动机随机生成的字符串全部交给 `moonschema` 校验。
- 有限语言上，掩码允许的 token 与穷举得到的“存在合法补全的 token”一致。
- 前缀树算出的 token 集合与逐个扫描词表的结果相同：小词表上每个 DFA 状态都对照过，GPT-2 词表上对照过若干状态。
- 固定 GBNF 文法由 DFA 采样，采样结果全部被同一文法的解释器接受。
- 手动逐步调用 `monkey_step` 与 `monkey` 的输出逐 token 相同。
- Playground 的每个预设都能编译，加掩码的随机采样全部合法。

CI 在 Ubuntu、macOS、Windows 上跑 `moon check --deny-warn`、`moon test --deny-warn`、格式和 `.mbti` 接口文件检查；另有 native 后端的猴子实验和 Playground 构建。
