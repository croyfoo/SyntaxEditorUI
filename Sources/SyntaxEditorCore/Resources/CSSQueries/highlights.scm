(comment) @editor.syntax.css.comment

(tag_name) @editor.syntax.css.declaration.other
(nesting_selector) @editor.syntax.css.declaration.other
(universal_selector) @editor.syntax.css.declaration.other
(class_name) @editor.syntax.css.declaration.other
(id_name) @editor.syntax.css.declaration.other
(namespace_name) @editor.syntax.css.declaration.other

((property_name) @editor.syntax.css.keyword
 (#not-match? @editor.syntax.css.keyword "^--"))
(media_statement
  (feature_query
    (feature_name) @editor.syntax.css.keyword))
(attribute_name) @editor.syntax.css.plain
(supports_statement (feature_query (feature_name) @editor.syntax.css.plain))

(pseudo_element_selector (tag_name) @editor.syntax.css.declaration.other)
(pseudo_class_selector (class_name) @editor.syntax.css.declaration.other)
(attribute_selector (string_value) @editor.syntax.css.string)
(attribute_selector (plain_value) @editor.syntax.css.string)

((function_name) @editor.syntax.css.keyword
 (#match? @editor.syntax.css.keyword "^(rgba?|hsla?|repeat)$"))
(function_name) @editor.syntax.css.plain

((property_name) @editor.syntax.css.plain
 (#match? @editor.syntax.css.plain "^--"))
((plain_value) @editor.syntax.css.plain
 (#match? @editor.syntax.css.plain "^--"))

[
  "@media"
  "@import"
  "@charset"
  "@supports"
  "@keyframes"
] @editor.syntax.css.keyword
; BEGIN GENERATED EDITOR SYNTAX WORDS: css-at-rules
[
  "@keyframes"
  "@supports"
] @editor.syntax.css.declaration.other
; END GENERATED EDITOR SYNTAX WORDS: css-at-rules
(at_keyword) @editor.syntax.css.keyword
(keyframes_name) @editor.syntax.css.declaration.other
(to) @editor.syntax.css.keyword
(from) @editor.syntax.css.keyword
(important) @editor.syntax.css.keyword

(string_value) @editor.syntax.css.string
(color_value) @editor.syntax.css.number
(integer_value) @editor.syntax.css.number
(float_value) @editor.syntax.css.number
(unit) @editor.syntax.css.keyword

[
  "~"
  ">"
  "+"
  "-"
  "*"
  "/"
  "="
  "^="
  "|="
  "~="
  "$="
  "*="
  "and"
  "or"
  "not"
  "only"
] @editor.syntax.css.plain

[
  "#"
  ","
  ":"
] @editor.syntax.css.plain
