
-- Pandoc Lua filter: Markdown -> S1000D AsciiDoc
-- *italic* => <<cross-reference>>
-- **bold** => [[anchor-id]]

function Emph(el)
  local content_text = pandoc.utils.stringify(el.content)
  return pandoc.RawInline("asciidoc", "<<" .. content_text .. ">>")
end

function Strong(el)
  local content_text = pandoc.utils.stringify(el.content)
  return pandoc.RawInline("asciidoc", "[[" .. content_text .. "]]")
end
