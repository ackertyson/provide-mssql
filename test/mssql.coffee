MSSQL = require '../src/mssql'

describe 'MSSQL', ->
  before (done) ->
    schema =
      primary_key: '_id'
      _id: 'Int'
      date: 'Date'
      name: 'VarChar'
    table1_schema =
      name: 'VarChar'
    dummy = new MSSQL table1_schema, 'table1'
    @mssql = new MSSQL schema, 'test'
    done()

  describe 'build_query', ->
    it 'should build simple query', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
      query.should.equal 'SELECT table1.column1,test.* FROM table1,test'

    it 'should limit SELECT on base table if specified', ->
      [query, params] = @mssql.build_query
        select:
          '@': ['name', 'date']
      query.should.equal 'SELECT test.name,test.date FROM test'

    it 'should add default SELECT on base table', ->
      [query, params] = @mssql.build_query
        order_by: ['columnX']
      query.should.equal 'SELECT test.* FROM test   ORDER BY columnX'

    it 'should build simple query with column alias', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1:alias1']
      query.should.equal 'SELECT table1.column1 AS alias1,test.* FROM table1,test'

    it 'should build query with multiple columns on same table', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1', 'column2', 'column3: alias3']
      query.should.equal 'SELECT table1.column1,table1.column2,table1.column3 AS alias3,test.* FROM table1,test'

    it 'should build query with multiple tables', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
          table2: ['column2:alias2']
      query.should.equal 'SELECT table1.column1,table2.column2 AS alias2,test.* FROM table1,table2,test'

    it 'should build query with JOIN', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        join: [
          ['@._id', 'table2.vehicle_id']
        ]
      query.should.equal 'SELECT table1.column1,test.* FROM table1,test LEFT JOIN table2 ON test._id = table2.vehicle_id'

    it 'should build query with ORDER BY', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        order_by: ['columnX']
      query.should.equal 'SELECT table1.column1,test.* FROM table1,test   ORDER BY columnX'

    it 'should build query with ORDER BY (with table)', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        order_by: ['tableX.columnX']
      query.should.equal 'SELECT table1.column1,test.* FROM table1,test   ORDER BY tableX.columnX'

    it 'should build query with JOIN and ORDER BY', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        join: [
          ['table1._id', 'table2.vehicle_id']
        ]
        order_by: ['column1']
      query.should.equal 'SELECT table1.column1,test.* FROM test,table1 LEFT JOIN table2 ON table1._id = table2.vehicle_id  ORDER BY column1'

    it 'should build query with WHERE', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where:
          '@._id': @mssql.eq 1234
      query.should.equal "SELECT table1.column1,test.* FROM table1,test  WHERE [test].[_id] = @id"
      params.should.have.length 1
      params[0].value.should.equal 1234

    it 'should ignore empty WHERE', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: {}
      query.should.equal "SELECT table1.column1,test.* FROM table1,test"
      params.should.have.length 0

    it 'should ignore broken WHERE', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: []
      query.should.equal "SELECT table1.column1,test.* FROM table1,test"
      params.should.have.length 0

    it 'should build query with multiple WHERE', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where:
          '@._id': @mssql.eq 1234
          'table1.name': @mssql.lt 'fred'
      query.should.equal "SELECT table1.column1,test.* FROM table1,test  WHERE [test].[_id] = @id AND [table1].[name] < @table1name"
      params.should.have.length 2
      params[0].value.should.equal 1234

    it 'should build query with JOIN, WHERE and ORDER BY', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        join: [
          ['table1._id', 'table2.vehicle_id']
        ]
        where:
          '@._id': @mssql.eq 1234
          'table1.name': @mssql.contains 'fred'
        order_by: ['column1']
      query.should.equal "SELECT table1.column1,test.* FROM test,table1 LEFT JOIN table2 ON table1._id = table2.vehicle_id WHERE [test].[_id] = @id AND [table1].[name] LIKE  @table1name ORDER BY column1"
      params.should.have.length 2
      params[0].value.should.equal 1234

    it 'should build INSERT query', ->
      [query, params] = @mssql.build_query
        insert:
          name: 'new name'
          date: '2016-12-01'
          junk: 'ignore this'
      query.should.equal "INSERT INTO [test] ([name],[date]) OUTPUT INSERTED.* VALUES (@name0,@date0)"
      params.should.have.length 2
      params[0].value.should.equal 'new name'
      params[0].should.not.have.property 'junk'

    it 'should build INSERT query with multiple items', ->
      [query, params] = @mssql.build_query
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
      query.should.equal "INSERT INTO [test] ([name],[date]) OUTPUT INSERTED.* VALUES (@name0,@date0),(@name1,@date1)"
      params.should.have.length 4
      params[2].value.should.equal 'new name2'
      params[2].should.not.have.property 'junk'

    it 'should build UPDATE query', ->
      [query, params] = @mssql.build_query
        update:
          name: 'new name'
          date: '2016-12-01'
          junk: 'ignore this'
        where:
          _id: @mssql.eq 1234
      query.should.equal "UPDATE [test] SET [name]=@name,[date]=@date OUTPUT INSERTED.* WHERE [_id] = @id"
      params.should.have.length 3
      params[0].value.should.equal 'new name'

    it 'should ignore WHERE table in UPDATE query', ->
      [query, params] = @mssql.build_query
        update:
          name: 'new name'
          date: '2016-12-01'
        where:
          'table_name._id': @mssql.eq 1234
      query.should.equal "UPDATE [test] SET [name]=@name,[date]=@date OUTPUT INSERTED.* WHERE [_id] = @id"
      params.should.have.length 3
      params[0].value.should.equal 'new name'

    it 'should build DELETE query', ->
      [query, params] = @mssql.build_query
        delete: {}
        where:
          _id: @mssql.eq 1234
      query.should.equal "DELETE FROM [test] OUTPUT DELETED.* WHERE [_id] = @id"
      params.should.have.length 1
      params[0].value.should.equal 1234

    it 'should ignore WHERE table in DELETE query', ->
      [query, params] = @mssql.build_query
        delete: {}
        where:
          'table_name._id': @mssql.eq 1234
      query.should.equal "DELETE FROM [test] OUTPUT DELETED.* WHERE [_id] = @id"
      params.should.have.length 1
      params[0].value.should.equal 1234
