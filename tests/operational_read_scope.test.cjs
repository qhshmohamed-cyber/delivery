const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
function source(name){const start=html.search(new RegExp('(?:async )?function '+name+'\\('));assert(start>=0);return html.slice(start,html.indexOf('\n}',start)+2);}
const deferred=()=>{let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve};};
function setup(){
 const elements={complaintsRows:{isConnected:true,textContent:''},managerGpsHealth:{isConnected:true,textContent:''}};
 const ctx={me:{user_id:'operator'},selectedBranch:1,appSessionEpoch:0,$:id=>elements[id],complaintsInboxRows:[],painted:0,paintComplaintsInbox(){ctx.painted++;}};
 vm.createContext(ctx);vm.runInContext('const operationalReadRequests=new Map();\n'+source('captureOperationalRead')+'\n'+source('loadComplaintsInbox'),ctx);
 return {ctx,elements};
}
(async()=>{
 for(const change of ['account','branch','epoch','view']){
  const {ctx,elements}=setup(),hold=deferred();ctx.safeRpc=()=>hold.promise;
  const running=ctx.loadComplaintsInbox();
  if(change==='account')ctx.me={user_id:'next-operator'};
  if(change==='branch')ctx.selectedBranch=2;
  if(change==='epoch')ctx.appSessionEpoch++;
  if(change==='view')elements.complaintsRows={isConnected:true,textContent:'next screen'};
  hold.resolve({data:[{details:'old private response'}]});await running;
  assert.equal(ctx.painted,0,change+' must reject old response');assert.equal(ctx.complaintsInboxRows.length,0);
 }
 const {ctx}=setup(),first=deferred(),second=deferred();let n=0;
 ctx.safeRpc=()=>++n===1?first.promise:second.promise;
 const a=ctx.loadComplaintsInbox(),b=ctx.loadComplaintsInbox();
 second.resolve({data:[{id:2}]});await b;first.resolve({data:[{id:1}]});await a;
 assert.equal(ctx.complaintsInboxRows[0].id,2);assert.equal(ctx.painted,1);
 // A branch switch while GPS freshness is fetching must not render the old branch.
 const gps=setup(),orders=deferred(),locations=deferred();let reads=0;
 const chain=p=>({eq(){return this;},not(){return this;},in(){return this;},limit(){return p;}});
 gps.ctx.canViewManagerBoard=()=>true;gps.ctx.sb={from:()=>({select:()=>({})})};
 gps.ctx.branchQuery=()=>{reads++;return chain(orders.promise);};gps.ctx.safeRpc=()=>{reads++;return locations.promise;};
 vm.runInContext(source('loadDriverGpsHealth'),gps.ctx);
 const running=gps.ctx.loadDriverGpsHealth();orders.resolve({data:[{driver_id:'driver'}]});
 await new Promise(setImmediate);assert.equal(reads,2);
 gps.ctx.selectedBranch=2;locations.resolve({data:[{driver_id:'driver',updated_at:new Date().toISOString()}]});await running;
 assert.equal(gps.elements.managerGpsHealth.innerHTML,undefined);
 // The refresh coordinator must wait for every role-specific read.
 const one=deferred(),two=deferred(),refresh={me:{workflow_role:'callcenter_followup'},loadCallcenterOrders:()=>one.promise,loadCallcenterRatings:()=>two.promise};
 vm.createContext(refresh);vm.runInContext(source('refreshView'),refresh);
 let settled=false;const work=refresh.refreshView().then(()=>{settled=true;});one.resolve();await Promise.resolve();assert.equal(settled,false);two.resolve();await work;assert.equal(settled,true);
 console.log('PASS operational reads: old account/branch/session/view and out-of-order results rejected; GPS second await guarded; refresh waits for all reads');
})().catch(e=>{console.error(e);process.exitCode=1;});
