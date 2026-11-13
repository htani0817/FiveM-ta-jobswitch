-- ta-jobswitch 設定ファイル（client / server の両方から読み込まれる）
Config = {}

-- ================== 開き方 ==================

-- 画面を開くキー（FiveM のキー設定に「ジョブ切り替え」として登録される）
-- 既定のキーは、まだ割り当てていないプレイヤーにだけ効く。あとで変えても、すでに遊んだプレイヤーは
-- 「設定 → キー割り当て → FiveM」で各自変える必要がある
Config.Key = 'J'

-- 画面の大きさの倍率。縦1080pxの画面を基準に、画面の高さに合わせて自動で拡大・縮小したうえで掛ける
Config.UiScale = 1.0

-- ================== 切り替え ==================

-- 持っているジョブを自分で外せるようにする
Config.AllowRemove = true

-- 自分では外せないジョブ（例: { police = true }）。管理者に外してもらう
Config.RemoveBlocked = {}

-- ================== 管理者 ==================

-- 管理者の画面（すべてのジョブに就ける）を使える ACE
-- permissions.cfg の「add_ace group.admin admin allow」をそのまま使う
Config.AdminAce = 'admin'

-- ================== 表示 ==================

-- 所属名の日本語表示。ここに無いジョブは jobs.lua の label をそのまま出す
Config.JobLabels = {
    unemployed = '一般市民',
    police = 'ロスサントス市警',
    bcso = '郡保安官事務所',
    sasp = '州警察',
    ambulance = '救急',
    realestate = '不動産',
    taxi = 'タクシー',
    bus = 'バス',
    cardealer = '車の販売店',
    mechanic = '整備工場',
    judge = '裁判所',
    lawyer = '法律事務所',
    reporter = '報道',
    trucker = 'トラック運送',
    tow = 'レッカー',
    garbage = 'ゴミ収集',
    vineyard = 'ぶどう園',
    hotdog = 'ホットドッグ',
}

-- 職員証の色帯。jobs.lua の type で決める（type が無いジョブは default）
-- 色を持つのは職員証の帯だけ。種類が分かれば足りるので、同じ種類は同じ色
Config.TypeColors = {
    leo = '#3d6db5',      -- 警察
    ems = '#d0473f',      -- 救急
    mechanic = '#d9822b', -- 整備
    default = '#7d8792',
}

-- 給料の表示に使う間隔（分）。qbx_core の config/server.lua の paycheckTimeout と揃える
Config.PaycheckMinutes = 10
