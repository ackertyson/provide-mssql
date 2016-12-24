Model = require 'provide-model'

describe 'Base Model', ->
  before (done) ->
    class ModelX
      @schema:
        one: 'two'
      methodA: (arg) ->
        yield Promise.resolve "A #{arg}"
      methodB: (arg) ->
        yield Promise.resolve "B #{arg}"
      methodC: (arg) ->
        yield Promise.reject new Error "C #{arg}"
    class ModelY
      methodD: (arg) ->
        yield Promise.resolve "D #{arg}"
    @m = new Model ModelY
    @model = @m.provide ModelX, 'fake'
    done()


  describe 'attach', ->
    beforeEach (done) ->
      @host = [
        { id: 1234, name: 'one', p_id: 4 }
        { id: 5678, name: 'two', p_id: 8 }
        { id: 9101, name: 'three', p_id: 12 }
      ]
      @parasite = [
        { id: 4, name: 'p_one' }
        { id: 8, name: 'p_two' }
      ]
      done()

    it 'should merge objects', ->
      result = @base.attach(@parasite, 'id').to(@host, 'p_id').as 'crap'
      result.should.have.length 3
      result[0].should.have.property('crap').which.has.property 'name', 'p_one'
      result[0].should.have.property('crap').which.has.property 'id', 4
      result[1].should.have.property('crap').which.has.property 'name', 'p_two'
      result[1].should.have.property('crap').which.has.property 'id', 8
      result[2].should.not.have.property 'crap'

    it 'should merge only selected keys of objects', ->
      result = @base.attach(@parasite, 'id').pick('name').to(@host, 'p_id').as 'crap'
      result.should.have.length 3
      result[0].should.have.property('crap').which.has.property 'name', 'p_one'
      result[0].should.have.property('crap').which.should.not.have.property 'id'
      result[1].should.have.property('crap').which.has.property 'name', 'p_two'
      result[1].should.have.property('crap').which.should.not.have.property 'id'
      result[2].should.not.have.property 'crap'


  describe 'list_of_key', ->
    it 'should create array of KEY from resultset', ->
      data = [
        { id: 1234, name: 'one', p_id: 4 }
        { id: 5678, name: 'two', p_id: 8 }
        { id: 9101, name: 'three', p_id: 12 }
      ]
      result = @base.list_of_key data, 'id'
      result.should.have.length 3
      result[0].should.equal 1234
      result[1].should.equal 5678
      result[2].should.equal 9101

    it 'should create arrays of KEYs from resultset', ->
      data = [
        { id: 1234, name: 'one', p_id: 4 }
        { id: 5678, name: 'two', p_id: 8 }
        { id: 9101, name: 'three', p_id: 12 }
      ]
      result = @base.list_of_key data, 'id', 'name'
      result.should.have.length 2
      [ids, names] = result
      ids[0].should.equal 1234
      names[1].should.equal 'two'


  describe 'provide', ->
    it 'should wrap provided class methods', ->
      @base.methodA('one').then (data) ->
        data.should.equal 'A one'
      @base.methodB('two').then (data) ->
        data.should.equal 'B'
      @base.methodC('three').then (data) ->
        expect(data).to.be.null
      .catch (err) ->
        err.message.should.equal 'C three'

    it 'should add BaseModel methods', ->
      @base.should.have.property 'request'
      @base.should.have.property 'parameterize'
