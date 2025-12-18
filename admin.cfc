component {

  // --- server-side admin check (keep in sync with your front-end list) ---
  private boolean function isAdminUser(required string ace) output="false" {

    // TODO: move to DB later; for now keep it hard-coded
    var ADMIN_WHITELIST = "DG4QJ0,BR5TBB,KWC2RJ";
    return len(ace) AND listFindNoCase(ADMIN_WHITELIST, ace) GT 0;
  }


  /**
   * Summary metrics used by the cards and chart.
   */
  remote any function getDashboardData()
    returnFormat="JSON" produces="application/json" output="false" {

    cfheader(name="Content-Type", value="application/json;charset=UTF-8");

    var q = queryExecute(
      "
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN Status='Pending'  THEN 1 ELSE 0 END) AS pending,
        SUM(CASE WHEN Status='Approved' THEN 1 ELSE 0 END) AS approved,
        SUM(CASE WHEN Status='Modify'   THEN 1 ELSE 0 END) AS modified,
        SUM(CASE WHEN Status='Declined' THEN 1 ELSE 0 END) AS declined
      FROM PCSV_dw.dbo.FlexTimeRequests
      ",
      {},
      { datasource = "pcsv_dw" }
    );

    if ( !q.recordCount ) {
      return { TOTAL:0, PENDING:0, APPROVED:0, MODIFICATION:0, DECLINED:0 };
    }

    return {
      TOTAL        : val(q.total[1]),
      PENDING      : val(q.pending[1]),
      APPROVED     : val(q.approved[1]),
      MODIFICATION : val(q.modified[1]),
      DECLINED     : val(q.declined[1])
    };
  }


  /**
   * Returns the rows for the table.
   * NOTE: If you want admins to see ALL requests, remove the WHERE CreatedBy = :currentUserAce.
   */
  remote any function getFlexRequests(required string userid, required numeric year)
    returnFormat="JSON" produces="application/json" output="false" {

    cfheader(name="Content-Type", value="application/json;charset=UTF-8");

    // show only rows from Jan 1, 2025 onward
    var startFrom = createDate(year, 1, 1);
    var endAt = createDate(year + 1, 1, 1)

    var params  = { startFrom: { value:startFrom, cfsqltype:"cf_sql_date" }, endAt: { value:endAt, cfsqltype:"cf_sql_date" } };
    var isAdmin = isAdminUser(arguments.userid);

    var sql = "
      WITH LatestAudit AS (
        SELECT
          a.RequestID,
          a.Comment,
          a.ChangedBy,
          a.ChangedDate,
          a.OldStatus,
          a.NewStatus,
          ROW_NUMBER() OVER (PARTITION BY a.RequestID ORDER BY a.ChangedDate DESC, a.AuditID DESC) AS rn
        FROM PCSV_dw.dbo.FlexTimeAudit a
      ),
      LatestFile AS (
        SELECT z.RequestID, z.FileId, z.FileName
        FROM (
          SELECT
            f.RequestID, f.FileId, f.FileName, f.UploadedAt,
            ROW_NUMBER() OVER (PARTITION BY f.RequestID ORDER BY f.UploadedAt DESC, f.FileId DESC) AS rn
          FROM PCSV_dw.dbo.FlexTimeFileStorage f
        ) z WHERE z.rn = 1
      )
      SELECT
        ftr.RequestID,
        ftr.FacilityID,
        vb.B_FIN_NAME               AS FacilityName,
        ftr.Craft,
        ftr.LabourDistributionCode,
        ftr.OperationNumber,
        ftr.HoursPerWeek,
        ftr.Justification,
        ftr.Status,
        CONVERT(VARCHAR(10), ftr.StartDate, 23) AS StartDate,
        CONVERT(VARCHAR(10), ftr.EndDate,   23) AS EndDate,
        ftr.CreatedBy,
        cp.user_fname,
        cp.user_lname,
        CONVERT(VARCHAR(19), ftr.CreatedDate, 120) AS CreatedOn,
        la.Comment,
        la.ChangedBy,
        CONVERT(VARCHAR(19), la.ChangedDate, 120)  AS ChangedDate,
        lf.FileId,
        lf.FileName
      FROM pcsv_dw.dbo.FlexTimeRequests AS ftr
      LEFT JOIN PCSV_csaw.dbo.csaw_pw AS cp 
        ON ftr.CreatedBy = cp.user_id
      LEFT JOIN PCSV_dw.dbo.var_base vb
        ON vb.B_FIN_NBR = ftr.FacilityID
      LEFT JOIN LatestAudit la
        ON la.RequestID = ftr.RequestID AND la.rn = 1
      LEFT JOIN LatestFile lf
        ON lf.RequestID = ftr.RequestID
      WHERE ftr.CreatedDate >= :startFrom AND ftr.CreatedDate < :endAt
      ORDER BY ftr.CreatedDate DESC";
  
    var raw = queryExecute(sql, params, { datasource:"pcsv_dw" });

    var cleaned = [];
    for ( var i = 1; i <= raw.recordCount; i++ ) {
      var id     = raw["RequestID"][i];
      var fileId = raw["FileId"][i];
      var fname  = raw["FileName"][i];

      var hasFile        = isNumeric(fileId) AND val(fileId) GT 0;
      var attachmentUrl  = "";
      var attachmentName = "";

      if ( hasFile ) {
        attachmentUrl  = "/ref/api/v1/toolbox/flex/flex.cfc?method=downloadAttachment&requestID=" & id;
        if ( isSimpleValue(fname) AND len(trim(toString(fname))) ) {
          attachmentName = fname;
        }
      }

      arrayAppend(cleaned, {
        REQUESTID              : id,
        FACILITYID             : raw["FacilityID"][i],
        FACILITYNAME           : raw["FacilityName"][i],
        CRAFT                  : raw["Craft"][i],
        LABOURDISTRIBUTIONCODE : raw["LabourDistributionCode"][i],
        OPERATIONNUMBER        : raw["OperationNumber"][i],
        HOURSPERWEEK           : raw["HoursPerWeek"][i],
        JUSTIFICATION          : raw["Justification"][i],
        STATUS                 : raw["Status"][i],
        STARTDATE              : raw["StartDate"][i],
        ENDDATE                : raw["EndDate"][i],
        CREATEDBY              : raw["CreatedBy"][i],
        USER_FNAME             : raw["user_fname"][i],
        USER_LNAME             : raw["user_lname"][i],
        CREATEDON              : raw["CreatedOn"][i],
        COMMENT                : raw["Comment"][i],
        CHANGEDBY              : raw["ChangedBy"][i],
        CHANGEDDATE            : raw["ChangedDate"][i],
        ATTACHMENTURL          : attachmentUrl,
        ATTACHMENTNAME         : attachmentName
      });
    }

    return cleaned;
  }


  /**
   * Header values for banner: facility name, current FY and week.
   * Keeps Master_Calendar as source of truth; if it returns nothing,
   * fallback computes FY start as the last Saturday in September.
   */
  remote any function getHeaderData(required string userid)
    returnFormat="JSON" produces="application/json" output="false" {

    cfheader(name="Content-Type", value="application/json;charset=UTF-8");

    var hdr = {};

    // ---------- Office/Facility name ----------
    var qFac = queryExecute(
      "
      SELECT TOP 1 vb.B_FIN_NAME AS officeName
      FROM PCSV_csaw.dbo.csaw_pw cp
      JOIN PCSV_dw.dbo.FlexTimeRequests ftr ON cp.user_id = ftr.CreatedBy
      JOIN PCSV_dw.dbo.var_base vb          ON ftr.FacilityID = vb.B_FIN_NBR
      WHERE cp.user_id = :uid
      ORDER BY ftr.CreatedDate DESC
      ",
      { uid: { value:arguments.userid, cfsqltype:"cf_sql_varchar" } },
      { datasource:"pcsv_dw" }
    );

    hdr.officeName = qFac.recordCount ? qFac.officeName[1] : "";

    if ( !len(hdr.officeName) ) {
      var qLast = queryExecute(
        "
        SELECT TOP 1 vb.B_FIN_NAME AS officeName
        FROM PCSV_dw.dbo.FlexTimeRequests f
        LEFT JOIN PCSV_dw.dbo.var_base vb ON vb.B_FIN_NBR = f.FacilityID
        ORDER BY f.CreatedDate DESC
        ",
        {},
        { datasource:"pcsv_dw" }
      );
      if ( qLast.recordCount ) hdr.officeName = qLast.officeName[1];
    }
    if ( !len(hdr.officeName) ) hdr.officeName = "Multiple Facilities";

    // ---------- Fiscal Year & Week (today) ----------
    // 1) Primary: strict "between" match using DATE param
    var qWeek = queryExecute(
      "
      SELECT TOP 1 cal_fy_long AS fiscalYear, cal_fy_wk AS week
      FROM PCSV_dw.dbo.Master_Calendar
      WHERE :todayDate BETWEEN cal_date_beg_wk AND cal_date_end_wk
      ORDER BY cal_id DESC
      ",
      { todayDate: { value:now(), cfsqltype:"cf_sql_date" } },
      { datasource:"pcsv_dw" }
    );

    if ( qWeek.recordCount ) {
      hdr.fiscalYear = qWeek.fiscalYear[1];
      hdr.week       = qWeek.week[1];
      return hdr;
    }

    // 2) Fallback from table: pick the latest week whose begin <= today
    var qWeek2 = queryExecute(
      "
      SELECT TOP 1 cal_fy_long AS fiscalYear, cal_fy_wk AS week
      FROM PCSV_dw.dbo.Master_Calendar
      WHERE cal_date_beg_wk <= :todayDate
      ORDER BY cal_date_beg_wk DESC, cal_id DESC
      ",
      { todayDate: { value:now(), cfsqltype:"cf_sql_date" } },
      { datasource:"pcsv_dw" }
    );

    if ( qWeek2.recordCount ) {
      hdr.fiscalYear = qWeek2.fiscalYear[1];
      hdr.week       = qWeek2.week[1];
      return hdr;
    }

    // 3) Last resort: compute USPS FY/Week (last Saturday of September)
    var today    = now();
    var thisYear = year(today);

    var septLast = createDate(thisYear, 9, 30);
    var backDays = ( dayOfWeek(septLast) mod 7 ); // Sat -> 0
    var lastSat  = dateAdd("d", -backDays, septLast);

    var fyStart = (
      today < lastSat
        ? dateAdd("d", -(dayOfWeek(createDate(thisYear-1, 9, 30)) mod 7), createDate(thisYear-1, 9, 30))
        : lastSat
    );

    hdr.fiscalYear = year(fyStart) + 1;

    var todayDateOnly   = parseDateTime( dateFormat(today,   "yyyy-mm-dd") );
    var fyStartDateOnly = parseDateTime( dateFormat(fyStart, "yyyy-mm-dd") );
    var daysIn          = dateDiff("d", fyStartDateOnly, todayDateOnly);
    var weekNum         = 1 + int( daysIn / 7 );

    hdr.week = weekNum;

    return hdr;
  }


  /**
   * Update request status and insert audit row, then email the requester.
   * Returns {SUCCESS, MESSAGE}.
   */
  remote any function updateRequest(required string userid)
    returnFormat="JSON" produces="application/json" output="false" {

    // ---- read payload safely ----
    var payload = {};
    try {
      var http = getHTTPRequestData();
      if ( structKeyExists(http, "content") AND len(trim(http.content)) ) {
        payload = deserializeJSON(http.content);
      }
    } catch ( any __p ) {
      payload = {};
    }

    var reqID   = ( structKeyExists(payload, "requestID") ? val(payload.requestID)   : 0  );
    var newStat = ( structKeyExists(payload, "status")    ? toString(payload.status) : "" );
    var comment = ( structKeyExists(payload, "comment")   ? toString(payload.comment): "" );

    var result = { SUCCESS:false, MESSAGE:"" };

    try {
      transaction {
        // ---- 0) Read current (OLD) status FIRST ----
        var qCur = queryExecute(
          "SELECT TOP 1 Status FROM PCSV_dw.dbo.FlexTimeRequests WHERE RequestID = :rid",
          { rid: { value:reqID, cfsqltype:"cf_sql_integer" } },
          { datasource:"pcsv_dw" }
        );
        if ( !qCur.recordCount ) {
          result.SUCCESS = false;
          result.MESSAGE = "Request not found.";
          return result;
        }
        var oldStat = qCur.Status[1];

        // Idempotent: no change → skip update/audit
        if ( compareNoCase(oldStat, newStat) EQ 0 ) {
          result.SUCCESS = true;
          result.MESSAGE = "No status change.";
          return result;
        }

        // ---- 1) Update status on the canonical row ----
        queryExecute(
          "
          UPDATE PCSV_dw.dbo.FlexTimeRequests
             SET Status       = :newStatus,
                 ModifiedBy   = :user,
                 ModifiedDate = GETDATE()
           WHERE RequestID    = :reqID
          ",
          {
            newStatus : { value:newStat,         cfsqltype:"cf_sql_varchar" },
            user      : { value:arguments.userid, cfsqltype:"cf_sql_varchar" },
            reqID     : { value:reqID,           cfsqltype:"cf_sql_integer" }
          },
          { datasource:"pcsv_dw" }
        );

        // ---- 2) Insert ONE audit row using the captured old/new ----
        queryExecute(
          "
          INSERT INTO PCSV_dw.dbo.FlexTimeAudit
            (RequestID, Comment, ChangedBy, ChangedDate, OldStatus, NewStatus)
          VALUES
            (:reqID, :cmnt, :user, GETDATE(), :oldStatus, :newStatus)
          ",
          {
            reqID     : { value:reqID,           cfsqltype:"cf_sql_integer" },
            cmnt      : { value:comment,         cfsqltype:"cf_sql_varchar" },
            user      : { value:arguments.userid, cfsqltype:"cf_sql_varchar" },
            oldStatus : { value:oldStat,         cfsqltype:"cf_sql_varchar" },
            newStatus : { value:newStat,         cfsqltype:"cf_sql_varchar" }
          },
          { datasource:"pcsv_dw" }
        );
      } // transaction

      // ---- 3) Email requester (unchanged) ----
      try {
        var r = queryExecute(
          "
          SELECT TOP 1
            f.RequestID, f.FacilityID, f.Craft, f.LabourDistributionCode, f.OperationNumber,
            f.HoursPerWeek, f.Justification,
            CONVERT(VARCHAR(10), f.StartDate, 23) AS StartDate,
            CONVERT(VARCHAR(10), f.EndDate,   23) AS EndDate,
            f.CreatedBy,
            vb.B_FIN_NAME AS FacilityName,
            LTRIM(RTRIM(COALESCE(pw.user_fname,'') + ' ' + COALESCE(pw.user_lname,''))) AS UserName,
            NULLIF(LTRIM(RTRIM(pw.user_email)), '') AS UserEmail
          FROM PCSV_dw.dbo.FlexTimeRequests f
          LEFT JOIN PCSV_dw.dbo.var_base vb ON vb.B_FIN_NBR = f.FacilityID
          LEFT JOIN PCSV_csaw.dbo.csaw_pw pw ON pw.user_id   = f.CreatedBy
          WHERE f.RequestID = :rid
          ",
          { rid: { value:reqID, cfsqltype:"cf_sql_integer" } },
          { datasource:"pcsv_dw" }
        );

        if ( r.recordCount ) {
          var toEmail = "";
          if ( structKeyExists(r, "UserEmail") AND len( trim( r.UserEmail[1] ) ) ) {
            toEmail = trim( r.UserEmail[1] );
          }

          if ( len(toEmail) ) {
            var subj = "Flex Time " & newStat & " (ID " & reqID & ")";

            var uname = r.UserName[1]       ?: "";
            var facId = r.FacilityID[1]     ?: "";
            var facNm = r.FacilityName[1]   ?: "";
            var craft = r.Craft[1]          ?: "";
            var ldc   = r.LabourDistributionCode[1] ?: "";
            var op    = r.OperationNumber[1] ?: "";
            var hrs   = r.HoursPerWeek[1]   ?: "";
            var sd    = r.StartDate[1]      ?: "";
            var ed    = r.EndDate[1]        ?: "";

            var parts = [];
            arrayAppend(parts, "<p>Hello" & ( len(uname) ? " " & htmlEditFormat(uname) : "" ) & ",</p>");
            if(newStat == "Modify") {
              arrayAppend(parts, "<p>Your Flex Time request was <b>requested for modification.</b></p>");
            } else {
              arrayAppend(parts, "<p>Your Flex Time request was <b>" & htmlEditFormat(newStat) & "</b></p>");
            }

            if ( len(trim(comment)) ) {
              arrayAppend(parts, "<p><b>Comment</b><br>" & htmlEditFormat(comment) & "</p>");
            }

            var details = "<p>";
            details &= "<b>Facility</b> " & htmlEditFormat(facId);
            if ( len(facNm) ) details &= " - " & htmlEditFormat(facNm);
            if ( len(craft) ) details &= "<br><b>Craft</b> " & htmlEditFormat(craft);
            if ( len(ldc) )   details &= "<br><b>LDC</b> "   & htmlEditFormat(ldc);
            if ( len(op) )    details &= "<br><b>Operation</b> " & htmlEditFormat(op);
            if ( len( hrs & "" ) ) details &= "<br><b>Hours Per Week</b> " & htmlEditFormat( hrs & "" );
            details &= "<br><b>Dates</b> " & htmlEditFormat(sd) & " to " & htmlEditFormat(ed) & "</p>";

            arrayAppend(parts, details);
            arrayAppend(parts, "<p><a href=""https://eagnmnwbp161f.usps.gov/ref/toolbox/flex/dashboard.html"">Open dashboard</a></p>");

            var html = arrayToList(parts, "");

             var mailer = createObject("component", "ref.api.v1.toolbox.flex.flexmail").init();
            var ok = mailer.sendStatusChangeEmail( toEmail, reqID, subj, html ); 
            writeLog(file="application", text="Attempted to send email and result is: " &ok)

            // mail(
            //   to      = toEmail,
            //   from    = "Workhour Efficiency <workhourefficiencysupport@usps.gov>",
            //   subject = subj,
            //   type    = "html"
            // ) {
            //   writeOutput(html);
            // }
          }
        }
      } catch ( any __mailErr ) {
        writeLog(file="application", text="admindashboardservice.updateRequest email error: " & __mailErr.message & " :: " & __mailErr.detail);
      }

      result.SUCCESS = true;
      result.MESSAGE = "Status updated to " & newStat;

    } catch ( any e ) {
      writeLog(file="application", text="admin updateRequest error: " & e.message & " :: " & e.detail);
      result.SUCCESS = false;
      result.MESSAGE = "Error: " & e.message;
    }

    return result;
  }


  /**
   * Update fields for a request (existing behavior preserved).
   */
  remote any function updateRequestFields(
    numeric requestId       = 0,
    string  facility        = "",
    string  craft           = "",
    numeric ldc             = 0,
    string  operationNumber = "",
    string  hours           = "",
    string  justification   = "",
    string  startDate       = "",
    string  endDate         = "",
    string  status          = "",
    required string userid
  ) returnFormat="JSON" produces="application/json" output="false" {

    cfheader(name="Content-Type", value="application/json;charset=UTF-8");

    var result = { SUCCESS:false, MESSAGE:"", REQUESTID:0, DATA:{} };

    try {
      var http = getHTTPRequestData();
      var ct   = lcase( toString( http.headers["Content-Type"] ?: http.headers["content-type"] ?: "" ) );

      if ( findNoCase("application/json", ct) AND len(trim(http.content)) ) {
        var body = deserializeJSON(http.content);

        if ( structKeyExists(body, "requestID") AND NOT structKeyExists(body, "requestId") ) {
          body.requestId = body.requestID;
        }

        if ( structKeyExists(body, "requestId") )       requestId       = val(body.requestId);
        if ( structKeyExists(body, "facility") )        facility        = toString(body.facility);
        if ( structKeyExists(body, "craft") )           craft           = toString(body.craft);
        if ( structKeyExists(body, "ldc") )             ldc             = val(body.ldc);
        if ( structKeyExists(body, "operationNumber") ) operationNumber = toString(body.operationNumber);
        if ( structKeyExists(body, "hours") )           hours           = toString(body.hours);
        if ( structKeyExists(body, "justification") )   justification   = toString(body.justification);
        if ( structKeyExists(body, "startDate") )       startDate       = toString(body.startDate);
        if ( structKeyExists(body, "endDate") )         endDate         = toString(body.endDate);
        if ( structKeyExists(body, "status") )          status          = toString(body.status);
      }

      if ( NOT val(requestId) ) {
        result.MESSAGE = "requestId is required.";
        return result;
      }

      var startDateVal = javacast("null", "");
      var endDateVal   = javacast("null", "");

      if ( len(startDate) ) {
        try { startDateVal = parseDateTime(startDate); } catch ( any e ) {}
        if ( NOT isDate(startDateVal) ) startDateVal = lsParseDateTime(startDate);
      }

      if ( len(endDate) ) {
        try { endDateVal = parseDateTime(endDate); } catch ( any e ) {}
        if ( NOT isDate(endDateVal) ) endDateVal = lsParseDateTime(endDate);
      }

      if ( isDate(startDateVal) AND isDate(endDateVal) AND endDateVal < startDateVal ) {
        result.MESSAGE = "End date can’t be before start date.";
        return result;
      }

      if ( len(trim(status)) ) {
        var okStatuses = "Pending,Approved,Declined,Modify";
        if ( listFindNoCase(okStatuses, status) EQ 0 ) {
          result.MESSAGE = "Invalid status. Allowed: #okStatuses#.";
          return result;
        }
      }

      var sets   = [];
      var params = { rid: { value:val(requestId), cfsqltype:"cf_sql_integer" } };

      if ( len(trim(facility)) )        { arrayAppend(sets, "FacilityID = :facility");            params.facility      = { value:facility,        cfsqltype:"cf_sql_varchar" }; }
      if ( len(trim(craft)) )           { arrayAppend(sets, "Craft = :craft");                    params.craft         = { value:craft,           cfsqltype:"cf_sql_varchar" }; }
      if ( val(ldc) GT 0 )              { arrayAppend(sets, "LabourDistributionCode = :ldc");     params.ldc           = { value:val(ldc),        cfsqltype:"cf_sql_integer" }; }
      if ( len(trim(operationNumber)) ) { arrayAppend(sets, "OperationNumber = :opnum");          params.opnum         = { value:operationNumber, cfsqltype:"cf_sql_varchar" }; }
      if ( len(trim(hours)) AND isNumeric(hours) ) {
        arrayAppend(sets, "HoursPerWeek = :hours");
        params.hours = { value:val(hours), cfsqltype:"cf_sql_numeric" };
      }
      if ( len(trim(justification)) )   { arrayAppend(sets, "Justification = :justification");    params.justification = { value:justification,   cfsqltype:"cf_sql_varchar" }; }
      if ( isDate(startDateVal) )       { arrayAppend(sets, "StartDate = :startDate");            params.startDate     = { value:startDateVal,    cfsqltype:"cf_sql_date"    }; }
      if ( isDate(endDateVal) )         { arrayAppend(sets, "EndDate = :endDate");                params.endDate       = { value:endDateVal,      cfsqltype:"cf_sql_date"    }; }
      if ( len(trim(status)) )          { arrayAppend(sets, "Status = :status");                  params.status        = { value:status,          cfsqltype:"cf_sql_varchar" }; }

      if ( arrayLen(sets) EQ 0 ) {
        result.SUCCESS   = true;
        result.MESSAGE   = "No changes detected.";
        result.REQUESTID = val(requestId);
        return result;
      }

      transaction {
        arrayAppend(sets, "ModifiedBy = :modBy");
        arrayAppend(sets, "ModifiedDate = GETDATE()");
        params.modBy = {
          value    :arguments.userid,
          cfsqltype: "cf_sql_varchar"
        };

        queryExecute(
          "UPDATE PCSV_dw.dbo.FlexTimeRequests SET #arrayToList(sets, ', ')# WHERE RequestID = :rid",
          params,
          { datasource:"pcsv_dw" }
        );

        var q = queryExecute(
          "
          SELECT TOP 1
            RequestID, FacilityID, Craft, LabourDistributionCode, OperationNumber,
            HoursPerWeek, Justification, Status,
            CONVERT(VARCHAR(10), StartDate, 23) AS StartDate,
            CONVERT(VARCHAR(10), EndDate,   23) AS EndDate,
            CONVERT(VARCHAR(19), CreatedDate, 120) AS CreatedOn
          FROM PCSV_dw.dbo.FlexTimeRequests
          WHERE RequestID = :rid
          ",
          { rid: { value:val(requestId), cfsqltype:"cf_sql_integer" } },
          { datasource:"pcsv_dw" }
        );
      }

      if ( NOT q.recordCount ) {
        result.SUCCESS = false;
        result.MESSAGE = "Request not found.";
        return result;
      }

      var row = {
        REQUESTID             : q.RequestID[1],
        FACILITYID            : q.FacilityID[1],
        CRAFT                 : q.Craft[1],
        LABOURDISTRIBUTIONCODE: q.LabourDistributionCode[1],
        OPERATIONNUMBER       : q.OperationNumber[1],
        HOURSPERWEEK          : q.HoursPerWeek[1],
        JUSTIFICATION         : q.Justification[1],
        STATUS                : q.Status[1],
        STARTDATE             : q.StartDate[1],
        ENDDATE               : q.EndDate[1],
        CREATEDON             : q.CreatedOn[1]
      };

      result.SUCCESS   = true;
      result.MESSAGE   = "Updated.";
      result.REQUESTID = val(requestId);
      result.DATA      = row;

    } catch ( any e ) {
      writeLog(file="application", text="Admin.updateRequestFields ERROR: " & e.message & " :: " & e.detail);
      result.SUCCESS = false;
      result.MESSAGE = "Server error: " & e.message;
      result.DETAILS = e.detail;
    }

    return result;
  }

  function getMyFacilities(required string userid) access="remote" returnFormat="json" produces="application/json" {
    cfheader( name="Content-Type", value="application/json;charset=UTF-8" );
    local.result = { success: true, message: "", detail: "" };

    try {
        local.sql ="
            select
            b_fin_name,
            b_area,
            b_area_name,
            b_cluster,
            b_cluster_name,
            b_mpoo,
            b_lead_fin_nbr,
            b_lead_name,
            b_fin_name,
            b_fin_nbr
        FROM (
            SELECT
                csaw1.user_area_code as UserAreaCode,
                csaw1.user_district_code as UserDistrictCode,
                csaw1.user_area as AreaAccessInd,
                csaw1.user_district as DistrictAccessInd,
                csaw1.user_unit as UnitAccessInd,
                csaw1.user_fname as UserFirstName,
                csaw1.user_lname as UserLastName,
                csaw2.user_list
            FROM pcsv_csaw.dbo.csaw_pw csaw1 with(nolock)
                inner join
                    (
                        SELECT
                            csaw.user_id user_id , y.value as 'user_list'
                        FROM pcsv_csaw.dbo.csaw_pw csaw with(nolock)
                cross apply string_split(csaw.user_list,',') y
                WHERE user_id = :user_id
            ) csaw2
                on csaw1.user_id=csaw2.user_id
        ) a
        inner join pcsv_dw.dbo.var_base base with(nolock)
        on a.user_list = b_fin_nbr
        ";

        local.q = queryExecute(
            local.sql,
            {
                user_id: { value: arguments.userid, cfsqltype: "cf_sql_varchar" }
            },
            { datasource: "pcsv_dw" }
        );

        return queryToArray( local.q )
    } catch (any e) {
        local.result.success = false;
        local.result.message = e.message;
        local.result.detail = e.detail;
        return local.result;
    }

    return queryToArray( local.queryResult.getResult() )
}

public array function queryToArray( required query data ) {
        var local = StructNew();

        local.Columns = ListToArray( arguments.data.ColumnList );
        local.QueryArray = ArrayNew( 1 );

        for (local.RowIndex = 1; local.RowIndex LTE arguments.data.RecordCount; local.RowIndex = (Local.RowIndex + 1)) {
        local.Row = StructNew();

        for (local.ColumnIndex = 1; local.ColumnIndex LTE ArrayLen( local.Columns ); local.ColumnIndex = (Local.ColumnIndex + 1)) {
            local.ColumnName = local.Columns[local.ColumnIndex];
            local.Row[local.ColumnName] = arguments.data[local.ColumnName][local.RowIndex];
        }

        ArrayAppend( local.QueryArray, local.Row );
        };

        return ( local.QueryArray )
  }

}
