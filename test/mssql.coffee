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
          hours: 'Decimal': precision: 4, scale: 2
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

  describe '_coerce_int', ->
    it 'should turn false to zero', ->
      value = @mssql._coerce_int false
      value.should.equal 0

    it 'should turn undefined to null', ->
      value = @mssql._coerce_int()
      expect(value).to.be.null

    it 'should turn junk to null', ->
      value = @mssql._coerce_int 'string'
      expect(value).to.be.null

    it 'should turn true to 1', ->
      value = @mssql._coerce_int true
      value.should.equal 1


  describe '_coerce_time', ->
    it 'should return ISO string unchanged', ->
      value = @mssql._coerce_time "2017-01-30T19:33:53.779Z"
      value.should.equal "2017-01-30T19:33:53.779Z"

    it 'should convert HH:MM to ISO string', ->
      value = @mssql._coerce_time "19:33"
      expect(/T19:33/.test value).to.equal true

    it 'should return undefined on empty input', ->
      value = @mssql._coerce_time()
      expect(value).to.equal undefined


  describe 'build_query', ->
    it 'should build simple query', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
      query.should.equal 'SELECT [table1].[column1],[test].* FROM [table1],[test]'

    it 'should limit SELECT on base table if specified', ->
      [query, params] = @mssql.build_query
        select:
          '@': ['name', 'date']
      query.should.equal 'SELECT [test].[name],[test].[date] FROM [test]'

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
      query.should.equal 'SELECT [test].* FROM [test]   ORDER BY [test].[columnX]'

    it 'should build simple query with column alias', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1:alias1']
      query.should.equal 'SELECT [table1].[column1] AS alias1,[test].* FROM [table1],[test]'

    it 'should build query with multiple columns on same table', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1', 'column2', 'column3: alias3']
      query.should.equal 'SELECT [table1].[column1],[table1].[column2],[table1].[column3] AS alias3,[test].* FROM [table1],[test]'

    it 'should build query with multiple tables', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
          table2: ['column2:alias2']
      query.should.equal 'SELECT [table1].[column1],[table2].[column2] AS alias2,[test].* FROM [table1],[table2],[test]'

    it 'should build query with JOIN', ->
      [query, params] = @mssql.build_query
        select:
          table2: ['column1']
        join: [
          ['@._id', 'table2.vehicle_id']
        ]
      query.should.equal 'SELECT [table2].[column1],[test].* FROM [test] LEFT JOIN [table2] ON [test].[_id] = [table2].[vehicle_id]'

    it 'should honor provided JOIN direction', ->
      [query, params] = @mssql.build_query
        select:
          table2: ['column1']
        join: [
          ['RIGHT', '@._id', 'table2.vehicle_id']
        ]
      query.should.equal 'SELECT [table2].[column1],[test].* FROM [test] RIGHT JOIN [table2] ON [test].[_id] = [table2].[vehicle_id]'

    it 'should build query with multiple JOIN on same table', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
          table2: ['column1']
        join: [
          ['@._id', 'table2.vehicle_id']
          ['@.column1', 'table1.column1']
        ]
      query.should.equal 'SELECT [table1].[column1],[table2].[column1],[test].* FROM [test] LEFT JOIN [table2] ON [test].[_id] = [table2].[vehicle_id] LEFT JOIN [table1] ON [test].[column1] = [table1].[column1]'

    it 'should build query with ORDER BY', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        order_by: ['columnX']
      query.should.equal 'SELECT [table1].[column1],[test].* FROM [table1],[test]   ORDER BY [test].[columnX]'

    it 'should build query with ORDER BY direction', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        order_by: ['columnX DESC']
      query.should.equal 'SELECT [table1].[column1],[test].* FROM [table1],[test]   ORDER BY [test].[columnX] DESC'

    it 'should build query with ORDER BY (with table)', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        order_by: ['tableX.columnX']
      query.should.equal 'SELECT [table1].[column1],[test].* FROM [table1],[test]   ORDER BY [tableX].[columnX]'

    it 'should build query with ORDER BY (with table and direction)', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        order_by: ['tableX.columnX DESC']
      query.should.equal 'SELECT [table1].[column1],[test].* FROM [table1],[test]   ORDER BY [tableX].[columnX] DESC'

    it 'should build query with ORDER BY (with base table)', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        order_by: ['@.columnX']
      query.should.equal 'SELECT [table1].[column1],[test].* FROM [table1],[test]   ORDER BY [test].[columnX]'

    it 'should build query with ORDER BY (with base table and direction)', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        order_by: ['@.columnX DESC']
      query.should.equal 'SELECT [table1].[column1],[test].* FROM [table1],[test]   ORDER BY [test].[columnX] DESC'

    it 'should build query with JOIN and ORDER BY', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        join: [
          ['@.column1', 'table1.column1']
          ['table1._id', 'table2.vehicle_id']
        ]
        order_by: ['column1']
      query.should.equal 'SELECT [table1].[column1],[test].* FROM [test] LEFT JOIN [table1] ON [test].[column1] = [table1].[column1] LEFT JOIN [table2] ON [table1].[_id] = [table2].[vehicle_id]  ORDER BY [test].[column1]'

    it 'should build query with WHERE', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @mssql.eq 1234]
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] = @id00"
      params.should.have.length 1
      params[0].value.should.equal 1234

    it 'should build query with WHERE...IS NULL', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @mssql.is_null()]
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] IS NULL"
      params.should.have.length 0

    it 'should ignore CAST with WHERE...IS NULL', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @mssql.cast @mssql.is_null(), 'tinyint']
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] IS NULL"
      params.should.have.length 0

    it 'should build query with WHERE...IN', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @mssql.in [1,2,3,4]]
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] IN (@id00,@id01,@id02,@id03)"
      params.should.have.length 4
      params[1].value.should.equal 2

    it 'should build query with nonarray WHERE...IN', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @mssql.in 3]
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] IN (@id00)"
      params.should.have.length 1
      params[0].value.should.equal 3

    it 'should build query with WHERE...LIKE', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @mssql.starts_with 'bea']
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] LIKE @id00"
      params.should.have.length 1
      params[0].value.should.equal 'bea%'

    it 'should ignore empty WHERE', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: []
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]"
      params.should.have.length 0

    it 'should ignore broken WHERE', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: {}
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]"
      params.should.have.length 0

    it 'should build query with multiple WHERE', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @mssql.eq 1234]
          ['table1.name', @mssql.lt 'fred']
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] = @id00 AND [table1].[name] < @table1name10"
      params.should.have.length 2
      params[0].value.should.equal 1234

    it 'should build query which specifies WHERE and/or', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @mssql.eq 1234]
          ['OR', 'table1.name', @mssql.lt 'fred']
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] = @id00 OR [table1].[name] < @table1name10"
      params.should.have.length 2
      params[0].value.should.equal 1234

    it 'should ignore initial WHERE and/or', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: [
          ['AND', '@._id', @mssql.eq 1234]
          ['OR', 'table1.name', @mssql.lt 'fred']
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] = @id00 OR [table1].[name] < @table1name10"
      params.should.have.length 2
      params[0].value.should.equal 1234

    it 'should ignore random WHERE and/or', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @mssql.eq 1234]
          ['ZAZZ', 'table1.name', @mssql.lt 'fred']
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] = @id00 AND [table1].[name] < @table1name10"
      params.should.have.length 2
      params[0].value.should.equal 1234

    it 'should build query with WHERE and CAST', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @mssql.cast @mssql.eq(1234), 'tinyint']
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE CAST([test].[_id] AS tinyint) = @id00"
      params.should.have.length 1
      params[0].value.should.equal 1234

    it 'should ignore invalid CAST type', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @mssql.cast @mssql.eq(1234), 'fake']
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] = @id00"
      params.should.have.length 1
      params[0].value.should.equal 1234

    it 'should handle missing CAST type', ->
      [query, params] = @mssql.build_query
        select:
          table1: ['column1']
        where: [
          ['@._id', @mssql.cast @mssql.eq(1234)]
        ]
      query.should.equal "SELECT [table1].[column1],[test].* FROM [table1],[test]  WHERE [test].[_id] = @id00"
      params.should.have.length 1
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
      query.should.equal "SELECT [table1].[column1],[test].* FROM [test] LEFT JOIN [table1] ON [test].[column1] = [table1].[column1] LEFT JOIN [table2] ON [table1].[_id] = [table2].[vehicle_id] WHERE [test].[_id] = @id00 AND [table1].[name] LIKE @table1name10 ORDER BY [test].[column1]"
      params.should.have.length 2
      params[0].value.should.equal 1234

    it 'should build INSERT query', ->
      [query, params] = @mssql.build_query
        insert:
          name: 'new name'
          date: '2016-12-01'
          junk: 'ignore this'
      query.should.equal "INSERT INTO [test] ([name],[date]) OUTPUT INSERTED.* VALUES (@name00,@date00)"
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
      query.should.equal "INSERT INTO [test] ([name],[date]) OUTPUT INSERTED.* VALUES (@name00,@date00),(@name10,@date10)"
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
      query.should.equal "UPDATE [test] SET [name]=@name0,[date]=@date0 OUTPUT INSERTED.* WHERE [_id] = @id00"
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
      query.should.equal "UPDATE [test] SET [name]=@name0,[date]=@date0 OUTPUT INSERTED.* WHERE [_id] = @id00"
      params.should.have.length 3
      params[0].value.should.equal 'new name'

    it 'should build DELETE query', ->
      [query, params] = @mssql.build_query
        delete: {}
        where: [
          ['@._id', @mssql.eq 1234]
        ]
      query.should.equal "DELETE FROM [test] OUTPUT DELETED.* WHERE [_id] = @id00"
      params.should.have.length 1
      params[0].value.should.equal 1234

    it 'should ignore WHERE table in DELETE query', ->
      [query, params] = @mssql.build_query
        delete: {}
        where: [
          ['table_name._id', @mssql.eq 1234]
        ]
      query.should.equal "DELETE FROM [test] OUTPUT DELETED.* WHERE [_id] = @id00"
      params.should.have.length 1
      params[0].value.should.equal 1234


  describe 'parameterize', ->
    it 'should handle OPTIONS', ->
      [column, params] = @mssql.parameterize 'test', 'hours', 11.5
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
      [column, params] = @mssql.parameterize 'test', 'column1', 'nice'
      params.should.have.length 1
      params[0].should.have.property 'name'
      params[0].name.should.equal 'column10'
      params[0].should.have.property 'type'
      params[0].type.should.equal 'VarChar'
      params[0].should.have.property 'value'
      params[0].value.should.equal 'nice'
