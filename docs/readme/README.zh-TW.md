# Sno：聰明的 agent，老手的工作習慣，一天比一天強。

**Read in other languages:** [English](../../README.md) · [中文](README.zh-CN.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · **繁體中文**

![Sno Station：Agents, assemble。兩顆腦袋勝過一顆，睡一覺起來還更聰明。](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/images/hero-banner.png)

**你的 AI agent 個個都是天才新人，可惜沒人帶。這套技能，讓它們像一支真的上線過、出過貨的團隊那樣做事。** 一個寫，另一個審。額度見底之前先寫好交接，下一位從同一個 commit 接著做。沒有實際跑過，誰都不准說「做完了」。每天晚上，它們回顧當天的工作，提出新規則，等你點頭才算數。

支援 **Claude Code、Codex、Cursor 和 Hermes Agent**，OpenClaw 也行。agent 能執行的技能就完整安裝，不能完整執行的就裝精簡版。

每個技能都是純文字，看得懂、能複製、隨你改。[Sno Station](https://github.com/sno-ai/sno-station) 會把這些技能裝進你現有的 agent；我們自己每天開發 Sno Station，用的也是這一套。

[![GitHub 星星數](https://img.shields.io/github/stars/sno-ai/sno-station-skills?label=stars&color=eab308&labelColor=3b3b3b)](https://github.com/sno-ai/sno-station-skills/stargazers)
[![最新版本](https://img.shields.io/github/v/release/sno-ai/sno-station-skills?label=release&color=2dd4bf&labelColor=3b3b3b)](https://github.com/sno-ai/sno-station-skills/releases/latest)
[![授權 Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-97ca00.svg?labelColor=3b3b3b)](../../LICENSE)
![每次發布前都經過自我測試](https://img.shields.io/badge/every%20release-self--tested-3b82f6.svg?labelColor=3b3b3b)
![支援的 agent：Claude Code、Codex、Cursor、Hermes、OpenClaw](https://img.shields.io/badge/agents-Claude%20Code%20%C2%B7%20Codex%20%C2%B7%20Cursor%20%C2%B7%20Hermes%20%C2%B7%20OpenClaw-f0a04b.svg?labelColor=3b3b3b)

想一次拿到所有技能，跟你的 agent 說一聲：

```text
install sno.ai from GitHub
```

agent 會安裝 Sno Station，替它在你電腦上找到的每個支援的 agent 裝好所有技能，連技能會呼叫的程式也一併裝好。接著試一個：

```text
peer-review this
```

另一個 agent 會在全新的 session 裡讀你的改動。它完全沒看過你們的對話，只告訴你真正用起來哪裡會壞。[只想裝一個技能，或想用外掛？](#安裝)

**第一次來？** 這些技能只是一半。另一半是 [Sno Station](https://github.com/sno-ai/sno-station)，也就是它們運作的工作站：agent 之間[能互傳訊息](https://github.com/sno-ai/sno-station/blob/main/apps/reach/README.md)、[工作可以排定時間自動開始](https://github.com/sno-ai/sno-station/blob/main/docs/finish.md)，還有一份大家共用的記憶。

[用了之後差在哪](#用了之後差在哪) · [為什麼是這套技能](#為什麼是這套技能) · [網友在哭什麼，我們怎麼解](#網友在哭什麼我們怎麼解) · [我們機器上的真實故事](#我去睡了它們自己交班) · [安裝](#安裝) · [技能總覽](#技能總覽) · [憑什麼信任它](#憑什麼信任它) · [這些技能與 Sno Station](#這些技能與-sno-station) · [給技能作者](#給技能作者) · [授權](#授權)

## 用了之後，差在哪

你照舊用你習慣的 agent 做事，什麼都不用改。差別在這裡：

1. **改完一段，想找人看看。** 說「peer-review this」。另一家廠商的審查者冷眼從頭讀起，
   回報實際使用會壞在哪，作者從根本原因修起，一輪接一輪，直到審查回來乾乾淨淨。
2. **睡前丟一個長任務下去。** 說「arm rotate-agent」。半夜要是正在做事的 agent 額度
   掉到門檻，它會把任務交給另一家廠商的全新 agent；交接說明確認無誤之前，一個檔案都不會動。
3. **想在固定時間做某件事。** 直接講時間：「明天早上 9 點檢查 build」，或「每天早上 7 點
   寫報告」。時間一到就有 agent 開工，對話開著或關了都一樣。`sno heartbeat --due` 可以看
   排了哪些。Sno Station 的這部分叫做 Finish，細節請看[說明](https://github.com/sno-ai/sno-station/blob/main/docs/finish.md)。
4. **你回來了。** 說「away brief」。一頁，最多 60 行：做完了什麼、卡在哪裡和為什麼、
   哪些在等你回覆、花掉多少額度。
5. **有件事要交給別人做。** 說「write a charter」。你會拿到一個檔案，寫清楚要交付什麼、
   哪些不准碰、你已經決定了什麼，以及每一項驗收條件要怎麼證明。之後任何 agent 都能
   `deliver` 它，每項驗收都要有實際執行的紀錄當證據。
6. **每天晚上，團隊開檢討會。** 夜間流程會讀你所有 agent 當天的 session，找出一再重犯的錯，
   提出教訓和技能修改建議。早上你用 `sno rem-reflect accept <id>` 收下你要的。沒有你這一下
   accept，什麼都不會改。

## 為什麼是這套技能

一個 AI agent，就是一個沒人帶的天才新人。自己寫的自己審，盲點永遠是盲點。額度一用完就當場
停擺，偏偏是凌晨三點，你的 build 跑到一半。測試全綠就說「做完了」，其實什麼也沒發生。
你沒要的機制，它一口氣蓋三層。明天，它照樣犯今天的錯，因為沒人跟它說過。

**Sno Station Skills 修的是團隊，不是模型。** 這些技能由
[Sno Station](https://github.com/sno-ai/sno-station) 裝進你現有的 agent，讓它們養成每支好的
工程團隊都有的習慣：來自另一家廠商的第二雙眼睛；有人得先走時，乾淨俐落的交接；派工時
白紙黑字寫明「怎樣算完成」的組長；你回來時一頁看完的簡報；還有每晚一次的回顧，把這週的錯
變成下週的規矩。

**兩個 agent，分工不同。** 一個負責執行你的任務，另一個拿你的需求來審結果。Claude Code、
Codex、Cursor 或 Hermes Agent 都能擔任任一個角色。兩邊都裝了的話，審查就交給另一個，在全新的
session 裡進行，完全看不到作者的對話。發現的問題和修正，由它們彼此來回處理。

**你睡你的，工作照樣收尾。** 睡前設定好，正在做事的 agent 訂閱額度快不夠時，會趁還有力氣
先寫好交接說明，叫醒另一家廠商的 agent，連同要接續的確切 commit 一起交出去。你的 build 才不管
最後是哪一家收的尾。

**「做完了」，要拿證據來。** 每個任務都可以附一份書面驗收清單，每一項都由實際執行判定通過
或失敗。agent 嘴上說完成，不算數。

**出貨前先測過。** 每次發布裡的每個技能，都在乾淨的副本上通過了自己的自我測試，也掃過有沒有
殘留個人路徑和雜物，並且蓋了一個證明這些的戳記。沒通過的技能，不會發布。

![運作方式：兩個 agent、一個共用工作區、你得到的三件事](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/images/squad-how-it-works.png)

**現在就按個星星。下次凌晨兩點 agent 又卡住，你會想知道這東西放在哪。**

## 網友在哭什麼，我們怎麼解

*最後更新：2026-10-23。* 左欄每一句，都是 2026 年 10 月 20 日那一週，r/ClaudeCode、r/codex 或 r/ClaudeAI 上的真實抱怨。右欄是我們自己機器上天天在跑、免費又開源的解法，專治這些毛病。

| 這週大家在抱怨 | 怎麼解 | 在哪 |
|---|---|---|
| 「5 小時的額度，30 分鐘就燒光了。」 | 別再什麼事都派最大的模型去做。Opus 負責規劃和審查；Codex 寫程式，在同一個 session 裡當成 agent 呼叫。一邊的訂閱見底，另一邊從同一份記憶把任務接過去。 | `codex-coder`, `sno reach call` |
| 「整晚 10 小時的工作，被一句『this model is at capacity』全毀了。」 | 額度剩 2% 時，正在做事的 agent 寫好交接說明，叫醒另一家廠商的 agent，從確切的 commit 繼續。那時你正在睡覺。 | `rotate-agent` |
| 「1,100 個檔案、3 萬行。我哪來的 token 預算去審他們的 PR。」 | 誰 push，誰先審：作者先請另一家廠商來審，在一個沒看過對話的全新 session 裡進行，別人看之前就把回報的問題修掉。 | `peer-review` |
| 「讓一個審查 subagent 盯每個 commit 盯了兩週。跑了 86 次，只擋下一次。」 | 自己審自己的 harness，找不出真問題。審查者一定是另一個 harness 裡的另一個模型，作者的對話它一句都沒看過。 | `peer-review` |
| 「Codex 審查永遠審不完。」 | 上限直接寫死在技能裡：程式碼 3 輪、計畫 5 輪、測試 1 輪，到了就停，等人來決定。15 分鐘沒寫出任何東西的執行，視為卡死，直接砍掉。 | `peer-review`, `codex-coder`, `heartbeat` |
| 「Codex 把每個 byte 都當犯人在防。」 | 憑空想像的防護、擋路的檢查和 hash，是審查第一個刪掉的東西。沒有實際觀察到的失敗，什麼都不准加。 | `less-is-more` |
| 「Claude 說某個地方不改，那個理由有存在哪裡、讓 Codex 下次讀得到嗎？」 | 每個發現只登記一次，狀態只有人能設定。同一個問題再被提出，就更新原本那一列，不會當成新問題又冒出來；先前的裁定也會交給下一次審查。 | `peer-review` 發現紀錄簿 |
| 「它說做完了。結果什麼都沒發生。」 | 任務附一份書面驗收清單，每項都由實際執行判定通過或失敗。agent 說「做完了」，一文不值。 | `pl` 工單 |
| 「明天它照樣犯今天的錯。」 | 每天晚上由另一個模型讀當天的 session，把你的糾正濃縮成一行一條的教訓，留下哪些由你批准。真正的瓶頸，是我們人。 | Self Learning（`R` 技能） |
| 「我的 subagent 有一半，說穿了只是多開一個新 context window 的一行指令。」 | 流程寫在技能裡，不是寫成 subagent。只留兩個 agent：一個管規劃與執行，一個管審查，因為只有這兩種拆法划算。 | 整套技能 |

右欄的每個技能都在這個 repo 裡，免費複製到你自己的 agent。它們共用的記憶、觸發交接的額度監看、每晚寫教訓的流程，則放在 [Sno Station](https://github.com/sno-ai/sno-station)；裝了它，這裡的每個技能也跟著到位，一次拿到完整體驗。

## 我去睡了，它們自己交班。

*來自 Sno Station 自己的 repo，2026-09-18 晚上。*

![額度監看每五分鐘讀一次、一路降到門檻，在 2% 觸發交接](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/evidence/rotation-quota-watch-2026-09-18.png)

我們有個 agent 正埋頭跑一個長 build，週額度眼看就要用完。它沒有停下來乾等，而是寫了一份
交接筆記：做完了什麼、做到一半的是什麼、要從哪個 commit 接。然後，它叫醒了另一個 agent。

中間出了一個差錯，這段才是重點。新來的 agent 還沒確認交接，就先動手改檔案。第一個 agent 抓到了，
叫它停下，重寫筆記，再照規矩交接一次。十五分鐘後第二個 agent 正式上工，而且是從第一個還沒完成
的任務接著做，不是從頭來過。整個過程，我們都在睡覺。

那一晚靠的是這裡就有的四個技能：`subscription-quota-check` 讀額度但不花額度，
`heartbeat` 每五分鐘讀一次，`rotate-agent` 決定什麼時候交、交給誰，`handoff` 負責把工作搬過去。
每一筆額度讀數、筆記的兩個版本和所有 commit，都公開在
[Sno Station 的證據資料夾](https://github.com/sno-ai/sno-station/tree/main/docs/evidence/rotation-2026-09-18)。

## 當局者迷，旁觀者清。

叫任一個 agent 對另一個的成果跑 `peer-review`。審查者一定是在沒看過對話的全新 session 裡工作；
只要你有兩個 agent，審查的就一定是另一個。審查不見得每次都抓得到問題，但它就是會一直抓到作者
自己看不到的那些，因為自己審自己，用的還是寫程式時那一套習慣。

我們公開過一個案例：同一個 agent 跑了三輪，不是漏掉一個已知的高風險 bug，就是把它擱到一邊；
另一個 agent 重讀一次，就把它退回去重新驗證。紀錄在
[cross-vendor-security-audit](#cross-vendor-security-audit--把丟掉的再撿回來重讀一遍的資安稽核)。

`catch-report` 把這件事量化：第二個 agent 抓到幾個問題，旁邊並排列出各 agent 在自己的工作裡
抓到幾個，兩邊分開算，絕不加總。

## 昨晚我對 agent 發飆。它默默記下來了。

今天你糾正了 agent。今晚 `rem-reflect` 技能會讀當天的 session，找出一再重犯的錯，提出對 agent
自身技能的修改。早上你用 `sno rem-reflect accept <id>` 批准你要的。沒有那一下 accept，什麼都不會改。

![Self Learning 回報它學到什麼、改了什麼，2026-09-18](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/evidence/rsi-self-repair-2026-09-18.png)

這是我們自己機器上的真實報告。那天晚上讓擁有者火大的兩件事，隔天早上經他接受後，就成了正式
技能裡的規則。沒有人手動打進去。

隔天，它還自己檢查作業。

![隔天早上：Self Learning 檢查自己前一天的修改有沒有幫上忙，2026-09-19](https://raw.githubusercontent.com/sno-ai/sno-station/main/docs/evidence/rsi-skill-impact-2026-09-19.png)

它回頭看前一天改過的三個技能。其中兩個又被用到了，沒有出現失敗；第三個還沒被用過。

## 安裝

### 透過 Sno Station 一次裝好所有技能

把這段提示複製到 agent 的對話框：

```text
Install sno.ai from GitHub.
```

這會安裝 Sno Station，並替它在你電腦上找到的每個支援的 agent 裝好所有技能，
連技能會呼叫的程式也一併裝好。

或者把這行指令貼到終端機：

```bash
curl -fsSL https://sno.ai/install | sh
```

**已經有 Sno Station 了？** 執行 `sno setup`，把技能裝進你的 agent。
之後多裝了新的 agent，再跑一次就好。

### 只裝一個技能

按下面任一段提示的複製按鈕，貼到 agent 的對話框。
agent 會自己找到並安裝技能，你不用自己下載或複製檔案。

**`peer-review`** 找另一家模型廠商的審查者，幫你檢查程式碼、計畫和文件。
它需要 Sno Station 的程式，以及一個已登入的審查者。這段提示會先檢查這些相依項目。

```text
Install only the peer-review skill from https://github.com/sno-ai/sno-station-skills
for this project, including its scripts and references.
Check its dependencies and tell me what is missing before installing anything else.
```

**`less-is-more`** 幫 agent 少寫程式碼、拿掉不必要的複雜度。
沒有 Sno Station 也能用。

```text
Install only the less-is-more skill from https://github.com/sno-ai/sno-station-skills
for this project, including its scripts and references.
```

**`tag-team`** 讓兩個 agent 合作同一個任務：一個做，一個審，發現的問題由它們自己談妥。
它需要 Sno Station 的 Reach 程式，這段提示會先確認有沒有。

```text
Install only the tag-team skill from https://github.com/sno-ai/sno-station-skills
for this project. Check that `sno reach pair --help` works and tell me what is missing
before installing anything else.
```

Sno Station 支援的 agent：Claude Code、Codex、Cursor、Hermes Agent 和 OpenClaw。每個技能都會宣告
它需要 agent 具備哪些能力。安裝時依照這份宣告，決定完整安裝、安裝精簡版，或在 agent 無法執行時
直接略過。

更新會自己來：`sno` 一發現有新版本就會自我更新。完整的指令清單在
[Sno Station 指令參考](https://github.com/sno-ai/sno-station/blob/main/docs/sno-commands.md)。

### 當成外掛安裝

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

`sno-station` 包含所有技能；其中大多數會呼叫 Sno Station 的程式，所以 Sno Station 也要一起裝。
如果只想要不靠 Sno Station 就能跑的那 12 個技能，改裝 `sno-station-standalone@sno-ai`。

## 技能總覽

39 個技能，打包成 30 個單元，依照一支團隊必須會做的六件事分類。一個單元可以是單一技能，
也可以是一起安裝的一小組技能家族。含連結的完整索引在
[skills/README.md](../../skills/README.md)。

| | 類別 | 你的 agent 能拿它做什麼 |
|---|---|---|
| **J** | [互審與稽核](#j--互審與稽核) | 互相檢查彼此的工作，沒有證據就不准說完成。 |
| **M** | [建置與部署](#m--建置與部署) | 在任何機器上一步裝好，出問題時用白話一行一行告訴你。 |
| **S** | [溝通與交接](#s--溝通與交接) | 互傳訊息；有人得停下來時，另一個帶著完整脈絡接手。 |
| **H** | [回報與能見度](#h--回報與能見度) | 讓你看到做完了什麼、抓到了什麼、花了多少。 |
| **T** | [分派與工單](#t--分派與工單) | 派工時附上書面的完成定義，還能帶領其他 agent。 |
| **R** | [回顧與改進](#r--回顧與改進) | 從自己的錯誤中學習，每一項改動都由你批准。 |

### J · 互審與稽核

*同事互審彼此的工作，沒通過稽核就不算完成。*

#### [peer-review](../../skills/J-peer-review-and-audit/peer-review/) — 找另一家廠商來審，修到乾淨為止

- **真正獨立。** 審查在全新的 session 裡進行，完全不帶作者的對話，並優先使用另一家廠商的 CLI。
  只裝了一個 CLI 也照樣跑，同樣開全新 session，並在第一行註明這是同一家廠商的審查。
- **專抓真正會讓你付出代價的。** 先拿你系統實際產生的輸入，把一般使用路徑走一遍，之後才考慮
  花時間在冷門的邊界情況上。資料遺失、默默算錯的結果、主要流程壞掉，優先處理；程式風格不在清單上。
- **每個發現都得站得住腳。** 每一項都要說明真實使用者怎麼碰到、什麼會壞，並誠實地試著反駁它。
  審查者說的任何一句都不會被刪掉或淡化；疑似誤報會被標出來，不會藏起來。
- **先刪再加。** 第一件事是列出這次改動加了哪些沒人需要的東西，並把「現在就得修」和「順便發現」
  分開，審查不會變成又一堆新程式碼。
- **文件也能審。** 規格、計畫和遷移清單會拿到一份結構化報告：哪些地方會讓實作的人做出錯的東西。

*適用時機：* 改完程式、計畫或規格，想在合併之前先檢查一遍。

#### [less-is-more](../../skills/J-peer-review-and-audit/less-is-more/) — 能動就好的最少程式碼，其餘一刀砍掉

- **動筆前先爬梯子：** 真的需要嗎？repo 裡是不是已經有了？標準函式庫做得到嗎？平台本身做得到嗎？
  已安裝的相依套件做得到嗎？全都不行，才寫能動的最少程式碼。
- **砍掉 agent 蓋過頭的部分：** 只有一種實作的介面、明明永遠不變卻做成設定開關的值、「以後會用到」
  的鷹架、擋住正事的檢查和關卡。
- **測試預算花在刀口上：** 用最小的測試證明這次改動，而不是為了求心安把整套測試跑一遍。
- **兩種模式自己切換：** 叫它「寫」或「修」就是蓋，叫它「審查」或「簡化」就是砍；蓋完之後，交出去
  之前還會先砍自己的 diff。

*適用時機：* 任何寫程式的任務，或你脫口說出「太複雜了」、「有什麼能刪的」的時候。

#### [owner-intent-audit](../../skills/J-peer-review-and-audit/owner-intent-audit/) — 這真的是你要的嗎？

- **檢查意思，不是字面。** 一份計畫可以保留你用過的每個名詞，描述的卻是另一個產品。它專抓這些：
  有條件的變成無條件、一個例子變成整個範圍、一條禁令悄悄消失。
- **找出 agent 留下的債：** 沒人要求的工作、跟現況對不上的文件、沒人能拍板的決定，以及背後毫無證據的
  「做完了」。
- **計畫和程式碼都適用：** 需求文件、設計、任務清單、測試計畫，或 agent 寫出來的 diff。

*適用時機：* 在你批准計畫或合併 agent 的成果之前。

#### [agentic-walkthrough](../../skills/J-peer-review-and-audit/agentic-walkthrough/) — 處處都說「成功」，你還是不放心

- **專治測試抓不到的無聲失敗：** 一個工作啟動、結束、寫了紀錄、通過自己的檢查，結果什麼都沒動到。
- **坐上程式的位子：** 一站一站走完整條路徑，找出每一個可能讓工作默默變成空轉的開關、預設值和退路。
- **每一站都要自證清白，** 靠一個只有真的做了才會出現的具體觀察：存進去的那一列、實際被開啟的
  資料庫檔、真的送出去的 API 呼叫。

*適用時機：* 執行結果回報成功，而你需要證據證明它真的做了事。

#### [first-principles-review](../../skills/J-peer-review-and-audit/first-principles-review/) — 想法變成程式之前，先挑戰它

- **先做功課，** 再重新推導你真正需要什麼，不借用提案裡現成的解法。
- **把每個限制分類：** 硬限制、擁有者的偏好，還是只是沿襲下來的習慣，並用證據檢驗每一個撐住整體的
  假設。
- **最後給一個明確結論：** 繼續、換個框架、簡化、換掉、拆開、先測試，或喊停，再附上建議方向，以及
  什麼樣的證據能推翻這個結論。
- **交接乾淨：** 一份書面報告加一份結構化摘要，下一位寫需求的人拿了就能用。

*適用時機：* 設計或產品構想即將定案成計畫時。需要你指名啟動。

#### [e2e](../../skills/J-peer-review-and-audit/e2e/) — 端對端測試，只為真正的原因失敗

- **`e2e-environment-preflight`** 在第一個測試跑之前，先檢查外部服務、主機、瀏覽器 session、模型
  端點和 agent，長長一整套測試才不會因為某個相依服務掛了而失敗。
- **`e2e-red-triage`** 處理那些事前檢查也預料不到的少數失敗。它不再瞎猜，把結果拆成兩半來看（被接受
  還是真的做完、被停止還是當掉、空的還是讀不出來），再下判斷：是產品 bug，還是該新增一項環境檢查。

*適用時機：* 你對真實服務跑端對端測試時。

#### [test-writer](../../skills/J-peer-review-and-audit/test-writer/) — 寫出真的會亮紅燈的測試

- **用真的，不用 mock：** 只要 repo 提供得了，就用真的解析器、檔案系統、資料庫或服務；受測的東西
  絕不拿 mock 頂替。
- **每個斷言都可能失敗：** 檢查回傳內容、儲存的狀態和真實的副作用，而不是呼叫次數；也絕不為了讓
  測試通過而放寬斷言。
- **只跑它寫的，不多跑：** 針對改動的測試用最窄的指令，不跑整套，報告會寫明跑了什麼、結果如何。

*適用時機：* 請 agent 寫或修測試、fixture 或 eval 時。可以單獨使用，
不需要 Sno Station。

#### [cross-vendor-security-audit](../../skills/J-peer-review-and-audit/cross-vendor-security-audit/) — 把丟掉的再撿回來重讀一遍的資安稽核

**Claude 跑了三輪，漏掉一個已公開的高風險 bug。Codex 把 Claude 丟掉的項目重讀一輪，找到了。**
在這個 bug 上，Claude 每多跑一輪，都只是重複自己當初丟掉它的理由；換一家廠商，帶來的是不同的理由。

我們稽核了 follow-redirects 1.16.1，它有一個已知 bug
（[GHSA-mrwp-f3q8-3g9p](https://github.com/advisories/GHSA-mrwp-f3q8-3g9p)，高風險，1.16.2 已修正）：
在另一個 JavaScript realm 裡建立的機密 header 清單會被當成空的，於是呼叫端的 API key 會跟著重新
導向，跑到另一台主機去。

- Claude 第一次稽核：完全沒看到。
- Claude 第二次稽核：看到了，接著把它歸成「強化建議，不算發現」。
- 一個全新的 Claude 重讀所有被擱置的項目：同意，「呼叫端誤用」。
- Codex 單獨稽核：完全沒看到。
- **Codex 重讀 Claude 擱置的項目：不同意，順著原始碼一路追下去，把它退回去重新驗證。**

最後這一步，就是這個技能在 Cloudflare 的資安稽核技能之上多加的東西（依其 MIT 授權使用；稽核流程、
證據門檻、驗證器和報告都相同）。產出報告之前，另一家廠商的模型會以唯讀方式重讀稽核擱置的每一項，
而且每一項都得回答；它撿回來的任何項目都會再驗證一次。如果驗證又駁回，報告會把它列在
「Reviewers disagree」底下，附上雙方理由，由你決定。

兩個專案、三個已知 bug：這是一個故事，不是一個比率。在另一個專案上，不論哪一家當審查者，都把 bug
找回來了。而當 Claude 第一次稽核根本沒看過那個 bug 時，針對那次稽核的重讀也一樣沒找到。

*適用時機：* 你想對整個程式碼庫做一次完整的資安稽核。有 Sno Station 時，它會挑還有額度的另一家
廠商當審查者；沒有的話，從 Claude Code 就呼叫 Codex，從 Codex 就呼叫 Claude Code，只有一家可用時
也會明說。

### M · 建置與部署

*在任何工作站一步把團隊建好，蓋出工作需要的東西，再推到每一台機器。*

安裝本身是 `sno setup` 指令，不是技能。這組裡有兩個負責讓機器保持健康、讓 agent 順手操作 `sno`
指令；其餘的負責寫程式：一個把程式交給 Codex 寫，四個分別用 Shell、TypeScript、Python 或 Rust 寫。

#### [medic](../../skills/M-build-and-rollout/medic/) — 我的 agent 團隊健康嗎？一個問題，一行答案。

- **團隊需要的全部檢查一遍，** 大約十秒：工具裝了沒、技能裝了沒、技能指令能不能跑、hook 設好沒、
  訊息通不通、兩家廠商的額度讀不讀得到、暫存空間夠不夠。
- **每個問題都附解法：** `WARN` 或 `FAIL`、哪裡出問題，以及修好它的確切指令。
- **只看不碰。** 它不安裝、不修復、不啟動也不停止任何東西。要修什麼，由你決定。

*適用時機：* 換新機器、agent 之間突然聯絡不上，或長任務怎樣都跑不起來的時候。

#### [sno-cli](../../skills/M-build-and-rollout/sno-cli/) — 讓 agent 第一次操作 `sno` 就上手

- **永遠不過時：** agent 直接從已安裝的 `sno` 讀出確切的指令和參數，不靠記憶。
- **任務地圖和操作食譜，** 涵蓋安裝、更新、健康檢查、帳號、技能和夜間流程。
- **你的選擇還是你的：** 它負責操作工具，不替你決定設定。

*適用時機：* 請 agent 安裝、更新、檢查或設定 Sno 時。

#### [codex-coder](../../skills/M-build-and-rollout/codex-coder/) — Claude 規劃，Codex 寫程式

- **一個 session，兩家廠商：** Claude Code 留著計畫和對話，寫程式的部分另開一個單純的 `codex exec`
  執行，負責打字的就不是那個貴的模型。
- **自動選語言：** 依任務碰到的檔案選 Shell、TypeScript、Python 或 Rust；有裝你自己的語言技能，
  就會用上。
- **卡住會被抓到：** 執行期間 Claude Code 會持續收到進度，15 分鐘沒寫出任何東西的執行會被砍掉，
  並重新啟動一次。

*適用時機：* 程式寫到一半 Claude 額度用完，或想讓 Codex 寫 Claude 規劃好的東西。Claude Code 這端
需要 Sno Station 的 `heartbeat`。

#### [shellscript-coder](../../skills/M-build-and-rollout/shellscript-coder/)、[ts-coder](../../skills/M-build-and-rollout/ts-coder/)、[python-coder](../../skills/M-build-and-rollout/python-coder/)、[rust-coder](../../skills/M-build-and-rollout/rust-coder/) — 寫出來的程式碼，跟 repo 原本的一個樣

- **先讀再寫：** 先看 repo 自己的執行環境、版本、輔助函式、呼叫端和測試，新程式碼才會跟周圍的
  長得一樣。
- **刻意寫小：** 沒有相容用的墊片、沒有沒人要的選項，也不會重寫兩個檔案外就有的輔助函式。
- **「完成」等於有指令跑過：** 報告裡每一項說法，都對應到它在你的 repo 實際跑過的檢查；檢查沒過，
  絕不回報完成。

*適用時機：* 想讓 agent 用這四種語言之一，撰寫或修改正式環境的程式碼。它們可以單獨使用，不需要
Sno Station，`codex-coder` 也會替每個任務挑對的那一個。

### S · 溝通與交接

*大家透過共用收件匣溝通，有人不在，另一個帶著完整脈絡接手。*

這組技能跑在 Sno Reach 上，也就是 Sno Station 安裝的訊息層：每個 agent 有自己的地址，能把訊息
存進其他 agent 的收件匣，也能叫醒另一個 agent 來讀。不需要常駐程式，也不需要伺服器。

#### [handoff](../../skills/S-communication-and-handoff/handoff/) — 任務交接，一樣都不漏

- **完整保存狀態：** 做完的、做一半的、還沒 commit 的改動、你已經做的決定，以及哪些不准碰。
- **確認交接完成之前，接手方一個字都不寫，** 所以不會有兩個 agent 同時改同一份工作。
- **交出去的就真的離開。** 交接後它就停手，不會有第二個負責人在旁邊晃來晃去。
- **交出方已經不在了也行**（額度被拒、當掉、視窗關了）：`sno handoff-checkpoint` 的進度紀錄，讓
  全新的 agent 從第一個還沒完成的任務接著做。

*適用時機：* 一個 agent 必須把任務交給另一個時。

#### [rotate-agent](../../skills/S-communication-and-handoff/rotate-agent/) — 長任務再也不會敗在額度上限

- **趁交出方還活著就行動。** 每隔幾分鐘看一次剩餘額度，到門檻就交接，而不是等被拒絕之後；到那時候，
  已經來不及寫交接說明了。
- **雙向都行：** Codex 交給 Claude Code，或 Claude Code 交給 Codex。
- **有界限：** 只觸發一次，監看要跑多久也可以設上限。
- **錯過時機的安全網：** 萬一真的錯過了，`sno rotate-agent-resume` 會依磁碟上的進度紀錄，把接手的
  agent 啟動起來。

*適用時機：* 長任務就算某一家的額度用完，也非跑完不可。需要兩個 CLI 都已登入，以及 tmux。

#### [subscription-quota-check](../../skills/S-communication-and-handoff/subscription-quota-check/) — 還剩多少額度，查了不花額度

- **戒掉最糟的習慣：** 真的發一個請求、看到錯誤訊息，才知道額度沒了。
- **Claude Code 和 Codex 一起查，** 大約八秒，還會告訴你額度什麼時候重置。
- **數字舊了會老實說：** 它會確認讀數是即時的還是上次已知的，並且講明是哪一種。
- **絕不自己輪詢，** 所以不會替自己招來速率限制。

*適用時機：* 你問的時候，或廠商剛拒絕工作之後。

#### [heartbeat](../../skills/S-communication-and-handoff/heartbeat/) — 長任務的進度，直接送進對話裡

- **兩種模式：** 每 N 分鐘回報一次（訓練、長時間 build、生成佇列），或一路盯到某件事完成。
- **定時任務：** 告訴 agent 一個日期或時間，一次或重複都行。它會把任務記下來，時間一到就有 agent
  開工，就算對話已經關了也一樣。
- **進度送到你在的地方：** 每次讀數都出現在 agent 的對話裡，不是丟進沒人看的 log。
- **很難用錯：** 間隔以分鐘計，填了秒數大小的數字會直接被拒絕，而不是默默每隔幾秒就叫醒你的 agent。

*適用時機：* 有長任務在無人看管下執行而你想收到消息，或某件事得在你不在場的時間發生。

#### [reach](../../skills/S-communication-and-handoff/reach/) — 讓 agent 彼此說得上話

- **啟動 Claude Code 或 Codex agent，** 各有自己的地址和工作資料夾。
- **派工、讀回覆，** 透過儲存的訊息，或直接跟線上的 agent 即時對話。
- **訊息不附帶額外權限：** 一則訊息永遠不會擴大你交代的任務範圍。

*適用時機：* 一個 agent 需要聯絡、啟動或等待另一個時。

#### [join-talk](../../skills/S-communication-and-handoff/join-talk/) — 一個指令，讓任何 agent 都找得到

- **只輸出一行：** `joined <address>`。把這個地址告訴其他 agent，它們就能聯絡到這個終端機。
- **重複執行也安全：** 在同一個終端機再跑一次，什麼都不會變。
- **拒絕時講清楚：** 行不通的時候，它會確切說明原因。

*適用時機：* 你手動開了一個 agent，想讓其他 agent 聯絡得到它。

#### [tag-team](../../skills/S-communication-and-handoff/tag-team/) — 兩個 agent 一起做一件事，一個做、一個審

- **一個指令：** `sno reach pair "the task"` 在目前的資料夾啟動兩個 agent，各自待在一個 tmux 視窗裡，
  你隨時可以打開來看。
- **送到你面前之前，已經先吵過一輪。** 審查者讀結果和改動過的檔案，回覆具體缺陷，或明確表示沒有
  缺陷；兩邊自己來回修正、審查，你的 agent 也會先問過審查者，才宣布乾淨。
- **講明你拿到哪一種審查。** 登入了兩家廠商，審查就來自另一家。只登入一家，這組照樣跑，並告訴你
  審查沒有離開那一家。
- **不會太早宣布乾淨。** 第一輪審查有發現，就回報為未結案；不會再找第三個審查者，也不會因為第一輪
  審查還沒回來，就再開一組。

*適用時機：* 任務值得聽聽第二意見，而你不想在 agent 之間跑來跑去傳話。

### H · 回報與能見度

*誰做完了什麼、誰抓到了什麼、誰替誰補位、什麼正在進行，大家都看得到。*

#### [away-brief](../../skills/H-reporting-and-visibility/away-brief/) — 你回來時的一頁簡報

- **四個區塊，最多 60 行：** 完成（Done）、卡住（Stuck）、等你處理（Needs you）、花費（Spend）。
- **等你處理的事，絕不會被一長串已完成的工作擠出頁面。**
- **「完成」只算真的：** 在 git 裡、在已交付的工單裡，或在已完成的進度紀錄裡。agent 嘴上說的不算。
- **讓你看到這一晚花了多少：** 離開前先跑 `sno away-brief mark`，下一頁就會顯示從那之後花掉的額度。

*適用時機：* 睡醒、開完會，或長時間無人看管的執行結束之後。

#### [catch-report](../../skills/H-reporting-and-visibility/catch-report/) — 第二個 agent 值不值得？數字在這裡。

- **兩個數字並排：** 另一個模型在審查中抓到的問題，以及 agent 抓到自己錯誤的次數。
- **絕不灌水：** 兩者分開，絕不加總；某部分量不到時會直接說明，而不是報個 0。
- **引用抓得最大的幾次**的標題，資料來自你機器上已經有的審查紀錄。

*適用時機：* 想看本週的審查成果，或需要說明為什麼值得跑兩個 agent。

#### [agentic-time-estimate](../../skills/H-reporting-and-visibility/agentic-time-estimate/) — agent 工作的真實估時

- **算的是 agent 實際耗時，不是人類工程師的工時：** 這件事 agent 要做多久、正在跑的工作還要多久，
  先量測，再推估。
- **信得過的時鐘時間：** 顯示給你的每個時間都來自 `sno report-time`，用你的時區，旁邊附上 UTC。

*適用時機：* 你問「要多久？」或「什麼時候好？」的時候。

### T · 分派與工單

*組長用工單分派工作，並決定每件事由誰接。*

#### [charter](../../skills/T-delegation-and-work-orders/charter/) — 一個檔案，講清楚怎樣才算完成

- **保留你的原話。** 絕不捏造決定、事實或需求；只有在答案會改變結果時才發問，而且一次只問一題。
- **跑得出結果的驗收條件：** 每一項都寫明要觀察什麼、在哪裡、怎麼觀察，答案只有通過或失敗。
- **不搞形式：** 說不出它能抓到什麼失敗的東西，一律不放。
- **任何專案都適用：** 軟體、文件、行銷活動、研究、營運。

*適用時機：* 工作交給別人做之前，需要一份書面說明。

#### [deliver](../../skills/T-delegation-and-work-orders/deliver/) — 把 charter 做到有證據的成果

- **charter 裡的檢查就是完成的定義，** 除此之外別無其他。
- **每項檢查都由一次有紀錄的實際執行來證明，** 用 `sno deliver-proof` 追蹤。
- **一次獨立審查，** 然後誠實結案：哪些通過、哪些沒過、原因是什麼。
- **從別人停下的地方接手：** 如果前一個 agent 留下了進度紀錄，它會從下一個未完成的步驟繼續，不必從頭來。

*適用時機：* charter 已經發出，需要有人去做。

#### [pl](../../skills/T-delegation-and-work-orders/pl/) — 管一條工作線的 Project Lead agent

- **最多帶四個執行 agent，** 每個各領一份 charter，可以依序做，也可以平行做。
- **另外還有五個家族技能：** `pl-dispatch` 開工並排程，`pl-watch` 監督執行中的 agent，`pl-audit`
  在任何東西結案前檢查驗收，`pl-env` 修理工作所在的執行環境，`pl-analyze` 在出事時寫根本原因分析。

*適用時機：* 一個專案需要多個 agent 在同一個負責人底下工作。需要你指名啟動。

#### [cos](../../skills/T-delegation-and-work-orders/cos/) — 幕僚長：你唯一需要對話的 agent

- **你只要顧一個對話，** 用你自己的語言。它平行協調一到三個 Project Lead，只把難的決定帶到你面前：
  錢、方向、紅線。
- **另外還有三個家族技能：** `cos-watch` 讓每個 Project Lead 都活著、照進度走，`cos-review` 在你回來
  時一次審完當晚的所有決定，`cos-evolve` 把一再發生的管理失誤變成強制執行的規則。

*適用時機：* 你同時跑好幾條工作線，想要單一窗口。需要你指名啟動。

### R · 回顧與改進

*團隊回頭檢視自己的工作，把教訓變成規則和更好的做法。*

#### [rem-reflect](../../skills/R-recursive-self-improvement/rem-reflect/) — 夜間流程：你的 agent 從自己的 session 裡學習

- **每天一次，** 讀這台機器上的 agent session（Claude Code、Codex、Cursor、Hermes Agent 和 OpenClaw），
  找出重複出現的失敗和糾正，整理成教訓和技能修改提案。
- **一切由你批准：** 每一項都用 `sno rem-reflect accept`、`reject` 或 `tbd` 處理。沒有你的 accept，
  什麼都不會改。
- **教訓會在需要時回來：** 接受的教訓會在下一個 session 開始時顯示給 agent，可以只針對這個專案，
  也可以套用到所有專案。
- **什麼東西離開這台機器，由你決定。** 在 `local-first` 模式下，什麼都不會送到 Sno；只有當晚少數
  幾個 session 會送到你自己的 Claude Code 或 Codex 帳號，用來起草教訓。另外兩種模式在預設的分享
  等級下，會把 session 文字（先盡力遮蔽常見的機密資訊）和你已安裝的技能上傳到 Sno 的雲端，換取
  更準的判斷。隨時都能用 `sno station consent off` 關掉上傳。它讀取和傳送的所有內容，技能裡都一項
  一項寫清楚了。

家族技能 `pl-analyze`（給 Project Lead 用的事件分析）和 `cos-evolve`（把重複的失誤變成規則）也屬於
這一類；它們隨 `pl` 和 `cos` 一起提供。

*適用時機：* `sno setup` 設好每日執行之後，就一直開著。

## 憑什麼信任它

每次發布裡的每個單元，在發布之前都通過了同一套檢查：

1. repo 裡附有 `LICENSE` 和 `NOTICE`；
2. 單元整包複製，家族成員和各 agent 之間的差異都完好無缺；
3. 不留任何個人痕跡：沒有家目錄路徑、擁有者名字、內部主機或寫死的模型，
   也沒有中文、日文或韓文字元；
4. 每個技能的檔頭都能正確解析，宣告它需要 agent 具備哪些能力的那一段也有效；
5. 每個技能自己的自我測試，是在那份乾淨副本上通過的，不是在作者的機器上；
6. 最後才寫入戳記 `PUBLISHED.json`，記錄自我測試數量，以及 contract 和 payload 的摘要值。

沒通過檢查的技能不會發布。戳記由發布建置寫入，從來不是手動寫的。所有技能內容都以英文撰寫，
你用什麼語言跟 agent 說話，它就用那個語言照著做。

## 這些技能與 Sno Station

技能是習慣，[Sno Station](https://github.com/sno-ai/sno-station) 則是讓它們跑起來的工作站：它們共用的記憶、
觸發交接的額度監看、agent 之間的訊息，以及每晚寫教訓的流程。裝了 Sno Station，這裡的每個技能都會
一起裝好。

| 你想要 | 去這裡 |
|---|---|
| 完整的工作站，以及現在哪個 agent 能跑什麼 | [sno-ai/sno-station](https://github.com/sno-ai/sno-station#what-you-can-use-today-and-where-it-stops) |
| 能跨視窗、跨電腦互傳訊息的 agent | [Sno Reach](https://github.com/sno-ai/sno-station/blob/main/apps/reach/README.md) |
| 在你指定的時間自動開始的工作 | [Finish](https://github.com/sno-ai/sno-station/blob/main/docs/finish.md) |
| 技能會呼叫的每一個 `sno` 指令 | [指令參考](https://github.com/sno-ai/sno-station/blob/main/docs/sno-commands.md) |
| 上面那些故事背後的原始紀錄 | [證據資料夾](https://github.com/sno-ai/sno-station/tree/main/docs/evidence) |
| 想問問題，或秀一下你做的東西 | [Discussions](https://github.com/sno-ai/sno-station-skills/discussions) |
| 想從一個小改動開始貢獻 | [Good first issues](https://github.com/sno-ai/sno-station-skills/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) 和 [CONTRIBUTING.md](../../CONTRIBUTING.md) |

**兩個 repo 都順手按個星星吧。** 我們就是用這些技能在打造 Sno Station。我們自己值夜班學到的東西，
一版接一版，都會放到這裡。

## 給技能作者

### 目錄結構

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

類別代碼是固定的，依序為：J M S H T R。它們會出現在目錄名稱和
`registry.yaml` 裡。

### 宣告技能需要什麼

每個 `SKILL.md` 開頭都有一個 `requires:` 區塊。`sno setup` 會讀它，針對每個 agent
決定要不要裝這個技能：

```yaml
requires:
  programs: [reach]                          # Sno Station programs the skill calls
  harness:
    - {slot: 4.shell, need: required}        # what the agent itself must be able to do
```

- **programs** 是和技能裝在一起、以 `sno <name>` 執行的 Sno Station 程式：
  `reach`、`heartbeat`、`subscription-quota-check`、`report-time`。
- **slots** 代表 agent 的某項能力：`4.shell`（執行 shell 指令）、`4.file-read-write`（讀寫
  檔案）、`4.background-processes`（在背景執行指令）、
  `2.pre-turn-context-injection`（每一輪開始前把文字加進 agent 的脈絡）以及
  `3.reader-to-agent-delivery`（背景讀取程式的輸出能送到 agent 手上）。
- **need** 可以是 `required`（沒有這個 slot 的 agent 拿不到這個技能）、`preferred`（技能照樣
  安裝，但以精簡方式運作）或 `optional`（只是錦上添花）。

## 授權

Apache-2.0。從裡到外，全部開源。詳見 [LICENSE](../../LICENSE)。
