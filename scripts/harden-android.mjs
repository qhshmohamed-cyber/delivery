import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

export function hardenManifest(xml){
 const tags=xml.match(/<application\b[^>]*>/g);
 if(!tags||tags.length!==1||!xml.includes('xmlns:android="http://schemas.android.com/apk/res/android"'))throw new Error('Unexpected Android manifest');
 let tag=tags[0];
 const attrs={allowBackup:'false',fullBackupContent:'@xml/backup_rules',dataExtractionRules:'@xml/data_extraction_rules',usesCleartextTraffic:'false'};
 for(const [key,value] of Object.entries(attrs)){
  tag=tag.replace(new RegExp('\\s+android:'+key+'="[^"]*"','g'),'');
  tag=tag.replace(/>$/,` android:${key}="${value}">`);
 }
 // Gradle supplies debuggable=false for release; never ship the debug variant.
 if(/android:debuggable="true"/.test(tag))throw new Error('Debuggable application declared in main manifest');
 return xml.replace(tags[0],tag);
}
export const domains=['root','file','database','sharedpref','external','device_root','device_file','device_database','device_sharedpref'];
const exclusions=domains.map(domain=>`    <exclude domain="${domain}" path="."/>`).join('\n');
export const backupRules=`<?xml version="1.0" encoding="utf-8"?>\n<full-backup-content>\n${exclusions}\n</full-backup-content>\n`;
export const extractionRules=`<?xml version="1.0" encoding="utf-8"?>\n<data-extraction-rules>\n  <cloud-backup>\n${exclusions}\n  </cloud-backup>\n  <device-transfer>\n${exclusions}\n  </device-transfer>\n</data-extraction-rules>\n`;
export async function hardenAndroid(root=process.cwd()){
 const main=join(root,'android/app/src/main'),manifest=join(main,'AndroidManifest.xml'),res=join(main,'res/xml');
 const hardened=hardenManifest(await readFile(manifest,'utf8'));
 await mkdir(res,{recursive:true});
 await writeFile(join(res,'backup_rules.xml'),backupRules);
 await writeFile(join(res,'data_extraction_rules.xml'),extractionRules);
 await writeFile(manifest,hardened);
 console.log('Android privacy controls applied: no backup/transfer or cleartext traffic.');
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)await hardenAndroid();
