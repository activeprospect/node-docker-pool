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


  drain: (callback) ->
    @_log.info('draining')
    @_pool.min = 0
    teardown = =>
      @_log.info('drained')
      containers = []
      for _, container of @_containers
        containers.push container

      if containers.length > 0 || @_destroyQueue.length() > 0
        drain = @_destroyQueue.drain
        @_destroyQueue.drain = =>
          @_destroyQueue.drain = drain
          callback()
        for container in containers
          @destroy container, (->)
      else
        callback()

    if @_pool.waitingClientsCount() > 0
      @_pool.drain ->
        teardown()
    else
      teardown()


  destroy: (container, callback) ->
    @_destroyQueue.push container, (err) =>
      if err
        if container.destroyCount >= @_maxDestroyAttempts
          container._log.info 'cannot destroy: giving up'
          callback(err) if callback
        else
          container._log.info 'retry destroy'
          retry = =>
            @_destroyWorker container, callback
          setTimeout retry, 1000
      else
        delete @_containers[container.id]
        callback() if callback


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






