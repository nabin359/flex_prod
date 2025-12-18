component {

  /**
   * Summary metrics used by the cards and chart (user scope).
   */
  remote any function getDashboardData(required string userid)
    returnFormat="JSON" produces="application/json" output="false" {

    cfheader(name="Content-Type", value="application/json;charset=UTF-8");

    /** filter condition change (user-scoped) **/
    var q = queryExecute(
      "
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN Status='Pending'  THEN 1 ELSE 0 END) AS pending,
        SUM(CASE WHEN Status='Approved' THEN 1 ELSE 0 END) AS approved,
        SUM(CASE WHEN Status='Modify'   THEN 1 ELSE 0 END) AS Modified,
        SUM(CASE WHEN Status='Declined' THEN 1 ELSE 0 END) AS declined
      FROM PCSV_dw.dbo.FlexTimeRequests
      WHERE CreatedBy = :uid
      ",
      { uid: { value: arguments.userid, cfsqltype: "cf_sql_varchar" } },
      { datasource: "pcsv_dw" }
    );

    return {
      TOTAL        : q.total,
      PENDING      : q.Pending,
      APPROVED     : q.Approved,
      MODIFICATION : q.Modified,
      DECLINED     : q.Declined
    };
  }


  /**
   * Header values for banner: facility name, current FY and week (user scope).
   */
  remote any function getHeaderData(required string userid)
    returnFormat="JSON" produces="application/json" output="false" {

    cfheader(name="Content-Type", value="application/json;charset=UTF-8");

    var hdr = {};

    // Facility name for the current user (based on any of their requests)
    var qFac = queryExecute(
      "
      SELECT TOP 1
             cp.user_id,
             vb.B_FIN_NAME AS officeName
        FROM PCSV_csaw.dbo.csaw_pw cp
        JOIN PCSV_dw.dbo.FlexTimeRequests ftr
          ON cp.user_id = ftr.CreatedBy
        JOIN PCSV_dw.dbo.var_base vb
          ON ftr.FacilityID = vb.B_FIN_NBR
       WHERE cp.user_id = :uid
       ORDER BY ftr.CreatedDate DESC
      ",
      { uid: { value: arguments.userid, cfsqltype: "cf_sql_varchar" } },
      { datasource: "pcsv_dw" }
    );

    hdr.officeName = qFac.recordCount ? qFac.officeName[1] : "Unknown Facility";

    // Current FY/week from master calendar
    var qWeek = queryExecute(
      "
      SELECT TOP 1
             cal_fy_long AS fiscalYear,
             cal_fy_wk   AS week
        FROM PCSV_dw.dbo.Master_Calendar
       WHERE :today BETWEEN cal_date_beg_wk AND cal_date_end_wk
       ORDER BY cal_id DESC
      ",
      { today: { value: now(), cfsqltype: "cf_sql_timestamp" } },
      { datasource: "pcsv_dw" }
    );

    if ( qWeek.recordCount ) {
      hdr.fiscalYear = qWeek.fiscalYear[1];
      hdr.week       = qWeek.week[1];
    } else {
      hdr.fiscalYear = "";
      hdr.week       = "";
    }

    return hdr;
  }


  /**
   * Returns rows for the user’s table (only their requests).
   * Dynamically pulls AREA/MPOO-like columns if present on var_base.
   */
  remote any function getFlexRequests(required string userid)
    returnFormat="JSON" produces="application/json" output="false" {

    cfheader(name="Content-Type", value="application/json;charset=UTF-8");

    // --- Detect optional Area / MPOO columns on var_base safely ---
    var areaCandidates = "AREA,AREA_NAME,AREA_DESC,AREA_NM,AREANAME";
    var mpooCandidates = "MPOO,MPOO_GROUP,MPOO_GRP,MPOO_DESC,MPOO_NAME";
    var quoted = listQualify(areaCandidates & "," & mpooCandidates, "'", ",");
    var cols = queryExecute(
      "
      SELECT UPPER(COLUMN_NAME) AS COL
        FROM INFORMATION_SCHEMA.COLUMNS
       WHERE TABLE_SCHEMA = 'dbo'
         AND TABLE_NAME   = 'var_base'
         AND COLUMN_NAME IN (#quoted#)
      ",
      {},
      { datasource: "pcsv_dw" }
    );

    var areaCol = "NULL";
    var mpooCol = "NULL";
    for ( var r = 1; r <= cols.recordCount; r++ ) {
      var c = cols.COL[r];
      if ( areaCol EQ "NULL" AND listFindNoCase(areaCandidates, c) ) areaCol = "vb." & c;
      if ( mpooCol  EQ "NULL" AND listFindNoCase(mpooCandidates, c) ) mpooCol = "vb." & c;
    }

    var areaExpr = areaCol;
    var mpooExpr = mpooCol;

    var raw = queryExecute(
      "
      SELECT
        ftr.RequestID,
        ftr.FacilityID,
        ftr.Craft,
        ftr.LabourDistributionCode,
        ftr.OperationNumber,
        ftr.HoursPerWeek,
        ftr.Justification,
        ftr.Status,
        ftr.ModifiedBy,
        CONVERT(VARCHAR(10), ftr.StartDate, 23) AS StartDate,
        CONVERT(VARCHAR(10), ftr.EndDate,   23) AS EndDate,
        ftr.CreatedBy,
        cp.user_fname,
        cp.user_lname,
        CONVERT(VARCHAR(19), ftr.CreatedDate, 120) AS CreatedOn,

        vb.B_FIN_NAME AS FacilityName,
        #areaExpr#    AS AreaName,
        #mpooExpr#    AS MPOOGroup,

        -- Latest audit comment (optional)
        fta.Comment     AS LatestComment,
        fta.ChangedBy   AS LatestChangedBy,
        CONVERT(VARCHAR(19), fta.ChangedDate, 120) AS LatestChangedDate,

        CASE
          WHEN ISNULL(ftr.Status,'Pending') = 'Modify'                THEN 0
          WHEN ISNULL(ftr.Status,'Pending') <> 'Pending'              THEN 1
          WHEN ftr.ModifiedBy IS NOT NULL                             THEN 1
          WHEN EXISTS (SELECT 1 FROM PCSV_dw.dbo.FlexTimeAudit a
                        WHERE a.RequestID = ftr.RequestID)            THEN 1
          ELSE 0
        END AS IsLocked

      FROM pcsv_dw.dbo.FlexTimeRequests ftr
      LEFT JOIN PCSV_csaw.dbo.csaw_pw cp
              ON ftr.CreatedBy = cp.user_id
      LEFT  JOIN PCSV_dw.dbo.var_base vb
              ON vb.B_FIN_NBR  = ftr.FacilityID

      -- Latest comment per request
      LEFT JOIN (
        SELECT x.RequestID, x.Comment, x.ChangedBy, x.ChangedDate
          FROM (
            SELECT
              a.RequestID, a.Comment, a.ChangedBy, a.ChangedDate,
              ROW_NUMBER() OVER (PARTITION BY a.RequestID ORDER BY a.ChangedDate DESC) AS rn
            FROM PCSV_dw.dbo.FlexTimeAudit a
          ) x
         WHERE x.rn = 1
      ) fta ON fta.RequestID = ftr.RequestID

      WHERE ftr.CreatedBy = :currentUserAce
      ORDER BY CreatedOn DESC
      ",
      { currentUserAce: { value: arguments.userid, cfsqltype: "cf_sql_varchar" } },
      { datasource: "pcsv_dw" }
    );

    var out = [];
    for ( var i = 1; i <= raw.recordCount; i++ ) {
      arrayAppend(out, {
        REQUESTID              : raw["RequestID"][i],
        FACILITYID             : raw["FacilityID"][i],
        FACILITYNAME           : raw["FacilityName"][i],
        AREA                   : raw["AreaName"][i],
        MPOO                   : raw["MPOOGroup"][i],
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
        LOCKED                 : raw["IsLocked"][i],  // 0 or 1
        COMMENT                : raw["LatestComment"][i],
        CHANGEDBY              : raw["LatestChangedBy"][i],
        CHANGEDDATE            : raw["LatestChangedDate"][i]
      });
    }

    return out;
  }


  /**
   * Returns counts by status for each of the last 15 days.
   */
  remote any function getTrendData15Days()
    returnFormat="JSON" produces="application/json" output="false" {

    cfheader(name="Content-Type", value="application/json;charset=UTF-8");

    var q = queryExecute(
      "
      SELECT
        CONVERT(VARCHAR(10), CreatedDate, 23) AS DayDate,  -- YYYY-MM-DD
        COUNT(*) AS Total,
        SUM(CASE WHEN Status='Pending'  THEN 1 ELSE 0 END) AS Pending,
        SUM(CASE WHEN Status='Approved' THEN 1 ELSE 0 END) AS Approved,
        SUM(CASE WHEN Status='Declined' THEN 1 ELSE 0 END) AS Declined
      FROM PCSV_dw.dbo.FlexTimeRequests
      WHERE CreatedDate >= DATEADD(day, -14, GETDATE())
      GROUP BY CONVERT(VARCHAR(10), CreatedDate, 23)
      ORDER BY DayDate
      ",
      [],
      { datasource: "pcsv_dw" }
    );

    var out = [];
    for ( var i = 1; i <= q.recordCount; i++ ) {
      arrayAppend(out, {
        DayDate  : q.DayDate[i],
        Total    : q.Total[i],
        Pending  : q.Pending[i],
        Approved : q.Approved[i],
        Declined : q.Declined[i]
      });
    }

    return out;
  }


  /**
   * Allow the requester (non-admin) to edit their own Pending request,
   * only if the request has NOT been touched by admin.
   *
   * Accepts form/multipart or application/json.
   */
  remote any function updateUserRequest(
    numeric requestId = 0,
    any     hours     = "",     // optional
    string  justification = "", // optional
    string  startDate = "",     // optional, YYYY-MM-DD
    string  endDate   = "",      // optional, YYYY-MM-DD
    required string userid
  ) returnFormat="JSON" produces="application/json" output="false" {

    cfheader(name="Content-Type", value="application/json;charset=UTF-8");

    // Merge JSON body if present
    var http = getHTTPRequestData();
    var ct   = lcase( toString( http.headers["Content-Type"] ?: http.headers["content-type"] ?: "" ) );
    if ( findNoCase("application/json", ct) AND len(trim(http.content)) ) {
      try {
        var j = deserializeJSON(http.content);
        if ( structKeyExists(j,"requestId") )    arguments.requestId    = val(j.requestId);
        if ( structKeyExists(j,"hours") )        arguments.hours        = j.hours;
        if ( structKeyExists(j,"justification") )arguments.justification= toString(j.justification);
        if ( structKeyExists(j,"startDate") )    arguments.startDate    = toString(j.startDate);
        if ( structKeyExists(j,"endDate") )      arguments.endDate      = toString(j.endDate);
      } catch ( any __e ) { /* ignore parse errors */ }
    }

    var rid = val(arguments.requestId);
    if ( rid LTE 0 ) return { SUCCESS:false, MESSAGE:"requestId is required." };

    // Verify ownership + lock condition
    var row = queryExecute(
      "
      SELECT TOP 1
             CreatedBy,
             ISNULL(Status,'Pending') AS CurrStatus,
             CASE
               WHEN ISNULL(Status,'Pending') = 'Modify' THEN 0
               WHEN ISNULL(Status,'Pending') <> 'Pending' THEN 1
               WHEN ModifiedBy IS NOT NULL THEN 1
               WHEN EXISTS (SELECT 1 FROM PCSV_dw.dbo.FlexTimeAudit a WHERE a.RequestID = :rid) THEN 1
               ELSE 0
             END AS IsLocked
        FROM PCSV_dw.dbo.FlexTimeRequests
       WHERE RequestID = :rid
      ",
      { rid: { value: rid, cfsqltype: "cf_sql_integer" } },
      { datasource: "pcsv_dw" }
    );

    if ( !row.recordCount )                     return { SUCCESS:false, MESSAGE:"Request not found." };
    if ( row.CreatedBy[1] NEQ arguments.userid ) return { SUCCESS:false, MESSAGE:"Not your request." };
    if ( row.IsLocked[1] )                      return { SUCCESS:false, MESSAGE:"Request is locked by admin; cannot modify." };

    // Build dynamic SET clause
    var sets   = [];
    var params = { rid: { value: rid, cfsqltype: "cf_sql_integer" } };

    if ( structKeyExists(arguments,"hours") AND isNumeric(arguments.hours) ) {
      arrayAppend(sets, "HoursPerWeek = :hours");
      params.hours = { value: arguments.hours, cfsqltype: "cf_sql_numeric" };
    }
    if ( len(arguments.justification) ) {
      arrayAppend(sets, "Justification = :justification");
      params.justification = { value: arguments.justification, cfsqltype: "cf_sql_varchar" };
    }
    if ( len(arguments.startDate) ) {
      arrayAppend(sets, "StartDate = :sd");
      params.sd = { value: arguments.startDate, cfsqltype: "cf_sql_date" };
    }
    if ( len(arguments.endDate) ) {
      arrayAppend(sets, "EndDate = :ed");
      params.ed = { value: arguments.endDate, cfsqltype: "cf_sql_date" };
    }

    if ( arrayLen(sets) EQ 0 ) return { SUCCESS:false, MESSAGE:"No updatable fields provided." };

    try {
      queryExecute(
        "UPDATE PCSV_dw.dbo.FlexTimeRequests SET #arrayToList(sets, ', ')# WHERE RequestID = :rid",
        params,
        { datasource: "pcsv_dw" }
      );

      // Flip back to Pending if previous status was Modify
      if ( compareNoCase(row.CurrStatus[1], "Modify") EQ 0 ) {
        queryExecute(
          "
          UPDATE PCSV_dw.dbo.FlexTimeRequests
             SET Status = 'Pending',
                 ModifiedBy = NULL,
                 ModifiedDate = GETDATE()
           WHERE RequestID = :rid
          ",
          { rid: { value: rid, cfsqltype: "cf_sql_integer" } },
          { datasource: "pcsv_dw" }
        );
      }

      var q = queryExecute(
        "
        SELECT
          RequestID, FacilityID, Craft, LabourDistributionCode, OperationNumber,
          HoursPerWeek, Justification, Status,
          CONVERT(VARCHAR(10), StartDate, 23) AS StartDate,
          CONVERT(VARCHAR(10), EndDate,   23) AS EndDate,
          CreatedBy, CONVERT(VARCHAR(19), CreatedDate, 120) AS CreatedOn
        FROM PCSV_dw.dbo.FlexTimeRequests
        WHERE RequestID = :rid
        ",
        { rid: { value: rid, cfsqltype: "cf_sql_integer" } },
        { datasource: "pcsv_dw" }
      );

      if ( !q.recordCount ) return { SUCCESS:false, MESSAGE:"Reload failed." };

      var data = {
        REQUESTID              : q.RequestID[1],
        FACILITYID             : q.FacilityID[1],
        CRAFT                  : q.Craft[1],
        LABOURDISTRIBUTIONCODE : q.LabourDistributionCode[1],
        OPERATIONNUMBER        : q.OperationNumber[1],
        HOURSPERWEEK           : q.HoursPerWeek[1],
        JUSTIFICATION          : q.Justification[1],
        STATUS                 : q.Status[1],
        STARTDATE              : q.StartDate[1],
        ENDDATE                : q.EndDate[1],
        CREATEDBY              : q.CreatedBy[1],
        CREATEDON              : q.CreatedOn[1]
      };

      // --- EMAIL: confirm user edit (non-blocking) ---
      try {
        var createdByAce = ( row.recordCount ? toString(row.CreatedBy[1]) : "" );
        var toEmail = "";
        var uname   = "";

        if ( len(createdByAce) ) {
          var mailQ = queryExecute(
            "
            SELECT TOP 1
                   NULLIF(LTRIM(RTRIM(COALESCE(user_email, email, mail))), '') AS userEmail,
                   LTRIM(RTRIM(COALESCE(user_fname,'') + ' ' + COALESCE(user_lname,''))) AS userName
              FROM PCSV_csaw.dbo.csaw_pw
             WHERE user_id = :uid
            ",
            { uid: { value: createdByAce, cfsqltype: "cf_sql_varchar" } },
            { datasource: "pcsv_dw" }
          );
          if ( mailQ.recordCount ) {
            toEmail = trim(mailQ.userEmail[1] ?: "");
            uname   = trim(mailQ.userName[1]  ?: "");
          }
        }

        if ( len(toEmail) ) {
          var mailer = new ref.api.v1.toolbox.flex.flexmail();
          var reqForEmail = {
            requestId       : q.RequestID[1],
            facilityId      : q.FacilityID[1],
            craft           : q.Craft[1],
            ldc             : q.LabourDistributionCode[1],
            operationNumber : q.OperationNumber[1],
            hours           : q.HoursPerWeek[1],
            justification   : q.Justification[1],
            startDate       : q.StartDate[1],
            endDate         : q.EndDate[1],
            attachmentSaved : false,
            submitterName   : uname
          };
          mailer.sendFlexUserEdited( toEmail = toEmail, req = reqForEmail );
        }
      } catch ( any __mailErr ) {
        writeLog(file="application", text="dashboardservice.updateUserRequest mail error: #__mailErr.message# :: #__mailErr.detail#");
      }

      return { SUCCESS:true, MESSAGE:"Updated.", DATA:data };

    } catch ( any e ) {
      writeLog(file="application", text="updateUserRequest error: " & e.message & " :: " & e.detail);
      return { SUCCESS:false, MESSAGE:e.message, DETAILS:e.detail };
    }
  }


  /**
   * Allow the requester to delete their own Pending request,
   * only if the request has NOT been touched by admin.
   */
  remote any function deleteUserRequest(
    numeric requestId = 0,
    required string userid
  ) returnFormat="JSON" produces="application/json" output="false" {

    cfheader(name="Content-Type", value="application/json;charset=UTF-8");

    var rid = val(arguments.requestId);

    // Support JSON body as well
    var http = getHTTPRequestData();
    var ct   = lcase( toString( http.headers["Content-Type"] ?: http.headers["content-type"] ?: "" ) );
    if ( findNoCase("application/json", ct) AND len(trim(http.content)) ) {
      try {
        var j = deserializeJSON(http.content);
        if ( structKeyExists(j,"requestId") ) rid = val(j.requestId);
      } catch ( any __e ) { /* ignore */ }
    }

    if ( rid LTE 0 ) return { SUCCESS:false, MESSAGE:"requestId is required." };

    var row = queryExecute(
      "
      SELECT TOP 1
             CreatedBy,
             ISNULL(Status,'Pending') AS CurrStatus,
             CASE
               WHEN ISNULL(Status,'Pending') = 'Modify' THEN 0
               WHEN ISNULL(Status,'Pending') <> 'Pending' THEN 1
               WHEN ModifiedBy IS NOT NULL THEN 1
               WHEN EXISTS (SELECT 1 FROM PCSV_dw.dbo.FlexTimeAudit a WHERE a.RequestID = :rid) THEN 1
               ELSE 0
             END AS IsLocked
        FROM PCSV_dw.dbo.FlexTimeRequests
       WHERE RequestID = :rid
      ",
      { rid: { value: rid, cfsqltype: "cf_sql_integer" } },
      { datasource: "pcsv_dw" }
    );

    if ( !row.recordCount )                    return { SUCCESS:false, MESSAGE:"Request not found." };
    if ( row.CreatedBy[1] NEQ arguments.userid )return { SUCCESS:false, MESSAGE:"Not your request." };
    if ( row.IsLocked[1] )                     return { SUCCESS:false, MESSAGE:"Request is locked by admin; cannot delete." };

    // Prefetch minimal row to include in email
    var prev = queryExecute(
      "
      SELECT TOP 1
             RequestID, FacilityID, Craft, LabourDistributionCode, OperationNumber,
             HoursPerWeek, CONVERT(VARCHAR(10), StartDate, 23) AS StartDate,
             CONVERT(VARCHAR(10), EndDate,   23) AS EndDate, CreatedBy, Justification
        FROM PCSV_dw.dbo.FlexTimeRequests
       WHERE RequestID = :rid
      ",
      { rid: { value: rid, cfsqltype: "cf_sql_integer" } },
      { datasource: "pcsv_dw" }
    );

    try {
      transaction {
        queryExecute(
          "DELETE FROM PCSV_dw.dbo.FlexTimeFileStorage WHERE RequestID = :rid",
          { rid: { value: rid, cfsqltype: "cf_sql_integer" } },
          { datasource: "pcsv_dw" }
        );

        queryExecute(
          "DELETE FROM PCSV_dw.dbo.FlexTimeRequests WHERE RequestID = :rid",
          { rid: { value: rid, cfsqltype: "cf_sql_integer" } },
          { datasource: "pcsv_dw" }
        );
      }

      // --- EMAIL: confirm user delete (non-blocking) ---
      try {
        var createdByAce = ( prev.recordCount ? toString(prev.CreatedBy[1]) : "" );
        var toEmail = "";
        var uname   = "";

        if ( len(createdByAce) ) {
          var mailQ = queryExecute(
            "
            SELECT TOP 1
                   NULLIF(LTRIM(RTRIM(COALESCE(user_email, email, mail))), '') AS userEmail,
                   LTRIM(RTRIM(COALESCE(user_fname,'') + ' ' + COALESCE(user_lname,''))) AS userName
              FROM PCSV_csaw.dbo.csaw_pw
             WHERE user_id = :uid
            ",
            { uid: { value: createdByAce, cfsqltype: "cf_sql_varchar" } },
            { datasource: "pcsv_dw" }
          );
          if ( mailQ.recordCount ) {
            toEmail = trim(mailQ.userEmail[1] ?: "");
            uname   = trim(mailQ.userName[1]  ?: "");
          }
        }

        if ( len(toEmail) ) {
          var mailer = new ref.api.v1.toolbox.flex.flexmail();
          var reqForEmail = {
            requestId       : prev.RequestID[1],
            facilityId      : prev.FacilityID[1],
            craft           : prev.Craft[1],
            ldc             : prev.LabourDistributionCode[1],
            operationNumber : prev.OperationNumber[1],
            hours           : prev.HoursPerWeek[1],
            justification   : prev.Justification[1],
            startDate       : prev.StartDate[1],
            endDate         : prev.EndDate[1],
            submitterName   : uname,
            submitterId     : createdByAce
          };
          mailer.sendFlexUserEdited( toEmail = toEmail, req = reqForEmail );
        }
      } catch ( any __mailErr ) {
        writeLog(file="application", text="dashboardservice.deleteUserRequest mail error: #__mailErr.message# :: #__mailErr.detail#");
      }

      return { SUCCESS:true, MESSAGE:"Deleted." };

    } catch ( any e ) {
      writeLog(file="application", text="deleteUserRequest error: " & e.message & " :: " & e.detail);
      return { SUCCESS:false, MESSAGE:e.message, DETAILS:e.detail };
    }
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



