(comment) @comment

(tag_name) @selector.css.element
(nesting_selector) @selector.css.nesting
(universal_selector) @selector.css.universal
(class_name) @selector.css.class
(id_name) @selector.css.id
(namespace_name) @selector.css.namespace

(property_name) @property.css.name
(feature_name) @property.css.feature
(attribute_name) @attribute.css.name
(supports_statement (feature_query (feature_name) @property.css.feature.supports))

(pseudo_element_selector (tag_name) @selector.css.pseudoElement)
(pseudo_class_selector (class_name) @selector.css.pseudoClass)
(attribute_selector (string_value) @string.css.attributeValue)
(attribute_selector (plain_value) @string.css.attributeValue)

((function_name) @function.css.name.keyword
 (#match? @function.css.name.keyword "^(rgba?|hsla?|repeat)$"))
(function_name) @function.css.name

((property_name) @variable.css.customProperty
 (#match? @variable.css.customProperty "^--"))
((plain_value) @variable.css.customProperty
 (#match? @variable.css.customProperty "^--"))

[
  "@media"
  "@import"
  "@charset"
  "@namespace"
  "@supports"
  "@keyframes"
] @keyword.css.atRule
"@supports" @keyword.css.supports
"@keyframes" @keyword.css.keyframes
(at_keyword) @keyword.css.atRule
(keyframes_name) @selector.css.keyframesName
(to) @keyword.css.keyframe
(from) @keyword.css.keyframe
(important) @keyword.css.important

(string_value) @string.css.value
(color_value) @string.css.color
(integer_value) @number.css.value
(float_value) @number.css.value
(unit) @type.css.unit

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
] @operator.css

[
  "#"
  ","
  ":"
] @punctuation.delimiter
