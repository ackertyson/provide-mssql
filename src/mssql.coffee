each = require 'async/eachOfSeries'
crypto = require 'crypto'
sql = require 'mssql'

class MSSQL
  @_cache: {} # static DB connection cache
  @_config: {} # static DB connection cache
  @_all_schema: {} # static SCHEMA store of all models

  constructor: (Model, server, user_name, password, @database) ->
    server ?= process.env.SQL_SERVER
    user_name ?= process.env.SQL_USERNAME
    password ?= process.env.SQL_PASSWORD
    @database ?= process.env.SQL_DATABASE

    @schema = Model.prototype?.table?.schema
    @primary_key = Model.prototype?.table?.primary_key
    @table_name = Model.prototype?.table?.name
    throw new Error "Please define a TABLE property on the model class with a NAME for your DB table" unless @table_name?
    @ctor = @constructor
    @ctor._all_schema[@database] ?= {}
    @ctor._all_schema[@database][@table_name] = @schema or {} # make SCHEMA available to other models

    # hash connection params to find/create cached connection
    hash = crypto.createHash 'sha256'
    hash.update "#{server}#{user_name}#{password}#{@database}"
    @hashkey = hash.digest 'hex'

    @ctor._config[@hashkey] ?= tedious: null, pool: null
    @ctor._config[@hashkey].tedious ?=
      server: server
      database: @database
      user: user_name
      password: password
      options:
        encrypt: true
        useUTC: true
    @ctor._config[@hashkey].pool ?=
      min: 2
      max: 10
    options = Model.prototype?.config or {}
    pool_options = options.pool or {}
    has_custom_config = (Object.keys(options).length + Object.keys(pool_options).length) > 0
    if Object.keys(pool_options).length > 0
      @ctor._config[@hashkey].pool[k] = v for own k, v of pool_options # add'l config for ConnectionPool
      delete options.pool
    @ctor._config[@hashkey].tedious.options[k] = v for own k, v of options # add'l config for Tedious

    Date::to_mssql_string = () ->
      @getUTCFullYear()+'-'+@_pad(@getUTCMonth()+1)+'-'+@_pad(@getUTCDate())+' '+@_pad(@getUTCHours())+':'+@_pad(@getUTCMinutes())+':'+@_pad(@getUTCSeconds())


  # WHERE clause operators
  contains: (value) -> ['LIKE', "%#{value}%"]
  ends_with: (value) -> ['LIKE', "%#{value}"]
  eq: (value) -> ['=', value]
  gt: (value) -> ['>', value]
  gte: (value) -> ['>=', value]
  in: (values) ->
    values = [values] unless @typeof values, 'array'
    ['IN', values]
  is_not_null: -> ['IS NOT NULL']
  is_null: -> ['IS NULL']
  lt: (value) -> ['<', value]
  lte: (value) -> ['<=', value]
  neq: (value) -> ['<>', value]
  starts_with: (value) -> ['LIKE', "#{value}%"]


  build_param: (name, type, value, options) ->
    { name: name, type: type, value: value, options: options }


  build_delete_query: (params) ->
    throw new Error "Build query: DELETE query requires WHERE clause" unless params.where? and Object.keys(params.where)?.length > 0
    sql_params = []

    where_clause = ''
    oper = 'WHERE'
    for set, i in params.where
      [table_column, criterion] = set
      [table, column] = table_column.split '.'
      [comparator, value] = criterion
      column = table unless column? # drop table name if any provided (DELETE can only be run on model's base table)
      [param_name, parameters] = @parameterize @table_name, column, value, i
      param_name = "(#{param_name})" if comparator is 'IN'
      where_clause += "#{oper} [#{column}] #{comparator} #{param_name}"
      Array::push.apply sql_params, parameters
      oper = ' AND'

    query = "DELETE FROM [#{@table_name}] OUTPUT DELETED.* #{where_clause}"
    [query.trim(), sql_params]


  build_insert_query: (params) ->
    params.insert = [params.insert] unless Array.isArray params.insert
    items = []
    sql_params = []
    for item,i in params.insert
      body = @sanitize item
      columns = []
      p_names = []
      for own column, value of body
        columns.push "[#{column}]"
        [param_name, parameters] = @parameterize @table_name, column, value, i
        Array::push.apply sql_params, parameters
        p_names.push "#{param_name}"
      items.push "(#{p_names.join ','})"
    query = "INSERT INTO [#{@table_name}] (#{columns.join ','}) OUTPUT INSERTED.* VALUES #{items.join ','}"
    [query.trim(), sql_params]


  build_update_query: (params) ->
    throw new Error "Build query: UPDATE query requires WHERE clause" unless params.where? and Object.keys(params.where)?.length > 0
    body = @sanitize params.update
    updates = []
    sql_params = []
    for own column, value of body
      [param_name, parameters] = @parameterize @table_name, column, value
      updates.push "[#{column}]=#{param_name}"
      Array::push.apply sql_params, parameters

    where_clause = ''
    oper = 'WHERE'
    for set, i in params.where
      [table_column, criterion] = set
      [table, column] = table_column.split '.'
      [comparator, value] = criterion
      column = table unless column? # drop table name if any provided (UPDATE can only be run on model's base table)
      [param_name, parameters] = @parameterize @table_name, column, value, i
      param_name = "(#{param_name})" if comparator is 'IN'
      where_clause += "#{oper} [#{column}] #{comparator} #{param_name}"
      Array::push.apply sql_params, parameters
      oper = ' AND'

    query = "UPDATE [#{@table_name}] SET #{updates} OUTPUT INSERTED.* #{where_clause}"
    [query.trim(), sql_params]


  build_query: (params) ->
    return params if @typeof params, 'string' # literal string query; no action required
    return @build_delete_query params if params.delete?
    return @build_insert_query params if params.insert?
    return @build_update_query params if params.update?
    params.select ?= {}
    params.select[@table_name] = ['*'] unless params.select[@table_name]? or params.select['@']? # base table default selection
    tables = Object.keys params.select or []

    from_tables = (table for table in tables)
    for table,i in from_tables
      from_tables[i] = @table_name if table is '@' # base table alias

    select_clause = 'SELECT '
    separator = ''
    for table, columns of params.select
      table = @table_name if table is '@' # base table alias
      for column in columns
        [column, alias] = column.split ':'
        [alias, column, table] = [alias?.toString().trim(), column?.toString().trim(), table?.toString().trim()]
        if @ctor._all_schema[@database][table]?[column] or (@ctor._all_schema[@database][table]? and column is '*')
          column = "[#{column}]" unless column is '*'
          select_clause += "#{separator}[#{table}].#{column}"
          select_clause += " AS #{alias}" if alias?
          separator = ','
    throw new Error "No valid tables/fields in SELECT clause" unless select_clause.length > 'SELECT '.length

    join_clause = ''
    if params.join?
      joins = []
      for set, i in params.join
        direction = 'LEFT' # default
        [a, b] = set
        [direction, a, b] = set if set.length is 3 # DIRECTION is LEFT/RIGHT/INNER/OUTER
        [tableA, columnA] = a.split '.'
        [tableB, columnB] = b.split '.'
        tableA = @table_name if tableA is '@'
        tableB = @table_name if tableB is '@'
        target = tableB

        if i is 0 # use first JOIN table in FROM clause
          root_join_table = tableA
        tmp = {} # find tables in FROM clause...
        tmp[tableA] = from_tables.indexOf tableA
        tmp[tableB] = from_tables.indexOf tableB
        for table, pos of tmp # ...and remove them (unless they're the root table)
          from_tables.splice pos, 1 if pos > -1 and table isnt root_join_table

        a = [tableA, columnA].join '].['
        b = [tableB, columnB].join '].['
        clause = "#{direction} JOIN [#{target}] ON [#{a}] = [#{b}]"
        joins.push clause
      join_clause = joins.join ' '

    from_clause = 'FROM '
    # move join table to end of FROM clause...
    if make_last? and from_tables.indexOf make_last > -1
      element = from_tables.splice from_tables.indexOf(make_last), 1
      from_tables.push element
    from_clause += '[' + from_tables.join('],[') + ']'

    where_clause = ''
    sql_params = []
    if params.where?.length > 0
      oper = 'WHERE'
      for set, i in params.where
        [table_column, criterion] = set
        if set.length is 3 # optional AND/OR keyword provided
          if oper is 'WHERE' # ...but ignore it if this is first condition
            [_ignore, table_column, criterion] = set
          else
            [oper, table_column, criterion] = set
            oper = oper.toString().trim().toUpperCase()
            oper = 'AND' unless oper in ['AND', 'OR']
        [table, column] = table_column.split '.'
        table = @table_name if table is '@'
        [comparator, value] = criterion
        if !value? # IS [NOT] NULL
          where_clause += " #{oper} [#{table}].[#{column}] #{comparator}"
        else
          [param_name, parameters] = @parameterize table, column, value, i
          param_name = "(#{param_name})" if comparator is 'IN'
          where_clause += " #{oper} [#{table}].[#{column}] #{comparator} #{param_name}"
          Array::push.apply sql_params, parameters
        where_clause = where_clause.trim()
        oper = 'AND'

    order_by_clause = ''
    if params.order_by?
      order_by_clause = 'ORDER BY '
      for item in params.order_by
        [table, column] = item.split '.'
        [table, column] = [@table_name, table] unless column? # no table specified; use model base table
        table = @table_name if table is '@' # replace '@' with model base table
        [column, direction] = column.split ' '
        order_by_clause += "[#{table}].[#{column}]"
        if direction? and direction.toString().toUpperCase() in ['ASC', 'DESC']
          order_by_clause += " #{direction},"
        else
          order_by_clause += ','
      order_by_clause = order_by_clause.slice 0, -1 # trim trailing comma

    offset_clause = ''
    if params.offset? and !isNaN(Number(params.offset)) and order_by_clause.length > 0
      offset_clause = "OFFSET #{Number params.offset} ROWS"

    fetch_clause = ''
    if params.fetch? and !isNaN(Number(params.fetch)) and offset_clause.length > 0
      fetch_clause = "FETCH NEXT #{Number params.fetch} ROWS ONLY"

    query = "#{select_clause} #{from_clause} #{join_clause} #{where_clause} #{order_by_clause} #{offset_clause} #{fetch_clause}"
    [query.trim(), sql_params]


  _coerce_int: (value) ->
    return value if @typeof value, 'number'
    return null unless @typeof value, 'boolean'
    return if value is true then 1 else 0


  _coerce_time: (value) ->
    return unless value?
    return value if /T[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}/.test value # already ISO datetime
    # ...otherwise build/return ISO string...
    d = new Date
    parse = value.split ':'
    d.setUTCHours(parse[0], parse[1]) if parse.length > 1
    d.toISOString()


  connect: () ->
    return Promise.resolve(@ctor._cache[@hashkey]) if @ctor._cache[@hashkey]?

    new Promise (resolve) =>
      return setTimeout(@connect.bind(@), 200) if @connecting 

      @connecting = true
      config = @ctor._config[@hashkey]
      tds = config.tedious
      tds.pool = config.pool
      sql.on 'error', console.error 

      sql.connect(tds)
        .then (pool) =>
          if !@ctor._cache[@hashkey]? or has_custom_config # overwrite existing defs with cumulative custom config
            @ctor._cache[@hashkey] =
              pool: pool,
              transaction: () -> new sql.Transaction(pool)
          resolve @ctor._cache[@hashkey]
        .catch (err) =>
          console.error(err)
          console.error 'Trying again...'
          setTimeout @connect.bind(@), 1000


  end_transaction: (tx) -> 
    (err) ->
      return tx.rollback() if err?
      tx.commit();


  error_msg: (err, query, params=[]) ->
    ps = ''
    for param in params
      for k, v of param
        ps += "[#{k}: #{v}] "
      ps += "\n"
    return """\n#{new Date()}
      ERROR : #{err.message}
      QUERY : #{query}
      PARAMS:\n#{ps}"""


  _execStmt: (name, req, query, params=[]) ->
    for param in params
      param.value = JSON.stringify(param.value) if @typeof param.value, 'object'
      options = param.options
      # OPTIONS become args to TYPE() if they exist, otherwise use string TYPE
      type = if options? then sql[param.type]?(options...) else sql[param.type]
      req.input param.name, type, param.value
    req.query(query).then (res) ->
      { name, data: res.recordset }


  mssql_date_string: (date) ->
    return date if date is null
    if @typeof date, 'string'
      date = new Date(date)
    date.to_mssql_string()


  _pad: (number) ->
    number = number.toString()
    return number unless number.length is 1
    return '0' + number


  parameterize: (table, column, value, tag='') ->
    if table is @table_name # use this model's schema
      type = @schema[column] if @schema?
    else # check other model schema
      type = @ctor._all_schema[@database][table]?[column]
      column = "#{table}.#{column}"
    options = {}
    # additional options passed as object...
    { type, options } = ({ type: k, options: v} for k,v of type)[0] if @typeof(type, 'object')
    throw new Error "MSSQL: #{@table_name} model: no schema definition found for #{column}" unless type?
    param_base = column.replace /[^a-zA-Z0-9]/g, '' # strip all non-alphanumeric characters
    param_base = param_base + tag.toString() if tag.toString().length > 0
    parameters = []
    param_name = ''
    value = [value] unless @typeof value, 'array' # simplify BETWEEN and IN logic by processing as array
    for v, i in value
      v = @_coerce_int v if type.toLowerCase() is 'tinyint'
      v = @_coerce_time v if type.toLowerCase() is 'time'
      param_name += "@#{param_base}#{i},"
      parameters.push @build_param "#{param_base}#{i}", type, v, options
    param_name = param_name.slice 0, -1 # remove trailing comma
    [param_name, parameters]


  request: (query, params=[], transaction) =>
    @connect().then (connection) =>
      try
        [query, params] = @build_query query if @typeof query, 'object'
      catch ex
        console.log @error_msg ex, query, params
        return Promise.reject ex
      data = []
      if transaction? # use provided connection
        req = new sql.Request(transaction.tx)
      else # acquire new connection from pool
        req = connection.pool.request()
      @_execStmt(null, req, query, params).then (result) ->
        result.data
      .catch (err) =>
        return transaction.done(err) if transaction?
        console.log @error_msg err, query, params
        Promise.reject err


  sanitize: (body) ->
    throw new Error "No schema found for #{table_name}" unless @schema? and Object.keys(@schema).length > 0
    sanitized = {}
    for own column, value of body # leave PRIMARY_KEY (if defined) out of sanitized body
      sanitized[column] = value if @schema[column]? and not (@primary_key? and column is @primary_key)
    sanitized


  start_transaction: () =>
    transaction = @ctor._cache[@hashkey].pool.transaction()
    transaction.begin()
      .then () -> { tx: transaction, done: @end_transaction(transaction) }


  transaction: (queries) =>
    new Promise (resolve, reject) =>
      transaction = @ctor._cache[@hashkey].pool.transaction()
      transaction.begin().then () =>
        results = {}
        done = @end_transaction(transaction)
        each queries, ({ name, query, params }, index, next) =>
          try
            [query, params] = @build_query query if @typeof query, 'object'
          catch ex
            return next ex
          name ?= index
          params ?= []
          @_execStmt(name, transaction.request, query, params).then (result) ->
            results[result.name] = result.data
            next()
          .catch next
        , done # call TX callback with async/each result


  typeof: (subject, type) ->
    # typeof that actually works!
    Object::toString.call(subject).toLowerCase().slice(8, -1) is type


module.exports = MSSQL
