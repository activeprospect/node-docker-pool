PoolFactory = require('generic-pool').Pool
async = require 'async'
bunyan = require 'bunyan'
Container = require './container'

class Pool

  constructor: (options={}) ->
    @_log = options.log || bunyan.createLogger(name: 'docker-pool', module: 'pool')
    delete options.log

    @_maxDestroyAttempts = @_option options.maxDestroyAttempts, 10
    delete options.maxDestroyAttempts

    @_readyCheck = @_option options.readyCheck, (container, retryCount, callback) ->
      callback(null, true, 0 ) # default callback indicates immediate readiness

    @_createConcurrency = @_option options.createConcurrency, 1
    delete options.createConcurrency

    @_disposeConcurrency = @_option options.disposeConcurrency, 1
    delete options.disposeConcurrency

    @_containerOptions = options.container
    @_containerOptions.log = @_log
    delete options.container

    for key, value of options
      @[key] = value

    @_createQueue = async.queue(@_createWorker, @_createConcurrency)
    @_destroyQueue = async.queue(@_destroyWorker, @_disposeConcurrency)

    @_containers = {}
    @_pool = new PoolFactory(@)


  acquire: (callback, priority) =>
    @_pool.acquire callback, priority


  release: (container) ->
    container._log.info('releasing')
    @_pool.release(container)


  #
  # Public: Wait for all currently acquired containers to finish their current job, then dispose of all containers.
  # An error will be thrown if acquire is called after drain.
  #
  drain: (callback) ->
    @_log.info('draining')
    @_pool.min = 0
    @_pool.drain =>
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
          @dispose container
      else
        callback()



  #
  # Public: Dispose of a container by removing it from the pool and destroying it.
  #
  dispose: (container, callback) ->
    container.on 'destroy', callback if callback
    @_pool.destroy(container)


  #
  # Internal: Used by the pool to create a new container
  #
  create: (callback) =>
    @_createQueue.push {}, callback


  #
  # Internal: Used by the pool to destroy a container
  #
  destroy: (container) ->
    afterDestroy = (err) =>
      if err
        if container.destroyCount >= @_maxDestroyAttempts
          container._log.info 'cannot destroy: giving up'
        else
          container._log.info 'retry destroy'
          retry = =>
            @_destroyWorker container, afterDestroy
          setTimeout retry, 1000
      else
        delete @_containers[container.id]

    @_destroyQueue.push container, afterDestroy


  #
  # Private: Creates a new container. This function is used as the worker for the @_createQueue.
  #
  _createWorker: (_, callback) =>
    container = new Container(@_containerOptions)
    container.start (err) =>
      return callback(err) if err
      @_containers[container.id] = container
      @_log.info(container: container.id, 'started')

      retryCount = 0
      readyCheckCallback = (err=null, ready=true, retryMillis=100) =>
        if err
          @_log.error(err, 'ready check error')
          callback(err, container)
        else if ready
          @_log.info(container: container.id, 'ready')
          callback(null, container)
        else
          retryCount += 1
          @_log.warn(container: container.id, wait: retryMillis, retries: retryCount, 'ready check retry')
          retryReadyCheck = =>
            @_readyCheck container, retryCount, readyCheckCallback
          setTimeout retryReadyCheck, retryMillis

      @_readyCheck container, retryCount, readyCheckCallback

  #
  # Private: Destroys a container. This function is used as the worker for the @_destroyQueue.
  #
  _destroyWorker: (container, callback) =>
    container.destroy callback


  _option: (value, deflt) ->
    if value? then value else deflt

module.exports = Pool






