// ═══════════════════════════════════════════════════════════════════
//  Tree Manager Dashboard — Main Application Script
// ═══════════════════════════════════════════════════════════════════

// ─── STATE ─────────────────────────────────────
let TREES = [];
let STATS = {};
let ALERTS = [];
let ANALYTICS = {};
let filteredTrees = [];

// Map state
let leafletMap = null;
let overviewMap = null;
let mapMarkers = null;
let currentLayer = "street";
let clusterEnabled = true;
let mapSpeciesFilter = "";
let mapStatusFilter = "";
let tileLayer = null;

// Table state
let currentPage = 1;
let pageSize = 25;
let sortCol = "tree_id";
let sortDir = "asc";

// Chart instances
let charts = {};

// ─── HELPERS ───────────────────────────────────
const statusColor = (s) =>
  s === "good" ? "#2d6a4f" : s === "not_good" ? "#f77f00" : "#d62828";
const statusLabel = (s) =>
  s === "good"
    ? "Tốt"
    : s === "not_good"
      ? "Cần xử lý"
      : s === "die"
        ? "Chết"
        : s;
const statusIcon = (s) =>
  s === "good" ? "✅" : s === "not_good" ? "⚠️" : "💀";

function openLightbox(src) {
  document.getElementById("lbImg").src = src;
  document.getElementById("lightbox").classList.add("active");
}

function formatDateTime(iso) {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleString("vi-VN");
}

function formatDateShort(iso) {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleDateString("vi-VN");
}

function timeAgo(iso) {
  if (!iso) return "";
  const now = new Date();
  const d = new Date(iso);
  const diff = Math.floor((now - d) / 1000);
  if (diff < 60) return "vừa xong";
  if (diff < 3600) return Math.floor(diff / 60) + " phút trước";
  if (diff < 86400) return Math.floor(diff / 3600) + " giờ trước";
  if (diff < 604800) return Math.floor(diff / 86400) + " ngày trước";
  return formatDateShort(iso);
}

// ─── NAVIGATION ────────────────────────────────
function switchPage(page) {
  document
    .querySelectorAll(".page")
    .forEach((p) => p.classList.remove("active"));
  document
    .querySelectorAll(".nav-item")
    .forEach((n) => n.classList.remove("active"));
  document.getElementById("page-" + page).classList.add("active");
  document
    .querySelector('.nav-item[data-page="' + page + '"]')
    .classList.add("active");

  const titles = {
    overview: "Tổng quan",
    alerts: "Cảnh báo & Hành động",
    analytics: "Phân tích chi tiết",
    map: "Bản đồ quản lý",
    data: "Dữ liệu chi tiết",
  };
  document.getElementById("pageTitle").textContent = titles[page] || page;

  if (page === "map" && leafletMap) {
    setTimeout(function () {
      leafletMap.invalidateSize();
    }, 100);
  }
  if (page === "overview" && overviewMap) {
    setTimeout(function () {
      overviewMap.invalidateSize();
    }, 100);
  }
  // Close mobile sidebar
  document.getElementById("sidebar").classList.remove("open");
}

// ─── DATA FETCH ────────────────────────────────
async function fetchData() {
  const resp = await fetch("/api/trees");
  return resp.json();
}

async function refreshData() {
  const btn = document.getElementById("refreshBtn");
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner"></span> Đang tải…';
  document.getElementById("syncDot").classList.remove("error");

  try {
    const data = await fetchData();
    TREES = data.trees;
    STATS = data.stats;
    ALERTS = data.alerts || [];
    ANALYTICS = data.analytics || {};

    TREES.sort(function (a, b) {
      return (parseInt(a.tree_id) || 0) - (parseInt(b.tree_id) || 0);
    });
    filteredTrees = TREES.slice();

    renderKPIs();
    renderAlertSummary();
    renderActivityFeed();
    loadChartJs().then(function () {
      renderOverviewCharts();
      renderAnalyticsPage();
    });
    renderAlertPage();
    renderOverviewMap();
    renderFullMap();
    renderTable();
    populateFilters();
    populateMapFilters();
    updateAlertBadge();

    var now = new Date();
    document.getElementById("syncText").textContent =
      "Đồng bộ lúc " +
      now.toLocaleTimeString("vi-VN") +
      " — " +
      STATS.total +
      " cây";

    document.getElementById("loadingOverlay").style.display = "none";
    document.getElementById("dashboardBody").style.display = "block";
  } catch (err) {
    console.error("Failed to fetch data:", err);
    document.getElementById("syncDot").classList.add("error");
    document.getElementById("syncText").textContent = "Lỗi kết nối!";
  } finally {
    btn.disabled = false;
    btn.innerHTML =
      '<svg aria-hidden="true" viewBox="0 0 24 24" style="width:16px;height:16px;fill:currentColor"><path d="M17.65 6.35A7.96 7.96 0 0012 4a8 8 0 108 8h-2a6 6 0 11-1.76-4.24L14 10h7V3l-3.35 3.35z"/></svg> Làm mới';
  }
}

// ─── KPIs ──────────────────────────────────────
function renderKPIs() {
  var s = STATS;
  document.getElementById("kpiGrid").innerHTML =
    '<div class="kpi">' +
    '<div class="kpi-icon green">🌳</div>' +
    '<div class="kpi-info">' +
    '<div class="kpi-value">' +
    s.total +
    "</div>" +
    '<div class="kpi-label">Tổng số cây</div>' +
    "</div>" +
    "</div>" +
    '<div class="kpi">' +
    '<div class="kpi-icon purple">🌿</div>' +
    '<div class="kpi-info">' +
    '<div class="kpi-value">' +
    s.species_count +
    "</div>" +
    '<div class="kpi-label">Số loài</div>' +
    "</div>" +
    "</div>" +
    '<div class="kpi">' +
    '<div class="kpi-icon green">💚</div>' +
    '<div class="kpi-info">' +
    '<div class="kpi-value" style="color:var(--good)">' +
    s.good_pct +
    "%</div>" +
    '<div class="kpi-label">Tỷ lệ khỏe mạnh</div>' +
    '<div class="kpi-trend up">' +
    s.good +
    " / " +
    s.total +
    " cây</div>" +
    "</div>" +
    "</div>" +
    '<div class="kpi">' +
    '<div class="kpi-icon orange">⚠️</div>' +
    '<div class="kpi-info">' +
    '<div class="kpi-value" style="color:var(--warn)">' +
    s.not_good +
    "</div>" +
    '<div class="kpi-label">Cần xử lý</div>' +
    "</div>" +
    "</div>" +
    '<div class="kpi">' +
    '<div class="kpi-icon red">💀</div>' +
    '<div class="kpi-info">' +
    '<div class="kpi-value" style="color:var(--danger)">' +
    s.die +
    "</div>" +
    '<div class="kpi-label">Đã chết</div>' +
    "</div>" +
    "</div>" +
    '<div class="kpi">' +
    '<div class="kpi-icon blue">📅</div>' +
    '<div class="kpi-info">' +
    '<div class="kpi-value">' +
    s.avg_age +
    "</div>" +
    '<div class="kpi-label">Tuổi trung bình (năm)</div>' +
    "</div>" +
    "</div>";
}

// ─── ALERT SUMMARY (overview page) ────────────
function renderAlertSummary() {
  var el = document.getElementById("alertSummary");
  if (!ALERTS.length) {
    el.innerHTML =
      '<div class="empty-state" style="padding:30px"><div class="icon">✅</div><p>Tất cả cây khỏe mạnh!</p></div>';
    return;
  }
  var top5 = ALERTS.slice(0, 5);
  el.innerHTML = top5
    .map(function (a) {
      return (
        '<div class="alert-item" onclick="openTreeDetail(\'' +
        a.tree_id +
        "')\">" +
        '<div class="alert-icon ' +
        a.priority +
        '">' +
        (a.priority === "critical" ? "🚨" : "⚠️") +
        "</div>" +
        '<div class="alert-content">' +
        '<div class="alert-title">Cây ' +
        a.tree_id +
        " — " +
        a.species +
        "</div>" +
        '<div class="alert-desc">' +
        a.message +
        "</div>" +
        "</div>" +
        '<span class="alert-priority ' +
        a.priority +
        '">' +
        (a.priority === "critical" ? "Nghiêm trọng" : "Cảnh báo") +
        "</span>" +
        "</div>"
      );
    })
    .join("");
}

function updateAlertBadge() {
  var badge = document.getElementById("alertBadge");
  if (ALERTS.length > 0) {
    badge.style.display = "inline";
    badge.textContent = ALERTS.length;
  } else {
    badge.style.display = "none";
  }
}

// ─── ACTIVITY FEED (overview page) ─────────────
function renderActivityFeed() {
  var el = document.getElementById("activityFeed");
  var recent = (ANALYTICS.recent_activity || []).slice(0, 8);
  if (!recent.length) {
    el.innerHTML =
      '<div class="empty-state" style="padding:30px"><div class="icon">📭</div><p>Chưa có hoạt động</p></div>';
    return;
  }
  el.innerHTML = recent
    .map(function (a) {
      return (
        '<div class="activity-item" onclick="openTreeDetail(\'' +
        a.tree_id +
        '\')" style="cursor:pointer">' +
        '<div class="activity-dot" style="background:' +
        statusColor(a.status) +
        '"></div>' +
        '<div class="activity-text">' +
        "<strong>" +
        (a.updated_by || "Hệ thống") +
        "</strong> cập nhật cây <strong>" +
        a.tree_id +
        "</strong> (" +
        a.species +
        ")" +
        '<div class="activity-time">' +
        timeAgo(a.updated_at) +
        "</div>" +
        "</div>" +
        '<span class="badge ' +
        a.status +
        '" style="font-size:.65rem">' +
        statusLabel(a.status) +
        "</span>" +
        "</div>"
      );
    })
    .join("");
}

// ─── OVERVIEW CHARTS ───────────────────────────
function destroyChart(name) {
  if (charts[name]) {
    charts[name].destroy();
    delete charts[name];
  }
}

function renderOverviewCharts() {
  // Health donut
  destroyChart("health");
  var healthCounts = {};
  TREES.forEach(function (t) {
    healthCounts[t.status] = (healthCounts[t.status] || 0) + 1;
  });
  charts.health = new Chart(document.getElementById("healthChart"), {
    type: "doughnut",
    data: {
      labels: Object.keys(healthCounts).map(statusLabel),
      datasets: [
        {
          data: Object.values(healthCounts),
          backgroundColor: Object.keys(healthCounts).map(statusColor),
          borderWidth: 2,
          borderColor: "#fff",
        },
      ],
    },
    options: {
      plugins: {
        legend: {
          position: "bottom",
          labels: { padding: 16, usePointStyle: true },
        },
        tooltip: {
          callbacks: {
            label: function (ctx) {
              var total = ctx.dataset.data.reduce(function (a, b) {
                return a + b;
              }, 0);
              var pct = Math.round((ctx.parsed / total) * 100);
              return (
                " " + ctx.label + ": " + ctx.parsed + " cây (" + pct + "%)"
              );
            },
          },
        },
      },
      cutout: "60%",
    },
  });

  // Species x Health stacked bar
  destroyChart("speciesHealth");
  var speciesList = [];
  var seen = {};
  TREES.forEach(function (t) {
    if (!seen[t.species]) {
      seen[t.species] = true;
      speciesList.push(t.species);
    }
  });
  speciesList.sort();
  var statusList = [];
  var seenS = {};
  TREES.forEach(function (t) {
    if (!seenS[t.status]) {
      seenS[t.status] = true;
      statusList.push(t.status);
    }
  });
  var stackedDS = statusList.map(function (s) {
    return {
      label: statusLabel(s),
      data: speciesList.map(function (sp) {
        return TREES.filter(function (t) {
          return t.species === sp && t.status === s;
        }).length;
      }),
      backgroundColor: statusColor(s),
      borderRadius: 4,
    };
  });
  charts.speciesHealth = new Chart(
    document.getElementById("speciesHealthChart"),
    {
      type: "bar",
      data: { labels: speciesList, datasets: stackedDS },
      options: {
        plugins: {
          legend: { position: "bottom", labels: { usePointStyle: true } },
        },
        scales: {
          x: { stacked: true },
          y: { stacked: true, beginAtZero: true, ticks: { stepSize: 1 } },
        },
      },
    },
  );

  // Overview species donut
  destroyChart("overviewSpecies");
  var speciesCounts = {};
  TREES.forEach(function (t) {
    speciesCounts[t.species] = (speciesCounts[t.species] || 0) + 1;
  });
  var colors = [
    "#2d6a4f",
    "#40916c",
    "#52b788",
    "#74c69d",
    "#95d5b2",
    "#b7e4c7",
    "#d8f3dc",
    "#1b4332",
    "#081c15",
  ];
  charts.overviewSpecies = new Chart(
    document.getElementById("overviewSpeciesChart"),
    {
      type: "doughnut",
      data: {
        labels: Object.keys(speciesCounts),
        datasets: [
          {
            data: Object.values(speciesCounts),
            backgroundColor: colors.slice(0, Object.keys(speciesCounts).length),
            borderWidth: 2,
            borderColor: "#fff",
          },
        ],
      },
      options: {
        plugins: {
          legend: {
            position: "right",
            labels: {
              padding: 8,
              usePointStyle: true,
              font: { size: 11 },
            },
          },
        },
        cutout: "55%",
      },
    },
  );
}

// ─── ALERT PAGE ────────────────────────────────
function renderAlertPage() {
  var critical = ALERTS.filter(function (a) {
    return a.priority === "critical";
  }).length;
  var warning = ALERTS.filter(function (a) {
    return a.priority === "warning";
  }).length;
  document.getElementById("alertCriticalCount").textContent = critical;
  document.getElementById("alertWarningCount").textContent = warning;
  document.getElementById("alertHealthyCount").textContent = STATS.good;
  document.getElementById("alertTotal").textContent =
    ALERTS.length + " cảnh báo";

  var el = document.getElementById("alertList");
  if (!ALERTS.length) {
    el.innerHTML =
      '<div class="empty-state" style="padding:60px"><div class="icon">✅</div><p>Tất cả cây đều khỏe mạnh! Không có cảnh báo nào.</p></div>';
    return;
  }
  el.innerHTML = ALERTS.map(function (a) {
    var coordHtml =
      a.lat && a.lng
        ? '<div class="alert-desc" style="margin-top:4px">📍 ' +
          a.lat.toFixed(5) +
          ", " +
          a.lng.toFixed(5) +
          "</div>"
        : "";
    return (
      '<div class="alert-item" onclick="openTreeDetail(\'' +
      a.tree_id +
      "')\">" +
      '<div class="alert-icon ' +
      a.priority +
      '">' +
      (a.priority === "critical" ? "🚨" : "⚠️") +
      "</div>" +
      '<div class="alert-content">' +
      '<div class="alert-title">Cây ' +
      a.tree_id +
      " — " +
      a.species +
      "</div>" +
      '<div class="alert-desc">' +
      a.message +
      "</div>" +
      coordHtml +
      "</div>" +
      '<span class="alert-priority ' +
      a.priority +
      '">' +
      (a.priority === "critical" ? "Nghiêm trọng" : "Cảnh báo") +
      "</span>" +
      "</div>"
    );
  }).join("");
}

// ─── ANALYTICS PAGE ────────────────────────────
function renderAnalyticsPage() {
  var a = ANALYTICS;
  document.getElementById("analyticsKPIs").innerHTML =
    '<div class="kpi">' +
    '<div class="kpi-icon blue">📏</div>' +
    '<div class="kpi-info">' +
    '<div class="kpi-value">' +
    (a.height ? a.height.avg : 0) +
    "</div>" +
    '<div class="kpi-label">Chiều cao TB (m)</div>' +
    '<div class="kpi-trend">' +
    (a.height ? a.height.min : 0) +
    " — " +
    (a.height ? a.height.max : 0) +
    " m</div>" +
    "</div>" +
    "</div>" +
    '<div class="kpi">' +
    '<div class="kpi-icon green">🌿</div>' +
    '<div class="kpi-info">' +
    '<div class="kpi-value">' +
    (a.diameter ? a.diameter.avg : 0) +
    "</div>" +
    '<div class="kpi-label">Đường kính TB (cm)</div>' +
    '<div class="kpi-trend">' +
    (a.diameter ? a.diameter.min : 0) +
    " — " +
    (a.diameter ? a.diameter.max : 0) +
    " cm</div>" +
    "</div>" +
    "</div>" +
    '<div class="kpi">' +
    '<div class="kpi-icon purple">🍃</div>' +
    '<div class="kpi-info">' +
    '<div class="kpi-value">' +
    (a.canopy ? a.canopy.avg : 0) +
    "</div>" +
    '<div class="kpi-label">Tán lá TB (m)</div>' +
    '<div class="kpi-trend">Tổng: ' +
    (a.canopy ? a.canopy.total_coverage : 0) +
    " m</div>" +
    "</div>" +
    "</div>" +
    '<div class="kpi">' +
    '<div class="kpi-icon orange">📅</div>' +
    '<div class="kpi-info">' +
    '<div class="kpi-value">' +
    STATS.avg_age +
    "</div>" +
    '<div class="kpi-label">Tuổi TB (năm)</div>' +
    "</div>" +
    "</div>";

  // Height chart
  destroyChart("height");
  var hd = a.height && a.height.distribution ? a.height.distribution : {};
  charts.height = new Chart(document.getElementById("heightChart"), {
    type: "bar",
    data: {
      labels: Object.keys(hd),
      datasets: [
        {
          label: "Số cây",
          data: Object.values(hd),
          backgroundColor: "#52b788",
          borderRadius: 6,
        },
      ],
    },
    options: {
      plugins: { legend: { display: false } },
      scales: { y: { beginAtZero: true, ticks: { stepSize: 1 } } },
    },
  });

  // Diameter chart
  destroyChart("diameter");
  var dd = a.diameter && a.diameter.distribution ? a.diameter.distribution : {};
  charts.diameter = new Chart(document.getElementById("diameterChart"), {
    type: "bar",
    data: {
      labels: Object.keys(dd),
      datasets: [
        {
          label: "Số cây",
          data: Object.values(dd),
          backgroundColor: "#74c69d",
          borderRadius: 6,
        },
      ],
    },
    options: {
      plugins: { legend: { display: false } },
      scales: { y: { beginAtZero: true, ticks: { stepSize: 1 } } },
    },
  });

  // Age chart
  destroyChart("age");
  var ages = TREES.map(function (t) {
    return Number(t.age) || 0;
  });
  var maxAge = Math.max.apply(null, ages.concat([1]));
  var bins = [];
  for (var i = 1; i <= maxAge; i++) bins.push(i);
  var ageData = bins.map(function (b) {
    return ages.filter(function (a2) {
      return a2 === b;
    }).length;
  });
  charts.age = new Chart(document.getElementById("ageChart"), {
    type: "bar",
    data: {
      labels: bins.map(function (b) {
        return b + " năm";
      }),
      datasets: [
        {
          label: "Số cây",
          data: ageData,
          backgroundColor: "#40916c",
          borderRadius: 6,
        },
      ],
    },
    options: {
      plugins: { legend: { display: false } },
      scales: { y: { beginAtZero: true, ticks: { stepSize: 1 } } },
    },
  });

  // Canopy by species
  destroyChart("canopy");
  var spList = [];
  var spSeen = {};
  TREES.forEach(function (t) {
    if (!spSeen[t.species]) {
      spSeen[t.species] = true;
      spList.push(t.species);
    }
  });
  spList.sort();
  var canopyAvg = spList.map(function (sp) {
    var trees = TREES.filter(function (t) {
      return t.species === sp && t.canopy;
    });
    if (!trees.length) return 0;
    return parseFloat(
      (
        trees.reduce(function (s, t) {
          return s + Number(t.canopy);
        }, 0) / trees.length
      ).toFixed(1),
    );
  });
  charts.canopy = new Chart(document.getElementById("canopyChart"), {
    type: "bar",
    data: {
      labels: spList,
      datasets: [
        {
          label: "Tán lá TB (m)",
          data: canopyAvg,
          backgroundColor: "#95d5b2",
          borderRadius: 6,
        },
      ],
    },
    options: {
      plugins: { legend: { display: false } },
      scales: { y: { beginAtZero: true } },
    },
  });

  // Species detail table
  var tBody = document.getElementById("speciesTableBody");
  var speciesHealth = a.species_health || {};
  tBody.innerHTML = spList
    .map(function (sp) {
      var sh = speciesHealth[sp] || {
        good: 0,
        not_good: 0,
        die: 0,
        total: 0,
      };
      var trees = TREES.filter(function (t) {
        return t.species === sp;
      });
      var avgAge = trees.length
        ? (
            trees.reduce(function (s, t) {
              return s + (Number(t.age) || 0);
            }, 0) / trees.length
          ).toFixed(1)
        : "—";
      var hTrees = trees.filter(function (t) {
        return t.height;
      });
      var avgH = hTrees.length
        ? (
            hTrees.reduce(function (s, t) {
              return s + (Number(t.height) || 0);
            }, 0) / hTrees.length
          ).toFixed(1)
        : "—";
      var dTrees = trees.filter(function (t) {
        return t.diameter;
      });
      var avgD = dTrees.length
        ? (
            dTrees.reduce(function (s, t) {
              return s + (Number(t.diameter) || 0);
            }, 0) / dTrees.length
          ).toFixed(1)
        : "—";
      var pct = sh.total ? Math.round(((sh.good || 0) / sh.total) * 100) : 0;
      var pctColor =
        pct >= 80 ? "var(--good)" : pct >= 50 ? "var(--warn)" : "var(--danger)";
      return (
        "<tr>" +
        "<td><strong>" +
        sp +
        "</strong></td>" +
        "<td>" +
        sh.total +
        "</td>" +
        '<td style="color:var(--good)">' +
        (sh.good || 0) +
        "</td>" +
        '<td style="color:var(--warn)">' +
        (sh.not_good || 0) +
        "</td>" +
        '<td style="color:var(--danger)">' +
        (sh.die || 0) +
        "</td>" +
        '<td><span style="color:' +
        pctColor +
        ';font-weight:600">' +
        pct +
        "%</span></td>" +
        "<td>" +
        avgAge +
        "</td>" +
        "<td>" +
        avgH +
        "</td>" +
        "<td>" +
        avgD +
        "</td>" +
        "</tr>"
      );
    })
    .join("");
}

// ─── MAPS ──────────────────────────────────────
var tileLayers = {
  street: {
    url: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
    attr: "© OpenStreetMap",
  },
  satellite: {
    url: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
    attr: "© Esri",
  },
  topo: {
    url: "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png",
    attr: "© OpenTopoMap",
  },
};

function createMapMarker(t) {
  var color =
    t.status === "good"
      ? "#2d6a4f"
      : t.status === "not_good"
        ? "#f77f00"
        : "#d62828";
  var icon = L.divIcon({
    className: "",
    html:
      '<div style="width:16px;height:16px;border-radius:50%;background:' +
      color +
      ';border:2.5px solid #fff;box-shadow:0 0 6px rgba(0,0,0,.4);cursor:pointer"></div>',
    iconSize: [16, 16],
    iconAnchor: [8, 8],
  });
  var imgHtml =
    t.images && t.images.length
      ? '<br><img alt="Hình ảnh cây " + t.tree_id + " src="' +
        t.images[0] +
        '" style="width:140px;border-radius:6px;margin-top:6px" onerror="this.style.display=\'none\'">'
      : "";
  var marker = L.marker([t.lat, t.lng], { icon: icon });
  marker.bindPopup(
    '<div style="min-width:160px">' +
      '<b style="font-size:.9rem">' +
      t.tree_id +
      " — " +
      t.species +
      "</b><br>" +
      '<span style="font-size:.8rem">' +
      "Tuổi: " +
      t.age +
      " năm | " +
      statusLabel(t.status) +
      "<br>" +
      "Cao: " +
      t.height +
      "m | ĐK: " +
      t.diameter +
      "cm<br>" +
      "Tán lá: " +
      t.canopy +
      "m" +
      "</span>" +
      imgHtml +
      '<br><a href="#" onclick="openTreeDetail(\'' +
      t.tree_id +
      '\');return false" style="color:#2d6a4f;font-size:.78rem;font-weight:600">Xem chi tiết →</a>' +
      "</div>",
  );
  return marker;
}

function renderOverviewMap() {
  var pts = TREES.filter(function (t) {
    return t.lat && t.lng;
  });
  if (!pts.length) return;

  if (overviewMap) {
    overviewMap.remove();
    overviewMap = null;
  }

  overviewMap = L.map("overviewMap").setView([pts[0].lat, pts[0].lng], 17);
  L.tileLayer(tileLayers.street.url, {
    attribution: tileLayers.street.attr,
  }).addTo(overviewMap);

  var cluster = L.markerClusterGroup({ maxClusterRadius: 40 });
  pts.forEach(function (t) {
    cluster.addLayer(createMapMarker(t));
  });
  overviewMap.addLayer(cluster);

  var bounds = L.latLngBounds(
    pts.map(function (t) {
      return [t.lat, t.lng];
    }),
  );
  overviewMap.fitBounds(bounds.pad(0.15));

  addMapLegend(overviewMap);
}

function renderFullMap() {
  var pts = TREES.filter(function (t) {
    return t.lat && t.lng;
  });
  if (!pts.length) return;

  if (leafletMap) {
    leafletMap.remove();
    leafletMap = null;
  }

  leafletMap = L.map("map").setView([pts[0].lat, pts[0].lng], 17);
  tileLayer = L.tileLayer(tileLayers[currentLayer].url, {
    attribution: tileLayers[currentLayer].attr,
    maxZoom: 19,
  }).addTo(leafletMap);

  renderMapMarkers();
  addMapLegend(leafletMap);
}

function renderMapMarkers() {
  if (!leafletMap) return;
  if (mapMarkers) leafletMap.removeLayer(mapMarkers);

  var pts = TREES.filter(function (t) {
    return t.lat && t.lng;
  });
  if (mapSpeciesFilter) {
    pts = pts.filter(function (t) {
      return t.species === mapSpeciesFilter;
    });
  }
  if (mapStatusFilter) {
    pts = pts.filter(function (t) {
      return t.status === mapStatusFilter;
    });
  }

  if (clusterEnabled) {
    mapMarkers = L.markerClusterGroup({ maxClusterRadius: 40 });
  } else {
    mapMarkers = L.layerGroup();
  }

  pts.forEach(function (t) {
    mapMarkers.addLayer(createMapMarker(t));
  });
  leafletMap.addLayer(mapMarkers);

  if (pts.length) {
    var bounds = L.latLngBounds(
      pts.map(function (t) {
        return [t.lat, t.lng];
      }),
    );
    leafletMap.fitBounds(bounds.pad(0.15));
  }
}

function addMapLegend(map) {
  var legend = L.control({ position: "bottomright" });
  legend.onAdd = function () {
    var div = L.DomUtil.create("div", "map-legend");
    div.innerHTML =
      "<strong>Chú giải</strong><br>" +
      '<span class="map-legend-dot" style="background:#2d6a4f"></span> Tốt<br>' +
      '<span class="map-legend-dot" style="background:#f77f00"></span> Cần xử lý<br>' +
      '<span class="map-legend-dot" style="background:#d62828"></span> Chết';
    return div;
  };
  legend.addTo(map);
}

function setMapLayer(layer) {
  currentLayer = layer;
  if (tileLayer) leafletMap.removeLayer(tileLayer);
  tileLayer = L.tileLayer(tileLayers[layer].url, {
    attribution: tileLayers[layer].attr,
    maxZoom: 19,
  }).addTo(leafletMap);

  var sel = document.getElementById("mapLayerSelect");
  if (sel) sel.value = layer;
}

function toggleCluster() {
  clusterEnabled = !clusterEnabled;
  document.getElementById("clusterBtn").textContent =
    "Gom nhóm: " + (clusterEnabled ? "Bật" : "Tắt");
  renderMapMarkers();
}

function applyMapFilters() {
  mapSpeciesFilter = document.getElementById("mapSpeciesFilter").value;
  mapStatusFilter = document.getElementById("mapStatusFilter").value;
  renderMapMarkers();
}

function populateMapFilters() {
  var sel = document.getElementById("mapSpeciesFilter");
  if (!sel) return;
  var current = sel.value;
  sel.innerHTML = '<option value="">Tất cả loài cây</option>';
  var spSeen = {};
  var speciesList = [];
  TREES.forEach(function (t) {
    if (t.species && !spSeen[t.species]) {
      spSeen[t.species] = true;
      speciesList.push(t.species);
    }
  });
  speciesList.sort();
  speciesList.forEach(function (s) {
    var o = document.createElement("option");
    o.value = s;
    o.textContent = s;
    if (s === current) o.selected = true;
    sel.appendChild(o);
  });
}

// ─── TABLE (with pagination & sorting) ─────────
function renderTable() {
  var sorted = filteredTrees.slice().sort(function (a, b) {
    var va = a[sortCol],
      vb = b[sortCol];
    if (sortCol === "tree_id") {
      va = parseInt(va) || 0;
      vb = parseInt(vb) || 0;
    } else if (
      ["age", "height", "diameter", "canopy"].indexOf(sortCol) !== -1
    ) {
      va = Number(va) || 0;
      vb = Number(vb) || 0;
    } else {
      va = String(va).toLowerCase();
      vb = String(vb).toLowerCase();
    }
    if (va < vb) return sortDir === "asc" ? -1 : 1;
    if (va > vb) return sortDir === "asc" ? 1 : -1;
    return 0;
  });

  var totalPages = Math.ceil(sorted.length / pageSize) || 1;
  if (currentPage > totalPages) currentPage = totalPages;
  var start = (currentPage - 1) * pageSize;
  var pageData = sorted.slice(start, start + pageSize);

  document.getElementById("resultsCount").textContent =
    sorted.length + " kết quả — Trang " + currentPage + "/" + totalPages;

  document.querySelectorAll("#dataTable th").forEach(function (th) {
    th.classList.remove("sorted-asc", "sorted-desc");
  });

  var tb = document.getElementById("tableBody");
  tb.innerHTML = pageData
    .map(function (t) {
      var badge =
        '<span class="badge ' +
        t.status +
        '">' +
        statusLabel(t.status) +
        "</span>";
      var img =
        t.images && t.images.length
          ? '<img alt="Hình ảnh cây ' +
            t.tree_id +
            '" src="' +
            t.images[0] +
            '" class="img-thumb" onclick="event.stopPropagation();openLightbox(\'' +
            t.images[0] +
            "')\" onerror=\"this.style.display='none'\" />"
          : '<span style="color:var(--muted)">—</span>';
      var lat = t.lat ? t.lat.toFixed(5) : "—";
      var lng = t.lng ? t.lng.toFixed(5) : "—";
      return (
        "<tr onclick=\"openTreeDetail('" +
        t.tree_id +
        '\')" style="cursor:pointer" title="Nhấn để xem chi tiết">' +
        '<td><strong style="color:var(--accent)">' +
        t.tree_id +
        "</strong></td>" +
        "<td>" +
        t.species +
        "</td>" +
        "<td>" +
        t.age +
        "</td>" +
        "<td>" +
        t.height +
        "</td>" +
        "<td>" +
        t.diameter +
        "</td>" +
        "<td>" +
        t.canopy +
        "</td>" +
        "<td>" +
        badge +
        "</td>" +
        '<td style="font-size:.72rem;color:var(--muted)">' +
        lat +
        ", " +
        lng +
        "</td>" +
        "<td>" +
        img +
        "</td>" +
        '<td style="font-size:.75rem">' +
        timeAgo(t.updated_at) +
        "</td>" +
        '<td style="font-size:.75rem">' +
        (t.updated_by || "—") +
        "</td>" +
        "</tr>"
      );
    })
    .join("");

  renderPagination(totalPages);
}

function renderPagination(totalPages) {
  var el = document.getElementById("pagination");
  var showing = Math.min(
    pageSize,
    filteredTrees.length - (currentPage - 1) * pageSize,
  );
  if (showing < 0) showing = 0;
  var html =
    "<span>Hiển thị " + showing + " / " + filteredTrees.length + " cây</span>";
  html += '<div class="pagination-btns">';

  html +=
    '<button class="page-btn" ' +
    (currentPage <= 1 ? "disabled" : "") +
    ' onclick="goToPage(' +
    (currentPage - 1) +
    ')">‹</button>';

  var maxShow = 5;
  var startP = Math.max(1, currentPage - 2);
  var endP = Math.min(totalPages, startP + maxShow - 1);
  if (endP - startP < maxShow - 1) startP = Math.max(1, endP - maxShow + 1);

  if (startP > 1) {
    html += '<button class="page-btn" onclick="goToPage(1)">1</button>';
    if (startP > 2)
      html += '<span style="padding:0 4px;color:var(--muted)">…</span>';
  }
  for (var i = startP; i <= endP; i++) {
    html +=
      '<button class="page-btn ' +
      (i === currentPage ? "active" : "") +
      '" onclick="goToPage(' +
      i +
      ')">' +
      i +
      "</button>";
  }
  if (endP < totalPages) {
    if (endP < totalPages - 1)
      html += '<span style="padding:0 4px;color:var(--muted)">…</span>';
    html +=
      '<button class="page-btn" onclick="goToPage(' +
      totalPages +
      ')">' +
      totalPages +
      "</button>";
  }

  html +=
    '<button class="page-btn" ' +
    (currentPage >= totalPages ? "disabled" : "") +
    ' onclick="goToPage(' +
    (currentPage + 1) +
    ')">›</button>';
  html += "</div>";
  el.innerHTML = html;
}

function goToPage(p) {
  currentPage = p;
  renderTable();
  var tc = document.querySelector(".table-container");
  if (tc) tc.scrollTo(0, 0);
}

function changePageSize() {
  pageSize = parseInt(document.getElementById("pageSizeSelect").value);
  currentPage = 1;
  renderTable();
}

function sortTable(col) {
  if (sortCol === col) {
    sortDir = sortDir === "asc" ? "desc" : "asc";
  } else {
    sortCol = col;
    sortDir = "asc";
  }
  currentPage = 1;
  renderTable();
}

function populateFilters() {
  var speciesSel = document.getElementById("speciesFilter");
  speciesSel.innerHTML = '<option value="">Tất cả loài cây</option>';
  var spSeen = {};
  var speciesList = [];
  TREES.forEach(function (t) {
    if (!spSeen[t.species]) {
      spSeen[t.species] = true;
      speciesList.push(t.species);
    }
  });
  speciesList.sort();
  speciesList.forEach(function (s) {
    var count = TREES.filter(function (t) {
      return t.species === s;
    }).length;
    var o = document.createElement("option");
    o.value = s;
    o.textContent = s + " (" + count + ")";
    speciesSel.appendChild(o);
  });
}

function applyFilters() {
  var q = document.getElementById("searchInput").value.toLowerCase();
  var sp = document.getElementById("speciesFilter").value;
  var st = document.getElementById("statusFilter").value;
  filteredTrees = TREES.slice();
  if (sp)
    filteredTrees = filteredTrees.filter(function (t) {
      return t.species === sp;
    });
  if (st)
    filteredTrees = filteredTrees.filter(function (t) {
      return t.status === st;
    });
  if (q) {
    filteredTrees = filteredTrees.filter(function (t) {
      var searchable = [
        t.tree_id,
        t.species,
        t.age,
        t.height,
        t.diameter,
        t.canopy,
        t.status,
        statusLabel(t.status),
        t.created_by,
        t.updated_by,
      ]
        .join(" ")
        .toLowerCase();
      return searchable.includes(q);
    });
  }
  currentPage = 1;
  renderTable();
}

// ─── TREE DETAIL PANEL ─────────────────────────
function openTreeDetail(treeId) {
  var tree = TREES.find(function (t) {
    return t.tree_id === treeId;
  });
  if (!tree) return;

  document.getElementById("detailTitle").textContent =
    "Cây " + tree.tree_id + " — " + tree.species;

  var statusBar = tree.status;
  var statusMsg =
    tree.status === "good"
      ? "Cây khỏe mạnh"
      : tree.status === "not_good"
        ? "Cần kiểm tra và xử lý"
        : "Cây đã chết — cần thay thế";

  var imagesHtml = "";
  if (tree.images && tree.images.length) {
    imagesHtml =
      '<div class="detail-section">' +
      '<div class="section-label">Hình ảnh</div>' +
      '<div class="detail-images">' +
      tree.images
        .map(function (img) {
          return (
            '<img alt="H\u00ecnh \u1ea3nh c\u00e2y ' +
            tree.tree_id +
            '" src="' +
            img +
            '" onclick="openLightbox(\'' +
            img +
            "')\" onerror=\"this.style.display='none'\" />"
          );
        })
        .join("") +
      "</div>" +
      "</div>";
  }

  var erLinkHtml = "";
  if (tree.event_id) {
    erLinkHtml =
      '<div style="margin-top:10px">' +
      '<a href="https://epictech.pamdas.org/events/' +
      tree.event_id +
      '" target="_blank" ' +
      'class="btn btn-outline btn-sm" style="width:100%;justify-content:center">' +
      "📍 Mở trên EarthRanger" +
      "</a>" +
      "</div>";
  }

  document.getElementById("detailBody").innerHTML =
    '<div class="detail-status-bar ' +
    statusBar +
    '">' +
    '<span class="status-icon">' +
    statusIcon(tree.status) +
    "</span>" +
    '<span class="status-text">' +
    statusMsg +
    "</span>" +
    '<span class="badge ' +
    statusBar +
    '" style="margin-left:auto">' +
    statusLabel(tree.status) +
    "</span>" +
    "</div>" +
    imagesHtml +
    '<div class="detail-section">' +
    '<div class="section-label">Thông tin cơ bản</div>' +
    '<div class="detail-grid">' +
    '<div class="detail-field"><div class="label">Mã cây</div><div class="value">' +
    tree.tree_id +
    "</div></div>" +
    '<div class="detail-field"><div class="label">Loài cây</div><div class="value">' +
    tree.species +
    "</div></div>" +
    '<div class="detail-field"><div class="label">Tuổi</div><div class="value">' +
    tree.age +
    " năm</div></div>" +
    '<div class="detail-field"><div class="label">Tình trạng</div><div class="value">' +
    statusLabel(tree.status) +
    "</div></div>" +
    "</div>" +
    "</div>" +
    '<div class="detail-section">' +
    '<div class="section-label">Kích thước</div>' +
    '<div class="detail-grid">' +
    '<div class="detail-field"><div class="label">Chiều cao</div><div class="value">' +
    (tree.height || "—") +
    " m</div></div>" +
    '<div class="detail-field"><div class="label">Đường kính thân</div><div class="value">' +
    (tree.diameter || "—") +
    " cm</div></div>" +
    '<div class="detail-field"><div class="label">Tán lá</div><div class="value">' +
    (tree.canopy || "—") +
    " m</div></div>" +
    "</div>" +
    "</div>" +
    '<div class="detail-section">' +
    '<div class="section-label">Vị trí</div>' +
    '<div class="detail-grid">' +
    '<div class="detail-field"><div class="label">Vĩ độ</div><div class="value">' +
    (tree.lat || "—") +
    "</div></div>" +
    '<div class="detail-field"><div class="label">Kinh độ</div><div class="value">' +
    (tree.lng || "—") +
    "</div></div>" +
    "</div>" +
    erLinkHtml +
    "</div>" +
    '<div class="detail-section">' +
    '<div class="section-label">Lịch sử</div>' +
    '<div class="detail-grid">' +
    '<div class="detail-field"><div class="label">Ngày tạo</div><div class="value" style="font-size:.8rem">' +
    formatDateTime(tree.created_at) +
    "</div></div>" +
    '<div class="detail-field"><div class="label">Người tạo</div><div class="value">' +
    (tree.created_by || "—") +
    "</div></div>" +
    '<div class="detail-field"><div class="label">Cập nhật lần cuối</div><div class="value" style="font-size:.8rem">' +
    formatDateTime(tree.updated_at) +
    "</div></div>" +
    '<div class="detail-field"><div class="label">Người cập nhật</div><div class="value">' +
    (tree.updated_by || "—") +
    "</div></div>" +
    "</div>" +
    "</div>" +
    '<div class="detail-section">' +
    '<div class="section-label">Hệ thống</div>' +
    '<div class="detail-grid">' +
    '<div class="detail-field"><div class="label">Số sê-ri</div><div class="value" style="font-size:.78rem">' +
    (tree.sn || "—") +
    "</div></div>" +
    '<div class="detail-field"><div class="label">Trạng thái sự kiện</div><div class="value">' +
    (tree.event_state || "—") +
    "</div></div>" +
    '<div class="detail-field" style="grid-column:span 2"><div class="label">Đồng bộ lần cuối</div><div class="value" style="font-size:.78rem">' +
    formatDateTime(tree.synced_at) +
    "</div></div>" +
    "</div>" +
    "</div>";

  document.getElementById("detailPanel").classList.add("open");
  document.getElementById("detailBackdrop").classList.add("active");
}

function closeDetail() {
  document.getElementById("detailPanel").classList.remove("open");
  document.getElementById("detailBackdrop").classList.remove("active");
}

document.addEventListener("keydown", function (e) {
  if (e.key === "Escape") closeDetail();
});

// ─── LAZY LOADERS ──────────────────────────────
var _chartJsPromise = null;
function loadChartJs() {
  if (window.Chart) return Promise.resolve();
  if (_chartJsPromise) return _chartJsPromise;
  _chartJsPromise = new Promise(function (resolve, reject) {
    var s = document.createElement("script");
    s.src = "https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js";
    s.onload = resolve;
    s.onerror = reject;
    document.head.appendChild(s);
  });
  return _chartJsPromise;
}

var _html2pdfPromise = null;
function loadHtml2Pdf() {
  if (window.html2pdf) return Promise.resolve();
  if (_html2pdfPromise) return _html2pdfPromise;
  _html2pdfPromise = new Promise(function (resolve, reject) {
    var s = document.createElement("script");
    s.src =
      "https://cdnjs.cloudflare.com/ajax/libs/html2pdf.js/0.10.1/html2pdf.bundle.min.js";
    s.onload = resolve;
    s.onerror = reject;
    document.head.appendChild(s);
  });
  return _html2pdfPromise;
}

// ─── EXPORTS ───────────────────────────────────
function exportPDF() {
  loadHtml2Pdf().then(function () {
    var el = document.getElementById("reportContent");
    el.classList.add("pdf-mode");
    var opt = {
      margin: [10, 10, 10, 10],
      filename: "Tree_Report_" + new Date().toISOString().slice(0, 10) + ".pdf",
      image: { type: "jpeg", quality: 0.95 },
      html2canvas: { scale: 2, useCORS: true, scrollY: 0 },
      jsPDF: { unit: "mm", format: "a3", orientation: "landscape" },
      pagebreak: { mode: ["avoid-all", "css", "legacy"] },
    };
    html2pdf()
      .set(opt)
      .from(el)
      .save()
      .then(function () {
        el.classList.remove("pdf-mode");
      });
  });
}

function exportCSV() {
  var headers = [
    "ID",
    "Loài",
    "Tuổi",
    "Cao (m)",
    "ĐK thân (cm)",
    "Tán lá (m)",
    "Tình trạng",
    "Lat",
    "Lng",
    "Tạo lúc",
    "Người tạo",
    "Cập nhật",
    "Người CN",
  ];
  var csvRows = [headers.join(",")];
  TREES.forEach(function (t) {
    csvRows.push(
      [
        t.tree_id,
        '"' + t.species + '"',
        t.age,
        t.height,
        t.diameter,
        t.canopy,
        statusLabel(t.status),
        t.lat,
        t.lng,
        '"' + t.created_at + '"',
        '"' + t.created_by + '"',
        '"' + t.updated_at + '"',
        '"' + t.updated_by + '"',
      ].join(","),
    );
  });
  var blob = new Blob(["\uFEFF" + csvRows.join("\n")], {
    type: "text/csv;charset=utf-8;",
  });
  var url = URL.createObjectURL(blob);
  var a = document.createElement("a");
  a.href = url;
  a.download = "Tree_Report_" + new Date().toISOString().slice(0, 10) + ".csv";
  a.click();
  URL.revokeObjectURL(url);
}

// ─── AUTO-REFRESH ──────────────────────────────
var autoRefreshInterval = null;

function startAutoRefresh(minutes) {
  if (autoRefreshInterval) clearInterval(autoRefreshInterval);
  autoRefreshInterval = setInterval(
    function () {
      refreshData();
    },
    minutes * 60 * 1000,
  );
}

// ─── RESPONSIVE ────────────────────────────────
function checkResponsive() {
  var menuBtn = document.getElementById("menuBtn");
  if (window.innerWidth <= 1024) {
    menuBtn.style.display = "inline-flex";
  } else {
    menuBtn.style.display = "none";
    document.getElementById("sidebar").classList.remove("open");
  }
}
window.addEventListener("resize", checkResponsive);

// ─── INIT ──────────────────────────────────────
window.addEventListener("DOMContentLoaded", function () {
  checkResponsive();
  refreshData();
  startAutoRefresh(5);
});
