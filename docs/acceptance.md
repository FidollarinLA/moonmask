# 开发证据与演示指南

用户已确认项目通过验收，无需再提交表格。本文件保留为开发演示指南，不是申报表；后续重点是功能、测试与可复现证据。

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

## 提交前状态

本轮所有改动均为未提交的本地修改。线上 Playground 仍是此前发布版本；没有 commit、push、PR 或 moon publish。`_local/` 包含交接、工具链和原始日志，受忽略规则保护，不进入提交或发布。
