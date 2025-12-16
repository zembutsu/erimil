# Project Template v0.1.0 フィードバック

> Erimil開発時に気づいた課題メモ
> Date: 2025-12-13
> Updated: 2025-12-17 (S003 - State Snapshot, 役割分担, macOS 制約)

## 強み

- 「ゲームアナロジー」が直感的で秀逸
- PROJECT.mdをエントリーポイントにする設計が明確
- WORKFLOW.mdのAI協調開発モデルが実践的
- 規模別ドキュメント推奨マトリクスが親切

## 課題（v0.2.0向け）

| # | 課題 | 説明 |
|---|------|------|
| 1 | 重複 | `project-docs-methodology.md`にテンプレート例も含まれており、`templates/`と役割が被る。methodology説明とtemplatesは分離すべき |
| 2 | 欠落 | `CHANGELOG-template.md`がない |
| 3 | 欠落 | `LICENSE`への言及はあるがテンプレートなし |
| 4 | 不統一 | 「Template Information」の位置（末尾 vs 冒頭）が不統一 |
| 5 | ADR | docs/adr/構造のscaffoldがない |
| 6 | 使い方 | テンプレートをコピー後、置換すべき`{placeholder}`一覧があると親切 |

## 追加提案

- [ ] Quick Start用のシェルスクリプト（テンプレートコピー＆リネーム）
- [ ] .gitignore テンプレート
- [ ] GitHub Issue/PR テンプレート

---

## Phase 1 実践フィードバック (2025-12-13)

### 実際の使用パターン

| ドキュメント | 参照頻度 | 更新頻度 | 価値 |
|-------------|---------|---------|------|
| PROJECT.md | セッション開始時のみ | Phase完了時 | 高（ゴールが明確） |
| DESIGN.md | 判断時に参照 | セッション終了時 | **最高**（決定記録が残る） |
| ARCHITECTURE.md | ほぼ参照せず | Phase完了時のみ | 中（大規模変更時に有用） |
| WORKFLOW.md | 問題発生時 | セッション終了時 | 高（学びが蓄積） |

### 発見した課題

| # | 課題 | 発見状況 | 対応 |
|---|------|---------|------|
| 7 | 更新タイミング不明 | いつどのドキュメントを更新すべきか迷った | Document Lifecycle セクションを WORKFLOW.md に追加 |
| 8 | 実装中は更新不可能 | コード書きながらドキュメント更新は非現実的 | 「実装中は後回し、終了時にまとめて記録」をルール化 |
| 9 | ARCHITECTURE.md の位置づけ | 開発中ほぼ見なかった | 大規模プロジェクト or 構造変更時のみ更新に限定 |

### 追加した運用ルール

WORKFLOW.md に「Document Lifecycle」セクションを追加：

1. **Phase Start Checklist** - 開始時に読むドキュメント
2. **During Development** - 状況別アクション表
3. **Phase End Checklist** - 終了時に更新するドキュメント

### v0.2.0 への提案

1. **Document Lifecycle を標準化**
   - テンプレートにデフォルトで含める
   - プロジェクト規模別にカスタマイズ可能に

2. **DESIGN.md を中心に据える**
   - 最も価値が高い
   - Decision テンプレートの充実

3. **ARCHITECTURE.md はオプショナルに**
   - 小規模プロジェクトでは不要な場合も
   - 「構造が複雑になったら作成」でも可

4. **Development Principles セクションを標準化**
   - WORKFLOW.md に「学んだこと」を蓄積する場所として

---

## Phase 2.1 実践フィードバック (2025-12-14)

### 発生した問題

**「フォルダ復元」機能に最も時間がかかった**

想定: 簡単な機能（UserDefaults にパス保存 → 起動時復元）

実際の流れ:
```
1. UserDefaults に保存 → OK
2. 起動時に読み取り → 空（なぜ？）
3. デバッグログ追加 → 保存後は読める、再起動後は消える
4. Bundle ID 確認 → 正しい
5. サンドボックス制約に気づく → children count: 0
6. Security-Scoped Bookmarks が必要と判明
7. Entitlements 設定が必要と判明
8. Xcode で Entitlements の場所がわからない → スクリーンショット往復
9. UserDefaults が Xcode debug で永続化されない問題に遭遇
10. ファイルベース保存（Application Support）に変更 → 解決
```

### 根本原因分析

**Bebop ドキュメントに欠けていたもの:**

| 欠落 | 影響 |
|------|------|
| **Technical Constraints** | AI がプラットフォーム制約を知らず、間違ったアプローチから開始 |
| **Development Setup** | Xcode 設定手順の説明に時間を浪費 |
| **Technical Risks in Issue** | 「簡単そう」な機能の罠を事前識別できず |
| **Troubleshooting** | 問題発生時の解決パターンがなかった |

### 新規課題（v0.2.0 向け）

| # | 課題 | 説明 | 優先度 |
|---|------|------|--------|
| 10 | **Technical Constraints 欠落** | プラットフォーム固有制約の記載場所がない | **高** |
| 11 | **Development Setup 欠落** | IDE/環境セットアップ手順がない | **高** |
| 12 | **Technical Risks in Issue** | Issue テンプレートに技術リスク欄がない | 中 |
| 13 | **Troubleshooting 欠落** | よくある問題と解決策の記載場所がない | 中 |

### 実施した対策

- [x] ARCHITECTURE.md に Technical Constraints セクション追加
- [x] ARCHITECTURE.md に Development Setup セクション追加
- [x] ARCHITECTURE.md に Troubleshooting セクション追加
- [x] LOGBOOK.md に **Handoff Bridge** セクション追加（セッション間の引き継ぎ）
- [x] WORKFLOW.md に **Step Back Before Diving Deeper** 原則追加
- [x] WORKFLOW.md の Session Checklist に Handoff Bridge 確認を追加
- [ ] Issue テンプレートに Technical Risks セクション追加（TODO）

### 学び

**1. 「設計」と「制約」は別物**
- Bebop 方式は設計議論（DESIGN.md）に強い
- しかしプラットフォーム制約のドキュメント化が欠けていた
- → ARCHITECTURE.md に制約セクションを標準化すべき

**2. AI は知らない制約を推測できない**
- ドキュメントに書いてなければ間違ったアプローチから始める
- macOS サンドボックスの知識がなければ UserDefaults から始めるのは自然
- → プロジェクト固有の制約は明示的にドキュメント化

**3. 「簡単そう」な機能こそ危険**
- 実装難易度と実際の時間が乖離しやすい
- 技術リスクの事前チェックリストが必要
- → Issue テンプレートに Technical Risks を追加

**4. Xcode 操作は言葉だけでは伝わらない**
- 「Build Settings を開いて...」は曖昧
- スクリーンショット + ステップバイステップが必要
- → Development Setup に具体的な手順を記載

**5. 近視眼的な修正より俯瞰**
- 小さな修正を繰り返してかえって時間がかかった
- 2-3回試して解決しなければ、立ち戻って全体を見るべき
- → WORKFLOW.md に "Step Back Before Diving Deeper" 原則を追加

**6. セッション間の引き継ぎが必要**
- 学びや注意点が次のセッションに伝わらない
- LOGBOOK.md に引き継ぎセクションを標準化
- → LOGBOOK.md テンプレートに **Handoff Bridge** を追加

### v0.2.0 への追加提案

1. **ARCHITECTURE.md テンプレートに以下を追加**
   - Technical Constraints（プラットフォーム制約）
   - Development Setup（環境セットアップ）
   - Troubleshooting（よくある問題）

2. **Issue テンプレートに Technical Risks セクション追加**
   ```markdown
   ## Technical Risks
   - [ ] サンドボックス/権限制約あり？
   - [ ] プラットフォーム固有 API 使用？
   - [ ] 非同期処理の race condition は？
   - [ ] 外部依存追加が必要？
   ```

3. **Platform Checklist の標準化**
   - macOS: サンドボックス、Entitlements、公証
   - iOS: App Store ガイドライン、プライバシー
   - Web: CORS、CSP、ブラウザ互換性

4. **LOGBOOK.md テンプレートに Handoff Bridge セクション追加**
   ```markdown
   ### 🌉 Handoff Bridge
   - 次のセッションへの引き継ぎ
   - 注意点、確認すべきこと
   ```
   - セッション間で学びや注意点を明示的に引き継ぐ
   - 文脈と理由が同じファイル内で完結

5. **WORKFLOW.md に Step Back 原則を標準化**
   ```markdown
   ### Step Back Before Diving Deeper
   When small fixes aren't working after 2-3 attempts:
   1. Stop iterating
   2. Ask "what's fundamentally different?"
   3. Question assumptions
   4. Check platform constraints
   5. Search for standard patterns
   ```

6. **WORKFLOW.md Session Checklist に Handoff Bridge 確認を追加**
   ```markdown
   ### Session Start Checklist
   - [ ] Read LOGBOOK.md (latest entry) - Check Handoff Bridge
   - [ ] Check ARCHITECTURE.md Technical Constraints (if relevant)
   ```

---

## 実践から得られた重要なインサイト (2025-12-14)

Phase 2.1 セッション終了時の振り返りで発見した、Bebop 方式の次の進化に向けたアイデア。

### セッション管理の課題

**現状の問題**:
- セッション中に「今・誰が・何をしているか」の記録がない
- GitHub Issue 番号だけでは前後関係がわからない
- 複数セッションが並列になると追跡が破綻する

**発見のきっかけ**:
- Issue のクローズ確認時に「どれが完了でどれが未完了か」が曖昧だった
- #5（フルスクリーン）と #7（黒画面）の状態が混乱

### 提案: LOG#\<num\> によるセッショントラッキング

```
LOG#001: Phase 2.1 UX Improvements
├─ issues: [#2, #3, #4, #6]
├─ depends_on: []
├─ status: completed
└─ handoff: [LOG#002, LOG#003]

LOG#002: ★ Export          LOG#003: Bug fixes
├─ issues: [#11]           ├─ issues: [#5, #7]
├─ depends_on: [LOG#001]   ├─ depends_on: [LOG#001]
└─ ...                     └─ ...
```

**利点**:
- GitHub Issue（機能単位）と LOG#（セッション単位）の分離
- 依存関係の明示（depends_on, blocks）
- 並列作業の追跡可能

### 提案: Session Sheet（リアルタイム記録）

セッション中に「誰が・何を・どの Issue を」記録するフォーマット:

```markdown
| Time | Actor | Action | Issue | Status |
|------|-------|--------|-------|--------|
| 14:00 | Zem | Session start | - | - |
| 14:05 | Claude | Propose approach | #5 | 🔄 |
```

**利点**:
- 判断の経緯が追える
- セッション終了時に LOGBOOK へ書き出しやすい
- 複数 Actor の協働が可視化

### 提案: Setlist Check（Issue 棚卸し）

セッション開始/終了時に GitHub Issues を確認するルーチン:
- Open Issues の状態確認
- 今日取り組む Issue の決定
- 終了時のステータス更新

**Bebop 用語**: Setlist（今日演奏する曲のリスト）

### 将来の発展: bebop CLI ツール

```bash
$ bebop start --issues "#5,#7"
→ LOG#002 created

$ bebop status
LOG#002 [active] - #5 ★Export, #7 Black screen

$ bebop graph
LOG#001 ──┬──→ LOG#002 (active)
          └──→ LOG#003 (pending)

$ bebop sync
→ GitHub Issues updated with LOG# references
```

### v0.2.0+ への提案

| 優先度 | 提案 | 説明 |
|--------|------|------|
| 高 | Setlist Check | Session 開始/終了時の Issue 確認ルーチン |
| 高 | Session Sheet テンプレート | リアルタイム記録フォーマット |
| 高 | Parking Lot 機構 | スコープ外話題の即時記録・後回しルール |
| 高 | 統一テンプレート | Issue / LOGBOOK のフォーマット固定（セッション内） |
| 高 | Auto-Judgment Scope | AI 自律動作領域の明示（typo, debug log, minor fix） |
| 中 | LOG#\<num\> 採番規則 | セッション単位のトラッキング |
| 中 | `ai-exp/` prefix | AI 実験的リポジトリの命名規則 |
| 低 | bebop CLI | 将来的な自動化ツール |

これらは「ソロ演奏」から「アンサンブル」への進化の布石となる。

### 追加提案: スコープ制御とAI自律性 (2025-12-14 夜)

Phase 2.1 セッション終了後のレビューで追加された提案。

**1. Parking Lot 機構**

セッション中にスコープ外の話題が出たとき：
- 即座に「Parked」としてマーク
- Issue / LOGBOOK / Later のいずれかに振り分け
- セッションのフォーカスに戻る

目的：コンテキスト肥大化防止、注意散漫防止

**2. 統一テンプレート**

- Issue テンプレート（Description, Context, Acceptance Criteria, Technical Notes, Related）
- LOGBOOK エントリテンプレート（セッション内固定、セッション間で進化）

**3. Auto-Judgment Scope**

AI/System が人間承認なしで実行できる操作：
- Typo 修正
- Debug ログ追加
- 軽微な bugfix（自明なもの）
- コードフォーマット

人間承認が必要な操作：
- 新機能
- 設計変更
- 依存関係変更

**リポジトリ命名規則**: `ai-exp/<n>` で AI 実験プロジェクトを明示

---

## Bebop 方式の本質的洞察 (2025-12-14)

Phase 2.1 セッション終了後の議論で見えてきた、Bebop 方式の本質と可能性。

### Human-AI 協働を超えて

Bebop 方式は AI 駆動開発の文脈で生まれたが、**人間だけの開発にも適用可能**。

| 観点 | Vibe Coding | SDD | AI駆動 | **Bebop** |
|------|-------------|-----|--------|-----------|
| 主導 | AI 任せ | 仕様 | AI | セッション参加者 |
| 記録 | なし | 事前設計 | ログ | LOGBOOK（資産化） |
| 進化 | なし | 計画的 | なし | 実践から自然発生 |
| 協調 | なし | 同期 | なし | Handoff Bridge |

### ジャズセッションのメタファー

```
ジャズセッション
├─ 誰でも参加できる（オープン）
├─ でも空気を読む（プロトコル）
├─ 得意なときだけソロを取る（スポット貢献）
├─ Trading で引き継ぐ（非同期協調）
└─ 全員がリーダーであり、フォロワー（自律分散）
```

**道場破り** ≠ **セッション参加**

OSS で見られる「空気を読まない PR」は道場破り。Bebop は Setlist Check でコンテキストを読み、Trading Notes で引き継ぐ。

### 従来モデルとの比較

| 観点 | スプリント | OSS (現状) | Bebop |
|------|-----------|-----------|-------|
| 時間単位 | 固定（2週間） | なし | セッション（可変） |
| 参加方法 | アサイン | PR 投げつけ | セッション参加 |
| 協調 | 毎日スタンドアップ | 非同期レビュー | Handoff Bridge |
| 文脈共有 | チケット | Issue コメント | LOGBOOK + LOG# |
| 空気 | 読まなくていい | 読めない | 読む（Setlist Check） |

### 新しい経済活動への示唆

```
従来の雇用
└─ 固定時間、固定場所、固定チーム

Bebop 的参加
├─ 時間があるときだけ（タイムシェア）
├─ 得意分野だけ（スキルマッチ）
├─ セッション単位で貢献（スポットワーク）
└─ LOG# で貢献が追跡可能（価値の可視化）
```

スポットワーク、ギグエコノミーの文脈で、**貢献の記録と文脈の継承** が可能になる。

### 自律分散制御との接続

```
ROS2 ノード          Bebop Actor
├─ 独立して動作       ├─ 独立してセッション
├─ トピックで通信     ├─ LOGBOOK/Handoff で通信
├─ 必要なときだけ購読  ├─ 関心のある Issue だけ参加
└─ 中央なし          └─ 中央なし
```

Bebop 方式は、ソフトウェア開発だけでなく、**自律分散システムの協調プロトコル** としても応用可能かもしれない。

### 重要な気づき

1. **実践から生まれた** - 誰かの真似ではなく、手を動かした結果
2. **再現性がある** - Erimil 固有ではなく、他プロジェクトに適用可能
3. **Human-AI-Human すべてに適用** - 協働の形態を選ばない
4. **方法論自体が進化する** - TEMPLATE-FEEDBACK がその証拠

---

## S003 実践フィードバック (2025-12-17)

Phase 2.2 実装（Slide Mode）に集中したセッション。fullScreenCover() が iOS 専用と判明し、大きなアーキテクチャ変更が必要だった。主な成果：機能実装 + プロセス改善。

### 発見

| # | 課題 | 説明 |
|---|------|------|
| 21 | **プラットフォーム対応が常に文書化されていない** | fullScreenCover() は iOS 専用だが多くのチュートリアルで言及なし。Apple 公式ドキュメントで常に確認が必要。 |
| 22 | **コンテキスト喪失は双方向** | Claude（コンテキストウィンドウ圧縮）も Human（中断、タスク切り替え）もコンテキストを失う。両方に緩和策が必要。 |
| 23 | **役割分担は動的であるべき** | 「Claude は X、Human は Y」という固定ではなく「このタスクに対して誰がより速く、より正確か？」 |
| 24 | **Park→Issue 変換の形式化が必要** | Park された項目は溜まるが Issue への変換がアドホック。明示的な分類と変換フローが必要。 |

### 新規特定課題

| # | 課題 | 説明 | 優先度 |
|---|------|------|--------|
| 25 | **State Snapshot 機構が必要** | 長いセッションでコンテキスト喪失；定期的な状態キャプチャが必要 | 高 |
| 26 | **Park メタデータ欠落** | 誰が、いつ、どの文脈で park したか追跡されていない | 高 |
| 27 | **macOS 固有パターン未文書化** | NSWindow クリーンアップ、フルスクリーン制約が WORKFLOW.md にない | 中 |

### 実施した対策

- [x] State Snapshot Mechanism を WORKFLOW.md に追加
- [x] Park Metadata 形式を WORKFLOW.md に追加
- [x] Park→Issue Conversion フローを WORKFLOW.md に追加
- [x] macOS Fullscreen Constraints を WORKFLOW.md Development Principles に追加
- [x] NSWindow Cleanup Pattern を WORKFLOW.md Development Principles に追加
- [x] Build Cache Awareness を WORKFLOW.md Development Principles に追加
- [x] セッション park から 5 件の新規 GitHub Issues (#14-#18) を作成

### 重要な学び: State Snapshot Mechanism

**問題**: 以下によりコンテキストが失われる：
- Claude のコンテキストウィンドウ圧縮（S003 で2回発生）
- Human の中断やタスク切り替え
- 多くのステップを含む長いセッション

**解決策**: ステップ境界で state snapshot を記録：

```markdown
## [STATE] S003 / Step 3 Complete / 05:35

### Position
- Phase: 2.2, Step: 3/4
- Branch: feature/5-quick-look-navigation

### Completed
- [x] Step 1: ImageViewerCore
- [x] Step 2: a/d navigation
- [x] Step 3: Slide Mode

### Current State
- Files modified: 4 files
- Key decision: D005 (NSWindow for fullscreen)

### Next
- Step 4: z/c favorite navigation
```

**将来の応用**: 並列処理の基盤（複数 Claude、Human+Claude 並行作業）。

### 重要な学び: タスク特性による役割分担

**観察**: 効果的な Human-AI コラボレーションには動的な役割分担が必要：

| タスク特性 | 適任 | 理由 |
|-----------|------|------|
| 依存関係の多い大規模ドキュメント | Claude | ファイル間の一貫性・正確性 |
| 公式ドキュメント参照・検証 | Claude | 体系的なチェック |
| 数行、依存関係1-2個 | Human | シンプルなタスクは早い |
| 複雑な判断が必要 | Human | 文脈と意図 |
| 反復的で正確さ重視 | Claude | 疲労なし、精度維持 |

**原則**: 「このタスクに対して誰がより速く、より正確か？」

これは固定的な役割ではなく動的配分。S003 で Human が Claude に大規模ドキュメント更新を明示的に依頼した理由：
- 相互依存のある多数のファイル
- ファイル間の一貫性が重要
- 相互参照の検証が必要

### 重要な学び: Park メタデータ

**変更前**: `[PARKED] Topic - Description`

**変更後**: `[PARKED/誰/セッション/文脈] Topic - Description`

例：
- `[PARKED/Claude/S003/Step4] 重複コード - goToPreviousFavorite が3箇所`
- `[PARKED/Human/S003] 機能アイデア - Grid-Preview 同期`

**利点**:
- 誰が提起したかわかる
- いつ提起されたかわかる
- どの文脈で観察されたかわかる
- セッション/プロジェクト横断的な学習が可能

### 重要な学び: Park→Issue 変換

セッション終了時に park 項目を分類：

| カテゴリ | アクション |
|---------|----------|
| コード品質 / リファクタ | → GitHub Issue (`refactor`, `ai-exp`) |
| 機能リクエスト | → GitHub Issue (`enhancement`) |
| バグ発見 | → GitHub Issue (`bug`) |
| パフォーマンス問題 | → GitHub Issue (`enhancement`, `performance`) |
| プロセス改善 | → WORKFLOW.md |
| 哲学 / 洞察 | → LOGBOOK.md |

**S003 結果**: 12 park 項目 → 5 Issues (#14-#18) + 3 WORKFLOW.md 追加 + 4 Later/LOGBOOK

### v0.2.0 への提案

1. **Session Sheet テンプレートに State Snapshot を追加**
   
   スナップショット形式とトリガーを追加：
   ```markdown
   ### [STATE] S{NNN} / Step {N} {Status} / {Timestamp}
   - Position: Phase X.Y, Step N/M
   - Completed: [list]
   - Current: [state]
   - Next: [action]
   ```

2. **WORKFLOW.md に役割分担ガイドラインを追加**
   
   セクション追加：
   ```markdown
   ### Dynamic Role Division
   
   特性に基づいてタスクを配分：
   | 特性 | 適任 |
   |------|------|
   | 大量、多依存関係 | Claude |
   | シンプル、依存1-2個 | Human |
   | ファイル間一貫性必要 | Claude |
   | 複雑な判断必要 | Human |
   ```

3. **WORKFLOW.md にプラットフォーム固有パターンを追加**
   
   macOS 固有セクション追加：
   - fullScreenCover() は iOS 専用
   - NSWindow クリーンアップパターン
   - ビルドキャッシュの認識

4. **Park メタデータを標準化**
   
   Parking Lot Mechanism 更新：
   ```markdown
   形式: [PARKED/誰/セッション/文脈] Topic - Description
   ```

---

## Licks Discovered (S003)

| # | タイプ | 内容 |
|---|--------|------|
| 12 | 🔧 技術 | fullScreenCover() は macOS で利用不可 - 常にプラットフォーム対応を確認 |
| 13 | 🔧 技術 | NSWindow クリーンアップ: contentView = nil → orderOut → close → nil 参照 |
| 14 | 🔧 技術 | シングルトンでビルドキャッシュ問題 - Clean Build (Cmd+Shift+K) で解決 |
| 15 | 📋 プロセス | State Snapshot 機構でステップ間のコンテキスト保持 |
| 16 | 📋 プロセス | Park メタデータ: [PARKED/誰/セッション/文脈] 形式で追跡性向上 |
| 17 | 📋 プロセス | セッション終了時の Park→Issue 変換フローとカテゴリ分類 |
| 18 | 🤝 協働 | タスク特性による役割分担（量、依存関係、一貫性要件） |
| 19 | 💡 洞察 | 「このタスクに対して誰がより速く、より正確か？」を配分原則に |
| 20 | 💡 洞察 | コンテキスト喪失は双方向 - AI も Human も緩和策が必要 |
