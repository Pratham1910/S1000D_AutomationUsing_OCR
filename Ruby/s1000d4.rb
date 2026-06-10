require 'asciidoctor'
require 'asciidoctor/helpers' # Attempt to ensure EscapeUtils is available

module Asciidoctor
  class Converter::S1000D < Converter::Base
    register_for 's1000d'

    # ... (QUOTE_TAGS, alias convert_preamble, initialize, common_attributes, esc_text, esc_content, parse_dmc_string - all same as your last code) ...
    # Define mappings for inline text formatting
    (QUOTE_TAGS = {
      monospaced: ['<verbatimText>', '</verbatimText>'],
      emphasis: ['<emphasis emphasisType="em02">', '</emphasis>'],
      strong: ['<emphasis emphasisType="em01">', '</emphasis>'],
      mark: ['<changeInline changeMark="1">', '</changeInline>'],
      superscript: ['<superScript>', '</superScript>'],
      subscript: ['<subScript>', '</subScript>']
    }).default = ['', ''] # Default for unhandled types

    alias convert_preamble content_only

    def initialize *args
      super
      basebackend 'xml'
      filetype 'xml'
      outfilesuffix '.xml'
      htmlsyntax 'xml'
    end

    def common_attributes id
      id ? %( id="#{id}") : ''
    end

    def esc_text(text)
      return '' if text.nil?
      defined?(Asciidoctor::EscapeUtils) ? Asciidoctor::EscapeUtils.escape_xml(text) : text
    end

    def esc_content(text_or_content)
      return '' if text_or_content.nil?
      return text_or_content unless text_or_content.is_a?(String)
      defined?(Asciidoctor::EscapeUtils) ? Asciidoctor::EscapeUtils.escape_xml(text_or_content) : text_or_content
    end

    def parse_dmc_string(dmc_string)
      puts "DEBUG (parse_dmc_string): Received dmc_string: '#{dmc_string}'"
      return nil unless dmc_string && dmc_string.is_a?(String) && !dmc_string.strip.empty?
      regex = /^(?:DMC-)?([A-Z0-9]{2,14})-([A-Z0-9]{1})-([A-Z0-9]{2,3})-([A-Z0-9]{1})-([A-Z0-9]{1})-([A-Z0-9]{2}|[A-Z0-9]{4})-([A-Z0-9]{2})-([A-Z0-9]{1,3})-([A-Z0-9]{3})-([A-Z0-9]{1})-([A-Z0-9]{1})$/i
      match = regex.match(dmc_string.strip)
      if match
          puts "DEBUG (parse_dmc_string): Regex MATCHED! Parts: #{match.captures.inspect}"
          return {
            modelIdentCode: match[1].upcase, systemDiffCode: match[2].upcase, systemCode: match[3].upcase,
            subSystemCode: match[4].upcase, subSubSystemCode: match[5].upcase, assyCode: match[6].upcase,
            disassyCode: match[7].upcase, disassyCodeVariant: match[8].upcase, infoCode: match[9].upcase,
            infoCodeVariant: match[10].upcase, itemLocationCode: match[11].upcase
          }
      else
          puts "DEBUG (parse_dmc_string): Regex DID NOT MATCH for input '#{dmc_string.strip}'."
          return nil
      end
    end
    # ============================================================
    # HELPER METHODS for PRELIMINARY/CLOSEOUT REQUIREMENTS (Keep these as they are)
    # ============================================================
    def generate_req_cond_group_xml(section_node)
      return "<reqCondGroup><noConds/></reqCondGroup>" unless section_node
      conditions = []
      section_node.blocks.each do |block|
        if block.context == :paragraph
          conditions << "<condition>#{block.convert}</condition>"
        elsif block.context == :ulist || block.context == :olist
          block.items.each do |item|
            text_content = item.text
            dm_ref_xml = ""
            dm_ref_attr_val = item.attr('dmref')
            if dm_ref_attr_val
              parsed_dm_ref_code = parse_dmc_string(dm_ref_attr_val)
              if parsed_dm_ref_code
                dm_ref_xml = %(<dmRef><dmRefIdent><dmCode modelIdentCode="#{parsed_dm_ref_code[:modelIdentCode]}" systemDiffCode="#{parsed_dm_ref_code[:systemDiffCode]}" systemCode="#{parsed_dm_ref_code[:systemCode]}" subSystemCode="#{parsed_dm_ref_code[:subSystemCode]}" subSubSystemCode="#{parsed_dm_ref_code[:subSubSystemCode]}" assyCode="#{parsed_dm_ref_code[:assyCode]}" disassyCode="#{parsed_dm_ref_code[:disassyCode]}" disassyCodeVariant="#{parsed_dm_ref_code[:disassyCodeVariant]}" infoCode="#{parsed_dm_ref_code[:infoCode]}" infoCodeVariant="#{parsed_dm_ref_code[:infoCodeVariant]}" itemLocationCode="#{parsed_dm_ref_code[:itemLocationCode]}"/></dmRefIdent></dmRef>)
              else
                warn "asciidoctor: WARNING: Invalid dmref attribute format: '#{dm_ref_attr_val}' on list item '#{text_content}'."
              end
            end
            item_content_xml = item.blocks? ? item.content : "<para>#{esc_text(text_content)}</para>"
            conditions << "<condition>#{item_content_xml}#{dm_ref_xml}</condition>"
          end
        else
            conditions << "<condition>#{block.convert}</condition>"
        end
      end
      return conditions.empty? ? "<reqCondGroup><noConds/></reqCondGroup>" : "<reqCondGroup>\n" + conditions.join("\n") + "\n</reqCondGroup>"
    end

    def generate_req_persons_xml(section_node)
      return "" unless section_node
      table_node = section_node.blocks.find { |b| b.context == :table }
      return "" unless table_node
      personnel_entries = []
      table_node.rows.body.each do |row_cells|
        desc_text        = row_cells[0] ? esc_text(row_cells[0].text.strip) : "N/A"
        category_code    = row_cells[1] ? esc_text(row_cells[1].text.strip.upcase) : "MAINT"
        skill_level_code = row_cells[2] ? esc_text(row_cells[2].text.strip) : "01"
        number_val       = row_cells[3] ? esc_text(row_cells[3].text.strip) : "1"
        time_val         = row_cells[4] ? esc_text(row_cells[4].text.strip) : "0.0"
        time_unit        = (row_cells[5] && !row_cells[5].text.strip.empty?) ? esc_text(row_cells[5].text.strip.downcase) : "h"
        personnel_entries << <<~PERSON_ENTRY
          <personnel>
            <personnelIdent categoryCode="#{category_code}" skillLevelCode="#{skill_level_code}"><personnelDesc>#{desc_text}</personnelDesc></personnelIdent>
            <numberOfPersonnel value="#{number_val}"/><estimatedTime value="#{time_val}" timeUnit="#{time_unit}"/>
          </personnel>
        PERSON_ENTRY
      end
      return personnel_entries.empty? ? "" : "<reqPersons>\n" + personnel_entries.join("\n") + "\n</reqPersons>"
    end
    
    def generate_table_based_req_list(section_node, list_tag, item_tag, no_item_tag, cols_map)
      return "<#{list_tag}>#{no_item_tag}</#{list_tag}>" unless section_node
      table_node = section_node.blocks.find { |b| b.context == :table }
      if !table_node
        if section_node.blocks.length == 1 && section_node.blocks.first.context == :paragraph
          content = section_node.blocks.first.source.downcase
          if content.include?("no ") && (content.include?(item_tag.downcase) || content.include?(list_tag.downcase.gsub(/^req|s$/,'')))
            return "<#{list_tag}>#{no_item_tag}</#{list_tag}>"
          end
        end
        return "<#{list_tag}>#{no_item_tag}</#{list_tag}>"
      end
      item_xml_entries = []
      table_node.rows.body.each do |row_cells|
        name_text = row_cells[cols_map[:name]] ? esc_text(row_cells[cols_map[:name]].text.strip) : "N/A"
        mfr_code_text = (cols_map[:mfr] && row_cells[cols_map[:mfr]]) ? esc_text(row_cells[cols_map[:mfr]].text.strip) : ""
        part_no_text  = (cols_map[:pn] && row_cells[cols_map[:pn]])  ? esc_text(row_cells[cols_map[:pn]].text.strip)  : ""
        qty_text      = row_cells[cols_map[:qty]] ? esc_text(row_cells[cols_map[:qty]].text.strip) : "1"
        uom_code_text = (cols_map[:uom] && row_cells[cols_map[:uom]]) ? esc_text(row_cells[cols_map[:uom]].text.strip.upcase) : "EA"
        case item_tag
        when "supportEquip"; item_xml_entries << <<~ITEM
            <supportEquip><identNumber manuCode="#{mfr_code_text}" partNumber="#{part_no_text}">#{name_text}</identNumber><quantity>#{qty_text}</quantity></supportEquip>
          ITEM
        when "supply"; item_xml_entries << <<~ITEM
            <supply><supplyIdent><supplyIdentNumber manuCode="#{mfr_code_text}" partNumber="#{part_no_text}">#{name_text}</supplyIdentNumber></supplyIdent><supplyQuantity quantity="#{qty_text}" unitOfMeasure="#{uom_code_text}"/></supply>
           ITEM
        when "spare"; item_xml_entries << <<~ITEM
            <spare><itemIdent><itemIdentNumber manuCode="#{mfr_code_text}" partNumber="#{part_no_text}">#{name_text}</itemIdentNumber></itemIdent><quantityPerEquip>#{qty_text}</quantityPerEquip></spare>
           ITEM
        end
      end
      return item_xml_entries.empty? ? "<#{list_tag}>#{no_item_tag}</#{list_tag}>" : "<#{list_tag}>\n" + item_xml_entries.join("\n") + "\n</#{list_tag}>"
    end
    
    def generate_req_safety_xml(section_node)
        return "<reqSafety><noSafety/></reqSafety>" unless section_node
        safety_paras = []
        section_node.blocks.each do |block|
            if block.context == :paragraph; safety_paras << block.convert
            elsif block.context == :ulist || block.context == :olist
                block.items.each { |item| safety_paras << (item.blocks? ? item.content : "<para>#{esc_text(item.text)}</para>") }
            end
        end
        return safety_paras.empty? ? "<reqSafety><noSafety/></reqSafety>" : "<reqSafety><safetySignificant>\n" + safety_paras.join("\n") + "\n</safetySignificant></reqSafety>"
    end

    def generate_preliminary_requirements_xml(document_node)
      prelim_section = document_node.blocks.find { |b| b.context == :section && (b.id == 'prelim_reqs' || b.title.downcase.include?('preliminary requirements')) }
      req_conds_xml = "<reqCondGroup><noConds/></reqCondGroup>"; req_persons_xml = ""
      req_support_equip_xml = "<reqSupportEquips><noSupportEquips/></reqSupportEquips>"
      req_supplies_xml = "<reqSupplies><noSupplies/></reqSupplies>"
      req_spares_xml = "<reqSpares><noSpares/></reqSpares>"; req_safety_xml = "<reqSafety><noSafety/></reqSafety>"
      if prelim_section
        puts "DEBUG: Found 'Preliminary Requirements' section."
        prelim_section.blocks.each do |sub_block|
          next unless sub_block.context == :section
          id_or_title = sub_block.id ? sub_block.id.downcase : sub_block.title.downcase
          if id_or_title.include?('req_conds') || id_or_title.include?('required condition'); 
            req_conds_xml = generate_req_cond_group_xml(sub_block)
          elsif id_or_title.include?('req_persons') || id_or_title.include?('required person'); 
            req_persons_xml = generate_req_persons_xml(sub_block)
          elsif id_or_title.include?('req_equip') || id_or_title.include?('support equipment'); 
            req_support_equip_xml = generate_table_based_req_list(sub_block, "reqSupportEquips", "supportEquip", "<noSupportEquips/>", {name:0, mfr:1, pn:2, qty:3, uom:4})
          elsif id_or_title.include?('req_consum') || id_or_title.include?('consumable'); 
            req_supplies_xml = generate_table_based_req_list(sub_block, "reqSupplies", "supply", "<noSupplies/>", {name:0, mfr:1, pn:2, qty:3, uom:4})
          elsif id_or_title.include?('req_spares') || id_or_title.include?('spare'); 
            req_spares_xml = generate_table_based_req_list(sub_block, "reqSpares", "spare", "<noSpares/>", {name:0, mfr:1, pn:2, qty:3})
          elsif id_or_title.include?('req_safety') || id_or_title.include?('safety condition'); 
            req_safety_xml = generate_req_safety_xml(sub_block)
          end
        end
      else
        puts "DEBUG: 'Preliminary Requirements' section not found. Using defaults for prelimRqmts."
      end
      prelim_xml_parts = [req_conds_xml, (req_persons_xml unless req_persons_xml.empty?), req_support_equip_xml, req_supplies_xml, req_spares_xml, req_safety_xml].compact.join("\n")
      "<preliminaryRqmts>\n#{prelim_xml_parts}\n</preliminaryRqmts>"
    end
    
    def generate_main_procedure_steps_xml(document_node) # Used by 'procedure' type
      main_proc_section = document_node.blocks.find { |b| b.context == :section && (b.id == 'main_proc_steps' || b.title.downcase.include?('main procedure')) }
      steps_content = ""; blocks_to_process = []
      if main_proc_section; blocks_to_process = main_proc_section.blocks; puts "DEBUG: Found 'Main Procedure Steps' section."
      else
          blocks_to_process = document_node.blocks.reject { |b| b.context == :section && ((b.id == 'prelim_reqs' || b.title.downcase.include?('preliminary req')) || (b.id == 'closeout_reqs' || b.title.downcase.include?('closeout req'))) }
          puts "DEBUG: No 'Main Procedure Steps' section. Processing eligible blocks from root."
      end
      blocks_to_process.each_with_index do |block, index|
          if block.context == :olist
              block.items.each_with_index { |li, li_idx| steps_content << "<proceduralStep id=\"step-main-#{index}-#{li_idx}\">#{li.blocks? ? li.content : "<para>#{esc_text(li.text)}</para>"}</proceduralStep>\n" }
          else; steps_content << "<proceduralStep id=\"step-main-#{index}\">#{block.convert}</proceduralStep>\n"; end
      end
      return steps_content.empty? ? "<proceduralStep><para/></proceduralStep>" : steps_content.strip
    end

    # ============================================================
    # NEW HELPER METHOD for FAULT ISOLATION MAIN PROCEDURE
    # ============================================================
    def generate_fault_isolation_main_procedure_xml(document_node)
      # This is the core of the fault isolation.
      # It will contain <isolationStep> elements, which can be complex (question, action, end).
      # For now, a very basic placeholder.
      # You'll need to define how to author fault isolation logic in AsciiDoc.
      # Example: could look for sections with specific roles or titles.

      fault_main_section = document_node.blocks.find { |b| b.context == :section && (b.id == 'fault_iso_main' || b.title.downcase.include?('fault isolation procedure')) }
      
      isolation_steps_content = ""
      blocks_to_process = []

      if fault_main_section
          blocks_to_process = fault_main_section.blocks
          puts "DEBUG: Found 'Fault Isolation Procedure' (main) section."
      else
          blocks_to_process = document_node.blocks.reject do |b|
              b.context == :section && (
                  (b.id == 'prelim_reqs' || b.title.downcase.include?('preliminary req')) ||
                  (b.id == 'closeout_reqs' || b.title.downcase.include?('closeout req')) ||
                  # Add other sections to ignore for fault DM if any, like faultDescr
                  (b.id == 'fault_descr' || b.title.downcase.include?('fault description')) 
              )
          end
          puts "DEBUG: No dedicated 'Fault Isolation Procedure' (main) section. Processing eligible blocks from root."
      end

      # Very simple mapping: each block becomes content of an <isolationStep>.
      # S1000D <isolationStep> has children like <question>, <action>, <yesAnswer>, <noAnswer>, <isolationStepEnd>.
      # This requires a much more detailed mapping strategy.
      if blocks_to_process.empty?
        isolation_steps_content = "<isolationStep><isolationStepQuestion><para>No isolation steps defined.</para></isolationStepQuestion><yesAnswer><nextAction><gotoStandardTask targetDmRefIdent=" + '"FIXME-TARGET-DMREF"' + "/></nextAction></yesAnswer><noAnswer><nextAction><gotoStandardTask targetDmRefIdent=" + '"FIXME-TARGET-DMREF"' + "/></nextAction></noAnswer></isolationStep>" # Basic placeholder
      else
        blocks_to_process.each_with_index do |block, index|
            # This is NOT a valid S1000D isolationStep structure. Placeholder only.
            isolation_steps_content << "<isolationStep id=\"iso-step-#{index}\">#{block.convert}</isolationStep>\n"
        end
      end
      # A valid fault isolation often ends with <isolationProcedureEnd/>
      # For now, just returning the processed blocks.
      # The template shows <isolationProcedureEnd id="stp-0001"/>
      # We will add a default one if no content was generated.
      main_content = isolation_steps_content.empty? ? "<isolationProcedureEnd id=\"auto-end-0001\"/>" : isolation_steps_content.strip
      "<isolationMainProcedure>\n#{main_content}\n</isolationMainProcedure>"
    end
    
    def generate_close_requirements_xml(document_node)
      close_section = document_node.blocks.find { |b| b.context == :section && (b.id == 'closeout_reqs' || b.title.downcase.include?('closeout requirements') || b.title.downcase.include?('requirements after job completion')) }
      req_conds_xml = "<reqCondGroup><noConds/></reqCondGroup>"
      if close_section
          puts "DEBUG: Found 'Closeout Requirements' section."
          conds_subsection = close_section.blocks.find { |b| b.context == :section && (b.id == 'closeout_conds' || b.title.downcase.include?('required conditions after job completion')) }
          target_node_for_conds = conds_subsection || close_section
          req_conds_xml = generate_req_cond_group_xml(target_node_for_conds)
      else
          puts "DEBUG: 'Closeout Requirements' section not found. Using defaults for closeRqmts."
      end
      "<closeRqmts>\n#{req_conds_xml}\n</closeRqmts>"
    end

    def convert_document node
      doc_attrs = node.document.attributes
      # --- Metadata parsing (remains the same as your provided code) ---
      dmc_attr_string = doc_attrs['dmc'] || doc_attrs['part-title']; 
      dm_code_attrs = parse_dmc_string(dmc_attr_string)
      default_dm_code_values = { modelIdentCode: "S1KDTOOLS", systemDiffCode: "A", systemCode: "00", subSystemCode: "0", subSubSystemCode: "0", assyCode: "0000", disassyCode: "00", disassyCodeVariant: "A", infoCode: "000", infoCodeVariant: "A", itemLocationCode: "A" }
      if dmc_attr_string && dm_code_attrs.nil?; warn "asciidoctor: WARNING: Invalid DMC: '#{dmc_attr_string}'"; dm_code_attrs = default_dm_code_values
      elsif dm_code_attrs.nil?; dm_code_attrs = default_dm_code_values; end
      lang_code = (doc_attrs['lang'] || 'en').downcase; country_code = (doc_attrs['country-code'] || 'US').upcase
      issue_number = doc_attrs['issue-number'] || "001"; in_work_status = doc_attrs['in-work'] || "00"
      date_str = doc_attrs['revdate'] || doc_attrs['issue-date']; date_str = date_str.strip if date_str
      year, month, day = "2025", "10", "01"; if date_str && date_str.match?(/^\d{4}-\d{2}-\d{2}$/); year, month, day = date_str.split('-'); elsif date_str && !date_str.empty?; warn "asciidoctor: WARNING: Invalid date: #{date_str}"; end
      tech_name = doc_attrs['tech-name'] || node.doctitle || "Def Tech-Name"; dm_title_text = doc_attrs['dm-title'] || tech_name
      security_classification = doc_attrs['security-classification'] || "01"; responsible_partner_company = doc_attrs['responsible-partner-company'] || "UNKNOWN"
      originator_enterprise = doc_attrs['originator-enterprise'] || responsible_partner_company; applic_display_text = doc_attrs['applicability'] || "All"
      brex_dmc_string = doc_attrs['brex-dmc']; brex_dm_code_attrs = parse_dmc_string(brex_dmc_string)
      default_brex_dm_code_attrs = { modelIdentCode: "S1000D", systemDiffCode: "H", systemCode: "04", subSystemCode: "1", subSubSystemCode: "0", assyCode: "0301", disassyCode: "00", disassyCodeVariant: "A", infoCode: "022", infoCodeVariant: "A", itemLocationCode: "D" }
      if brex_dmc_string && brex_dm_code_attrs.nil?; warn "asciidoctor: WARNING: Invalid BREX DMC: '#{brex_dmc_string}'"; brex_dm_code_attrs = default_brex_dm_code_attrs
      elsif brex_dm_code_attrs.nil?; brex_dm_code_attrs = default_brex_dm_code_attrs; end
      rfu_elements = ""; rfu_text_raw = doc_attrs['reason-for-update']
      if rfu_text_raw; rfu_text_escaped = esc_text(rfu_text_raw); rfu_elements = %(\n<reasonForUpdate id="rfu-0001" updateHighlight="1" updateReasonType="urt02"><simplePara>#{rfu_text_escaped}</simplePara></reasonForUpdate>)
      else; rfu_elements = %(\n<reasonForUpdate id="rfu-0001" updateHighlight="1" updateReasonType="urt02"><simplePara>Initial issue or generic update.</simplePara></reasonForUpdate>)
      end
      # --- End Metadata Parsing ---

      dm_type = (doc_attrs['dm-type'] || 'descript').downcase.strip
      puts "DEBUG: Detected dm-type: '#{dm_type}'"

      content_markup = ""
      # --- *** MODIFIED PART for Content Structure *** ---
      case dm_type
      when 'procedure', 'procedural'
        prelim_reqs_markup = generate_preliminary_requirements_xml(node)
        main_procedure_markup = generate_main_procedure_steps_xml(node)
        close_reqs_markup = generate_close_requirements_xml(node)
        content_markup = <<~XML_PROCEDURE_CONTENT
          <procedure>
            #{prelim_reqs_markup}
            <mainProcedure>
            #{main_procedure_markup}
            </mainProcedure>
            #{close_reqs_markup}
          </procedure>
        XML_PROCEDURE_CONTENT
      when 'fault', 'faultisolation' # Handles fault and faultisolation
        # For fault, we also need <faultDescr> before <faultIsolation> typically.
        # This is a simplified version focusing on reusing prelim/close for isolation.
        # A full fault DM would parse <faultDescr> content from AsciiDoc too.
        
        # Placeholder for fault description - you'd parse this from a specific section
        fault_descr_xml = "<faultDescr><para>Fault description placeholder. Author this in AsciiDoc.</para></faultDescr>"
        
        prelim_reqs_markup = generate_preliminary_requirements_xml(node) # Reusable
        fault_iso_main_markup = generate_fault_isolation_main_procedure_xml(node) # New specific helper
        close_reqs_markup = generate_close_requirements_xml(node) # Reusable

        content_markup = <<~XML_FAULT_CONTENT
          <fault>
            #{fault_descr_xml}
            <faultIsolation>
              <faultIsolationProcedure>
                <isolationProcedure>
                  #{prelim_reqs_markup}
                  #{fault_iso_main_markup}
                  #{close_reqs_markup}
                </isolationProcedure>
              </faultIsolationProcedure>
            </faultIsolation>
          </fault>
        XML_FAULT_CONTENT
      when 'descript', 'description'
        content_markup = "<description>\n#{node.content}\n</description>"
      else
        warn "asciidoctor: WARNING: Unknown dm-type '#{dm_type}'. Defaulting to descriptive content."
        content_markup = "<description>\n#{node.content}\n</description>"
      end


      icn_ids = content_markup.scan(/ICN-[\w-]+/).uniq

      doctype_parts = []
      # Assume CGM for all ICNs as per the user's example.
      # If other NOTATIONs are needed, this logic would need to be expanded.
      # For simplicity, only declare NOTATION CGM if there are ICN entities.
      if !icn_ids.empty?
        doctype_parts << "<!NOTATION CGM SYSTEM \"CGM\">"
        icn_ids.each do |icn|
          # Assumes the file is named <icn>.CGM (e.g., ICN-XYZ.CGM)
          doctype_parts << "<!ENTITY #{esc_text(icn)} SYSTEM \"#{esc_text(icn)}.CGM\" NDATA CGM>"
        end
      end

      doctype_declaration = '<!DOCTYPE dmodule'
      if !doctype_parts.empty?
        doctype_declaration << " [\n  "
        doctype_declaration << doctype_parts.join("\n  ")
        doctype_declaration << "\n]>"
      else
        doctype_declaration << ">"
      end
      # --- End DTD Generation ---
      # --- *** END MODIFIED PART for Content Structure *** ---

      schema_file = case dm_type
                    when 'procedure', 'procedural'; 'proced.xsd'
                    when 'fault', 'faultisolation'; 'fault.xsd' # Added schema for fault
                    else 'descript.xsd'
                    end

              

      # --- XML Comment Block and Final XML Assembly (remains the same) ---
      comment_dmc_attr_string = esc_text(dmc_attr_string || 'N/A'); 
      comment_lang_code = esc_text(lang_code); 
      comment_country_code = esc_text(country_code)
      comment_issue_number = esc_text(issue_number); 
      comment_in_work_status = esc_text(in_work_status); 
      comment_date_str = esc_text(date_str || 'N/A')
      comment_tech_name_attr = esc_text(doc_attrs['tech-name'] || 'N/A (using doctitle)'); 
      comment_dm_title_attr = esc_text(doc_attrs['dm-title'] || 'N/A (using tech-name)')
      comment_security_classification = esc_text(security_classification); 
      comment_rpc = esc_text(responsible_partner_company); 
      comment_oe = esc_text(originator_enterprise)
      comment_applic = esc_text(applic_display_text); 
      comment_brex_dmc = esc_text(brex_dmc_string || 'N/A (using default)'); 
      comment_rfu = esc_text(rfu_text_raw || 'N/A (using default)')
      result = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
       #{doctype_declaration}
      <dmodule xmlns:dc="http://www.purl.org/dc/elements/1.1/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.s1000d.org/S1000D_6/xml_schema_flat/#{schema_file}">
        <identAndStatusSection>
          <dmAddress>
            <dmIdent>
              <dmCode modelIdentCode="#{dm_code_attrs[:modelIdentCode]}" systemDiffCode="#{dm_code_attrs[:systemDiffCode]}" systemCode="#{dm_code_attrs[:systemCode]}" subSystemCode="#{dm_code_attrs[:subSystemCode]}" subSubSystemCode="#{dm_code_attrs[:subSubSystemCode]}" assyCode="#{dm_code_attrs[:assyCode]}" disassyCode="#{dm_code_attrs[:disassyCode]}" disassyCodeVariant="#{dm_code_attrs[:disassyCodeVariant]}" infoCode="#{dm_code_attrs[:infoCode]}" infoCodeVariant="#{dm_code_attrs[:infoCodeVariant]}" itemLocationCode="#{dm_code_attrs[:itemLocationCode]}"/>
              <language languageIsoCode="#{lang_code}" countryIsoCode="#{country_code}"/>
              <issueInfo issueNumber="#{issue_number}" inWork="#{in_work_status}"/>
            </dmIdent>
            <dmAddressItems>
              <issueDate year="#{year}" month="#{month}" day="#{day}"/>
              <dmTitle>
                <techName>#{esc_text(tech_name)}</techName>
                <infoName>#{esc_text(dm_title_text)}</infoName>
              </dmTitle>
            </dmAddressItems>
          </dmAddress>
          <dmStatus issueType="changed">
            <security securityClassification="#{security_classification}"/>
            <responsiblePartnerCompany enterpriseCode="1671Y">
              <enterpriseName>#{esc_text(responsible_partner_company)}</enterpriseName>
            </responsiblePartnerCompany>
            <originator enterpriseCode="1671Y">
              <enterpriseName>#{esc_text(originator_enterprise)}</enterpriseName>
            </originator>
            <applic>
              <displayText>
                <simplePara>#{esc_text(applic_display_text)}</simplePara>
              </displayText>
            </applic>
            <brexDmRef>
              <dmRef>
                <dmRefIdent>
                  <dmCode modelIdentCode="#{brex_dm_code_attrs[:modelIdentCode]}" systemDiffCode="#{brex_dm_code_attrs[:systemDiffCode]}" systemCode="#{brex_dm_code_attrs[:systemCode]}" subSystemCode="#{brex_dm_code_attrs[:subSystemCode]}" subSubSystemCode="#{brex_dm_code_attrs[:subSubSystemCode]}" assyCode="#{brex_dm_code_attrs[:assyCode]}" disassyCode="#{brex_dm_code_attrs[:disassyCode]}" disassyCodeVariant="#{brex_dm_code_attrs[:disassyCodeVariant]}" infoCode="#{brex_dm_code_attrs[:infoCode]}" infoCodeVariant="#{brex_dm_code_attrs[:infoCodeVariant]}" itemLocationCode="#{brex_dm_code_attrs[:itemLocationCode]}"/>
                </dmRefIdent>
              </dmRef>
            </brexDmRef>
            <qualityAssurance>
              <unverified/>
            </qualityAssurance>
            #{rfu_elements.strip}
          </dmStatus>
        </identAndStatusSection>
        <content>
          #{content_markup.strip}
        </content>
      </dmodule>
      XML
      result.chomp
    end

    # --- Standard Block and Inline Converters (Keep all of these from your provided code) ---
    # ... (convert_paragraph, convert_ulist, convert_olist, etc. ... all the way to convert_fallback) ...
    def convert_paragraph node; 
        %(<para#{common_attributes node.id}>#{node.content}</para>); end
    def convert_ulist node; 
        result = %(<para><randomList#{common_attributes node.id}>); node.items.each { |item| result << %(<listItem>#{item.blocks? ? item.content : "<para>#{esc_text(item.text)}</para>"}</listItem>) }; result << %(</randomList></para>); end
    def convert_olist node; 
        result = %(<para><sequentialList#{common_attributes node.id}>); 
        node.items.each { |item| result << %(<listItem>#{item.blocks? ? item.content : "<para>#{esc_text(item.text)}</para>"}</listItem>) }; result << %(</sequentialList></para>); end
    def convert_dlist node; result = %(<para><definitionList#{common_attributes node.id}>); node.items.each do |terms, dd|; result << %(<definitionListItem><listItemTerm>); terms.each {|dt| result << esc_text(dt.text) }; result << %(</listItemTerm><listItemDefinition>); if dd; result << %(<para>#{esc_text(dd.text)}</para>) if dd.text?; result << dd.content if dd.blocks?; else; result << %(<para/>); end; result << %(</definitionListItem></definitionListItem>); end; result << %(</definitionList></para>); end
    def convert_section node; %(<levelledPara#{common_attributes node.id}><title>#{esc_text(node.title)}</title>#{node.content}</levelledPara>); end
    def convert_inline_anchor node; case node.type; when :xref; target = node.attributes['refid'] || node.target; target = target[1..-1] if target.start_with?('#'); %(<internalRef internalRefId="#{esc_text(target)}">#{esc_text(node.text || target)}</internalRef>); when :link; %(<externalRef destination="#{esc_text(node.target)}">#{esc_text(node.text)}</externalRef>); when :ref; ''; else; esc_text(node.text || node.target); end; end
    def convert_table node; pgwide = (node.option? 'pgwide') ? 1 : 0; frame = node.attr 'frame', 'all'; grid = node.attr 'grid', 'all'; rowsep = (grid == 'none' || grid == 'cols') ? 0 : 1; colsep = (grid == 'none' || grid == 'rows') ? 0 : 1; orient = (node.attr? 'orientation', 'landscape') ? ' land' : ''; result = %(<table#{common_attributes node.id} frame="#{frame}" pgwide="#{pgwide}" rowsep="#{rowsep}" colsep="#{colsep}"#{orient.empty? ? '' : %( orient="#{orient}")}>); result << %(<title>#{esc_text(node.title)}</title>) if node.title?; result << %(<tgroup cols="#{node.attr 'colcount'}">); node.columns.each { |col| result << %(<colspec colname="col_#{col.attr 'colnumber'}" colwidth="#{(col.attr 'width') ? "#{col.attr 'width'}*" : "1*"}"/>) }; node.rows.to_h.each do |tsec, rows|; next if rows.empty?; result << %(<t#{tsec}>); rows.each do |row|; result << %(<row>); row.each do |cell|; colnum = cell.column.attr 'colnumber'; halign = (cell.attr? 'halign') ? %( align="#{cell.attr 'halign'}") : ''; valign = (cell.attr? 'valign') ? %( valign="#{cell.attr 'valign'}") : ''; colspan = cell.colspan ? %( namest="col_#{colnum}" nameend="col_#{colnum + cell.colspan - 1}") : ''; rowspan = cell.rowspan ? %( morerows="#{cell.rowspan - 1}") : ''; entry_start = %(<entry#{halign}#{valign}#{colspan}#{rowspan}>); cell_body = case cell.style; when :asciidoc then cell.content; when :literal then %(<para><verbatimText>#{esc_text(cell.text)}</verbatimText></para>); else cell.text.empty? ? '' : %(<para>#{esc_text(cell.text)}</para>); end; result << %(#{entry_start}#{cell_body || ''}</entry>); end; result << %(</row>); end; result << %(</t#{tsec}>); end; result << %(</tgroup></table>); end
    alias convert_embedded content_only
    def convert_image node; 
        info_entity_ident = node.attr('icn') || File.basename(node.attr('target')); 
        result = %(<figure#{common_attributes node.id}>); 
        result << %(<title>#{esc_text(node.title)}</title>) if node.title?; 
        # width_attr = (node.attr? 'scaledwidth') ? %( reproductionWidth="#{node.attr 'scaledwidth'}") : (node.attr? 'width') ? %( reproductionWidth="#{node.attr 'width'}px") : ''; 
        # height_attr = (node.attr? 'scaledheight') ? %( reproductionHeight="#{node.attr 'scaledheight'}") : (node.attr? 'height') ? %( reproductionHeight="#{node.attr 'height'}px") : ''; scale_attr = (node.attr? 'scale') ? %( reproductionScale="#{node.attr 'scale'}") : ''; 

        parent_blocks = node.parent.blocks
        current_index = parent_blocks.index(node)
        next_block = parent_blocks[current_index + 1]
        icn_match = next_block&.content&.match(/ICN-[A-Z0-9\-]+/)

        image_basename = icn_match ? icn_match[0] : 'image'
        ext = File.extname(node.attr('target'))
        new_target = "#{image_basename}"
        img_target = node.image_uri(new_target)

        result << %(<graphic infoEntityIdent="#{esc_text(img_target)}"/>); 
        result << %(</figure>); 
    end
    def convert_inline_quoted node; 
        open, close = QUOTE_TAGS[node.type]; 
        attrs = common_attributes(node.id); 
        %(#{open.sub('>', "#{attrs}>")}#{esc_text(node.text)}#{close}); 
    end
    def convert_admonition node; 
        type = node.attr('name').upcase; attrs = common_attributes(node.id); 
        title_element = node.title ? "<title>#{esc_text(node.title)}</title>" : ""; 
        case type
        when 'WARNING'
          title_element = node.title? ? "<title>#{esc_text(node.title)}</title>" : ""
          %(<warning#{attrs}>#{title_element}<warningAndCautionPara>#{node.content}</warningAndCautionPara></warning>)
        when 'CAUTION'
          title_element = node.title? ? "<title>#{esc_text(node.title)}</title>" : ""
          %(<caution#{attrs}>#{title_element}<warningAndCautionPara><para>#{node.content}</para></warningAndCautionPara></caution>)
        when 'NOTE'
          # Standard S1000D <note> contains <notePara>
          %(<note#{attrs}><notePara>#{node.content}</notePara></note>)
        when 'TIP', 'IMPORTANT' # These are mapped to a standard S1000D <note>
          warn "asciidoctor: INFO: Admonition type '#{type}' mapped to standard S1000D <note>."
          %(<note#{attrs}><notePara><para>#{node.content}</para></notePara></note>) # No remarkType
        else
          # Fallback for any other unknown admonition types - map to a generic S1000D <note>
          warn "asciidoctor: WARNING: Unknown admonition type '#{type}' mapped to generic S1000D <note>."
          %(<note#{attrs}><notePara><para>#{node.content}</para></notePara></note>) # No remarkType
        end
    end
    def convert_open node; %(<para#{common_attributes node.id}>#{node.content}</para>); end
    def convert_listing node; result = %(<figure#{common_attributes node.id}>); result << %(<title>#{esc_text(node.title)}</title>) if node.title?; result << %(<graphic><verbatimText><![CDATA[#{node.content}]]></verbatimText></graphic>); result << %(</figure>); end
    def convert_literal node; %(<para#{common_attributes node.id}><verbatimText>#{esc_text(node.content)}</verbatimText></para>); end
    def convert_fallback node; warn %(asciidoctor: WARNING: S1000D converter missing handler for node type: #{node.node_name}); node.content if node.respond_to? :content; end

    def convert_inline_image(node)
        target = node.target
        alt_text = node.attr('alt', '')
        %Q{<graphic infoEntityIdent="ICN-#{File.basename(target, '.*')}" infoName="ICN"/>}
      end
      

  end
end