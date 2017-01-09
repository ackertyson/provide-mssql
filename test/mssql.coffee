MSSQL = require '../src/mssql'

describe 'MSSQL', ->
  before (done) ->
    class TestModel
      table:
        name: 'test'
        primary_key: '_id'
        schema:
          _id: 'Int'
          column1: 'VarChar'
          date: 'Date'
          name: 'VarChar'
    class Table1Model
      table:
        name: 'table1'
        schema:
          column1: 'VarChar'
          column2: 'VarChar'
          column3: 'VarChar'
          name: 'VarChar'
    class Table2Model
      table:
        name: 'table2'
        schema:
          name: 'VarChar'
          column1: 'VarChar'
          column2: 'VarChar'
          vehicle_id: 'Int'
    dummy = new MSSQL Table1Model
    dummy2 = new MSSQL Table2Model
    @mssql = new MSSQL TestModel
    done()


  describe 'contains', ->
    it 'should clean up bad inputs', ->
      value = @mssql.contains 'bad\\,stuff'
      value.should.have.length 2
      value[1].should.equal "\'%badstuff%\'"


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

    it 'should throw if no valid SELECT fields', ->
      try
        [query, params] = @mssql.build_query
          select:
            '@': ['sname', 'datezzz']
        expect(query).to.be.null
      catch ex
        ex.should.be.instanceOf Error

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
          table2: ['column1']
        join: [
          ['@._id', 'table2.vehicle_id']
        ]
      query.should.equal 'SELECT table2.column1,test.* FROM test LEFT JOIN table2 ON test._id = table2.vehicle_id'

    it 'should honor provided JOIN direction', ->
      [query, params] = @mssql.build_query
        select:
          table2: ['column1']
        join: [
          ['RIGHT', '@._id', 'table2.vehicle_id']
        ]
      query.should.equal 'SELECT table2.column1,test.* FROM test RIGHT JOIN table2 ON test._id = table2.vehicle_id'

    it 'should build query with multiple JOIN on same table', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
          table2: ['column1']
        join: [
          ['@._id', 'table2.vehicle_id']
          ['@.column1', 'table1.column1']
        ]
      query.should.equal 'SELECT table1.column1,table2.column1,test.* FROM test LEFT JOIN table2 ON test._id = table2.vehicle_id LEFT JOIN table1 ON test.column1 = table1.column1'

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
          ['@.column1', 'table1.column1']
          ['table1._id', 'table2.vehicle_id']
        ]
        order_by: ['column1']
      query.should.equal 'SELECT table1.column1,test.* FROM test LEFT JOIN table1 ON test.column1 = table1.column1 LEFT JOIN table2 ON table1._id = table2.vehicle_id  ORDER BY column1'

    it 'should build query with WHERE', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @mssql.eq 1234]
        ]
      query.should.equal "SELECT table1.column1,test.* FROM table1,test  WHERE [test].[_id] = @id0"
      params.should.have.length 1
      params[0].value.should.equal 1234

    it 'should ignore empty WHERE', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: []
      query.should.equal "SELECT table1.column1,test.* FROM table1,test"
      params.should.have.length 0

    it 'should ignore broken WHERE', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: {}
      query.should.equal "SELECT table1.column1,test.* FROM table1,test"
      params.should.have.length 0

    it 'should build query with multiple WHERE', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @mssql.eq 1234]
          ['table1.name', @mssql.lt 'fred']
        ]
      query.should.equal "SELECT table1.column1,test.* FROM table1,test  WHERE [test].[_id] = @id0 AND [table1].[name] < @table1name1"
      params.should.have.length 2
      params[0].value.should.equal 1234

    it 'should build query with JOIN, WHERE and ORDER BY', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        join: [
          ['@.column1', 'table1.column1']
          ['table1._id', 'table2.vehicle_id']
        ]
        where: [
          ['@._id', @mssql.eq 1234]
          ['table1.name', @mssql.contains 'fred']
        ]
        order_by: ['column1']
      query.should.equal "SELECT table1.column1,test.* FROM test LEFT JOIN table1 ON test.column1 = table1.column1 LEFT JOIN table2 ON table1._id = table2.vehicle_id WHERE [test].[_id] = @id0 AND [table1].[name] LIKE '%fred%' ORDER BY column1"
      params.should.have.length 1
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
        where: [
          ['@._id', @mssql.eq 1234]
        ]
      query.should.equal "UPDATE [test] SET [name]=@name,[date]=@date OUTPUT INSERTED.* WHERE [_id] = @id0"
      params.should.have.length 3
      params[0].value.should.equal 'new name'

    it 'should ignore WHERE table in UPDATE query', ->
      [query, params] = @mssql.build_query
        update:
          name: 'new name'
          date: '2016-12-01'
        where: [
          ['table_name._id', @mssql.eq 1234]
        ]
      query.should.equal "UPDATE [test] SET [name]=@name,[date]=@date OUTPUT INSERTED.* WHERE [_id] = @id0"
      params.should.have.length 3
      params[0].value.should.equal 'new name'

    it 'should build DELETE query', ->
      [query, params] = @mssql.build_query
        delete: {}
        where: [
          ['@._id', @mssql.eq 1234]
        ]
      query.should.equal "DELETE FROM [test] OUTPUT DELETED.* WHERE [_id] = @id0"
      params.should.have.length 1
      params[0].value.should.equal 1234

    it 'should ignore WHERE table in DELETE query', ->
      [query, params] = @mssql.build_query
        delete: {}
        where: [
          ['table_name._id', @mssql.eq 1234]
        ]
      query.should.equal "DELETE FROM [test] OUTPUT DELETED.* WHERE [_id] = @id0"
      params.should.have.length 1
      params[0].value.should.equal 1234


  describe 'strip_bad_chars', ->
    it 'should pass good string unaltered', ->
      value = @mssql.strip_bad_chars 'abra'
      value.should.equal 'abra'

    it 'should strip simple symbols', ->
      value = @mssql.strip_bad_chars 'ab+ra'
      value.should.equal 'abra'

    it 'should strip slashes and single-quote', ->
      value = @mssql.strip_bad_chars "ab'r\a"
      value.should.equal 'abra'

    it 'should strip backslashes and double-quote', ->
      value = @mssql.strip_bad_chars '\/ab\\"ra/'
      value.should.equal 'abra'

    it 'should handle being passed a RegExp', ->
      value = @mssql.strip_bad_chars /ab\\"ra/
      value.should.equal 'abra'
