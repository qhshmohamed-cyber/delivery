/* Your Staff: one leased auth session per employee; root owner is exempt.
   Server RPCs are the authority; this client never grants permissions by itself. */
(function(root){
  'use strict';
  function createStaffSessionGuard(client,options={}){
    const intervalMs=options.intervalMs||45000;
    const onLost=options.onLost||(()=>{});
    let userId='',owner=false,heartbeatTimer=null,pending=false,active=false,disposed=false;
    function removeHooks(){
      if(heartbeatTimer!==null){clearInterval(heartbeatTimer);heartbeatTimer=null;}
      if(typeof document!=='undefined')document.removeEventListener('visibilitychange',onResume);
      if(typeof window!=='undefined'){
        window.removeEventListener('online',onResume);
        window.removeEventListener('pageshow',onResume);
      }
    }
    function stop(){
      removeHooks();userId='';owner=false;active=false;disposed=true;
    }
    async function pulse(){
      if(!active||owner||pending||disposed)return true;
      if(typeof navigator!=='undefined'&&navigator.onLine===false)return true;
      pending=true;
      try{
        const {data,error}=await client.rpc('dlv_staff_session_heartbeat');
        if(error) return true; // Transient network/API failures must not kick out an active driver.
        if(data!==true){stop();onLost();return false;}
        return true;
      }catch(_){return true;}
      finally{pending=false;}
    }
    function onResume(){
      if(typeof document==='undefined'||document.visibilityState==='visible')void pulse();
    }
    async function begin(session){
      if(!session?.user?.id)return {allowed:false,reason:'unauthenticated'};
      const {data,error}=await client.rpc('dlv_staff_session_claim');
      if(error)throw error;
      if(!data||data.allowed!==true){
        stop();
        return {allowed:false,reason:data?.reason||'already_active'};
      }
      removeHooks();
      disposed=false;userId=session.user.id;active=true;owner=data.owner===true;
      if(!owner){
        heartbeatTimer=setInterval(()=>{void pulse();},intervalMs);
        if(typeof document!=='undefined')document.addEventListener('visibilitychange',onResume);
        if(typeof window!=='undefined'){
          window.addEventListener('online',onResume);
          window.addEventListener('pageshow',onResume);
        }
      }
      return {allowed:true,owner};
    }
    async function release(){
      const shouldRelease=active&&!owner&&userId.length>0;
      stop();
      if(!shouldRelease)return;
      try{await client.rpc('dlv_staff_session_release');}
      catch(_){/* Lease expires automatically after a bounded inactivity period. */}
    }
    return {begin,pulse,release,stop,get owner(){return owner;},get active(){return active;}};
  }
  if(typeof module==='object'&&module.exports)module.exports={createStaffSessionGuard};
  else root.createStaffSessionGuard=createStaffSessionGuard;
})(globalThis);
