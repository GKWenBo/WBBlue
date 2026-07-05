//
//  HexTests.swift
//  WBBlueSwiftTests
//
//  hex 编解码纯函数单元测试。
//

import Foundation
import Testing
@testable import WBBlueSwift

struct HexTests {

    @Test("hex 字符串解码为 Data")
    func decodeBasic() {
        #expect(Data(hexString: "A55A01") == Data([0xA5, 0x5A, 0x01]))
    }

    @Test("解码容忍空格、0x 前缀与大小写混排")
    func decodeTolerant() {
        #expect(Data(hexString: "0xa5 5A 01") == Data([0xA5, 0x5A, 0x01]))
    }

    @Test("奇数长度或非法字符返回 nil")
    func decodeInvalid() {
        #expect(Data(hexString: "A5F") == nil)
        #expect(Data(hexString: "GG") == nil)
    }

    @Test("空字符串解码为空 Data")
    func decodeEmpty() {
        #expect(Data(hexString: "") == Data())
    }

    @Test("Data 编码为大写 hex,可带分隔符")
    func encode() {
        let data = Data([0xA5, 0x5A, 0x01])
        #expect(data.hexString() == "A55A01")
        #expect(data.hexString(separator: " ") == "A5 5A 01")
    }
}
