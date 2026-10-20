package org.trickynerdy.forgehub;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.WindowInsets;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebResourceRequest;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.URI;
import java.net.URL;
import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.X509EncodedKeySpec;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Forge Hub preview. Plain Android SDK; no account server, tracker, or privileged installer. */
public final class MainActivity extends Activity {
    private static final int BG=0xff111610, PANEL=0xff1c231b, BORDER=0xff354030,
        FG=0xfff2f5e9, MUTED=0xffb0ba9e, LIME=0xffd6ef83, AMBER=0xffe8b970;
    private static final String RADIO_PACKAGE="org.lumaradio.commandcenter";
    private static final String RADIO_URL="https://github.com/Tricky-Nerdy/LumaRadio/releases/download/command-center-preview/LumaRadio-0.2.0-command-center.apk";
    private static final String RADIO_HASH="92315e10ff112787506efa247c2d5607bfcdbbe9bd6e3303c571f92c1e085ded";
    private static final String UPDATE_BASE="https://github.com/Tricky-Nerdy/LumaRadio/releases/download/command-center-preview/";
    private static final String UPDATE_KEY="MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAxaV5Q5E1Udll6J+aoFGBIeSPicfTA9dxXrPygIYHB6wNxVDUynlF2WSJUOB1To4jStUOHFYmVUHFddubvYoAdp+Y9zh8u9mNEyXXTp7uS7X4t9DbRib+hQpiA731xjLpvpWHeoJpKr/l2ZS8Z74B5MlqWR2ZXCnUBHCz2HHywtCITHtsOONF+I4qcaMkSDVyYUeJXKh+6YYzQsL7F2bEICJs5EqmbVqXnXlI2pGkrqxpwSd4Snc4uFIfbLAc72aX3ePqXj49Ujkrc3A39fUgAiWQMelT6GLqHr3tK1/msm07o1/hyMblGQkejQFAkfI2JYH15UQQCDyTX4qQGfzXTcNrRnyAW158zK2bA/FPQQpPyFlPeNWecsGmMyX2w52aIUSXvJBv2Bsc4xczB+8nOZV0A5ixcHahuX+iWqEWvI/VttetAuQVyFD7OwPvVx5kwS8BSBz2Bh3uGf2IW7bFdQrPVjHxhIX96llWii88SV4tg2o3p4Jjus+bhDKzP4qFAgMBAAE=";
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private SharedPreferences prefs;
    private LinearLayout shell, body, tabs;
    private TextView status;
    private String page="Hub", notice="Ready for your next build.";
    private volatile boolean downloading=false;
    private JSONObject desktop;
    private File pendingInstall;
    private WebView stationView;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state); prefs=getSharedPreferences("forge-private", MODE_PRIVATE);
        getWindow().setStatusBarColor(BG); getWindow().setNavigationBarColor(BG);
        render();
    }
    private int dp(float n) { return Math.round(n*getResources().getDisplayMetrics().density); }
    private GradientDrawable box(int fill, int stroke, int radius) {
        GradientDrawable d=new GradientDrawable(); d.setColor(fill); d.setCornerRadius(dp(radius));
        if(stroke!=0)d.setStroke(dp(1),stroke); return d;
    }
    private LinearLayout column() { LinearLayout l=new LinearLayout(this); l.setOrientation(LinearLayout.VERTICAL); return l; }
    private TextView text(String s, int size, int color, boolean bold) {
        TextView v=new TextView(this); v.setText(s); v.setTextSize(size); v.setTextColor(color);
        v.setLineSpacing(dp(3),1f); if(bold)v.setTypeface(Typeface.DEFAULT,Typeface.BOLD); return v;
    }
    private void gap(LinearLayout l,int h) { View v=new View(this); l.addView(v,new LinearLayout.LayoutParams(1,dp(h))); }
    private void label(LinearLayout l,String s) { TextView v=text(s,11,MUTED,true); v.setLetterSpacing(.13f); l.addView(v); gap(l,10); }
    private LinearLayout card(String eyebrow, String title, String detail) {
        LinearLayout c=column(); c.setPadding(dp(18),dp(18),dp(18),dp(18)); c.setBackground(box(PANEL,BORDER,18));
        LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2); p.bottomMargin=dp(12); body.addView(c,p);
        if(!eyebrow.isEmpty()) { TextView e=text(eyebrow,10,LIME,true); e.setLetterSpacing(.1f); c.addView(e); gap(c,9); }
        c.addView(text(title,22,FG,true)); gap(c,8); c.addView(text(detail,14,MUTED,false)); gap(c,10); return c;
    }
    private Button button(String title, boolean primary, Runnable action) {
        Button b=new Button(this); b.setAllCaps(false); b.setText(title); b.setTextSize(14);
        b.setTypeface(Typeface.DEFAULT,Typeface.BOLD); b.setTextColor(primary?BG:FG);
        b.setBackground(box(primary?LIME:0xff2a3326,primary?0:BORDER,12));
        b.setPadding(dp(14),dp(7),dp(14),dp(7)); b.setMinHeight(dp(46));
        LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2); p.topMargin=dp(7); b.setLayoutParams(p);
        b.setOnClickListener(v->action.run()); return b;
    }
    private void render() {
        if(stationView!=null){stationView.destroy();stationView=null;}
        shell=column(); shell.setBackgroundColor(BG); shell.setPadding(dp(20),dp(12),dp(20),dp(12));
        shell.setOnApplyWindowInsetsListener((v,insets)->{
            int top=insets.getSystemWindowInsetTop(),bottom=insets.getSystemWindowInsetBottom();
            shell.setPadding(dp(20),dp(12)+top,dp(20),dp(12)+bottom); return insets;
        }); setContentView(shell);
        LinearLayout header=new LinearLayout(this); header.setGravity(Gravity.CENTER_VERTICAL);
        TextView emblem=text("F",25,BG,true); emblem.setGravity(Gravity.CENTER); emblem.setBackground(box(LIME,0,12));
        header.addView(emblem,new LinearLayout.LayoutParams(dp(43),dp(43)));
        LinearLayout brand=column(); brand.setPadding(dp(12),0,0,0);
        brand.addView(text("FORGE HUB",18,FG,true)); TextView sub=text("LUMA SYSTEMS  /  SOLAR 0.3",10,MUTED,true); sub.setLetterSpacing(.1f); brand.addView(sub);
        header.addView(brand,new LinearLayout.LayoutParams(0,-2,1));
        TextView user=text(prefs.getString("callsign","LOCAL"),11,LIME,true); user.setOnClickListener(v->profile()); header.addView(user);
        shell.addView(header); gap(shell,20);
        tabs=new LinearLayout(this);
        for(String name:new String[]{"Hub","Broadcast","Solar","Updates","Pair"}) {
            TextView t=text(name,13,page.equals(name)?BG:MUTED,true); t.setGravity(Gravity.CENTER);
            t.setPadding(0,dp(11),0,dp(11)); t.setBackground(box(page.equals(name)?LIME:BG,0,10));
            LinearLayout.LayoutParams tp=new LinearLayout.LayoutParams(0,dp(42),1); tp.setMargins(dp(2),0,dp(2),0); tabs.addView(t,tp);
            t.setOnClickListener(v->{page=name;render();});
        }
        shell.addView(tabs); gap(shell,16);
        if(page.equals("Solar")){
            showSolarStation();
            status=text(notice,11,MUTED,false);status.setPadding(0,dp(8),0,0);status.setMaxLines(3);shell.addView(status);
            return;
        }
        ScrollView scroll=new ScrollView(this); scroll.setFillViewport(false); scroll.setClipToPadding(false);
        body=column(); body.setPadding(0,0,0,dp(16)); scroll.addView(body); shell.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        if(page.equals("Hub")) hub(); else if(page.equals("Broadcast")) radio(); else if(page.equals("Updates")) updates(); else pairing();
        status=text(notice,11,MUTED,false); status.setPadding(0,dp(8),0,0); status.setMaxLines(3); shell.addView(status);
    }
    private void hub() {
        label(body,"YOUR WORKSHOP, CONNECTED");
        body.addView(text("Build something\nworth tuning into.",31,FG,true)); gap(body,10);
        body.addView(text("One hub for your radio, local AI, and desktop tools.",15,MUTED,false)); gap(body,22);
        LinearLayout hero=card("FORGE SOLAR  ·  PREVIEW 0.3","Solar Station","Plan a focused show, choose a world, and preview silent data signals. Planning and map selection work offline.");
        hero.addView(button("Open Solar Station",true,this::openBroadcast));
        hero.addView(button("Open 3D / VR map on this device",false,this::openSolarMap));
        hero.addView(button("Open Luma Radio  ↗",false,this::openRadio));
        hero.addView(button("Install verified Radio preview",false,this::installRadio));
        label(body,"DESKTOP TELEMETRY");
        if(desktop==null) {
            LinearLayout c=card("AWAITING PAIRING","Your desktop cockpit","Pair your desktop for real CPU, memory, GPU, and network readings. Values appear only after a successful connection.");
            c.addView(button("Pair a desktop",false,()->{page="Pair";render();}));
        } else showMetrics();
        label(body,"CHOOSE YOUR TOOLS");
        module("Luma Discord","Desktop service","Install and configure the Discord voice bot on Linux. Bot credentials stay on your desktop.");
        module("LM Studio / LMS","Desktop runtime","Use the Linux hub to open LM Studio and discover LMS. Local models run on supported desktop hardware.");
        module("Vox","Voice tools","Desktop voice tools are listed when detected. Android voice integration is a later module.");
        if(!prefs.contains("name")) body.addView(button("Create your local profile",false,this::profile));
    }
    private void module(String name,String platform,String detail) {
        LinearLayout c=card(platform.toUpperCase(Locale.US),name,detail);
        c.addView(button("View desktop setup",false,()->{page="Pair";render();}));
    }
    private void showMetrics() {
        JSONObject r=desktop.optJSONObject("resources"); if(r==null)r=new JSONObject();
        LinearLayout c=card("CONNECTED  ·  "+desktop.optString("host","DESKTOP"),"Real work. Real readings.","Sampled when you press Refresh. Resource use follows useful work; Forge does not burn cycles to meet a percentage.");
        metric(c,"CPU",r,"cpu_percent"); metric(c,"MEMORY",r,"ram_percent"); metric(c,"GPU",r,"gpu_percent");
        JSONArray net=r.optJSONArray("network");
        if(net!=null) for(int i=0;i<net.length();i++) {
            JSONObject n=net.optJSONObject(i); if(n==null)continue;
            c.addView(text(n.optString("interface","Network")+"  ↓ "+rate(n,"rx_bps")+"  ↑ "+rate(n,"tx_bps"),12,MUTED,false));
        }
        c.addView(button("Refresh desktop",false,this::refreshDesktop));
    }
    private String rate(JSONObject n,String k) { return n.isNull(k)||!n.has(k)?"unavailable":String.format(Locale.US,"%.1f KB/s",n.optDouble(k)/1024); }
    private void metric(LinearLayout c,String name,JSONObject r,String key) {
        boolean known=r.has(key)&&!r.isNull(key); double value=known?r.optDouble(key):0;
        c.addView(text(name+"   "+(known?String.format(Locale.US,"%.1f%%",value):"UNAVAILABLE"),12,known?FG:MUTED,true));
        ProgressBar bar=new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal); bar.setMax(100); bar.setProgress((int)Math.max(0,Math.min(100,value)));
        bar.setProgressTintList(android.content.res.ColorStateList.valueOf(LIME)); bar.setProgressBackgroundTintList(android.content.res.ColorStateList.valueOf(BORDER));
        c.addView(bar,new LinearLayout.LayoutParams(-1,dp(9))); gap(c,12);
    }
    private void radio() {
        label(body,"LUMA RADIO  /  BROADCAST");
        LinearLayout c=card("SOLAR STATION","The program starts here.","Create connected text briefs and silent data signals. The legacy soundboard remains a separate app; this station produces no voice or tones.");
        c.addView(button("Open Broadcast Studio",true,this::openBroadcast));
        c.addView(button("Open Button Radio (legacy Godot)",false,this::openRadio)); c.addView(button("Install Button Radio preview",false,this::installRadio));
        LinearLayout rundown=card("PROMPTED FORMATS","Choose a connected show.","Each format has its own running order and editable target duration.");
        segment(rundown,"5 min","Mars News","Lead report, map context, and the next development.");
        segment(rundown,"6 min","Star News","One astronomy story, its science, limits, and takeaway.");
        segment(rundown,"60 min","Talk Hour","One question, perspectives, a fair challenge, and synthesis.");
        segment(rundown,"20 min","Interviews","Guest purpose, experience, follow-ups, and closing.");
        rundown.addView(text("Target times plan the show; they do not measure a rendered performance. AI drafting needs a paired model host.",12,AMBER,false));
        LinearLayout next=card("CONTROL ROOM","Keep the channel honest.","Creative direction sets the focus. Fiction stays labeled, and source-based stories need notes. Drafts are text; no audio is generated.");
        next.addView(button("View Radio repository",false,()->openWeb("https://github.com/Tricky-Nerdy/LumaRadio")));
    }
    private void segment(LinearLayout c,String time,String title,String detail) {
        LinearLayout row=new LinearLayout(this); row.setPadding(0,dp(8),0,dp(8));
        TextView at=text(time,12,LIME,true); row.addView(at,new LinearLayout.LayoutParams(dp(65),-2));
        LinearLayout copy=column(); copy.addView(text(title,15,FG,true)); copy.addView(text(detail,12,MUTED,false)); row.addView(copy,new LinearLayout.LayoutParams(0,-2,1)); c.addView(row);
    }
    private void updates() {
        label(body,"VERIFIED PACKAGES");
        LinearLayout c=card("ANDROID PACKAGE MANAGER","Your phone. Your approval.","No root. No silent installs. Forge checks a package before handing it to Android, and Android asks you to approve the installation.");
        c.addView(button("Check Radio Command Center update",true,this::installRadio));
        c.addView(text("Radio Command Center 0.2.0\nSHA-256: "+RADIO_HASH,11,MUTED,false));
        boolean solarPreview=getPackageName().equals("org.trickynerdy.forgehub.solarpreview");
        LinearLayout f=card(solarPreview?"SOLAR STATION  ·  0.3.0-PREVIEW":"FORGE HUB  ·  0.1.2-PREVIEW",solarPreview?"Separate preview package":"Signed update feed",solarPreview?"This build installs alongside your existing Forge app. It uses a development signer and does not replace the original app or its trusted update feed.":prefs.contains("feed_url")?"A trusted feed is configured. Updates require a valid signed manifest, APK hash, matching app identity, and the installed signing certificate.":"The built-in Command Center preview feed is verified with its publisher key. Your custom trusted feed, if configured, takes priority for Forge updates.");
        if(solarPreview)f.addView(button("View preview builds",false,()->openWeb("https://github.com/Tricky-Nerdy/LumaRadio/pull/1")));
        else {f.addView(button("Check Forge update",false,this::checkForgeUpdate));f.addView(button("Configure trusted feed",false,this::configureFeed));}
        LinearLayout p=card("PRIVATE BY DEFAULT","Local profile only","Your display name, pairing token, and preferences are stored in this app's private storage. No cloud signup or account synchronization is active.");
        p.addView(button("Edit local profile",false,this::profile));
        p.addView(button("Forget desktop pairing",false,()->{prefs.edit().remove("desktop_url").remove("desktop_token").apply();desktop=null;say("Desktop pairing removed.");render();}));
    }
    private void pairing() {
        label(body,"PHONE + DESKTOP");
        LinearLayout c=card("PAIR OVER YOUR LAN","Connect an optional host.","Open Forge Hub on the desktop, enable LAN access, and generate a pairing token there. Both devices must be on the same reachable network.");
        c.addView(button(prefs.contains("desktop_url")?"Edit desktop pairing":"Enter desktop pairing",true,this::pairDialog));
        c.addView(button("Connect / refresh readings",false,this::refreshDesktop));
        if(prefs.contains("desktop_url"))c.addView(text("Desktop: "+prefs.getString("desktop_url",""),12,LIME,false));
        if(desktop!=null)showMetrics();
        card("LINUX WORKSHOP","Install what you need.","The Linux Forge installer offers Luma Radio, the Discord bot, LM Studio / LMS discovery, and Vox discovery. The Android hub does not run desktop executables or expose a remote shell.");
        card("LOCAL NETWORK","Trusted LAN pairing","An HTTP LAN connection sends the token unencrypted. Use only your trusted private network. Use an HTTPS endpoint when available. Pairing grants read-only status access.");
    }
    private EditText input(String hint,String value,boolean secret) {
        EditText e=new EditText(this); e.setHint(hint); e.setText(value); e.setTextColor(FG); e.setHintTextColor(MUTED); e.setTextSize(14);
        e.setSingleLine(true); e.setPadding(dp(10),dp(10),dp(10),dp(10));
        e.setInputType(secret?InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_VARIATION_PASSWORD:InputType.TYPE_CLASS_TEXT);
        return e;
    }
    private LinearLayout form() { LinearLayout f=column(); f.setPadding(dp(20),dp(8),dp(20),dp(8)); return f; }
    private void profile() {
        LinearLayout f=form(); f.addView(text("A profile on this device. No cloud account is created.",14,MUTED,false));
        EditText name=input("Display name",prefs.getString("name",""),false),call=input("Call sign",prefs.getString("callsign",""),false); f.addView(name); f.addView(call);
        AlertDialog d=new AlertDialog.Builder(this).setTitle("Join your local workshop").setView(f).setNegativeButton("Cancel",null).setPositiveButton("Save profile",null).create();
        d.setOnShowListener(v->d.getButton(-1).setOnClickListener(w->{
            String n=name.getText().toString().trim(),s=call.getText().toString().trim();
            if(n.isEmpty()||n.length()>60||s.length()>24){name.setError("Use a name of 1–60 characters and a call sign up to 24.");return;}
            prefs.edit().putString("name",n).putString("callsign",s.isEmpty()?n:s).apply();d.dismiss();say("Local profile saved.");render();
        }));d.show();
    }
    private void pairDialog() {
        LinearLayout f=form(); f.addView(text("Use the address and token shown by your desktop Forge Hub.",14,MUTED,false));
        EditText url=input("http://192.168.1.10:8787",prefs.getString("desktop_url",""),false),token=input("Pairing token",prefs.getString("desktop_token",""),true);f.addView(url);f.addView(token);
        AlertDialog d=new AlertDialog.Builder(this).setTitle("Pair desktop").setView(f).setNegativeButton("Cancel",null).setPositiveButton("Save and connect",null).create();
        d.setOnShowListener(v->d.getButton(-1).setOnClickListener(w->{
            String u=url.getText().toString().trim().replaceAll("/+$",""),t=token.getText().toString().trim();
            try { URI uri=new URI(u); if(uri.getHost()==null||uri.getUserInfo()!=null||uri.getQuery()!=null||uri.getFragment()!=null||!("http".equals(uri.getScheme())||"https".equals(uri.getScheme()))||!(uri.getPath()==null||uri.getPath().isEmpty()))throw new Exception();
                if(t.isEmpty()||t.length()>256)throw new Exception();
            }catch(Exception e){url.setError("Enter a base HTTP(S) address and the desktop token.");return;}
            prefs.edit().putString("desktop_url",u).putString("desktop_token",t).apply();d.dismiss();refreshDesktop();
        }));d.show();
    }
    private void refreshDesktop() {
        String base=prefs.getString("desktop_url",""),token=prefs.getString("desktop_token","");
        if(base.isEmpty()){pairDialog();return;}say("Connecting to paired desktop…");
        worker.execute(()->{try {
            URL url=new URL(base+"/api/status");
            if("http".equals(url.getProtocol())){
                for(InetAddress a:InetAddress.getAllByName(url.getHost()))if(!a.isSiteLocalAddress()&&!a.isLoopbackAddress())throw new Exception("HTTP pairing is restricted to private LAN addresses; use HTTPS for remote endpoints.");
            }
            HttpURLConnection c=(HttpURLConnection)url.openConnection();c.setConnectTimeout(8000);c.setReadTimeout(8000);c.setInstanceFollowRedirects(false);c.setRequestProperty("X-Forge-Token",token);
            JSONObject result;try{if(c.getResponseCode()!=200)throw new Exception("Desktop rejected the request (HTTP "+c.getResponseCode()+"). Check LAN access and token.");result=new JSONObject(new String(readLimited(c.getInputStream(),1024*1024),"UTF-8"));}finally{c.disconnect();}
            if(!result.optBoolean("ok"))throw new Exception("Desktop did not return a valid status.");
            runOnUiThread(()->{desktop=result;say("Desktop connected. Readings are from this refresh.");render();});
        }catch(Exception e){fail("Desktop unavailable",e);}});
    }
    private void openBroadcast() {
        page="Solar";render();
    }
    private void openSolarMap() {
        Intent launch=getPackageManager().getLaunchIntentForPackage("org.trickynerdy.lumasolar.preview");
        if(launch==null){say("Install the Luma Forge Solar Map preview on this device to open it here.");return;}
        startActivity(launch);
    }
    private void showSolarStation() {
        stationView=new WebView(this);
        stationView.setBackgroundColor(BG);
        stationView.getSettings().setJavaScriptEnabled(true);
        stationView.getSettings().setDomStorageEnabled(true);
        stationView.getSettings().setAllowFileAccess(false);
        stationView.getSettings().setAllowContentAccess(false);
        stationView.getSettings().setJavaScriptCanOpenWindowsAutomatically(false);
        stationView.getSettings().setMediaPlaybackRequiresUserGesture(true);
        stationView.setWebViewClient(new WebViewClient(){
            @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){return true;}
            @Override public boolean shouldOverrideUrlLoading(WebView view,String url){return true;}
        });
        shell.addView(stationView,new LinearLayout.LayoutParams(-1,0,1));
        try(InputStream input=getAssets().open("station.html")){
            stationView.loadDataWithBaseURL("https://forge.invalid/",new String(readLimited(input,1024*1024),"UTF-8"),"text/html","UTF-8",null);
            notice="Solar Station ready offline. No audio or desktop connection is required.";
        }catch(Exception e){say("Station asset could not be opened.");}
    }
    private void openPairedBroadcast() {
        String url=prefs.getString("desktop_url","");
        if(url.isEmpty()){say("No optional Broadcast host is paired. Solar Station works offline.");return;}
        openWeb(url.endsWith("/")?url:url+"/");
    }
    private void openRadio() {
        Intent launch=getPackageManager().getLaunchIntentForPackage(RADIO_PACKAGE);
        if(launch==null){new AlertDialog.Builder(this).setTitle("Radio is not installed").setMessage("Install the verified LumaRadio preview from the Updates tab?").setNegativeButton("Cancel",null).setPositiveButton("Install preview",(d,w)->installRadio()).show();return;}
        startActivity(launch);
    }
    private void installRadio() {
        say("Checking signed Radio update feed…");
        worker.execute(()->{try {
            JSONObject release=signedRelease(UPDATE_BASE+"radio-update.json",UPDATE_KEY);
            if(!RADIO_PACKAGE.equals(release.getString("packageName")))throw new Exception("Radio manifest is for a different application.");
            long installed=0;
            try {installed=versionCode(getPackageManager().getPackageInfo(RADIO_PACKAGE,0));}
            catch(PackageManager.NameNotFoundException firstInstall) { /* Separate preview preserves the old soundboard. */ }
            if(release.getLong("versionCode")<=installed){runOnUiThread(()->say("Radio Command Center is up to date."));return;}
            String url=release.getString("url"),hash=release.getString("sha256");validateHttps(url);validateHash(hash);
            final boolean firstInstall=installed==0;
            runOnUiThread(()->new AlertDialog.Builder(this).setTitle(firstInstall?"Install Radio Command Center?":"Update Radio Command Center?")
                .setMessage("Version "+release.optString("versionName","new release")+". "+(firstInstall?"This separate preview keeps the old Radio app installed. ":"")+"The preview plays tones and sends desktop controls; microphone audio is not connected. Android will ask you to approve installation.")
                .setNegativeButton("Later",null).setPositiveButton("Download",(d,w)->downloadApk(url,hash,RADIO_PACKAGE,false)).show());
        }catch(Exception e){fail("Radio update check failed",e);}});
    }
    private JSONObject signedRelease(String address,String key) throws Exception {
        JSONObject envelope=new JSONObject(new String(getHttps(address,1024*1024),"UTF-8"));
        byte[] payload=android.util.Base64.decode(envelope.getString("payload"),android.util.Base64.DEFAULT);
        byte[] signature=android.util.Base64.decode(envelope.getString("signature"),android.util.Base64.DEFAULT);
        Signature verifier=Signature.getInstance("SHA256withRSA");verifier.initVerify(parsePublicKey(key));verifier.update(payload);
        if(!verifier.verify(signature))throw new Exception("Release manifest signature did not match the publisher key.");
        return new JSONObject(new String(payload,"UTF-8"));
    }
    private void configureFeed() {
        LinearLayout f=form();f.addView(text("Trust only your release publisher. The RSA public key verifies the feed before any download. Never paste a private key.",14,MUTED,false));
        EditText url=input("HTTPS signed-manifest URL",prefs.getString("feed_url",""),false),key=input("RSA public key (base64 SPKI)",prefs.getString("feed_key",""),false);key.setSingleLine(false);key.setMaxLines(4);f.addView(url);f.addView(key);
        AlertDialog d=new AlertDialog.Builder(this).setTitle("Trust a release feed").setView(f).setNegativeButton("Cancel",null).setPositiveButton("Save trusted feed",null).create();
        d.setOnShowListener(v->d.getButton(-1).setOnClickListener(w->{try{
            String u=url.getText().toString().trim(),k=key.getText().toString().trim();validateHttps(u);parsePublicKey(k);
            prefs.edit().putString("feed_url",u).putString("feed_key",k).apply();d.dismiss();say("Trusted signed feed saved.");render();
        }catch(Exception e){url.setError("Use an HTTPS URL and valid RSA public key.");}}));d.show();
    }
    private PublicKey parsePublicKey(String text) throws Exception {
        String base=text.replace("-----BEGIN PUBLIC KEY-----","").replace("-----END PUBLIC KEY-----","").replaceAll("\\s","");
        PublicKey key=KeyFactory.getInstance("RSA").generatePublic(new X509EncodedKeySpec(android.util.Base64.decode(base,android.util.Base64.DEFAULT)));
        if(((java.security.interfaces.RSAPublicKey)key).getModulus().bitLength()<2048)throw new Exception("RSA key must be at least 2048 bits.");return key;
    }
    private void checkForgeUpdate() {
        say("Checking signed Forge release feed…");worker.execute(()->{try{
            JSONObject release=signedRelease(prefs.getString("feed_url",UPDATE_BASE+"forge-update.json"),prefs.getString("feed_key",UPDATE_KEY));
            if(!getPackageName().equals(release.getString("packageName")))throw new Exception("Release manifest is for a different application.");
            if(release.getLong("versionCode")<=versionCode(getPackageManager().getPackageInfo(getPackageName(),0))){runOnUiThread(()->say("Forge Hub is up to date for this trusted feed."));return;}
            String url=release.getString("url"),hash=release.getString("sha256");validateHttps(url);validateHash(hash);
            runOnUiThread(()->new AlertDialog.Builder(this).setTitle("Verified Forge update").setMessage("Version "+release.optString("versionName","new release")+" is available. Download and ask Android to install it?")
                .setNegativeButton("Later",null).setPositiveButton("Download",(d,w)->downloadApk(url,hash,getPackageName(),true)).show());
        }catch(Exception e){fail("Update check failed",e);}});
    }
    private void downloadApk(String url,String expected,String expectedPackage,boolean self) {
        if(downloading){say("A package download is already running.");return;}downloading=true;say("Downloading verified package…");
        worker.execute(()->{File apk=null;try {
            validateHash(expected);validateHttps(url);File dir=new File(getCacheDir(),"verified-apks");if(!dir.isDirectory()&&!dir.mkdirs())throw new Exception("Could not create private package cache.");
            apk=new File(dir,self?"forge.apk":"radio.apk");File partial=new File(dir,apk.getName()+".part");
            HttpURLConnection c=openHttps(url);MessageDigest digest=MessageDigest.getInstance("SHA-256");long size=0,last=0;
            try(InputStream in=c.getInputStream();FileOutputStream out=new FileOutputStream(partial)){
                byte[] buf=new byte[65536];int n;while((n=in.read(buf))!=-1){size+=n;if(size>256L*1024*1024)throw new Exception("APK exceeded the 256 MB package limit.");out.write(buf,0,n);digest.update(buf,0,n);
                    if(size-last>1024*1024){last=size;final long current=size;runOnUiThread(()->say(String.format(Locale.US,"Downloading… %.1f MB",current/1048576.0)));}}
                out.getFD().sync();
            }finally{c.disconnect();}
            if(!hex(digest.digest()).equalsIgnoreCase(expected)){partial.delete();throw new Exception("APK checksum mismatch. Installation blocked.");}
            if(apk.exists()&&!apk.delete())throw new Exception("Could not replace cached package.");if(!partial.renameTo(apk))throw new Exception("Could not finalize verified download.");
            PackageInfo info=getPackageManager().getPackageArchiveInfo(apk.getAbsolutePath(),Build.VERSION.SDK_INT>=28?PackageManager.GET_SIGNING_CERTIFICATES:PackageManager.GET_SIGNATURES);
            if(info==null||!expectedPackage.equals(info.packageName)){apk.delete();throw new Exception("APK application identity did not match. Installation blocked.");}
            if(self){PackageInfo installed=getPackageManager().getPackageInfo(getPackageName(),Build.VERSION.SDK_INT>=28?PackageManager.GET_SIGNING_CERTIFICATES:PackageManager.GET_SIGNATURES);
                if(versionCode(info)<=versionCode(installed)||!sameSigner(info,installed)){apk.delete();throw new Exception("Update version or signing certificate did not match. Installation blocked.");}}
            if(!self){
                try {
                    PackageInfo installed=getPackageManager().getPackageInfo(expectedPackage,Build.VERSION.SDK_INT>=28?PackageManager.GET_SIGNING_CERTIFICATES:PackageManager.GET_SIGNATURES);
                    if(versionCode(info)<=versionCode(installed)||!sameSigner(info,installed)){apk.delete();throw new Exception("Radio update version or signing certificate did not match. Installation blocked.");}
                } catch(PackageManager.NameNotFoundException firstInstall) { /* No existing Command Center to replace. */ }
            }
            File verified=apk;runOnUiThread(()->{pendingInstall=verified;say("Hash and application identity verified. Android approval is next.");requestInstall();});
        }catch(Exception e){fail("Package download failed",e);}finally{downloading=false;}});
    }
    private static long versionCode(PackageInfo info) { return Build.VERSION.SDK_INT>=28?info.getLongVersionCode():info.versionCode; }
    @SuppressWarnings("deprecation") private boolean sameSigner(PackageInfo a,PackageInfo b) throws Exception {
        android.content.pm.Signature[] x=Build.VERSION.SDK_INT>=28?a.signingInfo.getApkContentsSigners():a.signatures,y=Build.VERSION.SDK_INT>=28?b.signingInfo.getApkContentsSigners():b.signatures;
        if(x==null||y==null||x.length!=y.length)return false;java.util.Set<String> sx=new java.util.HashSet<>(),sy=new java.util.HashSet<>();
        for(android.content.pm.Signature s:x)sx.add(hex(MessageDigest.getInstance("SHA-256").digest(s.toByteArray())));for(android.content.pm.Signature s:y)sy.add(hex(MessageDigest.getInstance("SHA-256").digest(s.toByteArray())));return sx.equals(sy);
    }
    private void requestInstall() {
        if(pendingInstall==null||!pendingInstall.isFile()){say("Verified download is no longer available. Download again.");return;}
        if(!getPackageManager().canRequestPackageInstalls()){
            new AlertDialog.Builder(this).setTitle("Allow Forge to request installation").setMessage("Android requires you to allow installs from Forge Hub. You will still approve the individual APK installation.")
                .setNegativeButton("Cancel",(d,w)->say("Install permission not granted. Package remains cached."))
                .setPositiveButton("Open Android settings",(d,w)->{Intent i=new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,Uri.parse("package:"+getPackageName()));startActivityForResult(i,50);}).show();return;
        }
        Uri uri=Uri.parse("content://"+getPackageName()+".apks/"+pendingInstall.getName());Intent intent=new Intent(Intent.ACTION_VIEW).setDataAndType(uri,"application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        intent.setClipData(ClipData.newRawUri("Verified APK",uri));
        try{startActivity(intent);say("Installer opened. Android will ask you to confirm.");}catch(Exception e){say("No Android package installer could open the verified APK.");}
    }
    @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(request==50){if(getPackageManager().canRequestPackageInstalls())requestInstall();else say("Android install permission was not granted.");}}
    private static void validateHash(String h)throws Exception{if(!h.matches("[0-9a-fA-F]{64}"))throw new Exception("Missing or invalid SHA-256 pin.");}
    private static void validateHttps(String s)throws Exception{URI u=new URI(s);if(!"https".equals(u.getScheme())||u.getHost()==null||u.getUserInfo()!=null)throw new Exception("Package and feed URLs must use HTTPS.");}
    private HttpURLConnection openHttps(String address)throws Exception {
        for(int redirects=0;redirects<6;redirects++){
            validateHttps(address);HttpURLConnection c=(HttpURLConnection)new URL(address).openConnection();c.setConnectTimeout(15000);c.setReadTimeout(30000);c.setInstanceFollowRedirects(false);c.setRequestProperty("User-Agent","ForgeHub/0.1 Android");
            int code=c.getResponseCode();if(code>=300&&code<400){String next=c.getHeaderField("Location");URL resolved=new URL(new URL(address),next==null?"":next);c.disconnect();address=resolved.toString();continue;}
            if(code!=200){c.disconnect();throw new Exception("Download server returned HTTP "+code+".");}return c;
        }throw new Exception("Too many HTTPS redirects.");
    }
    private byte[] getHttps(String url,int max)throws Exception{HttpURLConnection c=openHttps(url);try{return readLimited(c.getInputStream(),max);}finally{c.disconnect();}}
    private static byte[] readLimited(InputStream source,int max)throws Exception{try(InputStream in=source;ByteArrayOutputStream out=new ByteArrayOutputStream()){byte[] b=new byte[8192];int n,total=0;while((n=in.read(b))!=-1){total+=n;if(total>max)throw new Exception("Response was too large.");out.write(b,0,n);}return out.toByteArray();}}
    private static String hex(byte[] b){StringBuilder s=new StringBuilder();for(byte n:b)s.append(String.format(Locale.US,"%02x",n&255));return s.toString();}
    private void openWeb(String url){try{startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(url)));}catch(Exception e){say("No browser is available.");}}
    private void say(String s){notice=s;if(status!=null)status.setText(s);}
    private void fail(String title,Exception e){runOnUiThread(()->{String m=e.getMessage();say(title+". "+(m==null?"Please try again.":m));});}
    @Override protected void onPause(){if(stationView!=null){stationView.evaluateJavascript("window.ForgeStudio && window.ForgeStudio.disconnect()",null);stationView.onPause();}super.onPause();}
    @Override protected void onResume(){super.onResume();if(stationView!=null)stationView.onResume();}
    @Override protected void onDestroy(){if(stationView!=null){stationView.destroy();stationView=null;}super.onDestroy();worker.shutdown();}
}
