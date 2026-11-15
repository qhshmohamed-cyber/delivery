package com.yourstaff.delivery;

import android.Manifest;
import android.app.AlertDialog;
import android.content.Intent;
import android.os.Build;
import androidx.core.content.ContextCompat;
import com.getcapacitor.*;
import com.getcapacitor.annotation.*;
import org.json.JSONObject;

@CapacitorPlugin(name="YourStaffBackground",permissions={
    @Permission(alias="location",strings={Manifest.permission.ACCESS_FINE_LOCATION,Manifest.permission.ACCESS_COARSE_LOCATION}),
    @Permission(alias="notifications",strings={Manifest.permission.POST_NOTIFICATIONS})
})
public class YourStaffBackgroundPlugin extends Plugin {
    private static final java.util.concurrent.atomic.AtomicInteger generation=new java.util.concurrent.atomic.AtomicInteger();
    private final java.util.concurrent.ExecutorService io=java.util.concurrent.Executors.newSingleThreadExecutor();
    private boolean current(PluginCall call){return call.getInt("nativeGeneration",-1)==generation.get();}
    private boolean allowedKey(String key){return NativeEndpoint.AUTH_KEY.equals(key)||(NativeEndpoint.AUTH_KEY+"-code-verifier").equals(key);}
    @PluginMethod public void getItem(PluginCall call){
        String key=call.getString("key","");if(!allowedKey(key)){call.reject("Storage key forbidden");return;}
        try{
            // Native refresh is the single refresh authority; GoTrue's native auto-refresh is disabled.
            if(key.equals(NativeEndpoint.AUTH_KEY)){
                try{NativeApi.session(getContext());}catch(NativeApi.Denied denied){DriverLocationService.stopNow(getContext());SessionVault.put(getContext(),key,null);}
                catch(java.io.IOException offline){ /* Keep stored session for an online retry. */ }
            }
            String value=SessionVault.get(getContext(),key);JSObject result=new JSObject();result.put("value",value==null?JSONObject.NULL:value);call.resolve(result);
        }catch(Exception error){call.reject("Secure session storage unavailable");}
    }
    @PluginMethod public void setItem(PluginCall call){
        String key=call.getString("key","");if(!allowedKey(key)){call.reject("Storage key forbidden");return;}
        try{SessionVault.put(getContext(),key,call.getString("value"));call.resolve();}catch(Exception e){call.reject("Secure session write failed");}
    }
    @PluginMethod public void removeItem(PluginCall call){
        String key=call.getString("key","");if(!allowedKey(key)){call.reject("Storage key forbidden");return;}
        try{if(key.equals(NativeEndpoint.AUTH_KEY))DriverLocationService.stopNow(getContext());SessionVault.put(getContext(),key,null);call.resolve();}catch(Exception e){call.reject("Secure session removal failed");}
    }
    @PluginMethod public void start(PluginCall call){
        call.getData().put("nativeGeneration",generation.incrementAndGet());
        if(DriverLocationService.runningForUser(call.getString("userId",""))){JSObject result=new JSObject();result.put("started",true);call.resolve(result);return;}
        getActivity().runOnUiThread(()->new AlertDialog.Builder(getActivity()).setTitle("مشاركة الموقع أثناء الشفت")
            .setMessage("سيشارك Your Staff موقعك مع إدارة فرعك أثناء الشفت، حتى عند قفل الشاشة أو فتح تطبيق آخر. يظهر إشعار دائم. يمكنك الإيقاف من التطبيق أو تسجيل الخروج. لا يبدأ التتبع بعد إعادة تشغيل الهاتف تلقائيًا.")
            .setPositiveButton("موافق — تشغيل التتبع",(dialog,which)->requestLocation(call))
            .setNegativeButton("إلغاء",(dialog,which)->call.reject("تم إلغاء تشغيل مشاركة الموقع"))
            .setOnCancelListener(dialog->call.reject("تم إلغاء تشغيل مشاركة الموقع")).show());
    }
    private void requestLocation(PluginCall call){
        if(!current(call)){call.reject("تم إلغاء الطلب");return;}
        if(getPermissionState("location")!=PermissionState.GRANTED)requestPermissionForAlias("location",call,"locationReady");else locationReady(call);
    }
    @PermissionCallback private void locationReady(PluginCall call){
        if(!current(call)){call.reject("تم إلغاء الطلب");return;}
        if(getPermissionState("location")!=PermissionState.GRANTED){call.reject("يلزم السماح بالموقع الدقيق لتشغيل التتبع");return;}
        if(Build.VERSION.SDK_INT>=33&&getPermissionState("notifications")!=PermissionState.GRANTED)requestPermissionForAlias("notifications",call,"notificationsReady");else notificationsReady(call);
    }
    @PermissionCallback private void notificationsReady(PluginCall call){
        if(!current(call)){call.reject("تم إلغاء الطلب");return;}
        if(Build.VERSION.SDK_INT>=33&&getPermissionState("notifications")!=PermissionState.GRANTED){call.reject("يلزم السماح بإشعار التتبع الظاهر");return;}
        io.execute(()->{try{
            JSONObject session=NativeApi.session(getContext());String requested=call.getString("userId","");
            if(requested.isEmpty()||!requested.equals(SessionVault.user(session))){call.reject("جلسة الحساب غير متاحة");return;}
            JSONObject duty=NativeApi.request("/rest/v1/rpc/dlv_my_driver_duty",session.getString("access_token"),new JSONObject());
            if(!duty.optString("state").equals("available")&&!duty.optString("state").equals("delivering")){call.reject("ابدأ الشفت أولًا");return;}
            synchronized(generation){
            if(!current(call)){call.reject("تم إلغاء الطلب");return;}
            if(DriverLocationService.runningForUser(requested)){JSObject result=new JSObject();result.put("started",true);call.resolve(result);return;}
            DriverLocationService.stopNow(getContext());
            String run=new JSONObject().put("userId",requested).put("runId",java.util.UUID.randomUUID().toString()).toString();
            SessionVault.put(getContext(),DriverLocationService.WANTED,run);
            ContextCompat.startForegroundService(getContext(),new Intent(getContext(),DriverLocationService.class));
            confirmStarted(call,run,50);
            }
        }catch(Exception e){DriverLocationService.stopNow(getContext());call.reject("تعذر تشغيل خدمة الخلفية؛ تحقق من الجلسة وصلاحية الموقع");}});
    }
    private void confirmStarted(PluginCall call,String run,int remaining){
        if(!current(call)){call.reject("تم إلغاء الطلب");return;}
        if(DriverLocationService.runningFor(run)){JSObject result=new JSObject();result.put("started",true);call.resolve(result);return;}
        if(remaining==0){DriverLocationService.stopNow(getContext());call.reject("لم يؤكد Android تشغيل الخدمة؛ أعد المحاولة من التطبيق");return;}
        new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(()->confirmStarted(call,run,remaining-1),100);
    }
    @PluginMethod public void stop(PluginCall call){
        synchronized(generation){generation.incrementAndGet();DriverLocationService.stopNow(getContext());}try{SessionVault.put(getContext(),DriverLocationService.WANTED,null);call.resolve();}catch(Exception e){call.reject("تعذر تأكيد إيقاف التتبع");}
    }
    @PluginMethod public void status(PluginCall call){try{call.resolve(JSObject.fromJSONObject(DriverLocationService.status()));}catch(Exception e){call.reject("تعذر قراءة حالة الخدمة");}}
}
