(function(root){
'use strict';
// Pure KPI calculation; never assigns drivers or calls external services.
const ACTIVE=new Set(['new','received','out']);
const CLOSED=new Set(['delivered','failed','cancelled']);
function milliseconds(value){
  if(value===null||value===undefined||value==='')return null;
  const parsed=new Date(value).getTime();
  return Number.isFinite(parsed)?parsed:null;
}
function limit(value,label){
  if(typeof value!=='number'||!Number.isFinite(value)||value<=0)throw new TypeError(label+' must be a positive finite number');
  return value*60000;
}
function summarizeDeliveryOperations(orders,cfg){
  if(!Array.isArray(orders))throw new TypeError('orders must be an array');
  if(!cfg||!Number.isFinite(cfg.nowMs))throw new TypeError('nowMs is required');
  const kitchenMs=limit(cfg.kitchenLimitMinutes,'kitchenLimitMinutes');
  const deliveryMs=limit(cfg.deliveryLimitMinutes,'deliveryLimitMinutes');
  const result={total:0,active:0,delivered:0,failed:0,cancelled:0,unknown:0,lateKitchen:0,lateDelivery:0,invalidTimeRows:0};
  for(const o of orders){
    result.total++;
    if(!o||typeof o!=='object'){result.unknown++;continue;}
    const status=String(o.status||'');
    if(ACTIVE.has(status))result.active++;
    else if(CLOSED.has(status))result[status]++;
    else result.unknown++;
    const created=milliseconds(o.created_at),ready=milliseconds(o.kitchen_ready_at);
    const out=milliseconds(o.out_at),delivered=milliseconds(o.delivered_at);
    if(['created_at','kitchen_ready_at','out_at','delivered_at'].some(k=>o[k]!==null&&o[k]!==undefined&&o[k]!==''&&milliseconds(o[k])===null))result.invalidTimeRows++;
    if(created!==null){
      const end=ready!==null?ready:status==='new'?cfg.nowMs:null;
      if(end!==null&&end>=created&&end-created>kitchenMs)result.lateKitchen++;
    }
    if(out!==null){
      const end=delivered!==null?delivered:status==='out'?cfg.nowMs:null;
      if(end!==null&&end>=out&&end-out>deliveryMs)result.lateDelivery++;
    }
  }
  return Object.freeze(result);
}
if(typeof module==='object'&&module.exports)module.exports={summarizeDeliveryOperations};
else root.summarizeDeliveryOperations=summarizeDeliveryOperations;
})(globalThis);
