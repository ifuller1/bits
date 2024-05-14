"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.helloWorld = void 0;
const helloWorld = async (event, context) => {
    return {
        statusCode: 200,
        body: JSON.stringify({
            message: "Hello, world!!! 09.41",
        }),
    };
};
exports.helloWorld = helloWorld;
