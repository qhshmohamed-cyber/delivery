const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
function extract(name){
 const start=html.indexOf('function '+name+'(');
 assert(start>=0);
 const end=html.indexOf('\n}',start)+2;
 return html.slice(start,end);
}
(async()=>{
 let wiped=0,removed=0,ended=0;
 const dialogs=Array.from({length:2},()=>({
  dispatchEvent(event){assert.equal(event.type,'private-session-ended');ended++;},
  querySelectorAll(selector){assert.equal(selector,'input,textarea');return [{set value(v){assert.equal(v,'');wiped++;}}];},
  remove(){removed++;}
 }));
 const ctx={Event,document:{querySelectorAll(selector){assert.equal(selector,'.modal,#ownerAssistantOverlay');return dialogs;}}};
 vm.createContext(ctx);vm.runInContext(extract('clearPrivateSessionDialogs'),ctx);
 ctx.clearPrivateSessionDialogs();
 assert.equal(ended,2);assert.equal(wiped,2);assert.equal(removed,2);

 // A server response arriving after logout must never render owner data.
 let resolve;
 const response=new Promise(r=>{resolve=r;});
 const owner={user_id:'owner'};
 const assistant={appSessionEpoch:0,me:owner,isOwner(){return this.me===owner;},
  $(){return null;},safeRpc(){return response;},flash(){throw Error('Stale response displayed');},
  document:{createElement(){throw Error('Stale owner dialog created');}}
 };
 // Avoid relying on JavaScript receiver binding for the app's global predicate.
 assistant.isOwner=()=>assistant.me===owner;
 vm.createContext(assistant);vm.runInContext('async '+extract('openOwnerAssistant'),assistant);
 const pending=assistant.openOwnerAssistant();
 assistant.appSessionEpoch++;assistant.me=null;
 resolve({data:[]});await pending;
 console.log('PASS private session UI: modal and assistant disposal, field wiping, cleanup event, delayed owner response rejected after logout');
})().catch(error=>{console.error(error);process.exitCode=1;});
