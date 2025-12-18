component 
{
  // ------------------------------------------------------------
  // Envelope helpers (added to match sample formatting)
  // ------------------------------------------------------------
  private struct function newResp() {
    return {
      status: 200,
      headers: { explanation: "" },
      content: { status: "success", message: "", data: [], error: [] }
    };
  }

  private void function addError(
    required struct resp,
    required numeric status,
    required string title,
    required string detail
  ) {
    arrayAppend(arguments.resp.content.error, {
      status: toString(arguments.status),
      title: arguments.title,
      detail: arguments.detail
    });
    arguments.resp.headers.explanation = arguments.title;
    arguments.resp.status = arguments.status;
    arguments.resp.content.status = "fail";
  }

  private void function setJsonHeader() {
    cfheader(name = "Content-Type", value = "application/json; charset=UTF-8");
  }

  // Keep exact/desired key casing when serializing query rows
  private array function queryToArrayWithCase(required query q, required array colNames) {
    var rows = [];
    for (var i = 1; i <= q.recordCount; i++) {
      var row = {};
      for (var c in colNames) {
        row[c] = q[c][i]; // CF is case-insensitive for query column lookup
      }
      arrayAppend(rows, row);
    }
    return rows;
  }

  // Generic fallback (not used by getWeekOptions, but kept for parity with sample)
  private array function queryToArray(required query q) {
    var rows = [];
    for (var i = 1; i <= q.recordCount; i++) {
      arrayAppend(rows, queryGetRow(q, i));
    }
    return rows;
  }


  /**
   * Returns the fiscal‐year week 1..52 rows (FY26–FY27 window)
   * Now formatted like sample (envelope + explicit column casing)
   */
remote any function getWeekOptions()
    returnformat="json"
    produces="application/json"
{
    // -----------------------------------------------------
    // Set JSON response header
    // -----------------------------------------------------
    cfheader(
        name = "Content-Type",
        value = "application/json;charset=UTF-8"
    );

    try {
        // -------------------------------------------------
        // Fiscal-year date ranges
        // -------------------------------------------------
        // FY25: 2024-09-28 (Sat) .. 2025-09-26 (Fri)
        // FY26: 2025-09-27 (Sat) .. 2026-09-25 (Fri)
        // FY27: 2026-09-26 (Sat) .. 2027-09-24 (Fri)
        var startFY26 = createDate(2025, 9, 27);
        var endFY27   = createDate(2027, 9, 24);

        var referenceDates = getStartAndEnd();



        // -------------------------------------------------
        // Query weeks from Master_Calendar for FY26 & FY27
        // -------------------------------------------------
        
        var q = queryExecute(
            "
            WITH Ranked AS (
                   SELECT
                      cal_fy_long     AS fiscalYear,
                      cal_fy_wk       AS week,
                      MIN(cal_date_beg_wk) AS startDate,
                      MAX(cal_date_end_wk) AS endDate
                  FROM PCSV_dw.dbo.Master_Calendar
                  WHERE cal_fy_long IN (2026, 2027)
                    AND cal_date_beg_wk >= :startDate
                    AND cal_date_end_wk <= :endDate
                  GROUP BY
                      cal_fy_long,
                      cal_fy_wk
                
            )
            SELECT
                fiscalYear,
                week,
                startDate,
                endDate
            FROM Ranked
            ORDER BY fiscalYear, week
            ",
            {
                startDate = { value = referenceDates.startDate, cfsqltype = "cf_sql_date" },
                endDate   = { value = referenceDates.endDate,   cfsqltype = "cf_sql_date" }
            },
            { datasource = "pcsv_dw" }
        );

        // -------------------------------------------------
        // Return query directly (ColdFusion serializes to JSON)
        // -------------------------------------------------
        return q;

    } catch (any e) {
        // -------------------------------------------------
        // Handle errors gracefully (return structured JSON)
        // -------------------------------------------------
        var err = {
            error   : true,
            message : "getWeekOptions failed: " & e.message,
            detail  : (structKeyExists(e, "detail") ? e.detail : "")
        };
        return err;
    }
}

  /** CAT server detection – robust short/FQDN match with a one-time log */
  private boolean function isCatServer() output="false" {
    var hostName  = "";
    var shortHost = "";
    var catName   = "";

    try {
      var inet = createObject("java", "java.net.InetAddress");
      hostName  = inet.getLocalHost().getHostName();        // e.g. eagnmnwbc1db.usps.gov OR eagnmnwbc1db
      shortHost = listFirst(hostName, ".");                 // always the short name
    } catch (any __inet) {
      writeLog(file="application", text="isCatServer: hostname lookup failed: #__inet.message#");
      return false;
    }

    try {
      var q = queryExecute("
          SELECT TOP 1 srv_name
          FROM var_servers.dbo.var_servers WITH (NOLOCK)
          WHERE srv_active_ind=1 AND srv_web_ind=1 AND srv_cat_ind=1
        ", {}, { datasource: "var_exec_cdv" });
      if (q.recordCount) catName = trim(q.srv_name[1]);
    } catch (any __db) {
      writeLog(file="application", text="isCatServer: CAT lookup failed: #__db.message# :: #__db.detail#");
      return false;
    }

    // Log what we compare (helps once, then you can remove)
    writeLog(file="application", text="isCatServer check → host=#hostName# short=#shortHost# cat=#catName#");

    // Accept match on short host OR contains either way (handles FQDN vs short)
    return (
      len(catName)
      AND (
        compareNoCase(shortHost, catName) EQ 0
        OR findNoCase(catName, hostName) GT 0
        OR findNoCase(hostName, catName) GT 0
      )
    );
  }

  private struct function getStartAndEnd() {

        var result = {};
        var currentYear = year(now());
        var endYear = currentYear + 2;

        var lastDayOfSeptemberCurrentYear = dateAdd(
            "d",
            -1,
            createDate(currentYear, 10, 1)
        );

        var daysToSubtract = (dayOfWeek(lastDayOfSeptemberCurrentYear) - 7 + 7) % 7;

        var startDate = dateAdd(
            "d",
            -daysToSubtract,
            lastDayOfSeptemberCurrentYear
        );


        var lastDayOfSeptemberEndYear = dateAdd(
            "d",
            -1,
            createDate(endYear, 10, 1)
        );

        var daysToSubtractForFuture = (dayOfWeek(lastDayOfSeptemberEndYear) - 7 + 7) % 7;

        var endDatePlusOne = dateAdd(
            "d",
            -daysToSubtractForFuture,
            lastDayOfSeptemberEndYear
        );

        var endDate = dateAdd(
          "d",
          -1,
          endDatePlusOne
        );

        result.startDate = startDate;
        result.endDate = endDate;

        return result;
  }

  /*
   * INSERT flex-time request + OPTIONAL attachment into FILESTREAM table.
   * Accepts either multipart/form-data (FormData) or JSON.
   * Behavior unchanged.
   */
  function post(
    string facility       = "",
    string craft          = "",
    numeric operation     = 0,         // LDC
    string  operationCode = "",
    numeric hours         = 0,
    string  justification = "",
    date    wk_start      = "",
    date    wk_end        = "",
    any     file          = "",        // multipart field name is "file"
    string  filename      = "",
    string  filetype      = "",
    string  notifyEmail   = ""
  ) access="remote" returnFormat="JSON" returnType="any" output="false" {

    var result = { SUCCESS=true, MESSAGE:"", DETAILS:"", REQUESTID=0, ATTACHMENT_SAVED=false };

    // --- Parse body (JSON vs multipart) ---
    var http = getHTTPRequestData();
    var ct   = lcase( toString( http.headers["Content-Type"] ?: http.headers["content-type"] ?: "" ) );
    var payload = {};

    try {
      if ( findNoCase("application/json", ct) AND len(trim(http.content)) ) {
        payload = deserializeJSON(http.content);
      } else {
        // multipart/form-data → rely on FORM scope
        payload = {
          facility      = len(arguments.facility)      ? arguments.facility      : form.facility,
          craft         = len(arguments.craft)         ? arguments.craft         : form.craft,
          operation     = arguments.operation          ? arguments.operation     : val(form.operation),
          operationCode = len(arguments.operationCode) ? arguments.operationCode : toString(form.operationCode),
          hours         = arguments.hours              ? arguments.hours         : val(form.hours),
          justification = len(arguments.justification) ? arguments.justification : form.justification,
          wk_start      = len(arguments.wk_start)      ? arguments.wk_start      : form.wk_start,
          wk_end        = len(arguments.wk_end)        ? arguments.wk_end        : form.wk_end,
          filename      = len(arguments.filename)      ? arguments.filename      : ( structKeyExists(form,"filename") ? form.filename : "" ),
          filetype      = len(arguments.filetype)      ? arguments.filetype      : ( structKeyExists(form,"filetype") ? form.filetype : "" ),
          notifyEmail   = len(arguments.notifyEmail)   ? arguments.notifyEmail   : ( structKeyExists(form,"notifyEmail") ? form.notifyEmail : "" )
        };
      }
    } catch (any ex) {
      writeLog(file="application", text="Flex post parse error: " & ex.message & " :: " & ex.detail);
      return { SUCCESS=false, MESSAGE="Invalid request payload.", DETAILS=ex.detail };
    }

    var createdByVal = structKeyExists(session,"userACE") ? session.userACE : cgi.remote_user;
    // Normalize DOMAIN\user → user (use Chr(92) = backslash)
    if ( find(Chr(92), createdByVal) ) {
      createdByVal = listLast(createdByVal, Chr(92));
    }

    writeLog(file="application", text="Flex post payload => " & serializeJSON(payload));

    // --- 1) Insert request & get ID ---
    try {
      var insertQ = queryExecute(
        "
          INSERT INTO PCSV_dw.dbo.FlexTimeRequests
            (FacilityID, Craft, LabourDistributionCode, OperationNumber,
             HoursPerWeek, Justification, StartDate, EndDate, CreatedBy)
          VALUES
            (:facilityId, :craft, :ldc, :opnum,
             CAST(:hoursPerWeek AS DECIMAL(9,2)), :justification, :wk_start, :wk_end, :createdBy);

          SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewID;
        ",
        {
          facilityId   : { value=payload.facility,      cfsqltype="cf_sql_varchar" },
          craft        : { value=payload.craft,         cfsqltype="cf_sql_varchar" },
          ldc          : { value=payload.operation,     cfsqltype="cf_sql_integer" },
          opnum        : { value=payload.operationCode, cfsqltype="cf_sql_varchar" },
          hoursPerWeek : { value=payload.hours,         cfsqltype="cf_sql_decimal", scale=2 },
          justification: { value=payload.justification, cfsqltype="cf_sql_varchar" },
          wk_start     : { value=payload.wk_start,      cfsqltype="cf_sql_date" },
          wk_end       : { value=payload.wk_end,        cfsqltype="cf_sql_date" },
          createdBy    : { value=createdByVal,          cfsqltype="cf_sql_varchar" }
        },
        { datasource="pcsv_dw" }
      );

      result.REQUESTID = ( structKeyExists(insertQ, "NewID") AND insertQ.recordCount )
        ? val(insertQ.NewID[1]) : 0;

      if ( result.REQUESTID LTE 0 ) {
        return { SUCCESS=false, MESSAGE="Failed to create request (no ID returned)." };
      }
    } catch (any e) {
      writeLog(file="application", text="Flex insert error: " & e.message & " :: " & e.detail);
      return { SUCCESS=false, MESSAGE=e.message, DETAILS=e.detail };
    }

    // --- 2) OPTIONAL attachment → FILESTREAM table ---
    var hadUpload = false;
    var up = {};
    var tmpPath = "";
    var MAX_BYTES = 10 * 1024 * 1024; // 10 MB

    try {
      if ( findNoCase("multipart/form-data", ct) AND structKeyExists(form, "file") ) {
        up = fileUpload( getTempDirectory(), "file", "*", "makeunique" );
        tmpPath   = up.serverDirectory & "/" & up.serverFile;
        hadUpload = fileExists(tmpPath);
        if ( hadUpload AND up.fileSize GT MAX_BYTES ) {
          fileDelete(tmpPath);
          hadUpload = false;
          writeLog(file="application", text="Flex upload skipped: exceeds 10 MB (" & up.fileSize & " bytes).");
        }
      }
    } catch (any upErr) {
      writeLog(file="application", text="Flex upload error: " & upErr.message & " :: " & upErr.detail);
      hadUpload = false;
      if ( len(tmpPath) AND fileExists(tmpPath) ) fileDelete(tmpPath);
    }

    if ( hadUpload ) {
      try {
        var fileBytes = fileReadBinary( tmpPath );
        fileDelete( tmpPath );

        var saveName = len(payload.filename) ? payload.filename : ( up.clientFile ?: up.serverFile );
        var saveType = len(payload.filetype) ? payload.filetype : ( up.contentType ?: "application/octet-stream" );

        queryExecute(
          "
            INSERT INTO PCSV_dw.dbo.FlexTimeFileStorage
              (FileName, FileType, FileContent, UploadedAt, RequestID, RowGuid)
            VALUES
              (:fn, :ft, :fc, GETDATE(), :rid, NEWID())
          ",
          {
            fn  : { value=left(saveName,255),   cfsqltype="cf_sql_varchar" },
            ft  : { value=left(saveType,100),   cfsqltype="cf_sql_varchar" },
            fc  : { value=fileBytes,            cfsqltype="cf_sql_blob" },
            rid : { value=result.REQUESTID,     cfsqltype="cf_sql_integer" }
          },
          { datasource="pcsv_dw" }
        );

        result.ATTACHMENT_SAVED = true;
      } catch (any insErr) {
        writeLog(file="application", text="Flex filestream insert error: " & insErr.message & " :: " & insErr.detail);
        result.ATTACHMENT_SAVED = false;
      }
    }

    // --- EMAIL: send receipt to the submitter (non-blocking) ---
    try {
      sendSubmitEmail( createdByVal, payload, result );
    } catch (any mailErr) {
      writeLog(
        file = "application",
        text = "FlexService.post outer mail error: " & mailErr.message & " :: " & mailErr.detail
      );
    }
    // --- end EMAIL block ---

    // --- Done ---
    result.SUCCESS = true;
    result.MESSAGE = result.ATTACHMENT_SAVED ? "Request submitted; attachment saved." : "Request submitted; no attachment saved.";
    return result;
  }


  // ----------------------------------------------------------------------
  // Helper: send the submit receipt email (unchanged behavior)
  // ----------------------------------------------------------------------
  private void function sendSubmitEmail(
    required string createdByVal,
    required struct payload,
    required struct result
  ) output="false" {

    // Normalize DOMAIN\user → user (Chr(92) = '\')
    var backslash = Chr(92);
    if ( find(backslash, arguments.createdByVal) ) {
      arguments.createdByVal = listLast(arguments.createdByVal, backslash);
    }

    // 1) Resolve recipient (CSAW)
    var toEmail       = "";
    var submitterName = arguments.createdByVal;

    try {
      var qMailQ = new Query();
      qMailQ.setDatasource("pcsv_dw");
      qMailQ.setSQL("
          SELECT TOP 1
                 NULLIF(LTRIM(RTRIM(user_email)),'') AS userEmail,
                 LTRIM(RTRIM(COALESCE(user_fname,'') + ' ' + COALESCE(user_lname,''))) AS userName
            FROM PCSV_csaw.dbo.csaw_pw
           WHERE user_id = :uid
      ");
      qMailQ.addParam( value = arguments.createdByVal, cfsqltype = "cf_sql_varchar" );
      var qMail = qMailQ.execute().getResult();

      if ( qMail.recordCount ) {
        if ( len(trim(qMail.userEmail[1])) ) { toEmail       = trim(qMail.userEmail[1]); }
        if ( len(trim(qMail.userName[1])) )  { submitterName = trim(qMail.userName[1]); }
      }
    } catch (any __lookupErr) {
      // ignore; fallback below
    }

    if ( NOT len(toEmail) AND structKeyExists(arguments.payload, "notifyEmail") ) {
      toEmail = trim( arguments.payload.notifyEmail );
    }

    // 2) Facility display name (optional)
    var facilityName = "";
    try {
      var qFacQ = new Query();
      qFacQ.setDatasource("pcsv_dw");
      qFacQ.setSQL("
          SELECT TOP 1 B_FIN_NAME
            FROM PCSV_dw.dbo.var_base
           WHERE B_FIN_NBR = ?
      ");
      qFacQ.addParam( value = arguments.payload.facility, cfsqltype = "cf_sql_varchar" );
      var qFac = qFacQ.execute().getResult();
      if ( qFac.recordCount ) { facilityName = qFac.B_FIN_NAME[1]; }
    } catch (any __facErr) {
      // ignore
    }

    // 3) Build reqForEmail (plain struct)
    var reqForEmail = structNew();
    reqForEmail.requestId        = arguments.result.REQUESTID;
    reqForEmail.facilityId       = arguments.payload.facility;
    reqForEmail.facilityName     = facilityName;
    reqForEmail.craft            = arguments.payload.craft;
    reqForEmail.ldc              = arguments.payload.operation;
    reqForEmail.operationNumber  = arguments.payload.operationCode;
    reqForEmail.hours            = arguments.payload.hours;
    reqForEmail.justification    = arguments.payload.justification;
    reqForEmail.startDate        = arguments.payload.wk_start & "";
    reqForEmail.endDate          = arguments.payload.wk_end & "";
    reqForEmail.attachmentSaved  = arguments.result.ATTACHMENT_SAVED;
    reqForEmail.submitterName    = submitterName;
    reqForEmail.submitterId      = arguments.createdByVal;

    // 4) Send (DB Mail → CFMAIL fallback) via your MailService
    try {
      if ( len(toEmail) ) {
        var mailer = createObject("component", "ref.api.v1.toolbox.flex.flexmail").init();
        var ok = mailer.sendFlexSubmission( toEmail, reqForEmail );

        writeLog(
          file = "application",
          text = "FlexService.post mail result id=" & arguments.result.REQUESTID &
                 " to=" & toEmail & " ok=" & ok
        );
      } else {
        writeLog(
          file = "application",
          text = "FlexService.post: no recipient email for submitter " & arguments.createdByVal & "; skipping mail."
        );
      }
    } catch (any __sendErr) {
      writeLog(
        file = "application",
        text = "FlexService.post mail exception id=" & arguments.result.REQUESTID &
               " msg=" & __sendErr.message & " :: " & __sendErr.detail
      );
    }
  }



  /**
   * (Optional) Simple download endpoint for latest file on a request.
   * Behavior unchanged.
   */
  function downloadAttachment( required numeric requestID )
    access="remote" returnFormat="plain" output="true" {

    var q = queryExecute("
      SELECT TOP 1 FileName, FileType, FileContent
      FROM PCSV_dw.dbo.FlexTimeFileStorage
      WHERE RequestID = :rid
      ORDER BY UploadedAt DESC
    ", { rid: { value=arguments.requestID, cfsqltype="cf_sql_integer" } }, { datasource="pcsv_dw" });

    if (!q.recordCount) {
      cfheader(statuscode="404", statustext="Not Found");
      writeOutput("No attachment found for RequestID=" & arguments.requestID);
      return;
    }

    var fn = q.FileName[1];
    var ft = len(q.FileType[1]) ? q.FileType[1] : "application/octet-stream";

    cfheader(name="Content-Type", value=ft);
    cfheader(name="Content-Disposition", value='attachment; filename="' & fn & '"');
    cfcontent(type=ft, variable=q.FileContent[1], reset=true);
  }

  /**
   * Compatibility endpoint for index.js::notifyAfterSubmit().
   * Behavior unchanged (no-op send).
   */
  function sendSubmitEmails( numeric requestId = 0 )
    access="remote" returnFormat="JSON" produces="application/json" output="false" {

    setJsonHeader();
    // Intentionally NO-OP to avoid double-send; post() dispatches the submit receipt.
    return { SUCCESS: true, SENT: false, MESSAGE: "Submission receipt was sent during post()." };
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

function getAccess(string userid) access="remote" returnFormat="json" produces="application/json" {
        cfheader( name="Content-Type", value="application/json;charset=UTF-8" );
        
        local.sql = "
            select
                UPPER(user_id) as ACE_ID,
                user_idx as user_idx,
                user_area_code as UserAreaCode,
                user_district_code as UserDistrictCode,
                user_area as AreaAccessInd,
                user_district as DistrictAccessInd,
                user_unit as UnitAccessInd,
                user_fname as UserFirstName,
                user_lname as UserLastName,
                user_email as UserEmail,
                user_pw as user_adhoc_ind,
                CASE
                    WHEN len(user_list) >6 THEN LEFT(user_list, CHARINDEX(',', user_list) -1)
                    ELSE user_list
                end AS FirstFinance
            FROM pcsv_csaw.dbo.csaw_pw with(nolock)
            where user_id = :user_id
        ";

        local.q = queryExecute(
            local.sql,
            {
                user_id: { value: arguments.userid, cfsqltype: "cf_sql_varchar" }
            },
            { datasource: "pcsv_dw" }
        )
        
        return queryToArray( local.q )
    }


}

