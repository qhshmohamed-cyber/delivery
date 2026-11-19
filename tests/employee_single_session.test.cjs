const assert=require('node:assert/strict');
const {createStaffSessionGuard}=require('../employee-session-guard.js');
async function main(){
  const first=[];
  const client={rpc:async name=>{
    first.push(name);
    if(name==='dlv_staff_session_claim')return {data:{allowed:true,owner:false}};
    if(name==='dlv_staff_session_heartbeat')return {data:true};
    if(name==='dlv_staff_session_release')return {data:true};
    throw new Error(name);
  }};
  const guard=createStaffSessionGuard(client,{intervalMs:999999});
  assert.deepEqual(await guard.begin({user:{id:'staff-A'}}),{allowed:true,owner:false});
  assert.equal(await guard.pulse(),true);
  await guard.release();
  assert.deepEqual(first,['dlv_staff_session_claim','dlv_staff_session_heartbeat','dlv_staff_session_release']);
  let lost=0;
  const denied=createStaffSessionGuard({rpc:async()=>({data:{allowed:false,reason:'already_active'}})},{onLost:()=>lost++});
  assert.equal((await denied.begin({user:{id:'staff-B'}})).allowed,false);
  assert.equal(denied.active,false);
  denied.stop();
  const rootOwner=createStaffSessionGuard({rpc:async()=>({data:{allowed:true,owner:true}})},{intervalMs:999999});
  assert.equal((await rootOwner.begin({user:{id:'root'}})).owner,true);
  assert.equal(rootOwner.active,true);
  await rootOwner.release();
  let revocations=0;
  let call=0;
  const revokeGuard=createStaffSessionGuard({rpc:async name=>({data:name==='dlv_staff_session_claim'?{allowed:true,owner:false}:false})},{intervalMs:999999,onLost:()=>revocations++});
  await revokeGuard.begin({user:{id:'staff-C'}});
  assert.equal(await revokeGuard.pulse(),false);
  assert.equal(revocations,1);
  revokeGuard.stop();
  console.log('PASS staff session guard: claim, deny, owner exception, pulse/release, revocation');
}
main().catch(error=>{console.error(error);process.exitCode=1;});
