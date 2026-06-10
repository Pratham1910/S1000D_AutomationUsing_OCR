<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:xlink="http://www.w3.org/1999/xlink">
  <xsl:output method="html" indent="yes" encoding="UTF-8"/>
  <xsl:strip-space elements="*"/>
  <xsl:key name="appById" match="content/referencedApplicGroup/applic" use="@id"/>
  <xsl:key name="taskByApplic" match="content/maintPlanning/taskDefinition[@applicRefId]" use="@applicRefId"/>
  <xsl:key name="anyByApplic" match="content/maintPlanning/taskDefinition[@applicRefId] | content/maintPlanning/timeLimitInfo[@applicRefId]" use="@applicRefId"/>

  <xsl:template match="/dmodule">
    <html lang="en">
      <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <title>
          <xsl:value-of select="normalize-space(identAndStatusSection/dmAddress/dmAddressItems/dmTitle/techName)"/>
          <xsl:text> - </xsl:text>
          <xsl:value-of select="normalize-space(identAndStatusSection/dmAddress/dmAddressItems/dmTitle/infoName)"/>
        </title>
        <style>
          :root {
            --bg: #f4f7fb;
            --paper: #ffffff;
            --ink: #172033;
            --muted: #5b6b84;
            --line: #dbe4f1;
            --head: #153f74;
            --head-2: #2a68ad;
            --chip: #e8f1ff;
          }
          * { box-sizing: border-box; }
          body {
            margin: 0;
            background: radial-gradient(circle at 80% 0%, #dcecff 0%, var(--bg) 46%);
            color: var(--ink);
            font-family: "Segoe UI", Tahoma, sans-serif;
            line-height: 1.45;
          }
          .hero {
            padding: 20px 24px;
            color: #fff;
            background: linear-gradient(120deg, var(--head) 0%, var(--head-2) 100%);
            border-bottom: 4px solid #0f2e55;
          }
          .hero h1 {
            margin: 0;
            font-size: 24px;
            line-height: 1.2;
          }
          .hero p {
            margin: 8px 0 0;
            font-size: 14px;
            opacity: 0.95;
          }
          .wrap {
            max-width: 1320px;
            margin: 0 auto;
            padding: 18px;
          }
          .card {
            background: var(--paper);
            border: 1px solid var(--line);
            border-radius: 12px;
            box-shadow: 0 8px 24px rgba(13, 33, 62, 0.08);
            margin-bottom: 14px;
            overflow: hidden;
          }
          .card h2 {
            margin: 0;
            padding: 12px 14px;
            font-size: 18px;
            background: #f0f5fc;
            border-bottom: 1px solid var(--line);
          }
          .card .inner {
            padding: 14px;
          }
          .grid {
            display: grid;
            gap: 10px;
            grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
          }
          .kv {
            border: 1px solid var(--line);
            border-radius: 10px;
            padding: 10px;
            background: #fbfdff;
          }
          .kv .k {
            color: var(--muted);
            font-size: 12px;
            text-transform: uppercase;
            letter-spacing: .05em;
          }
          .kv .v {
            font-size: 15px;
            margin-top: 2px;
            word-break: break-word;
          }
          table {
            width: 100%;
            border-collapse: collapse;
            font-size: 13px;
          }
          th, td {
            border: 1px solid var(--line);
            padding: 7px 8px;
            vertical-align: top;
            text-align: left;
          }
          th {
            background: #eef4fb;
            font-weight: 600;
            white-space: nowrap;
          }
          .muted { color: var(--muted); }
          .chip {
            display: inline-block;
            margin: 0 4px 4px 0;
            padding: 2px 8px;
            border-radius: 999px;
            background: var(--chip);
            border: 1px solid #c8dbfb;
            font-size: 12px;
          }
          .task {
            border: 1px solid var(--line);
            border-radius: 10px;
            margin-bottom: 10px;
            overflow: hidden;
          }
          .task-head {
            background: #f6faff;
            border-bottom: 1px solid var(--line);
            padding: 10px;
            font-size: 14px;
            font-weight: 600;
          }
          .task-body {
            padding: 10px;
          }
          ul {
            margin: 8px 0;
            padding-left: 18px;
          }
          .small { font-size: 12px; }
          a { color: #0f4ea3; text-decoration: none; }
          a:hover { text-decoration: underline; }
          .filter-bar {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            align-items: center;
          }
          .filter-bar label { font-weight: 600; }
          .filter-bar select {
            border: 1px solid var(--line);
            border-radius: 8px;
            padding: 6px 10px;
            background: #fff;
            color: var(--ink);
          }
          @media (max-width: 780px) {
            .hero h1 { font-size: 20px; }
            .wrap { padding: 12px; }
          }
        </style>
      </head>
      <body>
        <div class="hero">
          <h1>
            <xsl:value-of select="normalize-space(identAndStatusSection/dmAddress/dmAddressItems/dmTitle/techName)"/>
            <xsl:text> - </xsl:text>
            <xsl:value-of select="normalize-space(identAndStatusSection/dmAddress/dmAddressItems/dmTitle/infoName)"/>
          </h1>
          <p>
            <xsl:text>Issue </xsl:text><xsl:value-of select="identAndStatusSection/dmAddress/dmIdent/issueInfo/@issueNumber"/>
            <xsl:text> / In work </xsl:text><xsl:value-of select="identAndStatusSection/dmAddress/dmIdent/issueInfo/@inWork"/>
            <xsl:text> / Language </xsl:text>
            <xsl:value-of select="identAndStatusSection/dmAddress/dmIdent/language/@languageIsoCode"/>
            <xsl:text>-</xsl:text>
            <xsl:value-of select="identAndStatusSection/dmAddress/dmIdent/language/@countryIsoCode"/>
          </p>
        </div>

        <div class="wrap">
          <div class="card">
            <h2>Document Metadata</h2>
            <div class="inner">
              <div class="grid">
                <div class="kv"><div class="k">Model</div><div class="v"><xsl:value-of select="identAndStatusSection/dmAddress/dmIdent/dmCode/@modelIdentCode"/></div></div>
                <div class="kv"><div class="k">System</div><div class="v"><xsl:value-of select="identAndStatusSection/dmAddress/dmIdent/dmCode/@systemCode"/></div></div>
                <div class="kv"><div class="k">Subsystem</div><div class="v"><xsl:value-of select="identAndStatusSection/dmAddress/dmIdent/dmCode/@subSystemCode"/>.<xsl:value-of select="identAndStatusSection/dmAddress/dmIdent/dmCode/@subSubSystemCode"/></div></div>
                <div class="kv"><div class="k">Info Code</div><div class="v"><xsl:value-of select="identAndStatusSection/dmAddress/dmIdent/dmCode/@infoCode"/><xsl:value-of select="identAndStatusSection/dmAddress/dmIdent/dmCode/@infoCodeVariant"/></div></div>
                <div class="kv"><div class="k">Issue Date</div><div class="v"><xsl:value-of select="identAndStatusSection/dmAddress/dmAddressItems/issueDate/@year"/>-<xsl:value-of select="identAndStatusSection/dmAddress/dmAddressItems/issueDate/@month"/>-<xsl:value-of select="identAndStatusSection/dmAddress/dmAddressItems/issueDate/@day"/></div></div>
                <div class="kv"><div class="k">Security Class</div><div class="v"><xsl:value-of select="identAndStatusSection/dmStatus/security/@securityClassification"/></div></div>
              </div>
            </div>
          </div>

          <xsl:if test="identAndStatusSection/dmStatus/reasonForUpdate">
            <div class="card">
              <h2>Reasons For Update</h2>
              <div class="inner">
                <ul>
                  <xsl:for-each select="identAndStatusSection/dmStatus/reasonForUpdate">
                    <li>
                      <xsl:value-of select="@id"/>
                      <xsl:text>: </xsl:text>
                      <xsl:for-each select="simplePara">
                        <xsl:value-of select="normalize-space(.)"/>
                        <xsl:if test="position() != last()">
                          <xsl:text> | </xsl:text>
                        </xsl:if>
                      </xsl:for-each>
                    </li>
                  </xsl:for-each>
                </ul>
              </div>
            </div>
          </xsl:if>

          <xsl:if test="content/referencedApplicGroup/applic or identAndStatusSection/dmStatus/applic">
            <div class="card">
              <h2>Applicability</h2>
              <div class="inner">
                <xsl:if test="identAndStatusSection/dmStatus/applic/displayText/simplePara">
                  <div class="task">
                    <div class="task-head">Default Applicability</div>
                    <div class="task-body">
                      <xsl:value-of select="normalize-space(identAndStatusSection/dmStatus/applic/displayText/simplePara)"/>
                    </div>
                  </div>
                </xsl:if>
                <xsl:for-each select="content/referencedApplicGroup/applic">
                  <div class="task">
                    <div class="task-head">
                      <xsl:text>Applic ID: </xsl:text><xsl:value-of select="@id"/>
                    </div>
                    <div class="task-body">
                      <xsl:value-of select="normalize-space(displayText/simplePara)"/>
                    </div>
                  </div>
                </xsl:for-each>
              </div>
            </div>
          </xsl:if>

          <div class="card">
            <h2>Applicability Filter</h2>
            <div class="inner">
              <div class="filter-bar">
                <label for="applicFilter">Show data for:</label>
                <select id="applicFilter">
                  <option value="ALL">All applicability</option>
                  <xsl:if test="content/maintPlanning/taskDefinition[not(@applicRefId)] or content/maintPlanning/timeLimitInfo[not(@applicRefId)]">
                    <option value="DEFAULT">Default applicability</option>
                  </xsl:if>
                  <xsl:for-each select="content/referencedApplicGroup/applic">
                    <option value="{@id}">
                      <xsl:value-of select="@id"/>
                    </option>
                  </xsl:for-each>
                  <xsl:for-each select="content/maintPlanning/taskDefinition[@applicRefId and generate-id() = generate-id(key('anyByApplic', @applicRefId)[1]) and not(key('appById', @applicRefId))] | content/maintPlanning/timeLimitInfo[@applicRefId and generate-id() = generate-id(key('anyByApplic', @applicRefId)[1]) and not(key('appById', @applicRefId))]">
                    <option value="{@applicRefId}">
                      <xsl:value-of select="@applicRefId"/>
                    </option>
                  </xsl:for-each>
                </select>
                <span class="small muted" id="applicFilterStatus">Showing all applicability</span>
              </div>
              <p class="small muted">Filter applies to Time Limits and Scheduled Maintenance Tasks.</p>
            </div>
          </div>

          <xsl:if test="content/refs/dmRef/dmRefIdent/dmCode or content/refs/externalPubRef/externalPubRefIdent">
            <div class="card">
              <h2>Document References</h2>
              <div class="inner">
                <xsl:if test="content/refs/dmRef/dmRefIdent/dmCode">
                  <p><strong>Data Module References:</strong></p>
                  <ul class="small">
                    <xsl:for-each select="content/refs/dmRef/dmRefIdent/dmCode">
                      <xsl:variable name="dmCodeText" select="concat(@modelIdentCode,'-',@systemDiffCode,'-',@systemCode,'-',@subSystemCode,@subSubSystemCode,'-',@assyCode,'-',@disassyCode,@disassyCodeVariant,'-',@infoCode,@infoCodeVariant,'-',@itemLocationCode)"/>
                      <xsl:variable name="dmHref" select="concat('DMC-', $dmCodeText, '.html')"/>
                      <li><a href="{$dmHref}"><xsl:value-of select="$dmCodeText"/></a></li>
                    </xsl:for-each>
                  </ul>
                </xsl:if>

                <xsl:if test="content/refs/externalPubRef/externalPubRefIdent">
                  <p><strong>External Publications:</strong></p>
                  <ul class="small">
                    <xsl:for-each select="content/refs/externalPubRef/externalPubRefIdent">
                      <xsl:variable name="extHref">
                        <xsl:choose>
                          <xsl:when test="@xlink:href">
                            <xsl:value-of select="@xlink:href"/>
                          </xsl:when>
                          <xsl:otherwise>
                            <xsl:value-of select="normalize-space(externalPubCode)"/>
                          </xsl:otherwise>
                        </xsl:choose>
                      </xsl:variable>
                      <li>
                        <a href="{$extHref}"><xsl:value-of select="normalize-space(externalPubCode)"/></a>
                        <xsl:text> - </xsl:text>
                        <xsl:value-of select="normalize-space(externalPubTitle)"/>
                      </li>
                    </xsl:for-each>
                  </ul>
                </xsl:if>
              </div>
            </div>
          </xsl:if>

          <xsl:apply-templates select="content/maintPlanning"/>
        </div>
        <script>
          (function () {
            var select = document.getElementById('applicFilter');
            if (!select) {
              return;
            }

            var rowsAndCards = document.querySelectorAll('[data-applic]');
            var status = document.getElementById('applicFilterStatus');

            function applyFilter() {
              var selected = select.value;
              for (var i = 0; i &lt; rowsAndCards.length; i++) {
                var el = rowsAndCards[i];
                var app = el.getAttribute('data-applic') || 'DEFAULT';
                var show = (selected === 'ALL' || app === selected);
                el.style.display = show ? '' : 'none';
              }

              if (status) {
                status.textContent = (selected === 'ALL') ? 'Showing all applicability' : ('Showing ' + selected);
              }
            }

            select.addEventListener('change', applyFilter);
            applyFilter();
          })();
        </script>
      </body>
    </html>
  </xsl:template>

  <xsl:template match="maintPlanning">
    <xsl:if test="refs/dmRef/dmRefIdent/dmCode or refs/externalPubRef/externalPubRefIdent">
      <div class="card">
        <h2>General References</h2>
        <div class="inner">
          <xsl:if test="refs/dmRef/dmRefIdent/dmCode">
            <p><strong>Data Module References:</strong></p>
            <ul class="small">
              <xsl:for-each select="refs/dmRef/dmRefIdent/dmCode">
                <xsl:variable name="dmCodeText" select="concat(@modelIdentCode,'-',@systemDiffCode,'-',@systemCode,'-',@subSystemCode,@subSubSystemCode,'-',@assyCode,'-',@disassyCode,@disassyCodeVariant,'-',@infoCode,@infoCodeVariant,'-',@itemLocationCode)"/>
                <xsl:variable name="dmHref" select="concat('DMC-', $dmCodeText, '.html')"/>
                <li><a href="{$dmHref}"><xsl:value-of select="$dmCodeText"/></a></li>
              </xsl:for-each>
            </ul>
          </xsl:if>

          <xsl:if test="refs/externalPubRef/externalPubRefIdent">
            <p><strong>External Publications:</strong></p>
            <ul class="small">
              <xsl:for-each select="refs/externalPubRef/externalPubRefIdent">
                <xsl:variable name="extHref">
                  <xsl:choose>
                    <xsl:when test="@xlink:href">
                      <xsl:value-of select="@xlink:href"/>
                    </xsl:when>
                    <xsl:otherwise>
                      <xsl:value-of select="normalize-space(externalPubCode)"/>
                    </xsl:otherwise>
                  </xsl:choose>
                </xsl:variable>
                <li>
                  <a href="{$extHref}">
                    <xsl:value-of select="normalize-space(externalPubCode)"/>
                  </a>
                  <xsl:text> - </xsl:text>
                  <xsl:value-of select="normalize-space(externalPubTitle)"/>
                </li>
              </xsl:for-each>
            </ul>
          </xsl:if>
        </div>
      </div>
    </xsl:if>

    <xsl:if test="timeLimitInfo">
      <div class="card">
        <h2>Time Limits</h2>
        <div class="inner">
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>Item</th>
                <th>Part Number</th>
                <th>Quantity</th>
                <th>Applicability</th>
                <th>Category</th>
                <th>Limits</th>
              </tr>
            </thead>
            <tbody>
              <xsl:for-each select="timeLimitInfo">
                <tr>
                  <xsl:attribute name="data-applic">
                    <xsl:choose>
                      <xsl:when test="@applicRefId"><xsl:value-of select="@applicRefId"/></xsl:when>
                      <xsl:otherwise>DEFAULT</xsl:otherwise>
                    </xsl:choose>
                  </xsl:attribute>
                  <td><xsl:value-of select="@timeLimitIdent"/></td>
                  <td><xsl:value-of select="normalize-space(equipGroup/equip/name)"/></td>
                  <td><xsl:value-of select="normalize-space(equipGroup/equip/identNumber/partAndSerialNumber/partNumber)"/></td>
                  <td>
                    <xsl:value-of select="normalize-space(reqQuantity)"/>
                    <xsl:if test="reqQuantity/@unitOfMeasure">
                      <xsl:text> </xsl:text><xsl:value-of select="reqQuantity/@unitOfMeasure"/>
                    </xsl:if>
                  </td>
                  <td>
                    <xsl:choose>
                      <xsl:when test="@applicRefId">
                        <xsl:variable name="appNode" select="key('appById', @applicRefId)[1]"/>
                        <div><strong><xsl:value-of select="@applicRefId"/></strong></div>
                        <xsl:if test="$appNode/displayText/simplePara">
                          <div class="small muted"><xsl:value-of select="normalize-space($appNode/displayText/simplePara)"/></div>
                        </xsl:if>
                      </xsl:when>
                      <xsl:otherwise>
                        <span class="muted">Default</span>
                      </xsl:otherwise>
                    </xsl:choose>
                  </td>
                  <td><xsl:value-of select="timeLimitCategory/@timeLimitCategoryValue"/></td>
                  <td>
                    <xsl:for-each select="timeLimit">
                      <div>
                        <xsl:value-of select="limitType/@limitUnitType"/>
                        <xsl:text>: </xsl:text>
                        <xsl:value-of select="limitType/threshold/thresholdValue"/>
                        <xsl:if test="limitType/threshold/@thresholdUnitOfMeasure">
                          <xsl:text> </xsl:text><xsl:value-of select="limitType/threshold/@thresholdUnitOfMeasure"/>
                        </xsl:if>
                        <xsl:if test="limitType/threshold/tolerance/@toleranceValue">
                          <xsl:text> (+/- </xsl:text><xsl:value-of select="limitType/threshold/tolerance/@toleranceValue"/><xsl:text>)</xsl:text>
                        </xsl:if>
                      </div>
                    </xsl:for-each>
                  </td>
                </tr>
              </xsl:for-each>
            </tbody>
          </table>
        </div>
      </div>
    </xsl:if>

    <xsl:if test="taskDefinition">
      <div class="card">
        <h2>Task Applicability Summary</h2>
        <div class="inner">
          <table>
            <thead>
              <tr>
                <th>Applic Ref</th>
                <th>Applicability Text</th>
                <th>Task Count</th>
                <th>Task IDs</th>
              </tr>
            </thead>
            <tbody>
              <xsl:for-each select="taskDefinition[@applicRefId and generate-id() = generate-id(key('taskByApplic', @applicRefId)[1])]">
                <xsl:sort select="@applicRefId"/>
                <xsl:variable name="appId" select="@applicRefId"/>
                <xsl:variable name="appNode" select="key('appById', $appId)[1]"/>
                <tr data-applic="{$appId}">
                  <td><xsl:value-of select="$appId"/></td>
                  <td>
                    <xsl:choose>
                      <xsl:when test="$appNode/displayText/simplePara">
                        <xsl:value-of select="normalize-space($appNode/displayText/simplePara)"/>
                      </xsl:when>
                      <xsl:otherwise><span class="muted">No referenced applicability text found</span></xsl:otherwise>
                    </xsl:choose>
                  </td>
                  <td><xsl:value-of select="count(key('taskByApplic', $appId))"/></td>
                  <td>
                    <xsl:for-each select="key('taskByApplic', $appId)">
                      <xsl:value-of select="@taskIdent"/>
                      <xsl:if test="position() != last()">
                        <xsl:text>, </xsl:text>
                      </xsl:if>
                    </xsl:for-each>
                  </td>
                </tr>
              </xsl:for-each>
              <xsl:if test="count(taskDefinition[not(@applicRefId)]) &gt; 0">
                <tr data-applic="DEFAULT">
                  <td>Default</td>
                  <td>
                    <xsl:choose>
                      <xsl:when test="/dmodule/identAndStatusSection/dmStatus/applic/displayText/simplePara">
                        <xsl:value-of select="normalize-space(/dmodule/identAndStatusSection/dmStatus/applic/displayText/simplePara)"/>
                      </xsl:when>
                      <xsl:otherwise><span class="muted">Uses module default (no explicit applicRefId)</span></xsl:otherwise>
                    </xsl:choose>
                  </td>
                  <td><xsl:value-of select="count(taskDefinition[not(@applicRefId)])"/></td>
                  <td>
                    <xsl:for-each select="taskDefinition[not(@applicRefId)]">
                      <xsl:value-of select="@taskIdent"/>
                      <xsl:if test="position() != last()">
                        <xsl:text>, </xsl:text>
                      </xsl:if>
                    </xsl:for-each>
                  </td>
                </tr>
              </xsl:if>
            </tbody>
          </table>
        </div>
      </div>

      <div class="card">
        <h2>Scheduled Maintenance Tasks</h2>
        <div class="inner">
          <xsl:for-each select="taskDefinition">
            <div class="task">
              <xsl:attribute name="data-applic">
                <xsl:choose>
                  <xsl:when test="@applicRefId"><xsl:value-of select="@applicRefId"/></xsl:when>
                  <xsl:otherwise>DEFAULT</xsl:otherwise>
                </xsl:choose>
              </xsl:attribute>
              <div class="task-head">
                <xsl:text>Task </xsl:text><xsl:value-of select="@taskIdent"/>
                <xsl:if test="@taskCode"><xsl:text> (</xsl:text><xsl:value-of select="@taskCode"/><xsl:text>)</xsl:text></xsl:if>
              </div>
              <div class="task-body">
                <p><strong>Description:</strong> <xsl:value-of select="normalize-space(task/taskDescr/simplePara)"/></p>

                <div>
                  <span class="chip"><xsl:text>Worthiness: </xsl:text><xsl:value-of select="@worthinessLimit"/></span>
                  <span class="chip"><xsl:text>Reduced Maint: </xsl:text><xsl:value-of select="@reducedMaint"/></span>
                  <xsl:if test="@skillType"><span class="chip"><xsl:text>Skill Type: </xsl:text><xsl:value-of select="@skillType"/></span></xsl:if>
                  <xsl:if test="@applicRefId"><span class="chip"><xsl:text>Applic Ref: </xsl:text><xsl:value-of select="@applicRefId"/></span></xsl:if>
                </div>

                <xsl:if test="@applicRefId">
                  <xsl:variable name="taskApplic" select="key('appById', @applicRefId)[1]"/>
                  <p class="small">
                    <strong>Applicability:</strong>
                    <xsl:text> </xsl:text>
                    <xsl:value-of select="@applicRefId"/>
                    <xsl:if test="$taskApplic/displayText/simplePara">
                      <xsl:text> - </xsl:text>
                      <xsl:value-of select="normalize-space($taskApplic/displayText/simplePara)"/>
                    </xsl:if>
                  </p>
                </xsl:if>

                <xsl:if test="preliminaryRqmts/reqPersons/person">
                  <p><strong>Required Persons:</strong></p>
                  <ul>
                    <xsl:for-each select="preliminaryRqmts/reqPersons/person">
                      <li>
                        <xsl:value-of select="normalize-space(trade)"/>
                        <xsl:text> / </xsl:text>
                        <xsl:value-of select="personCategory/@personCategoryCode"/>
                        <xsl:if test="estimatedTime">
                          <xsl:text> / </xsl:text>
                          <xsl:value-of select="normalize-space(estimatedTime)"/>
                          <xsl:text> </xsl:text>
                          <xsl:value-of select="estimatedTime/@unitOfMeasure"/>
                        </xsl:if>
                      </li>
                    </xsl:for-each>
                  </ul>
                </xsl:if>

                <xsl:if test="preliminaryRqmts/reqSupportEquips/supportEquipDescrGroup/supportEquipDescr">
                  <p><strong>Support Equipment:</strong></p>
                  <ul>
                    <xsl:for-each select="preliminaryRqmts/reqSupportEquips/supportEquipDescrGroup/supportEquipDescr">
                      <li>
                        <xsl:value-of select="normalize-space(name)"/>
                        <xsl:if test="identNumber/partAndSerialNumber/partNumber">
                          <xsl:text> (</xsl:text><xsl:value-of select="identNumber/partAndSerialNumber/partNumber"/><xsl:text>)</xsl:text>
                        </xsl:if>
                        <xsl:if test="reqQuantity">
                          <xsl:text> - </xsl:text><xsl:value-of select="normalize-space(reqQuantity)"/>
                          <xsl:if test="reqQuantity/@unitOfMeasure"><xsl:text> </xsl:text><xsl:value-of select="reqQuantity/@unitOfMeasure"/></xsl:if>
                        </xsl:if>
                      </li>
                    </xsl:for-each>
                  </ul>
                </xsl:if>

                <xsl:if test="preliminaryRqmts/reqSupplies/supplyDescrGroup/supplyDescr">
                  <p><strong>Supplies:</strong></p>
                  <ul>
                    <xsl:for-each select="preliminaryRqmts/reqSupplies/supplyDescrGroup/supplyDescr">
                      <li>
                        <xsl:value-of select="normalize-space(name)"/>
                        <xsl:if test="identNumber/partAndSerialNumber/partNumber">
                          <xsl:text> (</xsl:text><xsl:value-of select="identNumber/partAndSerialNumber/partNumber"/><xsl:text>)</xsl:text>
                        </xsl:if>
                        <xsl:if test="reqQuantity"><xsl:text> - </xsl:text><xsl:value-of select="normalize-space(reqQuantity)"/></xsl:if>
                      </li>
                    </xsl:for-each>
                  </ul>
                </xsl:if>

                <xsl:if test="limit">
                  <p><strong>Limits:</strong></p>
                  <ul>
                    <xsl:for-each select="limit">
                      <li>
                        <xsl:if test="@limitTypeValue">
                          <xsl:text>Type </xsl:text><xsl:value-of select="@limitTypeValue"/><xsl:text>; </xsl:text>
                        </xsl:if>
                        <xsl:if test="@limitCond">
                          <xsl:text>Condition </xsl:text><xsl:value-of select="@limitCond"/><xsl:text>; </xsl:text>
                        </xsl:if>
                        <xsl:if test="threshold/thresholdValue">
                          <xsl:text>Threshold </xsl:text><xsl:value-of select="threshold/thresholdValue"/>
                          <xsl:if test="threshold/@thresholdUnitOfMeasure"><xsl:text> </xsl:text><xsl:value-of select="threshold/@thresholdUnitOfMeasure"/></xsl:if>
                        </xsl:if>
                        <xsl:if test="inspectionType/@inspectionTypeCategory">
                          <xsl:text>; Inspection </xsl:text><xsl:value-of select="inspectionType/@inspectionTypeCategory"/>
                        </xsl:if>
                        <xsl:if test="limitRange">
                          <xsl:text>; Range </xsl:text>
                          <xsl:value-of select="limitRange/limitRangeFrom/threshold/thresholdValue"/>
                          <xsl:text>-</xsl:text>
                          <xsl:value-of select="limitRange/limitRangeTo/threshold/thresholdValue"/>
                        </xsl:if>
                      </li>
                    </xsl:for-each>
                  </ul>
                </xsl:if>

                <xsl:if test="refs/dmRef/dmRefIdent/dmCode">
                  <p><strong>References:</strong></p>
                  <ul class="small">
                    <xsl:for-each select="refs/dmRef/dmRefIdent/dmCode">
                      <xsl:variable name="dmCodeText" select="concat(@modelIdentCode,'-',@systemDiffCode,'-',@systemCode,'-',@subSystemCode,@subSubSystemCode,'-',@assyCode,'-',@disassyCode,@disassyCodeVariant,'-',@infoCode,@infoCodeVariant,'-',@itemLocationCode)"/>
                      <xsl:variable name="dmHref" select="concat('DMC-', $dmCodeText, '.html')"/>
                      <li>
                        <a href="{$dmHref}">
                          <xsl:value-of select="$dmCodeText"/>
                        </a>
                      </li>
                    </xsl:for-each>
                  </ul>
                </xsl:if>

                <xsl:if test="refs/externalPubRef/externalPubRefIdent">
                  <p><strong>External Publications:</strong></p>
                  <ul class="small">
                    <xsl:for-each select="refs/externalPubRef/externalPubRefIdent">
                      <xsl:variable name="extHref">
                        <xsl:choose>
                          <xsl:when test="@xlink:href">
                            <xsl:value-of select="@xlink:href"/>
                          </xsl:when>
                          <xsl:otherwise>
                            <xsl:value-of select="normalize-space(externalPubCode)"/>
                          </xsl:otherwise>
                        </xsl:choose>
                      </xsl:variable>
                      <li>
                        <a href="{$extHref}">
                          <xsl:value-of select="normalize-space(externalPubCode)"/>
                        </a>
                        <xsl:text> - </xsl:text>
                        <xsl:value-of select="normalize-space(externalPubTitle)"/>
                      </li>
                    </xsl:for-each>
                  </ul>
                </xsl:if>
              </div>
            </div>
          </xsl:for-each>
        </div>
      </div>
    </xsl:if>

    <xsl:if test="inspectionDefinition/taskGroup/taskItem">
      <div class="card">
        <h2>Inspection Task Groups</h2>
        <div class="inner">
          <xsl:for-each select="inspectionDefinition/taskGroup">
            <div class="task">
              <div class="task-head">
                <xsl:text>Group </xsl:text><xsl:value-of select="@taskGroupNumber"/>
                <xsl:if test="@taskName"><xsl:text> - </xsl:text><xsl:value-of select="@taskName"/></xsl:if>
              </div>
              <div class="task-body">
                <table>
                  <thead>
                    <tr>
                      <th>Seq</th>
                      <th>Task Name</th>
                      <th>Description</th>
                      <th>Reference</th>
                    </tr>
                  </thead>
                  <tbody>
                    <xsl:for-each select="taskItem">
                      <tr>
                        <td><xsl:value-of select="@taskSeqNumber"/></td>
                        <td><xsl:value-of select="@taskName"/></td>
                        <td><xsl:value-of select="normalize-space(task/taskDescr/simplePara)"/></td>
                        <td>
                          <xsl:for-each select="refs/dmRef/dmRefIdent/dmCode">
                            <xsl:variable name="dmCodeText" select="concat(@modelIdentCode,'-',@systemDiffCode,'-',@systemCode,'-',@subSystemCode,@subSubSystemCode,'-',@assyCode,'-',@disassyCode,@disassyCodeVariant,'-',@infoCode,@infoCodeVariant,'-',@itemLocationCode)"/>
                            <xsl:variable name="dmHref" select="concat('DMC-', $dmCodeText, '.html')"/>
                            <div class="small">
                              <a href="{$dmHref}">
                                <xsl:value-of select="@systemCode"/><xsl:text>-</xsl:text><xsl:value-of select="@infoCode"/><xsl:value-of select="@infoCodeVariant"/>
                              </a>
                            </div>
                          </xsl:for-each>
                        </td>
                      </tr>
                    </xsl:for-each>
                  </tbody>
                </table>
              </div>
            </div>
          </xsl:for-each>
        </div>
      </div>
    </xsl:if>

    <xsl:if test="maintAllocation/maintAllocationGroup">
      <div class="card">
        <h2>Maintenance Allocation Chart</h2>
        <div class="inner">
          <xsl:if test="maintAllocation/title">
            <p><strong>Allocation Title:</strong> <xsl:value-of select="normalize-space(maintAllocation/title)"/></p>
          </xsl:if>
          <table>
            <thead>
              <tr>
                <th>Group</th>
                <th>Component</th>
                <th>Skill</th>
                <th>Function</th>
                <th>Level</th>
                <th>Tools</th>
                <th>Remarks</th>
              </tr>
            </thead>
            <tbody>
              <xsl:for-each select="maintAllocation/maintAllocationGroup">
                <xsl:variable name="grp" select="groupNumber"/>
                <xsl:variable name="comp" select="normalize-space(componentAssy/name)"/>
                <xsl:variable name="skill" select="@skillLevelCode"/>
                <xsl:for-each select="maintQualifier">
                  <tr>
                    <td><xsl:value-of select="$grp"/></td>
                    <td><xsl:value-of select="$comp"/></td>
                    <td><xsl:value-of select="$skill"/></td>
                    <td><xsl:value-of select="maintFunction/@function"/></td>
                    <td>
                      <xsl:for-each select="maintLevelGroup/maintLevel">
                        <div>
                          <xsl:value-of select="@maintLevelCode"/><xsl:text>: </xsl:text><xsl:value-of select="normalize-space(.)"/>
                        </div>
                      </xsl:for-each>
                    </td>
                    <td>
                      <xsl:for-each select="toolsRefs/internalRef">
                        <div>
                          <a href="#{@internalRefId}"><xsl:value-of select="@internalRefId"/></a>
                        </div>
                      </xsl:for-each>
                    </td>
                    <td>
                      <xsl:for-each select="remarksRefs/internalRef">
                        <div>
                          <a href="#{@internalRefId}"><xsl:value-of select="@internalRefId"/></a>
                        </div>
                      </xsl:for-each>
                    </td>
                  </tr>
                </xsl:for-each>
              </xsl:for-each>
            </tbody>
          </table>

          <xsl:if test="toolsList/toolsListGroup">
            <h3>Tools Legend</h3>
            <table>
              <thead>
                <tr>
                  <th>Tool ID</th>
                  <th>Code</th>
                  <th>Name</th>
                </tr>
              </thead>
              <tbody>
                <xsl:for-each select="toolsList/toolsListGroup">
                  <tr id="{toolRef/@id}">
                    <td><xsl:value-of select="toolRef/@id"/></td>
                    <td><xsl:value-of select="toolsListCode"/></td>
                    <td><xsl:value-of select="normalize-space(name)"/></td>
                  </tr>
                </xsl:for-each>
              </tbody>
            </table>
          </xsl:if>

          <xsl:if test="remarksGroup/remarksList/remarks">
            <h3>Remarks</h3>
            <ul>
              <xsl:for-each select="remarksGroup/remarksList/remarks">
                <li id="{@remarkCode}">
                  <xsl:value-of select="@remarkCode"/><xsl:text>: </xsl:text>
                  <xsl:value-of select="normalize-space(simplePara)"/>
                </li>
              </xsl:for-each>
            </ul>
          </xsl:if>
        </div>
      </div>
    </xsl:if>

    <xsl:if test="*[not(self::timeLimitInfo or self::taskDefinition or self::inspectionDefinition or self::maintAllocation)]">
      <div class="card">
        <h2>Additional Sections</h2>
        <div class="inner">
          <ul>
            <xsl:for-each select="*[not(self::timeLimitInfo or self::taskDefinition or self::inspectionDefinition or self::maintAllocation)]">
              <li><xsl:value-of select="name()"/></li>
            </xsl:for-each>
          </ul>
        </div>
      </div>
    </xsl:if>
  </xsl:template>

  <xsl:template match="text()"/>
</xsl:stylesheet>
