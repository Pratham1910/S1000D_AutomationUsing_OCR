# Developed By Prathamesh Naik
# This code is a Python script that defines a custom Asciidoctor converter for S1000D XML documents.
# Translated from Ruby to Python.
# This is Licensed under the Apache License, Version 2.0

import re
import json
import uuid
import html
import os
from datetime import datetime

# This is a placeholder for a compatible Node object. In a real implementation,
# you would create this by processing the output of a library like `asciidoc-py`.
# For this script to run, you need to provide objects with this structure.
class MockNode:
    def __init__(self, context, **kwargs):
        self.context = context
        self.node_name = context # For fallback messages
        self._attributes = kwargs.get('attributes', {})
        self.id = self._attributes.get('id')
        self.role = self._attributes.get('role')
        self.style = self._attributes.get('style')
        self.title = self._attributes.get('title')
        self.items = kwargs.get('items', [])
        self.blocks = kwargs.get('blocks', [])
        self.source = kwargs.get('source', '')
        self.text = kwargs.get('text', '')
        self.document = kwargs.get('document', self) # A node needs a reference to the top-level document

    def attr(self, key, default=None):
        return self._attributes.get(key, default)

    def has_attr(self, key):
        return key in self._attributes

    def option(self, key):
        return self.has_attr(key) # Simplified for demonstration

    def content(self):
        # In a real implementation, this would recursively call the converter
        # on all child blocks and join the results.
        return "\n".join([block.source for block in self.blocks])

    def convert(self):
        # This would be the hook to call the main converter's 'convert' method
        # This is a highly simplified stub.
        return self.content()


# In a real application, this would inherit from a base class provided by the
# AsciiDoc parsing library.
class S1000DConverter:
    """
    An Asciidoctor-compatible converter for generating S1000D XML from AsciiDoc.
    This class is intended to be used by a Python-based AsciiDoc processor.
    """
    # Class-level dictionary for quote tags, similar to the Ruby version
    QUOTE_TAGS = {
        'monospaced': ('<verbatimText>', '</verbatimText>'),
        'emphasis': ('<emphasis emphasisType="em02">', '</emphasis>'),
        'strong': ('<emphasis emphasisType="em01">', '</emphasis>'),
        'mark': ('<changeInline changeMark="1">', '</changeInline>'),
        'superscript': ('<superScript>', '</superScript>'),
        'subscript': ('<subScript>', '</subScript>')
    }

    def __init__(self, backend='s1000d', **kwargs):
        """Initializes the S1000D converter."""
        self.basebackend = backend
        self.filetype = 'xml'
        self.outfilesuffix = '.xml'
        self.htmlsyntax = 'xml'
        
        # Initialize instance variables to collect definitions
        self.s1000d_applic_definitions = []
        self.s1000d_product_definitions = []
        self.s1000d_product_attribute_definitions = []
        self.global_applic_eval_hash = None

    def convert(self, node, transform=None):
        """
        Main dispatch method that calls the appropriate conversion method
        based on the node's context (e.g., 'paragraph', 'olist').
        """
        transform = transform or node.context
        method_name = f'convert_{transform}'
        if hasattr(self, method_name):
            # Call the specific converter method (e.g., self.convert_paragraph(node))
            return getattr(self, method_name)(node)
        else:
            # If no specific method exists, use a fallback
            return self.convert_fallback(node)

    # Alias for preamble conversion
    def convert_preamble(self, node):
        return self.content_only(node)
        
    def content_only(self, node):
        """Helper to convert only the content of a node."""
        if not hasattr(node, 'blocks') or not node.blocks:
            return ""
        return "\n".join(self.convert(b) for b in node.blocks)

    # --- UTILITY AND HELPER METHODS ---

    def esc_text(self, text):
        """Escapes text for safe inclusion in XML."""
        if text is None:
            return ''
        return html.escape(str(text), quote=True)

    def common_attributes(self, node_id):
        """Generates a common 'id' attribute string if an ID exists."""
        return f' id="{self.esc_text(node_id)}"' if node_id else ''

    def applic_ref_attribute(self, node):
        """Generates a common 'applicRefId' attribute string."""
        return f' applicRefId="{self.esc_text(node.attr("applic_ref"))}"' if node.has_attr('applic_ref') else ''

    def parse_dmc_string(self, dmc_string):
        """Parses an 11-part Data Module Code (DMC) string."""
        if not dmc_string or not isinstance(dmc_string, str) or not dmc_string.strip():
            return None
        cleaned_dmc_string = dmc_string.split('//')[0].strip()
        regex = re.compile(
            r"^(?:DMC-)?([A-Z0-9]{2,17})-([A-Z0-9]{1})-([A-Z0-9]{2,4})-([A-Z0-9]{1,2})-"
            r"([A-Z0-9]{1,2})-([A-Z0-9]{2,4})-([A-Z0-9]{2})-([A-Z0-9]{1,4})-([A-Z0-9]{3})-"
            r"([A-Z0-9]{1})-([A-Z0-9]{1})$", re.IGNORECASE)
        match = regex.match(cleaned_dmc_sring)
        if match:
            return {
                "modelIdentCode": match.group(1).upper(), "systemDiffCode": match.group(2).upper(),
                "systemCode": match.group(3).upper(), "subSystemCode": match.group(4).upper(),
                "subSubSystemCode": match.group(5).upper(), "assyCode": match.group(6).upper(),
                "disassyCode": match.group(7).upper(), "disassyCodeVariant": match.group(8).upper(),
                "infoCode": match.group(9).upper(), "infoCodeVariant": match.group(10).upper(),
                "itemLocationCode": match.group(11).upper()
            }
        else:
            print(f"asciidoctor: WARNING (parse_dmc_string): Regex DID NOT MATCH for 11-part DMC input '{cleaned_dmc_string}'.")
            return None

    def parse_pmc_string(self, pmc_string):
        """Parses an 8-part Publication Module Code (PMC) string."""
        if not pmc_string or not isinstance(pmc_string, str) or not pmc_string.strip():
            return None
        cleaned_pmc_string = pmc_string.split('//')[0].strip()
        regex = re.compile(
            r"^(?:PMC-)?([A-Z0-9]{2,17})-([A-Z0-9]{5})-([A-Z0-9]{5})-([A-Z0-9]{2})-"
            r"([a-z]{2})-([A-Z]{2})-([0-9]{3})-([0-9A-Z]{2})$", re.IGNORECASE)
        match = regex.match(cleaned_pmc_string)
        if match:
            return {
                "modelIdentCode": match.group(1).upper(), "pmIssuer": match.group(2).upper(),
                "pmNumber": match.group(3).upper(), "pmVolume": match.group(4).upper(),
                "languageIsoCode": match.group(5).lower(), "countryIsoCode": match.group(6).upper(),
                "issueNumber": match.group(7), "inWork": match.group(8).upper()
            }
        else:
            print(f"asciidoctor: WARNING (parse_pmc_string): Regex DID NOT MATCH for 8-part PMC input '{cleaned_pmc_string}'.")
            return None

    def determine_internal_ref_target_type(self, target_node, target_id_for_warning):
        """Determines the S1000D 'internalRefTargetType' based on the node context."""
        if not target_node:
            return ""
        
        context_map = {
            'image': 'irtt01',
            'table': 'irtt03',
            'section': 'irtt07',
        }
        if target_node.context in context_map:
            return f' internalRefTargetType="{context_map[target_node.context]}"'
            
        if target_node.context == 'paragraph':
            return ' internalRefTargetType="irtt08"' if target_node.role == 'note-para' else ' internalRefTargetType="irtt02"'
        
        if target_node.context == 'admonition':
            name = (target_node.attr('name') or '').upper()
            if name == 'NOTE': return ' internalRefTargetType="irtt08"'
            if name == 'WARNING': return ' internalRefTargetType="irtt09"'
            if name == 'CAUTION': return ' internalRefTargetType="irtt0A"'
            return ''
            
        if target_node.context in ['olist_item', 'ulist_item']:
            is_step = (target_node.context == 'olist_item' or
                       (target_node.id and target_node.id.lower().startswith('step_')) or
                       target_node.role == 'proceduralStep')
            return ' internalRefTargetType="irtt0F"' if is_step else ' internalRefTargetType="irtt04"'
            
        print(f"asciidoctor: INFO: Could not determine S1000D internalRefTargetType for ID '{target_id_for_warning}' (context: {target_node.context}). Omitting.")
        return ''

    # --- DEFINITION PROCESSING METHODS ---

    def process_as_applic_definition(self, node):
        """Processes a block as an <applic> definition and stores it."""
        node_id = node.id
        display_text_content = node.source
        prop_ident = node.attr('propertyident')
        prop_values = node.attr('propertyvalues')
        prop_type = node.attr('propertytype', 'prodattr')

        if not (node_id and prop_ident and prop_values):
            print(f"asciidoctor: WARNING: Applicability definition (applicdef) block '{node_id or 'Unnamed'}' is missing required attributes. Skipping.")
            return False
            
        applic_xml = f"""<applic id="{self.esc_text(node_id)}">
  <displayText>
    <simplePara>{self.esc_text(display_text_content.strip())}</simplePara>
  </displayText>
  <assert applicPropertyIdent="{self.esc_text(prop_ident)}" applicPropertyType="{self.esc_text(prop_type)}" applicPropertyValues="{self.esc_text(prop_values)}"/>
</applic>"""
        self.s1000d_applic_definitions.append(applic_xml)
        return True

    def process_as_product_definition(self, node):
        """Processes a block as a <product> definition and stores it."""
        # ... Translation of the corresponding Ruby method ...
        return True

    def process_as_product_attribute_definition(self, node):
        """Processes a block as a <productAttribute> definition."""
        # ... Translation of the corresponding Ruby method ...
        return True

    # --- CORE CONVERTER METHODS ---

    def convert_document(self, node):
        """Converts the entire AsciiDoc document to an S1000D dmodule."""
        # Reset state
        self.s1000d_applic_definitions = []
        self.s1000d_product_definitions = []
        self.s1000d_product_attribute_definitions = []
        self.global_applic_eval_hash = None
        
        doc_attrs = node.document.attributes
        doc_attrs['document_node'] = node # For context
        
        dmc_str = doc_attrs.get('dmc') or doc_attrs.get('part-title')
        dm_code_attrs = self.parse_dmc_string(dmc_str)
        if not dm_code_attrs:
            print("asciidoctor: ERROR: Document is missing a valid 'dmc' attribute. Using fallback.")
            dm_code_attrs = {"modelIdentCode": "S1KDTOOLS", "systemDiffCode": "A", "systemCode": "00", "subSystemCode": "0", "subSubSystemCode": "0", "assyCode": "0000", "disassyCode": "00", "disassyCodeVariant": "A", "infoCode": "000", "infoCodeVariant": "A", "itemLocationCode": "A"}

        brex_dmc_str = doc_attrs.get('brex-dmc')
        brex_dm_code_attrs = self.parse_dmc_string(brex_dmc_str)
        if not brex_dm_code_attrs:
            print("asciidoctor: WARNING: BREX DMC not found or invalid. Using default.")
            brex_dm_code_attrs = {"modelIdentCode": "S1000D", "systemDiffCode": "G", "systemCode": "04", "subSystemCode": "1", "subSubSystemCode": "0", "assyCode": "0301", "disassyCode": "00", "disassyCodeVariant": "A", "infoCode": "022", "infoCodeVariant": "A", "itemLocationCode": "D"}

        global_applic_text = (doc_attrs.get('s1000d-applic-text') or doc_attrs.get('applicability-text') or doc_attrs.get('applicability') or "All applicable conditions").strip()
        
        # ... (Other attribute processing from the Ruby version) ...
        act_dm_ref_xml = "" # Placeholder
        rfu_xml = "" # Placeholder

        # This first pass populates the definition arrays and global hashes by calling convert on all blocks
        for block in node.blocks:
            self.convert(block)

        dm_type = (doc_attrs.get('dm-type') or 'descript').lower().strip()

        # Logic to generate main content based on dm-type
        main_dm_content = ""
        if dm_type in ['procedure', 'procedural']:
            prelim = self.generate_preliminary_requirements_xml(node)
            main_proc_steps_sequence = self.generate_main_procedure_steps_xml(node)
            closeout = self.generate_close_requirements_xml(node)
            main_dm_content = f"""<procedure>
  {prelim.indent(2)}
  <mainProcedure>
    {main_proc_steps_sequence.indent(4)}
  </mainProcedure>
  {closeout.indent(2)}
</procedure>"""
        # ... (add elif for 'fault', 'act', 'descript', etc.) ...
        else: # Default to descriptive
            general_content_processed = self.content_only(node) # Simplified
            content_indented = general_content_processed.indent(2)
            main_dm_content = f"<description>\n{content_indented}\n</description>"

        # Assemble the final content XML
        rag_xml = ""
        if self.s1000d_applic_definitions:
            defs_indented = "\n".join(d.indent(4) for d in self.s1000d_applic_definitions)
            rag_xml = f"<referencedApplicGroup>\n{defs_indented}\n</referencedApplicGroup>"

        final_content_parts = [rag_xml, main_dm_content]
        final_content_xml = "\n".join(p for p in final_content_parts if p)

        # Build final XML document
        ident_status_section = self.build_ident_and_status_section_xml(doc_attrs, dm_code_attrs, act_dm_ref_xml, global_applic_text, brex_dm_code_attrs, rfu_xml, node)
        doctype_decl = self.build_doctype_declaration(final_content_xml)
        schema_file = self.get_schema_file(dm_type)
        schema_base = doc_attrs.get('s1000d-schema-base-path', "http://www.s1000d.org/S1000D_5.0/xml_schema_flat/")
        
        # Assemble the dmodule
        result = f"""<?xml version="1.0" encoding="UTF-8"?>
{doctype_decl}
<dmodule xmlns:dc="http://www.purl.org/dc/elements/1.1/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="{schema_base}{schema_file}">
  {ident_status_section.indent(2)}
  <content>
    {final_content_xml.indent(4)}
  </content>
</dmodule>
"""
        return re.sub(r'\n\s*\n', '\n', result).strip()

    def convert_section(self, node):
        """Converts an AsciiDoc section to an S1000D <levelledPara>."""
        # This is a complex method in Ruby. A full translation needs to handle
        # grouping of admonitions vs. other content.
        # Simplified version for demonstration:
        title_xml = f"<title>{self.esc_text(node.title)}</title>" if node.title else ""
        attrs = self.common_attributes(node.id) + self.applic_ref_attribute(node)
        content = self.content_only(node)
        return f"<levelledPara{attrs}>{title_xml}{content}</levelledPara>"

    def convert_paragraph(self, node):
        """Converts an AsciiDoc paragraph to an S1000D <para>."""
        if node.role == 'applicdef':
            self.process_as_applic_definition(node)
            return ""
        if node.role == 'productdef':
            self.process_as_product_definition(node)
            return ""
            
        # The .content() method should handle inline elements (macros, xrefs, etc.)
        processed_content = node.content() 
        para_attrs = self.common_attributes(node.id) + self.applic_ref_attribute(node)
        
        if not processed_content or not processed_content.strip():
            return f"<para{para_attrs}/>"
            
        return f"<para{para_attrs}>{processed_content}</para>"

    def convert_open(self, node):
        """Handles open blocks, delegating to definition processors if needed."""
        # Delegate to special processors based on role
        if node.role == 'applicdef': return "" if self.process_as_applic_definition(node) else None
        if node.role == 'productdef': return "" if self.process_as_product_definition(node) else None
        if node.role == 'attribute_def': return "" if self.process_as_product_attribute_definition(node) else None
        if node.role == 'dmlref' or node.style == 'dmlref': return self.global_refdmlref(node)

        # Standard open block to <levelledPara>
        content = node.content().strip()
        open_attrs = self.common_attributes(node.id) + self.applic_ref_attribute(node)
        title_el = f"<title>{self.esc_text(node.title)}</title>" if node.title else ""

        # Logic to return content directly if no special attributes
        if not title_el and not open_attrs.strip() and node.style != 'example' and node.role != 'example':
            return content

        if node.style == 'example' or node.role == 'example':
            return f'<levelledPara{open_attrs} class="example">{title_el}{content}</levelledPara>'

        if not content and not title_el and not open_attrs.strip():
            return ""
            
        return f'<levelledPara{open_attrs}>{title_el}{content}</levelledPara>'

    def convert_olist(self, node):
        """Converts an ordered list to a <sequentialList>."""
        item_outputs = []
        for item in node.items:
            li_attrs = self.common_attributes(item.id) + self.applic_ref_attribute(item)
            inner_content = item.content()
            if not inner_content and item.text:
                inner_content = f"<para>{self.esc_text(item.text.strip())}</para>"
            elif not inner_content:
                inner_content = "<para/>"
            item_outputs.append(f"<listItem{li_attrs}>{inner_content}</listItem>")
        
        if not item_outputs:
            return ""
            
        list_attrs = self.common_attributes(node.id) + self.applic_ref_attribute(node)
        list_item_xml = "\n".join(item_outputs)
        
        return f"<para><sequentialList{list_attrs}>\n{list_item_xml}\n</sequentialList></para>"
        
    def convert_ulist(self, node):
        """Converts an unordered list to a <randomList>."""
        if node.role == 'attribute_def' or node.style == 'attribute_def':
            return ""

        list_attrs = self.common_attributes(node.id) + self.applic_ref_attribute(node)
        items = [
            f"<listItem{self.common_attributes(item.id)}{self.applic_ref_attribute(item)}>{item.content() or f'<para>{self.esc_text(item.text)}</para>' if item.text else '<para/>'}</listItem>"
            for item in node.items
        ]
        
        if not items:
            return ""
            
        return f"<para><randomList{list_attrs}>\n" + "\n".join(items) + "\n</randomList></para>"

    def convert_listing(self, node):
        """Converts a listing block to <figure> or <para><verbatimText>."""
        attrs = self.common_attributes(node.id) + self.applic_ref_attribute(node)
        content = self.esc_text(node.content())
        
        if node.title:
            return f'<figure{attrs}><title>{self.esc_text(node.title)}</title><graphic><verbatimText>{content}</verbatimText></graphic></figure>'
        
        if not content and attrs: return f"<para{attrs}/>"
        if not content and not attrs: return ""
        
        return f'<para{attrs}><verbatimText>{content}</verbatimText></para>'

    def convert_literal(self, node):
        """Converts a literal block, checking for special roles like global applicability."""
        if node.role == 'global_applicability_definition' or node.style == 'global_applicability_definition':
            try:
                parsed = json.loads(node.content())
                if isinstance(parsed, dict) and parsed:
                    self.global_applic_eval_hash = parsed
                else:
                    print("asciidoctor: WARNING: Global applicability JSON is not a non-empty dictionary.")
                    self.global_applic_eval_hash = None
            except json.JSONDecodeError:
                print("asciidoctor: WARNING: Failed to parse JSON from global_applicability_definition block.")
                self.global_applic_eval_hash = None
            return ""

        para_attrs = self.common_attributes(node.id) + self.applic_ref_attribute(node)
        content = node.content().strip()
        
        if not content:
            return f"<para{para_attrs}/>" if para_attrs else ""
            
        return f"<para{para_attrs}><verbatimText>{self.esc_text(node.content())}</verbatimText></para>"

    def convert_image(self, node):
        """Converts an image block to an S1000D <figure>."""
        attrs = self.common_attributes(node.id) + self.applic_ref_attribute(node)
        title_xml = f"<title>{self.esc_text(node.title)}</title>" if node.title else ""
        
        icn_val = node.attr('icn')
        if not icn_val or not icn_val.strip():
            img_tgt_bn = os.path.splitext(os.path.basename(node.attr('target', 'unknown.png')))[0]
            alt = node.attr('alt')
            if alt and re.match(r'^(?:ICN|FIG)-', alt, re.IGNORECASE):
                icn_val = alt.upper()
            elif re.match(r'^(?:ICN|FIG)-', img_tgt_bn, re.IGNORECASE):
                icn_val = img_tgt_bn.upper()
            else:
                fallback_base = alt or img_tgt_bn
                icn_val = "FIG-" + re.sub(r'[^A-Za-z0-9\-_\.]', '_', fallback_base).replace('__', '_').upper()
                print(f"asciidoctor: INFO: Image target did not resolve to a valid ICN. Using fallback: {icn_val}.")

        return f'<figure{attrs}>{title_xml}<graphic infoEntityIdent="{self.esc_text(icn_val.strip())}"/></figure>'

    def convert_admonition(self, node):
        """Converts admonition blocks (NOTE, WARNING, CAUTION) to their S1000D equivalents."""
        attrs = self.common_attributes(node.id) + self.applic_ref_attribute(node)
        admonition_type = (node.attr('name') or 'note').upper()
        
        processed_content = node.content().strip()
        final_inner_xml = ""

        # Determine the inner content wrapper (<notePara> or <warningAndCautionPara>)
        if not node.blocks: # Simple paragraph content
            if not processed_content:
                final_inner_xml = "<warningAndCautionPara/>" if admonition_type in ['WARNING', 'CAUTION'] else "<notePara/>"
            else:
                text_to_wrap = self.esc_text(processed_content)
                final_inner_xml = f"<warningAndCautionPara>{text_to_wrap}</warningAndCautionPara>" if admonition_type in ['WARNING', 'CAUTION'] else f"<notePara>{text_to_wrap}</notePara>"
        else: # Complex content with blocks
            final_inner_xml = processed_content or ("<warningAndCautionPara/>" if admonition_type in ['WARNING', 'CAUTION'] else "<notePara/>")

        # Determine the outer tag (<note>, <warning>, <caution>)
        if admonition_type == 'WARNING': return f"<warning{attrs}>{final_inner_xml}</warning>"
        if admonition_type == 'CAUTION': return f"<caution{attrs}>{final_inner_xml}</caution>"
        if admonition_type in ['NOTE', 'TIP', 'IMPORTANT']:
            if admonition_type != 'NOTE': print(f"asciidoctor: INFO: Admonition type '{admonition_type}' is treated as a NOTE in S1000D.")
            return f"<note{attrs}>{final_inner_xml}</note>"
        
        # Fallback for unknown admonition types
        print(f"asciidoctor: WARNING: Unhandled admonition type '{admonition_type}'. Converting as a NOTE.")
        return f"<note{attrs}>{final_inner_xml}</note>"

    def convert_inline_quoted(self, node):
        """Handles inline formatting like bold, italic, etc."""
        # node.type should be a string like 'strong', 'emphasis', etc.
        open_tag, close_tag = self.QUOTE_TAGS.get(node.type, ('', ''))
        text_content = self.esc_text(node.text) if node.text else ""
        return f"{open_tag}{text_content}{close_tag}"

    def convert_thematic_break(self, node):
        """Thematic breaks (horizontal rules) are ignored in S1000D."""
        return ''

    def convert_fallback(self, node):
        """Fallback for any node types not explicitly handled."""
        print(f"asciidoctor: WARNING: S1000D converter encountered unhandled node type: '{node.node_name}' (ID: '{node.id}', Context: '{node.context}'). This content will be SKIPPED.")
        return ""

    # --- XML GENERATOR HELPER METHODS ---
    # These methods correspond to the 'generate_*_xml' methods in the Ruby version.
    # They are complex and would require a full translation of their internal logic.
    # The following are stubs to show where they would fit.

    def generate_preliminary_requirements_xml(self, document_node):
        # Find the preliminary requirements section and process it
        # ... full translation needed ...
        return "<preliminaryRqmts>\n  <reqCondGroup><noConds/></reqCondGroup>\n</preliminaryRqmts>"

    def generate_main_procedure_steps_xml(self, document_node):
        # Find the main procedure section or top-level ordered lists
        # ... full translation needed ...
        return "<proceduralStep><para/></proceduralStep>"

    def generate_close_requirements_xml(self, document_node):
        # Find and process the closeout requirements section
        # ... full translation needed ...
        return "<closeRqmts>\n  <reqCondGroup><noConds/></reqCondGroup>\n</closeRqmts>"

    # --- DOCTYPE AND SCHEMA METHODS ---

    def build_ident_and_status_section_xml(self, doc_attrs, dm_code_attrs, act_dm_ref_xml, global_applic_text, brex_dm_code_attrs, rfu_xml, current_node):
        """Builds the <identAndStatusSection> of the dmodule."""
        # ... This would be a full translation of the very large Ruby method ...
        # Simplified for demonstration
        model_code = self.esc_text(dm_code_attrs.get('modelIdentCode', ''))
        tech_name = self.esc_text(doc_attrs.get('tech-name', 'Default Technical Name'))
        info_name = self.esc_text(doc_attrs.get('dm-title', tech_name))
        
        return f"""<identAndStatusSection>
  <dmAddress>
    <dmIdent>
      <dmCode modelIdentCode="{model_code}" systemDiffCode="A" systemCode="00" subSystemCode="0" subSubSystemCode="0" assyCode="0000" disassyCode="00" disassyCodeVariant="A" infoCode="040" infoCodeVariant="A" itemLocationCode="A"/>
      <language languageIsoCode="en" countryIsoCode="US"/>
      <issueInfo issueNumber="001" inWork="00"/>
    </dmIdent>
    <dmAddressItems>
      <issueDate year="2025" month="08" day="02"/>
      <dmTitle>
        <techName>{tech_name}</techName>
        <infoName>{info_name}</infoName>
      </dmTitle>
    </dmAddressItems>
  </dmAddress>
  <dmStatus issueType="new">
    <security securityClassification="01"/>
    <responsiblePartnerCompany enterpriseCode="0000X">
      <enterpriseName>UNKNOWN RPC</enterpriseName>
    </responsiblePartnerCompany>
    <originator enterpriseCode="0000X">
      <enterpriseName>UNKNOWN RPC</enterpriseName>
    </originator>
    <applic>
      <displayText><simplePara>{self.esc_text(global_applic_text)}</simplePara></displayText>
    </applic>
    <brexDmRef><dmRef><dmRefIdent><dmCode modelIdentCode="S1000D" systemDiffCode="G" systemCode="04" subSystemCode="1" subSubSystemCode="0" assyCode="0301" disassyCode="00" disassyCodeVariant="A" infoCode="022" infoCodeVariant="A" itemLocationCode="D"/></dmRefIdent></dmRef></brexDmRef>
    <qualityAssurance><unverified/></qualityAssurance>
  </dmStatus>
</identAndStatusSection>"""

    def build_doctype_declaration(self, content_markup_for_icns):
        """Builds the DOCTYPE declaration, including entities for referenced images."""
        icn_ids = set(re.findall(r'infoEntityIdent=["\']((?:ICN|FIG)-[A-Z0-9\-]+)["\']', content_markup_for_icns))
        if not icn_ids:
            return "<!DOCTYPE dmodule>"
        
        declarations = ["<!NOTATION PNG SYSTEM \"PNG\">"]
        declarations.extend(f'<!ENTITY {self.esc_text(icn)} SYSTEM "{self.esc_text(icn)}.png" NDATA PNG>' for icn in icn_ids)
        
        declarations_str = "\n  ".join(declarations)
        return f"<!DOCTYPE dmodule [\n  {declarations_str}\n]>"
        
    def get_schema_file(self, dm_type_str):
        """Returns the appropriate S1000D schema file name based on the dm-type."""
        dm_type = (dm_type_str or 'descript').lower().strip()
        schema_map = {
            'procedure': 'proced.xsd', 'procedural': 'proced.xsd',
            'fault': 'fault.xsd', 'faultisolation': 'fault.xsd',
            'act': 'applicom.xsd', 'pct': 'applicom.xsd', 'cct': 'applicom.xsd',
            'descript': 'descript.xsd', 'description': 'descript.xsd', 'descriptive': 'descript.xsd',
            'crew': 'crew.xsd', 'sched': 'sched.xsd', 'catalog': 'ipd.xsd', 'ipd': 'ipd.xsd',
            'learning': 'learning.xsd', 'comrep': 'comrep.xsd', 'sb': 'sb.xsd','ciency': 'process.xsd', 'wiring': 'wire.xsd'
        }
        if dm_type not in schema_map:
            print(f"asciidoctor: WARNING: Unrecognized dm-type '{dm_type}'. Defaulting to 'descript.xsd'.")
        return schema_map.get(dm_type, 'descript.xsd')

# Example of how to use the converter (this part would be in your main script)
if __name__ == '__main__':
    print("S1000D Converter Class Loaded.")
    print("This script defines the converter class but does not execute a conversion.")
    print("To use it, you need a main script that:")
    print("1. Reads an AsciiDoc file.")
    print("2. Parses it using a library like 'asciidoc-py'.")
    print("3. Creates a node structure that mimics the Asciidoctor API.")
    print("4. Instantiates this S1000DConverter class.")
    print("5. Calls the converter's `convert_document` method with the root node.")

    # Example mock usage:
    # converter = S1000DConverter()
    # document_node = MockNode('document', attributes={'dmc': 'MY-DMC-CODE-001...'}, blocks=[
    #     MockNode('paragraph', source='This is the first paragraph.')
    # ])
    # xml_output = converter.convert_document(document_node)
    # print("\n--- Mock Output ---")
    # print(xml_output)