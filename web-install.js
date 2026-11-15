(function(root){
 'use strict';
 function createInstallController({secure=true,installed=false}={}){
  let deferred=null,busy=false;
  return {
   capture(event){deferred=event;},
   installed(){installed=true;deferred=null;},
   async request(){
    if(!secure)return 'insecure';
    if(installed)return 'installed';
    if(busy)return 'busy';
    if(!deferred)return 'manual';
    const event=deferred;deferred=null;busy=true;
    try{await event.prompt();const choice=await event.userChoice;return choice?.outcome==='accepted'?'accepted':'dismissed';}
    catch(_){return 'error';}
    finally{busy=false;}
   }
  };
 }
 if(typeof module==='object'&&module.exports){module.exports={createInstallController};return;}
 const bar=document.getElementById('webInstallBar'),button=document.getElementById('webInstallButton');
 if(!bar||!button)return;
 // Customer tracking links never display an app installation prompt.
 const tracking=new URL(location.href).searchParams.has('t');
 const standalone=()=>window.matchMedia('(display-mode: standalone)').matches||navigator.standalone===true;
 const controller=createInstallController({secure:window.isSecureContext,installed:standalone()});
 const update=()=>{bar.hidden=tracking||standalone()||!window.isSecureContext;bar.style.display=bar.hidden?'none':'flex';};
 update();
 window.addEventListener('beforeinstallprompt',event=>{if(tracking||standalone())return;event.preventDefault();controller.capture(event);update();});
 window.addEventListener('appinstalled',()=>{controller.installed();bar.hidden=true;bar.style.display='none';document.getElementById('webInstallHelp')?.remove();});
 function help(message){
  if(document.getElementById('webInstallHelp'))return;
  const dialog=document.createElement('div');dialog.id='webInstallHelp';dialog.className='modal';dialog.style.zIndex='120';dialog.setAttribute('role','dialog');dialog.setAttribute('aria-modal','true');dialog.setAttribute('aria-labelledby','webInstallTitle');
  dialog.innerHTML='<div><h2 id="webInstallTitle">تثبيت Your Staff من المتصفح</h2><p data-install-result></p><p>نفس حسابك وشركتك وفرعك، مع أيقونة على الشاشة الرئيسية. التشغيل يحتاج اتصالًا بالإنترنت.</p><ol><li>على Android: افتح رابط النظام في Chrome، ثم القائمة ⋮ ← تثبيت التطبيق أو إضافة إلى الشاشة الرئيسية.</li><li>على iPhone: افتح الرابط في Safari ← مشاركة ← إضافة إلى الشاشة الرئيسية.</li></ol><p>لو الرابط مفتوح داخل واتساب أو تطبيق آخر، افتحه في المتصفح أولًا. هذه الطريقة لا تحتاج تنزيل ملف APK أو تغيير إعدادات حماية الجهاز.</p><div class="row"><button type="button" data-copy-install-link>نسخ رابط النظام</button><button type="button" data-close-install-help>إغلاق</button></div><p data-copy-status role="status"></p></div>';
  dialog.querySelector('[data-install-result]').textContent=message;
  document.body.appendChild(dialog);dialog.querySelector('[data-close-install-help]').onclick=()=>{dialog.remove();button.focus();};
  dialog.querySelector('[data-copy-install-link]').onclick=async()=>{
   const status=dialog.querySelector('[data-copy-status]');
   try{await navigator.clipboard.writeText(new URL('./',location.href).href);status.textContent='تم نسخ رابط النظام.';}
   catch(_){status.textContent='تعذر النسخ تلقائيًا. انسخ عنوان الموقع من شريط المتصفح.';}
  };
  dialog.querySelector('[data-close-install-help]').focus();
 }
 button.onclick=async()=>{
  button.disabled=true;
  const result=await controller.request();button.disabled=false;
  if(result==='manual')help('إذا لم يظهر زر تثبيت المتصفح، استخدم الخطوات التالية.');
  else if(result==='error')help('تعذر فتح نافذة التثبيت. يمكنك المحاولة من قائمة المتصفح.');
  else if(result==='accepted')button.textContent='جارٍ إكمال التثبيت في المتصفح…';
  else if(result==='installed'){bar.hidden=true;bar.style.display='none';}
 };
})(globalThis);
