@echo off
setlocal enabledelayedexpansion

rem ======================================================================
rem DOCX to S1000D AsciiDoc Converter (Procedural + Descriptive + Scheduled)
rem ======================================================================

set "globalDocType=%1"
set "inputDir=StyledDocuments"
set "outputDir=AsciiDoc"
set "cleanupScript=.\cleanup.ps1"

if not exist "%outputDir%" mkdir "%outputDir%"

if not exist "%cleanupScript%" (
    echo ERROR: cleanup.ps1 not found.
    pause
    exit /b
)

echo.
echo ======================================================================
echo Starting DOCX to AsciiDoc Conversion Process
echo ======================================================================
echo Input Directory = %inputDir%
echo Output Directory = %outputDir%
echo.

rem Loop through all DOCX files
for /F "delims=" %%f in ('dir /b /a-d "%inputDir%\*.docx"') do (
    set "rawfile=%%~nf"
    set "filename=!rawfile!"
    set "outputFile=%outputDir%\!filename!.adoc"

    set "firstTwo=!filename:~0,2!"
    if "!firstTwo!"=="~$" (
        echo STATUS: SKIPPED Word temporary file: %%~nxf
        echo.
    ) else (

        echo ---------------------------------------------------------------
        echo Processing: %%~nxf

        rem -----------------------
        rem DMC parsing logic
        set "baseCode=!filename:DMC-=!"
        set "finalDMC=!baseCode!"
        set "wasConverted=false"

        for /f "tokens=1-9 delims=-" %%a in ("!baseCode!") do (
            if not "%%i"=="" (
                set "p1=%%a" & set "p2=%%b" & set "p3=%%c" & set "p4=%%d"
                set "p5=%%e" & set "p6=%%f" & set "p7=%%g" & set "p8=%%h"
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

        if "!wasConverted!"=="true" (
            echo Original Base Code: !baseCode!
            echo Converted 11-part DMC: !finalDMC!
        ) else (
            echo WARNING: Not a valid 9-part DMC. Using base filename as DMC.
        )

        rem -----------------------
        rem Determine document type
        set "docType=descript"
        if defined globalDocType (
            set "docType=!globalDocType!"
            if /I "!docType!"=="schedule" set "docType=sched"
            if /I "!docType!"=="scheduled" set "docType=sched"
            if /I "!docType!"=="scheduled maintenance" set "docType=sched"
            echo STATUS: Document type override: !docType!
        ) else (
            if "!wasConverted!"=="true" (
                if defined infoCode (
                    if "!infoCode!"=="000" (
                        set "docType=proced"
                    ) else (
                        set "docType=descript"
                    )
                ) else (
                    set "docType=descript"
                )
            ) else (
                set "docType=descript"
            )
        )
        echo Document Type Selected: !docType!

        rem -----------------------
        rem Create AsciiDoc Header
        if /I "!docType!"=="sched" (
            (
                echo :dmc: DMC-!finalDMC!
                echo :dm-type: sched
                echo :issue-number: 001
                echo :dm-title: Scheduled Maintenance Module
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
            ) > "!outputFile!"
        ) else if "!docType!"=="proced" (
            (
                echo = My Procedural Data Module
                echo :dmc: DMC-!finalDMC!
                echo :dm-type: procedural
                echo :issue-number: 001
                echo :issue-date: 2023-10-26
                echo :tech-name: Comprehensive Converter Test Procedure
                echo :dm-title: Step-by-Step Guide
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
            ) > "!outputFile!"
        ) else (
            (
                echo :dmc: DMC-!finalDMC!
                echo :dm-type: descript
                echo :issue-number: 001
                echo :dm-title: Sample Descriptive Module
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
            ) > "!outputFile!"
        )

        rem -----------------------
        rem Convert DOCX → AsciiDoc using Pandoc
        echo STATUS: Converting DOCX with Pandoc...
        pandoc "%inputDir%\%%~nxf" -t asciidoc >> "!outputFile!"

        rem -----------------------
        rem Append procedural footer
        if "!docType!"=="proced" (
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

        rem -----------------------
        rem Run cleanup.ps1
        echo STATUS: Running cleanup script...
        powershell -ExecutionPolicy Bypass -File "%cleanupScript%" -FilePath "!outputFile!"

        echo STATUS: COMPLETED → !outputFile!
        echo.
    )
)

echo ----------------------------------------------------------------------
echo Conversion Process Complete.
echo ======================================================================
pause
