import {readdir,readFile,copyFile,mkdir,rm} from 'node:fs/promises';
import {join,extname} from 'node:path';
const root=process.cwd(),dest=join(root,'www');
const index=await readFile(join(root,'index.html'),'utf8');
if(!index.includes('<head')||!index.includes('supabase'))throw new Error('Expected app entry point missing');
if(/service_role|sb_secret_/i.test(index))throw new Error('Potential privileged credential in frontend');
await rm(dest,{recursive:true,force:true});await mkdir(dest,{recursive:true});
const allowed=new Set(['.html','.css','.js','.json','.webmanifest','.svg','.png','.jpg','.jpeg','.webp','.ico','.woff','.woff2']);
let count=0;
for(const entry of await readdir(root,{withFileTypes:true})){
 if(!entry.isFile()||!allowed.has(extname(entry.name).toLowerCase())||entry.name==='package.json'||entry.name==='capacitor.config.json')continue;
 await copyFile(join(root,entry.name),join(dest,entry.name));count++;
}
if(!count)throw new Error('No web assets copied');
console.log('Android web assets prepared:',count);
