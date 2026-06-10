require 'nokogiri'
require 'date'
require 'fileutils'

class AsciidocToS1000dPmc
  # --- Configuration (Unchanged) ---
  DEFAULT_PM_ISSUER = "00000"
  DEFAULT_PM_NUMBER = "00001"
  DEFAULT_PM_VOLUME = "00"
  DEFAULT_SECURITY_CLASSIFICATION = "01"
  DEFAULT_COUNTRY_ISO_CODE = "IN"
  DEFAULT_DM_ISSUE_NUMBER = "001"
  DEFAULT_DM_IN_WORK = "00"
  INFO_CODE_TO_NAME = {
    "001A" => "Title page", "009A" => "Foreword", "00DA" => "List of effective data modules",
    "400A" => "Descriptive", "410A" => "Removal", "412A" => "Installation",
    "520A" => "Removal Procedure", "720A" => "Installation Procedure",
  }
  DEFAULT_INFO_NAME_FALLBACK_PREFIX = "Information for "
  BREX_DM_CODE = {
    modelIdentCode: "S1000D", systemDiffCode: "F", systemCode: "04",
    subSystemCode: "1", subSubSystemCode: "0", assyCode: "0301",
    disassyCode: "00", disassyCodeVariant: "A", infoCode: "022",
    infoCodeVariant: "A", itemLocationCode: "D"
  }

  attr_reader :adoc_header, :dm_includes

  def initialize(adoc_filepath)
    @adoc_filepath = adoc_filepath
    @adoc_header = {}
    @dm_includes = []
    parse_adoc_file
  end

  def parse_adoc_file
    # This method is fine, no changes needed here.
    lines = File.readlines(@adoc_filepath)
    in_header = true
    lines.each do |line|
      line.strip!; next if line.empty? || line.start_with?('//'); if in_header && line.empty? && !@adoc_header.empty?; in_header = false; next; end
      if in_header
        if line.start_with?('= ') && !@adoc_header[:title_line]; @adoc_header[:title_line] = line
        elsif @adoc_header[:title_line] && !@adoc_header[:author_line] && !line.start_with?(':'); @adoc_header[:author_line] = line
        elsif line.start_with?(':'); key, value = line[1..].split(':', 2).map(&:strip); @adoc_header[key.downcase.to_sym] = value
        elsif line.match?(/^v\d+\.\d+\.\d+,/); @adoc_header[:version_line] = line
        else in_header = false; end
      end
      if line.start_with?("include::"); match = line.match(/include::([^\[]+)\[/); if match; @dm_includes << match[1]; end; end
    end
    @adoc_header[:lang] ||= "en"; @adoc_header[:"chapter-signifier"] ||= "Chapter"; @adoc_header[:country_iso_code] ||= DEFAULT_COUNTRY_ISO_CODE
    if @adoc_header[:version_line] && @adoc_header[:version_line].include?('{docdatetime}'); date_str = Time.now.strftime('%Y-%m-%d'); @adoc_header[:version_line].sub!('{docdatetime}', date_str); @adoc_header[:docdatetime] ||= date_str; end
    @adoc_header[:docdatetime] ||= Time.now.strftime('%Y-%m-%d'); @adoc_header[:version_line] ||= "v0.0.0, #{Time.now.strftime('%Y-%m-%d')}: Initial"
  end

  # --- ### MAJOR FIX & DEBUGGING ### ---
  # This new helper function robustly finds the file and tells you what it's doing.
  def find_dm_file_path(dm_path)
    puts "--> Trying to locate file for include: '#{dm_path}'"

    # Strategy 1: Check if the path as-is (absolute path) exists.
    # This is the most likely case for your `D:/...` paths.
    if File.exist?(dm_path)
      puts "  [SUCCESS] Found file at absolute path: '#{dm_path}'"
      return dm_path
    else
      puts "  [INFO] Did not find file at absolute path: '#{dm_path}'"
    end

    # Strategy 2: Check for the file relative to the main .adoc file's location.
    relative_path = File.expand_path(dm_path, File.dirname(@adoc_filepath))
    if File.exist?(relative_path)
      puts "  [SUCCESS] Found file at relative path: '#{relative_path}'"
      return relative_path
    else
      puts "  [INFO] Did not find file at relative path: '#{relative_path}'"
    end
    
    # If both failed, return nil.
    puts "  [ERROR] Could not locate file. Will use fallback logic."
    nil
  end

  # --- ### MAJOR FIX ### ---
  # This function now uses the robust path finder. The rest is improved for reliability.
  def parse_dm_file_attributes(actual_filepath)
    attributes = {}
    return attributes if actual_filepath.nil? # Exit if the file wasn't found

    puts "  -> Reading attributes from: '#{actual_filepath}'"
    begin
      in_header = true
      File.foreach(actual_filepath) do |line|
        break unless in_header
        line.strip!

        # Skip comments and empty lines
        next if line.empty? || line.start_with?('//')

        if line.start_with?(':') && line.count(':') >= 2
          match = line.match(/:([^:]+):\s*(.*)/)
          if match
            key = match[1].strip.downcase.gsub('-', '_').to_sym
            value = match[2].strip
            attributes[key] = value
            puts "     - Found attribute: #{key} = '#{value}'"
          end
        elsif !attributes[:dm_title] && line.match?(/^=+\s*/)
          title = line.sub(/^=+\s*/, '').strip
          attributes[:dm_title] = title
          puts "     - Found header title: '#{title}'"
        elsif !line.start_with?('=') # If it's a content line, stop reading the header
          in_header = false
        end
      end
    rescue => e
      puts "  [ERROR] Could not read attributes from DM file '#{actual_filepath}': #{e.message}"
    end
    
    attributes[:dm_title] ||= attributes[:tech_name]
    attributes
  end

  # --- ### MAJOR FIX ### ---
  # This is the main orchestrator, now using the corrected helper functions.
  def parse_dm_filename(dm_path_from_include)
    # 1. Parse filename for DM Code (this part is fine)
    filename = File.basename(dm_path_from_include, ".adoc")
    parts = filename.split('-')
    parts.shift if ["DMC"].include?(parts.first.upcase)
    return nil if parts.length < 8

    dm_data = {}; dm_data[:modelIdentCode] = parts.shift; dm_data[:systemDiffCode] = parts.shift
    dm_data[:systemCode] = parts.shift; dm_data[:subSystemCode] = parts.shift
    dm_data[:subSubSystemCode] = parts.shift; dm_data[:assyCode] = parts.shift
    dm_data[:disassyCode] = "00"; dm_data[:disassyCodeVariant] = parts.shift
    ic_icv_combined = parts.shift
    if ic_icv_combined && ic_icv_combined.length >= 4; dm_data[:infoCode] = ic_icv_combined[0...3]; dm_data[:infoCodeVariant] = ic_icv_combined[3]; else; dm_data[:infoCode] = (ic_icv_combined || "").ljust(3, 'X'); dm_data[:infoCodeVariant] = 'A'; end
    dm_data[:itemLocationCode] = parts.shift || 'D'

    # 2. Use our new robust function to find the REAL file path
    actual_filepath = find_dm_file_path(dm_path_from_include)
    
    # 3. Read attributes from the file if it was found
    file_attributes = parse_dm_file_attributes(actual_filepath)

    # 4. Combine filename data with file attribute data
    dm_data[:dm_title]      = file_attributes[:dm_title]
    dm_data[:issue_number]  = file_attributes[:issue_number]
    dm_data[:in_work]       = file_attributes[:in_work]

    dm_data
  rescue StandardError => e
    puts "  [ERROR] Could not parse DM filename '#{filename}': #{e.message}"
    nil
  end

  # --- This method is updated to use the per-DM issue info (no changes needed from last time) ---
  def generate_pmc_xml
    parsed_dms = @dm_includes.map { |path| parse_dm_filename(path) }.compact
    dms_by_subsystem_code = parsed_dms.group_by { |dm| dm[:subSystemCode] }

    pm_title_full = @adoc_header[:title_line] ? @adoc_header[:title_line].sub(/^=\s*/, '') : "Untitled"
    pm_title_parts = pm_title_full.split(":", 2); pm_main_title = pm_title_parts[0].strip
    pm_short_title = pm_title_parts[1] ? pm_title_parts[1].strip : pm_main_title
    author_name = @adoc_header[:author_line] ? @adoc_header[:author_line].split('<').first.strip : "Unknown"

    pm_issue_number = DEFAULT_DM_ISSUE_NUMBER; pm_in_work = DEFAULT_DM_IN_WORK
    if @adoc_header[:version_line]; version_match = @adoc_header[:version_line].match(/v(\d+)\.(\d+)\.(\d+)/)
      if version_match; major_minor_val = (version_match[1].to_i * 10) + version_match[2].to_i; pm_issue_number = major_minor_val.to_s.rjust(3, '0'); pm_in_work = version_match[3].to_s.rjust(2, '0'); end
    end

    issue_date_str = @adoc_header[:docdatetime].split(',').first; year, month, day = issue_date_str.split('-').map(&:to_i)
    lang_code = @adoc_header[:lang]; country_code = @adoc_header[:country_iso_code]

    builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
      xml.pm('xmlns:xsi' => "http://www.w3.org/2001/XMLSchema-instance", 'xsi:noNamespaceSchemaLocation' => "http://www.s1000d.org/S1000D_4-2/xml_schema_flat/pm.xsd") {
        xml.identAndStatusSection { # ... pmAddress and pmStatus sections are unchanged ...
           xml.pmAddress {
            xml.pmIdent {
              mic = parsed_dms.first ? parsed_dms.first[:modelIdentCode] : "DEFAULT"
              xml.pmCode(modelIdentCode: mic, pmIssuer: DEFAULT_PM_ISSUER, pmNumber: DEFAULT_PM_NUMBER, pmVolume: DEFAULT_PM_VOLUME)
              xml.language(languageIsoCode: lang_code, countryIsoCode: country_code)
              xml.issueInfo(issueNumber: pm_issue_number, inWork: pm_in_work)
            }
            xml.pmAddressItems {
              xml.issueDate(year: year.to_s, month: month.to_s.rjust(2, '0'), day: day.to_s.rjust(2, '0'))
              xml.pmTitle pm_main_title; xml.shortPmTitle pm_short_title
            }
          }
          xml.pmStatus {
            xml.security(securityClassification: DEFAULT_SECURITY_CLASSIFICATION)
            xml.responsiblePartnerCompany { xml.enterpriseName author_name }
            xml.applic { xml.displayText { xml.simplePara "All" } }
            xml.brexDmRef { xml.dmRef { xml.dmRefIdent { xml.dmCode(BREX_DM_CODE) } } }
            xml.qualityAssurance { xml.unverified }
          }
        }
        xml.content {
          sorted_subsystem_codes = dms_by_subsystem_code.keys.sort { |a, b| a == "00" ? -1 : (b == "00" ? 1 : a.to_i <=> b.to_i) }
          chapter_counter = 1
          sorted_subsystem_codes.each do |ssc|
            dms_in_group = dms_by_subsystem_code[ssc]
            pm_entry_title = if ssc == "00"; "Front Matter"; else; title = "#{@adoc_header[:"chapter-signifier"]} #{chapter_counter}"; chapter_counter += 1; title; end
            xml.pmEntry {
              xml.pmEntryTitle pm_entry_title
              dms_in_group.each do |dm|
                xml.dmRef {
                  xml.dmRefIdent {
                    xml.dmCode(modelIdentCode: dm[:modelIdentCode], systemDiffCode: dm[:systemDiffCode], systemCode: dm[:systemCode], subSystemCode: dm[:subSystemCode], subSubSystemCode: dm[:subSubSystemCode], assyCode: dm[:assyCode], disassyCode: dm[:disassyCode], disassyCodeVariant: dm[:disassyCodeVariant], infoCode: dm[:infoCode], infoCodeVariant: dm[:infoCodeVariant], itemLocationCode: dm[:itemLocationCode])
                    xml.issueInfo(issueNumber: dm[:issue_number] || DEFAULT_DM_ISSUE_NUMBER, inWork: dm[:in_work] || DEFAULT_DM_IN_WORK)
                    xml.language(languageIsoCode: lang_code, countryIsoCode: country_code)
                  }
                  xml.dmRefAddressItems {
                    xml.dmTitle {
                      title_text = dm[:dm_title]
                      unless title_text
                        full_info_code = "#{dm[:infoCode]}#{dm[:infoCodeVariant]}"
                        title_text = INFO_CODE_TO_NAME[full_info_code] || "#{DEFAULT_INFO_NAME_FALLBACK_PREFIX}#{full_info_code}"
                      end
                      xml.techName title_text; xml.infoName title_text
                    }
                  }
                }
              end
            }
          end
        }
      }
    end
    builder.to_xml
  end
end


# --- Main execution (unchanged) ---
if ARGV.empty?
  puts "Usage: ruby #{$PROGRAM_NAME} <input_asciidoc_file.adoc>"
  exit 1
end
input_adoc_file = ARGV[0]

unless File.exist?(input_adoc_file)
  puts "Error: Input file '#{input_adoc_file}' not found."
  exit 1
end

begin
    converter = AsciidocToS1000dPmc.new(input_adoc_file)
    pmc_xml_content = converter.generate_pmc_xml
    output_filename_base = File.basename(input_adoc_file, ".adoc")
    output_pmc_file = "#{output_filename_base}.xml"
    File.write(output_pmc_file, pmc_xml_content)
    puts "S1000D PMC XML generated successfully: #{output_pmc_file}"
rescue => e
    puts "An error occurred during conversion: #{e.message}"
    puts e.backtrace.join("\n")
    exit 1
end