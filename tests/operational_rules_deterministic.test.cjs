const assert=require('node:assert/strict');
const {summarizeDeliveryOperations:compute}=require('../operational-rules.js');
const minute=60000,now=Date.UTC(2026,10,19,16);
const when=m=>new Date(now-m*minute).toISOString();
const cfg={nowMs:now,kitchenLimitMinutes:30,deliveryLimitMinutes:30};
const fixture=[
 Object.freeze({id:1,status:'new',created_at:when(45)}),
 Object.freeze({id:2,status:'delivered',created_at:when(80),kitchen_ready_at:when(60),out_at:when(45),delivered_at:when(10)}),
 Object.freeze({id:3,status:'cancelled',created_at:when(5)}),
 Object.freeze({id:4,status:'out',created_at:when(90),kitchen_ready_at:when(70),out_at:when(10)})
];
const original=JSON.stringify(fixture);
const result=compute(fixture,cfg);
assert.equal(result.total,4);assert.equal(result.active,2);assert.equal(result.delivered,1);
assert.equal(result.cancelled,1);assert.equal(result.lateKitchen,1);assert.equal(result.lateDelivery,1);
assert.deepEqual(compute([...fixture].reverse(),cfg),result);
assert.equal(JSON.stringify(fixture),original,'Inputs must stay unchanged');
assert(Object.isFrozen(result));
assert.throws(()=>compute([], {...cfg,kitchenLimitMinutes:0}),TypeError);
// Deterministic offline fixtures, NOT real throughput or concurrent load testing.
const rows=Array.from({length:500},(_,id)=>Object.freeze({
 id:id+1,status:id%5===0?'delivered':id%5===1?'cancelled':'new',
 created_at:when(id%90),kitchen_ready_at:id%5===0?when(2):null,
 out_at:id%5===0?when(40):null,delivered_at:id%5===0?when(1):null
}));
const snapshot=compute(rows,cfg);
assert.equal(snapshot.total,500);
assert.equal(snapshot.active+snapshot.delivered+snapshot.failed+snapshot.cancelled+snapshot.unknown,500);
assert.deepEqual(snapshot,compute(rows,cfg));
assert(rows.every(o=>!('driver_id' in o)));
console.log('PASS: deterministic KPI rules and 500 offline test orders; no automatic driver assignment.');
