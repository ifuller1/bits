import {
    APIGatewayProxyEvent,
    APIGatewayProxyResult,
    Handler,
} from "aws-lambda";
import {
    DynamoDBClient,
    PutItemCommand,
    PutItemCommandInput,
} from "@aws-sdk/client-dynamodb";

import BigNumber from "bignumber.js";
import { z } from "zod";

// DynamoDB client
const dynamoDb = new DynamoDBClient();

// Define the schema using Zod
const paymentSchema = z.object({
    paymentId: z.string().uuid(),
    userId: z.string().uuid(),
    paymentTimestamp: z.string().refine((val) => !isNaN(Date.parse(val)), {
        message: "Invalid date format, should be ISO 8601",
    }),
    description: z.string(),
    currency: z
        .string()
        .length(3, { message: "Currency should be a 3-letter ISO code" }),
    amount: z.string(),
});

export const handler: Handler<
    APIGatewayProxyEvent,
    APIGatewayProxyResult
> = async (event) => {
    try {
        // Parse the body from the event
        const body =
            typeof event.body === "string"
                ? JSON.parse(event.body || "{}")
                : event.body;

        console.log("Received event:", JSON.stringify(event, null, 2));

        try {
            // Validate the parsed JSON against the schema
            paymentSchema.parse(body);
        } catch (error: any) {
            return {
                statusCode: 400,
                body: JSON.stringify({
                    message: error.message || "Bad Request: Invalid input data",
                    stack: error.stack,
                }),
            };
        }

        console.log("Validated input:", JSON.stringify(body, null, 2));

        // Use BigNumber for the amount to ensure precision
        const amount = new BigNumber(body.amount);

        console.log("Parsed amount:", amount.toString());

        // Prepare data for DynamoDB
        const item: PutItemCommandInput = {
            TableName: "CommitmentsTable",
            Item: {
                id: { S: body.paymentId }, // Use the paymentId as the primary key
                paymentId: { S: body.paymentId }, //
                userId: { S: body.userId }, //
                paymentTimestamp: { S: body.paymentTimestamp }, //
                description: { S: body.description }, //
                currency: { S: body.currency }, //
                amountString: { S: amount.toString() }, //, preserving precision
                amount: { N: amount.toString() },
            },
        };

        console.log(
            "Writing to DynamoDB:",
            JSON.stringify(item, null, 2),
            dynamoDb,
            "<<"
        );

        await dynamoDb.send(new PutItemCommand(item));

        console.log("Successfully wrote to DynamoDB");

        return {
            statusCode: 200,
            body: JSON.stringify({
                message: "Payment commitmment recorded successfully",
                paymentId: body.paymentId,
                amount: amount.toString(),
                currency: body.currency,
            }),
        };
    } catch (error: any) {
        return {
            statusCode: 500,
            body: JSON.stringify({
                message: error.message || "Unknown error processing payment.",
            }),
        };
    }
};
