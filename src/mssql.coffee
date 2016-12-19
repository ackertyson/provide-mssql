crypto = require 'crypto'
tedious = require 'tedious'
Request = tedious.Request
TYPES = tedious.TYPES
ConnectionPool = require 'tedious-connection-pool'
Promise = require 'promise'


class MSSQL
  @_cache: {} # static DB connection cache

  constructor: (@table_name, @schema, server, user_name, password, database) ->
    server ?= process.env.SQL_SERVER
    user_name ?= process.env.SQL_USERNAME
    password ?= process.env.SQL_PASSWORD
    database ?= process.env.SQL_DATABASE
    config =
      server: server
      userName: user_name
      password: password
      options:
        encrypt: true
        database: database
        useUTC: true
    pool_config =
      min: 2
      max: 10

    # hash connection vars to check for or create cached connection
    hash = crypto.createHash 'sha256'
    hash.update "#{server}#{user_name}#{password}#{database}"
    dbconn = hash.digest 'hex'
    if @constructor._cache[dbconn]? # used cached connection
      @pool = @constructor._cache[dbconn]
    else # create new connection
      @pool = new ConnectionPool pool_config, config
      @constructor._cache[dbconn] = @pool

    pad = (number) ->
      number = number.toString()
      return number unless number.length is 1
      return '0' + number
    Date::to_mssql_string = () ->
      @getUTCFullYear()+'-'+pad(@getUTCMonth()+1)+'-'+pad(@getUTCDate())+' '+pad(@getUTCHours())+':'+pad(@getUTCMinutes())+':'+pad(@getUTCSeconds())


  build_filters: (query, raw_filters) ->
    # DEPRECATED; just haven't replaced this last bit...
    if filter.date_range? and filter.table? and filter.column? and whitelist[filter.table]?[filter.column]?
      filters.date_range ?= []
      comparator = if filter.direction is 'before' then '<=' else '>='
      index = filters.date_range.length
      # reformat MM-DD-YYYY date to ISO-8601 (YYYY-MM-DD)...
      params.push @build_param 'date_'+filter.direction+index, 'Date', filter.value.replace /^([0-9]{1,2})\/([0-9]{1,2})\/([0-9]{4})$/, '$3-$1-$2'
      filters.date_range.push { query: " AND ["+filter.table+"].["+filter.column+"] #{comparator} @date_#{filter.direction}#{index}" }


  build_param: (name, type, value, options) ->
    { name: name, type: type, value: value, options: options }


  build_delete_query: (params) ->
    throw new Error "Build query: DELETE query requires WHERE clause" unless params.where? and Object.keys(params.where)?.length > 0
    sql_params = []

    where_clause = ''
    oper = 'WHERE'
    for table_column, criterion of params.where
      [table, column] = table_column.split '.'
      [comparator, value] = criterion
      column = table unless column? # drop table name if any provided (DELETE can only be run on model's base table)
      [safe_column, sql_param] = @parameterize @table_name, column, value
      where_clause += "#{oper} [#{column}] #{comparator} @#{safe_column}"
      sql_params.push sql_param
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
        [safe_column, sql_param] = @parameterize @table_name, column, value, i
        sql_params.push sql_param
        p_names.push "@#{safe_column}"
      items.push "(#{p_names.join ','})"
    query = "INSERT INTO [#{@table_name}] (#{columns.join ','}) OUTPUT INSERTED.* VALUES #{items.join ','}"
    [query.trim(), sql_params]


  build_update_query: (params) ->
    throw new Error "Build query: UPDATE query requires WHERE clause" unless params.where? and Object.keys(params.where)?.length > 0
    body = @sanitize params.update
    updates = []
    sql_params = []
    for own column, value of body
      [safe_column, sql_param] = @parameterize @table_name, column, value
      updates.push "[#{column}]=@#{safe_column}"
      sql_params.push sql_param

    where_clause = ''
    oper = 'WHERE'
    for table_column, criterion of params.where
      [table, column] = table_column.split '.'
      [comparator, value] = criterion
      column = table unless column? # drop table name if any provided (UPDATE can only be run on model's base table)
      [safe_column, sql_param] = @parameterize @table_name, column, value
      where_clause += "#{oper} [#{column}] #{comparator} @#{safe_column}"
      sql_params.push sql_param
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
        select_clause += "#{separator}#{table}.#{column.trim()}"
        select_clause += " AS #{alias.trim()}" if alias?
        separator = ','

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
        if i is 0 # move first join table to end of FROM clause
          make_last = tableA
        else
          ia = from_tables.indexOf(tableA)
          from_tables.splice ia, 1 if ia > -1
        ib = from_tables.indexOf tableB
        from_tables.splice ib, 1 if ib > -1
        a = [tableA, columnA].join '.'
        b = [tableB, columnB].join '.'
        clause = "#{direction} JOIN #{target} ON #{a} = #{b}"
        clause += " AND #{and_clause}" if and_clause?
        joins.push clause
      join_clause = joins.join ' '

    from_clause = 'FROM '
    # move join table to end of FROM clause...
    if make_last? and from_tables.indexOf make_last > -1
      element = from_tables.splice from_tables.indexOf(make_last), 1
      from_tables.push element
    from_clause += from_tables.join ','

    where_clause = ''
    sql_params = []
    if params.where? and Object.keys(params.where)?.length > 0
      oper = 'WHERE'
      for table_column, criterion of params.where
        [table, column] = table_column.split '.'
        table = @table_name if table is '@'
        [comparator, value] = criterion
        if comparator in ['IN', 'LIKE'] # don't use parameters
          where_clause += "#{oper} [#{table}].[#{column}] #{comparator} #{value}"
        else
          [safe_column, sql_param] = @parameterize table, column, value
          where_clause += "#{oper} [#{table}].[#{column}] #{comparator} @#{safe_column}"
          sql_params.push sql_param
        oper = ' AND'

    order_by_clause = ''
    if params.order_by?
      order_by_clause = 'ORDER BY '
      for item in params.order_by
        item = item.split '.'
        item[0] = @table_name if item[0] is '@' # replace '@' with model base table
        item = item.join '.' if item.length > 1
        order_by_clause += item + ','
      order_by_clause = order_by_clause.slice 0, -1 # trim trailing comma

    offset_clause = ''
    if params.offset? and !isNaN(Number(params.offset)) and order_by_clause.length > 0
      offset_clause = "OFFSET #{Number params.offset} ROWS"

    fetch_clause = ''
    if params.fetch? and !isNaN(Number(params.fetch)) and offset_clause.length > 0
      fetch_clause = "FETCH NEXT #{Number params.fetch} ROWS ONLY"

    query = "#{select_clause} #{from_clause} #{join_clause} #{where_clause} #{order_by_clause} #{offset_clause} #{fetch_clause}"
    [query.trim(), sql_params]


  error_msg: (err, query, params) ->
    ps = ''
    for k, v of params
      ps += "[#{k}: #{v}] "
    return """\n#{new Date()}
      ERROR : #{err.message}
      QUERY : #{query}
      PARAMS: #{ps}"""


  mssql_date_string: (date) ->
    return date if date is null
    if @typeof date, 'string'
      date = new Date(date)
    date.to_mssql_string()


  parameterize: (table, column, value, tag='') ->
    column = "#{table}.#{column}" if table isnt @table_name
    throw new Error "MSSQL: #{@table_name}: no schema definition found for #{column}" unless @schema?[column]?
    safe_column = column.replace /[^a-zA-Z0-9]/g, '' # strip all non-alphanumeric characters
    safe_column = safe_column + tag.toString() if tag.toString().length > 0
    sql_param = @build_param safe_column, @schema[column], value
    [safe_column, sql_param]


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
    for own column, value of body
      sanitized[column] = value if @schema[column]?
    sanitized


  typeof: (subject, type) ->
    # typeof that actually works!
    Object::toString.call(subject).toLowerCase().slice(8, -1) is type


module.exports = MSSQL
