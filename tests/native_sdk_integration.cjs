// Real pinned SDK with the native storage adapter; synthetic auth HTTP responses only.
const assert=require('node:assert/strict'),fs=require('node:fs'),crypto=require('node:crypto'),Module=require('node:module');
const {createNativeBackground}=require('../native-background.js');
(async()=>{
 const html=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
 const script=html.match(/<script src="(https:\/\/cdn\.jsdelivr\.net\/npm\/@supabase\/supabase-js@[^\"]+)" integrity="sha384-([^\"]+)"/);assert(script);
 const code=process.env.YS_SDK_FIXTURE?fs.readFileSync(process.env.YS_SDK_FIXTURE):Buffer.from(await (await fetch(script[1],{signal:AbortSignal.timeout(30000)})).arrayBuffer());
 assert.equal(crypto.createHash('sha384').update(code).digest('base64'),script[2]);
 const compiled=new Module('/tmp/yourstaff-sdk-verified.cjs',module);compiled.filename='/tmp/yourstaff-sdk-verified.cjs';compiled.paths=module.paths;compiled._compile(code.toString()+'\nmodule.exports=supabase;','yourstaff-sdk-verified.cjs');
 const authKey='sb-mkptmejkcemdhlhdaort-auth-token',store=new Map(),accessed=[];
 const allowed=key=>[authKey,authKey+'-user',authKey+'-code-verifier',authKey+'-flows-code-verifier'].includes(key)||new RegExp('^'+authKey+'-flow-[a-fA-F0-9]{32}-code-verifier$').test(key);
 const guard=key=>{accessed.push(key);assert(allowed(key),'unexpected SDK storage key '+key);};
 const plugin={getItem:async({key})=>{guard(key);return {value:store.get(key)??null};},setItem:async({key,value})=>{guard(key);store.set(key,value);},removeItem:async({key})=>{guard(key);store.delete(key);}};
 const native=createNativeBackground({getPlatform:()=> 'android',isNativePlatform:()=>true,registerPlugin:()=>plugin});
 const user={id:'00000000-0000-4000-8000-000000000001',aud:'authenticated',email:'fixture@example.invalid',app_metadata:{},user_metadata:{},created_at:new Date().toISOString()};
 const encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url');const token=encode({alg:'HS256',typ:'JWT'})+'.'+encode({sub:user.id,exp:Math.floor(Date.now()/1000)+3600,aud:'authenticated'})+'.synthetic';
 const client=compiled.exports.createClient('https://mkptmejkcemdhlhdaort.supabase.co','synthetic-public-key',{auth:{storage:native.storage,persistSession:true,autoRefreshToken:false,detectSessionInUrl:false},global:{fetch:async(url)=>{
  if(String(url).includes('/token?grant_type=password'))return new Response(JSON.stringify({access_token:token,refresh_token:'synthetic-refresh',expires_in:3600,token_type:'bearer',user}),{status:200,headers:{'Content-Type':'application/json'}});
  if(String(url).includes('/logout'))return new Response(null,{status:204});throw Error('Unexpected network request');
 }}});
 assert.equal((await client.auth.signInWithPassword({email:user.email,password:'synthetic-fixture'})).error,null);
 assert.equal((await client.auth.getSession()).data.session.user.id,user.id);
 assert.equal((await client.auth.signOut({scope:'local'})).error,null);
 assert.equal((await client.auth.getSession()).data.session,null);
 assert.equal(store.has(authKey),false);assert(accessed.includes(authKey+'-flows-code-verifier'));assert(accessed.includes(authKey+'-user'));
 console.log('PASS pinned Supabase SDK: native-storage sign-in, persisted session, full sign-out/PKCE/user cleanup and SRI verification');
})().catch(e=>{console.error(e);process.exitCode=1;});
