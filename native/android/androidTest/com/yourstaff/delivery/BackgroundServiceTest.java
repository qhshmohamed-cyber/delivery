package com.yourstaff.delivery;

import static org.junit.Assert.*;
import org.junit.*;
import org.junit.runner.RunWith;
import org.json.JSONObject;
import android.content.*;
import android.location.Location;
import android.os.*;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.util.concurrent.atomic.AtomicInteger;

@RunWith(AndroidJUnit4.class)
public class BackgroundServiceTest {
    Context context;
    @Before public void before() throws Exception {
        context=InstrumentationRegistry.getInstrumentation().getTargetContext();
        DriverLocationService.stopNow(context);
        NativeApi.setTestTransport(context,(path,token,body)->{
            if(path.startsWith("/auth/"))return session("fresh",3600);
            return new JSONObject().put("state","available");
        });
    }
    @After public void after() throws Exception {try(ParcelFileDescriptor p=InstrumentationRegistry.getInstrumentation().getUiAutomation().executeShellCommand("input keyevent KEYCODE_WAKEUP")){new java.io.FileInputStream(p.getFileDescriptor()).read(new byte[2048]);}DriverLocationService.stopNow(context);SessionVault.put(context,NativeEndpoint.AUTH_KEY,null);NativeApi.setTestTransport(context,null);}
    private JSONObject session(String token,long seconds) throws Exception {
        return new JSONObject().put("access_token",token).put("refresh_token","synthetic-refresh").put("expires_at",System.currentTimeMillis()/1000+seconds).put("user",new JSONObject().put("id","synthetic-driver"));
    }
    @Test public void sdkSessionCleanupStorageKeys(){
        for(String suffix:new String[]{"","-user","-code-verifier","-flows-code-verifier","-flow-0123456789abcdef0123456789abcdef-code-verifier"})assertTrue(YourStaffBackgroundPlugin.allowedKey(NativeEndpoint.AUTH_KEY+suffix));
        assertFalse(YourStaffBackgroundPlugin.allowedKey("other-project-auth-token"));assertFalse(YourStaffBackgroundPlugin.allowedKey(NativeEndpoint.AUTH_KEY+"-arbitrary"));
    }
    @Test public void encryptedStorageAndSharedRefresh() throws Exception {
        SessionVault.put(context,NativeEndpoint.AUTH_KEY,session("old",1).toString());
        assertFalse(context.getSharedPreferences("yourstaff_private_session",0).getString(NativeEndpoint.AUTH_KEY,"").contains("synthetic-refresh"));
        assertEquals("fresh",NativeApi.session(context).getString("access_token"));
        assertEquals("fresh",new JSONObject(SessionVault.get(context,NativeEndpoint.AUTH_KEY)).getString("access_token"));
    }
    @Test public void invalidAndStaleLocationsAreRejected(){
        Location fix=new Location("gps");fix.setLatitude(30);fix.setLongitude(31);fix.setAccuracy(10);fix.setElapsedRealtimeNanos(SystemClock.elapsedRealtimeNanos());assertTrue(DriverLocationService.valid(fix));
        fix.setLatitude(91);assertFalse(DriverLocationService.valid(fix));fix.setLatitude(30);fix.setAccuracy(151);assertFalse(DriverLocationService.valid(fix));fix.setAccuracy(10);fix.setElapsedRealtimeNanos(SystemClock.elapsedRealtimeNanos()-60000000000L);assertFalse(DriverLocationService.valid(fix));
    }
    @Test public void foregroundServiceSurvivesBackgroundAndStopsAtLogout() throws Exception {
        for(String permission:new String[]{"ACCESS_FINE_LOCATION","ACCESS_COARSE_LOCATION","POST_NOTIFICATIONS"}){
            try(ParcelFileDescriptor p=InstrumentationRegistry.getInstrumentation().getUiAutomation().executeShellCommand("pm grant "+context.getPackageName()+" android.permission."+permission)){new java.io.FileInputStream(p.getFileDescriptor()).read(new byte[2048]);}
        }
        AtomicInteger sends=new AtomicInteger();
        NativeApi.setTestTransport(context,(path,token,body)->{if(path.endsWith("dlv_update_location"))sends.incrementAndGet();return new JSONObject().put("state","available");});
        SessionVault.put(context,NativeEndpoint.AUTH_KEY,session("fixture",3600).toString());
        SessionVault.put(context,DriverLocationService.WANTED,new JSONObject().put("userId","synthetic-driver").put("runId","test-run").toString());
        Intent activity=new Intent(context,BackgroundTestActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);InstrumentationRegistry.getInstrumentation().startActivitySync(activity);
        androidx.core.content.ContextCompat.startForegroundService(context,new Intent(context,DriverLocationService.class));
        for(int i=0;i<50&&(!DriverLocationService.status().optBoolean("running"));i++)SystemClock.sleep(100);
        assertTrue("Foreground service must start",DriverLocationService.status().getBoolean("running"));
        context.startActivity(new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        int beforeBackground=sends.get();
        try(ParcelFileDescriptor p=InstrumentationRegistry.getInstrumentation().getUiAutomation().executeShellCommand("input keyevent KEYCODE_SLEEP")){new java.io.FileInputStream(p.getFileDescriptor()).read(new byte[2048]);}
        SystemClock.sleep(5500);
        Location fix=new Location("gps");fix.setLatitude(30);fix.setLongitude(31);fix.setAccuracy(10);fix.setElapsedRealtimeNanos(SystemClock.elapsedRealtimeNanos());
        DriverLocationService.instance.onLocationChanged(fix);
        for(int i=0;i<50&&sends.get()<=beforeBackground;i++)SystemClock.sleep(100);
        assertTrue("Location must be sent after activity goes to background",sends.get()>beforeBackground);
        DriverLocationService.stopNow(context);SessionVault.put(context,NativeEndpoint.AUTH_KEY,null);
        int before=sends.get();SystemClock.sleep(600);assertFalse(DriverLocationService.status().getBoolean("running"));assertEquals(before,sends.get());
    }
}
