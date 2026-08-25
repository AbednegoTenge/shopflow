const AWSXRay = require('aws-xray-sdk-core');
const { EventBridgeClient, PutEventsCommand } = require('@aws-sdk/client-eventbridge');

const client = AWSXRay.captureAWSv3Client(new EventBridgeClient({ region: process.env.AWS_REGION || 'us-east-1' }));

async function publishOrderCreated(orderId) {
    await client.send(new PutEventsCommand({
        Entries: [{
            Source: 'shopflow.app',
            DetailType: 'OrderCreated',
            Detail: JSON.stringify({ orderId })
        }]
    }));
}

module.exports = { publishOrderCreated };
