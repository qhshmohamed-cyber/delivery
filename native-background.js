(function(root){
 'use strict';
 function createNativeBackground(cap){
  const available=!!(cap?.getPlatform?.()==='android'&&cap?.isNativePlatform?.());
  const plugin=available?cap.registerPlugin('YourStaffBackground'):null;
  return {available,
   storage:available?{getItem:async key=>(await plugin.getItem({key})).value??null,setItem:async(key,value)=>{await plugin.setItem({key,value});},removeItem:async key=>{await plugin.removeItem({key});}}:undefined,
   start:async userId=>{if(!plugin)return false;await plugin.start({userId});return true;},
   stop:async()=>{if(plugin)await plugin.stop();},
   status:async()=>plugin?plugin.status():{running:false,state:'web_only'}
  };
 }
 if(typeof module==='object'&&module.exports)module.exports={createNativeBackground};
 else root.createNativeBackground=createNativeBackground;
})(typeof window==='object'?window:globalThis);
