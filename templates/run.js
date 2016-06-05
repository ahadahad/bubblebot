//Recommended to set this for easier debugging
Error.stackTraceLimit = Infinity;

console.log('run.js: requiring bubblebot');

bubblebot = require('bubblebot');

console.log('run.js: initializing configuration');

//Loads configuration from configuration.json.
//Alternately, can pass an object with configuration values to use instead.
bubblebot.initialize_configuration(function (){
    console.log('run.js: creating server');

    //Create the bubblebot server
    server = new bubblebot.Server()

    console.log('run.js: starting server');

    //Do any customization here

    //Start the server
    server.start()

    console.log('run.js: server started');
});
