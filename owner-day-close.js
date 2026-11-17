/* Your Staff Delivery - owner-only day close panel.
 * Integration: window.YourStaffDayClose.mount({root, supabase, branchId, ownerVerified:true})
 * DO NOT replace production index.html. Mount only inside verified owner dashboard.
 */
(function(){
'use strict';
function el(tag,text){const x=document.createElement(tag);if(text!==undefined)x.textContent=String(text);return x;}
function isoDay(d){return new Intl.DateTimeFormat('en-CA',{timeZone:'Africa/Cairo',year:'numeric',month:'2-digit',day:'2-digit'}).format(d);}
function mount({root,supabase,branchId,ownerVerified}={}){
 if(!root||!supabase||!Number.isInteger(Number(branchId))||!ownerVerified)throw Error('Owner dashboard context required');
 const b=Number(branchId),wrap=el('section'),heading=el('h3','تقفيل اليوم وأرشيف التقارير'),date=el('input'),check=el('button','فحص اليوم'),close=el('button','قفل اليوم'),archive=el('button','عرض الأرشيف'),notice=el('p'),list=el('div');
 date.type='date';date.value=isoDay(new Date(Date.now()-86400000));close.disabled=true;
 wrap.setAttribute('dir','rtl');wrap.style.cssText='border:1px solid currentColor;border-radius:12px;padding:12px;margin:12px 0';
 [heading,date,check,close,archive,notice,list].forEach(x=>wrap.appendChild(x));root.appendChild(wrap);
 let checked=null,busy=false;
 function message(s){notice.textContent=s;}
 async function rpc(name,args){const {data,error}=await supabase.rpc(name,args);if(error)throw error;return data;}
 async function inspect(){
  close.disabled=true;checked=null;busy=true;
  try{const d=await rpc('dlv_owner_day_close_status',{p_branch_id:b,p_day:date.value});
    checked=d;message('الطلبات: '+d.total_orders+' | غير المنتهية: '+d.unfinished_orders+' | '+(d.closed?'اليوم مقفول':d.eligible?'جاهز للإقفال':'غير جاهز'));
    close.disabled=!d.eligible;
  }catch(e){message('تعذر الفحص: '+e.message);}finally{busy=false;}
 }
 date.addEventListener('change',()=>{checked=null;close.disabled=true;message('اضغط فحص اليوم أولاً');});
 check.addEventListener('click',()=>{if(!busy)inspect();});
 close.addEventListener('click',async()=>{
  if(busy||!checked||!checked.eligible||checked.day!==date.value)return;
  if(!window.confirm('تأكيد قفل يوم '+date.value+' للفرع المحدد؟ لا يمكن إضافة طلبات لهذا اليوم بعد الإقفال.'))return;
  close.disabled=true;busy=true;
  try{const r=await rpc('dlv_close_day',{p_branch_id:b,p_day:date.value});
   message(r.already_closed?'اليوم مقفول بالفعل':'تم إقفال اليوم وحفظ التقرير');await inspect();
  }catch(e){message('فشل الإقفال: '+e.message);}finally{busy=false;}
 });
 archive.addEventListener('click',async()=>{
  list.replaceChildren();try{const items=await rpc('dlv_owner_day_close_archive',{p_branch_id:b,p_limit:90});
   if(!items.length){list.textContent='لا توجد تقارير مؤرشفة';return;}
   items.forEach(item=>{const line=el('div',item.day+' — '+(item.closed?'مقفول':'تقرير مؤرشف فقط'));line.style.padding='6px';list.appendChild(line);});
  }catch(e){message('تعذر عرض الأرشيف: '+e.message);}
 });
 message('حدد اليوم ثم اضغط فحص اليوم. الأرشيف يعرض الأيام دون تفاصيل العملاء.');
 return {destroy(){wrap.remove();}};
}
window.YourStaffDayClose={mount};
})();