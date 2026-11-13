-- ta-jobswitch クライアント側
-- J キー（/jobmenu）で画面を開き、NUI からの操作をサーバーに渡す。判定はすべてサーバー側

local open = false
local busy = false -- サーバーの返事を待っている間は次の操作を送らない

local function notify(msg, kind)
    exports['okokNotify']:Alert('ジョブ', msg, 4000, kind or 'info')
end

local function nui(action, data)
    data = data or {}
    data.action = action
    data.scale = Config.UiScale
    SendNUIMessage(data)
end

local function setOpen(v)
    open = v
    SetNuiFocus(v, v)
end

-- 開いてよいか（死亡中・ポーズメニュー中・ほかの画面を操作中は開かない）
local function canOpen()
    if open or IsPauseMenuActive() or IsNuiFocused() then return false end
    if IsEntityDead(cache.ped) then return false end
    return true
end

local function openMenu(view)
    if not canOpen() then return end
    local state = lib.callback.await('ta-jobswitch:state', false)
    if not state then return end
    local data = { state = state, view = 'main' }
    if view == 'admin' then
        if not state.isAdmin then
            notify('管理者だけが使えます', 'error')
            return
        end
        local admin = lib.callback.await('ta-jobswitch:adminJobs', false)
        if not admin then return end
        data.view = 'admin'
        data.jobs = admin.jobs
    end
    setOpen(true)
    nui('open', data)
end

RegisterCommand('jobmenu', function() openMenu('main') end, false)
RegisterKeyMapping('jobmenu', 'ジョブ切り替え', 'keyboard', Config.Key)
RegisterCommand('jobadmin', function() openMenu('admin') end, false)

-- 開いている間にジョブや出勤状態が変わったら（ほかのスクリプトや管理者の操作）、画面を描き直す
local function refresh()
    if not open or busy then return end
    local state = lib.callback.await('ta-jobswitch:state', false)
    if state and open then nui('state', { state = state }) end
end

RegisterNetEvent('QBCore:Client:OnJobUpdate', function() CreateThread(refresh) end)
RegisterNetEvent('QBCore:Client:SetDuty', function() CreateThread(refresh) end)
RegisterNetEvent('qbx_core:client:onGroupUpdate', function() CreateThread(refresh) end)

-- ================== NUI からの操作 ==================

-- サーバーに渡して、結果（ok, message, state）をそのまま NUI に返す
local function forward(name, ...)
    if busy then return { ok = false, busy = true } end
    busy = true
    local res = lib.callback.await(name, false, ...) or { ok = false, message = '応答がありません' }
    busy = false
    if res.message then notify(res.message, res.ok and 'success' or 'error') end
    return res
end

RegisterNUICallback('close', function(_, cb)
    setOpen(false)
    cb({})
end)

RegisterNUICallback('switch', function(data, cb)
    cb(forward('ta-jobswitch:switch', type(data) == 'table' and data.name or nil))
end)

RegisterNUICallback('duty', function(data, cb)
    cb(forward('ta-jobswitch:duty', type(data) == 'table' and data.on == true))
end)

RegisterNUICallback('remove', function(data, cb)
    cb(forward('ta-jobswitch:remove', type(data) == 'table' and data.name or nil))
end)

RegisterNUICallback('adminJobs', function(_, cb)
    cb(lib.callback.await('ta-jobswitch:adminJobs', false) or {})
end)

RegisterNUICallback('adminTake', function(data, cb)
    data = type(data) == 'table' and data or {}
    cb(forward('ta-jobswitch:adminTake', data.name, data.grade))
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    if open then SetNuiFocus(false, false) end
end)
