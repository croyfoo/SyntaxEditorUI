; Properties
;-----------

(table
  (bare_key) @editor.syntax.toml.plain)

(table
  (dotted_key
    (bare_key) @editor.syntax.toml.plain))

(quoted_key) @editor.syntax.toml.string

(pair
  (bare_key)) @editor.syntax.toml.attribute

(pair
  (dotted_key
    (bare_key) @editor.syntax.toml.attribute))

; Literals
;---------

(boolean) @editor.syntax.toml.keyword

(comment) @editor.syntax.toml.comment

(string) @editor.syntax.toml.string

[
  (integer)
  (float)
] @editor.syntax.toml.number

[
  (offset_date_time)
  (local_date_time)
  (local_date)
  (local_time)
] @editor.syntax.toml.string

; Punctuation
;------------

[
  "."
  ","
] @editor.syntax.toml.plain

"=" @editor.syntax.toml.plain

[
  "["
  "]"
  "[["
  "]]"
  "{"
  "}"
] @editor.syntax.toml.plain
