PoolFactory = require('generic-pool').Pool
async = require 'async'
Container = require './container'

class Pool
  constructor: (options={}) ->
    @_maxDestroyAttempts = options.maxDestroyAttempts || 10
    delete options.maxDestroyAttempts

    @_containerOptions = options.container
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
    @_destroyQueue.drain = =>
      @_destroyQueue.drain = null
      callback()

  destroy: (container) ->
    @_enqueueDestroy container

  _enqueueDestroy: (container, callback) ->
    cb = (err) ->
      callback(err) if callback

    container.destroyCount ?= 0
    @_destroyQueue.push container, (err) =>
      container.destroyCount += 1
      giveUp = @_maxDestroyAttempts <= container.destroyCount
      if err
        cb(err)
        if giveUp
        else
          @_enqueueDestroy container, callback
      else
        delete @_containers[container.id]
        cb()

  _createWorker: (_, callback) =>
    container = new Container(@_containerOptions)
    container.start (err) =>
      return callback(err) if err
      @_containers[container.id] = container
      callback(null, container)

  _destroyWorker: (container, callback) =>
    container.destroy callback



module.exports = Pool






