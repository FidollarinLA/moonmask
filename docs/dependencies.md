# 依赖与许可来源

moonmask 的原创实现使用仓库根目录 Apache-2.0 LICENSE。以下组件作为外部依赖使用，未将模型权重或第三方完整实现复制到本仓库。

| 组件 | 用途 | 许可/来源 |
| --- | --- | --- |
| howtomakeaname/tokenizers-moonbit 0.13.1 | 词表解析 | Apache-2.0，依赖moon.mod及上游仓库声明 |
| moonbitstack/moonschema 0.2.0 | 独立schema验证 | Apache-2.0，上游moon.mod |
| moonbitlang/x 0.5.5 | 文件/系统辅助 | Apache-2.0，上游moon.mod |
| moonbit-community/rabbita | Playground界面 | 见Playground依赖包LICENSE及 https://github.com/moonbit-community/rabbita |
| GPT-2 tokenizer.json | 用户另行下载的词表 | https://github.com/openai/gpt-2 （MIT）；固定下载哈希见scripts |
| DistilGPT-2 权重 | 可选真实logits示例 | 模型卡Apache-2.0，固定revision见examples/logits/README；不进入Git或发布包 |

PyTorch、Transformers等Python依赖由用户独立安装，见examples/logits/requirements.txt和模型运行说明。算法方法与视觉参考在README“参考与许可证”列出；参考设计不表示复制上游代码。发布包与GitHub源码的版本可能不同，必须按实际发布版本确认接口。
