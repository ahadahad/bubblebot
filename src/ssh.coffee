ssh = exports


ssh.run = (host, private_key, cmd, {can_fail, timeout}) ->
    stream = exec_ssh host, private_key, cmd

    output = []

    exit_code = null

    close_block = Block()
    block = Block()
    on_data = (data) ->
        output.push data
    stream.on 'data', on_data

    on_stderr_data = (data) ->
        output.push data
    stream.stderr.on 'data', on_stderr_data

    on_error = (err) ->
        block.fail err
        close_block.fail err
    stream.on 'error', on_error

    on_close = (code) ->
        exit_code = code
        setTimeout ->
            close_block.success()
        , 200
    stream.on 'close', on_close

    on_end = ->
        setTimeout ->
            block.success()
        , 200
    stream.on 'end', on_end

    close_block.wait(timeout)
    block.wait(10)

    stream.removeListener 'data', on_data
    stream.stderr.removeListener 'data', on_stderr_data
    stream.removeListener 'error', on_error
    stream.removeListener 'close', on_close
    stream.removeListener 'end', on_end

    output = output.join ''

    if exit_code isnt 0 and not can_fail
        throw new Error 'call "' + cmd + '" failed with non-zero exit code ' + exit_code + ': ' + output

    return output


ssh.upload_file = (host, privateKey, filename, path) ->
    block = u.Block 'upload_file'
    scp2.scp filename, {host, privateKey, path}, block.make_cb()
    block.wait()

ssh.write_file = (host, privateKey, destination, content) ->
    block = u.Block 'write_file'
    client = new scp2.Client {host, privateKey}
    client.write {destination, content}, block.make_Cb()
    block.wait()

exec_ssh = (host, private_key, cmd) ->
    block = u.Block('exec_ssh')
    conn = get_connection(host, private_key)
    conn.exec cmd, {pty: true}, (err, stream) ->
        if err
            block.fail err
        else
            block.success stream
    handler = (err) ->
        block.fail err
    conn.once 'error', handler
    res = block.wait()
    conn.removeListener 'error', handler
    return res


#Gets or creates a connection to the given host
get_connection = (host, private_key) ->
    ssh_connections = u.get_context().ssh_connections

    if not ssh_connections[host]

        conn = new SSHClient()
        block = u.Block('getting connection')

        conn.on 'ready', -> block.success()

        conn.on 'end', ->
            if ssh_connections[host] is conn
                delete ssh_connections[host]

        conn.on 'close', ->
            if ssh_connections[host] is conn
                delete ssh_connections[host]

        conn.connect {
            host: to_hostname host
            port: 22
            username: 'ec2-user'
            privateKey: private_key
        }

        conn.once 'error', (err) -> block.fail err

        block.wait()

        ssh_connections[host] = conn
    return ssh_connections[host]

u = require './utilities'
SSHClient = require('ssh2').Client
scp2 = require 'scp2'