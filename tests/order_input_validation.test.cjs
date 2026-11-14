const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
const names=['deliveryDigits','deliveryMobile','orderSearchTerm'];
const context={};vm.createContext(context);
for(const name of names){const start=html.indexOf('function '+name+'('),end=html.indexOf('\n}',start)+2;assert(start>=0&&end>start);vm.runInContext(html.slice(start,end),context);}
for(const input of ['01012345678','+20 10 1234 5678','٠١٠١٢٣٤٥٦٧٨','۰۱۰۱۲۳۴۵۶۷۸','٢٠١٠١٢٣٤٥٦٧٨'])assert.equal(context.deliveryMobile(input),'201012345678');
for(const prefix of ['011','012','015'])assert.equal(context.deliveryMobile(prefix+'12345678'),'20'+prefix.slice(1)+'12345678');
for(const input of ['01312345678','01012345','+971501234567','123','0'])assert.equal(context.deliveryMobile(input),null);
assert.equal(context.deliveryMobile('  '),'');
assert.equal(context.orderSearchTerm('محمد عبد العظيم'),'محمد عبد العظيم');
assert.equal(context.orderSearchTerm('طلب ١٢٣-٤'),'طلب 123-4');
assert.equal(context.orderSearchTerm('  01012345678  '),'01012345678');
assert(!/[%(),.*]/.test(context.orderSearchTerm('test%,phone.neq.(x),*')));
assert.equal(context.orderSearchTerm('أ'.repeat(80)).length,60);
assert(html.includes('p_phone: isMgr ? normalizedCustomerPhone||null'));
assert(html.includes("const q=orderSearchTerm($('f_q').value)"));
(async()=>{
 const start=html.indexOf('async function updateCustomerOrderCount()'),end=html.indexOf('\n  }',start)+4;
 const label={textContent:'',isConnected:true},phone={value:'٠١٠١٢٣٤٥٦٧٨'};let calls=[];
 context.$=id=>({n_customer_count:label,n_p:phone,n_branch:{value:'1'}})[id];
 context.selectedBranch=1;context.me={branch_id:1};context.safeRpc=async(name,args)=>{calls.push({name,args});return {data:3,error:null};};
 vm.runInContext('let customerCountRequest=0;\n'+html.slice(start,end),context);
 await context.updateCustomerOrderCount();
 assert.deepEqual(calls.map(x=>[x.name,x.args.p_branch_id,x.args.p_phone]),[['dlv_customer_order_count',1,'201012345678']]);
 assert(label.textContent.includes('3'));
 calls=[];phone.value='01312345678';await context.updateCustomerOrderCount();assert.equal(calls.length,0);assert(label.textContent.includes('صحيح'));
 console.log('PASS order inputs: Egyptian phone formats, Arabic/Persian digits, Arabic search, filter punctuation removed, actual customer-count form invokes scoped RPC for valid numbers only');
})().catch(error=>{console.error(error);process.exitCode=1;});
