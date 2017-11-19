MSSQL = require '../../src/index'

describe 'MSSQL', ->
  before (done) ->
    @MSSQL = MSSQL
    class TestModel extends MSSQL
      table:
        name: 'test'
        primary_key: '_id'
        schema:
          _id: 'Int'
          column1: 'VarChar'
          date: 'Date'
          name: 'VarChar'
          hours: 'Decimal': precision: 4, scale: 2
    class Table1Model extends MSSQL
      table:
        name: 'table1'
        schema:
          column1: 'VarChar'
          column2: 'VarChar'
          column3: 'VarChar'
          name: 'VarChar'
    class Table2Model extends MSSQL
      table:
        name: 'table2'
        schema:
          name: 'VarChar'
          column1: 'VarChar'
          column2: 'VarChar'
          vehicle_id: 'Int'
    @dummy = new Table1Model null, null, null, 'testdb'
    dummy2 = new Table2Model null, null, null, 'testdb'
    @model = new TestModel null, null, null, 'testdb'
    done()

  describe 'ctor', ->
    it 'should add DB conn to cache', ->
      @MSSQL._cache.should.be.an 'object'
      Object.keys(@MSSQL._cache).should.have.length 1

    it 'should store all table schema', ->
      @MSSQL._all_schema.should.have.property 'testdb'
      @MSSQL._all_schema.should.not.have.property 'fake'
      @MSSQL._all_schema.testdb.should.have.property 'test'
      @MSSQL._all_schema.testdb.should.have.property 'table1'
      @MSSQL._all_schema.testdb.should.have.property 'table2'
      @MSSQL._all_schema.testdb.test.should.have.property 'name', 'VarChar'

    it 'should store table primary_key', ->
      @model.should.have.property 'primary_key', '_id'

    it '...unless not provided', ->
      @dummy.should.have.property 'primary_key', undefined


  describe 'model instance interaction', ->
    before (done) ->
      class ModelX extends MSSQL
        table:
          name: 'fake'
        generators:
          methodA: (arg) ->
            yield Promise.resolve "AX #{arg}"
          methodB: (arg) ->
            yield @methodA "B #{arg}"
          methodC: (arg) ->
            yield Promise.reject new Error "C #{arg}"
      class ModelZ extends MSSQL
        table:
          name: 'fake2'
        generators:
          methodA: (arg) ->
            yield Promise.resolve "AZ #{arg}"
      class ModelY extends MSSQL
        @prop: 999
        table:
          name: 'fake2'
        generators:
          methodD: (arg) ->
            yield Promise.resolve "A #{arg}"
      @modelX = new ModelX
      @modelY = new ModelY
      @modelZ = new ModelZ
      done()

    it 'should add instance properties', ->
      @modelX.should.have.property 'methodA'
      @modelX.should.not.have.property 'methodD'

      @modelY.should.have.property 'methodD'
      @modelY.should.not.have.property 'methodA'


    it 'should allow model methods to see each other', ->
      @modelX.methodB('one').then (data) ->
        data.should.equal 'AX B one'

    it 'should not overwrite methods of same name', ->
      @modelX.methodA('one').then (data) ->
        data.should.equal 'AX one'

      @modelZ.methodA('one').then (data) ->
        data.should.equal 'AZ one'


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
      result = @model.attach(@parasite, 'id').to(@host, 'p_id').as 'crap'
      result.should.have.length 3
      result[0].should.have.property('crap').which.has.property 'name', 'p_one'
      result[0].should.have.property('crap').which.has.property 'id', 4
      result[1].should.have.property('crap').which.has.property 'name', 'p_two'
      result[1].should.have.property('crap').which.has.property 'id', 8
      result[2].should.not.have.property 'crap'

    it 'should merge only selected keys of objects', ->
      result = @model.attach(@parasite, 'id').pick('name').to(@host, 'p_id').as 'crap'
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
      result = @model.list_of_key data, 'id'
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
      result = @model.list_of_key data, 'id', 'name'
      result.should.have.length 2
      [ids, names] = result
      ids[0].should.equal 1234
      names[1].should.equal 'two'


  describe '_coerce_int', ->
    it 'should turn false to zero', ->
      value = @model._coerce_int false
      value.should.equal 0

    it 'should turn undefined to null', ->
      value = @model._coerce_int()
      expect(value).to.be.null

    it 'should turn junk to null', ->
      value = @model._coerce_int 'string'
      expect(value).to.be.null

    it 'should turn true to 1', ->
      value = @model._coerce_int true
      value.should.equal 1


  describe '_coerce_time', ->
    it 'should return ISO string unchanged', ->
      value = @model._coerce_time "2017-01-30T19:33:53.779Z"
      value.should.equal "2017-01-30T19:33:53.779Z"

    it 'should convert HH:MM to ISO string', ->
      value = @model._coerce_time "19:33"
      expect(/T19:33/.test value).to.equal true

    it 'should return undefined on empty input', ->
      value = @model._coerce_time()
      expect(value).to.equal undefined


  describe 'build_query', ->
    it 'should build simple query', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
      query.should.equal 'SELECT [table1].[column1],[test].* FROM [table1],[test]'

    it 'should limit SELECT on base table if specified', ->
      [query, params] = @model.build_query
        select:
          '@': ['name', 'date']
      query.should.equal 'SELECT [test].[name],[test].[date] FROM [test]'

    it 'should throw if no valid SELECT fields', ->
      try
        [query, params] = @model.build_query
          select:
            '@': ['sname', 'datezzz']
        expect(query).to.be.null
      catch ex
        ex.should.be.instanceOf Error

    it 'should add default SELECT on base table', ->
      [query, params] = @model.build_query
        order_by: ['columnX']
      query.should.equal 'SELECT [test].* FROM [test]   ORDER BY [test].[columnX]'

    it 'should build simple query with column alias', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1:alias1']
      query.should.equal 'SELECT [table1].[column1] AS alias1,[test].* FROM [table1],[test]'

    it 'should build query with multiple columns on same table', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1', 'column2', 'column3: alias3']
      query.should.equal 'SELECT [table1].[column1],[table1].[column2],[table1].[column3] AS alias3,[test].* FROM [table1],[test]'

    it 'should build query with multiple tables', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
          table2: ['column2:alias2']
      query.should.equal 'SELECT [table1].[column1],[table2].[column2] AS alias2,[test].* FROM [table1],[table2],[test]'

    it 'should build query with JOIN', ->
      [query, params] = @model.build_query
        select:
          table2: ['column1']
        join: [
          ['@._id', 'table2.vehicle_id']
        ]
      query.should.equal 'SELECT [table2].[column1],[test].* FROM [test] LEFT JOIN [table2] ON [test].[_id] = [table2].[vehicle_id]'

    it 'should honor provided JOIN direction', ->
      [query, params] = @model.build_query
        select:
          table2: ['column1']
        join: [
          ['RIGHT', '@._id', 'table2.vehicle_id']
        ]
      query.should.equal 'SELECT [table2].[column1],[test].* FROM [test] RIGHT JOIN [table2] ON [test].[_id] = [table2].[vehicle_id]'

    it 'should build query with multiple JOIN on same table', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
          table2: ['column1']
        join: [
          ['@._id', 'table2.vehicle_id']
          ['@.column1', 'table1.column1']
        ]
      query.should.equal 'SELECT [table1].[column1],[table2].[column1],[test].* FROM [test] LEFT JOIN [table2] ON [test].[_id] = [table2].[vehicle_id] LEFT JOIN [table1] ON [test].[column1] = [table1].[column1]'

    it 'should build query with ORDER BY', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
        order_by: ['columnX']
      query.should.equal 'SELECT [table1].[column1],[test].* FROM [table1],[test]   ORDER BY [test].[columnX]'

    it 'should build query with ORDER BY direction', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
        order_by: ['columnX DESC']
      query.should.equal 'SELECT [table1].[column1],[test].* FROM [table1],[test]   ORDER BY [test].[columnX] DESC'

    it 'should build query with ORDER BY (with table)', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
        order_by: ['tableX.columnX']
      query.should.equal 'SELECT [table1].[column1],[test].* FROM [table1],[test]   ORDER BY [tableX].[columnX]'

    it 'should build query with ORDER BY (with table and direction)', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
        order_by: ['tableX.columnX DESC']
      query.should.equal 'SELECT [table1].[column1],[test].* FROM [table1],[test]   ORDER BY [tableX].[columnX] DESC'

    it 'should build query with ORDER BY (with base table)', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
        order_by: ['@.columnX']
      query.should.equal 'SELECT [table1].[column1],[test].* FROM [table1],[test]   ORDER BY [test].[columnX]'

    it 'should build query with ORDER BY (with base table and direction)', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
        order_by: ['@.columnX DESC']
      query.should.equal 'SELECT [table1].[column1],[test].* FROM [table1],[test]   ORDER BY [test].[columnX] DESC'

    it 'should build query with JOIN and ORDER BY', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
        join: [
          ['@.column1', 'table1.column1']
          ['table1._id', 'table2.vehicle_id']
        ]
        order_by: ['column1']
      query.should.equal 'SELECT [table1].[column1],[test].* FROM [test] LEFT JOIN [table1] ON [test].[column1] = [table1].[column1] LEFT JOIN [table2] ON [table1].[_id] = [table2].[vehicle_id]  ORDER BY [test].[column1]'

    it 'should build query with WHERE', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @MSSQL.eq 1234]
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] = @id00"
      params.should.have.length 1
      params[0].value.should.equal 1234

    it 'should build query with WHERE...IN', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @MSSQL.in [1,2,3,4]]
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] IN (@id00,@id01,@id02,@id03)"
      params.should.have.length 4
      params[1].value.should.equal 2

    it 'should build query with nonarray WHERE...IN', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @MSSQL.in 3]
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] IN (@id00)"
      params.should.have.length 1
      params[0].value.should.equal 3

    it 'should build query with WHERE...LIKE', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @MSSQL.starts_with 'bea']
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] LIKE @id00"
      params.should.have.length 1
      params[0].value.should.equal 'bea%'

    it 'should ignore empty WHERE', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
        where: []
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]"
      params.should.have.length 0

    it 'should ignore broken WHERE', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
        where: {}
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]"
      params.should.have.length 0

    it 'should build query with multiple WHERE', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @MSSQL.eq 1234]
          ['table1.name', @MSSQL.lt 'fred']
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] = @id00 AND [table1].[name] < @table1name10"
      params.should.have.length 2
      params[0].value.should.equal 1234

    it 'should build query which specifies WHERE and/or', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @MSSQL.eq 1234]
          ['OR', 'table1.name', @MSSQL.lt 'fred']
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] = @id00 OR [table1].[name] < @table1name10"
      params.should.have.length 2
      params[0].value.should.equal 1234

    it 'should ignore initial WHERE and/or', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
        where: [
          ['AND', '@._id', @MSSQL.eq 1234]
          ['OR', 'table1.name', @MSSQL.lt 'fred']
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] = @id00 OR [table1].[name] < @table1name10"
      params.should.have.length 2
      params[0].value.should.equal 1234

    it 'should ignore random WHERE and/or', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @MSSQL.eq 1234]
          ['ZAZZ', 'table1.name', @MSSQL.lt 'fred']
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] = @id00 AND [table1].[name] < @table1name10"
      params.should.have.length 2
      params[0].value.should.equal 1234

    it 'should build query with JOIN, WHERE and ORDER BY', ->
      [query, params] = @model.build_query
        select:
          table1: ['column1']
        join: [
          ['@.column1', 'table1.column1']
          ['table1._id', 'table2.vehicle_id']
        ]
        where: [
          ['@._id', @MSSQL.eq 1234]
          ['table1.name', @MSSQL.contains 'fred']
        ]
        order_by: ['column1']
      query.should.equal "SELECT [table1].[column1],[test].* FROM [test] LEFT JOIN [table1] ON [test].[column1] = [table1].[column1] LEFT JOIN [table2] ON [table1].[_id] = [table2].[vehicle_id] WHERE [test].[_id] = @id00 AND [table1].[name] LIKE @table1name10 ORDER BY [test].[column1]"
      params.should.have.length 2
      params[0].value.should.equal 1234

    it 'should build INSERT query', ->
      [query, params] = @model.build_query
        insert:
          name: 'new name'
          date: '2016-12-01'
          junk: 'ignore this'
      query.should.equal "INSERT INTO [test] ([name],[date]) OUTPUT INSERTED.* VALUES (@name00,@date00)"
      params.should.have.length 2
      params[0].value.should.equal 'new name'
      params[0].should.not.have.property 'junk'

    it 'should build INSERT query with multiple items', ->
      [query, params] = @model.build_query
        insert: [
          {
            name: 'new name'
            date: '2016-12-01'
          }
          {
            name: 'new name2'
            date: '2016-12-02'
            junk: 'ignore this'
          }
        ]
      query.should.equal "INSERT INTO [test] ([name],[date]) OUTPUT INSERTED.* VALUES (@name00,@date00),(@name10,@date10)"
      params.should.have.length 4
      params[2].value.should.equal 'new name2'
      params[2].should.not.have.property 'junk'

    it 'should build UPDATE query', ->
      [query, params] = @model.build_query
        update:
          name: 'new name'
          date: '2016-12-01'
          junk: 'ignore this'
        where: [
          ['@._id', @MSSQL.eq 1234]
        ]
      query.should.equal "UPDATE [test] SET [name]=@name0,[date]=@date0 OUTPUT INSERTED.* WHERE [_id] = @id00"
      params.should.have.length 3
      params[0].value.should.equal 'new name'

    it 'should ignore WHERE table in UPDATE query', ->
      [query, params] = @model.build_query
        update:
          name: 'new name'
          date: '2016-12-01'
        where: [
          ['table_name._id', @MSSQL.eq 1234]
        ]
      query.should.equal "UPDATE [test] SET [name]=@name0,[date]=@date0 OUTPUT INSERTED.* WHERE [_id] = @id00"
      params.should.have.length 3
      params[0].value.should.equal 'new name'

    it 'should build DELETE query', ->
      [query, params] = @model.build_query
        delete: {}
        where: [
          ['@._id', @MSSQL.eq 1234]
        ]
      query.should.equal "DELETE FROM [test] OUTPUT DELETED.* WHERE [_id] = @id00"
      params.should.have.length 1
      params[0].value.should.equal 1234

    it 'should ignore WHERE table in DELETE query', ->
      [query, params] = @model.build_query
        delete: {}
        where: [
          ['table_name._id', @MSSQL.eq 1234]
        ]
      query.should.equal "DELETE FROM [test] OUTPUT DELETED.* WHERE [_id] = @id00"
      params.should.have.length 1
      params[0].value.should.equal 1234


  describe 'parameterize', ->
    it 'should handle OPTIONS', ->
      [column, params] = @model.parameterize 'test', 'hours', 11.5
      params.should.have.length 1
      params[0].should.have.property 'name'
      params[0].name.should.equal 'hours0'
      params[0].should.have.property 'type'
      params[0].type.should.equal 'Decimal'
      params[0].should.have.property 'value'
      params[0].value.should.equal 11.5
      params[0].should.have.property 'options'
      params[0].options.should.have.property 'precision', 4
      params[0].options.should.have.property 'scale', 2

    it 'should handle no OPTIONS', ->
      [column, params] = @model.parameterize 'test', 'column1', 'nice'
      params.should.have.length 1
      params[0].should.have.property 'name'
      params[0].name.should.equal 'column10'
      params[0].should.have.property 'type'
      params[0].type.should.equal 'VarChar'
      params[0].should.have.property 'value'
      params[0].value.should.equal 'nice'
