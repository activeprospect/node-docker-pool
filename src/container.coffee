path = require('path')
bunyan = require('bunyan')
async = require('async')
EventEmitter = require('events').EventEmitter
shellwords = require('shellwords')
Docker = require('dockerode')


class Container extends EventEmitter
  constructor: (options={}) ->
    @_socketPath = options.dockerSocket || '/var/run/docker.sock'
    @_docker = new Docker(socketPath: @_socketPath)

    @id = null
    @name = null
    @pid = null
    @ip = null
    @startedAt = null
    @destroyCount = 0

    @_log = options.log?.child(module: 'container') || bunyan.createLogger(name: 'docker-pool', module: 'container')
    @_image = options.image
    @_command = shellwords.split(options.command)
    @_volumes = options.volumes || []
    @_ports = options.ports || []
    @_binds = options.binds || {}
    @_ramBytes = parseInt(options.ramBytes || 10485760) # 10 MB
    @_cpuShare = parseInt(options.cpuShare || 1)
    @_stopTimeout = parseInt(options.stopTimeout || 10)
    @_container = null


  start: (callback) ->
    @_createContainer (err) =>
      if err
        @_log.error(err, 'could not create')
        return callback(err)
      @_log.info('created')
      @emit('create')
      @_startContainer callback


  stop: (callback) =>
    @_container.stop t: @_stopTimeout, (err) =>
      notFound = err and err.message.match(/404/)
      if err
        if notFound
          @_log.warn('cannot be stopped: not found')
        else
          @_log.error(err, 'cannot be stopped')
          return callback(err)

      unless notFound
        @_log.info('stopped')
        @emit('stop')

      callback()


  remove: (callback) =>
    @_container.remove (err) =>
      notFound = err and err.message.match(/404/)
      if err
        if notFound
          @_log.warn('cannot be removed: not found')
        else
          @_log.error(err, 'cannot be removed')
          return callback(err)

      unless notFound
        @emit('remove')
        @_log.info('removed')

      callback()


  destroy: (callback) ->
    @_log.info(retries: @destroyCount, 'destroying')
    @destroyCount++

    cb = callback
    callback = (err) ->
      cb(err) if cb

    timedOut = false

    timeoutCallback = =>
      timedOut = true
      err = new Error('timeout waiting for destroy')
      @_log.error(retries: @destroyCount, err)
      callback(err)

    timeout = setTimeout(timeoutCallback, 5000)

    pause = ->
      setTimeout(callback, 1000)

    async.series [@stop, pause, @remove], (err) =>
      return if timedOut
      clearTimeout(timeout)
      unless err
        @emit('destroy')
        @_log.info('destroyed')
      callback(err) if callback


  restart: (callback) ->
    cb = (err) ->
      callback(err) if callback

    @_container.restart t: @_stopTimeout, (err) =>
      return cb(err) if err
      @emit('restart')
      cb()


  info: (callback) ->
    @_container.inspect callback


  _createContainer: (callback) ->
    exposedPorts = @_ports.reduce ((ports, containerPort) =>
      ports["#{containerPort}/tcp"] = {}
      ports
    ), {}

    volumes = @_volumes.reduce ((vols, volume)->
      vols[volume] = {}
      vols
    ), {}

    options =
      Image: @_image
      Tty: false
      OpenStdin: false
      StdinOnce: false
      ExposedPorts: exposedPorts
      Volumes: volumes

    options.Memory = @_ramBytes if @_ramBytes
    options.CpuShare = @_cpuShare if @_cpuShare
    options.Cmd = @_command if @_command

    @_docker.createContainer options, (err, container) =>
      return callback(err, container) if err
      @id = container.id[0...12]
      @_log = @_log.child(container: @id)
      @_container = container
      callback()


  _startContainer: (callback) ->
    binds = Object.keys(@_binds).map (hostBind) =>
      "#{hostBind}:#{@_binds[hostBind]}"

    options =
      Binds: binds

    @_container.start options, (err) =>
      if (err)
        @_log.error(err, 'could not start')
        return callback(err, @)
      @_log.info('started')

      @info (err, info) =>
        if (err)
          @_log.error(err, 'could not get info')
          return callback(err, info)
        @_log.info('got info')
        @_parseInfo(info)
        @emit('start')
        callback(null, @)


  _parseInfo: (info) ->
    if info
      @name = info.Name.replace(/^\//, '')
      @pid = info.State.Pid
      @ip = info.NetworkSettings.IPAddress
      @startedAt = new Date(info.State.StartedAt)


module.exports = Container