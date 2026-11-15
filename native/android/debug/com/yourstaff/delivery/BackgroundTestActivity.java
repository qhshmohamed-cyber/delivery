package com.yourstaff.delivery;
/** Debug-only foreground activity: isolates lifecycle tests from real accounts and APIs. */
public class BackgroundTestActivity extends android.app.Activity {
    @Override public void onCreate(android.os.Bundle state){super.onCreate(state);android.widget.TextView view=new android.widget.TextView(this);view.setText("Your Staff background service test");setContentView(view);}
}
