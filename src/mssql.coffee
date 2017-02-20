crypto = require 'crypto'
tedious = require 'tedious'
Request = tedious.Request
TYPES = tedious.TYPES
ConnectionPool = require 'tedious-connection-pool'

class MSSQL
  @_cache: {} # static DB connection cache
  @_all_schema: {} # static SCHEMA store of all models

  constructor: (Model, server, user_name, password, @database) ->
    server ?= process.env.SQL_SERVER
    user_name ?= process.env.SQL_USERNAME
    password ?= process.env.SQL_PASSWORD
    @database ?= process.env.SQL_DATABASE
    config =
      server: server
      userName: user_name
      password: password
      options:
        encrypt: true
        database: @database
        useUTC: true
    pool_config =
      min: 2
      max: 10

    @schema = Model.prototype?.table?.schema
    @primary_key = Model.prototype?.table?.primary_key
    @table_name = Model.prototype?.table?.name
    throw new Error "Please define a TABLE property on the model class with a NAME for your DB table" unless @table_name?
    @constructor._all_schema[@database] ?= {}
    @constructor._all_schema[@database][@table_name] = @schema or {} # make SCHEMA available to other models

    # hash connection params to find/create cached connection
    hash = crypto.createHash 'sha256'
    hash.update "#{server}#{user_name}#{password}#{@database}"
    dbconn = hash.digest 'hex'
    @constructor._cache[dbconn] ?= new ConnectionPool pool_config, config
    @pool = @constructor._cache[dbconn]

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
        if @constructor._all_schema[@database][table]?[column] or (@constructor._all_schema[@database][table]? and column is '*')
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
        item = item.split '.'
        item[0] = @table_name if item[0] is '@' # replace '@' with model base table
        item = item.join '].[' if item.length > 1
        order_by_clause += "[#{item}]" + ','
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


  error_msg: (err, query, params...) ->
    ps = ''
    for param in params
      for k, v of param
        ps += "[#{k}: #{v}] "
      ps += "\n"
    return """\n#{new Date()}
      ERROR : #{err.message}
      QUERY : #{query}
      PARAMS:\n#{ps}"""


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
      type = @constructor._all_schema[@database][table]?[column]
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


  request: (query, params...) =>
    new Promise (resolve, reject) =>
      try
        [query, params] = @build_query query if @typeof query, 'object'
      catch ex
        reject @error_msg ex, query, params...
      data = []
      @pool.acquire (err, connection) =>
        reject @error_msg err, query, params... if err?
        request = new Request query, (err, count) =>
          connection.release()
          if err?
            reject @error_msg err, query, params...
          else
            resolve data

        for param in params
          param.value = JSON.stringify(param.value) if @typeof param.value, 'object'
          if TYPES[param.type]?
            request.addParameter param.name, TYPES[param.type], param.value, param.options
          else
            msg = if param?.type? then 'No such TDS datatype: '+param.type.toString() else 'Malformed param: '+param
            reject @error_msg { message: msg }, query, params...

        request.on 'row', (columns) =>
          row = {}
          columns.forEach (column) =>
            column.value = column.value.trim() if @typeof column.value, 'string'
            row[column.metadata.colName.toLowerCase()] = column.value
          data.push row

        connection.execSql request


  sanitize: (body) ->
    throw new Error "No schema found for #{table_name}" unless @schema? and Object.keys(@schema).length > 0
    sanitized = {}
    for own column, value of body # leave PRIMARY_KEY (if defined) out of sanitized body
      sanitized[column] = value if @schema[column]? and not (@primary_key? and column is @primary_key)
    sanitized


  typeof: (subject, type) ->
    # typeof that actually works!
    Object::toString.call(subject).toLowerCase().slice(8, -1) is type


module.exports = MSSQL
