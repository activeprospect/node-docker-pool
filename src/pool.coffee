PoolFactory = require('generic-pool').Pool
async = require 'async'
bunyan = require 'bunyan'
Container = require './container'

class Pool
  constructor: (options={}) ->
    @_log = options.log || bunyan.createLogger(name: 'docker-pool', module: 'pool')
    delete options.log

    @_maxDestroyAttempts = options.maxDestroyAttempts || 10
    delete options.maxDestroyAttempts

    @_containerOptions = options.container
    @_containerOptions.log = @_log
    delete options.container

    for key, value of options
      @[key] = value

    @_createQueue = async.queue(@_createWorker, 1)
    @_destroyQueue = async.queue(@_destroyWorker, 1)

    @_containers = {}
    @_pool = new PoolFactory(@)

  acquire: (callback, priority) =>
    @_pool.acquire callback, priority

  release: (container) ->
    @_pool.release(container)

  create: (callback) =>
    @_createQueue.push {}, callback

  destroyAll: (callback) ->
    for _, container of @_containers
      @_enqueueDestroy container
    if @_destroyQueue.length() == 0
      return callback()
    @_destroyQueue.drain = =>
      @_destroyQueue.drain = null
      callback()

  destroy: (container) ->
    @_enqueueDestroy container

  _enqueueDestroy: (container, callback) ->
    @_log.info(container: container.id, "enqueuing for destroy (awaiting #{@_destroyQueue.length()} others)")

    cb = (err) ->
      callback(err) if callback

    container.destroyCount ?= 0
    @_destroyQueue.push container, (err) =>
      container.destroyCount += 1
      log = @_log.child(container: container.id, retries: container.destroyCount)
      giveUp = @_maxDestroyAttempts <= container.destroyCount
      if err
        cb(err)
        if giveUp
          log.info 'cannot destroy: giving up'
        else
          log.info 'retry destroy'
          @_enqueueDestroy container, callback
      else
        log.info 'destroyed'
        delete @_containers[container.id]
        cb()

  _createWorker: (_, callback) =>
    container = new Container(@_containerOptions)
    container.start (err) =>
      return callback(err) if err
      @_containers[container.id] = container
      @_log.info(container: container.id, 'ready')
      callback(null, container)

  _destroyWorker: (container, callback) =>
    container.destroy callback



module.exports = Pool






