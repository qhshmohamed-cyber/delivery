const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(require('node:path').join(__dirname,'../team-tools.js'),'utf8');
class Node {
 constructor(tag,doc){this.tagName=tag;this.doc=doc;this.children=[];this.dataset={};this.style={};this.events={};this.text='';this.value='';}
 set textContent(v){this.text=String(v);this.children=[];}get textContent(){return this.text+this.children.map(n=>n.textContent).join('');}
 append(...nodes){for(const n of nodes){n.remove();n.parent=this;this.children.push(n);}}
 replaceChildren(...nodes){for(const n of this.children)n.parent=null;this.children=[];this.text='';this.append(...nodes);}
 remove(){if(this.parent){this.parent.children=this.parent.children.filter(n=>n!==this);this.parent=null;}}
 get isConnected(){return this===this.doc.body||!!this.parent?.isConnected;}
 setAttribute(k,v){this[k]=v;}addEventListener(k,v){this.events[k]=v;}dispatchEvent(e){this.events[e.type]?.(e);}
}
function setup(manager=false){
 const doc={visibilityState:'visible',events:{},createElement(tag){return new Node(tag,this);},addEventListener(k,v){this.events[k]=v;}};doc.body=new Node('body',doc);
 const intervals=new Map();let timer=0,uuid=0,epoch=1,user='user-A';const calls=[];let inbox=[];let custom;
 const sandbox={module:{exports:{}},console,Date,Event,Set,Array,Promise,navigator:{onLine:true},crypto:{randomUUID:()=>`request-${++uuid}`},
 setInterval(fn){intervals.set(++timer,fn);return timer;},clearInterval(id){intervals.delete(id);},setTimeout,clearTimeout};
 vm.createContext(sandbox);vm.runInContext(source,sandbox);const api=sandbox.module.exports;
 const rpc=async(name,args)=>{calls.push({name,args});if(custom){const r=await custom(name,args);if(r!==undefined)return r;}
  if(name==='dlv_team_inbox')return {data:inbox};
  if(name==='dlv_team_members')return {data:[{user_id:'target',full_name:'موظف <script>',company_name:'شركة أ',branch_name:'الفرع أ',job_title:'طيار',online:true,visible:true}]};
  if(name==='dlv_team_thread')return {data:[]};
  if(name==='dlv_team_ack'){const m=inbox.find(m=>m.id===args.p_id);if(m){m.delivered_at='2026-11-16T12:00:00Z';if(args.p_read)m.read_at=m.delivered_at;}return {data:true};}
  return {data:true};};
 const tools=api.createTeamTools({document:doc,identity:()=>user,epoch:()=>epoch,canManage:()=>manager,rpc,error(){}});
 const all=()=>{const nodes=[];const visit=n=>{nodes.push(n);n.children.forEach(visit);};visit(doc.body);return nodes;};
 return {api,tools,doc,calls,intervals,all,button:text=>all().find(n=>n.tagName==='button'&&n.textContent===text),setEpoch:()=>epoch++,setUser:v=>user=v,setInbox:v=>inbox=v,setCustom:v=>custom=v};
}
const tick=async()=>{for(let i=0;i<12;i++)await Promise.resolve();};
(async()=>{
 let s=setup();assert.equal(s.api.validMessage('  '),false);assert.equal(s.api.validMessage('🙂'.repeat(2000)),true);assert.equal(s.api.validMessage('x'.repeat(2001)),false);
 s.tools.start();await tick();assert.equal(s.button('👥 المتصلون والرسائل'),undefined);s.tools.stop();assert.equal(s.intervals.size,0);
 s=setup();s.setInbox([{id:'message',sender_name:'مدير',body:'<img src=x onerror=alert(1)>',created_at:'2026-11-16T12:00:00Z',read_at:null}]);s.tools.start();await tick();
 assert(s.doc.body.textContent.includes('<img src=x onerror=alert(1)>'));assert(s.calls.some(c=>c.name==='dlv_team_ack'&&!c.args.p_read));
 const read=s.button('تمت القراءة');await read.onclick({currentTarget:read});await tick();assert(s.calls.some(c=>c.name==='dlv_team_ack'&&c.args.p_read));s.tools.stop();
 s=setup();s.setCustom(name=>name==='dlv_team_inbox'?{error:{code:'42501'}}:undefined);s.tools.start();await tick();assert.equal(s.doc.body.children.length,0);assert.equal(s.intervals.size,0);
 s=setup();let resolve;s.setCustom(name=>name==='dlv_team_inbox'?new Promise(r=>resolve=r):undefined);s.tools.start();await tick();s.setEpoch();s.tools.stop();resolve({data:[{id:'secret',sender_name:'old',body:'PRIVATE',created_at:'2026-11-16T12:00:00Z'}]});await tick();assert.equal(s.doc.body.children.length,0);
 s=setup(true);s.tools.start();await tick();s.button('👥 المتصلون والرسائل').onclick();await tick();s.button('إرسال رسالة').onclick();await tick();
 const field=s.all().find(n=>n.tagName==='textarea');field.value='رسالة اختبار';let sendAttempts=0;
 s.setCustom(name=>{if(name==='dlv_team_send'){sendAttempts++;return sendAttempts===1?{error:{message:'network'}}:{data:'saved'};}});
 await s.button('إرسال الرسالة').onclick();await s.button('إرسال الرسالة').onclick();
 const sends=s.calls.filter(c=>c.name==='dlv_team_send');assert.equal(sends.length,2);assert.equal(sends[0].args.p_request,sends[1].args.p_request);assert.equal(field.value,'');
 field.value='ثانية';let resolveSend;s.setCustom(name=>name==='dlv_team_send'?new Promise(r=>resolveSend=r):undefined);const first=s.button('إرسال الرسالة').onclick();const second=s.button('إرسال الرسالة').onclick();await tick();resolveSend({data:'saved'});await Promise.all([first,second]);assert.equal(s.calls.filter(c=>c.name==='dlv_team_send').length,3);
 s.tools.stop();assert.equal(s.intervals.size,0);assert.equal(s.doc.body.children.length,0);
 assert(!source.includes('innerHTML'),'Message text must not be parsed as HTML');
 console.log('PASS team tools: role controls, literal message text, delivery/read receipts, stale session rejection, idempotent retries, double-click suppression and cleanup');
})().catch(e=>{console.error(e);process.exitCode=1;});
