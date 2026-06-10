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
      @global_applic_eval_hash = nil # Stores parsed JSON from the global_applicability_definition block
    end

    def common_attributes(id)
      id ? %( id="#{id}") : ''
    end

    def applic_ref_attribute(node)
      node.attr?('applic_ref') ? %( applicRefId="#{esc_text(node.attr('applic_ref'))}") : ''
    end

    # Escape text for XML content - Preserving user's original (potentially flawed) escaping style
    def esc_text(text)
      return '' if text.nil?
      text.to_s
          .gsub('&', '&') # Note: This should ideally be .gsub('&', '&')
          .gsub('<', '<') # Note: This should ideally be .gsub('<', '<')
          .gsub('>', '>') # Note: This should ideally be .gsub('>', '>')
          .gsub('"', '"') # Note: This should ideally be .gsub('"', '"')
    end

    # For content that might already be XML (minimal escaping)
    def esc_content(text_or_content)
      return '' if text_or_content.nil?
      return text_or_content unless text_or_content.is_a?(String) # If already processed
      text_or_content.to_s
    end

    # Parse S1000D Data Module Code (DMC) - From new code (cleans comments)
    def parse_dmc_string(dmc_string)
      return nil unless dmc_string && dmc_string.is_a?(String) && !dmc_string.strip.empty?
      cleaned_dmc_string = dmc_string.split('//').first.strip # Remove comments

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
          warn "asciidoctor: WARNING (parse_dmc_string): Regex DID NOT MATCH for 11-part DMC input '#{cleaned_dmc_string}'. Ensure DMC is 11 parts and conforms to S1000D structure. Check for invalid characters or incorrect segment lengths."
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

      unless id && name_text && descr_text
        if node.context == :ulist && node.role == 'attribute_def' # If role is on ulist directly
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
      enumerations_xml_parts.each do |enum_xml|
        attribute_xml << "  #{enum_xml}\n"
      end
      attribute_xml << "</productAttribute>"

      @s1000d_product_attribute_definitions << attribute_xml
      return true
    end

    # ***** Using ORIGINAL generate_req_cond_group_xml and its helper *****
    def generate_req_cond_group_xml(section_node, for_closeout = false)
      return "<reqCondGroup><noConds/></reqCondGroup>" unless section_node

      conditions_xml_elements = []
      has_actual_conditions = false

      section_node.blocks.each_with_index do |block, idx|
        case block.context
        when :paragraph
          is_likely_xref_target_only = block.id &&
                                       section_node.document.references[:ids].key?(block.id) &&
                                       block.source.lines.count <= 2 &&
                                       block.source.downcase.include?(block.id.downcase)

          unless is_likely_xref_target_only
            warn "asciidoctor: WARNING: Paragraph found directly in '#{section_node.title}' section: '#{block.source.lines.first.strip[0,70]}...'. This paragraph will be SKIPPED for S1000D <reqCondGroup> generation. Place such text outside the specific list of conditions or ensure it's part of a list item."
          end

        when :ulist, :olist
          has_actual_conditions = true
          block.items.each do |item|
            item_text_content = item.text
            dm_ref_attr_val = item.attr('dmref')

            cleaned_text_for_req_cond_para = item_text_content
                .gsub(/\[dmref=.*?\]/, '')
                .strip
            # item.content will trigger conversion of nested blocks, respecting applicRefId etc.
            req_cond_inner_xml = item.blocks? ? item.content : "#{esc_text(cleaned_text_for_req_cond_para)}"


            if dm_ref_attr_val
              dm_ref_xml_part = ""
              parsed_dm_ref_code = parse_dmc_string(dm_ref_attr_val)
              if parsed_dm_ref_code
                dm_code_attrs_xml = parsed_dm_ref_code.map { |k, v| %(#{k}="#{esc_text(v)}") }.join(' ')
                dm_ref_xml_part = "<dmRef><dmRefIdent><dmCode #{dm_code_attrs_xml}/></dmRefIdent></dmRef>"
                conditions_xml_elements << "<reqCondDm#{common_attributes item.id}#{applic_ref_attribute item}><reqCond>#{req_cond_inner_xml}</reqCond>#{dm_ref_xml_part}</reqCondDm>"
              else
                warn "asciidoctor: WARNING: Invalid dmref attribute '#{dm_ref_attr_val}' in Required Conditions for item '#{item_text_content}'. Treating as reqCondNoRef."
                internal_ref_xml_parts = []
                item_text_content.scan(/<<([^>]+)>>/) do |match|
                  target_id = match[0]
                  target_node = section_node.document.catalog[:ids][target_id]
                  target_type_attr = determine_internal_ref_target_type(target_node, target_id)
                  internal_ref_xml_parts << "<internalRef internalRefId=\"#{esc_text(target_id)}\"#{target_type_attr}/>"
                end
                conditions_xml_elements << "<reqCondNoRef#{common_attributes item.id}#{applic_ref_attribute item}><reqCond>#{req_cond_inner_xml}</reqCond>#{internal_ref_xml_parts.join("\n")}</reqCondNoRef>"
              end
            else
              internal_ref_xml_parts = []
              item_text_content.scan(/<<([^>]+)>>/) do |match|
                target_id = match[0]
                target_node = section_node.document.catalog[:ids][target_id]
                target_type_attr = determine_internal_ref_target_type(target_node, target_id)
                internal_ref_xml_parts << "<internalRef internalRefId=\"#{esc_text(target_id)}\"#{target_type_attr}/>"
              end
              conditions_xml_elements << "<reqCondNoRef#{common_attributes item.id}#{applic_ref_attribute item}><reqCond>#{req_cond_inner_xml}</reqCond>#{internal_ref_xml_parts.join("\n")}</reqCondNoRef>"
            end
          end

        when :admonition
          has_actual_conditions = true
          if block.attr('name')&.casecmp('note')&.zero?
            conditions_xml_elements << block.convert
          else
            warn "asciidoctor: WARNING: Non-NOTE admonition (#{block.attr('name')}) found directly in '#{section_node.title}'. It will be converted but may not be valid within <reqCondGroup> depending on schema. Content: #{block.source.lines.first.strip[0,50]}..."
            conditions_xml_elements << block.convert
          end

        else
          unless block.context == :thematic_break # Thematic breaks are fine
             warn "asciidoctor: WARNING: Unhandled block type '#{block.context}' in '#{section_node.title}' section. This block will be SKIPPED for S1000D <reqCondGroup> generation."
          end
        end
      end

      if !has_actual_conditions || conditions_xml_elements.empty?
        return "<reqCondGroup><noConds/></reqCondGroup>"
      else
        return "<reqCondGroup>\n" + conditions_xml_elements.join("\n") + "\n</reqCondGroup>"
      end
    end

    # ***** Using ORIGINAL generate_req_tech_info_group_xml *****
    def generate_req_tech_info_group_xml(section_node)
      default_no_req_tech_info = "<reqTechInfoGroup><noReqTechInfo/></reqTechInfoGroup>"
      return default_no_req_tech_info unless section_node

      tech_info_entries = []
      found_explicit_no_info = false

      section_node.blocks.each do |block|
        break if found_explicit_no_info

        if block.context == :ulist || block.context == :olist
          block.items.each do |item|
            dmc_to_parse = nil
            dmc_attr_value = item.attr('dmc')
            if dmc_attr_value && !dmc_attr_value.strip.empty?
              dmc_to_parse = dmc_attr_value.strip
            else
              raw_item_text = item.text.to_s.strip
              if raw_item_text.downcase.match?(/(no|none)\s+(required\s+)?tech(nical)?\s+info(rmation)?/i)
                found_explicit_no_info = true
                break
              end
              dmc_candidate_regex = /((?:DMC-)?(?:[A-Z0-9]+-){10}[A-Z0-9]+)/i
              match_data = dmc_candidate_regex.match(raw_item_text)
              if match_data && match_data[1]
                potential_dmc_from_text = match_data[1]
                if parse_dmc_string(potential_dmc_from_text)
                   dmc_to_parse = potential_dmc_from_text
                else
                  if !raw_item_text.empty?
                     warn "asciidoctor: INFO: Text '#{raw_item_text}' in 'Required Technical Information' contains a DMC-like pattern ('#{potential_dmc_from_text}') that did not fully parse. No 'dmc' attribute was found. Skipping item."
                  end
                  next
                end
              else
                if !raw_item_text.empty?
                  warn "asciidoctor: INFO: List item text '#{raw_item_text}' in 'Required Technical Information' does not appear to contain a valid DMC, and no 'dmc' attribute was found. Skipping item."
                end
                next
              end
            end

            next if dmc_to_parse.nil? || dmc_to_parse.empty?

            category = item.attr('category', 'ti01')
            parsed_dmc_hash = parse_dmc_string(dmc_to_parse)

            if parsed_dmc_hash
              dm_code_attrs_xml = parsed_dmc_hash.map { |k, v| %(#{k}="#{esc_text(v)}") }.join(' ')
              # Added common_attributes and applic_ref_attribute to reqTechInfo
              tech_info_entries << <<~TECH_INFO_ENTRY.strip
                <reqTechInfo#{common_attributes item.id}#{applic_ref_attribute item} reqTechInfoCategory="#{esc_text(category)}">
                  <dmRef>
                    <dmRefIdent>
                      <dmCode #{dm_code_attrs_xml}/>
                    </dmRefIdent>
                  </dmRef>
                </reqTechInfo>
              TECH_INFO_ENTRY
            else
              warn "asciidoctor: WARNING: Failed to parse '#{dmc_to_parse}' as a valid DMC in 'Required Technical Information'. Skipping."
            end
          end
        elsif block.context == :paragraph
          if block.source.strip.downcase.match?(/(no|none)\s+(required\s+)?tech(nical)?\s+info(rmation)?/i)
            found_explicit_no_info = true
          elsif !block.source.strip.empty?
             warn "asciidoctor: WARNING: Non-list paragraph found in 'Required Technical Information' section: '#{block.source.lines.first.strip[0,50]}...'. Such paragraphs are ignored unless they state 'no required technical information'; use a list for DMCs."
          end
        end
      end

      if found_explicit_no_info || tech_info_entries.empty?
        return default_no_req_tech_info
      else
        return "<reqTechInfoGroup>\n" + tech_info_entries.join("\n") + "\n</reqTechInfoGroup>"
      end
    end

    # ***** Using ORIGINAL determine_internal_ref_target_type *****
    def determine_internal_ref_target_type(target_node, target_id_for_warning)
      return "" unless target_node

      case target_node.context
      when :image, :figure_node
        ' internalRefTargetType="irtt01"'
      when :paragraph
        if target_node.role == 'note-para'
            ' internalRefTargetType="irtt08"'
        else
            ' internalRefTargetType="irtt02"'
        end
      when :table
        ' internalRefTargetType="irtt03"'
      when :admonition
        case target_node.attr('name')&.upcase
        when 'NOTE';    ' internalRefTargetType="irtt08"'
        when 'WARNING'; ' internalRefTargetType="irtt09"'
        when 'CAUTION'; ' internalRefTargetType="irtt0A"'
        else ''
        end
      when :olist_item, :ulist_item, :list_item
        if target_node.role == 'proceduralStep' || target_node.id&.start_with?('step_')
           ' internalRefTargetType="irtt0F"'
        else
           ''
        end
      when :section
        ''
      else
        warn "asciidoctor: INFO: Could not determine specific S1000D internalRefTargetType for target ID '#{target_id_for_warning}' (context: #{target_node.context}). Omitting type."
        ''
      end
    end

    # ***** Using ORIGINAL generate_req_persons_xml *****
    def generate_req_persons_xml(section_node)
      return "" unless section_node
      table_node = section_node.blocks.find { |b| b.context == :table }
      return "" unless table_node
      personnel_entries = []
      # Added common_attributes node.id and applic_ref_attribute node to <person>
      # However, S1000D <person> doesn't typically have these. Attributes usually go on items or steps.
      # For now, I will assume they are not needed directly on <person>, but if there's a requirement
      # to make the entire personnel group conditional, that's handled by the <reqPersons> wrapper.
      # The attributes on table rows/cells are not directly translatable to <person> attributes.
      table_node.rows.body.each_with_index do |row_cells, idx| # Added index for potential ID generation
        # Attempt to get ID and applic_ref from the first cell's node if it exists,
        # assuming the first cell might carry these attributes for the row.
        # This is a heuristic. Ideally, attributes would be on the row, but Asciidoctor::Table::Row doesn't support attributes directly.
        row_id = row_cells[0]&.id || "person-#{idx}" # Fallback ID
        row_applic_ref_attr = row_cells[0] ? applic_ref_attribute(row_cells[0]) : ''


        desc_text        = row_cells[0] ? esc_text(row_cells[0].text.strip) : "N/A"
        category_code    = row_cells[1] ? esc_text(row_cells[1].text.strip.upcase) : "MAINT"
        skill_level_code = row_cells[2] ? esc_text(row_cells[2].text.strip) : "01"
        number_val       = row_cells[3] ? esc_text(row_cells[3].text.strip) : "1"
        time_val         = row_cells[4] ? esc_text(row_cells[4].text.strip) : "0.0"
        time_unit        = (row_cells[5] && !row_cells[5].text.strip.empty?) ? esc_text(row_cells[5].text.strip.downcase) : "h"

        # S1000D schema for <person> does not have @id or @applicRefId.
        # If these are needed, they should be on a higher-level S1000D element or a custom extension.
        # For now, omitting common_attributes and applic_ref_attribute directly on <person>.
        personnel_entries << <<~PERSON_ENTRY
          <person man="#{number_val}">
            <personCategory personCategoryCode="#{category_code}"></personCategory>
            <personSkill skillLevelCode="#{skill_level_code}" />
            <trade>#{desc_text}</trade>
            <estimatedTime unitOfMeasure="#{time_unit}">#{time_val}</estimatedTime>
          </person>
        PERSON_ENTRY
      end
      return personnel_entries.empty? ? "" : "<reqPersons>\n" + personnel_entries.join("\n") + "\n</reqPersons>"
    end

    # ***** Using ORIGINAL generate_table_based_req_list *****
    # Modified to add common_attributes and applic_ref_attribute to the individual item tag
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

      individual_item_xml_entries = []

      table_node.rows.body.each_with_index do |row_cells, idx| # Added index for ID
        # Heuristic: use first cell's attributes for the item.
        # This assumes attributes for the item are placed on its first cell in the Asciidoc table.
        item_id_attr = row_cells[cols_map[:name]] ? common_attributes(row_cells[cols_map[:name]].id || "#{individual_item_tag}-#{idx}") : common_attributes("#{individual_item_tag}-#{idx}")
        item_applic_attr = row_cells[cols_map[:name]] ? applic_ref_attribute(row_cells[cols_map[:name]]) : ''


        name_text = row_cells[cols_map[:name]] ? esc_text(row_cells[cols_map[:name]].text.strip) : "N/A"
        mfr_code_text = (cols_map[:mfr] && row_cells[cols_map[:mfr]]) ? esc_text(row_cells[cols_map[:mfr]].text.strip) : ""
        part_no_text  = (cols_map[:pn] && row_cells[cols_map[:pn]])  ? esc_text(row_cells[cols_map[:pn]].text.strip)  : ""
        qty_text      = row_cells[cols_map[:qty]] ? esc_text(row_cells[cols_map[:qty]].text.strip) : "1"
        uom_code_text = (cols_map[:uom] && row_cells[cols_map[:uom]]) ? esc_text(row_cells[cols_map[:uom]].text.strip.upcase) : "EA"

        case group_tag
        when "supportEquipDescrGroup"
          individual_item_xml_entries << <<~ITEM
            <#{individual_item_tag}#{item_id_attr}#{item_applic_attr}><catalogSeqNumberRef figureNumber="#{name_text}" item="#{mfr_code_text}"></catalogSeqNumberRef><reqQuantity>#{qty_text}</reqQuantity></#{individual_item_tag}>
          ITEM
        when "supplyDescrGroup"
          individual_item_xml_entries << <<~ITEM
            <#{individual_item_tag}#{item_id_attr}#{item_applic_attr}><identNumber><manufacturerCode>#{mfr_code_text}</manufacturerCode><partAndSerialNumber>
                  <partNumber>#{part_no_text}</partNumber>
                </partAndSerialNumber></identNumber><reqQuantity unitOfMeasure="#{uom_code_text}">#{qty_text}</reqQuantity></#{individual_item_tag}>
           ITEM
        when "spareDescrGroup"
          individual_item_xml_entries << <<~ITEM
            <#{individual_item_tag}#{item_id_attr}#{item_applic_attr}><catalogSeqNumberRef figureNumber="#{name_text}" item="#{mfr_code_text}"/><reqQuantity>#{qty_text}</reqQuantity></#{individual_item_tag}>
           ITEM
        end
      end

      if individual_item_xml_entries.empty?
        return "<#{list_tag}>#{no_item_tag}</#{list_tag}>"
      else
        items_joined_xml = individual_item_xml_entries.join("\n")
        grouped_items_xml = "<#{group_tag}>\n#{items_joined_xml}\n</#{group_tag}>"
        return "<#{list_tag}>\n#{grouped_items_xml}\n</#{list_tag}>"
      end
    end


    # ***** Using NEWER generate_req_safety_xml (more flexible) *****
    def generate_req_safety_xml(section_node)
        return "<reqSafety><noSafety/></reqSafety>" unless section_node
        # This will convert ALL blocks within the safety section.
        # If a definition block (applicdef, etc.) is mistakenly placed here, its convert method should return ""
        safety_elements = section_node.blocks.map(&:convert).map(&:strip).reject(&:empty?) # block.convert ensures applicRefId is handled
        if safety_elements.empty?
          return "<reqSafety><noSafety/></reqSafety>"
        else
          # The <safetyRqmts> element itself does not typically have id or applicRefId in S1000D.
          # These attributes are on the individual warnings, cautions, notes.
          return "<reqSafety><safetyRqmts>\n" + safety_elements.join("\n") + "\n</safetyRqmts></reqSafety>"
        end
    end

    # ***** Using ORIGINAL generate_preliminary_requirements_xml *****
    # (But ensure sub-calls use the updated generators that handle applicRefId)
    def generate_preliminary_requirements_xml(document_node)
      prelim_section = document_node.blocks.find { |b| b.context == :section && (b.id == 'prelim_reqs' || b.title.downcase.include?('preliminary requirements')) }

      req_conds_xml = "<reqCondGroup><noConds/></reqCondGroup>"
      req_persons_xml = ""
      req_tech_info_xml = "<reqTechInfoGroup><noReqTechInfo/></reqTechInfoGroup>"
      req_support_equip_xml = "<reqSupportEquips><noSupportEquips/></reqSupportEquips>"
      req_supplies_xml = "<reqSupplies><noSupplies/></reqSupplies>"
      req_spares_xml = "<reqSpares><noSpares/></reqSpares>"
      req_safety_xml = "<reqSafety><noSafety/></reqSafety>"

      if prelim_section
        # Add common_attributes and applic_ref_attribute to the <preliminaryRqmts> element itself
        # prelim_attrs = common_attributes(prelim_section.id) + applic_ref_attribute(prelim_section)
        # S1000D <preliminaryRqmts> does not have @id or @applicRefId. Attributes go on contained elements.

        prelim_section.blocks.each do |sub_block|
          next unless sub_block.context == :section
          id_or_title = sub_block.id ? sub_block.id.downcase : sub_block.title.downcase

          if id_or_title.include?('req_conds') || id_or_title.include?('required condition')
            req_conds_xml = generate_req_cond_group_xml(sub_block) # This will handle internal applicRefId
          elsif id_or_title.include?('req_persons') || id_or_title.include?('required person')
            req_persons_xml = generate_req_persons_xml(sub_block)
          elsif id_or_title.include?('req_tech_info') || id_or_title.include?('required technical information')
            req_tech_info_xml = generate_req_tech_info_group_xml(sub_block)
          elsif id_or_title.include?('req_equip') || id_or_title.include?('support equipment')
            req_support_equip_xml = generate_table_based_req_list(
              sub_block, "reqSupportEquips", "supportEquipDescrGroup", "supportEquipDescr",
              "<noSupportEquips/>", {name:0, mfr:1, pn:2, qty:3, uom:4}
            )
          elsif id_or_title.include?('req_consum') || id_or_title.include?('consumable')
            req_supplies_xml = generate_table_based_req_list(
              sub_block, "reqSupplies", "supplyDescrGroup", "supplyDescr",
              "<noSupplies/>", {name:0, mfr:1, pn:2, qty:3, uom:4}
            )
          elsif id_or_title.include?('req_spares') || id_or_title.include?('spare')
            req_spares_xml = generate_table_based_req_list(
              sub_block, "reqSpares", "spareDescrGroup", "spareDescr",
              "<noSpares/>", {name:0, mfr:1, pn:2, qty:3} # uom not typical for spares list
            )
          elsif id_or_title.include?('req_safety') || id_or_title.include?('safety condition')
            req_safety_xml = generate_req_safety_xml(sub_block)
          end
        end
      end

      prelim_xml_parts = [
        req_conds_xml,
        (req_persons_xml unless req_persons_xml.empty?),
        req_tech_info_xml,
        req_support_equip_xml,
        req_supplies_xml,
        req_spares_xml,
        req_safety_xml
      ].compact.join("\n")

      # Add attributes to preliminaryRqmts if prelim_section exists and has them
      prelim_attrs = ""
      if prelim_section
        prelim_attrs = common_attributes(prelim_section.id) + applic_ref_attribute(prelim_section)
      end
      # However, standard S1000D <preliminaryRqmts> doesn't have id or applicRefId.
      # These would be on contained elements or via applicability on the DM itself.
      # For now, omitting prelim_attrs from <preliminaryRqmts>.

      "<preliminaryRqmts>\n#{prelim_xml_parts}\n</preliminaryRqmts>"
    end

    # ***** Using ORIGINAL generate_main_procedure_steps_xml *****
    # Modified to add attributes to <proceduralStep>
    def generate_main_procedure_steps_xml(document_node)
      main_proc_section = document_node.blocks.find { |b| b.context == :section && (b.id == 'main_proc_steps' || b.title.downcase.include?('main procedure')) }
      steps_content = "";
      blocks_to_process = []
      if main_proc_section;
        blocks_to_process = main_proc_section.blocks;
      else
          blocks_to_process = document_node.blocks.reject { |b| b.context == :section && ((b.id == 'prelim_reqs' || b.title.downcase.include?('preliminary req')) || (b.id == 'closeout_reqs' || b.title.downcase.include?('closeout req'))) }
      end
      blocks_to_process.each_with_index do |block, index|
          if block.context == :olist
              block.items.each_with_index do |li, li_idx|
                # If li is a complex block, li.content will call convert, which handles applicRefId.
                # If li is simple text, para wraps it. The applicRefId should be on the <proceduralStep> from the list item.
                step_id = li.id || "step-main-#{index}-#{li_idx}"
                step_attrs = common_attributes(step_id) + applic_ref_attribute(li)
                inner_content = li.blocks? ? li.content : "<para#{applic_ref_attribute(li)}>#{esc_text(li.text)}</para>" # Added applic to inner para too if simple
                steps_content << "<proceduralStep#{step_attrs}>#{inner_content}</proceduralStep>\n"
              end
          elsif block # This handles paragraphs, images, tables etc. directly as steps
            # block.convert will handle its own ID and applic_ref.
            # The <proceduralStep> itself can take an ID from the block or generate one.
            # It can also take an applic_ref from the block.
            step_id = block.id || "step-main-#{index}"
            step_attrs = common_attributes(step_id) + applic_ref_attribute(block)
            steps_content << "<proceduralStep#{step_attrs}>#{block.convert}</proceduralStep>\n"
          end
      end
      return steps_content.empty? ? "<proceduralStep><para/></proceduralStep>" : steps_content.strip
    end

    # ***** Using ORIGINAL generate_fault_isolation_main_procedure_xml *****
    # Modified to add attributes to <isolationStep>
    def generate_fault_isolation_main_procedure_xml(document_node)
      fault_main_section = document_node.blocks.find { |b| b.context == :section && (b.id == 'fault_iso_main' || b.title.downcase.include?('fault isolation procedure')) }
      isolation_steps_content = "";
      blocks_to_process = []
      if fault_main_section
          blocks_to_process = fault_main_section.blocks
      else
          blocks_to_process = document_node.blocks.reject do |b|
              b.context == :section && (
                  (b.id == 'prelim_reqs' || b.title.downcase.include?('preliminary req')) ||
                  (b.id == 'closeout_reqs' || b.title.downcase.include?('closeout req')) ||
                  (b.id == 'fault_descr' || b.title.downcase.include?('fault description'))
              )
          end
      end
      if blocks_to_process.empty?
        # This default step needs review if it should support ID/applicRefId; typically not for a default.
        isolation_steps_content = "<isolationStep><isolationStepQuestion><para>No isolation steps defined.</para></isolationStepQuestion><yesAnswer><nextAction><gotoStandardTask targetDmRefIdent=" + '"FIXME-TARGET-DMREF"' + "/></nextAction></yesAnswer><noAnswer><nextAction><gotoStandardTask targetDmRefIdent=" + '"FIXME-TARGET-DMREF"' + "/></nextAction></noAnswer></isolationStep>"
      else
        blocks_to_process.each_with_index do |block, index|
            # block.convert handles its internal content and attributes.
            # <isolationStep> can take ID and applic_ref from the block.
            step_id = block.id || "iso-step-#{index}"
            step_attrs = common_attributes(step_id) + applic_ref_attribute(block)
            isolation_steps_content << "<isolationStep#{step_attrs}>#{block.convert}</isolationStep>\n"
        end
      end
      main_content = isolation_steps_content.empty? ? "<isolationProcedureEnd id=\"auto-end-0001\"/>" : isolation_steps_content.strip
      "<isolationMainProcedure>\n#{main_content}\n</isolationMainProcedure>"
    end

    # ***** Using ORIGINAL generate_close_requirements_xml *****
    # (But relies on generate_req_cond_group_xml which is now updated)
    def generate_close_requirements_xml(document_node)
      close_section = document_node.blocks.find { |b| b.context == :section && (b.id == 'closeout_reqs' || b.title.downcase.include?('closeout requirements') || b.title.downcase.include?('requirements after job completion')) }
      req_conds_xml = "<reqCondGroup><noConds/></reqCondGroup>"
      # S1000D <closeRqmts> itself does not have ID or applicRefId.
      # attrs_for_close_rqmts = ""
      if close_section
          # attrs_for_close_rqmts = common_attributes(close_section.id) + applic_ref_attribute(close_section)
          conds_subsection = close_section.blocks.find { |b| b.context == :section && (b.id == 'closeout_conds_after' || b.title.downcase.include?('required conditions after job completion')) }
          target_node_for_conds = conds_subsection || close_section
          req_conds_xml = generate_req_cond_group_xml(target_node_for_conds, true) # Handles internal applicRefIds
      end
      "<closeRqmts>\n#{req_conds_xml}\n</closeRqmts>" # Removed attrs_for_close_rqmts
    end

    # --- START: Helper methods for convert_document (from new code) ---
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
                evaluate_children_xml = collected_assert_strings.map { |s_assert| s_assert.gsub(/^/, '  ') }.join("\n")
                asserts_container_xml = <<~EVALUATE_XML.strip
                  <evaluate andOr="#{operator}">
                  #{evaluate_children_xml}
                  </evaluate>
                EVALUATE_XML
            else
                asserts_container_xml = collected_assert_strings[0] # Single assert
            end
            asserts_container_xml = asserts_container_xml.gsub(/^/, '      ')
        end
        asserts_container_xml
    end

    def build_ident_and_status_section_xml(doc_attrs, dm_code_attrs_in, act_dm_ref_for_dmstatus, global_applic_text_val, brex_dm_code_attrs_in, rfu_elements_xml, current_node_for_title)
        dm_code_attrs = dm_code_attrs_in # Assumes dm_code_attrs_in is already defaulted
        lang_code = (doc_attrs['lang'] || 'en').downcase; country_code = (doc_attrs['country-code'] || 'US').upcase
        issue_number = doc_attrs['issue-number'] || "001"; in_work_status = doc_attrs['in-work'] || "00"

        date_str = doc_attrs['revdate'] || doc_attrs['issue-date']
        date_str = date_str.strip if date_str
        year, month, day = "2025", "10", "01" # Default date
        if date_str && date_str.match?(/^\d{4}-\d{2}-\d{2}$/)
          year, month, day = date_str.split('-')
        elsif date_str && !date_str.empty?
          warn "asciidoctor: WARNING: Invalid date format: '#{date_str}'. Expected YYYY-MM-DD. Using default."
        elsif date_str.nil? || date_str.empty?
           # Use current date if nothing provided
           current_time = Time.now
           year = current_time.strftime('%Y')
           month = current_time.strftime('%m')
           day = current_time.strftime('%d')
        end

        tech_name = doc_attrs['tech-name'] || current_node_for_title.doctitle || "Default Technical Name" # Use current_node_for_title.doctitle
        dm_title_text = doc_attrs['dm-title'] || doc_attrs['infoName'] || tech_name # infoName is an S1000D term

        security_classification = doc_attrs['security-classification'] || "01"
        responsible_partner_company = doc_attrs['responsible-partner-company'] || "UNKNOWN"
        originator_enterprise = doc_attrs['originator-enterprise'] || responsible_partner_company
        brex_dm_code_attrs = brex_dm_code_attrs_in || { modelIdentCode: "S1000D", systemDiffCode: "H", systemCode: "04", subSystemCode: "1", subSubSystemCode: "0", assyCode: "0301", disassyCode: "00", disassyCodeVariant: "A", infoCode: "022", infoCodeVariant: "A", itemLocationCode: "D" }

        global_applic_conditions_xml = ""
        if @global_applic_eval_hash && @global_applic_eval_hash.is_a?(Hash)
            raw_conditions_xml = build_applic_condition_xml(@global_applic_eval_hash, 0)
            global_applic_conditions_xml = raw_conditions_xml.strip.gsub(/^/, '      ') unless raw_conditions_xml.strip.empty?
        else
            global_applic_conditions_xml = generate_flat_global_asserts_xml(doc_attrs)
            document_node_for_check = doc_attrs[:document_node]
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
        if !icn_ids.empty?
          doctype_parts << "<!NOTATION PNG SYSTEM \"PNG\">"
          icn_ids.each { |icn| doctype_parts << "<!ENTITY #{esc_text(icn)} SYSTEM \"#{esc_text(icn)}.png\" NDATA PNG>" }
        end
        declaration = '<!DOCTYPE dmodule'
        if !doctype_parts.empty?
          declaration << " [\n  #{doctype_parts.join("\n  ")}\n]>"
        else
          declaration << ">"
        end
        declaration
    end

    def get_schema_file(dm_type_str)
        case dm_type_str
        when 'procedure', 'procedural'; 'proced.xsd'
        when 'fault', 'faultisolation'; 'fault.xsd'
        when 'act', 'pct'; 'applicom.xsd' # Schema for ACT/PCT
        else 'descript.xsd'
        end
    end

    def node_has_global_applic_block(document_node)
        return false unless document_node && document_node.respond_to?(:blocks)
        document_node.blocks.any? { |b| b.role == 'global_applicability_definition' || b.style == 'global_applicability_definition' }
    end
    # --- END: Helper methods for convert_document ---

    def convert_document node
      # Reset instance variables for each document conversion
      @s1000d_applic_definitions, @s1000d_product_definitions, @s1000d_product_attribute_definitions = [], [], []
      @global_applic_eval_hash = nil

      doc_attrs = node.document.attributes
      doc_attrs[:document_node] = node # Make document node available to helpers (e.g., for node_has_global_applic_block)

      # DMC Parsing (from original, with default handling)
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
      dm_code_attrs ||= default_dmc_values # Ensure it's not nil

      # BREX DMC Parsing (from original, with default handling)
      brex_dmc_string = doc_attrs['brex-dmc']
      brex_dm_code_attrs = parse_dmc_string(brex_dmc_string)
      default_brex_dmc_attrs = { modelIdentCode: "S1000D", systemDiffCode: "H", systemCode: "04", subSystemCode: "1", subSubSystemCode: "0", assyCode: "0301", disassyCode: "00", disassyCodeVariant: "A", infoCode: "022", infoCodeVariant: "A", itemLocationCode: "D" }
      if brex_dmc_string && brex_dm_code_attrs.nil?
        warn "asciidoctor: WARNING: Invalid BREX DMC: '#{brex_dmc_string}' in document header. Using default."
        brex_dm_code_attrs = default_brex_dmc_attrs
      elsif brex_dm_code_attrs.nil?
        warn "asciidoctor: WARNING: No BREX DMC attribute provided. Using default BREX."
        brex_dm_code_attrs = default_brex_dmc_attrs
      end
      brex_dm_code_attrs ||= default_brex_dmc_attrs

      # ACT/PCT related attributes
      s1000d_global_applic_text = (doc_attrs['s1000d-applic-text'] || doc_attrs['applicability'] || "All").strip # 'applicability' from original for fallback
      act_dmc_string = doc_attrs['act-dmc']; act_dm_ref_for_dmstatus = ""
      if act_dmc_string && !act_dmc_string.strip.empty?
        act_dm_c = parse_dmc_string(act_dmc_string)
        if act_dm_c
          act_dm_ref_for_dmstatus = "<applicCrossRefTableRef><dmRef><dmRefIdent><dmCode modelIdentCode=\"#{act_dm_c[:modelIdentCode]}\" systemDiffCode=\"#{act_dm_c[:systemDiffCode]}\" systemCode=\"#{act_dm_c[:systemCode]}\" subSystemCode=\"#{act_dm_c[:subSystemCode]}\" subSubSystemCode=\"#{act_dm_c[:subSubSystemCode]}\" assyCode=\"#{act_dm_c[:assyCode]}\" disassyCode=\"#{act_dm_c[:disassyCode]}\" disassyCodeVariant=\"#{act_dm_c[:disassyCodeVariant]}\" infoCode=\"#{act_dm_c[:infoCode]}\" infoCodeVariant=\"#{act_dm_c[:infoCodeVariant]}\" itemLocationCode=\"#{act_dm_c[:itemLocationCode]}\"/></dmRefIdent></dmRef></applicCrossRefTableRef>".strip
        else
          warn "asciidoctor: WARNING: Invalid ACT DMC '#{act_dmc_string}' provided. <applicCrossRefTableRef> will not be generated in <dmStatus>."
        end
      end

      # Reason For Update (RFU) (from original)
      rfu_text_raw = doc_attrs['reason-for-update']
      rfu_elements = if rfu_text_raw && !rfu_text_raw.strip.empty?
        %(\n<reasonForUpdate id="rfu-0001" updateHighlight="1" updateReasonType="urt02"><simplePara>#{esc_text(rfu_text_raw)}</simplePara></reasonForUpdate>)
      else
        %(\n<reasonForUpdate id="rfu-0001" updateHighlight="1" updateReasonType="urt02"><simplePara>Initial issue or generic update.</simplePara></reasonForUpdate>)
      end

      dm_type = (doc_attrs['dm-type'] || 'descript').downcase.strip

      # FIRST PASS: Convert all top-level blocks.
      # This allows convert_literal, convert_paragraph, etc., to populate definition instance variables.
      # These specialized converters should return "" to prevent duplicate output.
      node.blocks.each { |b| b.convert }

      # Build XML parts from collected definitions
      pal_xml = @s1000d_product_attribute_definitions.empty? ? "" : "<productAttributeList>\n#{@s1000d_product_attribute_definitions.map { |pa| pa.gsub(/^/, '  ') }.join("\n")}\n</productAttributeList>"

      pct_dm_ref_xml = ""
      if dm_type == 'act' # PCT DM ref is only relevant for an ACT DM
        pct_dmc_str = doc_attrs['pct-dmc']
        if pct_dmc_str && !pct_dmc_str.strip.empty?
          pct_dm_c = parse_dmc_string(pct_dmc_str)
          if pct_dm_c
            pct_dm_ref_xml = "<productCrossRefTableRef><dmRef><dmRefIdent><dmCode modelIdentCode=\"#{pct_dm_c[:modelIdentCode]}\" systemDiffCode=\"#{pct_dm_c[:systemDiffCode]}\" systemCode=\"#{pct_dm_c[:systemCode]}\" subSystemCode=\"#{pct_dm_c[:subSystemCode]}\" subSubSystemCode=\"#{pct_dm_c[:subSubSystemCode]}\" assyCode=\"#{pct_dm_c[:assyCode]}\" disassyCode=\"#{pct_dm_c[:disassyCode]}\" disassyCodeVariant=\"#{pct_dm_c[:disassyCodeVariant]}\" infoCode=\"#{pct_dm_c[:infoCode]}\" infoCodeVariant=\"#{pct_dm_c[:infoCodeVariant]}\" itemLocationCode=\"#{pct_dm_c[:itemLocationCode]}\"/></dmRefIdent></dmRef></productCrossRefTableRef>".strip
          else
            warn "asciidoctor: WARNING: Invalid PCT DMC '#{pct_dmc_str}' provided for ACT DM. <productCrossRefTableRef> will not be generated."
          end
        end
      end

      internal_pct_xml = @s1000d_product_definitions.empty? ? "" : "<productCrossRefTable>\n#{@s1000d_product_definitions.map { |p| p.gsub(/^/, '  ') }.join("\n")}\n</productCrossRefTable>"
      if internal_pct_xml.empty? && ['act', 'pct'].include?(dm_type)
        warn "asciidoctor: INFO: dm-type '#{dm_type}', no '.productdef' blocks found. Internal <productCrossRefTable> will be empty or omitted."
      end

      act_outer_xml = ""
      if dm_type == 'act'
        act_children = [pal_xml, internal_pct_xml, pct_dm_ref_xml].map(&:strip).reject(&:empty?)
        unless act_children.empty?
          act_outer_xml = "<applicCrossRefTable>\n#{act_children.map{|c| c.gsub(/^/,'  ')}.join("\n")}\n</applicCrossRefTable>"
        else
          warn "asciidoctor: INFO: dm-type 'act', but no content found for <productAttributeList>, internal <productCrossRefTable>, or <productCrossRefTableRef>. Omitting <applicCrossRefTable>."
        end
      end

      rag_xml = @s1000d_applic_definitions.empty? ? "" : "<referencedApplicGroup>\n#{@s1000d_applic_definitions.map { |a| a.gsub(/^/, '  ') }.join("\n")}\n</referencedApplicGroup>"

      # SECOND PASS: Process general content, skipping definition blocks already handled.
      general_content_processed = ""
      node.blocks.each do |block|
        # Check role and style for definition blocks
        is_definition_block = ['applicdef', 'productdef', 'attribute_def', 'global_applicability_definition'].include?(block.role)
        is_definition_block ||= ['applicdef', 'productdef', 'attribute_def', 'global_applicability_definition'].include?(block.style) if !is_definition_block && block.respond_to?(:style)


        unless is_definition_block
            conversion_result = block.convert # This will call the respective convert_ methods
            general_content_processed << conversion_result if conversion_result.is_a?(String) && !conversion_result.empty?
        end
      end
      general_content_processed.strip!


      # Determine main DM content based on dm-type
      main_dm_content = ""
      case dm_type
      when 'procedure', 'procedural'
        prelim_reqs_markup = generate_preliminary_requirements_xml(node)
        main_procedure_markup = generate_main_procedure_steps_xml(node)
        close_reqs_markup = generate_close_requirements_xml(node)
        main_dm_content = <<~XML_PROCEDURE_CONTENT
          <procedure>
            #{prelim_reqs_markup}
            <mainProcedure>
            #{main_procedure_markup}
            </mainProcedure>
            #{close_reqs_markup}
          </procedure>
        XML_PROCEDURE_CONTENT
      when 'fault', 'faultisolation'
        # Fault description can be authored as general content before the fault isolation section
        # For now, using the general_content_processed for the <faultDescr>
        # This might need a dedicated section detection in future.
        fault_descr_xml = if !general_content_processed.empty?
                            "<faultDescr>\n#{general_content_processed.gsub(/^/, '  ')}\n</faultDescr>"
                          else
                            "<faultDescr><para>Fault description placeholder. Author this in AsciiDoc.</para></faultDescr>"
                          end
        prelim_reqs_markup = generate_preliminary_requirements_xml(node)
        fault_iso_main_markup = generate_fault_isolation_main_procedure_xml(node)
        close_reqs_markup = generate_close_requirements_xml(node)
        main_dm_content = <<~XML_FAULT_CONTENT
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
      when 'act'
        # For ACT, general_content_processed is typically for <descr> if any.
        # The main content is act_outer_xml (<applicCrossRefTable>)
        main_dm_content << "<description>\n#{general_content_processed.gsub(/^/, '  ')}\n</description>\n" unless general_content_processed.empty?
        main_dm_content << act_outer_xml unless act_outer_xml.empty?
      when 'pct'
        # For PCT, general_content_processed is for <descr> if any.
        # The main content is internal_pct_xml (<productCrossRefTable>)
        main_dm_content << "<description>\n#{general_content_processed.gsub(/^/, '  ')}\n</description>\n" unless general_content_processed.empty?
        main_dm_content << internal_pct_xml unless internal_pct_xml.empty?
      when 'descript', 'description'
        # general_content_processed already contains the converted blocks
        main_dm_content = "<description>\n#{general_content_processed}\n</description>"
      else
        warn "asciidoctor: WARNING: Unknown dm-type '#{dm_type}'. Defaulting to descriptive content."
        main_dm_content = "<description>\n#{general_content_processed}\n</description>"
      end

      # Assemble final content section, RAG is usually at the top for non-ACT/PCT
      final_content_parts = []
      if !rag_xml.empty? && !['act', 'pct'].include?(dm_type)
        final_content_parts << rag_xml.strip
      end
      final_content_parts << main_dm_content.strip unless main_dm_content.strip.empty?
      final_content_xml = final_content_parts.join("\n")

      # Build IdentAndStatusSection
      # Pass `node` itself for `current_node_for_title.doctitle`
      ident_status_section = build_ident_and_status_section_xml(
        doc_attrs, dm_code_attrs, act_dm_ref_for_dmstatus,
        s1000d_global_applic_text, brex_dm_code_attrs, rfu_elements, node
      )

      doctype_decl = build_doctype_declaration(final_content_xml) # Use final_content_xml for ICN scanning
      schema = get_schema_file(dm_type)

      result = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
       #{doctype_decl}
      <dmodule xmlns:dc="http://www.purl.org/dc/elements/1.1/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.s1000d.org/S1000D_6/xml_schema_flat/#{schema}">
      #{ident_status_section.gsub(/^/, '  ')}
        <content>
          #{final_content_xml.empty? ? "<noContent/>" : final_content_xml.strip.gsub(/^/, '    ')}
        </content>
      </dmodule>
      XML
      result.chomp.gsub(/^\s+$/, '') # Clean up trailing whitespace/empty lines
    end

    # ==========================================================================
    # Standard Block and Inline Converters (Modified to handle roles & applicRefId)
    # ==========================================================================
    def convert_paragraph(node)
      if node.role == 'applicdef'; process_as_applic_definition(node); return ""
      elsif node.role == 'productdef'; process_as_product_definition(node); return ""
      elsif node.role == 'attribute_def'
        warn "asciidoctor: WARNING: '.attribute_def' on para '#{node.id}'. Attributes (id,name,descr) processed, but enumerations need an open block with ulist or a ulist with this role."
        process_as_product_attribute_definition(node); return ""
      end
      # Ensure content is not nil before calling esc_text or other methods on it.
      # node.content calls convert recursively on child blocks if any.
      content = node.content
      return "" if content.nil? || (content.is_a?(String) && content.empty? && !node.text?) # Avoid empty <para></para> for truly empty source paragraphs
      %(<para#{common_attributes(node.id)}#{applic_ref_attribute(node)}>#{content}</para>)
    end

    def convert_open(node) # For blocks like -- --, ====, ****
      if node.role == 'applicdef'; process_as_applic_definition(node); return ""
      elsif node.role == 'productdef'; process_as_product_definition(node); return ""
      elsif node.role == 'attribute_def'; process_as_product_attribute_definition(node); return ""
      end
      content = node.content; return "" if content.nil? || (content.is_a?(String) && content.empty?)
      # Default for other open blocks (e.g., example, sidebar if not styled further)
      # S1000D doesn't have a direct equivalent for a generic open block.
      # Mapping to <levelledPara> or just its content might be options.
      # For now, let's wrap its content, similar to how a section's content is handled.
      # If it has a title, it could be a <levelledPara>.
      if node.title?
        %(<levelledPara#{common_attributes(node.id)}#{applic_ref_attribute(node)}><title>#{esc_text(node.title)}</title>#{content}</levelledPara>)
      else
        # If no title, just output the content, assuming it will be wrapped by a parent element correctly.
        # Or, wrap in a <para> if it's simple text content.
        # node.content already produces wrapped elements like <para> for its children.
        # So, if an open block is just a container, its content is what matters.
        # Let's ensure it's wrapped if it doesn't produce its own S1000D block elements.
        # This part is tricky. For now, treat as a simple para wrapper if no title.
        %(<para#{common_attributes(node.id)}#{applic_ref_attribute(node)}>#{content}</para>)
      end
    end

    def convert_ulist(node)
        if node.role == 'attribute_def'
            process_as_product_attribute_definition(node); return ""
        end
        list_attributes = common_attributes(node.id) + applic_ref_attribute(node)
        result = %(<para><randomList#{list_attributes}>) # S1000D usually wraps lists in para
        node.items.each do |item|
            item_id_attr = common_attributes(item.id)
            item_applic_attr = applic_ref_attribute(item)
            # item.content calls convert on child blocks if item has blocks,
            # otherwise item.text for simple text.
            inner_content = item.blocks? ? item.content : "<para#{common_attributes(nil)}#{applic_ref_attribute(item)}>#{esc_text(item.text)}</para>" # Ensure simple text is also wrapped and can carry applic_ref from item
            result << %(<listItem#{item_id_attr}#{item_applic_attr}>#{inner_content}</listItem>)
        end
        result << %(</randomList></para>)
        result
    end

    def convert_olist(node)
        list_attributes = common_attributes(node.id) + applic_ref_attribute(node)
        # Check if this olist is part of a proceduralStep generation, in which case it might be handled differently.
        # However, a generic olist should convert to <sequentialList>.
        # Procedural steps are typically generated by generate_main_procedure_steps_xml.
        result = %(<para><sequentialList#{list_attributes}>) # S1000D usually wraps lists in para
        node.items.each_with_index do |item, idx| # Added index for potential sub-step ID
            item_id_attr = common_attributes(item.id || "#{node.id || 'seqlist'}-item-#{idx}")
            item_applic_attr = applic_ref_attribute(item)
            inner_content = item.blocks? ? item.content : "<para#{common_attributes(nil)}#{applic_ref_attribute(item)}>#{esc_text(item.text)}</para>"
            result << %(<listItem#{item_id_attr}#{item_applic_attr}>#{inner_content}</listItem>)
        end
        result << %(</sequentialList></para>)
        result
    end

    def convert_dlist(node)
        dl_attributes = common_attributes(node.id) + applic_ref_attribute(node)
        result = %(<para><definitionList#{dl_attributes}>) # S1000D wraps lists
        node.items.each do |terms_nodes, dd_node|
            # Assuming terms_nodes is an array of DtNode, and dd_node is a DdNode
            # S1000D <definitionListItem> does not have its own ID/applicRefId by default.
            # These would apply to the whole list or specific terms/definitions if schema allowed.
            result << %(<definitionListItem>) # Removed item_id_attr and item_applic_attr from here
            result << %(<listItemTerm>)
            terms_nodes.each { |dt| result << esc_text(dt.text) } # dt.text is raw text
            result << %(</listItemTerm>)
            result << %(<listItemDefinition>)
            if dd_node
              # dd_node.content will convert blocks within the definition.
              # If it's simple text, dd_node.text.
              # The applicRefId should be on the list or term/def if supported, here it's on the overall list.
              dd_content = dd_node.blocks? ? dd_node.content : (dd_node.text? ? "<para>#{esc_text(dd_node.text)}</para>" : "<para/>")
              result << dd_content
            else
              result << %(<para/>) # Empty definition
            end
            result << %(</listItemDefinition>)
            result << %(</definitionListItem>) # S1000D schema error in original: was </definitionListItem></definitionListItem>
        end
        result << %(</definitionList></para>)
        result
    end


    def convert_literal(node) # Handles `....` blocks (verbatim)
      if node.role == 'global_applicability_definition' || node.style == 'global_applicability_definition'
        if node.style == 'global_applicability_definition' && node.role != 'global_applicability_definition'
            warn "asciidoctor: INFO: Using style='global_applicability_definition' for literal block '#{node.id}'. Prefer role '[.global_applicability_definition]'."
        end
        json_string = node.content
        begin
          parsed_json = JSON.parse(json_string)
          if parsed_json.is_a?(Hash)
            @global_applic_eval_hash = parsed_json
          else
            warn "asciidoctor: WARNING: JSON in 'global_applicability_definition' block did not parse into a Hash. Parsed as: #{parsed_json.class}"
            @global_applic_eval_hash = nil
          end
        rescue JSON::ParserError => e
          warn "asciidoctor: WARNING: Failed to parse JSON from 'global_applicability_definition' literal block: #{e.message}"
          @global_applic_eval_hash = nil
        end
        return "" # Consume the block
      end

      # Standard literal block conversion
      para_attributes = common_attributes(node.id) + applic_ref_attribute(node)
      %(<para#{para_attributes}><verbatimText>#{esc_text(node.content)}</verbatimText></para>)
    end

    def convert_listing(node) # Handles ---- blocks (source code)
      # S1000D typically uses <figure><graphic><verbatimText> for listings
      figure_attributes = common_attributes(node.id) + applic_ref_attribute(node)
      result = %(<figure#{figure_attributes}>)
      result << %(<title>#{esc_text(node.title)}</title>) if node.title?
      # Using CDATA for listing content to preserve special characters
      result << %(<graphic><verbatimText><![CDATA[#{node.content}]]></verbatimText></graphic>)
      result << %(</figure>)
      result
    end


    def convert_section(node)
      # Sections are often containers in AsciiDoc. In S1000D, they might map to <levelledPara>
      # or specific S1000D structures if titled appropriately (handled by generate_..._xml methods).
      # This is a generic conversion for a section not caught by those.
      levelled_para_attrs = common_attributes(node.id) + applic_ref_attribute(node)
      %(<levelledPara#{levelled_para_attrs}><title>#{esc_text(node.title)}</title>#{node.content}</levelledPara>)
    end

    def convert_inline_anchor(node)
      case node.type
      when :xref
        target = node.attributes['refid'] || node.target
        target = target[1..-1] if target.start_with?('#') # Clean leading #
        # Determine internalRefTargetType based on the target node if possible
        target_node = node.document.catalog[:ids][target]
        target_type_attr = determine_internal_ref_target_type(target_node, target)
        # S1000D internalRef does not have ID or applicRefId itself. Node.text is the display text.
        %(<internalRef internalRefId="#{esc_text(target)}"#{target_type_attr}>#{esc_text(node.text || target)}</internalRef>)
      when :link # External link
        %(<externalRef destination="#{esc_text(node.target)}">#{esc_text(node.text)}</externalRef>)
      when :ref # bibliography anchor
        '' # S1000D doesn't have a direct equivalent, often handled by specific referencing mechanisms.
      else # E.g. :bibref
        warn "asciidoctor: WARNING: Unsupported inline anchor type: #{node.type}. Text: '#{node.text}'"
        esc_text(node.text || node.target) # Fallback to text
      end
    end

    def convert_table(node)
      table_attributes = common_attributes(node.id) + applic_ref_attribute(node)
      pgwide = (node.option? 'pgwide') ? 1 : 0
      frame = node.attr 'frame', 'all' # S1000D frames: top, bottom, topbot, all, sides, none
      # S1000D grid: rowsep, colsep (0 or 1)
      grid = node.attr 'grid', 'all'
      rowsep = (grid == 'none' || grid == 'cols') ? 0 : 1
      colsep = (grid == 'none' || grid == 'rows') ? 0 : 1
      orient = (node.attr? 'orientation', 'landscape') ? 'land' : 'port' # S1000D uses land/port

      result = %(<table#{table_attributes} frame="#{frame}" pgwide="#{pgwide}" rowsep="#{rowsep}" colsep="#{colsep}" orient="#{orient}">)
      result << %(<title>#{esc_text(node.title)}</title>) if node.title?
      result << %(<tgroup cols="#{node.attr 'colcount'}">)
      node.columns.each do |col|
        # S1000D colspec: colname is mandatory. colwidth can be proportional (1*) or fixed (e.g., "10mm")
        colwidth_attr = (col.attr 'width') ? %( colwidth="#{col.attr 'width'}*") : "" # Assuming % means proportional
        result << %(<colspec colname="col_#{col.attr 'colnumber'}"#{colwidth_attr}/>)
      end

      [:head, :foot, :body].each do |tsec_name|
        rows = node.rows.send(tsec_name) # Get rows for :head, :foot, :body
        next if rows.empty?
        result << %(<t#{tsec_name}>) # <thead/>, <tfoot/>, <tbody/>
        rows.each do |row|
          # S1000D <row> does not have ID or applicRefId. Attributes are on <entry>.
          result << %(<row>)
          row.each do |cell|
            # Cell attributes for S1000D <entry>
            entry_attrs = ""
            entry_attrs << %( halign="#{cell.attr 'halign'}") if cell.attr? 'halign' # left, right, center, justify, char
            entry_attrs << %( valign="#{cell.attr 'valign'}") if cell.attr? 'valign' # top, middle, bottom
            if cell.colspan && cell.colspan > 1
              entry_attrs << %( namest="col_#{cell.column.attr 'colnumber'}" nameend="col_#{cell.column.attr('colnumber') + cell.colspan - 1}")
            end
            entry_attrs << %( morerows="#{cell.rowspan - 1}") if cell.rowspan && cell.rowspan > 1
            # Add ID and applic_ref from cell to the <entry>
            entry_attrs << common_attributes(cell.id)
            entry_attrs << applic_ref_attribute(cell)


            cell_body = case cell.style
                        when :asciidoc then cell.content # Recursively convert AsciiDoc content in cell
                        when :literal then %(<para><verbatimText>#{esc_text(cell.text)}</verbatimText></para>)
                        else cell.text.empty? ? '' : %(<para>#{esc_text(cell.text)}</para>) # Default to para
                        end
            cell_body = "<para/>" if cell_body.to_s.strip.empty? # Ensure entry is not completely empty if source was empty

            result << %(<entry#{entry_attrs}>#{cell_body}</entry>)
          end
          result << %(</row>)
        end
        result << %(</t#{tsec_name}>)
      end
      result << %(</tgroup></table>)
      result
    end

    alias convert_embedded content_only # E.g., for passthrough content

    def convert_image(node)
      figure_attributes = common_attributes(node.id) + applic_ref_attribute(node)
      title_el = node.title ? "<title>#{esc_text(node.title)}</title>" : ""
      icn = node.attr('icn')
      if icn.nil? || icn.empty?
        base_name = File.basename(node.attr('target', 'unknown.png'), '.*')
        if base_name.match?(/^ICN(-[A-Z0-9]+){2,}$/i) # Check if filename looks like an ICN
            icn = base_name.upcase
            warn "asciidoctor: INFO: Image target '#{node.attr('target')}' - inferred ICN '#{icn}' from filename. Consider using the 'icn' attribute for clarity (e.g., image::path.png[alt, icn=#{icn}])."
        else
            icn_fallback_source = node.attr('alt') || base_name
            # Create a somewhat unique FIG identifier if not an ICN
            icn = "FIG-#{icn_fallback_source.gsub(/[^A-Za-z0-9\-]/, '').upcase}"
            warn "asciidoctor: WARNING: Image target '#{node.attr('target')}' - no 'icn' attribute provided and filename not ICN-like. Using generated infoEntityIdent: #{icn}. Please provide a proper ICN via the 'icn' attribute for S1000D compliance."
        end
      end
      icn_ident = esc_text(icn)
      %(<figure#{figure_attributes}>
        #{title_el}
        <graphic infoEntityIdent="#{icn_ident}"/>
      </figure>)
    end

    def convert_inline_quoted(node)
        open_tag, close_tag = QUOTE_TAGS[node.type]
        # For inline elements, ID and applic_ref are usually not standard S1000D attributes.
        # However, if needed, they could be added if the schema supports it (e.g. for <emphasis id="...">).
        # For now, using common_attributes which just adds 'id'. Applicability is often on the containing block.
        attrs = common_attributes(node.id) # applic_ref_attribute(node) might be too much for simple emphasis/strong
        final_open_tag = open_tag
        if attrs && !attrs.empty? && open_tag.include?('>')
           final_open_tag = open_tag.sub('>', "#{attrs}>")
        end
        %(#{final_open_tag}#{esc_text(node.text)}#{close_tag})
    end

    def convert_admonition(node)
        admonition_attributes = common_attributes(node.id) + applic_ref_attribute(node)
        type = node.attr('name').upcase # WARNING, CAUTION, NOTE
        # node.content handles complex content within admonitions (e.g., lists, paragraphs)
        # node.source is the raw text if no blocks.
        inner_content = if node.blocks?
                          node.content
                        else
                          # If it's simple text, it needs to be wrapped in S1000D para equivalent
                          "#{esc_text(node.source)}" # This needs to be wrapped appropriately by the specific admonition type
                        end

        case type
        when 'WARNING'
          # <warningAndCautionPara> is the typical S1000D wrapper for text content in warnings/cautions
          para_content = node.blocks? ? inner_content : "<warningAndCautionPara>#{inner_content}</warningAndCautionPara>"
          %(<warning#{admonition_attributes}>#{para_content}</warning>)
        when 'CAUTION'
          para_content = node.blocks? ? inner_content : "<warningAndCautionPara>#{inner_content}</warningAndCautionPara>"
          %(<caution#{admonition_attributes}>#{para_content}</caution>)
        when 'NOTE'
          # <notePara> for notes
          para_content = node.blocks? ? inner_content : "<notePara>#{inner_content}</notePara>"
          %(<note#{admonition_attributes}>#{para_content}</note>)
        when 'TIP', 'IMPORTANT' # S1000D doesn't have TIP or IMPORTANT, map to NOTE
          warn "asciidoctor: INFO: Admonition type '#{type}' mapped to standard S1000D <note>."
          para_content = node.blocks? ? inner_content : "<notePara>#{inner_content}</notePara>"
          %(<note#{admonition_attributes}>#{para_content}</note>)
        else # Unknown admonition type
          warn "asciidoctor: WARNING: Unknown admonition type '#{type}' mapped to generic S1000D <note>."
          para_content = node.blocks? ? inner_content : "<notePara>#{inner_content}</notePara>"
          %(<note#{admonition_attributes}>#{para_content}</note>)
        end
    end

    def convert_thematic_break(node)
      # Thematic breaks (---, ***, ___) usually don't map directly to S1000D content elements.
      # They might signify a change in section or topic, handled by structure.
      '' # Return empty string, effectively ignoring them.
    end

    def convert_inline_image(node)
        target = node.target
        icn_base = File.basename(target, '.*')
        # Try to get ICN from 'icn' attribute, then 'alt', then generate from filename
        icn = node.attr('icn') || node.attr('alt')
        if icn.nil? || icn.to_s.strip.empty?
            icn = "ICN-INLINE-#{icn_base.gsub(/[^A-Za-z0-9\-]/, '').upcase}"
            warn "asciidoctor: INFO: Inline image '#{target}' missing 'icn' or 'alt'. Generated ICN: #{icn}."
        elsif !icn.match?(/^ICN(-[A-Z0-9]+){2,}$/i) && !icn.match?(/^FIG-/i) # If 'alt' was used but not ICN-like
             warn "asciidoctor: INFO: Inline image '#{target}' using alt text '#{icn}' as infoEntityIdent. Consider providing a proper ICN."
        end

        # S1000D <graphic> is typically within <figure>. True inline graphics might be <symbol>.
        # For simplicity, converting to <graphic> and warning.
        warn "asciidoctor: INFO: Inline image converted to <graphic infoEntityIdent=\"#{esc_text(icn)}\"/>. True inline placement depends on S1000D context and may require <symbol> or specific styling."
        %Q{<graphic infoEntityIdent="#{esc_text(icn)}"/>}
    end


    def convert_fallback(node)
      warn %(asciidoctor: WARNING: S1000D converter missing handler for node type: #{node.node_name}. Content will be skipped or may cause errors.)
      # Return empty string or node.content based on whether unhandled content should appear.
      # node.content if node.respond_to? :content # This might output raw AsciiDoc or partially converted.
      "" # Safer to output nothing for unhandled node types.
    end

  end
end