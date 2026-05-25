struct LocalModel {
    let value: Int
}

enum LocalState {
    case ready
}

macro LocalMacro() = #externalMacro(module: "FixtureMacros", type: "LocalMacro")

func localFunction(_ model: LocalModel, count: Int) -> LocalModel {
    let localValue = count
    print(localValue)
    return LocalModel(value: localValue)
}

let title: String = "title"
let state = LocalState.ready
let model = LocalModel(value: 1)
let output = localFunction(model, count: 2)
let expanded = #LocalMacro()
let external = #ExternalMacro()
@UnknownFixture var attributed: Int
