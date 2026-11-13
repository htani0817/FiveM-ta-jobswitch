// ta-jobswitch の NUI。ジョブ切り替えの画面と、管理者の「すべてのジョブ」画面
'use strict';

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : null;
const $ = (id) => document.getElementById(id);
const fmt = (n) => Math.round(Number(n) || 0).toLocaleString('ja-JP');

// 外から来る文字（ジョブ名・階級名）は、必ずこれを通してから HTML に入れる
function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function post(name, data) {
    if (!RES) return Promise.resolve(Preview.post(name, data || {}));
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    }).then((r) => r.json()).catch(() => null);
}

const ICON = {
    userMinus: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 11h-6"/></svg>',
    chevDown: '<svg class="chev" viewBox="0 0 24 24" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>',
};

const TYPE_LABEL = { leo: '警察', ems: '救急', mechanic: '整備' };

const ui = {
    dock: $('dock'),
    main: $('main'),
    admin: $('admin'),
    rows: $('rows'),
    search: $('a-search'),
    list: $('a-list'),
    note: $('a-note'),
};

let S = null;           // サーバーから届いた今の状態
let adminJobs = [];     // 管理者の画面のジョブ一覧
let view = 'main';
let sel = 0;            // 選んでいる行
let confirmName = null; // 外す確認中のジョブ
let confirmTimer = null;
let openJob = null;     // 管理者の画面で開いているジョブ
let busy = false;

const color = (type) => (S && S.colors && (S.colors[type] || S.colors.default)) || '#7d8792';
const payText = (n) => `${fmt(n)}円 / ${(S && S.payMinutes) || 10}分`;

// 一覧の行。持っているジョブ（最大5つ）のあとに一般市民
function rowList() {
    if (!S) return [];
    return [...S.jobs, Object.assign({}, S.unemployed, { unemployedRow: true, current: S.current.name === 'unemployed' })];
}

// ================== ジョブ切り替え ==================

function renderBadge() {
    const c = S.current;
    const isCiv = c.name === 'unemployed';
    ui.main.style.setProperty('--band', color(c.type));
    $('b-id').textContent = `${c.name} · ${c.grade}`;
    $('b-name').textContent = c.label;
    $('b-grade').textContent = c.gradeLabel;
    $('b-pay').textContent = payText(c.payment);
    $('b-foot').classList.toggle('hidden', isCiv);
    $('b-lamp').classList.toggle('on', !!c.onduty);
    $('b-duty').textContent = c.onduty ? '出勤中' : '退勤中';
    $('b-duty-label').textContent = c.onduty ? '退勤する' : '出勤する';
}

function renderRows() {
    const list = rowList();
    sel = Math.max(0, Math.min(sel, list.length - 1));
    ui.rows.innerHTML = list.map((j, i) => {
        const key = j.unemployedRow ? '0' : String(i + 1);
        const confirm = confirmName === j.name;
        const lamp = j.current ? `<span class="lamp${S.current.onduty ? ' on' : ''}"></span>` : '';
        let sub = j.unemployedRow ? '無職' : esc(j.gradeLabel);
        if (j.current) sub += ' · いまのジョブ';
        if (confirm) sub = 'もう一度押すと外れます';
        const remove = !j.unemployedRow && j.removable
            ? `<button class="icon-btn" data-remove="${esc(j.name)}" aria-label="${esc(j.label)} を外す">${ICON.userMinus}</button>`
            : '<span class="spacer"></span>';
        return `<li class="row${i === sel ? ' sel' : ''}${confirm ? ' confirm' : ''}" data-i="${i}">
            <kbd>${key}</kbd>
            <div class="row-text">
                <div class="row-name">${lamp}<span>${esc(j.label)}</span></div>
                <div class="row-sub">${sub}</div>
            </div>
            <span class="row-pay num">${j.payment ? fmt(j.payment) + '円' : ''}</span>
            ${remove}
        </li>`;
    }).join('');
    $('held-count').textContent = `${S.jobs.length} / ${S.max}`;
    $('to-admin').classList.toggle('hidden', !S.isAdmin);
}

function render() {
    if (!S) return;
    renderBadge();
    renderRows();
    if (view === 'admin') renderAdmin();
}

function setBusy(v) {
    busy = v;
    ui.main.classList.toggle('busy', v);
    ui.admin.classList.toggle('busy', v);
}

// サーバーに送って、返ってきた状態で描き直す
async function act(name, data) {
    if (busy) return null;
    setBusy(true);
    const res = await post(name, data);
    setBusy(false);
    if (res && res.state) {
        S = res.state;
        render();
    }
    return res;
}

function switchTo(i) {
    const j = rowList()[i];
    if (!j) return;
    sel = i;
    if (j.current) { renderRows(); return; }
    act('switch', { name: j.name });
}

function askRemove(name) {
    if (confirmName === name) {
        clearTimeout(confirmTimer);
        confirmName = null;
        act('remove', { name });
        return;
    }
    confirmName = name;
    clearTimeout(confirmTimer);
    confirmTimer = setTimeout(() => { confirmName = null; renderRows(); }, 3000);
    renderRows();
}

function toggleDuty() {
    if (!S || S.current.name === 'unemployed') return;
    act('duty', { on: !S.current.onduty });
}

ui.rows.addEventListener('click', (e) => {
    const rm = e.target.closest('[data-remove]');
    if (rm) {
        e.stopPropagation();
        askRemove(rm.dataset.remove);
        return;
    }
    const row = e.target.closest('.row');
    if (row) switchTo(Number(row.dataset.i));
});

// ================== すべてのジョブ（管理者） ==================

function renderAdmin() {
    $('a-count').textContent = `持っているジョブ ${S.jobs.length} / ${S.max}`;
    const full = S.jobs.length >= S.max;
    const held = {};
    for (const j of S.jobs) held[j.name] = j.grade;

    const q = ui.search.value.trim().toLowerCase();
    const shown = adminJobs.filter((j) => !q || j.label.toLowerCase().includes(q) || j.name.includes(q)
        || j.grades.some((g) => g.label.toLowerCase().includes(q)));

    if (!shown.length) {
        ui.list.innerHTML = '<div class="empty">見つかりません</div>';
        return;
    }

    let html = '';
    let lastGroup = null;
    for (const j of shown) {
        const group = TYPE_LABEL[j.type] || 'その他';
        if (group !== lastGroup) {
            html += `<div class="group-label">${group}</div>`;
            lastGroup = group;
        }
        const isOpen = openJob === j.name || (q && shown.length === 1);
        const h = held[j.name];
        const heldGrade = h != null ? j.grades.find((g) => g.grade === h) : null;
        const heldText = heldGrade ? `就いている · ${esc(heldGrade.label)}` : `${j.grades.length}階級`;
        html += `<div class="job${isOpen ? ' open' : ''}">
            <button class="job-head" data-job="${esc(j.name)}">
                <span class="chip" style="background:${esc(color(j.type))}"></span>
                <span class="job-name">${esc(j.label)}</span>
                <span class="job-key num">${esc(j.name)}</span>
                <span class="job-held">${heldText}</span>
                ${ICON.chevDown}
            </button>`;
        if (isOpen) {
            html += '<ul class="grades">' + j.grades.map((g) => {
                const now = h === g.grade && S.current.name === j.name;
                let actHtml;
                if (now) actHtml = '<span class="now">いまの階級</span>';
                else if (full && h == null) actHtml = '';
                else actHtml = `<button class="btn plain" data-take="${esc(j.name)}" data-grade="${g.grade}">就く</button>`;
                return `<li class="grade">
                    <span class="grade-level num">${g.grade}</span>
                    <span class="grade-name">${esc(g.label)}</span>
                    ${g.isboss ? '<span class="grade-boss">ボス</span>' : ''}
                    <span class="grade-pay num">${fmt(g.payment)}円</span>
                    <span class="grade-act">${actHtml}</span>
                </li>`;
            }).join('') + '</ul>';
        }
        html += '</div>';
    }
    ui.list.innerHTML = html;

    ui.note.classList.toggle('error', full);
    ui.note.textContent = full
        ? `持てるジョブは${S.max}つまでです。外してから就いてください`
        : '自分がこのジョブに就きます。持っているジョブの数に入ります';
}

ui.list.addEventListener('click', (e) => {
    const take = e.target.closest('[data-take]');
    if (take) {
        act('adminTake', { name: take.dataset.take, grade: Number(take.dataset.grade) });
        return;
    }
    const head = e.target.closest('[data-job]');
    if (head) {
        openJob = openJob === head.dataset.job ? null : head.dataset.job;
        renderAdmin();
    }
});

ui.search.addEventListener('input', () => renderAdmin());

async function showAdmin(jobs) {
    if (!jobs) {
        const res = await post('adminJobs');
        if (!res || !res.jobs) return;
        jobs = res.jobs;
        if (res.state) S = res.state;
    }
    adminJobs = jobs;
    view = 'admin';
    openJob = S.current.name !== 'unemployed' ? S.current.name : null;
    ui.search.value = '';
    ui.main.classList.add('hidden');
    ui.admin.classList.remove('hidden');
    render();
    ui.search.focus();
}

function showMain() {
    view = 'main';
    ui.admin.classList.add('hidden');
    ui.main.classList.remove('hidden');
    render();
}

// ================== 開く・閉じる ==================

function open(m) {
    S = m.state;
    sel = Math.max(0, rowList().findIndex((j) => j.current));
    confirmName = null;
    ui.dock.classList.remove('hidden');
    if (m.view === 'admin') showAdmin(m.jobs);
    else showMain();
}

function close(notify) {
    if (ui.dock.classList.contains('hidden')) return;
    ui.dock.classList.add('hidden');
    clearTimeout(confirmTimer);
    confirmName = null;
    if (notify) post('close');
}

document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-act]');
    if (!b) return;
    const a = b.dataset.act;
    if (a === 'close') close(true);
    if (a === 'duty') toggleDuty();
    if (a === 'admin') showAdmin();
    if (a === 'back') showMain();
});

document.addEventListener('keydown', (e) => {
    if (ui.dock.classList.contains('hidden')) return;
    const typing = e.target === ui.search;
    if (e.key === 'Escape') {
        if (view === 'admin' && typing && ui.search.value) { ui.search.value = ''; renderAdmin(); return; }
        close(true);
        return;
    }
    if (typing) return;
    if (e.key === 'j' || e.key === 'J') { close(true); return; }
    if (view === 'admin') {
        if (e.key === 'Backspace') showMain();
        return;
    }
    const list = rowList();
    if (e.key === 'ArrowDown') { sel = (sel + 1) % list.length; renderRows(); e.preventDefault(); }
    else if (e.key === 'ArrowUp') { sel = (sel - 1 + list.length) % list.length; renderRows(); e.preventDefault(); }
    else if (e.key === 'Enter') switchTo(sel);
    else if (e.key === 'd' || e.key === 'D') toggleDuty();
    else if (e.key === '0') switchTo(list.length - 1);
    else if (/^[1-9]$/.test(e.key) && Number(e.key) <= S.jobs.length) switchTo(Number(e.key) - 1);
});

// ---- 大きさ ----
// 縦1080pxの画面を基準に、画面の高さに合わせて拡大・縮小する。config の UiScale を掛ける
let uiScale = 1;
let screenHeight = null; // 見本の表示で、ゲームの画面の高さを指定するときだけ使う

function applyScale() {
    const base = Math.max(0.6, Math.min(3, (screenHeight || window.innerHeight) / 1080));
    document.documentElement.style.setProperty('--scale', (base * (Number(uiScale) || 1)).toFixed(3));
}

window.addEventListener('resize', applyScale);
applyScale();

// ---- Lua からの命令 ----

window.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.scale != null) {
        uiScale = Number(m.scale) || 1;
        applyScale();
    }
    switch (m.action) {
        case 'open': open(m); break;
        case 'state':
            if (m.state) { S = m.state; render(); }
            break;
        case 'close': close(false); break;
    }
});

// ================== ブラウザで開いたときの見本 ==================
// FiveM の外（ブラウザで index.html を直接開く）で、見た目と操作を確かめるためのデータ
// index.html?view=main|admin|full|empty&h=画面の高さ&bg=背景の画像
const Preview = {
    defs: {
        police: { label: 'ロスサントス市警', type: 'leo', grades: ['Recruit', 'Officer', 'Sergeant', 'Lieutenant', 'Chief'], pay: [20000, 25000, 30000, 35000, 40000] },
        bcso: { label: '郡保安官事務所', type: 'leo', grades: ['Recruit', 'Officer', 'Sergeant', 'Lieutenant', 'Chief'], pay: [20000, 25000, 30000, 35000, 40000] },
        ambulance: { label: '救急', type: 'ems', grades: ['Recruit', 'Paramedic', 'Doctor', 'Surgeon', 'Chief'], pay: [18000, 22000, 28000, 34000, 40000] },
        mechanic: { label: '整備工場', type: 'mechanic', grades: ['Recruit', 'Novice', 'Experienced', 'Advanced', 'Manager'], pay: [5000, 7000, 9000, 11000, 14000] },
        taxi: { label: 'タクシー', type: 'default', grades: ['Recruit', 'Driver', 'Event Driver', 'Sales', 'Manager'], pay: [2000, 2500, 3000, 3500, 5000] },
        bus: { label: 'バス', type: 'default', grades: ['Driver'], pay: [2000] },
        garbage: { label: 'ゴミ収集', type: 'default', grades: ['Collector'], pay: [2000] },
        reporter: { label: '報道', type: 'default', grades: ['Journalist'], pay: [6000] },
    },
    held: {},
    current: 'unemployed',
    onduty: true,
    max: 5,
    entry(name, grade) {
        if (name === 'unemployed') return { name, label: '一般市民', grade: 0, gradeLabel: 'Freelancer', payment: 3000, type: 'default' };
        const d = Preview.defs[name];
        return { name, label: d.label, grade, gradeLabel: d.grades[grade], payment: d.pay[grade], type: d.type, removable: true };
    },
    state() {
        const P = Preview;
        const cur = P.entry(P.current, P.held[P.current] || 0);
        cur.onduty = P.current !== 'unemployed' && P.onduty;
        const jobs = Object.keys(P.held).map((n) => Object.assign(P.entry(n, P.held[n]), { current: n === P.current }))
            .sort((a, b) => (a.label < b.label ? -1 : 1));
        return {
            current: cur, jobs, unemployed: P.entry('unemployed', 0), max: P.max, isAdmin: true, payMinutes: 10,
            colors: { leo: '#3d6db5', ems: '#d0473f', mechanic: '#d9822b', default: '#7d8792' },
        };
    },
    adminJobs() {
        const order = { leo: 1, ems: 2, mechanic: 3 };
        return Object.keys(Preview.defs).map((name) => {
            const d = Preview.defs[name];
            return { name, label: d.label, type: d.type, grades: d.grades.map((label, i) => ({ grade: i, label, payment: d.pay[i], isboss: i === d.grades.length - 1 && d.grades.length > 1 })) };
        }).sort((a, b) => (order[a.type] || 9) - (order[b.type] || 9) || (a.label < b.label ? -1 : 1));
    },
    post(name, data) {
        const P = Preview;
        if (name === 'switch') { P.current = data.name; P.onduty = true; }
        if (name === 'duty') P.onduty = !!data.on;
        if (name === 'remove') { delete P.held[data.name]; if (P.current === data.name) P.current = 'unemployed'; }
        if (name === 'adminTake') {
            if (P.held[data.name] == null && Object.keys(P.held).length >= P.max) return { ok: false, state: P.state() };
            P.held[data.name] = data.grade; P.current = data.name; P.onduty = true;
        }
        if (name === 'adminJobs') return { jobs: P.adminJobs(), state: P.state() };
        return { ok: true, state: P.state() };
    },
    start() {
        const q = new URLSearchParams(location.search);
        const v = q.get('view');
        if (!v) return;
        document.body.style.background = q.get('bg') ? `#4b545c url("${q.get('bg')}") center / cover no-repeat` : '#4b545c';
        screenHeight = Number(q.get('h')) || 1080;
        applyScale();
        const P = Preview;
        if (v === 'main' || v === 'admin') { P.held = { police: 2, ambulance: 1, taxi: 0 }; P.current = 'police'; }
        if (v === 'off') { P.held = { police: 2, ambulance: 1, taxi: 0 }; P.current = 'ambulance'; P.onduty = false; }
        if (v === 'full') { P.held = { police: 2, ambulance: 1, taxi: 0, mechanic: 3, reporter: 0 }; P.current = 'mechanic'; }
        if (v === 'empty') { P.held = {}; P.current = 'unemployed'; }
        const isAdmin = v === 'admin' || v === 'full';
        open({ state: P.state(), view: isAdmin ? 'admin' : 'main', jobs: isAdmin ? P.adminJobs() : null });
    },
};

if (!RES) Preview.start();
