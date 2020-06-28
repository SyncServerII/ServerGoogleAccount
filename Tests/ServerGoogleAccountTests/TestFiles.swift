//
//  TestFiles.swift
//  ServerTests
//
//  Created by Christopher G Prince on 10/23/18.
//

import Foundation
import XCTest
import ServerShared

struct TestFile {
    enum FileContents {
        case string(String)
        case url(URL)
    }
    
    let md5CheckSum:String // Google
    
    let contents: FileContents
    let mimeType: MimeType
    
    func checkSum(type: AccountScheme.AccountName) -> String! {
        switch type {
        case AccountScheme.google.accountName:
            return md5CheckSum
            
        default:
            XCTFail()
            return nil
        }
    }
    
    static let test1 = TestFile(
        md5CheckSum: "b10a8db164e0754105b7a99be72e3fe5",
        contents: .string("Hello World"),
        mimeType: .text)
    
    static let test2 = TestFile(
        md5CheckSum: "a9d2b23e3001e558213c4ee056f31ba1",
        contents: .string("This is some longer text that I'm typing here and hopefullly I don't get too bored"),
        mimeType: .text)

#if os(macOS)
        private static let catFileURL = URL(fileURLWithPath: "/tmp/Cat.jpg")
#else
        private static let catFileURL = URL(fileURLWithPath: "./Resources/Cat.jpg")
#endif

    static let catJpg = TestFile(
        md5CheckSum: "5edb34be3781c079935b9314b4d3340d",
        contents: .url(catFileURL),
        mimeType: .jpeg)

#if os(macOS)
        private static let urlFile = URL(fileURLWithPath: "/tmp/example.url")
#else
        private static let urlFile = URL(fileURLWithPath: "./Resources/example.url")
#endif

    // The specific hash values are obtained from bootstraps in the iOS client test cases.
    static let testUrlFile = TestFile(
        md5CheckSum: "958c458be74acfcf327619387a8a82c4",
        contents: .url(urlFile),
        mimeType: .url)
}
