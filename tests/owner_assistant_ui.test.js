const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const s=fs.readFileSync(require('path').join(__dirname,'../index.html'),'utf8');
const extract=n=>s.match(new RegExp('function '+n+'\\([^]*?\\n\\}'))[0];
const context={};vm.createContext(context);vm.runInContext(extract('ownerAssistantNormalize')+'\n'+extract('ownerAssistantIntent'),context);
for(const [command,action,name] of [['أنشئ شركة باسم مطاعم النخبة','create_company','مطاعم النخبة'],['اعمل شركة اسمها مطعم جديد','create_company','مطعم جديد'],['ضيف فرع جديد باسم التجمع','add_branch','التجمع'],['غير اسم الفرع إلى الزمالك','rename_branch','الزمالك'],['عدل بيانات الموظف كود ٨٨','update_employee','']]){const p=context.ownerAssistantIntent(command);assert.equal(p.action,action);assert.equal(p.name,name)}
assert.equal(context.ownerAssistantIntent('عدل بيانات الموظف كود ٨٨').code,'88');
assert.ok(context.ownerAssistantIntent('غير كلمة المرور').sensitive);
assert.ok(context.ownerAssistantIntent('عدل رمز القفل').sensitive);
assert.equal(context.ownerAssistantIntent('امسح قاعدة البيانات').action,'');
assert(s.includes('dlv_owner_assistant_execute'));assert(s.includes('if(!prepared||busy)return'));assert(s.includes('crypto.randomUUID()'));
console.log('PASS owner assistant: supported Arabic commands, digit normalization, unknown and credential command rejection, explicit review and idempotent request wiring');
