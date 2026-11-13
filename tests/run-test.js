// fengari で Lua のテストを動かす。node run-test.js <リソースのフォルダ> <テスト.lua>
// テストからは SOURCES['server.lua'] のようにリソースのファイルを読める
const fs = require('fs'), path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const [dir, test] = process.argv.slice(2);
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_newtable(L);
for (const f of ['config.lua', 'server.lua', 'client.lua']) {
  lua.lua_pushstring(L, to_luastring(fs.readFileSync(path.join(dir, f), 'utf8')));
  lua.lua_setfield(L, -2, to_luastring(f));
}
lua.lua_setglobal(L, to_luastring('SOURCES'));
if (lauxlib.luaL_loadstring(L, to_luastring(fs.readFileSync(test, 'utf8'))) !== 0 || lua.lua_pcall(L, 0, 0, 0) !== 0) {
  console.error('エラー:', lua.lua_tojsstring(L, -1));
  process.exit(1);
}
