@echo off
setlocal enabledelayedexpansion

rem ======================================================================
rem  Markdown (.md) to S1000D AsciiDoc Converter
rem  Supports all 21 DM schema types (S1000D Issue 4.2 / 6.0)
rem
rem  Usage:  Converter_md_S1000D.bat [dm-type]
rem
rem  dm-type options (21 schemas):
rem    descript               Descriptive
rem    procedure              Procedural (generic)
rem    fault                  Fault isolation
rem    proced                 Procedural (structured, with sub-sections)
rem    sched                  Scheduled maintenance
rem    container              Container
rem    crew                   Crew / operator information
rem    sb                     Service bulletin
rem    pim                    Preliminary information
rem    chkl                   Checklist
rem    learning               Learning / CBT training
rem    frontmatter            Front matter (title page, TOC)
rem    appliccrossreftable    Applicability cross-reference table
rem    condcrossreftable      Condition cross-reference table
rem    functionalitem         Functional item repository
rem    partrepository         Parts repository
rem    illustratedpartscatalog  Illustrated parts catalog (IPC)
rem    wrngdata               Wiring data
rem    comrepository          Comments repository
rem    brex                   Business rules exchange
rem    techrep                Technical report
rem
rem  If no dm-type is supplied the script auto-detects:
rem    infoCode 000  -> proced
rem    everything else -> descript
rem ======================================================================

set "globalDocType=%1"
set "inputDir=MarkdownDocuments"
set "outputDir=AsciiDoc"
set "cleanupScript=.\cleanup.ps1"
set "luaFilter=.\Ruby\s1000d_md_styles.lua"

if not exist "%outputDir%" mkdir "%outputDir%"

if not exist "%cleanupScript%" (
    echo WARNING: cleanup.ps1 not found. Cleanup step will be skipped.
)

echo.
echo ======================================================================
echo  Markdown to S1000D AsciiDoc Conversion
echo ======================================================================
echo  Input Directory  = %inputDir%
echo  Output Directory = %outputDir%
echo.

rem -----------------------------------------------------------------------
rem  Loop over every .md file in the input directory
rem -----------------------------------------------------------------------
for /F "delims=" %%f in ('dir /b /a-d "%inputDir%\*.md" 2^>nul') do (
    set "rawfile=%%~nf"
    set "filename=!rawfile!"
    set "outputFile=%outputDir%\!filename!.adoc"

    set "firstTwo=!filename:~0,2!"
    if "!firstTwo!"=="~$" (
        echo STATUS: SKIPPED temporary file: %%~nxf
        echo.
    ) else (

        echo ---------------------------------------------------------------
        echo  Processing: %%~nxf

        rem -------------------------------------------------------------------
        rem  DMC filename parsing
        rem -------------------------------------------------------------------
        set "finalDMC=!filename!"
        set "wasConverted=false"
        set "infoCode="

        set "prefix=!filename:~0,4!"
        if /I "!prefix!"=="DMC-" (
            set "baseCode=!filename:DMC-=!"
            for /f "tokens=1-9 delims=-" %%a in ("!baseCode!") do (
                if not "%%i"=="" (
                    set "p1=%%a"
                    set "p2=%%b"
                    set "p3=%%c"
                    set "p4=%%d"
                    set "p5=%%e"
                    set "p6=%%f"
                    set "p7=%%g"
                    set "p8=%%h"
                    set "p9=%%i"
                    set "wasConverted=true"

                    set "subSystemCode=!p4:~0,1!"
                    set "subSubSystemCode=!p4:~1,1!"
                    set "disassyCode=!p7:~0,-1!"
                    set "disassyCodeVariant=!p7:~-1!"
                    set "infoCode=!p8:~0,-1!"
                    set "infoCodeVariant=!p8:~-1!"
                    set "finalDMC=!p1!-!p2!-!p3!-!subSystemCode!-!subSubSystemCode!-!p5!-!p6!-!disassyCode!-!disassyCodeVariant!-!infoCode!-!infoCodeVariant!-!p9!"
                )
            )
        )

        if "!wasConverted!"=="true" (
            echo  Original filename : !filename!
            echo  Converted DMC     : !finalDMC!
        ) else (
            echo  WARNING: Not a standard DMC filename. Using filename as DMC reference.
        )

        rem -------------------------------------------------------------------
        rem  Determine DM type
        rem -------------------------------------------------------------------
        set "docType=descript"
        if defined globalDocType (
            set "docType=!globalDocType!"
            if /I "!docType!"=="schedule"              set "docType=sched"
            if /I "!docType!"=="scheduled"             set "docType=sched"
            if /I "!docType!"=="scheduled maintenance" set "docType=sched"
            echo  DM type override  : !docType!
        ) else (
            if "!wasConverted!"=="true" (
                if defined infoCode (
                    if "!infoCode!"=="000" set "docType=proced"
                )
            )
        )
        echo  DM type selected  : !docType!

        rem -------------------------------------------------------------------
        rem  Write AsciiDoc header skeleton (calls :WriteHeader subroutine)
        rem -------------------------------------------------------------------
        call :WriteHeader "!docType!" "!outputFile!" "!finalDMC!"

        rem -------------------------------------------------------------------
        rem  Convert Markdown to AsciiDoc body using Pandoc
        rem -------------------------------------------------------------------
        echo  STATUS: Running Pandoc...
        if exist "%luaFilter%" (
            pandoc "%inputDir%\%%~nxf" --lua-filter "%luaFilter%" -t asciidoc >> "!outputFile!"
        ) else (
            pandoc "%inputDir%\%%~nxf" -t asciidoc >> "!outputFile!"
        )

        rem -------------------------------------------------------------------
        rem  Append closeout footer for 'proced' type
        rem -------------------------------------------------------------------
        if /I "!docType!"=="proced" (
            (
                echo.
                echo [[closeout_reqs]]
                echo == Closeout Requirements
                echo.
                echo [[closeout_conds_after]]
                echo === Required Conditions After Job Completion
                echo.
            ) >> "!outputFile!"
        )

        rem -------------------------------------------------------------------
        rem  Run cleanup script
        rem -------------------------------------------------------------------
        if exist "%cleanupScript%" (
            echo  STATUS: Running cleanup script...
            powershell -ExecutionPolicy Bypass -File "%cleanupScript%" -FilePath "!outputFile!"
        )

        echo  STATUS: COMPLETED ^-^> !outputFile!
        echo.
    )
)

echo ----------------------------------------------------------------------
echo  Conversion Process Complete.
echo ======================================================================
pause
exit /b 0


rem ========================================================================
rem  SUBROUTINE: WriteHeader
rem    %~1  docType
rem    %~2  outputFile (full path)
rem    %~3  finalDMC
rem ========================================================================

:WriteHeader
set "_type=%~1"
set "_out=%~2"
set "_dmc=%~3"

if /I "!_type!"=="descript"                goto :hdr_descript
if /I "!_type!"=="procedure"               goto :hdr_procedure
if /I "!_type!"=="fault"                   goto :hdr_fault
if /I "!_type!"=="proced"                  goto :hdr_proced
if /I "!_type!"=="sched"                   goto :hdr_sched
if /I "!_type!"=="schedule"                goto :hdr_sched
if /I "!_type!"=="scheduled"               goto :hdr_sched
if /I "!_type!"=="container"               goto :hdr_container
if /I "!_type!"=="crew"                    goto :hdr_crew
if /I "!_type!"=="sb"                      goto :hdr_sb
if /I "!_type!"=="pim"                     goto :hdr_pim
if /I "!_type!"=="chkl"                    goto :hdr_chkl
if /I "!_type!"=="learning"                goto :hdr_learning
if /I "!_type!"=="frontmatter"             goto :hdr_frontmatter
if /I "!_type!"=="appliccrossreftable"     goto :hdr_appliccrossreftable
if /I "!_type!"=="condcrossreftable"       goto :hdr_condcrossreftable
if /I "!_type!"=="functionalitem"          goto :hdr_functionalitem
if /I "!_type!"=="partrepository"          goto :hdr_partrepository
if /I "!_type!"=="illustratedpartscatalog" goto :hdr_illustratedpartscatalog
if /I "!_type!"=="wrngdata"                goto :hdr_wrngdata
if /I "!_type!"=="comrepository"           goto :hdr_comrepository
if /I "!_type!"=="brex"                    goto :hdr_brex
if /I "!_type!"=="techrep"                 goto :hdr_techrep
rem  Unknown type — fall through to descript
goto :hdr_descript


rem ---- 1. descript ---------------------------------------------------
:hdr_descript
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: descript
    echo :dm-title: Component Description
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[description]]
    echo == Description
    echo.
) > "!_out!"
exit /b

rem ---- 2. procedure --------------------------------------------------
:hdr_procedure
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: procedure
    echo :dm-title: Maintenance Procedure
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[prelim_reqs]]
    echo == Preliminary Requirements
    echo.
    echo [[main_proc]]
    echo == Procedure
    echo . Perform maintenance step
    echo.
) > "!_out!"
exit /b

rem ---- 3. fault ------------------------------------------------------
:hdr_fault
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: fault
    echo :dm-title: Fault Isolation
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[fault_reporting]]
    echo == Fault Reporting
    echo.
    echo [[fault_isolation]]
    echo == Fault Isolation
    echo . Check fault indicator
    echo.
) > "!_out!"
exit /b

rem ---- 4. proced (structured procedural) ----------------------------
:hdr_proced
(
    echo = Procedural Data Module
    echo :dmc: DMC-!_dmc!
    echo :dm-type: procedural
    echo :dm-title: Step-by-Step Procedure
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo :s1000d-schema-base-path: http://www.s1000d.org/S1000D_4-2/xml_schema_flat/
    echo.
    echo [[prelim_reqs]]
    echo == Preliminary Requirements
    echo.
    echo [[required_conditions_pr]]
    echo === Required Conditions
    echo.
    echo [[required_persons_pr]]
    echo === Required Persons
    echo.
    echo [[required_tech_info_pr]]
    echo === Required Technical Information
    echo.
    echo [[required_equip_pr]]
    echo === Required Support Equipment
    echo.
    echo [[required_supplies_pr]]
    echo === Required Supplies
    echo.
    echo [[required_spares_pr]]
    echo === Required Spares
    echo.
    echo [[required_safety_pr]]
    echo === Required Safety
    echo.
    echo [[main_proc_steps]]
    echo == Main Procedure
    echo.
) > "!_out!"
exit /b

rem ---- 5. sched ------------------------------------------------------
:hdr_sched
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: sched
    echo :dm-title: Scheduled Maintenance Tasks
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[prelim_reqs]]
    echo == Preliminary Requirements
    echo.
    echo [[sched_tasks]]
    echo == Scheduled Maintenance Tasks
    echo . Perform scheduled inspection tasks.
    echo . Record status and maintenance findings.
    echo.
) > "!_out!"
exit /b

rem ---- 6. container --------------------------------------------------
:hdr_container
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: container
    echo :dm-title: Container Data Module
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[container_content]]
    echo == Container Content
    echo.
) > "!_out!"
exit /b

rem ---- 7. crew -------------------------------------------------------
:hdr_crew
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: crew
    echo :dm-title: Crew and Operator Information
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[crew_roles]]
    echo == Crew Roles
    echo.
    echo [[crew_procedures]]
    echo == Crew Procedures
    echo.
) > "!_out!"
exit /b

rem ---- 8. sb (service bulletin) --------------------------------------
:hdr_sb
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: sb
    echo :dm-title: Service Bulletin
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[sb_planning]]
    echo == Planning Information
    echo.
    echo [[sb_procedure]]
    echo == Service Bulletin Procedure
    echo.
) > "!_out!"
exit /b

rem ---- 9. pim (preliminary information) ------------------------------
:hdr_pim
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: pim
    echo :dm-title: Preliminary Information
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[prelim_info]]
    echo == Preliminary Information
    echo.
) > "!_out!"
exit /b

rem ---- 10. chkl (checklist) ------------------------------------------
:hdr_chkl
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: chkl
    echo :dm-title: Maintenance Checklist
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[checklist_items]]
    echo == Checklist Items
    echo . Inspect component A
    echo . Verify torque values
    echo.
) > "!_out!"
exit /b

rem ---- 11. learning --------------------------------------------------
:hdr_learning
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: learning
    echo :dm-title: Learning and Training Module
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[learning_objectives]]
    echo == Learning Objectives
    echo.
    echo [[content]]
    echo == Content
    echo.
) > "!_out!"
exit /b

rem ---- 12. frontmatter -----------------------------------------------
:hdr_frontmatter
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: frontmatter
    echo :dm-title: Front Matter
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[title_page]]
    echo == Title Page
    echo.
    echo [[table_of_contents]]
    echo == Table of Contents
    echo.
) > "!_out!"
exit /b

rem ---- 13. appliccrossreftable ---------------------------------------
:hdr_appliccrossreftable
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: appliccrossreftable
    echo :dm-title: Applicability Cross-Reference Table
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[applicability]]
    echo == Applicability Cross-Reference
    echo.
) > "!_out!"
exit /b

rem ---- 14. condcrossreftable -----------------------------------------
:hdr_condcrossreftable
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: condcrossreftable
    echo :dm-title: Condition Cross-Reference Table
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[conditions]]
    echo == Condition Cross-Reference
    echo.
) > "!_out!"
exit /b

rem ---- 15. functionalitem --------------------------------------------
:hdr_functionalitem
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: functionalitem
    echo :dm-title: Functional Item Repository
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[functional_items]]
    echo == Functional Items
    echo.
) > "!_out!"
exit /b

rem ---- 16. partrepository --------------------------------------------
:hdr_partrepository
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: partrepository
    echo :dm-title: Parts Repository
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[parts]]
    echo == Parts List
    echo.
) > "!_out!"
exit /b

rem ---- 17. illustratedpartscatalog (IPC) ----------------------------
:hdr_illustratedpartscatalog
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: illustratedpartscatalog
    echo :dm-title: Illustrated Parts Catalog
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[ipc_general]]
    echo == General
    echo.
    echo [[ipc_parts]]
    echo == Illustrated Parts
    echo.
) > "!_out!"
exit /b

rem ---- 18. wrngdata (wiring data) ------------------------------------
:hdr_wrngdata
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: wrngdata
    echo :dm-title: Wiring Data
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[wiring_list]]
    echo == Wiring List
    echo.
    echo [[wiring_diagram]]
    echo == Wiring Diagram
    echo.
) > "!_out!"
exit /b

rem ---- 19. comrepository (comments repository) ----------------------
:hdr_comrepository
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: comrepository
    echo :dm-title: Comments Repository
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[comments]]
    echo == Comments
    echo.
) > "!_out!"
exit /b

rem ---- 20. brex ------------------------------------------------------
:hdr_brex
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: brex
    echo :dm-title: Business Rules Exchange
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[brex_rules]]
    echo == Business Rules
    echo.
    echo [[brex_applicability]]
    echo == Applicability
    echo.
) > "!_out!"
exit /b

rem ---- 21. techrep (technical report) --------------------------------
:hdr_techrep
(
    echo :dmc: DMC-!_dmc!
    echo :dm-type: techrep
    echo :dm-title: Technical Report
    echo :tech-name: Sample System
    echo :revdate: 2025-09-02
    echo :issue-number: 001
    echo :in-work: 00
    echo :lang: en
    echo :country-code: IN
    echo :security-classification: 01
    echo :responsible-partner-company: LNTDEFENCE
    echo :enterprise-code-rpc: 1671Y
    echo :originator-enterprise: LNTDEFENCE
    echo :enterprise-code-originator: 1671Y
    echo :applicability: All applicable units and serial numbers.
    echo :brex-dmc: DMC-GSV-H-041-1-0-0301-00-A-022-A-D
    echo :reason-for-update: Initial draft for demonstration purposes.
    echo.
    echo [[summary]]
    echo == Summary
    echo.
    echo [[technical_details]]
    echo == Technical Details
    echo.
) > "!_out!"
exit /b
