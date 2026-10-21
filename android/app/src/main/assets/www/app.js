(function () {
  "use strict";

  var REFRESH_MS = 20000;
  var TRACE_MS = 15000;
  var PROVIDERS_MS = 10 * 60 * 1000;
  var DEFAULT_BASE = "https://magpie.example.invalid";
  var DEFAULT_COOKIE = "magpie_web_3430";

  var PALETTE = [
    "#7c3aed", "#0ea5e9", "#f43f5e", "#10b981", "#f59e0b",
    "#8b5cf6", "#06b6d4", "#ec4899", "#84cc16", "#6366f1"
  ];

  var state = {
    period: "today",
    metric: "calls",
    view: "overview",
    usage: null,
    quotas: null,
    trace: null,
    traceAt: 0,
    providers: null,
    providersAt: 0,
    providerQuery: "",
    loading: false,
    token: 0,
    timer: null,
    lastOK: 0
  };

  var openProviders = {};
  var openQuotas = {};
  var bridge = window.Android || null;

  /* ---------- 基础工具 ---------- */

  function $(id) {
    return document.getElementById(id);
  }

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function clamp(n, lo, hi) {
    n = Number(n) || 0;
    return Math.max(lo, Math.min(hi, n));
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

  function fmtMoney(n) {
    n = Number(n) || 0;
    if (n > 0 && n < 0.01) return "$" + n.toFixed(4);
    if (n >= 10000) return "$" + (n / 1000).toFixed(1) + "K";
    return "$" + n.toFixed(2);
  }

  function fmtMs(ms) {
    ms = Number(ms) || 0;
    if (ms >= 1000) return (ms / 1000).toFixed(1) + "s";
    return Math.round(ms) + "ms";
  }

  function pad2(n) {
    return n < 10 ? "0" + n : String(n);
  }

  function fmtClock(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime())) return "";
    return pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds());
  }

  function fmtUntil(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime())) return "";
    var ms = d.getTime() - Date.now();
    if (ms <= 0) return "即将重置";
    var h = Math.floor(ms / 3600000);
    if (h >= 24) return Math.floor(h / 24) + " 天 " + (h % 24) + " 小时";
    if (h > 0) return h + " 小时 " + Math.floor((ms % 3600000) / 60000) + " 分";
    return Math.max(1, Math.floor(ms / 60000)) + " 分钟";
  }

  function colorFor(s) {
    s = String(s || "");
    var h = 0;
    for (var i = 0; i < s.length; i++) {
      h = (h * 31 + s.charCodeAt(i)) >>> 0;
    }
    return PALETTE[h % PALETTE.length];
  }

  function initialOf(s) {
    s = String(s || "?").trim();
    return s ? s.charAt(0).toUpperCase() : "?";
  }

  /* ---------- 配置 ---------- */

  function readConfig() {
    if (bridge && bridge.getConfig) {
      try {
        return JSON.parse(bridge.getConfig());
      } catch (e) {
        /* fall through */
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
    localStorage.setItem("magpieCfg", JSON.stringify({
      base: base || cur.base,
      cookie: cookie || cur.cookie,
      key: key || cur.key || ""
    }));
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
      openSetup();
    }
  }

  /* ---------- 视图 ---------- */

  function switchView(name) {
    state.view = name;
    var map = {
      overview: "view-overview",
      routing: "view-routing",
      quotas: "view-quotas",
      providers: "view-providers"
    };
    Object.keys(map).forEach(function (k) {
      var el = $(map[k]);
      if (el) el.hidden = k !== name;
    });
    $("view-setup").hidden = true;
    $("tabbar").hidden = false;
    var tabs = $("tabbar").querySelectorAll(".tab");
    Array.prototype.forEach.call(tabs, function (tab) {
      tab.classList.toggle("active", tab.getAttribute("data-view") === name);
    });
    window.scrollTo(0, 0);
    if (name === "overview") {
      setTimeout(renderChart, 30);
    }
  }

  function openSetup(msg) {
    var c = readConfig();
    $("in-base").value = c.base || DEFAULT_BASE;
    $("in-cookie").value = c.cookie || DEFAULT_COOKIE;
    $("in-key").value = "";
    $("in-key").placeholder = c.hasKey ? "已保存，留空则不修改" : "粘贴 ?k= 后面的密钥";
    $("setup-msg").textContent = msg || "";
    $("setup-msg").className = "msg";

    ["view-overview", "view-routing", "view-quotas", "view-providers"].forEach(function (id) {
      $(id).hidden = true;
    });
    $("view-setup").hidden = false;
    $("tabbar").hidden = true;
    window.scrollTo(0, 0);
  }

  function closeSetup() {
    switchView(state.view || "overview");
  }

  /* ---------- 刷新 ---------- */

  function refreshAll(force) {
    if (state.loading) return;
    var token = ++state.token;
    state.loading = true;
    spin(true);

    Promise.all([
      api("/api/usage?period=" + encodeURIComponent(state.period)),
      api("/api/usage/quotas")
    ]).then(function (res) {
      if (token !== state.token) return;
      state.usage = res[0] || {};
      state.quotas = res[1] || [];
      state.lastOK = Date.now();
      renderOverview();
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
    if (!force && state.trace && now - state.traceAt < TRACE_MS) return;

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
      renderRouting();
    }).catch(function () {
      /* 次要数据，静默失败 */
    });
  }

  function loadProviders(force) {
    var now = Date.now();
    if (!force && state.providers && now - state.providersAt < PROVIDERS_MS) return;

    api("/api/providers").then(function (d) {
      state.providers = d;
      state.providersAt = now;
      renderProviders();
    }).catch(function () {
      /* 次要数据，静默失败 */
    });
  }

  /* ---------- 概览 ---------- */

  var PERIOD_LABEL = { today: "今日", "7d": "7 天", "30d": "30 天", all: "全部" };

  function renderOverview() {
    var u = state.usage || {};
    $("hero-period").textContent = PERIOD_LABEL[state.period] || "今日";
    $("k-cost").textContent = fmtMoney(u.cost);
    $("k-calls").textContent = fmtInt(u.calls);
    $("k-errors").textContent = fmtInt(u.errors);
    $("k-retried").textContent = fmtInt(u.retried);

    $("k-input").textContent = fmtCompact(u.input);
    $("k-output").textContent = fmtCompact(u.output);
    $("k-cache").textContent = fmtCompact(u.cache_read);
    var ttft = u.timed ? u.ttft_ms / u.timed : 0;
    $("k-ttft").textContent = ttft ? fmtMs(ttft) : "--";

    var totalIn = (Number(u.input) || 0) + (Number(u.cache_read) || 0);
    var hit = totalIn > 0 ? (Number(u.cache_read) || 0) / totalIn * 100 : 0;
    $("k-input-foot").textContent = "缓存占比 " + Math.round(hit) + "%";
    $("k-output-foot").textContent = u.calls
      ? "每次 " + fmtCompact((Number(u.output) || 0) / u.calls) + " tokens"
      : "本期累计";
    $("k-cache-foot").textContent = "命中率 " + Math.round(hit) + "%";

    renderSpark(u.series || []);
    renderChart();
    renderModels(u.models || []);
    renderAgents(u.agents || []);

    if (state.lastOK) {
      $("footnote").textContent = "最后更新 " + fmtClock(new Date(state.lastOK).toISOString()) +
        " · 每 " + Math.round(REFRESH_MS / 1000) + " 秒自动刷新";
    }
  }

  function renderSpark(series) {
    var el = $("hero-spark");
    var vals = (series || []).map(function (s) {
      return Number(s.calls) || 0;
    });
    if (vals.length < 2) {
      el.innerHTML = "";
      return;
    }
    var W = 360;
    var H = 54;
    var pad = 2;
    var max = Math.max.apply(null, vals.concat([1]));
    var n = vals.length;
    var pts = vals.map(function (v, i) {
      return [
        pad + (W - pad * 2) * i / (n - 1),
        H - pad - (H - pad * 2) * (v / max)
      ];
    });
    var d = pts.map(function (p, i) {
      return (i ? "L" : "M") + p[0].toFixed(1) + "," + p[1].toFixed(1);
    }).join(" ");
    var area = d + " L" + (W - pad) + "," + H + " L" + pad + "," + H + " Z";
    el.innerHTML = '<svg viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="none">' +
      '<defs><linearGradient id="sparkFill" x1="0" y1="0" x2="0" y2="1">' +
      '<stop offset="0" stop-color="#c084fc" stop-opacity="0.42"/>' +
      '<stop offset="1" stop-color="#c084fc" stop-opacity="0"/>' +
      "</linearGradient></defs>" +
      '<path d="' + area + '" fill="url(#sparkFill)"/>' +
      '<path d="' + d + '" fill="none" stroke="#d8b4fe" stroke-width="1.6" ' +
      'stroke-linecap="round" stroke-linejoin="round"/>' +
      "</svg>";
  }

  function renderChart() {
    var series = (state.usage && state.usage.series) || [];
    var svg = $("trend");
    var empty = $("chart-empty");

    if (!series.length) {
      svg.innerHTML = "";
      empty.hidden = false;
      $("chart-peak").textContent = "—";
      $("chart-total").textContent = "—";
      return;
    }
    empty.hidden = true;

    var W = Math.max(280, $("chart-wrap").clientWidth || 320);
    var H = 172;
    var padL = 6;
    var padR = 6;
    var padT = 22;
    var padB = 24;
    var isCost = state.metric === "cost";
    var values = series.map(function (s) {
      return Number(isCost ? s.cost : s.calls) || 0;
    });
    var max = Math.max.apply(null, values.concat([1]));
    var n = values.length;
    var xAt = function (i) {
      return padL + (W - padL - padR) * (n === 1 ? 0.5 : i / (n - 1));
    };
    var yAt = function (v) {
      return padT + (H - padT - padB) * (1 - v / max);
    };

    var grid = "";
    for (var g = 0; g < 4; g++) {
      var gy = padT + (H - padT - padB) * g / 3;
      grid += '<line x1="' + padL + '" y1="' + gy.toFixed(1) + '" x2="' + (W - padR) +
        '" y2="' + gy.toFixed(1) + '" stroke="rgba(148,163,184,0.09)" stroke-width="1"/>';
    }

    var line = "";
    values.forEach(function (v, i) {
      line += (i ? "L" : "M") + xAt(i).toFixed(1) + "," + yAt(v).toFixed(1);
    });
    var area = line + " L" + xAt(n - 1).toFixed(1) + "," + (H - padB) +
      " L" + xAt(0).toFixed(1) + "," + (H - padB) + " Z";

    var labels = "";
    var step = Math.max(1, Math.ceil(n / 5));
    for (var j = 0; j < n; j += step) {
      var lbl = series[j].label != null ? String(series[j].label) : "";
      if (lbl) {
        labels += '<text x="' + xAt(j).toFixed(1) + '" y="' + (H - 6) +
          '" fill="#5d6a88" font-size="9" text-anchor="middle">' + esc(lbl) + "</text>";
      }
    }

    var maxIdx = values.indexOf(max);
    var maxX = xAt(maxIdx);
    var maxY = yAt(max);
    var maxText = isCost ? fmtMoney(max) : fmtCompact(max);

    var gradId = isCost ? "areaCost" : "areaCalls";
    var areaColor = isCost ? "#22d3ee" : "#8b5cf6";
    var lineColor = isCost ? "#67e8f9" : "#c4b5fd";

    svg.setAttribute("viewBox", "0 0 " + W + " " + H);
    svg.innerHTML =
      "<defs>" +
        '<linearGradient id="' + gradId + '" x1="0" y1="0" x2="0" y2="1">' +
          '<stop offset="0" stop-color="' + areaColor + '" stop-opacity="0.34"/>' +
          '<stop offset="1" stop-color="' + areaColor + '" stop-opacity="0"/>' +
        "</linearGradient>" +
      "</defs>" +
      grid +
      '<path d="' + area + '" fill="url(#' + gradId + ')"/>' +
      '<path d="' + line + '" fill="none" stroke="' + lineColor + '" stroke-width="2.2" ' +
        'stroke-linecap="round" stroke-linejoin="round"/>' +
      '<circle cx="' + maxX.toFixed(1) + '" cy="' + maxY.toFixed(1) +
        '" r="7" fill="' + areaColor + '" opacity="0.18"/>' +
      '<circle cx="' + maxX.toFixed(1) + '" cy="' + maxY.toFixed(1) +
        '" r="3.2" fill="' + lineColor + '" stroke="#070a14" stroke-width="1.6"/>' +
      '<text x="' + Math.max(26, Math.min(W - 26, maxX)).toFixed(1) + '" y="' +
        Math.max(12, maxY - 9) + '" fill="#cbd5e1" font-size="9.5" text-anchor="middle">' +
        esc(maxText) + "</text>" +
      labels;

    var total = values.reduce(function (a, b) {
      return a + b;
    }, 0);
    $("chart-peak").textContent = "峰值 " + (isCost ? fmtMoney(max) : fmtCompact(max));
    $("chart-total").textContent = "合计 " + (isCost ? fmtMoney(total) : fmtInt(total) + " 次");
    $("chart-sub").textContent = state.period === "today" ? "按小时统计" : "按天统计";
  }

  function renderModels(models) {
    var box = $("models");
    if (!models.length) {
      box.innerHTML = '<div class="empty">暂无模型数据</div>';
      $("model-count").textContent = "";
      return;
    }
    models = models.slice().sort(function (a, b) {
      return (Number(b.calls) || 0) - (Number(a.calls) || 0);
    });
    var max = Number(models[0].calls) || 1;
    var shown = models.slice(0, 10);
    box.innerHTML = shown.map(function (m, i) {
      var name = m.model || m.name || String(m.id || "").split(" @ ")[0] || "未知模型";
      var sub = [];
      if (m.provider) sub.push(m.provider);
      if (m.cost) sub.push(fmtMoney(m.cost));
      if (m.errors) sub.push("错误 " + fmtInt(m.errors));
      var pct = Math.max(3, (Number(m.calls) || 0) / max * 100);
      return '<div class="rank">' +
        '<div class="rank-pos">' + (i + 1) + "</div>" +
        '<div class="rank-main">' +
          '<div class="rank-top"><span class="rank-name">' + esc(name) + "</span>" +
            '<span class="rank-val">' + fmtCompact(m.calls) + "</span></div>" +
          '<div class="rank-track"><i style="width:' + pct + '%"></i></div>' +
          '<div class="rank-sub">' + esc(sub.join(" · ")) + "</div>" +
        "</div>" +
      "</div>";
    }).join("");
    $("model-count").textContent = "共 " + models.length + " 个";
  }

  function renderAgents(agents) {
    var box = $("agents");
    if (!agents.length) {
      box.innerHTML = '<div class="empty">暂无智能体数据</div>';
      $("agent-count").textContent = "";
      return;
    }
    agents = agents.slice().sort(function (a, b) {
      return (Number(b.calls) || 0) - (Number(a.calls) || 0);
    });
    var max = Number(agents[0].calls) || 1;
    var shown = agents.slice(0, 8);
    box.innerHTML = shown.map(function (a, i) {
      var name = a.name || a.id || "未知";
      var sub = [];
      if (a.cost) sub.push(fmtMoney(a.cost));
      if (a.errors) sub.push("错误 " + fmtInt(a.errors));
      var pct = Math.max(3, (Number(a.calls) || 0) / max * 100);
      return '<div class="rank">' +
        '<div class="rank-pos">' + (i + 1) + "</div>" +
        '<div class="rank-main">' +
          '<div class="rank-top"><span class="rank-name">' + esc(name) + "</span>" +
            '<span class="rank-val">' + fmtCompact(a.calls) + "</span></div>" +
          '<div class="rank-track"><i style="width:' + pct + '%"></i></div>' +
          '<div class="rank-sub">' + esc(sub.join(" · ") || "调用次数") + "</div>" +
        "</div>" +
      "</div>";
    }).join("");
    $("agent-count").textContent = "共 " + agents.length + " 个";
  }

  /* ---------- 路由 ---------- */

  function renderRouting() {
    var t = state.trace;
    if (!t) return;
    var totals = t.totals || {};
    $("r-requests").textContent = fmtCompact(totals.requests);
    $("r-rerouted").textContent = fmtCompact(totals.rerouted);
    $("r-errors").textContent = fmtCompact(totals.errors);

    var box = $("routes");
    var routes = (t.routes || []).slice(-20).reverse();
    if (!routes.length) {
      box.innerHTML = '<div class="empty">暂无路由记录</div>';
      return;
    }
    box.innerHTML = routes.map(routeCard).join("");
    $("route-foot").textContent = "显示最近 " + routes.length + " 条 · 每 20 秒刷新";
  }

  function routeCard(r) {
    var name = r.group && r.group.name
      ? r.group.name
      : String(r.model || "").replace(/^group\//, "");
    var tries = r.tries || [];
    var nodes = [];

    if (tries.length) {
      tries.forEach(function (tr, idx) {
        var cls = "chain-node";
        if (r.done && idx === tries.length - 1) cls += " ok";
        else if (!r.done && idx === tries.length - 1) cls += " live";
        else cls += " fail";
        nodes.push('<span class="' + cls + '"><i></i>' +
          esc(tr.id || tr.provider || "未知") + "</span>");
      });
    } else if (r.provider) {
      nodes.push('<span class="chain-node ' + (r.done ? "ok" : "live") + '"><i></i>' +
        esc(r.provider) + "</span>");
    }

    var meta = [];
    if (r.agent) meta.push(r.agent);
    var clock = fmtClock(r.time);
    if (clock) meta.push(clock);
    if (r.prompt && r.prompt.tokens) meta.push(fmtCompact(r.prompt.tokens) + " tokens");
    if (tries.length > 1) meta.push("尝试 " + tries.length + " 次");

    return '<div class="route">' +
      '<div class="route-head">' +
        '<span class="route-model">' + esc(name || "未知模型") + "</span>" +
        '<span class="state ' + (r.done ? "done" : "live") + '">' +
          (r.done ? "完成" : "进行中") + "</span>" +
      "</div>" +
      '<div class="chain">' + nodes.join('<span class="chain-arrow"></span>') + "</div>" +
      '<div class="route-meta">' + esc(meta.join(" · ")) + "</div>" +
    "</div>";
  }

  /* ---------- 额度 ---------- */

  function renderQuotas() {
    var box = $("quotas");
    var list = (state.quotas || []).filter(function (q) {
      return q && q.windows && q.windows.length;
    });

    if (!list.length) {
      box.innerHTML = '<div class="empty">暂无配额数据</div>';
      $("quota-health").textContent = "--";
      $("quota-summary").textContent = "没有可用的额度窗口";
      $("quota-foot").textContent = "";
      return;
    }

    list.forEach(function (q) {
      var minRemain = 100;
      q.windows.forEach(function (w) {
        minRemain = Math.min(minRemain, 100 - clamp(w.used, 0, 100));
      });
      q._min = minRemain;
    });
    list.sort(function (a, b) {
      return a._min - b._min;
    });

    var allRemain = [];
    var lowCount = 0;
    list.forEach(function (q) {
      q.windows.forEach(function (w) {
        var remain = 100 - clamp(w.used, 0, 100);
        allRemain.push(remain);
        if (remain < 30) lowCount++;
      });
    });
    var health = allRemain.reduce(function (a, b) {
      return a + b;
    }, 0) / allRemain.length;

    var ring = $("ring-fg");
    ring.style.strokeDashoffset = String(314 - 314 * health / 100);
    ring.style.stroke = health >= 60 ? "#34d399" : health >= 30 ? "#fbbf24" : "#fb7185";
    $("quota-health").textContent = Math.round(health) + "%";
    $("quota-summary").textContent = list.length + " 个供应商 · " +
      allRemain.length + " 个额度窗口" + (lowCount ? " · " + lowCount + " 项低于 30%" : " · 整体充足");

    box.innerHTML = list.map(function (q) {
      var remainMin = q._min;
      var cls = remainMin >= 60 ? "good" : remainMin >= 30 ? "warn" : "low";
      var color = colorFor(q.provider || q.name);
      var plan = q.plan || q.provider || "";
      var qid = q.provider || q.name || "quota";
      var isOpen = !!openQuotas[qid];

      var seen = {};
      var labeled = q.windows.map(function (w) {
        var label = w.name || "额度";
        seen[label] = (seen[label] || 0) + 1;
        return { w: w, label: seen[label] > 1 ? label + " #" + seen[label] : label };
      });
      var visible = isOpen ? labeled : labeled.slice(0, 4);

      var wins = visible.map(function (item) {
        var w = item.w;
        var used = clamp(w.used, 0, 100);
        var remain = 100 - used;
        var barCls = remain >= 60 ? "" : remain >= 30 ? "warn" : "low";
        var detail = w.display ||
          (w.amount != null && w.limit != null ? fmtInt(w.amount) + " / " + fmtInt(w.limit) : "");
        var reset = w.resetsAt ? "重置 " + fmtUntil(w.resetsAt) : "";
        return '<div class="q-window">' +
          '<div class="q-win-top"><span>' + esc(item.label) + "</span>" +
            "<b>剩余 " + Math.round(remain) + "%</b></div>" +
          '<div class="q-track"><i class="' + barCls + '" style="width:' + remain + '%"></i></div>' +
          '<div class="q-win-foot">' + esc([detail, reset].filter(Boolean).join(" · ")) + "</div>" +
        "</div>";
      }).join("");

      var more = q.windows.length > 4
        ? '<button class="q-more" type="button" data-qid="' + esc(qid) + '">' +
          (isOpen ? "收起" : "展开全部 " + q.windows.length + " 项") + "</button>"
        : "";

      return '<div class="quota">' +
        '<div class="q-head">' +
          '<span class="q-avatar" style="--c:' + color + '">' + esc(initialOf(q.name)) + "</span>" +
          '<div class="q-title"><b>' + esc(q.name || q.provider) + "</b>" +
            "<small>" + esc(plan) + "</small></div>" +
          '<span class="q-pct ' + cls + '">' + Math.round(remainMin) + "%<em>最低</em></span>" +
        "</div>" + wins + more +
      "</div>";
    }).join("");

    $("quota-foot").textContent = "按最低剩余额度排序 · 数据来自 magpie";
  }

  /* ---------- 供应商 ---------- */

  function renderProviders() {
    var box = $("providers");
    var data = state.providers;
    if (!data || !data.providers || !data.providers.length) {
      box.innerHTML = '<div class="empty">暂无供应商数据</div>';
      $("provider-foot").textContent = "";
      return;
    }

    var q = state.providerQuery.trim().toLowerCase();
    var list = data.providers.filter(function (p) {
      if (!q) return true;
      return (String(p.name || "") + " " + String(p.id || "") + " " + String(p.host || ""))
        .toLowerCase().indexOf(q) >= 0;
    });

    list.sort(function (a, b) {
      var ra = a.ready && !a.off ? 1 : 0;
      var rb = b.ready && !b.off ? 1 : 0;
      if (ra !== rb) return rb - ra;
      return String(a.name || a.id || "").localeCompare(String(b.name || b.id || ""), "zh-CN");
    });

    if (!list.length) {
      box.innerHTML = '<div class="empty">没有匹配的供应商</div>';
      $("provider-foot").textContent = "";
      return;
    }

    box.innerHTML = list.map(function (p) {
      var models = p.models || [];
      var onCount = models.filter(function (m) {
        return m && m.on;
      }).length;
      var isOpen = !!openProviders[p.id];
      var stateCls = p.off ? "off" : (p.ready ? "on" : "");
      var stateTxt = p.off ? "停用" : (p.ready ? "在线" : "离线");
      var sub = [];
      sub.push(models.length + " 个模型");
      if (models.length && onCount !== models.length) sub.push(onCount + " 已启用");
      if (p.host) sub.push(p.host);

      var chips = models.slice(0, 12).map(function (m) {
        return '<span class="model-chip ' + (m.on ? "on" : "") + '">' +
          esc(m.name || m.id) + "</span>";
      }).join("");
      if (models.length > 12) {
        chips += '<span class="model-chip">+' + (models.length - 12) + "</span>";
      }
      if (!models.length) chips = '<span class="model-chip">暂无模型清单</span>';

      return '<div class="provider' + (isOpen ? " open" : "") + '" data-pid="' + esc(p.id) + '">' +
        '<div class="p-main">' +
          '<span class="p-avatar" style="--c:' + colorFor(p.id || p.name) + '">' +
            esc(initialOf(p.name || p.id)) + "</span>" +
          '<div class="p-body">' +
            '<div class="p-name">' + esc(p.name || p.id || "未知") + "</div>" +
            '<div class="p-sub">' + esc(sub.join(" · ")) + "</div>" +
          "</div>" +
          '<span class="p-state ' + stateCls + '"><i></i>' + stateTxt + "</span>" +
        "</div>" +
        '<div class="p-models">' + chips + "</div>" +
      "</div>";
    }).join("");

    var online = data.providers.filter(function (p) {
      return p.ready && !p.off;
    }).length;
    $("provider-foot").textContent = "共 " + data.providers.length + " 个 · " +
      online + " 个在线" + (q ? " · 筛选出 " + list.length + " 个" : "");
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
    if (b) b.classList.toggle("spin", !!on);
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
      openSetup("");
    });

    $("btn-back").addEventListener("click", closeSetup);

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
        switchView("overview");
        refreshAll(true);
      }, 120);
    });

    $("btn-reset").addEventListener("click", function () {
      clearKey();
      openSetup("已清除保存的密钥。");
    });

    var tabs = $("tabbar").querySelectorAll(".tab");
    Array.prototype.forEach.call(tabs, function (tab) {
      tab.addEventListener("click", function () {
        switchView(tab.getAttribute("data-view"));
      });
    });

    var periods = $("period-tabs").querySelectorAll(".seg-item");
    Array.prototype.forEach.call(periods, function (btn) {
      btn.addEventListener("click", function () {
        Array.prototype.forEach.call(periods, function (b) {
          b.classList.remove("active");
        });
        btn.classList.add("active");
        state.period = btn.getAttribute("data-period") || "today";
        refreshAll(true);
      });
    });

    var metrics = $("metric-tabs").querySelectorAll("button");
    Array.prototype.forEach.call(metrics, function (btn) {
      btn.addEventListener("click", function () {
        Array.prototype.forEach.call(metrics, function (b) {
          b.classList.remove("active");
        });
        btn.classList.add("active");
        state.metric = btn.getAttribute("data-metric") || "calls";
        renderChart();
      });
    });

    $("provider-search").addEventListener("input", function () {
      state.providerQuery = this.value || "";
      renderProviders();
    });

    $("providers").addEventListener("click", function (e) {
      var main = e.target.closest ? e.target.closest(".p-main") : null;
      if (!main) return;
      var card = main.parentNode;
      var pid = card.getAttribute("data-pid");
      openProviders[pid] = !openProviders[pid];
      card.classList.toggle("open");
    });

    $("quotas").addEventListener("click", function (e) {
      var more = e.target.closest ? e.target.closest(".q-more") : null;
      if (!more) return;
      var qid = more.getAttribute("data-qid");
      openQuotas[qid] = !openQuotas[qid];
      renderQuotas();
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
      resizeTimer = setTimeout(renderChart, 160);
    });
  }

  function renderSkeletons() {
    ["models", "agents", "routes", "quotas", "providers"].forEach(function (id) {
      var box = $(id);
      if (box) {
        box.innerHTML = '<div class="skeleton"></div><div class="skeleton"></div><div class="skeleton"></div>';
      }
    });
  }

  function init() {
    bind();
    renderSkeletons();
    var c = readConfig();
    if (!c.hasKey) {
      openSetup("");
      return;
    }
    switchView("overview");
    refreshAll(true);
    startTimer();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
