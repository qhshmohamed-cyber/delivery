const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {createInstallController}=require('../web-install.js');
(async()=>{
 assert.equal(await createInstallController({secure:false}).request(),'insecure');
 assert.equal(await createInstallController({installed:true}).request(),'installed');
 const controller=createInstallController();assert.equal(await controller.request(),'manual');
 let prompts=0,resolve;
 const choice=new Promise(r=>{resolve=r;});
 controller.capture({prompt:async()=>{prompts++;},userChoice:choice});
 const first=controller.request();assert.equal(await controller.request(),'busy');resolve({outcome:'accepted'});assert.equal(await first,'accepted');assert.equal(prompts,1);
 // Accepting a prompt is not proof of completed installation.
 assert.equal(await controller.request(),'manual');controller.installed();assert.equal(await controller.request(),'installed');
 const dismissed=createInstallController();dismissed.capture({prompt:async()=>{},userChoice:Promise.resolve({outcome:'dismissed'})});assert.equal(await dismissed.request(),'dismissed');
 const failed=createInstallController();failed.capture({prompt:async()=>{throw Error('blocked');}});assert.equal(await failed.request(),'error');
 const root=path.join(__dirname,'..'),manifest=JSON.parse(fs.readFileSync(path.join(root,'manifest.webmanifest'),'utf8'));
 assert.equal(manifest.id,'./');assert.equal(manifest.start_url,'./');assert.equal(manifest.prefer_related_applications,false);
 for(const size of [192,512]){const icon=manifest.icons.find(x=>x.sizes===size+'x'+size);assert(icon);const bytes=fs.readFileSync(path.join(root,icon.src));assert.equal(bytes.readUInt32BE(16),size);assert.equal(bytes.readUInt32BE(20),size);}
 console.log('PASS web install: HTTPS, user-controlled prompt, concurrency, no false installation success, cancellation, error recovery, stable manifest identity and real-size app icons');
})().catch(error=>{console.error(error);process.exitCode=1;});
