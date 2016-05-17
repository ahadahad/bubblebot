slack = exports
events = require 'events'

slack.SlackClient = class SlackClient extends events.EventEmitter
    constructor: (@server) ->
        token = config.get('slack_token')
        @api = new RtmClient token, {
            dataStore: new MemoryDataStore()
            autoReconnect: true
            autoMark: true
        }
        @api.start()
        @web_client = new WebClient(token)

        @talking_to = {}
        @talking_to_lock = {}

        ready = u.Block 'slack api initializing'

        _opened = false

        @api.on 'message', @handle_message.bind(this)

        @api.on 'open', ->
            _opened = true
            ready.success()

        @api.on 'error', (err) =>
            #if we haven't opened yet, shut down the server
            if not _opened
                msg = 'ERROR CONNECTING TO SLACK: ' + (err.stack ? err)
                @shutdown msg

            #Otherwise, this is just an uncaught exception
            else
                throw err

        @api.on 'disconnect', =>
            @shutdown 'SLACK CLIENT DISCONNECTED.  SHUTTING DOWN THE SERVER IN 30 SECONDS...'

        ready.wait()

    #If our slack client becomes broken, we want to kill bubblebot because we can't communicate.
    #We log to the default logger and to the console, wait 30 seconds to give logs a chance to flow
    #and to avoid an excessive number of retries, then shut down the server
    shutdown: (msg) ->
        setTimeout ->
            process.exit(1)
        , 30000
        console.log msg
        try
            u.log msg
        catch err
            console.log err.stack ? err


    #Handles incoming messages
    handle_message: (message) ->
        channel = @api.dataStore.getChannelGroupOrDMById(message.channel)
        #If this is not a private message, ignore it
        if not channel.is_im
            return

        text = message.text

        #If we are already talking to this user, send the message to the conversation
        talk_cb = @talking_to[message.user]
        if talk_cb?
            talk_cb null, text
            delete @talking_to[message.user]

        #otherwise, interpet this as a new conversation
        @emit 'new_conversation', message.user, text

    #Sends a message to the indicated user
    message: (user_id, msg) ->
        block = u.Block 'sending message'
        @send_im user_id, msg, block.make_cb()
        block.wait()

    #Sends a message to the current user
    reply: (msg) ->
        user_id = u.context()?.user_id
        if not user_id?
            throw new Error 'tried to reply but no user / context: context is ' + u.context() + ' and user id is ' + user_id
        block = u.Block 'replying'
        @send_im user_id, msg, block.make_cb()
        block.wait()

    get_user_info: (user_id) -> @api.dataStore.getUserById(user_id)

    #Sends an im to the given user
    send_im: (user_id, msg, cb) ->
        user = @api.dataStore.getUserById(user_id)
        dm = @api.dataStore.getDMByName(user.name)
        @api.sendMessage(msg, dm.id, cb)

    #Asks the given user a question, and returns their reply
    ask: (user_id, msg, dont_cancel) ->
        #Only one thread can be trying to talk to a single user at a time...
        #We set a long timeout because we'd rather not timeout from multiple
        #threads waiting on the same user
        @talking_to_lock[user_id] ?= u.Lock(60 * 60 * 1000)

        return @talking_to_lock[user_id].run =>

            block = u.Block 'sending message'
            @send_im user_id, msg, block.make_cb()
            block.wait()

            block = u.Block 'waiting for reply'
            @talking_to[user_id] = block.make_cb()

            reminder = setTimeout ->
                @send_im 'Hey, still waiting for an answer...'
                reminder = setTimeout ->
                    @send_im "Mmm? In 2 minutes I'm going to give up..."
                , 6 * 60 * 1000
            , 2 * 60 * 1000

            try
                response = block.wait(10 * 60 * 1000)
            catch err
                if err.reason is u.TIMEOUT
                    err = new Error 'timed out waiting for user to reply'
                    err.reason = u.USER_TIMEOUT
                throw err

            if not dont_cancel and response.toLowerCase().trim() in ['cancel', 'abort']
                err = new Error 'Got a request to cancel from the user'
                err.reason = u.CANCEL

            clearTimeout reminder

            return response

    #Asks the given user to confirm something, and returns true if they want to continue,
    #false otherwise
    confirm: (user_id, msg) ->
        while true
            response = @ask user_id, msg, true
            if response.toLowerCase().trim() in ['cancel', 'abort', 'no', 'n']
                return false
            if response.toLowerCase().trim() in ['yes', 'y', 'okay', 'ok']
                return true
            u.reply "Oops, I don't understand what you mean by '#{response}'.  Try yes / y or no / n instead."

    #Sends a message to the announcements channel
    announce: (msg) ->
        u.ensure_fiber ->
            channel = @get_announcement_channel()
            block = u.Block 'sending message'
            @api.sendMessage msg, channel.id, block.make_cb()
            block.wait()


    #Sends a PM to admin users
    report: (msg) ->
        u.ensure_fiber =>
            admin_ids = @server.get_admins()
            try
                for id in admin_ids
                    u.retry =>
                        block = u.Block 'messaging admin'
                        @send_im id, msg, block.make_cb()
                        block.wait()

            catch err
                #If we can't successfully contact the admins, shut down
                @shutdown 'Failed to contact admins: ' + err.stack ? err


    #Gets the user id that owns the slack channel
    get_slack_owner: ->
        users = @get_all_users()
        for user in users
            if user.is_primary_owner
                return user.id
        throw new Error 'Could not find primary owner!: ' + JSON.stringify(users)

    #Lists all the users
    get_all_users: ->
        block = u.Block 'listing users'
        @web_client.users.list block.make_cb()
        return block.wait()


    #Returns the first channel that we are a member of
    get_announcement_channel: (cb) ->
        block = u.Block 'listing channels'
        @web_client.channels.list block.make_cb()
        res = block.wait()
        for channel in res.channels ? []
            if channel.is_member
                return channel

        throw new Error 'Not a member of any channels: ' + JSON.stringify(res)




RtmClient = require('@slack/client').RtmClient
WebClient = require('@slack/client').WebClient
MemoryDataStore = require('@slack/client').MemoryDataStore
u = require './utilities'


