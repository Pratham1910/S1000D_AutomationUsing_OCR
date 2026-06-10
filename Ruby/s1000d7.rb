# Devloped By Prathamesh Naik
# This code is a Ruby script that defines a custom Asciidoctor converter for S1000D XML documents.
# This is Licenced under the Apache License, Version 2.0

require 'asciidoctor'
require 'asciidoctor/helpers' 
require 'json' # For parsing nested applicability from custom block

module Asciidoctor
  class Converter::S1000D < Converter::Base
    register_for 's1000d'

    (QUOTE_TAGS = {
      monospaced: ['<verbatimText>', '</verbatimText>'],
      emphasis: ['<emphasis emphasisType="em02">', '</emphasis>'],
      strong: ['<emphasis emphasisType="em01">', '</emphasis>'],
      mark: ['<changeInline changeMark="1">', '</changeInline>'],
      superscript: ['<superScript>', '</superScript>'],
      subscript: ['<subScript>', '</subScript>']
    }).default = ['', ''] 

    alias convert_preamble content_only # Skip preamble processing if it's handled differently

    def initialize *args
      super
      basebackend 'xml'
      filetype 'xml'
      outfilesuffix '.xml'
      htmlsyntax 'xml'
      # Instance variables to collect definitions from blocks
      @s1000d_applic_definitions = [] 
      @s1000d_product_definitions = [] 
      @s1000d_product_attribute_definitions = [] 
      @global_applic_eval_hash = nil # Stores parsed JSON from the global_applicability_definition block
    end

    # Helper for common 'id' attribute
    def common_attributes(id)
      id ? %( id="#{id}") : ''
    end
    
    # Helper for 'applicRefId' attribute
    def applic_ref_attribute(node)
      node.attr?('applic_ref') ? %( applicRefId="#{esc_text(node.attr('applic_ref'))}") : ''
    end

    # Escape text for XML content
    def esc_text(text)
      return '' if text.nil?
      text.to_s
          .gsub('&', '&')
          .gsub('<', '<')
          .gsub('>', '>')
          .gsub('"', '"')
    end
    
    # For content that might already be XML (minimal escaping)
    def esc_content(text_or_content) 
      return '' if text_or_content.nil?
      return text_or_content unless text_or_content.is_a?(String) # If already processed
      text_or_content.to_s 
    end

    # Parse S1000D Data Module Code (DMC)
    def parse_dmc_string(dmc_string)
      return nil unless dmc_string && dmc_string.is_a?(String) && !dmc_string.strip.empty?
      # Remove potential comments from the DMC string (e.g., // comment)
      cleaned_dmc_string = dmc_string.split('//').first.strip
      
      # Regex for S1000D DMC structure
      regex = /^(?:DMC-)?([A-Z0-9]{2,17})-([A-Z0-9]{1})-([A-Z0-9]{2,4})-([A-Z0-9]{1,2})-([A-Z0-9]{1,2})-([A-Z0-9]{2,4})-([A-Z0-9]{2})-([A-Z0-9]{1,4})-([A-Z0-9]{3})-([A-Z0-9]{1})-([A-Z0-9]{1})$/i
      match = regex.match(cleaned_dmc_string)
      if match
          return {
            modelIdentCode:     match[1].upcase, systemDiffCode:     match[2].upcase,
            systemCode:         match[3].upcase, subSystemCode:      match[4].upcase,
            subSubSystemCode:   match[5].upcase, assyCode:           match[6].upcase,
            disassyCode:        match[7].upcase, disassyCodeVariant: match[8].upcase,
            infoCode:           match[9].upcase, infoCodeVariant:    match[10].upcase,
            itemLocationCode:   match[11].upcase
          }
      else
          warn "asciidoctor: WARNING (parse_dmc_string): Regex DID NOT MATCH for 11-part DMC input '#{cleaned_dmc_string}'."
          return nil
      end
    end
    
    # Process blocks marked as '.applicdef' for <referencedApplicGroup>
    def process_as_applic_definition(node)
      id = node.id
      display_text_content = node.source # Raw content of the block
      prop_ident = node.attr('propertyident')
      prop_values = node.attr('propertyvalues') 
      prop_type = node.attr('propertytype', 'prodattr') # Default
      unless id && prop_ident && prop_values
        warn "asciidoctor: WARNING: Applicability definition (applicdef) block '#{id || 'Unnamed'}' is missing required attributes (id, propertyident, propertyvalues). Skipping."
        return false 
      end
      applic_xml = <<~APPLIC_DEF.strip
        <applic id="#{esc_text(id)}">
          <displayText>
            <simplePara>#{esc_text(display_text_content.strip)}</simplePara>
          </displayText>
          <assert applicPropertyIdent="#{esc_text(prop_ident)}" applicPropertyType="#{esc_text(prop_type)}" applicPropertyValues="#{esc_text(prop_values)}"/>
        </applic>
      APPLIC_DEF
      @s1000d_applic_definitions << applic_xml
      return true 
    end

    # Process blocks marked as '.productdef' for <productCrossRefTable>
    def process_as_product_definition(node)
      id = node.id
      prop_ident = node.attr('propertyident')
      prop_value = node.attr('propertyvalue') # Singular for <assign>
      prop_type = node.attr('propertytype', 'prodattr')
      unless id && prop_ident && prop_value
        warn "asciidoctor: WARNING: Product definition (productdef) block '#{id || 'Unnamed'}' is missing required attributes (id, propertyident, propertyvalue). Skipping."
        return false
      end
      product_xml = <<~PRODUCT_DEF.strip
        <product id="#{esc_text(id)}">
          <assign applicPropertyIdent="#{esc_text(prop_ident)}" applicPropertyType="#{esc_text(prop_type)}" applicPropertyValue="#{esc_text(prop_value)}"/>
        </product>
      PRODUCT_DEF
      @s1000d_product_definitions << product_xml
      return true
    end

    # Process blocks marked as '.attribute_def' for <productAttributeList>
    def process_as_product_attribute_definition(node)
      id = node.id
      name_text = node.attr('name')
      descr_text = node.attr('descr')

      # Ensure attributes are present on the node that carries the role
      unless id && name_text && descr_text 
        if node.context == :ulist && node.role == 'attribute_def' # If role is on ulist directly
            id ||= node.id # Get id from ulist if not on a parent open block
            name_text ||= node.attr('name')
            descr_text ||= node.attr('descr')
        end
        # Final check
        unless id && name_text && descr_text
            warn "asciidoctor: WARNING: Product attribute definition (attribute_def) block '#{id || 'Unnamed'}' is missing required attributes (id, name, descr) on itself. Skipping."
            return false
        end
      end

      enumerations_xml_parts = []
      list_node_for_enum = nil
      # Determine where the ulist for enumerations is
      if node.context == :ulist && (node.role == 'attribute_def') # Role directly on the ulist
        list_node_for_enum = node
      elsif node.context == :open && node.blocks.first&.context == :ulist # Role on open block containing ulist
        list_node_for_enum = node.blocks.first
      end

      if list_node_for_enum
        list_node_for_enum.items.each do |item|
          value = item.text.to_s.split.first.strip # Take first "word" as value
          unless value.empty?
            # XML for <enumeration>, will be indented later when joining
            enumerations_xml_parts << "<enumeration applicPropertyValues=\"#{esc_text(value)}\"/>"
          end
        end
      else
        warn "asciidoctor: WARNING: Product attribute definition (attribute_def) block '#{id}' expects an open block with a ulist, or a ulist itself with role '.attribute_def'. No enumerations generated."
      end
      
      # Build the <productAttribute> XML
      attribute_xml = "<productAttribute id=\"#{esc_text(id)}\">\n"
      attribute_xml << "  <name>#{esc_text(name_text)}</name>\n"
      attribute_xml << "  <descr>#{esc_text(descr_text)}</descr>\n"
      enumerations_xml_parts.each do |enum_xml|
        attribute_xml << "  #{enum_xml}\n" # Indent <enumeration> relative to <productAttribute>
      end
      attribute_xml << "</productAttribute>"
      
      @s1000d_product_attribute_definitions << attribute_xml
      return true
    end

    # --- START: generate_..._xml methods (ensure these call .convert on sub-blocks) ---
    # These are crucial for procedural and fault DMs. They must iterate their sections/blocks
    # and call `sub_block.convert` or `item.content` to ensure definition filtering works.
    # For brevity, using simplified stubs here. Replace with your full, tested implementations.
    def generate_req_cond_group_xml(section_node, for_closeout = false); return "<reqCondGroup><noConds/></reqCondGroup>"; end
    def generate_req_tech_info_group_xml(section_node); return "<reqTechInfoGroup><noReqTechInfo/></reqTechInfoGroup>"; end
    def determine_internal_ref_target_type(target_node, target_id_for_warning); return ""; end
    def generate_req_persons_xml(section_node); return "<reqPersons><noReqPersons/></reqPersons>"; end
    def generate_table_based_req_list(s_n, l_t, g_t, i_i_t, n_i_t, c_m); return "<#{l_t}>#{n_i_t}</#{l_t}>"; end
    def generate_req_safety_xml(section_node)
        return "<reqSafety><noSafety/></reqSafety>" unless section_node
        safety_elements = section_node.blocks.map(&:convert).map(&:strip).reject(&:empty?)
        if safety_elements.empty?; return "<reqSafety><noSafety/></reqSafety>"; else
        return "<reqSafety><safetyRqmts>\n" + safety_elements.join("\n") + "\n</safetyRqmts></reqSafety>"; end
    end
    def generate_preliminary_requirements_xml(document_node); return "<preliminaryRqmts><reqCondGroup><noConds/></reqCondGroup></preliminaryRqmts>"; end
    def generate_main_procedure_steps_xml(document_node); return "<proceduralStep><para/></proceduralStep>"; end
    def generate_fault_isolation_main_procedure_xml(document_node); return "<isolationMainProcedure><isolationStep><para/></isolationStep></isolationMainProcedure>"; end
    def generate_close_requirements_xml(document_node); return "<closeRqmts><reqCondGroup><noConds/></reqCondGroup></closeRqmts>"; end
    # --- END: generate_..._xml methods ---

    # --- START: Helper methods for convert_document ---
    # Recursive helper method to build <evaluate> and <assert> XML from hash (parsed JSON)
    def build_applic_condition_xml(condition_hash, indent_level = 0)
      current_indent_str = "  " * indent_level 
      xml_string = ""
      unless condition_hash.is_a?(Hash)
        warn "asciidoctor: WARNING: Invalid applic condition data (expected Hash): #{condition_hash.inspect}"
        return ""
      end
      type = condition_hash['type']&.downcase
      if type == 'evaluate'
        and_or = condition_hash['andOr']&.downcase || 'and' 
        children = condition_hash['children']
        xml_string << "#{current_indent_str}<evaluate andOr=\"#{esc_text(and_or)}\">\n"
        if children.is_a?(Array)
          children.each { |child_hash| xml_string << build_applic_condition_xml(child_hash, indent_level + 1) }
        else
          warn "asciidoctor: WARNING: 'evaluate' node in global applic missing 'children' array or not an array."
        end
        xml_string << "#{current_indent_str}</evaluate>\n"
      elsif type == 'assert'
        prop_ident = condition_hash['propertyIdent']
        prop_values = condition_hash['propertyValues']
        prop_type = condition_hash['propertyType'] || 'prodattr' 
        if prop_ident && prop_values
          xml_string << "#{current_indent_str}<assert applicPropertyIdent=\"#{esc_text(prop_ident)}\" applicPropertyType=\"#{esc_text(prop_type)}\" applicPropertyValues=\"#{esc_text(prop_values)}\"/>\n"
        else
          warn "asciidoctor: WARNING: 'assert' node in global applic missing 'propertyIdent' or 'propertyValues'."
        end
      else
        warn "asciidoctor: WARNING: Unknown condition type '#{type}' in global applicability structure."
      end
      xml_string
    end

    # Fallback for global applicability if JSON block method is not used or fails
    def generate_flat_global_asserts_xml(doc_attrs)
        asserts_container_xml = ""
        collected_assert_strings = [] 
        assert_index = 1
        loop do
            prop_ident_key = "s1000d-global-assert-#{assert_index}-propertyident"
            prop_values_key = "s1000d-global-assert-#{assert_index}-propertyvalues"
            prop_type_key = "s1000d-global-assert-#{assert_index}-propertytype"

            prop_ident = doc_attrs.fetch(prop_ident_key, '').to_s.strip
            prop_values = doc_attrs.fetch(prop_values_key, '').to_s.strip
            
            break if prop_ident.empty? || prop_values.empty?

            prop_type_attr = doc_attrs.fetch(prop_type_key, '').to_s.strip
            prop_type = prop_type_attr.empty? ? 'prodattr' : prop_type_attr

            single_assert_xml = <<~ASSERT_XML.strip 
              <assert applicPropertyIdent="#{esc_text(prop_ident)}" applicPropertyType="#{esc_text(prop_type)}" applicPropertyValues="#{esc_text(prop_values)}"/>
            ASSERT_XML
            collected_assert_strings << single_assert_xml
            assert_index += 1
        end

        if !collected_assert_strings.empty?
            if collected_assert_strings.length > 1
                operator_attr = doc_attrs.fetch('s1000d-global-assert-operator', '').to_s.downcase.strip
                operator = ['and', 'or'].include?(operator_attr) ? operator_attr : 'and'
                # Indent children of <evaluate>
                evaluate_children_xml = collected_assert_strings.map { |s_assert| s_assert.gsub(/^/, '  ') }.join("\n")
                asserts_container_xml = <<~EVALUATE_XML.strip
                  <evaluate andOr="#{operator}">
                  #{evaluate_children_xml}
                  </evaluate>
                EVALUATE_XML
            else
                asserts_container_xml = collected_assert_strings[0] # Single assert
            end
            # Indent the whole container (<assert> or <evaluate>) to be child of <applic>
            asserts_container_xml = asserts_container_xml.gsub(/^/, '      ') 
        end
        asserts_container_xml
    end

    def build_ident_and_status_section_xml(doc_attrs, dm_code_attrs_in, act_dm_ref_for_dmstatus, global_applic_text_val, brex_dm_code_attrs_in, rfu_elements_xml)
        dm_code_attrs = dm_code_attrs_in # Assumes dm_code_attrs_in is already defaulted if parsing failed
        lang_code = (doc_attrs['lang'] || 'en').downcase; country_code = (doc_attrs['country-code'] || 'US').upcase
        issue_number = doc_attrs['issue-number'] || "001"; in_work_status = doc_attrs['in-work'] || "00"
        date_str = doc_attrs['revdate'] || doc_attrs['issue-date'] || Time.now.strftime('%Y-%m-%d')
        year, month, day = date_str.match?(/^\d{4}-\d{2}-\d{2}$/) ? date_str.split('-') : ["2025", "10", "01"] # Default if format is wrong
        current_doctitle = doc_attrs[:doctitle] || "Default Document Title"
        tech_name = doc_attrs['tech-name'] || current_doctitle
        dm_title_text = doc_attrs['dm-title'] || doc_attrs['infoName'] || tech_name
        security_classification = doc_attrs['security-classification'] || "01"
        responsible_partner_company = doc_attrs['responsible-partner-company'] || "UNKNOWN"
        originator_enterprise = doc_attrs['originator-enterprise'] || responsible_partner_company
        brex_dm_code_attrs = brex_dm_code_attrs_in || { modelIdentCode: "S1000D", systemDiffCode: "H", systemCode: "04", subSystemCode: "1", subSubSystemCode: "0", assyCode: "0301", disassyCode: "00", disassyCodeVariant: "A", infoCode: "022", infoCodeVariant: "A", itemLocationCode: "D" }

        global_applic_conditions_xml = ""
        # puts "DEBUG build_ident_and_status: @global_applic_eval_hash is: #{@global_applic_eval_hash.inspect}" # Keep for debugging
        if @global_applic_eval_hash && @global_applic_eval_hash.is_a?(Hash)
            # puts "DEBUG build_ident_and_status: Processing @global_applic_eval_hash."
            raw_conditions_xml = build_applic_condition_xml(@global_applic_eval_hash, 0) 
            # puts "DEBUG build_ident_and_status: Raw conditions XML from build_applic_condition_xml: #{raw_conditions_xml.inspect}"
            global_applic_conditions_xml = raw_conditions_xml.strip.gsub(/^/, '      ') unless raw_conditions_xml.strip.empty?
            # puts "DEBUG build_ident_and_status: Final global_applic_conditions_xml (indented): #{global_applic_conditions_xml.inspect}"
        else
            # puts "DEBUG build_ident_and_status: @global_applic_eval_hash was NIL or NOT A HASH. Falling back to flat asserts."
            global_applic_conditions_xml = generate_flat_global_asserts_xml(doc_attrs)
            document_node_for_check = doc_attrs[:document_node] # Get the passed node
            if global_applic_conditions_xml.empty? && @global_applic_eval_hash.nil? && node_has_global_applic_block(document_node_for_check) 
                 warn "asciidoctor: INFO: global_applicability_definition block was present but JSON parsing failed or content was empty, and no flat asserts found."
            elsif global_applic_conditions_xml.empty? && !doc_attrs['s1000d-global-applic-eval'].to_s.strip.empty? # Old attribute check
                 warn "asciidoctor: INFO: s1000d-global-applic-eval attribute was present but invalid, and no flat asserts found."
            end
        end
        
        iass_xml = <<~IASS_XML
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
            <responsiblePartnerCompany enterpriseCode="1671Y"><enterpriseName>#{esc_text(responsible_partner_company)}</enterpriseName></responsiblePartnerCompany>
            <originator enterpriseCode="1671Y"><enterpriseName>#{esc_text(originator_enterprise)}</enterpriseName></originator>
            #{act_dm_ref_for_dmstatus.empty? ? '' : act_dm_ref_for_dmstatus.gsub(/^/, '    ').strip}
            <applic>
              <displayText>
                <simplePara>#{esc_text(global_applic_text_val)}</simplePara>
              </displayText>
            #{global_applic_conditions_xml.empty? ? '' : "\n" + global_applic_conditions_xml}
            </applic>
            <brexDmRef><dmRef><dmRefIdent>
              <dmCode modelIdentCode="#{brex_dm_code_attrs[:modelIdentCode]}" systemDiffCode="#{brex_dm_code_attrs[:systemDiffCode]}" systemCode="#{brex_dm_code_attrs[:systemCode]}" subSystemCode="#{brex_dm_code_attrs[:subSystemCode]}" subSubSystemCode="#{brex_dm_code_attrs[:subSubSystemCode]}" assyCode="#{brex_dm_code_attrs[:assyCode]}" disassyCode="#{brex_dm_code_attrs[:disassyCode]}" disassyCodeVariant="#{brex_dm_code_attrs[:disassyCodeVariant]}" infoCode="#{brex_dm_code_attrs[:infoCode]}" infoCodeVariant="#{brex_dm_code_attrs[:infoCodeVariant]}" itemLocationCode="#{brex_dm_code_attrs[:itemLocationCode]}"/>
            </dmRefIdent></dmRef></brexDmRef>
            <qualityAssurance><unverified/></qualityAssurance>
            #{rfu_elements_xml.strip.gsub(/^/, '    ')}
          </dmStatus>
        </identAndStatusSection>
        IASS_XML
        iass_xml.strip
    end
    
    def build_doctype_declaration(content_markup_for_icns)
        icn_ids = content_markup_for_icns.scan(/infoEntityIdent=["'](ICN-[A-Z0-9\-]+)["']/).flatten.uniq 
        doctype_parts = []
        if !icn_ids.empty?; doctype_parts << "<!NOTATION PNG SYSTEM \"PNG\">"; icn_ids.each { |icn| doctype_parts << "<!ENTITY #{esc_text(icn)} SYSTEM \"#{esc_text(icn)}.png\" NDATA PNG>" }; end
        declaration = '<!DOCTYPE dmodule'; if !doctype_parts.empty?; declaration << " [\n  #{doctype_parts.join("\n  ")}\n]>"; else; declaration << ">"; end; declaration
    end

    def get_schema_file(dm_type_str)
        case dm_type_str; when 'procedure', 'procedural'; 'proced.xsd'; when 'fault', 'faultisolation'; 'fault.xsd'; when 'act', 'pct'; 'applicom.xsd'; else 'descript.xsd'; end
    end

    # Helper to check if the document node contains the global_applicability_definition block
    def node_has_global_applic_block(document_node)
        return false unless document_node && document_node.respond_to?(:blocks)
        document_node.blocks.any? { |b| b.role == 'global_applicability_definition' || b.style == 'global_applicability_definition' }
    end
    # --- END: Helper methods for convert_document ---

    def convert_document node
      @s1000d_applic_definitions, @s1000d_product_definitions, @s1000d_product_attribute_definitions = [], [], []
      @global_applic_eval_hash = nil 
      doc_attrs = node.document.attributes
      doc_attrs[:doctitle] = node.doctitle 
      doc_attrs[:document_node] = node # Make document node available to helpers

      dmc_attr_string = doc_attrs['dmc'] || doc_attrs['part-title']
      dm_code_attrs = parse_dmc_string(dmc_attr_string) 
      default_dmc_values = { modelIdentCode: "S1KDTOOLS", systemDiffCode: "A", systemCode: "00", subSystemCode: "0", subSubSystemCode: "0", assyCode: "0000", disassyCode: "00", disassyCodeVariant: "A", infoCode: "000", infoCodeVariant: "A", itemLocationCode: "A" }
      if dmc_attr_string && dm_code_attrs.nil? 
          warn "asciidoctor: WARNING: Invalid Data Module Code '#{dmc_attr_string}' in document header. Using defaults."
          dm_code_attrs = default_dmc_values
      elsif dm_code_attrs.nil? 
          warn "asciidoctor: WARNING: No Data Module Code attribute provided. Using defaults."
          dm_code_attrs = default_dmc_values
      end
      dm_code_attrs ||= default_dmc_values # Final safety net
      
      s1000d_global_applic_text = (doc_attrs['s1000d-applic-text'] || "All").strip
      act_dmc_string = doc_attrs['act-dmc']; act_dm_ref_for_dmstatus = ""
      if act_dmc_string && !act_dmc_string.strip.empty?; act_dm_c = parse_dmc_string(act_dmc_string); if act_dm_c; act_dm_ref_for_dmstatus = "<applicCrossRefTableRef><dmRef><dmRefIdent><dmCode modelIdentCode=\"#{act_dm_c[:modelIdentCode]}\" systemDiffCode=\"#{act_dm_c[:systemDiffCode]}\" systemCode=\"#{act_dm_c[:systemCode]}\" subSystemCode=\"#{act_dm_c[:subSystemCode]}\" subSubSystemCode=\"#{act_dm_c[:subSubSystemCode]}\" assyCode=\"#{act_dm_c[:assyCode]}\" disassyCode=\"#{act_dm_c[:disassyCode]}\" disassyCodeVariant=\"#{act_dm_c[:disassyCodeVariant]}\" infoCode=\"#{act_dm_c[:infoCode]}\" infoCodeVariant=\"#{act_dm_c[:infoCodeVariant]}\" itemLocationCode=\"#{act_dm_c[:itemLocationCode]}\"/></dmRefIdent></dmRef></applicCrossRefTableRef>".strip; end; end

      brex_dmc_string = doc_attrs['brex-dmc']; brex_dm_code_attrs = parse_dmc_string(brex_dmc_string) 
      if brex_dmc_string && brex_dm_code_attrs.nil?; warn "asciidoctor: WARNING: Invalid BREX DMC '#{brex_dmc_string}'. Default used.";
      elsif brex_dm_code_attrs.nil?; warn "asciidoctor: WARNING: No BREX DMC. Default used."; end
      
      rfu_text = doc_attrs['reason-for-update']; rfu_elements = if rfu_text && !rfu_text.strip.empty?; "\n<reasonForUpdate id=\"rfu-0001\" updateHighlight=\"1\" updateReasonType=\"urt02\"><simplePara>#{esc_text(rfu_text)}</simplePara></reasonForUpdate>"; else "\n<reasonForUpdate id=\"rfu-0001\" updateHighlight=\"1\" updateReasonType=\"urt02\"><simplePara>Initial issue or generic update.</simplePara></reasonForUpdate>"; end
      dm_type = (doc_attrs['dm-type'] || 'descript').downcase.strip
      
      # FIRST PASS: This calls .convert on all top-level blocks.
      # The convert_literal method (and others for .applicdef etc.) will populate instance variables.
      node.blocks.each { |b| b.convert } 

      pal_xml = @s1000d_product_attribute_definitions.empty? ? "" : "<productAttributeList>\n#{@s1000d_product_attribute_definitions.map { |pa| pa.gsub(/^/, '  ') }.join("\n")}\n</productAttributeList>"
      pct_dm_ref_xml = ""; if dm_type == 'act'; pct_dmc_str = doc_attrs['pct-dmc']; if pct_dmc_str && !pct_dmc_str.strip.empty?; pct_dm_c = parse_dmc_string(pct_dmc_str); if pct_dm_c; pct_dm_ref_xml = "<productCrossRefTableRef><dmRef><dmRefIdent><dmCode modelIdentCode=\"#{pct_dm_c[:modelIdentCode]}\" systemDiffCode=\"#{pct_dm_c[:systemDiffCode]}\" systemCode=\"#{pct_dm_c[:systemCode]}\" subSystemCode=\"#{pct_dm_c[:subSystemCode]}\" subSubSystemCode=\"#{pct_dm_c[:subSubSystemCode]}\" assyCode=\"#{pct_dm_c[:assyCode]}\" disassyCode=\"#{pct_dm_c[:disassyCode]}\" disassyCodeVariant=\"#{pct_dm_c[:disassyCodeVariant]}\" infoCode=\"#{pct_dm_c[:infoCode]}\" infoCodeVariant=\"#{pct_dm_c[:infoCodeVariant]}\" itemLocationCode=\"#{pct_dm_c[:itemLocationCode]}\"/></dmRefIdent></dmRef></productCrossRefTableRef>".strip; end; end; end
      internal_pct_xml = @s1000d_product_definitions.empty? ? "" : "<productCrossRefTable>\n#{@s1000d_product_definitions.map { |p| p.gsub(/^/, '  ') }.join("\n")}\n</productCrossRefTable>"
      if internal_pct_xml.empty? && ['act', 'pct'].include?(dm_type); warn "asciidoctor: INFO: dm-type '#{dm_type}', no '.productdef' blocks. Internal <productCrossRefTable> omitted."; end
      act_outer_xml = ""; if dm_type == 'act'; act_children = [pal_xml, internal_pct_xml, pct_dm_ref_xml].map(&:strip).reject(&:empty?); unless act_children.empty?; act_outer_xml = "<applicCrossRefTable>\n#{act_children.map{|c| c.gsub(/^/,'  ')}.join("\n")}\n</applicCrossRefTable>"; else warn "asciidoctor: INFO: dm-type 'act', no content for <applicCrossRefTable>. Omitting."; end; end
      rag_xml = @s1000d_applic_definitions.empty? ? "" : "<referencedApplicGroup>\n#{@s1000d_applic_definitions.map { |a| a.gsub(/^/, '  ') }.join("\n")}\n</referencedApplicGroup>"
      
      general_content_processed = ""
      node.blocks.each do |block|
        is_definition_block = ['applicdef', 'productdef', 'attribute_def', 'global_applicability_definition'].include?(block.role)
        # Also check style as a fallback if roles aren't consistently used for these custom types
        is_definition_block ||= ['applicdef', 'productdef', 'attribute_def', 'global_applicability_definition'].include?(block.style) if !is_definition_block

        unless is_definition_block
            conversion_result = block.convert 
            general_content_processed << conversion_result if conversion_result.is_a?(String)
        end
      end
      general_content_processed.strip!
      
      main_dm_content = ""; case dm_type
      when 'act'; main_dm_content << "<description>\n#{general_content_processed}\n</description>" unless general_content_processed.empty?; main_dm_content << "\n#{act_outer_xml}" unless act_outer_xml.empty?
      when 'pct'; main_dm_content << "<description>\n#{general_content_processed}\n</description>" unless general_content_processed.empty?; main_dm_content << "\n#{internal_pct_xml}" unless internal_pct_xml.empty?
      when 'procedure', 'procedural'; prelim = generate_preliminary_requirements_xml(node); main_proc = generate_main_procedure_steps_xml(node); close_rqmts = generate_close_requirements_xml(node); main_dm_content = "<procedure>\n#{prelim}\n<mainProcedure>\n#{main_proc}\n</mainProcedure>\n#{close_rqmts}\n</procedure>"
      when 'fault', 'faultisolation'; main_dm_content = "<fault><!-- fault content from generate_ methods --></fault>" # Placeholder
      when 'descript', 'description'; main_dm_content = "<description>\n#{general_content_processed}\n</description>" unless general_content_processed.empty?
      else warn "asciidoctor: WARNING: Unknown dm-type '#{dm_type}'. Defaulting to descriptive."; main_dm_content = "<description>\n#{general_content_processed}\n</description>" unless general_content_processed.empty?; end

      final_content = ""; final_content << "#{rag_xml.strip}\n" if !rag_xml.empty? && !['act', 'pct'].include?(dm_type); final_content << main_dm_content.strip unless main_dm_content.strip.empty?
      
      ident_status_section = build_ident_and_status_section_xml(doc_attrs, dm_code_attrs, act_dm_ref_for_dmstatus, s1000d_global_applic_text, brex_dm_code_attrs, rfu_elements)
      doctype_decl = build_doctype_declaration(final_content)
      schema = get_schema_file(dm_type)
      
      result = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
       #{doctype_decl}
      <dmodule xmlns:dc="http://www.purl.org/dc/elements/1.1/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.s1000d.org/S1000D_6/xml_schema_flat/#{schema}">
      #{ident_status_section.gsub(/^/, '  ')}
        <content>
          #{final_content.empty? ? '' : final_content.strip.gsub(/^/, '    ')}
        </content>
      </dmodule>
      XML
      result.chomp.gsub(/^\s+$/, '') 
    end

    # ==========================================================================
    # Standard Block and Inline Converters (Prioritize Role)
    # ==========================================================================
    def convert_paragraph(node)
      # puts "--- PARA --- ID: #{node.id}, Role: '#{node.role}', Style: '#{node.style}'"
      if node.role == 'applicdef'; process_as_applic_definition(node); return "" 
      elsif node.role == 'productdef'; process_as_product_definition(node); return ""                            
      elsif node.role == 'attribute_def'
        warn "asciidoctor: WARNING: '.attribute_def' on para '#{node.id}'. Attributes (id,name,descr) processed, but enumerations need an open block with ulist or a ulist with this role."
        process_as_product_attribute_definition(node); return "" 
      # No longer relying on style for these custom defs, role is primary.
      end
      content = node.content; return "" if content.nil? && !node.text? # Added !node.text? check for truly empty paras
      %(<para#{common_attributes(node.id)}#{applic_ref_attribute(node)}>#{content}</para>)
    end

    def convert_open(node) # For blocks like -- --, ====, ****
      # puts "--- OPEN --- ID: #{node.id}, Role: '#{node.role}', Style: '#{node.style}', Context: #{node.context}"
      if node.role == 'applicdef'; process_as_applic_definition(node); return ""
      elsif node.role == 'productdef'; process_as_product_definition(node); return ""                            
      elsif node.role == 'attribute_def'; process_as_product_attribute_definition(node); return ""
      # No longer relying on style for these custom defs for open blocks, role is primary.
      end
      content = node.content; return "" if content.nil? 
      %(<para#{common_attributes(node.id)}#{applic_ref_attribute(node)}>#{content}</para>) # Default for other open blocks
    end
    
    def convert_ulist(node)
        # puts "--- ULIST --- ID: #{node.id}, Role: '#{node.role}', Style: '#{node.style}'"
        if node.role == 'attribute_def' 
            # This ulist IS the attribute definition (id, name, descr must be on it)
            # and its items are the enumerations.
            process_as_product_attribute_definition(node); return ""
        # No longer relying on style for this custom def for ulist, role is primary.
        end
        # Standard ulist conversion
        list_attributes = common_attributes(node.id) + applic_ref_attribute(node)
        result = %(<para><randomList#{list_attributes}>)
        node.items.each do |item|
            item_id_attr = common_attributes(item.id)
            item_applic_attr = applic_ref_attribute(item) 
            inner_content = item.blocks? ? item.content : "<para>#{esc_text(item.text)}</para>"
            result << %(<listItem#{item_id_attr}#{item_applic_attr}>#{inner_content}</listItem>)
        end
        result << %(</randomList></para>)
        result
    end

    def convert_literal(node) # Handles `....` blocks
      # puts "--- CONVERT_LITERAL --- ID: #{node.id}, Role: '#{node.role}', Style: '#{node.style}', First line of content: '#{node.lines.first&.strip}'"
    
      if node.role == 'global_applicability_definition' # Prioritize role
        json_string = node.content 
        begin
          parsed_json = JSON.parse(json_string)
          if parsed_json.is_a?(Hash) 
            @global_applic_eval_hash = parsed_json
            # puts "DEBUG: Successfully parsed global_applic_eval_hash from literal block."
          else
            warn "asciidoctor: WARNING: JSON in 'global_applicability_definition' block did not parse into a Hash. Parsed as: #{parsed_json.class}"
            @global_applic_eval_hash = nil
          end
        rescue JSON::ParserError => e
          warn "asciidoctor: WARNING: Failed to parse JSON from 'global_applicability_definition' literal block: #{e.message}"
          @global_applic_eval_hash = nil
        end
        return "" # Consume the block
      elsif node.style == 'global_applicability_definition' # Fallback for style (less ideal)
        warn "asciidoctor: INFO: Using style='global_applicability_definition' for literal block '#{node.id}'. Prefer role '[.global_applicability_definition]'."
        json_string = node.content
        begin
          @global_applic_eval_hash = JSON.parse(json_string)
          # puts "DEBUG: Successfully parsed (via style) global_applic_eval_hash from literal block."
        rescue JSON::ParserError => e
          warn "asciidoctor: WARNING: Failed to parse JSON (via style) from 'global_applicability_definition' literal block: #{e.message}"
          @global_applic_eval_hash = nil
        end
        return "" 
      end
      
      para_attributes = common_attributes(node.id) + applic_ref_attribute(node)
      %(<para#{para_attributes}><verbatimText>#{esc_text(node.content)}</verbatimText></para>)
    end

    # --- Other convert_... methods (olist, dlist, section, etc.) from previous full code ---
    def convert_olist(node); list_attributes = common_attributes(node.id) + applic_ref_attribute(node); result = %(<para><sequentialList#{list_attributes}>); node.items.each { |item| item_id_attr = common_attributes(item.id); item_applic_attr = applic_ref_attribute(item); inner_content = item.blocks? ? item.content : "<para>#{esc_text(item.text)}</para>"; result << %(<listItem#{item_id_attr}#{item_applic_attr}>#{inner_content}</listItem>) }; result << %(</sequentialList></para>); result; end
    def convert_dlist(node); dl_attributes = common_attributes(node.id) + applic_ref_attribute(node); result = %(<para><definitionList#{dl_attributes}>); node.items.each do |terms_nodes, dd_node|; result << %(<definitionListItem><listItemTerm>); terms_nodes.each { |dt| result << esc_text(dt.text) }; result << %(</listItemTerm><listItemDefinition>); if dd_node; result << %(<para>#{esc_text(dd_node.text)}</para>) if dd_node.text?; result << dd_node.content if dd_node.blocks?; else; result << %(<para/>); end; result << %(</listItemDefinition></definitionListItem>); end; result << %(</definitionList></para>); result; end
    def convert_section(node); %(<levelledPara#{common_attributes(node.id)}#{applic_ref_attribute(node)}><title>#{esc_text(node.title)}</title>#{node.content}</levelledPara>); end
    def convert_inline_anchor(node); case node.type; when :xref; target = node.attributes['refid'] || node.target; target = target[1..-1] if target.start_with?('#'); %(<internalRef internalRefId="#{esc_text(target)}">#{esc_text(node.text || target)}</internalRef>); when :link; %(<externalRef destination="#{esc_text(node.target)}">#{esc_text(node.text)}</externalRef>); when :ref; ''; else; esc_text(node.text || node.target); end; end
    def convert_table(node); table_attributes = common_attributes(node.id) + applic_ref_attribute(node); pgwide = (node.option? 'pgwide') ? 1 : 0; frame = node.attr 'frame', 'all'; grid = node.attr 'grid', 'all'; rowsep = (grid == 'none' || grid == 'cols') ? 0 : 1; colsep = (grid == 'none' || grid == 'rows') ? 0 : 1; orient = (node.attr? 'orientation', 'landscape') ? ' land' : ''; result = %(<table#{table_attributes} frame="#{frame}" pgwide="#{pgwide}" rowsep="#{rowsep}" colsep="#{colsep}"#{orient.empty? ? '' : %( orient="#{orient}")}>); result << %(<title>#{esc_text(node.title)}</title>) if node.title?; result << %(<tgroup cols="#{node.attr 'colcount'}">); node.columns.each { |col| result << %(<colspec colname="col_#{col.attr 'colnumber'}" colwidth="#{(col.attr 'colwidth') ? "#{col.attr 'colwidth'}*" : "1*"}"/>) }; node.rows.to_h.each do |tsec, rows|; next if rows.empty?; result << %(<t#{tsec}>); rows.each do |row|; result << %(<row>); row.each do |cell|; colnum = cell.column.attr 'colnumber'; halign = (cell.attr? 'halign') ? %( align="#{cell.attr 'halign'}") : ''; valign = (cell.attr? 'valign') ? %( valign="#{cell.attr 'valign'}") : ''; colspan = cell.colspan ? %( namest="col_#{colnum}" nameend="col_#{colnum + cell.colspan - 1}") : ''; rowspan = cell.rowspan ? %( morerows="#{cell.rowspan - 1}") : ''; cell_body = case cell.style; when :asciidoc then cell.content; when :literal then %(<para><verbatimText>#{esc_text(cell.text)}</verbatimText></para>); else cell.text.empty? ? '' : %(<para>#{esc_text(cell.text)}</para>); end; result << %(<entry#{halign}#{valign}#{colspan}#{rowspan}>#{cell_body || ''}</entry>); end; result << %(</row>); end; result << %(</t#{tsec}>); end; result << %(</tgroup></table>); result; end
    alias convert_embedded content_only
    def convert_image(node); figure_attributes = common_attributes(node.id) + applic_ref_attribute(node); title_el = node.title ? "<title>#{esc_text(node.title)}</title>" : ""; icn = node.attr('icn'); if icn.nil? || icn.empty?; base_name = File.basename(node.attr('target', 'unknown.png'), '.*'); if base_name.match?(/^ICN(-[A-Z0-9]+){2,}$/i); icn = base_name.upcase; warn "asciidoctor: INFO: Image '#{node.attr('target')}' inferred ICN '#{icn}'."; else; icn_fallback_source = node.attr('alt') || base_name; icn = "FIG-#{icn_fallback_source.gsub(/[^A-Za-z0-9\-]/, '').upcase}"; warn "asciidoctor: WARNING: Image '#{node.attr('target')}' no 'icn'. Using: #{icn}."; end; end; icn_ident = esc_text(icn); %(<figure#{figure_attributes}>#{title_el}<graphic infoEntityIdent="#{icn_ident}"/></figure>); end
    def convert_inline_quoted(node); open_tag, close_tag = QUOTE_TAGS[node.type]; attrs = node.id ? %( id="#{node.id}") : ''; %(#{open_tag.sub('>', "#{attrs}>")}#{esc_text(node.text)}#{close_tag}); end
    def convert_admonition(node); admonition_attributes = common_attributes(node.id) + applic_ref_attribute(node); type = node.attr('name').upcase; inner_content = if node.blocks?; node.content; else esc_text(node.source); end; case type; when 'WARNING'; %(<warning#{admonition_attributes}><warningAndCautionPara>#{inner_content}</warningAndCautionPara></warning>); when 'CAUTION'; %(<caution#{admonition_attributes}><warningAndCautionPara>#{inner_content}</warningAndCautionPara></caution>); when 'NOTE'; %(<note#{admonition_attributes}><notePara>#{inner_content}</notePara></note>); when 'TIP', 'IMPORTANT'; warn "asciidoctor: INFO: Admonition '#{type}' to <note>."; %(<note#{admonition_attributes}><notePara>#{inner_content}</notePara></note>); else; warn "asciidoctor: WARNING: Unknown admonition '#{type}' to <note>."; %(<note#{admonition_attributes}><notePara>#{inner_content}</notePara></note>); end; end
    def convert_listing(node); figure_attributes = common_attributes(node.id) + applic_ref_attribute(node); result = %(<figure#{figure_attributes}>); result << %(<title>#{esc_text(node.title)}</title>) if node.title?; result << %(<graphic><verbatimText><![CDATA[#{node.content}]]></verbatimText></graphic>); result << %(</figure>); result; end
    def convert_thematic_break(node); ''; end
    def convert_fallback(node); warn %(asciidoctor: WARNING: S1000D fallback for: #{node.node_name}); node.content if node.respond_to? :content; end
    def convert_inline_image(node); target = node.target; icn_base = File.basename(target, '.*'); icn = node.attr('icn') || node.attr('alt', "ICN-INLINE-#{icn_base.gsub(/[^A-Za-z0-9\-]/, '').upcase}"); icn = "ICN-INLINE-#{icn_base.gsub(/[^A-Za-z0-9\-]/, '').upcase}" if icn.to_s.strip.empty?; warn "asciidoctor: INFO: Inline image to <graphic infoEntityIdent=\"#{esc_text(icn)}\"/>."; %Q{<graphic infoEntityIdent="#{esc_text(icn)}"/>}; end
    # --- End of Standard Block and Inline Converters ---
  end
end