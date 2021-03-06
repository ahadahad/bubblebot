commands = exports

build = ->
    u.log u.run_local 'rm npm-shrinkwrap.json', {can_fail: true}
    u.log u.run_local 'npm prune'
    u.run_local 'npm install'
    u.run_local 'npm dedupe'
    u.run_local 'npm shrinkwrap'
    u.log 'Build complete'


#For testing stuff
commands.temp = (access_key, secret_access_key) ->
    u.SyncRun 'temp', ->
        config.init()
        config.set 'command_line', true

        if access_key
            u.log 'Got access key from command line: ' + access_key
            config.set('accessKeyId', access_key)
        if secret_access_key
            u.log 'Got secret from command line'
            config.set('secretAccessKey', secret_access_key)

        config.init_account_specific()

        #DO WHATEVER TESTING HERE
        bbserver = bbobjects.get_bbserver()
        software.verify_supervisor bbserver, 'bubblebot', 20

        process.exit()

commands.build = ->
    u.SyncRun 'build', ->
        build()
        process.exit()

commands.publish = (access_key, secret_access_key) ->
    u.SyncRun 'publish', ->
        #Load the local configuration from disk
        config.init()

        #Indicate that we are running from the command line
        config.set 'command_line', true

        #If the user passed in an access key / secret, set it
        if access_key
            u.log 'Got access key from command line: ' + access_key
            config.set('accessKeyId', access_key)
        if secret_access_key
            u.log 'Got secret from command line'
            config.set('secretAccessKey', secret_access_key)

        config.init_account_specific()

        u.log 'Searching for bubblebot server...'

        bbserver = bbobjects.get_bbserver()

        u.log 'Found bubblebot server'

        #Ensure we have the necessary deployment key installed
        bbserver.install_private_key config.get('deploy_key_path')

        #Clone our bubblebot installation to a fresh directory, and run npm install and npm test
        install_dir = 'bubblebot-' + Date.now()
        bbserver.run('git clone ' + config.get('remote_repo') + ' ' + install_dir)
        bbserver.run("cd #{install_dir} && npm install", {timeout: 300000})

        #Create a symbolic link pointing to the new directory, deleting the old one if it exits
        bbserver.run('rm -rf bubblebot-old', {can_fail: true})
        bbserver.run("mv $(readlink #{config.get('install_directory')}) bubblebot-old", {can_fail: true})
        bbserver.run('unlink ' + config.get('install_directory'), {can_fail: true})
        bbserver.run('ln -s ' + install_dir + ' ' +  config.get('install_directory'))

        #Ask bubblebot to restart itself
        try
            results = bbserver.run("curl -X POST http://localhost:8081/shutdown")
            if results.indexOf(bubblebot_server.SHUTDOWN_ACK) is -1
                throw new Error 'Unrecognized response: ' + results
        catch err
            u.log 'Was unable to tell bubble bot to restart itself.  Server might not be running.  Will restart manually.  Error was: \n' + err.stack
            #make sure supervisord is running
            software.supervisor_start(true) bbserver
            #stop bubblebot if it is running
            bbserver.run('supervisorctl stop bubblebot', {can_fail: true})
            #start bubblebot
            res = bbserver.run('supervisorctl start bubblebot')
            if res.indexOf('ERROR (abnormal termination)') isnt -1
                console.log 'Error starting supervisor, tailing logs:'
                bbserver.run('tail -n 100 /tmp/bubblebot*')

            else
                u.log 'Waiting twenty seconds to see if it is still running...'
                try
                    software.verify_supervisor bbserver, 'bubblebot', 20
                catch err
                    console.log err.message

        process.exit()


#Installs bubblebot into a directory
#If force is set to "force", overwrites existing files
commands.install = (force) ->
    force = force is "force"

    u.SyncRun 'install', ->
        for name in ['run.js', 'configuration.json']
            u.log 'Creating ' + name
            data = fs.readFileSync __dirname + '/../templates/' + name
            try
                fs.writeFileSync name, data, {flag: if force then 'w' else 'wx'}
            catch err
                u.log 'Could not create ' + name + ' (a file with that name may already exist)'

        u.log 'Installation complete!'

        process.exit()

update = ->
    u.log 'Checking for updates...'
    u.log u.run_local 'rm npm-shrinkwrap.json', {can_fail: true}
    u.log u.run_local 'npm install bubblebot'
    u.log u.run_local 'npm update bubblebot'


commands.update = ->
    u.SyncRun 'update', ->
        update()
        build()
        process.exit()

commands.dev = ->
    u.SyncRun 'dev', ->
        u.log u.run_local 'coffee -o node_modules/bubblebot/lib -c node_modules/bubblebot/src/*.coffee && node node_modules/bubblebot/node_modules/eslint/bin/eslint.js node_modules/bubblebot/lib'
        process.exit()

commands.set_config = (name, value) ->
    u.SyncRun 'set_config', ->
        config.init()
        config.set 'command_line', true
        config.init_account_specific()

        if value.indexOf('file:') is 0
            value = fs.readFileSync value[5...], 'utf8'

        config.set_secure name, value
        u.log 'config set successfully'
        process.exit()

commands.get_config = (name) ->
    u.SyncRun 'get_config', ->
        config.init()
        config.set 'command_line', true
        config.init_account_specific()

        res = config.get_secure name
        u.log 'config for ' + name + ': '
        u.log res
        process.exit()

#Prints the help for the bubblebot command line tool
commands.print_help = ->
    u.log 'Available commands:'
    u.log '  install -- creates default files for a bubblebot installation'
    u.log '  build -- packages this directory for distribution'
    u.log '  publish -- deploys bubblebot to a remote repository'
    u.log '  update  -- updates the bubblebot code (npm update bubblebot)'
    u.log '  dev -- builds bubblebot assuming a development symlink'
    u.log '  set_config [name] [value] -- stores a secure config option in s3.  Pass file:/path/to/file for value to read in a file.'
    u.log '  get_config [name] -- retrieves a config set by set_config'
    process.exit()


u = require './utilities'
fs = require 'fs'
os = require 'os'
config = require './config'
strip_comments = require 'strip-json-comments'
path = require 'path'
bubblebot_server = require './bbserver'
bbobjects = require './bbobjects'
software = require './software'