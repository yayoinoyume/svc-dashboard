package uk.yayoi.magpiemonitor;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.view.Window;
import android.webkit.ConsoleMessage;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import org.json.JSONObject;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

/**
 * 单 Activity 的 Magpie 监控壳。
 *
 * 前端资源打包在 assets/www 下，页面 origin 固定为 https://app.local：
 * - /index.html /app.js /style.css 由本类从 assets 返回；
 * - /api/* 由本类用原生 HttpURLConnection 转发到用户配置的 magpie 地址，
 *   并附加 Cookie，从而绕开 WebView 的跨域限制。
 *
 * magpie 密钥只保存在本机 SharedPreferences，不写入代码或安装包资源。
 */
public class MainActivity extends Activity {
    private static final String LOCAL_HOST = "app.local";
    private static final String DEFAULT_BASE = "";
    private static final String DEFAULT_COOKIE = "magpie_web_3430";

    private WebView web;
    private SharedPreferences prefs;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        prefs = getSharedPreferences("magpie", MODE_PRIVATE);

        Window w = getWindow();
        w.setStatusBarColor(Color.parseColor("#0B1020"));
        w.setNavigationBarColor(Color.parseColor("#0B1020"));

        web = new WebView(this);
        web.setBackgroundColor(Color.parseColor("#0B1020"));
        setContentView(web);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setCacheMode(WebSettings.LOAD_NO_CACHE);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setSupportZoom(false);
        s.setUserAgentString(s.getUserAgentString() + " MagpieMonitor/1.0");

        web.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                return intercept(request.getUrl());
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri u = request.getUrl();
                if (LOCAL_HOST.equals(u.getHost())) {
                    return false;
                }
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, u));
                } catch (Exception ignored) {
                }
                return true;
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onConsoleMessage(ConsoleMessage m) {
                return true;
            }
        });
        web.addJavascriptInterface(new Bridge(), "Android");

        web.loadUrl("https://" + LOCAL_HOST + "/index.html");
    }

    private WebResourceResponse intercept(Uri uri) {
        if (uri == null || !LOCAL_HOST.equals(uri.getHost())) {
            return null;
        }
        String path = uri.getPath();
        if (path == null) {
            path = "/";
        }
        if (path.startsWith("/api/")) {
            String q = uri.getEncodedQuery();
            return proxy(path + (q == null ? "" : "?" + q));
        }
        switch (path) {
            case "/":
            case "/index.html":
                return asset("www/index.html", "text/html");
            case "/app.js":
                return asset("www/app.js", "application/javascript");
            case "/style.css":
                return asset("www/style.css", "text/css");
            default:
                return asset("www/404.txt", "text/plain");
        }
    }

    private WebResourceResponse asset(String name, String mime) {
        try {
            InputStream in = getAssets().open(name);
            Map<String, String> headers = new HashMap<>();
            headers.put("Cache-Control", "no-store");
            return new WebResourceResponse(mime, "utf-8", 200, "OK", headers, in);
        } catch (IOException e) {
            return null;
        }
    }

    private WebResourceResponse proxy(String pathAndQuery) {
        String base = prefs.getString("base", DEFAULT_BASE).trim();
        String key = prefs.getString("key", "").trim();
        String cookieName = prefs.getString("cookie", DEFAULT_COOKIE).trim();

        if (key.isEmpty()) {
            return json(401, "{\"error\":\"no-key\"}");
        }
        if (base.endsWith("/")) {
            base = base.substring(0, base.length() - 1);
        }

        HttpURLConnection conn = null;
        try {
            URL url = new URL(base + pathAndQuery);
            conn = (HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(10000);
            // wait=1 是 magpie 的长轮询：无新事件时服务器会挂起连接，读超时必须放宽。
            boolean longPoll = pathAndQuery.indexOf("wait=1") >= 0;
            conn.setReadTimeout(longPoll ? 65000 : 20000);
            conn.setRequestMethod("GET");
            conn.setRequestProperty("Cookie", cookieName + "=" + key);
            conn.setRequestProperty("Accept", "application/json");
            conn.setRequestProperty("User-Agent", "MagpieMonitor/1.0");

            int code = conn.getResponseCode();
            InputStream in = code >= 400 ? conn.getErrorStream() : conn.getInputStream();
            byte[] body = readAll(in);
            return json(code, new String(body, StandardCharsets.UTF_8));
        } catch (Exception e) {
            String msg = e.getClass().getSimpleName() + ": " + String.valueOf(e.getMessage());
            return json(502, "{\"error\":" + JSONObject.quote(msg) + "}");
        } finally {
            if (conn != null) {
                conn.disconnect();
            }
        }
    }

    private WebResourceResponse json(int code, String body) {
        Map<String, String> headers = new HashMap<>();
        headers.put("Cache-Control", "no-store");
        headers.put("Access-Control-Allow-Origin", "*");
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        return new WebResourceResponse("application/json", "utf-8", code,
                code >= 400 ? "Error" : "OK", headers, new ByteArrayInputStream(bytes));
    }

    private static byte[] readAll(InputStream in) throws IOException {
        if (in == null) {
            return new byte[0];
        }
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) {
            out.write(buf, 0, n);
        }
        in.close();
        return out.toByteArray();
    }

    @Override
    public void onBackPressed() {
        if (web != null && web.canGoBack()) {
            web.goBack();
        } else {
            super.onBackPressed();
        }
    }

    /** 暴露给前端的配置接口。getConfig 不回传密钥，只回传是否已保存。 */
    public class Bridge {
        @JavascriptInterface
        public String getConfig() {
            try {
                JSONObject o = new JSONObject();
                o.put("base", prefs.getString("base", DEFAULT_BASE));
                o.put("cookie", prefs.getString("cookie", DEFAULT_COOKIE));
                o.put("hasKey", !prefs.getString("key", "").isEmpty());
                return o.toString();
            } catch (Exception e) {
                return "{\"base\":\"" + DEFAULT_BASE + "\",\"cookie\":\"" + DEFAULT_COOKIE + "\",\"hasKey\":false}";
            }
        }

        @JavascriptInterface
        public void saveConfig(String base, String key, String cookie) {
            SharedPreferences.Editor e = prefs.edit();
            if (base != null && !base.trim().isEmpty()) {
                e.putString("base", base.trim());
            }
            if (cookie != null && !cookie.trim().isEmpty()) {
                e.putString("cookie", cookie.trim());
            }
            if (key != null && !key.trim().isEmpty()) {
                e.putString("key", key.trim());
            }
            e.apply();
        }

        @JavascriptInterface
        public void clearKey() {
            prefs.edit().remove("key").apply();
        }

        @JavascriptInterface
        public void openExternal(String url) {
            try {
                startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
            } catch (Exception ignored) {
            }
        }
    }
}
