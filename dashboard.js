import { createApp } from 'https://cdnjs.cloudflare.com/ajax/libs/vue/3.5.13/vue.esm-browser.min.js';

createApp({
  data() {
    return {
      serviceFolder: '/ref/api/v1/toolbox/flex/',
      metrics: { TOTAL: 0, PENDING: 0, APPROVED: 0, MODIFICATION: 0, DECLINED: 0 },

      statusChart: null,            // (already used for the bar)
  statusOptions: [],            // dropdown list for STATUS
  filters: {
  REQUESTID: '',
  FACILITYID: '',
  FACILITYNAME: '',
  HOURSPERWEEK: '',
  CRAFT: '',
  LABOURDISTRIBUTIONCODE: '',
  OPERATIONNUMBER: '',
  JUSTIFICATION: '',
  STARTDATE: '',
  ENDDATE: '',
  CREATEDBY: '',
  USER_NAME: '',
  CREATEDON: '',
  STATUS: '',
  COMMENT: ''
},
compactView: true,            // NEW: default like admin
shrinkToFit: false,           // NEW
filterMenu: { open:false, field:'', x:0, y:0 }, // NEW

facilityData: [],
trendData: [],
flexRequests: [],
userDisplayHeader: '',
officeName: '',
fiscalYear: '',
week:'',

facilities: [],                       // list of facilities user can access
bannerMenu: { open:false, x:0, y:0 }, // banner popover placement
userAceid: '',
selectedRequest: null,
weekOptions: [],
showEditModal: false,
editForm: { requestId: null, hours: null, justification: '', startDate: '', endDate: '', wk_start: '', wk_end:'' },
editStatus: '',
editStatusOK: false
    };
  },


computed: {
  filteredRequests() {
    const rows = Array.isArray(this.flexRequests) ? this.flexRequests : [];
    const f = this.filters;
    const match = (val, filter) =>
      !filter || String(val ?? '').toLowerCase().includes(String(filter).toLowerCase());

    return rows.filter((r) => {
      if (!r || typeof r !== 'object') return false;
      const userName = `${r.USER_FNAME || ''} ${r.USER_LNAME || ''}`.trim();

      return (
        match(r.REQUESTID,               f.REQUESTID) &&
        match(r.FACILITYID,              f.FACILITYID) &&
        match(r.FACILITYNAME,            f.FACILITYNAME) &&
        match(r.HOURSPERWEEK,            f.HOURSPERWEEK) &&
        match(r.CRAFT,                   f.CRAFT) &&
        match(r.LABOURDISTRIBUTIONCODE,  f.LABOURDISTRIBUTIONCODE) &&
        match(r.OPERATIONNUMBER,         f.OPERATIONNUMBER) &&
        match(r.JUSTIFICATION,           f.JUSTIFICATION) &&
        match(r.STARTDATE,               f.STARTDATE) &&
        match(r.ENDDATE,                 f.ENDDATE) &&
        match(r.CREATEDBY,               f.CREATEDBY) &&
        match(userName,                  f.USER_NAME) &&
        match(r.CREATEDON,               f.CREATEDON) &&
        (!f.STATUS || String(r.STATUS || '').toLowerCase() === f.STATUS.toLowerCase()) &&
        match(r.COMMENT,                 f.COMMENT)
      );
    });
  }
},





  methods: {
    // Authentication & data fetching (unchanged)
    // async authenticate() {
    //   try {
    //     await axios.get(`/ref/api/v1/authenticate.cfc?method=getUserAuth`).then((res) => {
    //       console.log('response data: ', res.data);
    //       if (res.data) {
    //         this.userDisplayHeader = `${res.data.first} ${
    //           res.data.last
    //         } (${res.data.aceid.toUpperCase()})`;
    //       }
    //     });
    //   } catch (e) {
    //     console.error('Auth error', e);
    //   }
    // },


   
      async authenticate() {
  try {
    const res = await axios.get(`/ref/api/v1/authenticate.cfc?method=getUserAuth`);
    if (res.data) {
      this.userDisplayHeader = `${res.data.first} ${res.data.last} (${res.data.aceid.toUpperCase()})`;
      this.userAceid = res.data.aceid || '';
      if (this.userAceid) await this.getMyFacilities(); // load facilities for banner
    }
  } catch (e) {
    console.error('Auth error', e);
  }
},


async getMyFacilities() {
  try {
    const res = await axios.get(
      `${this.serviceFolder}dashboard.cfc?method=getMyFacilities&userid=${encodeURIComponent(this.userAceid)}`
    );
    this.facilities = Array.isArray(res.data) ? res.data : [];

    // If server header doesn't give us officeName and there is only one facility, show it
    if ((!this.officeName || !this.officeName.trim()) && this.facilities.length === 1) {
      const f = this.facilities[0];
      this.officeName = f.B_FIN_NAME || this.officeName;
    }
  } catch (e) {
    console.error('Facilities error', e);
    this.facilities = [];
  }
},


async loadWeekOptions() {
  try {
    const res = await axios.get(`${this.serviceFolder}flex.cfc?method=getWeekOptions&returnformat=json`);
    if (res.data) {
      const raw = res.data.DATA || res.data.data || [];
      const FMT = [
        'YYYY-MM-DD',
        'YYYY-MM-DD HH:mm',
        'YYYY-MM-DD HH:mm:ss',
        'YYYY-MM-DD HH:mm:ss.SSS',
        'YYYY-MM-DDTHH:mm:ssZ',
        'YYYY-MM-DDTHH:mm:ss.SSSZ',
        'MM/DD/YYYY'
      ];
      const toISO = (v) => {
        if (!v) return '';
        if (typeof v === 'number') {
          const ms = v < 1e12 ? v * 1000 : v;
          return moment(ms).format('YYYY-MM-DD');
        }
        let m = moment(v, FMT, true);
        if (!m.isValid()) m = moment.parseZone(v);
        return m.isValid() ? m.format('YYYY-MM-DD') : '';
      };
      // raw row: [fiscalYear, week, startDate, endDate]
      this.weekOptions = raw.map(row => [row[0], row[1], toISO(row[2]), toISO(row[3])]);
    }
  } catch (e) {
    console.error("Couldn't load weeks", e);
    this.weekOptions = [];
  }
},



asDate(v) {
  if (!v) return null;
  const FMT = [
    'YYYY-MM-DD',
    'YYYY-MM-DD HH:mm',
    'YYYY-MM-DD HH:mm:ss',
    'YYYY-MM-DD HH:mm:ss.SSS',
    'YYYY-MM-DDTHH:mm:ssZ',
    'YYYY-MM-DDTHH:mm:ss.SSSZ'
  ];
  let m = moment(v, FMT, true);
  if (!m.isValid()) m = moment.parseZone(v);
  return m.isValid() ? m.toDate() : null;
},

onEditStartChange() {
  // keep startDate mirrored to wk_start
  this.editForm.startDate = this.editForm.wk_start || '';
  const s = this.asDate(this.editForm.wk_start);
  const e = this.asDate(this.editForm.wk_end);
  if (s && e && e < s) {
    // nudge end up to start
    this.editForm.wk_end   = this.editForm.wk_start;
    this.editForm.endDate  = this.editForm.wk_end;
  }
},

onEditEndChange() {
  // keep endDate mirrored to wk_end
  this.editForm.endDate = this.editForm.wk_end || '';
  const s = this.asDate(this.editForm.wk_start);
  const e = this.asDate(this.editForm.wk_end);
  if (s && e && e < s) {
    // show a quick guard; you can style/message if you want
    this.editForm.wk_end  = this.editForm.wk_start;
    this.editForm.endDate = this.editForm.wk_end;
  }
},



    async fetchDashboard() {
      try {
        const res = await axios.get(
          `${this.serviceFolder}dashboard.cfc?method=getDashboardData&userid=${encodeURIComponent(this.userAceid)}`
        );
        this.metrics = res.data;
        this.renderChart();
      } catch (e) {
        console.error('Dashboard load error', e);
      }
    },


    async fetchHeaderData() {
  try {
    const res = await axios.get(
      `${this.serviceFolder}dashboard.cfc?method=getHeaderData&userid=${encodeURIComponent(this.userAceid)}`
    );
    this.officeName = res.data.officeName || this.officeName || '';
    this.fiscalYear = res.data.fiscalYear || '';
    this.week       = res.data.week || '';

    // client fallback if needed
    if (!this.fiscalYear || !this.week) {
      const x = this.computeClientFYWeek();
      if (!this.fiscalYear) this.fiscalYear = x.fy;
      if (!this.week)       this.week       = x.week;
    }
  } catch (e) {
    console.error('Header load error', e);
    const x = this.computeClientFYWeek();
    // fallback if network error
    if (!this.fiscalYear) this.fiscalYear = x.fy;
    if (!this.week)       this.week       = x.week;
  }
},


openBannerMenu(evt) {
  const wrap = this.$refs.bannerWrap;
  if (!wrap) return;
  const b = evt.currentTarget.getBoundingClientRect();
  const w = wrap.getBoundingClientRect();
  // position relative to banner
  this.bannerMenu.x = (b.left - w.left);
  this.bannerMenu.y = (b.bottom - w.top) + 6;
  this.bannerMenu.open = true;
  evt.stopPropagation();
},
gotoFacility(f) {
  if (!f) return;

  // update banner text
  this.officeName = f.B_FIN_NAME || this.officeName;
  // optional: if you later add filters on dashboard, set them here
  // e.g., this.filters.FACILITYID = String(f.B_FIN_NBR || '');
  if (this.filters && Object.prototype.hasOwnProperty.call(this.filters, 'FACILITYID')) {
    this.filters.FACILITYID = String(f.B_FIN_NBR || '');
  }
  this.bannerMenu.open = false;
},
_onDocClickBanner(e) {
  if (!this.bannerMenu.open) return;
  const pop = this.$refs.bannerMenuRef;
  if (pop && pop.contains(e.target)) return; // clicks inside popover keep it open
  // ignore clicks on the trigger itself
  if (e.target && e.target.closest && e.target.closest('[title="View all facilities"]')) return;
  this.bannerMenu.open = false;
},



   computeClientFYWeek() {
  const today = new Date();
  const y = today.getFullYear();

  const sept30 = new Date(y, 8, 30); // Sep
  const dow = sept30.getDay();       // 0=Sun..6=Sat
  const backDays = (dow === 6 ? 0 : (dow + 1)); // days since Saturday
  const lastSat = new Date(sept30); lastSat.setDate(sept30.getDate() - backDays);

  let fyStart = lastSat;
  if (today < lastSat) {
    const prevSept30 = new Date(y - 1, 8, 30);
    const prevDow = prevSept30.getDay();
    const prevBack = (prevDow === 6 ? 0 : (prevDow + 1));
    fyStart = new Date(prevSept30); fyStart.setDate(prevSept30.getDate() - prevBack);
  }

  const fy = fyStart.getFullYear() + 1;

  const startUTC = Date.UTC(fyStart.getFullYear(), fyStart.getMonth(), fyStart.getDate());
  const todayUTC = Date.UTC(today.getFullYear(), today.getMonth(), today.getDate());
  const days = Math.floor((todayUTC - startUTC) / (1000 * 60 * 60 * 24));
  const week = 1 + Math.floor(days / 7);

  return { fy, week };
},


// ADD inside methods:{ ... }
async saveEdit() {
  try {
    const rid = this.editForm.requestId;
    if (!rid) {
      this.editStatusOK = false;
      this.editStatus = 'Missing RequestID.';
      return;
    }

    // Normalize fields only if provided/changed
    const toISO = (v) => (v ? String(v).slice(0, 10) : '');
    const numOrEmpty = (v) => (v === null || v === undefined || v === '' ? '' : String(v));

    const fd = new FormData();
    fd.append('requestId', String(rid));

    // Only append fields the user actually edited; CF won't update missing ones
    if (this.editForm.hours !== null && this.editForm.hours !== undefined && this.editForm.hours !== '') {
      fd.append('hours', numOrEmpty(this.editForm.hours));
    }
    if (this.editForm.justification && this.editForm.justification.trim().length) {
      fd.append('justification', this.editForm.justification.trim());
    }
    if (this.editForm.startDate) {
      fd.append('startDate', toISO(this.editForm.startDate)); // YYYY-MM-DD
    }
    if (this.editForm.endDate) {
      fd.append('endDate', toISO(this.editForm.endDate));     // YYYY-MM-DD
    }

    // Send as multipart/form-data (CF classic path)
    const url = `${this.serviceFolder}dashboard.cfc?method=updateUserRequest&returnformat=json&userid=${encodeURIComponent(this.userAceid)}`;
    const res = await axios.post(url, fd, { validateStatus: () => true });

    console.log('updateUserRequest →', res.status, res.data);

    // Surface server errors clearly
    if (res.status !== 200 || !res.data || res.data.SUCCESS !== true) {
      const msg = (res.data && (res.data.MESSAGE || res.data.DETAILS)) || `Save failed (HTTP ${res.status})`;
      this.editStatusOK = false;
      this.editStatus = msg;
      alert(msg); // make it obvious in UI
      return;
    }

    // Success → patch the row from the authoritative server payload
    const data = res.data.DATA || {};
    const idx = this.flexRequests.findIndex(r => r.REQUESTID === data.REQUESTID);
    if (idx >= 0) this.flexRequests[idx] = { ...this.flexRequests[idx], ...data };

    this.editStatusOK = true;
    this.editStatus = 'Saved.';
    this.showEditModal = false;
  } catch (e) {
    console.error('saveEdit error', e);
    this.editStatusOK = false;
    this.editStatus = 'Save failed.';
    alert('Save failed. See console for details.');
  }
},

    //New line below
    // async fetchDashboard(){
    //   try {
    //     const res = await axios.get(
    //       `${this.serviceFolder}dashboardservice.cfc?method=getDashboardData`
    //     );

    //     //unpacking everything
    //     const data = res.data;
    //     this.metrics = data.metrics;
    //     this.facilityData = data.facilityData;
    //     this.trendData = data.trendData;

    //     //now draw both charts
    //     this.renderCharts();

    //   }catch (e) {
    //     console.error('Dashboard load error', e);
    //   }

    //   },

    // async fetchFlexRequests() {
    //   try {
    //     const res = await axios.get(
    //       `${this.serviceFolder}dashboardservice.cfc?method=getFlexRequests`
    //     );
    //     console.log('Requests', res.data);
    //     this.flexRequests = res.data;
    //   } catch (e) {
    //     console.error('Error loading request', e);
    //   }
    // },



    async fetchFlexRequests() {
  try {
    const res = await axios.get(`${this.serviceFolder}dashboard.cfc?method=getFlexRequests&userid=${encodeURIComponent(this.userAceid)}`);
    const rows = Array.isArray(res.data) ? res.data : [];
    this.flexRequests = rows.filter(r => r && typeof r === 'object');

    // Build status dropdown values
    this.statusOptions = Array.from(
      new Set(this.flexRequests.map(r => r.STATUS).filter(Boolean))
    ).sort();
  } catch (e) {
    console.error('Error loading request', e);
    this.flexRequests = [];
    this.statusOptions = [];
  }
},


    // ---------- chart (includes Modify) ----------
    renderChart() {
      const el = document.getElementById('trendChart');
      if (!el) return;
      const ctx = el.getContext('2d');
      if (this.statusChart) { this.statusChart.destroy(); this.statusChart = null; }

      const { TOTAL, PENDING, APPROVED, MODIFICATION, DECLINED } = this.metrics;

      this.statusChart = new Chart(ctx, {
        type: 'bar',
        data: {
          labels: ['TOTAL', 'PENDING', 'APPROVED', 'MODIFY', 'DECLINED'],
          datasets: [{
            label: 'Number of Requests',
            data: [TOTAL, PENDING, APPROVED, MODIFICATION, DECLINED],
            backgroundColor: [
              'rgba(54, 162, 235, 0.8)',
              'rgba(255, 206, 86, 0.8)',
              'rgba(75, 192, 192, 0.8)',
              'rgba(153, 102, 255, 0.8)',
              'rgba(255, 99, 132, 0.8)'
            ],
            borderColor: [
              'rgba(54, 162, 235, 1)',
              'rgba(255, 206, 86, 1)',
              'rgba(75, 192, 192, 1)',
              'rgba(153, 102, 255, 1)',
              'rgba(255, 99, 132, 1)'
            ],
            borderWidth: 1,
            borderRadius: 8,
            barPercentage: 0.6,
            categoryPercentage: 0.5
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            title: { display: true, text: 'Request Trend', font: { size: 18, weight: '500' } },
            legend: { display: false }
          },
          scales: {
            x: { grid: { display: false }, ticks: { font: { size: 13 } } },
            y: {
              beginAtZero: true,
              grid: { color: 'rgba(0,0,0,0.05)', borderDash: [3, 3] },
              ticks: { stepSize: 10, font: { size: 12 } }
            }
          }
        }
      });
    },



    // Status chip class (same mapping as admin)
statusClass(status) {
  switch ((status || '').toString()) {
    case 'Approved': return 'chip chip-approved';
    case 'Pending':  return 'chip chip-pending';
    case 'Declined': return 'chip chip-declined';
    case 'Modify':   return 'chip chip-modify';
    default:         return 'chip chip-default';
  }
},

// Excel-style filter menu placement (anchor to .tbl-wrap)
openFilterMenu(field, evt) {
  const btn = evt.currentTarget;
  const container = this.$refs.tblWrap;
  if (!btn || !container) return;

  const b = btn.getBoundingClientRect();
  const c = container.getBoundingClientRect();

  // account for shrink scaling
  const scaleX = (c.width  / container.clientWidth)  || 1;
  const scaleY = (c.height / container.clientHeight) || 1;

  let x = (b.left - c.left) / scaleX + container.scrollLeft;
  const y = (b.bottom - c.top) / scaleY + container.scrollTop + 6;

  // keep inside container
  const menuWidth = 260;
  const maxX = container.scrollLeft + container.clientWidth - menuWidth - 8;
  if (x > maxX) x = Math.max(container.scrollLeft, maxX);

  this.filterMenu = { open:true, field, x, y };
  evt.stopPropagation();
},
onStatusChange(e){
  const val = (e && e.target) ? e.target.value : '';
  this.filters.STATUS = String(val || '');
  this.filterMenu.open = false;
},
clearFilter(field){
  this.filters[field] = '';
  this.filterMenu.open = false;
},
onDocClick(e){
  const pop = this.$refs.filterMenuRef;
  if (!pop) { this.filterMenu.open = false; return; }
  if (!pop.contains(e.target)) this.filterMenu.open = false;
},
onContainerScroll(){ if (this.filterMenu.open) this.filterMenu.open = false; },
onWinResize(){ if (this.filterMenu.open) this.filterMenu.open = false; },


/**
 * Fetch 15-day status trends and render the line chart.
 */
// async fetchTrendData15Days() {
//   try {
//     const res = await axios.get(
//       `${this.serviceFolder}dashboardservice.cfc?method=getTrendData15Days`
//     );
//     this.trendData15Days = res.data;
//     this.renderTrendLineChart();
//   } catch (e) {
//     console.error('Trend data load error', e);
//   }
// },


/**
 * Renders a multi-series line chart into #facilityChart
 */
// renderTrendLineChart() {
//   if (!this.trendData15Days.length) return;
//   const labels = this.trendData15Days.map(r => r.DayDate);
//   const totals    = this.trendData15Days.map(r => r.Total);
//   const pending   = this.trendData15Days.map(r => r.Pending);
//   const approved  = this.trendData15Days.map(r => r.Approved);
//   const declined  = this.trendData15Days.map(r => r.Declined);

//   const ctx = document.getElementById('facilityChart').getContext('2d');
//   // destroy old chart if exists
//   if (this.trendLineChart) this.trendLineChart.destroy();

//   this.trendLineChart = new Chart(ctx, {
//     type: 'line',
//     data: {
//       labels,
//       datasets: [
//         {
//           label: 'Total',
//           data: totals,
//           borderWidth: 2,
//           tension: 0.3
//         },
//         {
//           label: 'Pending',
//           data: pending,
//           borderWidth: 2,
//           tension: 0.3
//         },
//         {
//           label: 'Approved',
//           data: approved,
//           borderWidth: 2,
//           tension: 0.3
//         },
//         {
//           label: 'Declined',
//           data: declined,
//           borderWidth: 2,
//           tension: 0.3
//         }
//       ]
//     },
//     options: {
//       responsive: true,
//       plugins: {
//         legend: { position: 'top' },
//         title: {
//           display: false
//         }
//       },
//       scales: {
//         x: {
//           ticks: { maxRotation: 0 },
//           title: { display: true, text: 'Date' }
//         },
//         y: {
//           beginAtZero: true,
//           title: { display: true, text: 'Count' }
//         }
//       }
//     }
//   });
// },


isLocked(req) {
  if (!req) return true;
  // Allow editing while Pending or Modify, regardless of audit history
  if (req.STATUS === 'Pending' || req.STATUS === 'Modify') return false;
  // Otherwise fall back to server-provided lock flag
  return !!(req.LOCKED === 1 || req.LOCKED === true);
},


// openEdit(req) {
//   try {
//     if (!req) return;
//     if (this.isLocked(req)) return;

//     // show the modal first so even if data massaging fails, user sees something
//     this.showEditModal = true;

//     const numOrNull = (v) => (v === null || v === undefined || v === '') ? null : Number(v);
//     const toDate10   = (v) => (v && typeof v === 'string') ? v.slice(0, 10) : (v || '');

//     // keep a reference for Save
//     this.selectedRequest = req;

//     // initialize edit form defensively
//     this.editForm = {
//       requestId:     req.REQUESTID,
//       hours:         numOrNull(req.HOURSPERWEEK) ?? 0,
//       justification: (req.JUSTIFICATION || ''),
//       startDate:     toDate10(req.STARTDATE),
//       endDate:       toDate10(req.ENDDATE)
//     };

//     // clear any old status messages
//     this.editStatus   = '';
//     this.editStatusOK = false;

//     // focus first input after modal mounts (optional)
//     this.$nextTick(() => {
//       const first = document.querySelector('input[type="number"], textarea');
//       if (first) first.focus();
//     });
//   } catch (e) {
//     console.error('openEdit error:', e);
//     this.editStatus   = 'Unable to open editor.';
//     this.editStatusOK = false;
//     // ensure modal is visible even if something threw
//     this.showEditModal = true;
//   }
// },


openEdit(req) {
  try {
    if (!req) return;
    if (this.isLocked(req)) return;

    this.showEditModal = true;

    const numOrNull = (v) => (v === null || v === undefined || v === '') ? null : Number(v);
    const toDate10  = (v) => (v && typeof v === 'string') ? v.slice(0, 10) : (v || '');

    this.selectedRequest = req;

    this.editForm = {
      requestId:     req.REQUESTID,
      hours:         numOrNull(req.HOURSPERWEEK) ?? 0,
      justification: (req.JUSTIFICATION || ''),
      startDate:     toDate10(req.STARTDATE), // existing ISO
      endDate:       toDate10(req.ENDDATE),   // existing ISO
      wk_start:      toDate10(req.STARTDATE), // NEW: seed the selects to match
      wk_end:        toDate10(req.ENDDATE)    // NEW
    };

    this.editStatus   = '';
    this.editStatusOK = false;

    this.$nextTick(() => {
      const first = document.querySelector('input[type="number"], textarea');
      if (first) first.focus();
    });
  } catch (e) {
    console.error('openEdit error:', e);
    this.editStatus   = 'Unable to open editor.';
    this.editStatusOK = false;
    this.showEditModal = true;
  }
},






// onEditClick(req) {
//   // Quick visibility/log to prove the handler is firing
//   try { console.log('Edit clicked:', req?.REQUESTID, 'locked?', this.isLocked(req)); } catch(_) {}

//   // Call your existing logic
//   this.openEdit(req);

//   // Safety net: even if openEdit hit a minor issue, ensure the modal shows
//   if (!this.showEditModal) {
//     this.showEditModal = true;
//   }
// },

async onEditClick(req) {
  try { console.log('Edit clicked:', req?.REQUESTID, 'locked?', this.isLocked(req)); } catch(_){}
  if (!this.weekOptions || !this.weekOptions.length) {
    await this.loadWeekOptions();
  }
  this.openEdit(req);
  if (!this.showEditModal) this.showEditModal = true;
},





confirmDelete(req) {
  if (this.isLocked(req)) return;
  const ok = window.confirm(`Delete request #${req.REQUESTID}? This cannot be undone.`);
  if (!ok) return;
  this.deleteRequest(req);
},

async deleteRequest(req) {
  const fd = new FormData();
  fd.append('requestId', req.REQUESTID);

  try {
    const res = await axios.post(
      `${this.serviceFolder}dashboard.cfc?method=deleteUserRequest&returnformat=json&userid=${encodeURIComponent(this.userAceid)}`,
      fd,
      { validateStatus: () => true }
    );

    if (res.status === 200 && res.data && res.data.SUCCESS) {
      this.flexRequests = this.flexRequests.filter(r => r.REQUESTID !== req.REQUESTID);
    } else {
      console.log("failed response is: " + JSON.stringify(res.data?.MESSAGE))
      alert(res.data?.MESSAGE || `Delete failed (HTTP ${res.status})`);
    }
  } catch (err) {
    console.error(err);
    alert('Delete failed.');
  }
},



    exportTableToCSV() {
      // CSV Headers
      const headers = ['ID', 'Facility', 'Hours', 'Start', 'End', 'By', 'On'];

      // Extract data from flexRequests array
      const rows = this.flexRequests.map((req) => [
        req.REQUESTID,
        req.FACILITYID,
        req.HOURSPERWEEK,
        req.STARTDATE,
        req.ENDDATE,
        req.CREATEDBY,
        req.CREATEDON
      ]);

      // Convert to CSV format
      const csvContent = [
        headers.join(','), // header row
        ...rows.map((row) =>
          row
            .map((cell) => {
              const text = String(cell).replace(/"/g, '""');
              return `"${text}"`;
            })
            .join(',')
        )
      ].join('\r\n');

      // Create and trigger download
      const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
      const url = URL.createObjectURL(blob);
      const downloadLink = document.createElement('a');
      downloadLink.href = url;
      downloadLink.setAttribute('download', 'flex-time-requests.csv');
      document.body.appendChild(downloadLink);
      downloadLink.click();
      document.body.removeChild(downloadLink);
      URL.revokeObjectURL(url);
    }
  },
  async mounted() {

    document.addEventListener('click', this._onDocClickBanner);
      document.addEventListener('click', this.onDocClick);  



      
      console.clear();
    this.authenticate().then(() => {
      this.fetchHeaderData(); // ensure banner shows FY/Week on load
      this.loadWeekOptions();
      this.fetchDashboard();
      this.fetchFlexRequests();
    });

     // keep popover sane on scroll/resize (NEW)
  const cont = this.$refs.tblWrap;
  if (cont) cont.addEventListener('scroll', this.onContainerScroll, { passive:true });
  window.addEventListener('resize', this.onWinResize, { passive:true });

  window.addEventListener('error', (e) => console.error('GlobalError:', e.error || e.message));
window.addEventListener('unhandledrejection', (e) => console.error('UnhandledRejection:', e.reason));
  },

  beforeUnmount() {
  document.removeEventListener('click', this._onDocClickBanner);

      document.removeEventListener('click', this.onDocClick);
const cont = this.$refs.tblWrap;
if (cont) cont.removeEventListener('scroll', this.onContainerScroll);
window.removeEventListener('resize', this.onWinResize);

},

}).mount('#dashboardApp');
