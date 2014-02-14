assert = require('chai').assert
async = require('async')
Pool = require('../src/pool')

describe 'Pool', ->
  @timeout(30000)
  pool = null

  beforeEach ->
    pool = new Pool
      container:
        image: 'ubuntu'
        command: "/bin/sh -c \"trap 'exit' TERM; while true; do sleep 1; done\""


  afterEach (done) ->
    if pool
      pool.destroyAll done

  it 'should callback quickly when there are no containers to destroy', (done) ->
    pool.destroyAll done

  it 'should acquire container', (done) ->
    pool.acquire (err, container) ->
      assert.equal container.id.length, 64
      done(err)

  it 'should acquire same container', (done) ->
    pool.max = 1
    pool.acquire (err, container1) ->
      return done(err) if err
      pool.release(container1)
      pool.acquire (err, container2) ->
        return done(err) if err
        assert.equal container1.id, container2.id
        done()

  it 'should acquire different containers', (done) ->
    pool.max = 2
    pool.acquire (err, container1) ->
      return done(err) if err
      pool.acquire (err, container2) ->
        return done(err) if err
        assert.notEqual container1.id, container2.id
        done()
