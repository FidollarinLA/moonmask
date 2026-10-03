# 开发证据与演示指南

根据选手提供的验收指南，审核通过后无需再次提交表格，只需持续开发并上传 GitHub。本文记录九项验收证据与复现入口；审核通过不等于最终验收通过，最终结论由主办方作出。

## 九项验收对照

| 验收要求 | 实现与验证入口 |
| --- | --- |
| 1. MoonBit 为主，moonc ≥ 0.10.14 | 核心五包、CLI 和 Playground 均为 MoonBit；`moon version --all` 查看工具链，README 标明最低版本。Python 仅用于可选模型推理与独立验证。 |
| 2. GitHub 公开，历史清晰 | [公开仓库与历史](https://github.com/FidollarinLA/moonmask/commits/main/)，保留真实开发和发布时间。 |
| 3. 结构与核心功能 | `regex/schema/gbnf/vocab/mask` 分包；支持范围与不支持项见 [Schema 规格](schema-subset.md)、[GBNF 规格](gbnf.md) 和 [设计](design.md)。 |
| 4. README 可复现 | [README](../README.md) 含工具链、包安装、最小示例、源码运行、模型演示及限制。 |
| 5. CI 覆盖检查、构建、测试 | [CI](../.github/workflows/ci.yml) 覆盖 Windows/Linux/macOS、native、Playground、logits 协议与评分；另检查格式及公开接口。 |
| 6. 可运行示例 | `moon run cmd/quickstart` 无需模型或词表；[模型示例](../examples/logits/README.md) 为可选扩展。 |
| 7. 核心测试 | 88 项核心测试、10 项 Playground 测试、6 项协议与 4 项评分测试；见下方复现命令。测试数仅描述当前版本，不代表穷尽所有输入。 |
| 8. mooncakes 发布 | 模块 `FidollarinLA/moonmask@0.1.0`；使用 `moon view FidollarinLA/moonmask` 查询、`moon add FidollarinLA/moonmask@0.1.0` 安装。[包文档](https://mooncakes.io/docs/FidollarinLA/moonmask)。 |
| 9. OSI 许可证与来源 | 根目录 [Apache-2.0 LICENSE](../LICENSE)，[依赖与参考来源](dependencies.md)。模型权重及下载词表不随包分发。 |

## 0.1.0 发布验证

2026-10-01 北京时间 15:22:59，mooncakes 接受 `FidollarinLA/moonmask@0.1.0`（注册表记录的 UTC 时间为 07:22:59）。`moon view FidollarinLA/moonmask` 已返回版本、Apache-2.0 许可及公开仓库地址。随后在临时独立项目中实际下载发布包，通过 `moon check --deny-warn`、`moon build --deny-warn` 和 quickstart；没有使用本地模块覆盖。

本机 moonc v0.10.14：核心与 native 各 88/88，Playground 10/10，协议与评分 10/10；六组 native 随机实验（紧凑/空白 × 三个 schema）分别 masked 100/100、unmasked 0/100。已验证格式与接口无额外变化。真实模型的已有记录见下文，本次发布核查没有重新下载权重或重跑模型推理。

## 本地复现

使用 moonc ≥ 0.10.14，源码根目录执行：

```bash
moon version --all
moon update
./scripts/fetch-gpt2.sh  # Windows: python scripts/fetch-gpt2.py
moon check --deny-warn
moon build --deny-warn
moon test --deny-warn
moon run cmd/quickstart
moon test --target native --deny-warn
moon check --target js --deny-warn
moon build --target js --release cmd/logits
python3 -m unittest discover -s examples/logits -p 'test_*.py' -v
moon info && moon fmt
git diff --exit-code
```

协议测试需 Node.js；native 测试需 C 编译器。Playground 在 `playground/` 内运行 `moon check --deny-warn`、`moon test --target js -p FidollarinLA/moonmask-playground/app` 与 `./build.sh`。最新执行结果以 [Actions](https://github.com/FidollarinLA/moonmask/actions) 为准。

## 项目说明

moonmask 是 MoonBit 原生的结构化输出约束库，把受支持的 JSON Schema、正则与非递归 GBNF 转为字节级 DFA，再通过词表前缀树计算每个状态允许的 token。随机采样 CLI 和 Playground 保留原有演示；新增的 [examples/logits](../examples/logits/README.md) 已接通真实 DistilGPT-2，由 MoonBit 根据逐步 logits 选择 token。

可展示的实现包括：多种约束共用自动机与 token 掩码；有死状态剪枝、接受距离与按状态缓存；Schema 不支持的关键字显式报错；支持 required/可选字段、本地无环引用、解码后字符串长度及受限 pattern；可视化逐 token 掩码和自动机。

本轮新增 `whitespace=true`：默认紧凑 JSON 保持兼容，可选放行结构边界和文档首尾的 SP/TAB/CR/LF，覆盖引用、枚举及空/嵌套容器，不放宽数字、字符串与逗号规则。

## 三分钟演示

1. 打开本地 Playground 的 JSON Schema / user 预设。解释初始掩码、required 和接受状态。
2. 切换 **Allow JSON whitespace**，观察新增四种空白 token；点一次换行，证明前导空白合法但还不能结束。
3. 单步或播放到完整 JSON；展示 eos 只在接受状态出现。切回 **Compact JSON**，确认状态、输出和旧实验被清空。
4. 跑 30 + 30 samples；展示独立 moonschema 校验，并明确这是随机采样器的结构合法性检验。
5. 展示三组 native 实验与真实 logits 记录，说明“合法 JSON”和“已经 EOS”是独立指标，并演示可选收尾策略。

## 验收证据入口

- [空白与 schema 边界测试](../schema/whitespace_test.mbt)：结构空白、required、分隔符、引用交集、enum/const、字符串和数字。
- [token / EOS / 预算测试](../mask/whitespace_test.mbt)：多字节结构 token、空白循环、接受后尾部空白、强制收尾、稀疏词表无法完成。
- [Playground 测试](../playground/app/app_wbtest.mbt)：全部预设、空白模式、重建重置及非 Schema 模式不受影响。
- [Schema API](../schema/pkg.generated.mbti)：两个默认关闭的可选空白参数；[Mask API](../mask/pkg.generated.mbti)：新增 greedy logits 选择及明确的错误类型。
- [复现实验记录](verification-2026-09-29.md)：工具链、命令、结果、限制。

## 后续证据

真实逐步 logits 示例及四任务回归入口已完成，见 [模型演示记录](logits-demo.md)与[批量运行说明](../examples/logits/README.md#multi-case-regression)。回归将 schema、EOS、完整预期值匹配分开统计。下一步扩展模型比较及更多任务；当前手写小语料不能推导通用准确率。

随后补冷/热状态掩码延迟、编译时间、内存和真实解码端到端耗时的重复测量。当前 CLI 的一次起始状态耗时不构成完整性能报告；随机样本的 token 长度也不证明推理速度提升。

## 时间与交付边界

2026-09-30 的本地成果在 2026-10-01 才同步 GitHub，详见[历史记录](acceptance-plan-2026-09-30.md)。后续发布与补充工作按实际时间记录，不能当作截止前交付的证据。`_local/` 永不进入 GitHub 或发布包。本文是工程证据，不代替主办方的最终验收结论。
