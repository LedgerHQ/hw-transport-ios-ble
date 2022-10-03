//
//  APDUTests.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/15/22.
//

import XCTest
@testable import BleTransport

final class APDUTests: XCTestCase {
    
    func testRawInitNotHexString() {
        let apdu = APDU(raw: "NotHex")
        
        XCTAssert(apdu.data.isEmpty)
    }
    
    func testEmptyRawInit() {
        let apdu = APDU(raw: "")
        
        XCTAssert(apdu.data.isEmpty)
    }
    
    func testEmptyDataInit() {
        let apdu = APDU(data: [])
        
        XCTAssert(apdu.data.isEmpty)
        XCTAssert(apdu.chunks.isEmpty)
    }
    
    func testRawInitOddVersusEvenStringCount() {
        let apduOdd = APDU(raw: "abc")
        let apduEven = APDU(raw: "abcd")
        
        XCTAssert(apduOdd.data.isEmpty)
        XCTAssert(!apduEven.data.isEmpty)
    }
    
    func testChunkSingleFrame() {
        let dataToUse: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06]
        let apdu = APDU(data: dataToUse)
        
        XCTAssert(apdu.chunks.count == 1)
        
        let frame = apdu.chunks.first!
        
        let intFrame = [UInt8](frame).map({ Int($0) })
        XCTAssert(!frame.isEmpty)
        
        /// Head is always 0x05 for Nano X
        XCTAssert(frame.first == 0x05)
        
        /// Index is 2 bytes
        XCTAssert((intFrame[1] * 256) + intFrame[2] == 0)
        
        /// Size is 2 bytes
        XCTAssert((intFrame[3] * 256) + intFrame[4] == dataToUse.count)
        
        /// The amount of actual data bytes we send has to be equal to the mtuSize minus the header/index/size bytes or equal to the total data length
        let currentFrameActualDataCount = (intFrame.count - 5)
        XCTAssert(currentFrameActualDataCount == dataToUse.count)
    }
    
    func testChunkMultipleFrames() {
        let dataToUse: [UInt8] = Array(repeating: 0x01, count: APDU.mtuSize * 3 + 10)
        let apdu = APDU(data: dataToUse)
        
        let frames = apdu.chunks
        
        for (index, frame) in frames.enumerated() {
            let intFrame = [UInt8](frame).map({ Int($0) })
            XCTAssert(!frame.isEmpty)
            
            /// Head is always 0x05 for Nano X
            XCTAssert(frame.first == 0x05)
            
            /// Index is 2 bytes
            XCTAssert((intFrame[1] * 256) + intFrame[2] == index)
            
            let maxDataForCurrentFrame = index == 0 ? (APDU.mtuSize - 5) : (APDU.mtuSize - 3)
            let currentFrameActualDataCount = (intFrame.count - (index == 0 ? 5 : 3))
            
            if index == 0 {
                /// We only send the size in the first frame
                XCTAssert((intFrame[3] * 256) + intFrame[4] == dataToUse.count)
                
                /// The amount of actual data bytes we send has to be equal to the mtuSize minus the header/index/size bytes or equal to the total data length
                XCTAssert(currentFrameActualDataCount == min(maxDataForCurrentFrame, dataToUse.count))
            } else {
                /// In the first frame we used 2 bytes for the size
                let alreadySentDataCount = index * maxDataForCurrentFrame - 2
                
                /// The amount of actual data bytes we send has to be equal to the mtuSize minus the header/index/size bytes or equal to the total data length
                XCTAssert(currentFrameActualDataCount == min(maxDataForCurrentFrame, dataToUse.count - alreadySentDataCount))
            }
        }
    }
}
