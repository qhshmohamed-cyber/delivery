'use strict';
// Intentionally uses a public client only, never an employee's stored session.
const FEEDBACK_API = 'https://mkptmejkcemdhlhdaort.supabase.co';
const FEEDBACK_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1rcHRtZWprY2VtZGhsaGRhb3J0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQwODE2MTQsImV4cCI6MjEwOTY1NzYxNH0.ovPRrF8RDXPut2jY8HMHdO27sFvxmyDymBVAKBV7mC8';
const by = id => document.getElementById(id);
const formId = new URLSearchParams(location.search).get('f');
if('serviceWorker' in navigator)void navigator.serviceWorker.getRegistration().then(r=>r?.update()).catch(()=>{});
let pending = null, busy = false;
function digits(value){return value.replace(/[٠-٩]/g,c=>String(c.charCodeAt(0)-1632)).replace(/[۰-۹]/g,c=>String(c.charCodeAt(0)-1776));}
async function rpc(name,payload){
 const response=await fetch(FEEDBACK_API+'/rest/v1/rpc/'+name,{method:'POST',credentials:'omit',cache:'no-store',referrerPolicy:'no-referrer',headers:{'Content-Type':'application/json',apikey:FEEDBACK_KEY,Authorization:'Bearer '+FEEDBACK_KEY},body:JSON.stringify(payload),signal:AbortSignal.timeout(20000)});
 if(!response.ok)throw Error('تعذر إتمام الاتصال. حاول مرة أخرى بعد قليل.');return response.json();
}
function safeLogo(value){try{const u=new URL(value,location.href);return u.protocol==='https:'?u.href:null;}catch{return null;}}
function color(value,fallback){return /^#[0-9a-f]{6}$/i.test(value||'')?value:fallback;}
async function init(){
 try{
  if(!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(formId||''))throw Error('رابط النموذج غير صحيح. اطلب الكود الصحيح من المطعم.');
  const config=await rpc('dlv_feedback_config',{p_form:formId});
  if(!config?.available||!config.branches?.length)throw Error('هذا النموذج غير متاح حاليًا. تواصل مع المطعم.');
  by('company').textContent=config.company_name;document.title='الشكاوى والمقترحات — '+config.company_name;
  document.documentElement.style.setProperty('--brand',color(config.brand_color,'#5a3317'));
  document.documentElement.style.setProperty('--gold',color(config.gold_color,'#b9832e'));
  const logo=safeLogo(config.logo_url);if(logo){by('logo').src=logo;by('logo').alt='شعار '+config.company_name;by('logo').hidden=false;}
  by('branch').replaceChildren(new Option('اختر الفرع',''),...config.branches.map(b=>new Option(b.name,String(b.id))));
  if(config.branch_id||config.branches.length===1){by('branch').value=String(config.branch_id||config.branches[0].id);}
  by('status').hidden=true;by('feedbackForm').hidden=false;
 }catch(e){by('status').textContent=e.message||'تعذر تحميل النموذج. أعد المحاولة.';}
}
by('feedbackForm').addEventListener('submit',async event=>{
 event.preventDefault();if(busy)return;by('error').textContent='';
 if(by('website').value)return;
 const phone=digits(by('phone').value).replace(/[ +()-]/g,'');
 if(!/^[0-9]{8,15}$/.test(phone)){by('error').textContent='اكتب رقم هاتف صحيحًا للتواصل.';return;}
 const payload={p_form:formId,p_branch:Number(by('branch').value),p_name:by('name').value.trim(),p_phone:phone,p_kind:by('kind').value,p_message:by('message').value.trim(),p_order:by('order').value.trim()||null};
 if(!payload.p_branch||payload.p_name.length<2||payload.p_message.length<10||!by('consent').checked){by('error').textContent='اختر الفرع وأكمل البيانات والموافقة. نص الرسالة 10 أحرف على الأقل.';return;}
 const fingerprint=JSON.stringify(payload);if(!pending||pending.fingerprint!==fingerprint)pending={fingerprint,id:crypto.randomUUID()};
 busy=true;by('send').disabled=true;by('send').textContent='جارٍ إرسال رسالتك…';
 try{
  const result=await rpc('dlv_submit_public_feedback',{...payload,p_request:pending.id});
  if(!result?.success)throw Error(result?.message||'لم يتم حفظ الرسالة، حاول مرة أخرى.');
  by('receipt').textContent=result.receipt;
  by('registeredAt').textContent='وقت التسجيل: '+new Date(result.created_at).toLocaleString('ar-EG',{timeZone:'Africa/Cairo'})+' — بتوقيت القاهرة';
  by('feedbackForm').hidden=true;by('success').hidden=false;pending=null;
 }catch(e){by('error').textContent=e.name==='TimeoutError'?'انقطع الاتصال قبل التأكد من الحفظ. أعد الإرسال بنفس البيانات؛ لن تُكرر الرسالة.':e.message||'تعذر الاتصال. أعد الإرسال بنفس البيانات.';}
 finally{busy=false;by('send').disabled=false;by('send').textContent='إرسال الرسالة';}
});
by('another').onclick=()=>{by('feedbackForm').reset();by('success').hidden=true;by('feedbackForm').hidden=false;pending=null;by('name').focus();};
void init();
