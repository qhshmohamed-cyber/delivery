const assert=require('node:assert/strict');
(async()=>{
 const {hardenManifest,backupRules,extractionRules,domains}=await import('../scripts/harden-android.mjs');
 const fixture='<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:allowBackup="true" android:usesCleartextTraffic="true"><activity/></application></manifest>';
 const secured=hardenManifest(fixture);
 assert.match(secured,/android:allowBackup="false"/);
 assert.match(secured,/android:usesCleartextTraffic="false"/);
 assert.match(secured,/android:fullBackupContent="@xml\/backup_rules"/);
 assert.match(secured,/android:dataExtractionRules="@xml\/data_extraction_rules"/);
 assert.equal(hardenManifest(secured),secured,'hardening must be idempotent');
 assert.throws(()=>hardenManifest('<manifest/>'));
 assert.throws(()=>hardenManifest(fixture.replace('<application ','<application android:debuggable="true" ')));
 for(const domain of domains){
  assert(backupRules.includes(`domain="${domain}" path="."`));
  assert.equal(extractionRules.split(`domain="${domain}" path="."`).length-1,2,'both cloud and device transfer must exclude app data');
 }
 const config=require('../capacitor.config.json');
 assert.equal(config.android.webContentsDebuggingEnabled,false);
 assert.equal(config.android.allowMixedContent,false);
 assert.equal(config.loggingBehavior,'none');
 console.log('Android hardening tests passed');
})().catch(e=>{console.error(e);process.exitCode=1});
