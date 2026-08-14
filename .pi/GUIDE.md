# Forge 使用指南

Forge 是 [pi](https://pi.dev) 的 coding agent 模板/harness——clone 这个仓库开始一个新项目，路由默认值、agent profile、`.pi/work/` 约定都已经接好线。这份文档回答"我该用哪种模式做事、怎么触发"；`.pi/FORGE.md` 回答"精确的运作细节"（会话里每轮自动注入，不用手动 read）；`.pi/design.md` 回答"为什么设计成这样"。三份文档分工不同，内容不重复，这份是给第一次用的人看的。

## 1. 五分钟上手

- clone 这个模板之后，仓库根目录是空的（除了 `.github/`、`.gitignore`）——那是留给你要开发的项目的，Forge 自己的一切都在 `.pi/` 下面，不会跟你的项目文件冲突。
- 会话一开始，Forge 会自动检查 `.pi/work/` 下有没有未完成的 feature（`tasks.md` 里还有没打勾的项），有的话会主动提一句"你有 N 个进行中的功能"，不用你记得敲 `/resume`。
- `.pi/FORGE.md` 的内容每轮都会自动拼进 system prompt，你不需要手动读它、也不需要告诉 agent 去读——它已经知道。
- 日常直接用中文交流，代码标识符、commit message、命令名保留英文。

## 2. 开发场景一览表

先看这张表，找到你现在的场景属于哪一类；每一类具体怎么触发、精确阈值是什么，看第 3 节和 `.pi/FORGE.md` 的 Routing 表。

| 我想做的事 | 对应模式 |
|---|---|
| 随口问一句，不涉及改文件 | 直接在当前会话问 |
| 单一职责的小改动 | 直接在当前会话做 |
| 有好几个方向要探（哪怕只是一个问题，但有几个角度都值得查） | dispatch scout 并行探索 |
| A 做完、B 接着用 A 的结果 | chain dispatch |
| 公共 API 改动/破坏性改动/改动范围大，想要独立复核 | 本会话直接改+测，完了 chain 到 reviewer（说"guard X"） |
| 真的想对比两种实现，不只是讨论 | Race 模式（说"race A vs B"） |
| 需求模糊、改动范围大、或者要跨会话存活 | `.pi/work/<slug>/`（spec-driven 流程） |
| 一次坐下要做完，但想要看得见进度、要点结构 | `/plan` 模式 |
| 没人盯着、要按计划长期反复重试 | `.pi/scripts/loop.sh` |

## 3. 各模式怎么触发

### 直接问答 / 单会话开发
什么都不用做，正常说话就行。这是默认路径，多数任务走到这一步就结束了。

### Scout 并行探索
不用自己手动 dispatch——描述清楚你想查的问题，主 session 会自己判断要不要并行派 scout 去查。scout 是只读的，探完直接回来报告文件路径和行号，不会自己改代码。

### Chain 顺序调度
适合"先做 A，A 的结果喂给 B"这种有依赖的多阶段任务，通常也是主 session 自己判断触发，不需要你手写调用形状。真正的调用参数细节（`{previous}` 怎么传、并行上限是多少）在 `.pi/FORGE.md`"How to actually dispatch"里。

### Guard —— 说"guard X"
大改动想要独立复核时用这个：改动本身还是在当前会话做、测试也在当前会话跑，只有最后一步"独立看一遍"会 chain 到 `.pi/agents/reviewer.md`，没过这关不算完。

### Race 模式 —— 说"race A vs B"
真的要对比两种实现方案时用，会开两个 git worktree、并行派 `.pi/agents/builder.md` 各写一份，跑完你选一个赢家合并、清理另一个 worktree。完整步骤和坑点在 `.pi/FORGE.md`"Race mode mechanics"和 `.pi/skills/worktree/SKILL.md`。

### spec-driven —— `.pi/work/<slug>/`
需求模糊、改动范围大、或者需要跨会话恢复时用。会经过 spec → clarifications → plan → tasks → build → validate 几个阶段，文件落在 `.pi/work/<slug>/` 下面，提交进 git，相当于给这个功能留一份设计文档附件。具体文件约定看 `.pi/work/README.md`，方法论看 `.pi/skills/spec-driven/SKILL.md`。

### `/plan` 模式
一次坐下能做完，但想要个结构化的执行清单时用。`/plan`（或 `--plan` 启动参数、`Ctrl+Alt+P`）打开只读探索模式：

1. **发散**——如果任务本身有歧义，agent 会先摆出几个真正可行的方案，各自说清楚包含什么、不包含什么，也会指出哪些方案适合走 Race；任务足够简单的话这一步会直接跳过。
2. **收敛**——用 questionnaire 工具把候选范围做成一条条可以打勾的清单，让你逐项确认要不要，而不是一段开放式文字讨论。
3. 确认完，agent 收敛成一份编号 `Plan:` 清单。
4. 这时候会问你"Execute the plan / Stay in plan mode / Refine the plan"——选 **Execute the plan** 会自动退出 plan mode、恢复完整工具权限，按步骤开始执行，每完成一步打一个 `[DONE:n]`。`/todos` 随时能看当前进度。

### `loop.sh` 无人值守
要让一个目标在没人盯着的情况下按计划反复重试（比如夜间跑、定时跑），用 `.pi/scripts/loop.sh`，靠 launchd/cron 这类外部调度器驱动一次次独立的 `pi -p` 进程。用法和例子在 `.pi/scripts/README.md`。

## 4. 常用命令速查

| 命令 | 作用 |
|---|---|
| `/plan` | 切换 plan 模式（只读探索+发散收敛） |
| `/todos` | 看当前 plan 的执行进度 |
| `/commit` | 按项目约定生成 commit |
| `/changelog` | 更新 changelog |
| `/readme` | 生成/更新 README |
| `/status` | 扫描 `.pi/work/*/tasks.md` 汇报进度 |
| `/retro` | 从导出的会话日志里挖掘真实的摩擦点，转成文档修复项 |
| `/smoketest` | 一次性跑一遍路由/dispatch/Race/spec-driven/prompt template 等全部机制 |
| `/init` | 生成或更新项目自己的 `AGENTS.md`（不会覆盖手写内容） |
| `/btw <问题>` | 不打断当前任务/plan 状态，快速回答一个题外问题 |
| `/release` | 串联版本号→changelog→tag→GitHub release→部署 |
| `/footer` | 切换底部状态栏显示 |
| `/label [name]` | 给当前 session 命名，方便在选择器和 footer 里认出来 |
| `/handoff <goal>` | 把当前会话的关键决策/进度提炼成一段 prompt，开一个新会话接着做 |
| `/recap [instructions]` | 立刻手动触发一次 compact（也会在 context 用量超过阈值时自动触发） |

## 5. 接下来读哪里

- `.pi/FORGE.md` —— 运作细节、精确的路由表、dispatch 调用形状。
- `.pi/design.md` —— 为什么是这样，完整决策记录。
- `.pi/work/README.md` —— spec-driven 的文件约定。
- `.pi/skills/*/SKILL.md` —— 语言、架构、方法论参考，按需自动加载。
- `.pi/scripts/README.md` —— `loop.sh`/`worktree.sh` 的用法和例子。
