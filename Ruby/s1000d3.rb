# Devloped By Prathamesh Naik
# This code is a Ruby script that defines a custom Asciidoctor converter for S1000D XML documents.
# This is Licenced under the Apache License, Version 2.0

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
    end

    def common_attributes(id)
      id ? %( id="#{id}") : ''
    end

    def applic_ref_attribute(node)
      node.attr?('applic_ref') ? %( applicRefId="#{esc_text(node.attr('applic_ref'))}") : ''
    end

    def esc_text(text)
      return '' if text.nil?
      text.to_s.gsub('&', '&').gsub('<', '<').gsub('>', '>').gsub('"', '"')
    end

    def esc_content(text_or_content)
      return '' if text_or_content.nil?
      return text_or_content unless text_or_content.is_a?(String)
      text_or_content.to_s
    end

    def parse_dmc_string(dmc_string)
      return nil unless dmc_string && dmc_string.is_a?(String) && !dmc_string.strip.empty?
      cleaned_dmc_string = dmc_string.split('//').first.strip
      regex = /^(?:DMC-)?([A-Z0-9]{2,17})-([A-Z0-9]{1})-([A-Z0-9]{2,4})-([A-Z0-9]{1,2})-([A-Z0-9]{1,2})-([A-Z0-9]{2,4})-([A-Z0-9]{2})-([A-Z0-9]{1,4})-([A-Z0-9]{3})-([A-Z0-9]{1})-([A-Z0-9]{1})$/i
      match = regex.match(cleaned_dmc_string)
      if match
          return { modelIdentCode: match[1].upcase, systemDiffCode: match[2].upcase, systemCode: match[3].upcase, subSystemCode: match[4].upcase, subSubSystemCode: match[5].upcase, assyCode: match[6].upcase, disassyCode: match[7].upcase, disassyCodeVariant: match[8].upcase, infoCode: match[9].upcase, infoCodeVariant: match[10].upcase, itemLocationCode: match[11].upcase }
      else
          warn "asciidoctor: WARNING (parse_dmc_string): Regex DID NOT MATCH for 11-part DMC input '#{cleaned_dmc_string}'."
          return nil
      end
    end

    def parse_pmc_string(pmc_string)
      return nil unless pmc_string && pmc_string.is_a?(String) && !pmc_string.strip.empty?
      cleaned_pmc_string = pmc_string.split('//').first.strip
      regex = /^(?:PMC-)?([A-Z0-9]{2,17})-([A-Z0-9]{5})-([A-Z0-9]{5})-([A-Z0-9]{2})-([a-z]{2})-([A-Z]{2})-([0-9]{3})-([0-9A-Z]{2})$/i
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

    def convert_text_with_inline_xrefs(text, context_node)
      return "<para/>" if text.nil? || text.strip.empty?
      parts = []
      last_idx = 0
      text.scan(/<<([^>]+?)(?:,([^>]*?))?>>/) do |match_arr|
        match_data = Regexp.last_match
        pre_text = text[last_idx...match_data.begin(0)]
        parts << esc_text(pre_text) unless pre_text.empty?
        target_id = match_arr[0].strip
        display_text_xref = (match_arr[1].nil? || match_arr[1].strip.empty?) ? target_id : match_arr[1].strip
        target_node_obj = context_node.document.catalog[:ids][target_id]
        target_type_attr = determine_internal_ref_target_type(target_node_obj, target_id)
        parts << "<internalRef internalRefId=\"#{esc_text(target_id)}\"#{target_type_attr}>#{esc_text(display_text_xref)}</internalRef>"
        last_idx = match_data.end(0)
      end
      remaining_text = text[last_idx..-1]
      parts << esc_text(remaining_text) if remaining_text && !remaining_text.strip.empty?
      "#{parts.join}"
    end

    def generate_req_cond_group_xml(section_node, for_closeout = false)
      return "<reqCondGroup><noConds/></reqCondGroup>" unless section_node
      conditions_xml_elements = []
      has_actual_conditions = false
      section_node.blocks.each_with_index do |block, idx|
        case block.context
        when :paragraph
          is_likely_xref_target_only = block.id && section_node.document.references[:ids].key?(block.id) && block.source.lines.count <= 2 && block.source.downcase.include?(block.id.downcase)
          unless is_likely_xref_target_only
            warn "asciidoctor: WARNING: Paragraph found directly in '#{section_node.title}' section: '#{block.source.lines.first.strip[0,70]}...'. This paragraph will be SKIPPED."
          end
        when :ulist, :olist
          has_actual_conditions = true
          block.items.each do |item|
            item_id_val = item.id
            item_applic_ref_val = item.attr('applic_ref')
            item_s1000d_id_attr_str = common_attributes(item_id_val)
            item_s1000d_applic_attr_str = item_applic_ref_val ? %( applicRefId="#{esc_text(item_applic_ref_val)}") : ''
            pm_ref_attr = item.attr('pmref')
            dm_ref_attr = item.attr('dmref')
            pm_to_parse = nil
            dm_to_parse = nil
            raw_item_text_content = item.text.to_s
            text_for_condition = raw_item_text_content.dup.strip

            if pm_ref_attr && !pm_ref_attr.strip.empty?
              pm_to_parse = pm_ref_attr.strip
              text_for_condition.gsub!(/\[pmref=#{Regexp.escape(pm_to_parse)}\s*\]/i, '').strip!
              text_for_condition.gsub!(/\bpmcref:\s*#{Regexp.escape(pm_to_parse)}\b/i, '').strip!
            elsif dm_ref_attr && !dm_ref_attr.strip.empty?
              dm_to_parse = dm_ref_attr.strip
              text_for_condition.gsub!(/\[dmref=#{Regexp.escape(dm_to_parse)}\s*\]/i, '').strip!
              text_for_condition.gsub!(/\bdmcref:\s*#{Regexp.escape(dm_to_parse)}\b/i, '').strip!
            else
              pm_match = text_for_condition.match(/(?:pmcref:\s*)?((?:PMC-)?(?:[A-Z0-9]{2,17})-(?:[A-Z0-9]{5})-(?:[A-Z0-9]{5})-(?:[A-Z0-9]{2})-(?:[a-z]{2})-(?:[A-Z]{2})-(?:[0-9]{3})-(?:[0-9A-Z]{2}))/i)
              if pm_match && pm_match[1]
                pm_to_parse = pm_match[1]
                text_for_condition.gsub!(pm_match[0], '').strip!
              else
                dm_match = text_for_condition.match(/(?:dmcref:\s*)?((?:DMC-)?(?:[A-Z0-9]{2,17})(?:-[A-Z0-9]{1,4}){9}-[A-Z0-9]{1})/i)
                if dm_match && dm_match[1]
                  dm_to_parse = dm_match[1]
                  text_for_condition.gsub!(dm_match[0], '').strip!
                end
              end
            end
            if item_id_val.nil? && text_for_condition.match?(/\A\s*\[id=([^,\]\s]+)/i); text_for_condition.sub!(/\A\s*\[id=[^\]]+\]\s*/i, '').strip!; end
            if item_applic_ref_val.nil?; if text_for_condition.match?(/\A\s*\[(?:[^\]]*?,?\s*)?applic_ref=([^,\]\s]+)/i); text_for_condition.sub!(/\A\s*\[[^\]]+\]\s*/i, '').strip!; end; end
            if text_for_condition.start_with?('[') && text_for_condition.include?(']'); text_for_condition.sub!(/\A\s*\[[^\]]+\]\s*/, '').strip!; end

            req_cond_inner_xml = if item.blocks?
                                   item.content # Calls standard convert_olist for <sequentialList>
                                 else
                                   convert_text_with_inline_xrefs(text_for_condition.strip, item)
                                 end

            if pm_to_parse && !pm_to_parse.strip.empty?
              parsed_pm_ref_code = parse_pmc_string(pm_to_parse)
              if parsed_pm_ref_code; pm_ref_xml_part = <<~XML.strip; conditions_xml_elements << "<reqCondPm#{item_s1000d_id_attr_str}#{item_s1000d_applic_attr_str}><reqCond>#{req_cond_inner_xml}</reqCond>#{pm_ref_xml_part}</reqCondPm>"
                  <pmRef><pmRefIdent><pmCode modelIdentCode="#{esc_text(parsed_pm_ref_code[:modelIdentCode])}" pmIssuer="#{esc_text(parsed_pm_ref_code[:pmIssuer])}" pmNumber="#{esc_text(parsed_pm_ref_code[:pmNumber])}" pmVolume="#{esc_text(parsed_pm_ref_code[:pmVolume])}"/><language languageIsoCode="#{esc_text(parsed_pm_ref_code[:languageIsoCode])}" countryIsoCode="#{esc_text(parsed_pm_ref_code[:countryIsoCode])}"/></pmRefIdent></pmRef>
                XML
              else warn "..."; conditions_xml_elements << "<reqCondNoRef#{item_s1000d_id_attr_str}#{item_s1000d_applic_attr_str}><reqCond>#{req_cond_inner_xml}</reqCond></reqCondNoRef>"; end
            elsif dm_to_parse && !dm_to_parse.strip.empty?
              parsed_dm_ref_code = parse_dmc_string(dm_to_parse)
              if parsed_dm_ref_code; dm_code_attrs_xml=parsed_dm_ref_code.map{|k,v|%(#{k}="#{esc_text(v)}")}.join(' ');dm_ref_xml_part="<dmRef><dmRefIdent><dmCode #{dm_code_attrs_xml}/></dmRefIdent></dmRef>";conditions_xml_elements << "<reqCondDm#{item_s1000d_id_attr_str}#{item_s1000d_applic_attr_str}><reqCond>#{req_cond_inner_xml}</reqCond>#{dm_ref_xml_part}</reqCondDm>";
              else warn "..."; conditions_xml_elements << "<reqCondNoRef#{item_s1000d_id_attr_str}#{item_s1000d_applic_attr_str}><reqCond>#{req_cond_inner_xml}</reqCond></reqCondNoRef>"; end
            else
              conditions_xml_elements << "<reqCondNoRef#{item_s1000d_id_attr_str}#{item_s1000d_applic_attr_str}><reqCond>#{req_cond_inner_xml}</reqCond></reqCondNoRef>"
            end
          end
        when :admonition
          has_actual_conditions = true
          if block.attr('name')&.casecmp('note')&.zero?; conditions_xml_elements << block.convert;
          else warn "..."; conditions_xml_elements << block.convert; end
        else
          unless block.context == :thematic_break; warn "..."; end
        end
      end
      if !has_actual_conditions || conditions_xml_elements.empty?; return "<reqCondGroup><noConds/></reqCondGroup>";
      else return "<reqCondGroup>\n#{conditions_xml_elements.join("\n")}\n</reqCondGroup>"; end
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
                else if !raw_item_text.empty?; warn "..."; 
                end; 
                next; 
              end
              else if !raw_item_text.empty?; warn "..."; 
              end; next; 
            end
            end
            next if dmc_to_parse.nil? || dmc_to_parse.empty?
            category = item.attr('category', 'ti01'); parsed_dmc_hash = parse_dmc_string(dmc_to_parse)
            if parsed_dmc_hash; dm_code_attrs_xml = parsed_dmc_hash.map { |k, v| %(#{k}="#{esc_text(v)}") }.join(' '); tech_info_entries << <<~XML.strip; else warn "..."; end
              <reqTechInfo#{common_attributes item.id}#{applic_ref_attribute item} reqTechInfoCategory="#{esc_text(category)}"><dmRef><dmRefIdent><dmCode #{dm_code_attrs_xml}/></dmRefIdent></dmRef></reqTechInfo>
            XML
          end
        elsif block.context == :paragraph
          if block.source.strip.downcase.match?(/(no|none)\s+(required\s+)?tech(nical)?\s+info(rmation)?/i); found_explicit_no_info = true;
          elsif !block.source.strip.empty?; warn "..."; end
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
        nam       = (cols_map[:nm] && row_cells[cols_map[:nm]])  ? esc_text(row_cells[cols_map[:nm]].text.strip)  : ""
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
      content_map = { req_conds: "<reqCondGroup><noConds/></reqCondGroup>", req_persons: "", req_tech_info: "<reqTechInfoGroup><noReqTechInfo/></reqTechInfoGroup>", req_support_equip: "<reqSupportEquips><noSupportEquips/></reqSupportEquips>", req_supplies: "<reqSupplies><noSupplies/></reqSupplies>", req_spares: "<reqSpares><noSpares/></reqSpares>", req_safety: "<reqSafety><noSafety/></reqSafety>" }
      if prelim_section
        prelim_section.blocks.each do |sub_block|
          next unless sub_block.context == :section; title_key = sub_block.id&.downcase || sub_block.title.downcase
          if title_key.include?('req_conds')||title_key.include?('required condition'); content_map[:req_conds]=generate_req_cond_group_xml(sub_block);
          elsif title_key.include?('req_persons')||title_key.include?('required person'); content_map[:req_persons]=generate_req_persons_xml(sub_block);
          elsif title_key.include?('req_tech_info')||title_key.include?('required technical information'); content_map[:req_tech_info]=generate_req_tech_info_group_xml(sub_block);
          elsif title_key.include?('req_equip')||title_key.include?('support equipment'); content_map[:req_support_equip]=generate_table_based_req_list(sub_block, "reqSupportEquips","supportEquipDescrGroup","supportEquipDescr","<noSupportEquips/>",{name:0,mfr:5,pn:2,qty:3,rmk:7,iem:1,nm:4});
          elsif title_key.include?('req_consum')||title_key.include?('supply'); content_map[:req_supplies]=generate_table_based_req_list(sub_block, "reqSupplies","supplyDescrGroup","supplyDescr","<noSupplies/>",{name:0,mfr:1,pn:2,qty:3,uom:4,rmk:5,nm:0});
          elsif title_key.include?('req_spares')||title_key.include?('spare'); content_map[:req_spares]=generate_table_based_req_list(sub_block, "reqSpares","spareDescrGroup","spareDescr","<noSpares/>",{name:0,mfr:5,pn:2,qty:3,rmk:6,iem:1,nm:4});
          elsif title_key.include?('req_safety')||title_key.include?('safety condition'); content_map[:req_safety]=generate_req_safety_xml(sub_block); end
        end
      end
      prelim_parts = [content_map[:req_conds],(content_map[:req_persons] unless content_map[:req_persons].empty?),content_map[:req_tech_info],content_map[:req_support_equip],content_map[:req_supplies],content_map[:req_spares],content_map[:req_safety]].compact.join("\n")
      prelim_attrs = prelim_section ? common_attributes(prelim_section.id)+applic_ref_attribute(prelim_section) : ""
      indented_prelim_parts = prelim_parts.empty? ? "" : "\n#{prelim_parts.gsub(/^/, '  ')}\n"
      "<preliminaryRqmts#{prelim_attrs}>#{indented_prelim_parts}</preliminaryRqmts>"
    end

    # Method to convert an array of Asciidoctor::ListItem into a string of <proceduralStep> XML
        # Method to convert an array of Asciidoctor::ListItem into a string of <proceduralStep> XML
    def convert_list_items_to_procedural_steps(list_items_array, parent_list_node = nil)
      return "" if list_items_array.nil? || list_items_array.empty?
      xml_parts = []
      parent_list_node ||= list_items_array.first&.parent if list_items_array.first

      list_items_array.each_with_index do |li, idx|
        step_id = li.id
        unless step_id
          step_proc = SecureRandom.uuid
          parent_id_prefix = parent_list_node&.id || "uuid_#{step_proc}"
          step_id = "#{parent_id_prefix}"
        end
        step_attrs = common_attributes(step_id) + applic_ref_attribute(li)
        current_step_xml = "<proceduralStep#{step_attrs}>"

        # --- THIS IS THE CRITICAL FIX ---
        # Get the raw text of the list item
        title_text = li.text
        if title_text && !title_text.strip.empty?
          # Use apply_subs to process inline macros (like dmlref::[]), formatting, and xrefs.
          # The result of apply_subs is already processed content, so DO NOT escape it with esc_text.
          processed_title = li.apply_subs(title_text.strip)
          current_step_xml << "<title>#{processed_title}</title>"
        end
        # --- END OF FIX ---

        if li.blocks?
          li.blocks.each do |block_in_li|
            if block_in_li.context == :olist # CRITICAL: Ensures nested olist items also become steps
              current_step_xml << convert_list_items_to_procedural_steps(block_in_li.items, block_in_li)
            else # For ulist, para, image, or open block containing an olist (which would then use standard convert_olist)
              current_step_xml << block_in_li.convert
            end
          end
        end
        current_step_xml << "</proceduralStep>"
        xml_parts << current_step_xml
      end
      xml_parts.join("\n")
    end

    # THIS IS THE STANDARD olist converter, for generating <sequentialList>
    def convert_olist(node)
      item_outputs = []
      node.items.each_with_index do |item, idx|
        li_attrs = common_attributes(item.id) + applic_ref_attribute(item)
        # item.content handles text and nested blocks correctly for list items
        inner_content = if item.blocks?
                         item.content
                       elsif item.text && !item.text.strip.empty?
                         "<para>#{esc_text(item.text.strip)}</para>"
                       else
                         "<para/>" # S1000D listItems usually require some content
                       end
        item_outputs << "<listItem#{li_attrs}>#{inner_content}</listItem>"
      end
      return "" if item_outputs.empty?
      list_attrs_for_seq_list = common_attributes(node.id) + applic_ref_attribute(node)
      list_item_xml = item_outputs.join("\n")
      # Common S1000D practice is to wrap lists in <para> when they are flow content
      "<para><sequentialList#{list_attrs_for_seq_list}>#{list_item_xml}</sequentialList></para>"
    end

    # This is the main step generator. It calls convert_list_items_to_procedural_steps for olist.
    def generate_main_procedure_steps_xml(document_node)
      main_proc_section = document_node.blocks.find { |b| b.context == :section && (b.id == 'main_proc_steps' || b.title.downcase.include?('main procedure')) }
      blocks_to_consider = if main_proc_section
                             main_proc_section.blocks
                           else
                             document_node.blocks.reject do |b|
                               is_prelim = b.context == :section && (b.id == 'prelim_reqs' || b.title.downcase.include?('preliminary req'))
                               is_closeout = b.context == :section && (b.id == 'closeout_reqs' || b.title.downcase.include?('closeout req'))
                               is_definition_block = ['applicdef', 'productdef', 'attribute_def', 'global_applicability_definition'].include?(b.role) || ['applicdef', 'productdef', 'attribute_def', 'global_applicability_definition'].include?(b.style)
                               is_prelim || is_closeout || is_definition_block
                             end
                           end
      procedural_steps_xml_parts = []
      blocks_to_consider.each_with_index do |block, index|
        if block.context == :olist
          # This olist is directly considered for procedural steps
          procedural_steps_xml_parts << convert_list_items_to_procedural_steps(block.items, block)
        elsif block.context == :section && block.role != 'attribute_def'
            step_id = block.id || "procstep-section-#{index + 1}"
            step_attrs = common_attributes(step_id) + applic_ref_attribute(block)
            title_xml = block.title? ? "<title>#{esc_text(block.title)}</title>" : ""
            # block.content will trigger standard convert_olist if an olist is nested here
            content_xml = block.content
            procedural_steps_xml_parts << "<proceduralStep#{step_attrs}>#{title_xml}#{content_xml}</proceduralStep>"
        elsif [:image, :listing, :literal, :admonition, :table, :open, :paragraph].include?(block.context)
          is_def_block = (block.role && ['applicdef', 'productdef', 'attribute_def'].include?(block.role)) || (block.style && ['applicdef', 'productdef', 'attribute_def'].include?(block.style))
          next if is_def_block
          is_empty_para_without_id = block.context == :paragraph && !block.id && block.source.strip.empty?
          unless is_empty_para_without_id
            step_id = block.id || "procstep-block-#{index + 1}"
            step_attrs = common_attributes(step_id) + applic_ref_attribute(block)
            converted_content = block.convert # Standard conversion
            next if converted_content.to_s.strip.empty?
            title_outer_xml = ""
            if block.title?
                is_title_handled_internally = case block.context; when :image, :listing, :table; true; else converted_content.strip.match?(/\A<(?:figure|levelledPara|note|warning|caution)(?:[^>]*)?>\s*<title>/m); end
                title_outer_xml = "<title>#{esc_text(block.title)}</title>" unless is_title_handled_internally
            end
            procedural_steps_xml_parts << "<proceduralStep#{step_attrs}>#{title_outer_xml}#{converted_content}</proceduralStep>"
          end
        end
      end
      steps_content = procedural_steps_xml_parts.compact.reject(&:empty?).join("\n")
      steps_content.empty? ? "<proceduralStep><para/></proceduralStep>" : steps_content
    end

    def generate_fault_isolation_main_procedure_xml(document_node)
      fault_main_section = document_node.blocks.find { |b| b.context == :section && (b.id == 'fault_iso_main' || b.title.downcase.include?('fault isolation procedure')) }
      blocks_to_process = if fault_main_section; fault_main_section.blocks; else document_node.blocks.reject { |b| ['prelim_reqs', 'closeout_reqs', 'fault_descr'].any? { |id_part| b.id&.include?(id_part) || b.title.downcase.include?(id_part) } || ['applicdef', 'productdef', 'attribute_def', 'global_applicability_definition'].any? { |role_style| b.role == role_style || b.style == role_style }}; end
      isolation_steps_content = blocks_to_process.each_with_index.map do |block, index| step_id = block.id || "iso-step-#{index + 1}"; step_attrs = common_attributes(step_id) + applic_ref_attribute(block); converted_content = block.convert; converted_content.to_s.strip.empty? ? nil : "<isolationStep#{step_attrs}>#{converted_content}</isolationStep>"; end.compact.join("\n")
      isolation_steps_content = "<isolationProcedureEnd id=\"auto-end-empty-proc\"/>" if isolation_steps_content.strip.empty?; main_proc_attrs = fault_main_section ? common_attributes(fault_main_section.id) + applic_ref_attribute(fault_main_section) : ""; indented_steps = isolation_steps_content.empty? ? "" : "\n#{isolation_steps_content.gsub(/^/, '  ')}\n"; "<isolationMainProcedure#{main_proc_attrs}>#{indented_steps}</isolationMainProcedure>"
    end

    def generate_close_requirements_xml(document_node)
      close_section = document_node.blocks.find { |b| b.context == :section && (b.id == 'closeout_reqs' || b.title.downcase.include?('closeout requirements') || b.title.downcase.include?('requirements after job completion')) }; req_conds_xml = "<reqCondGroup><noConds/></reqCondGroup>"; attrs_for_close_rqmts = ""
      if close_section; attrs_for_close_rqmts = common_attributes(close_section.id) + applic_ref_attribute(close_section); conds_subsection = close_section.blocks.find { |b| b.context == :section && (b.id == 'closeout_conds_after' || b.title.downcase.include?('required conditions after job completion')) }; target_node_for_conds = conds_subsection || close_section; req_conds_xml = generate_req_cond_group_xml(target_node_for_conds, true); end
      indented_conds = req_conds_xml.empty? ? "" : "\n#{req_conds_xml.gsub(/^/, '  ')}\n"; "<closeRqmts#{attrs_for_close_rqmts}>#{indented_conds}</closeRqmts>"
    end

    def build_applic_condition_xml(condition_hash, indent_level = 0)
      current_indent_str = "  " * indent_level; xml_string = ""; unless condition_hash.is_a?(Hash); warn "..."; return ""; end; type = condition_hash['type']&.downcase
      if type == 'evaluate'; and_or = condition_hash['andOr']&.downcase || 'and'; children = condition_hash['children']; xml_string << "#{current_indent_str}<evaluate andOr=\"#{esc_text(and_or)}\">\n"; if children.is_a?(Array) && !children.empty?; children.each { |child_hash| xml_string << build_applic_condition_xml(child_hash, indent_level + 1) }; else warn "..."; end; xml_string << "#{current_indent_str}</evaluate>\n";
      elsif type == 'assert'; prop_ident = condition_hash['propertyIdent']; prop_values = condition_hash['propertyValues']; prop_type = condition_hash['propertyType'] || 'prodattr'; if prop_ident && prop_values; xml_string << "#{current_indent_str}<assert applicPropertyIdent=\"#{esc_text(prop_ident)}\" applicPropertyType=\"#{esc_text(prop_type)}\" applicPropertyValues=\"#{esc_text(prop_values)}\"/>\n"; else warn "..."; end;
      else warn "..."; end; xml_string
    end

    def generate_flat_global_asserts_xml(doc_attrs)
      collected_asserts = []; (1..).each do |i|; prop_ident = doc_attrs.fetch("s1000d-global-assert-#{i}-propertyident",nil).to_s.strip; prop_values = doc_attrs.fetch("s1000d-global-assert-#{i}-propertyvalues",nil).to_s.strip; break if prop_ident.empty?||prop_values.empty?; prop_type=doc_attrs.fetch("s1000d-global-assert-#{i}-propertytype",'prodattr').to_s.strip; prop_type='prodattr' if prop_type.empty?; collected_asserts << %(<assert applicPropertyIdent="#{esc_text(prop_ident)}" applicPropertyType="#{esc_text(prop_type)}" applicPropertyValues="#{esc_text(prop_values)}"/>); end; return "" if collected_asserts.empty?
      if collected_asserts.length > 1; operator = doc_attrs.fetch('s1000d-global-assert-operator','and').to_s.downcase.strip; operator = ['and','or'].include?(operator) ? operator : 'and'; %(<evaluate andOr="#{operator}">\n#{collected_asserts.map { |a| "  #{a}" }.join("\n")}\n</evaluate>); else collected_asserts.first; end
    end

    def build_ident_and_status_section_xml(doc_attrs, dm_code_attrs_in, act_dm_ref_for_dmstatus, global_applic_text_val, brex_dm_code_attrs_in, rfu_elements_xml, current_node_for_title)
      dm_code_attrs = dm_code_attrs_in; lang_code=(doc_attrs['lang']||doc_attrs['language']||'en').downcase; country_code=(doc_attrs['country-code']||doc_attrs['country']||'US').upcase; issue_number=doc_attrs['issue-number']||"001"; in_work_status=doc_attrs['in-work']||doc_attrs['inwork-status']||"00"; date_str=(doc_attrs['revdate']||doc_attrs['issue-date']).to_s.strip; year,month,day = nil,nil,nil; if date_str.match?(/^\d{4}-\d{2}-\d{2}$/);year,month,day=date_str.split('-');elsif date_str.match?(/^\d{8}$/);year,month,day=date_str[0..3],date_str[4..5],date_str[6..7];elsif !date_str.empty?;warn "...";end; unless year&&month&&day;now=Time.now;year,month,day=now.strftime('%Y'),now.strftime('%m'),now.strftime('%d');warn "..." if date_str.empty?;end; doc_title_obj=current_node_for_title.doctitle if current_node_for_title.respond_to?(:doctitle); tech_name=doc_attrs['tech-name']||doc_title_obj||"Default Technical Name"; dm_title_text=doc_attrs['dm-title']||doc_attrs['infoName']||tech_name; security_class=doc_attrs['security-classification']||"01"; enterprise_rpc_code=doc_attrs['enterprise-code-rpc']||"0000X"; rpc_name=doc_attrs['responsible-partner-company']||"UNKNOWN RPC"; enterprise_orig_code=doc_attrs['enterprise-code-originator']||enterprise_rpc_code; orig_name=doc_attrs['originator-enterprise']||rpc_name; brex_attrs=brex_dm_code_attrs_in; global_applic_inner_xml=""; if @global_applic_eval_hash&&@global_applic_eval_hash.is_a?(Hash)&&!@global_applic_eval_hash.empty?;raw_xml=build_applic_condition_xml(@global_applic_eval_hash);global_applic_inner_xml=raw_xml.strip;else flat_asserts_xml=generate_flat_global_asserts_xml(doc_attrs);global_applic_inner_xml=flat_asserts_xml.strip;if global_applic_inner_xml.empty?;if @global_applic_eval_hash&.empty?&&node_has_global_applic_block(doc_attrs[:document_node]);warn "...";elsif node_has_global_applic_block(doc_attrs[:document_node])&&@global_applic_eval_hash.nil?;warn "...";end;end;end; global_applic_xml_for_status=global_applic_inner_xml.empty? ? "" : "\n#{global_applic_inner_xml.gsub(/^/,'      ')}"; indented_rfu=rfu_elements_xml.strip.empty? ? "" : "\n"+rfu_elements_xml.strip.gsub(/^/,'    '); indented_act_ref=act_dm_ref_for_dmstatus.strip.empty? ? '' : "\n"+act_dm_ref_for_dmstatus.strip.gsub(/^/,'    ');
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
      else warn "...";'descript.xsd';
      end
    end

    def node_has_global_applic_block(document_node)
      return false unless document_node&.respond_to?(:blocks); document_node.blocks.any? { |b| (b.role == 'global_applicability_definition') || (b.style == 'global_applicability_definition') }
    end

    def convert_document node
      @s1000d_applic_definitions, @s1000d_product_definitions, @s1000d_product_attribute_definitions = [], [], []
      @global_applic_eval_hash = nil
      doc_attrs = node.document.attributes.dup; doc_attrs[:document_node] = node
      dmc_str = doc_attrs['dmc'] || doc_attrs['part-title']; dm_code_attrs = parse_dmc_string(dmc_str) || begin warn "..."; { modelIdentCode: "S1KDTOOLS", systemDiffCode: "A", systemCode: "00", subSystemCode: "0", subSubSystemCode: "0", assyCode: "0000", disassyCode: "00", disassyCodeVariant: "A", infoCode: "000", infoCodeVariant: "A", itemLocationCode: "A" }; 
      end
      brex_dmc_str = doc_attrs['brex-dmc']; brex_dm_code_attrs = parse_dmc_string(brex_dmc_str) || begin warn "..."; { modelIdentCode: "S1000D", systemDiffCode: "G", systemCode: "04", subSystemCode: "1", subSubSystemCode: "0", assyCode: "0301", disassyCode: "00", disassyCodeVariant: "A", infoCode: "022", infoCodeVariant: "A", itemLocationCode: "D" }; 
      end
      global_applic_text = (doc_attrs['s1000d-applic-text'] || doc_attrs['applicability-text'] || doc_attrs['applicability'] || "All applicable conditions").strip
      act_dmc_str = doc_attrs['act-dmc']; act_dm_ref_xml = ""; if act_dmc_str && !act_dmc_str.strip.empty?; if act_dm_c = parse_dmc_string(act_dmc_str); act_dm_ref_xml = "<applicCrossRefTableRef><dmRef><dmRefIdent><dmCode modelIdentCode=\"#{act_dm_c[:modelIdentCode]}\" systemDiffCode=\"#{act_dm_c[:systemDiffCode]}\" systemCode=\"#{act_dm_c[:systemCode]}\" subSystemCode=\"#{act_dm_c[:subSystemCode]}\" subSubSystemCode=\"#{act_dm_c[:subSubSystemCode]}\" assyCode=\"#{act_dm_c[:assyCode]}\" disassyCode=\"#{act_dm_c[:disassyCode]}\" disassyCodeVariant=\"#{act_dm_c[:disassyCodeVariant]}\" infoCode=\"#{act_dm_c[:infoCode]}\" infoCodeVariant=\"#{act_dm_c[:infoCodeVariant]}\" itemLocationCode=\"#{act_dm_c[:itemLocationCode]}\"/></dmRefIdent></dmRef></applicCrossRefTableRef>"; 
    else warn "..."; 
    end; 
  end
      rfu_raw = doc_attrs['reason-for-update'] || doc_attrs['rfu']; rfu_xml = if rfu_raw && !rfu_raw.strip.empty?; id_val,h_val,t_val=doc_attrs.values_at('rfu-id','rfu-highlight','rfu-type').map(&:to_s); %(\n<reasonForUpdate id="#{esc_text(id_val.empty? ? "rfu-0001" : id_val)}" updateHighlight="#{esc_text(h_val.empty? ? "1" : h_val)}" updateReasonType="#{esc_text(t_val.empty? ? "urt02" : t_val)}"><simplePara>#{esc_text(rfu_raw)}</simplePara></reasonForUpdate>); 
      else %(\n<reasonForUpdate id="rfu-def-0001" updateHighlight="1" updateReasonType="urt01"><simplePara>Initial issue or standard update.</simplePara></reasonForUpdate>); 
      end
      dm_type = (doc_attrs['dm-type'] || 'descript').downcase.strip
      node.blocks.each(&:convert) # This first pass populates definition arrays and @global_applic_eval_hash

      pal_xml = @s1000d_product_attribute_definitions.empty? ? "" : "<productAttributeList>\n#{@s1000d_product_attribute_definitions.map { |pa| "  #{pa.gsub(/^/, '  ')}" }.join("\n")}\n</productAttributeList>"
      pct_dm_ref_xml = ""; 
      if dm_type == 'act'; 
        pct_dmc_str = doc_attrs['pct-dmc']; 
      if pct_dmc_str && !pct_dmc_str.strip.empty?; 
        if pct_dm_c = parse_dmc_string(pct_dmc_str); 
        pct_dm_ref_xml = "<productCrossRefTableRef><dmRef><dmRefIdent><dmCode modelIdentCode=\"#{pct_dm_c[:modelIdentCode]}\" systemDiffCode=\"#{pct_dm_c[:systemDiffCode]}\" systemCode=\"#{pct_dm_c[:systemCode]}\" subSystemCode=\"#{pct_dm_c[:subSystemCode]}\" subSubSystemCode=\"#{pct_dm_c[:subSubSystemCode]}\" assyCode=\"#{pct_dm_c[:assyCode]}\" disassyCode=\"#{pct_dm_c[:disassyCode]}\" disassyCodeVariant=\"#{pct_dm_c[:disassyCodeVariant]}\" infoCode=\"#{pct_dm_c[:infoCode]}\" infoCodeVariant=\"#{pct_dm_c[:infoCodeVariant]}\" itemLocationCode=\"#{pct_dm_c[:itemLocationCode]}\"/></dmRefIdent></dmRef></productCrossRefTableRef>"; 
    else warn "..."; 
    end; 
  end; 
end
      internal_pct_xml = @s1000d_product_definitions.empty? ? "" : "<productCrossRefTable>\n#{@s1000d_product_definitions.map { |p| "  #{p.gsub(/^/, '  ')}" }.join("\n")}\n</productCrossRefTable>"
      act_outer_xml = ""; 
      if dm_type == 'act'; act_children_parts = [ (pal_xml.empty? ? nil : pal_xml), (internal_pct_xml.empty? ? nil : internal_pct_xml), (pct_dm_ref_xml.empty? ? nil : pct_dm_ref_xml) ].compact; act_children_indented = act_children_parts.map { |c| c.gsub(/^/, '  ') }.join("\n"); act_outer_xml = act_children_parts.empty? ? "" : "<applicCrossRefTable>\n#{act_children_indented}\n</applicCrossRefTable>"; 
      end
      rag_xml = @s1000d_applic_definitions.empty? ? "" : "<referencedApplicGroup>\n#{@s1000d_applic_definitions.map { |a| "  #{a.gsub(/^/, '  ')}" }.join("\n")}\n</referencedApplicGroup>"

      content_blocks_for_general = node.blocks.reject do |block|; is_def_block = (block.role && ['applicdef','productdef','attribute_def','global_applicability_definition'].include?(block.role)) || (block.style && ['applicdef','productdef','attribute_def','global_applicability_definition'].include?(block.style)); is_part_of_proc_structure = false; 
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
                          main_proc_steps_sequence = generate_main_procedure_steps_xml(node) # Should be the direct sequence
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
                          fault_descr_xml = fault_descr_content.empty? ? "<faultDescr><para>No fault description provided.</para></faultDescr>" : "<faultDescr>\n#{fault_descr_content.gsub(/^/, '  ')}\n</faultDescr>"; 
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
                        else warn "..."; 
                          content_indented = general_content_processed.gsub(/^/, '  '); 
                          "<description>\n#{content_indented}\n</description>"; 
                        end
      final_content_parts = []; 
      final_content_parts << rag_xml.strip if !rag_xml.empty?; 
      final_content_parts << main_dm_content.strip unless main_dm_content.strip.empty?; final_content_xml = final_content_parts.empty? ? "<noContent/>" : final_content_parts.join("\n")
      ident_status_section = build_ident_and_status_section_xml(doc_attrs, dm_code_attrs, act_dm_ref_xml, global_applic_text, brex_dm_code_attrs, rfu_xml, node)
      doctype_decl = build_doctype_declaration(final_content_xml); 
      schema_file = get_schema_file(dm_type); schema_base = doc_attrs['s1000d-schema-base-path'] || "http://www.s1000d.org/S1000D_5.0/xml_schema_flat/"
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

        # FINAL, CORRECTED convert_paragraph
    def convert_paragraph(node)
      # --- Handle special block roles first ---
      if node.role == 'applicdef'; process_as_applic_definition(node); return ""; end
      if node.role == 'productdef'; process_as_product_definition(node); return ""; end
      if node.role == 'attribute_def'; warn "..."; process_as_product_attribute_definition(node); return ""; end

      # --- This is the key ---
      # By calling `node.content`, we ask Asciidoctor to process all inline
      # elements within this paragraph (text, formatting, and our custom macro).
      # The engine will find `dmlref::[]` and automatically call our `convert_inline_macro`.
      processed_content = node.content

      para_attrs = common_attributes(node.id) + applic_ref_attribute(node)

      # If the result is empty, just create the tag with its attributes.
      return "<para#{para_attrs}/>" if processed_content.nil? || processed_content.strip.empty?

      # Wrap the fully-processed content in the <para> tag.
      %(<para#{para_attrs}>#{processed_content}</para>)
    end
    

    # REVISED convert_open
    
    def convert_open(node)
      if node.role == 'applicdef'; process_as_applic_definition(node); return ""
      elsif node.role == 'productdef'; process_as_product_definition(node); return ""
      elsif node.role == 'attribute_def'; process_as_product_attribute_definition(node); return ""
      # ADDED: Check for the new dmlref block role
      elsif node.role == 'dmlref' || node.style == 'dmlref'
        return global_refdmlref(node)
      end

      # --- Fallback to original logic for standard open blocks ---
      content = node.content.to_s.strip
      open_attrs = common_attributes(node.id) + applic_ref_attribute(node)
      title_el = node.title? ? "<title>#{esc_text(node.title)}</title>" : ""

      if title_el.empty? && open_attrs.strip.empty? && node.style != 'example' && node.role != 'example'
        return content # Return just the content if no attrs/title/example style
      end

      if node.style == 'example' || node.role == 'example'
        return %(<levelledPara#{open_attrs} class="example">#{title_el}#{content}</levelledPara>)
      end

      return "" if content.empty? && title_el.empty? && open_attrs.strip.empty?
      %(<levelledPara#{open_attrs}>#{title_el}#{content}</levelledPara>)
    end

    # NEW Reusable Helper Function
    # This function handles the logic for creating various reference types.
    def generate_global_ref(node)
      dmc_to_parse = node.attr('dmref') || node.attr('dmc')
      pmc_to_parse = node.attr('pmref') || node.attr('pmc')

      inner_ref_xml = ""

      if dmc_to_parse && !dmc_to_parse.strip.empty?
        parsed_code = parse_dmc_string(dmc_to_parse)
        if parsed_code
          code_attrs = parsed_code.map { |k, v| %(#{k}="#{esc_text(v)}") }.join(' ')
          inner_ref_xml = "<para><dmRef><dmRefIdent><dmCode #{code_attrs}/></dmRefIdent></dmRef></para>"
        else
          warn "asciidoctor: WARNING (generate_global_ref): Failed to parse DMC: '#{dmc_to_parse}'. Skipping."
          return "" # Return empty if parsing fails
        end
      elsif pmc_to_parse && !pmc_to_parse.strip.empty?
        parsed_code = parse_pmc_string(pmc_to_parse)
        if parsed_code
          inner_ref_xml = <<~XML.strip
          <para>
            <pmRef>
              <pmRefIdent>
                <pmCode modelIdentCode="#{esc_text(parsed_code[:modelIdentCode])}" pmIssuer="#{esc_text(parsed_code[:pmIssuer])}" pmNumber="#{esc_text(parsed_code[:pmNumber])}" pmVolume="#{esc_text(parsed_code[:pmVolume])}"/>
                <language languageIsoCode="#{esc_text(parsed_code[:languageIsoCode])}" countryIsoCode="#{esc_text(parsed_code[:countryIsoCode])}"/>
              </pmRefIdent>
            </pmRef>
            </para>
          XML
        else
          warn "asciidoctor: WARNING (generate_global_ref): Failed to parse PMC: '#{pmc_to_parse}'. Skipping."
          return "" # Return empty if parsing fails
        end
      else
        return "" # Not a recognized reference block
      end

      # Now, check the role to determine the wrapper element
      case node.role
      when 'req-content'
        # This role specifically requests a <reqContent> wrapper
        attrs = common_attributes(node.id) + applic_ref_attribute(node)
        return "<reqContent#{attrs}>#{inner_ref_xml}</reqContent>"
      else
        # Default behavior: return the reference directly, without a wrapper.
        # The attributes (id, applic_ref) will be attached to the <dmRef> or <pmRef> itself.
        # Note: S1000D schema might not allow attributes on <dmRef>, so this is a choice.
        # A safer default might be to wrap in a <para>. For now, let's return it directly.
        return inner_ref_xml
      end
    end

        # NEW: Handles custom inline macros like dmlref::[]
    # This provides a concise syntax for creating complex inline elements.
    def convert_inline_macro(node)
      case node.name
      when 'dmlref'
        # This handles the dmlref::[] macro.

        # Extract attributes from the Asciidoctor node's attribute list
        model_ident_code = node.attr('modelIdentCode')
        sender_ident     = node.attr('senderIdent')
        dml_type         = node.attr('dmlType')
        year             = node.attr('yearOfDataIssue')
        seq_number       = node.attr('seqNumber')

        # Validate that all required attributes are present.
        required_attrs = {
          'modelIdentCode'  => model_ident_code,
          'senderIdent'     => sender_ident,
          'dmlType'         => dml_type,
          'yearOfDataIssue' => year,
          'seqNumber'       => seq_number
        }

        missing_attrs = required_attrs.select { |key, value| value.nil? || value.to_s.strip.empty? }.keys
        unless missing_attrs.empty?
          warn "asciidoctor: WARNING (inline dmlref macro): An inline 'dmlref' is missing required attributes: #{missing_attrs.join(', ')}. Skipping output."
          return "" # Return an empty string to prevent invalid XML output.
        end

        # Build the S1000D <dmlRef> XML structure.
        # The `common_attributes` helper correctly handles the optional `id` attribute.
        <<~XML.strip
          <dmlRef#{common_attributes(node.id)}>
            <dmlRefIdent>
              <dmlCode modelIdentCode="#{esc_text(model_ident_code)}" senderIdent="#{esc_text(sender_ident)}" dmlType="#{esc_text(dml_type)}" yearOfDataIssue="#{esc_text(year)}" seqNumber="#{esc_text(seq_number)}"/>
            </dmlRefIdent>
          </dmlRef>
        XML
      else
        # Fallback for any other unhandled inline macros.
        warn %(asciidoctor: WARNING: S1000D converter encountered unhandled inline macro: '#{node.name}'. This content will be SKIPPED.)
        ""
      end
    end


    # NEW function to handle <dmlRef> generation from an AsciiDoc block.
    # This is triggered by a block with the 'dmlref' role.
    #
    # Example AsciiDoc usage:
    #   [[my-dml-ref]]
    #   [dmlref, modelIdentCode=EX, senderIdent=12345, dmlType=c, yearOfDataIssue=2018, seqNumber=00001]
    #   --
    #   This block generates a reference to a Data Management List (DML).
    #   The content inside this block is ignored by the converter.
    #   --
    def global_refdmlref(node)
      # Extract attributes from the Asciidoctor node
      model_ident_code = node.attr('modelIdentCode')
      sender_ident     = node.attr('senderIdent')
      dml_type         = node.attr('dmlType')
      year             = node.attr('yearOfDataIssue')
      seq_number       = node.attr('seqNumber')

      # Validate that all required attributes are present.
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
        return "" # Return an empty string to prevent invalid XML output.
      end

      # Build the S1000D <dmlRef> XML structure.
      # The `common_attributes` helper adds support for an optional `id`.
      <<~XML.strip
        <dmlRef#{common_attributes(node.id)}>
          <dmlRefIdent>
            <dmlCode modelIdentCode="#{esc_text(model_ident_code)}" senderIdent="#{esc_text(sender_ident)}" dmlType="#{esc_text(dml_type)}" yearOfDataIssue="#{esc_text(year)}" seqNumber="#{esc_text(seq_number)}"/>
          </dmlRefIdent>
        </dmlRef>
      XML
    end

   
   # UPDATED convert_ulist with the global helper logic
    # UPDATED convert_ulist with the global helper logic
    def convert_ulist(node)
      # NEW: Check if this ulist is being used as a special reference block.
      # A reference block is a ulist with attributes and exactly one simple item.
      if (node.attr?('dmref') || node.attr?('dmc') || node.attr?('pmref') || node.attr?('pmc')) &&
        node.items.length == 1 &&
        !node.items.first.blocks? &&
        (node.items.first.text.to_s.strip == '.' || node.items.first.text.to_s.strip.empty?)

        # It matches our pattern! Delegate to the global helper.
        return generate_global_ref(node) || ""
      end

      # --- The original, generic ulist logic is the fallback ---
      return "" if node.role == 'attribute_def' || node.style == 'attribute_def'
      list_attrs_for_rand_list = common_attributes(node.id) + applic_ref_attribute(node)
      items = node.items.map do |item|
        item_attrs = common_attributes(item.id) + applic_ref_attribute(item)
        inner_content = if item.blocks?; item.content; elsif item.text && !item.text.strip.empty?; "<para>#{esc_text(item.text)}</para>"; else "<para/>"; end
        "<listItem#{item_attrs}>#{inner_content}</listItem>"
      end.compact.join("\n")
      return "" if items.empty?
      "<para><randomList#{list_attrs_for_rand_list}>#{items}</randomList></para>"
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
        json_string = node.content; 
        begin; parsed = JSON.parse(json_string); @global_applic_eval_hash = (parsed.is_a?(Hash) && !parsed.empty?) ? parsed : (warn("...") ; nil); 
        rescue JSON::ParserError => e; warn "..."; @global_applic_eval_hash = nil; 
        end; 
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

    # REVISED AND CORRECTED convert_section
def convert_section(node)
  # This is the key to the solution. We use `chunk` to group consecutive blocks.
  # Blocks are grouped by whether they are an admonition or not.
  # This creates groups like:
  #   [ [false, [para, list]], [true, [warning]], [false, [para]], [true, [caution, note]] ]
  groups = node.blocks.chunk do |block|
    block.context == :admonition
  end

  output_parts = []
  # We only want to add the section's main ID and title to the VERY FIRST <levelledPara>
  has_output_first_levelled_para = false

  groups.each do |is_admonition_group, blocks_in_group|
    if is_admonition_group
      # This group contains only admonitions. Convert each one directly.
      # They will NOT be wrapped in <levelledPara>.
      blocks_in_group.each do |admonition_block|
        output_parts << admonition_block.convert
      end
    else
      # This group contains standard content (paragraphs, lists, tables, etc.).
      # We will convert all of them and wrap the combined result in a single <levelledPara>.
      content_for_para = blocks_in_group.map(&:convert).join("\n")

      # Avoid creating empty <levelledPara> tags.
      next if content_for_para.strip.empty?

      para_attrs = ""
      title_xml = ""

      # The main section ID, attributes, and title should only be applied to the
      # first chunk of "wrappable" content.
      unless has_output_first_levelled_para
        para_attrs = common_attributes(node.id) + applic_ref_attribute(node)
        title_xml = node.title? ? "<title>#{esc_text(node.title)}</title>" : ""
        has_output_first_levelled_para = true
      end

      # Assemble and add the <levelledPara> to our output.
      output_parts << "<levelledPara#{para_attrs}>#{title_xml}#{content_for_para}</levelledPara>"
    end
  end

  # Join all the generated parts (both <levelledPara>s and standalone admonitions)
  # into the final string.
  output_parts.join("\n")
end

    def convert_inline_anchor(node)
      case node.type
      when :xref; target=(node.attributes['refid']||node.target).sub(/^#/,'');tn=node.document.catalog[:ids][target];ta=determine_internal_ref_target_type(tn,target);dt=node.text||target;"<internalRef internalRefId=\"#{esc_text(target)}\"#{ta}>#{esc_text(dt)}</internalRef>"
      when :link; dt=node.text||node.target;"<externalRef destination=\"#{esc_text(node.target)}\">#{esc_text(dt)}</externalRef>"
      when :ref,:bibref; node.text ? esc_text(node.text) : ""
      else warn "..."; esc_text(node.text || node.target); end
    end

    def convert_table(node)
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
      result
    end

    alias convert_embedded content_only

    def convert_image(node)
      attrs=common_attributes(node.id)+applic_ref_attribute(node);title_xml=node.title ? "<title>#{esc_text(node.title)}</title>" : "";icn_val=node.attr('icn')
      unless icn_val && !icn_val.strip.empty?;img_tgt_bn=File.basename(node.attr('target','unknown.png'),'.*');alt=node.attr('alt');
        if alt && alt.match?(/^(?:ICN|FIG)-/i);icn_val=alt.upcase;elsif img_tgt_bn.match?(/^(?:ICN|FIG)-/i);icn_val=img_tgt_bn.upcase;
        else fb=alt||img_tgt_bn;icn_val="FIG-#{fb.gsub(/[^A-Za-z0-9\-_\.]/,'_').gsub(/_+/,'_').upcase}";warn "... #{icn_val}.";
        end;
      end
      "<figure#{attrs}>#{title_xml}<graphic infoEntityIdent=\"#{esc_text(icn_val.strip)}\"/></figure>"
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
      case type;when 'WARNING';"<warning#{attrs}>#{final_inner_xml}</warning>";when 'CAUTION';"<caution#{attrs}>#{final_inner_xml}</caution>";when 'NOTE';"<note#{attrs}>#{final_inner_xml}</note>";when 'TIP','IMPORTANT';warn "...";"<note#{attrs}>#{final_inner_xml}</note>";
      else warn "...";fallback_text_content=node.content.to_s.strip;fallback_para=if fallback_text_content.empty?;"<notePara/>";elsif !node.blocks?;"<notePara>#{esc_text(fallback_text_content)}</notePara>";else fallback_text_content;end;"<note#{attrs}>#{fallback_para}</note>";end
    end

    def convert_thematic_break(node)
      ''
    end

    def convert_inline_image(node)
      target_path=node.target;icn_val=node.attr('icn'); unless icn_val && !icn_val.strip.empty?;alt_text=node.attr('alt');base_filename=File.basename(target_path,'.*'); if alt_text && alt_text.match?(/^(?:ICN|FIG)-/i);icn_val=alt_text.upcase;elsif base_filename.match?(/^(?:ICN|FIG)-/i);icn_val=base_filename.upcase; else fallback_base=alt_text||base_filename;icn_val="INL-FIG-#{fallback_base.gsub(/[^A-Za-z0-9\-_\.]/,'_').gsub(/_+/,'_').upcase}";warn "... #{icn_val}.";end;end; "<graphic infoEntityIdent=\"#{esc_text(icn_val.strip)}\"/>"
    end

    def convert_fallback(node)
      warn %(asciidoctor: WARNING: S1000D converter encountered unhandled node type: '#{node.node_name}' (ID: '#{node.id}', Context: '#{node.context}'). This content will be SKIPPED.); ""
    end
  end
end