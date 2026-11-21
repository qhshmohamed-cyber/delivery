'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const start = source.indexOf('function stageDurationText(');
const end = source.indexOf('const isLate =', start);
assert.ok(start >= 0 && end > start, 'Timeline helper definitions must be present');
const context = vm.createContext({
  esc: x => String(x ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])),
  tm: x => x || '—'
});
vm.runInContext(source.slice(start, end), context, {timeout: 1000});
const {stageDurationText, orderTotalDurationText, orderTimelineHtml} =
  vm.runInContext('({stageDurationText,orderTotalDurationText,orderTimelineHtml})', context);
assert.equal(stageDurationText('2026-11-21T08:00:00Z', '2026-11-21T09:10:00Z'), '1 س 10 د');
assert.equal(stageDurationText('2026-11-21T08:05:00Z', '2026-11-21T08:25:00Z'), '20 د');
assert.equal(stageDurationText(null, '2026-11-21T08:25:00Z'), '—');
assert.equal(stageDurationText('2026-11-21T09:10:00Z', '2026-11-21T08:00:00Z'), '—');
const delivered = {
  created_at:'2026-11-21T08:00:00Z',
  kitchen_received_at:'2026-11-21T08:05:00Z',
  kitchen_ready_at:'2026-11-21T08:25:00Z',
  supervisor_received_at:'2026-11-21T08:30:00Z',
  pilot_assigned_at:'2026-11-21T08:40:00Z',
  out_at:'2026-11-21T08:50:00Z',
  delivered_at:'2026-11-21T09:10:00Z',
  status:'delivered',
  workflow_stage:'delivered'
};
assert.equal(orderTotalDurationText(delivered), '1 س 10 د');
const html = orderTimelineHtml(delivered);
assert.ok(html.includes('المدة: 20 د'), 'Kitchen stage 20m');
assert.ok(html.includes('المدة: 10 د'), 'Supervisor stage 10m');
assert.ok(html.includes('مدة التوصيل: 20 د'), 'Rider delivery stage 20m');
assert.ok(html.includes('إجمالي وقت الطلب'), 'Full order duration displayed');
assert.equal(orderTotalDurationText({...delivered, status:'cancelled', delivered_at:null}), 'لم يكتمل بالتسليم');
assert.match(orderTotalDurationText({...delivered, status:'out', delivered_at:null}), /^جارٍ:/);
assert.ok(source.includes('id="managerTimelineRows"'), 'Manager timing table present');
assert.ok(source.includes('async function loadManagerTimeline()'), 'Manager loader present');
assert.ok(source.includes('delivered_at,driver:driver_id(full_name)'), 'Callcenter includes delivery completion timestamp');
console.log('PASS order timeline metrics: completed, ongoing, cancelled, missing, manager/callcenter integration');
