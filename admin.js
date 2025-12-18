// /rework/flex_time/admin.js
// NOTE: All behavior preserved; only formatting, comments, and minor structural fixes.
import { createApp } from 'https://unpkg.com/vue@3.5.13/dist/vue.esm-browser.js';

createApp({
  // ---------------------------------------------------------------------------
  // Reactive State
  // ---------------------------------------------------------------------------
  data() {
    return {
      serviceFolder: '/ref/api/v1/toolbox/flex/',

      // Header / banner
      userDisplayHeader: '',
      officeName: '',
      fiscalYear: '',
      week: '',
      facilities: [],                        // facilities user can access
      bannerMenu: { open: false, x: 0, y: 0 },
      userAceid: '',
      isAllowed: false,
      denyReason: '',

      // Metrics + chart
      metrics: { TOTAL: 0, PENDING: 0, APPROVED: 0, MODIFICATION: 0, DECLINED: 0 },
      statusChart: null,

      // Requests and column filters
      flexRequests: [],
      statusOptions: [],
      filters: {
        REQUESTID: '',
        FACILITYID: '',
        AREA: '',
        CLUSTER: '',
        MPOO: '',
        HOURSPERWEEK: '',
        CRAFT: '',
        LABOURDISTRIBUTIONCODE: '',
        OPERATIONNUMBER: '',
        JUSTIFICATION: '',
        STARTDATE: '',
        ENDDATE: '',
        CREATEDBY: '',
        // USER_NAME: '',
        CREATEDON: '',
        STATUS: '',
        COMMENT: '',
        CHANGEDBY: '',
        CHANGEDDATE: ''
      },

      // >>> Pagination defaults (enabled)
      pageSize: 10,
      currentPage: 1,

      // UI toggles
      compactView: true,
      shrinkToFit: false,

      // Modal + inline edits
      showingModal: false,
      selectedRequest: null,
      isEditing: false,
      editForm: {
        requestID: null,
        facilityID: '',
        craft: '',
        ldc: null,
        operationNumber: '',
        hoursPerWeek: null,
        justification: '',
        startDate: '',
        endDate: '',
        status: ''
      },
      selectedComment: '',
      actionComment: '',
      processStatus: '',
      customCommentDraft: '',

      // Filter popover
      filterMenu: { open: false, field: '', x: 0, y: 0 },

      // Year selector
      flexTimeYears: Array.from({length: new Date().getFullYear() - 2024 + 1}, (_, i) => new Date().getFullYear()-i),
      flexTimeSelectedYear: new Date().getFullYear()
    };
  },

  // ---------------------------------------------------------------------------
  // Computed
  // ---------------------------------------------------------------------------
  computed: {
    /**
     * Filtered list based on column filters.
     * NOTE: the table currently renders paginatedRequests (below).
     */
    filteredRequests() {
      const rows = Array.isArray(this.flexRequests) ? this.flexRequests : [];
      const f = this.filters;

      const match = (val, filter) =>
        !filter || String(val ?? '').toLowerCase().includes(String(filter).toLowerCase());

      return rows.filter((r) => {
        if (!r || typeof r !== 'object') return false;
        // const userName = `${r.USER_FNAME || ''} ${r.USER_LNAME || ''}`.trim();

        return (
          match(r.REQUESTID,               f.REQUESTID) &&
          match(r.FACILITYID,              f.FACILITYID) &&
          match(r.HOURSPERWEEK,            f.HOURSPERWEEK) &&
          match(r.AREA,                    f.AREA) &&
          match(r.CLUSTER,                 f.CLUSTER) &&
          match(r.MPOO,                    f.MPOO) &&
          match(r.CRAFT,                   f.CRAFT) &&
          match(r.LABOURDISTRIBUTIONCODE,  f.LABOURDISTRIBUTIONCODE) &&
          match(r.OPERATIONNUMBER,         f.OPERATIONNUMBER) &&
          match(r.JUSTIFICATION,           f.JUSTIFICATION) &&
          match(r.STARTDATE,               f.STARTDATE) &&
          match(r.ENDDATE,                 f.ENDDATE) &&
          match(r.CREATEDBY,               f.CREATEDBY) &&
          // match(userName,                  f.USER_NAME) &&
          match(r.CREATEDON,               f.CREATEDON) &&
          (!f.STATUS || String(r.STATUS || '').toLowerCase() === f.STATUS.toLowerCase()) &&
          match(r.COMMENT,                 f.COMMENT) &&
          match(r.CHANGEDBY,               f.CHANGEDBY) &&
          match(r.CHANGEDDATE,             f.CHANGEDDATE)
        );
      });
    },

    // Pagination helpers
    totalRows() {
      return Array.isArray(this.filteredRequests) ? this.filteredRequests.length : 0;
    },
    totalPages() {
      return Math.max(1, Math.ceil(this.totalRows / this.pageSize));
    },
    firstRowIndex() {
      return (this.currentPage - 1) * this.pageSize;
    },
    lastRowIndex() {
      return Math.min(this.firstRowIndex + this.pageSize, this.totalRows);
    },
    paginatedRequests() {
      return this.filteredRequests.slice(this.firstRowIndex, this.lastRowIndex);
    }
  },

  // ---------------------------------------------------------------------------
  // Methods
  // ---------------------------------------------------------------------------
  methods: {
    /** Auth + gate admin access (hard-coded allow-list). */
    async authenticate() {
      try {
        const res = await axios.get('/ref/api/v1/authenticate.cfc?method=getUserAuth');
        if (res.data) {
          const aceid = (res.data.aceid || '').toUpperCase();
          const allowedAdmins = ['DG4QJ0', 'TR28H0', 'BR5TBB', 'KWC2RJ'];

          if (!allowedAdmins.includes(aceid)) {
            alert('You are not authorized to access this page.');
            window.location.href = `/ref/toolbox/flex/dashboard.html`;
            return;
          }

          this.userDisplayHeader = `${res.data.first} ${res.data.last} (${aceid})`;
          this.userAceid = aceid;

          if (this.userAceid) await this.fetchFacilities();
        }
      } catch (e) {
        console.error('Auth error', e);
        alert('Error during authentication. Access denied.');
      }
    },

    /** Load facilities user can access. */
    async fetchFacilities() {
      try {
        const res = await axios.get(
          `${this.serviceFolder}admin.cfc?method=getMyFacilities&userid=${encodeURIComponent(this.userAceid)}`
        );
        this.facilities = Array.isArray(res.data) ? res.data : [];

        // If header missing name and exactly 1 facility, use it in banner
        if ((!this.officeName || !this.officeName.trim()) && this.facilities.length === 1) {
          const f = this.facilities[0];
          this.officeName = f.B_FIN_NAME || this.officeName;
        }
      } catch (e) {
        console.error('fetchFacilities error', e);
        this.facilities = [];
      }
    },

    /** Small toast helper. */
    showToast(message = 'Saved.', type = 'success') {
      const el = document.getElementById('ft-toast');
      const txt = document.getElementById('ft-toast-text');
      if (!el || !txt) return;
      el.classList.remove('toast-success','toast-error','toast-info');
      el.classList.add(type === 'error' ? 'toast-error' : type === 'info' ? 'toast-info' : 'toast-success');
      txt.textContent = message;
      el.classList.add('show');
      clearTimeout(this.__toastTimer);
      this.__toastTimer = setTimeout(() => { el.classList.remove('show'); }, 2600);
    },

    /** Close modal, then refresh table + metrics. */
    closeModalAndRefresh() {
      this.closeModal();
      this.fetchFlexRequests();
      this.fetchDashboard();
    },

    /** Header values (office, FY, week). Falls back to client-side compute. */
    async fetchHeaderData() {
      try {
        const res = await axios.get(`${this.serviceFolder}admin.cfc?method=getHeaderData&userid=${encodeURIComponent(this.userAceid)}`);
        this.officeName = res.data.officeName || this.officeName || '';
        this.fiscalYear = res.data.fiscalYear || '';
        this.week       = res.data.week || '';

        if (!this.fiscalYear || !this.week) {
          const x = this.computeClientFYWeek();
          if (!this.fiscalYear) this.fiscalYear = x.fy;
          if (!this.week)       this.week       = x.week;
        }
      } catch (e) {
        console.error('Header load error', e);
        const x = this.computeClientFYWeek();
        if (!this.fiscalYear) this.fiscalYear = x.fy;
        if (!this.week)       this.week       = x.week;
      }
    },

    /** Open banner facility popover (positioned relative to banner). */
    openBannerMenu(evt) {
      const wrap = this.$refs.bannerWrap;
      if (!wrap) return;
      const b = evt.currentTarget.getBoundingClientRect();
      const w = wrap.getBoundingClientRect();
      this.bannerMenu.x = (b.left - w.left);
      this.bannerMenu.y = (b.bottom - w.top) + 6;
      this.bannerMenu.open = true;
      evt.stopPropagation();
    },

    /** Choose a facility from banner menu. */
    gotoFacility(f) {
      if (!f) return;
      this.officeName = f.B_FIN_NAME || this.officeName;
      if (this.filters && Object.prototype.hasOwnProperty.call(this.filters, 'FACILITYID')) {
        this.filters.FACILITYID = String(f.B_FIN_NBR || '');
      }
      this.bannerMenu.open = false;
    },

    /** Close banner popover on outside click. */
    _onDocClickBanner(e) {
      if (!this.bannerMenu.open) return;
      const pop = this.$refs.bannerMenuRef;
      if (pop && pop.contains(e.target)) return;
      if (e.target && e.target.closest && e.target.closest('[title="View all facilities"]')) return;
      this.bannerMenu.open = false;
    },

    /** Client-side FY/week computation (Saturday fiscal week alignment). */
    computeClientFYWeek() {
      const today = new Date();
      const y = today.getFullYear();

      const sept30 = new Date(y, 8, 30);     // Sep 30
      const dow = sept30.getDay();           // 0..6
      const backDays = (dow === 6 ? 0 : (dow + 1));
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

    /** Load KPI metrics + render chart. */
    async fetchDashboard() {
      try {
        const res = await axios.get(`${this.serviceFolder}admin.cfc?method=getDashboardData`);
        if (res?.data) {
          const d = res.data;
          this.metrics = {
            TOTAL:        Number(d.TOTAL || d.total || 0),
            PENDING:      Number(d.PENDING || d.pending || 0),
            APPROVED:     Number(d.APPROVED || d.approved || 0),
            MODIFICATION: Number(d.MODIFICATION || d.modified || 0),
            DECLINED:     Number(d.DECLINED || d.declined || 0)
          };
          this.renderChart();
        }
      } catch (e) {
        console.error('Dashboard load error', e);
      }
    },

    /** Load all flex requests + build status filter options. */
    async fetchFlexRequests() {
      try {
        const res = await axios.get(`${this.serviceFolder}admin.cfc?method=getFlexRequests&userid=${encodeURIComponent(this.userAceid)}&year=${this.flexTimeSelectedYear}`);
        const rows = Array.isArray(res.data) ? res.data : [];
        this.flexRequests = rows.filter(r => r && typeof r === 'object');

        this.statusOptions = Array.from(new Set(this.flexRequests.map(r => r.STATUS).filter(Boolean))).sort();
      } catch (e) {
        console.error('Error loading request', e);
        this.flexRequests = [];
        this.statusOptions = [];
        this.clampPage();
      }
    },

    /** Dismiss filter menu when scrolling/resizing. */
    onContainerScroll() { if (this.filterMenu.open) this.filterMenu.open = false; },
    onWinResize()       { if (this.filterMenu.open) this.filterMenu.open = false; },

    /** Render the status chart. */
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

    /** Status → chip class. */
    statusClass(status) {
      switch ((status || '').toString()) {
        case 'Approved': return 'bg-green-100 text-green-800';
        case 'Pending':  return 'bg-blue-100 text-blue-800';
        case 'Declined': return 'bg-red-100 text-red-800';
        case 'Modify':   return 'bg-yellow-100 text-yellow-800';
        default:         return 'bg-gray-100 text-gray-800';
      }
    },

    /** Open modal and seed edit form. */
    selectRequest(req) {
      if (!req) return;
      this.selectedRequest = req;
      this.actionComment   = '';
      this.processStatus   = '';
      this.isEditing       = false;
      this.showingModal    = true;

      this.editForm = {
        requestID:       req.REQUESTID,
        facilityID:      req.FACILITYID,
        craft:           req.CRAFT,
        ldc:             Number(req.LABOURDISTRIBUTIONCODE),
        operationNumber: req.OPERATIONNUMBER,
        hoursPerWeek:    Number(req.HOURSPERWEEK),
        justification:   req.JUSTIFICATION,
        startDate:       req.STARTDATE,
        endDate:         req.ENDDATE,
        status:          req.STATUS
      };
    },

    /** Persist inline field edits for the selected request. */
    async saveFieldEdits() {
      try {
        const reqId = this.editForm.requestID;
        if (!reqId) { this.processStatus = 'Missing RequestID.'; return; }

        const toISO = (v) => (v ? new Date(v).toISOString().slice(0, 10) : '');

        const fd = new FormData();
        fd.append('requestId', reqId);
        if (this.editForm.facilityID)            fd.append('facility', this.editForm.facilityID);
        if (this.editForm.craft)                 fd.append('craft', this.editForm.craft);
        if (this.editForm.ldc != null)           fd.append('ldc', this.editForm.ldc);
        if (this.editForm.operationNumber)       fd.append('operationNumber', this.editForm.operationNumber);
        if (this.editForm.hoursPerWeek != null)  fd.append('hours', this.editForm.hoursPerWeek);
        if (this.editForm.justification)         fd.append('justification', this.editForm.justification);
        if (this.editForm.startDate)             fd.append('startDate', toISO(this.editForm.startDate));
        if (this.editForm.endDate)               fd.append('endDate', toISO(this.editForm.endDate));
        if (this.editForm.status)                fd.append('status', this.editForm.status);

        const res = await axios.post(
          `${this.serviceFolder}admin.cfc?method=updateRequestFields&returnformat=json&userid=${encodeURIComponent(this.userAceid)}`,
          fd,
          { validateStatus: () => true }
        );

        if (res.status === 200 && res.data && res.data.SUCCESS) {
          const idx = this.flexRequests.findIndex(r => r.REQUESTID === reqId);
          if (idx >= 0) {
            this.flexRequests[idx] = {
              ...this.flexRequests[idx],
              FACILITYID:             this.editForm.facilityID      ?? this.flexRequests[idx].FACILITYID,
              CRAFT:                  this.editForm.craft           ?? this.flexRequests[idx].CRAFT,
              LABOURDISTRIBUTIONCODE: this.editForm.ldc             ?? this.flexRequests[idx].LABOURDISTRIBUTIONCODE,
              OPERATIONNUMBER:        this.editForm.operationNumber ?? this.flexRequests[idx].OPERATIONNUMBER,
              HOURSPERWEEK:           this.editForm.hoursPerWeek    ?? this.flexRequests[idx].HOURSPERWEEK,
              JUSTIFICATION:          this.editForm.justification   ?? this.flexRequests[idx].JUSTIFICATION,
              STARTDATE:              this.editForm.startDate       || this.flexRequests[idx].STARTDATE,
              ENDDATE:                this.editForm.endDate         || this.flexRequests[idx].ENDDATE,
              STATUS:                 this.editForm.status          || this.flexRequests[idx].STATUS
            };
          }
          this.processStatus = 'Changes saved.';
          this.selectedRequest =  this.flexRequests[idx];
          this.isEditing = false;
        } else {
          console.error('Server error body:', res.data);
          this.processStatus = (res.data && res.data.MESSAGE)
            ? res.data.MESSAGE
            : `Save failed (HTTP ${res.status})`;
        }
      } catch (err) {
        console.error('saveFieldEdits error', err);
        this.processStatus = 'Error saving changes';
      }
    },

    /** Update request status with optional comment + toast feedback. */
    async updateStatus(newStatus) {
      if (!this.selectedRequest) return;

      try {
        const res = await axios.post(
          `${this.serviceFolder}admin.cfc?method=updateRequest&userid=${encodeURIComponent(this.userAceid)}`,
          {
            requestID: this.selectedRequest.REQUESTID,
            status: newStatus,
            comment: this.actionComment
          }
        );

        const ok = res && res.status === 200 &&
                   (res.data?.SUCCESS === true ||
                    String(res.data?.MESSAGE || '').toLowerCase().includes('status updated'));

        if (ok) {
          let msg = 'Updated';
          let type = 'success';
          if (newStatus === 'Approved')      { msg = 'Request Approved';           type = 'success'; }
          else if (newStatus === 'Declined') { msg = 'Request Declined';           type = 'error'; }
          else if (newStatus === 'Modify')   { msg = 'Modification Requested';     type = 'info'; }

          this.showToast(msg, type);
          this.closeModalAndRefresh();
        } else {
          console.error('Server response:', res?.data);
          this.showToast('Update failed', 'error');
          this.processStatus = 'Error updating request';
        }
      } catch (err) {
        console.error(err);
        this.showToast('Network error', 'error');
        this.processStatus = 'Error updating request';
      }
    },

    /** Close modal without refresh. */
    closeModal() {
      this.showingModal = false;
      this.selectedRequest = null;
      this.processStatus = '';
    },

    /** Handle quick comment selection. */
    onQuickCommentChange() {
      if (this.selectedComment === 'OTHER') {
        this.actionComment = this.customCommentDraft || '';
        this.$nextTick(() => { this.$refs.otherCommentBox?.focus(); });
      } else if (this.selectedComment) {
        if (this.customCommentDraft !== this.actionComment && this.actionComment?.length) {
          this.customCommentDraft = this.actionComment;
        }
        this.actionComment = this.selectedComment;
      } else {
        this.actionComment = '';
      }
    },

    /** Simple number formatter. */
    fmt(n) {
      const v = Number(n || 0);
      return new Intl.NumberFormat('en-US').format(v);
    },

    // ------------------- Excel-style filter popover -------------------
    openFilterMenu(field, evt) {
      const btn = evt.currentTarget;
      const container = this.$refs.tblWrap;
      if (!btn || !container) return;

      const b = btn.getBoundingClientRect();
      const c = container.getBoundingClientRect();

      // If "shrink to fit" applies transform: scale(), adjust coordinates.
      const scaleX = (c.width  / container.clientWidth)  || 1;
      const scaleY = (c.height / container.clientHeight) || 1;

      // Position inside container coords
      const leftInContainer = (b.left   - c.left) / scaleX + container.scrollLeft;
      const topInContainer  = (b.bottom - c.top)  / scaleY + container.scrollTop + 6;

      // Clamp horizontally (menu width 260px)
      const menuWidth = 260;
      const maxX = container.scrollLeft + container.clientWidth - menuWidth - 8;
      let x = leftInContainer;
      if (x > maxX) x = Math.max(container.scrollLeft, maxX);

      this.filterMenu.field = field;
      this.filterMenu.x = x;
      this.filterMenu.y = topInContainer;
      this.filterMenu.open = true;

      evt.stopPropagation();
    },

    onDocClick(e) {
      const pop = this.$refs.filterMenuRef;
      if (!pop) { this.filterMenu.open = false; return; }
      if (!pop.contains(e.target)) { this.filterMenu.open = false; }
    },

    onStatusChange(e) {
      const val = (e && e.target) ? e.target.value : '';
      this.filters.STATUS = String(val || '');
      this.filterMenu.open = false;
    },

    clearFilter(field) {
      this.filters[field] = '';
      this.filterMenu.open = false;
    },

    /** Export current filtered table to CSV (unchanged, full columns). */
    exportTableToCSV() {
      const headers = [
        'ID','Facility','FacilityName','Area','Cluster','Mpoo','Hours','Craft','LDC','Operation',
        'Justification','Start','End','By','On','Status','Comment','ChangedBy','ChangedDate','UserFName','UserLName'
      ];

      const rows = (Array.isArray(this.filteredRequests) ? this.filteredRequests : []).map(req => [
        req.REQUESTID,
        req.FACILITYID,
        req.FACILITYNAME,
        req.AREA,
        req.CLUSTER,
        req.MPOO,
        req.HOURSPERWEEK,
        req.CRAFT,
        req.LABOURDISTRIBUTIONCODE,
        req.OPERATIONNUMBER,
        req.JUSTIFICATION,
        req.STARTDATE,
        req.ENDDATE,
        req.CREATEDBY,
        req.CREATEDON,
        req.STATUS,
        req.COMMENT,
        req.CHANGEDBY,
        req.CHANGEDDATE,
        req.USER_FNAME,
        req.USER_LNAME
      ]);

      const csvContent = [
        headers.join(','),
        ...rows.map(row => row.map(cell => {
          const text = String(cell ?? '').replace(/"/g, '""');
          return `"${text}"`;
        }).join(','))
      ].join('\r\n');

      const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.setAttribute('download', 'flex-time-requests.csv');
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    },

    // ------------------- Pagination helpers -------------------
    setPage(n) {
      const page = Number(n) || 1;
      this.currentPage = Math.min(Math.max(1, page), this.totalPages);
    },
    nextPage() { if (this.currentPage < this.totalPages) this.currentPage += 1; },
    prevPage() { if (this.currentPage > 1) this.currentPage -= 1; },
    clampPage() {
      if (this.currentPage > this.totalPages) this.currentPage = this.totalPages;
      if (this.currentPage < 1) this.currentPage = 1;
    },
    handleFlexYearChange(e) {
      const newYear = e.target.value;
      if(newYear === this.flexTimeSelectedYear) return

      this.flexRequests = []

      this.fetchFlexRequests()

    }
  },

  // ---------------------------------------------------------------------------
  // Watchers
  // ---------------------------------------------------------------------------
  watch: {
    // Keep draft "Other" comment text preserved
    actionComment(newVal) {
      if (this.selectedComment === 'OTHER') {
        this.customCommentDraft = newVal;
      }
    },

    // If filtered dataset changes, keep page in range
    filteredRequests() {
      this.currentPage = 1;
      this.clampPage();
    }
  },

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------
  mounted() {
    // Global click handlers (filters & banner)
    document.addEventListener('click', this.onDocClick);
    document.addEventListener('click', this._onDocClickBanner);

    // Initial loads
    this.authenticate().then( () => {
 this.fetchHeaderData();
    this.fetchDashboard();
    this.fetchFlexRequests();
    });
   

    // Keep filter popover sane on scroll/resize
    const cont = this.$refs.tblWrap;
    if (cont) cont.addEventListener('scroll', this.onContainerScroll, { passive: true });
    window.addEventListener('resize', this.onWinResize, { passive: true });
  },

  beforeUnmount() {
    document.removeEventListener('click', this.onDocClick);
    document.removeEventListener('click', this._onDocClickBanner);
    const cont = this.$refs.tblWrap;
    if (cont) cont.removeEventListener('scroll', this.onContainerScroll);
    window.removeEventListener('resize', this.onWinResize);
  }
}).mount('#dashboardApp');
