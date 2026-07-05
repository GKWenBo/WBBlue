//
//  Hex.swift
//  WBBlueSwift
//
//  hex 字符串与 Data 的互转。BLE 调试(读写特征、私有协议帧)大量使用 hex 表示,
//  解码端对用户输入做宽容处理:忽略空白、逗号与 0x 前缀,大小写不敏感。
//

import Foundation

extension Data {

    /// 从 hex 字符串解码。非法字符或清理后长度为奇数返回 nil。
    init?(hexString: String) {
        var cleaned = hexString.lowercased()
        for junk in ["0x", " ", "\n", "\t", ","] {
            cleaned = cleaned.replacingOccurrences(of: junk, with: "")
        }
        guard cleaned.count.isMultiple(of: 2) else { return nil }

        var bytes = [UInt8]()
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    /// 编码为大写 hex 字符串,可指定字节间分隔符(默认无)。
    func hexString(separator: String = "") -> String {
        map { String(format: "%02X", $0) }.joined(separator: separator)
    }
}
