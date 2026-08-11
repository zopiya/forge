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

对这份方案有异议或要调整的地方直接说，我按你的反馈改这份文档。
