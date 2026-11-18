'use strict';
/* Offline smoke test for the additive upgrade. Run: node tests/efficient_upgrade_smoke.test.cjs */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const script = fs.readFileSync(path.join(__dirname, '..', 'yourstaff-efficient-20261119.js'), 'utf8');
new vm.Script(script, {filename: 'yourstaff-efficient-20261119.js'});
assert(script.length < 50000, 'Upgrade must remain a small additive script');
for (const required of [
  'dlv_manager_stage_bars',
  'dlv_map_locations',
  'dlv_root_owner_accounts',
  'dlv_root_create_secondary_owner',
  'dlv_root_promote_secondary_owner',
  'dlv_root_toggle_secondary_owner',
  'isLocationManager',
  'reportOperationalDay'
]) assert(script.includes(required), 'Missing integration: ' + required);
for (const forbidden of ['service_role', 'localStorage.setItem', 'eval(']) {
  assert(!script.includes(forbidden), 'Unexpected browser feature/secret: ' + forbidden);
}
const listeners = [];
const window = {};
class MockMutationObserver { observe() {} }
const document = {
  readyState: 'loading',
  body: null,
  addEventListener(type, listener) { listeners.push({type, listener}); },
  getElementById() { return null; }
};
const sandbox = {
  window, document, MutationObserver: MockMutationObserver,
  requestAnimationFrame() {}, setInterval() { return 1; },
  navigator: {onLine: true}, console, Intl, Map, Set, Date, Number, String
};
vm.runInNewContext(script, sandbox, {timeout: 1500});
assert.equal(listeners.filter(x => x.type === 'DOMContentLoaded').length, 2);
assert.equal(window.__ysBrandPerformance20261118Loaded, true);
assert.equal(window.__ysOwnerAccess20261119Loaded, true);
vm.runInNewContext(script, sandbox, {timeout: 1500});
assert.equal(listeners.filter(x => x.type === 'DOMContentLoaded').length, 2, 'Must initialize at most once');
console.log('PASS: syntax, small size, expected RPCs, guards, duplicate-load safety');
