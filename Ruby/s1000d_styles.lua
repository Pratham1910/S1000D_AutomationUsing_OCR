
-- Pandoc Lua filter for S1000D Style Conversion
-- Mappings:
-- 1. Text formatted as Italics (Emph) -> AsciiDoc Cross-Reference <<ref>>
-- 2. Text formatted as Bold (Strong) -> AsciiDoc Anchor [[id]]
-- 3. Word Style 'List Number' -> AsciiDoc List (Level 1, . )
-- 4. Word Style 'List Number 2' -> AsciiDoc List (Level 2, .. )

-- Function to convert Emphasis element (Cross-Reference)
function Emph(el)
  local content_text = pandoc.utils.stringify(el.content)
  return pandoc.RawInline("asciidoc", "<<" .. content_text .. ">>")
end

-- Function to convert Strong element (Cross-Reference)
function Strong(el)
  local content_text = pandoc.utils.stringify(el.content)
  return pandoc.RawInline("asciidoc", "[[" .. content_text .. "]]")
end

-- CRITICAL FIX: The ListItem function now directly modifies its content
-- by prepending the correct AsciiDoc marker based on its custom style.
function ListItem(el)
  local style_name = el.attributes["custom-style-name"]
  local marker_str = nil
  
  if style_name == "List Number" then
    marker_str = ". "
  elseif style_name == "List Number 2" then 
    marker_str = ".. "
  end
  
  if marker_str then
    -- Ensure the list item has content (e.g., a paragraph)
    if #el.content > 0 then
      local first_block = el.content[1]
      
      -- If it's a Plain or Para block (most common for list items)
      if first_block.tag == "Plain" or first_block.tag == "Para" then
        -- Create new inlines by prepending the marker
        local new_inlines = pandoc.Inlines{pandoc.Str(marker_str)}
        
        -- Append the original content of the first block
        for _, inline_el in ipairs(first_block.content) do
          table.insert(new_inlines, inline_el)
        end
        -- Replace the first block with a new Plain block containing the marked content
        el.content[1] = pandoc.Plain(new_inlines)
      end
    end
    
    -- Return the modified ListItem. It has its marker directly injected.
    return el
  end
  
  -- If no custom style, let Pandoc handle it normally
  return nil
end

-- The OrderedList function is TEMPORARILY REMOVED to isolate the "nil value" error.
-- We will address [arabic] attributes in Python cleanup if necessary.
-- function OrderedList(el)
--   el.attributes = pandoc.Attr()
--   return el
-- end

-- BulletList function is no longer needed for custom-styled lists,
-- as ListItem directly handles the marking.
