macro FixtureMacro() = #externalMacro(module: "FixtureMacros", type: "FixtureMacro")

#if swift(>=5.9) && compiler(>=6.0)
let fixtureValue = #FixtureMacro()
#else
let fixtureValue = 0
#endif

#sourceLocation(file: "SwiftPreprocessorMacros.swift", line: 100)
let sourceLocationFixture: Any? = nil
#sourceLocation()
