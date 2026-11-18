/* Your Staff Delivery — per-manager complaint read receipts.
   Status, assignment, reporting, and history remain untouched. */
(()=>{
'use strict';
let loading=false, queued=false, scope='', lastLoaded=0;
function allowed(){try{return (typeof isOwner==='function'&&isOwner())||(typeof isLocationManager==='function'&&isLocationManager());}catch(_){return false;}}
function branch(){try{return (typeof selectedBranch==='undefined'||!selectedBranch)?null:Number(selectedBranch);}catch(_){return null;}}
function rpc(name,args){if(typeof safeRpc!=='function')return Promise.resolve({error:{message:'خدمة الاتصال غير متاحة'}});return safeRpc(name,args||{});}
function tag(name,cls){const n=document.createElement(name);if(cls)n.className=cls;return n;}
function setText(parent,name,value,cls){const n=tag(name,cls);n.textContent=String(value??'');parent.append(n);return n;}
function complaintLabel(c){const labels={open:'مفتوحة',in_progress:'جارٍ المتابعة',resolved:'تم الحل'};return labels[c.status]||c.status;}
function clock(t){try{return new Date(t).toLocaleString('ar-EG',{timeZone:'Africa/Cairo'});}catch(_){return '—';}}
async function read(id,button){
 button.disabled=true;
 const {data,error}=await rpc('dlv_mark_complaint_read',{p_incident:Number(id)});
 if(error||data?.success!==true){button.disabled=false;const status=document.getElementById('ysManagerUnreadStatus');if(status)status.textContent='تعذر حفظ القراءة؛ لا يزال التنبيه ظاهرًا.';return;}
 await load();
}
function render(rows){
 const root=document.getElementById('ysManagerUnreadRows'),info=document.getElementById('ysManagerUnreadStatus');
 if(!root||!info)return;
 root.replaceChildren();
 info.textContent=rows.length?'شكاوى جديدة أو تم تحديثها: '+rows.length+' — التأكيد يخفي التنبيه من حسابك فقط.':'✓ لا توجد تنبيهات شكاوى غير مقروءة حاليًا.';
 for(const c of rows.slice(0,15)){
   const card=tag('div','card');card.style.padding='10px';
   setText(card,'b','شكوى #'+c.id+' · '+(c.title||'شكوى عميل'));
   setText(card,'p',(c.order_no?'الطلب #'+c.order_no+' · ':'')+complaintLabel(c)+' · '+clock(c.updated_at||c.created_at),'meta');
   setText(card,'div',String(c.details||'').slice(0,220));
   if(c.followup_action)setText(card,'div','آخر إجراء: '+String(c.followup_action).slice(0,180),'meta');
   const button=tag('button','p');button.type='button';button.textContent='✓ تمت القراءة';
   button.addEventListener('click',()=>void read(c.id,button));
   card.append(button);root.append(card);
 }
 if(rows.length>15)setText(root,'p','يوجد '+(rows.length-15)+' تنبيه إضافي؛ استخدم صفحة الشكاوى للمراجعة.','meta');
}
async function load(){
 const root=document.getElementById('ysManagerUnreadRows');if(!root||!allowed()||loading||!navigator.onLine)return;
 const active=branch();const token=String(active);loading=true;
 const info=document.getElementById('ysManagerUnreadStatus');if(info)info.textContent='جاري مراجعة الشكاوى...';
 try{
   const [all,readRows]=await Promise.all([rpc('dlv_complaint_inbox_v2',{p_branch:active}),rpc('dlv_list_read_complaints',{p_branch:active})]);
   if(!root.isConnected||!allowed()||String(branch())!==token)return;
   if(all.error||readRows.error){if(info)info.textContent='تعذر تحميل التنبيهات؛ اضغط تحديث للمحاولة.';return;}
   const read=new Set((readRows.data||[]).map(x=>Number(x.incident_id)));
   render((Array.isArray(all.data)?all.data:[]).filter(x=>!read.has(Number(x.id))));
   lastLoaded=Date.now();
 }catch(_){if(info)info.textContent='حدث خطأ أثناء تحديث التنبيهات.';}
 finally{loading=false;}
}
function attach(){
 const anchor=document.getElementById('repeatCustomerDashboard');
 if(!anchor||!allowed())return;
 if(document.getElementById('ysManagerUnreadPanel'))return;
 const section=tag('section','card');section.id='ysManagerUnreadPanel';
 setText(section,'h2','📨 تنبيهات شكاوى العملاء');
 const note=setText(section,'p','التنبيه يختفي لهذا المدير بعد «تمت القراءة»، مع بقاء الشكوى لدى مسؤول الشكاوى وفي التقارير.','meta');note.style.marginBottom='10px';
 const refresh=tag('button','g');refresh.type='button';refresh.textContent='↻ تحديث التنبيهات';refresh.addEventListener('click',()=>void load());section.append(refresh);
 const status=setText(section,'div','جاري التحميل...','meta');status.id='ysManagerUnreadStatus';status.setAttribute('role','status');
 const rows=tag('div');rows.id='ysManagerUnreadRows';section.append(rows);
 anchor.after(section);scope=String(branch());void load();
}
function schedule(){
 if(queued)return;queued=true;setTimeout(()=>{
   queued=false;attach();
   const panel=document.getElementById('ysManagerUnreadPanel');
   if(panel&&scope!==String(branch())){scope=String(branch());void load();}
 },150);
}
function boot(){
 if(!document.body)return;
 new MutationObserver(schedule).observe(document.body,{childList:true,subtree:true});
 schedule();
 setInterval(()=>{if(document.visibilityState==='visible'&&document.getElementById('ysManagerUnreadPanel')&&(Date.now()-lastLoaded>25000))void load();},30000);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();