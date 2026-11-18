(function(root){
 'use strict';
 function entryUrl(base,formId,purpose='complaints'){
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(formId)))throw Error('رابط الفرع غير صحيح');
  if(!['staff','complaints'].includes(purpose))throw Error('نوع الرابط غير صحيح');
  const url=new URL(purpose==='staff'?'./':'feedback.html',base);
  url.search='';url.hash='';url.searchParams.set(purpose==='staff'?'staff':'f',formId);return url;
 }
 function matchesBranches(config,permitted){
  if(!config?.available)return false;
  const ids=new Set((permitted||[]).map(Number));
  return (config.branches||[]).some(b=>ids.has(Number(b.id)));
 }
 const api={entryUrl,matchesBranches};
 if(typeof module==='object'&&module.exports)module.exports=api;
 else root.ysStaffEntry=api;
})(globalThis);
