; Block-grammar highlights, remapped from tree-sitter-markdown v0.5.1 into this
; package's editor.syntax.<language>.<kind> capture scheme. Inline spans
; (emphasis, links, code spans) are highlighted by the injected markdown-inline
; layer (see injections.scm).

(atx_heading (inline) @editor.syntax.markdown.keyword)
(setext_heading (paragraph) @editor.syntax.markdown.keyword)

[
  (atx_h1_marker)
  (atx_h2_marker)
  (atx_h3_marker)
  (atx_h4_marker)
  (atx_h5_marker)
  (atx_h6_marker)
  (setext_h1_underline)
  (setext_h2_underline)
] @editor.syntax.markdown.keyword

[
  (link_title)
  (indented_code_block)
  (fenced_code_block)
] @editor.syntax.markdown.string

[
  (fenced_code_block_delimiter)
] @editor.syntax.markdown.keyword

[
  (link_destination)
] @editor.syntax.markdown.url

[
  (link_label)
] @editor.syntax.markdown.identifier

[
  (list_marker_plus)
  (list_marker_minus)
  (list_marker_star)
  (list_marker_dot)
  (list_marker_parenthesis)
  (thematic_break)
] @editor.syntax.markdown.keyword

[
  (block_continuation)
  (block_quote_marker)
] @editor.syntax.markdown.keyword

[
  (backslash_escape)
] @editor.syntax.markdown.character
