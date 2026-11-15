// Execute production handlers against deterministic browser/network fault adapters.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
function extract(name){const re=new RegExp('(?:async )?function '+name+'\\('),start=html.search(re),end=html.indexOf('\n}',start)+2;assert(start>=0&&end>start);return html.slice(start,end);}
const deferred=()=>{let resolve;return {promise:new Promise(r=>resolve=r),resolve:v=>resolve(v)};};
function gpsContext(){
 const calls=[],elements={locst:{textContent:''},locdetail:{textContent:''}},timers=new Map();let timer=0;
 const context={Date,Number,Math,nativeBackground:{available:false},me:{role:'driver',user_id:'fixture-driver'},appSessionEpoch:0,
  navigator:{onLine:true,geolocation:{watchPosition(){return 7;},clearWatch(){},getCurrentPosition(){}},wakeLock:{request:async()=>({addEventListener(){},release:async()=>{}})}},
  document:{visibilityState:'visible'},window:{isSecureContext:true},$:id=>elements[id],
  setInterval:fn=>{timers.set(++timer,fn);return timer;},clearInterval:id=>timers.delete(id),setTimeout(){},
  flash(){},tm:()=>'',safeRpc:async(name,args)=>{calls.push({name,args});return {error:null};}
 };
 vm.createContext(context);vm.runInContext(html.slice(html.indexOf('let watchId ='),html.indexOf('// استئناف تلقائي من الموقع الحالي')),context);
 return {context,calls,elements,timers};
}
async function run(){
 const reports=[];
 async function test(name,fn){try{await fn();reports.push({name,pass:true});}catch(error){reports.push({name,pass:false,error:error.message});}}
 await test('one status mutation for rapid double click',async()=>{
  const hold=deferred();let calls=0,refreshes=0;
  const ctx={requireOnline:()=>true,safeRpc:()=>{calls++;return hold.promise;},flash(){},refreshView(){refreshes++;}};vm.createContext(ctx);
  vm.runInContext('const orderStatusPending=new Set();\n'+extract('setStatus'),ctx);
  const first=ctx.setStatus(1,'received'),second=ctx.setStatus(1,'out');assert.equal(calls,1);hold.resolve({error:null});await Promise.all([first,second]);assert.equal(refreshes,1);
 });
 await test('uncertain network response refreshes authoritative state',async()=>{
  let refreshed=0;const ctx={requireOnline:()=>true,safeRpc:async()=>({error:{message:'connection lost'}}),flash(){},refreshView(){refreshed++;}};vm.createContext(ctx);
  vm.runInContext('const orderStatusPending=new Set();\n'+extract('setStatus'),ctx);await ctx.setStatus(1,'received');assert.equal(refreshed,1);
 });
 await test('invalid stale and future GPS samples never reach server',async()=>{
  const {context,calls}=gpsContext();await context.startShare();
  for(const sample of [
   {coords:{latitude:30,longitude:31,accuracy:10}},
   {timestamp:Date.now()+60000,coords:{latitude:30,longitude:31,accuracy:10}},
   {timestamp:Date.now()-60000,coords:{latitude:30,longitude:31,accuracy:10}},
   {timestamp:Date.now(),coords:{latitude:91,longitude:31,accuracy:10}},
   {timestamp:Date.now(),coords:{latitude:30,longitude:31,accuracy:-1}},
   {timestamp:Date.now(),coords:{latitude:30,longitude:31,accuracy:151}}
  ])await context.sendDriverPosition(sample,true);
  assert.equal(calls.length,0);
  await context.sendDriverPosition({timestamp:Date.now(),coords:{latitude:30,longitude:31,accuracy:10}},true);assert.equal(calls.length,1);
  context.navigator.onLine=false;await context.sendDriverPosition({timestamp:Date.now(),coords:{latitude:30,longitude:31,accuracy:10}},true);assert.equal(calls.length,1);
 });
 await test('wake lock arriving after stop is released',async()=>{
  const {context,timers}=gpsContext();const hold=deferred();let releases=0;context.navigator.wakeLock.request=()=>hold.promise;
  const starting=context.startShare();await context.stopShare(false);
  hold.resolve({addEventListener(){},release:async()=>{releases++;}});await starting;
  assert.equal(releases,1);assert.equal(timers.size,0);
 });
 await test('callbacks from a stopped GPS run cannot submit in a new run',async()=>{
  const {context,calls}=gpsContext();const callbacks=[];
  context.navigator.geolocation.watchPosition=fn=>{callbacks.push(fn);return callbacks.length;};
  await context.startShare();await context.stopShare(false);await context.startShare();
  await callbacks[0]({timestamp:Date.now(),coords:{latitude:30,longitude:31,accuracy:10}});assert.equal(calls.length,0);
  await callbacks[1]({timestamp:Date.now(),coords:{latitude:30,longitude:31,accuracy:10}});assert.equal(calls.length,1);
 });
 await test('resume callback cannot cross tracking runs',async()=>{
  const {context,calls}=gpsContext(),callbacks=[];
  context.navigator.geolocation.getCurrentPosition=fn=>callbacks.push(fn);
  vm.runInContext('let resumeLocationBusy=false;\n'+extract('resumeDriverLocationNow'),context);
  await context.startShare();await context.resumeDriverLocationNow();await context.stopShare(false);await context.startShare();
  await callbacks[1]({timestamp:Date.now(),coords:{latitude:30,longitude:31,accuracy:10}});assert.equal(calls.length,0);
 });
 await test('role change dismisses previous privileged dialogs and cached orders',async()=>{
  let cleared=0,booted=0;const ctx={profileSyncBusy:false,profileSyncFingerprint:'old',appSessionEpoch:0,me:{user_id:'fixture-user',role:'manager'},ORD:{1:{id:1}},
   document:{visibilityState:'visible'},console,profileSignature:()=> 'new',clearPrivateSessionDialogs:()=>{cleared++;},boot:async()=>{booted++;},
   sb:{from:()=>({select:()=>({eq:()=>({maybeSingle:async()=>({data:{user_id:'fixture-user'},error:null})})})})}};
  vm.createContext(ctx);vm.runInContext(extract('checkProfileUpdates'),ctx);await ctx.checkProfileUpdates();
  assert.equal(cleared,1);assert.equal(Object.keys(ctx.ORD).length,0);assert.equal(ctx.appSessionEpoch,1);assert.equal(booted,1);
 });
 await test('driver response arriving after logout cannot touch the next screen',async()=>{
  const hold=deferred(),elements={ol:{innerHTML:'untouched'},s1:{textContent:'untouched'}};
  const builder={select(){return this;},eq(){return this;},in(){return this;},order(){return this;},limit(){return hold.promise;}};
  const ctx={me:{user_id:'fixture-driver',role:'driver'},appSessionEpoch:0,selectedBranch:1,$:id=>elements[id],sb:{from:()=>builder},branchQuery:q=>q};
  vm.createContext(ctx);vm.runInContext('let driverOrdersRequest=0;\n'+extract('loadMine'),ctx);
  const pending=ctx.loadMine();ctx.me=null;ctx.appSessionEpoch++;hold.resolve({data:[],error:null});await pending;
  assert.equal(elements.ol.innerHTML,'untouched');assert.equal(elements.s1.textContent,'untouched');
 });
 await test('order save is single flight and a detached form never touches a replacement form',async()=>{
  const hold=deferred();let calls=0;
  const fields=Object.fromEntries(['n_no','n_staff','n_p','n_c','n_a','n_n','n_ok','n_x','ferr'].map(id=>[id,{value:'',disabled:false,textContent:''}]));
  fields.n_no.value='QA-fixture';fields.n_staff.value='1';
  const dialog={isConnected:true,querySelectorAll:()=>Object.values(fields)};
  const ctx={d:dialog,orderSubmitting:false,staffBranchReady:1,selectedBranch:1,me:{branch_id:1,allowed_branch_ids:[1]},isMgr:true,isOwner:()=>false,
   $:id=>fields[id],requireOnline:()=>true,deliveryMobile:()=>'',safeRpc:()=>{calls++;return hold.promise;}};
  const start=html.indexOf("$('n_ok').onclick = async () => {"),bodyStart=html.indexOf('{',start)+1,end=html.indexOf('\n  };\n}',bodyStart);
  assert(start>=0&&end>bodyStart);vm.createContext(ctx);vm.runInContext('async function submitOrder(){'+html.slice(bodyStart,end)+'\n}',ctx);
  const first=ctx.submitOrder();await ctx.submitOrder();assert.equal(calls,1);assert(Object.values(fields).every(x=>x.disabled));
  dialog.isConnected=false;ctx.$=()=>{throw Error('Old save accessed replacement form');};hold.resolve({data:100,error:null});await first;
 });
 await test('confirmed suspension denial clears stale screen while transport errors retain it',async()=>{
  for(const code of ['42501','NETWORK']){
   let cleared=0;const elements={app:{innerHTML:'previous data'},suspendedRetry:{},suspendedOut:{}};
   const ctx={profileSyncBusy:false,profileSyncFingerprint:'same',appSessionEpoch:0,me:{user_id:'fixture-user',role:'manager'},ORD:{1:{}},
    document:{visibilityState:'visible',body:{classList:{add(){}}}},console,profileSignature:()=> 'same',isOwner:()=>false,
    clearPrivateSessionDialogs:()=>{cleared++;},stopProfileSync(){},resetPlatformBrand(){},$:id=>elements[id],
    safeRpc:async()=>({data:null,error:{code}}),sb:{from:()=>({select:()=>({eq:()=>({maybeSingle:async()=>({data:{},error:null})})})})}};
   vm.createContext(ctx);vm.runInContext(extract('checkProfileUpdates'),ctx);await ctx.checkProfileUpdates();
   assert.equal(cleared,code==='42501'?1:0);assert.equal(Object.keys(ctx.ORD).length,code==='42501'?0:1);
   assert.equal(elements.app.innerHTML==='previous data',code!=='42501');
  }
 });
 for(const result of reports)console.log((result.pass?'PASS':'FAIL')+': '+result.name+(result.error?' — '+result.error:''));
 assert(reports.every(r=>r.pass),'Operational fault scenarios failed');
}
run().catch(error=>{console.error(error.message);process.exitCode=1;});
