//
//  QueueTests.swift
//  BleTransport
//
//  Created by Dante Puglisi on 8/15/22.
//

import XCTest
@testable import BleTransport

class QueueTests: XCTestCase {

    class OperationMock: TaskOperation {
        var finished: EmptyResponse?
        
        var hasStarted = false
        
        func start() {
            hasStarted = true
        }
    }
    
    var queue: Queue!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        queue = Queue()
    }

    override func tearDownWithError() throws {
        queue = nil
        try super.tearDownWithError()
    }

    func testOperationGetsAddedToQueue() {
        let operation = OperationMock()
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        queue.add(operation) {
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 2, handler: nil)
        
        XCTAssert(queue.queue.count == 1)
    }
    
    func testMultipleOperationsGetAddedToQueue() {
        let operation1 = OperationMock()
        let operation2 = OperationMock()
        let operation3 = OperationMock()
        
        let exp = expectation(description: "\(#function)\(#line)")
        exp.expectedFulfillmentCount = 3
        
        queue.add(operation1) {
            exp.fulfill()
        }
        queue.add(operation2) {
            exp.fulfill()
        }
        queue.add(operation3) {
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 2, handler: nil)
        
        XCTAssert(queue.queue.count == 3)
    }
    
    func testCallingNextRemovesFirstOperation() {
        let operation1 = OperationMock()
        let operation2 = OperationMock()
        
        let exp = expectation(description: "\(#function)\(#line)")
        exp.expectedFulfillmentCount = 3
        
        queue.add(operation1) {
            exp.fulfill()
        }
        queue.add(operation2) {
            exp.fulfill()
        }
        queue.next {
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 2, handler: nil)
        
        XCTAssert(queue.first === operation2)
    }
    
    func testCallingNextWhenThereIsOnlyOneOperationLeftEmptiesTheQueue() {
        let operation1 = OperationMock()
        let operation2 = OperationMock()
        
        let exp = expectation(description: "\(#function)\(#line)")
        exp.expectedFulfillmentCount = 4
        
        queue.add(operation1) {
            exp.fulfill()
        }
        queue.add(operation2) {
            exp.fulfill()
        }
        queue.next {
            exp.fulfill()
        }
        queue.next {
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 2, handler: nil)
        
        XCTAssert(queue.isEmpty)
    }
    
    func testRemoveAllFromQueue() {
        let operation1 = OperationMock()
        let operation2 = OperationMock()
        
        let exp = expectation(description: "\(#function)\(#line)")
        exp.expectedFulfillmentCount = 3
        
        queue.add(operation1) {
            exp.fulfill()
        }
        queue.add(operation2) {
            exp.fulfill()
        }
        queue.removeAll {
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 2, handler: nil)
        
        XCTAssert(queue.isEmpty)
    }
    
    func testAddingFirstOperationToQueueStartsIt() {
        let operation = OperationMock()
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        queue.add(operation) {
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 2, handler: nil)
        
        let firstOperationInQueue = (queue.first as? OperationMock)
        XCTAssert(firstOperationInQueue?.hasStarted == true)
    }
    
    func testAddingAnOperationToNonEmptyQueueDoesNotStartOperation() {
        let operation1 = OperationMock()
        let operation2 = OperationMock()
        
        let exp = expectation(description: "\(#function)\(#line)")
        exp.expectedFulfillmentCount = 2
        
        queue.add(operation1) {
            exp.fulfill()
        }
        queue.add(operation2) {
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 2, handler: nil)
        
        let lastOperationInQueue = (queue.queue.last as? OperationMock)
        XCTAssert(lastOperationInQueue?.hasStarted == false)
    }
    
    func testMovingToNextOperationStartsIt() {
        let operation1 = OperationMock()
        let operation2 = OperationMock()
        
        let exp = expectation(description: "\(#function)\(#line)")
        exp.expectedFulfillmentCount = 3
        
        queue.add(operation1) {
            exp.fulfill()
        }
        queue.add(operation2) {
            exp.fulfill()
        }
        queue.next {
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 2, handler: nil)
        
        let firstOperationInQueue = (queue.first as? OperationMock)
        XCTAssert(firstOperationInQueue?.hasStarted == true)
    }

}
