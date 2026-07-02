; Inline-grammar highlights, remapped from tree-sitter-markdown-inline v0.5.1
; into this package's editor.syntax.<language>.<kind> capture scheme. This layer
; is injected into markdown inline content (see the block grammar's injections).

[
  (code_span)
  (link_title)
] @editor.syntax.markdown-inline.string

[
  (emphasis_delimiter)
  (code_span_delimiter)
] @editor.syntax.markdown-inline.keyword

(emphasis) @editor.syntax.markdown-inline.identifier

(strong_emphasis) @editor.syntax.markdown-inline.attribute

[
  (link_destination)
  (uri_autolink)
] @editor.syntax.markdown-inline.url

[
  (link_label)
  (link_text)
  (image_description)
] @editor.syntax.markdown-inline.identifier

[
  (backslash_escape)
  (hard_line_break)
] @editor.syntax.markdown-inline.character

(image ["!" "[" "]" "(" ")"] @editor.syntax.markdown-inline.keyword)
(inline_link ["[" "]" "(" ")"] @editor.syntax.markdown-inline.keyword)
(shortcut_link ["[" "]"] @editor.syntax.markdown-inline.keyword)
