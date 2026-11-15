const fs=require('node:fs');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const html=fs.readFileSync(require('node:path').join(__dirname,'..','index.html'),'utf8');
for(const m of html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g))if(m[1].trim())new vm.Script(m[1]);
assert.match(html,/<select id="complaintsFilter"><option value="active">/);
const source=html.split('\n').find(line=>line.includes('const rows=complaintsInboxRows.filter('));
const ctx={complaintsInboxRows:[{id:1,status:'open',title:'شكوى أولى'},{id:2,status:'in_progress',title:'جارٍ حلها'},{id:3,status:'resolved',title:'تم الحل'}],q:'',status:'active'};
vm.createContext(ctx);
function visible(){return Array.from(vm.runInContext(source.replace('const rows=','globalThis.visibleRows=')+';visibleRows.map(x=>x.id)',ctx));}
assert.deepEqual(visible(),[1,2],'Open and in-progress complaints are visible by default');
ctx.complaintsInboxRows[0].status='resolved';assert.deepEqual(visible(),[2],'Resolving removes the card from active queue');
ctx.status='resolved';assert.deepEqual(visible(),[1,3],'Resolved records remain in the archive');
ctx.complaintsInboxRows[0].status='open';ctx.status='active';assert.deepEqual(visible(),[1,2],'Reopening returns complaint to active queue');
ctx.q='تم الحل';assert.deepEqual(visible(),[],'Searching active queue cannot reveal a resolved complaint');
ctx.status='all';ctx.q='';assert.deepEqual(visible(),[1,2,3]);
console.log('PASS: active queue, resolved archive, reopen, search, syntax');
