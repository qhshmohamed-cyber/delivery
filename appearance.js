(function(root){
 'use strict';
 const targets={
  text:['النصوص الأساسية','#app :is(p,label,td,li),#app .card'],
  headings:['العناوين','#app :is(h1,h2,h3),#app .ord b'],
  muted:['النصوص المساعدة','#app :is(.meta,small,.stat span)'],
  cards:['مربعات وبطاقات البيانات','#app :is(.card,.stat,.ys-operations-bar)'],
  inputs:['خانات الكتابة والقوائم','body.ys-tenant :is(input:not([type=color]):not([type=checkbox]):not([type=radio]),select,textarea)'],
  buttons:['الأزرار العادية','#app button:not(.p):not(.g)'],
  primary:['الأزرار الأساسية','#app button.p'],
  gold:['الأزرار الثانوية','#app button.g'],
  header:['مربع الحساب وأزراره','#app .ys-app-header,#app .ys-app-header :is(h1,small,span,div,button)']
 };
 const tag='(?:div|section|header|nav|main|aside|article|form|details|summary|table|thead|tbody|tr|td|th|ul|ol|li|label|input|select|textarea|button|h1|h2|h3|p|small|span|strong|b|a)';
 const pathPattern=new RegExp('^path:([a-z_]{1,32}):('+tag+':nth-of-type\\([1-9][0-9]{0,2}\\)(?:>'+tag+':nth-of-type\\([1-9][0-9]{0,2}\\)){0,11})$');
 const color=v=>typeof v==='string'&&/^#[a-f0-9]{6}$/i.test(v);
 const numeric=(v,min,max)=>typeof v==='number'&&Number.isFinite(v)&&v>=min&&v<=max;
 function normalize(input){
  const result={};if(!input||typeof input!=='object'||Array.isArray(input))return result;
  for(const [key,value] of Object.entries(input).slice(0,120)){
   if(!Object.hasOwn(targets,key)&&!pathPattern.test(key))continue;
   if(!value||typeof value!=='object'||Array.isArray(value))continue;
   const rule={};
   for(const prop of ['color','background','border'])if(color(value[prop]))rule[prop]=value[prop].toLowerCase();
   for(const [prop,min,max] of [['size',14,32],['padding',8,28],['radius',0,28]])if(numeric(value[prop],min,max))rule[prop]=value[prop];
   if([400,500,600,700].includes(value.weight))rule.weight=value.weight;
   if(Object.keys(rule).length)result[key]=rule;
  }
  return result;
 }
 function luminance(hex){return [1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4).reduce((n,v,i)=>n+v*[.2126,.7152,.0722][i],0);}
 function contrast(a,b){const x=luminance(a),y=luminance(b);return (Math.max(x,y)+.05)/(Math.min(x,y)+.05);}
 function ink(bg){return contrast('#000000',bg)>=contrast('#ffffff',bg)?'#000000':'#ffffff';}
 function selector(key){
  if(Object.hasOwn(targets,key))return targets[key][1];
  const match=key.match(pathPattern);return match?'body[data-ys-view="'+match[1]+'"] #app>'+match[2]:'';
 }
 function css(input){
  return Object.entries(normalize(input)).sort(([a],[b])=>Number(a.startsWith('path:'))-Number(b.startsWith('path:'))).map(([key,v])=>{
   let declarations='';
   if(v.color)declarations+='--ys-on-card:'+v.color+';--ys-muted-card:'+v.color+';--text:'+v.color+';--muted:'+v.color+';';
   if(v.background)declarations+='--card:'+v.background+';';
   for(const [prop,style] of [['color','color'],['background','background-color'],['border','border-color']])if(v[prop])declarations+=style+':'+v[prop]+'!important;';
   for(const [prop,style] of [['size','font-size'],['padding','padding'],['radius','border-radius']])if(v[prop]!==undefined)declarations+=style+':'+v[prop]+'px!important;';
   if(v.weight)declarations+='font-weight:'+v.weight+'!important;';
   // A path or category always stays under the authenticated company surface.
   const scoped='html body.ys-tenant :is('+selector(key)+')';
   return scoped+'{'+declarations+'}';
  }).join('\n');
 }
 function apply(input){
  let style=document.getElementById('ysCompanyAppearance');
  if(!style){style=document.createElement('style');style.id='ysCompanyAppearance';document.head.appendChild(style);}
  style.textContent=css(input);
 }
 function targetFor(element,app,view){
  if(!/^[a-z_]{1,32}$/.test(view))return '';
  const path=[];let node=element;
  while(node&&node!==app){
   const name=node.tagName?.toLowerCase();if(!name)return '';
   const siblings=Array.from(node.parentElement?.children||[]).filter(s=>s.tagName===node.tagName);
   path.unshift(name+':nth-of-type('+(siblings.indexOf(node)+1)+')');node=node.parentElement;
   if(path.length>12)return '';
  }
  const key='path:'+view+':'+path.join('>');return node===app&&pathPattern.test(key)?key:'';
 }
 function open({config,brand,onSave}){
  if(document.getElementById('ysAppearanceEditor'))return;
  let original=normalize(config),draft=normalize(config),busy=false,picking=false,chosen='text';
  const modal=document.createElement('div');modal.id='ysAppearanceEditor';modal.className='modal';modal.setAttribute('role','dialog');modal.setAttribute('aria-modal','true');modal.setAttribute('aria-label','الخط والألوان والخانات');
  modal.innerHTML='<div><div class="ya-head"><h2>الخط والألوان والخانات</h2><button type="button" data-close>إغلاق</button></div><p data-help>التعديلات تخص هذه الشركة وفروعها فقط. اختَر نوع العناصر، أو اضغط اختيار خانة ثم المسها في الصفحة.</p><div data-editor-form><label for="yaTarget">العنصر المراد تعديله</label><select id="yaTarget"></select><button type="button" data-pick>⌖ اختيار خانة من الصفحة</button><div class="ya-grid"><div><label for="yaSize">حجم الخط <output id="yaSizeValue"></output></label><input id="yaSize" type="range" min="14" max="32" step="1"></div><div><label for="yaWeight">سُمك الخط</label><select id="yaWeight"><option value="400">عادي</option><option value="500">متوسط</option><option value="600">واضح</option><option value="700">عريض</option></select></div><div><label for="yaColor">لون الخط</label><input id="yaColor" type="color"></div><div><label for="yaBackground">لون مربع الخانة</label><input id="yaBackground" type="color"></div><div><label for="yaBorder">لون حدود المربع</label><input id="yaBorder" type="color"></div><div><label for="yaPadding">مساحة الخانة <output id="yaPaddingValue"></output></label><input id="yaPadding" type="range" min="8" max="28" step="1"></div><div><label for="yaRadius">استدارة المربع <output id="yaRadiusValue"></output></label><input id="yaRadius" type="range" min="0" max="28" step="1"></div></div><div data-preview>معاينة: متابعة الطلبات — رقم الطلب ١٢٣<br>كلام واضح داخل مربع الخانة</div><p data-help data-contrast></p><button type="button" data-auto>اختيار لون خط واضح تلقائيًا</button><button type="button" data-reset>استعادة الشكل الأصلي لهذا العنصر</button><p data-help>اختيار خانة يخص مكانها في هذه الشاشة. عناصر الصفوف المتكررة تتبع مكان الصف، ولا تُحفظ بيانات موظف أو عميل ضمن إعدادات المظهر.</p></div><p data-status role="status" aria-live="polite"></p><div class="ya-actions"><button type="button" data-save>حفظ المظهر للشركة</button><button type="button" data-cancel>إلغاء التغييرات</button><button type="button" data-reset-all>استعادة مظهر الشركة الافتراضي</button></div></div>';
  document.body.appendChild(modal);
  const $=s=>modal.querySelector(s),by=id=>modal.querySelector('#'+id);
  const previousFocus=document.activeElement;
  const status=(message,error=false)=>{$('[data-status]').textContent=message;$('[data-status]').dataset.error=String(error);};
  function options(){
   const select=by('yaTarget');select.replaceChildren();
   for(const key of [...Object.keys(targets),...Object.keys(draft).filter(k=>k.startsWith('path:')),...(chosen.startsWith('path:')&&!draft[chosen]?[chosen]:[])]){
    const option=document.createElement('option');option.value=key;option.textContent=targets[key]?.[0]||'خانة محددة · '+key.split(':')[1]+' · '+key.split('>').at(-1);select.appendChild(option);
   }
   select.value=chosen;
  }
  function defaults(key){
   const bg=(key==='primary'?brand.brand_color:key==='gold'?brand.gold_color:brand.card_color)||'#1b1d20';
   const element=document.querySelector(selector(key));const computed=element?getComputedStyle(element):null;
   return {size:Math.max(14,Math.min(32,parseFloat(computed?.fontSize)||16)),weight:600,color:ink(bg),background:bg,border:brand.gold_color||'#b9832e',padding:12,radius:12};
  }
  function values(){return {size:Number(by('yaSize').value),weight:Number(by('yaWeight').value),color:by('yaColor').value,background:by('yaBackground').value,border:by('yaBorder').value,padding:Number(by('yaPadding').value),radius:Number(by('yaRadius').value)};}
  function preview(){
   const v=values();const node=$('[data-preview]');
   Object.assign(node.style,{fontSize:v.size+'px',fontWeight:v.weight,color:v.color,backgroundColor:v.background,borderColor:v.border,padding:v.padding+'px',borderRadius:v.radius+'px'});
   for(const name of ['Size','Padding','Radius'])by('ya'+name+'Value').textContent=by('ya'+name).value+' px';
   const ratio=contrast(v.color,v.background);$('[data-contrast]').textContent='وضوح النص: '+ratio.toFixed(1)+' : 1 — '+(ratio>=4.5?'واضح':'ضعيف؛ غيّر لون الخط أو المربع');
   return ratio;
  }
  function load(){const v={...defaults(chosen),...draft[chosen]};for(const name of ['size','weight','color','background','border','padding','radius'])by('ya'+name[0].toUpperCase()+name.slice(1)).value=v[name];preview();}
  function edit(){
   if(busy)return;const ratio=preview();
   if(ratio<4.5){status('الألوان المختارة تخفي الكلام. لم تُطبق على الصفحة؛ استخدم زر اللون الواضح التلقائي.',true);return;}
   draft[chosen]=values();apply(draft);status('معاينة فقط — اضغط حفظ لتطبيقها على حسابات الشركة.');
  }
  function stopPicking(){picking=false;modal.classList.remove('ya-picking');document.body.classList.remove('ya-picking');modal.setAttribute('aria-modal','true');document.removeEventListener('click',pick,true);}
  function close(restore=true){stopPicking();if(restore)apply(original);document.removeEventListener('keydown',keyDown);modal.remove();previousFocus?.focus?.();}
  function keyDown(event){if(event.key==='Escape'&&!busy){event.preventDefault();if(picking){stopPicking();status('تم إلغاء اختيار الخانة.');}else close();}}
  function pick(event){
   if(modal.contains(event.target))return;
   event.preventDefault();event.stopImmediatePropagation();
   const element=event.target.closest('input,select,textarea,button,label,h1,h2,h3,p,small,td,th,.meta,.card,.stat');
   const app=document.getElementById('app');const key=element&&app?.contains(element)?targetFor(element,app,document.body.dataset.ysView||'staff'):'';
   if(!key){status('اختَر خانة داخل شاشة التشغيل، أو استخدم أنواع العناصر من القائمة.',true);return;}
   chosen=key;stopPicking();options();load();status('تم تحديد الخانة. عدّل شكلها ثم احفظ.');by('yaTarget').focus();
  }
  by('yaTarget').onchange=()=>{chosen=by('yaTarget').value;load();status('');};
  for(const name of ['Size','Weight','Color','Background','Border','Padding','Radius'])by('ya'+name).oninput=edit;
  $('[data-auto]').onclick=()=>{by('yaColor').value=ink(by('yaBackground').value);edit();};
  $('[data-pick]').onclick=()=>{if(busy)return;picking=true;modal.classList.add('ya-picking');document.body.classList.add('ya-picking');modal.setAttribute('aria-modal','false');status('المس الخانة المطلوبة. إغلاق أو Escape يلغي الاختيار.');document.addEventListener('click',pick,true);};
  $('[data-reset]').onclick=()=>{delete draft[chosen];apply(draft);load();status('استُعيد الشكل الافتراضي لهذا العنصر في المعاينة. احفظ للاعتماد.');};
  $('[data-reset-all]').onclick=()=>{draft={};chosen='text';apply(draft);options();load();status('تمت استعادة المظهر الافتراضي في المعاينة. احفظ للاعتماد.');};
  $('[data-save]').onclick=async()=>{
   if(busy)return;if(preview()<4.5)return status('اختر لون خط أو خلفية أوضح قبل الحفظ.',true);
   busy=true;modal.querySelectorAll('button,input,select').forEach(el=>el.disabled=true);status('جارٍ حفظ مظهر الشركة…');
   try{const saved=await onSave(normalize(draft));if(!modal.isConnected)return;original=normalize(saved||draft);draft=normalize(original);apply(original);status('تم الحفظ للشركة وفروعها.');}
   catch(error){if(modal.isConnected)status(error.message||'تعذر الحفظ. إعدادات الشركة السابقة ما زالت محفوظة.',true);}
   finally{busy=false;if(modal.isConnected)modal.querySelectorAll('button,input,select').forEach(el=>el.disabled=false);}
  };
  $('[data-close]').onclick=$('[data-cancel]').onclick=()=>{if(!busy)close();};
  modal.addEventListener('private-session-ended',()=>close(false),{once:true});
  document.addEventListener('keydown',keyDown);options();load();by('yaTarget').focus();
 }
 const api={normalize,css,contrast,ink,targetFor,apply,open};
 if(typeof module==='object'&&module.exports)module.exports=api;else root.YourStaffAppearance=api;
})(globalThis);
