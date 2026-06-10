# Devloped By Prathamesh Naik
# This code is a Ruby script that defines a custom Asciidoctor converter for S1000D XML documents.
# This is Licenced under the Apache License, Version 2.0

require 'asciidoctor'
require 'asciidoctor/helpers' 

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
    end

    def common_attributes id
      id ? %( id="#{id}") : ''
    end

    def esc_text(text)
      return '' if text.nil?
      text.to_s
          .gsub('&', '&')
          .gsub('<', '<')
          .gsub('>', '>')
          .gsub('', '')
          # .gsub("'", ''') # Optional: apostrophe if needed for attribute values in single quotes
    end
    

    def esc_content(text_or_content)
      return '' if text_or_content.nil?
      return text_or_content unless text_or_content.is_a?(String)
      text_or_content.to_s.gsub('&', '&').gsub('<', '<').gsub('>', '>').gsub('"', '"')
    end

    def parse_dmc_string(dmc_string)
      return nil unless dmc_string && dmc_string.is_a?(String) && !dmc_string.strip.empty?
      stripped_dmc = dmc_string.strip
      regex = /^(?:DMC-)?([A-Z0-9]{2,17})-([A-Z0-9]{1})-([A-Z0-9]{2,4})-([A-Z0-9]{1,2})-([A-Z0-9]{1,2})-([A-Z0-9]{2,4})-([A-Z0-9]{2})-([A-Z0-9]{1,4})-([A-Z0-9]{3})-([A-Z0-9]{1})-([A-Z0-9]{1})$/i
      match = regex.match(stripped_dmc)
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
          warn "asciidoctor: WARNING (parse_dmc_string): Regex DID NOT MATCH for 11-part DMC input '#{stripped_dmc}'. Ensure DMC is 11 parts and conforms to S1000D structure. Check for invalid characters or incorrect segment lengths."
          return nil
      end
    end

    # ***** REVISED generate_req_cond_group_xml and its helper *****
    def generate_req_cond_group_xml(section_node, for_closeout = false)
      return "<reqCondGroup><noConds/></reqCondGroup>" unless section_node
      
      conditions_xml_elements = []
      has_actual_conditions = false

      section_node.blocks.each_with_index do |block, idx|
        case block.context
        when :paragraph
          # Check if this paragraph is primarily an xref target and has minimal other text.
          # This is a heuristic to reduce warnings for simple xref target paragraphs.
          is_likely_xref_target_only = block.id && 
                                       section_node.document.references[:ids].key?(block.id) && 
                                       block.source.lines.count <= 2 && # e.g., the ID line and one short line of text
                                       block.source.downcase.include?(block.id.downcase) # text mentions its own ID

          unless is_likely_xref_target_only
            warn "asciidoctor: WARNING: Paragraph found directly in '#{section_node.title}' section: '#{block.source.lines.first.strip[0,70]}...'. This paragraph will be SKIPPED for S1000D <reqCondGroup> generation. Place such text outside the specific list of conditions or ensure it's part of a list item."
          end
          # Paragraphs are skipped from being direct children of reqCondGroup

        when :ulist, :olist
          has_actual_conditions = true 
          block.items.each do |item|
            item_text_content = item.text 
            dm_ref_attr_val = item.attr('dmref')
            
            cleaned_text_for_req_cond_para = item_text_content
                .gsub(/\[dmref=.*?\]/, '') 
                .strip 
            req_cond_inner_xml = item.blocks? ? item.content : "#{esc_text(cleaned_text_for_req_cond_para)}"

            if dm_ref_attr_val
              dm_ref_xml_part = ""
              parsed_dm_ref_code = parse_dmc_string(dm_ref_attr_val)
              if parsed_dm_ref_code
                dm_code_attrs_xml = parsed_dm_ref_code.map { |k, v| %(#{k}="#{esc_text(v)}") }.join(' ')
                dm_ref_xml_part = "<dmRef><dmRefIdent><dmCode #{dm_code_attrs_xml}/></dmRefIdent></dmRef>"
                conditions_xml_elements << "<reqCondDm#{common_attributes item.id}><reqCond>#{req_cond_inner_xml}</reqCond>#{dm_ref_xml_part}</reqCondDm>"
              else
                warn "asciidoctor: WARNING: Invalid dmref attribute '#{dm_ref_attr_val}' in Required Conditions for item '#{item_text_content}'. Treating as reqCondNoRef."
                internal_ref_xml_parts = []
                item_text_content.scan(/<<([^>]+)>>/) do |match|
                  target_id = match[0]
                  target_node = section_node.document.catalog[:ids][target_id]
                  target_type_attr = determine_internal_ref_target_type(target_node, target_id)
                  internal_ref_xml_parts << "<internalRef internalRefId=\"#{esc_text(target_id)}\"#{target_type_attr}/>"
                end
                conditions_xml_elements << "<reqCondNoRef#{common_attributes item.id}><reqCond>#{req_cond_inner_xml}</reqCond>#{internal_ref_xml_parts.join("\n")}</reqCondNoRef>"
              end
            else
              internal_ref_xml_parts = []
              item_text_content.scan(/<<([^>]+)>>/) do |match|
                target_id = match[0]
                target_node = section_node.document.catalog[:ids][target_id]
                target_type_attr = determine_internal_ref_target_type(target_node, target_id)
                internal_ref_xml_parts << "<internalRef internalRefId=\"#{esc_text(target_id)}\"#{target_type_attr}/>"
              end
              conditions_xml_elements << "<reqCondNoRef#{common_attributes item.id}><reqCond>#{req_cond_inner_xml}</reqCond>#{internal_ref_xml_parts.join("\n")}</reqCondNoRef>"
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
          unless block.context == :thematic_break # Thematic breaks are fine, handled by convert_thematic_break
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

            # 1. Prioritize the 'dmc' attribute from the list item
            dmc_attr_value = item.attr('dmc')
            if dmc_attr_value && !dmc_attr_value.strip.empty?
              dmc_to_parse = dmc_attr_value.strip
            else
              # 2. No 'dmc' attribute, or it's empty. Try to extract from item.text.
              raw_item_text = item.text.to_s.strip

              if raw_item_text.downcase.match?(/(no|none)\s+(required\s+)?tech(nical)?\s+info(rmation)?/i)
                found_explicit_no_info = true
                break # Stop processing items in this list
              end

              # Try to find a DMC pattern anywhere in the raw_item_text,
              # giving preference to one at the beginning.
              # This regex captures a full 11-part DMC.
              dmc_regex = /(DMC-(?:[A-Z0-9]{2,17}-){9}[A-Z0-9]{2,4}-[A-Z0-9]{2}-[A-Z0-9]{1,4}-[A-Z0-9]{3}-[A-Z0-9]{1}-[A-Z0-9]{1}|(?:[A-Z0-9]{2,17}-){10}[A-Z0-9]{1})/i
              
              # Corrected DMC regex for parse_dmc_string:
              # (?:[A-Z0-9]{2,17})-([A-Z0-9]{1})-([A-Z0-9]{2,4})-([A-Z0-9]{1,2})-([A-Z0-9]{1,2})-([A-Z0-9]{2,4})-([A-Z0-9]{2})-([A-Z0-9]{1,4})-([A-Z0-9]{3})-([A-Z0-9]{1})-([A-Z0-9]{1})

              # Let's use the same regex structure as parse_dmc_string for pre-filtering
              # This regex looks for a sequence that matches the structure of a DMC
              # It's simplified here for matching, parse_dmc_string does the full capture.
              # Grouping for the 10 hyphens and then the final part.
              dmc_candidate_regex = /((?:DMC-)?(?:[A-Z0-9]+-){10}[A-Z0-9]+)/i
              
              match_data = dmc_candidate_regex.match(raw_item_text)

              if match_data && match_data[1]
                # We found something that looks like a DMC pattern
                potential_dmc_from_text = match_data[1]
                # Further check if this candidate passes the more stringent parse_dmc_string regex format
                # by attempting to parse it. If parse_dmc_string returns nil, it's not a valid DMC.
                if parse_dmc_string(potential_dmc_from_text) # Test parse
                   dmc_to_parse = potential_dmc_from_text
                else
                  # It looked like a DMC but didn't parse fully.
                  # This path might be hit if the initial regex is too loose.
                  # For the warnings you saw, the issue was more about item.text containing non-DMC chars.
                  if !raw_item_text.empty?
                     warn "asciidoctor: INFO: Text '#{raw_item_text}' in 'Required Technical Information' contains a DMC-like pattern ('#{potential_dmc_from_text}') that did not fully parse. No 'dmc' attribute was found. Skipping item."
                  end
                  next
                end
              else
                # No DMC-like pattern found in the text
                if !raw_item_text.empty?
                  warn "asciidoctor: INFO: List item text '#{raw_item_text}' in 'Required Technical Information' does not appear to contain a valid DMC, and no 'dmc' attribute was found. Skipping item."
                end
                next # Skip this list item
              end
            end

            next if dmc_to_parse.nil? || dmc_to_parse.empty?

            category = item.attr('category', 'ti01')
            # Now, dmc_to_parse should be a clean string.
            # We call parse_dmc_string again to get the structured hash for attributes.
            parsed_dmc_hash = parse_dmc_string(dmc_to_parse)

            if parsed_dmc_hash
              dm_code_attrs_xml = parsed_dmc_hash.map { |k, v| %(#{k}="#{esc_text(v)}") }.join(' ')
              tech_info_entries << <<~TECH_INFO_ENTRY.strip
                <reqTechInfo reqTechInfoCategory="#{esc_text(category)}">
                  <dmRef>
                    <dmRefIdent>
                      <dmCode #{dm_code_attrs_xml}/>
                    </dmRefIdent>
                  </dmRef>
                </reqTechInfo>
              TECH_INFO_ENTRY
            else
              # This warning should ideally not be hit if the pre-check worked,
              # but kept for robustness.
              warn "asciidoctor: WARNING: Failed to parse '#{dmc_to_parse}' as a valid DMC in 'Required Technical Information' (should have been caught by pre-check). Skipping."
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
    # ***** END REVISED generate_req_cond_group_xml *****


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


    def esc_text(text)
      # Basic XML escaping, you might have a more robust one
      text.to_s.gsub('&', '&').gsub('<', '<').gsub('>', '>').gsub('"', '"').gsub("", '')
    end
    
    def generate_table_based_req_list(section_node, list_tag, group_tag, individual_item_tag, no_item_tag, cols_map)
      return "<#{list_tag}>#{no_item_tag}</#{list_tag}>" unless section_node
    
      table_node = section_node.blocks.find { |b| b.context == :table }
      if !table_node
        if section_node.blocks.length == 1 && section_node.blocks.first.context == :paragraph
          content = section_node.blocks.first.source.downcase
          # Adjusted the check for item_tag which is now group_tag
          # and individual_item_tag for more accuracy if needed, or a generic term like "item"
          if content.include?("no ") && (content.include?(individual_item_tag.downcase) || content.include?(list_tag.downcase.gsub(/^req|s$/,'')))
            return "<#{list_tag}>#{no_item_tag}</#{list_tag}>"
          end
        end
        return "<#{list_tag}>#{no_item_tag}</#{list_tag}>"
      end
    
      individual_item_xml_entries = [] # Stores <supportEquipDescr>, <supplyDescr>, etc.
    
      table_node.rows.body.each do |row_cells|
        name_text = row_cells[cols_map[:name]] ? esc_text(row_cells[cols_map[:name]].text.strip) : "N/A"
        mfr_code_text = (cols_map[:mfr] && row_cells[cols_map[:mfr]]) ? esc_text(row_cells[cols_map[:mfr]].text.strip) : ""
        part_no_text  = (cols_map[:pn] && row_cells[cols_map[:pn]])  ? esc_text(row_cells[cols_map[:pn]].text.strip)  : ""
        qty_text      = row_cells[cols_map[:qty]] ? esc_text(row_cells[cols_map[:qty]].text.strip) : "1"
        uom_code_text = (cols_map[:uom] && row_cells[cols_map[:uom]]) ? esc_text(row_cells[cols_map[:uom]].text.strip.upcase) : "EA"
    
        # The case now uses group_tag to determine the *content structure* of the individual_item_tag
        case group_tag # This was item_tag before, it defines the type of items we're creating
        when "supportEquipDescrGroup"
          individual_item_xml_entries << <<~ITEM
            <#{individual_item_tag}><catalogSeqNumberRef figureNumber="#{name_text}" item="#{mfr_code_text}"></catalogSeqNumberRef><reqQuantity>#{qty_text}</reqQuantity></#{individual_item_tag}>
          ITEM
        when "supplyDescrGroup"
          individual_item_xml_entries << <<~ITEM
            <#{individual_item_tag}><identNumber><manufacturerCode>#{mfr_code_text}</manufacturerCode><partAndSerialNumber>
                  <partNumber>#{part_no_text}</partNumber>
                </partAndSerialNumber></identNumber><reqQuantity unitOfMeasure="#{uom_code_text}">#{qty_text}</reqQuantity></#{individual_item_tag}>
           ITEM
        when "spareDescrGroup"
          individual_item_xml_entries << <<~ITEM
            <#{individual_item_tag}><catalogSeqNumberRef figureNumber="#{name_text}" item="#{mfr_code_text}"/><reqQuantity>#{qty_text}</reqQuantity></#{individual_item_tag}>
           ITEM
        end
      end
    
      if individual_item_xml_entries.empty?
        return "<#{list_tag}>#{no_item_tag}</#{list_tag}>"
      else
        # Join the individual items
        items_joined_xml = individual_item_xml_entries.join("\n")
        # Wrap them with the group_tag
        grouped_items_xml = "<#{group_tag}>\n#{items_joined_xml}\n</#{group_tag}>"
        # Wrap the group with the list_tag
        return "<#{list_tag}>\n#{grouped_items_xml}\n</#{list_tag}>"
      end
    end
    
    
    def generate_req_safety_xml(section_node) # Keep version that relies on :admonition context
      return "<reqSafety><noSafety/></reqSafety>" unless section_node
      safety_elements = []
      section_node.blocks.each do |block|
          if block.context == :admonition 
              safety_elements << block.convert 
          elsif block.context == :paragraph && !block.source.strip.empty?
              warn "asciidoctor: INFO: General paragraph in Safety Conditions: '#{block.source.lines.first.strip[0,50]}...'"
          elsif block.context == :ulist || block.context == :olist
              warn "asciidoctor: INFO: List in Safety Conditions."
              safety_elements << block.convert 
          else
              unless block.context == :thematic_break
                  warn "asciidoctor: WARNING: Unhandled block '#{block.context}' in Safety Conditions."
              end
          end
      end
      if safety_elements.empty?
        return "<reqSafety><noSafety/></reqSafety>"
      else
        return "<reqSafety><safetyRqmts>\n" + safety_elements.join("\n") + "\n</safetyRqmts></reqSafety>"
      end
  end
  def generate_preliminary_requirements_xml(document_node)
    prelim_section = document_node.blocks.find { |b| b.context == :section && (b.id == 'prelim_reqs' || b.title.downcase.include?('preliminary requirements')) }
    
    # Default XML parts
    req_conds_xml = "<reqCondGroup><noConds/></reqCondGroup>"
    req_persons_xml = "" # Default to empty, will be generated if section exists
    req_tech_info_xml = "<reqTechInfoGroup><noReqTechInfo/></reqTechInfoGroup>" # New default
    req_support_equip_xml = "<reqSupportEquips><noSupportEquips/></reqSupportEquips>"
    req_supplies_xml = "<reqSupplies><noSupplies/></reqSupplies>"
    req_spares_xml = "<reqSpares><noSpares/></reqSpares>"
    req_safety_xml = "<reqSafety><noSafety/></reqSafety>"

    if prelim_section
      prelim_section.blocks.each do |sub_block|
        next unless sub_block.context == :section # Process only subsections
        
        id_or_title = sub_block.id ? sub_block.id.downcase : sub_block.title.downcase

        if id_or_title.include?('req_conds') || id_or_title.include?('required condition')
          req_conds_xml = generate_req_cond_group_xml(sub_block)
        elsif id_or_title.include?('req_persons') || id_or_title.include?('required person')
          req_persons_xml = generate_req_persons_xml(sub_block)
        elsif id_or_title.include?('req_tech_info') || id_or_title.include?('required technical information') # New
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
            "<noSpares/>", {name:0, mfr:1, pn:2, qty:3}
          )
        elsif id_or_title.include?('req_safety') || id_or_title.include?('safety condition')
          req_safety_xml = generate_req_safety_xml(sub_block)
        end
      end
    end

    # Assemble the parts in the desired S1000D order
    prelim_xml_parts = [
      req_conds_xml,
      (req_persons_xml unless req_persons_xml.empty?), # Only include if not empty
      req_tech_info_xml, # Added here
      req_support_equip_xml,
      req_supplies_xml,
      req_spares_xml,
      req_safety_xml
    ].compact.join("\n") # compact removes nil entries (like an empty req_persons_xml)

    "<preliminaryRqmts>\n#{prelim_xml_parts}\n</preliminaryRqmts>"
  end
    
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
              block.items.each_with_index { |li, li_idx| steps_content << "<proceduralStep id=\"step-main-#{index}-#{li_idx}\">#{li.blocks? ? li.content : "<para>#{esc_text(li.text)}</para>"}</proceduralStep>\n" }
          elsif block 
            steps_content << "<proceduralStep id=\"step-main-#{index}\">#{block.convert}</proceduralStep>\n"
          end
      end
      return steps_content.empty? ? "<proceduralStep><para/></proceduralStep>" : steps_content.strip
    end

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
        isolation_steps_content = "<isolationStep><isolationStepQuestion><para>No isolation steps defined.</para></isolationStepQuestion><yesAnswer><nextAction><gotoStandardTask targetDmRefIdent=" + '"FIXME-TARGET-DMREF"' + "/></nextAction></yesAnswer><noAnswer><nextAction><gotoStandardTask targetDmRefIdent=" + '"FIXME-TARGET-DMREF"' + "/></nextAction></noAnswer></isolationStep>"
      else
        blocks_to_process.each_with_index do |block, index|
            isolation_steps_content << "<isolationStep id=\"iso-step-#{index}\">#{block.convert}</isolationStep>\n"
        end
      end
      main_content = isolation_steps_content.empty? ? "<isolationProcedureEnd id=\"auto-end-0001\"/>" : isolation_steps_content.strip
      "<isolationMainProcedure>\n#{main_content}\n</isolationMainProcedure>"
    end
    
    def generate_close_requirements_xml(document_node)
      close_section = document_node.blocks.find { |b| b.context == :section && (b.id == 'closeout_reqs' || b.title.downcase.include?('closeout requirements') || b.title.downcase.include?('requirements after job completion')) }
      req_conds_xml = "<reqCondGroup><noConds/></reqCondGroup>"
      if close_section
          conds_subsection = close_section.blocks.find { |b| b.context == :section && (b.id == 'closeout_conds_after' || b.title.downcase.include?('required conditions after job completion')) } # Changed ID here
          target_node_for_conds = conds_subsection || close_section
          req_conds_xml = generate_req_cond_group_xml(target_node_for_conds, true) # Calls revised method, passes true for closeout
      end
      "<closeRqmts>\n#{req_conds_xml}\n</closeRqmts>"
    end

    def convert_document node
      doc_attrs = node.document.attributes
      dmc_attr_string = doc_attrs['dmc'] || doc_attrs['part-title']; 
      dm_code_attrs = parse_dmc_string(dmc_attr_string)
      default_dm_code_values = { modelIdentCode: "S1KDTOOLS", systemDiffCode: "A", systemCode: "00", subSystemCode: "0", subSubSystemCode: "0", assyCode: "0000", disassyCode: "00", disassyCodeVariant: "A", infoCode: "000", infoCodeVariant: "A", itemLocationCode: "A" }
      if dmc_attr_string && dm_code_attrs.nil?; warn "asciidoctor: WARNING: Invalid DMC: '#{dmc_attr_string}' in document header. Ensure it is a valid 11-part code. Using defaults."; 
        dm_code_attrs = default_dm_code_values
      elsif dm_code_attrs.nil?; warn "asciidoctor: WARNING: No DMC attribute provided. Using defaults."; 
        dm_code_attrs = default_dm_code_values; end
      lang_code = (doc_attrs['lang'] || 'en').downcase; 
      country_code = (doc_attrs['country-code'] || 'US').upcase
      issue_number = doc_attrs['issue-number'] || "001"; 
      in_work_status = doc_attrs['in-work'] || "00"
      date_str = doc_attrs['revdate'] || doc_attrs['issue-date']; 
      date_str = date_str.strip if date_str
      year, month, day = "2025", "10", "01"; 
      if date_str && date_str.match?(/^\d{4}-\d{2}-\d{2}$/); year, month, day = date_str.split('-'); 
      elsif date_str && !date_str.empty?; 
        warn "asciidoctor: WARNING: Invalid date: #{date_str}"; 
      end
      tech_name = doc_attrs['tech-name'] || node.doctitle || "Def Tech-Name"; 
      dm_title_text = doc_attrs['dm-title'] || tech_name
      security_classification = doc_attrs['security-classification'] || "01"; 
      responsible_partner_company = doc_attrs['responsible-partner-company'] || "UNKNOWN"
      originator_enterprise = doc_attrs['originator-enterprise'] || responsible_partner_company; 
      applic_display_text = doc_attrs['applicability'] || "All"
      brex_dmc_string = doc_attrs['brex-dmc']; 
      brex_dm_code_attrs = parse_dmc_string(brex_dmc_string)
      default_brex_dm_code_attrs = { modelIdentCode: "S1000D", systemDiffCode: "H", systemCode: "04", subSystemCode: "1", subSubSystemCode: "0", assyCode: "0301", disassyCode: "00", disassyCodeVariant: "A", infoCode: "022", infoCodeVariant: "A", itemLocationCode: "D" }
      if brex_dmc_string && brex_dm_code_attrs.nil?; warn "asciidoctor: WARNING: Invalid BREX DMC: '#{brex_dmc_string}' in document header. Ensure it is a valid 11-part code. Using default."; 
        brex_dm_code_attrs = default_brex_dm_code_attrs
      elsif brex_dm_code_attrs.nil?; warn "asciidoctor: WARNING: No BREX DMC attribute provided. Using default BREX."; 
        brex_dm_code_attrs = default_brex_dm_code_attrs; end
      rfu_elements = ""; 
      rfu_text_raw = doc_attrs['reason-for-update']
      if rfu_text_raw; 
        rfu_text_escaped = esc_text(rfu_text_raw); 
        rfu_elements = %(\n<reasonForUpdate id="rfu-0001" updateHighlight="1" updateReasonType="urt02"><simplePara>#{rfu_text_escaped}</simplePara></reasonForUpdate>)
      else; 
        rfu_elements = %(\n<reasonForUpdate id="rfu-0001" updateHighlight="1" updateReasonType="urt02"><simplePara>Initial issue or generic update.</simplePara></reasonForUpdate>)
      end
      dm_type = (doc_attrs['dm-type'] || 'descript').downcase.strip
      content_markup = ""
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
      when 'fault', 'faultisolation' 
        fault_descr_xml = "<faultDescr><para>Fault description placeholder. Author this in AsciiDoc.</para></faultDescr>"
        prelim_reqs_markup = generate_preliminary_requirements_xml(node) 
        fault_iso_main_markup = generate_fault_isolation_main_procedure_xml(node) 
        close_reqs_markup = generate_close_requirements_xml(node) 
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
      icn_ids = content_markup.scan(/infoEntityIdent=["'](ICN-[A-Z0-9\-]+)["']/).flatten.uniq 
      doctype_parts = []
      if !icn_ids.empty?
        doctype_parts << "<!NOTATION PNG SYSTEM \"PNG\">"
        icn_ids.each do |icn|
          doctype_parts << "<!ENTITY #{esc_text(icn)} SYSTEM \"#{esc_text(icn)}.png\" NDATA PNG>" 
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
      schema_file = case dm_type
                    when 'procedure', 'procedural'; 'proced.xsd'
                    when 'fault', 'faultisolation'; 'fault.xsd' 
                    else 'descript.xsd'
                    end
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

    def convert_paragraph node
        %(<para#{common_attributes node.id}>#{node.content}</para>)
    end
    def convert_ulist node
        result = %(<para><randomList#{common_attributes node.id}>); node.items.each { |item| result << %(<listItem>#{item.blocks? ? item.content : "<para>#{esc_text(item.text)}</para>"}</listItem>) }; result << %(</randomList></para>)
    end
    def convert_olist node
        result = %(<para><sequentialList#{common_attributes node.id}>); 
        node.items.each { |item| result << %(<listItem>#{item.blocks? ? item.content : "<para>#{esc_text(item.text)}</para>"}</listItem>) }; result << %(</sequentialList></para>)
    end
    def convert_dlist node; result = %(<para><definitionList#{common_attributes node.id}>); 
      node.items.each do |terms, dd|; 
        result << %(<definitionListItem><listItemTerm>); 
        terms.each {|dt| result << esc_text(dt.text) }; 
        result << %(</listItemTerm><listItemDefinition>); 
        if dd; 
          result << %(<para>#{esc_text(dd.text)}</para>) if dd.text?; result << dd.content if dd.blocks?; 
        else; 
          result << %(<para/>); 
        end; 
        result << %(</definitionListItem></definitionListItem>); 
      end; 
      result << %(</definitionList></para>); 
    end

    def convert_section node; 
      %(<levelledPara#{common_attributes node.id}><title>#{esc_text(node.title)}</title>#{node.content}</levelledPara>); 
    end

    def convert_inline_anchor node; 
      case node.type; 
      when :xref; 
        target = node.attributes['refid'] || node.target; target = target[1..-1] if target.start_with?('#'); 
        %(<internalRef internalRefId="#{esc_text(target)}">#{esc_text(node.text || target)}</internalRef>); 
      when :link; %(<externalRef destination="#{esc_text(node.target)}">#{esc_text(node.text)}</externalRef>); 
      when :ref; ''; 
      else; esc_text(node.text || node.target); 
      end; 
    end
    def convert_table node; 
      pgwide = (node.option? 'pgwide') ? 1 : 0; 
      frame = node.attr 'frame', 'all'; 
      grid = node.attr 'grid', 'all'; rowsep = (grid == 'none' || grid == 'cols') ? 0 : 1; colsep = (grid == 'none' || grid == 'rows') ? 0 : 1; orient = (node.attr? 'orientation', 'landscape') ? ' land' : ''; 
      result = %(<table#{common_attributes node.id} frame="#{frame}" pgwide="#{pgwide}" rowsep="#{rowsep}" colsep="#{colsep}"#{orient.empty? ? '' : %( orient="#{orient}")}>); result << %(<title>#{esc_text(node.title)}</title>) if node.title?; 
      result << %(<tgroup cols="#{node.attr 'colcount'}">); 
      node.columns.each { |col| result << %(<colspec colname="col_#{col.attr 'colnumber'}" colwidth="#{(col.attr 'width') ? "#{col.attr 'width'}*" : "1*"}"/>) }; 
      node.rows.to_h.each do |tsec, rows|; 
        next if rows.empty?; 
        result << %(<t#{tsec}>); 
        rows.each do |row|; 
          result << %(<row>); 
          row.each do |cell|; 
            colnum = cell.column.attr 'colnumber'; 
            halign = (cell.attr? 'halign') ? %( align="#{cell.attr 'halign'}") : ''; 
            valign = (cell.attr? 'valign') ? %( valign="#{cell.attr 'valign'}") : ''; 
            colspan = cell.colspan ? %( namest="col_#{colnum}" nameend="col_#{colnum + cell.colspan - 1}") : ''; 
            rowspan = cell.rowspan ? %( morerows="#{cell.rowspan - 1}") : ''; 
            entry_start = %(<entry#{halign}#{valign}#{colspan}#{rowspan}>); 
            cell_body = case cell.style; when :asciidoc then cell.content; 
            when :literal then %(<para><verbatimText>#{esc_text(cell.text)}</verbatimText></para>); 
            else cell.text.empty? ? '' : %(<para>#{esc_text(cell.text)}</para>); 
            end; 
            result << %(#{entry_start}#{cell_body || ''}</entry>); end; result << %(</row>); 
          end; 
            result << %(</t#{tsec}>); 
          end; 
            result << %(</tgroup></table>); 
          end
    alias convert_embedded content_only

    def convert_image node
      id_attr = common_attributes(node.id)
      title_el = node.title ? "<title>#{esc_text(node.title)}</title>" : ""
      icn = node.attr('icn')
      if icn.nil? || icn.empty?
        base_name = File.basename(node.attr('target', 'unknown.png'), '.*')
        if base_name.match?(/^ICN(-[A-Z0-9]+){2,}$/i) 
            icn = base_name.upcase
            warn "asciidoctor: INFO: Image target '#{node.attr('target')}' - inferred ICN '#{icn}' from filename. Consider using the 'icn' attribute for clarity (e.g., image::path.png[alt, icn=#{icn}])."
        else
            icn_fallback_source = node.attr('alt') || base_name
            icn = "FIG-#{icn_fallback_source.gsub(/[^A-Za-z0-9\-]/, '').upcase}" 
            warn "asciidoctor: WARNING: Image target '#{node.attr('target')}' - no 'icn' attribute provided and filename not ICN-like. Using generated infoEntityIdent: #{icn}. Please provide a proper ICN via the 'icn' attribute for S1000D compliance."
        end
      end
      icn_ident = esc_text(icn) 
      %(<figure#{id_attr}>
        #{title_el}
        <graphic infoEntityIdent="#{icn_ident}"/>
      </figure>)
    end

    def convert_inline_quoted node
        open, close = QUOTE_TAGS[node.type]; 
        attrs = common_attributes(node.id); 
        %(#{open.sub('>', "#{attrs}>")}#{esc_text(node.text)}#{close}); 
    end
    def convert_admonition node
        type = node.attr('name').upcase; attrs = common_attributes(node.id); 
        inner_content = if node.blocks?
                          node.content 
                        else
                          "#{esc_text(node.source)}" 
                        end
        case type
        when 'WARNING'
          %(<warning#{attrs}><warningAndCautionPara>#{inner_content}</warningAndCautionPara></warning>)
        when 'CAUTION'
          %(<caution#{attrs}><warningAndCautionPara>#{inner_content}</warningAndCautionPara></caution>)
        when 'NOTE'
          %(<note#{attrs}><notePara>#{inner_content}</notePara></note>)
        when 'TIP', 'IMPORTANT' 
          warn "asciidoctor: INFO: Admonition type '#{type}' mapped to standard S1000D <note>."
          %(<note#{attrs}><notePara>#{inner_content}</notePara></note>) 
        else
          warn "asciidoctor: WARNING: Unknown admonition type '#{type}' mapped to generic S1000D <note>."
          %(<note#{attrs}><notePara>#{inner_content}</notePara></note>) 
        end
    end
    def convert_open node; 
      %(<para#{common_attributes node.id}>#{node.content}</para>); 
    end
    def convert_listing node; 
      result = %(<figure#{common_attributes node.id}>); 
      result << %(<title>#{esc_text(node.title)}</title>) if node.title?; 
      result << %(<graphic><verbatimText><![CDATA[#{node.content}]]></verbatimText></graphic>); 
      result << %(</figure>); 
    end
    def convert_literal node; 
      %(<para#{common_attributes node.id}><verbatimText>#{esc_text(node.content)}</verbatimText></para>); 
    end
    
    def convert_thematic_break node
      ''
    end

    def convert_fallback node; warn %(asciidoctor: WARNING: S1000D converter missing handler for node type: #{node.node_name}, content: #{node.content if node.respond_to?(:content)}); node.content if node.respond_to? :content; 
    end

    def convert_inline_image(node)
        target = node.target
        icn_base = File.basename(target, '.*')
        icn = node.attr('icn', "ICN-INLINE-#{icn_base.gsub(/[^A-Za-z0-9\-]/, '').upcase}")
        warn "asciidoctor: INFO: Inline image converted to <graphic>. True inline placement depends on S1000D context and may require <symbol> or similar."
        %Q{<graphic infoEntityIdent="#{esc_text(icn)}"/>}
      end
      
  end
end