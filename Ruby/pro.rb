require 'base64'
require 'asciidoctor'
require 'asciidoctor/helpers'
require 'json' # For parsing nested applicability from custom block
require 'securerandom' # For fallback IDs, if needed

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


    alias convert_preamble content_only

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
      @global_applic_eval_hash = nil
      @is_in_table_context = false
      # This flag tracks if we are currently inside the main procedure.
      @is_in_main_procedure = false
    end

    def common_attributes(id)
      id ? %( id="#{id}") : ''
    end

    def applic_ref_attribute(node)
      node.attr?('applic_ref') ? %( applicRefId="#{esc_text(node.attr('applic_ref'))}") : ''
    end

    def esc_text(text)
      return '' if text.nil?
      text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
    end

    def esc_content(text_or_content)
      return '' if text_or_content.nil?
      return text_or_content unless text_or_content.is_a?(String)
      text_or_content.to_s
    end

    def parse_dmc_string(dmc_string)
      return nil unless dmc_string && dmc_string.is_a?(String) && !dmc_string.strip.empty?
      
      cleaned_dmc = dmc_string.split('//').first.strip.gsub(/\.xml$/i, '').gsub(/^DMC-/, '')

      strict_regex = /^([A-Z0-9]{2,17})-([A-Z0-9]{1,3})-([A-Z0-9]{2,4})-([A-Z0-9]{1,2})-([A-Z0-9]{1,2})-([A-Z0-9]{2,4})-([A-Z0-9]{2})-([A-Z0-9]{1})-([A-Z0-9]{3})-([A-Z0-9]{1})-([A-Z0-9]{1})$/i
      
      match = strict_regex.match(cleaned_dmc)
      if match
        return {
          modelIdentCode:     match[1].upcase,
          systemDiffCode:     match[2].upcase,
          systemCode:         match[3].upcase,
          subSystemCode:      match[4].upcase,
          subSubSystemCode:   match[5].upcase,
          assyCode:           match[6].upcase,
          disassyCode:        match[7].upcase,
          disassyCodeVariant: match[8].upcase,
          infoCode:           match[9].upcase,
          infoCodeVariant:    match[10].upcase,
          itemLocationCode:   match[11].upcase
        }
      end

      flexible_regex = /^([A-Z0-9]{2,17})-([A-Z0-9]{1,3})-([A-Z0-9]{2,4})-([A-Z0-9]{2,4})-([A-Z0-9]{2,4})-([A-Z0-9]{1,3})-([A-Z0-9]{1,4})-([A-Z0-9]{1})$/i
      
      match = flexible_regex.match(cleaned_dmc)
      if match
        sub_system_codes = match[4]
        sub_system_code = sub_system_codes[0] || '0'
        sub_sub_system_code = sub_system_codes[1] || '0'
        
        disassy_codes = match[6]
        disassy_code = disassy_codes[0..1] || '00'
        disassy_code_variant = disassy_codes[2] || 'A'
        
        info_codes = match[7]
        info_code = info_codes[0..2] || '000'
        info_code_variant = info_codes[3] || 'A'
        
        return {
          modelIdentCode:     match[1].upcase,
          systemDiffCode:     match[2].upcase,
          systemCode:         match[3].upcase,
          subSystemCode:      sub_system_code.upcase,
          subSubSystemCode:   sub_sub_system_code.upcase,
          assyCode:           match[5].upcase,
          disassyCode:        disassy_code.upcase,
          disassyCodeVariant: disassy_code_variant.upcase,
          infoCode:           info_code.upcase,
          infoCodeVariant:    info_code_variant.upcase,
          itemLocationCode:   match[8].upcase
        }
      else
        warn "asciidoctor: WARNING (parse_dmc_string): Input '#{dmc_string}' did not match a valid 11-part or 8-part condensed DMC format."
        return nil
      end
    end

    def parse_pmc_string(pmc_string)
      return nil unless pmc_string && pmc_string.is_a?(String) && !pmc_string.strip.empty?
      cleaned_pmc_string = pmc_string.split('//').first.strip
      regex = /^(?:PMC-)?([A-Z0-9]{2,17})-([A-Z0-9]{5})-([A-Z0-9]{5})-([A-Z0-9]{2})-([A-Za-z]{2})-([A-Z]{2})-([0-9]{3})-([0-9A-Z]{2})$/i
      match = regex.match(cleaned_pmc_string)
      if match
          return { modelIdentCode: match[1].upcase, pmIssuer: match[2].upcase, pmNumber: match[3].upcase, pmVolume: match[4].upcase, languageIsoCode: match[5].downcase, countryIsoCode: match[6].upcase, issueNumber: match[7], inWork: match[8].upcase }
      else
          warn "asciidoctor: WARNING (parse_pmc_string): Regex DID NOT MATCH for 8-part PMC input '#{cleaned_pmc_string}'."
          return nil
      end
    end

    def process_as_applic_definition(node)
      id = node.id
      display_text_content = node.source
      prop_ident = node.attr('propertyident')
      prop_values = node.attr('propertyvalues')
      prop_type = node.attr('propertytype', 'prodattr')
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

    def process_as_product_definition(node)
      id = node.id
      prop_ident = node.attr('propertyident')
      prop_value = node.attr('propertyvalue')
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

    def process_as_product_attribute_definition(node)
      id = node.id
      name_text = node.attr('name')
      descr_text = node.attr('descr')
      unless id && name_text && descr_text
        if node.context == :ulist && node.role == 'attribute_def'
            id ||= node.id
            name_text ||= node.attr('name')
            descr_text ||= node.attr('descr')
        end
        unless id && name_text && descr_text
            warn "asciidoctor: WARNING: Product attribute definition (attribute_def) block '#{id || 'Unnamed'}' is missing required attributes (id, name, descr) on itself. Skipping."
            return false
        end
      end
      enumerations_xml_parts = []
      list_node_for_enum = nil
      if node.context == :ulist && (node.role == 'attribute_def')
        list_node_for_enum = node
      elsif node.context == :open && node.blocks.first&.context == :ulist
        list_node_for_enum = node.blocks.first
      end
      if list_node_for_enum
        list_node_for_enum.items.each do |item|
          value = item.text.to_s.split.first.strip
          unless value.empty?
            enumerations_xml_parts << "<enumeration applicPropertyValues=\"#{esc_text(value)}\"/>"
          end
        end
      else
        warn "asciidoctor: WARNING: Product attribute definition (attribute_def) block '#{id}' expects an open block with a ulist, or a ulist itself with role '.attribute_def'. No enumerations generated."
      end
      attribute_xml = "<productAttribute id=\"#{esc_text(id)}\">\n"
      attribute_xml << "  <name>#{esc_text(name_text)}</name>\n"
      attribute_xml << "  <descr>#{esc_text(descr_text)}</descr>\n"
      enumerations_xml_parts.each { |enum_xml| attribute_xml << "  #{enum_xml}\n" }
      attribute_xml << "</productAttribute>"
      @s1000d_product_attribute_definitions << attribute_xml
      return true
    end

    def generate_req_cond_group_xml(section_node, for_closeout = false)
      return "<reqCondGroup><noConds/></reqCondGroup>" unless section_node
      conditions_xml_elements = []
      has_actual_conditions = false
      
      filtered_blocks = section_node.blocks.reject do |block|
        ['applicdef', 'productdef', 'attribute_def', 'global_applicability_definition', 'dmlref'].any? do |role_style|
          block.role == role_style || block.style == role_style
        end
      end

      filtered_blocks.each do |block|
        case block.context
        when :paragraph
          has_actual_conditions = true
          conditions_xml_elements << "<reqCondNoRef#{common_attributes(block.id)}#{applic_ref_attribute(block)}><reqCond>#{block.content}</reqCond></reqCondNoRef>"
        when :ulist, :olist
          has_actual_conditions = true
          block.items.each do |item|
            item_id_val = item.id
            item_applic_ref_val = item.attr('applic_ref')
            item_s1000d_id_attr_str = common_attributes(item_id_val)
            item_s1000d_applic_attr_str = item_applic_ref_val ? %( applicRefId="#{esc_text(item_applic_ref_val)}") : ''
            
            raw_item_text_content = item.text.to_s.strip
            processed_content_for_condition = item.apply_subs(raw_item_text_content) 
            item_blocks_xml = item.blocks.map(&:convert).join("\n")

            text_xml_part = processed_content_for_condition.strip.empty? ? "" : "#{processed_content_for_condition}"
            final_req_cond_content = "#{text_xml_part}#{item_blocks_xml}"

            if final_req_cond_content.strip.empty?
              final_req_cond_content = "<simplePara/>"
            end

            pm_to_parse = item.attr('pmref')
            dm_to_parse = item.attr('dmref')

            if pm_to_parse && !pm_to_parse.strip.empty?
              parsed_pm_ref_code = parse_pmc_string(pm_to_parse)
              if parsed_pm_ref_code; pm_ref_xml_part = <<~XML.strip; conditions_xml_elements << "<reqCondPm#{item_s1000d_id_attr_str}#{item_s1000d_applic_attr_str}><reqCond>#{final_req_cond_content}</reqCond>#{pm_ref_xml_part}</reqCondPm>"
                  <pmRef><pmRefIdent><pmCode modelIdentCode="#{esc_text(parsed_pm_ref_code[:modelIdentCode])}" pmIssuer="#{esc_text(parsed_pm_ref_code[:pmIssuer])}" pmNumber="#{esc_text(parsed_pm_ref_code[:pmNumber])}" pmVolume="#{esc_text(parsed_pm_ref_code[:pmVolume])}"/><language languageIsoCode="#{esc_text(parsed_pm_ref_code[:languageIsoCode])}" countryIsoCode="#{esc_text(parsed_pm_ref_code[:countryIsoCode])}"/></pmRefIdent></pmRef>
                XML
              else warn "asciidoctor: WARNING: Failed to parse PMC reference in condition item. Skipping PMC attributes."; conditions_xml_elements << "<reqCondNoRef#{item_s1000d_id_attr_str}#{item_s1000d_applic_attr_str}><reqCond>#{final_req_cond_content}</reqCond></reqCondNoRef>"; end
            elsif dm_to_parse && !dm_to_parse.strip.empty?
              parsed_dm_ref_code = parse_dmc_string(dm_to_parse)
              if parsed_dm_ref_code; dm_code_attrs_xml=parsed_dm_ref_code.map{|k,v|%(#{k}="#{esc_text(v)}")}.join(' ');dm_ref_xml_part="<dmRef><dmRefIdent><dmCode #{dm_code_attrs_xml}/></dmRefIdent></dmRef>";conditions_xml_elements << "<reqCondDm#{item_s1000d_id_attr_str}#{item_s1000d_applic_attr_str}><reqCond>#{final_req_cond_content}</reqCond>#{dm_ref_xml_part}</reqCondDm>";
              else warn "asciidoctor: WARNING: Failed to parse DMC reference in condition item. Skipping DMC attributes."; conditions_xml_elements << "<reqCondNoRef#{item_s1000d_id_attr_str}#{item_s1000d_applic_attr_str}><reqCond>#{final_req_cond_content}</reqCond></reqCondNoRef>"; end
            else
              conditions_xml_elements << "<reqCondNoRef#{item_s1000d_id_attr_str}#{item_s1000d_applic_attr_str}><reqCond>#{final_req_cond_content}</reqCond></reqCondNoRef>"
            end
          end
        when :admonition
          has_actual_conditions = true
          conditions_xml_elements << block.convert
        when :table 
            has_actual_conditions = true
            conditions_xml_elements << block.convert
        else
          unless block.context == :thematic_break || block.context == :section 
            warn "asciidoctor: WARNING: Block of context '#{block.context}' found directly in required conditions section. Converting as generic paragraph."
            has_actual_conditions = true
            conditions_xml_elements << "<reqCondNoRef#{common_attributes(block.id)}#{applic_ref_attribute(block)}><reqCond><simplePara>#{block.content}</simplePara></reqCond></reqCondNoRef>"
          end
        end
      end
      if !has_actual_conditions || conditions_xml_elements.empty?; return "<reqCondGroup><noConds/></reqCondGroup>";
      else 
        return "<reqCondGroup>\n#{conditions_xml_elements.join("\n")}\n</reqCondGroup>"; 
      end
    end

    def generate_req_tech_info_group_xml(section_node)
      default_no_req_tech_info = "<reqTechInfoGroup><noReqTechInfo/></reqTechInfoGroup>"
      return default_no_req_tech_info unless section_node
      tech_info_entries = []
      found_explicit_no_info = false
      
      section_node.blocks.each do |block|
        break if found_explicit_no_info
        if block.context == :ulist || block.context == :olist
          block.items.each do |item|
            dmc_to_parse = nil; dmc_attr_value = item.attr('dmc')
            if dmc_attr_value && !dmc_attr_value.strip.empty?; dmc_to_parse = dmc_attr_value.strip;
            else
              raw_item_text = item.text.to_s.strip
              if raw_item_text.downcase.match?(/(no|none)\s+(required\s+)?tech(nical)?\s+info(rmation)?/i); found_explicit_no_info = true; break; end
              dmc_candidate_regex = /((?:DMC-)?(?:[A-Z0-9]+-){10}[A-Z0-9]+)/i; match_data = dmc_candidate_regex.match(raw_item_text)
              if match_data && match_data[1]; potential_dmc_from_text = match_data[1]
                if parse_dmc_string(potential_dmc_from_text); dmc_to_parse = potential_dmc_from_text;
                else if !raw_item_text.empty?; warn "asciidoctor: WARNING: Text in technical info item looks like a DMC but failed to parse: '#{raw_item_text}'. Skipping this entry.";
                end; 
                next; 
              end
              else if !raw_item_text.empty?; warn "asciidoctor: WARNING: Text in technical info item is not a recognized DMC format: '#{raw_item_text}'. Skipping this entry.";
              end; next; 
            end
            end
            next if dmc_to_parse.nil? || dmc_to_parse.empty?
            category = item.attr('category', 'ti01'); parsed_dmc_hash = parse_dmc_string(dmc_to_parse)
            if parsed_dmc_hash; dm_code_attrs_xml = parsed_dmc_hash.map { |k, v| %(#{k}="#{esc_text(v)}") }.join(' '); tech_info_entries << <<~XML.strip; else warn "asciidoctor: WARNING: DMC for technical info item failed to parse after explicit attribute. Skipping."; end
              <reqTechInfo#{common_attributes item.id}#{applic_ref_attribute item} reqTechInfoCategory="#{esc_text(category)}"><dmRef><dmRefIdent><dmCode #{dm_code_attrs_xml}/></dmRefIdent></dmRef></reqTechInfo>
            XML
          end
        elsif block.context == :paragraph
          if block.source.strip.downcase.match?(/(no|none)\s+(required\s+)?tech(nical)?\s+info(rmation)?/i); found_explicit_no_info = true;
          elsif !block.source.strip.empty?; warn "asciidoctor: WARNING: Paragraph content found directly in required technical information section: '#{block.source.strip}'. Skipping."; end
        end
      end
      if found_explicit_no_info || tech_info_entries.empty?; return default_no_req_tech_info;
      else return "<reqTechInfoGroup>\n#{tech_info_entries.join("\n")}\n</reqTechInfoGroup>"; 
      end
    end

    def determine_internal_ref_target_type(target_node, target_id_for_warning)
      return "" unless target_node
      case target_node.context
      when :image; ' internalRefTargetType="irtt01"'
      when :paragraph; target_node.role == 'note-para' ? ' internalRefTargetType="irtt08"' : ' internalRefTargetType="irtt02"'
      when :table; ' internalRefTargetType="irtt03"'
      when :admonition; case target_node.attr('name')&.upcase; when 'NOTE'; ' internalRefTargetType="irtt08"'; when 'WARNING'; ' internalRefTargetType="irtt09"'; when 'CAUTION'; ' internalRefTargetType="irtt0A"'; else ''; end
      when :olist_item, :ulist_item; if target_node.context == :olist_item || target_node.id&.downcase&.start_with?('step_') || target_node.role == 'proceduralStep'; ' internalRefTargetType="irtt0F"'; else ' internalRefTargetType="irtt04"'; end
      when :section; ' internalRefTargetType="irtt07"'
      else warn "asciidoctor: INFO: Could not determine S1000D internalRefTargetType for ID '#{target_id_for_warning}' (context: #{target_node.context}). Omitting."; ''; end
    end

    def generate_req_persons_xml(section_node)
      return "" unless section_node; table_node = section_node.blocks.find { |b| b.context == :table }; return "" unless table_node
      personnel_entries = table_node.rows.body.map do |row|
        desc_text = row[0] ? esc_text(row[0].text.strip) : "N/A"
        category_code = row[1] ? esc_text(row[1].text.strip.upcase) : "MAINT"
        skill_level_code = row[2] ? esc_text(row[2].text.strip) : "01"
        number_val = row[3] ? esc_text(row[3].text.strip) : "1"
        time_val = row[4] ? esc_text(row[4].text.strip) : "0.0"
        time_unit = (row[5] && !row[5].text.strip.empty?) ? esc_text(row[5].text.strip.downcase) : "h"
        <<~XML.strip
          <person man="#{number_val}"><personCategory personCategoryCode="#{category_code}"></personCategory><personSkill skillLevelCode="#{skill_level_code}"/><trade>#{desc_text}</trade><estimatedTime unitOfMeasure="#{time_unit}">#{time_val}</estimatedTime></person>
        XML
      end
      personnel_entries.empty? ? "" : "<reqPersons>\n#{personnel_entries.join("\n")}\n</reqPersons>"
    end

    def generate_table_based_req_list(section_node, list_tag, group_tag, individual_item_tag, no_item_tag, cols_map)
      return "<#{list_tag}>#{no_item_tag}</#{list_tag}>" unless section_node
      table_node = section_node.blocks.find { |b| b.context == :table }
      if !table_node
        if section_node.blocks.length == 1 && section_node.blocks.first.context == :paragraph
          content = section_node.blocks.first.source.downcase
          if content.include?("no ") && (content.include?(individual_item_tag.downcase) || content.include?(list_tag.downcase.gsub(/^req|s$/,'')))
            return "<#{list_tag}>#{no_item_tag}</#{list_tag}>"
          end
        end
        return "<#{list_tag}>#{no_item_tag}</#{list_tag}>"
      end
      items_xml = table_node.rows.body.each_with_index.map do |row_cells, idx|
        name_cell_idx = cols_map[:name]; attr_cell = row_cells[name_cell_idx]
        item_id_attr = attr_cell ? common_attributes(attr_cell.id || "#{individual_item_tag}-#{idx}") : common_attributes("#{individual_item_tag}-#{idx}")
        item_applic_attr = attr_cell ? applic_ref_attribute(attr_cell) : ''
        name_text = (cols_map[:name] && row_cells[cols_map[:name]]) ? esc_text(row_cells[cols_map[:name]].text.strip) : "N/A"
        mfr_code  = (cols_map[:mfr] && row_cells[cols_map[:mfr]]) ? esc_text(row_cells[cols_map[:mfr]].text.strip) : ""
        part_no   = (cols_map[:pn] && row_cells[cols_map[:pn]])  ? esc_text(row_cells[cols_map[:pn]].text.strip)  : ""
        qty       = (cols_map[:qty] && row_cells[cols_map[:qty]]) ? esc_text(row_cells[cols_map[:qty]].text.strip) : "1"
        uom_code  = (cols_map[:uom] && row_cells[cols_map[:uom]]) ? esc_text(row_cells[cols_map[:uom]].text.strip.upcase) : "EA"
        rem       = (cols_map[:rmk] && row_cells[cols_map[:rmk]])  ? esc_text(row_cells[cols_map[:rmk]].text.strip)  : ""
        itm       = (cols_map[:iem] && row_cells[cols_map[:iem]])  ? esc_text(row_cells[cols_map[:iem]].text.strip)  : ""
        nam       = (cols_map[:nm] && row_cells[cols_map[:nm]])  ? esc_text(row_cells[cols_map[:nm]].text.strip)  : "N/A" 
        case group_tag
        when "supportEquipDescrGroup"; %(<#{individual_item_tag}#{item_id_attr}#{item_applic_attr}><name>#{nam}</name><catalogSeqNumberRef figureNumber="#{name_text}" item="#{itm}"></catalogSeqNumberRef><identNumber><manufacturerCode>#{mfr_code}</manufacturerCode><partAndSerialNumber><partNumber>#{part_no}</partNumber></partAndSerialNumber></identNumber><reqQuantity>#{qty}</reqQuantity><remarks><simplePara>#{rem}</simplePara></remarks></#{individual_item_tag}>)
        when "supplyDescrGroup"; %(<#{individual_item_tag}#{item_id_attr}#{item_applic_attr}><name>#{nam}</name><identNumber><manufacturerCode>#{mfr_code}</manufacturerCode><partAndSerialNumber><partNumber>#{part_no}</partNumber></partAndSerialNumber></identNumber><reqQuantity unitOfMeasure="#{uom_code}">#{qty}</reqQuantity><remarks><simplePara>#{rem}</simplePara></remarks></#{individual_item_tag}>)
        when "spareDescrGroup"; %(<#{individual_item_tag}#{item_id_attr}#{item_applic_attr}><name>#{nam}</name><catalogSeqNumberRef figureNumber="#{name_text}" item="#{itm}"/><identNumber><manufacturerCode>#{mfr_code}</manufacturerCode><partAndSerialNumber><partNumber>#{part_no}</partNumber></partAndSerialNumber></identNumber><reqQuantity>#{qty}</reqQuantity><remarks><simplePara>#{rem}</simplePara></remarks></#{individual_item_tag}>)
        end
      end.compact.join("\n")
      if items_xml.empty?; "<#{list_tag}>#{no_item_tag}</#{list_tag}>";
      else list_tag_attrs = common_attributes(section_node.id) + applic_ref_attribute(section_node); "<#{list_tag}#{list_tag_attrs}><#{group_tag}>\n#{items_xml}\n</#{group_tag}></#{list_tag}>"; end
    end

    def generate_req_safety_xml(section_node)
      return "<reqSafety><noSafety/></reqSafety>" unless section_node
      safety_elements = section_node.blocks.map(&:convert).map(&:strip).reject(&:empty?)
      req_safety_attrs = common_attributes(section_node.id) + applic_ref_attribute(section_node)
      if safety_elements.empty?; "<reqSafety#{req_safety_attrs}><noSafety/></reqSafety>";
      else "<reqSafety#{req_safety_attrs}><safetyRqmts>\n#{safety_elements.join("\n")}\n</safetyRqmts></reqSafety>"; end
    end

    def generate_preliminary_requirements_xml(document_node)
      prelim_section = document_node.blocks.find { |b| b.context == :section && (b.id == 'prelim_reqs' || b.title.downcase.include?('preliminary requirements')) }
      
      content_map = { 
        req_conds: "<reqCondGroup><noConds/></reqCondGroup>", 
        req_persons: "", 
        req_tech_info: "<reqTechInfoGroup><noReqTechInfo/></reqTechInfoGroup>", 
        req_support_equip: "<reqSupportEquips><noSupportEquips/></reqSupportEquips>", 
        req_supplies: "<reqSupplies><noSupplies/></reqSupplies>", 
        req_spares: "<reqSpares><noSpares/></reqSpares>", 
        req_safety: "<reqSafety><noSafety/></reqSafety>" 
      }

      subsection_handlers = {
        'required conditions' => :req_conds,
        'required_conditions_pr' => :req_conds,
        'required persons' => :req_persons,
        'required_persons_pr' => :req_persons,
        'required technical information' => :req_tech_info,
        'required_tech_info_pr' => :req_tech_info,
        'required support equipment' => :req_support_equip,
        'required_equip_pr' => :req_support_equip,
        'required supplies' => :req_supplies,
        'required_supplies_pr' => :req_supplies,
        'required spares' => :req_spares,
        'required_spares_pr' => :req_spares,
        'required safety' => :req_safety,
        'required_safety_pr' => :req_safety,
      }

      if prelim_section
        prelim_section.blocks.each do |sub_block|
          next unless sub_block.context == :section 
          
          key = sub_block.id&.downcase || sub_block.title.downcase.strip
          handler_sym = subsection_handlers[key]

          if handler_sym
            case handler_sym
            when :req_conds
              content_map[:req_conds] = generate_req_cond_group_xml(sub_block)
            when :req_persons
              content_map[:req_persons] = generate_req_persons_xml(sub_block)
            when :req_tech_info
              content_map[:req_tech_info] = generate_req_tech_info_group_xml(sub_block)
            when :req_support_equip
              content_map[:req_support_equip] = generate_table_based_req_list(sub_block, "reqSupportEquips", "supportEquipDescrGroup", "supportEquipDescr", "<noSupportEquips/>", {name:0, mfr:5, pn:2, qty:3, rmk:6, iem:1, nm:4})
            when :req_supplies
              content_map[:req_supplies] = generate_table_based_req_list(sub_block, "reqSupplies", "supplyDescrGroup", "supplyDescr", "<noSupplies/>", {name:0, mfr:1, pn:2, qty:3, uom:4, rmk:5, nm:0})
            when :req_spares
              content_map[:req_spares] = generate_table_based_req_list(sub_block, "reqSpares", "spareDescrGroup", "spareDescr", "<noSpares/>", {name:0, mfr:5, pn:2, qty:3, rmk:6, iem:1, nm:4})
            when :req_safety
              content_map[:req_safety] = generate_req_safety_xml(sub_block)
            end
          else
            warn "asciidoctor: WARNING: Unrecognized sub-section in Preliminary Requirements: '#{sub_block.title}' (ID: #{sub_block.id}). Content will be skipped."
          end
        end
      end
      
      prelim_parts = [
        content_map[:req_conds],
        (content_map[:req_persons] unless content_map[:req_persons].empty?),
        content_map[:req_tech_info],
        content_map[:req_support_equip],
        content_map[:req_supplies],
        content_map[:req_spares],
        content_map[:req_safety]
      ].compact.join("\n")

      prelim_attrs = prelim_section ? common_attributes(prelim_section.id) + applic_ref_attribute(prelim_section) : ""
      indented_prelim_parts = prelim_parts.empty? ? "" : "\n#{prelim_parts.gsub(/^/, '  ')}\n"
      "<preliminaryRqmts#{prelim_attrs}>#{indented_prelim_parts}</preliminaryRqmts>"
    end

    # This function sets the context flag before processing.
    def generate_main_procedure_steps_xml(document_node)
      main_proc_section = document_node.blocks.find { |b| b.context == :section && (b.id == 'main_proc_steps' || b.title.downcase.include?('main procedure')) }

      blocks_for_main_procedure_body = if main_proc_section
                             main_proc_section.blocks
                           else
                             document_node.blocks.reject do |b|
                               is_special_section = b.context == :section &&
                                                    (['prelim_reqs', 'closeout_reqs', 'fault_iso_main', 'fault_descr'].any? { |id_part| b.id&.include?(id_part) || b.title.downcase.include?(id_part) })
                               is_definition_block_or_ref = ['applicdef', 'productdef', 'attribute_def', 'global_applicability_definition', 'dmlref'].any? { |role_style| b.role == role_style || b.style == role_style }
                               is_special_section || is_definition_block_or_ref
                             end
                           end
      
      # Set the context flag to true before we start processing the procedure.
      @is_in_main_procedure = true
      steps_content = process_blocks_into_steps(blocks_for_main_procedure_body, "main-proc")
      # Unset the flag after we are done to prevent side-effects.
      @is_in_main_procedure = false
      
      steps_content.empty? ? "<proceduralStep><para/></proceduralStep>" : steps_content
    end
    
    # This function is now a simple dispatcher.
    def process_blocks_into_steps(blocks_array, parent_step_id_prefix)
      steps_xml_parts = []
      
      filtered_blocks = blocks_array.reject do |b|
        ['applicdef', 'productdef', 'attribute_def', 'global_applicability_definition', 'dmlref'].any? { |role_style| b.role == role_style || b.style == role_style } ||
        (b.context == :paragraph && !b.id && b.source.strip.empty?) ||
        b.context == :thematic_break
      end
      
      filtered_blocks.each do |block|
        if block.context == :section
          # A section is a step. Let the smart `convert_section` handle it.
          steps_xml_parts << block.convert
          
        elsif block.context == :olist
          # An ordered list is a SEQUENCE of steps.
          block.items.each do |li|
            step_attrs = common_attributes(li.id) + applic_ref_attribute(li)
            step_xml = "<proceduralStep#{step_attrs}>"
            if li.text? && !li.text.strip.empty?
              step_xml << "<title>#{li.apply_subs(li.text)}</title>"
            end
            step_xml << li.content if li.blocks?
            step_xml << "</proceduralStep>"
            steps_xml_parts << step_xml
          end
          
        else
          # Any other block at the top level (e.g., a loose paragraph)
          # becomes its own simple step.
          steps_xml_parts << "<proceduralStep>#{block.convert}</proceduralStep>"
        end
      end

      steps_xml_parts.join("\n")
    end

    def generate_fault_isolation_main_procedure_xml(document_node)
      fault_main_section = document_node.blocks.find { |b| b.context == :section && (b.id == 'fault_iso_main' || b.title.downcase.include?('fault isolation procedure')) }
      blocks_to_process = if fault_main_section; fault_main_section.blocks; else document_node.blocks.reject { |b| ['prelim_reqs', 'closeout_reqs', 'fault_descr'].any? { |id_part| b.id&.include?(id_part) || b.title.downcase.include?(id_part) } || ['applicdef', 'productdef', 'attribute_def', 'global_applicability_definition'].any? { |role_style| b.role == role_style || b.style == role_style }}; end
      isolation_steps_content = blocks_to_process.each_with_index.map do |block, index| step_id = block.id || "iso-step-#{index + 1}"; step_attrs = common_attributes(step_id) + applic_ref_attribute(block); converted_content = block.convert; converted_content.to_s.strip.empty? ? nil : "<isolationStep#{step_attrs}>#{converted_content}</isolationStep>"; end.compact.join("\n")
      isolation_steps_content = "<isolationProcedureEnd id=\"auto-end-empty-proc\"/>" if isolation_steps_content.strip.empty?; main_proc_attrs = fault_main_section ? common_attributes(fault_main_section.id) + applic_ref_attribute(fault_main_section) : ""; indented_steps = isolation_steps_content.empty? ? "" : "\n#{isolation_steps_content.gsub(/^/, '  ')}\n"; "<isolationMainProcedure#{main_proc_attrs}>#{indented_steps}</isolationMainProcedure>"
    end

    def generate_close_requirements_xml(document_node)
      close_section = document_node.blocks.find { |b| b.context == :section && (b.id == 'closeout_reqs' || b.title.downcase.include?('closeout requirements') || b.title.downcase.include?('requirements after job completion')) }
      req_conds_xml = "<reqCondGroup><noConds/></reqCondGroup>"
      attrs_for_close_rqmts = ""

      if close_section
        attrs_for_close_rqmts = common_attributes(close_section.id) + applic_ref_attribute(close_section)
        conds_subsection = close_section.blocks.find { |b| b.context == :section && (b.id == 'closeout_conds_after' || b.title.downcase.include?('required conditions after job completion')) }
        target_node_for_conds = conds_subsection || close_section 

        req_conds_xml = generate_req_cond_group_xml(target_node_for_conds, true)
      end

      indented_conds = req_conds_xml.empty? ? "" : "\n#{req_conds_xml.gsub(/^/, '  ')}\n"
      "<closeRqmts#{attrs_for_close_rqmts}>#{indented_conds}</closeRqmts>"
    end

    def build_applic_condition_xml(condition_hash, indent_level = 0)
      current_indent_str = "  " * indent_level; xml_string = ""; unless condition_hash.is_a?(Hash); warn "asciidoctor: WARNING: Applicability condition hash is not a Hash. Skipping."; return ""; end; type = condition_hash['type']&.downcase
      if type == 'evaluate'; and_or = condition_hash['andOr']&.downcase || 'and'; children = condition_hash['children']; xml_string << "#{current_indent_str}<evaluate andOr=\"#{esc_text(and_or)}\">\n"; if children.is_a?(Array) && !children.empty?; children.each { |child_hash| xml_string << build_applic_condition_xml(child_hash, indent_level + 1) }; else warn "asciidoctor: WARNING: Applicability 'evaluate' block has no children or invalid children array. Skipping."; end; xml_string << "#{current_indent_str}</evaluate>\n";
      elsif type == 'assert'; prop_ident = condition_hash['propertyIdent']; prop_values = condition_hash['propertyValues']; prop_type = condition_hash['propertyType'] || 'prodattr'; if prop_ident && prop_values; xml_string << "#{current_indent_str}<assert applicPropertyIdent=\"#{esc_text(prop_ident)}\" applicPropertyType=\"#{esc_text(prop_type)}\" applicPropertyValues=\"#{esc_text(prop_values)}\"/>\n"; else warn "asciidoctor: WARNING: Applicability 'assert' block is missing propertyIdent or propertyValues. Skipping."; end;
      else warn "asciidoctor: WARNING: Unknown applicability condition type '#{type}'. Skipping."; end; xml_string
    end

    def generate_flat_global_asserts_xml(doc_attrs)
      collected_asserts = []; (1..).each do |i|; prop_ident = doc_attrs.fetch("s1000d-global-assert-#{i}-propertyident",nil).to_s.strip; prop_values = doc_attrs.fetch("s1000d-global-assert-#{i}-propertyvalues",nil).to_s.strip; break if prop_ident.empty?||prop_values.empty?; prop_type=doc_attrs.fetch("s1000d-global-assert-#{i}-propertytype",'prodattr').to_s.strip; prop_type='prodattr' if prop_type.empty?; collected_asserts << %(<assert applicPropertyIdent="#{esc_text(prop_ident)}" applicPropertyType="#{esc_text(prop_type)}" applicPropertyValues="#{esc_text(prop_values)}"/>); end; return "" if collected_asserts.empty?
      if collected_asserts.length > 1; operator = doc_attrs.fetch('s1000d-global-assert-operator','and').to_s.downcase.strip; operator = ['and','or'].include?(operator) ? operator : 'and'; %(<evaluate andOr="#{operator}">\n#{collected_asserts.map { |a| "  #{a}" }.join("\n")}\n</evaluate>); else collected_asserts.first; end
    end

    def build_ident_and_status_section_xml(doc_attrs, dm_code_attrs_in, act_dm_ref_for_dmstatus, global_applic_text_val, brex_dm_code_attrs_in, rfu_elements_xml, current_node_for_title)
      dm_code_attrs = dm_code_attrs_in; lang_code=(doc_attrs['lang']||doc_attrs['language']||'en').downcase; country_code=(doc_attrs['country-code']||doc_attrs['country']||'IN').upcase; issue_number=doc_attrs['issue-number']||"001"; in_work_status=doc_attrs['in-work']||doc_attrs['inwork-status']||"00"; date_str=(doc_attrs['revdate']||doc_attrs['issue-date']).to_s.strip; year,month,day = nil,nil,nil; if date_str.match?(/^\d{4}-\d{2}-\d{2}$/);year,month,day=date_str.split('-');elsif date_str.match?(/^\d{8}$/);year,month,day=date_str[0..3],date_str[4..5],date_str[6..7];elsif !date_str.empty?;warn "...";end; unless year&&month&&day;now=Time.now;year,month,day=now.strftime('%Y'),now.strftime('%m'),now.strftime('%d');warn "..." if date_str.empty?;end; doc_title_obj=current_node_for_title.doctitle if current_node_for_title.respond_to?(:doctitle); tech_name=doc_attrs['tech-name']||doc_title_obj||"Default Technical Name"; dm_title_text=doc_attrs['dm-title']||doc_attrs['infoName']||tech_name; security_class=doc_attrs['security-classification']||"01"; enterprise_rpc_code=doc_attrs['enterprise-code-rpc']||"0000X"; rpc_name=doc_attrs['responsible-partner-company']||"UNKNOWN RPC"; enterprise_orig_code=doc_attrs['enterprise-code-originator']||enterprise_rpc_code; orig_name=doc_attrs['originator-enterprise']||rpc_name; brex_attrs=brex_dm_code_attrs_in; global_applic_inner_xml=""; if @global_applic_eval_hash&&@global_applic_eval_hash.is_a?(Hash)&&!@global_applic_eval_hash.empty?;raw_xml=build_applic_condition_xml(@global_applic_eval_hash);global_applic_inner_xml=raw_xml.strip;else flat_asserts_xml=generate_flat_global_asserts_xml(doc_attrs);global_applic_inner_xml=flat_asserts_xml.strip;if global_applic_inner_xml.empty?;if @global_applic_eval_hash&.empty?&&node_has_global_applic_block(doc_attrs[:document_node]);warn "...";elsif node_has_global_applic_block(doc_attrs[:document_node])&&@global_applic_eval_hash.nil?;warn "...";end;end;end; global_applic_xml_for_status=global_applic_inner_xml.empty? ? "" : "\n#{global_applic_inner_xml.gsub(/^/,'      ')}"; indented_rfu=rfu_elements_xml.strip.empty? ? "" : "\n"+rfu_elements_xml.strip.gsub(/^/,'    '); indented_act_ref=act_dm_ref_for_dmstatus.strip.empty? ? '' : "\n"+act_dm_ref_for_dmstatus.strip.gsub(/^/,'    ');
      <<~IASS_XML.strip
      <identAndStatusSection><dmAddress><dmIdent><dmCode modelIdentCode="#{dm_code_attrs[:modelIdentCode]}" systemDiffCode="#{dm_code_attrs[:systemDiffCode]}" systemCode="#{dm_code_attrs[:systemCode]}" subSystemCode="#{dm_code_attrs[:subSystemCode]}" subSubSystemCode="#{dm_code_attrs[:subSubSystemCode]}" assyCode="#{dm_code_attrs[:assyCode]}" disassyCode="#{dm_code_attrs[:disassyCode]}" disassyCodeVariant="#{dm_code_attrs[:disassyCodeVariant]}" infoCode="#{dm_code_attrs[:infoCode]}" infoCodeVariant="#{dm_code_attrs[:infoCodeVariant]}" itemLocationCode="#{dm_code_attrs[:itemLocationCode]}"/><language languageIsoCode="#{lang_code}" countryIsoCode="#{country_code}"/><issueInfo issueNumber="#{issue_number}" inWork="#{in_work_status}"/></dmIdent><dmAddressItems><issueDate year="#{year}" month="#{month}" day="#{day}"/><dmTitle><techName>#{esc_text(tech_name)}</techName><infoName>#{esc_text(dm_title_text)}</infoName></dmTitle></dmAddressItems></dmAddress><dmStatus issueType="new"><security securityClassification="#{security_class}"/><responsiblePartnerCompany enterpriseCode="#{esc_text(enterprise_rpc_code)}"><enterpriseName>#{esc_text(rpc_name)}</enterpriseName></responsiblePartnerCompany><originator enterpriseCode="#{esc_text(enterprise_orig_code)}"><enterpriseName>#{esc_text(orig_name)}</enterpriseName></originator>#{indented_act_ref}<applic><displayText><simplePara>#{esc_text(global_applic_text_val)}</simplePara></displayText>#{global_applic_xml_for_status}</applic><brexDmRef><dmRef><dmRefIdent><dmCode modelIdentCode="#{brex_attrs[:modelIdentCode]}" systemDiffCode="#{brex_attrs[:systemDiffCode]}" systemCode="#{brex_attrs[:systemCode]}" subSystemCode="#{brex_attrs[:subSystemCode]}" subSubSystemCode="#{brex_attrs[:subSubSystemCode]}" assyCode="#{brex_attrs[:assyCode]}" disassyCode="#{brex_attrs[:disassyCode]}" disassyCodeVariant="#{brex_attrs[:disassyCodeVariant]}" infoCode="#{brex_attrs[:infoCode]}" infoCodeVariant="#{brex_attrs[:infoCodeVariant]}" itemLocationCode="#{brex_attrs[:itemLocationCode]}"/></dmRefIdent></dmRef></brexDmRef><qualityAssurance><unverified/></qualityAssurance>#{indented_rfu}</dmStatus></identAndStatusSection>
      IASS_XML
    end

    def build_doctype_declaration(content_markup_for_icns)
      icn_ids = content_markup_for_icns.scan(/infoEntityIdent=["']((?:ICN|FIG)-[A-Z0-9\-]+)["']/).flatten.uniq; return "<!DOCTYPE dmodule>" if icn_ids.empty?; declarations = ["<!NOTATION PNG SYSTEM \"PNG\">"]; icn_ids.each { |icn| declarations << "<!ENTITY #{esc_text(icn)} SYSTEM \"#{esc_text(icn)}.png\" NDATA PNG>" }; "<!DOCTYPE dmodule [\n  #{declarations.join("\n  ")}\n]>"
    end

    def get_schema_file(dm_type_str)
      type = dm_type_str.downcase.strip; 
      case type; 
      when 'procedure','procedural';'proced.xsd';
      when 'fault','faultisolation';'fault.xsd';
      when 'act','applic cross-reference table';'applicom.xsd';
      when 'pct','product cross-reference table';'applicom.xsd';
      when 'cct','condition cross-reference table';'applicom.xsd';
      when 'descript','description','descriptive';'descript.xsd';
      when 'crew';'crew.xsd';
      when 'sched','scheduled maintenance';'sched.xsd';
      when 'catalog','ipd','illustrated parts data';'ipd.xsd';
      when 'learning';'learning.xsd';
      when 'comrep';'comrep.xsd';
      when 'sb','service bulletin';'sb.xsd';
      when 'process';'process.xsd';
      when 'wiring';'wire.xsd';
      else warn "asciidoctor: WARNING: Unknown DM type '#{type}'. Defaulting to descript.xsd.";'descript.xsd';
      end
    end

    def node_has_global_applic_block(document_node)
      return false unless document_node&.respond_to?(:blocks); document_node.blocks.any? { |b| (b.role == 'global_applicability_definition') || (b.style == 'global_applicability_definition') }
    end

    def collect_definitions_recursively(blocks)
      blocks.each do |block|
        if block.role == 'applicdef'; process_as_applic_definition(block);
        elsif block.role == 'productdef'; process_as_product_definition(block);
        elsif block.role == 'attribute_def'; process_as_product_attribute_definition(block);
        elsif block.role == 'global_applicability_definition' || block.style == 'global_applicability_definition'
          json_string = block.content
          begin
            parsed = JSON.parse(json_string)
            @global_applic_eval_hash = (parsed.is_a?(Hash) && !parsed.empty?) ? parsed : (warn("asciidoctor: WARNING: Global applicability JSON block was empty or not a hash. Ignoring."); nil);
          rescue JSON::ParserError => e
            warn "asciidoctor: ERROR: Failed to parse JSON in global applicability definition block: #{e.message}. Skipping."; @global_applic_eval_hash = nil;
          end;
        elsif block.blocks?
          collect_definitions_recursively(block.blocks)
        end
      end
    end

    def convert_document node
      @s1000d_applic_definitions, @s1000d_product_definitions, @s1000d_product_attribute_definitions = [], [], []
      @global_applic_eval_hash = nil
      doc_attrs = node.document.attributes.dup; doc_attrs[:document_node] = node

      collect_definitions_recursively(node.blocks)

      dmc_str = doc_attrs['dmc'] || doc_attrs['part-title']; dm_code_attrs = parse_dmc_string(dmc_str) || begin warn "asciidoctor: ERROR: Document DMC attribute '#{dmc_str}' is invalid. Using placeholder DMC."; { modelIdentCode: "S1KDTOOLS", systemDiffCode: "A", systemCode: "00", subSystemCode: "0", subSubSystemCode: "0", assyCode: "0000", disassyCode: "00", disassyCodeVariant: "A", infoCode: "000", infoCodeVariant: "A", itemLocationCode: "A" }; 
      end
      brex_dmc_str = doc_attrs['brex-dmc']; brex_dm_code_attrs = parse_dmc_string(brex_dmc_str) || begin warn "asciidoctor: WARNING: BREX DMC attribute '#{brex_dmc_str}' is invalid. Using default BREX DMC."; { modelIdentCode: "S1000D", systemDiffCode: "G", systemCode: "04", subSystemCode: "1", subSubSystemCode: "0", assyCode: "0301", disassyCode: "00", disassyCodeVariant: "A", infoCode: "022", infoCodeVariant: "A", itemLocationCode: "D" }; 
      end
      global_applic_text = (doc_attrs['s1000d-applic-text'] || doc_attrs['applicability-text'] || doc_attrs['applicability'] || "All applicable conditions").strip
      act_dmc_str = doc_attrs['act-dmc']; act_dm_ref_xml = ""; if act_dmc_str && !act_dmc_str.strip.empty?; if act_dm_c = parse_dmc_string(act_dmc_str); act_dm_ref_xml = "<applicCrossRefTableRef><dmRef><dmRefIdent><dmCode modelIdentCode=\"#{act_dm_c[:modelIdentCode]}\" systemDiffCode=\"#{act_dm_c[:systemDiffCode]}\" systemCode=\"#{act_dm_c[:systemCode]}\" subSystemCode=\"#{act_dm_c[:subSystemCode]}\" subSubSystemCode=\"#{act_dm_c[:subSubSystemCode]}\" assyCode=\"#{act_dm_c[:assyCode]}\" disassyCode=\"#{act_dm_c[:disassyCode]}\" disassyCodeVariant=\"#{act_dm_c[:disassyCodeVariant]}\" infoCode=\"#{act_dm_c[:infoCode]}\" infoCodeVariant=\"#{act_dm_c[:infoCodeVariant]}\" itemLocationCode=\"#{act_dm_c[:itemLocationCode]}\"/></dmRefIdent></dmRef></applicCrossRefTableRef>"; 
    else warn "asciidoctor: WARNING: ACT DMC attribute '#{act_dmc_str}' is invalid. Skipping ACT reference."; 
    end; 
  end
      rfu_raw = doc_attrs['reason-for-update'] || doc_attrs['rfu']; rfu_xml = if rfu_raw && !rfu_raw.strip.empty?; id_val,h_val,t_val=doc_attrs.values_at('rfu-id','rfu-highlight','rfu-type').map(&:to_s); %(\n<reasonForUpdate id="#{esc_text(id_val.empty? ? "rfu-0001" : id_val)}" updateHighlight="#{esc_text(h_val.empty? ? "1" : h_val)}" updateReasonType="#{esc_text(t_val.empty? ? "urt02" : t_val)}"><simplePara>#{esc_text(rfu_raw)}</simplePara></reasonForUpdate>); 
      else %(\n<reasonForUpdate id="rfu-def-0001" updateHighlight="1" updateReasonType="urt01"><simplePara>Initial issue or standard update.</simplePara></reasonForUpdate>); 
      end
      dm_type = (doc_attrs['dm-type'] || 'descript').downcase.strip

      pal_xml = @s1000d_product_attribute_definitions.empty? ? "" : "<productAttributeList>\n#{@s1000d_product_attribute_definitions.map { |pa| "  #{pa.gsub(/^/, '  ')}" }.join("\n")}\n</productAttributeList>"
      pct_dm_ref_xml = ""; 
      if dm_type == 'act'; 
        pct_dmc_str = doc_attrs['pct-dmc']; 
      if pct_dmc_str && !pct_dmc_str.strip.empty?; 
        if pct_dm_c = parse_dmc_string(pct_dmc_str); 
        pct_dm_ref_xml = "<productCrossRefTableRef><dmRef><dmRefIdent><dmCode modelIdentCode=\"#{pct_dm_c[:modelIdentCode]}\" systemDiffCode=\"#{pct_dm_c[:systemDiffCode]}\" systemCode=\"#{pct_dm_c[:systemCode]}\" subSystemCode=\"#{pct_dm_c[:subSystemCode]}\" subSubSystemCode=\"#{pct_dm_c[:subSubSystemCode]}\" assyCode=\"#{pct_dm_c[:assyCode]}\" disassyCode=\"#{pct_dm_c[:disassyCode]}\" disassyCodeVariant=\"#{pct_dm_c[:disassyCodeVariant]}\" infoCode=\"#{pct_dm_c[:infoCode]}\" infoCodeVariant=\"#{pct_dm_c[:infoCodeVariant]}\" itemLocationCode=\"#{pct_dm_c[:itemLocationCode]}\"/></dmRefIdent></dmRef></productCrossRefTableRef>"; 
    else warn "asciidoctor: WARNING: PCT DMC attribute '#{pct_dmc_str}' is invalid. Skipping PCT reference."; 
    end; 
  end; 
end
      internal_pct_xml = @s1000d_product_definitions.empty? ? "" : "<productCrossRefTable>\n#{@s1000d_product_definitions.map { |p| "  #{p.gsub(/^/, '  ')}" }.join("\n")}\n</productCrossRefTable>"
      act_outer_xml = ""; 
      if dm_type == 'act'; act_children_parts = [ (pal_xml.empty? ? nil : pal_xml), (internal_pct_xml.empty? ? nil : internal_pct_xml), (pct_dm_ref_xml.empty? ? nil : pct_dm_ref_xml) ].compact; act_children_indented = act_children_parts.map { |c| c.gsub(/^/, '  ') }.join("\n"); act_outer_xml = act_children_parts.empty? ? "" : "<applicCrossRefTable>\n#{act_children_indented}\n</applicCrossRefTable>"; 
      end
      rag_xml = @s1000d_applic_definitions.empty? ? "" : "<referencedApplicGroup>\n#{@s1000d_applic_definitions.map { |a| "  #{a.gsub(/^/, '  ')}" }.join("\n")}\n</referencedApplicGroup>"

      content_blocks_for_general = node.blocks.reject do |block|
        is_def_block = ['applicdef','productdef','attribute_def','global_applicability_definition','dmlref'].any? { |role_style| block.role == role_style || block.style == role_style }
        is_part_of_proc_structure = false
        if ['procedure','procedural','fault','faultisolation'].include?(dm_type); 
          if block.context == :section; is_part_of_proc_structure ||= (block.id == 'prelim_reqs' || block.title.downcase.include?('preliminary req')); is_part_of_proc_structure ||= (block.id == 'main_proc_steps' || block.title.downcase.include?('main procedure')); is_part_of_proc_structure ||= (block.id == 'closeout_reqs' || block.title.downcase.include?('closeout req')); is_part_of_proc_structure ||= (block.id == 'fault_iso_main' || block.title.downcase.include?('fault isolation procedure')); 
          end; 
          if !main_proc_section_exists(node) && block.context == :olist && ['procedure','procedural'].include?(dm_type); is_part_of_proc_structure = true; 
          end; 
        end; 
          is_def_block || is_part_of_proc_structure; 
        end
      general_content_processed = content_blocks_for_general.map(&:convert).compact.map(&:strip).reject(&:empty?).join("\n")

      main_dm_content = case dm_type
                        when 'procedure', 'procedural'
                          prelim = generate_preliminary_requirements_xml(node)
                          main_proc_steps_sequence = generate_main_procedure_steps_xml(node) 
                          closeout = generate_close_requirements_xml(node)
                          <<~PROCEDURE_XML.strip
                            <procedure>
                              #{prelim.gsub(/^/, '  ')}
                              <mainProcedure>
                                #{main_proc_steps_sequence.gsub(/^/, '  ')}
                              </mainProcedure>
                              #{closeout.gsub(/^/, '  ')}
                            </procedure>
                          PROCEDURE_XML
                        when 'fault', 'faultisolation'; 
                          fault_descr_content = general_content_processed; 
                          fault_descr_xml = fault_descr_content.empty? ? "<faultDescr><para>No fault description provided.</para></faultDescr>" : "<faultDescr>\n#{fault_descr_content.gsub(/^/,'  ')}\n</faultDescr>"; 
                          prelim = generate_preliminary_requirements_xml(node); 
                          fault_iso = generate_fault_isolation_main_procedure_xml(node); 
                          closeout = generate_close_requirements_xml(node); 
                          <<~FAULT_XML.strip
                            <fault>
                            #{fault_descr_xml.gsub(/^/,'  ')}
                            <faultIsolation>
                            <faultIsolationProcedure>
                            <isolationProcedure>
                            #{prelim.gsub(/^/,'    ')}#{fault_iso.gsub(/^/,'    ')}#{closeout.gsub(/^/,'    ')}
                            </isolationProcedure>
                            </faultIsolationProcedure>
                            </faultIsolation>
                            </fault>
                          FAULT_XML
                        when 'act'; 
                          desc_content = general_content_processed; desc_xml = desc_content.empty? ? "" : "<description>\n#{desc_content.gsub(/^/, '  ')}\n</description>\n"; 
                          desc_xml + act_outer_xml
                        when 'pct'; 
                          desc_content = general_content_processed; desc_xml = desc_content.empty? ? "" : "<description>\n#{desc_content.gsub(/^/, '  ')}\n</description>\n"; 
                          desc_xml + internal_pct_xml
                        when 'descript', 'description', 'descriptive'; 
                          content_indented = general_content_processed.gsub(/^/, '  '); 
                          "<description>\n#{content_indented}\n</description>"
                        else warn "asciidoctor: WARNING: Unknown DM type '#{dm_type}'. Treating as descriptive data module."; 
                          content_indented = general_content_processed.gsub(/^/, '  '); 
                          "<description>\n#{content_indented}\n</description>"; 
                        end
      final_content_parts = []; 
      final_content_parts << rag_xml.strip if !rag_xml.empty?; 
      final_content_parts << main_dm_content.strip unless main_dm_content.strip.empty?; final_content_xml = final_content_parts.empty? ? "<noContent/>" : final_content_parts.join("\n")
      ident_status_section = build_ident_and_status_section_xml(doc_attrs, dm_code_attrs, act_dm_ref_xml, global_applic_text, brex_dm_code_attrs, rfu_xml, node)
      doctype_decl = build_doctype_declaration(final_content_xml); 
      schema_file = get_schema_file(dm_type); schema_base = doc_attrs['s1000d-schema-base-path'] || "http://www.s1000d.org/S1000D_4-2/xml_schema_flat/"
      result = <<~XML; result.gsub(/\n\s*\n/, "\n").strip
      <?xml version="1.0" encoding="UTF-8"?>
      #{doctype_decl}
      <dmodule xmlns:dc="http://www.purl.org/dc/elements/1.1/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="#{schema_base}#{schema_file}">
      #{ident_status_section.gsub(/^/, '  ')}
        <content>
      #{final_content_xml.gsub(/^/, '    ')}
        </content>
      </dmodule>
      XML
    end

    def main_proc_section_exists(document_node)
      document_node.blocks.any? { |b| b.context == :section && (b.id == 'main_proc_steps' || b.title.downcase.include?('main procedure')) }
    end

    def convert_paragraph(node)
      return "" if ['applicdef', 'productdef'].include?(node.role)
      para_attrs = common_attributes(node.id) + applic_ref_attribute(node)
      processed_content = node.content
      return "<para#{para_attrs}/>" if processed_content.nil? || processed_content.strip.empty?
      %(<para#{para_attrs}>#{processed_content}</para>)
    end
    
    def convert_open(node)
      if node.role == 'applicdef'; process_as_applic_definition(node); return ""
      elsif node.role == 'productdef'; process_as_product_definition(node); return ""
      elsif node.role == 'attribute_def'; process_as_product_attribute_definition(node); return "";
      elsif node.role == 'dmlref' || node.style == 'dmlref'
        return global_refdmlref(node)
      elsif node.role == 'global_applicability_definition' || node.style == 'global_applicability_definition'
        return ""; 
      end

      content = node.content.to_s.strip
      open_attrs = common_attributes(node.id) + applic_ref_attribute(node)
      
      if node.style == 'example' || node.role == 'example'
        title_el = node.title? ? "<title>#{esc_text(node.title)}</title>" : ""
        return %(<levelledPara#{open_attrs} class="example">#{title_el}#{content}</levelledPara>)
      end

      if node.title?
        title_text = esc_text(node.title)
        content_xml = content.empty? ? "<para/>" : content 
        return %(<subTitle>#{title_text}</subTitle>#{content_xml})
      end

      return "" if content.empty? && open_attrs.strip.empty?
      %(<para#{open_attrs}>#{content}</para>)
    end

    def global_refdmlref(node)
      model_ident_code = node.attr('modelIdentCode')
      sender_ident     = node.attr('senderIdent')
      dml_type         = node.attr('dmlType')
      year             = node.attr('yearOfDataIssue')
      seq_number       = node.attr('seqNumber')

      required_attrs = {
        'modelIdentCode'  => model_ident_code,
        'senderIdent'     => sender_ident,
        'dmlType'         => dml_type,
        'yearOfDataIssue' => year,
        'seqNumber'       => seq_number
      }

      missing_attrs = required_attrs.select { |key, value| value.nil? || value.to_s.strip.empty? }.keys
      unless missing_attrs.empty?
        warn "asciidoctor: WARNING (global_refdmlref): A 'dmlref' block (ID: #{node.id || 'N/A'}) is missing required attributes: #{missing_attrs.join(', ')}. Skipping."
        return ""
      end

      <<~XML.strip
        <dmlRef#{common_attributes(node.id)}>
          <dmlRefIdent>
            <dmlCode modelIdentCode="#{esc_text(model_ident_code)}" senderIdent="#{esc_text(sender_ident)}" dmlType="#{esc_text(dml_type)}" yearOfDataIssue="#{esc_text(year)}" seqNumber="#{esc_text(seq_number)}"/>
          </dmlRefIdent>
        </dmlRef>
      XML
    end
    
    def convert_ulist(node)
      list_attrs = common_attributes(node.id) + applic_ref_attribute(node)
      item_outputs = node.items.map do |item|
        li_attrs = common_attributes(item.id) + applic_ref_attribute(item)
        text_content = item.text? ? item.apply_subs(item.text) : ''
        blocks_content = item.blocks? ? item.blocks.map(&:convert).join("\n") : ''
        final_inner_content = ""
        if !text_content.strip.empty?
          final_inner_content << "<para>#{text_content}</para>"
        end
        final_inner_content << blocks_content
        if final_inner_content.strip.empty?
          final_inner_content = "<para/>"
        end
        "<listItem#{li_attrs}>#{final_inner_content}</listItem>"
      end.join("\n")
      "<para><randomList#{list_attrs}>#{item_outputs}</randomList></para>"
    end

    def convert_olist(node)
      list_attrs = common_attributes(node.id) + applic_ref_attribute(node)
      item_outputs = node.items.map do |item|
        li_attrs = common_attributes(item.id) + applic_ref_attribute(item)
        text_content = item.text? ? item.apply_subs(item.text) : ''
        blocks_content = item.blocks? ? item.blocks.map(&:convert).join("\n") : ''
        final_inner_content = ""
        if !text_content.strip.empty?
          final_inner_content << "<para>#{text_content}</para>"
        end
        final_inner_content << blocks_content
        if final_inner_content.strip.empty?
          final_inner_content = "<para/>"
        end
        "<listItem#{li_attrs}>#{final_inner_content}</listItem>"
      end.join("\n")
      "<para><sequentialList#{list_attrs}>#{item_outputs}</sequentialList></para>"
    end

    def convert_dlist(node)
      dl_attrs = common_attributes(node.id) + applic_ref_attribute(node)
      items = node.items.map do |terms, dd|
        term_xml = terms.map { |dt| esc_text(dt.text) }.join("; ")
        dd_content = if dd; if dd.blocks?; dd.content; elsif dd.text? && !dd.text.strip.empty?; "<para#{applic_ref_attribute(dd)}>#{esc_text(dd.text)}</para>"; else "<para#{applic_ref_attribute(dd)}/>"; end; else "<para/>"; end
        "<definitionListItem><listItemTerm>#{term_xml}</listItemTerm><listItemDefinition>#{dd_content}</listItemDefinition></definitionListItem>"
      end.join("\n")
      return "" if items.empty?
      "<definitionList#{dl_attrs}>#{items}</definitionList>"
    end

    def convert_literal(node)
      if node.role == 'global_applicability_definition' || node.style == 'global_applicability_definition'
        return ""; 
      end
      para_attrs = common_attributes(node.id) + applic_ref_attribute(node)
      return "<para#{para_attrs}/>" if node.content.to_s.strip.empty? && !para_attrs.empty?
      return "" if node.content.to_s.strip.empty? && para_attrs.empty?
      "<para#{para_attrs}><verbatimText>#{esc_text(node.content)}</verbatimText></para>"
    end

    def convert_listing(node)
      attrs = common_attributes(node.id) + applic_ref_attribute(node); content = esc_text(node.content)
      if node.title?; "<figure#{attrs}><title>#{esc_text(node.title)}</title><graphic><verbatimText>#{content}</verbatimText></graphic></figure>";
      else return "<para#{attrs}/>" if content.empty? && !attrs.empty?; return "" if content.empty? && attrs.empty?; "<para#{attrs}><verbatimText>#{content}</verbatimText></para>"; 
      end
    end

    def convert_section(node)
      if @is_in_main_procedure
        step_attrs = common_attributes(node.id) + applic_ref_attribute(node)
        
        # MODIFICATION START: Conditionally suppress title for deeply nested procedural steps (e.g., level 4 or greater)
        # This achieves the user's request to have the nested <proceduralStep> content immediately follow the tag.
        if node.level >= 5 
            title_xml = ""
        else
            title_xml = node.title? ? "<title>#{esc_text(node.title)}</title>" : ""
        end
        # MODIFICATION END
        
        content_xml = node.content
        "<proceduralStep#{step_attrs}>#{title_xml}#{content_xml}</proceduralStep>"
      else
        para_attrs = common_attributes(node.id) + applic_ref_attribute(node)
        title_xml = node.title? ? "<title>#{esc_text(node.title)}</title>" : ""
        content_xml = node.content.to_s.strip.empty? ? "" : node.content
        "<levelledPara#{para_attrs}>#{title_xml}#{content_xml}</levelledPara>"
        \
        
      end
    end

    def convert_inline_anchor(node)
      case node.type
      when :xref
        target = (node.attributes['refid'] || node.target).sub(/^#/, '')
        tn = node.document.catalog[:ids][target]
        ta = determine_internal_ref_target_type(tn, target)
        dt = node.text || target
        "<internalRef internalRefId=\"#{esc_text(target)}\"#{ta}>#{esc_text(dt)}</internalRef>"
      when :link
        target = node.target
        potential_dmc = target.gsub(/\.html$/i, '')
        parsed_dmc = parse_dmc_string(potential_dmc)
        if parsed_dmc
          dm_code_attrs_xml = parsed_dmc.map { |k, v| %(#{k}="#{esc_text(v)}") }.join(' ')
          <<~XML.strip
          <dmRef>
            <dmRefIdent>
              <dmCode #{dm_code_attrs_xml}/>
            </dmRefIdent>
          </dmRef>
          XML
        else
          dt = node.text || node.target
          "<externalPubRef xlink:href=\"#{esc_text(node.target)}\"><externalPubRefIdent><externalPubTitle>#{esc_text(dt)}</externalPubTitle></externalPubRefIdent></externalPubRef>"
        end
      when :ref, :bibref
        node.text ? esc_text(node.text) : ""
      else
        warn "asciidoctor: WARNING (S1000D converter): Unhandled inline anchor type: #{node.type}. Text: '#{node.text}'"
        esc_text(node.text || node.target)
      end
    end

    def convert_table(node)
      previous_table_state = @is_in_table_context
      @is_in_table_context = true
      attrs = common_attributes(node.id) + applic_ref_attribute(node)
      pgwide_attr = (node.option?('pgwide') || node.attr?('width', '100%')) ? ' pgwide="1"' : ' pgwide="0"'
      s1k_frame = case node.attr('frame', 'all')
                  when 'topbot'; 'topbot'
                  when 'sides';  'sides'
                  when 'none';   'none'
                  else 'all'
                  end
      frame_attr = %( frame="#{s1k_frame}")
      grid_val = node.attr('grid', 'all')
      rowsep_attr = (grid_val == 'all' || grid_val == 'rows') ? ' rowsep="1"' : ' rowsep="0"'
      colsep_attr = (grid_val == 'all' || grid_val == 'cols') ? ' colsep="1"' : ' colsep="0"'
      orient_attr = node.attr?('orientation', 'landscape', 'table-orient') ? ' orient="land"' : ' orient="port"'

      result = "<table#{attrs}#{frame_attr}#{pgwide_attr}#{rowsep_attr}#{colsep_attr}#{orient_attr}>"
      result << "<title>#{esc_text(node.title)}</title>" if node.title?
      result << "<tgroup cols=\"#{node.attr 'colcount'}\">"

      node.columns.each do |col|
        col_num = col.attr('colnumber')
        colname_attr = %( colname="c#{col_num}")
        width_val = col.attr('width')
        colwidth_attr = width_val ? %( colwidth="#{width_val}*") : ""
        align_val = col.attr('halign')
        align_attr = align_val ? %( align="#{align_val}") : ""
        result << "<colspec#{colname_attr}#{colwidth_attr}#{align_attr}/>"
      end

      [:head, :foot, :body].each do |tsec_name|
        rows_collection = node.rows.send(tsec_name)
        next if rows_collection.empty?
        result << "<t#{tsec_name}>"
        rows_collection.each do |row|
          result << "<row>"
          row.each do |cell|
            entry_attrs = ""
            halign_val = cell.attr('halign')
            entry_attrs << %( align="#{halign_val}") if halign_val
            valign_val = cell.attr('valign')
            entry_attrs << %( valign="#{valign_val}") if valign_val
            col_num_start = cell.column.attr('colnumber')
            if cell.colspan.to_i > 1
              entry_attrs << %( namest="c#{col_num_start}" nameend="c#{col_num_start + cell.colspan - 1}")
            else
              entry_attrs << %( nameend="c#{col_num_start}" namest="c#{col_num_start}")
            end
            entry_attrs << %( morerows="#{cell.rowspan - 1}") if cell.rowspan.to_i > 1
            entry_attrs << common_attributes(cell.id) << applic_ref_attribute(cell)

            cell_body = case cell.style
                       when :asciidoc
                         cell.content
                       when :literal
                         "<para><verbatimText>#{esc_text(cell.text)}</verbatimText></para>"
                       else
                         cell.text.to_s.strip.empty? ? "<para/>" : "<para>#{esc_text(cell.text)}</para>"
                       end
            result << "<entry#{entry_attrs}>#{cell_body}</entry>"
          end
          result << "</row>"
        end
        result << "</t#{tsec_name}>"
      end
      result << "</tgroup></table>"
      @is_in_table_context = previous_table_state 
      result
    end

    alias convert_embedded content_only

    def convert_image(node)
      icn_val = node.attr('icn')

      unless icn_val && !icn_val.strip.empty?
        img_tgt_bn = File.basename(node.attr('target', 'unknown.png'), '.*')
        alt = node.attr('alt')
        if alt && alt.match?(/^(?:ICN|FIG)-/i)
          icn_val = alt.upcase
        elsif img_tgt_bn.match?(/^(?:ICN|FIG)-/i)
          icn_val = img_tgt_bn.upcase
        else
          fb = alt || img_tgt_bn
          icn_val = "FIG-#{fb.gsub(/[^A-Za-z0-9\-_\.]/,'_').gsub(/_+/,'_').upcase}"
          warn "asciidoctor: INFO: Could not determine ICN from 'icn' attribute, alt text, or filename for image target '#{node.attr('target') || 'N/A'}' (alt: '#{node.attr('alt') || 'N/A'}'). Generated fallback ICN: #{icn_val}."
        end
      end

      if @is_in_table_context 
        "<para><symbol infoEntityIdent=\"#{esc_text(icn_val.strip)}\"/></para>"
      else
        attrs = common_attributes(node.id) + applic_ref_attribute(node) 
        title_xml = node.title ? "<title>#{esc_text(node.title)}</title>" : "" 
        "<figure#{attrs}>#{title_xml}<graphic infoEntityIdent=\"#{esc_text(icn_val.strip)}\"/></figure>"
      end
    end

    def convert_inline_quoted(node)
      open_tag, close_tag = QUOTE_TAGS[node.type];text_content = node.text ? esc_text(node.text) : "";"#{open_tag}#{text_content}#{close_tag}"
    end

    def convert_admonition(node)
      attrs=common_attributes(node.id)+applic_ref_attribute(node);type=node.attr('name').upcase;processed_content_from_node=node.content.to_s.strip;final_inner_xml=""
      if !node.blocks?;
        if processed_content_from_node.empty?;
          case type;when 'WARNING','CAUTION';final_inner_xml="<warningAndCautionPara/>";else final_inner_xml="<notePara/>";end;else text_to_wrap=esc_text(processed_content_from_node);case type;when 'WARNING','CAUTION';final_inner_xml="<warningAndCautionPara>#{text_to_wrap}</warningAndCautionPara>";else final_inner_xml="<notePara>#{text_to_wrap}</notePara>";end;end;
      elsif node.blocks?;if processed_content_from_node.empty?;case type;when 'WARNING','CAUTION';final_inner_xml="<warningAndCautionPara/>";else final_inner_xml="<notePara/>";end;else final_inner_xml=processed_content_from_node;end;
      else case type;when 'WARNING','CAUTION';final_inner_xml="<warningAndCautionPara/>";else final_inner_xml="<notePara/>";end;end
      case type;when 'WARNING';"<warning#{attrs}>#{final_inner_xml}</warning>";when 'CAUTION';"<caution#{attrs}>#{final_inner_xml}</caution>";when 'NOTE';"<note#{attrs}>#{final_inner_xml}</note>";when 'TIP','IMPORTANT';warn "asciidoctor: WARNING: Admonition type '#{type}' is not a standard S1000D type (Note, Caution, Warning). Converting as <note>.";"<note#{attrs}>#{final_inner_xml}</note>";
      else warn "asciidoctor: WARNING: Unknown admonition type '#{type}'. Converting as generic <note>.";fallback_text_content=node.content.to_s.strip;fallback_para=if fallback_text_content.empty?;"<notePara/>";elsif !node.blocks?;"<notePara>#{esc_text(fallback_text_content)}</notePara>";else fallback_text_content;end;"<note#{attrs}>#{fallback_para}</note>";end
    end

    def convert_thematic_break(node)
      ''
    end

    def convert_inline_image(node)
      target_path = node.target
      icn_val = node.attr('icn')
      role = node.attr('role')
      
      # Determine the ICN value (reusing your existing logic)
      unless icn_val && !icn_val.strip.empty?
        alt_text = node.attr('alt')
        base_filename = File.basename(target_path, '.*')
        if alt_text && alt_text.match?(/^(?:ICN|FIG)-/i)
          icn_val = alt_text.upcase
        elsif base_filename.match?(/^(?:ICN|FIG)-/i)
          icn_val = base_filename.upcase
        else
          fallback_base = alt_text || base_filename
          # Logic specific to your requirement: if it's an icon, prefix it correctly if needed
          prefix = (target_path.include?('icons/') || role == 'symbol') ? "ICN" : "INL-FIG"
          icn_val = "#{prefix}-#{fallback_base.gsub(/[^A-Za-z0-9\-_\.]/, '_').gsub(/_+/, '_').upcase}"
        end
      end

      # Logic for S1000D <symbol>
      # We trigger this if the path contains 'icons/' or the user explicitly sets [role=symbol]
      if target_path.include?('icons/') || role == 'symbol'
        # reproductionScale: use the width attribute if provided (e.g., the '16' in [Warning,16,16])
        # In S1000D, scale is often expressed as an integer. If no width, default to 60.
        scale = node.attr('width') || "60"
        
        return %(<symbol infoEntityIdent="#{esc_text(icn_val.strip)}" reproductionScale="#{esc_text(scale)}" />)
      end

      # Fallback for standard inline graphics
      %(<graphic infoEntityIdent="#{esc_text(icn_val.strip)}"/>)
    end

    def convert_fallback(node)
      warn %(asciidoctor: WARNING: S1000D converter encountered unhandled node type: '#{node.node_name}' (ID: '#{node.id}', Context: '#{node.context}'). This content will be SKIPPED.); ""
    end
    
  end
end