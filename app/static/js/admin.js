/* admin.js — Admin dashboard mock data & inline-SVG chart */

(function () {
  "use strict";

  // ── Mock data ──────────────────────────────────────────────────────────────

  const KPI = [
    { label: "Total Users",      value: 1284,  delta: "+12%",  up: true  },
    { label: "Active This Week", value: 348,   delta: "+7%",   up: true  },
    { label: "Premium Users",    value: 89,    delta: "+3%",   up: true  },
    { label: "Flagged Accounts", value: 3,     delta: "-1",    up: false },
  ];

  const CHART_DATA = {
    labels: ["Dec", "Jan", "Feb", "Mar", "Apr", "May"],
    values: [820, 940, 870, 1050, 1180, 1284],
  };

  const USERS = [
    { name: "Alice Nguyen",    email: "alice@contoso.com",   role: "Admin",   last: "2 min ago",    active: true  },
    { name: "Bob Martínez",    email: "bob@contoso.com",     role: "Premium", last: "18 min ago",   active: true  },
    { name: "Chloe Laurent",   email: "chloe@fabrikam.com",  role: "Premium", last: "1 hour ago",   active: true  },
    { name: "David Park",      email: "david@fabrikam.com",  role: "User",    last: "3 hours ago",  active: true  },
    { name: "Eva Romero",      email: "eva@contoso.com",     role: "User",    last: "Yesterday",    active: false },
    { name: "Finn O'Brien",    email: "finn@contoso.com",    role: "User",    last: "2 days ago",   active: false },
  ];

  const ROLE_BADGE_CLASS = { Admin: "role-admin", Premium: "role-premium", User: "role-regular" };

  // ── KPI cards ──────────────────────────────────────────────────────────────

  const kpiGrid = document.getElementById("kpi-grid");
  if (kpiGrid) {
    KPI.forEach(({ label, value, delta, up }) => {
      kpiGrid.insertAdjacentHTML("beforeend", `
        <div class="kpi-card">
          <div class="kpi-label">${label}</div>
          <div class="kpi-value">${value.toLocaleString()}</div>
          <div class="kpi-delta ${up ? "" : "down"}">${delta} vs last month</div>
        </div>
      `);
    });
  }

  // ── Animated counters ─────────────────────────────────────────────────────

  const countEls = {
    regular: document.getElementById("count-regular"),
    premium: document.getElementById("count-premium"),
    admin:   document.getElementById("count-admin"),
  };

  const counts = { regular: 0, premium: 0, admin: 0 };
  USERS.forEach((u) => {
    if (u.role === "User")    counts.regular++;
    if (u.role === "Premium") counts.premium++;
    if (u.role === "Admin")   counts.admin++;
  });

  function animateCount(el, target) {
    if (!el) return;
    let current = 0;
    const step = Math.ceil(target / 20);
    const timer = setInterval(() => {
      current = Math.min(current + step, target);
      el.textContent = current;
      if (current >= target) clearInterval(timer);
    }, 50);
  }

  animateCount(countEls.regular, counts.regular);
  animateCount(countEls.premium, counts.premium);
  animateCount(countEls.admin,   counts.admin);

  // ── Inline SVG bar chart ──────────────────────────────────────────────────

  const chartContainer = document.getElementById("admin-chart");
  if (chartContainer) {
    const W = 660, H = 180, PAD = { top: 20, right: 20, bottom: 36, left: 48 };
    const plotW = W - PAD.left - PAD.right;
    const plotH = H - PAD.top - PAD.bottom;
    const maxVal = Math.max(...CHART_DATA.values);
    const n = CHART_DATA.values.length;
    const barW = Math.floor(plotW / n * 0.5);
    const gap  = plotW / n;

    const barColor = "#6366f1";
    const lineColor = "#8b5cf6";

    // Bar x-centres
    const xs = CHART_DATA.values.map((_, i) => PAD.left + gap * i + gap / 2);
    const ys = CHART_DATA.values.map((v) => PAD.top + plotH - (v / maxVal) * plotH);

    // Build bars
    let bars = "";
    CHART_DATA.values.forEach((v, i) => {
      const barH = (v / maxVal) * plotH;
      bars += `<rect x="${xs[i] - barW / 2}" y="${ys[i]}" width="${barW}"
        height="${barH}" rx="4" fill="${barColor}" opacity="0.2"/>`;
    });

    // Build area path
    const linePts = xs.map((x, i) => `${i === 0 ? "M" : "L"}${x},${ys[i]}`).join(" ");
    const areaPts = linePts +
      ` L${xs[n-1]},${PAD.top + plotH} L${xs[0]},${PAD.top + plotH} Z`;

    // Y-axis labels
    let yLabels = "";
    for (let i = 0; i <= 4; i++) {
      const yVal = Math.round((maxVal / 4) * i);
      const y = PAD.top + plotH - (yVal / maxVal) * plotH;
      yLabels += `<text x="${PAD.left - 8}" y="${y + 4}" text-anchor="end"
        font-size="10" fill="var(--muted)">${yVal.toLocaleString()}</text>
        <line x1="${PAD.left}" y1="${y}" x2="${PAD.left + plotW}" y2="${y}"
          stroke="var(--border)" stroke-width="1"/>`;
    }

    // X-axis labels & dots
    let xLabels = "", dots = "";
    CHART_DATA.labels.forEach((lbl, i) => {
      xLabels += `<text x="${xs[i]}" y="${PAD.top + plotH + 20}" text-anchor="middle"
        font-size="11" fill="var(--muted)">${lbl}</text>`;
      dots += `<circle cx="${xs[i]}" cy="${ys[i]}" r="5"
        fill="${lineColor}" stroke="var(--surface)" stroke-width="2">
        <title>${lbl}: ${CHART_DATA.values[i].toLocaleString()}</title>
      </circle>`;
    });

    const svg = `
      <svg viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg"
           style="width:100%;font-family:var(--font);" role="img" aria-label="Monthly active users chart">
        <defs>
          <linearGradient id="area-fill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="${lineColor}" stop-opacity="0.25"/>
            <stop offset="100%" stop-color="${lineColor}" stop-opacity="0"/>
          </linearGradient>
        </defs>
        ${yLabels}
        ${bars}
        <path d="${areaPts}" fill="url(#area-fill)"/>
        <path d="${linePts}" fill="none" stroke="${lineColor}" stroke-width="2.5"
              stroke-linecap="round" stroke-linejoin="round"/>
        ${dots}
        ${xLabels}
      </svg>`;

    chartContainer.innerHTML = svg;
  }

  // ── Users table ───────────────────────────────────────────────────────────

  const tbody = document.getElementById("users-tbody");
  if (tbody) {
    USERS.forEach(({ name, email, role, last, active }) => {
      const badgeCls = ROLE_BADGE_CLASS[role] || "";
      tbody.insertAdjacentHTML("beforeend", `
        <tr>
          <td><strong>${name}</strong></td>
          <td style="color:var(--muted)">${email}</td>
          <td><span class="badge ${badgeCls}">${role}</span></td>
          <td style="color:var(--muted)">${last}</td>
          <td><span class="status-dot ${active ? "" : "inactive"}">${active ? "Active" : "Inactive"}</span></td>
        </tr>
      `);
    });
  }
})();
