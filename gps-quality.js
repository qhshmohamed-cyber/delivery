(function(root){
 'use strict';
 const nowMono=()=>root.performance?.now?root.performance.now():Date.now();
 const numeric=v=>v!==null&&v!==undefined&&typeof v!=='boolean'&&String(v).trim()!==''&&Number.isFinite(Number(v));
 const validPoint=p=>!!p&&numeric(p.lat)&&numeric(p.lng)&&Math.abs(Number(p.lat))<=90&&Math.abs(Number(p.lng))<=180;
 function snapshot(p,wall=Date.now(),mono=nowMono(),latency=0){
  const at=Date.parse(p?.loc_at||p?.recorded_at||p?.updated_at||''),server=Date.parse(p?.server_at||'');
  return {...p,lat:validPoint(p)?Number(p.lat):null,lng:validPoint(p)?Number(p.lng):null,
   accuracy:numeric(p?.accuracy)?Number(p.accuracy):NaN,fixTime:at,ageAtReceipt:(Number.isFinite(server)?server+Math.max(0,latency):wall)-at,receivedMono:mono};
 }
 function state(p,mono=nowMono()){
  const ageMs=p?p.ageAtReceipt+Math.max(0,mono-p.receivedMono):NaN;
  const valid=validPoint(p)&&Number.isFinite(p.accuracy)&&p.accuracy>=0&&p.accuracy<=150&&Number.isFinite(ageMs)&&ageMs>=-5000;
  return {valid,live:valid&&ageMs<60000,ageMs};
 }
 function distance(a,b){
  if(!validPoint(a)||!validPoint(b))return NaN;
  const rad=Math.PI/180,dl=(b.lat-a.lat)*rad,dg=(b.lng-a.lng)*rad;
  return 12742000*Math.asin(Math.min(1,Math.sqrt(Math.sin(dl/2)**2+Math.cos(a.lat*rad)*Math.cos(b.lat*rad)*Math.sin(dg/2)**2)));
 }
 function motion(previous,next,mono=nowMono()){
  const status=state(next,mono);if(!status.valid)return {accept:false,animate:false,rotate:false,reason:'invalid'};
  if(!previous||!state(previous,mono).valid)return {accept:true,animate:false,rotate:false,reason:'first'};
  const dt=(next.fixTime-previous.fixTime)/1000,metres=distance(previous,next);
  if(dt<0)return {accept:false,animate:false,rotate:false,reason:'older_sample'};
  if(dt===0)return {accept:metres<0.1,animate:false,rotate:false,reason:'same_sample'};
  if(metres>65*dt+previous.accuracy+next.accuracy+30)return {accept:false,animate:false,rotate:false,reason:'implausible_jump'};
  return {accept:true,animate:status.live&&metres>=2&&metres<=2000,rotate:status.live&&next.accuracy<=40&&metres>Math.max(12,next.accuracy*1.5),reason:'sample'};
 }
 const api={snapshot,state,distance,motion,validPoint,nowMono};
 if(typeof module==='object'&&module.exports)module.exports=api;else root.ysGps=api;
})(globalThis);
