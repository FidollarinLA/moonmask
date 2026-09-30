# 2026-09-30 验收检查与截止前迭代方案

依据用户提供的九项验收指南。最后开始核查的时间为北京时间23:40，23:33已过；目标是在午夜前同步已验证成果。最终是否通过由主办方决定。

## 可接续执行清单

- [x] 读取本地交接、根AGENTS、git状态；保留此前所有草稿。
- [x] 用户本轮明确授权分阶段commit/push；_local仍禁止进入Git；不得改git config。
- [ ] 核对以下九项证据，无法验证的列为待确认。
- [ ] 重跑严格检查/测试/构建、logits协议及评分测试、限定Playground测试。
- [ ] 第一阶段：提交并推送已有空白/logits/模型回归成果，记录commit及远端一致性。
- [ ] 第二阶段：修复Playground操作状态/可视化说明，完善README干净环境复现和Windows入口；测试后推送。
- [ ] 查询远端CI与Pages部署，记录真实状态和失败原因。
- [ ] 北京时间23:59最终同步检查（定时设置成功前不可标完成）。

## 九项验收证据

| 项 | 当前判定 | 证据/缺口 |
| --- | --- | --- |
| 1 MoonBit及版本 | 本地满足 | 核心引擎/CLI/Playground均MoonBit；便携moonc v0.10.14。Python仅计算真实模型logits及独立校验 |
| 2 公开GitHub与提交 | 仓库公开，最新功能待推送 | https://github.com/FidollarinLA/moonmask；本轮需同步未提交成果 |
| 3 结构与核心功能 | 本地满足，重跑确认 | regex/schema/gbnf/vocab/mask职责独立；JSON空白与真实logits接入已有测试 |
| 4 README可复现 | 有文档，需改善 | 增加跨平台安装/最小示例与验证入口；不依赖私有_local工具链 |
| 5 CI检查构建测试 | 配置满足，最新执行待查 | .github/workflows/ci.yml；Windows/Linux/macOS检查测试，JS协议及Pages构建 |
| 6 可运行示例 | 本地满足 | cmd/main随机实验；examples/logits真实模型；Playground交互 |
| 7 核心测试 | 本地历史通过，重跑确认 | 各后端88/88、Playground8/8、协议+评分10/10；边界/错误/EOS/预算覆盖 |
| 8 mooncakes发布 | 待在线核实 | 本地moon.mod版本0.1.0并不证明已发布；查询注册表或消费包验证 |
| 9 OSI许可/依赖 | 主许可证满足，依赖复查 | Apache-2.0 LICENSE；模型不入库，引用/依赖需标来源与许可 |

## 产品优先级与范围

截止前优先可复现、明确错误状态、可操作示例、线上同步。保留已验证接口，避免截止前扩大schema子集。已有四任务48次真实模型回归必须保留失败案例：结构正确不代表语义正确。后续再做低开销绑定、性能拆分、更多模型，不能将随机采样率包装成质量/速度提升。

## 继续工作的命令

本机PowerShell先 `. ./_local/env.ps1`。其他电脑按README安装MoonBit，Unix先 `export PATH="$HOME/.moon/bin:$PATH"`。

```text
moon check --deny-warn
moon build --deny-warn
moon test --deny-warn
moon test --target native --deny-warn
moon check --target js --deny-warn
moon build --target js --release cmd/logits
python -m unittest discover -s examples/logits -p 'test_*.py' -v
moon info
moon fmt
```

Playground目录运行 `moon test --target js -p FidollarinLA/moonmask-playground/app`。仅将明确审阅过的文件git add，永不`git add .`。每轮更新_local/AGENT.md §2/§9。以实际推送成功为准，不把计划写成结果。
