package com.yourstaff.delivery;

import android.content.Context;
import java.net.URL;
import javax.net.ssl.HttpsURLConnection;
import java.nio.charset.StandardCharsets;
import java.io.InputStream;
import org.json.JSONObject;

final class NativeApi {
    interface Transport { JSONObject request(String path,String token,JSONObject body) throws Exception; }
    // Only instrumentation/debug builds can install this transport; release always uses HTTPS.
    private static volatile Transport testTransport;
    static void setTestTransport(Context context,Transport transport){
        if((context.getApplicationInfo().flags&android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE)==0)throw new SecurityException("Release test transport forbidden");
        testTransport=transport;
    }
    static final class Denied extends Exception { Denied(){super("Session or access no longer valid");} }
    static JSONObject request(String path,String token,JSONObject body) throws Exception {
        if(testTransport!=null)return testTransport.request(path,token,body);
        if(!path.equals("/auth/v1/token?grant_type=refresh_token")&&!path.equals("/rest/v1/rpc/dlv_my_driver_duty")&&!path.equals("/rest/v1/rpc/dlv_update_location"))throw new SecurityException("Endpoint forbidden");
        HttpsURLConnection connection=(HttpsURLConnection)new URL(NativeEndpoint.URL+path).openConnection();
        connection.setInstanceFollowRedirects(false);connection.setConnectTimeout(10000);connection.setReadTimeout(10000);
        connection.setRequestMethod("POST");connection.setDoOutput(true);
        connection.setRequestProperty("Content-Type","application/json");connection.setRequestProperty("apikey",NativeEndpoint.PUBLIC_KEY);
        if(token!=null)connection.setRequestProperty("Authorization","Bearer "+token);
        try{
            try(java.io.OutputStream out=connection.getOutputStream()){out.write(body.toString().getBytes(StandardCharsets.UTF_8));}
            int status=connection.getResponseCode();
            if(status==400&&path.startsWith("/auth/")||status==401||status==403)throw new Denied();
            if(status<200||status>=300)throw new java.io.IOException("Temporary server error");
            try(InputStream in=connection.getInputStream()){
                String result=readText(in).trim();
                return result.isEmpty()||result.equals("null")?new JSONObject():new JSONObject(result);
            }
        }finally{connection.disconnect();}
    }
    private static String readText(InputStream in) throws Exception {
        java.io.ByteArrayOutputStream out=new java.io.ByteArrayOutputStream();byte[] buffer=new byte[4096];int size;
        while((size=in.read(buffer))!=-1){if(out.size()+size>1024*1024)throw new java.io.IOException("Response too large");out.write(buffer,0,size);}
        return new String(out.toByteArray(),StandardCharsets.UTF_8);
    }
    /** One refresh authority for both native storage reads and background updates. */
    static JSONObject session(Context c) throws Exception {
        synchronized(SessionVault.class){
            String raw=SessionVault.get(c,NativeEndpoint.AUTH_KEY);if(raw==null)return null;
            JSONObject current=new JSONObject(raw);
            if(current.optLong("expires_at")>System.currentTimeMillis()/1000+90)return current;
            String refresh=current.optString("refresh_token");if(refresh.isEmpty())throw new Denied();
            JSONObject next=request("/auth/v1/token?grant_type=refresh_token",null,new JSONObject().put("refresh_token",refresh));
            if(!SessionVault.user(current).equals(SessionVault.user(next))||next.optString("access_token").isEmpty()||next.optString("refresh_token").isEmpty())throw new Denied();
            if(!next.has("expires_at"))next.put("expires_at",System.currentTimeMillis()/1000+next.getLong("expires_in"));
            // Keep SDK session fields (including user) in the same encrypted auth storage.
            for(java.util.Iterator<String> i=next.keys();i.hasNext();){String k=i.next();current.put(k,next.get(k));}
            SessionVault.put(c,NativeEndpoint.AUTH_KEY,current.toString());return current;
        }
    }
}
