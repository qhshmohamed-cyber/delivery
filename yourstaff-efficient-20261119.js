/* Your Staff Delivery – horizontal, tenant-branded stage dashboard
 * Add after the application's existing inline script; do not replace index.html.
 * Uses the authenticated, branch-scoped dlv_manager_stage_bars RPC.
 */
(() => {
  'use strict';
  if(window.__ysBrandPerformance20261118Loaded)return;
  window.__ysBrandPerformance20261118Loaded=true;
  const ID = 'ys-brand-stage-bars';
  const VERSION = '2026-11-18';
  let requestNo = 0;
  let loadedKey = '';
  let dayOverride = '';
  let showAllHours = false;
  let scheduled = false;
  let lastUpdateAt = 0;

  const html = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const num = v => Number.isFinite(Number(v)) ? Number(v) : 0;
  const clamp = v => Math.max(0,Math.min(100,num(v)));
  const color = (v,fallback) => /^#[0-9a-f]{6}$/i.test(String(v||'')) ? String(v) : fallback;
  const escWidth = v => `${clamp(v).toFixed(1)}%`;
  const ar = n => new Intl.NumberFormat('ar-EG',{maximumFractionDigits:1}).format(num(n));
  const percent = n => n===null || n===undefined ? '—' : `${ar(n)}%`;
  const hourText = h => `${ar(Number(h)%12||12)} ${Number(h)<12?'ص':'م'}`;
  const onScreen = () => document.getElementById(ID)?.isConnected;
  const required = () => {
    try {
      if (typeof me === 'undefined' || !me || typeof selectedBranch === 'undefined') return null;
      if (!(typeof isOwner === 'function' && isOwner()) && !(typeof isLocationManager === 'function' && isLocationManager())) return null;
      const branch = Number(selectedBranch);
      const anchor = document.getElementById('managerLiveKpi');
      if (!Number.isInteger(branch) || branch < 1 || !anchor || !anchor.isConnected) return null;
      return {branch,user:String(me.user_id),anchor};
    } catch (_) { return null; }
  };
  const operationalDay = () => {
    if (typeof reportOperationalDay === 'function') return reportOperationalDay();
    const f = new Intl.DateTimeFormat('en-CA',{timeZone:'Africa/Cairo',year:'numeric',month:'2-digit',day:'2-digit'});
    return f.format(new Date());
  };
  function injectStyle() {
    if (document.getElementById('ys-brand-bars-style')) return;
    const style = document.createElement('style');
    style.id = 'ys-brand-bars-style';
    style.textContent = `
      #${ID}{--ysbc:#5a3317;--ysgc:#b9832e;--ysbg:#fff8ea;--ysink:#322217;--ysmuted:#65503a;
        box-sizing:border-box;background:var(--ysbg)!important;color:var(--ysink)!important;
        border:2px solid var(--ysgc)!important;border-radius:18px;padding:16px;margin:14px 0;
        font-family:inherit;box-shadow:0 5px 18px #00000012}
      #${ID} *{box-sizing:border-box}
      #${ID} .ysb-head{display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin-bottom:14px}
      #${ID} .ysb-logo{height:58px;width:58px;object-fit:contain;background:#ffffffb8;border:1px solid #b9832e55;border-radius:12px;padding:5px}
      #${ID} .ysb-headtitle{flex:1;min-width:160px}
      #${ID} .ysb-headtitle h2{margin:0;color:var(--ysink)!important;font-size:18px;font-weight:900}
      #${ID} .ysb-meta{font-size:12px;opacity:.83;color:var(--ysmuted)!important;line-height:1.8}
      #${ID} .ysb-controls{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-bottom:12px}
      #${ID} button,#${ID} input{font:inherit;font-size:13px;border-radius:10px;padding:8px 10px}
      #${ID} button{cursor:pointer;background:var(--ysbc)!important;color:#fff!important;border:1px solid var(--ysbc)!important}
      #${ID} input{max-width:180px;min-height:36px;background:transparent;color:var(--ysink)!important;border:1px solid var(--ysgc)!important}
      #${ID} .ysb-legend{display:flex;gap:12px;flex-wrap:wrap;font-size:12px;margin-bottom:10px;color:var(--ysink)!important}
      #${ID} .ysb-swatch{display:inline-block;width:11px;height:11px;border-radius:3px;margin-inline-end:5px;vertical-align:middle}
      #${ID} .ysb-stage{padding:12px 0;border-top:1px solid var(--ysgc)}
      #${ID} .ysb-stage-head{display:flex;justify-content:space-between;gap:8px;flex-wrap:wrap;margin-bottom:8px;font-size:14px;color:var(--ysink)!important}
      #${ID} .ysb-barline{display:grid;grid-template-columns:56px minmax(0,1fr) 54px;align-items:center;gap:8px;margin-top:8px;font-size:12px;color:var(--ysink)!important}
      #${ID} .ysb-track{height:14px;border-radius:8px;overflow:hidden;background:#88888829;border:1px solid #77777732;direction:ltr}
      #${ID} .ysb-fill{height:100%;border-radius:8px;transition:width .35s ease}
      #${ID} .ysb-rate{text-align:left;font-variant-numeric:tabular-nums;font-weight:800}
      #${ID} .ysb-hours{margin-top:16px;padding-top:10px;border-top:2px solid var(--ysgc)}
      #${ID} .ysb-hours h3{font-size:15px;color:var(--ysink)!important;margin:0 0 10px}
      #${ID} .ysb-hour{padding:7px 0;border-bottom:1px solid #77777724}
      #${ID} .ysb-hour summary{list-style:none;display:grid;grid-template-columns:53px minmax(0,1fr) 37px;align-items:center;gap:9px;cursor:pointer;color:var(--ysink)!important;font-size:12px}
      #${ID} .ysb-hour summary::-webkit-details-marker{display:none}
      #${ID} .ysb-stack{height:17px;background:#88888829;display:flex;overflow:hidden;border-radius:9px;direction:ltr}
      #${ID} .ysb-stack>i{height:100%;display:block}
      #${ID} .ysb-hourdetails{padding:7px 10px;font-size:12px;color:var(--ysmuted)!important}
      #${ID} .ysb-footer{margin-top:12px;line-height:1.65;color:var(--ysmuted)!important;font-size:11px}
      #${ID} .ysb-status{font-size:12px;min-height:18px;margin:8px 0;color:var(--ysmuted)!important}
      #${ID} .ysb-empty{padding:14px;border:1px dashed var(--ysgc);border-radius:10px;font-size:13px;color:var(--ysink)!important}
      @media(max-width:550px){#${ID}{padding:12px}#${ID} .ysb-barline{grid-template-columns:49px minmax(0,1fr) 48px;gap:5px}}
      @media(prefers-reduced-motion:reduce){#${ID} .ysb-fill{transition:none}}
      @media print{#${ID}{break-inside:avoid;box-shadow:none}}
    `;
    document.head.appendChild(style);
  }
  function createPanel(anchor) {
    injectStyle();
    const node=document.createElement('section');
    node.id=ID;
    node.setAttribute('aria-label','مؤشر الالتزام والتأخير حسب الفرع');
    node.innerHTML=`<div class="ysb-head"><img class="ysb-logo" alt="شعار الشركة" hidden><div class="ysb-headtitle"><h2>📊 الالتزام والتأخير — تحليل الفرع</h2><div class="ysb-meta" data-brand-name></div></div></div>
      <div class="ysb-controls"><label for="ysb-day">يوم التشغيل</label><input id="ysb-day" type="date"><button data-refresh type="button">↻ تحديث</button></div>
      <div class="ysb-status" data-status aria-live="polite">جاري تحميل التقرير…</div><div data-body></div>`;
    anchor.insertAdjacentElement('afterend',node);
    const input=node.querySelector('#ysb-day');
    input.value=dayOverride||operationalDay();
    input.max=new Intl.DateTimeFormat('en-CA',{timeZone:'Africa/Cairo',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
    input.addEventListener('change',()=>{dayOverride=input.value; loadedKey='';void refresh(true);});
    node.querySelector('[data-refresh]').addEventListener('click',()=>void refresh(true));
    return node;
  }
  function paint(data,node) {
    if (!node || !node.isConnected) return;
    const t=data?.theme||{};
    const primary=color(t.brand,'#5a3317'), gold=color(t.gold,'#b9832e');
    const card=color(t.card,'#fff8ea');
    const rgb=card.slice(1).match(/.{2}/g).map(v=>parseInt(v,16));
    const dark=(rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722)<145;
    const ink=dark?'#fff7e8':'#322217', muted=dark?'#e6d4ba':'#65503a';
    node.style.setProperty('--ysbc',primary);node.style.setProperty('--ysgc',gold);
    node.style.setProperty('--ysbg',card);node.style.setProperty('--ysink',ink);node.style.setProperty('--ysmuted',muted);
    const logo=node.querySelector('.ysb-logo');
    if (logo) {
      const u=String(t.logo||'');
      const valid=u.startsWith('https://')||/^[\w./-]+$/.test(u)&&!u.startsWith('//');
      if(valid){logo.src=u;logo.hidden=false;logo.onerror=()=>{logo.hidden=true};}else{logo.hidden=true;logo.removeAttribute('src');}
    }
    node.querySelector('[data-brand-name]').textContent=`${data.company||'الشركة'} · ${data.branch||'الفرع'} · ${data.day||''}`;
    const stages=Array.isArray(data.stages)?data.stages:[];
    const hours=Array.isArray(data.hours)?data.hours:[];
    const tone3=mix(primary,gold,.53);
    const stageHtml=stages.map(x=>{
      const measured=num(x.measured), on=num(x.on_time), late=num(x.late);
      const a=measured>0?clamp(x.on_time_pct):0, b=measured>0?clamp(x.late_pct):0;
      const progress=(title,width,fill,value)=>`<div class="ysb-barline"><span>${title}</span><div class="ysb-track" role="meter" aria-label="${html(x.label)} ${title}" aria-valuenow="${width}" aria-valuemin="0" aria-valuemax="100"><div class="ysb-fill" style="width:${escWidth(width)};background:${fill}"></div></div><span class="ysb-rate">${value}</span></div>`;
      return `<div class="ysb-stage"><div class="ysb-stage-head"><strong>${html(x.label)}</strong><span>الحد ${ar(x.limit)} د · محسوبة ${ar(measured)} · متوسط ${x.average_minutes===null?'—':`${ar(x.average_minutes)} د`}</span></div>
        ${progress('التزام',a,gold,measured?percent(x.on_time_pct):'—')}
        ${progress('تأخير',b,primary,measured?percent(x.late_pct):'—')}
        <div class="ysb-meta">ملتزم ${ar(on)} · متأخر ${ar(late)}${!measured?' · لا توجد مراحل مكتملة قابلة للقياس':''}</div></div>`;
    }).join('');
    const max=Math.max(1,...hours.map(h=>num(h.total)));
    const nonzero=hours.filter(h=>num(h.total)>0);
    const filtered=showAllHours?hours:nonzero.sort((a,b)=>num(b.total)-num(a.total)).slice(0,8).sort((a,b)=>((num(a.hour)+19)%24)-((num(b.hour)+19)%24));
    const hourlyHtml=filtered.map(h=>{
      const k=num(h.kitchen),s=num(h.dispatch),d=num(h.delivery),total=num(h.total);
      return `<details class="ysb-hour"><summary title="اضغط لعرض التفاصيل"><strong>${hourText(h.hour)}</strong><div class="ysb-stack" aria-label="${html(hourText(h.hour))}: ${ar(total)} حالات تأخير">
        <i style="width:${escWidth(k/max*100)};background:${gold}"></i>
        <i style="width:${escWidth(s/max*100)};background:${primary}"></i>
        <i style="width:${escWidth(d/max*100)};background:${tone3}"></i></div><strong style="text-align:left">${ar(total)}</strong></summary>
        <div class="ysb-hourdetails">المطبخ ${ar(k)} · المشرف ${ar(s)} · الطيار ${ar(d)} (حسب ساعة إتمام المرحلة)</div></details>`;
    }).join('');
    const peak=nonzero.length?nonzero.reduce((a,b)=>num(b.total)>num(a.total)?b:a):null;
    node.querySelector('[data-body]').innerHTML=`<div class="ysb-legend"><span><i class="ysb-swatch" style="background:${gold}"></i>التزام</span><span><i class="ysb-swatch" style="background:${primary}"></i>تأخير</span><span>طلبات يوم التشغيل: <strong>${ar(data.total_orders)}</strong></span></div>
      ${stageHtml||'<div class="ysb-empty">لا توجد بيانات مراحل.</div>'}
      <div class="ysb-hours"><h3>⏰ ساعات زيادة التأخير</h3>
        <div class="ysb-legend"><span><i class="ysb-swatch" style="background:${gold}"></i>مطبخ</span><span><i class="ysb-swatch" style="background:${primary}"></i>مشرف</span><span><i class="ysb-swatch" style="background:${tone3}"></i>طيار</span></div>
        ${peak?`<div class="ysb-meta">أعلى ساعة تأخير: <strong>${hourText(peak.hour)}</strong> · ${ar(peak.total)} مراحل متأخرة</div>`:'<div class="ysb-empty">لا توجد مراحل متأخرة مسجلة في يوم التشغيل المختار.</div>'}
        ${hourlyHtml}${hours.length?`<button type="button" data-allhours style="margin-top:10px">${showAllHours?'عرض ساعات التأخير فقط':'عرض جميع ساعات اليوم'}</button>`:''}</div>
      <div class="ysb-footer">النسب تُحسب من المراحل المكتملة ذات التوقيتات الصحيحة فقط. يبدأ يوم التشغيل ٥ صباحًا وينتهي ٥ صباح اليوم التالي. قد يتأخر نفس الطلب في أكثر من مرحلة؛ أعداد الساعات هي حالات مراحل، وليست عدد طلبات فريدة. آخر تحديث: ${new Intl.DateTimeFormat('ar-EG',{timeZone:'Africa/Cairo',hour:'2-digit',minute:'2-digit'}).format(new Date())}</div>`;
    const btn=node.querySelector('[data-allhours]');
    if(btn) btn.addEventListener('click',()=>{showAllHours=!showAllHours;paint(data,node);});
    node.querySelector('[data-status]').textContent='تم تحميل البيانات حسب صلاحيات فرعك.';
  }
  function mix(a,b,w){
    const x=[a,b].map(c=>c.slice(1).match(/.{2}/g).map(v=>parseInt(v,16)));
    return '#'+x[0].map((v,i)=>Math.round(v*(1-w)+x[1][i]*w).toString(16).padStart(2,'0')).join('');
  }
  async function refresh(force=false){
    const ctx=required(),node=document.getElementById(ID);
    if(!ctx || !node || !node.isConnected || typeof safeRpc!=='function')return;
    const input=node.querySelector('#ysb-day');
    const day=input?.value||operationalDay();
    if(!/^\d{4}-\d{2}-\d{2}$/.test(day))return;
    const key=`${ctx.user}/${ctx.branch}/${day}`;
    if(!force && loadedKey===key && Date.now()-lastUpdateAt<60000)return;
    const token=++requestNo;
    const status=node.querySelector('[data-status]');
    if(status)status.textContent='جارٍ تحديث نسب الأداء…';
    try{
      const {data,error}=await safeRpc('dlv_manager_stage_bars',{p_branch:ctx.branch,p_day:day});
      const now=required();
      if(token!==requestNo || !node.isConnected || !now || now.user!==ctx.user || now.branch!==ctx.branch || (node.querySelector('#ysb-day')?.value)!==day)return;
      if(error)throw new Error(error.message||'تعذر تحميل التحليل');
      if(!data || Number(data.branch_id)!==ctx.branch || String(data.day)!==day || !Array.isArray(data.stages) || !Array.isArray(data.hours))throw new Error('البيانات لا تتطابق مع الفرع والتاريخ');
      loadedKey=key;lastUpdateAt=Date.now();paint(data,node);
    }catch(e){if(token!==requestNo || !node.isConnected)return;
      status.textContent='تعذر تحميل التحليل: '+String(e?.message||'خطأ غير معروف').slice(0,140);
    }
  }
  function updateOwnerLabel(){
    try{
      if(typeof isOwner!=='function'||!isOwner()||typeof me==='undefined')return;
      document.querySelectorAll('#app h2').forEach(h=>{
        if(h.textContent.trim()==='👑 تحكم المالك')h.textContent='👑 '+String(me.full_name||'مالك النظام')+' — مالك النظام';
      });
    }catch(_){/* no changes outside owner session */}
  }
  function sync(){
    scheduled=false;updateOwnerLabel();bindManagerMap();
    if(mapClose&&!mapScope())mapClose();
    const ctx=required();
    if(!ctx){loadedKey='';requestNo++;return;}
    let panel=document.getElementById(ID);
    if(!panel || !panel.isConnected || panel.previousElementSibling!==ctx.anchor){
      panel?.remove();panel=createPanel(ctx.anchor);loadedKey='';lastUpdateAt=0;
    }
    if(panel.dataset.branch!==String(ctx.branch)||panel.dataset.user!==ctx.user){
      panel.dataset.branch=String(ctx.branch);panel.dataset.user=ctx.user;
      dayOverride='';showAllHours=false;loadedKey='';lastUpdateAt=0;
      panel.querySelector('#ysb-day').value=operationalDay();
    }
    void refresh();
  }
  function schedule(){if(!scheduled){scheduled=true;requestAnimationFrame(sync);}}
  /* ---- Manager map: read only, scoped to one authorized branch via RPC. ---- */
  const LIVE_MAP_ID='ys-manager-map-live';
  let mapClose=null;
  const mapScope=()=>{
    try {
      if(typeof me==='undefined'||!me||typeof isLocationManager!=='function'||!isLocationManager())return null;
      const id=Number(selectedBranch);
      if(!Number.isInteger(id)||id<1||!document.getElementById('managerLiveKpi'))return null;
      return {user:String(me.user_id),branch:id};
    }catch(_){return null;}
  };
  function bindManagerMap(){
    const context=mapScope(),btn=document.getElementById('mp');
    if(!context||!btn||btn.dataset.ysGpsMapV2==='1')return;
    const oldHandler=btn.onclick;
    btn.dataset.ysGpsMapV2='1';
    btn.onclick=e=>{
      if(typeof L==='undefined'||typeof safeRpc!=='function'){
        if(typeof oldHandler==='function')return oldHandler.call(btn,e);
        return;
      }
      try{openManagerLiveMap();}
      catch(err){console.warn('Manager map unavailable',err);if(typeof oldHandler==='function')oldHandler.call(btn,e);}
    };
    btn.title='مواقع الطيارين في الفرع — تُعرض القراءة الحديثة فقط';
  }
  function openManagerLiveMap(){
    const scope=mapScope();if(!scope)return;
    const previous=document.getElementById(LIVE_MAP_ID);
    if(previous){previous.focus();return;}
    const panel=document.createElement('div');
    panel.id=LIVE_MAP_ID;panel.tabIndex=-1;panel.dir='rtl';
    panel.style.cssText='position:fixed;inset:0;z-index:70;background:var(--bg,#faf7ef);color:var(--brand,#54331f);display:flex;flex-direction:column;overflow:hidden;padding-top:env(safe-area-inset-top,0)';
    panel.setAttribute('role','dialog');panel.setAttribute('aria-modal','true');
    panel.setAttribute('aria-label','خريطة الطيارين المصرح بها لمدير الفرع');
    const brandTitle=(typeof brandConfig==='object'&&brandConfig)?String(brandConfig.brand_name||'الشركة'):'الشركة';
    const title=(typeof branchTitle==='function')?branchTitle(scope.branch):'الفرع';
    panel.innerHTML=`<div style="padding:12px 14px;background:var(--card,#fff8ea);border-bottom:2px solid var(--gold,#b9832e)">
      <div style="display:flex;gap:12px;align-items:center;justify-content:space-between;flex-wrap:wrap">
       <div><strong style="font-size:17px">🛵 خريطة طياري ${html(brandTitle)}</strong><div style="font-size:12px">${html(title)} · آخر موقع مسجل وليس مسارًا متوقعًا</div></div>
       <button type="button" data-map-close style="border-radius:8px;padding:9px 15px;background:var(--brand,#54331f);color:white;border:0">إغلاق</button>
      </div><div data-map-status role="status" aria-live="polite" style="padding-top:8px;font-size:12px">جاري تحميل المواقع المصرح بها…</div></div>
      <div data-map-canvas style="flex:1;min-height:240px"></div>
      <div style="padding:8px 14px;background:var(--card,#fff8ea);font-size:11px">أخضر: قراءة خلال دقيقة · رمادي: آخر قراءة خلال 5 دقائق · الأقدم لا يُعرض على الخريطة. يتطلب استمرار GPS فتح صفحة الطيار والسماح بالموقع.</div>`;
    document.body.appendChild(panel);panel.focus();
    const safeEsc=html;
    const status=panel.querySelector('[data-map-status]');
    let map=null,layer=null,timer=null,busy=false,closed=false,firstFit=false;
    const markers=new Map();
    const permitted=()=>{const c=mapScope();return !!c&&c.user===scope.user&&c.branch===scope.branch;};
    const onResume=()=>{if(!closed&&document.visibilityState==='visible')void refresh();};
    const close=()=>{
      if(closed)return;closed=true;
      if(mapClose===close)mapClose=null;
      clearInterval(timer);
      document.removeEventListener('visibilitychange',onResume);
      window.removeEventListener('online',onResume);
      try{map?.remove();}catch(_){}
      panel.remove();
    };
    panel.querySelector('[data-map-close]').addEventListener('click',close);
    mapClose=close;
    if(typeof L==='undefined'){status.textContent='خدمة الخرائط غير متاحة على الجهاز الحالي.';return;}
    try{
      map=L.map(panel.querySelector('[data-map-canvas]'),{zoomControl:true}).setView([0,0],2);
      layer=L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',{maxZoom:19,attribution:'Tiles © Esri'}).addTo(map);
    }catch(e){status.textContent='تعذر فتح الخريطة. تحقق من اتصال الخرائط.';console.warn(e);close();return;}
    const iconFor=live=>L.divIcon({className:'ys-manager-rider-icon',html:`<span style="display:flex;width:35px;height:35px;border:2px solid white;box-shadow:0 2px 5px #0005;border-radius:50%;background:${live?'#218838':'#6b7280'};align-items:center;justify-content:center;font-size:21px">🛵</span>`,iconSize:[35,35],iconAnchor:[17,17]});
    async function refresh(){
      if(closed||busy||!permitted()){if(!permitted())close();return;}
      if(document.visibilityState==='hidden'||!navigator.onLine){status.textContent='الاتصال متوقف أو التطبيق في الخلفية؛ لا توجد تحديثات جديدة.';return;}
      busy=true;
      try{
        const result=await safeRpc('dlv_map_locations',{p_branch:scope.branch});
        if(closed||!permitted()){close();return;}
        if(result.error)throw new Error(result.error.message||'تعذر تحميل المواقع');
        const rows=Array.isArray(result.data)?result.data:[];
        const valid=rows.filter(r=>Number(r.branch_id)===scope.branch&&Number.isFinite(Number(r.lat))&&Number.isFinite(Number(r.lng))&&Math.abs(Number(r.lat))<=90&&Math.abs(Number(r.lng))<=180);
        const ids=valid.map(r=>r.driver_id).filter(Boolean).slice(0,500);
        let profileRows=[];
        if(ids.length&&typeof sb!=='undefined'){
          const people=await sb.from('dlv_profiles').select('user_id,full_name,branch_id').eq('branch_id',scope.branch).eq('role','driver').in('user_id',ids).limit(500);
          if(!people.error)profileRows=people.data||[];
        }
        if(closed||!permitted()){close();return;}
        const names=new Map(profileRows.map(p=>[String(p.user_id),String(p.full_name||'طيار')]));
        const seen=new Set();let liveCount=0,staleCount=0,rejected=0;
        valid.forEach(r=>{
          const at=Date.parse(r.recorded_at||r.updated_at||'');
          const server=Date.parse(r.server_at||'')||Date.now();
          const age=server-at;
          const accuracy=Number(r.accuracy);
          if(!Number.isFinite(age)||age< -5000||age>300000||!Number.isFinite(accuracy)||accuracy<0||accuracy>150){rejected++;return;}
          const fresh=age<=60000;
          if(fresh)liveCount++;else staleCount++;
          const id=String(r.driver_id),loc=[Number(r.lat),Number(r.lng)];seen.add(id);
          const msg=`<div dir="rtl" style="min-width:150px"><b>🛵 ${safeEsc(names.get(id)||'طيار')}</b><div>${fresh?'GPS حديث':'آخر ظهور (غير مباشر)'} · ${Math.max(0,Math.round(age/1000))} ثانية</div><div>دقة الإشارة: حوالي ${Math.round(accuracy)} متر</div></div>`;
          const old=markers.get(id);
          if(old){old.setLatLng(loc);old.setIcon(iconFor(fresh));old.setPopupContent(msg);}
          else{const marker=L.marker(loc,{icon:iconFor(fresh)}).addTo(map).bindPopup(msg);markers.set(id,marker);}
        });
        markers.forEach((marker,id)=>{if(!seen.has(id)){map.removeLayer(marker);markers.delete(id);}});
        status.textContent=`${liveCount} طيار بموقع حديث · ${staleCount} موقع قديم أقل من 5 دقائق · ${rejected} موقع مخفي لعدم حداثته أو دقته · آخر فحص ${new Intl.DateTimeFormat('ar-EG',{timeZone:'Africa/Cairo',hour:'2-digit',minute:'2-digit'}).format(new Date())}`;
        if(!firstFit&&markers.size){map.fitBounds(L.featureGroup([...markers.values()]).getBounds().pad(.25),{maxZoom:16});firstFit=true;}
        if(!markers.size&&valid.length)status.textContent+=' — لا يوجد موقع صالح للعرض المباشر حاليًا';
      }catch(e){if(!closed)status.textContent='تعذر تحديث GPS: '+String(e?.message||'خطأ مؤقت').slice(0,110);}
      finally{busy=false;}
    }
    document.addEventListener('visibilitychange',onResume);
    window.addEventListener('online',onResume);
    setTimeout(()=>{if(!closed){map.invalidateSize();void refresh();}},100);
    timer=setInterval(onResume,12000);
  }

  const observer=new MutationObserver(schedule);
  const start=()=>{
    if(!document.body)return;
    observer.observe(document.getElementById('app')||document.body,{subtree:true,childList:true});
    schedule();
    setInterval(()=>{if(document.visibilityState==='visible')schedule()},60000);
    document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')schedule()});
    window.addEventListener('online',schedule);
  };
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();
/* Your Staff Delivery — second platform-owner account management.
   Owner page only. The database validates ROOT ACCOUNT + live session + independent PIN.
   No storage, polling, global network subscriptions, or third-party resources.
*/
(() => {
  'use strict';
  if (window.__ysOwnerAccess20261119Loaded) return;
  window.__ysOwnerAccess20261119Loaded = true;
  const BUTTON = 'ys-second-owner-button';
  const DIALOG = 'ys-owner-manager-dialog';
  let checkedUser = '', primary = false, lastCheck = 0, checking = false, scheduled = false;
  const $ = (selector, root=document) => root.querySelector(selector);
  const escape = value => String(value ?? '').replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
  const context = () => {
    try {
      if (typeof me === 'undefined' || !me || typeof isOwner !== 'function' || !isOwner()) return null;
      return String(me.user_id);
    } catch { return null; }
  };
  const requestSync = () => {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(() => { scheduled = false; void sync(); });
  };
  async function sync() {
    const user = context();
    const app = document.getElementById('app');
    if (!user || !app) return;
    const parent = app.querySelector('#ownAccounts')?.closest('section');
    if (!parent) return;
    if (checkedUser !== user) { checkedUser = user; primary = false; lastCheck = 0; }
    if (primary) {
      if (!document.getElementById(BUTTON)) {
        const btn = document.createElement('button');
        btn.id = BUTTON;
        btn.className = 'g big';
        btn.type = 'button';
        btn.textContent = '👑 إدارة ملاك النظام';
        btn.style.cssText = 'min-height:45px;width:100%;margin-top:10px';
        btn.addEventListener('click', () => void openManager());
        parent.appendChild(btn);
      }
      return;
    }
    if (checking || Date.now() - lastCheck < 60000 || typeof safeRpc !== 'function') return;
    checking = true;
    lastCheck = Date.now();
    try {
      const {data,error} = await safeRpc('dlv_root_owner_accounts');
      if (error || context() !== user || !Array.isArray(data)) return;
      primary = data.some(row => row.is_root === true && String(row.user_id) === user);
      if (primary) requestSync();
    } catch (error) { console.warn('Owner management access unavailable', String(error?.message||'')); }
    finally { checking = false; }
  }
  function makeDialog() {
    const host = document.createElement('div');
    host.id = DIALOG;
    host.className = 'modal';
    host.setAttribute('role', 'dialog');
    host.setAttribute('aria-modal', 'true');
    host.setAttribute('aria-label', 'إدارة حسابات ملاك المنصة');
    host.style.zIndex = '95';
    host.innerHTML = `<div dir="rtl" style="max-width:680px;max-height:93vh;overflow:auto">
      <div class="ord"><h2>👑 ملاك منصة Your Staff</h2><button type="button" data-close>إغلاق</button></div>
      <p class="meta">الحساب الأساسي محمي. يمكن تشغيل حسابين للمالك فقط، لكل حساب بريد وكلمة مرور وPIN مستقل. كل مالك يستطيع إدارة الشركات والفروع؛ تعديل ملاك المنصة محصور في الحساب الأساسي.</p>
      <div data-accounts role="status" aria-live="polite">جاري تحميل الحسابات…</div>
      <hr>
      <label>رمز حماية المالك الأساسي (6 أرقام) — مطلوب لتأكيد أي تغيير</label>
      <input data-pin type="password" inputmode="numeric" autocomplete="off" maxlength="6" pattern="[0-9]{6}" placeholder="●●●●●●" style="max-width:170px;direction:ltr;text-align:center">
      <details data-create><summary style="font-weight:700;cursor:pointer;margin:12px 0">➕ إنشاء حساب مالك ثانٍ جديد</summary>
        <div style="display:grid;gap:7px">
          <label>الاسم<input data-name maxlength="120" autocomplete="off" placeholder="اسم مالك النظام الثاني"></label>
          <label>البريد الإلكتروني<input data-email type="email" dir="ltr" autocomplete="off" placeholder="owner@example.com"></label>
          <label>كود الحساب<input data-code maxlength="40" dir="ltr" autocomplete="off" placeholder="SYS-SECOND"></label>
          <label>كلمة المرور الأولية — 12 حرفًا على الأقل، كبير وصغير ورقم ورمز<input data-password type="password" autocomplete="new-password" minlength="12"></label>
          <div class="row"><button type="button" data-generate>إنشاء كلمة مرور قوية</button><label><input type="checkbox" data-show style="width:auto"> إظهارها مؤقتًا</label></div>
          <button type="button" class="p big" data-create-action>إنشاء حساب المالك الثاني</button>
        </div>
      </details>
      <details data-promote style="margin-top:12px"><summary style="font-weight:700;cursor:pointer">⬆ ترقية مدير فرع حالي إلى مالك للنظام</summary>
        <p class="meta">تمنحه إدارة جميع الشركات والفروع. يظل الكود والبريد وكلمة المرور الحالية كما هي، ويضبط PIN جديدًا لحسابه عند أول دخول.</p>
        <label>كود حساب مدير الفرع<input data-existing-code dir="ltr" maxlength="40" autocomplete="off"></label>
        <button type="button" class="g big" data-promote-action style="margin-top:9px">منح صلاحية مالك النظام</button>
      </details>
      <div data-message role="status" aria-live="polite" style="white-space:pre-wrap;margin-top:12px;font-size:13px"></div>
      <div data-credentials hidden style="margin-top:10px;padding:10px;border:1px solid var(--gold,#b9832e);border-radius:10px">
        <b>بيانات الحساب الجديد — تظهر مرة واحدة فقط</b><textarea readonly data-once rows="4" style="width:100%;direction:ltr" autocomplete="off"></textarea>
        <button type="button" data-copy>نسخ بيانات الحساب</button>
      </div>
    </div>`;
    document.body.appendChild(host);
    host.querySelector('[data-close]').addEventListener('click', () => {
      host.querySelector('[data-pin]').value = '';
      host.querySelector('[data-password]').value = '';
      host.querySelector('[data-once]').value = '';
      host.remove();
    });
    host.querySelector('[data-show]').addEventListener('change', ev => {
      host.querySelector('[data-password]').type = ev.target.checked ? 'text' : 'password';
    });
    host.querySelector('[data-generate]').addEventListener('click', () => {
      if (typeof generateStrongPassword === 'function') {
        host.querySelector('[data-password]').value = generateStrongPassword();
      } else {
        host.querySelector('[data-message]').textContent = 'اكتب كلمة مرور قوية بنفسك.';
      }
    });
    host.querySelector('[data-copy]').addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(host.querySelector('[data-once]').value);
        host.querySelector('[data-message]').textContent = 'تم نسخ بيانات الحساب. احفظها في مكان آمن، ثم امسحها من الحافظة بعد تسليمها.';
      } catch { host.querySelector('[data-message]').textContent = 'يمكنك تحديد النص ونسخه يدويًا.'; }
    });
    return host;
  }
  const rowHtml = a => {
    const isRoot = a.is_root === true;
    const active = a.active === true;
    const id = String(a.user_id||'');
    const validId = /^[0-9a-f-]{36}$/i.test(id) ? id : '';
    return `<div class="card" style="margin:8px 0;padding:9px 12px">
      <div class="ord"><b>${escape(a.name||'حساب')}</b><span class="badge">${isRoot?'الحساب الأساسي':active?'مالك ثانٍ — نشط':'مالك ثانٍ — معطل'}</span></div>
      <div class="meta" dir="ltr" style="text-align:right">${escape(a.email||'')} · ${escape(a.code||'')}</div>
      ${isRoot ? '<div class="meta">لا يمكن تعطيل الحساب الأساسي من هنا.</div>' : validId ?
        `<button type="button" data-owner-toggle="${validId}" data-enable="${active?'false':'true'}" class="g" style="margin-top:7px">${active?'إيقاف وصول هذا المالك':'إعادة تفعيل هذا المالك'}</button>` : ''}
    </div>`;
  };
  async function openManager() {
    if (!primary || !context() || typeof safeRpc !== 'function') return;
    const existing = document.getElementById(DIALOG);
    if (existing) return existing.querySelector('[data-pin]')?.focus();
    const host = makeDialog();
    const list = host.querySelector('[data-accounts]');
    const message = host.querySelector('[data-message]');
    let busy = false;
    const show = (txt, failed=false) => { message.style.color = failed?'#b91c1c':'inherit'; message.textContent = txt; };
    const pin = () => {
      const el = host.querySelector('[data-pin]');
      const value = el.value.trim();
      el.value = '';
      if (!/^[0-9]{6}$/.test(value)) throw new Error('أدخل رمز حماية المالك الصحيح المكون من 6 أرقام.');
      return value;
    };
    const run = async (rpc,args,done) => {
      if (busy || !host.isConnected || !context()) return;
      busy = true;
      host.querySelectorAll('button').forEach(el=>el.disabled=true);
      show('جارٍ تنفيذ العملية بشكل آمن…');
      try {
        const {data,error} = await safeRpc(rpc,args);
        if (error) throw Error(error.message||'تعذر تنفيذ الطلب');
        if (!host.isConnected) return;
        if (done) done(data);
        await reload();
      } catch (error) { if (host.isConnected) show(String(error?.message||'فشل غير معروف'),true); }
      finally { busy=false;if(host.isConnected)host.querySelectorAll('button').forEach(el=>el.disabled=false); }
    };
    const reload = async () => {
      const {data,error} = await safeRpc('dlv_root_owner_accounts');
      if (!host.isConnected) return;
      list.innerHTML = error ? `<div class="msg e">${escape(error.message)}</div>` :
        Array.isArray(data) ? data.map(rowHtml).join('') : 'تعذر تحميل قائمة الحسابات';
    };
    host.querySelector('[data-create-action]').addEventListener('click',async()=>{
      try {
        const name=host.querySelector('[data-name]').value.trim(),
          email=host.querySelector('[data-email]').value.trim().toLowerCase(),
          code=host.querySelector('[data-code]').value.trim(),
          pass=host.querySelector('[data-password]').value;
        if (name.length<2 || code.length<2 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
            pass.length<12 || !/[A-Z]/.test(pass) || !/[a-z]/.test(pass) ||
            !/[0-9]/.test(pass) || !/[^A-Za-z0-9]/.test(pass))
          throw Error('راجع الاسم والبريد والكود وقوة كلمة المرور.');
        if (!confirm('سيحصل هذا الحساب على صلاحيات كاملة لكل الشركات والفروع. هل تؤكد إنشاءه؟')) return;
        const p=pin();
        await run('dlv_root_create_secondary_owner',{
          p_name:name,p_email:email,p_code:code,p_password:pass,p_pin:p},()=>{
          const once=host.querySelector('[data-credentials]');
          once.hidden=false;
          host.querySelector('[data-once]').value=`الاسم: ${name}\nالبريد: ${email}\nالكود: ${code}\nكلمة المرور: ${pass}`;
          host.querySelector('[data-password]').value='';
          show('تم إنشاء الحساب. على صاحبه إعداد رمز حماية مستقل عند أول دخول.');
        });
      } catch (error) { show(error.message||'بيانات غير صالحة',true); }
    });
    host.querySelector('[data-promote-action]').addEventListener('click',async()=>{
      try {
        const code=host.querySelector('[data-existing-code]').value.trim();
        if (code.length<2) throw Error('أدخل كود حساب المدير الحالي.');
        if (!confirm('سيصبح حساب المدير مالكًا لجميع الشركات والفروع. هل تؤكد هذا التصعيد؟')) return;
        const p=pin();
        await run('dlv_root_promote_secondary_owner',{p_employee_code:code,p_pin:p},()=>show('تمت الترقية. مطلوب إعداد PIN مستقل للحساب.'));
      } catch(error) { show(error.message||'تعذر تنفيذ الترقية',true); }
    });
    list.addEventListener('click',async event=>{
      const button=event.target.closest('[data-owner-toggle]');
      if (!button || !list.contains(button)) return;
      try {
        const user=button.dataset.ownerToggle,active=button.dataset.enable==='true';
        if (!confirm(active?'تأكيد إعادة تفعيل المالك الثاني؟':'تأكيد إيقاف وصول المالك الثاني فورًا؟')) return;
        const p=pin();
        await run('dlv_root_toggle_secondary_owner',{p_user:user,p_active:active,p_pin:p},()=>show(active?'تمت إعادة تفعيل الحساب.':'تم تعطيل الحساب ومنع إجراءات الإدارة الجديدة.'));
      } catch(error) { show(error.message||'تعذر تعديل الحساب',true); }
    });
    await reload();
  }
  const start = () => {
    const app=document.getElementById('app');
    if (!app) return;
    new MutationObserver(requestSync).observe(app,{childList:true});
    document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')requestSync();});
    requestSync();
  };
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true}); else start();
})();