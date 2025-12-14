# LOGBOOK

> 航海日誌 - 判断・気づき・学びの記録
> 未知の海を進むための現在地確認

---

## 2025-12-14

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
```
