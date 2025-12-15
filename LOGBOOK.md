# LOGBOOK

> 航海日誌 - 判断・気づき・学びの記録
> 未知の海を進むための現在地確認

---

## 2025-12-14 (LOG#001: Phase 2.1 UX Improvements)

### 📍 Current Position
- Phase 2.1 完了（v0.3.0）
- Branch: feature/phase2.1-ux-improvements
- 実装: サムネサイズ、キャッシュ、キーボード、プレビュー、★/☆、フォルダ復元

### ⏱️ 時間配分の振り返り

| 機能 | 想定 | 実際 | 原因 |
|------|------|------|------|
| サムネサイズ | 短 | 短 | 既存パターン |
| ディスクキャッシュ | 中 | 中 | 設計議論あり |
| キーボードナビ | 短 | 短 | SwiftUI 標準 |
| Space プレビュー | 短 | 中 | 黒画面バグ |
| ★/☆ ハイブリッド | 中 | 中〜長 | 設計議論（価値あり） |
| **フォルダ復元** | **短** | **長** | **サンドボックス制約** |

→ 「簡単なはず」の機能に最も時間がかかった

### ⚓ Decisions
- **Hybrid Favorites Design** 採用（→ DESIGN.md Decision 14）
  - byContent + bySource の両方でトラッキング
  - ★（直接）= 保護対象、☆（継承）= 参照のみ
  - 理由: 蒸留ワークフローで「前回何を選んだか」を可視化
- **ファイルベース Bookmark 保存**（→ DESIGN.md Decision 15）
  - UserDefaults → Application Support/last_folder_bookmark.data
  - 理由: Xcode デバッグ環境で UserDefaults が永続化されない
- **Security-Scoped Bookmarks** 必須
  - Entitlements に `bookmarks.app-scope` 追加
  - 理由: サンドボックス環境でフォルダアクセス権を復元するため
- **PROTECTED フィードバック（2秒）**
  - 常時表示 → 操作時のみ一時表示
  - 理由: 常時表示は視覚的ノイズ

### 💡 Insights

**設計に関する気づき**
- **contentHash の力**: 同一画像を自動認識、異なるZIP間でも☆継承
- **★/☆ の区別が生んだ価値**: ユーザーフィードバック「同じ画像が別ZIPでも★になる」から設計改善
- **蒸留ワークフロー**: 家族写真アーカイブの個人視点での選別という新しいユースケース発見

**実装に関する気づき**
- **SwiftUI の @State とレンダリング**
  - `favoritesVersion` パターンで強制再描画
  - 外部状態（CacheManager）変更時に必要
- **race condition の典型パターン**
  - ソース切り替え時に古い非同期結果が到着
  - `loadID` パターンで世代管理して解決
- **「children count: 0」の意味**
  - 権限がない = 空に見える（エラーではない）
  - ログで気づけたのは幸運

**プロセスに関する気づき**
- **ログ共有の価値**: `children count: 0 vs 12` で原因が一目瞭然
- **スクリーンショットの価値**: Xcode 操作はテキストより画像
- **「なぜ動かないか」より「何が違うか」**: 成功ケースとの差分比較が有効
- **俯瞰の欠如**: 小さな修正を繰り返すより、立ち戻って全体を見るべきだった
  - UserDefaults デバッグを何度も試行 → 「そもそもサンドボックスでは？」と最初から問うべき
  - → WORKFLOW.md に "Step Back Before Diving Deeper" として追加

### 📚 Learnings (Erimil 固有)

**macOS サンドボックス**
- ユーザー選択以外のパスには直接アクセス不可
- NSOpenPanel で選択 → アクセス権取得
- 起動を跨ぐには Security-Scoped Bookmarks が必須

**Security-Scoped Bookmarks**
```swift
// 保存
let bookmarkData = try url.bookmarkData(options: .withSecurityScope)
try bookmarkData.write(to: fileURL)

// 復元
let data = try Data(contentsOf: fileURL)
let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope)
url.startAccessingSecurityScopedResource()
```

**SwiftUI 非同期パターン**
```swift
// 問題: 古い非同期結果が新しい状態を上書き
// 解決: loadID で世代管理
@State private var loadID = UUID()

func loadData() {
    let currentID = loadID
    Task {
        let result = await fetch()
        if loadID == currentID {  // まだ有効か確認
            self.data = result
        }
    }
}
```

**Entitlements 設定手順**
1. File → New → Property List → `Erimil.entitlements`
2. 右クリック → Open As → Source Code
3. XML を貼り付け
4. Build Settings → Code Signing Entitlements にパス設定

### ⏸️ Parked
- サムネイルサイズの deprecated 警告（動作に問題なし）
- 日本語 ZIP ファイル名の edge case テスト
- ★エクスポート機能（Issue 作成済み）

### 🌊 Ideas
- **Favorites Export**（→ ISSUE-favorites-export.md）
  - 現在のソースから★のみをZIP化
  - 選出モードより軽量な「コレクション作成」
- **Favorites Gallery**（→ ISSUE-favorites-gallery.md）
  - 横断的★一覧表示
  - 複数ソースからベストセレクションZIP作成
  - 家族写真アーカイブの個人蒸留ワークフロー
- スライドモード（フルスクリーンプレゼンテーション）

### 🌉 Handoff Bridge

- 永続化機能（設定保存、状態復元）は最初から ARCHITECTURE.md Technical Constraints を確認
- 「簡単そう」な機能こそ技術リスクを事前確認
- 小さな修正を2-3回試して解決しなければ、立ち戻って俯瞰する
- #7 黒画面バグ未修正 - 次セッションで対応
- #5 フルスクリーン未実装 - ウィンドウ内プレビューのみ完了

**💡 Ideas for next iteration**:
- **LOG#\<num\> トラッキング**: GitHub Issue とは別に、プロジェクト内でセッション単位の追跡
  - 依存関係の可視化（depends_on, blocks）
  - 複数 Actor（Claude-A, Claude-B, Zem）の並列作業対応
  - 将来的には CLI ツール化（`bebop start`, `bebop status`, `bebop graph`）
- **Session Sheet**: リアルタイムで「誰が・何を・どの Issue を」記録
- **Setlist Check**: セッション開始/終了時の Issue 棚卸し

---

## 2025-12-14 (Phase 2)

### 📍 Current Position
- Phase 2 完了
- Branch: feature/phase2-image-source → main にマージ予定

### ⚓ Decisions
- ImageSource プロトコル抽象化を採用（→ DESIGN.md Decision 8）
  - 理由: ZIP/フォルダを統一的に扱い、将来の tar.gz/7z 対応を見据える
- Finder風UI採用（→ DESIGN.md Decision 9）
  - ▶ で展開、行クリックで表示
  - 理由: macOS ユーザーに馴染みのある操作感
- 「保持モード」→「選出モード」に改名
  - 理由: Erimil（選り見る）の名前と統一感
- 未保存警告の判定を selectedPaths に変更
  - 原因: excludedPaths は計算値で、選出モード時に誤判定
  - 学び: 「ユーザーの実際のアクション」で判定すべき

### 💡 Insights
- SwiftUI の状態管理は「誰が真実を持つか」が重要
  - selectedPaths を ContentView に持ち上げたことで解決
- 命名の一貫性が混乱を防ぐ
  - excludedPaths / selectedPaths / pathsToRemove の整理

### 📚 Learnings
- ZIPFoundation: Archive インスタンスは操作ごとに開く（公式パターン）
  - メンバ変数として保持すると encoding 問題が発生
- macOS Sandbox: NSSavePanel でユーザー選択 → 権限取得
- SwiftUI List selection: `.tag()` + `selection` Binding で Finder 風動作

### ⏸️ Parked
- 日本語ファイル名 ZIP の動作確認（Phase 1 で一応動いたが要再確認）
- サムネイルサイズのカスタマイズ（Settings に追加可能）
- ArchiveManager/FolderManager の deprecated 警告対応

### 🌊 Ideas
- ドラッグ&ドロップで ZIP/フォルダ追加
- kurumil 直接呼び出し（設定でパス指定）
- 複数 ZIP 一括処理
- キーボードショートカット（全選択、反転など）
- 選択状態のプレビュー（処理前確認画面）

---

## 2025-12-13

### 📍 Current Position
- Phase 1 MVP 完了
- Repository: https://github.com/zembutsu/erimil

### ⚓ Decisions
- 新規ファイル作成方式を採用（_opt.zip）
  - 理由: 「消すのは怖い」→ 安全第一
- Select-to-exclude モードをデフォルトに
  - 理由: 未選択 = 保持 が安全なフェイルセーフ
- ZIPFoundation 採用
  - 理由: Swift ネイティブ、SPM 対応、十分な機能

### 💡 Insights
- 公式ドキュメントを先に読むべき
  - ZIPFoundation の使い方で半日ハマった
- SwiftUI の sheet タイミング問題
  - async で画像ロード → sheet 表示前に nil
  - 解決: 同期ロードしてから sheet 表示

### 📚 Learnings
- macOS App Sandbox の権限モデル
- NSSavePanel / NSOpenPanel の使い方
- SwiftUI + AppKit 連携パターン

### ⏸️ Parked
- Quick Look 風プレビュー（スペースキー）
- 複数選択のドラッグ操作

---

## Template Reference

```
## YYYY-MM-DD (LOG#<num>: <Session Title>)

### 📍 Current Position
- Phase/状態
- Branch/関連 Issue

### ⚓ Decisions
- 決定事項（→ DESIGN.md 参照）
- 理由

### 💡 Insights
- 気づき・発見

### 📚 Learnings
- 技術的な学び

### ⏸️ Parked
- 保留事項・後で検討

### 🌊 Ideas
- アイデア・将来構想

### 🌉 Handoff Bridge
- 次のセッションへの引き継ぎ
- 注意点、確認すべきこと
```

See also: `docs/TEMPLATE-SESSION-SHEET.md` for real-time session recording.
