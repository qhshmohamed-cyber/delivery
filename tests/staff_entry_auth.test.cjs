const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {entryUrl,matchesBranches}=require('../staff-entry.js');
const id='ac6420e7-d0ba-4b92-8ab8-477b2432f42d';
for(const base of ['https://example.com/','https://example.com/Test/','https://example.com/Test/index.html?t=old#x']){
 const staff=entryUrl(base,id,'staff'),complaint=entryUrl(base,id);
 assert.equal(staff.searchParams.get('staff'),id);assert.equal(complaint.searchParams.get('f'),id);
 assert.equal(staff.hash,'');assert.equal(staff.searchParams.has('t'),false);
 assert.equal(staff.pathname,base.includes('/Test/')?'/Test/':'/');
 assert.equal(complaint.pathname,base.includes('/Test/')?'/Test/feedback.html':'/feedback.html');
}
assert.throws(()=>entryUrl('https://example.com/', '../private','staff'));
assert.throws(()=>entryUrl('https://example.com/',id,'owner'));
assert.equal(matchesBranches({available:true,branches:[{id:1}]},[1]),true);
assert.equal(matchesBranches({available:true,branches:[{id:1}]},[2]),false);
assert.equal(matchesBranches({available:false,branches:[{id:1}]},[1]),false);
const html=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
const customTitlePattern=vm.runInNewContext(html.match(/customTitle.length>60\|\|(\/[^\n]*?\/)\.test\(customTitle\)/)[1]);
for(const title of ['كاشير','Cashier','صالة 1'])assert.equal(customTitlePattern.test(title),false);
for(const title of ['<bad>','bad\njob'])assert.equal(customTitlePattern.test(title),true);
const boot=html.slice(html.indexOf('async function boot('),html.indexOf('\n}',html.indexOf('async function boot('))+2);
function context(){
 const c={bootRequestId:0,appSessionEpoch:0,staffEntryId:null,loadStaffEntry:async()=>null,loginView:()=>{},
 reconnectView:()=>{},appSignOut:async()=>{c.signedOut=true;},isOwner:()=>false,
 startProfileSync:()=>{},document:{documentElement:{classList:{remove(){}}},body:{classList:{remove(){}}}},
 safeRpc:async()=>({data:[{id:1,name:'branch'}]}),branchNames:{},ysStaffEntry:{matchesBranches},resetPlatformBrand(){},
 loadBrandConfig:async()=>{},subscribeBrandConfig(){},driverView(){c.rendered='driver';},kitchenView(){c.rendered='kitchen';},
 callcenterView(){c.rendered='callcenter';},complaintsOfficerView(){c.rendered='complaints';},customStaffView(){},managerView(){c.rendered='manager';},
 startKitchenDelayMonitor(){},subscribe(){},startRealtime(){},console,setInterval:()=>0,clearInterval(){}};
 c.sb={auth:{getSession:async()=>({data:{session:{user:{id:'driver'}}}}),getUser:async()=>({data:{user:{id:'driver'}}})},
 from:()=>({select:()=>({eq:()=>({maybeSingle:async()=>({data:{user_id:'driver',role:'driver',workflow_role:'driver',active:true,branch_id:1}})})})})};
 vm.createContext(c);vm.runInContext(boot,c);return c;
}
(async()=>{
 const mismatch=context();await mismatch.boot('owner');assert.equal(mismatch.signedOut,true);assert.equal(mismatch.rendered,undefined);
 const stale=context();let resolve;stale.sb.from=()=>({select:()=>({eq:()=>({maybeSingle:()=>new Promise(r=>resolve=r)})})});
 const pending=stale.boot('driver');while(!resolve)await Promise.resolve();stale.appSessionEpoch++;resolve({data:{user_id:'owner',role:'admin',workflow_role:'admin',active:true}});
 await pending;assert.equal(stale.me,undefined);assert.equal(stale.rendered,undefined);
 const wrongBranch=context();wrongBranch.staffEntryId=id;wrongBranch.loadStaffEntry=async()=>({available:true,branch_id:2,branches:[{id:2}]});
 await wrongBranch.boot('driver');assert.equal(wrongBranch.signedOut,true);assert.equal(wrongBranch.rendered,undefined);
 const unavailable=context();unavailable.staffEntryId=id;unavailable.loadStaffEntry=async()=>({available:false});await unavailable.boot();assert.equal(unavailable.rendered,undefined);
 console.log('PASS: QR paths for root and Test, malformed tokens, branch scope, suspended entry, account mismatch and stale profile rejected');
})().catch(e=>{console.error(e);process.exitCode=1;});
