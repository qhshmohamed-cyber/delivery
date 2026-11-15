package com.yourstaff.delivery;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.content.pm.ServiceInfo;
import android.location.*;
import android.os.*;
import androidx.core.app.NotificationCompat;
import androidx.core.content.ContextCompat;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import org.json.JSONObject;

/** Foreground location service: never depends on a WebView timer or a service worker. */
public class DriverLocationService extends Service implements LocationListener {
    static volatile DriverLocationService instance;
    static final String WANTED="tracking-user",CHANNEL="yourstaff_driver_location";
    private volatile boolean running;
    private volatile Location latest;
    private volatile long lastSent;
    private volatile String state="starting";
    private String user="",wanted;
    private LocationManager locations;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final AtomicBoolean busy=new AtomicBoolean(false);
    private final Runnable pulse=new Runnable(){public void run(){if(running){submit();main.postDelayed(this,30000);}}};
    static void stopNow(Context c){
        DriverLocationService service=instance;if(service!=null)service.halt();
        c.stopService(new Intent(c,DriverLocationService.class));
    }
    @Override public void onCreate(){super.onCreate();instance=this;}
    @Override public int onStartCommand(Intent intent,int flags,int id){
        if(running)return START_STICKY;
        try{
            wanted=SessionVault.get(this,WANTED);user=wanted==null?null:new JSONObject(wanted).optString("userId");
            if(user==null||user.isEmpty()||ContextCompat.checkSelfPermission(this,Manifest.permission.ACCESS_FINE_LOCATION)!=PackageManager.PERMISSION_GRANTED){stopSelf();return START_NOT_STICKY;}
            NotificationManager manager=getSystemService(NotificationManager.class);
            manager.createNotificationChannel(new NotificationChannel(CHANNEL,"تتبع توصيلات Your Staff",NotificationManager.IMPORTANCE_LOW));
            Intent open=getPackageManager().getLaunchIntentForPackage(getPackageName());
            PendingIntent view=PendingIntent.getActivity(this,0,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
            Notification notification=new NotificationCompat.Builder(this,CHANNEL).setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setContentTitle("Your Staff — مشاركة موقع الطيار")
                .setContentText("التتبع يعمل أثناء الشفت. افتح التطبيق لإيقافه أو تسجيل الخروج.")
                .setContentIntent(view).setOngoing(true).setCategory(NotificationCompat.CATEGORY_SERVICE).build();
            if(Build.VERSION.SDK_INT>=29)startForeground(17223,notification,ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION);else startForeground(17223,notification);
            running=true;locations=(LocationManager)getSystemService(LOCATION_SERVICE);
            // GPS only: no cached or network-derived stale fix is submitted.
            locations.requestLocationUpdates(LocationManager.GPS_PROVIDER,10000,0,this,Looper.getMainLooper());
            main.post(pulse);return START_STICKY;
        }catch(Exception error){state="permission_or_start_failed";halt();return START_NOT_STICKY;}
    }
    @Override public void onLocationChanged(Location location){if(!running)return;latest=new Location(location);submit();}
    private void submit(){
        if(!running||!busy.compareAndSet(false,true))return;
        worker.execute(()->{
            PowerManager.WakeLock lock=((PowerManager)getSystemService(POWER_SERVICE)).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"YourStaff:location-send");
            try{
                lock.acquire(60000);
                JSONObject session=NativeApi.session(this);
                if(!running)return;
                if(session==null||!user.equals(SessionVault.user(session))||!wanted.equals(SessionVault.get(this,WANTED))){halt();return;}
                String token=session.getString("access_token");
                JSONObject duty=NativeApi.request("/rest/v1/rpc/dlv_my_driver_duty",token,new JSONObject());
                if(!running)return;
                if(!duty.optString("state").equals("available")&&!duty.optString("state").equals("delivering")){state="shift_inactive";halt();return;}
                Location fix=latest;
                if(fix==null||!valid(fix)){state="waiting_for_fresh_gps";return;}
                if(System.currentTimeMillis()-lastSent<5000)return;
                JSONObject body=new JSONObject().put("p_lat",fix.getLatitude()).put("p_lng",fix.getLongitude()).put("p_acc",fix.getAccuracy());
                // stop/logout changes running immediately; server independently validates session, company and role.
                if(!running||!wanted.equals(SessionVault.get(this,WANTED)))return;
                NativeApi.request("/rest/v1/rpc/dlv_update_location",token,body);
                if(running){lastSent=System.currentTimeMillis();state="running";}
            }catch(NativeApi.Denied denied){state="access_revoked";halt();}
             catch(Exception temporary){if(running)state="waiting_for_network";}
            finally{if(lock.isHeld())lock.release();busy.set(false);}
        });
    }
    static boolean valid(Location fix){
        long age=(SystemClock.elapsedRealtimeNanos()-fix.getElapsedRealtimeNanos())/1000000;
        return age>=0&&age<=20000&&fix.hasAccuracy()&&Float.isFinite(fix.getAccuracy())&&fix.getAccuracy()>=0&&fix.getAccuracy()<=150
            &&Double.isFinite(fix.getLatitude())&&Math.abs(fix.getLatitude())<=90&&Double.isFinite(fix.getLongitude())&&Math.abs(fix.getLongitude())<=180&&!fix.isFromMockProvider();
    }
    static JSONObject status() throws Exception {
        DriverLocationService s=instance;return new JSONObject().put("running",s!=null&&s.running).put("lastSent",s==null?0:s.lastSent).put("state",s==null?"stopped":s.state);
    }
    private void halt(){
        running=false;main.removeCallbacks(pulse);
        if(locations!=null)try{locations.removeUpdates(this);}catch(Exception ignored){}
        try{synchronized(SessionVault.class){if(wanted!=null&&wanted.equals(SessionVault.get(this,WANTED)))SessionVault.put(this,WANTED,null);}}catch(Exception ignored){}
        stopForeground(STOP_FOREGROUND_REMOVE);stopSelf();
    }
    @Override public void onDestroy(){halt();worker.shutdownNow();if(instance==this)instance=null;super.onDestroy();}
    @Override public IBinder onBind(Intent intent){return null;}
}
