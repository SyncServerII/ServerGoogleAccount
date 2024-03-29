//
//  GoogleDriveTests.swift
//  Server
//
//  Created by Christopher Prince on 1/7/17.
//
//

import XCTest
import Foundation
import HeliumLogger
import LoggerAPI
import ServerShared
@testable import ServerGoogleAccount
import ServerAccount

struct GooglePlist: Decodable, GoogleCredsConfiguration {
    let refreshToken: String
    let GoogleServerClientId: String?
    let GoogleServerClientSecret: String?
    
    static func load(from url: URL) -> Self {
        guard let data = try? Data(contentsOf: url) else {
            fatalError("Could not get data from url")
        }

        let decoder = PropertyListDecoder()

        guard let plist = try? decoder.decode(Self.self, from: data) else {
            fatalError("Could not decode the plist")
        }

        return plist
    }
}

class GoogleDriveTests: XCTestCase {
    // In my Google Drive, at the top-level:
    let knownPresentFolder = "Programming"
    let knownPresentFile = "DO-NOT-REMOVE.txt"
    
    let knownPresentImageFile = "DO-NOT-REMOVE.png"
    let knownPresentURLFile = "DO-NOT-REMOVE.url"

    // This is special in that (a) it contains only two characters, and (b) it was causing me problems for downloading on 2/4/18.
    let knownPresentFile2 = "DO-NOT-REMOVE2.txt"
    
    let knownAbsentFolder = "Markwa.Farkwa.Blarkwa"
    let knownAbsentFile = "Markwa.Farkwa.Blarkwa"
    let knownAbsentURLFile = "Markwa.Farkwa.Blarkwa.url"

    // Folder that will be created and removed.
    let folderCreatedAndDeleted = "abcdefg12345temporary"
    
    let plist = GooglePlist.load(from: URL(fileURLWithPath: "/Users/chris/Developer/Private/ServerGoogleAccount/token.plist"))
    let plistRevoked = GooglePlist.load(from: URL(fileURLWithPath: "/Users/chris/Developer/Private/ServerGoogleAccount/tokenRevoked.plist"))
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testListFiles() {
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = plist.refreshToken
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            guard error == nil, creds.accessToken != nil else {
                XCTFail("Failed to fresh: \(String(describing: error))")
                exp.fulfill()
                return
            }
            
            creds.listFiles { json, error in
                guard error == nil else {
                    XCTFail()
                    exp.fulfill()
                    return
                }
                
                guard let json = json else {
                    XCTFail()
                    exp.fulfill()
                    return
                }
                
                XCTAssert(json.count > 0)
                exp.fulfill()
            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }

    func searchForFolder(name:String, presentExpected:Bool) {
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = plist.refreshToken
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            guard error == nil, creds.accessToken != nil else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            creds.searchFor(.folder, itemName: name) { result, error in
                if presentExpected {
                    XCTAssert(result != nil)
                }
                else {
                    XCTAssert(result == nil)
                }
                XCTAssert(error == nil)
                exp.fulfill()
            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }

    func searchForFile(name:String, withMimeType mimeType:String, inFolder folderName:String?, presentExpected:Bool) {
    
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = plist.refreshToken
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        Log.debug("Folder name: \(String(describing: folderName))")
        
        func searchForFile(parentFolderId:String?) {
            creds.searchFor(.file(mimeType:mimeType, parentFolderId:parentFolderId), itemName: name) { result, error in
                if presentExpected {
                    XCTAssert(result != nil, "\(String(describing: error))")
                }
                else {
                    XCTAssert(result == nil)
                }
                XCTAssert(error == nil)
                exp.fulfill()
            }
        }
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            if folderName == nil {
                searchForFile(parentFolderId: nil)
            }
            else {
                creds.searchFor(.folder, itemName: folderName!) { result, error in
                    XCTAssert(result != nil)
                    XCTAssert(error == nil)
                    searchForFile(parentFolderId: result!.itemId)
                }
            }
        }

        waitForExpectations(timeout: 20, handler: nil)
    }
    
    func testSearchForPresentFolder() {
        searchForFolder(name: self.knownPresentFolder, presentExpected: true)
    }
    
    func testSearchForAbsentFolder() {
        searchForFolder(name: self.knownAbsentFolder, presentExpected: false)
    }
    
    func testSearchForPresentFile() {
        searchForFile(name: knownPresentFile, withMimeType: "text/plain", inFolder: nil, presentExpected: true)
    }
    
    func testSearchForPresentImageFile() {
        searchForFile(name: knownPresentImageFile, withMimeType: "image/png", inFolder: nil, presentExpected: true)
    }
    
    // On success, returns the uploaded filename
    @discardableResult
    func uploadFile(accountType: AccountScheme.AccountName, creds: CloudStorage, deviceUUID:String, testFile: TestFile, uploadRequest:UploadFileRequest, fileVersion: FileVersionInt, options:CloudStorageFileNameOptions? = nil, nonStandardFileName: String? = nil, failureExpected: Bool = false, errorExpected: CloudStorageError? = nil, expectAccessTokenRevokedOrExpired: Bool = false) -> String? {
    
        var fileContentsData: Data!
        
        switch testFile.contents {
        case .string(let fileContents):
            fileContentsData = fileContents.data(using: .ascii)!
        case .url(let url):
            fileContentsData = try? Data(contentsOf: url)
        }
        
        guard fileContentsData != nil else {
            XCTFail("No fileContentsData")
            return nil
        }
        
        var cloudFileName:String!
        if let nonStandardFileName = nonStandardFileName {
            cloudFileName = nonStandardFileName
        }
        else {
            guard let mimeType = uploadRequest.mimeType else {
                XCTFail()
                return nil
            }
            cloudFileName = Filename.inCloud(deviceUUID: deviceUUID, fileUUID: uploadRequest.fileUUID, mimeType: mimeType, fileVersion: fileVersion)
        }
        
        let exp = expectation(description: "\(#function)\(#line)")

        creds.uploadFile(cloudFileName: cloudFileName, data: fileContentsData, options: options) { result in
            switch result {
            case .success(let checkSum):
                XCTAssert(testFile.checkSum(type: accountType) == checkSum)
                Log.debug("checkSum: \(checkSum)")
                if failureExpected {
                    XCTFail()
                }
            case .failure(let error):
                if expectAccessTokenRevokedOrExpired {
                    XCTFail()
                }
                
                cloudFileName = nil
                Log.debug("uploadFile: \(error)")
                if !failureExpected {
                    XCTFail()
                }
                
                if let errorExpected = errorExpected {
                    guard let error = error as? CloudStorageError else {
                        XCTFail()
                        exp.fulfill()
                        return
                    }
                    
                    XCTAssert(error == errorExpected)
                }
            case .accessTokenRevokedOrExpired:
                if !expectAccessTokenRevokedOrExpired {
                    XCTFail()
                }
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        return cloudFileName
    }
    
    func fullUpload(file: TestFile, mimeType: String, nonStandardFileName: String? = nil) {
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = plist.refreshToken
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            exp.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)
        
        // Do the upload
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUID
        uploadRequest.mimeType = mimeType
        uploadRequest.sharingGroupUUID = UUID().uuidString
        uploadRequest.checkSum = file.md5CheckSum

        let options = CloudStorageFileNameOptions(cloudFolderName: self.knownPresentFolder, mimeType: mimeType)
        
        let fileVersion: FileVersionInt = 0
        
        uploadFile(accountType: AccountScheme.google.accountName, creds: creds, deviceUUID: deviceUUID, testFile: file, uploadRequest: uploadRequest, fileVersion: fileVersion, options: options, nonStandardFileName: nonStandardFileName)
        
        // The second time we try it, it should fail with CloudStorageError.alreadyUploaded -- same file.
        uploadFile(accountType: AccountScheme.google.accountName, creds: creds, deviceUUID: deviceUUID, testFile: file, uploadRequest: uploadRequest, fileVersion: fileVersion, options: options, nonStandardFileName: nonStandardFileName, failureExpected: true, errorExpected: CloudStorageError.alreadyUploaded)
    }
    
    
    // Searches in knownPresentFolder
    func lookupFile(cloudFileName: String, mimeType: MimeType = .text, expectError:Bool = false) -> Bool? {
        var foundResult: Bool?
        
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return nil
        }
        
        creds.refreshToken = plist.refreshToken
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            let options = CloudStorageFileNameOptions(cloudFolderName: self.knownPresentFolder, mimeType: mimeType.rawValue)
            
            creds.lookupFile(cloudFileName:cloudFileName, options:options) { result in
                switch result {
                case .success(let found):
                    if expectError {
                        XCTFail()
                    }
                    else {
                       foundResult = found
                    }
                case .failure, .accessTokenRevokedOrExpired:
                    if !expectError {
                        XCTFail()
                    }
                }
                
                exp.fulfill()
            }
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        return foundResult
    }
    
    func testBootStrapTestSearchForPresentURLFile() {
        let file = knownPresentURLFile
        if let found = lookupFile(cloudFileName: file, mimeType: .url) {
            // Uploads to knownPresentFolder
            if !found {
                fullUpload(file: TestFile.testUrlFile, mimeType: MimeType.url.rawValue, nonStandardFileName: file)
            }
        }
        else {
            XCTFail()
        }
    }
    
    func testSearchForPresentURLFile() {
        searchForFile(name: knownPresentURLFile, withMimeType: MimeType.url.rawValue, inFolder: knownPresentFolder, presentExpected: true)
    }
    
    func testSearchForAbsentFile() {
        searchForFile(name: knownAbsentFile, withMimeType: "text/plain", inFolder: nil, presentExpected: false)
    }
    
   func testSearchForAbsentURLFile() {
        searchForFile(name: knownAbsentURLFile, withMimeType: MimeType.url.rawValue, inFolder: nil, presentExpected: false)
    }
    
    func testSearchForPresentFileInFolder() {
        searchForFile(name: knownPresentFile, withMimeType: "text/plain", inFolder: knownPresentFolder, presentExpected: true)
    }
    
    func testSearchForPresentURLFileInFolder() {
        searchForFile(name: knownPresentURLFile, withMimeType: MimeType.url.rawValue, inFolder: knownPresentFolder, presentExpected: true)
    }
    
    func testSearchForAbsentFileInFolder() {
        searchForFile(name: knownAbsentFile, withMimeType: "text/plain", inFolder: knownPresentFolder, presentExpected: false)
    }
    
    func testSearchForAbsentURLFileInFolder() {
        searchForFile(name: knownAbsentURLFile, withMimeType: MimeType.url.rawValue, inFolder: knownPresentFolder, presentExpected: false)
    }

    // Haven't been able to get trashFile to work yet.
/*
    func testTrashFolder() {
        let creds = GoogleCreds()
        creds.refreshToken = self.credentialsToken()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
//            creds.createFolder(folderName: "TestMe") { folderId, error in
//                XCTAssert(folderId != nil)
//                XCTAssert(error == nil)
            
                let folderId = "0B3xI3Shw5ptRdWtPR3ZLdXpqbHc"
                creds.trashFile(fileId: folderId) { error in
                    XCTAssert(error == nil)
                    exp.fulfill()
                }
//            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
*/

    func testCreateAndDeleteFolder() {
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = plist.refreshToken
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            creds.createFolder(rootFolderName: "TestMe") { folderId, error in
                XCTAssert(folderId != nil)
                XCTAssert(error == nil)
            
                creds.deleteFile(fileId: folderId!) { error in
                    XCTAssert(error == nil)
                    exp.fulfill()
                }
            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testDeleteFolderThatDoesNotExistFailure() {
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = plist.refreshToken
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            creds.deleteFile(fileId: "foobar") { error in
                XCTAssert(error != nil)
                exp.fulfill()
            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func deleteFile(cloudFileName: String, options: CloudStorageFileNameOptions, fileNotFoundOK: Bool = false) {

        let exp = expectation(description: "\(#function)\(#line)")

        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = plist.refreshToken
        
        creds.refresh { error in
            guard error == nil, creds.accessToken != nil else {
                print("Error: \(error!)")
                XCTFail()
                exp.fulfill()
                return
            }
            
            creds.deleteFile(cloudFileName:cloudFileName, options:options) { result in
                switch result {
                case .success:
                    break
                case .accessTokenRevokedOrExpired:
                    XCTFail()
                case .failure(let error):
                    XCTFail("\(error)")
                }
                
                exp.fulfill()
            }
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func cloudStorageFileDelete(file: TestFile, mimeType: MimeType) {
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = plist.refreshToken
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            exp.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)
        
        // Do the upload
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUID
        uploadRequest.mimeType = mimeType.rawValue
        uploadRequest.sharingGroupUUID = UUID().uuidString
        uploadRequest.checkSum = file.md5CheckSum

        let options = CloudStorageFileNameOptions(cloudFolderName: self.knownPresentFolder, mimeType: mimeType.rawValue)
        
        let fileVersion:FileVersionInt = 0
        
        uploadFile(accountType: AccountScheme.google.accountName, creds: creds, deviceUUID: deviceUUID, testFile: file, uploadRequest: uploadRequest, fileVersion: fileVersion, options: options)

        let cloudFileName = Filename.inCloud(deviceUUID: deviceUUID, fileUUID: fileUUID, mimeType: mimeType.rawValue, fileVersion: fileVersion)
        
        deleteFile(cloudFileName: cloudFileName, options: options)
    }
    
    func testCloudStorageFileDeleteWorks() {
        cloudStorageFileDelete(file: .test1, mimeType: .text)
    }
    
    func testCloudStorageURLFileDeleteWorks() {
        cloudStorageFileDelete(file: .testUrlFile, mimeType: .url)
    }
    
    func testCloudStorageFileDeleteWithRevokedRefreshToken() {
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = plist.refreshToken

        let options = CloudStorageFileNameOptions(cloudFolderName: self.knownPresentFolder, mimeType: "text/plain")
        let file = TestFile.test1
        
        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = Foundation.UUID().uuidString
        uploadRequest.mimeType = "text/plain"
        uploadRequest.sharingGroupUUID = UUID().uuidString
        uploadRequest.checkSum = file.md5CheckSum
        
        let deviceUUID = Foundation.UUID().uuidString
        
        guard let mimeType = uploadRequest.mimeType else {
            XCTFail()
            return
        }

        let cloudFileName = Filename.inCloud(deviceUUID: deviceUUID, fileUUID: uploadRequest.fileUUID, mimeType: mimeType, fileVersion: 0)

        let exp = expectation(description: "\(#function)\(#line)")

        creds.deleteFile(cloudFileName:cloudFileName, options:options) { result in
            switch result {
            case .success:
                XCTFail()
            case .accessTokenRevokedOrExpired:
                break
            case .failure:
                XCTFail()
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }

    func testCreateFolderIfDoesNotExist() {
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = plist.refreshToken
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            creds.createFolderIfDoesNotExist(rootFolderName: self.folderCreatedAndDeleted) { (folderIdA, error) in
                XCTAssert(folderIdA != nil)
                XCTAssert(error == nil)
                
                // It should be there after being created.
                creds.searchFor(.folder, itemName: self.folderCreatedAndDeleted) { (result, error) in
                    
                    XCTAssert(result != nil)
                    XCTAssert(error == nil)
                    
                    // And attempting to create it again shouldn't fail.
                    creds.createFolderIfDoesNotExist(rootFolderName: self.folderCreatedAndDeleted) { (folderIdB, error) in
                        XCTAssert(folderIdB != nil)
                        XCTAssert(error == nil)
                        XCTAssert(folderIdA == folderIdB)
                        
                        creds.deleteFile(fileId: folderIdA!) { error in
                            XCTAssert(error == nil)
                            exp.fulfill()
                        }
                    }
                }
            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }

    func testFullUploadWorks() {
        fullUpload(file: TestFile.test1, mimeType: MimeType.text.rawValue)
    }
    
    func testFullUploadWorksForURLFile() {
        fullUpload(file: TestFile.testUrlFile, mimeType: MimeType.url.rawValue)
    }
    
    func testUploadWithRevokedRefreshToken() {
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = plist.refreshToken
        
        // Do the upload
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        let file = TestFile.test1
        
        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUID
        uploadRequest.mimeType = "text/plain"
        uploadRequest.sharingGroupUUID = UUID().uuidString
        uploadRequest.checkSum = file.md5CheckSum

        let options = CloudStorageFileNameOptions(cloudFolderName: self.knownPresentFolder, mimeType: "text/plain")
        
        uploadFile(accountType: AccountScheme.google.accountName, creds: creds, deviceUUID: deviceUUID, testFile: file, uploadRequest: uploadRequest, fileVersion: 0, options: options, expectAccessTokenRevokedOrExpired: true)
    }
    
    func downloadFile(cloudFileName:String, mimeType: MimeType, expectError:Bool = false, expectedFileNotFound: Bool = false) {
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = plist.refreshToken
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            let options = CloudStorageFileNameOptions(cloudFolderName: self.knownPresentFolder, mimeType: mimeType.rawValue)
            
            creds.downloadFile(cloudFileName: cloudFileName, options:options) { result in
                switch result {
                case .success:
                    if expectError {
                        XCTFail()
                    }
                case .failure, .accessTokenRevokedOrExpired:
                    XCTFail()
                case .fileNotFound:
                    if !expectedFileNotFound {
                        XCTFail()
                    }
                }

                // A different unit test will check to see if the contents of the file are correct.
                
                exp.fulfill()
            }
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testBasicFileDownloadWorks() {
        downloadFile(cloudFileName: self.knownPresentFile, mimeType: .text)
    }
    
    func testBasicURLFileDownloadWorks() {
        downloadFile(cloudFileName: self.knownPresentURLFile, mimeType: .url)
    }
    
    func testSearchForPresentFile2() {
        searchForFile(name: knownPresentFile2, withMimeType: "text/plain", inFolder: nil, presentExpected: true)
    }
    
    func testBasicFileDownloadWorks2() {
        downloadFile(cloudFileName: self.knownPresentFile2, mimeType: .text)
    }
    
    func testFileDownloadOfNonExistentFileFails() {
        downloadFile(cloudFileName: self.knownAbsentFile, mimeType: .text, expectedFileNotFound: true)
    }
    
    func testDownloadWithRevokedRefreshToken() {
        let cloudFileName = self.knownPresentFile
        
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = plist.refreshToken
        
        let exp = expectation(description: "\(#function)\(#line)")

        let options = CloudStorageFileNameOptions(cloudFolderName: self.knownPresentFolder, mimeType: "text/plain")
        
        creds.downloadFile(cloudFileName: cloudFileName, options:options) { result in
            switch result {
            case .success:
                XCTFail()
            case .failure(let error):
                XCTFail("error: \(error)")
            case .accessTokenRevokedOrExpired:
                break
            case .fileNotFound:
                XCTFail()
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testFileDirectDownloadOfNonExistentFileFails() {
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = plist.refreshToken
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            creds.completeSmallFileDownload(fileId: "foobar") { data, error in
                if let error = error {
                    switch error {
                    case GoogleCreds.DownloadSmallFileError.fileNotFound:
                        break
                    default:
                        XCTFail()
                    }
                }
                else {
                    XCTFail()
                }
                
                exp.fulfill()
            }
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }

    func testThatAccessTokenRefreshOccursWithBadToken() {
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = plist.refreshToken
        let exp = expectation(description: "\(#function)\(#line)")
        
        // Use a known incorrect access token. We expect this to generate a 401 unauthorized, and thus cause an access token refresh. But, the refresh will work.
        creds.accessToken = "foobar"
        
        let options = CloudStorageFileNameOptions(cloudFolderName: self.knownPresentFolder, mimeType: "text/plain")
        
        creds.downloadFile(cloudFileName: self.knownPresentFile, options:options) { result in
            switch result {
            case .success:
                break
            case .failure, .accessTokenRevokedOrExpired:
                XCTFail()
            case .fileNotFound:
                XCTFail()
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testThatAccessTokenRefreshFailsWithBadRefreshToken() {
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = "foobar"
        
        let exp = expectation(description: "\(#function)\(#line)")

        let options = CloudStorageFileNameOptions(cloudFolderName: self.knownPresentFolder, mimeType: "text/plain")
        
        creds.downloadFile(cloudFileName: self.knownPresentFile, options:options) { result in
            switch result {
            case .success:
                XCTFail()
            case .failure:
                XCTFail()
            case .accessTokenRevokedOrExpired:
                break
            case .fileNotFound:
                XCTFail()
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }

    func testLookupFileWithRevokedRefreshToken() {
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        creds.refreshToken = plistRevoked.refreshToken
        
        let exp = expectation(description: "\(#function)\(#line)")

        let options = CloudStorageFileNameOptions(cloudFolderName: self.knownPresentFolder, mimeType: "text/plain")
        
        creds.lookupFile(cloudFileName:knownPresentFile, options:options) { result in
            switch result {
            case .success:
                XCTFail()
            case .failure:
                XCTFail()
            case .accessTokenRevokedOrExpired:
                break
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testLookupFileThatExists() {
        let result = lookupFile(cloudFileName: knownPresentFile)
        XCTAssert(result == true)
    }
    
    func testLookupURLFileThatExists() {
        let result = lookupFile(cloudFileName: knownPresentURLFile, mimeType: .url)
        XCTAssert(result == true)
    }
    
    func testLookupFileThatDoesNotExist() {
        let result = lookupFile(cloudFileName: knownAbsentFile)
        XCTAssert(result == false)
    }
    
    func testRevokedGoogleRefreshToken() {
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        creds.refreshToken = plistRevoked.refreshToken
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            if let error = error {
                switch error {
                case GoogleCreds.CredentialsError.expiredOrRevokedAccessToken:
                    break
                default:
                    XCTFail()
                }
            }
            else {
                XCTFail()
            }

            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    // I recently repaired an issue with a bad GoogleCredsConfiguration. I want to make sure it doesn't occur again.
    func testBadGoogleCredsConfigurationFails() {
        let badConfig = GooglePlist(refreshToken: "unused", GoogleServerClientId: "foo", GoogleServerClientSecret: "bar")
        
        guard let creds = GoogleCreds(configuration: badConfig, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = plist.refreshToken
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error != nil)
            exp.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    // This is in response to an issue arising on 8/28/21
    func testUploadFileDeleteItThenSearch() {
        let file = TestFile.test1
        
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = plist.refreshToken
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            exp.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)
        
        // Do the upload
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUID
        uploadRequest.mimeType = file.mimeType.rawValue
        uploadRequest.sharingGroupUUID = UUID().uuidString
        uploadRequest.checkSum = file.md5CheckSum

        let options = CloudStorageFileNameOptions(cloudFolderName: self.knownPresentFolder, mimeType: file.mimeType.rawValue)
        
        let fileVersion: FileVersionInt = 0
        
        guard let cloudFileName = uploadFile(accountType: AccountScheme.google.accountName, creds: creds, deviceUUID: deviceUUID, testFile: file, uploadRequest: uploadRequest, fileVersion: fileVersion, options: options) else {
            XCTFail()
            return
        }
        
        let exp2 = expectation(description: "\(#function)\(#line)")

        creds.deleteFile(cloudFileName:cloudFileName, options:options) { result in
            switch result {
            case .success:
                break
            case .accessTokenRevokedOrExpired:
                XCTFail()
            case .failure:
                XCTFail()
            }
            
            exp2.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        searchForFile(name: cloudFileName, withMimeType: file.mimeType.rawValue, inFolder: self.knownPresentFolder, presentExpected: false)
    }
    
    // This is in response to an issue arising on 8/28/21
    func testUploadFileDeleteItThenUpload() {
        let file = TestFile.test1
        
        guard let creds = GoogleCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.refreshToken = plist.refreshToken
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            exp.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)
        
        // Do the upload
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUID
        uploadRequest.mimeType = file.mimeType.rawValue
        uploadRequest.sharingGroupUUID = UUID().uuidString
        uploadRequest.checkSum = file.md5CheckSum

        let options = CloudStorageFileNameOptions(cloudFolderName: self.knownPresentFolder, mimeType: file.mimeType.rawValue)
        
        let fileVersion: FileVersionInt = 0
        
        guard let cloudFileName = uploadFile(accountType: AccountScheme.google.accountName, creds: creds, deviceUUID: deviceUUID, testFile: file, uploadRequest: uploadRequest, fileVersion: fileVersion, options: options) else {
            XCTFail()
            return
        }
        
        let exp2 = expectation(description: "\(#function)\(#line)")

        creds.deleteFile(cloudFileName:cloudFileName, options:options) { result in
            switch result {
            case .success:
                break
            case .accessTokenRevokedOrExpired:
                XCTFail()
            case .failure:
                XCTFail()
            }
            
            exp2.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        guard let _ = uploadFile(accountType: AccountScheme.google.accountName, creds: creds, deviceUUID: deviceUUID, testFile: file, uploadRequest: uploadRequest, fileVersion: fileVersion, options: options, nonStandardFileName: cloudFileName) else {
            XCTFail()
            return
        }
    }
}

