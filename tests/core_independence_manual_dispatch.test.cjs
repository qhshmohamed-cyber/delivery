const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.join(__dirname,'..');
const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
const runtimeFiles=['index.html','feedback.html',...fs.readdirSync(root).filter(n=>n.endsWith('.js'))];
const forbidden=/(?:https?:)?\/\/(?:api\.)?(?:openai\.com|anthropic\.com|generativelanguage\.googleapis\.com|api\.deepseek\.com|api\.x\.ai)\b/i;
for(const name of runtimeFiles){
  const body=fs.readFileSync(path.join(root,name),'utf8');
  assert(!forbidden.test(body),name+' directly uses a known generative-model endpoint');
}
for(const action of ['dlv_kitchen_forward','dlv_supervisor_receive','dlv_assign_driver']){
  assert(html.includes("safeRpc('"+action+"'"),action+' server workflow missing');
}
assert(html.includes('data-act="assign"'),'Manual assignment control missing');
const first=html.indexOf('async function assignOrder(id)');
const last=html.indexOf('async function supervisorReceive(id)',first);
assert(first>=0&&last>first,'Manual dispatch handler missing');
const assign=html.slice(first,last);
assert(assign.includes("me?.workflow_role!=='supervisor'"),'Supervisor check missing');
assert(assign.includes("const sel = $('as_' + id)"),'Explicit driver selector missing');
assert(assign.includes('if (!pid)'),'Selection validation missing');
assert(assign.includes('if(isOwner() && !confirm('),'Owner confirmation missing');
assert(!/(?:setInterval|setTimeout)\s*\(\s*assignOrder\b/.test(html),'Scheduled assignment introduced');
console.log('PASS: known AI endpoints absent from frontend; server workflow and human dispatch guard remain.');
