# Forge — 基于 pi 的 coding agent harness 设计方案

> 状态：P1+P2 已落地（见根目录），文档随实现同步更新
> 前身：opencode-harness / Conductor
> 目标运行时：https://pi.dev (earendil-works/pi)
> 命名说明："Forge" 是这套方法论/设计层的名字，不是目录命名空间——落盘路径仍用 pi 自己的 `.pi/` 前缀（类似 `.git/`），两者不冲突
>
> **勘误（落地后发现）**：3.3/3.8/第 5 节原来断言"v1 不需要写任何 extension 代码"，这个判断是错的。`.pi/agents/*.md` 的发现和 dispatch（single/parallel/chain）**不是 pi 核心功能**，完全由 pi 自带的一个示例 extension 定义和实现——不装这个 extension，`.pi/agents/*.md` 就是没人读的死文件，pi 启动 banner 也不会有 Agents 分区。已把这个 extension 原样 vendor 进 `.pi/extensions/subagent/`（`index.ts` + `agents.ts`，来自 pi 官方 `examples/extensions/subagent/`）。"不做 guardrail extension" 这条结论不受影响，"完全不需要 extension 代码"这条不成立。另外这个 tool 的 `agentScope` 默认是 `"user"`（只认 `~/.pi/agent/agents/`），dispatch 时必须显式传 `agentScope: "both"` 才能看到项目里 `.pi/agents/` 下的定义，见 `AGENTS.md`"How to actually dispatch"。

---

## 0. 定位

这不是 Conductor 的 1:1 移植，而是一次**用 pi 的原语 + 目前主流最佳实践，重新实现 Conductor 想解决的问题**的机会。判断标准只有一个：**这个组件在 pi 的价值观下还创造净价值吗？** 创造就留（哪怕要换实现方式），不创造就砍，不为了"完整对应原架构"而保留仪式感。

已确认的前提性决策：

| 决策项 | 结论 |
| --- | --- |
| **运行环境假设** | **默认容器化**——GitHub Codespaces / devcontainer 这类一次性、隔离的工作区，clone 模板仓库进容器开发是默认工作流，不是边缘场景。这条是下面权限决策的前提，不是并列项 |
| 权限/护栏模型 | 不做 opencode 式细粒度 per-tool allow/deny 矩阵，**也不做默认的破坏性动作确认钩子**——容器边界本身就是真实隔离，弹窗确认是重复保护，直接跟随 pi 原生的默认放行。v1 不内置，非容器/裸机场景需要时再手动加，见 3.4 |
| MCP | 不做；改用"轻量 CLI 工具 + README"，模型按需读取文档，渐进式披露，避免常驻 token 开销 |
| 使用场景 | 个人使用，但需要**多任务并行 / 多 worktree** 同时进行——不是团队协作场景，但要状态隔离 |
| **产品定位** | **彻底只做 dev**：编码 / 调试 / 测试 / 部署相关任务是唯一的一等公民，不预置通用写作、头脑风暴等非开发能力。技术栈不锁定单一方向——后端/系统编程（Rust/Python 类）、前端/Web（TypeScript 生态）、基础设施/云（Cloudflare 类）、混合栈都要覆盖。固化程度是"默认假设 + 可覆盖"：AGENTS.md/skill 里把 dev 工作流写成默认行为（改完代码默认跑 test/lint），但不是不可绕过的硬规则。真正的硬约束只剩 3.1 节的诚实性原则，不再有运行时权限拦截 |
| **仓库形态** | 做成 **git 模板仓库**——开发新 app 时先 clone 这个模板起步，`.pi/work/` 也进 git（见 3.6） |

---

## 1. 保留的核心思想（跨框架不变的部分）

这些是 Conductor 真正的产品判断，价值不依赖于 opencode，值得原样保留：

- **先识别意图，再选流程重量**：小任务直接做，大任务才上门禁和 artifact。
- **角色边界清晰**：规划 / 实现 / 探查 / 调试 / 测试 / 审查是不同的判断，不该混在一次输出里做完。
- **状态可持续**：复杂工作要能跨轮次恢复，不能每次重新对齐。
- **spec-first 是可选升档路径，不是强制仪式**。

## 2. 因 pi 哲学而改变判断的部分

pi 作者的核心论点（有充分证据支撑，不是臆测）：

- 子 agent 常是"黑箱套黑箱"，很多滥用场景其实是 workflow 设计问题，不是需要子 agent 本身。
- Plan mode 不该是运行时黑箱状态，应该是磁盘上的文件——可 diff、可编辑、可跨会话协作。
- 权限弹窗是安全剧场，真正的隔离要靠容器/沙箱，不是 allow/deny 矩阵。
- MCP 每个会话注入大量常驻 token，多数场景可以用"CLI + README，模型按需读"替代。
- 系统提示应该精简（<1000 token），赌前沿模型已经"懂"角色，不需要冗长说教。

结合这些论点和"多任务并行"场景，我对 Conductor 每个支柱的具体处理如下。

---

## 3. 逐组件方案

### 3.1 Constitution → 精简版 `SYSTEM.md` / `APPEND_SYSTEM.md`

- 只保留**真正不可谈判的硬约束**：禁止编造结果、诚实报告失败、不确定时如实声明置信度。
- **不再包含"破坏性操作前必须确认"**——最初草案里这条是硬约束，但结合"默认容器化运行"这个前提（见 0 节）重新判断：确认弹窗保护的是"操作后果不可挽回"，容器/一次性工作区本身已经兜住了这一层，两道锁做同一件事没有增量价值。诚实性和破坏性操作确认是两回事，砍了后者不等于连诚实性一起砍。
- 去掉原 `law/constitution.md` 里偏程序性的内容（那些应该在 AGENTS.md 或 skill 里）。
- 用 `APPEND_SYSTEM.md` 而非完全替换默认系统提示——保留 pi 默认提示对模型行为的既有校准，只追加我们的强约束，不重新发明一遍"你是个 coding agent"。
- **诚实声明边界**：这套假设的前提是"容器化默认"。如果哪天在裸机、没有沙箱的机器上直接跑 Forge，这里没有兜底——这是刻意取舍，不是遗漏，写在这里是为了不让未来的自己踩坑。

### 3.2 AGENTS.md → 直接复用 pi 原生机制

- pi 原生支持 `~/.pi/agent/AGENTS.md`（全局）→ 父目录级联 → 当前目录，命名和语义与 Conductor 现状完全一致。
- 原 Conductor 的 `AGENTS.md`（全局助手行为 + agent registry 总览）可以**近乎原样迁移**，只需把 opencode 专属的路由描述换成 pi 的 dispatch 工具说明。

### 3.3 Agent 角色 → `.pi/agents/*.md`，但默认不拆

pi 官方 subagent 示例已经是 "Markdown + YAML frontmatter（name/description/tools/model）+ 独立进程隔离" 的模式，和 Conductor 的 agent 概念同构，可以复用这套机制本身。但**默认调用方式要改**：

- **默认路径（多数任务）**：单 session 里完成 plan + build + debug，用磁盘上的 `plan.md` / `TODO.md` 承载"计划"，不拆子 agent。这是对 Zechner 论点的采纳——避免为了流程仪式感制造黑箱。
- **升档路径（隔离/并行确实有收益时）**才 dispatch 到独立 `.pi/agents/*.md` 子 agent：
  - `explore`（scout，Haiku 级快速模型，只读工具）→ 用 pi 的 **parallel dispatch**（最多 8 任务/4 并发）做多方向代码库侦查
  - `review`（独立视角）→ 用 **single dispatch**，保证审查者没有被实现过程中的自我合理化污染
  - `test`（验证）→ 视情况用 single 或作为 **chain dispatch** 的最后一环（implement → test，`{previous}` 传递变更摘要）
  - `plan` 在复杂任务（spec-driven 升档）时可以单独 dispatch 出去做需求/任务拆解，其余场景内嵌在主 session

角色数量从 8 个精简为按需启用的 4 个 profile（scout / planner / reviewer / worker），与 pi 官方参考实现对齐，减少要维护的 agent 定义文件数量。`build` / `debug` / `general` 合并进主 session（worker）职责，不再单列。

- **信任配置**：pi 对项目级 agent（`.pi/agents/*.md`）默认要交互确认信任（`agentScope`/`confirmProjectAgents`）。结合容器化默认前提，直接设 `confirmProjectAgents: false`，不做逐项目确认。pi 的 `trust.json` 是按文件夹路径记录、支持父目录继承的——如果哪天想留一点摩擦，信任容器里的工作区根目录一次就够，不需要每个 worktree 单独确认。

### 3.4 Rules → 拆两半；护栏从"默认必装"降级为"按需 opt-in，v1 不做"

- **纯策略文本**（git 提交规范、代码风格、taste）：并入 AGENTS.md 级联内容，或做成 skill（按需加载，不常驻 token）。
- **escalation（护栏）**：**重新判断后不再是默认构建的一部分。** 最初设想是写一个 `pi.on("tool_call")` extension 拦截破坏性操作再确认。但结合已确认的"默认容器化运行"前提，容器边界本身就是真实隔离，钩子层面的确认反而是 pi 作者说的"安全剧场"——已经有真沙箱的情况下再加一层弹窗，只有摩擦、没有增量安全收益。
  - **v1 不写这个 extension**，Forge 默认就是 pi 原生的放行行为。
  - 万一未来真的要在非容器环境（裸机、没有沙箱的机器）跑，草案清单先留着，不急着现在敲定粒度：
    - **通用**：`git push --force`、`git reset --hard`、`rm -rf`、写 `.env`/密钥/凭证类路径
    - **基础设施/云（Cloudflare 类）**：`wrangler deploy`（生产环境）、`wrangler d1 execute` 里的 DDL/DELETE、任何触达生产 binding 的命令
    - **数据库**：migration 里的 `DROP`/`TRUNCATE`，或直连生产库的操作
    - 判断标准统一：**不可逆 或 影响生产环境** 才拦截确认

### 3.5 Skills → 原样迁移，且天然就是纯 dev 范畴

- Conductor 的 `skills/*/SKILL.md` 已经是 Agent Skills 标准格式，直接拷贝到 `.pi/skills/`（项目级）或 `~/.pi/agent/skills/`（全局），基本不需要改写。
- 逐个核对了现有 11 个 skill，**没有一个是通用非 dev 内容**，"彻底只做 dev"这条不需要砍任何东西：
  - `brainstorm` 实际是"架构权衡评估 + spec 结构"参考知识，不是通用头脑风暴，天然 dev-scoped，保留（只需把里面对 Synapse feature room 的引用改成 3.6 节的 `.pi/work/` 文件）。
  - `python` / `rust` / `typescript` / `shell` — 语言技能，直接保留，覆盖"后端系统编程 + 前端 Web + 混合栈"三个确认过的场景方向。
  - `api` / `architecture` / `paradigms` / `test` / `git` / `spec-driven` — 方法论类，dev 通用，保留。
- 技术栈定位是"全都要、不锁定优先级"，所以不做语言 skill 的取舍，只在 3.9 节的 CLI 工具清单里针对 Cloudflare 类基础设施场景补一块（Conductor 原本没有专门的 infra/deploy skill，是新增项，见 3.9）。
- `detection.md` 这类"什么时候该触发什么 skill"的规则并入对应 SKILL.md 的 description，让 pi 的自动加载机制生效，不需要额外的路由逻辑。

### 3.6 Synapse → 砍掉"服务"，留下"约定"

**结论：功能保留，实现整体替换为纯文件方案，不做专属存储服务/协议。**

原因：
1. pi 明确反对黑箱运行时状态，主张磁盘文件；这和"多任务并行/多 worktree"场景天然兼容——每个 worktree 本来就是独立目录，文件状态自动隔离，不需要一个中心化 room 服务去做隔离。
2. 自建协议/工具是这次唯一真正"无中生有"的大块工作，在个人使用场景下投入产出比低。
3. 文件方案更符合"只做有价值的事"：Git 原生可 diff、可追溯、可在编辑器里直接改，比自定义 room 协议更透明。

设计：

```
.pi/work/<feature-slug>/
  spec.md              # 需求 + 验收标准（原 requirements_spec）
  clarifications.md     # 未决/已决歧义（原 clarifications）
  plan.md               # 架构/接口/风险/验证策略（原 technical_plan）
  tasks.md              # 任务列表 + 完成状态（原 implementation_tasks）
  build-log.md          # 实现摘要 + 改动文件（原 build_result）
  validation.md         # 验证命令 + 结果（原 validation_report）
  drift-review.md       # spec/plan/tasks 与实现的一致性检查（原 drift_review）
```

- 任何 agent（主 session 或 dispatch 出去的子 agent）用普通 `read`/`write`/`edit` 工具读写这些文件，不需要专属 tool。
- 多任务并行：不同 feature-slug 目录天然隔离；配合 `git worktree`，每个 worktree 检出各自分支时，`.pi/work/` 下的目录也随分支走，不会串。
- 跨会话恢复：新开 pi session 时，`meta`（主 session 的角色，见 3.7）先看 `.pi/work/` 下是否有未完成的 feature 目录，有则读取当前进度，等价于原来的 `/resume`。
- 需要长期沉淀的，本来就在仓库里，不需要"导出"这一步——这是对原设计"Markdown 只是可选导出"的转正：从可选变默认。

**要不要进 git：进。** Forge 本身准备做成一个 git 模板仓库——开发新 app 时先 clone 这个模板起步，所以 `.pi/work/` 里的 spec/plan/build-log 应该跟着对应的 feature branch 一起提交。好处是顺带的：feature 合并时，这些文件天然变成这次改动的"设计文档附件"，不需要额外导出这一步。模板仓库本身的 `.pi/work/` 保持空（放一个 `.gitkeep` 或一份示例目录），真正的状态积累发生在每个由模板派生出来的具体项目里。

**`<feature-slug>` 命名规则**：`<kebab-case 短描述>-<4~6 位随机后缀>`，例如 `payment-retry-a3f9`。目录第一次创建时生成一次，之后不变。随机后缀是为了防止多个 worktree/分支各自开了同名 feature（比如都叫 `auth-fix`）——即使两个分支后来合并到一起，目录名也不会撞。

**什么时候才建这个目录**：不是所有任务都要建，复用原 `agents/meta.md` 里 Room Decision Matrix 的判断逻辑，翻译成"要不要落 `.pi/work/`"：

| 任务形态 | 建目录？ |
| --- | --- |
| 直接问答 / 单一明确小改动 | 否——答完/改完就完了，不留痕迹 |
| 单一职责，主 session 能直接搞定 | 否——最多在对话里维护一个临时 TODO，不落盘 |
| 需要并行探查/多方案比较（Race） | 是——并行结果要汇总，值得留一个目录 |
| 需要 build→test/review 门禁（Guard） | 视规模——改动大或涉及公共 API 才建，小范围门禁在对话里跟就够 |
| 多阶段、需要跨轮恢复（PM / Spec-driven） | 是——这正是 `.pi/work/` 存在的意义 |

统一判断标准：**这次工作会不会跨会话继续，或者产出需不需要长期留痕**。会 → 建目录；这一轮对话内就能解决完 → 不建。

### 3.7 meta 的角色 → 主 session 的行为约定，而非独立进程

pi 没有"自动路由到不同进程"的内置机制，`meta` 不再是一个会被 spawn 出去的独立 agent，而是**主 session 自身的开场行为**：

- 通过 AGENTS.md / SYSTEM.md 指示主 session：先判断任务形态和风险，再决定走哪条路径（对应原来的 Direct / Single / Pipeline / Guard / Race / PM / Spec-driven 七档）。
- "分派给专业角色"这件事，落地为主 session 决定要不要调用 dispatch 工具（3.3 节的 single/parallel/chain 三种模式），而不是把"路由"本身做成一个要被调用的黑箱子 agent。
- 好处：路由判断本身是可见的（就在主 session 的输出里），不是"黑箱决定黑箱"。

#### 路由判断标准（从原 `agents/meta.md` 提炼，砍掉仪式性机制，只留判断本身）

原 `meta.md` 有一整套很完整的机制：5 维加权置信度公式、Tier 1-5 分级、结构化 dispatch envelope、Synapse room 生命周期管理、逐信号的 escalation 状态机（含重试退避）。这套东西是为"meta 是独立进程、要把完整上下文塞进结构化信封传给子 agent"这个架构设计的。Forge 里 meta 就是主 session 自己，不存在跨进程传上下文的问题，这套机制**价值归零，直接砍**，只留判断内容本身：

**任务形态 → 处理方式**（替代原来的 Tier 1-5 + 置信度公式）：

| 任务形态 | 处理方式 |
| --- | --- |
| 纯问答，不动文件 | 直接回答 |
| 单一职责，主 session 自己能判断清楚 | 主 session 直接做 |
| 独立的多个工作方向（探查多方向/比较多方案） | parallel dispatch |
| 有依赖顺序的多阶段（先 A 再 B） | chain dispatch |
| 涉及公共 API / 破坏性改动 / 改动范围大 | chain dispatch，最后一环是 test/review，没过这道关不算完 |
| 一次性多阶段任务，要看得见进度但不需要跨会话恢复 | 主 session 维护一个对话内 TODO（不落盘），逐条推进 |
| 需求本身模糊、改动范围大、或需要跨会话恢复 | 升档到 spec-driven，见 3.6 的目录 + 分阶段写文件 |

**默认判断偏好**（原样保留，是好的工程判断，不依赖具体架构）：拿不准的时候，往"更轻"的方向走，不要预设任务比实际复杂。

**常见任务类型的默认判断链**（原 Composition Matrix，按 Forge"默认不拆"的原则重新解读——下面这些阶段大多数时候都在同一个 session 里完成，不是每个箭头都对应一次真实 dispatch）：

| 意图 | 默认链路 |
| --- | --- |
| `feat` | explore → plan → build → test/review（并行） |
| `fix` | debug → build → test |
| `refactor` | explore → plan → build → test |
| `docs` | build（主 session 直接写，不需要探查） |
| `perf` | debug → plan → build → test |
| `chore` / `ci` | build → test |

**手动模式触发关键词**（原样保留，成本低、直接好用）：用户说"loop until X" / "race A vs B" / "guard add X" / "pm full feature" / 描述一个需要跨轮恢复的完整功能 → 对应触发 Loop / Race / Guard / PM / Spec-driven。

**遇到问题时怎么办**（大幅简化原来的 escalation 状态机）：dispatch 出去的子 agent 卡住或信息不够，直接在主 session 里问用户一个具体问题，不做自动重试退避、不做多级信号分类——那套是为多 agent 编排系统的可观测性设计的，单人开发场景下是过度设计。

工作流模式到 pi 原语的映射：

| Conductor 模式 | pi 实现 |
| --- | --- |
| Direct | 主 session 直接回答/改动，不落 `.pi/work/` |
| Single agent | 主 session 自己做，或一次 single dispatch |
| Pipeline | chain dispatch，`{previous}` 传递上一步产出 |
| Guard | chain dispatch，最后一环是 test/review agent，失败即停 |
| Race | parallel dispatch 多个方案，主 session 比较后选择 |
| PM mode | 对话内 TODO，不落盘（规模大到需要跨会话恢复时才升级成 `.pi/work/`，见 3.6 的阈值判断） |
| Spec-driven | intake→…→close 各阶段依次写 3.6 节对应文件，复杂任务才升档到这一档 |

### 3.8 Commands → 大部分不需要写 extension 代码，用 pi 原生 prompt template

重新过了一遍，5 个命令里只有 1 个真正需要代码，其余是"读文件/读 git log + 按格式生成文本"，pi 自带的 **prompt template** 机制（`.pi/prompts/*.md`，Handlebars 变量替换，`/name` 直接调用）就是为这种场景准备的，没必要包一层 `registerCommand()`：

| 命令 | 实现方式 | 理由 |
| --- | --- | --- |
| `/commit` | prompt template | 高频，但逻辑是"读 staged diff → 按 conventional commit 规范生成一句话"，纯文本生成任务 |
| `/changelog` | prompt template | 低频，"读 git log → 按 Keep a Changelog 格式总结"，同上 |
| `/readme` | prompt template | 同上 |
| `/status` | prompt template（或几行 bash 脚本） | 在新设计里等价于"扫 `.pi/work/*/tasks.md` 汇总进度"，对多任务并行场景有用，但同样不需要专属代码 |
| `/resume` | **直接砍掉，不做独立命令** | 本质是"session 开始时看有没有没完成的 feature"，折进 3.7 节 meta 的默认启动行为——AGENTS.md 里写明每次 session 启动自动扫 `.pi/work/`，有未完成的主动提出来，不需要用户记得敲命令 |

3.4 节确认容器化默认之后，guardrail 这个 v1 也不写了——意味着 **v1 大概率不需要写任何 `pi.registerCommand()` / `pi.on()` extension 代码**，全靠 AGENTS.md + skill + prompt template + `.pi/agents/*.md` 这几种纯配置/文本机制就能跑起来。

### 3.9 MCP → 不做协议层，优先复用已有原生 CLI

- 当前 Conductor 依赖的 MCP（context7 查文档、cloudflare、playwright 浏览器自动化）在新系统里不做协议桥接。
- **关键判断**：定位一确认是"纯 dev"，会发现原来靠 MCP 包一层的能力，大多数场景下**本来就有原生 CLI**，根本不需要新写封装，只需要把"怎么用"写成一份 README/skill，让模型用 `bash` 直接调：
  | 原 MCP 能力 | 对应场景 | 替代方式 |
  | --- | --- | --- |
  | cloudflare MCP | 基础设施/云（Cloudflare 类，已确认在范围内） | 直接用 `wrangler` CLI 本身，写一份 skill 说明常用命令（`wrangler deploy`/`wrangler tail`/`wrangler d1` 等）；危险命令记在 3.4 节的清单里，但默认不启用拦截 |
  | playwright MCP | 前端/Web e2e 测试（已确认在范围内） | 直接用 `playwright test` / `@playwright/test` 原生 CLI，不用再封装成"browser nav/click"这种交互式浏览器操作；e2e 场景本来就该写成测试用例跑，而不是让模型手动操作浏览器 |
  | context7 MCP（查库文档） | 通用，跨技术栈都会用到 | 唯一没有对应"原生 CLI"的能力，v1 不解决，需要时再评估：可以是一个简单的"查本地 node_modules/README 或已缓存文档"脚本，不追求覆盖 context7 的全部实时性 |
- 因此 P4（第 5 节表格）的实际工作量比最初设想的小：多数情况是"写 skill 文档说明现成 CLI 怎么用"，只有 context7 这类真的没有 CLI 对应物的能力，才需要考虑要不要单独写工具。
- 这块按你确认的决策，v1 不做协议层，需要具体能力时再单独评估。

### 3.10 pi 的 session 存储位置（事实核查，非决策项）

之前这是标了"需要核实"的技术细节，查了 pi 文档确认：

- **Session 文件**存在全局用户目录 `~/.pi/agent/sessions/`，按**启动 pi 时的工作目录**分类组织，不是存在项目目录里。
- 这对"多任务并行/多 worktree"这个已确认场景是好消息：`git worktree add` 本来就会给每个 worktree 一个独立的文件系统路径，pi 按工作目录分类 session 的机制天然让每个 worktree 的会话历史互不干扰，不需要额外配置。
- **信任记录**（`trust.json`）是按**文件夹路径**记录的，不是按 git remote，且支持父目录继承——这个事实支撑了 3.3 节"信任容器工作区根目录一次即可覆盖所有 worktree"的判断。

---

## 4. 新目录结构（草案）

```
<project>/
  .pi/
    agents/            # scout.md, planner.md, reviewer.md（worker 就是主 session，不需要文件）
    skills/            # 从 Conductor skills/ 迁移
    work/              # 原 Synapse 的替代，见 3.6，按 feature-slug 分目录
    tools/             # 自建 CLI（替代 MCP 能力，仅 context7 类无原生 CLI 对应物时才需要），每个工具配一份 README
    prompts/
      commit.md        # /commit
      changelog.md      # /changelog
      readme.md          # /readme
      status.md           # /status
    extensions/          # v1 默认为空——容器化前提下不需要 guardrail，见 3.4；非容器场景需要时再加 guardrail.ts
  AGENTS.md              # 全局行为 + 角色说明（原 AGENTS.md 精简版，含"启动时自动扫 .pi/work/"的默认行为、3.7 的路由判断标准）
  SYSTEM.md / APPEND_SYSTEM.md   # 原 constitution 精简版
```

## 5. 分阶段落地（确认方案后再执行）

| 阶段 | 内容 | 成本 |
| --- | --- | --- |
| P1 | skills 原样迁移、AGENTS.md 改写（启动自动扫 `.pi/work/` 取代 /resume、写入 3.7 路由判断标准）、4 个 prompt template（commit/changelog/readme/status）、`.pi/work/` 文件约定落地 | 低，可跑通最小版本，**v1 不需要写任何 extension 代码** |
| P2 | scout/planner/reviewer 三个 `.pi/agents/*.md` + dispatch 模式映射（Pipeline/Guard/Race） | 中 |
| P3（按需，可能永远不做） | guardrail extension——仅当真的要在非容器/裸机环境跑 Forge 时才需要，见 3.4 的清单草案 | 按需，默认不做 |
| P4（按需） | 多数是"写 skill 文档说明现成 CLI 怎么用"（wrangler/playwright test/cargo/pytest 等），只有 context7 类无原生 CLI 对应物的能力才需要新写工具，哪个用到再补哪个 | 按需，比最初预估的轻 |

---

## 6. 开放项状态

**已解决：**

- ~~新名字~~ ✅ **Forge**。
- ~~guardrail 清单要不要现在敲定~~ ✅ 不敲定——默认容器化运行，v1 不做 guardrail，清单留作裸机场景的草案，见 3.4。
- ~~`.pi/work/` 要不要进 git~~ ✅ 进，见 3.6。
- ~~要不要现在建新仓库~~ ✅ 做成 git 模板仓库，clone 起步，见 0 节 + 3.6。
- ~~pi 的 session 存储位置~~ ✅ 已核实：全局存在 `~/.pi/agent/sessions/`，按工作目录分类，多 worktree 并行天然隔离，见 3.10。
- ~~meta 的路由判断标准~~ ✅ 已从原 `agents/meta.md` 提炼改写，砍掉仪式性机制，见 3.7。
- ~~`.pi/work/<slug>` 命名规则 + 建目录的阈值~~ ✅ 见 3.6。

**还没定：**

1. **每个 agent 角色具体接哪家 provider/model**——按你的决定，不预先定，等实际用的时候再接入，不是阻塞项。

---

## 7. 落地后基于真实机制的适配

读了 `.pi/extensions/subagent/index.ts` 源码之后（不是文档摘要，是实际代码），发现 `subagent` 工具的真实机制比最初设计假设的更具体，也更有用，值得基于此调整设计，而不是死守最初的静态方案：

### 7.1 dispatch 的真实成本模型

不是"角色扮演"，是**每次调用都会真的 spawn 一个独立 `pi` 子进程**——全新上下文、全新 token 消耗、全新耗时。这印证了 3.3/3.7 里"默认不拆"的判断是对的，而且给了更具体的理由：dispatch 贵在真金白银的进程开销和模型调用，不只是"哲学上更啰嗦"。`AGENTS.md` 里现在把这个具体讲清楚了，而不是停留在"避免黑箱"这种抽象表述。

### 7.2 chain 的 `{previous}` 是纯文本替换，不是上下文共享

之前设计文档没细说这点，容易让人以为 chain 里下一步能拿到上一步的完整上下文。实际是：`step.task.replace(/\{previous\}/g, previousOutput)`，就是字符串替换。已经在 `AGENTS.md` 里加了规则：chain 里传指针/指令，不要传大段粘贴内容，被 dispatch 的 agent 自己有 `read`/`grep`/`bash`，该重新查的自己查，比传大段文本更准（不会过时）也更省 token。

同时确认了 chain **第一步失败就整体停**（源码里 `Chain stopped at step N`），没有部分继续，已经写进 `AGENTS.md`。

### 7.3 每个 task 都能带 `cwd` —— Race 模式的关键，之前设计没用到这个能力

这是最大的一处补强。`subagent` 工具的 single/parallel/chain 三种模式的每个 task 都接受一个 `cwd` 参数（独立工作目录），之前的设计完全没提这个字段，导致 Race 模式（比较多个实现方案）设计上是空的——3.7 节原来只写了"parallel dispatch 多个方案，主 session 比较后选择"，但没说清楚：如果要 dispatch 出去真的写代码比较两个实现，两个并行进程写同一个工作目录会互相打架。

修复方式：

- 新增第 4 个 agent profile——**`builder`**（`.pi/agents/builder.md`）：唯一一个有完整读写权限的可 dispatch 角色，但**只在 Race 模式下用**，日常单路径实现仍然是主 session 直接做，不走这个角色。
- Race 的具体机制：每个变体先 `git worktree add` 出一个独立目录和 `race/<slug>-<variant>` 分支，parallel dispatch `builder` 到各自的 `cwd`，比较结果后合并赢家、`git worktree remove` 清理。
- 这个设计和 3.6 节"多任务并行/多 worktree"的场景假设是同一个机制的自然延伸——不是新发明一套隔离方案，是把已经决定要用的 `git worktree` 用在了刀刃上。
- `.pi/skills/git/SKILL.md` 的分支表加了一行 `race/*`（可 commit/merge，不 push，用完即删）。

角色数量因此是 **8 → 4**（scout / planner / reviewer / builder），不是原来写的"8 → 3"——builder 是后来因为摸清真实机制才补上的，不是最初就想到的。

### 7.4 Parallel 的硬上限

`MAX_PARALLEL_TASKS = 8`，`MAX_CONCURRENCY = 4`——如果某个任务真的需要超过 8 个独立方向，需要分批调用，不能指望一次塞完。已写进 `AGENTS.md`。

---

## 8. Dogfooding 回路：用真实 session log 驱动改进

跑了第一个真实 pi 会话之后确认：与其建一套反馈流水线，不如复用已经在用的机制——`.pi/prompts/`。新增 `.pi/prompts/retro.md`：输入一份 `/export` 出来的 session JSONL，扫描里面的摩擦点（失败的工具调用、模型自己回退推翻的判断、重复犯的同一个错），对每一条追根到具体证据（原始 tool_use 参数、tool_result 文本），分成四类——Forge 真 bug / 文档缺口 / 一次性模型失误 / pi 本身的坑——只对前两类出修改清单，其余记录不改。这本身也是"只做有价值的事"的延伸：不新建工具或存储机制，用已有的 prompt template 约定把这件事变成可重复的操作，而不是一次性人工排查。

第一次真实运行就产出了一个例子：3 个并行 scout 全部失败，报 `Unknown agent: "scout". Available agents: none.`。排查过程本身（见该次 session log）反转了两次结论——一度怀疑是 `ctx.cwd` 问题，最后查到原始调用参数才发现是模型把 `agentScope`/`confirmProjectAgents` 错误嵌进了每个 task 对象里，而不是放在顶层；`TaskItem` schema 只认 `agent`/`task`/`cwd`，多余字段被静默丢弃，`agentScope` 回落默认值 `"user"`，而项目 agents 只在 `.pi/agents/`（project scope）下，于是查不到任何 agent。**结论：不是 Forge 的代码或设计问题**——vendored 扩展与官方 example 逐字节一致，参数放对位置后立刻成功。属于"文档缺口"一类：`AGENTS.md` 之前只给了正确写法的例子，没有明确警告"这两个参数不能放进 task 里"，导致同一个错误足以让人踩一次坑。已在 `AGENTS.md` 的"How to actually dispatch"里加了显式的错误/正确对照，直接引用这次的证据链，防止同一坑被踩第二次。

会话导出文件本身（大、含完整 thinking、纯个人排错记录）不进 git——`.gitignore` 加了 `*.jsonl`；`retro.md` 只要求一个本地路径，用完可以随手清理。

### 第一次全链路 `/smoke-test`：GitHub Codespace 里真实跑通

在真实 Codespace 容器（`/.dockerenv` + `CODESPACES=true`，不是本地 macOS）里跑了 `.pi/prompts/smoke-test.md` 的完整 16 步，结果 **15 pass / 1 partial**——覆盖了容器确认、启动扫描、纯问答路由、单会话小任务（技能自动加载）、git 分支门禁、并行 scout dispatch、chain dispatch、Guard 门禁、完整 spec-driven 生命周期、**Race 模式全链路**（首次真实跑通）、四个 prompt template。跑完导出 `test.jsonl`，按 `retro.md` 的方法过了一遍，只对"文档缺口"类出了修改，其余（如 reviewer 没执行逐字引用指令这种一次性模型失误）按 `retro.md` 的分类原则记录不改：

1. **Chain 结果只暴露最后一步的输出**（Step 9 partial 的根因）——调用方拿不到中间步骤 `{previous}` 被替换成的具体文本，只能看到链条最后一个 agent 的回复。`AGENTS.md`"Mechanics worth knowing"补了一条：需要核实某个中间步骤的确切输出时，用 `single` 单独 dispatch 那一步，别指望从 chain 结果里看到。
2. **Race 清理步骤和真实情况有出入**（Step 12，"pass with deviations"）——`builder` 跑测试会留下未追踪的构建产物（这次是 `__pycache__/`），导致 `git worktree remove` 直接拒绝；根因是仓库 `.gitignore` 本来就没盖 `__pycache__/`（已在 `.gitignore` 补上 `__pycache__/`/`*.pyc`/`.pytest_cache/`，这是永久性修复，不只是这次测试的临时绕过）。另外 `git worktree remove` 一次只认一个路径，输家分支是没合并的，删除要用 `-D` 不是 `-d`——原来 `AGENTS.md` 第 4 步写得含糊（"remove the others"容易让人以为能批量/一步到位），已改成显式的逐个操作说明。
3. **`/changelog` 对 `.pi/work/` 文档提交的分类没写清楚**——`docs` 类型默认归到 Changed，但 `.pi/work/<slug>/` 下的 spec/plan/tasks/build-log/validation 提交是某个 feature 自己的过程记录，不该在 changelog 里单独出现（已经有对应的 `feat`/`fix` 条目覆盖用户可见的部分了）。`changelog.md` 加了这条例外。
4. **`smoke-test.md` 自己的一个要求本身不可能被满足**——Phase 0 要求"确认 pi 启动 banner 的 `[Agents]` 分区"，但同一个 session 看不到自己启动时的 banner；已把这一步改成用"dispatch 成功"本身当证据，不再要求一个结构性看不到的东西。

这轮验证也确认了几件更重要的事：容器边界假设成立（真实检测到 `/.dockerenv`）、`agentScope`/`confirmProjectAgents` 的文档加固在真实环境里生效（Step 8 三个并行 scout 一次成功，没再复现上一轮的坑）、Guard 门禁真的会拦下东西（reviewer 抓到一个 NaN/inf 边界问题）、Race 模式端到端可用（两个 `builder` 各自 worktree 并行实现、真实 diff 比较、合并赢家、清理）。

---

## 9. Extension 生态调研 + 批量引入（功能/体验类，非护栏）

跑了几轮真实 session 之后做了一次针对 pi 官方 extension 生态（`earendil-works/pi` 的 `examples/extensions/`，以及独立仓库 `pi-review`/`pi-review-loop`）的系统调研，目的是"功能拓展 + 细节打磨"，不是补护栏——你的实际使用场景主要是 GitHub Codespaces，容器隔离已经有了，§3.4 的 sandbox extension 之类不需要。

### 9.1 两种安装机制，结论决定了怎么落地

调研过程中确认了 pi 有两条独立的"装东西"路径，行为差别很大，值得记下来避免以后重问：

| 方式 | 落盘位置 | Clone 后要不要额外操作 |
| --- | --- | --- |
| **vendor 源码**（像 `subagent` 一样，`.ts` 直接抄进 `.pi/extensions/` 并 commit） | 就在仓库里 | 不需要，pi 启动自动 discovery（`.pi/extensions/*.ts` / `*/index.ts`），只需过一次性的项目信任确认（`trust.json`，按文件夹路径记，父目录可继承） |
| **`pi install`** | 默认写 `~/.pi/agent/settings.json`（用户级，不进仓库）；带 `-l` 才写 `.pi/settings.json`（项目级，可进仓库），实际包代码缓存在 `.pi/npm/`/`.pi/git/<host>/<path>`（不进仓库，类似 `node_modules`） | 用 `-l` 的话，pi 官方文档原话："pi installs any missing packages automatically on startup after the project is trusted"——teammate clone 后过一次信任确认，pi 自动补装，不需要手动重新 `pi install` |

**这批（P2.5）全部用 vendor 方式**，因为都是官方 `examples/extensions/` 里的独立小文件、没有外部依赖，vendor 最简单、clone 即用、零网络依赖。`pi-review` / `pi-review-loop` 是维护在独立仓库的完整包，**调研过了但这轮先不落地**——真要装的话应该用 `pi install -l git:github.com/earendil-works/pi-review`（`.gitignore` 要记得补 `.pi/npm/`、`.pi/git/` 两行），不要手动 vendor 会跟不上上游更新。记这笔是为了不让以后的自己重新做一遍同样的调研。

### 9.2 引入的六个 extension

跟 `subagent` 一样，全部原样搬自 `earendil-works/pi` 的 `examples/extensions/`，只有两处必要的偏离（都记在对应文件的头部注释里，不只是这里）：

| Extension | 加的能力 | 为什么选它 |
| --- | --- | --- |
| `plan-mode/` | `/plan`（或 `--plan`、Ctrl+Alt+P）——只读探查：写工具关掉，bash 限制成只读白名单，agent 先出一份编号 `Plan:` 再动手；`[DONE:n]` 标记执行进度，`/todos` 查看 | 补的是 `AGENTS.md` 路由表里"一次坐下的多阶段任务，不需要跨会话恢复"这一档——之前只能靠对话里裸写 TODO，现在有了执行期防误写 + 进度可视化，比升档 `.pi/work/` 轻。**偏离**：upstream 的系统提示里有一行"Use brave-search skill via bash for web research"，Forge 没有这个 skill，已删掉这行，见 `plan-mode/index.ts` 头部注释。 |
| `custom-footer.ts` | `/footer` 切换状态栏：token 用量/花费 + session name + git branch + 当前 model | Race 模式重度依赖多 worktree 并行，branch 信息默认看不到。**偏离**：upstream 默认关闭、要手动 `/footer` 开；改成 `session_start` 时默认开。追加打磨（cost 超阈值变色、session name 段）见 §9.4。 |
| `session-name.ts` | `/session-name [name]` 给 session 命名，session selector 里显示这个名字而不是第一条消息 | 配合 `.pi/work/<feature-slug>` 命名约定，多任务并行时一眼认出哪个 session 对应哪个 feature。未改动。 |
| `notify.ts` | agent 跑完（`agent_end`）自动发终端通知 + ntfy 推送，探测终端类型选协议（OSC 777 / OSC 99 Kitty / Windows Toast） | 长 dispatch（parallel/chain）跑的时候人常常切到别的窗口，跑完了要通知；服务器/无人盯着的场景靠 ntfy。追加打磨见 §9.4。 |
| `handoff.ts` | `/handoff <goal>` 把当前会话的关键决策/进度提炼成一段自包含 prompt，开新 session 继续，而不是简单 compact 丢信息 | 长会话（比如跑完一次 `/smoke-test` 或 `/retro`）后要接着做具体修复时，比手动重新交代上下文省事。未改动。 |
| `trigger-compact.ts` | 超 100k token 自动 compact；`/trigger-compact [instructions]` 手动触发 | §7.1 已经确认 dispatch 贵在真实进程/模型开销，chain/parallel 场景 context 涨得快，这个减少手动 `/compact` 的次数。未改动。 |

`todo.ts`（另一个官方示例，纯任务清单 `/todos`）调研过但没装——跟 `plan-mode` 功能重叠（`plan-mode` 也注册了 `/todos`，且多了执行期防误写和进度条），二选一选了更完整的那个。

### 9.3 遗留的收尾项

如果以后真要装 `pi-review` / `pi-review-loop`，别忘了：
1. `pi install -l git:github.com/earendil-works/pi-review`（`-l` 不能漏，漏了就只装到 `~/.pi/agent/settings.json`，teammate clone 不会自动带上）
2. `.gitignore` 补 `.pi/npm/` 和 `.pi/git/` 两行，防止把下载缓存误提交

### 9.4 落地后追加打磨：ntfy 推送 + footer 视觉细节

批量引入之后又做了一轮"使用体验"打磨，动机是你的实际场景——pi 经常在服务器/Codespaces 上跑，人不一定盯着终端：

- **`notify.ts` 加了 ntfy.sh 推送通道**（`notifyNtfy`），跟原有的终端协议（OSC 777/99/Windows Toast）并存，不是替换。原因很直接：OSC 系列通知只有终端真的开着、attach 着的时候才看得到，detached tmux、关了盖子的笔记本、没人看的 Codespace 标签页都收不到。ntfy 是 HTTP POST 到一个 topic 就完事的推送服务，不需要 SMTP 账号/API key 这类要管理的凭证，配一个环境变量 `PI_NTFY_TOPIC` 就好，手机装 ntfy app 订阅同名 topic 即收。默认不开（没设 `PI_NTFY_TOPIC` 就整个函数直接 return，不发请求），改的人自己决定要不要用。`PI_NTFY_SERVER` 可以指向自建实例，不强制用公共 `ntfy.sh`（topic 在公共服务器上是无认证的，谁知道 topic 名字谁就能读，这个安全边界已经写进代码注释）。
  - 邮件通知调研过但没做：比 ntfy 多一层 SMTP/邮件 API 凭证管理，这类凭证不适合放进一个"读环境变量就完事"的轻量 extension，真要做建议走一个中间层（比如一个专门转发到邮件的 webhook），不在这轮范围内。
  - 顺带把通知内容从写死的 "Ready for input" 改成 agent 最后一条消息的预览（截断到 160 字符），标题带上当前工作目录名——服务器上可能同时跑好几个 pi 实例，锁屏通知上要能分清是哪个。
- **`custom-footer.ts` 加了三处视觉细节**：
  1. Cost 数字超过 `COST_WARN_THRESHOLD`（$1）就变成 warning 色——不是硬限制，是个视觉提醒，呼应 §7.1 已经确认的事实（dispatch 花的是真金白银，chain/parallel 每一步都在 spawn 真实的 pi 子进程）。
  2. Footer 里加了 session name 这一段（`pi.getSessionName()` 读 `session-name.ts` 设的名字），跟 branch、model 用统一的分隔符（`  ·  `）连接，视觉上比原来"tokens + 括号里塞 branch"的写法更有层次。
  3. **加了 context window 用量的方块进度条**（`renderContextBar`，10 个字符，`█`/`░`）。这不是凭空加的视觉效果——读了 pi 自己的内置 footer 源码（`packages/coding-agent/src/modes/interactive/components/footer.ts`）才发现它本来就在算 `ctx.getContextUsage()` 并在 70%/90% 阈值上变色（`warning`/`error`），只是没有条形可视化。条形是这轮唯一真正"装饰性"的加法，克制在单色 + 复用同样的两个阈值，没有动画、没有渐变色——Claude Code 自己的状态栏对 context 占用也是同一个理由给可视化：这个百分比直接预测 `trigger-compact` 什么时候会触发，眼睛扫一眼比从原始 token 数心算更快。
     阈值和数据源直接复用 pi 内置 footer 的实现，不是自己拍的新数字——避免"这个 extension 的 context% 和 pi 原生显示的 context% 对不上"这种以后要重新排查的坑。

两个文件的改动都记在各自文件头部的注释里（"Deviations from upstream"），不只是这里——这是延续 `plan-mode`/`subagent` 已经在用的记录习惯：以后升级到 upstream 新版本时，diff 一下头部注释列的点就知道哪些地方是故意偏离的，不用重新猜一遍。

### 9.5 tmux 场景加固

你提到实际用法是"服务器上跑，tmux 里开着，人不一定在看"——这是 §9.4 加 ntfy 时已经预见但没细做的一个子场景。查了 tmux 自己怎么处理 OSC 转义序列之后，发现原来的 `notifyTerminal`（OSC 777/99）在 tmux 里有个真实的坑，不是猜的：

- **tmux 默认不转发 OSC 序列。** `allow-passthrough` 这个选项从 tmux 3.3 才有，且**默认关**。关的时候，tmux 要么直接吞掉不认识的 OSC（安静但没用），要么在旧版本上把裸转义字节当普通文本漏到 pane 里，屏幕上会看到一坨 `]777;notify;...` 之类的乱码——这是一个有据可查的老问题，不是 Forge 独有。
- 所以 `notify.ts` 现在先用 `tmux show-options -gv allow-passthrough` 探测这个开关真实状态，**开了才信任 OSC 能穿透到外层终端**（比如 SSH 到服务器、外层用 iTerm2/kitty，passthrough 打开后 OSC 777 真的能弹出本机桌面通知）；没开就完全跳过 OSC，改用两个 tmux 原生、不需要客户端终端支持任何协议的信道：
  1. **BEL 字符**（`\x07`）——tmux 的 `monitor-bell`（默认开）会在状态栏给发出 bell 的那个 window 打标，哪怕你在另一个 window 也看得到该去哪找。
  2. **`tmux display-message`**——在状态栏弹一条临时消息，不需要切 window 就能看到内容预览。

推荐往 `~/.tmux.conf` 加这几行（不是 Forge 强制的，是让上面这套机制发挥最大效果）：

```tmux
set -g monitor-bell on        # tmux 默认就是 on，写出来只是显式化
set -g allow-passthrough on   # 想要 OSC 777 真的弹桌面通知穿透 tmux，才需要开这个
```

三层通知现在分工很清楚，覆盖"人在哪"的三种情况：
1. **ntfy**（§9.4）——人不在电脑前，靠手机推送，跟终端/tmux 完全无关。
2. **OSC passthrough**（这轮加固）——人在电脑前，tmux 配了 `allow-passthrough`，能拿到真正的桌面通知。
3. **tmux bell + display-message**（这轮新增）——人在电脑前但在另一个 tmux window，没配 passthrough 也有兜底，零客户端配置要求。

### 9.6 footer 改回纯文字：先列字段清单，再让你选

§9.4 给 footer 加了方块进度条（`renderContextBar`），你反馈"不想搞得花里胡哨，以文字为主，竖线分割，颜色为辅"——这条反馈直接推翻了 §9.4 那处改动，记下来是为了不让以后的自己重复踩"加装饰性效果"这个已经被否决的方向。

做法上没有直接改，而是先把 pi 能拿到的字段（累计 token、cache 读写/命中率、cost、context 占用+上限、pwd、branch、session name、model id、provider、thinking level、其它 extension 状态行）列成清单给你选，你确认要哪些之后才写代码——这是"先出选项再实现"，不是"先实现再等反馈改"，对这种纯偏好性的 UI 决定成本更低。

选定的字段和取舍：

| 字段 | 要/不要 | 备注 |
| --- | --- | --- |
| 累计 token（↑/↓） | 要 | 原有 |
| cache 命中率 | 要 | 只要 CH%，不要 R/W 原始读写数——判断依据是"命中率是决策信号，原始读写数是实现细节" |
| cost | 要 | 原有，阈值变色不变 |
| context 占用 + 上限 | 要 | 格式 `{percent}%/{window}`，跟 pi 内置 footer 一致，不是原始 token 数 |
| 自动压缩标记 | 要 | `(auto)`，见下面的诚实声明 |
| pwd / branch / session name | 要，有则显示无则不显示 | 挪到独立的第一行（identity），跟第二行（stats）分开 |
| model id | 要 | 原有 |
| thinking level | 要 | 只在模型支持 reasoning 时显示 |
| provider 名 | 不要 | 单 provider 场景是废信息，没问就不主动加 |
| 其它 extension 状态行（如 plan-mode 进度） | 暂不处理 | 提了一句风险——custom-footer 接管了 `ctx.ui.setFooter()`，pi 原生 footer 用来显示这行的机制可能被吞掉，还没验证，先不处理，等实际用到 `/plan` 时再看 |

布局上从 upstream 的单行改成两行：第一行 identity（cwd/branch/session name），第二行 stats（token/cache/cost/context/model/thinking）。理由：字段选下来一行装不下，与其靠 `truncateToWidth` 硬截断成谁也看不全的样子，不如学 pi 自己内置 footer 本来就是两行的做法——这是这几轮里第三次遇到"pi 自己已经这么做了，抄它的比自己发明的更可靠"的情况（context 阈值、chain/parallel 的 subagent 机制、这次的两行布局），值得记下来当一条经验：改 UI 细节前先看 pi 自己的内置实现怎么处理同一个问题。

**一处诚实声明**：`(auto)` 这个标记目前是**恒定显示**的，不是真的在读一个开关状态。pi 内置 footer 的同名字段读的是 pi 核心自己的 auto-compact 开关（`autoCompactEnabled`，由 interactive-mode 内部设置，extension 拿不到）；咱们这个 `(auto)` 实际读的是"`trigger-compact.ts` 这个 vendored extension 有没有装"——因为它目前没有开关，只要装了就是恒定生效，所以标记恒定显示。不是假信息（确实反映了"这个机制被接上了"），但也不是一个真正会变化的状态位。以后如果给 `trigger-compact.ts` 加开关命令，这个标记才会开始真正有信息量，先如实记下这个局限，不装作它已经是动态的。

### 9.7 竖线只标"大栏目"边界，不是逐字段分隔——参照 Claude Code 官方 statusline 约定重新分组

§9.6 定完字段清单之后的下一轮反馈：竖线用得太密了，逐字段分隔视觉上太碎，应该只在真正不同的"大栏目"之间用，同一栏目内部（比如 token 数、cache 命中率、cost 这几个都属于"用量"）不需要竖线，空格分开就够。同时要求把 identity（路径/分支）固定在上面一行，把 model 相关信息（model id、thinking level）挪到下面一行的右侧。

动手之前按你说的去查了 Claude Code 自己的 statusline 文档和示例（`code.claude.com/docs/en/statusline`）——这是"参照官方 API 怎么做"的具体依据，不是凭感觉调整：

- 官方单行示例：`[$MODEL] 📁 ${DIR##*/} | ${PCT}% context`——model+目录是一组，context 百分比是另一组，中间正好一根竖线。跟"竖线只标大栏目边界"的判断吻合。
- 官方多行示例（`statusline-multiline.png`）：第一行 `[MODEL] 📁 dir | 🌿 branch`，第二行 `BAR pct% | $cost | ⏱ duration`——第二行内部其实每个字段都用了竖线，跟你这轮"用量字段之间不要竖线"的要求不完全一样。这里明确按你的原话来，不照抄官方第二行的分隔密度——官方文档提供的是"两行布局 + 竖线做大栏目边界"这个大结构的验证，不是要逐字段照搬。

落地成这样：

```
~/workspace/forge on feature-x payment-retry
↑12.3k ↓4.1k CH67.3% $0.842 71%/200k (auto)  |  claude-sonnet-5 thinking: medium
```

- 第一行：identity，cwd + branch + session name，空格分隔，没有竖线。
- 第二行：**只有一根竖线**，隔开两个大栏目——左边"用量"（token/cache/cost/context，内部空格分隔），右边"model"（model id/thinking level，内部空格分隔）。

`bucketSep` 这个变量名和注释里直接写死了"只用在两个 bucket 之间，bucket 内部不用"，就是为了不让以后改动时把竖线加回字段之间——这条规则从这轮反馈来看已经反复被推翻过一次（§9.6 先是逐字段加竖线，这轮再改成只在大栏目边界加），值得在代码里而不只是文档里把约束钉死。

---

### 9.8 照着截图对样式：改回单行，颜色分类

你放了一张截图在仓库根目录（`Snipaste_2026-08-12_20-30-25.png`，另一个工具的 statusline），要求"这种风格，但字段按刚才说的来"。截图里的样式：单行，左边路径+分支（分支加粗、颜色突出），右边整块靠右对齐，model 名 + context 用量（绿色）+ 竖线 + cost（橙色）+ 竖线 + 用时/时钟。

这跟 §9.6/§9.7 刚定下的两行布局是矛盾的，直接照单收下会跟之前口头定的"token/cost/cache 之间不要竖线"打架（截图里 cost 前面明明有一根竖线）。处理方式是拆开看：**截图给的是排版和配色的参照，不是逐字段的竖线规范**——§9.7 已经用官方文档验证过"竖线只标大栏目边界"这条规则，这次继续按这条规则来，只是把"两行"改回"一行"，把"边界"从"line1 vs line2"改成"左 vs 右"。

落地结果（右侧两个栏目的顺序按下一轮反馈调整过——先用量后 model，不是先 model 后用量，见下方"顺序"一条）：

```
~/workspace/forge on main payment-retry                    ↑12.3k ↓4.1k CH67.3% $0.842 107k/1.0M (11%)  |  claude-sonnet-5 thinking: medium
```

- 左：cwd + branch（加粗 + accent 色，截图里最显眼的就是这个）+ session name，空格分隔。
- 右：用量栏目（token/cache/cost/context）**一根竖线** model 栏目（model id、thinking level），栏目内部空格分隔。
- 两侧用空格 pad 撑到终端宽度，不是竖线——这也是截图本来的样子，也是 upstream 单行版本原来的做法。

三处主动没有照抄截图的地方，都在代码头部注释里写了，这里再解释一遍原因：

1. **context 格式改成 `tokens/window (percent%)`**（例：`107k/1.0M (11%)`），不是之前的 `percent%/window`——这个改了，是真的抄截图，因为这个格式确实比纯百分比更贴"目前的上下文和模型的上限"这句原始需求，属于截图纠正了之前的猜测。
2. **cost 没有跟着截图变成恒定橙色**——截图里 cost 看起来是恒定色，不随金额变化；但之前定的"$1 以上才变 warning 色"是有信息量的设计（呼应 §7.1"dispatch 花真钱"），恒定色只是好看，没有信息量。保留阈值变色，只在低于阈值时用 dim。这条不确定完全猜对你的意图，如果你其实想要恒定色，说一声就改。
3. **去掉了 `(auto)` 标记**——§9.6 就已经承认这个标记是恒定显示、没有真实开关状态支撑；这次单行本来空间就更紧，与其继续显示一个没有信息量的静态徽章，不如先去掉，等 `trigger-compact.ts` 真的有开关命令了再加回来。

context 默认色（低于 70% 阈值时）从"dim"改成了"success"（绿色）——这个改动截图也确实是绿色，但独立于截图也站得住：低于阈值 = 健康状态，用绿色比 dim 更符合"红黄绿"三色阶梯的直觉，warning/error 两档已经在用了，success 补上低位阶正好凑齐三阶。

**顺序**：上面截图初版实现是"model 栏目 | 用量栏目"，跟着截图里 model 名在最前的顺序走的。下一轮反馈明确要倒过来——"token 相关的信息放在前面，model 的信息放在后面"，已经改成"用量栏目 | model 栏目"。这条直接照最新的原话来，不再猜。

### 9.9 去掉 thinking level，model 栏目末尾加时长 + 时钟

反馈："think 信息不需要显示了，最后显示一个时间啥的"——两个改动：model 栏目里的 `thinking: <level>` 删掉；末尾加时间。截图（§9.8）原本就有这个位置（`1h19m 12:30`），之前落地时没跟进这部分，这轮补上。

- **时长**：从这个 footer 组件被创建的时刻算起（`sessionStartedAt = Date.now()`，格式 `1h19m` / `23m` / `45s`，按最大单位裁）。**如实声明一个局限**：pi 没有给 extension 暴露"session 真实创建时间"这个字段，所以这个时长在**断线重连/resume 一个老 session** 的场景下，算的是"这个 footer 组件这次开始渲染以来过了多久"，不是这个 session 从第一次创建到现在的真实年龄。日常"这轮对话开了多久"的场景够用，跨会话续接的场景下数字会看着偏小，先如实记这个限制。
- **时钟**：`HH:MM`，24 小时制，本地时区。
- **保活**：之前 footer 只在 `footerData.onBranchChange()` 触发时重新渲染（换分支才更新），时钟/时长这种随时间自然变化的字段光靠这个会经常显得"卡住不动"（人不操作、不换分支的时候，界面会一直显示旧数字）。加了一个 30 秒的 `setInterval` 主动触发重渲染，并且在 `dispose()`（原来只清理 `onBranchChange` 的订阅）里一并 `clearInterval`，不留定时器泄漏。

### 9.10 推翻重来：仪表盘思路，只留两个真正会看的东西

反馈："感觉还是不太行……整体的 footer 只保留最核心最关键的信息，就像车的仪表板一样"，并点名 model 信息（"没啥用"）和 cost 信息都要去掉。

这不是又一次"删一两个字段"的小调整——是对 §9.4 到 §9.9 整个方向的推翻。回头看，这几轮的问题是每次反馈都是"这个不对"→改一处→下一轮又"这个也不对"，一直在同一个"信息越全越好，只是排版/配色需要调"的框架里打转，没有人问过"这些信息里到底哪些是真正会看的"。这轮反馈提供的是一个新框架，不是新参数：**仪表盘只放开车时真正会瞟一眼的东西（时速、油量），不是行车电脑那种十几个数字的详情页**。

对照下来，之前攒的字段里，只有一个是"仪表盘"级别的：**context window 占用**——这是唯一一个真正 actionable 的数字，它直接预示什么时候会触发 compact，跟"油量表快见底了该找加油站"是同一种信息。其余全部砍掉：

| 字段 | 处理 | 为什么够格/不够格 |
| --- | --- | --- |
| context 占用（tokens/window + percent，颜色三阶） | **留** | 唯一 actionable 的数字，预示 compact 触发时机 |
| cwd + branch + session name | **留** | "我在哪"，仪表盘上等价于挡位/导航，不是可选信息 |
| model id | 砍 | 反馈原话"没啥用"——切换频率低，真要查有 `/model` 命令，不需要常驻 |
| cost | 砍 | 反馈明确要求去掉；花费重要，但不是"开车时"要看的，更像行车电脑里的油耗统计 |
| 累计 token（↑/↓）、cache 命中率 | 砍 | 诊断信息，不是决策信息——用不着知道具体数字，只需要知道"快满了没有"（这就是保留的 context 占用在做的事） |
| session 时长 + 时钟 | 砍 | §9.9 刚加的，这轮直接一起砍——车上确实有钟，但这轮反馈的重点是"整体只留核心"，不是"留下已经加的东西"，宁可先砍到最小，需要再加回来 |

代码也跟着大幅精简：`COST_WARN_THRESHOLD`、`formatDuration`/`formatClock`、`sessionStartedAt`、`CLOCK_REFRESH_MS`/`setInterval`、cache 命中率的遍历统计——全部删掉，`render()` 从统计一整个 session 的累计用量，变成只读一次 `ctx.getContextUsage()`。文件行数从 ~210 行降到 ~110 行。

落地结果：

```
~/workspace/forge on main payment-retry                                    107k/1.0M (11%)
```

右边只有一个数字，不再需要"栏目"和竖线规则——§9.7 定的"竖线只标大栏目边界"这条规则现在没有用武之地了（只剩一个栏目），不是被推翻，是这次的场景用不上，以后如果核心信息又长回两类以上，这条规则还在，直接复用。

---

### 9.11 自主审计：两处"看起来对、实际不生效"的静默失效

跑了一轮不针对任何具体需求的全面自审（"寻找不足、打磨、熵减"），方法是对着**实际安装的 `pi` 二进制**（`/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent@0.84.1`）核对 `AGENTS.md`/`.pi/agents/*.md` 里写的工具名和机制假设，而不是只读文档互相对照——这轮抓到的两个问题都是"配置看起来合理，pi 内部把不认识的东西静默丢弃，所以没有任何报错，但也没有任何效果"这一类，属于最难靠读 diff 发现的坑：

1. **`glob` 不是 pi 的工具名，实际叫 `find`**——`scout`/`planner`/`reviewer`/`builder` 四个 agent profile 的 frontmatter 全部写的是 `tools: read, grep, glob, ls[, ...]`。核对 `dist/core/tools/` 目录和 `pi --help` 里 `--tools` 的官方示例（`pi --tools read,grep,find,ls -p "..."`）确认：内置工具就叫 `find`，从来没有 `glob`。`agent-session.js` 里 `setActiveToolsByName` 的原话是"Only tools in the registry can be enabled. Unknown tool names are ignored"——不认识的工具名不报错，直接从有效工具集里消失。后果是四个 dispatch 出去的 agent 里，`glob` 这一项从建立起就没生效过，`scout.md` 第 13 条"prefer grep/glob over reading whole files"这条指令实际上无工具可用；因为 `subagent` 工具只把最终结果文本带回来（§7.2 已经记过这个机制），这种"工具没生效但没报错"的失效模式在正常使用中几乎不可能被注意到。已把四个文件的 `glob` 全部改成 `find`，`scout.md` 的第 13 条也同步改了措辞。
2. **`plan-mode` 的系统提示引用了一个从未 vendor 过的工具**——`.pi/extensions/plan-mode/index.ts`（原样 vendored，未改动这部分）的 `PLAN_MODE_TOOLS` 里有 `"questionnaire"`，`before_agent_start` 的提示文本也明确写"Ask clarifying questions using the questionnaire tool"。但 §9.2 当初引入的六个 extension 里没有 `questionnaire.ts`——upstream 的 `plan-mode` 本来就假设它作为姊妹 extension 一起装（`examples/extensions/questionnaire.ts`，独立文件，无额外依赖），这轮之前一直没人注意到这个隐含依赖没被满足。效果和上一条同源：`questionnaire` 从有效工具集里静默消失，plan mode 自己的提示词指向一个不存在的工具。处理方式与 §9.1 定的 vendor 规则一致——原样搬进 `.pi/extensions/questionnaire.ts`，头部注释按 Forge 的记录习惯写明"为什么现在才补、修的是哪个依赖"。至此 vendored extension 数量是 subagent + 7（原六个 + questionnaire），不是 6。

两处都不属于"设计判断"，是纯粹的核对疏漏——记在这里是因为它们的失效模式（静默丢弃而非报错）值得当一条通用经验：以后新增/修改任何 `tools:` frontmatter 或任何依赖 pi 内置工具名的地方，核对对象应该是实际二进制的工具注册表或 `--help` 输出，不能只凭记忆或凭别的 extension 里出现过的名字类推。

---

### 9.12 逛了一圈 pi.dev/packages 之后：只吸收判断标准，不是照单全收

起因是你看到 `pi.dev/packages` 上一堆社区包（MCP adapter、web-access、结构化问卷等），问要不要引进来。查了实际页面内容（60 个包，绝大多数是个人发布的第三方 npm 包，跟目前 vendor 进来的七个官方 `examples/extensions/` 完全不是一个信任等级）之后的结论：

- **MCP adapter**——不引入。§3.9 已经用具体论点（每会话常驻 token 注入、多数场景原生 CLI 就够）拒绝过 MCP，市面上出现一个 adapter 不改变这个 trade-off，除非有个具体工具真的没有 CLI/API 可以直接 `bash` 调用。
- **web-access（搜索+抓取+clone+PDF+YouTube 打包）**——不引入。YAGNI：这五件事目前没有一件是被验证过的真实缺口；真要用，最小代价是照 §3.9 已经定的模式写一份 skill 文档说明 `curl`/`gh` 怎么用，不是装一整个 extension。
- **第三方结构化问卷（`@juicesharp/rpiv-ask-user-question`）**——不引入，§9.11 刚补的 `questionnaire.ts` 就是同一件事，来源还更可信（pi 官方 example，不是个人 npm 包）。

你的反馈把判断标准往前推了一步：不是"官方来源就一定用，第三方来源就一定不用"，而是——**官方 vendor 优先，因为省 review 成本；没有合适的官方对应物、但确实有真实缺口时，参考思路自己写，不引入外部代码**；无论哪种，都要有具体 ROI，不能为了"看起来该有"而装。按这个标准重新过了一遍官方 `examples/extensions/README.md` 里没 vendor 过的条目，找到三个：

| 名字 | 来源 | 处理 |
|---|---|---|
| `protected-paths.ts` | 官方 vendor，修了两处真缺陷 | 见下 |
| `dirty-repo-guard.ts` | 官方 vendor，原样 | 见下 |
| `doom-loop-guard.ts` | 参考 `pi-anti-doom-loop`（第三方包）的**思路**，从零自己写 | 见下 |

**`protected-paths.ts`**——静默拦截对 `.env`/`.git/`/`node_modules/` 的 `write`/`edit`，不弹窗。之所以不算重新打开 §3.4 拒绝掉的"确认弹窗"口子：它防的不是容器内的破坏性操作（容器本来就兜得住），是**泄露到容器外的东西**——密钥一旦被 commit/push，容器一次性这个属性完全救不了，这是容器边界确认覆盖不到的真实缺口。vendor 时修了两处，都是这轮审计已经验证过的同类问题：
1. upstream 只读 `event.input.path`，但内置 write/edit 工具实际接受 `path` 或 `file_path` 两种字段名（`dist/core/tools/write.js`: `args?.file_path ?? args?.path`）——跟 §9.11 修的 `glob`/`find` 是同一类"假设字段名"的坑，只不过这次是运行时直接 `undefined.includes()` 抛异常，不是静默失效。已改成两个字段名都读。
2. upstream 用 `path.includes(".env")` 子串匹配，会误伤 `some.envfile.txt` 这类无关文件；`.git/`/`node_modules/` 同理。改成按路径 segment 精确匹配（basename 等于 `.env` 或以 `.env.` 开头；任意目录 segment 等于 `.git`/`node_modules`），顺带把 `\` 归一化成 `/`，Windows 路径下行为一致。

**`dirty-repo-guard.ts`**——session 切换/新建/fork 时如果仓库有未提交改动，弹一次确认（非交互模式下直接拦截）。原样 vendor，没改。这个看起来像确认弹窗，但风险类型和 §3.4 拒绝掉的不一样：§3.4 防的是"容器已经兜底的不可逆操作"，这个防的是**脑子里还没落盘的工作被 session 切换/fork 弄丢**——容器还在、仓库还在，丢的是你刚才想清楚但还没 commit 的那部分，容器边界完全不覆盖这层损失。跟"多 worktree 并行"这个核心场景直接相关，值得这一次交互成本。

**`doom-loop-guard.ts`**——`pi.dev/packages` 上 `pi-anti-doom-loop` 的一句话简介是"检测并阻断连续重复的相同 tool call"，官方 examples 里没有对应实现，但这确实是目前零覆盖的一个真实稳定性盲区。没有读那个第三方包的源码，也没有照抄任何外部代码——按 `plan-mode`/`protected-paths` 已经验证过的同一套机制（`pi.on("tool_call")` 返回 `{block: true, reason}`）从零写了一个几十行的最小版本：同一个 tool（名字+参数完全一致）连续出现满 3 次时拦截第 3 次，`session_start` 时清空计数。头部注释如实声明了一个已知简化：按调用形状比较，不看结果，如果 Forge 以后真的需要一个后台轮询类的 extension，这条判断需要重新评估——先写在这，不是等以后踩坑才发现。

这三个的落地方式，正好对应你这轮定的规则：官方来源→vendor 到自己仓库、按需修正真缺陷；没有官方对应物但有真实需求→参考思路自己写、不引入外部代码；任何一种都不是"因为列表里有就装"。

---

### 9.13 全量插件健壮性审计

按你的要求，对 `.pi/extensions/` 下当时的全部 11 个 extension（含刚加的三个）逐个过了一遍代码本身的健壮性，不只是文档一致性。方法：对每个 hook 站在"如果这是被 `subagent` dispatch 出去的非交互子进程（`pi --mode json -p --no-session`），行为还对不对"这个角度重新看一遍——这是 Forge 的核心机制之一，也是最容易被忽略的运行环境。找到两处真问题，都已修复：

**`notify.ts`——非交互模式下会污染 dispatch 的 JSON 流，这不是猜测，是复现出来的。** upstream 的 `agent_end` handler 不看 `ctx.hasUI`，无条件触发终端通知。§9.11 验证 `questionnaire.ts` 时跑的那次真实 `pi --mode json -p` 会话，日志里能直接看到 `]777;notify;Pi · forge;...` 这段 OSC 序列原样嵌进了 JSON 输出流，紧贴着 `{"type":"agent_end",...}` 那一行——`subagent`/index.ts 的 `processLine` 按行 `JSON.parse`，解析失败就 `catch { return; }`，静默丢帧。这次丢的具体是 `agent_end` 事件（`subagent` 本来就不消费这个类型，无感），但同样的写入时机换一次就可能砸中真正要用的 `message_end` 行，静默丢失一个 dispatched agent 的最终输出，调用方只会看到"(no output)"，没有任何报错可查。而且即使不考虑数据损坏，ntfy 通道在非交互模式下也会跟着每个 dispatched 子进程各发一条推送——一次 8 路并行 scout 就是 8 条手机推送，跟"等待输入"这个通知本来的语义完全不符（`-p` 进程处理完就退出，从来没有"等待输入"这个状态）。修法是把整个 `notify()` 调用挂到 `ctx.hasUI` 后面——这也是 `custom-footer.ts`（`session_start`）和 `plan-mode`（自己的 `agent_end`）已经在用的同一个判断，notify.ts 加功能的时候漏掉了。

**`plan-mode/utils.ts`——三个允许列表条目能绕过"只读"保证。** `SAFE_PATTERNS` 里 `find`/`curl`/`sort` 是无条件放行的（`/^\s*find\b/` 等），`DESTRUCTIVE_PATTERNS` 只有一条通用的 `>` 重定向检测，抓不住这三个工具"不经过 shell 重定向符也能写文件"的旗标：`find ... -delete`/`-exec .. \;`/`-fprintf FILE`（直接删除/执行/写文件）、`curl -o`/`-O`/`--output`（把远程内容写到本地文件）、`sort -o FILE`（原地覆写）。这些命令字符串里根本没有 `>` 字符，现有规则形同虚设。补了三条 `DESTRUCTIVE_PATTERNS`，用 bun 实际跑了 8 个用例验证（`find -delete`/`curl -o`/`sort -o` 三个真被拦，`find -type f`/`curl -s`/`sort file.txt`（无 `-o`）三个未被误伤，外加两个既有安全命令回归），全部符合预期，不是纸面判断。

**明确没有去做的**：没有试图把这套正则做成"完整的 shell 命令安全解析"——plan mode 从设计上就不是安全边界（真正的边界是容器，§3.1/§3.4），这轮只关掉了两个具体、可复现、模型确实可能顺手用到的缺口，不是要证明这份 allowlist 覆盖完备（做不到，纯字符串正则天然做不到）。`protected-paths.ts` 同理留了一个已知局限没处理：按路径字符串匹配 `.git`/`node_modules`/`.env`，不解析符号链接，一个专门指向 `.git/hooks/` 之外的软链接可以绕过——这不是这轮的疏漏，是权衡后不做（对手不是攻击者，是可能糊涂的同一个 agent，ROI 不够支撑再往下做 realpath 解析）。`trigger-compact.ts` 也复查了一遍：如果一个 session 从一开始 token 数就已经超过 100k（比如某个 handoff 出去的新会话），"跨越阈值"这个判断永远不会触发，因为它只在"从低于阈值变成高于阈值"这个跳变点上触发——这是 upstream 原有行为，没改，记在这里是因为下次如果真的踩到这个坑，不用重新排查一遍。

其余 extension（`subagent`、`session-name`、`handoff`、`questionnaire`、`dirty-repo-guard`、`custom-footer`、`doom-loop-guard` 本身）逐个看过 `ctx.hasUI`/`ctx.mode` 相关的分支，没再找到同类问题——`dirty-repo-guard.ts` 的 `!ctx.hasUI → { cancel: true }` 和 `custom-footer.ts`/`plan-mode` 已有的 `ctx.hasUI` 判断本来就是正确模式，这次只是把 `notify.ts` 补齐到同一个标准。`doom-loop-guard.ts` 自己也顺手补了一处防御：`JSON.stringify` 遇到不可序列化输入（理论上极少见）时不再直接抛异常，退化成"这次不计入循环检测"而不是让整个 tool_call 钩子崩掉。

---

## 10. v1 之后新增：`/init`、`/btw`、夜间审计循环

三个新能力同一批需求确认后落地，延续第 9 节"只吸收判断标准，不是照单全收"：能用 prompt template 解决的不写 extension 代码；需要外部调度的能力不塞进 extension（见 §10.3）。

### 10.1 `/init` —— 生成/更新 AGENTS.md，绝不覆盖已手写的文件

同 `/readme`/`/status` 一样是纯 prompt template（`.pi/prompts/init.md`），不需要 extension 代码。核心约束是幂等/非破坏性：AGENTS.md 一旦存在就是手写的、经过设计的文件（Forge 自己这份就是逐决策记在本文档里的），`/init` 检测到已存在就只提"缺了什么、加在哪"的具体建议，问过再写，绝不整体重写或静默覆盖；只有全新项目（没有 AGENTS.md）才走"从头生成"这条路径——这也是这个命令的主要使用场景：把 Forge 方法论带到一个新项目。

### 10.2 `/btw` —— 顺带一问，不进入任务/plan 状态

同样是纯 prompt template（`.pi/prompts/btw.md`），不需要状态文件（已确认不需要持久化）。核心行为：简短回答，然后原样回到当前任务/plan，不碰 `.pi/work/`、todo、plan mode 状态——这个问题本身不算主任务的进展，也不是新任务。

### 10.3 夜间审计循环 —— 外部调度 + `pi -p` 一次性子进程，不是 extension 定时器

**为什么不用 extension 定时器**：pi 官方 extension 文档明确警告，不要在 extension factory 里启动后台资源（进程/socket/文件监听/定时器）；Forge 本来就没有任何调度原语。做法直接对齐已有的 `subagent` dispatch 模型——外部反复调用 `pi -p "..."` 起独立一次性进程，不是单个 session 里的常驻循环。调度本身（00:00–04:00 窗口、轮数上限）完全交给外部 OS 调度器（launchd 为主，crontab 作为备选说明），pi/extension 层不参与调度决策。

**`notify.ts` 决策：选"外部 wrapper 直接 curl ntfy.sh"，notify.ts 本身不改动一行**。理由：
1. `ctx.hasUI` 的整体门控是 §9.13 靠真实复现（OSC 字节混进 dispatch 的 JSON 流）修的一个具体缺陷，不是猜测性加固——为一个新场景重新打开这段推理，即便是 opt-in，也是在复用一个"已经验证过对"的边界上引入新的判断分支，回归风险不对称地大于收益。
2. 新查证的一点：pi 的 extension 文档里 `ctx.mode`/`ctx.hasUI` 对照表显示，`--mode json`（subagent dispatch）和 `-p`（审计循环用的正是这个）的 `ctx.hasUI` **都是 `false`**——notify.ts 现在的门控不是"专门针对 subagent 场景碰巧也拦住了审计循环"，而是一条通用规则"没有 UI 就不通知"，对两种 headless 调用形状都是对的。要区分"因为被 subagent dispatch 而 headless"和"因为被计划任务 `pi -p` 独立跑而 headless"，这个区分在 notify.ts 内部并不天然存在，容易和 §9.13 已经修好的边界纠缠出新的边角情况。
3. wrapper 脚本（`.pi/audit/run.sh`）本来就有更适合当作通知内容的材料——退出码、这一轮审计的区域（读 `log.md` 最新条目）、是否有新提交、耗时——比 notify.ts 通用的"最后一条 assistant 消息预览"更有用，不存在"通过修 notify.ts 换来更好的通知"这个交换。
4. 唯一代价是通知逻辑分两处（TS extension + shell 脚本），可接受——wrapper 里的 `ntfy()` 函数只有十来行 curl，不是新的判断逻辑，跟 notify.ts 里 `notifyNtfy()` 复用同一对环境变量 `PI_NTFY_TOPIC`/`PI_NTFY_SERVER`，行为上是一致的，只是调用点不同。

**轮换/状态机制**：`.pi/audit/log.md`，每轮 `/audit` 追加一条（日期、区域、修了什么、报告了什么），下一轮读它挑"最久没覆盖"的区域。选它而不是手工维护的队列文件：零配置，代码库结构变化时自动跟着调整（目录改名/新增不需要手动同步队列）；代价是"子系统边界"每轮都靠模型现推断，不如固定队列确定，但审计本来就是维护性质的重复劳动，不追求逐轮完全一致。

**自动修复的可复审策略**：`/audit` 模板要求把每个发现分两类——lint 级/死代码/明显错误/文档与代码矛盾这类"低风险、明确"的直接改并原子提交（一个 commit 一个修复，conventional commit 格式）；涉及行为/接口变更或任何拿不准的一律只报告、不动。要求收工前 `git status --porcelain` 必须为空，wrapper 脚本在每轮后也做同样的检查，不干净就整晚停止（fail closed）——不是因为不信任模型的判断，是因为"叠加在不确定状态上继续自动改"这件事本身风险不对称。全部提交落在独立的 `chore/nightly-audit-<date>` 分支上，不自动合并、不自动推送，早上人工 review 之后再决定要不要合并。

**时长/轮数上限**：`.pi/audit/run.sh` 里双重强制——`AUDIT_END_TIME`（默认 04:00，每轮开始前重新判断一次）和 `AUDIT_MAX_ROUNDS`（默认 7，与时间判断相互独立，任一个先触发都停）；再加一个每轮的 `AUDIT_ROUND_TIMEOUT_SECONDS`（默认 1500 秒）防单轮卡死拖垮整晚，以及一个 `.pi/audit/STOP` 哨兵文件作为人工紧急刹车。全部在外部脚本里，pi/extension 层不参与——这是"调度和上限都是外部机制的事"这个决定的直接体现。

**一个查证到的坑**：非交互模式（`-p`/`--mode json`/`--mode rpc`）不弹信任提示，`defaultProjectTrust` 是默认值 `"ask"`（或 `"never"`）时会直接**忽略**项目资源——也就是说没有一条已保存的信任记录时，`.pi/prompts/audit.md` 本身可能加载不到，整轮审计静默退化成对着一句字面上的 `/audit` 文本瞎聊。`run.sh` 因此显式带 `--approve`，不依赖 `~/.pi/agent/trust.json` 里可能存在也可能不存在的已保存信任决定。

**另一个查证到的坑（连带发现，范围外，先记录）**：Forge 现有的 `.pi/prompts/readme.md`/`commit.md`/`changelog.md` 用的 `{{arg}}` 占位符，pi 的模板替换（`substituteArgs()`，只认 `$1`/`$@`/`$ARGUMENTS`/`${1:-default}`）根本不认识这个语法——用户在 `/readme foo` 里键入的 `foo` 从来没有被替换进模板，模型看到的是字面的 `{{focus}}`。新增的 `/init`/`/btw`/`/audit` 三个模板改用真正生效的 `$1`/`$ARGUMENTS`，但这个发现本身不属于这次三个功能的范围，没有顺手改掉那三个既有文件——按"只做请求范围内的事"处理，留给下次单独修。

### 10.4 `.pi/settings.json` —— 关掉 skill 自动生成的 `/skill:name` 命令

加完 `/init`/`/btw`/`/audit` 之后自然带出一个问题：`/` 自动补全列表已经有二十多条，还会不会继续涨。查证结论：Forge 自己定义的命令（extension 注册的 5 个 + prompt template 的 9 个）不是问题——这是一个小规模、每次新增都是用户主动确认过要留的集合，增长很慢；真正会随时间线性膨胀的是 `.pi/skills/` 里每加一个 skill 就自动多一条的 `/skill:name` 命令（Forge 现在 10 个 skill，就是 10 条）。

按 pi 官方 `skills.md` 的说明，skill 的"按相关性自动加载"和"注册成 `/skill:name` 命令"是两条独立路径：启动时扫描 skill 的 name/description 写进 system prompt，任务匹配时 agent 自己用 `read` 加载对应 `SKILL.md`（`/skill:name` 只是"强制立刻加载"的手动快捷方式，不是自动加载依赖的机制）。所以关掉 `enableSkillCommands` 只是去掉了那条没人会手动打的命令入口，不影响 skill 本身按需自动加载的能力——新建 `.pi/settings.json`：

```json
{
  "enableSkillCommands": false
}
```

明确**不**在这次一并调整 `hideThinkingBlock`（隐藏 thinking block 显示）——虽然文档上确认这个开关只影响终端显示、不影响 `defaultThinkingLevel` 也就是推理深度，但保留默认可见更符合"需要看到它在想什么"的日常使用习惯，先不动，之后如果确实觉得吵可以单独再开。

### 10.5 把夜间审计的循环机制拆成通用引擎 `.pi/scripts/pi-loop.sh`

10.3 落地之后你提了一个更通用的需求：外部反复调用 `pi -p "..."` 这套"断点 + while 循环"的机制，不应该只服务于"审计"这一个场景——目标应该是可替换的，只要换一个 prompt，就能让 pi 朝任何一个长期目标不断被重新激活去尝试，循环骨架本身复用。原来 §10.3 写的 `run.sh` 把审计逻辑（建分支、脏树检查）和循环机制（时间窗口、轮数上限、STOP、通知）糅在一个文件里，不满足这个要求。

**拆分方式**：新增 `.pi/scripts/pi-loop.sh`，对"目标是什么"零知情——不认识 git，不认识"审计"，只认识"prompt + 断点条件"。它的职责严格限定在：读一个 `--prompt`/`--prompt-file`，反复 `pi --approve -p "<prompt>"`，直到 `--until`/`--duration`/`--max-rounds`（至少给一个，否则拒绝启动——不支持无界循环）或 STOP 文件触发停止；每轮记日志、可选 ntfy 推送。目标相关的判断力通过两个通用钩子注入，而不是让引擎认识目标领域：

- `--precheck CMD`：开始前跑一次，非零退出直接拒绝启动。
- `--post-round-check CMD`：每轮跑完之后跑一次，非零退出整晚 fail closed 停止。

两个钩子都只是"跑一个 shell 命令、看退出码"，引擎完全不解释命令内容——`.pi/audit/run.sh` 拿它们传 `[ -z "$(git status --porcelain)" ]` 做脏树检查，换一个目标就可以传完全不相关的检查，引擎代码不用改一行。

**`.pi/audit/run.sh` 重构**：不再自己起 while 循环，改成薄封装——建/切 `chore/nightly-audit-<date>` 分支、把 `AUDIT_END_TIME`/`AUDIT_MAX_ROUNDS`/`AUDIT_ROUND_TIMEOUT_SECONDS`/`AUDIT_MIN_GAP_SECONDS` 这几个既有环境变量原样转发成 `pi-loop.sh` 的 `--until`/`--max-rounds`/`--round-timeout`/`--interval`，脏树检查通过 `--precheck`/`--post-round-check` 挂进去，循环结束后自己算 commit 总数发一条更详细的收尾通知。对外接口（环境变量、`.pi/audit/README.md` 里的 dry-run 步骤）完全没变，只是内部不再自己维护 while 循环。

**测试方式**：这两个脚本没有官方测试框架可用，跟 §9.13 的方法一致——真的跑，不是纸面审查。用一个假的 `pi`（shell 函数，只 echo 参数、`exit 0`）替换 PATH 里的真实 `pi`，在 `/private/tmp` 的临时目录/临时 git 仓库里跑了：`--max-rounds` 正常停止、`--precheck` 失败时拒绝启动（且不跑任何一轮）、`--post-round-check` 失败时跑完当前这轮再 fail closed 停止、STOP 文件在运行中出现时跑完当前轮就退出、`run.sh` 实际用的那句待转义的 `--precheck`/`--post-round-check` 字符串在真实嵌套引号下确实按预期展开成 `bash -c` 能执行的命令。过程中真的抓到两个 bug，都是在这轮测试里发现并修的，不是靠读代码猜的：
1. `--post-round-check` 触发的 fail-closed 分支，最终汇总行把已经跑完的轮数少算了 1 轮（沿用了"提前于 round 递增退出"那几个分支的 `round - 1` 算法，但这个分支是round 递增后已经真正跑完一轮才退出的）——改成一个独立的 `rounds_completed` 计数器，在每轮真正跑完后才自增，所有退出路径统一读这个变量。
2. 没传 `--duration` 时启动日志把默认值和单位字符串直接拼接，显示成 `duration=nones`——改成显式判断，未设置时显示 `none`，设置了才拼 `s` 单位。

以后如果要让 pi 朝别的目标（不是审计）持续尝试，直接写一个新 prompt，调 `.pi/scripts/pi-loop.sh --prompt "..." --until/--duration/--max-rounds ...` 即可，不需要再写一次 while 循环。

### 10.6 补上 `project-layout` 引用的空头支票 + 让 `/init` 真的去建骨架

`project-layout` skill（§10.4 之外新加的，见 `feat/project-layout-skill` 分支）写了"具体语言的目录习惯参考 `typescript`/`python`/`rust` 三个 skill"，但实际打开这三个文件检查后发现里面完全没有目录布局相关内容——全是类型系统/错误处理/工具链命令。这是一个真实查出来的缺口，不是假设：一个 skill 引用另一个 skill 却没兑现，比没有这个引用更糟——会让人以为查过了。

修法：给 `typescript`/`python`/`rust` 三个 skill 各加一个 `## Layout` 小节，内容是该生态的标准目录骨架（TS 的 `src/index.ts` + feature-first 组织、Python 的 `src/<package>/` layout 取舍、Rust 由 Cargo 本身规定的 `src/main.rs`/`src/lib.rs`/`tests/`/`benches/` 约定），每个都回指 `project-layout` 讲跨语言的通用纪律。

同时 `/init` 之前只在"从头生成"路径里写一个 `AGENTS.md`，目录该怎么摆完全是纸面知识，从来没有被执行过。补了 Step 2 的第 0 步：如果仓库确实是空的/近乎空的（没有真实源码，最多一个 README/LICENSE），先确认项目类型/技术栈（用 `questionnaire` 工具问，不瞎猜），照 `project-layout` + 对应语言 skill 的 Layout 小节把初始骨架建出来、确认后再落地，然后才继续生成 `AGENTS.md`。如果仓库已经有真实源码结构，这一步直接跳过——不对着别人已有的组织方式强行套一个新形状。

这次顺带把 `project-layout` skill 合并进了 `feat/pi-commands-and-settings` 分支（而不是继续留在自己独立的 `feat/project-layout-skill` 分支）——因为 `/init` 依赖它，两个继续分开会导致谁先合并、谁先测都测不出真实效果。

## 11. `.pi/prompts/*.md` 里 `{{arg}}` 占位符不生效的 bug（修复）

查证到的一个真 bug：pi 的 prompt template 参数替换（`substituteArgs()`，`dist/core/prompt-templates.js`）只认正则 `\$\{(\d+|ARGUMENTS|@):-...\}` 和 `\$(ARGUMENTS|@|\d+)` 这两类写法，根本不处理 `{{xxx}}` 语法。`readme.md`/`commit.md`/`changelog.md`/`smoke-test.md`/`retro.md` 五个既有模板都用了 `{{focus}}`/`{{scope}}`/`{{range}}`/`{{session}}` 这种写法——用户敲 `/readme 某主题`、`/retro <导出路径>` 这类带参数的调用时，参数从来没有被替换进模板，模型看到的是字面文本 `{{focus}}`/`{{session}}`。`/retro` 这个尤其严重：它的核心输入就是一个会话导出文件路径，这个 bug 相当于让 `/retro <path>` 从来没有真正读到你给的那个文件。

改法：全部换成真正生效的 `$1`/`${1:-default}` 语法，同时给每个模板补上 `argument-hint` frontmatter（原来都没有，加上之后自动补全能看到参数提示）。`changelog.md` 里 `{{range}}` 出现两次，第二处（"用 range 当版本号标题"那句）改成直接引用"上面给出的 range/tag"而不是重复展开 `${1:-...}`，避免默认值文本（比如 "last 50 commits"）被当成字面版本号标题这种没意义的组合。

这个问题最早是在做 `/init`/`/btw`/`/audit` 那批工作时查证到的（当时只测了 `readme.md`/`commit.md`/`changelog.md` 三个，判定为"超出那次范围，先不修"），这次单独成一个 fix 补上，顺带发现 `smoke-test.md`/`retro.md` 也有同样问题——一并修了，不是新范围，是同一个 bug 的完整清理。

---

对这份方案有异议或要调整的地方直接说，我按你的反馈改这份文档。
