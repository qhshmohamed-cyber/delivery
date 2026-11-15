const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {createNativeBackground}=require('../native-background.js');
const html=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
function extract(name){const start=html.search(new RegExp('(?:async )?function '+name+'\\('));return html.slice(start,html.indexOf('\n}',start)+2);}
(async()=>{
 const web=createNativeBackground();assert.equal(web.available,false);assert.equal(web.storage,undefined);assert.equal(await web.start('driver'),false);
 const calls=[],items=new Map();let stops=0;
 const api={getItem:async({key})=>({value:items.get(key)}),setItem:async({key,value})=>{items.set(key,value);},removeItem:async({key})=>{items.delete(key);},start:async data=>calls.push(data),stop:async()=>{stops++;},status:async()=>({running:true,lastSent:123})};
 const native=createNativeBackground({getPlatform:()=> 'android',isNativePlatform:()=>true,registerPlugin:name=>{assert.equal(name,'YourStaffBackground');return api;}});
 await native.storage.setItem('auth','session');assert.equal(await native.storage.getItem('auth'),'session');await native.storage.removeItem('auth');assert.equal(await native.storage.getItem('auth'),null);
 await native.start('driver');assert.deepEqual(calls,[{userId:'driver'}]);await native.stop();assert.equal(stops,1);
 let finish;api.start=()=>new Promise(r=>finish=r);
 const ctx={nativeBackground:native,me:{role:'driver',user_id:'driver'},appSessionEpoch:1,locationGeneration:0,shareWanted:false,$:()=>null,renderShare(){}};
 vm.createContext(ctx);vm.runInContext(extract('startShare'),ctx);
 const pending=ctx.startShare();assert.equal(ctx.shareWanted,true);ctx.appSessionEpoch++;ctx.me=null;ctx.shareWanted=false;finish();await pending;assert.equal(stops,2,'late permission/start result must stop native tracking after logout');
 let signedOut=0;
 const logout={nativeBackground:{available:true,stop:async()=>{throw Error('stop failed');}},appLogoutBusy:false,flash(){},sessionActions:{signOut(){signedOut++;}}};
 vm.createContext(logout);vm.runInContext(extract('appSignOut'),logout);assert.equal(await logout.appSignOut(),false);assert.equal(signedOut,0,'do not claim logout while native tracking stop is unconfirmed');
 console.log('PASS native background bridge: web fallback, shared encrypted-storage adapter, native start/stop, late permission result after logout and stop failure');
})().catch(e=>{console.error(e);process.exitCode=1;});
