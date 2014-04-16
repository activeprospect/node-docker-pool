assert = require('chai').assert
bunyan = require('bunyan')
ringbuffer = new bunyan.RingBuffer({ limit: 10 })
async = require('async')
Pool = require('../src/pool')

describe 'Pool', ->
  @timeout(30000)
  pool = null

  beforeEach ->
    pool = new Pool
      log: bunyan.createLogger name: 'docker-pool', stream: ringbuffer
      container:
        image: 'ubuntu'
        command: "/bin/sh -c \"trap 'exit' TERM; while true; do sleep 1; done\""


  afterEach (done) ->
    if pool
      pool.drain done

  it 'should callback quickly when there are no containers to destroy', (done) ->
    pool.drain done

  it 'should acquire container', (done) ->
    pool.acquire (err, container) ->
      assert.equal container.id.length, 12
      pool.release(container)
      done(err)

  it 'should acquire same container', (done) ->
    pool.max = 1
    pool.acquire (err, container1) ->
      return done(err) if err
      pool.release(container1)
      pool.acquire (err, container2) ->
        return done(err) if err
        assert.equal container1.id, container2.id
        pool.release(container2)
        done()

  it 'should acquire different containers', (done) ->
    pool.max = 2
    pool.acquire (err, container1) ->
      return done(err) if err
      pool.acquire (err, container2) ->
        return done(err) if err
        assert.notEqual container1.id, container2.id
        pool.release(container1)
        pool.release(container2)
        done()

  it 'should use ready check callback', (done) ->
    retries = null
    pool._readyCheck = (container, retryCount, callback) ->
      retries = retryCount
      if retryCount > 1
        callback(null, true)
      else
        callback(null, false)

    pool.acquire (err, container) ->
      assert.equal retries, 2
      pool.release(container)
      done(err)

  it 'should retry on acquisition error', (done) ->
    acquire = pool._pool.acquire

    callCount = 0
    disposedContainer = null

    dispose = pool.dispose
    pool.dispose = (container) ->
      disposedContainer = container
      pool.dispose = dispose

    pool._pool.acquire = (callback, priority) ->
      callCount += 1
      if callCount == 1
        callback(new Error('something bad happened'), 'mr. container')
      else
        acquire(callback, priority)

    pool.acquire (err, container) ->
      assert.equal disposedContainer, 'mr. container'
      assert.equal callCount, 2
      pool.release(container)
      done(err)

