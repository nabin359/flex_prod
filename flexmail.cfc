<cfcomponent output="false" hint="Mailer via SQL Server Database Mail with CFMAIL fallback (tag-based)">
  <!-- === CONFIG === -->
  <cfset variables.mailDsn     = "pcsv_dw">
  <cfset variables.profileName = "DB Monitor">
  <cfset variables.smtpFrom    = "Workhour Efficiency <nabin.timsina@usps.gov>">

  <!-- ============================================================= -->
  <!-- init: allow overriding DSN/profile/from, return this for chaining -->
  <!-- ============================================================= -->
  <cffunction name="init" access="public" returntype="any" output="false">
    <cfargument name="mailDsn"     type="string" required="false" default="">
    <cfargument name="profileName" type="string" required="false" default="">
    <cfargument name="smtpFrom"    type="string" required="false" default="">

    <cfif len(arguments.mailDsn)>
      <cfset variables.mailDsn = arguments.mailDsn>
    </cfif>
    <cfif len(arguments.profileName)>
      <cfset variables.profileName = arguments.profileName>
    </cfif>
    <cfif len(arguments.smtpFrom)>
      <cfset variables.smtpFrom = arguments.smtpFrom>
    </cfif>

    <cfreturn this>
  </cffunction>

  <!-- ============================================================= -->
  <!-- Generic send: DB Mail first, CFMAIL fallback. Returns boolean -->
  <!-- ============================================================= -->
  <cffunction name="sendHtml" access="public" returntype="boolean" output="false">
    <cfargument name="toEmail" type="string"  required="true">
    <cfargument name="subject" type="string"  required="true">
    <cfargument name="html"    type="string"  required="true">
    <cfargument name="cc"      type="string"  required="false" default="">
    <cfargument name="bcc"     type="string"  required="false" default="">
    <cfargument name="replyTo" type="string"  required="false" default="">
    <cfargument name="from"    type="string"  required="false" default="#variables.smtpFrom#">

    <cfset var ok       = true>
    <cfset var bodyHtml = arguments.html>

      <cftry>
        <cfmail
          to      ="#arguments.toEmail#"
          from    ="#arguments.from#"
          cc      ="#arguments.cc#"
          bcc     ="#arguments.bcc#"
          subject ="#arguments.subject#"
          type    ="html"
          charset ="utf-8">
          #bodyHtml#
        </cfmail>

        <cflog file="application" text="MailService CFMAIL OK -> #arguments.toEmail# :: #arguments.subject#">
        <cfreturn true>

        <cfcatch type="any">
          <cflog file="application" text="MailService CFMAIL FAIL: #cfcatch.message# :: #cfcatch.detail#">
          <cfreturn false>
        </cfcatch>
      </cftry>

    <cfreturn ok>
  </cffunction>

  <!-- ============================== -->
  <!-- Helpers to build Flex messages -->
  <!-- ============================== -->

  <cffunction name="_safe" access="private" returntype="string" output="false">
    <cfargument name="v" required="true">

    <cfset var s = "">
    <cftry>
      <cfset s = encodeForHtml( toString( arguments.v & "" ) )>
      <cfcatch type="any">
        <cfset s = toString( arguments.v & "" )>
      </cfcatch>
    </cftry>

    <cfreturn s>
  </cffunction>

  <cffunction name="_summarySimple" access="private" returntype="string" output="false">
    <cfargument name="req" type="struct" required="true">

    <cfset var data          = arguments.req>
    <cfset var requestId     = "">
    <cfset var facilityId    = "">
    <cfset var facilityName  = "">
    <cfset var craft         = "">
    <cfset var ldc           = "">
    <cfset var opnum         = "">
    <cfset var hours         = "">
    <cfset var startDate     = "">
    <cfset var endDate       = "">
    <cfset var justification = "">
    <cfset var facDisplay    = "">
    <cfset var h             = "">

    <cfif structKeyExists(data, "requestId")>
      <cfset requestId = _safe(data.requestId)>
    </cfif>
    <cfif structKeyExists(data, "facilityId")>
      <cfset facilityId = _safe(data.facilityId)>
    </cfif>
    <cfif structKeyExists(data, "facilityName")>
      <cfset facilityName = _safe(data.facilityName)>
    </cfif>
    <cfif structKeyExists(data, "craft")>
      <cfset craft = _safe(data.craft)>
    </cfif>
    <cfif structKeyExists(data, "ldc")>
      <cfset ldc = _safe(data.ldc)>
    </cfif>
    <cfif structKeyExists(data, "operationNumber")>
      <cfset opnum = _safe(data.operationNumber)>
    </cfif>
    <cfif structKeyExists(data, "hours")>
      <cfset hours = _safe(data.hours)>
    </cfif>
    <cfif structKeyExists(data, "startDate")>
      <cfset startDate = _safe(data.startDate)>
    </cfif>
    <cfif structKeyExists(data, "endDate")>
      <cfset endDate = _safe(data.endDate)>
    </cfif>
    <cfif structKeyExists(data, "justification")>
      <cfset justification = _safe(data.justification)>
    </cfif>

    <cfset facDisplay = facilityId>
    <cfif len(facilityName)>
      <cfset facDisplay = facDisplay & " - " & facilityName>
    </cfif>

    <cfset h = h & "<b>Request ID:</b> " & requestId & "<br>">
    <cfset h = h & "<b>Facility:</b> " & facDisplay & "<br>">
    <cfset h = h & "<b>Craft:</b> " & craft & "<br>">
    <cfset h = h & "<b>LDC:</b> " & ldc & "<br>">
    <cfset h = h & "<b>Operation number:</b> " & opnum & "<br>">
    <cfset h = h & "<b>Hours/week:</b> " & hours & "<br>">
    <cfset h = h & "<b>Weeks:</b> " & startDate & " to " & endDate & "<br>">

    <cfif len(justification)>
      <cfset h = h & "<br><b>Justification:</b><br>" & justification & "<br>">
    </cfif>

    <cfreturn h>
  </cffunction>

  <cffunction name="_submitHtml" access="private" returntype="string" output="false">
    <cfargument name="req" type="struct" required="true">

    <cfset var url = "https://eagnmnwbc1db.usps.gov/rework/flex_time/dashboard.html">
    <cfset var nm  = "">
    <cfset var h   = "">

    <cfif structKeyExists(arguments.req, "submitterName")>
      <cfset nm = _safe(arguments.req.submitterName)>
    </cfif>

    <cfset h = "<div style='font-family:Segoe UI,Arial,sans-serif'>">

    <cfif len(nm)>
      <cfset h = h & "Hello " & nm & ",<br><br>">
    <cfelse>
      <cfset h = h & "Hello,<br><br>">
    </cfif>

    <cfset h = h & "Your Flex Time request has been <b>submitted</b> and is pending review.<br><br>">
    <!-- <cfset h = h & _summarySimple(arguments.req)> -->
    <cfset h = h & "<br><a href='" & url & "'>Open dashboard</a>">
    <cfset h = h & "</div>">

    <cfreturn h>
  </cffunction>

  <cffunction name="sendFlexSubmission" access="public" returntype="boolean" output="false">
    <cfargument name="toEmail" type="string" required="true">
    <cfargument name="req"     type="struct" required="true">
    <cfargument name="cc"      type="string" required="false" default="">
    <cfargument name="bcc"     type="string" required="false" default="">
    <cfargument name="replyTo" type="string" required="false" default="">
    <cfargument name="from"    type="string" required="false" default="#variables.smtpFrom#">


    <cfset var subjectId  = "">
    <cfset var subject    = "">
    <cfset var htmlBody   = "">
    <cfset var sendResult = false>

    <cfif structKeyExists(arguments.req, "requestId")>
      <cfset subjectId = arguments.req.requestId>
    </cfif>

    <cfset subject  = "Flex Time request submitted (ID " & subjectId & ")">
    <cfset htmlBody = _submitHtml(arguments.req)>

    <!-- Use positional params to avoid any weirdness -->
    <cfset sendResult = sendHtml(
      arguments.toEmail,
      subject,
      htmlBody,
      arguments.cc,
      arguments.bcc,
      arguments.replyTo,
      arguments.from
    )>

    <cfreturn sendResult>
  </cffunction>

  <cffunction name="sendStatusChangeEmail" access="public" returntype="boolean" output="false">
    <cfargument name="toEmail" type="string" required="true">
    <cfargument name="reqID"     type="string" required="true">
    <cfargument name="subject"     type="string" required="true">
    <cfargument name="html"     type="string" required="true">
    <cfargument name="from"    type="string" required="false" default="#variables.smtpFrom#">


  
    <cfset var sendResult = false>


    <!-- Use positional params to avoid any weirdness -->
    <cfset sendResult = sendHtml(
      arguments.toEmail,
      arguments.subject,
      arguments.html,
      arguments.from
    )>

    <cfreturn sendResult>
  </cffunction>
</cfcomponent>
