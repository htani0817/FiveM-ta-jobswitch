---
title: ta-jobswitch（ジョブ切り替え）
date: 2026-11-11
tags:
  - コーディング/fivem
status: 実装済み（FiveM 実機で動作確認済み）
aliases:
  - ta-jobswitch
  - tani-jobswitch
---

# ta-jobswitch（ジョブ切り替え）

Qbox サーバー向け。J キーで画面を開き、持っているジョブの中から「いまのジョブ」を選ぶ。出勤・退勤の切り替えと、ジョブを外すのも同じ画面でできる。管理者は「すべてのジョブ」画面から、jobs.lua にあるどのジョブ・階級にも自分で就ける。目次は [[FiveM-Script/README|FiveM-Script 目次]]。

旧名は `tani-jobswitch`（2026-11-13 に `ta-jobswitch` へ変えた）。旧名のまま入れているサーバーは、古いフォルダを消してから入れ直す。ジョブのデータは qbx_core が持っているので、引き継ぐものは無い。

> [!success] 動作確認済み
> FiveM の実機で動作を確認した。サーバー側の判定は疑似環境でも確かめ（下の「テスト」）、画面はブラウザでも描画して確かめている。

qbx_core 1.24.1 に標準で入っているマルチジョブ（`PlayerData.jobs` に複数持ち、`SetPlayerPrimaryJob` でメインを選ぶ）をそのまま使う。新しいデータベースの表は作らない。

## 使い方

| 操作 | 内容 |
| --- | --- |
| `J`（`/jobmenu`） | ジョブの画面を開く。もう一度 `J` か `Esc` で閉じる |
| `↑` `↓` → `Enter` | 選んだジョブに切り替える。行をクリックしても同じ |
| `1`〜`5` | その番号のジョブにすぐ切り替える。`0` は一般市民（無職） |
| `D` | 出勤・退勤を切り替える（一般市民には無い） |
| 行の右端のアイコン | そのジョブを外す。押すと「もう一度押すと外れます」に変わり、3秒以内にもう一度押すと外れる |
| 見出しの「すべてのジョブ」（`/jobadmin`） | 管理者だけ。全ジョブの一覧から階級を選んで「就く」 |

- 一般プレイヤーが切り替えられるのは、持っているジョブと一般市民だけ。新しいジョブは管理者が `/addjob` で付けるか、管理者が自分の画面で就く
- クールダウンは無い。続けてすぐ切り替えられる
- 倒れている間（`isdead` / `inlaststand`）と手錠中（`ishandcuffed`）は変えられない
- 切り替え直後の出勤状態は jobs.lua の `defaultDuty` に従う（qbx_core の動き）

## 画面

方向は「職員証とタイムカード」。灰色の土台は ta-fishing と同じで、色を持つのはいまのジョブの職員証の帯だけ（警察＝紺、救急＝赤、整備＝橙、その他＝灰。jobs.lua の `type` で決まる）。出勤中は緑のランプ、退勤中は輪郭だけのランプ。

- 画面の中央に出る。大きさは「画面の高さ / 1080 × `Config.UiScale`」
- ブラウザで `html/index.html?view=main` を開くと見本が出る。`view` は `main`（出勤中）、`off`（退勤中）、`empty`（ジョブ無し）、`admin`（すべてのジョブ）、`full`（上限の5つに達した状態）。`&h=1440` で画面の高さ、`&bg=画像` でゲームのスクリーンショットを背景にできる。見本の中でも切り替え・外す・就くを試せる

## 導入

1. このフォルダを `resources/[standalone]/ta-jobswitch` に置く（`tests/` は要らない）。server.cfg は `ensure [standalone]` で読み込まれるので変更不要
2. server.cfg の次の行を書き換えて、サーバーを再起動する（qbx_core は起動時に読むので restart では足りない）

```cfg
set qbx:max_jobs_per_player 5 # Sets the number of jobs per player
```

3. 管理者の判定は ACE の `admin`（permissions.cfg の `add_ace group.admin admin allow`）を使うので、追加の設定は無い

> [!note] キーの割り当て
> `Config.Key` は、まだこのキーを割り当てていないプレイヤーにだけ効く（FiveM の `RegisterKeyMapping` の仕様）。あとで変えた場合、すでに遊んだプレイヤーは「設定 → キー割り当て → FiveM → ジョブ切り替え」で各自変える。

## 設定（config.lua）

| 項目 | 既定 | 内容 |
| --- | --- | --- |
| `Key` | `'J'` | 画面を開くキー |
| `UiScale` | `1.0` | 画面の大きさの倍率 |
| `AllowRemove` | `true` | 自分でジョブを外せるか |
| `RemoveBlocked` | `{}` | 自分では外せないジョブ（例 `{ police = true }`） |
| `AdminAce` | `'admin'` | 管理者の画面を使える ACE |
| `JobLabels` | 18件 | 所属名の日本語表示。無いジョブは jobs.lua の `label` |
| `TypeColors` | 4色 | 職員証の帯の色（`type` ごと） |
| `PaycheckMinutes` | `10` | 給料の表示に使う間隔。qbx_core の `paycheckTimeout` と揃える |

## 仕組み

判定はすべてサーバー側（`server.lua`）。クライアントは画面の開閉と受け渡しだけ。

| コールバック | 内容 |
| --- | --- |
| `ta-jobswitch:state` | いまのジョブ、持っているジョブ、上限、管理者か |
| `ta-jobswitch:switch(name)` | 持っているジョブか一般市民なら `SetPlayerPrimaryJob` |
| `ta-jobswitch:duty(on)` | `SetJobDuty` |
| `ta-jobswitch:remove(name)` | `RemovePlayerFromJob`。いまのジョブを外すと一般市民になる（qbx_core の動き） |
| `ta-jobswitch:adminJobs` | 管理者だけ。全ジョブと階級 |
| `ta-jobswitch:adminTake(name, grade)` | 管理者だけ。`AddPlayerToJob` → `SetPlayerPrimaryJob`。サーバーのコンソールに誰が何に就いたかを出す |

どれも新しい状態を一緒に返し、画面はそれで描き直す。結果は okokNotify（タイトル「ジョブ」）でも出す。ほかのスクリプトや管理者がジョブを変えたときは、`QBCore:Client:OnJobUpdate` などを受けて開いている画面を描き直す。

## テスト

`tests/` に、ta-fishing と同じ方法のテストがある。

```sh
npm i fengari luaparse          # 作業用のフォルダで
node tests/check.js .           # Lua の構文・未定義のグローバル、BOM と CR
node tests/run-test.js . tests/test-server.lua
```

`test-server.lua` は qbx_core を疑似して、持っていないジョブへの切り替えを断る、続けてすぐ切り替えられる、倒れている・手錠、出勤退勤、外す（一般市民・RemoveBlocked）、管理者だけが就ける、上限の文言などを確かめる（2026-11-11 時点で 43 件）。

## 既知の制約

- 上限（`qbx:max_jobs_per_player`）は持っているジョブの数で、一般市民は数えない。上限に達すると、管理者でも新しいジョブには就けない（先に外す）
- 管理者が「就く」と、そのジョブは持っているジョブとして残る。要らなくなったら一般の画面で外す
- qbx_core の `/setjob` は、server.cfg の `qbx:setjob_replaces "true"` のため、いまのジョブを外してから新しいジョブに就かせる（2026-11-11 に、整備工場がいまのジョブの状態で `/setjob 1 ambulance 4` を実行し、整備工場が消えたのを確認）。ジョブを足すときは `/addjob <ID> <ジョブ> <階級>`、メインを変えるだけなら `/changejob <ID> <ジョブ>` を使う。`setjob_replaces` は `true` のままにする（`false` にすると、xt-prison の投獄や市役所の職業案内が古いジョブを残すようになり、投獄後も J で警察に戻れてしまう）
- FiveM 実機で確かめたこと: J で開くこと、切り替えで給料や警察の装備などがそのジョブのものに変わること、出勤退勤がほかのスクリプト（警察の出勤ブリップなど）に伝わること、画面の大きさ

## ライセンス

MIT License（`LICENSE`）
