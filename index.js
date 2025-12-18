import { createApp } from 'https://cdnjs.cloudflare.com/ajax/libs/vue/3.5.13/vue.esm-browser.min.js';
import { initFlowbite, Modal } from 'https://esm.sh/flowbite';

createApp({
  data() {
    return {
      serviceFolder: '/ref/api/v1/toolbox/flex/',
      user: {},
      csawUserObject: null,
      myCsawAccess: null,
      facilities: null,
      weekOptions: null,
      
      form: {
        facility: '',
        craft: '',
        operation: '',
        operationCode: '',
        hours: null,
        justification: '',
        wk_start: '',
        wk_end: '',
        file: null,
        fileName: ''
      },
      errors: {},
      submitStatus: '',
      lastRequestId: null,

      // NEW: all possible LDCs with their display names
      ldcList: [
        { ldc: 41, name: 'Unit Distribution — Automated' },
        { ldc: 42, name: 'Customer Services' },
        { ldc: 43, name: 'Unit Distribution — Manual' },
        { ldc: 44, name: 'Post Office Box Distribution' },
        { ldc: 45, name: 'Window Services' },
        { ldc: 48, name: 'Admin/Misc — Mixed' }
      ],

      operationsList: [
        // LDC 41
        { ldc: 41, code: '9050', name: 'ADUS Parcels' },
        { ldc: 41, code: '9100', name: 'ADUS Sunday Parcels' },
        { ldc: 41, code: '9090', name: 'ADUS SCF Volume' },
        { ldc: 41, code: '3150', name: 'SDUS Parcels' },
        { ldc: 41, code: '3170', name: 'SDUS Sunday Parcels' },
        { ldc: 41, code: '3190', name: 'SDUS SCF Volume' },
        { ldc: 41, code: '9080', name: 'ADUS Bundles Volume' },
        { ldc: 41, code: '3180', name: 'SDUS Bundles Volume' },

        // LDC 42 (all codes 6370, different names)
        { ldc: 42, code: '6370', name: 'Postage Due/BRM/MRS/PRS' },
        { ldc: 42, code: '6370', name: 'Processed Letters (BRM)' },
        { ldc: 42, code: '6370', name: 'Processed Flats (BRM)' },
        { ldc: 42, code: '6370', name: 'Processed Parcels (BRM)' },
        { ldc: 42, code: '6370', name: 'Processed Postcards (BRM)' },
        { ldc: 42, code: '6370', name: 'Processed Letters (PD)' },
        { ldc: 42, code: '6370', name: 'Processed Flats (PD)' },
        { ldc: 42, code: '6370', name: 'Processed Parcels (PD)' },
        { ldc: 42, code: '6370', name: 'LDC 42 Flex Time' },
        { ldc: 42, code: '6370', name: 'Merchandise Return Service' },
        { ldc: 42, code: '6370', name: 'Parcel Return Service (PRS)' },

        // LDC 43
        { ldc: 43, code: '1610', name: 'Manual Letter Distribution' },
        { ldc: 43, code: '1720', name: 'Manual Flat Distribution' },
        { ldc: 43, code: '0770', name: 'Sunday Parcels Distribution' },
        { ldc: 43, code: '0790', name: 'Packages/Sprs Distribution' },
        { ldc: 43, code: '0790', name: 'Manual PPVS' },
        { ldc: 43, code: '2410', name: 'F4 Allied Distribution (Clerk)' },
        { ldc: 43, code: '1710', name: 'LDC 43 Allied (Mailhandler)' },
        { ldc: 43, code: '2410', name: 'LDC 43 Flex Time (Clerk)' },
        { ldc: 43, code: '1710', name: 'LDC 43 Flex Time (Mailhandler)' },
        { ldc: 43, code: '2410', name: 'Dock Transfer AM (Clerk)' },
        { ldc: 43, code: '1710', name: 'Dock Transfer AM (Mailhandler)' },
        { ldc: 43, code: '2410', name: 'Tier 1 Allied Distribution (Clerk)' },
        { ldc: 43, code: '1710', name: 'Tier 1 Allied Distribution (Mailhandler)' },
        // { ldc: 43, code: '2410', name: 'LDC 43 Tier 1 Other Time (Clerk)' },
        // { ldc: 43, code: '1710', name: 'LDC 43 Tier 1 Other Time (Mailhandler)' },
        { ldc: 43, code: '2410', name: 'Daily AM Hashing Container (Clerk)' },
        { ldc: 43, code: '1710', name: 'Daily AM Hashing Container (Mailhandler)' },
        // { ldc: 43, code: '0770', name: 'Dynamic Route Spread' },

        // LDC 44.
        
        { ldc: 44, code: '7690', name: 'Box Section' },
        { ldc: 44, code: '7690', name: 'PO Box Manual Letter Volume' },
        { ldc: 44, code: '7690', name: 'PO Box DPS Letter Volume' },
        { ldc: 44, code: '7690', name: 'PO Box Manual Flat Volume' },
        { ldc: 44, code: '7690', name: 'PO Box Parcels' },
        { ldc: 44, code: '7690', name: 'LDC 44 Flex Time' },

        // LDC 45
        { ldc: 45, code: '3550', name: 'Window Services' },
        { ldc: 45, code: '3550', name: 'SSA Transactions' },
        { ldc: 45, code: '3550', name: 'Bulletproof Glass' },
        { ldc: 45, code: '3550', name: 'WOS Ancillary (54%)' },
        { ldc: 45, code: '3550', name: 'Open/Close' },
        { ldc: 45, code: '3550', name: 'SSK Transactions' },
        { ldc: 45, code: '3550', name: 'LDC 45 Flex Time' },

        // LDC 48
        { ldc: 48, code: '7420', name: 'Bulk Mailings' }, //changed it from Average Mailing to Bulk Mailing
        { ldc: 48, code: '7420', name: 'PO Box Accountables' },
        { ldc: 48, code: '7420', name: 'Caller Services (Paid)' },
        { ldc: 48, code: '7420', name: 'MIO On Revenue Pickup' },
        { ldc: 48, code: '5440', name: 'Carrier Accountables (CAGE)' },
        { ldc: 48, code: '7420', name: 'Carrier Accountables (CART)' },
        { ldc: 48, code: '5440', name: 'Carrier Accountables (ON…) CAGE' },
        { ldc: 48, code: '7420', name: 'Carrier Accountables (ON…) CART' },
        { ldc: 48, code: '7420', name: 'CFS/PARS Prep' },
        { ldc: 48, code: '7420', name: 'Collections (Clerk)' },
        { ldc: 48, code: '5590', name: 'Collections (Mailhandler)' },
        { ldc: 48, code: '7420', name: 'Dispatch (Clerk)' },
        { ldc: 48, code: '5590', name: 'Dispatch (Mailhandler)' },
        // { ldc: 48, code: '2280', name: 'Express Mail Delivery (F4)' },
        { ldc: 48, code: '7420', name: 'Firm Holdouts' },
        // { ldc: 48, code: '7420', name: 'LDC 48 Flex Time (Clerk)' },
        // { ldc: 48, code: '5590', name: 'LDC 48 Flex Time (Mailhandler)' },
        { ldc: 48, code: '7420', name: 'My PO Credit' },
        { ldc: 48, code: '6210', name: 'Offsite Travel/Admin' },
        { ldc: 48, code: '7420', name: 'Open & Close Building' }, //changed from supplies & .. to building 
        { ldc: 48, code: '7420', name: 'PO Box Maintenance' },
        { ldc: 48, code: '7420', name: 'Premium Forwarding Service' },
        { ldc: 48, code: '7420', name: 'Remote Forwarding Service' },
        { ldc: 48, code: '7420', name: 'Non AAU Scanning (Clerk)' },   //Changed it from scans to scanning 
        { ldc: 48, code: '5590', name: 'Non AAU Scanning (Mailhandler)' }, //Changed it from scans to scanning 
        { ldc: 48, code: '7420', name: 'SSK Maintenance' },
        { ldc: 48, code: '5580', name: 'TACS (Lead Clerks Only)' },
        { ldc: 48, code: '7420', name: 'Telephone' },
        { ldc: 48, code: '7420', name: 'UBBM' },
        { ldc: 48, code: '5580', name: 'Validate PS Form 1412(s)' },
        { ldc: 48, code: '5580', name: 'Verify Deposit & Transmit' },
        { ldc: 48, code: '7420', name: 'Sunday / Holiday Hub (Clerk)' },
        { ldc: 48, code: '5590', name: 'Sunday / Holiday Hub (Mailhandler)' },
        { ldc: 48, code: '7420', name: 'Scan Where You Band' },
        { ldc: 48, code: '7420', name: 'HCR Seals' },
        { ldc: 48, code: '7420', name: 'Registers' },
        { ldc: 48, code: '7420', name: 'Pouch Setup & Labeling (Clerk)' },
        { ldc: 48, code: '5590', name: 'Pouch Setup & Labeling (Mailhandler)' },
        { ldc: 48, code: '7420', name: 'Dock Transfer PM (Clerk)' },
        { ldc: 48, code: '5590', name: 'Dock Transfer PM (Mailhandler)' },
        // { ldc: 48, code: '7420', name: 'LDC 48 Tier 1 Other Time (Clerk)' },
        // { ldc: 48, code: '5590', name: 'LDC 48 Tier 1 Other Time (Mailhandler)' },
        { ldc: 48, code: '7420', name: 'Daily PM Hashing Container (Clerk)' },
        { ldc: 48, code: '5590', name: 'Daily PM Hashing Container (Mailhandler)' }
      ]
    };
  },

  computed: {
  // which LDCs are allowed by craft?
  filteredLDCs() {
    if (this.form.craft === 'mailhandler')
      return this.ldcList.filter((l) => [43, 48].includes(l.ldc));
    if (this.form.craft === 'clerk')
      return this.ldcList.filter((l) => [41, 42, 43, 44, 45, 48].includes(l.ldc));
    return [];
  },

  // Enforce Craft + LDC rules and then dedupe codes
  filteredOperationCodes() {
    const ldc   = Number(this.form.operation);
    const craft = String(this.form.craft || '').toLowerCase();
    if (!ldc) return [];

    const inLdc = this.operationsList.filter(o => o.ldc === ldc);

    const excludeCodesForMailhandlerByLdc = {
      43: new Set(['1610','1720','2410']),
      48: new Set(['5440','5580','7420'])
    };
    const excludeCodesForClerkByLdc = {
      43: new Set(['1710']),
      48: new Set(['5590'])
    };

    const filtered = inLdc.filter(o => {
      const nm = String(o.name || '').toLowerCase();
      if (craft === 'clerk') {
        if (nm.includes('mailhandler')) return false;
        if (excludeCodesForClerkByLdc[ldc]?.has(o.code)) return false;
        return true;
      }
      if (craft === 'mailhandler') {
        if (nm.includes('clerk')) return false;
        if (excludeCodesForMailhandlerByLdc[ldc]?.has(o.code)) return false;
        return true;
      }
      return true;
    });

    const seen = new Set();
    const codes = [];
    for (const o of filtered) {
      if (!seen.has(o.code)) { seen.add(o.code); codes.push(o.code); }
    }
    return codes;
  },

  // NEW: options for the Operation Number dropdown (used for rendering labels)
  filteredOperationOptions() {
    const ldc   = Number(this.form.operation);
    const craft = String(this.form.craft || '').toLowerCase();
    if (!ldc) return [];

    const inLdc = this.operationsList.filter(o => o.ldc === ldc);

    const excludeCodesForMailhandlerByLdc = {
      43: new Set(['1610','1720','2410']),
      48: new Set(['5440','5580', '7420'])
    };
    const excludeCodesForClerkByLdc = {
      43: new Set(['1710']),
      48: new Set(['5590'])
    };

    const filtered = inLdc.filter(o => {
      const nm = String(o.name || '').toLowerCase();
      if (craft === 'clerk') {
        if (nm.includes('mailhandler')) return false;
        if (excludeCodesForClerkByLdc[ldc]?.has(o.code)) return false;
        return true;
      }
      if (craft === 'mailhandler') {
        if (nm.includes('clerk')) return false;
        if (excludeCodesForMailhandlerByLdc[ldc]?.has(o.code)) return false;
        return true;
      }
      return true;
    });

    if (ldc === 43 || ldc === 48) {
      // show ALL distinct (code,name) combos
      const seen = new Set(); // code|name
      const opts = [];
      for (const o of filtered) {
        const k = `${o.code}|${o.name.toLowerCase()}`;
        if (!seen.has(k)) { seen.add(k); opts.push({ code: o.code, name: o.name }); }
      }
      return opts;
    }

    // other LDCs: keep one per code
    const seenCodes = new Set();
    const opts = [];
    for (const o of filtered) {
      if (!seenCodes.has(o.code)) { seenCodes.add(o.code); opts.push({ code: o.code, name: o.name }); }
    }
    return opts;
  }
},// <— keep this comma because methods: follows






  

  methods: {
    // Authentication & data fetching (unchanged)
    async authenticate() {
      try {
        await axios.get(`/ref/api/v2/authenticate.cfc?method=get`).then((res) => {
          if (res.data) this.user = res.data.data;
        });
        await this.getCsawAccess();
        await this.getMyFacilities();
        await this.loadWeekOptions();
      } catch (e) {
        console.error('Auth error', e);
      }
    },
    async getCsawAccess() {
      try {
        await axios
          .get(
            `${this.serviceFolder}flex.cfc?method=getAccess&userid=${encodeURIComponent(this.userAceid)}`
          )
          .then((res) => {
            if (res.data) this.csawUserObject = res.data;
          });
      } catch (e) {
        console.error('Access error', e);
      }
    },
    async getMyFacilities() {
      try {
        await axios
          .get(
            `${
              this.serviceFolder
            }flex.cfc?method=getMyFacilities&userid=${encodeURIComponent(this.user.ace_id)}`
          )
          .then((res) => {
            if (res.data) this.facilities = res.data;
          });
      } catch (e) {
        console.error('Facilities error', e);
      }
    },

  ensureOperationCodeValid() {
  if (!this.filteredOperationCodes.includes(this.form.operationCode)) {
    this.form.operationCode = '';
  }
},


  isDisallowedForMailhandler48(name, code) {
    const nm = String(name || '').toLowerCase();
    const cd = String(code || '').trim();

    // 1) 7240 Bulk Mailing (accept "bulk mailing" or "bulk mailings")
    if (cd === '7240' && (nm.includes('bulk mailing') || nm.includes('bulk mailings'))) return true;

    // 2) HCR Seals (code may vary)
    if (nm.includes('hcr seals')) return true;

    // 3) Specific 7420 disallows
    if (cd === '7420') {
      if (nm.includes('po box accountables')) return true;
      // handles "Carrier Accountables (Cart)" and "Carrier Accountables (ON..) Cart"
      if (nm.includes('carrier accountables') && nm.includes('cart')) return true;
      if (nm.includes('cfs/pars')) return true;              // matches "CFS/PARS", "CFS/PARS Prep"
      if (nm.includes('premium forwarding service')) return true;
      if (nm.includes('remote forwarding service')) return true;
      if (nm.includes('registers')) return true;
    }

    return false;
  },

//     async loadWeekOptions() {
//   try {
//     const res = await axios.get(`${this.serviceFolder}FlexService.cfc?method=getWeekOptions&returnformat=json`);
//     if (res.data) {
//       const raw = res.data.DATA || res.data.data || [];
//       // raw rows = [ fiscalYear, week, startDate, endDate ]
//       this.weekOptions = raw.map(row => {
//         const startISO = moment(row[2]).startOf('day').format('YYYY-MM-DD');
//         const endISO   = moment(row[3]).startOf('day').format('YYYY-MM-DD');
//         return [row[0], row[1], startISO, endISO];
//       });
//     }
//   } catch (e) {
//     console.error("Couldn't load weeks", e);
//   }
// },

// asDate(v) {
//   if (!v) return null;
//   // Accept ISO, ISO with time, or common US formats just in case
//   const m = moment(v, [
//     moment.ISO_8601, 'YYYY-MM-DD', 'YYYY/MM/DD',
//     'MM/DD/YYYY', 'MMM D, YYYY', 'MMMM D, YYYY'
//   ], true);
//   return m.isValid() ? m.toDate() : null;
// },


async loadWeekOptions() {
  try {
    const res = await axios.get(`${this.serviceFolder}flex.cfc?method=getWeekOptions&returnformat=json`);
    if (res.data) {
      const raw = res.data.DATA || res.data.data || [];
      // accepted server date shapes (strict)
      const FMT = [
        'YYYY-MM-DD',
        'YYYY-MM-DD HH:mm',
        'YYYY-MM-DD HH:mm:ss',
        'YYYY-MM-DD HH:mm:ss.SSS',
        'YYYY-MM-DDTHH:mm:ssZ',
        'YYYY-MM-DDTHH:mm:ss.SSSZ',
        'MM/DD/YYYY' // just in case
      ];
      const toISO = (v) => {
        if (!v) return '';
        // numbers → epoch (sec or ms)
        if (typeof v === 'number') {
          const ms = v < 1e12 ? v * 1000 : v;
          return moment(ms).format('YYYY-MM-DD');
        }
        // strings → try strict against common SQL/ISO shapes
        let m = moment(v, FMT, true);
        if (!m.isValid()) m = moment.parseZone(v); // handles ISO with offsets
        return m.isValid() ? m.format('YYYY-MM-DD') : '';
      };

      // raw row: [fiscalYear, week, startDate, endDate]
      this.weekOptions = raw.map(row => {
        const startISO = toISO(row[2]);
        const endISO   = toISO(row[3]);
        return [row[0], row[1], startISO, endISO];
      });
    }
  } catch (e) {
    console.error("Couldn't load weeks", e);
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
    'YYYY-MM-DDTHH:mm:ss.SSSZ',
  ];
  // Prefer strict known formats; fall back to parseZone for ISO with offset
  let m = moment(v, FMT, true);
  if (!m.isValid()) m = moment.parseZone(v);
  return m.isValid() ? m.toDate() : null;
},



onStartChange() {
  const start = this.asDate(this.form.wk_start);
  const end   = this.asDate(this.form.wk_end);
  if (start && end && end < start) {
    // Nudge end up to start if user previously picked an earlier week
    this.form.wk_end = this.form.wk_start;
  }
  this.errors.wk_end = '';
},

onEndChange() {
  const start = this.asDate(this.form.wk_start);
  const end   = this.asDate(this.form.wk_end);
  if (start && end && end < start) {
    this.errors.wk_end = 'End date can’t be before start date.';
  } else {
    this.errors.wk_end = '';
  }
},


    onFileChange(e) {
  const file = e.target.files[0];
  if (!file) {
    this.form.file = null;
    this.form.fileName = '';
    this.errors.file = '';
    return;
  }

  const maxBytes = 10 * 1024 * 1024;
  if (file.size > maxBytes) {
    this.errors.file = 'File must be 10 MB or smaller.';
    this.form.file = null;
    this.form.fileName = '';
    return;
  }

  // Types we handle server-side without third-party tools
  const okMimes = new Set([
    'application/pdf', 'image/jpeg', 'image/png', 'text/plain'
  ]);
  const okExts = ['.pdf','.jpg','.jpeg','.png','.txt','.csv'];

  const nameLower = file.name.toLowerCase();
  const hasOkExt  = okExts.some(ext => nameLower.endsWith(ext));
  const hasOkMime = okMimes.has(file.type);

  if (!hasOkExt && !hasOkMime) {
    this.errors.file = 'Unsupported type. Please upload PDF, JPG, PNG, TXT, or CSV (Office files should be saved as PDF).';
    this.form.file = null;
    this.form.fileName = '';
    return;
  }

  this.errors.file = '';
  this.form.file = file;
  this.form.fileName = file.name;

    },
    validate() {
  this.errors = {};
  if (!this.form.facility)      this.errors.facility = 'Please select a facility.';
  if (!this.form.craft)         this.errors.craft = 'Please select a craft.';
  if (!this.form.operation)     this.errors.operation = 'Please select an operation.';
  if (!this.form.operationCode) this.errors.operationCode = 'Please select an operation number.';
  if (!this.form.hours || this.form.hours < 0.01 || this.form.hours > 100)
    this.errors.hours = 'Hours must be between 0.01 and 100';
  if (!this.form.justification || !this.form.justification.trim().length)
    this.errors.justification = 'Justification is required.';
  if (!this.form.wk_start) this.errors.wk_start = 'Start date required.';
  if (!this.form.wk_end)   this.errors.wk_end   = 'End date required.';

  const start = this.asDate(this.form.wk_start);
  const end   = this.asDate(this.form.wk_end);
  if (start && end && end < start) {
    this.errors.wk_end = 'End date can’t be before start date.';
  }

  return Object.keys(this.errors).length === 0;
},

async notifyAfterSubmit() {
  try {
    if (!this.lastRequestId) return;
    const res = await axios.post(
      `${this.serviceFolder}flex.cfc?method=sendSubmitEmails&returnformat=json`,
      { requestId: this.lastRequestId || 0 },
      { validateStatus: () => true } // <-- fixed spelling
    );
    console.log('sendSubmitEmails =>', res.status, res.data);
  } catch (e) {
    console.error('notifyAfterSubmit failed', e);
  }
},

    async submitRequest() {
      if (!this.validate()) return;
      // Disable the submit button using DOM manipulation
      const submitBtn = document.getElementById('submitBtn');
      if (submitBtn) submitBtn.disabled = true;

      const payload = new FormData();
      Object.entries(this.form).forEach(([k, v]) => {
        if (k === 'file' && v) {
          // payload.append('filename', this.form.file.name);
          // payload.append('filetype', this.form.file.type);
          // payload.append('filecontent', this.form.file.TODO); //

          payload.append('file', this.form.file, this.form.file.name);     // real bytes
          payload.append('filename', this.form.file.name);                  // metadata
          payload.append('filetype', this.form.file.type || 'application/pdf');

        } else if (k !== 'fileName') payload.append(k, v);
      });

      // Optional: give the server a direct email for the submitter
if (this.user?.email)        payload.append('notifyEmail', this.user.email);
else if (this.user?.mail)    payload.append('notifyEmail', this.user.mail);
else if (this.user?.user_email) payload.append('notifyEmail', this.user.user_email);

      try {
        const response = await axios.post(
          `${this.serviceFolder}flex.cfc?method=post&returnformat=json`,
          payload,
          // { headers: { 'Content-Type': 'application/json' } }
        );
        this.submitStatus = 'Request submitted successfully!';
        if (response.data['SUCCESS'] === true) {

           this.lastRequestId = response.data.REQUESTID || null;
          document.getElementById('submitModal').classList.remove('hidden');
          // reset the form

          this.form = {
            facility: '',
            craft: '',
            operation: '',
            operationCode: '',
            hours: null,
            justification: '',
            wk_start: '',
            wk_end: '',
            file: null,
            fileName: ''
          };
        } else {
          // display failure modal
          document.getElementById('failureModal').classList.remove('hidden');
        }
      } catch (err) {
        console.error(err);
        this.submitStatus = 'Submission failed, please try again.';
      } finally {
        if (submitBtn) submitBtn.disabled = false;
      }
      // Re-enable the button
    }
  },

  watch: {
    'form.craft'()    { this.ensureOperationCodeValid(); },
'form.operation'(){ this.ensureOperationCodeValid(); },
  },
  
  mounted() {
    console.clear();
    initFlowbite();
    this.authenticate();
    console.log('App mounted', this);
    document.getElementById('closeModal').addEventListener('click', async () => {
  document.getElementById('submitModal').classList.add('hidden');

  // ⬇️ fire the emails
  await this.notifyAfterSubmit();

  // then navigate to dashboard
  window.location.href = 'https://eagnmnwbp161f.usps.gov/ref/toolbox/flex/dashboard.html';
});
  }
}).mount('#app');
