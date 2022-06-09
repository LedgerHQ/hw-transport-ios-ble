//
//  test.js
//  BleTransportDemo
//
//  Created by Dante Puglisi on 5/30/22.
//

function doubler(p1) {
    return new Promise((resolve, reject) => {
        resolve((p1 * 2).toString())
    })
}

function iOSWrapper(callbackFunction, functionToCall, arguments) {
    eval(functionToCall)(...arguments).then(
        function(value) { eval(callbackFunction)(value) },
        function(error) { eval(callbackFunction)(error) }
    )
}

function testClass() {
    /*let person = Transport.createWithFirstNameLastName("first_name", "last_name");
    person.birthYear = 1987;
    
    return person;*/
    
    let transport = Transport.create()
    
    doublerCallback("10")
    
    transport.send(() => {
        doublerCallback("8")
    })
    
    return "asd"
}

function test2() {
    doublerCallback("8")
}

