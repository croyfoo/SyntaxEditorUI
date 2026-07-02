; Captures use this package's `editor.syntax.<language>.<kind>` scheme; anything
; outside it is treated as plain text. Derived from the upstream tree-sitter-yaml
; highlights, remapped to the kinds the editor theme colors.

(boolean_scalar) @editor.syntax.yaml.keyword
(null_scalar) @editor.syntax.yaml.keyword

[
  (double_quote_scalar)
  (single_quote_scalar)
  (block_scalar)
  (string_scalar)
] @editor.syntax.yaml.string

[
  (integer_scalar)
  (float_scalar)
] @editor.syntax.yaml.number

(comment) @editor.syntax.yaml.comment

[
  (anchor_name)
  (alias_name)
] @editor.syntax.yaml.identifier

(tag) @editor.syntax.yaml.identifier.type

[
  (yaml_directive)
  (tag_directive)
  (reserved_directive)
] @editor.syntax.yaml.preprocessor

; Mapping keys are the dominant token in most YAML; color them like attributes.
(block_mapping_pair
  key: (flow_node
    [
      (double_quote_scalar)
      (single_quote_scalar)
    ] @editor.syntax.yaml.attribute))

(block_mapping_pair
  key: (flow_node
    (plain_scalar
      (string_scalar) @editor.syntax.yaml.attribute)))

(flow_mapping
  (_
    key: (flow_node
      [
        (double_quote_scalar)
        (single_quote_scalar)
      ] @editor.syntax.yaml.attribute)))

(flow_mapping
  (_
    key: (flow_node
      (plain_scalar
        (string_scalar) @editor.syntax.yaml.attribute))))
