// Simulated browser regression for PR #70. NO real customer data, GPS or production writes.
// Guarantees one selected button at a time in the new driver UI; it does not certify real-device tracking.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../navigation-target.js'), 'utf8');

function browser(initialRole='driver') {
  const nodes = new Map(), calls = [], allNav = [];
  const events = [], server = {selected: null, reject: false};
  const me = {role: initialRole};
  const labels = [];
  function element(name) {
    return {
      nodeName:name, dataset:{}, style:{}, isConnected:true, textContent:'', className:'',
      attrs:{}, listeners:{},
      addEventListener(type, handler) { this.listeners[type] = handler; },
      setAttribute(k,v) { this.attrs[k] = v; },
      getAttribute(k) { return this.attrs[k] ?? null; },
      append(child) { (this.children??=[]).push(child); },
      closest() { return null; }
    };
  }
  const actions = [5,6,7,8].map(id => {
    const buttons = [];
    return {id,buttons,
      querySelector(sel) { return buttons.find(x=>sel.includes('"'+x.dataset.navOrder+'"'))??null; },
      prepend(button) {
        button.closest = type => type==='.card'?{querySelector:()=>({textContent:'#'+id})}:null;
        buttons.unshift(button); allNav.push(button);
      }
    };
  });
  const delivered = actions.map(a=>({
    dataset:{act:'delivered',id:String(a.id)},
    closest(type){return type==='.acts'?a:null;}
  }));
  const root = {
    isConnected:true,
    before(child) { labels.push(child); nodes.set(child.id, child); },
    querySelectorAll(q) {
      if(q==='button[data-act="delivered"]') return delivered;
      if(q==='[data-nav-order]') return allNav;
      throw Error('Unexpected selector '+q);
    },
    querySelector(q) {
      const m = q.match(/data-nav-order="(\d+)"/);
      return m?allNav.find(b=>b.dataset.navOrder===m[1])??null:null;
    }
  };
  nodes.set('ol',root);
  const document = {readyState:'complete',body:{},visibilityState:'visible',
    getElementById:id=>nodes.get(id)||null, createElement:element};
  const ctx={
    document, me, navigator:{onLine:true},
    MutationObserver:class {observe(){}},
    setTimeout:fn=>{fn();return 1;},
    setInterval:()=>1,
    flash:(message,ok)=>events.push({message,ok}),
    safeRpc:async(name,args={})=>{
      calls.push({name,args});
      if(name==='dlv_current_customer_navigation') return {data:{order_id:server.selected}};
      if(server.reject) return {error:{message:'denied'}};
      if(name==='dlv_begin_customer_navigation'){server.selected=args.p_order_id;return {data:{success:true}};}
      if(name==='dlv_stop_customer_navigation'){
        const stopped = server.selected===args.p_order_id;
        if(stopped)server.selected=null;
        return {data:{stopped}};
      }
      throw Error('unexpected RPC '+name);
    }
  };
  vm.runInNewContext(source,ctx,{timeout:1000,filename:'navigation-target.js'});
  return {actions,allNav,calls,server,events,ctx};
}
const tick=()=>new Promise(r=>setImmediate(r));
function selected(ui) { return ui.allNav.filter(x=>x.attrs['aria-pressed']==='true').map(x=>Number(x.dataset.navOrder)); }
async function click(ui,id) {
  const b=ui.actions.find(a=>a.id===id).buttons[0];
  assert.ok(b,'navigation button should exist');
  b.listeners.click();
  await tick(); await tick();
}
(async()=>{
  const ui=browser();
  await tick();
  assert.equal(ui.allNav.length,4,'one navigation button per order');
  assert.deepEqual(selected(ui),[]);
  for(const id of [5,6,7,8]) {
    await click(ui,id);
    assert.equal(ui.server.selected,id);
    assert.deepEqual(selected(ui),[id], 'only the active order can be selected');
    for(const other of [5,6,7,8].filter(x=>x!==id))
      assert.equal(ui.actions.find(a=>a.id===other).buttons[0].attrs['aria-pressed'],'false');
  }
  await click(ui,8);
  assert.equal(ui.server.selected,null);
  assert.deepEqual(selected(ui),[]);
  assert.deepEqual(ui.calls.filter(x=>x.name==='dlv_begin_customer_navigation').map(x=>x.args.p_order_id),[5,6,7,8]);
  assert.equal(ui.calls.filter(x=>x.name==='dlv_stop_customer_navigation').length,1);
  const before=ui.calls.length;
  ui.ctx.navigator.onLine=false;
  await click(ui,5);
  assert.equal(ui.calls.length,before,'offline must not call backend');
  ui.ctx.navigator.onLine=true;
  ui.server.reject=true;
  await click(ui,5);
  assert.deepEqual(selected(ui),[],'denied target must not appear active');
  assert.equal(ui.server.selected,null);
  const mgr=browser('manager');
  await tick();
  assert.equal(mgr.allNav.length,0,'manager view cannot get driver navigation buttons');
  assert.equal(mgr.calls.length,0,'manager cannot query driver route via UI');
  console.log('PASS targeted navigation: four-order switch, exclusive selection, stop, offline, denied, non-driver');
})().catch(e=>{console.error(e);process.exitCode=1;});
