;; XML declaration

"xml" @editor.syntax.xml.keyword

[ "version" "encoding" "standalone" ] @editor.syntax.xml.attribute

(EncName) @editor.syntax.xml.string

(VersionNum) @editor.syntax.xml.number

[ "yes" "no" ] @editor.syntax.xml.keyword

;; Processing instructions

(PI) @editor.syntax.xml.plain

(PI (PITarget) @editor.syntax.xml.keyword)

;; Element declaration

(elementdecl
  "ELEMENT" @editor.syntax.xml.keyword
  (Name) @editor.syntax.xml.keyword)

(contentspec
  (_ (Name) @editor.syntax.xml.attribute))

"#PCDATA" @editor.syntax.xml.identifier.type.system

[ "EMPTY" "ANY" ] @editor.syntax.xml.string

[ "*" "?" "+" ] @editor.syntax.xml.plain

;; Entity declaration

(GEDecl
  "ENTITY" @editor.syntax.xml.keyword
  (Name) @editor.syntax.xml.identifier.constant)

(GEDecl (EntityValue) @editor.syntax.xml.string)

(NDataDecl
  "NDATA" @editor.syntax.xml.keyword
  (Name) @editor.syntax.xml.plain)

;; Parsed entity declaration

(PEDecl
  "ENTITY" @editor.syntax.xml.keyword
  "%" @editor.syntax.xml.plain
  (Name) @editor.syntax.xml.identifier.constant)

(PEDecl (EntityValue) @editor.syntax.xml.string)

;; Notation declaration

(NotationDecl
  "NOTATION" @editor.syntax.xml.keyword
  (Name) @editor.syntax.xml.identifier.constant)

(NotationDecl
  (ExternalID
    (SystemLiteral (URI) @editor.syntax.xml.string)))

;; Attlist declaration

(AttlistDecl
  "ATTLIST" @editor.syntax.xml.keyword
  (Name) @editor.syntax.xml.keyword)

(AttDef (Name) @editor.syntax.xml.attribute)

(AttDef (Enumeration (Nmtoken) @editor.syntax.xml.string))

(DefaultDecl (AttValue) @editor.syntax.xml.string)

[
  (StringType)
  (TokenizedType)
] @editor.syntax.xml.identifier.type.system

(NotationType "NOTATION" @editor.syntax.xml.identifier.type.system)

[
  "#REQUIRED"
  "#IMPLIED"
  "#FIXED"
] @editor.syntax.xml.attribute

;; Entities

(EntityRef) @editor.syntax.xml.identifier.constant

((EntityRef) @editor.syntax.xml.keyword
 (#any-of? @editor.syntax.xml.keyword
   "&amp;" "&lt;" "&gt;" "&quot;" "&apos;"))

(CharRef) @editor.syntax.xml.identifier.constant

(PEReference) @editor.syntax.xml.identifier.constant

;; External references

[ "PUBLIC" "SYSTEM" ] @editor.syntax.xml.keyword

(PubidLiteral) @editor.syntax.xml.string

(SystemLiteral (URI) @editor.syntax.xml.url)

;; Processing instructions

(XmlModelPI "xml-model" @editor.syntax.xml.keyword)

(StyleSheetPI "xml-stylesheet" @editor.syntax.xml.keyword)

(PseudoAtt (Name) @editor.syntax.xml.attribute)

(PseudoAtt (PseudoAttValue) @editor.syntax.xml.string)

;; Doctype declaration

(doctypedecl "DOCTYPE" @editor.syntax.xml.keyword)

(doctypedecl (Name) @editor.syntax.xml.identifier.type.system)

;; Tags

(STag (Name) @editor.syntax.xml.keyword)

(ETag (Name) @editor.syntax.xml.keyword)

(EmptyElemTag (Name) @editor.syntax.xml.keyword)

;; Attributes

(Attribute (Name) @editor.syntax.xml.attribute)

(Attribute (AttValue) @editor.syntax.xml.string)

;; Delimiters & punctuation

[
 "<?" "?>"
 "<!" "]]>"
 "<" ">"
 "</" "/>"
] @editor.syntax.xml.plain

[ "(" ")" "[" "]" ] @editor.syntax.xml.plain

[ "\"" "'" ] @editor.syntax.xml.plain

[ "," "|" "=" ] @editor.syntax.xml.plain

;; Text

(CharData) @editor.syntax.xml.plain

(CDSect
  (CDStart) @editor.syntax.xml.keyword
  (CData) @editor.syntax.xml.string
  "]]>" @editor.syntax.xml.keyword)

;; Misc

(Comment) @editor.syntax.xml.comment

(ERROR) @editor.syntax.xml.plain
