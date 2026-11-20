# Sno：聪明的 agent，老师傅的习惯，一天比一天强

**Read in other languages:** [English](../../README.md) · **中文** · [Deutsch](README.de.md) · [Español](README.es.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · [繁體中文](README.zh-TW.md)

![Sno Station——agent 们，集合！一人计短，二人计长，睡一觉起来更聪明。](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/images/hero-banner.png)

**你的 AI agent 是个天资过人的新员工，可惜入职第一天就没人带。这套技能，让它们学会一支真刀真枪交付过的团队的做事习惯。** 一个写，另一个来审。额度快见底之前，先把交接单写好，换一个 agent 从同一个 commit 接着干。想说“做完了”？先拿出一次真实运行来。每天夜里，它们还会把白天复个盘，提出新规矩，等你点头才算数。

支持 **Claude Code、Codex、Cursor 和 Hermes Agent**，OpenClaw 也行。agent 跑得动的技能，整套装上；跑不动的，装一个精简版。

每个技能都是纯文本，能读、能抄、能改。[Sno Station](https://github.com/sno-ai/sno-station) 往你现有的 agent 里装的就是这一套；我们自己天天开发 Sno Station，用的也是它。

[![GitHub star 数](https://img.shields.io/github/stars/sno-ai/sno-station-skills?label=stars&color=eab308&labelColor=3b3b3b)](https://github.com/sno-ai/sno-station-skills/stargazers)
[![最新版本](https://img.shields.io/github/v/release/sno-ai/sno-station-skills?label=release&color=2dd4bf&labelColor=3b3b3b)](https://github.com/sno-ai/sno-station-skills/releases/latest)
[![许可证 Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-97ca00.svg?labelColor=3b3b3b)](../../LICENSE)
![每个版本发布前都自测过](https://img.shields.io/badge/every%20release-self--tested-3b82f6.svg?labelColor=3b3b3b)
![支持的 agent：Claude Code、Codex、Cursor、Hermes、OpenClaw](https://img.shields.io/badge/agents-Claude%20Code%20%C2%B7%20Codex%20%C2%B7%20Cursor%20%C2%B7%20Hermes%20%C2%B7%20OpenClaw-f0a04b.svg?labelColor=3b3b3b)

想要全部技能，对你的 agent 说一句：

```text
install sno.ai from GitHub
```

agent 会装好 Sno Station，找出你电脑上它支持的那些 agent，把每个技能连同技能要调用的程序一起配好。然后挑一个试试：

```text
peer-review this
```

另一个 agent 会开一个全新的会话来读你的改动。它压根没看过你们之前聊了什么，只管告诉你：真用起来，哪里会坏。[只想要一个技能，或者想装成插件？](#安装)

**第一次来？** 这套技能只是一半。另一半是 [Sno Station](https://github.com/sno-ai/sno-station)，技能就跑在这个工作站上：agent 之间[能互相发消息](https://github.com/sno-ai/sno-station/blob/main/apps/reach/README.md)，[活儿可以定点开工](https://github.com/sno-ai/sno-station/blob/main/docs/finish.md)，大家还共用一份记忆。

[用了之后有什么不一样](#用了之后有什么不一样) · [为什么是这套技能](#为什么是这套技能) · [吐槽与解法](#这周大家在吐槽什么以及怎么治) · [我们自己机器上的故事](#我睡了它们自己交了个班) · [安装](#安装) · [技能一览](#技能一览) · [凭什么信得过](#凭什么信得过) · [这套技能和 Sno Station](#这套技能和-sno-station) · [写给技能作者](#写给技能作者) · [许可证](#许可证)

## 用了之后有什么不一样

你照旧干你的活，用哪个 agent 随你。不一样的是下面这些时刻：

1. **改完一段代码，想找人把把关。** 说一句 "peer-review this"。另一家厂商的审查者不带任何前情、从零读起，告诉你真用起来会坏在哪儿；作者从根上修，一轮接一轮，直到审查再也挑不出毛病。
2. **睡前开一个长任务。** 说 "arm rotate-agent"。夜里干活的 agent 额度一掉到阈值，就把任务交给另一家厂商的一个新 agent；交接单核对无误之前，对方一个文件都不碰。
3. **想让它到点就干。** 直接报时间：“明天 9 点查一下构建”，或者“每天早上 7 点写报告”。到点就有一个 agent 启动，把事办了，对话开着关着都一样。`sno heartbeat --due` 能看到排了哪些。Sno Station 里这一块叫 Finish，细节见[说明](https://github.com/sno-ai/sno-station/blob/main/docs/finish.md)。
4. **你回来了。** 说 "away brief"。一页纸，最多 60 行：做完了什么，卡在哪儿、为什么卡，什么在等你回话，花了多少额度。
5. **有活要交给别人干。** 说 "write a charter"。你会拿到一份文件，写清楚交付什么、哪些不许碰、你已经拍板的事，以及每一项验收标准怎么证明。之后任何 agent 都能 `deliver` 它，每一项检查都要靠一次有记录的真实运行来证明。
6. **每天晚上，团队开复盘会。** 夜间循环把你所有 agent 当天的会话读一遍，找出反复犯的错，提出经验和技能改动。早上你用 `sno rem-reflect accept <id>` 收下你认可的那些。不点这个 accept，什么都不会变。

## 为什么是这套技能

单个 AI agent，就是个天资过人、却没有同事的新员工。自己写的自己审，看不见的地方永远看不见。额度一用完就当场撂挑子：凌晨三点，你的构建刚跑到一半。测试一绿它就说“做完了”，其实啥也没发生。你没要的东西，它一口气给你搭三层。明天它还会犯今天的错，因为没人跟它说过。

**Sno Station Skills 修的是团队，不是模型。** 这套技能由 [Sno Station](https://github.com/sno-ai/sno-station) 装进你已经在用的 agent，让它们学会好团队都有的那些习惯：另一家厂商的第二双眼睛；有人要走时干干净净的交接班；一个带着书面“完成标准”派活的组长；你回来时的一页纸简报；还有每晚一次复盘，把这周踩过的坑变成下周的规矩。

**两个 agent，各管一摊。** 一个执行你的任务，另一个对照你的要求验收结果。Claude Code、Codex、Cursor 或 Hermes Agent，哪个都能演哪个角色。两个都装了的话，审查就放到另一个里跑，开一个全新的会话，作者的聊天记录一句不带。发现了什么、怎么改，两个 agent 自己来回对。

**你睡你的，活儿照样收尾。** 睡前把它打开；干活的 agent 订阅快见底时，趁自己还能动，先写好交接单，叫醒另一家厂商的 agent，连同该接着干的那个 commit 一起交过去。构建才不管最后是哪家收的尾。

**“做完了”得拿证据说话。** 每个任务都可以带一张写好的验收清单，每一项都由一次真实运行判定过还是不过。agent 嘴上说完了，不算。

**出厂之前先自测。** 每个版本里的每个技能，都在一份干净副本上跑过自己的自测，扫过一遍个人路径和残留，还盖着一个证明这件事的戳。没过的技能不发布。

![工作原理：两个 agent，一个共享工作区，你得到的三样东西](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/images/squad-how-it-works.png)

**现在就点个 Star。下回凌晨两点 agent 又在你面前卡死，你会想知道这东西在哪儿。**

## 这周大家在吐槽什么，以及怎么治

*最后更新：2026-10-23。* 左栏每一句，都是 2026 年 10 月 20 日那一周 r/ClaudeCode、r/codex 或 r/ClaudeAI 上的真实吐槽（译自英文原帖）。右栏是我们自己机器上正在跑的解法，免费、开源，专治这些。

| 这周网友原话 | 怎么治 | 在哪儿 |
|---|---|---|
| “5 小时的额度，30 分钟就烧完了。” | 别什么活都派最大的模型去干。Opus 管规划和审查；Codex 写代码，在同一个会话里当 agent 调用。一份订阅见底了，另一份从同一份记忆里把任务接过去。 | `codex-coder`, `sno reach call` |
| “一句 ‘this model is at capacity’，通宵 10 小时的活全打了水漂。” | 额度剩 2% 时，干活的 agent 写好交接单，叫醒另一家厂商的 agent，对方从同一个 commit 接着干。那会儿你在睡觉。 | `rotate-agent` |
| “1100 个文件，3 万行。他们的 PR 我根本没那么多 token 去审。” | 谁推代码谁先审：作者先找另一家厂商来审，开一个从没看过对话的全新会话，回来的问题修完了，别人才看。 | `peer-review` |
| “一个审查 subagent 每个 commit 都查，查了两周。跑了 86 次，真拦下来的就一次。” | 同一个 harness 自己审自己，查不出真东西。审查者永远是另一个 harness 里的另一个模型，作者的聊天记录一句不带。 | `peer-review` |
| “Codex 的审查就没有做完的时候。” | 上限直接写死在技能里：代码 3 轮，计划 5 轮，测试 1 轮，到了就停，等人来定。15 分钟一个字都没写的运行，按卡死处理，直接杀掉。 | `peer-review`, `codex-coder`, `heartbeat` |
| “Codex 看每个字节都像在看嫌疑犯。” | 凭空想象的防护、拦截和哈希，是审查头一个删的。没有真实观察到的故障来要，什么都不往里加。 | `less-is-more` |
| “Claude 说某处不改，这个理由存在哪儿了？下回 Codex 读得到吗？” | 每条发现只登记一次，状态只能由人来定。同一条发现再被提出来，只更新原来那一行，不会改头换面当成新问题；之前的裁决会交给下一轮审查。 | `peer-review` 发现台账 |
| “它说做完了。结果啥也没发生。” | 任务带一张写好的验收清单，每一项由一次真实运行判定过还是不过。agent 说一句“做完了”，一文不值。 | `pl` 工单 |
| “明天它还会犯今天的错。” | 每天晚上，另一个模型把当天的会话读一遍，把你的纠正浓缩成一句话的经验，留哪条由你批准。瓶颈在我们人这边。 | Self Learning（`R` 类技能） |
| “我一半的 subagent，不过是套了个新上下文窗口的一行命令。” | 流程放进技能，不放进 subagent。只留两处 agent 分工：一处把规划和执行分开，一处做审查，因为只有这两刀切下去是划算的。 | 整套技能 |

右栏里的每个技能都在这个仓库里，免费，抄进你自己的 agent 就能用。它们共用的记忆、触发交接的额度监控、每晚写经验的那次运行，在 [Sno Station](https://github.com/sno-ai/sno-station) 里；装上它，这里的技能一个不落全跟着来，整套体验一次到位。

## 我睡了，它们自己交了个班

*出自 Sno Station 自己的仓库，2026-09-18 夜里。*

![额度监控每五分钟读一次数，一路读到阈值，2% 时触发交接](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/evidence/rotation-quota-watch-2026-09-18.png)

我们的一个 agent 正埋头跑一个很长的构建，这时它的周额度快用光了。它没有停下来干等，而是写了一张交接单：做完了什么，做了一半的是什么，该从哪个 commit 接着干。然后叫醒了另一个 agent。

中间出了个岔子，而这恰恰是最值得看的部分。新来的 agent 还没确认交接，就先动手改起了东西。第一个 agent 发现了，叫它停下，重写交接单，规规矩矩又交了一遍。一刻钟后，第二个 agent 上手干活，而且是从第一个没做完的任务接着干，不是从头再来。整个过程，我们都在睡觉。

那一夜靠的是这里发布的四个技能：`subscription-quota-check` 读额度但不花额度，`heartbeat` 每五分钟读一次数，`rotate-agent` 决定什么时候交、交给谁，`handoff` 负责把活儿挪过去。每一次额度读数、交接单的两个版本和相关 commit，都公开在 [Sno Station 的证据文件夹](https://github.com/sno-ai/sno-station/tree/main/docs/evidence/rotation-2026-09-18)里。

## 当局者迷，旁观者清

让任意一个 agent 对另一个的活儿做 `peer-review`。审查者永远在一个从没看过这段对话的全新会话里干活；只要你装了两个，审查的就一定是另一个。审查不是每次都能挑出毛病。但作者自己看不见的那些，它一次又一次地挑出来，因为 agent 审自己，用的还是写代码时那套习惯。

我们公开过一个案例：同一个 agent 看了三遍，一个已知的高危 bug 要么没看见、要么被放过；换另一个重读一遍，就把它打了回来。记录在 [cross-vendor-security-audit](#cross-vendor-security-audit--安全审计扔掉的再捡回来看一遍) 下面。

`catch-report` 用数字说话：第二个 agent 抓到了多少问题，agent 在自己活儿里又抓到了多少，两个数分开摆，绝不加在一起。

## 昨晚骂了它一顿，它记小本本上了

今天你纠正了 agent。今晚，`rem-reflect` 技能把当天的会话读一遍，找出老是重犯的错，给 agent 自己的技能提改动。明早你用 `sno rem-reflect accept <id>` 批准想要的。不点这个 accept，什么都不变。

![Self Learning 汇报它学到了什么、改了什么，2026-09-18](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/evidence/rsi-self-repair-2026-09-18.png)

这是我们自己机器上的一份真实报告。那天晚上让机器主人窝火的两件事，第二天早上经批准后，就成了正在用的技能里的规矩。没有人手敲进去。

第二天，它还回头检查了自己的作业。

![第二天早上：Self Learning 检查自己前一天的改动有没有用，2026-09-19](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/evidence/rsi-skill-impact-2026-09-19.png)

它回看了前一天改过的三个技能：又被用到的两个没出过错，第三个还没轮到用。

## 安装

### 装全部技能，连同 Sno Station

把这句提示词复制到 agent 的对话框里：

```text
Install sno.ai from GitHub.
```

它会装好 Sno Station，并为它在你机器上找到的受支持 agent 配好每个技能，以及技能要调用的程序。

或者把这条命令粘到终端里：

```bash
curl -fsSL https://sno.ai/install | sh
```

**已经装了 Sno Station？** 运行 `sno setup`，把技能装进你的 agent。以后再添新 agent，再跑一次就行。

### 只装一个技能

点下面任意一段提示词的复制按钮，粘进 agent 的对话框。agent 自己会找到并装好这个技能，你不用手动下载或复制文件。

**`peer-review`** 请另一家模型厂商的审查者来检查代码、计划和文档。它需要 Sno Station 的程序和一个已登录的审查者。这段提示词会先检查这些依赖。

```text
Install only the peer-review skill from https://github.com/sno-ai/sno-station-skills
for this project, including its scripts and references.
Check its dependencies and tell me what is missing before installing anything else.
```

**`less-is-more`** 帮你的 agent 少写代码，砍掉不必要的复杂度。不装 Sno Station 也能用。

```text
Install only the less-is-more skill from https://github.com/sno-ai/sno-station-skills
for this project, including its scripts and references.
```

**`tag-team`** 让两个 agent 搭档干一件事：一个做，一个审，发现的问题它们自己商量着解决。它需要 Sno Station 的 Reach 程序，这段提示词会先检查它在不在。

```text
Install only the tag-team skill from https://github.com/sno-ai/sno-station-skills
for this project. Check that `sno reach pair --help` works and tell me what is missing
before installing anything else.
```

Sno Station 支持的 agent：Claude Code、Codex、Cursor、Hermes Agent 和 OpenClaw。每个技能都声明了它对 agent 有什么要求。setup 按这份声明决定：完整安装、装精简版，还是在 agent 跑不了时干脆跳过。

更新不用你操心：`sno` 发现新版本就会自己更新。完整命令列表见 [Sno Station 命令手册](https://github.com/sno-ai/sno-station/blob/main/docs/sno-commands.md)。

### 装成插件

Claude Code：

```bash
claude plugin marketplace add sno-ai/sno-station-skills
claude plugin install sno-station@sno-ai
```

Codex：

```bash
codex plugin marketplace add sno-ai/sno-station-skills
codex plugin add sno-station@sno-ai
```

`sno-station` 包含全部技能；其中大多数会调用 Sno Station 的程序，所以 Sno Station 也得装上。如果只要那 12 个不依赖 Sno Station 的技能，改装 `sno-station-standalone@sno-ai`。

## 技能一览

39 个技能，打包成 30 个单元发布，按一支团队必须会的六件事归类。一个单元就是一个技能，或者一小组一起安装的技能家族。带链接的完整目录在 [skills/README.md](../../skills/README.md)。

| | 类别 | 你的 agent 能用它做什么 |
|---|---|---|
| **J** | [互审与验收](#j--互审与验收) | 互相检查对方的活儿，拿不出证据，绝不说“做完了”。 |
| **M** | [搭建与上线](#m--搭建与上线) | 在任何机器上一步配好；哪里坏了，用大白话一行一行告诉你。 |
| **S** | [沟通与交接](#s--沟通与交接) | 互相发消息；一个干不下去了，另一个带着完整上下文接手。 |
| **H** | [汇报与透明](#h--汇报与透明) | 让你看到做完了什么、拦下了什么、花了多少。 |
| **T** | [派活与工单](#t--派活与工单) | 带着书面的完成标准派活，还能带领其他 agent。 |
| **R** | [复盘与改进](#r--复盘与改进) | 从自己的错误里学习，每一处改动都要你批准。 |

### J · 互审与验收

*同事之间互相审，验收不过，就不算完。*

#### [peer-review](../../skills/J-peer-review-and-audit/peer-review/) — 另一家厂商来审，修到干净为止

- **真正独立。** 审查在一个全新会话里跑，作者的对话一句不带，并优先用另一家厂商的 CLI。只装了一个 CLI 也照样跑，同样是全新会话，并在第一行写明这是同厂商审查。
- **专抓真正让你肉疼的。** 先用你系统真会产生的输入，把最普通的那条路走一遍，然后才肯在稀奇古怪的边界情况上花一分钟。数据丢失、悄无声息的错误结果、主流程断掉，排在最前；代码风格不在清单上。
- **每条发现都得站得住。** 每一条都要写清：真实用户怎么走到这一步、坏了什么，再加上一次认真的自我反驳。审查者说的话一句不删、不打折；疑似误报会标出来，不会藏起来。
- **先做减法，再做加法。** 头一件事是列出这次改动里多加了哪些没人需要的东西；“必须马上修”和“顺便发现”分开放，审查永远不会变成又一堆新代码。
- **文档也能审。** 需求说明、计划、迁移清单会拿到一份结构化报告：哪里会让照着做的人把错的东西交出去。

*什么时候用：* 改动、计划或需求写完了，合进去之前想找人把把关。

#### [less-is-more](../../skills/J-peer-review-and-audit/less-is-more/) — 能跑就行的最少代码，多余的一刀砍掉

- **动笔之前先爬梯子：** 到底要不要；仓库里是不是已经有了；标准库能不能做；平台能不能做；已经装的依赖能不能做。都不行，才写能跑的最少代码。
- **砍掉 agent 过度搭建的东西：** 只有一个实现的接口、明明永远不变却做成配置项的值、“以后用得上”的脚手架、挡住正事的检查和关卡。
- **测试预算花在刀刃上：** 用能证明这次改动的最小测试，不靠跑一遍全量测试求个心安。
- **两个方向自己切换：** 说“写”或“修”就盖，说“审”或“简化”就砍；盖完之后、交出去之前，先把自己的 diff 砍一遍。

*什么时候用：* 任何写代码的活儿，或者你说出“太复杂了”“有什么能删的”的时候。

#### [owner-intent-audit](../../skills/J-peer-review-and-audit/owner-intent-audit/) — 这真是你想要的吗？

- **查意思，不查字眼。** 一份计划可以把你说过的名词一个不落地留着，描述的却是另一个产品。它专抓这些：有条件的变成了无条件，一个例子被当成了全部边界，一条禁令悄悄没了。
- **翻出 agent 留下的烂账：** 没人要的活儿、和现实对不上的文档、没人能拍板的决定、没证据撑腰的“做完了”。
- **计划和代码都管：** 需求文档、设计、任务清单、测试计划，或者 agent 写的一份 diff。

*什么时候用：* 批准一份计划、合并 agent 的活儿之前。

#### [agentic-walkthrough](../../skills/J-peer-review-and-audit/agentic-walkthrough/) — 处处都显示“成功”，你心里还是没底

- **专治没有测试抓得住的无声失败：** 一个任务启动了、跑完了、写了日志、自己的检查也过了，结果什么都没碰。
- **把自己当成程序走一遍：** 一环一环往下走，找出每一个能把活儿悄悄变成空操作的开关、默认值和兜底逻辑。
- **每一环都得自证清白：** 用一个只有真干了活才会出现的窄观察来证明：存下来的那一行数据、真正被打开的那个数据库文件、真正发出去的那次 API 调用。

*什么时候用：* 一次运行报告成功，而你需要证据证明它真干了活。

#### [first-principles-review](../../skills/J-peer-review-and-audit/first-principles-review/) — 想法变成代码之前，先挑战它

- **先调研，** 再撇开提议里的方案，从头推一遍你到底需要什么。
- **把每条约束分好类：** 硬限制、拍板人的偏好，还是沿袭下来的老习惯；每个承重的假设都拿证据来检验。
- **最后给一个明确结论：** 继续、换个角度、简化、替换、拆分、先试，或者停下；附上建议方向，以及什么样的证据能推翻这个结论。
- **交接干净：** 一份书面报告，加一份结构化摘要，下一个写需求的人拿来就能用。

*什么时候用：* 一个设计或产品想法快要定型成计划的时候。需要点名启动。

#### [e2e](../../skills/J-peer-review-and-audit/e2e/) — 端到端测试，要挂只因为真问题

- **`e2e-environment-preflight`** 在第一个测试跑之前，先检查外部服务、主机、浏览器会话、模型接口和 agent，长长一套测试不会因为某个依赖早就挂了而白跑。
- **`e2e-red-triage`** 处理检查也没料到的那种少见失败。它不让人瞎猜，把结果拆成两半看（是被接收还是已完成，是被停掉还是崩了，是空的还是读不出来），再下判断：是产品 bug，还是该新加一条环境检查。

*什么时候用：* 对真实服务跑端到端测试的时候。

#### [test-writer](../../skills/J-peer-review-and-audit/test-writer/) — 真的会变红的测试

- **能用真的就不用假的：** 只要仓库提供得了，就用真的解析器、文件系统、数据库或服务；被测的那个东西，绝不拿 mock 顶替。
- **每条断言都可能失败：** 检查返回的内容、存下来的状态和真实的副作用，而不是调用次数；也绝不为了让测试通过去放松断言。
- **写什么跑什么，不多跑：** 只针对改过的测试跑最窄的那条命令，不跑全套；报告里写明跑了什么、看到了什么。

*什么时候用：* 让 agent 写或修测试、fixture 或 eval 的时候。它单独就能用，不需要 Sno Station。

#### [cross-vendor-security-audit](../../skills/J-peer-review-and-audit/cross-vendor-security-audit/) — 安全审计：扔掉的，再捡回来看一遍

**Claude 审了三遍，漏掉了一个已公开的高危 bug。Codex 把 Claude 扔掉的东西过了一遍，找到了它。** 在这个 bug 上，Claude 每多审一遍，都在重复自己当初放过它的那个理由；另一家厂商带来的是另一个理由。

我们审的是 follow-redirects 1.16.1，它有一个已知 bug（[GHSA-mrwp-f3q8-3g9p](https://github.com/advisories/GHSA-mrwp-f3q8-3g9p)，高危，1.16.2 修复）：在另一个 JavaScript realm 里构造的敏感 header 列表会被当成空的，于是调用方的 API key 会跟着重定向，跑到另一个主机上去。

- Claude 第一次审计：没看见。
- Claude 第二次审计：看见了，然后归为“加固建议，不算问题”。
- 一个新的 Claude 重读所有被搁置的条目：同意，“调用方用法不对”。
- Codex 单独审计：没看见。
- **Codex 重读 Claude 搁置的条目：不同意，顺着源码追了一遍，打回去重新验证。**

最后这一步，就是这个技能在 Cloudflare 的 security-audit 技能之上加的东西（依照其 MIT 许可证使用；审计流程、证据门槛、验证器和报告都一样）。出报告之前，另一家厂商的模型以只读方式，把审计搁置的每一条重读一遍，而且每一条都必须给出答复；它捞回来的任何一条都会重新验证。如果验证又把它否了，报告会把它列在 “Reviewers disagree”（审查者意见不一）下面，两边理由都写上，由你定夺。

两个项目，三个已知 bug：只算个案，不是统计。在另一个项目上，两家的审查者谁来都把 bug 找了回来。而当 Claude 第一次审计压根没看那个 bug 时，对那次审计的重读也没找到它。

*什么时候用：* 想给一个代码库做一次完整的安全审计。装了 Sno Station 时，它会挑还有额度的另一家厂商审查者；没装时，它在 Claude Code 里调用 Codex，或在 Codex 里调用 Claude Code，只有一家可用时会明说。

### M · 搭建与上线

*任何一台工作站，一步把团队配好；活儿需要什么就搭什么，再推到每一台机器上。*

配置本身靠的是 `sno setup` 命令，不是技能。这里有两个技能负责让机器保持健康、让你的 agent 用顺 `sno` 命令；剩下的负责写代码：一个把活儿交给 Codex，四个分别用 Shell、TypeScript、Python 和 Rust 写。

#### [medic](../../skills/M-build-and-rollout/medic/) — 我的 agent 团队还健康吗？一个问题一行答案。

- **团队需要的都查一遍，** 大约十秒：工具装没装、技能装没装、技能命令能不能跑、hook 配没配、消息通不通、两家厂商的额度能不能读、临时空间够不够。
- **每个问题都附上解法：** `WARN` 或 `FAIL`，哪里不对，以及修它的那条确切命令。
- **只看不动。** 它不安装、不修复、不启动、不停止任何东西。修什么由你定。

*什么时候用：* 新机器上；agent 之间联系不上了；或者一个长任务死活起不来。

#### [sno-cli](../../skills/M-build-and-rollout/sno-cli/) — 让你的 agent 第一次就把 `sno` 用对

- **永不过时：** agent 直接从装好的 `sno` 里读确切的命令和参数，不凭记忆。
- **常见任务，现成步骤：** 安装、更新、健康检查、账号、技能和夜间循环。
- **你的选择还是你的：** 它只负责操作工具，不替你决定设置。

*什么时候用：* 让 agent 安装、更新、检查或配置 Sno 的时候。

#### [codex-coder](../../skills/M-build-and-rollout/codex-coder/) — Claude 出方案，Codex 写代码

- **一个会话，两家厂商：** Claude Code 握着方案和对话，写代码时启动一次普通的 `codex exec`，敲键盘的不是那个贵的模型。
- **替你选语言：** 根据任务涉及的文件选 Shell、TypeScript、Python 或 Rust；你装了自己的语言技能，就用你的。
- **卡住的运行跑不掉：** 运行期间 Claude Code 会收到进度；15 分钟一个字都没写的运行会被杀掉，再重启一次。

*什么时候用：* 代码写到一半 Claude 额度用完了，或者你想让 Codex 去写 Claude 规划好的东西。在 Claude Code 这一侧需要 Sno Station 的 `heartbeat`。

#### [shellscript-coder](../../skills/M-build-and-rollout/shellscript-coder/), [ts-coder](../../skills/M-build-and-rollout/ts-coder/), [python-coder](../../skills/M-build-and-rollout/python-coder/), [rust-coder](../../skills/M-build-and-rollout/rust-coder/) — 写出来的代码，跟仓库是一个味儿

- **先读后写：** 先看仓库自己的运行时、版本、工具函数、调用方和测试，新代码才长得像周围的代码。
- **故意写小：** 不加兼容层，不加没人要的选项，不重写隔壁两个文件里就有的工具函数。
- **完成就是一条命令跑通了：** 报告里每一句话都对得上它在你仓库里真跑过的检查；有检查没过，绝不报完成。

*什么时候用：* 想让 agent 用这四种语言之一写或改生产代码。它们单独就能用，不需要 Sno Station；`codex-coder` 会为每个任务挑对的那一个。

### S · 沟通与交接

*大家通过共享收件箱说话；谁请假了，另一个带着完整上下文顶上。*

这些技能跑在 Sno Reach 上，也就是 Sno Station 装的消息层：每个 agent 有一个地址，能往别的 agent 的收件箱里发会保存下来的消息，还能叫醒另一个 agent 来读。没有守护进程，没有服务器。

#### [handoff](../../skills/S-communication-and-handoff/handoff/) — 交接班，一样都不落下

- **把整个状态都记下来：** 做完了什么、做到一半的、没提交的改动、你已经拍板的决定，还有哪些不许碰。
- **交接没核实之前，接班的一个字都不写，** 所以两个 agent 永远不会同时改同一份活儿。
- **交班的人是真走了。** 交接完成后它就停手，没有第二个主人在旁边转悠。
- **交班的人已经不在了也能接**（额度被拒、崩溃、窗口被关）：`sno handoff-checkpoint` 的进度记录能让一个新 agent 从第一个没做完的任务接着干。

*什么时候用：* 一个 agent 必须把任务交给另一个的时候。

#### [rotate-agent](../../skills/S-communication-and-handoff/rotate-agent/) — 长任务再也不会栽在额度上

- **趁交班的还活着就动手。** 它每隔几分钟看一次剩余额度，到阈值就交接，而不是等被拒了才动，那时候连交接单都来不及写了。
- **两个方向都行：** Codex 交给 Claude Code，或者 Claude Code 交给 Codex。
- **有边界：** 只触发一次，监控跑多久也可以由你限定。
- **错过时机也有兜底：** 如果时机错过了，`sno rotate-agent-resume` 会按磁盘上的进度记录把替班的启动起来。

*什么时候用：* 一个长任务必须跑完，哪怕某一家的额度用光了。需要两个 CLI 都已登录，还要有 tmux。

#### [subscription-quota-check](../../skills/S-communication-and-handoff/subscription-quota-check/) — 还剩多少额度？查一下，一分不花

- **戒掉最糟的习惯：** 真发一次请求、看到报错，才知道额度没了。
- **一次读 Claude Code 和 Codex 两家，** 大约八秒，还告诉你额度什么时候重置。
- **数字旧了会老实说：** 它会检查读数是当前的还是上一次已知的，并告诉你是哪种。
- **从不自己轮询，** 所以永远不会因为它自己招来限流。

*什么时候用：* 你问的时候，或者某家刚拒了活儿之后。

#### [heartbeat](../../skills/S-communication-and-handoff/heartbeat/) — 长任务的进度汇报，直接送到对话里

- **两种用法：** 每 N 分钟报一次（训练、长构建、生成队列），或者一直盯到某件事结束。
- **定时任务：** 告诉 agent 一个日期或钟点，一次或重复都行。它把任务记下来，到点就有 agent 启动，哪怕对话已经关了。
- **汇报落在你在的地方：** 每次读数都送进 agent 的对话里，而不是一份没人看的日志。
- **不容易用错：** 间隔以分钟为单位，填一个秒级大小的数字会被拒绝，而不是悄悄地每隔几秒把你的 agent 叫醒一次。

*什么时候用：* 有个长任务在没人看着的时候跑，你想听到它的动静；或者有件事得在你不在场的时间点做。

#### [reach](../../skills/S-communication-and-handoff/reach/) — agent 之间互相说话

- **启动一个 Claude Code 或 Codex agent，** 给它自己的地址和工作文件夹。
- **派活、看回复：** 通过会保存的消息，或者直接跟一个在线的 agent 当场对话。
- **消息不带额外权限：** 一条消息永远不会把你交代的任务范围放大。

*什么时候用：* 一个 agent 需要联系、启动或等待另一个的时候。

#### [join-talk](../../skills/S-communication-and-handoff/join-talk/) — 一条命令，让任何 agent 都能被找到

- **只输出一行：** `joined <address>`。把这个地址告诉其他 agent，它们就能找到这个终端。
- **重复跑也没事：** 在同一个终端再跑一次，什么都不会变。
- **拒绝也拒得明白：** 跑不了时，它会说清楚到底为什么。

*什么时候用：* 你手动开了一个 agent，想让别的 agent 能找到它。

#### [tag-team](../../skills/S-communication-and-handoff/tag-team/) — 两个 agent 搭档：一个干，一个审

- **一条命令：** `sno reach pair "the task"` 在当前文件夹里同时启动两个 agent，各自在一个 tmux 窗口里，你随时可以打开来看。
- **到你手上之前，已经吵过一轮了。** 审查者读结果和改过的文件，回复具体的缺陷，或者明确的“无缺陷”；两个 agent 自己来回修、来回审，你的 agent 宣布干净之前，还要先问过审查者。
- **告诉你这是哪种审查。** 登录了两家厂商，审查就来自另一家。只登录了一家，搭档照样跑，并告诉你审查没出这一家。
- **不会过早宣布干净。** 第一轮审查有发现，就报告为未解决；不会再拉第三个审查者，也不会因为第一轮审查还没回来，就再开第二对。

*什么时候用：* 一件活儿值得听听第二意见，而你又不想在两个 agent 之间来回传话。

### H · 汇报与透明

*谁都看得到：做完了什么，谁抓到了什么，谁替谁顶了班，什么正在进行。*

#### [away-brief](../../skills/H-reporting-and-visibility/away-brief/) — 你回来时的一页纸

- **四个部分，最多 60 行：** Done（已完成）、Stuck（卡住了）、Needs you（等你）、Spend（花费）。
- **等你处理的事，绝不会被一长串已完成的活儿挤出这一页。**
- **“已完成”只算真的：** 在 git 里、在已交付的工单里，或者在一份已完成的进度记录里。agent 嘴上说的不算。
- **告诉你这一夜花了多少：** 走之前跑一下 `sno away-brief mark`，下一页就会显示从那以后花掉的额度。

*什么时候用：* 睡醒、开完会，或者一次无人值守的长任务跑完之后。

#### [catch-report](../../skills/H-reporting-and-visibility/catch-report/) — 第二个 agent 值不值？看数字。

- **两个数并排摆：** 另一个模型在审查中抓到的问题，以及 agent 自己抓到自己错误的次数。
- **绝不注水：** 两个数分开放，从不相加；某部分测不了，就直说测不了，而不是报个零。
- **点名最大的几次拦截：** 按标题引用，来源是你机器上已有的审查记录。

*什么时候用：* 想看本周的审查成果，或者需要说明跑两个 agent 值得。

#### [agentic-time-estimate](../../skills/H-reporting-and-visibility/agentic-time-estimate/) — agent 干活要多久，给你个靠谱的估计

- **算 agent 的实际耗时，不算人类程序员的：** 这活儿 agent 要干多久，正在跑的任务还要多久，先测量，再估计。
- **钟点信得过：** 给你看的每个时间都来自 `sno report-time`，用你所在的时区，旁边附上 UTC。

*什么时候用：* 你问“要多久？”或者“什么时候能好？”的时候。

### T · 派活与工单

*组长用工单派活，并决定每件活儿谁来接。*

#### [charter](../../skills/T-delegation-and-work-orders/charter/) — 一份文件，说清楚什么叫“做完”

- **你说的话原样保留。** 它从不编造决定、事实或需求；只有答案会改变结果时，才问问题，而且一次只问一个。
- **验收标准能跑：** 每一项都写明观察什么、在哪儿、怎么看，结果只有通过或不通过。
- **不搞形式主义：** 说不出它能拦住哪种失败的东西，一概不写进去。
- **什么项目都行：** 软件、文档、营销活动、调研、运维。

*什么时候用：* 一件活儿交给别人之前，需要一份书面任务书。

#### [deliver](../../skills/T-delegation-and-work-orders/deliver/) — 把任务书一路做到有证据的结果

- **任务书里的检查就是“做完”的定义，** 别的都不算。
- **每项检查都靠一次有记录的真实运行证明，** 用 `sno deliver-proof` 跟踪。
- **一次独立审查，** 然后老老实实收尾：什么过了，什么没过，为什么。
- **从别人停下的地方接着干：** 如果前一个 agent 留了进度记录，它就从下一个没完成的步骤继续，不从头再来。

*什么时候用：* 任务书已经发出，得有人去干。

#### [pl](../../skills/T-delegation-and-work-orders/pl/) — 项目负责人 agent，管一条线的活儿

- **最多带四个执行 agent，** 每个领一份任务书，串行或并行都行。
- **还有一家子五个技能：** `pl-dispatch` 开工和排期，`pl-watch` 盯着干到一半的 agent，`pl-audit` 在任何东西收尾前做验收，`pl-env` 修活儿运行的环境，`pl-analyze` 在出事时写根因分析。

*什么时候用：* 一个项目需要好几个 agent 在一个负责人手下干活。需要点名启动。

#### [cos](../../skills/T-delegation-and-work-orders/cos/) — 幕僚长：你只用跟这一个 agent 说话

- **你只需要一个对话，** 用你的语言。它同时协调一到三个项目负责人，只把难决定的事带给你：钱、方向、红线。
- **还有一家子三个技能：** `cos-watch` 让每个项目负责人都活着、按计划走；`cos-review` 在你回来时一次性复查这一夜做的决定；`cos-evolve` 把反复出现的管理失误变成强制执行的规矩。

*什么时候用：* 你同时跑好几条工作线，只想要一个对接人。需要点名启动。

### R · 复盘与改进

*团队回头看自己的活儿，把教训变成规矩和更好的做法。*

#### [rem-reflect](../../skills/R-recursive-self-improvement/rem-reflect/) — 夜间循环：你的 agent 从自己的会话里学习

- **每天一次，** 它读这台机器上 agent 的会话（Claude Code、Codex、Cursor、Hermes Agent 和 OpenClaw），找出反复出现的失败和纠正，把它们变成经验和技能改动提案。
- **一切由你批准：** 每一条都用 `sno rem-reflect accept`、`reject` 或 `tbd` 处理。你不 accept，什么都不变。
- **经验在用得上的时候回来：** 被接受的经验会在下一次会话开始时出现在 agent 面前，只针对这个项目，或者针对所有项目。
- **什么离开这台机器，你说了算。** 在 `local-first` 模式下，什么都不发给 Sno；当晚的少量会话只会发到你自己的 Claude Code 或 Codex 账号上，用来起草经验。另外两种模式在默认共享级别下，会把会话文本（先尽力抹掉常见的密钥）和你装的技能上传到 Sno 的云端，换来更强的判断。随时可以用 `sno station consent off` 关掉上传。它读什么、发什么，技能里列得清清楚楚。

家族技能 `pl-analyze`（给项目负责人做事故分析）和 `cos-evolve`（把重复的失败变成规矩）也属于这一类；它们跟着 `pl` 和 `cos` 一起发布。

*什么时候用：* 一直开着，只要 `sno setup` 设好了每日运行。

## 凭什么信得过

每个版本里的每个单元，发布前都过了同样几道关：

1. 仓库带着自己的 `LICENSE` 和 `NOTICE`；
2. 单元整个复制，家族成员和针对不同 agent 的差异原样保留；
3. 不留任何个人痕迹：没有 home 路径、owner 名字、内部主机或写死的模型，也没有中文、日文或韩文字符；
4. 每个技能的头部都能解析，它对 agent 的需求声明也合法；
5. 每个技能自己的自测，在这份干净副本上通过，而不是在作者的机器上；
6. 最后才写入一个戳 `PUBLISHED.json`，记下自测数量，以及契约和内容的校验值。

任何一关没过的技能，不发布。戳由发布构建写入，从不手写。所有技能文本都是英文，你用什么语言跟 agent 说话，它就用什么语言照着做，跟它说中文也一样。

## 这套技能和 Sno Station

技能是习惯，[Sno Station](https://github.com/sno-ai/sno-station) 是让这些习惯跑起来的工作站：它们共用的记忆、触发交接的额度监控、agent 之间的消息，还有每晚写经验的那次运行。装上 Sno Station，这里的每个技能都跟着来。

| 你想要 | 去这里 |
|---|---|
| 整个工作站，以及今天哪些功能能在哪个 agent 上跑 | [sno-ai/sno-station](https://github.com/sno-ai/sno-station#what-you-can-use-today-and-where-it-stops) |
| 跨窗口、跨电脑互发消息的 agent | [Sno Reach](https://github.com/sno-ai/sno-station/blob/main/apps/reach/README.md) |
| 到你说的时间点就开工的活儿 | [Finish](https://github.com/sno-ai/sno-station/blob/main/docs/finish.md) |
| 技能调用的每一条 `sno` 命令 | [命令手册](https://github.com/sno-ai/sno-station/blob/main/docs/sno-commands.md) |
| 上面那些故事背后的原始记录 | [证据文件夹](https://github.com/sno-ai/sno-station/tree/main/docs/evidence) |
| 问个问题，或者晒晒你做的东西 | [Discussions](https://github.com/sno-ai/sno-station-skills/discussions) |
| 找个小改动练练手 | [Good first issues](https://github.com/sno-ai/sno-station-skills/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) 和 [CONTRIBUTING.md](../../CONTRIBUTING.md) |

**两个仓库都点个 Star 吧。** 我们就是用这套技能做 Sno Station 的。我们自己值夜班学到的东西，一版接一版，都会发布到这里。

## 写给技能作者

### 目录结构

```
skills/
  README.md                     the category index
  <category>/<unit>/
    skill/                      one skill: SKILL.md, references/, scripts/
    skills/<member>/            or a family of skills that ship together
    overlay/claude|codex/       per-agent differences, when a skill needs them
    public-bin/                 one file per `sno <file name>` command the skill provides
    PUBLISHED.json              the stamp, written into the release archive by the build
registry.yaml                   unit -> category code (and tier)
scripts/
  requirements-contract.json    the contract every requires: block is checked against
LICENSE                         Apache-2.0
```

类别代码是固定的，顺序为 J M S H T R，出现在目录名和 `registry.yaml` 里。

### 声明技能需要什么

每个 `SKILL.md` 开头都有一个 `requires:` 块。`sno setup` 读它，逐个 agent 决定要不要装这个技能：

```yaml
requires:
  programs: [reach]                          # Sno Station programs the skill calls
  harness:
    - {slot: 4.shell, need: required}        # what the agent itself must be able to do
```

- **programs** 是装在技能旁边、以 `sno <name>` 形式运行的 Sno Station 程序：`reach`、`heartbeat`、`subscription-quota-check`、`report-time`。
- **slots** 指 agent 的某种能力：`4.shell`（运行 shell 命令）、`4.file-read-write`（读写文件）、`4.background-processes`（在后台运行命令）、`2.pre-turn-context-injection`（每轮开始前往 agent 的上下文里加一段文字）和 `3.reader-to-agent-delivery`（后台读取器的输出能送到 agent 那里）。
- **need** 取值为 `required`（没有这个 slot 的 agent 拿不到这个技能）、`preferred`（技能照样装上，以精简方式工作）或 `optional`（只是锦上添花）。

## 许可证

Apache-2.0。从头到尾都开源。详见 [LICENSE](../../LICENSE)。
