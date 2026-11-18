const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const gps=require('../gps-quality.js'),html=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
const extract=name=>{const start=html.search(new RegExp('(?:async )?function '+name+'\\('));assert(start>=0);return html.slice(start,html.indexOf('\n}',start)+2);};
const base=Date.parse('2026-11-16T12:00:00Z');
function fix(lat=30.05,lng=31.2,offset=0,accuracy=8,wall=base+offset,mono=offset){return gps.snapshot({lat,lng,accuracy,recorded_at:new Date(base+offset).toISOString(),server_at:new Date(base+offset).toISOString()},wall,mono);}
const flush=async()=>{for(let i=0;i<12;i++)await Promise.resolve();};
let assertions=0;
function check(value,message){assert(value,message);assertions++;}
for(const lat of [null,undefined,'',' ',NaN,Infinity,-91,91,true])check(!gps.state(gps.snapshot({lat,lng:31,accuracy:8,updated_at:new Date(base).toISOString()},base,0),0).valid,'bad latitude');
for(const lng of [null,'',NaN,-181,181,Infinity,false])check(!gps.state(gps.snapshot({lat:30,lng,accuracy:8,updated_at:new Date(base).toISOString()},base,0),0).valid,'bad longitude');
for(const accuracy of [null,undefined,-1,151,Infinity,NaN])check(!gps.state(gps.snapshot({lat:30,lng:31,accuracy,updated_at:new Date(base).toISOString()},base,0),0).valid,'bad accuracy');
check(gps.state(fix(),59999).live,'valid before 60 seconds');check(!gps.state(fix(),60000).live,'expires at 60 seconds without a response');
for(const skew of [-3600000,-600000,600000,3600000]){const s=fix(30,31,0,8,base+skew,10);check(gps.state(s,5010).ageMs===5000,'server clock must defeat phone clock skew');}
const delayed=gps.snapshot({lat:30,lng:31,accuracy:8,loc_at:new Date(base).toISOString(),server_at:new Date(base+30000).toISOString()},base,100,35000);
check(!gps.state(delayed,100).live,'network-delayed response cannot reset freshness');
check(!gps.motion(fix(),fix(31,31.2,5000),5000).accept,'teleport rejected');
check(!gps.motion(fix(30,31,5000),fix(30,31,0),5000).accept,'out of order sample rejected');
check(!gps.motion(fix(),fix(30.1,31.2),0).accept,'same timestamp with changed position rejected');
check(!gps.motion(fix(),fix(30.05,31.2,5000),5000).rotate,'stop keeps heading');
check(!gps.motion(fix(),fix(30.05001,31.20001,5000,80),5000).rotate,'inaccurate jitter cannot rotate driver');

// Repeatable street-like route: cardinal turns, stationary periods, imperfect GPS,
// foreground/background gaps and connectivity loss. Coordinates are synthetic.
let seed=1791;const random=()=>{seed=(1664525*seed+1013904223)>>>0;return seed/4294967296;};
let samples=0,accepted=0,rejected=0,staleWindows=0;
for(let run=0;run<20;run++){
 let previous=null,lat=30.05,lng=31.2,lastHeading=0;
 for(let i=0;i<600;i++){
  const time=i*5000,stopped=i%120>=90,offline=i%200>=170,background=i%150>=130;
  if(!stopped){const direction=Math.floor(i/60)%4;if(direction===0)lng+=0.00009;else if(direction===1)lat+=0.00008;else if(direction===2)lng-=0.00009;else lat-=0.00008;}
  const jitter=()=> (random()-.5)*0.000025;
  const accuracy=i%71===0?180:i%47===0?90:8;
  const next=fix(lat+jitter(),lng+jitter(),time,accuracy,base+time+(run%2?600000:-600000),time);
  samples++;
  if(offline||background){if(previous&&!gps.state(previous,time).live)staleWindows++;continue;}
  const move=gps.motion(previous,next,time);
  if(move.accept){accepted++;if(move.rotate)lastHeading=1;previous=next;check(gps.validPoint(previous),'accepted GPS is finite and bounded');}
  else rejected++;
  check(lastHeading===0||lastHeading===1,'heading remains finite');
 }
}
check(samples===12000&&accepted>7000&&rejected>0&&staleWindows>0,'trace covers movement, rejects and stale intervals');

function managerFixture(){
 const nodes={},intervals=new Map(),handlers={},maps=[],markers=[];let intervalId=0,mono=0,wall=base;
 const doc={visibilityState:'visible',getElementById:id=>nodes[id]||null,addEventListener:(k,fn)=>handlers[k]=fn,removeEventListener:k=>delete handlers[k]};
 function node(tag){const e={tag,style:{},children:[],value:'',events:{},isConnected:false,setAttribute(){},addEventListener(k,fn){this.events[k]=fn;},appendChild(c){c.parentElement=this;c.isConnected=true;this.children.push(c);},remove(){this.isConnected=false;for(const [id,n]of Object.entries(nodes))if(n.owner===this)delete nodes[id];}};
  Object.defineProperty(e,'innerHTML',{set(v){this.html=v;for(const match of v.matchAll(/id="([^"]+)"/g)){const n=node('div');n.owner=this;n.parentElement={appendChild(){}};nodes[match[1]]=n;}},get(){return this.html;}});return e;
 }
 doc.createElement=node;doc.body={appendChild(e){e.isConnected=true;}};
 const point=(a,b)=>{const p=typeof a==='object'?{lat:a.lat,lng:a.lng}:{lat:a,lng:b};p.distanceTo=q=>gps.distance(p,q);return p;};
 const L={latLng:point,map(){const m={setView(){return this;},remove(){this.removed=true;},removeLayer(){},fitBounds(){},invalidateSize(){}};maps.push(m);return m;},tileLayer(){return {addTo(){return this;},on(){return this;}};},marker(pos){const m={pos:{lat:pos[0],lng:pos[1]},_map:true,addTo(){return this;},bindPopup(v){this.popup=v;return this;},getPopup(){return {setContent:v=>m.popup=v};},setOpacity(v){this.opacity=v;return this;},setIcon(){},setLatLng(v){this.pos=Array.isArray(v)?{lat:v[0],lng:v[1]}:v;},getLatLng(){return point(this.pos);},openPopup(){}};markers.push(m);return m;},circle(){return {addTo(){return this;},setLatLng(){return this;},setRadius(){return this;},setStyle(){return this;}};},featureGroup(){return {getBounds:()=>({pad(){return this;}})};}};
 const ctx={me:{user_id:'operator'},appSessionEpoch:0,selectedBranch:1,drivers:[{user_id:'driver',full_name:'QA driver'}],brandConfig:{brand_name:'QA'},document:doc,window:{addEventListener(){},removeEventListener(){}},navigator:{onLine:true},Date:class extends Date{static now(){return wall;}},performance:{now:()=>mono},L,ysGps:{...gps,nowMono:()=>mono,snapshot:r=>gps.snapshot(r,wall,mono),state:r=>gps.state(r,mono),motion:(a,b)=>gps.motion(a,b,mono)},$:id=>nodes[id],isOwner:()=>false,isLocationManager:()=>true,esc:v=>String(v),flash(){},tm:()=>'',bikeIcon:()=>({}),bikeBearing:()=>90,animateRiderMarker(){},cancelRiderAnimation(){},setTimeout(){},setInterval(fn,period){intervals.set(++intervalId,{fn,period});return intervalId;},clearInterval:id=>intervals.delete(id)};
 let resolveLocation,resolveOrders;
 ctx.safeRpc=()=>new Promise(r=>resolveLocation=r);ctx.sb={from:()=>({select(){return this;},eq(){return this;},in(){return this;},limit(){return new Promise(r=>resolveOrders=r);}})};
 vm.createContext(ctx);vm.runInContext(extract('openMap'),ctx);
 return {ctx,nodes,intervals,markers,maps,resolve(data){resolveLocation({data});resolveOrders({data:[]});},advance(ms){mono+=ms;wall+=ms;for(const t of [...intervals.values()])if(t.period===1000)t.fn();}};
}
// Run the actual public page's expiry callback, independently of network polling.
{
 let mono=0,removed=0,cancelled=0;const code={isConnected:true},status={textContent:''},map={style:{}},cleared=[];
 const ctx={latestTrackFix:fix(),trackStatus:'out',ownCodeField:code,freshnessTimer:7,tmr:8,mapT:{remove(){removed++;}},mk:{},lastTrackPos:{},navigator:{onLine:true},ysGps:{state:f=>gps.state(f,mono)},$:id=>({tc:code,trackGpsStatus:status,tmap:map})[id],cancelRiderAnimation(){cancelled++;},clearInterval:id=>cleared.push(id)};
 const start=html.indexOf('  function removeCustomerMap()'),end=html.indexOf('  const freshnessTimer=',start);
 vm.createContext(ctx);vm.runInContext(html.slice(start,end),ctx);ctx.updateGpsStatus();check(removed===0,'customer fresh marker retained');
 mono=60000;ctx.updateGpsStatus();check(removed===1&&cancelled===1&&map.style.display==='none','customer map expires without a network response');
 ctx.latestTrackFix=fix();mono=0;ctx.mapT={remove(){removed++;}};ctx.navigator.onLine=false;ctx.updateGpsStatus();check(removed===2&&status.textContent.includes('منقطع'),'customer offline map removed immediately');
 ctx.navigator.onLine=true;ctx.trackStatus='delivered';ctx.mapT={remove(){removed++;}};ctx.updateGpsStatus();check(removed===3,'completed delivery hides live map');
 code.isConnected=false;ctx.updateGpsStatus();check(cleared.includes(7)&&cleared.includes(8),'leaving tracking page clears both timers');
}
(async()=>{
 for(const mutation of ['close','branch','account','epoch']){
  const f=managerFixture();f.ctx.openMap();
  if(mutation==='close')f.nodes.mclose.onclick();if(mutation==='branch')f.ctx.selectedBranch=2;if(mutation==='account')f.ctx.me={user_id:'other'};if(mutation==='epoch')f.ctx.appSessionEpoch++;
  f.resolve([{driver_id:'driver',branch_id:1,lat:30,lng:31,accuracy:8,updated_at:new Date(base).toISOString(),server_at:new Date(base).toISOString()}]);await flush();check(f.markers.length===0,'late map response rejected after '+mutation);f.advance(1000);check(f.intervals.size===0,'old map timers cleaned after '+mutation);
 }
 const f=managerFixture();f.ctx.openMap();f.resolve([{driver_id:'driver',branch_id:1,lat:30,lng:31,accuracy:8,updated_at:new Date(base).toISOString(),server_at:new Date(base).toISOString()}]);await flush();check(f.markers.length===1,'fresh location renders');check(f.markers[0].opacity===undefined||f.markers[0].opacity===1,'fresh marker not dim');
 f.ctx.navigator.onLine=false;f.advance(61000);check(f.markers[0].opacity===0.55,'manager marker expires while offline');f.nodes.mclose.onclick();check(f.intervals.size===0,'closing map cleans all timers');
 const ctx={Date:class extends Date{static now(){return base;}},Number,me:{user_id:'driver',role:'driver'},shareWanted:true,locationGeneration:1,locationBusy:false,lastSend:0,navigator:{onLine:true},$:()=>({textContent:''}),tm:()=>'',safeRpc:async()=>({data:{accepted:false,reason:'implausible_jump'},error:null})};vm.createContext(ctx);vm.runInContext(extract('sendDriverPosition'),ctx);
 await ctx.sendDriverPosition({timestamp:base,coords:{latitude:30,longitude:31,accuracy:8}},true,1);check(ctx.lastSend===0,'rejected server update cannot be presented as sent');
 console.log(JSON.stringify({pass:true,samples,accepted,rejected,staleWindows,assertions,scenarios:['turns','stop','jitter','poor accuracy','offline','background','clock skew','network delay','late responses','logout/branch isolation','expiry','server rejection']}));
})().catch(error=>{console.error(error);process.exitCode=1;});
