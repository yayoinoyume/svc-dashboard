(function () {
  "use strict";

  var REFRESH_MS = 20000;
  var TRACE_MS = 15000;
  var PROVIDERS_MS = 10 * 60 * 1000;
  var DEFAULT_BASE = "https://magpie.example.invalid";
  var DEFAULT_COOKIE = "magpie_web_3430";

  var state = {
    period: "today",
    usage: null,
    quotas: null,
    trace: null,
    traceAt: 0,
    providers: null,
    providersAt: 0,
    loading: false,
    reqToken: 0,
    timer: null,
    lastOK: 0
  };

  var bridge = window.Android || null;

  function $(id) {
    return document.getElementById(id);
  }

  function pad2(n) {
    return n < 10 ? "0" + n : String(n);
  }

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function fmtInt(n) {
    n = Number(n) || 0;
    return n.toLocaleString("zh-CN");
  }

  function fmtCompact(n) {
    n = Number(n) || 0;
    if (n >= 1e9) return (n / 1e9).toFixed(1) + "B";
    if (n >= 1e6) return (n / 1e6).toFixed(1) + "M";
    if (n >= 1e3) return (n / 1e3).toFixed(1) + "K";
    return String(Math.round(n));
  }

  function fmtCost(n) {
    n = Number(n) || 0;
    if (n > 0 && n < 0.01) return "$" + n.toFixed(4);
    return "$" + n.toFixed(2);
  }

  function fmtClock(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime())) return "";
    return pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds());
  }

  function fmtReset(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime())) return "";
    return pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()) + " " +
      pad2(d.getHours()) + ":" + pad2(d.getMinutes());
  }

  /* ---------- 配置 ---------- */

  function readConfig() {
    if (bridge && bridge.getConfig) {
      try {
        return JSON.parse(bridge.getConfig());
      } catch (e) {
        /* 落到下面的默认值 */
      }
    }
    var saved = null;
    try {
      saved = JSON.parse(localStorage.getItem("magpieCfg") || "null");
    } catch (e) {
      saved = null;
    }
    if (saved && saved.base) {
      saved.hasKey = !!saved.key;
      return saved;
    }
    return { base: DEFAULT_BASE, cookie: DEFAULT_COOKIE, hasKey: false };
  }

  function saveConfig(base, key, cookie) {
    if (bridge && bridge.saveConfig) {
      bridge.saveConfig(base, key, cookie);
      return;
    }
    var cur = readConfig();
    var next = {
      base: base || cur.base,
      cookie: cookie || cur.cookie,
      key: key || cur.key || ""
    };
    localStorage.setItem("magpieCfg", JSON.stringify(next));
  }

  function clearKey() {
    if (bridge && bridge.clearKey) {
      bridge.clearKey();
      return;
    }
    var cur = readConfig();
    cur.key = "";
    localStorage.setItem("magpieCfg", JSON.stringify(cur));
  }

  /* ---------- 请求 ---------- */

  function api(path) {
    return fetch(path, { cache: "no-store" }).then(function (r) {
      return r.text().then(function (text) {
        var data = null;
        try {
          data = JSON.parse(text);
        } catch (e) {
          throw new Error("网关返回了非 JSON 内容（HTTP " + r.status + "）");
        }
        if (!r.ok) {
          var msg = data && data.error ? String(data.error) : "";
          if (msg === "no-key") msg = "未配置密钥";
          if (!msg) msg = "HTTP " + r.status;
          throw new Error(msg);
        }
        return data;
      });
    });
  }

  function handleError(e) {
    var text = e && e.message ? e.message : String(e);
    toast("刷新失败：" + text);
    if (/未配置密钥|no-key|401/i.test(text)) {
      showSetup("密钥无效或未配置，请重新填写。");
    }
  }

  /* ---------- 视图切换 ---------- */

  function showSetup(msg) {
    var c = readConfig();
    $("in-base").value = c.base || DEFAULT_BASE;
    $("in-cookie").value = c.cookie || DEFAULT_COOKIE;
    $("in-key").value = "";
    $("in-key").placeholder = c.hasKey ? "已保存，留空则不修改" : "粘贴 ?k= 后面的密钥";
    $("setup-msg").textContent = msg || "";
    $("setup-msg").className = "msg";
    $("view-setup").hidden = false;
    $("view-dash").hidden = true;
  }

  function showDash() {
    $("view-setup").hidden = true;
    $("view-dash").hidden = false;
  }

  /* ---------- 刷新 ---------- */

  function refreshAll(force) {
    if (state.loading) return;
    var token = ++state.reqToken;
    var period = state.period;
    state.loading = true;
    spin(true);

    Promise.all([
      api("/api/usage?period=" + encodeURIComponent(period)),
      api("/api/usage/quotas")
    ]).then(function (res) {
      if (token !== state.reqToken) return;
      state.usage = res[0] || {};
      state.quotas = res[1] || [];
      state.lastOK = Date.now();
      showDash();
      renderUsage();
      renderQuotas();
      loadTrace(force);
      loadProviders(force);
    }).catch(handleError).then(function () {
      state.loading = false;
      spin(false);
    });
  }

  function loadTrace(force) {
    var now = Date.now();
    if (!force && state.trace && now - state.traceAt < TRACE_MS) {
      renderRoutes();
      return;
    }
    var after = state.trace && state.trace.seq ? state.trace.seq : 0;
    api("/api/gateway/trace?after=" + after).then(function (d) {
      if (!after || !state.trace) {
        state.trace = d;
      } else {
        var map = {};
        (state.trace.routes || []).concat(d.routes || []).forEach(function (r) {
          if (r && r.seq != null) map[r.seq] = r;
        });
        var arr = Object.keys(map).map(function (k) {
          return map[k];
        }).sort(function (a, b) {
          return a.seq - b.seq;
        });
        state.trace = {
          totals: d.totals || state.trace.totals,
          routes: arr.slice(-80),
          seq: d.seq || state.trace.seq
        };
      }
      state.traceAt = now;
      renderRoutes();
    }).catch(function () {
      /* 路由是次要数据，失败不打断主界面 */
    });
  }

  function loadProviders(force) {
    var now = Date.now();
    if (!force && state.providers && now - state.providersAt < PROVIDERS_MS) {
      renderProviders();
      return;
    }
    api("/api/providers").then(function (d) {
      state.providers = d;
      state.providersAt = now;
      renderProviders();
    }).catch(function () {
      /* 供应商是次要数据，失败不打断主界面 */
    });
  }

  /* ---------- 渲染：概览 ---------- */

  function renderUsage() {
    var u = state.usage || {};
    $("k-calls").textContent = fmtInt(u.calls);
    $("k-cost").textContent = fmtCost(u.cost);
    $("k-errors").textContent = fmtInt(u.errors);
    $("k-retried").textContent = fmtInt(u.retried);
    $("k-input").textContent = fmtCompact(u.input);
    $("k-output").textContent = fmtCompact(u.output);
    $("k-cache").textContent = fmtCompact(u.cache_read);
    $("k-reasoning").textContent = fmtCompact(u.reasoning);

    drawChart(u.series || []);
    renderModels(u.models || []);
    renderAgents(u.agents || []);

    $("footnote").textContent = "最后更新 " + fmtClock(new Date(state.lastOK).toISOString()) +
      " · 每 " + Math.round(REFRESH_MS / 1000) + " 秒自动刷新";
  }

  function drawChart(series) {
    var cv = $("chart");
    if (!cv) return;
    var w = cv.clientWidth || 320;
    var h = 140;
    var dpr = window.devicePixelRatio || 1;
    var pw = Math.round(w * dpr);
    var ph = Math.round(h * dpr);
    if (cv.width !== pw || cv.height !== ph) {
      cv.width = pw;
      cv.height = ph;
    }
    var ctx = cv.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);

    var note = $("chart-note");
    if (!series.length) {
      if (note) note.textContent = "";
      ctx.fillStyle = "#94a3b8";
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText("暂无趋势数据", w / 2, h / 2);
      return;
    }

    var padT = 8;
    var padB = 20;
    var padL = 4;
    var padR = 4;
    var max = 0;
    var i;
    for (i = 0; i < series.length; i++) {
      max = Math.max(max, Number(series[i].calls) || 0);
    }
    if (max <= 0) max = 1;

    var n = series.length;
    var slot = (w - padL - padR) / n;
    var bw = Math.max(2, Math.min(18, slot * 0.62));

    ctx.strokeStyle = "rgba(148,163,184,0.12)";
    ctx.lineWidth = 1;
    for (var g = 0; g < 3; g++) {
      var gy = padT + (h - padT - padB) * g / 2;
      ctx.beginPath();
      ctx.moveTo(padL, gy);
      ctx.lineTo(w - padR, gy);
      ctx.stroke();
    }

    for (i = 0; i < n; i++) {
      var v = Number(series[i].calls) || 0;
      var bh = (h - padT - padB) * (v / max);
      var x = padL + slot * i + (slot - bw) / 2;
      var y = h - padB - bh;
      var grad = ctx.createLinearGradient(0, y, 0, h - padB);
      grad.addColorStop(0, "#c084fc");
      grad.addColorStop(1, "rgba(124,58,237,0.18)");
      ctx.fillStyle = grad;
      roundRect(ctx, x, y, bw, Math.max(1, bh), Math.min(3, bw / 2));
      ctx.fill();
    }

    ctx.fillStyle = "#94a3b8";
    ctx.font = "10px sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    var step = Math.max(1, Math.ceil(n / 6));
    for (var j = 0; j < n; j += step) {
      var lbl = series[j].label != null ? String(series[j].label) : "";
      if (lbl) {
        ctx.fillText(lbl, padL + slot * j + slot / 2, h - padB + 5);
      }
    }
    if (note) note.textContent = "峰值 " + fmtCompact(max) + " 次";
  }

  function roundRect(ctx, x, y, w, h, r) {
    if (h <= 0) return;
    r = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + w - r, y);
    ctx.quadraticCurveTo(x + w, y, x + w, y + r);
    ctx.lineTo(x + w, y + h - r);
    ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
    ctx.lineTo(x + r, y + h);
    ctx.quadraticCurveTo(x, y + h, x, y + h - r);
    ctx.lineTo(x, y + r);
    ctx.quadraticCurveTo(x, y, x + r, y);
    ctx.closePath();
  }

  /* ---------- 渲染：额度 ---------- */

  function renderQuotas() {
    var box = $("quotas");
    var list = state.quotas || [];
    var rows = [];
    var total = 0;

    list.forEach(function (q) {
      var wins = q.windows || [];
      wins.forEach(function (w) {
        total++;
        if (rows.length >= 14) return;
        var used = Math.max(0, Math.min(100, Number(w.used) || 0));
        var cls = used >= 85 ? "red" : used >= 60 ? "amber" : "green";
        var title = q.name || q.provider || "未知供应商";
        if (w.name) title += " · " + w.name;
        var sub = "";
        if (w.display) sub = w.display;
        else if (w.amount != null && w.limit != null) sub = fmtInt(w.amount) + " / " + fmtInt(w.limit);
        if (w.resetsAt) {
          var r = fmtReset(w.resetsAt);
          if (r) sub += (sub ? " · " : "") + "重置 " + r;
        }
        if (!sub) sub = "已用 " + used.toFixed(0) + "%";
        rows.push(
          '<div class="row">' +
            '<div class="row-main">' +
              '<div class="row-title">' + esc(title) + "</div>" +
              '<div class="row-sub">' + esc(sub) + "</div>" +
            "</div>" +
            '<div class="row-val">' + used.toFixed(0) + "%</div>" +
          "</div>" +
          '<div class="bar ' + cls + '"><i style="width:' + used + '%"></i></div>'
        );
      });
    });

    box.innerHTML = rows.length ? rows.join("") : '<div class="empty">暂无配额数据</div>';
    $("quota-note").textContent = total > rows.length
      ? "显示 " + rows.length + " / 共 " + total + " 项"
      : (total ? "共 " + total + " 项" : "");
  }

  /* ---------- 渲染：模型 / 智能体 ---------- */

  function renderModels(models) {
    var box = $("models");
    if (!models.length) {
      box.innerHTML = '<div class="empty">暂无模型数据</div>';
      return;
    }
    models = models.slice().sort(function (a, b) {
      return (Number(b.calls) || 0) - (Number(a.calls) || 0);
    }).slice(0, 8);
    var max = Number(models[0].calls) || 1;
    var html = models.map(function (m) {
      var name = m.model || String(m.id || "").split(" @ ")[0] || "未知模型";
      var sub = (m.provider || "") + " · " + fmtInt(m.calls) + " 次";
      if (m.errors) sub += " · 错误 " + fmtInt(m.errors);
      if (m.cost) sub += " · " + fmtCost(m.cost);
      var pct = Math.max(2, (Number(m.calls) || 0) / max * 100);
      return '<div class="row">' +
        '<div class="row-main">' +
          '<div class="row-title">' + esc(name) + "</div>" +
          '<div class="row-sub">' + esc(sub) + "</div>" +
        "</div>" +
        '<div class="row-val">' + fmtCompact(m.calls) + "</div>" +
      "</div>" +
      '<div class="bar"><i style="width:' + pct + '%"></i></div>';
    });
    box.innerHTML = html.join("");
  }

  function renderAgents(agents) {
    var box = $("agents");
    if (!agents.length) {
      box.innerHTML = '<div class="empty">暂无智能体数据</div>';
      return;
    }
    agents = agents.slice().sort(function (a, b) {
      return (Number(b.calls) || 0) - (Number(a.calls) || 0);
    }).slice(0, 8);
    var max = Number(agents[0].calls) || 1;
    var html = agents.map(function (a) {
      var name = a.name || a.id || "未知";
      var sub = fmtInt(a.calls) + " 次";
      if (a.cost) sub += " · " + fmtCost(a.cost);
      if (a.errors) sub += " · 错误 " + fmtInt(a.errors);
      var pct = Math.max(2, (Number(a.calls) || 0) / max * 100);
      return '<div class="row">' +
        '<div class="row-main">' +
          '<div class="row-title">' + esc(name) + "</div>" +
          '<div class="row-sub">' + esc(sub) + "</div>" +
        "</div>" +
        '<div class="row-val">' + fmtCompact(a.calls) + "</div>" +
      "</div>" +
      '<div class="bar"><i style="width:' + pct + '%"></i></div>';
    });
    box.innerHTML = html.join("");
  }

  /* ---------- 渲染：路由 ---------- */

  function renderRoutes() {
    var box = $("routes");
    var t = state.trace;
    if (!t || !t.routes || !t.routes.length) {
      box.innerHTML = '<div class="empty">暂无路由记录</div>';
      $("route-note").textContent = "";
      return;
    }
    var routes = t.routes.slice(-14).reverse();
    var html = routes.map(function (r) {
      var name = r.group && r.group.name ? r.group.name : (r.model || "未知模型");
      var tries = r.tries || [];
      var sub = r.provider || "";
      if (r.agent) sub = r.agent + " · " + sub;
      var clock = fmtClock(r.time);
      if (clock) sub += " · " + clock;
      if (tries.length > 1) sub += " · 尝试 " + tries.length;
      var pill = r.done
        ? '<span class="pill ok">完成</span>'
        : '<span class="pill live">进行中</span>';
      return '<div class="row">' +
        '<div class="row-main">' +
          '<div class="row-title">' + esc(name) + pill + "</div>" +
          '<div class="row-sub">' + esc(sub) + "</div>" +
        "</div>" +
      "</div>";
    });
    box.innerHTML = html.join("");
    var totals = t.totals || {};
    $("route-note").textContent = "总计 " + fmtCompact(totals.requests) + " 次" +
      (totals.rerouted ? " · 改道 " + fmtCompact(totals.rerouted) : "") +
      (totals.errors ? " · 错误 " + fmtCompact(totals.errors) : "");
  }

  /* ---------- 渲染：供应商 ---------- */

  function renderProviders() {
    var box = $("providers");
    var data = state.providers;
    if (!data || !data.providers || !data.providers.length) {
      box.innerHTML = '<div class="empty">暂无供应商数据</div>';
      $("provider-note").textContent = "";
      return;
    }
    var list = data.providers.slice().sort(function (a, b) {
      if (!!b.ready !== !!a.ready) return b.ready ? 1 : -1;
      return String(a.name || "").localeCompare(String(b.name || ""), "zh-CN");
    });
    var shown = list.slice(0, 12);
    var html = shown.map(function (p) {
      var modelCount = Array.isArray(p.models) ? p.models.length : (p.exposed || 0);
      var sub = "模型 " + fmtInt(modelCount);
      if (p.agents && p.agents.length) sub += " · 智能体 " + p.agents.length;
      if (p.off) sub += " · 已停用";
      var pill = p.off
        ? '<span class="pill bad">停用</span>'
        : (p.ready ? '<span class="pill ok">在线</span>' : '<span class="pill">离线</span>');
      return '<div class="row">' +
        '<div class="row-main">' +
          '<div class="row-title">' + esc(p.name || p.id || "未知") + pill + "</div>" +
          '<div class="row-sub">' + esc(sub) + "</div>" +
        "</div>" +
      "</div>";
    });
    box.innerHTML = html.join("");
    $("provider-note").textContent = list.length > shown.length
      ? "显示 " + shown.length + " / 共 " + list.length + " 个"
      : "共 " + list.length + " 个";
  }

  /* ---------- 交互 ---------- */

  function toast(text) {
    var el = $("toast");
    el.textContent = text;
    el.className = "toast show";
    clearTimeout(el._t);
    el._t = setTimeout(function () {
      el.className = "toast";
    }, 3200);
  }

  function spin(on) {
    var b = $("btn-refresh");
    if (!b) return;
    if (on) b.classList.add("spin");
    else b.classList.remove("spin");
  }

  function startTimer() {
    stopTimer();
    state.timer = setInterval(function () {
      if (!document.hidden) refreshAll(false);
    }, REFRESH_MS);
  }

  function stopTimer() {
    if (state.timer) {
      clearInterval(state.timer);
      state.timer = null;
    }
  }

  function bind() {
    $("btn-refresh").addEventListener("click", function () {
      refreshAll(true);
    });

    $("btn-settings").addEventListener("click", function () {
      showSetup("");
    });

    $("btn-save").addEventListener("click", function () {
      var base = $("in-base").value.trim();
      var key = $("in-key").value.trim();
      var cookie = $("in-cookie").value.trim() || DEFAULT_COOKIE;
      var msg = $("setup-msg");

      if (!/^https?:\/\//i.test(base)) {
        msg.textContent = "地址必须以 http:// 或 https:// 开头";
        msg.className = "msg";
        return;
      }
      var cur = readConfig();
      if (!key && !cur.hasKey) {
        msg.textContent = "请填写访问密钥";
        msg.className = "msg";
        return;
      }
      saveConfig(base, key, cookie);
      msg.textContent = "已保存，正在连接…";
      msg.className = "msg ok";
      setTimeout(function () {
        state.usage = null;
        state.trace = null;
        state.providers = null;
        state.loading = false;
        refreshAll(true);
      }, 120);
    });

    $("btn-reset").addEventListener("click", function () {
      clearKey();
      showSetup("已清除保存的密钥。");
    });

    var tabs = $("period-tabs").querySelectorAll(".tab");
    Array.prototype.forEach.call(tabs, function (tab) {
      tab.addEventListener("click", function () {
        Array.prototype.forEach.call(tabs, function (t) {
          t.classList.remove("active");
        });
        tab.classList.add("active");
        state.period = tab.getAttribute("data-period") || "today";
        refreshAll(true);
      });
    });

    document.addEventListener("visibilitychange", function () {
      if (document.hidden) {
        stopTimer();
      } else {
        startTimer();
        refreshAll(false);
      }
    });

    var resizeTimer = null;
    window.addEventListener("resize", function () {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(function () {
        if (state.usage) drawChart(state.usage.series || []);
      }, 160);
    });
  }

  function init() {
    bind();
    var c = readConfig();
    if (!c.hasKey) {
      showSetup("");
      return;
    }
    showDash();
    refreshAll(true);
    startTimer();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
