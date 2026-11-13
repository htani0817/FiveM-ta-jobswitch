// Lua の構文と、未定義のグローバル参照を調べる（ta-fishing の check.js と同じ方法）
// node check.js <リソースのフォルダ>
const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');
const dir = process.argv[2];
const files = ['config.lua', 'server.lua', 'client.lua', 'fxmanifest.lua'];
const known = new Set(('Config lib cache exports json source ' +
  'print pairs ipairs type tostring tonumber math table string next select error pcall setmetatable ' +
  'CreateThread Wait GetGameTimer TriggerClientEvent TriggerEvent AddEventHandler RegisterNetEvent RegisterCommand RegisterKeyMapping ' +
  'GetPlayerName GetPlayerIdentifiers GetCurrentResourceName GetConvarInt IsPlayerAceAllowed ' +
  'SendNUIMessage RegisterNUICallback SetNuiFocus IsNuiFocused IsPauseMenuActive IsEntityDead ' +
  'fx_version game name description author version ui_page files shared_scripts client_script server_script dependencies').split(/\s+/));
let bad = 0;
for (const f of files) {
  let src = fs.readFileSync(path.join(dir, f), 'utf8');
  if (src.charCodeAt(0) === 0xfeff) { console.log(f, 'BOM あり'); bad++; }
  if (src.includes('\r')) { console.log(f, 'CR あり'); bad++; }
  let ast;
  try {
    ast = luaparse.parse(src, { scope: true, luaVersion: '5.3' });
  } catch (e) { console.log(f, '構文エラー', e.message); bad++; continue; }
  const globals = new Set();
  (function walk(n) {
    if (!n || typeof n !== 'object') return;
    if (Array.isArray(n)) return n.forEach(walk);
    if (n.type === 'Identifier' && n.isLocal === false && !known.has(n.name)) globals.add(n.name);
    for (const k in n) if (k !== 'type') walk(n[k]);
  })(ast.body);
  if (globals.size) bad++;
  console.log(f, 'OK', globals.size ? '未知のグローバル: ' + [...globals].join(', ') : '');
}
// NUI のファイルも BOM と CR を調べる
for (const f of ['html/index.html', 'html/style.css', 'html/app.js']) {
  const src = fs.readFileSync(path.join(dir, f), 'utf8');
  if (src.charCodeAt(0) === 0xfeff) { console.log(f, 'BOM あり'); bad++; }
  if (src.includes('\r')) { console.log(f, 'CR あり'); bad++; }
}
process.exit(bad ? 1 : 0);
