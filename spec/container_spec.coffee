assert = require('chai').assert
bunyan = require('bunyan')
ringbuffer = new bunyan.RingBuffer({ limit: 10 })
net = require('net')
BufferStream = require('bufferstream')
Pool = require('../src/pool')

describe 'Container', ->
  @timeout(30000)

  container = null
  pool = null

  afterEach (done) ->
    if pool
      pool.destroyAll done


  describe 'that is responsive', ->

    beforeEach (done) ->
      pool = new Pool
        log: bunyan.createLogger(name: 'docker-pool', stream: ringbuffer)
        container:
          image: 'ubuntu'
          command: "/bin/sh -c \"trap 'exit' TERM; while true; do sleep 1; done\""


      pool.create (err, c) ->
        return done(err) if err
        container = c
        done()

    it 'should get info', (done) ->
      container.info (err, info) ->
        assert !err
        assert info.State.Running
        done()

    it 'should stop on destroy', (done) ->
      container.once 'stop', done
      container.destroy()

    it 'should remove on destroy', (done) ->
      container.on 'remove', done
      container.destroy()

    it 'should destroy gracefully before timeout', (done) ->
      stopping = new Date()
      container.destroy (err) ->
        return done(err) if err
        stopped = new Date()
        assert stopped - stopping < 10000, 'destroy took longer than 10s, container suspected to have been killed'
        done()


  describe 'that exposes ports', ->

    beforeEach (done) ->
      pool = new Pool
        log: bunyan.createLogger(name: 'docker-pool', stream: ringbuffer)
        container:
          image: 'activeprospect/docker-pool-test'
          ports: [5555]
          command: 'ncat -e /bin/cat -k -t -l 5555'

      pool.create (err, c) ->
        return done(err) if err
        container = c
        done()

    it 'should respond on container port', (done) ->
      @timeout(10000)
      stream = new BufferStream({size:'flexible'})
      stream.split('\r\n')
      stream.on 'split', (data) =>
        assert.equal data.toString(), 'hi'
        done()

      client = new net.Socket()
      client.connect 5555, container.ip, ->
        client.write('hi\r\n')
      client.on 'data', (data) ->
        stream.write(data)
      client.on 'error', (err) ->
        done(err)