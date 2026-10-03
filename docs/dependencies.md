# 依赖与许可来源

moonmask 的原创实现使用仓库根目录 Apache-2.0 LICENSE。以下组件作为外部依赖使用，未将模型权重或第三方完整实现复制到本仓库。

| 组件 | 用途 | 许可/来源 |
| --- | --- | --- |
| howtomakeaname/tokenizers-moonbit 0.13.1 | 词表解析 | Apache-2.0，依赖moon.mod及上游仓库声明 |
| moonbitstack/moonschema 0.2.0 | 独立schema验证 | Apache-2.0，上游moon.mod |
| moonbitlang/x 0.5.5 | 文件/系统辅助 | Apache-2.0，上游moon.mod |
| moonbitlang/regexp 0.3.5 | 正则差分测试 | Apache-2.0，[上游](https://github.com/moonbitlang/regexp.mbt) |
| moonbitlang/async | x 的传递依赖 | Apache-2.0，[上游](https://github.com/moonbitlang/async)；库解析为 0.19.2，Playground 工作区解析为 0.22.4 |
| moonbit-community/rabbita 0.16.3 | Playground 界面 | Apache-2.0，[上游](https://github.com/moonbit-community/rabbita) |
| moonbitlang/moonback 0.8.5 | Playground 传递依赖 | Apache-2.0，[上游](https://github.com/moonbitlang/moonback) |
| GPT-2 tokenizer.json | 用户另行下载的词表 | https://github.com/openai/gpt-2 （MIT）；固定下载哈希见scripts |
| DistilGPT-2 权重 | 可选真实logits示例 | 模型卡Apache-2.0，固定revision见examples/logits/README；不进入Git或发布包 |

PyTorch、Transformers等Python依赖由用户独立安装，见examples/logits/requirements.txt和模型运行说明。算法方法与视觉参考在README“参考与许可证”列出；参考设计不表示复制上游代码。发布包与GitHub源码的版本可能不同，必须按实际发布版本确认接口。

上述 MoonBit 依赖的许可证与仓库地址已对照实际解析版本的模块清单核查。依赖由包管理器获取，其许可证和版权声明保留在上游包中；本发布包不内嵌依赖源码。根目录 Apache-2.0 仅声明本项目原创代码的许可。

方法参考 [Outlines](https://github.com/dottxt-ai/outlines)（Apache-2.0）、[XGrammar](https://github.com/mlc-ai/xgrammar)（Apache-2.0）及 [llguidance](https://github.com/guidance-ai/llguidance)（MIT）；token 视觉参考 [tiktokenizer](https://github.com/dqbd/tiktokenizer)（MIT）。这些实现未复制进本仓库。四任务提示词与预期答案为项目手写集成样例，模型输出记录是演示证据，不代表通用准确率评测。
