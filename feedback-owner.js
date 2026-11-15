'use strict';
// Uses the application's existing owner session and server-side owner verification.
async function openFeedbackQr(companyId,branchId=null){
 if(!isOwner())return flash('هذه الخاصية لمالك المنصة فقط',false);
 const d=document.createElement('div');d.className='modal';
 const panel=document.createElement('div');panel.style.cssText='max-width:650px;width:100%;background:#fff8ea;color:#291b10;padding:22px;border-radius:20px;max-height:94vh;overflow:auto';d.append(panel);
 const heading=document.createElement('h2');heading.textContent='QR الشكاوى والمقترحات';panel.append(heading);
 const status=document.createElement('p');status.setAttribute('role','status');status.textContent='جارٍ تجهيز رابط الشركة…';panel.append(status);
 const close=document.createElement('button');close.textContent='إغلاق';close.type='button';close.onclick=()=>d.remove();panel.append(close);document.body.append(d);
 try{
  const result=await safeRpc('dlv_owner_feedback_form',{p_company:Number(companyId),p_branch:branchId===null?null:Number(branchId)});
  if(result.error||!result.data?.form_id)throw Error(result.error?.message||'تعذر إنشاء رابط الشكاوى');
  const configResult=await safeRpc('dlv_feedback_config',{p_form:result.data.form_id});
  if(configResult.error)throw Error('تعذر تحميل هوية الشركة');
  const config=configResult.data;
  const brand=ownerBrandCache.get(Number(companyId))||{};
  const companyName=config?.company_name||brand.brand_name||'الشركة';
  const branchName=branchId===null?'جميع الفروع — العميل يختار الفرع':(config?.branches||[]).find(x=>Number(x.id)===Number(branchId))?.name||branchNames[branchId]||'الفرع';
  const url=new URL('feedback.html',location.href);url.search='';url.hash='';url.searchParams.set('f',result.data.form_id);
  status.textContent=(config?.available?'العميل يسجل رسالته مباشرة، وتظهر داخل الفرع المصرح به.':'تم إنشاء الرابط. استقبال الرسائل يبدأ بعد تفعيل الشركة والفرع.')+' '+branchName;
  const qr=qrcode(0,'M');qr.addData(url.href,'Byte');qr.make();
  const canvas=document.createElement('canvas');canvas.width=1200;canvas.height=1600;canvas.style.cssText='width:100%;height:auto;display:block;margin:16px 0';panel.insertBefore(canvas,close);
  const ctx=canvas.getContext('2d');const safeColor=(v,f)=>/^#[0-9a-f]{6}$/i.test(v||'')?v:f;
  const primary=safeColor(config?.brand_color||brand.brand_color,'#5a3317'),gold=safeColor(config?.gold_color||brand.gold_color,'#b9832e');
  ctx.fillStyle='#fff8ea';ctx.fillRect(0,0,1200,1600);ctx.fillStyle=primary;ctx.fillRect(0,0,1200,370);ctx.fillStyle=gold;ctx.fillRect(0,365,1200,8);
  let logoUrl=config?.logo_url||brand.logo_url;
  if(logoUrl){try{
   const parsed=new URL(logoUrl,location.href);if(parsed.protocol!=='https:')throw Error('logo');
   const img=new Image();img.crossOrigin='anonymous';img.referrerPolicy='no-referrer';
   await new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=reject;img.src=parsed.href;setTimeout(()=>reject(Error('timeout')),10000);});
   ctx.fillStyle='#fff8ea';ctx.fillRect(500,32,200,200);const scale=Math.min(184/img.width,184/img.height);ctx.drawImage(img,600-img.width*scale/2,132-img.height*scale/2,img.width*scale,img.height*scale);
  }catch{ /* The QR and company name remain usable if a remote logo fails. */ }}
  const text=(t,y,size,color='#291b10')=>{ctx.fillStyle=color;ctx.textAlign='center';ctx.direction='rtl';ctx.font='bold '+size+'px Tahoma, Arial, sans-serif';ctx.fillText(t,600,y,1100);};
  const rgb=primary.slice(1).match(/../g).map(h=>parseInt(h,16));const onPrimary=(rgb[0]*.299+rgb[1]*.587+rgb[2]*.114)>160?'#21170e':'#ffffff';
  text(companyName,310,58,onPrimary);text('تسجيل الشكاوى والمقترحات',455,52);text(branchName,522,32);
  const n=qr.getModuleCount(),scale=Math.floor(780/(n+8)),size=(n+8)*scale,x=(1200-size)/2,y=580;
  ctx.fillStyle='#ffffff';ctx.fillRect(x,y,size,size);ctx.fillStyle='#000000';
  for(let row=0;row<n;row++)for(let col=0;col<n;col++)if(qr.isDark(row,col))ctx.fillRect(x+(col+4)*scale,y+(row+4)*scale,scale,scale);
  text('امسح الكود واكتب رسالتك مباشرة',1420,45);text('بدون حساب أو كود متابعة طلب',1490,34);text('بياناتك متاحة لفريق المتابعة المختص فقط',1550,28);
  const link=document.createElement('a');link.href=url.href;link.target='_blank';link.rel='noopener noreferrer';link.textContent='فتح صفحة العميل للاختبار';link.style.cssText='display:block;color:#44300f;text-decoration:underline;margin:10px 0';panel.insertBefore(link,close);
  const save=document.createElement('button');save.type='button';save.textContent='حفظ صورة QR بالشعار والألوان';save.onclick=()=>{try{const a=document.createElement('a');a.download='complaints-qr.png';a.href=canvas.toDataURL('image/png');a.click();}catch{flash('تعذر حفظ الصورة بسبب إعدادات الشعار. افتح الصفحة واطبع الكود.',false);}};panel.insertBefore(save,close);
  const copy=document.createElement('button');copy.type='button';copy.textContent='نسخ رابط الشكاوى';copy.onclick=async()=>{try{await navigator.clipboard.writeText(url.href);copy.textContent='تم نسخ الرابط';}catch{status.textContent=url.href;}};panel.insertBefore(copy,close);
 }catch(e){status.textContent=e.message||'تعذر تجهيز الكود؛ حاول مرة أخرى.';}
}
