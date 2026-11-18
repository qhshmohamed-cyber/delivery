(function(root){
 'use strict';
 const jobLabels={driver:'طيار',supervisor:'مشرف',manager:'مدير',admin:'مالك النظام',kitchen:'كنترول المطبخ',callcenter_followup:'متابعة كول سنتر',complaints_officer:'مسؤول الشكاوى',custom_unassigned:'وظيفة مخصصة'};
 const validMessage=body=>typeof body==='string'&&body.trim().length>0&&Array.from(body.trim()).length<=2000;
 const deliveryLabel=m=>m.read_at?'تمت القراءة':m.delivered_at?'وصلت للموظف':'أُرسلت — بانتظار اتصال الموظف';
 const presenceLabel=m=>m.online?(m.visible?'🟢 متصل الآن':'🟡 متصل بالخلفية'):(m.last_seen?'⚪ غير متصل — آخر ظهور '+new Date(m.last_seen).toLocaleString('ar-EG',{timeZone:'Africa/Cairo'}):'⚪ لم يظهر اتصال حديث');
 function createTeamTools(a){
  const d=a.document||root.document;
  let active=null,epoch=null,timer=null,dock=null,badge=null,banner=null,rows=[],seen=new Set(),inboxBusy=false,pingBusy=false,inboxPanel=null,threadRefresh=null;
  const dialogs=new Set();
  const current=()=>!!active&&a.identity()===active&&a.epoch()===epoch;
  const capture=()=>{const user=active,version=epoch;return ()=>current()&&active===user&&epoch===version;};
  const element=(tag,text,parent)=>{const e=d.createElement(tag);if(text!==undefined)e.textContent=text;if(parent)parent.append(e);return e;};
  const button=(text,action,parent)=>{const e=element('button',text,parent);e.type='button';e.onclick=action;return e;};
  const call=async(name,args)=>{const r=await a.rpc(name,args);if(r.error){const error=Error('تعذر تنفيذ العملية؛ تحقق من الاتصال والصلاحيات وحاول مجددًا.');error.code=r.error.code;throw error;}return r.data;};
  function dialog(title){
   const overlay=element('div');overlay.className='modal';overlay.dataset.ysTeam='dialog';overlay.setAttribute('role','dialog');overlay.setAttribute('aria-modal','true');overlay.setAttribute('aria-label',title);
   const panel=element('section',undefined,overlay);panel.className='card';panel.style.cssText='width:min(680px,96vw);max-height:88vh;overflow:auto;padding:20px';
   element('h2',title,panel);const cleanups=[];
   const close=()=>{if(!dialogs.has(overlay))return;dialogs.delete(overlay);cleanups.forEach(fn=>fn());overlay.remove();};
   button('إغلاق',close,panel);overlay.addEventListener('private-session-ended',close);d.body.append(overlay);dialogs.add(overlay);
   return {overlay,panel,close,cleanups,live:()=>current()&&overlay.isConnected};
  }
  async function acknowledge(id,read){
   const live=capture();await call('dlv_team_ack',{p_id:id,p_read:read});if(!live())return;
   if(read){if(banner?.dataset.message===id){banner.remove();banner=null;}await refreshInbox();}
  }
  function renderInbox(panel){
   panel.replaceChildren();
   if(!rows.length)element('p','لا توجد رسائل واردة.',panel);
   for(const message of rows){
    const card=element('article',undefined,panel);card.className='card';
    element('strong',message.sender_name,card);const body=element('p',message.body,card);body.style.whiteSpace='pre-wrap';
    element('small',new Date(message.created_at).toLocaleString('ar-EG',{timeZone:'Africa/Cairo'}),card);
    if(message.read_at)element('p','تمت القراءة',card);
    else button('تمت القراءة',async e=>{const b=e.currentTarget;b.disabled=true;try{await acknowledge(message.id,true);}catch(err){if(card.isConnected){b.disabled=false;a.error(err.message);}}},card);
    if(!message.delivered_at)void acknowledge(message.id,false).catch(()=>{});
   }
  }
  function openInbox(){
   if(!current())return;
   const view=dialog('✉️ رسائلي');inboxPanel=element('div',undefined,view.panel);
   const panel=inboxPanel;view.cleanups.push(()=>{if(inboxPanel===panel)inboxPanel=null;});renderInbox(panel);void refreshInbox();
  }
  function showBanner(message){
   if(banner?.isConnected||!current())return;
   seen.add(message.id);banner=element('aside');banner.dataset.ysTeam='notice';banner.dataset.message=message.id;
   banner.className='card';banner.setAttribute('role','alert');banner.style.cssText='position:fixed;bottom:76px;left:12px;right:12px;max-width:520px;margin:auto;z-index:98;padding:16px;box-shadow:0 4px 24px #0006';
   const notice=banner;element('strong','رسالة من '+message.sender_name,notice);const body=element('p',message.body,notice);body.style.cssText='white-space:pre-wrap;max-height:24vh;overflow:auto';
   button('تمت القراءة',async e=>{const b=e.currentTarget;b.disabled=true;try{await acknowledge(message.id,true);}catch(err){if(notice.isConnected){b.disabled=false;a.error(err.message);}}},notice);
   button('رسائلي',()=>{notice.remove();if(banner===notice)banner=null;openInbox();},notice);
   button('لاحقًا',()=>{notice.remove();if(banner===notice)banner=null;},notice);d.body.append(notice);
   void acknowledge(message.id,false).catch(()=>{});
  }
  async function refreshInbox(){
   if(!current()||inboxBusy)return;const live=capture();inboxBusy=true;
   try{const data=await call('dlv_team_inbox',{p_limit:50});if(!live())return;rows=data||[];
    if(badge)badge.textContent='✉️ رسائلي ('+rows.filter(m=>!m.read_at).length+')';
    if(inboxPanel?.isConnected)renderInbox(inboxPanel);
    const next=rows.find(m=>!m.read_at&&!seen.has(m.id));if(next&&!inboxPanel?.isConnected)showBanner(next);
    if(threadRefresh)void threadRefresh();
   }catch(error){if(live()&&error.code==='42501')stop();/* retain messages only during transport failures */}finally{if(live())inboxBusy=false;}
  }
  async function ping(){
   if(!current()||pingBusy||root.navigator?.onLine===false)return;const live=capture();pingBusy=true;
   try{await call('dlv_team_ping',{p_visible:d.visibilityState==='visible'});}catch(error){if(live()&&error.code==='42501')stop();}finally{if(live())pingBusy=false;}
  }
  function openThread(member){
   if(!current()||!a.canManage())return;
   const view=dialog('رسالة إلى '+member.full_name);element('p',member.company_name+' — '+member.branch_name,view.panel);
   const field=element('textarea',undefined,view.panel);field.maxLength=2000;field.rows=4;field.placeholder='اكتب رسالتك للموظف';field.setAttribute('aria-label','نص الرسالة');
   const status=element('p','',view.panel);status.setAttribute('role','status');let pending=null,busy=false,request=0;
   const history=element('div');
   const load=async()=>{const sequence=++request,live=capture();try{const data=await call('dlv_team_thread',{p_recipient:member.user_id,p_limit:50});if(!live()||!view.live()||sequence!==request)return;
    history.replaceChildren();element('h3','الرسائل المرسلة وحالة وصولها',history);
    for(const m of data||[]){const card=element('article',undefined,history);card.className='card';const body=element('p',m.body,card);body.style.whiteSpace='pre-wrap';element('small',deliveryLabel(m)+' · '+new Date(m.created_at).toLocaleString('ar-EG',{timeZone:'Africa/Cairo'}),card);}
   }catch(err){if(view.live())status.textContent=err.message;}};
   const send=button('إرسال الرسالة',async()=>{
    if(busy||!view.live())return;const body=field.value.trim();if(!validMessage(body)){status.textContent='اكتب رسالة من 1 إلى 2000 حرف.';return;}
    if(!pending||pending.body!==body)pending={id:root.crypto.randomUUID(),body};busy=true;send.disabled=true;status.textContent='جارٍ الإرسال…';const live=capture();
    try{await call('dlv_team_send',{p_recipient:member.user_id,p_body:body,p_request:pending.id});if(!live()||!view.live())return;
     pending=null;field.value='';status.textContent='تم حفظ الرسالة. حالة الوصول تظهر أسفلها.';await load();
    }catch(_){if(live()&&view.live())status.textContent='لم يتأكد الإرسال. أعد المحاولة بنفس الرسالة؛ لن تُرسل مرتين.';}
    finally{if(live()&&view.live()){busy=false;send.disabled=false;}}
   },view.panel);view.panel.append(history);threadRefresh=load;view.cleanups.push(()=>{if(threadRefresh===load)threadRefresh=null;});void load();
  }
  function openMembers(){
   if(!current()||!a.canManage())return;
   const view=dialog('👥 الموظفون والمتصلون الآن');
   element('p','تظهر حالة الاتصال الحديثة وآخر ظهور لموظفي الفروع المصرح لك بها.',view.panel);
   const search=element('input',undefined,view.panel);search.placeholder='بحث بالاسم أو الشركة أو الفرع';search.setAttribute('aria-label','بحث الموظفين');
   const status=element('p','',view.panel);status.setAttribute('role','status');const list=element('div',undefined,view.panel);let offset=0,sequence=0,debounce=null;
   const load=async()=>{const n=++sequence,live=capture();status.textContent='جارٍ التحديث…';try{
    const data=await call('dlv_team_members',{p_search:search.value.trim(),p_offset:offset,p_limit:100});if(!live()||!view.live()||n!==sequence)return;
    const members=data||[];list.replaceChildren();status.textContent=members.length?'عرض '+members.length+' موظفًا':'لا توجد نتائج ضمن صلاحياتك.';
    for(const member of members){const card=element('article',undefined,list);card.className='card';element('strong',member.full_name+' — '+(jobLabels[member.job_title]||member.job_title||''),card);element('p',member.company_name+' — '+member.branch_name,card);element('p',presenceLabel(member),card);button('إرسال رسالة',()=>openThread(member),card);}
    previous.disabled=offset===0;next.disabled=members.length<100;
   }catch(err){if(live()&&view.live()&&n===sequence)status.textContent=err.message;}};
   const previous=button('السابق',()=>{offset=Math.max(0,offset-100);void load();},view.panel),next=button('التالي',()=>{offset+=100;void load();},view.panel);
   button('تحديث القائمة',()=>void load(),view.panel);
   search.oninput=()=>{clearTimeout(debounce);offset=0;debounce=setTimeout(()=>void load(),300);};
   const interval=setInterval(()=>{if(d.visibilityState==='visible')void load();},15000);view.cleanups.push(()=>{clearInterval(interval);clearTimeout(debounce);});void load();
  }
  function stop(){
   active=null;epoch=null;clearInterval(timer);timer=null;inboxBusy=false;pingBusy=false;rows=[];seen.clear();
   for(const overlay of [...dialogs])overlay.dispatchEvent(new Event('private-session-ended'));
   dock?.remove();banner?.remove();dock=null;banner=null;badge=null;inboxPanel=null;threadRefresh=null;
  }
  function start(){
   const user=a.identity();if(!user)return;if(active===user&&epoch===a.epoch()&&dock?.isConnected)return;stop();active=user;epoch=a.epoch();
   dock=element('nav');dock.dataset.ysTeam='dock';dock.setAttribute('aria-label','رسائل الفريق');dock.style.cssText='position:fixed;bottom:10px;left:12px;z-index:97;display:flex;gap:8px;flex-wrap:wrap';
   badge=button('✉️ رسائلي (0)',openInbox,dock);if(a.canManage())button('👥 المتصلون والرسائل',openMembers,dock);d.body.append(dock);
   void ping();void refreshInbox();timer=setInterval(()=>{void ping();if(d.visibilityState==='visible')void refreshInbox();},25000);
  }
  d.addEventListener('visibilitychange',()=>{if(current()){void ping();if(d.visibilityState==='visible')void refreshInbox();}});
  return {start,stop,refreshInbox,openMembers,openInbox};
 }
 const api={validMessage,deliveryLabel,presenceLabel,createTeamTools};
 if(typeof module==='object'&&module.exports)module.exports=api;else root.createTeamTools=createTeamTools;
})(globalThis);
