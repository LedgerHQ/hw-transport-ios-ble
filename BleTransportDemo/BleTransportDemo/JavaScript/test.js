var Buffer = require('buffer').Buffer;

async function testSendData() {
    const transport = Transport.create()
    
    const bufferToSend = Buffer.from([0x08, 0x00, 0x00, 0x00, 0x00])
    const awaitedResult = await promisify(transport.exchange(bufferToSend))
    
    print("The answer from the device is: " + awaitedResult)
    
    return awaitedResult
}

function promisify(callback) {
    return new Promise((resolve, reject) => {
        callback(function(response) {
            resolve(response)
        })
    })
}

module.exports = { 'Buffer': Buffer, 'testSendData': testSendData };
