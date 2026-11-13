-- server.lua を FiveM の疑似環境で動かすテスト（fengari / Lua 5.3）
-- qbx_core の動き（SetPlayerPrimaryJob / AddPlayerToJob / RemovePlayerFromJob / SetJobDuty）は本物に合わせて疑似する
local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1 else fail = fail + 1; io.write('NG: ' .. msg .. '\n') end
end

-- ---- FiveM ----
local handlers = {}
function AddEventHandler(name, fn) handlers[name] = fn end
local commands = {}
function RegisterCommand(name, fn) commands[name] = fn end
function GetPlayerName() return 'テスト' end
local maxJobs = 5
function GetConvarInt(name, def)
  if name == 'qbx:max_jobs_per_player' then return maxJobs end
  return def
end
local admins = { ['2'] = true }
-- 実機の FiveM は許可で 1 を返す。不許可は 0 にしておく（Lua では 0 も真なので、取り違えを見つけられる）
function IsPlayerAceAllowed(src, ace) if ace == 'admin' and admins[src] == true then return 1 end return 0 end
local printed = {}
function print(...) printed[#printed + 1] = table.concat({ ... }, ' ') end
source = nil

-- ---- ox_lib ----
local callbacks = {}
lib = { callback = { register = function(name, fn) callbacks[name] = fn end } }
local function call(name, src, ...) return callbacks[name](src, ...) end

-- ---- qbx_core ----
local JOBS = {
  unemployed = { label = 'Civilian', grades = { [0] = { name = 'Freelancer', payment = 3000 } } },
  police = { label = 'LSPD', type = 'leo', grades = {
    [0] = { name = 'Recruit', payment = 20000 }, [1] = { name = 'Officer', payment = 25000 },
    [2] = { name = 'Sergeant', payment = 30000 }, [4] = { name = 'Chief', payment = 40000, isboss = true } } },
  ambulance = { label = 'EMS', type = 'ems', grades = { [0] = { name = 'Recruit', payment = 18000 }, [1] = { name = 'Paramedic', payment = 22000 } } },
  taxi = { label = 'Taxi', grades = { [0] = { name = 'Recruit', payment = 2000 } } },
  newsx = { label = 'News X', grades = { [0] = { name = 'Writer', payment = 1000 } } }, -- JobLabels に無いジョブ
}

local function toPlayerJob(name, grade, onduty)
  local job = JOBS[name]
  return { name = name, label = job.label, type = job.type, onduty = onduty,
    grade = { name = job.grades[grade].name, level = grade } }
end

local players = {
  [1] = { PlayerData = { source = 1, citizenid = 'CID1', jobs = { police = 2, ambulance = 1 }, job = toPlayerJob('police', 2, true), metadata = {} } },
  [2] = { PlayerData = { source = 2, citizenid = 'CID2', jobs = {}, job = toPlayerJob('unemployed', 0, true), metadata = {} } },
}
local byCid = { CID1 = players[1], CID2 = players[2] }
local dutyCalls = {}

local qbx = {}
function qbx:GetPlayer(src) return players[src] end
function qbx:GetJob(name) return JOBS[name] end
function qbx:GetJobs() return JOBS end
function qbx:SetPlayerPrimaryJob(cid, name)
  local p = byCid[cid]
  local grade = name == 'unemployed' and 0 or p.PlayerData.jobs[name]
  if not grade then return false, { code = 'player_not_in_job' } end
  p.PlayerData.job = toPlayerJob(name, grade, false)
  return true
end
function qbx:AddPlayerToJob(cid, name, grade)
  local p = byCid[cid]
  if not JOBS[name] then return false, { code = 'job_not_found' } end
  if not JOBS[name].grades[grade] then return false, { code = 'job_missing_grade' } end
  local n = 0
  for _ in pairs(p.PlayerData.jobs) do n = n + 1 end
  if n >= maxJobs and not p.PlayerData.jobs[name] then return false, { code = 'max_jobs' } end
  p.PlayerData.jobs[name] = grade
  return true
end
function qbx:RemovePlayerFromJob(cid, name)
  local p = byCid[cid]
  p.PlayerData.jobs[name] = nil
  if p.PlayerData.job.name == name then p.PlayerData.job = toPlayerJob('unemployed', 0, true) end
  return true
end
function qbx:SetJobDuty(src, on)
  dutyCalls[#dutyCalls + 1] = on
  players[src].PlayerData.job.onduty = on
end
exports = { qbx_core = qbx }

-- ---- 読み込み ----
assert(load(SOURCES['config.lua']))()
assert(load(SOURCES['server.lua']))()

-- ================== 状態 ==================
local st = call('ta-jobswitch:state', 1)
ok(st.current.name == 'police' and st.current.grade == 2, '今のジョブ')
ok(st.current.label == 'ロスサントス市警', '所属名は JobLabels を使う')
ok(st.current.gradeLabel == 'Sergeant' and st.current.payment == 30000, '階級名と給料')
ok(st.current.onduty == true, '出勤状態')
ok(#st.jobs == 2 and st.max == 5, '持っているジョブの数と上限')
ok(st.jobs[1].current ~= st.jobs[2].current, '今のジョブの印は1つだけ')
ok(st.isAdmin == false, '一般プレイヤーは管理者でない')
ok(call('ta-jobswitch:state', 2).isAdmin == true, '管理者は isAdmin（IsPlayerAceAllowed が 1 を返しても）')
ok(st.unemployed.label == '一般市民', '一般市民の行')
ok(st.colors.leo ~= nil and st.payMinutes == 10, '色と給料の間隔')

-- ================== 切り替え ==================
local r = call('ta-jobswitch:switch', 1, 'taxi')
ok(r.ok == false and r.message == 'そのジョブには就いていません', '持っていないジョブには切り替えられない')
r = call('ta-jobswitch:switch', 1, 'police')
ok(r.ok == false and r.message == 'すでにこのジョブです', '同じジョブ')
r = call('ta-jobswitch:switch', 1, 'ambulance')
ok(r.ok == true and players[1].PlayerData.job.name == 'ambulance', '持っているジョブに切り替え')
ok(r.state.current.name == 'ambulance', '返す状態も新しい')
r = call('ta-jobswitch:switch', 1, 'police')
ok(r.ok == true and players[1].PlayerData.job.name == 'police', '続けてすぐ切り替えられる（クールダウンなし）')
r = call('ta-jobswitch:switch', 1, 'unemployed')
ok(r.ok == true and players[1].PlayerData.job.name == 'unemployed', '一般市民に戻れる')
r = call('ta-jobswitch:switch', 1, 123)
ok(r.ok == false, '文字でない名前は断る')

players[1].PlayerData.metadata.isdead = true
r = call('ta-jobswitch:switch', 1, 'police')
ok(r.ok == false and r.message:find('倒れて') ~= nil, '倒れている間は断る')
players[1].PlayerData.metadata.isdead = false
players[1].PlayerData.metadata.ishandcuffed = true
r = call('ta-jobswitch:switch', 1, 'police')
ok(r.ok == false and r.message:find('手錠') ~= nil, '手錠中は断る')
players[1].PlayerData.metadata.ishandcuffed = false

-- ================== 出勤・退勤 ==================
r = call('ta-jobswitch:duty', 1, true)
ok(r.ok == false and r.message:find('一般市民') ~= nil, '一般市民は出勤退勤なし')
r = call('ta-jobswitch:switch', 1, 'police')
ok(r.ok == true and players[1].PlayerData.job.onduty == false, '切り替え直後は defaultDuty に従う（疑似では退勤）')
r = call('ta-jobswitch:duty', 1, true)
ok(r.ok == true and dutyCalls[#dutyCalls] == true and r.state.current.onduty == true, '出勤')
r = call('ta-jobswitch:duty', 1, true)
ok(r.ok == false and r.message == 'すでに出勤しています', '二重の出勤')
r = call('ta-jobswitch:duty', 1, false)
ok(r.ok == true and players[1].PlayerData.job.onduty == false, '退勤')

-- ================== 外す ==================
r = call('ta-jobswitch:remove', 1, 'unemployed')
ok(r.ok == false and r.message == '一般市民は外せません', '一般市民は外せない')
r = call('ta-jobswitch:remove', 1, 'taxi')
ok(r.ok == false and r.message == 'そのジョブには就いていません', '持っていないジョブは外せない')
Config.RemoveBlocked.police = true
r = call('ta-jobswitch:remove', 1, 'police')
ok(r.ok == false and r.message:find('管理者') ~= nil, 'RemoveBlocked のジョブは外せない')
st = call('ta-jobswitch:state', 1)
for _, j in ipairs(st.jobs) do
  if j.name == 'police' then ok(j.removable == false, '外せないジョブの印') end
end
Config.RemoveBlocked.police = nil
r = call('ta-jobswitch:remove', 1, 'police')
ok(r.ok == true and players[1].PlayerData.jobs.police == nil and r.state.current.name == 'unemployed', '今のジョブを外すと一般市民')
Config.AllowRemove = false
r = call('ta-jobswitch:remove', 1, 'ambulance')
ok(r.ok == false, 'AllowRemove = false なら外せない')
Config.AllowRemove = true

-- ================== 管理者 ==================
ok(call('ta-jobswitch:adminJobs', 1) == nil, '一般プレイヤーには全ジョブを返さない')
r = call('ta-jobswitch:adminTake', 1, 'police', 4)
ok(r.ok == false and players[1].PlayerData.jobs.police == nil, '一般プレイヤーは就けない')

local a = call('ta-jobswitch:adminJobs', 2)
ok(a and #a.jobs == 4, '全ジョブ（一般市民を除く）')
ok(a.jobs[1].name == 'police' and a.jobs[2].name == 'ambulance', '種類の順（警察→救急→その他）')
ok(a.jobs[1].grades[1].grade == 0 and a.jobs[1].grades[4].grade == 4 and a.jobs[1].grades[4].isboss == true, '階級は番号順')
local foundRaw = false
for _, j in ipairs(a.jobs) do if j.name == 'newsx' and j.label == 'News X' then foundRaw = true end end
ok(foundRaw, 'JobLabels に無いジョブは jobs.lua の label')

r = call('ta-jobswitch:adminTake', 2, 'police', 4)
ok(r.ok == true and players[2].PlayerData.jobs.police == 4 and players[2].PlayerData.job.name == 'police', '管理者は好きな階級に就ける')
ok(printed[#printed]:find('police') ~= nil, 'コンソールに記録')
r = call('ta-jobswitch:adminTake', 2, 'police', 3)
ok(r.ok == false and r.message == 'その階級はありません', '無い階級')
r = call('ta-jobswitch:adminTake', 2, 'nope', 0)
ok(r.ok == false and r.message == 'そのジョブはありません', '無いジョブ')
r = call('ta-jobswitch:adminTake', 2, 'unemployed', 0)
ok(r.ok == false, '一般市民には adminTake で就かない')

maxJobs = 1
r = call('ta-jobswitch:adminTake', 2, 'taxi', 0)
ok(r.ok == false and r.message == '持てるジョブは1つまでです。外してから就いてください', '上限の文言')
r = call('ta-jobswitch:adminTake', 2, 'police', 1)
ok(r.ok == true and players[2].PlayerData.jobs.police == 1, '持っているジョブの階級は上限でも変えられる')
maxJobs = 5

io.write(('server: %d 件 OK, %d 件 NG\n'):format(pass, fail))
if fail > 0 then error('テスト失敗') end
