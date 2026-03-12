import Foundation
import Testing

@testable import RescreenBroker

@Suite("AXNodeModel")
struct AXNodeModelTests {
    // MARK: - AXNode.toDict

    @Test("Minimal node includes id and role")
    func minimalNode() {
        let node = AXNode(id: "e0", role: "button", name: nil, value: nil, states: [], bounds: nil, childIDs: [])
        let dict = node.toDict()
        #expect(dict["id"] as? String == "e0")
        #expect(dict["role"] as? String == "button")
        #expect(dict["name"] == nil)
        #expect(dict["value"] == nil)
        #expect(dict["states"] == nil)
        #expect(dict["bounds"] == nil)
        #expect(dict["children"] == nil)
    }

    @Test("Full node includes all fields")
    func fullNode() {
        let node = AXNode(
            id: "e5",
            role: "textbox",
            name: "Username",
            value: "hello",
            states: ["focused", "selected"],
            bounds: NodeRect(x: 10, y: 20, width: 200, height: 30),
            childIDs: ["e6", "e7"]
        )
        let dict = node.toDict()
        #expect(dict["id"] as? String == "e5")
        #expect(dict["role"] as? String == "textbox")
        #expect(dict["name"] as? String == "Username")
        #expect(dict["value"] as? String == "hello")
        #expect(dict["states"] as? [String] == ["focused", "selected"])

        let bounds = dict["bounds"] as? [String: Int]
        #expect(bounds?["x"] == 10)
        #expect(bounds?["y"] == 20)
        #expect(bounds?["w"] == 200)
        #expect(bounds?["h"] == 30)

        #expect(dict["children"] as? [String] == ["e6", "e7"])
    }

    @Test("Empty name and value are omitted")
    func emptyFieldsOmitted() {
        let node = AXNode(id: "e0", role: "group", name: "", value: "", states: [], bounds: nil, childIDs: [])
        let dict = node.toDict()
        #expect(dict["name"] == nil)
        #expect(dict["value"] == nil)
    }

    @Test("Long values are truncated at 500 characters")
    func longValueTruncated() {
        let longValue = String(repeating: "x", count: 1000)
        let node = AXNode(id: "e0", role: "textbox", name: nil, value: longValue, states: [], bounds: nil, childIDs: [])
        let dict = node.toDict()
        let value = dict["value"] as? String ?? ""
        #expect(value.count == 503) // 500 + "..."
        #expect(value.hasSuffix("..."))
        #expect(dict["value_truncated"] as? Bool == true)
    }

    @Test("Values at exactly 500 characters are not truncated")
    func exactLimitNotTruncated() {
        let value = String(repeating: "x", count: 500)
        let node = AXNode(id: "e0", role: "textbox", name: nil, value: value, states: [], bounds: nil, childIDs: [])
        let dict = node.toDict()
        #expect(dict["value"] as? String == value)
        #expect(dict["value_truncated"] == nil)
    }

    // MARK: - TreeSerializer

    @Test("Serializes empty node list")
    func serializeEmpty() {
        let result = TreeSerializer.serialize(nodes: [])
        #expect(result.isEmpty)
    }

    @Test("Serializes multiple nodes")
    func serializeMultiple() {
        let nodes = [
            AXNode(id: "e0", role: "window", name: "Main", value: nil, states: [], bounds: nil, childIDs: ["e1"]),
            AXNode(id: "e1", role: "button", name: "OK", value: nil, states: [], bounds: nil, childIDs: []),
        ]
        let result = TreeSerializer.serialize(nodes: nodes)
        #expect(result.count == 2)
        #expect(result[0]["id"] as? String == "e0")
        #expect(result[1]["id"] as? String == "e1")
    }

    @Test("toJSON produces valid JSON string")
    func toJSONValid() {
        let nodes = [
            AXNode(id: "e0", role: "button", name: "OK", value: nil, states: [], bounds: nil, childIDs: []),
        ]
        let json = TreeSerializer.toJSON(nodes: nodes)
        // Should be parseable JSON
        let data = json.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data)
        #expect(parsed != nil)
    }

    @Test("toJSON of empty list returns []")
    func toJSONEmpty() {
        let json = TreeSerializer.toJSON(nodes: [])
        #expect(json == "[]")
    }
}
