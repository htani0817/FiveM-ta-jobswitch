-- ta-jobswitch サーバー側
-- 切り替え・出勤退勤・外す・管理者の就く を、すべてここで判定してから qbx_core に渡す

local function getPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

local function maxJobs()
    return GetConvarInt('qbx:max_jobs_per_player', 1)
end

-- IsPlayerAceAllowed は true ではなく 1 を返す（2026-11-11 に実機で確認）。どちらでも通す
-- Lua では 0 も真になるので、真偽をそのまま使わずに true か 1 かで見る
local function isAdmin(src)
    local allowed = IsPlayerAceAllowed(tostring(src), Config.AdminAce)
    return allowed == true or allowed == 1
end

local function jobLabel(name, job)
    return Config.JobLabels[name] or (job and job.label) or name
end

-- 階級の情報（jobs.lua の grades は数字のキー）
local function gradeOf(job, grade)
    local g = job and job.grades and job.grades[tonumber(grade) or 0]
    return g
end

-- 画面に渡すジョブ1件
local function jobEntry(name, grade, onduty)
    local job = exports.qbx_core:GetJob(name)
    if not job then return nil end
    local g = gradeOf(job, grade) or {}
    return {
        name = name,
        label = jobLabel(name, job),
        grade = tonumber(grade) or 0,
        gradeLabel = g.name or '',
        payment = g.payment or 0,
        type = job.type or 'default',
        isboss = g.isboss or false,
        offDutyPay = job.offDutyPay or false,
        onduty = onduty,
    }
end

-- 画面に渡す今の状態
local function buildState(src)
    local player = getPlayer(src)
    if not player then return nil end
    local pd = player.PlayerData
    local current = pd.job or {}
    local cur = jobEntry(current.name or 'unemployed', current.grade and current.grade.level or 0, current.onduty == true)

    local list = {}
    for name, grade in pairs(pd.jobs or {}) do
        if name ~= 'unemployed' then
            local e = jobEntry(name, grade, nil)
            if e then
                e.current = (name == current.name)
                e.removable = Config.AllowRemove and not Config.RemoveBlocked[name]
                list[#list + 1] = e
            end
        end
    end
    -- 並びは所属名順（毎回同じ順に出して、数字キーの位置を変えない）
    table.sort(list, function(a, b) return a.label < b.label end)

    return {
        current = cur,
        jobs = list,
        unemployed = jobEntry('unemployed', 0, nil),
        max = maxJobs(),
        isAdmin = isAdmin(src),
        payMinutes = Config.PaycheckMinutes,
        colors = Config.TypeColors,
    }
end

-- 操作してよいか。だめなら理由を返す
local function denyReason(player)
    local md = player.PlayerData.metadata or {}
    if md.isdead or md.inlaststand then
        return '倒れている間は変えられません'
    end
    if md.ishandcuffed then
        return '手錠をかけられている間は変えられません'
    end
    return nil
end

-- qbx_core のエラーを、画面に出す文に直す
local function errorText(err)
    local code = type(err) == 'table' and err.code or nil
    if code == 'max_jobs' then
        return ('持てるジョブは%dつまでです。外してから就いてください'):format(maxJobs())
    elseif code == 'player_not_in_job' then
        return 'そのジョブには就いていません'
    elseif code == 'job_not_found' then
        return 'そのジョブはありません'
    elseif code == 'job_missing_grade' then
        return 'その階級はありません'
    end
    return '変えられませんでした'
end

local function result(src, ok, message)
    return { ok = ok, message = message, state = buildState(src) }
end

-- ================== 一般プレイヤー ==================

lib.callback.register('ta-jobswitch:state', function(src)
    return buildState(src)
end)

lib.callback.register('ta-jobswitch:switch', function(src, name)
    local player = getPlayer(src)
    if not player or type(name) ~= 'string' then return result(src, false, '変えられませんでした') end
    local pd = player.PlayerData
    if pd.job and pd.job.name == name then
        return result(src, false, 'すでにこのジョブです')
    end
    if name ~= 'unemployed' and not (pd.jobs and pd.jobs[name]) then
        return result(src, false, 'そのジョブには就いていません')
    end
    local deny = denyReason(player)
    if deny then return result(src, false, deny) end

    local ok, err = exports.qbx_core:SetPlayerPrimaryJob(pd.citizenid, name)
    if not ok then return result(src, false, errorText(err)) end
    return result(src, true, ('%s に切り替えました'):format(jobLabel(name, exports.qbx_core:GetJob(name))))
end)

lib.callback.register('ta-jobswitch:duty', function(src, on)
    local player = getPlayer(src)
    if not player then return result(src, false, '変えられませんでした') end
    local job = player.PlayerData.job or {}
    if not job.name or job.name == 'unemployed' then
        return result(src, false, '一般市民には出勤・退勤がありません')
    end
    on = on == true
    if (job.onduty == true) == on then
        return result(src, false, on and 'すでに出勤しています' or 'すでに退勤しています')
    end
    local deny = denyReason(player)
    if deny then return result(src, false, deny) end

    exports.qbx_core:SetJobDuty(src, on)
    return result(src, true, on and '出勤しました' or '退勤しました')
end)

lib.callback.register('ta-jobswitch:remove', function(src, name)
    local player = getPlayer(src)
    if not player or type(name) ~= 'string' then return result(src, false, '外せませんでした') end
    if not Config.AllowRemove or Config.RemoveBlocked[name] then
        return result(src, false, 'このジョブは自分では外せません。管理者に頼んでください')
    end
    if name == 'unemployed' then
        return result(src, false, '一般市民は外せません')
    end
    local pd = player.PlayerData
    if not (pd.jobs and pd.jobs[name]) then
        return result(src, false, 'そのジョブには就いていません')
    end
    local deny = denyReason(player)
    if deny then return result(src, false, deny) end

    local label = jobLabel(name, exports.qbx_core:GetJob(name))
    local ok, err = exports.qbx_core:RemovePlayerFromJob(pd.citizenid, name)
    if not ok then return result(src, false, errorText(err)) end
    return result(src, true, ('%s を外しました'):format(label))
end)

-- ================== 管理者 ==================

lib.callback.register('ta-jobswitch:adminJobs', function(src)
    if not isAdmin(src) then return nil end
    local list = {}
    for name, job in pairs(exports.qbx_core:GetJobs() or {}) do
        if name ~= 'unemployed' then
            local grades = {}
            for level, g in pairs(job.grades or {}) do
                grades[#grades + 1] = {
                    grade = tonumber(level) or 0,
                    label = g.name or '',
                    payment = g.payment or 0,
                    isboss = g.isboss or false,
                }
            end
            table.sort(grades, function(a, b) return a.grade < b.grade end)
            list[#list + 1] = {
                name = name,
                label = jobLabel(name, job),
                type = job.type or 'default',
                grades = grades,
            }
        end
    end
    -- 種類（警察・救急・整備・その他）→ 所属名の順
    local order = { leo = 1, ems = 2, mechanic = 3 }
    table.sort(list, function(a, b)
        local oa, ob = order[a.type] or 9, order[b.type] or 9
        if oa ~= ob then return oa < ob end
        return a.label < b.label
    end)
    return { jobs = list, state = buildState(src) }
end)

lib.callback.register('ta-jobswitch:adminTake', function(src, name, grade)
    if not isAdmin(src) then return result(src, false, '管理者だけが使えます') end
    local player = getPlayer(src)
    if not player or type(name) ~= 'string' then return result(src, false, '就けませんでした') end
    grade = math.floor(tonumber(grade) or 0)
    local job = exports.qbx_core:GetJob(name)
    if not job or name == 'unemployed' then return result(src, false, 'そのジョブはありません') end
    if not gradeOf(job, grade) then return result(src, false, 'その階級はありません') end
    local deny = denyReason(player)
    if deny then return result(src, false, deny) end

    local cid = player.PlayerData.citizenid
    local ok, err = exports.qbx_core:AddPlayerToJob(cid, name, grade)
    if not ok then return result(src, false, errorText(err)) end
    ok, err = exports.qbx_core:SetPlayerPrimaryJob(cid, name)
    if not ok then return result(src, false, errorText(err)) end

    local label = jobLabel(name, job)
    local gradeLabel = gradeOf(job, grade).name or tostring(grade)
    print(('[ta-jobswitch] 管理者 %s (%s) が %s / %s (%d) に就いた'):format(GetPlayerName(src) or '?', cid, name, gradeLabel, grade))
    return result(src, true, ('%s の %s に就きました'):format(label, gradeLabel))
end)


-- 管理者の判定を確かめる（サーバーのコンソール専用）: jobswitch_check <プレイヤーID>
-- そのプレイヤーの識別子と、ACE の判定結果をコンソールに出す。IP は出さない
RegisterCommand('jobswitch_check', function(src, args)
    if src ~= 0 then return end
    local id = tonumber(args[1])
    if not id or not GetPlayerName(id) then
        print(('[ta-jobswitch] ID %s のプレイヤーはいません'):format(tostring(args[1])))
        return
    end
    print(('[ta-jobswitch] %s (ID %d)'):format(GetPlayerName(id), id))
    for _, idf in ipairs(GetPlayerIdentifiers(id) or {}) do
        if not idf:find('^ip:') then print('  識別子: ' .. idf) end
    end
    for _, ace in ipairs({ Config.AdminAce, 'command.setjob', 'command' }) do
        print(('  %s = %s（文字のID） / %s（数字のID）'):format(ace,
            tostring(IsPlayerAceAllowed(tostring(id), ace)), tostring(IsPlayerAceAllowed(id, ace))))
    end
    print('  画面の判定（isAdmin）= ' .. tostring(isAdmin(id)))
end, true)
