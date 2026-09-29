# 支持的 JSON Schema 子集

[← 返回 README](../README.md)

moonmask 只接受它能精确编译的关键字。写不进这个子集的关键字直接报错，不会被静默忽略，这样生成的自动机和 schema 的含义永远一致。

## 类型与关键字

- `string`，可带 `minLength` / `maxLength`。长度按 JSON 解码后的码点数计算：`\n` 算 1，一个汉字或 emoji 也算 1，不按源码字节数，也不按字素簇（`e` 加组合音符算 2）。内容是可见 ASCII、常见转义 `\" \\ \/ \b \f \n \r \t`、`\uXXXX`（四位十六进制），以及 U+0080 到 U+10FFFF 的合法 UTF-8。`\uD800\uDC00` 这种代理对算 1 个码点。落单的代理项、不足四位、非十六进制，以及 `\u{...}` 会被拒绝，不会生成。过长编码、截断的 UTF-8 同样拒绝。`pattern` 是不锚定的 ASCII 安全子集：字面量、分组、选择、量词，以及只含原始 JSON 字符串字节的字符类（可见 ASCII，不含 `"` 和 `\`）。它可以和长度、转义、`\uXXXX`、原样 UTF-8 同时使用。`pattern` 和 `minLength` / `maxLength` 没有交集时会报错，不会编成一个什么都不接受的自动机。`minLength` 大于 `maxLength` 同样报错。`.`、锚点、`\s`、pattern 里的 `\u` / `\u{...}` / Unicode 属性，以及其他写不进这个子集的 pattern 会报错，不会被忽略。
- `integer`。为了让结果能被 JSON 解析器精确读入，位数最多 15 位，不含前导零。可带 `minimum` / `maximum`。`exclusiveMinimum` / `exclusiveMaximum` 必须是数字，表示开区间；同时写时取更紧的一侧。
- `number`。小数部分最多 15 位，指数最多 2 位。带数值范围时不再生成科学计数法，只生成落在区间内的整数，以及最多 15 位小数。
- `boolean`、`null`。
- `enum`、`const`。如果同时写了 `type`，会先按类型过滤候选值。
- `object`。属性按 `properties` 的声明顺序输出。`required` 里的属性一定出现，其余属性可以省略，省略后不会留下多余的逗号。`required` 里的名字必须都已声明。没写 `additionalProperties`，或者写成 `false`，都表示不能多出别的字段。`true` 和一份 schema 会报错，不会被当成 `false`。
- `array`，必须有 `items`，可带 `minItems` / `maxItems`。
- `anyOf`，以及 `type` 写成类型数组。
- 注解键 `title`、`description`、`$schema`、`$id`、`$comment`、`examples`、`default` 会被忽略。
- 根 schema 上的 `$defs`。`$ref` 只能是 `#/$defs/名字`（名字按 JSON Pointer 转义，`~1` 表示 `/`），并在编译时展开。允许一串没有环的引用。`$ref` 旁边可以再写 `type`、`enum`、`const`、`minLength`、`maxLength`、`pattern`。这些关键字和被引用 schema 一起生效；没有交集就报错，不会生成空语言。被引用的 schema 自己如果也在 `$ref` 旁边写了同样这些关键字，多层一起取交集。长度仍按解码后的码点数，`pattern` 仍是不锚定的 ASCII 安全子集，写不进这个子集的 pattern 会报错。`minLength`、`maxLength`、`pattern` 只保留满足它们的字符串。被引用 schema 是字符串和其他类型的并集时，只留下这个字符串部分；如果引用根本给不出这样的字符串，就报错。别的关键字写在 `$ref` 旁边仍然报错。环、`$dynamicRef`、文档外的 URL、`#/definitions/`、以及没有落在某个 `$defs` 条目上的指针，都会报错。`$defs` 可以写在当前这个 schema 对象上，不限于文档根；`$ref` 用无环的 JSON Pointer 指向已经出现的 `$defs` 条目，例如 `#/$defs/名字` 或 `#/properties/a/$defs/名字`。
- 其余关键字，包括 `format`、`multipleOf`、`oneOf`，直接报错，不会静默忽略。draft-04 那种布尔值 `exclusiveMinimum` / `exclusiveMaximum` 同样报错。

## 限制

- 只生成紧凑 JSON，不含空白。
- 语言为空就报错，不会编成一个不接受任何字符串的自动机。直接写在 schema 上的 `pattern` 与 `minLength` / `maxLength` 没有交集时如此，`minLength` 大于 `maxLength` 时如此，`$ref` 上的约束没有交集时也如此。
- 字符串接受合法 UTF-8 和 `\uXXXX`。落单代理项和 `\u{...}` 会报错。`pattern` 不能写非 ASCII，也不能写 `\u` 或 Unicode 属性。
- object 的属性顺序固定为声明顺序，不会调换。`additionalProperties: true` 和 schema 形式会报错。
- 数值边界本身最多 15 位整数和 15 位小数；超出这个范围会报错，而不是截断。带范围的 `number` 不生成指数。
- `$ref` 不能成环，也不能指向另一份文档。递归 schema 和 `$dynamicRef` 不支持。`$defs` 可以写在当前 schema 对象上。`$ref` 必须是无环 JSON Pointer，而且要落在某个 `$defs` 条目上。`$ref` 旁边除了 `type`、`enum`、`const`、`minLength`、`maxLength`、`pattern`，别的约束不会和引用一起生效。这些关键字可以沿一串无环引用逐层收窄。
