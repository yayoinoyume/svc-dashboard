(function () {
  "use strict";

  var REFRESH_MS = 20000;
  var TRACE_MS = 15000;
  var PROVIDERS_MS = 10 * 60 * 1000;
  var DEFAULT_BASE = "";
  var DEFAULT_COOKIE = "magpie_web_3430";

  /* Material Design 3 (Material You) Tonal Accent Palette */
  var PALETTE = [
    "#d0bcff", "#78d9eb", "#f5b7d0", "#72f7be", "#ffdd80",
    "#b388ff", "#4dd0e1", "#ff80ab", "#b9f6ca", "#ffd54f"
  ];

  var state = {
    period: "today",
    metric: "calls",
    view: "overview",
    detailTab: "sessions",
    routingTab: "live",
    usage: null,
    quotas: null,
    trace: null,
    traceAt: 0,
    providers: null,
    providersAt: 0,
    groups: null,
    groupsAt: 0,
    history: null,
    historyAt: 0,
    providerQuery: "",
    loading: false,
    token: 0,
    timer: null,
    lastOK: 0,
    live: false,
    liveTimer: null,
    liveOK: false,
    traceLoaded: false,
    seenSeq: {},
    doneMap: {},
    routeOrder: []
  };

  var openProviders = {};
  var openQuotas = {};
  var openRoutes = {};
  var openGroups = {};
  var openDetails = {};
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

  function maskAccount(s) {
    s = String(s || "");
    var at = s.indexOf("@");
    if (at > 0) {
      var u = s.slice(0, at);
      var d = s.slice(at + 1);
      if (u.length <= 2) return u.charAt(0) + "***@" + d;
      return u.slice(0, 2) + "***" + u.slice(-1) + "@" + d;
    }
    if (/^1\d{10}$/.test(s)) return s.slice(0, 3) + "****" + s.slice(-4);
    if (s.length > 14) return s.slice(0, 6) + "…" + s.slice(-4);
    return s;
  }

  function shortId(s) {
    s = String(s || "");
    return s.length > 12 ? s.slice(0, 8) + "…" + s.slice(-4) : s;
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

  /* ---------- 平滑数字滚动过渡 (Count-Up Animation) ---------- */

  function countUp(el, targetVal, formatFn, duration) {
    if (!el) return;
    targetVal = Number(targetVal) || 0;
    if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      el.textContent = formatFn(targetVal);
      el._curVal = targetVal;
      return;
    }
    var startVal = el._curVal != null ? el._curVal : 0;
    if (Math.abs(startVal - targetVal) < 0.0001) {
      el.textContent = formatFn(targetVal);
      el._curVal = targetVal;
      return;
    }
    if (el._animId) cancelAnimationFrame(el._animId);
    duration = duration || 360;
    var startTime = null;

    function step(timestamp) {
      if (!startTime) startTime = timestamp;
      var progress = Math.min(1, (timestamp - startTime) / duration);
      // easeOutCubic
      var ease = 1 - Math.pow(1 - progress, 3);
      var current = startVal + (targetVal - startVal) * ease;
      el.textContent = formatFn(current);
      if (progress < 1) {
        el._animId = requestAnimationFrame(step);
      } else {
        el.textContent = formatFn(targetVal);
        el._curVal = targetVal;
        el._animId = null;
      }
    }
    el._animId = requestAnimationFrame(step);
  }

  /* ---------- Material Ripple 触摸涟漪效果 ---------- */

  function handleRipple(e) {
    var target = e.target.closest
      ? e.target.closest(".ripple, .icon-btn, .seg-item, .tab, .primary, .ghost, .back-btn, .route, .provider, .detail, .group, .q-more, .kpi")
      : null;
    if (!target) return;

    var rect = target.getBoundingClientRect();
    var circle = document.createElement("span");
    var d = Math.max(rect.width, rect.height);
    var clientX = e.clientX != null ? e.clientX : (e.touches && e.touches[0] ? e.touches[0].clientX : rect.left + rect.width / 2);
    var clientY = e.clientY != null ? e.clientY : (e.touches && e.touches[0] ? e.touches[0].clientY : rect.top + rect.height / 2);
    var x = clientX - rect.left - d / 2;
    var y = clientY - rect.top - d / 2;

    circle.className = "ripple-wave";
    circle.style.width = circle.style.height = d + "px";
    circle.style.left = x + "px";
    circle.style.top = y + "px";

    target.appendChild(circle);
    setTimeout(function () {
      if (circle.parentNode) {
        circle.parentNode.removeChild(circle);
      }
    }, 500);
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
      providers: "view-providers",
      details: "view-details"
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
      stopLive();
      setTimeout(renderChart, 30);
    } else if (name === "routing") {
      renderRouting();
      renderGroups();
      if (!state.groups) loadGroups(false);
      startLive();
    } else {
      stopLive();
      if (name === "details") renderDetails();
    }
  }

  function openSetup(msg) {
    stopLive();
    var c = readConfig();
    $("in-base").value = c.base || DEFAULT_BASE;
    $("in-cookie").value = c.cookie || DEFAULT_COOKIE;
    $("in-key").value = "";
    $("in-key").placeholder = c.hasKey ? "已保存，留空则不修改" : "粘贴 ?k= 后面的密钥";
    $("setup-msg").textContent = msg || "";
    $("setup-msg").className = "msg";

    ["view-overview", "view-routing", "view-quotas", "view-providers", "view-details"].forEach(function (id) {
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
      renderDetails();
      if (state.view !== "routing") loadTrace(force);
      loadProviders(force);
      loadGroups(force);
      loadHistory(force);
    }).catch(handleError).then(function () {
      state.loading = false;
      spin(false);
    });
  }

  function rkey(r) {
    return r && r.id != null ? String(r.id) : String(r && r.seq);
  }

  function sortRoutes(routes) {
    return routes.sort(function (a, b) {
      return (Number(a.seq) || 0) - (Number(b.seq) || 0);
    });
  }

  function mergeTrace(d, after) {
    if (!after || !state.trace) {
      var firstMap = {};
      (d.routes || []).forEach(function (r) {
        if (r) firstMap[rkey(r)] = r;
      });
      var firstRoutes = sortRoutes(Object.keys(firstMap).map(function (k) {
        return firstMap[k];
      }));
      state.trace = {
        totals: d.totals || {},
        seq: d.seq || 0,
        routes: firstRoutes
      };
      state.routeOrder = firstRoutes.map(rkey);
      state.traceLoaded = true;
      firstRoutes.forEach(function (r) {
        var k = rkey(r);
        state.seenSeq[k] = true;
        state.doneMap[k] = !!r.done;
      });
      return;
    }

    // magpie 会把"同一请求的状态更新"作为新的 seq 再推一次，必须按 id 覆盖，
    // 否则同一个请求会以"进行中"和"完成"两条卡片重复出现。
    // 同时保持首次出现顺序：状态更新原地刷新，不因新 seq 移动到列表其它位置，
    // 避免实时刷新时用户正在展开/阅读的卡片跳动。
    var map = {};
    (state.trace.routes || []).forEach(function (r) {
      if (r) map[rkey(r)] = r;
    });
    (d.routes || []).forEach(function (r) {
      if (!r) return;
      var k = rkey(r);
      map[k] = r;
      if (state.routeOrder.indexOf(k) < 0) state.routeOrder.push(k);
    });

    state.routeOrder = state.routeOrder.filter(function (k) {
      return !!map[k];
    });
    while (state.routeOrder.length > 80) {
      delete map[state.routeOrder.shift()];
    }

    state.trace = {
      totals: d.totals || state.trace.totals,
      routes: state.routeOrder.map(function (k) {
        return map[k];
      }).filter(Boolean),
      seq: d.seq || state.trace.seq
    };
  }

  function loadTrace(force) {
    var now = Date.now();
    if (!force && state.trace && now - state.traceAt < TRACE_MS) return;

    var after = state.trace && state.trace.seq ? state.trace.seq : 0;
    api("/api/gateway/trace?after=" + after).then(function (d) {
      mergeTrace(d, after);
      state.traceAt = now;
      renderRouting();
    }).catch(function () {
      /* 次要数据，静默失败 */
    });
  }

  function setLiveStatus(ok) {
    state.liveOK = ok;
    var el = $("live-status");
    var txt = $("live-text");
    if (!el || !txt) return;
    txt.textContent = ok ? "实时" : "重连中";
    el.classList.toggle("lost", !ok);
  }

  function startLive() {
    stopLive();
    state.live = true;
    liveLoop();
  }

  function stopLive() {
    state.live = false;
    if (state.liveTimer) {
      clearTimeout(state.liveTimer);
      state.liveTimer = null;
    }
  }

  function liveLoop() {
    if (!state.live) return;
    if (state.view !== "routing" || document.hidden) {
      state.liveTimer = setTimeout(liveLoop, 1500);
      return;
    }

    var after = state.trace && state.trace.seq ? state.trace.seq : 0;
    var url = "/api/gateway/trace?after=" + after + (after ? "&wait=1" : "");
    api(url).then(function (d) {
      mergeTrace(d, after);
      state.traceAt = Date.now();
      setLiveStatus(true);
      renderRouting();
    }).catch(function () {
      setLiveStatus(false);
    }).then(function () {
      if (!state.live) return;
      state.liveTimer = setTimeout(liveLoop, state.liveOK ? 400 : 1500);
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

  function loadGroups(force) {
    var now = Date.now();
    if (!force && state.groups && now - state.groupsAt < 60000) return;

    api("/api/groups").then(function (d) {
      state.groups = d;
      state.groupsAt = now;
      renderGroups();
    }).catch(function () {
      /* 次要数据，静默失败 */
    });
  }

  function loadHistory(force) {
    var now = Date.now();
    if (!force && state.history && now - state.historyAt < 10 * 60 * 1000) return;

    api("/api/gateway/history").then(function (d) {
      state.history = d;
      state.historyAt = now;
      if (state.metric === "daily") renderChart();
    }).catch(function () {
      /* 次要数据，静默失败 */
    });
  }

  /* ---------- 概览 ---------- */

  var PERIOD_LABEL = { today: "今日", "7d": "7 天", "30d": "30 天", all: "全部" };

  function renderOverview() {
    var u = state.usage || {};
    $("hero-period").textContent = PERIOD_LABEL[state.period] || "今日";

    countUp($("k-cost"), u.cost, fmtMoney);
    countUp($("k-calls"), u.calls, fmtInt);
    countUp($("k-errors"), u.errors, fmtInt);
    countUp($("k-retried"), u.retried, fmtInt);

    countUp($("k-input"), u.input, fmtCompact);
    countUp($("k-output"), u.output, fmtCompact);
    countUp($("k-cache"), u.cache_read, fmtCompact);
    countUp($("k-cache-write"), u.cache_write, fmtCompact);
    var ttft = u.timed ? u.ttft_ms / u.timed : 0;
    $("k-ttft").textContent = ttft ? fmtMs(ttft) : "--";
    var decode = u.decode_ms ? (Number(u.decode_out) || 0) / (u.decode_ms / 1000) : 0;
    $("k-decode").textContent = decode ? Math.round(decode) + " t/s" : "--";

    var totalIn = (Number(u.input) || 0) + (Number(u.cache_read) || 0);
    var hit = totalIn > 0 ? (Number(u.cache_read) || 0) / totalIn * 100 : 0;
    $("k-input-foot").textContent = "缓存占比 " + Math.round(hit) + "%";
    $("k-output-foot").textContent = u.calls
      ? "每次 " + fmtCompact((Number(u.output) || 0) / u.calls) + " tokens"
      : "本期累计";
    $("k-cache-foot").textContent = "命中率 " + Math.round(hit) + "%";

    renderQuality(u);
    renderSpark(u.series || []);
    renderChart();
    renderModels(u.models || []);
    renderAgents(u.agents || []);

    if (state.lastOK) {
      $("footnote").textContent = "最后更新 " + fmtClock(new Date(state.lastOK).toISOString()) +
        " · 每 " + Math.round(REFRESH_MS / 1000) + " 秒自动刷新";
    }
  }

  function renderQuality(u) {
    var calls = Number(u.calls) || 0;
    var errors = Number(u.errors) || 0;
    var success = calls ? (calls - errors) / calls * 100 : 0;

    countUp($("q-success"), calls ? success : 0, function (v) {
      return calls ? v.toFixed(1) + "%" : "--";
    });

    $("q-unpriced").textContent = u.unpriced ? fmtCompact(u.unpriced) + " 次" : "0";
    $("q-credits").textContent = u.credits ? fmtCompact(u.credits) : "—";
    $("q-avgcost").textContent = calls ? fmtMoney((Number(u.cost) || 0) / calls) : "—";
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
      '<stop offset="0" stop-color="#d0bcff" stop-opacity="0.38"/>' +
      '<stop offset="1" stop-color="#d0bcff" stop-opacity="0"/>' +
      "</linearGradient></defs>" +
      '<path d="' + area + '" fill="url(#sparkFill)" class="chart-area-anim"/>' +
      '<path d="' + d + '" fill="none" stroke="#d0bcff" stroke-width="2" ' +
      'stroke-linecap="round" stroke-linejoin="round" class="chart-line-anim"/>' +
      "</svg>";
  }

  function renderChart() {
    var isDaily = state.metric === "daily";
    var series;
    if (isDaily) {
      series = ((state.history && state.history.days) || []).map(function (d) {
        return {
          label: String(d.day || "").slice(5),
          calls: Number(d.requests) || 0,
          cost: 0
        };
      });
    } else {
      series = (state.usage && state.usage.series) || [];
    }
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
    var isCost = state.metric === "cost" && !isDaily;
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
        '" y2="' + gy.toFixed(1) + '" stroke="rgba(202,196,208,0.08)" stroke-width="1"/>';
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
        var lx = Math.max(18, Math.min(W - 18, xAt(j)));
        labels += '<text x="' + lx.toFixed(1) + '" y="' + (H - 6) +
          '" fill="#5d6a88" font-size="9" text-anchor="middle">' + esc(lbl) + "</text>";
      }
    }

    var maxIdx = values.indexOf(max);
    var maxX = xAt(maxIdx);
    var maxY = yAt(max);
    var maxText = isCost ? fmtMoney(max) : fmtCompact(max);

    var gradId = isCost ? "areaCost" : "areaCalls";
    var areaColor = isCost ? "#78d9eb" : "#d0bcff";
    var lineColor = isCost ? "#78d9eb" : "#d0bcff";

    svg.setAttribute("viewBox", "0 0 " + W + " " + H);
    svg.innerHTML =
      "<defs>" +
        '<linearGradient id="' + gradId + '" x1="0" y1="0" x2="0" y2="1">' +
          '<stop offset="0" stop-color="' + areaColor + '" stop-opacity="0.36"/>' +
          '<stop offset="1" stop-color="' + areaColor + '" stop-opacity="0"/>' +
        "</linearGradient>" +
      "</defs>" +
      grid +
      '<path d="' + area + '" fill="url(#' + gradId + ')" class="chart-area-anim"/>' +
      '<path d="' + line + '" fill="none" stroke="' + lineColor + '" stroke-width="2.4" ' +
        'stroke-linecap="round" stroke-linejoin="round" class="chart-line-anim"/>' +
      '<circle cx="' + maxX.toFixed(1) + '" cy="' + maxY.toFixed(1) +
        '" r="8" fill="' + areaColor + '" opacity="0.2"/>' +
      '<circle cx="' + maxX.toFixed(1) + '" cy="' + maxY.toFixed(1) +
        '" r="3.6" fill="' + lineColor + '" stroke="#141218" stroke-width="1.8"/>' +
      '<text x="' + Math.max(28, Math.min(W - 28, maxX)).toFixed(1) + '" y="' +
        Math.max(12, maxY - 10) + '" fill="#e6e0e9" font-size="10" font-weight="600" text-anchor="middle">' +
        esc(maxText) + "</text>" +
      labels;

    var total = values.reduce(function (a, b) {
      return a + b;
    }, 0);
    $("chart-peak").textContent = "峰值 " + (isCost ? fmtMoney(max) : fmtCompact(max));
    $("chart-total").textContent = "合计 " + (isCost ? fmtMoney(total) : fmtInt(total) + " 次");
    $("chart-sub").textContent = isDaily
      ? "最近 " + series.length + " 天每日请求量"
      : (state.period === "today" ? "按小时统计" : "按天统计");
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
    countUp($("r-requests"), totals.requests, fmtCompact);
    countUp($("r-rerouted"), totals.rerouted, fmtCompact);
    countUp($("r-errors"), totals.errors, fmtCompact);

    var box = $("routes");
    var routes = (t.routes || []).slice(-20).reverse();
    var running = routes.filter(function (r) {
      return !r.done;
    }).length;
    var sub = $("route-live-sub");
    if (sub) {
      sub.textContent = running
        ? "正在处理 " + running + " 个请求 · " + routes.length + " 条记录"
        : "当前空闲 · 最近 " + routes.length + " 条记录";
    }

    if (!routes.length) {
      box.innerHTML = '<div class="empty">暂无路由记录</div>';
      $("route-foot").textContent = "";
      return;
    }
    box.innerHTML = routes.map(routeCard).join("");
    $("route-foot").textContent = "长轮询实时流 · 有事件立即更新";
    tickElapsed();
  }

  function routeCard(r) {
    var key = rkey(r);
    var open = !!openRoutes[key];
    var isNew = state.traceLoaded && !state.seenSeq[key];
    var wasDone = state.doneMap[key];
    var justDone = !!r.done && wasDone === false;
    state.seenSeq[key] = true;
    state.doneMap[key] = !!r.done;

    var name = r.group && r.group.name
      ? r.group.name
      : String(r.model || "").replace(/^group\//, "");
    var tries = r.tries || [];
    var nodes = [];

    if (r.agent) {
      nodes.push('<span class="chain-node agent"><i></i>' + esc(r.agent) + "</span>");
    }
    nodes.push('<span class="chain-node hub"><i></i>magpie</span>');

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
    var clock = fmtClock(r.time);
    if (clock) meta.push(clock);
    if (r.prompt && r.prompt.tokens) meta.push(fmtCompact(r.prompt.tokens) + " tokens");
    if (tries.length > 1) meta.push("尝试 " + tries.length + " 次");
    if (r.effort) meta.push(r.effort);

    var elapsed = "";
    if (!r.done && r.time) {
      var started = new Date(r.time).getTime();
      if (!isNaN(started)) {
        elapsed = ' <span class="elapsed" data-start="' + started + '"></span>';
      }
    }

    var cls = "route" +
      (open ? " open" : "") +
      (r.done ? " done" : " running") +
      (isNew ? " new" : "") +
      (justDone ? " just-done" : "");

    return '<div class="' + cls + '" data-rid="' + esc(key) + '">' +
      '<div class="route-head">' +
        '<span class="route-model">' + esc(name || "未知模型") + "</span>" +
        '<span class="route-right">' +
          '<span class="state ' + (r.done ? "done" : "live") + '">' +
            (r.done ? "完成" : "进行中") + "</span>" +
          '<span class="chev">' + (open ? "▴" : "▾") + "</span>" +
        "</span>" +
      "</div>" +
      '<div class="chain">' + nodes.join('<span class="chain-arrow"></span>') + "</div>" +
      '<div class="route-meta">' + esc(meta.join(" · ")) + elapsed + "</div>" +
      (open ? routeDetail(r) : "") +
    "</div>";
  }

  function tickElapsed() {
    var els = document.querySelectorAll(".elapsed");
    if (!els.length) return;
    var now = Date.now();
    Array.prototype.forEach.call(els, function (el) {
      var start = Number(el.getAttribute("data-start"));
      if (!start) return;
      var sec = Math.max(0, (now - start) / 1000);
      el.textContent = sec < 60
        ? sec.toFixed(1) + "s"
        : Math.floor(sec / 60) + "m" + Math.floor(sec % 60) + "s";
    });
  }

  var PART_LABEL = {
    system: "系统",
    tools: "工具",
    memory: "记忆",
    files: "文件",
    messages: "消息",
    history: "历史",
    results: "结果",
    chat: "对话",
    user: "用户",
    assistant: "助手",
    tool_results: "工具结果",
    context: "上下文"
  };

  function routeDetail(r) {
    var html = "";

    var order = r.order || [];
    if (order.length) {
      var rows = order.slice(0, 10).map(function (o) {
        var pace = Math.round(clamp(o.pace, 0, 1) * 100);
        var used = "—";
        if (o.used != null && o.used !== "") {
          var n = Number(o.used);
          used = n >= 100 ? String(Math.round(n)) : (n >= 10 ? n.toFixed(1) : n.toFixed(2));
        }
        var label = o.name || o.id || "?";
        if (o.model) label += " · " + o.model;
        return '<div class="ord"><b>' + esc(label) + "</b>" +
          "<span>已用 " + esc(used) + (pace ? " · 速度 " + pace + "%" : "") + "</span></div>";
      }).join("");
      html += '<div class="rd"><div class="rd-title">候选池 <span>' + order.length +
        " 个</span></div><div class=\"rd-order\">" + rows + "</div></div>";
    }

    var aff = r.affinity;
    if (aff && (aff.why || aff.kept || aff.cacheRead)) {
      var WHY_LABEL = {
        turn: "同一轮对话",
        last: "上次使用",
        cache: "缓存亲和",
        affinity: "账号亲和",
        sticky: "粘性会话"
      };
      var bits = [];
      if (aff.kept) bits.push("保持缓存");
      if (aff.why) bits.push(WHY_LABEL[aff.why] || String(aff.why));
      if (aff.turn != null) bits.push("第 " + (Number(aff.turn) + 1) + " 轮");
      if (aff.cacheRead) bits.push("缓存 " + fmtCompact(aff.cacheRead));
      html += '<div class="rd"><div class="rd-title">亲和性</div>' +
        '<div class="rd-line">' + esc(bits.join(" · ")) + "</div></div>";
    }

    var parts = (r.prompt && r.prompt.parts) || [];
    if (parts.length) {
      var total = Number(r.prompt.tokens) || parts.reduce(function (a, p) {
        return a + (Number(p.tokens) || 0);
      }, 0);
      var maxp = Math.max.apply(null, parts.map(function (p) {
        return Number(p.tokens) || 0;
      }).concat([1]));
      var partRows = parts.map(function (p) {
        var t = Number(p.tokens) || 0;
        var pct = total ? Math.round(t / total * 100) : 0;
        var label = PART_LABEL[p.kind] || p.kind || "?";
        return '<div class="part"><span>' + esc(label) + "</span>" +
          "<b>" + fmtCompact(t) + "</b>" +
          '<i style="width:' + Math.max(2, t / maxp * 100) + '%"></i>' +
          "<em>" + pct + "%</em></div>";
      }).join("");
      html += '<div class="rd"><div class="rd-title">上下文构成 <span>' +
        fmtCompact(total) + " tokens</span></div>" +
        '<div class="rd-parts">' + partRows + "</div></div>";
    }

    var extra = [];
    if (r.effort) extra.push("强度 " + r.effort);
    if (r.cost) extra.push("费用 " + fmtMoney(r.cost));
    if (r.priced === false) extra.push("未计价");
    if (extra.length) {
      html += '<div class="rd"><div class="rd-line muted">' +
        esc(extra.join(" · ")) + "</div></div>";
    }

    return html
      ? '<div class="route-detail">' + html + "</div>"
      : '<div class="route-detail"><div class="empty">这条请求没有更多明细</div></div>';
  }

  /* ---------- 路由组 ---------- */

  function renderGroups() {
    var d = state.groups;
    var box = $("groups");
    if (!d) return;

    var groups = d.groups || [];
    var pools = d.pools || [];
    var deciders = d.deciders || [];

    $("g-count").textContent = groups.length;
    $("g-pools").textContent = pools.length;
    $("g-deciders").textContent = deciders.length;

    if (!groups.length && !pools.length) {
      box.innerHTML = '<div class="empty">暂无路由组数据</div>';
      $("group-foot").textContent = "";
      return;
    }

    var html = groups.map(function (g) {
      var open = !!openGroups["g:" + g.id];
      var infoMap = {};
      (g.memberInfo || []).forEach(function (m) {
        if (m && m.id) infoMap[m.id] = m;
      });
      var off = g.off || [];
      var members = (g.members || []).map(function (mid) {
        var info = infoMap[mid] || {};
        return {
          id: mid,
          provider: info.provider,
          model: info.model,
          name: info.name || mid,
          ready: info.ready !== false
        };
      });
      if (!members.length) members = g.memberInfo || [];
      var visible = open ? members : members.slice(0, 3);
      var chips = visible.map(function (m) {
        var label = m.provider ? (m.provider + "/" + (m.model || m.id)) : (m.name || m.id);
        var isOff = off.indexOf(m.id) >= 0;
        var cls = isOff ? "off" : (m.ready !== false ? "on" : "");
        return '<span class="model-chip ' + cls + '">' + esc(label) + "</span>";
      }).join("");
      if (members.length > 3 && !open) {
        chips += '<span class="model-chip">+' + (members.length - 3) + "</span>";
      }
      var meta = members.length + " 成员" +
        (off.length ? " · " + off.length + " 停用" : "") +
        (g.ready ? " · 就绪" : " · 未就绪");

      return '<div class="group' + (open ? " open" : "") + '" data-gid="' + esc(g.id) + '">' +
        '<div class="g-head">' +
          '<div class="g-name">' + esc(g.name || g.id) + "</div>" +
          '<span class="g-badge">' + esc(g.routing || "order") + "</span>" +
        "</div>" +
        '<div class="g-meta">' + esc(meta) + "</div>" +
        '<div class="g-members">' + chips + "</div>" +
      "</div>";
    }).join("");

    if (pools.length) {
      html += '<div class="section-label">账号池</div>';
      html += pools.map(function (p) {
        var who = (p.who || []).map(maskAccount).join("、");
        return '<div class="pool">' +
          '<div class="g-head"><div class="g-name">' + esc(p.name || p.provider) + "</div>" +
            '<span class="g-badge">' + esc(p.kind || "池") + "</span></div>" +
          '<div class="g-meta">' + esc(who || "无成员") + "</div>" +
        "</div>";
      }).join("");
    }

    if (deciders.length) {
      html += '<div class="section-label">决策器</div>';
      html += deciders.map(function (x) {
        return '<div class="pool">' +
          '<div class="g-head"><div class="g-name">' + esc(x.name || x.id) + "</div></div>" +
          '<div class="g-meta">' + esc(x.providerName || x.provider || "") + "</div>" +
        "</div>";
      }).join("");
    }

    box.innerHTML = html;
    $("group-foot").textContent = "共 " + groups.length + " 个路由组 · " +
      pools.length + " 个账号池 · " + deciders.length + " 个决策器";
  }

  /* ---------- 明细 ---------- */

  function costLabel(r) {
    var cost = Number(r.cost) || 0;
    if (cost > 0) return fmtMoney(cost);
    if (r.credits) return Number(r.credits).toFixed(1) + " 信用";
    return "";
  }

  function renderDetails() {
    var u = state.usage || {};
    var tab = state.detailTab;
    var rows = [];
    var title = "";
    var sub = "";
    var prefix = "";

    if (tab === "sessions") {
      rows = u.sessions || [];
      title = "会话用量";
      sub = "按调用次数排序，点击查看明细";
      prefix = "s";
    } else if (tab === "accounts") {
      rows = u.accounts || [];
      title = "账号用量";
      sub = "账号已打码，点击查看明细";
      prefix = "a";
    } else if (tab === "callers") {
      rows = u.callerKeys || [];
      title = "调用方用量";
      sub = "按调用方密钥统计";
      prefix = "c";
    } else {
      rows = u.providerKeys || [];
      title = "供应商密钥";
      sub = "按供应商密钥统计";
      prefix = "k";
    }

    rows = rows.slice().sort(function (a, b) {
      return (Number(b.calls) || 0) - (Number(a.calls) || 0);
    });

    $("detail-title").textContent = title;
    $("detail-sub").textContent = sub;
    $("detail-count").textContent = rows.length ? "共 " + rows.length + " 条" : "";

    var box = $("detail-list");
    if (!rows.length) {
      box.innerHTML = '<div class="empty">暂无数据</div>';
      $("detail-foot").textContent = "";
      return;
    }

    var max = Number(rows[0].calls) || 1;
    box.innerHTML = rows.map(function (r, i) {
      var key = prefix + ":" + i;
      var open = !!openDetails[key];
      var name = "";
      var line = "";

      if (tab === "sessions") {
        name = (r.agent || "未知") + " · #" + shortId(r.id);
        line = [
          costLabel(r),
          fmtCompact((Number(r.input) || 0) + (Number(r.output) || 0)) + " tokens",
          r.errors ? "错误 " + fmtInt(r.errors) : ""
        ].filter(Boolean).join(" · ");
      } else if (tab === "accounts") {
        name = maskAccount(r.account || r.name || r.id);
        line = [r.provider, costLabel(r)].filter(Boolean).join(" · ");
      } else if (tab === "callers") {
        name = r.name || r.callerKeyName || shortId(r.callerKeyId || r.id);
        line = [
          costLabel(r),
          r.errors ? "错误 " + fmtInt(r.errors) : "",
          r.unpriced ? "未计价 " + fmtInt(r.unpriced) : ""
        ].filter(Boolean).join(" · ");
      } else {
        name = (r.provider || "?") + " · " + (r.providerKeyName || shortId(r.providerKeyId || r.id));
        line = [costLabel(r), fmtInt(r.calls) + " 次"].filter(Boolean).join(" · ");
      }

      var pct = Math.max(3, (Number(r.calls) || 0) / max * 100);
      return '<div class="detail' + (open ? " open" : "") + '" data-dkey="' + key + '">' +
        '<div class="detail-head">' +
          '<div class="detail-main">' +
            '<div class="detail-name">' + esc(name) + "</div>" +
            '<div class="detail-sub">' + esc(line) + "</div>" +
            '<div class="rank-track"><i style="width:' + pct + '%"></i></div>' +
          "</div>" +
          '<div class="detail-right"><b>' + fmtCompact(r.calls) + "</b>" +
            '<span class="chev">' + (open ? "▴" : "▾") + "</span></div>" +
        "</div>" +
        (open ? detailBody(r) : "") +
      "</div>";
    }).join("");

    $("detail-foot").textContent = "数据来自 magpie 用量接口 · " + title;
  }

  function detailBody(r) {
    var cells = [
      ["输入", fmtCompact(r.input)],
      ["输出", fmtCompact(r.output)],
      ["缓存读", fmtCompact(r.cache_read)],
      ["缓存写", fmtCompact(r.cache_write)],
      ["推理", fmtCompact(r.reasoning)],
      ["信用", r.credits ? Number(r.credits).toFixed(1) : "—"],
      ["平均首字", r.timed ? fmtMs(r.ttft_ms / r.timed) : "—"],
      ["解码", r.decode_ms ? Math.round((r.decode_out || 0) / (r.decode_ms / 1000)) + " t/s" : "—"],
      ["未计价", fmtInt(r.unpriced)],
      ["计时请求", fmtInt(r.timed)]
    ];
    return '<div class="detail-body">' + cells.map(function (c) {
      return "<div><span>" + c[0] + "</span><b>" + c[1] + "</b></div>";
    }).join("") + "</div>";
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
    ring.style.stroke = health >= 60 ? "#72f7be" : health >= 30 ? "#ffdd80" : "#ffb4ab";

    countUp($("quota-health"), health, function (v) {
      return Math.round(v) + "%";
    });
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

      var modelRows = models.slice(0, 8).map(function (m) {
        var price = m.list || {};
        var bits = [];
        if (m.context) bits.push("上下文 " + fmtCompact(m.context));
        if (m.output) bits.push("输出 " + fmtCompact(m.output));
        if (price.input != null) bits.push("$" + price.input + " / $" + price.output);
        if (m.efforts && m.efforts.length) bits.push(m.efforts.join("/"));
        if (m.images) bits.push("图片");
        return '<div class="mdl' + (m.on ? " on" : "") + '"><b>' +
          esc(m.name || m.id) + "</b><span>" + esc(bits.join(" · ")) + "</span></div>";
      }).join("");
      if (models.length > 8) {
        modelRows += '<div class="mdl-more">还有 ' + (models.length - 8) + " 个模型</div>";
      }

      var extras = [];
      if (p.speaks && p.speaks.length) {
        extras.push('<span class="model-chip">' + esc(p.speaks.join(" / ")) + "</span>");
      }
      if (p.keyList && p.keyList.length) {
        extras.push('<span class="model-chip">密钥 ' + esc(p.keyList.map(function (k) {
          return k.name || "key";
        }).join("、")) + "</span>");
      }
      if (p.maxConcurrency) {
        extras.push('<span class="model-chip">并发 ' + esc(p.maxConcurrency) + "</span>");
      }
      if (p.website) {
        extras.push('<a class="model-chip link" href="' + esc(p.website) +
          '" target="_blank" rel="noopener">官网</a>');
      }
      var extrasHtml = extras.length
        ? '<div class="p-extra">' + extras.join("") + "</div>"
        : "";

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
        '<div class="p-models">' + chips + extrasHtml +
          (modelRows ? '<div class="mdl-list">' + modelRows + "</div>" : "") +
        "</div>" +
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
    document.addEventListener("pointerdown", handleRipple, { passive: true });

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
        if (state.metric === "daily") loadHistory(false);
        renderChart();
      });
    });

    var rtabs = $("routing-tabs").querySelectorAll(".seg-item");
    Array.prototype.forEach.call(rtabs, function (btn) {
      btn.addEventListener("click", function () {
        Array.prototype.forEach.call(rtabs, function (b) {
          b.classList.remove("active");
        });
        btn.classList.add("active");
        state.routingTab = btn.getAttribute("data-rtab") || "live";
        $("routing-live").hidden = state.routingTab !== "live";
        $("routing-groups").hidden = state.routingTab !== "groups";
        if (state.routingTab === "groups") {
          renderGroups();
          loadGroups(false);
        }
      });
    });

    var dtabs = $("detail-tabs").querySelectorAll(".seg-item");
    Array.prototype.forEach.call(dtabs, function (btn) {
      btn.addEventListener("click", function () {
        Array.prototype.forEach.call(dtabs, function (b) {
          b.classList.remove("active");
        });
        btn.classList.add("active");
        state.detailTab = btn.getAttribute("data-dtab") || "sessions";
        renderDetails();
      });
    });

    $("routes").addEventListener("click", function (e) {
      var card = e.target.closest ? e.target.closest(".route") : null;
      if (!card) return;
      var rid = card.getAttribute("data-rid");
      if (!rid) return;
      openRoutes[rid] = !openRoutes[rid];
      renderRouting();
    });

    $("groups").addEventListener("click", function (e) {
      var g = e.target.closest ? e.target.closest(".group") : null;
      if (!g) return;
      var gid = g.getAttribute("data-gid");
      openGroups["g:" + gid] = !openGroups["g:" + gid];
      renderGroups();
    });

    $("detail-list").addEventListener("click", function (e) {
      var d = e.target.closest ? e.target.closest(".detail") : null;
      if (!d) return;
      var key = d.getAttribute("data-dkey");
      openDetails[key] = !openDetails[key];
      renderDetails();
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
        stopLive();
      } else {
        startTimer();
        if (state.view === "routing") startLive();
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
    ["models", "agents", "routes", "quotas", "providers", "groups", "detail-list"].forEach(function (id) {
      var box = $(id);
      if (box) {
        box.innerHTML = '<div class="skeleton"></div><div class="skeleton"></div><div class="skeleton"></div>';
      }
    });
  }

  function init() {
    bind();
    renderSkeletons();
    setInterval(tickElapsed, 250);
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
