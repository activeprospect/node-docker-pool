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


  #
  # Public: Wait for all currently acquired containers to finish their current job, then dispose of all containers.
  # An error will be thrown if acquire is called after drain.
  #
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
          @dispose container
      else
        callback()

    if @_pool.waitingClientsCount() > 0
      @_pool.drain ->
        teardown()
    else
      teardown()


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
      @_log.info(container: container.id, 'ready')
      callback(null, container)


  #
  # Private: Destroys a container. This function is used as the worker for the @_destroyQueue.
  #
  _destroyWorker: (container, callback) =>
    container.destroy callback




module.exports = Pool






