/* Your Staff Delivery — one customer tracking target per driver.
   Only the backend decides which order may expose GPS coordinates.
   Designed as a small additive script; do not replace the live index.html. */
(()=>{
'use strict';
let activeOrder=null, view=null, busy=false, queued=false, pollBusy=false, operationEpoch=0;
function driver(){try{return typeof me!=='undefined' && me?.role==='driver';}catch(_){return false;}}
function rpc(name,args){if(typeof safeRpc!=='function')return Promise.resolve({error:{message:'خدمة الاتصال غير متاحة'}});return safeRpc(name,args||{});}
function notify(message,ok){if(typeof flash==='function')flash(message,!!ok);else {const e=document.getElementById('ysCurrentCustomer');if(e)e.textContent=message;}}
function updateLabel(){
 const root=document.getElementById('ol');
 if(!root||!driver())return;
 let label=document.getElementById('ysCurrentCustomer');
 if(!label){label=document.createElement('p');label.id='ysCurrentCustomer';label.className='meta';label.style.padding='8px';root.before(label);}
 const current=root.querySelector('[data-nav-order="'+activeOrder+'"]');
 const card=current?.closest('.card');
 const orderText=card?.querySelector('.ord b')?.textContent?.trim();
 const message=activeOrder&&orderText?'📍 العميل الجاري التوجه إليه: '+orderText+' — هذا الطلب فقط مسموح له برؤية GPS الحديث إذا توفر.':'📍 اختر «التوجه لهذا العميل» من الطلب الجاري توصيله. طلباتك الأخرى لا ترى موقعك.';
 if(label.textContent!==message)label.textContent=message;
 root.querySelectorAll('[data-nav-order]').forEach(b=>{
   const same=Number(b.dataset.navOrder)===activeOrder;
   const text=same?'⏹ إيقاف التوجه لهذا العميل':'📍 التوجه لهذا العميل';
   if(b.textContent!==text)b.textContent=text;
   const cls=same?'r':'g';if(b.className!==cls)b.className=cls;
   if(b.disabled!==busy)b.disabled=busy;
   if(b.getAttribute('aria-pressed')!==String(same))b.setAttribute('aria-pressed',String(same));
 });
}
async function current(){
 if(!driver()||!document.getElementById('ol')||pollBusy)return;
 pollBusy=true;const currentView=document.getElementById('ol'),requestEpoch=operationEpoch;
 try{const {data,error}=await rpc('dlv_current_customer_navigation');if(error)return;if(requestEpoch!==operationEpoch||!currentView.isConnected||!driver())return;activeOrder=Number(data?.order_id)||null;updateLabel();}
 catch(_){/* no GPS coordinates are ever made available by this UI */ }
 finally{pollBusy=false;}
}
async function choose(id){
 if(busy||!driver())return;
 if(!navigator.onLine){notify('شغّل الإنترنت أولًا',false);return;}
 busy=true;operationEpoch++;updateLabel();
 const isCurrent=activeOrder===id,endpoint=isCurrent?'dlv_stop_customer_navigation':'dlv_begin_customer_navigation';
 const args=isCurrent?{p_order_id:id}:{p_order_id:id};
 try{
   const {data,error}=await rpc(endpoint,args);
   if(error||(isCurrent?data?.stopped!==true:data?.success!==true))throw Error(error?.message||'لم يؤكد الخادم تغيير وجهة التتبع');
   activeOrder=isCurrent?null:id;
   notify(isCurrent?'تم إيقاف مشاركة الموقع مع هذا العميل':'تم تحديد العميل الحالي؛ باقي العملاء لن يروا موقعك',true);
 }catch(e){notify('تعذر تحديث وجهة الطيار: '+String(e?.message||e),false);void current();}
 finally{busy=false;updateLabel();}
}
function render(){
 const root=document.getElementById('ol');
 if(!root||!driver()){view=null;return;}
 if(view!==root){view=root;activeOrder=null;void current();}
 root.querySelectorAll('button[data-act="delivered"]').forEach(done=>{
   const id=Number(done.dataset.id),actions=done.closest('.acts');
   if(!Number.isSafeInteger(id)||id<=0||!actions||actions.querySelector('[data-nav-order="'+id+'"]'))return;
   const button=document.createElement('button');
   button.type='button';button.dataset.navOrder=String(id);
   button.addEventListener('click',()=>void choose(id));
   actions.prepend(button);
 });
 updateLabel();
}
function schedule(){if(queued)return;queued=true;setTimeout(()=>{queued=false;render();},100);}
function boot(){
 if(!document.body)return;
 new MutationObserver(schedule).observe(document.body,{childList:true,subtree:true});
 schedule();
 setInterval(()=>{if(document.visibilityState==='visible'&&driver()&&document.getElementById('ol'))void current();},12000);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();